import SwiftUI

/// Motion tokens for Cortex AI. One place decides how everything moves, so the app
/// never mixes five different easings. Every animation here has a Reduce Motion
/// escape hatch: when the system asks for less movement, the motion becomes a cut.
enum CortexMotion {
    /// Buttons, toggles, the send button morph.
    static let snappy = Animation.spring(response: 0.32, dampingFraction: 0.80)
    /// Bubbles arriving, cards expanding, sheets settling.
    static let gentle = Animation.spring(response: 0.52, dampingFraction: 0.88)
    /// Playful accents: the mark, suggestion chips, the voice ring.
    static let bouncy = Animation.spring(response: 0.44, dampingFraction: 0.62)
    static let fade = Animation.easeOut(duration: 0.22)

    /// Staggered delay for the n-th item of a list.
    static func delay(_ index: Int, step: Double = 0.045) -> Double {
        Double(min(index, 12)) * step
    }
}

// MARK: - Entrance

/// Rise-and-settle. Used for message bubbles, suggestion chips and rows, with a
/// small stagger so a list assembles instead of appearing all at once.
private struct CortexEntrance: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let index: Int
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 16)
            .scaleEffect(shown ? 1 : 0.97, anchor: .bottom)
            .onAppear {
                guard !shown else { return }
                guard !reduceMotion else { shown = true; return }
                withAnimation(CortexMotion.gentle.delay(CortexMotion.delay(index))) { shown = true }
            }
    }
}

extension View {
    func cortexEntrance(index: Int = 0) -> some View {
        modifier(CortexEntrance(index: index))
    }
}

// MARK: - Press

/// Shrinks slightly under the finger and gives a light haptic. Every tappable
/// surface in the app uses this instead of the default highlight.
struct CortexPressStyle: ButtonStyle {
    var scale: CGFloat = 0.955
    var haptic = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(CortexMotion.snappy, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed && haptic { Haptics.tap() }
            }
    }
}

extension ButtonStyle where Self == CortexPressStyle {
    static var cortexPress: CortexPressStyle { CortexPressStyle() }
    static func cortexPress(scale: CGFloat) -> CortexPressStyle { CortexPressStyle(scale: scale) }
}

// MARK: - Shimmer

/// A slow light sweep for skeletons and "thinking" surfaces.
private struct Shimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geo in
                    LinearGradient(
                        colors: [.clear, Color.white.opacity(0.09), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: max(60, geo.size.width * 0.55))
                    .offset(x: phase * geo.size.width * 1.7)
                }
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
                .opacity(reduceMotion ? 0 : 1)
            }
            .clipped()
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

extension View {
    func cortexShimmer() -> some View { modifier(Shimmer()) }
}

// MARK: - Breathing

/// A soft scale pulse, used by the mark while Cortex is working.
private struct Breathing: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let active: Bool
    @State private var up = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(up ? 1.06 : 1)
            .animation(
                reduceMotion || !active
                    ? CortexMotion.fade
                    : .easeInOut(duration: 1.35).repeatForever(autoreverses: true),
                value: up
            )
            .onAppear { up = active }
            .onChange(of: active) { _, next in up = next }
    }
}

extension View {
    func cortexBreathing(_ active: Bool) -> some View { modifier(Breathing(active: active)) }
}
