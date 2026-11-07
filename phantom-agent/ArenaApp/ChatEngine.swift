// ChatEngine — a saját motorunk: NATÍV chat (Cortex Phantom / Phantom Core 2).
// Full natív — nincs webes nézet, minden a miénk.
import Foundation

/// Az üzenet — a natív chat alap-típusa.
/// (Az ArenaMessage típus-alias marad a régi fájlban; ez a használt forma.)
typealias ChatMessage = ArenaMessage

/// A natív chat-ülés — kizárólag a saját AI-nkkal (Cortex Phantom, Phantom Core 2).
@MainActor
final class ChatSession: ObservableObject {
    @Published var messages: [ArenaMessage] = []
    @Published var streaming = false

    let cortex = CortexAPIClient()

    var canSend: Bool { !streaming }

    func send(_ text: String, onDelta: @escaping (String) -> Void) async {
        guard !text.isEmpty, !streaming else { return }
        streaming = true
        defer { streaming = false }
        messages.append(ArenaMessage(role: "user", content: text))
        var reply = ""
        do {
            reply = try await cortex.stream(messages: messages, onDelta: onDelta)
        } catch {
            reply = "Error: \(error.localizedDescription)"
        }
        messages.append(ArenaMessage(role: "assistant", content: reply))
    }

    func reset() { messages.removeAll() }
}
