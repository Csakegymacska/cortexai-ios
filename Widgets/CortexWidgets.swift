import SwiftUI
import WidgetKit

// ── Közös ────────────────────────────────────────────────────────────────────
// Négy widget, egy nyelvezet: fekete alapon violet–cián, kevés szöveg, nagy szám.
// Mindegyik a nyilvános Cortex API-ról dolgozik, ezért nem kell megosztott konténer
// (app group), és a telepítéskor sem kell hozzá külön engedély.

private enum Ink {
    static var background: Color { Color(red: 0.02, green: 0.02, blue: 0.025) }
    static var card: Color { Color(red: 0.06, green: 0.06, blue: 0.07) }
    static var text: Color { Color(red: 0.96, green: 0.96, blue: 0.97) }
    static var muted: Color { Color(red: 0.60, green: 0.60, blue: 0.66) }
    static var violet: Color { Color(red: 0.55, green: 0.36, blue: 0.96) }
    static var cyan: Color { Color(red: 0.13, green: 0.83, blue: 0.93) }
    static var green: Color { Color(red: 0.20, green: 0.83, blue: 0.60) }
    static var warn: Color { Color(red: 0.97, green: 0.44, blue: 0.52) }
}

/// Egyszer lefutó hívás: a WidgetKit completion-jét becsomagolja, hogy a háttérfeladatból
/// is biztonságosan (és csak egyszer) lehessen meghívni. Swift 6 alatt ez a tiszta út.
private final class Once<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false
    private let handler: (T) -> Void

    init(_ handler: @escaping (T) -> Void) { self.handler = handler }

    func fire(_ value: T) {
        lock.lock()
        if fired { lock.unlock(); return }
        fired = true
        lock.unlock()
        handler(value)
    }
}

private func deepLink(_ question: String) -> URL {
    let encoded = question.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
    return URL(string: "cortexai://ask?q=\(encoded)") ?? URL(string: "cortexai://ask")!
}

// ── 1. Állapot ───────────────────────────────────────────────────────────────

struct StatusEntry: TimelineEntry {
    let date: Date
    let model: String
    let online: Bool
    let runner: Bool
}

struct StatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> StatusEntry {
        StatusEntry(date: Date(), model: "Cortex Void", online: true, runner: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (StatusEntry) -> Void) {
        if context.isPreview { completion(placeholder(in: context)); return }
        let done = Once(completion)
        Task { done.fire(await load()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StatusEntry>) -> Void) {
        let done = Once(completion)
        Task {
            let entry = await load()
            done.fire(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(900))))
        }
    }

    private func load() async -> StatusEntry {
        async let health = WidgetData.health()
        async let sandbox = WidgetData.sandbox()
        let h = await health
        let s = await sandbox
        return StatusEntry(
            date: Date(),
            model: h?.model ?? "Cortex Void",
            online: h?.ok ?? false,
            runner: s?.ready ?? false
        )
    }
}

struct StatusWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StatusEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(entry.online ? Ink.green : Ink.warn)
                    .frame(width: 7, height: 7)
                Text(entry.model.uppercased())
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(Ink.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(entry.online ? "online" : "offline")
                .font(.system(size: 21, weight: .bold, design: .rounded))
                .foregroundStyle(entry.online ? Ink.text : Ink.warn)
            if family != .systemSmall {
                Text("magyarul, motor nélkül is")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Ink.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            HStack(spacing: 5) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 8, weight: .bold))
                Text(entry.runner ? "futtatás él" : "futtatás ki")
                    .font(.system(size: 9.5, weight: .semibold))
            }
            .foregroundStyle(entry.runner ? Ink.cyan : Ink.muted)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Ink.card, in: Capsule())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(for: .widget) { Ink.background }
        .widgetURL(URL(string: "cortexai://ask"))
    }
}

