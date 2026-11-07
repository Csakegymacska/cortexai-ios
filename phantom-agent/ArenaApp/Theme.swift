// Theme — a Cortex Phantom Agent dizájnvonal: sötét/violet, élő fényekkel.
// Szabály: UI-szöveg angolul, emoji sehol — csak SF Symbols és vektor.
// Saját betűtípusok: Sora (display) + Inter (UI) — beépítve, Resources/Fonts.
import SwiftUI
import UIKit

enum Theme {
    // Háttér-szintek
    static let bg = Color(red: 0.043, green: 0.043, blue: 0.071)        // #0B0B12
    static let surf = Color(red: 0.086, green: 0.082, blue: 0.137)      // #161523
    static let surf2 = Color(red: 0.125, green: 0.118, blue: 0.192)     // #201E31
    static let line = Color.white.opacity(0.08)

    // Violet gradiens
    static let vio = Color(red: 0.486, green: 0.361, blue: 0.965)       // #7C5CF6
    static let pink = Color(red: 0.910, green: 0.475, blue: 0.976)      // #E879F9
    static let blue = Color(red: 0.290, green: 0.345, blue: 0.930)      // hideg aurora-folt
    static var accent: LinearGradient {
        LinearGradient(colors: [vio, pink], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static let txt = Color.white
    static let txt2 = Color.white.opacity(0.62)
    static let txt3 = Color.white.opacity(0.38)

    // Saját betűtípusok — Sora a megjelenő szöveg, Inter a felület
    static func display(_ size: CGFloat) -> Font { .custom("Sora", size: size) }
    static func ui(_ size: CGFloat) -> Font { .custom("Inter", size: size) }

    static let mono = Font.system(.caption, design: .monospaced).weight(.medium)

    // Animációs ívek
    static let spring = Animation.spring(response: 0.42, dampingFraction: 0.82)
    static let softSpring = Animation.spring(response: 0.6, dampingFraction: 0.9)
}

/// Haptikus visszajelzés — a prémium érzés apró, de fontos része.
enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func select() { UISelectionFeedbackGenerator().selectionChanged() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
}

/// Aurora-háttér — beépített nebula-grafika + élő fénypontok + kódolt aurora.
struct AuroraBackground: View {
    @AppStorage("ui.reduceMotion") private var reduceMotion = false
    @State private var spin = false
    @State private var drift = false

    var body: some View {
        ZStack {
            Theme.bg

            // beépített nebula — lassú lebegés
            Image("BgNebula")
                .resizable()
                .scaledToFill()
                .opacity(0.62)
                .scaleEffect(drift && !reduceMotion ? 1.12 : 1.0)
                .offset(x: drift && !reduceMotion ? -14 : 8, y: drift && !reduceMotion ? -18 : 6)
                .animation(reduceMotion ? nil : .easeInOut(duration: 22).repeatForever(autoreverses: true), value: drift)

            // kódolt aurora — mozgás a kép fölött
            GeometryReader { geo in
                let s = max(geo.size.width, geo.size.height)
                RadialGradient(colors: [Theme.vio.opacity(0.22), .clear], center: .center, startRadius: 0, endRadius: s * 0.52)
                    .frame(width: s, height: s)
                    .offset(x: -s * 0.30, y: -s * 0.34)
                    .blur(radius: 46)
                RadialGradient(colors: [Theme.pink.opacity(0.14), .clear], center: .center, startRadius: 0, endRadius: s * 0.46)
                    .frame(width: s, height: s)
                    .offset(x: geo.size.width * 0.44, y: geo.size.height * 0.50)
                    .blur(radius: 52)
            }
            .rotationEffect(.degrees(spin && !reduceMotion ? 8 : -8))
            .animation(reduceMotion ? nil : .easeInOut(duration: 14).repeatForever(autoreverses: true), value: spin)

            // lebegő fény-pontok
            SparkleField()

            // olvashatóság: sötétítés a lap alján
            LinearGradient(colors: [.clear, Theme.bg.opacity(0.55)], startPoint: .center, endPoint: .bottom)
        }
        .ignoresSafeArea()
        .onAppear { spin = true; drift = true }
    }
}

/// Lebegő, pislogó fény-pontok — Canvas, nagyon olcsó.
struct SparkleField: View {
    @AppStorage("ui.reduceMotion") private var reduceMotion = false
    var body: some View {
        if reduceMotion {
            Color.clear
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
                Canvas { ctx, size in
                    let t = tl.date.timeIntervalSinceReferenceDate
                    for i in 0..<24 {
                        let seed = Double(i) * 7.31
                        let x = (sin(seed * 1.7 + t * 0.05) * 0.5 + 0.5) * size.width
                        let y = ((cos(seed * 2.3 + t * 0.035) * 0.5 + 0.5) * size.height + t * 5)
                            .truncatingRemainder(dividingBy: size.height)
                        let tw = 0.5 + 0.5 * sin(t * 1.3 + seed)
                        let r = 1.0 + 1.5 * (0.5 + 0.5 * sin(seed * 3.1))
                        ctx.opacity = 0.08 + 0.20 * tw
                        ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r * 2, height: r * 2)), with: .color(.white))
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }
}

/// Élő gyűrű — az agent „arca". Dolgozik: forgó gradiens, pulzáló mag, aura.
struct LiveRing: View {
    let working: Bool
    var size: CGFloat = 30
    @AppStorage("ui.reduceMotion") private var reduceMotion = false
    @State private var pulse = false
    @State private var spin = false

    var body: some View {
        ZStack {
            // aura
            Circle()
                .fill(RadialGradient(
                    colors: [(working ? Theme.pink : Theme.vio).opacity(working ? 0.34 : 0.16), .clear],
                    center: .center, startRadius: 0, endRadius: size * 0.85))
                .frame(width: size * 1.75, height: size * 1.75)
                .opacity(pulse && !reduceMotion ? 1 : 0.66)
            // gyűrű
            Circle()
                .strokeBorder(
                    AngularGradient(colors: working
                        ? [Theme.vio, Theme.pink, Theme.vio.opacity(0.75), Theme.pink, Theme.vio]
                        : [Theme.vio.opacity(0.7), Theme.pink.opacity(0.35), Theme.vio.opacity(0.7)],
                        center: .center),
                    lineWidth: max(2, size * 0.085)
                )
                .frame(width: size, height: size)
                .shadow(color: (working ? Theme.pink : Theme.vio).opacity(working ? 0.55 : 0.28), radius: working ? 8 : 5)
                .rotationEffect(.degrees(spin && !reduceMotion ? 360 : 0))
                .animation(reduceMotion ? nil : .linear(duration: working ? 5 : 16).repeatForever(autoreverses: false), value: spin)
            // mag
            if working {
                Circle()
                    .fill(Theme.pink.opacity(0.92))
                    .frame(width: size * 0.32, height: size * 0.32)
                    .scaleEffect(pulse && !reduceMotion ? 1.16 : 0.92)
                    .shadow(color: Theme.pink.opacity(0.85), radius: 6)
            } else {
                ZStack {
                    Circle()
                        .fill(Theme.vio.opacity(0.16))
                        .frame(width: size * 0.62, height: size * 0.62)
                    Image(systemName: "sparkles")
                        .font(.system(size: size * 0.30, weight: .bold))
                        .foregroundStyle(Theme.txt)
                        .shadow(color: Theme.vio.opacity(0.65), radius: 4)
                }
            }
        }
        .frame(width: size, height: size)
        .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: pulse)
        .onAppear { pulse = true; spin = true }
    }
}

/// Főgomb — gradiens, fény-sugárnyomással, finom nyomás-visszajelzéssel.
struct GlowButton: View {
    let title: String
    let icon: String
    var action: () -> Void
    @State private var pressed = false

