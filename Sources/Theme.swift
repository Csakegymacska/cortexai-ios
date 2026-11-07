import SwiftUI

/// Cortex AI design system. Everything is black: a true black canvas, faint violet/cyan
/// light bleeding in from the corners, and charcoal panels that only separate themselves
/// from the background with a 1 pt hairline.
enum Theme {
    // Canvas
    static let ink = Color(hex: 0x050506)
    static let surface = Color(hex: 0x0E0E11)
    static let surfaceRaised = Color(hex: 0x16161B)
    static let hairline = Color.white.opacity(0.07)
    static let hairlineStrong = Color.white.opacity(0.14)

    // Type
    static let text = Color(hex: 0xF5F5F7)
    static let textMuted = Color(hex: 0x9A9AA8)
    static let textFaint = Color(hex: 0x66667A)

    // Accents
    static let violet = Color(hex: 0x8B5CF6)
    static let violetSoft = Color(hex: 0xB79CFF)
    static let magenta = Color(hex: 0xE879F9)
    static let cyan = Color(hex: 0x22D3EE)
    static let danger = Color(hex: 0xFB7185)
    static let success = Color(hex: 0x34D399)

    static let brand = LinearGradient(
        colors: [Color(hex: 0x22D3EE), Color(hex: 0x8B5CF6), Color(hex: 0xE879F9)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    static let accent = LinearGradient(
        colors: [Color(hex: 0x8B5CF6), Color(hex: 0xE879F9)],
        startPoint: .leading, endPoint: .trailing
    )

    static let bubbleUser = LinearGradient(
        colors: [Color(hex: 0x7C4DFF).opacity(0.92), Color(hex: 0x6A34FF).opacity(0.92)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    // Metrics
    static let radius: CGFloat = 20
    static let radiusSmall: CGFloat = 14
    static let gutter: CGFloat = 18

    static func title(_ size: CGFloat) -> Font { .system(size: size, weight: .bold, design: .rounded) }
    static func body(_ size: CGFloat = 16) -> Font { .system(size: size, weight: .regular) }
    static let mono = Font.system(size: 13, design: .monospaced)
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

/// The ambient light behind every screen: two soft radial glows and a grain-free black base.
struct AuroraBackground: View {
    var intensity: Double = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            staticAurora
        } else {
            // 7.4: élő auróra — a fényfoltok lassan úsznak (30 fps plafon, alacsony fogyasztás).
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let d1 = CGSize(width: sin(t * 0.11) * 60, height: cos(t * 0.09) * 44)
                let d2 = CGSize(width: cos(t * 0.08) * 70, height: sin(t * 0.12) * 50)
                let d3 = CGSize(width: sin(t * 0.07 + 1.7) * 55, height: cos(t * 0.10 + 0.6) * 40)
                ZStack {
                    Theme.ink
                    RadialGradient(
                        colors: [Theme.violet.opacity(0.30 * intensity), .clear],
                        center: .init(x: 0.12 + d1.width / 1400, y: -0.05 + d1.height / 1400), startRadius: 8, endRadius: 520
                    )
                    RadialGradient(
                        colors: [Theme.cyan.opacity(0.16 * intensity), .clear],
                        center: .init(x: 1.05 + d2.width / 1400, y: 0.22 + d2.height / 1400), startRadius: 8, endRadius: 460
                    )
                    RadialGradient(
                        colors: [Theme.magenta.opacity(0.13 * intensity), .clear],
                        center: .init(x: 0.85 + d3.width / 1400, y: 1.05 + d3.height / 1400), startRadius: 8, endRadius: 520
                    )
                }
                .ignoresSafeArea()
            }
        }
    }

    private var staticAurora: some View {
        ZStack {
            Theme.ink
            RadialGradient(
                colors: [Theme.violet.opacity(0.30 * intensity), .clear],
                center: .init(x: 0.12, y: -0.05), startRadius: 8, endRadius: 520
            )
            RadialGradient(
                colors: [Theme.cyan.opacity(0.16 * intensity), .clear],
                center: .init(x: 1.05, y: 0.22), startRadius: 8, endRadius: 460
            )
            RadialGradient(
                colors: [Theme.magenta.opacity(0.13 * intensity), .clear],
                center: .init(x: 0.85, y: 1.05), startRadius: 8, endRadius: 520
            )
        }
        .ignoresSafeArea()
    }
}

/// The Cortex sigil: a broken ring with a solid core, drawn with the brand gradient.
struct CortexMark: View {
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0.08, to: 0.92)
                .stroke(Theme.brand, style: StrokeStyle(lineWidth: size * 0.20, lineCap: .round))
                .rotationEffect(.degrees(38))
            Circle()
                .fill(Theme.brand)
                .frame(width: size * 0.30, height: size * 0.30)
        }
        .frame(width: size, height: size)
        .shadow(color: Theme.violet.opacity(0.55), radius: size * 0.35)
    }
}

/// Charcoal panel used across the app.
struct Panel<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
    }
}

/// Small uppercase label used above sections.
struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .heavy))
            .tracking(1.2)
            .foregroundStyle(Theme.textFaint)
    }
}

struct GradientBorder: ViewModifier {
    var radius: CGFloat = 26
    var width: CGFloat = 1
    var opacity: Double = 0.75

    func body(content: Content) -> some View {
        content.overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Theme.brand.opacity(opacity), lineWidth: width)
        )
    }
}

extension View {
    func gradientBorder(radius: CGFloat = 26, width: CGFloat = 1, opacity: Double = 0.75) -> some View {
        modifier(GradientBorder(radius: radius, width: width, opacity: opacity))
    }
}
