// ChatEngine — motorválasztás: NATÍV (Cortex Phantom / Arena API) vs AGENT WEB.
// A natív két providerre bontva: a SAJÁT AI-nk (Cortex Phantom, cortanime.eu)
// és a hivatalos Arena API (api.arena.ai). Az agent-web a munkamenetes agent-mód.
import Foundation

enum ChatEngineKind: String, CaseIterable, Identifiable {
    case native = "native"
    case agentWeb = "agent-web"

    var id: String { rawValue }

    /// UI-címkék — angolul, a kötés szerint.
    var label: String {
        switch self {
        case .native: return "Native chat"
        case .agentWeb: return "Agent workspace (web)"
        }
    }

    var subtitle: String {
        switch self {
        case .native: return "Cortex Phantom (our AI) or Arena API — fully native"
        case .agentWeb: return "Full agent sessions with tools and workspace"
        }
    }
}

/// Natív chat-providerek.
enum ProviderKind: String, CaseIterable, Identifiable {
    case phantom = "phantom"
    case arena = "arena"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .phantom: return "Cortex Phantom"
        case .arena: return "Arena API"
        }
    }

    var subtitle: String {
        switch self {
        case .phantom: return "Our own AI — Phantom Core 2 pipeline"
        case .arena: return "Frontier models via api.arena.ai"
        }
    }
}

/// A natív chat-üllés — provider-érzékeny.
@MainActor
final class ChatSession: ObservableObject {
    @Published var messages: [ArenaMessage] = []
    @Published var streaming = false
    @Published var provider: ProviderKind = {
        ProviderKind(rawValue: UserDefaults.standard.string(forKey: "chat.provider") ?? "") ?? .phantom
    }()
    @Published var model = UserDefaults.standard.string(forKey: "arena.model") ?? "coding-router-preview"

    let arena = ArenaAPIClient()
    let cortex = CortexAPIClient()

    var canSend: Bool {
        !streaming && (provider == .phantom || !arena.apiKey.isEmpty)
    }

    func select(_ p: ProviderKind) {
        guard p != provider else { return }
        provider = p
        UserDefaults.standard.set(p.rawValue, forKey: "chat.provider")
        messages.removeAll()
    }

    func send(_ text: String, onDelta: @escaping (String) -> Void) async {
        guard !text.isEmpty, !streaming else { return }
        streaming = true
        defer { streaming = false }
        messages.append(ArenaMessage(role: "user", content: text))
        var reply = ""
        do {
            switch provider {
            case .phantom:
                reply = try await cortex.stream(messages: messages, onDelta: onDelta)
            case .arena:
                reply = try await arena.stream(model: model, messages: messages, onDelta: onDelta)
            }
        } catch {
            reply = "Error: \(error.localizedDescription)"
        }
        messages.append(ArenaMessage(role: "assistant", content: reply))
    }

    func reset() { messages.removeAll() }
}