    var body: some View {
        Button {
            Haptics.tap()
            withAnimation(Theme.spring) { pressed = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(Theme.spring) { pressed = false }
            }
            action()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(title).font(Theme.ui(15)).fontWeight(.semibold)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18).padding(.vertical, 12)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: Theme.vio.opacity(pressed ? 0.15 : 0.45), radius: pressed ? 4 : 12, y: 4)
            .scaleEffect(pressed ? 0.96 : 1)
        }
    }
}

/// Állapot-pill — a fejlécben, csendes élő fénnyel.
struct StatusPill: View {
    let status: AgentStatus
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(status.isWorking ? Theme.pink : Theme.txt3)
                .frame(width: 8, height: 8)
                .shadow(color: status.isWorking ? Theme.pink.opacity(0.8) : .clear, radius: 5)
            Text(AgentState(rawValue: status.state)?.label ?? "Idle")
                .font(Theme.ui(12)).fontWeight(.semibold)
                .foregroundStyle(Theme.txt2)
            if status.isWorking && status.at > 0 {
                Text(status.since, style: .timer)
                    .font(Theme.mono)
                    .foregroundStyle(Theme.txt3)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Theme.surf2, in: Capsule())
        .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
        .animation(Theme.softSpring, value: status.state)
    }
}

/// Villogó kurzor a streamelt válasz végén.
struct BlinkingCaret: View {
    @State private var on = true
    var body: some View {
        Rectangle()
            .fill(Theme.pink)
            .frame(width: 2, height: 15)
            .opacity(on ? 1 : 0)
            .animation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true), value: on)
            .onAppear { on = false }
    }
}

/// Induló képernyő — a márka belépője, utána elolvad.
struct IntroOverlay: View {
    @State private var on = false
    var body: some View {
        ZStack {
            Theme.bg
            AuroraBackground()
            VStack(spacing: 20) {
                LiveRing(working: true, size: 78)
                    .scaleEffect(on ? 1 : 0.72)
                Text("Cortex Phantom Agent")
                    .font(Theme.display(25)).fontWeight(.bold)
                    .foregroundStyle(Theme.accent)
                    .opacity(on ? 1 : 0)
                    .offset(y: on ? 0 : 12)
                Text("PHANTOM CORE 2")
                    .font(Theme.ui(11)).fontWeight(.semibold)
                    .kerning(3)
                    .foregroundStyle(Theme.txt3)
                    .opacity(on ? 1 : 0)
            }
        }
        .opacity(on ? 1 : 1)
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.8)) { on = true }
        }
    }
}

// ── felület-építők: kártya, szekció-címke, beviteli doboz ──

struct CardSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.surf2.opacity(0.92), Theme.surf.opacity(0.92)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Theme.line, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
    }
}

extension View {
    func cardSurface() -> some View { modifier(CardSurface()) }

    /// Kártyák belépő-animációja egymás után.
    func cardEntrance(_ index: Int, appeared: Bool) -> some View {
        opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 14)
            .animation(.spring(response: 0.5, dampingFraction: 0.82).delay(Double(index) * 0.05), value: appeared)
    }
}

struct SectionLabel: View {
    let icon: String
    let title: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .shadow(color: Theme.vio.opacity(0.45), radius: 6, y: 2)
            Text(title)
                .font(Theme.ui(12)).fontWeight(.semibold)
                .kerning(0.8)
                .textCase(.uppercase)
                .foregroundStyle(Theme.txt2)
        }
    }
}

struct FieldBox<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .font(Theme.ui(15))
            .foregroundStyle(Theme.txt)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(.horizontal, 12).padding(.vertical, 11)
            .background(Theme.bg.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.line, lineWidth: 1))
    }
}
