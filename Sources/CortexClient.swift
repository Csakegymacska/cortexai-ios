import Foundation

/// Talks to the Cortex AI backend (`/api/cortexai/*`).
///
/// The client never names an upstream provider: it only knows about "Cortex Void" tiers.
/// Streaming uses SSE (`data: {"delta": "…"}` chunks) so the UI can type the answer out.
final class CortexClient: @unchecked Sendable {
    static let shared = CortexClient()

    private let base = URL(string: "https://cortanime.eu/api/cortexai")!
    private let session: URLSession
    private let deviceID: String

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 600
        config.waitsForConnectivity = true
        session = URLSession(configuration: config)

        let key = "cortex.client.id"
        if let saved = UserDefaults.standard.string(forKey: key) {
            deviceID = saved
        } else {
            let fresh = UUID().uuidString
            UserDefaults.standard.set(fresh, forKey: key)
            deviceID = fresh
        }
    }

    /// What the worker says about a finished reply: which layer answered it, where the
    /// facts came from, and how long it took. The UI draws the chips from this.
    struct ReplyMeta: Sendable, Equatable {
        var layer: String = ""
        var sources: [String] = []
        var milliseconds: Int = 0
        var runs: Int = 0
        var suggestions: [String] = []
    }

    struct Health: Decodable {
        let ok: Bool
        let model: String
        let vendor: String
    }

    /// How far the self-trained core has got. Numbers only — no provider, no base model.
    struct CoreStatus: Decodable {
        struct Parts: Decodable {
            let identity: Double
            let catalog: Double
            let language: Double
        }
        struct Round: Decodable {
            let v: Int
            let score: Double
            let at: String?
        }
        let ok: Bool
        let phase: String
        let version: Int
        let score: Double
        let target: Double
        let progress: Int
        let parts: Parts?
        let trainedAt: String?
        let gate: Double
        let selfhost: Bool
        let nextRound: String
        let history: [Round]
    }

    enum ClientError: LocalizedError {
        case badStatus(Int, String)
        case busy
        case cancelled

        var errorDescription: String? {
            switch self {
            case .badStatus(let code, let body):
                // A 79. körben a motor szerveroldalra került: a hibák nagy része már nem
                // hálózati hiba, hanem fiók- vagy keret-állapot. Ezeket ne nyers
                // HTTP-kóddal lássa a felhasználó.
                switch code {
                case 401:
                    return "No API key linked yet. Open Plans and paste your key from cortanime.eu/api-keys."
                case 402, 503:
                    return "The engine is out of credit right now. Your plan is fine — try again in a few minutes."
                case 429:
                    return "Daily token allowance reached. It resets at midnight UTC."
                case 413:
                    return "That attachment is too large for one message."
                default:
                    return "Cortex is unavailable (\(code)). \(body.prefix(120))"
                }
            case .busy: return "Cortex is busy right now. Try again in a moment."
            case .cancelled: return "Cancelled."
            }
        }
    }

    func core() async throws -> CoreStatus {
        var request = URLRequest(url: base.appendingPathComponent("core"))
        request.setValue(deviceID, forHTTPHeaderField: "X-Cortex-Client")
        let (data, _) = try await session.data(for: request)
        return try JSONDecoder().decode(CoreStatus.self, from: data)
    }

    func health() async throws -> Health {
        var request = URLRequest(url: base.appendingPathComponent("health"))
        request.setValue(deviceID, forHTTPHeaderField: "X-Cortex-Client")
        let (data, _) = try await session.data(for: request)
        return try JSONDecoder().decode(Health.self, from: data)
    }

    /// Builds the request body the worker expects. Assistant/user history only.
    private func payload(messages: [ChatMessage], tier: String, extra: String?,
                         memory: [String] = [], images: [ChatImage] = [],
                         files: [ChatFile] = []) -> [String: Any] {
        var history: [[String: String]] = messages.compactMap { message in
            guard message.role != .system, !message.text.isEmpty else { return nil }
            return ["role": message.role == .assistant ? "assistant" : "user", "content": message.text]
        }
        // The last bubble is the one being answered — never send the empty placeholder.
        if let last = history.last, last["role"] == "assistant" { history.removeLast() }
        var body: [String: Any] = ["messages": history, "tier": tier, "stream": true]
        if !images.isEmpty {
            body["images"] = images.prefix(3).map { ["mime": $0.mime, "data": $0.data] }
        }
        // A dokumentumok szövege megy, a fájl nem: a worker nem tárol semmit.
        if !files.isEmpty {
            body["files"] = files.prefix(4).map { ["name": $0.name, "text": $0.text] }
        }
        if let extra, !extra.isEmpty { body["persona"] = extra }
        // What we know about the person travels with every request.
        if !memory.isEmpty { body["memory"] = Array(memory.suffix(24)) }
        return body
    }

    /// Streams a reply. `onDelta` is called on the main actor for every text chunk.
    @MainActor
    func stream(
        messages: [ChatMessage],
        tier: String,
        extraInstructions: String?,
        memory: [String] = [],
        images: [ChatImage] = [],
        files: [ChatFile] = [],
        agent: Bool = false,
        onStep: @escaping (AgentStep) -> Void = { _ in },
        onMeta: @escaping (ReplyMeta) -> Void = { _ in },
        onDelta: @escaping (String) -> Void
    ) async throws {
        var request = URLRequest(url: base.appendingPathComponent("chat"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue(deviceID, forHTTPHeaderField: "X-Cortex-Client")
        var body = payload(messages: messages, tier: tier, extra: extraInstructions, memory: memory, images: images, files: files)
        if agent { body["agent"] = true }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClientError.busy }
        guard http.statusCode == 200 else {
            var collected = ""
            for try await line in bytes.lines { collected += line; if collected.count > 300 { break } }
            throw ClientError.badStatus(http.statusCode, collected)
        }

        var meta = ReplyMeta()
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }
            let raw = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if raw.isEmpty || raw == "[DONE]" { continue }
            guard let data = raw.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if let error = obj["error"] as? String {
                throw ClientError.badStatus(503, error)
            }
            if let step = obj["step"] as? [String: Any], let label = step["label"] as? String {
                onStep(AgentStep(label: label,
                                 detail: step["detail"] as? String ?? "",
                                 ms: step["ms"] as? Int ?? 0,
                                 ok: step["ok"] as? Bool ?? true))
            }
            if let layer = obj["layer"] as? String, !layer.isEmpty { meta.layer = layer }
            if let runs = obj["runs"] as? Int, runs > 0 { meta.runs = runs }
            if let sug = obj["suggestions"] as? [String], !sug.isEmpty { meta.suggestions = sug }
            if let sources = obj["sources"] as? [String], !sources.isEmpty { meta.sources = sources }
            if obj["done"] as? Bool == true {
                if let ms = obj["ms"] as? Int { meta.milliseconds = ms }
                else if let ms = obj["ms"] as? Double { meta.milliseconds = Int(ms) }
                onMeta(meta)
                continue
            }
            if let delta = obj["delta"] as? String, !delta.isEmpty {
                onDelta(delta)
            }
        }
    }

    /// Non-streaming fallback used when streaming is disabled in settings.
    func complete(messages: [ChatMessage], tier: String, extraInstructions: String?,
                  memory: [String] = [], images: [ChatImage] = [], files: [ChatFile] = []) async throws -> String {
        var request = URLRequest(url: base.appendingPathComponent("chat"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(deviceID, forHTTPHeaderField: "X-Cortex-Client")
        var body = payload(messages: messages, tier: tier, extra: extraInstructions, memory: memory, images: images, files: files)
        body["stream"] = false
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ClientError.busy
        }
        struct Reply: Decodable { let ok: Bool; let text: String? }
        let reply = try JSONDecoder().decode(Reply.self, from: data)
        guard reply.ok, let text = reply.text, !text.isEmpty else { throw ClientError.busy }
        return text
    }

    // MARK: - Mély kutatás

    struct Research: Decodable {
        let ok: Bool
        let text: String?
        let sources: [String]?
        let suggestions: [String]?
        let ms: Int?
        let message: String?
    }

    /// Több forrásból dolgozó válasz. Nem streamel: a lépések után egyben jön,
    /// számozott hivatkozásokkal, és a források a válasz alá kerülnek.
    @MainActor
    func research(question: String) async throws -> Research {
        var request = URLRequest(url: base.appendingPathComponent("research"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(deviceID, forHTTPHeaderField: "X-Cortex-Client")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["question": question])
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ClientError.badStatus((response as? HTTPURLResponse)?.statusCode ?? 0, "research")
        }
        let study = try JSONDecoder().decode(Research.self, from: data)
        guard study.ok, let text = study.text, !text.isEmpty else {
            throw ClientError.badStatus(503, study.message ?? "Ehhez most nem találtam használható forrást.")
        }
        return study
    }

    // MARK: - Két hangnem

    private struct CompareReply: Decodable {
        struct Row: Decodable { let label: String; let text: String }
        let ok: Bool
        let answers: [Row]?
    }

    /// Ugyanaz a kérdés két hangnemben. Egy motor, két profil — gyors, és nem
    /// kell hozzá külön beállítás.
    @MainActor
    func compare(question: String, tier: String) async throws -> [TwoUpAnswer] {
        var request = URLRequest(url: base.appendingPathComponent("compare"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(deviceID, forHTTPHeaderField: "X-Cortex-Client")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["question": question, "tier": tier])
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw ClientError.busy }
        let reply = try JSONDecoder().decode(CompareReply.self, from: data)
        let rows = (reply.answers ?? []).filter { !$0.text.isEmpty }
        guard reply.ok, !rows.isEmpty else { throw ClientError.busy }
        return rows.map { TwoUpAnswer(label: $0.label, text: $0.text) }
    }

    // MARK: - Megosztás

    private struct ShareReply: Decodable { let ok: Bool; let url: String? }

    /// Olvasható link a beszélgetésről. 30 napig él, és nincs benne személyes adat.
    @MainActor
    func share(messages: [(role: String, text: String)], title: String) async throws -> URL {
        var request = URLRequest(url: base.appendingPathComponent("share"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(deviceID, forHTTPHeaderField: "X-Cortex-Client")
        let rows = messages.map { ["role": $0.role, "content": $0.text] }
        request.httpBody = try JSONSerialization.data(withJSONObject: ["messages": rows, "title": title])
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw ClientError.busy }
        let reply = try JSONDecoder().decode(ShareReply.self, from: data)
        guard reply.ok, let raw = reply.url, let url = URL(string: raw) else { throw ClientError.busy }
        return url
    }

    // MARK: - Napi brief

    struct Daily: Decodable {
        struct Episode: Decodable, Identifiable, Hashable {
            let title: String
            let ep: Int
            let aid: Int
            let at: String
            var id: String { "\(aid)-\(ep)" }
        }
        struct Headline: Decodable, Identifiable, Hashable {
            let title: String
            let source: String?
            let date: String?
            let link: String?
            var id: String { title }
        }
        let date: String
        let line: String
        let next: [Episode]?
        let news: [Headline]?
    }

    @MainActor
    func daily() async throws -> Daily {
        var request = URLRequest(url: base.appendingPathComponent("daily"))
        request.setValue(deviceID, forHTTPHeaderField: "X-Cortex-Client")
        let (data, _) = try await session.data(for: request)
        return try JSONDecoder().decode(Daily.self, from: data)
    }

    // MARK: - Újdonságok

    struct Feature: Decodable, Identifiable, Hashable {
        let key: String
        let title: String
        let body: String
        var id: String { key }
    }

    struct FeatureBoard: Decodable {
        let version: String
        let items: [Feature]
    }

    /// Az offline modellek katalógusa. Apró válasz, a súlyfájl nem itt jön.

    func features() async throws -> FeatureBoard {
        var request = URLRequest(url: base.appendingPathComponent("features"))
        request.setValue(deviceID, forHTTPHeaderField: "X-Cortex-Client")
        let (data, _) = try await session.data(for: request)
        return try JSONDecoder().decode(FeatureBoard.self, from: data)
    }

    // MARK: - Cortex Void Canvas (images)

    private struct ImageCreated: Decodable {
        let ok: Bool
        let id: String?
        let message: String?
    }

    private struct ImageJob: Decodable {
        let ok: Bool
        let status: String?
        let url: String?
    }

    /// Starts a render. Returns the job id the caller polls with `imageStatus(id:)`.
    @MainActor
    func createImage(prompt: String, style: String) async throws -> String {
        var request = URLRequest(url: base.appendingPathComponent("image"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(deviceID, forHTTPHeaderField: "X-Cortex-Client")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["prompt": prompt, "style": style])

        let (data, response) = try await session.data(for: request)
        let http = response as? HTTPURLResponse
        guard http?.statusCode == 200 else {
            throw ClientError.badStatus(http?.statusCode ?? 0, String(data: data, encoding: .utf8) ?? "")
        }
        let created = try JSONDecoder().decode(ImageCreated.self, from: data)
        guard created.ok, let id = created.id else {
            throw ClientError.badStatus(503, created.message ?? "")
        }
        return id
    }

    /// Polls one render. `status` is "processing", "succeeded" or "failed".
    @MainActor
    func imageStatus(id: String) async throws -> (status: String, url: String?) {
        var request = URLRequest(url: base.appendingPathComponent("image/" + id))
        request.setValue(deviceID, forHTTPHeaderField: "X-Cortex-Client")
        let (data, _) = try await session.data(for: request)
        let job = try JSONDecoder().decode(ImageJob.self, from: data)
        return (job.status ?? "unknown", job.url)
    }
}
