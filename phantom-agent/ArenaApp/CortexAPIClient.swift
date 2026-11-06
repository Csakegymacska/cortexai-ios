// CortexAPIClient — a SAJÁT AI-nk (Cortex Phantom) natív kliense.
// cortanime.eu/api/cortexai/chat — SSE: data: {"delta":"…"} … data: [DONE]
// A Phantom Core 2 csővezetéken megy (multi-jelölt + alkotmányos lektor).
import Foundation

@MainActor
final class CortexAPIClient: ObservableObject {
    @Published var lastError: String?

    private let base = URL(string: "https://cortanime.eu/api/cortexai")!
    private let session = URLSession(configuration: .ephemeral)

    /// Streamelt válasz a saját modelltől — a deltákat élőben kapja a hívó.
    func stream(messages: [ArenaMessage], tier: String = "void", user: String = "phantom-app", onDelta: @escaping (String) -> Void) async throws -> String {
        var req = URLRequest(url: base.appendingPathComponent("chat"))
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("CortexPhantomAgent/1.0 (iOS 26.0; CFNetwork)", forHTTPHeaderField: "User-Agent")
        let body: [String: Any] = [
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "tier": tier,
            "stream": true,
            "user": user,
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, resp) = try await session.bytes(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "Cortex API \(http.statusCode)"])
        }

        var full = ""
        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            if payload == "[DONE]" { break }
            if let obj = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any] {
                if let err = obj["error"] as? String {
                    throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: err])
                }
                if let delta = obj["delta"] as? String {
                    full += delta
                    onDelta(delta)
                }
            }
        }
        return full
    }
}