struct CortexStatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CortexStatus", provider: StatusProvider()) { entry in
            StatusWidgetView(entry: entry)
        }
        .configurationDisplayName("Cortex állapot")
        .description("Él-e a Cortex, és fut-e rajta kód.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// ── 2. Napi kérés ────────────────────────────────────────────────────────────

struct PromptEntry: TimelineEntry {
    let date: Date
    let prompt: String
}

struct PromptProvider: TimelineProvider {
    private func entry(_ now: Date = Date()) -> PromptEntry {
        PromptEntry(date: now, prompt: DailyPrompt.today(now))
    }

    func placeholder(in context: Context) -> PromptEntry { entry() }

    func getSnapshot(in context: Context, completion: @escaping (PromptEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PromptEntry>) -> Void) {
        let now = Date()
        let tomorrow = Calendar.current.nextDate(
            after: now, matching: DateComponents(hour: 0, minute: 5), matchingPolicy: .nextTime
        ) ?? now.addingTimeInterval(6 * 3600)
        completion(Timeline(entries: [entry(now)], policy: .after(tomorrow)))
    }
}

struct PromptWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PromptEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Ink.violet)
                Text("NAPI KÉRÉS")
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(Ink.muted)
            }
            Text(entry.prompt)
                .font(.system(size: family == .systemSmall ? 12.5 : 15, weight: .semibold))
                .foregroundStyle(Ink.text)
                .lineLimit(family == .systemSmall ? 4 : 3)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
            Text("koppints és kérdezd meg")
                .font(.system(size: 9.5))
                .foregroundStyle(Ink.violet.opacity(0.9))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(for: .widget) {
            LinearGradient(colors: [Ink.background, Ink.violet.opacity(0.18)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .widgetURL(deepLink(entry.prompt))
    }
}

struct CortexPromptWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CortexPrompt", provider: PromptProvider()) { entry in
            PromptWidgetView(entry: entry)
        }
        .configurationDisplayName("Napi kérés")
        .description("Egy kérdés naponta — koppintásra az app válaszol rá.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// ── 3. Következő adások ──────────────────────────────────────────────────────

struct ReleaseEntry: TimelineEntry {
    let date: Date
    let items: [WidgetData.Ep]
    let failed: Bool
}

struct ReleaseProvider: TimelineProvider {
    func placeholder(in context: Context) -> ReleaseEntry {
        ReleaseEntry(date: Date(), items: [], failed: false)
    }

    private func load() async -> ReleaseEntry {
        let items = await WidgetData.episodes()
        return ReleaseEntry(date: Date(), items: WidgetData.upcoming(items), failed: items.isEmpty)
    }

    func getSnapshot(in context: Context, completion: @escaping (ReleaseEntry) -> Void) {
        if context.isPreview { completion(placeholder(in: context)); return }
        let done = Once(completion)
        Task { done.fire(await load()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ReleaseEntry>) -> Void) {
        let done = Once(completion)
        Task {
            let entry = await load()
            done.fire(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(1800))))
        }
    }
}

struct ReleaseWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ReleaseEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Ink.cyan)
                Text("KÖVETKEZŐ ADÁSOK")
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(Ink.muted)
                Spacer(minLength: 0)
            }
            if entry.items.isEmpty {
                Spacer(minLength: 0)
                Text(entry.failed ? "Az adat most nem érhető el." : "Nincs a láthatáron új rész.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Ink.muted)
                Spacer(minLength: 0)
            } else {
                ForEach(Array(entry.items.enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title ?? "Sorozat")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Ink.text)
                            .lineLimit(1)
                        HStack(spacing: 5) {
                            Text("\(item.ep ?? 0). rész")
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundStyle(Ink.cyan)
                            Text(WidgetFormat.when(item.ts))
                                .font(.system(size: 9.5))
                                .foregroundStyle(Ink.muted)
                            Text("· \(WidgetFormat.countdown(item.ts))")
                                .font(.system(size: 9.5))
                                .foregroundStyle(Ink.muted.opacity(0.8))
                        }
                    }
                    if family != .systemMedium { Divider().overlay(Ink.muted.opacity(0.2)) }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(for: .widget) { Ink.background }
        .widgetURL(URL(string: "https://cortanime.eu/"))
    }
}

struct CortexReleaseWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CortexRelease", provider: ReleaseProvider()) { entry in
            ReleaseWidgetView(entry: entry)
        }
        .configurationDisplayName("Következő adások")
        .description("A legközelebbi részek magyar idő szerint.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

// ── 4. Gyorskérdés ───────────────────────────────────────────────────────────

struct AskEntry: TimelineEntry {
    let date: Date
}

struct AskProvider: TimelineProvider {
    func placeholder(in context: Context) -> AskEntry { AskEntry(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (AskEntry) -> Void) { completion(AskEntry(date: Date())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<AskEntry>) -> Void) {
        completion(Timeline(entries: [AskEntry(date: Date())], policy: .never))
    }
}

struct AskWidgetView: View {
    let entry: AskEntry

    private let actions: [(String, String, String, Color)] = [
        ("terminal.fill", "Számolj", "Számold ki lépésenként: ", Ink.cyan),
        ("text.bubble.fill", "Magyarázz", "Magyarázd el egyszerűen: ", Ink.violet),
        ("character.book.closed.fill", "Fordíts", "Fordítsd angolra: ", Ink.green),
        ("sparkles", "Ajánlj", "Ajánlj egy sorozatot estére a kínálatból.", Ink.muted)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CORTEX")
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .tracking(1.4)
                .foregroundStyle(Ink.muted)
            HStack(spacing: 8) {
                ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                    Link(destination: deepLink(action.2)) {
                        VStack(spacing: 5) {
                            Image(systemName: action.0)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(action.3)
                            Text(action.1)
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(Ink.text)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Ink.card, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(for: .widget) { Ink.background }
    }
}

struct CortexAskWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CortexAsk", provider: AskProvider()) { entry in
            AskWidgetView(entry: entry)
        }
        .configurationDisplayName("Gyorskérdés")
        .description("Négy gomb, négy kész kérdés — egy koppintás az appig.")
        .supportedFamilies([.systemMedium])
    }
}

// ── Belépő ───────────────────────────────────────────────────────────────────

@main
struct CortexWidgets: WidgetBundle {
    var body: some Widget {
        CortexStatusWidget()
        CortexPromptWidget()
        CortexReleaseWidget()
        CortexAskWidget()
        // Vezérlőközpont (iOS 18+): két kapcsoló, ugyanabban a kiterjesztésben.
        if #available(iOS 18.0, *) {
            AskCortexControl()
            DailyControl()
        }
    }
}
