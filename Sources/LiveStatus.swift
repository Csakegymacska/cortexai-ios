import SwiftUI

/// What the assistant is doing right now. The pill above the composer reads this, so
/// the app never shows a nameless spinner: it says whether Cortex is still thinking or
/// already writing.
enum CortexPhase: String, Equatable {
    case idle
    case thinking
    case writing

    var label: String {
        switch self {
        case .idle: return ""
        case .thinking: return "Thinking"
        case .writing: return "Writing"
        }
    }

    var symbol: String {
        switch self {
        case .idle: return "sparkles"
        case .thinking: return "brain.head.profile"
        case .writing: return "text.alignleft"
        }
    }

    var aura: AuraMode {
        switch self {
        case .idle: return .idle
        case .thinking: return .thinking
        case .writing: return .writing
        }
    }
}

// MARK: - Phase pill

/// A small glass pill that morphs between "Thinking" and "Writing". Collapses away
/// when idle so the transcript keeps the space.
struct PhasePill: View {
    let phase: CortexPhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: phase.symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.violetSoft)
                .contentTransition(.symbolEffect(.replace))
            Text(phase.label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textMuted)
                .contentTransition(.opacity)
            PhaseDots()
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: Capsule())
        .background(Theme.surface.opacity(0.7), in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
        .opacity(phase == .idle ? 0 : 1)
        .scaleEffect(phase == .idle && !reduceMotion ? 0.92 : 1)
        .animation(CortexMotion.snappy, value: phase)
        .accessibilityLabel(phase.label)
        .accessibilityIdentifier("chat.phase")
    }
}

/// Three dots that chase each other, driven by one animation instead of a timer.
struct PhaseDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animating = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Theme.violetSoft)
                    .frame(width: 4, height: 4)
                    .opacity(reduceMotion ? 0.6 : (animating ? 1 : 0.25))
                    .scaleEffect(reduceMotion ? 1 : (animating ? 1 : 0.7))
                    .animation(
                        reduceMotion
                            ? nil
                            : .easeInOut(duration: 0.55)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.16),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
    }
}

// MARK: - Streaming cursor

/// The caret at the end of a reply that is still arriving. It blinks on its own and
/// disappears the moment the stream ends — never before the last character paints.
struct StreamCursor: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var on = true

    var body: some View {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(LinearGradient(colors: [Theme.cyan, Theme.violet], startPoint: .top, endPoint: .bottom))
            .frame(width: 2.5, height: 15)
            .opacity(on ? 1 : 0.25)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: on)
            .onAppear { on.toggle() }
            .accessibilityHidden(true)
    }
}

// MARK: - Skeleton

/// Placeholder lines for the first moment of a reply, before the first token lands.
struct SkeletonLines: View {
    var widths: [CGFloat] = [0.92, 0.78, 0.55]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(widths.enumerated()), id: \.offset) { _, width in
                GeometryReader { geo in
                    Capsule()
                        .fill(Theme.surfaceRaised)
                        .frame(width: geo.size.width * width, height: 9)
                }
                .frame(height: 9)
            }
        }
        .cortexShimmer()
        .accessibilityHidden(true)
    }
}
