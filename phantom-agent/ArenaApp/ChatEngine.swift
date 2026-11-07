// ChatEngine — a saját motorunk: NATÍV chat (Cortex Phantom / Phantom Core 2)
// vagy WEB munkaterület (cortanime.eu/ai). Semmi külső — minden a miénk.
import Foundation

enum ChatEngineKind: String, CaseIterable, Identifiable {
    case native = "native"
    case agentWeb = "web"

    var id: String { rawValue }

    /// UI-címkék — angolul, a kötés szerint.
    var label: String {
        switch self {
        case .native: return "Native chat"
        case .agentWeb: return "Web workspace"
        }
    }

    var subtitle: String {
        switch self {
        case .native: return "Cortex Phantom — our own brain, fully native"
        case .agentWeb: return "Full agent sessions at cortanime.eu/ai"
        }
    }
}

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
