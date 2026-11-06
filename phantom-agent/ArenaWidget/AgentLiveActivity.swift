// AgentLiveActivity — a Dynamic Island és a zárt képernyő megjelenítései.
// Három island-formátum KÖTELEZŐ: minimal, compact (leading+trailing), expanded.
import ActivityKit
import SwiftUI
import WidgetKit

struct AgentLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AgentActivityAttributes.self) { context in
            // ── zárt képernyő / StandBy ──
            LockScreenView(state: context.state)
                .activityBackgroundTint(Color(red: 0.055, green: 0.051, blue: 0.09))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                // ── kibontott állapot ──
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        RingIcon(working: context.state.state == "working")
                            .frame(width: 26, height: 26)
                        Text(AgentState(rawValue: context.state.state)?.label ?? "Idle")
                            .font(.headline)
                            .foregroundStyle(.white)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.at > 0 {
                        Text(Date(timeIntervalSince1970: TimeInterval(context.state.at)), style: .timer)
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(Color(red: 0.91, green: 0.47, blue: 0.98))
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Image(systemName: "terminal")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                        Text(context.state.step.isEmpty ? "Standing by" : context.state.step)
                            .font(.caption.monospaced())
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(2)
                        Spacer()
                    }
                }
            } minimal: {
                RingIcon(working: context.state.state == "working")
                    .frame(width: 22, height: 22)
            } compactLeading: {
                RingIcon(working: context.state.state == "working")
                    .frame(width: 22, height: 22)
            } compactTrailing: {
                if context.state.at > 0 {
                    Text(Date(timeIntervalSince1970: TimeInterval(context.state.at)), style: .timer)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Color(red: 0.91, green: 0.47, blue: 0.98))
                        .frame(maxWidth: 44)
                } else {
                    Image(systemName: "terminal")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .keylineTint(Color(red: 0.55, green: 0.4, blue: 0.98))
        }
    }
}

/// Gradiens gyűrű — dolgozik: pulzáló fény; egyébként halvány.
struct RingIcon: View {
    let working: Bool
    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(
                    AngularGradient(colors: working
                        ? [Color(red: 0.49, green: 0.36, blue: 0.97), Color(red: 0.91, green: 0.47, blue: 0.98), Color(red: 0.49, green: 0.36, blue: 0.97)]
                        : [.white.opacity(0.25)], center: .center),
                    lineWidth: 2.5
                )
            if working {
                Circle().fill(Color(red: 0.91, green: 0.47, blue: 0.98).opacity(0.9))
                    .scaleEffect(0.42)
            } else {
                Image(systemName: "terminal")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }
}

/// Zárt képernyő-kártya.
struct LockScreenView: View {
    let state: AgentActivityAttributes.ContentState
    var body: some View {
        HStack(spacing: 12) {
            RingIcon(working: state.state == "working")
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(AgentState(rawValue: state.state)?.label ?? "Idle")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(state.step.isEmpty ? "Cortex Agent for Arena" : state.step)
                    .font(.caption.monospaced())
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
            Spacer()
            if state.at > 0 {
                Text(Date(timeIntervalSince1970: TimeInterval(state.at)), style: .timer)
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Color(red: 0.91, green: 0.47, blue: 0.98))
            }
        }
        .padding(16)
    }
}
