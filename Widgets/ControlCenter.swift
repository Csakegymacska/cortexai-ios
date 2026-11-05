import AppIntents
import SwiftUI
import WidgetKit

// ── Vezérlőközpont ──────────────────────────────────────────────────────────
// Két kapcsoló a Vezérlőközpontba, a zárképernyőre és a Beállítások mellé:
//   • Kérdezd a Cortexet — azonnal a beviteli mezőbe visz.
//   • Ma mi jön ki — a napi kártyát nyitja meg.
// Mindkettő a widget-kiterjesztésben él, mert a vezérlők ott laknak; futásukkor
// csak egy kérést tesznek le a UserDefaults-ba, és megnyitják az appot. Hálózatot
// nem hívnak, ezért azonnal reagálnak.

enum ControlBridge {
    static let pendingKey = "cortex.pendingPrompt"
    static let openDailyKey = "cortex.openDaily"
}

struct AskCortexControlIntent: AppIntent {
    static var title: LocalizedStringResource { "Ask Cortex" }
    static var description: IntentDescription { IntentDescription("Open Cortex AI ready for a question.") }
    static var openAppWhenRun: Bool { true }

    func perform() async throws -> some IntentResult {
        UserDefaults.standard.removeObject(forKey: ControlBridge.openDailyKey)
        return .result()
    }
}

struct OpenDailyControlIntent: AppIntent {
    static var title: LocalizedStringResource { "What airs today" }
    static var description: IntentDescription { IntentDescription("Open the daily card: airings and news.") }
    static var openAppWhenRun: Bool { true }

    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(true, forKey: ControlBridge.openDailyKey)
        return .result()
    }
}

@available(iOS 18.0, *)
struct AskCortexControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "hu.cortex.ai.control.ask") {
            ControlWidgetButton(action: AskCortexControlIntent()) {
                Label("Ask Cortex", systemImage: "sparkles")
            }
        }
        .displayName("Kérdezd a Cortexet")
        .description("Egy koppintás, és már írhatod is a kérdést.")
    }
}

@available(iOS 18.0, *)
struct DailyControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "hu.cortex.ai.control.daily") {
            ControlWidgetButton(action: OpenDailyControlIntent()) {
                Label("Ma mi jön ki", systemImage: "play.tv")
            }
        }
        .displayName("Ma mi jön ki")
        .description("A mai adások és a friss hírek, egy koppintással.")
    }
}

// ── Interaktív gomb a Gyorskérdés widgeten ──────────────────────────────────
// A kérdés-gombok eddig linkkel nyitottak. Most App Intenttel is mennek, így a
// widget maga is elindíthatja a kérést appnyitás nélkül a rendszer-naplóban.

struct AskQuestionIntent: AppIntent {
    static var title: LocalizedStringResource { "Ask this question" }
    static var openAppWhenRun: Bool { true }

    @Parameter(title: "Question")
    var question: String

    init() { self.question = "" }

    init(question: String) { self.question = question }

    func perform() async throws -> some IntentResult {
        let clean = question.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.isEmpty {
            UserDefaults.standard.set(clean, forKey: ControlBridge.pendingKey)
        }
        return .result()
    }
}
