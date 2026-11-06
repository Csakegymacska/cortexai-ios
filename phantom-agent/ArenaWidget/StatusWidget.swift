// StatusWidget — a kezdőképernyő widgetje: az agent állapota egy pillantásra.
import WidgetKit
import SwiftUI

struct StatusEntry: TimelineEntry {
    let date: Date
    let status: AgentStatus
}

struct StatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> StatusEntry {
        StatusEntry(date: .now, status: AgentStatus(state: "working", step: "bash: python3 tools/phantom_mix.py", at: Int(Date().timeIntervalSince1970)))
    }
    func getSnapshot(in context: Context, completion: @escaping (StatusEntry) -> Void) {
        completion(placeholder(in: context))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<StatusEntry>) -> Void) {
        // Lekérés a hídról — a widget 30 mp-enként frissülhet a policy szerint.
        let url = URL(string: UserDefaults(suiteName: "group.eu.cortex.phantom")?
            .string(forKey: "status.url") ?? "https://cortanime.eu/api/cortexai/agent/status")!
        URLSession.shared.dataTask(with: url) { data, _, _ in
            var s = AgentStatus()
            if let data, let j = try? JSONDecoder().decode(W.self, from: data) {
                s = AgentStatus(state: j.state, step: j.step, at: j.at, turn: 0)
            }
            let entry = StatusEntry(date: .now, status: s)
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(120))))
        }.resume()
    }
    struct W: Decodable { let state: String; let step: String; let at: Int }
}

struct StatusWidgetView: View {
    var entry: StatusEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        ZStack {
            Color(red: 0.055, green: 0.051, blue: 0.09)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    RingIcon(working: entry.status.isWorking)
                        .frame(width: 22, height: 22)
                    Text("Cortex Agent")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    if entry.status.at > 0 {
                        Text(entry.status.since, style: .timer)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(Color(red: 0.91, green: 0.47, blue: 0.98))
                    }
                }
                Text(AgentState(rawValue: entry.status.state)?.label ?? "Idle")
                    .font(.headline)
                    .foregroundStyle(.white)
                if family != .systemSmall {
                    Text(entry.status.step.isEmpty ? "Standing by" : entry.status.step)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
        }
    }
}

struct StatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "eu.cortex.phantom.status", provider: StatusProvider()) { entry in
            StatusWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color(red: 0.055, green: 0.051, blue: 0.09) }
        }
        .configurationDisplayName("Agent Status")
        .description("What the Cortex Agent is doing right now.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct ArenaWidgetBundle: WidgetBundle {
    var body: some Widget {
        StatusWidget()
        AgentLiveActivity()
    }
}
