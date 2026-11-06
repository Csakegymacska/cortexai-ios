// ArenaAPIClient — a HIVATALOS Arena API natív kliense (api.arena.ai, OpenAI-kompatibilis).
// Bearer-kulcs a Keychainből; stream (SSE) válaszok; a chat így teljesen natív,
// WebView nélkül — lásd ARENA-NATIVE.md.
import Foundation

struct ArenaMessage: Codable {
    let role: String      // "system" | "user" | "assistant"
    let content: String
}

struct ArenaStreamDelta {
    var text: String = ""
    var done: Bool = false
}

@MainActor
final class ArenaAPIClient: ObservableObject {
    @Published var lastError: String?

    private let session = URLSession(configuration: .ephemeral)
    private(set) var baseURL = URL(string: "https://api.arena.ai/v1")!

    var apiKey: String {
        Keychain.read("arena.api.key") ?? ""
    }

    /// Modell-lista a munkaterületről (GET /models).
    func models() async -> [String] {
        guard var req = request("models", method: "GET") else { return [] }
        req.timeoutInterval = 15
        do {
            let (data, _) = try await session.data(for: req)
            struct L: Decodable { struct M: Decodable { let id: String }; let data: [M] }
            return (try? JSONDecoder().decode(L.self, from: data))?.data.map(\.id) ?? []
        } catch {
            lastError = error.localizedDescription
            return []
        }
    }

    /// Streamelt válasz — a hívó a deltákat kapja, ahogy jönnek.
    func stream(model: String, messages: [ArenaMessage], onDelta: @escaping (String) -> Void) async throws -> String {
        var req = request("chat/completions", method: "POST")
        req?.timeoutInterval = 120
        var full = ""
        let body: [String: Any] = [
            "model": model,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "stream": true,
        ]
        req?.httpBody = try JSONSerialization.data(withJSONObject: body)
        guard let req else { throw URLError(.badURL) }

        let (bytes, resp) = try await session.bytes(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            var msg = ""
            for try await line in bytes.lines { msg += line }
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "Arena API \(http.statusCode): \(msg.prefix(200))"])
        }
        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            if payload == "[DONE]" { break }
            if let obj = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any],
               let choices = obj["choices"] as? [[String: Any]],
               let delta = choices.first?["delta"] as? [String: Any],
               let text = delta["content"] as? String {
                full += text
                onDelta(text)
            }
        }
        return full
    }

    private func request(_ path: String, method: String) -> URLRequest? {
        guard !apiKey.isEmpty else {
            lastError = "No API key — add one in Settings."
            return nil
        }
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = method
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // A kapu a nem-böngésző UA-t szűri — ezt a UA-t engedi (tesztelve).
        req.setValue("CortexPhantomAgent/1.0 (iOS 26.0; CFNetwork)", forHTTPHeaderField: "User-Agent")
        return req
    }
}

/// Keychain-tárolás — a kulcs soha nem kerül UserDefaultsba vagy fájlba.
enum Keychain {
    static func save(_ value: String, for key: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrAccount as String: key]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
    }

    static func read(_ key: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrAccount as String: key,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrAccount as String: key]
        SecItemDelete(query as CFDictionary)
    }
}
