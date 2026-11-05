import AppIntents
import Foundation

/// „Kérdezd a Cortexet” a Siri-ből, a Shortcuts-ból vagy a Spotlightból.
///
/// Az intent nem hálózatot hív és nem tart állapotot: egyetlen sort tesz le a
/// UserDefaults-ba, és megnyitja az appot. Az app a saját beszélgetésfolyamán
/// válaszol rá, így a válasz ugyanúgy jelenik meg, mintha begépelték volna —
/// memóriával, profillal, forrásokkal együtt.
struct AskCortexIntent: AppIntent {
    static var title: LocalizedStringResource { "Ask Cortex" }
    static var description: IntentDescription { IntentDescription("Ask a question and let Cortex answer in the app.") }
    static var openAppWhenRun: Bool { true }

    @Parameter(title: "Question")
    var question: String

    init() {}

    init(question: String) {
        self.question = question
    }

    func perform() async throws -> some IntentResult {
        let clean = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return .result() }
        UserDefaults.standard.set(clean, forKey: PendingPromptKey)
        return .result()
    }
}

/// The single key both sides agree on. Kept in one place so the app and the intent
/// cannot drift apart.
let PendingPromptKey = "cortex.pendingPrompt"

enum PendingPrompt {
    /// Takes the question left by the intent, and clears it so it only runs once.
    static func take() -> String? {
        let raw = UserDefaults.standard.string(forKey: PendingPromptKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.removeObject(forKey: PendingPromptKey)
        guard let raw, !raw.isEmpty else { return nil }
        return raw
    }
}

struct CortexShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskCortexIntent(),
            phrases: [
                "Ask \(.applicationName)",
                "Kérdezd meg a \(.applicationName)-t"
            ],
            shortTitle: "Ask Cortex",
            systemImageName: "sparkles"
        )
    }
}
