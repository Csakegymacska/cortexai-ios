// Theme — a Cortex Phantom Agent dizájnvonal: „mérnöki konzol".
// Sötét, szűk felületcsalád, kemény geometria (kis sarkok), hajszálvonalak,
// minimális árnyék, mono feliratok — nem dekoráció, hanem műszerfal.
// Szabály: UI-szöveg angolul, emoji sehol — csak SF Symbols és vektor.
// Saját betűtípusok: Sora (display) + Inter (UI) — Resources/Fonts.
import SwiftUI
import UIKit

enum Theme {
    // Felület-család — közel egymáshoz, hogy „egy környezet" legyen
    static let bg = Color(red: 0.039, green: 0.039, blue: 0.063)        // #0A0A10
    static let surf = Color(red: 0.071, green: 0.071, blue: 0.110)      // #12121C
    static let surf2 = Color(red: 0.098, green: 0.094, blue: 0.145)     // #191825
    static let line = Color.white.opacity(0.07)
    static let line2 = Color.white.opacity(0.12)

    // Kiemelő szín — TAKARÉKOSAN: csak futó állapot, elsődleges gomb
    static let vio = Color(red: 0.486, green: 0.361, blue: 0.965)       // #7C5CF6
    static let pink = Color(red: 0.910, green: 0.475, blue: 0.976)      // #E879F9
    static var accent: LinearGradient {
        LinearGradient(colors: [vio, pink], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // Állapot-színek — a lépés-napló jelzőihez
    static let ok = Color(red: 0.204, green: 0.827, blue: 0.600)       // #34D399
    static let warn = Color(red: 0.961, green: 0.651, blue: 0.137)     // #F5A623
    static let err = Color(red: 0.973, green: 0.443, blue: 0.443)      // #F87171

    static let txt = Color.white
    static let txt2 = Color.white.opacity(0.62)
    static let txt3 = Color.white.opacity(0.38)

    // Saját betűtípusok — Sora a megjelenő szöveg, Inter a felület
    static func display(_ size: CGFloat) -> Font { .custom("Sora", size: size) }
    static func ui(_ size: CGFloat) -> Font { .custom("Inter", size: size) }

    static let mono = Font.system(.caption, design: .monospaced).weight(.medium)

    // Sarkok — kemény geometria
    static let rSm: CGFloat = 8
    static let rMd: CGFloat = 12
    static let rLg: CGFloat = 16

    // Animációs ívek
    static let spring = Animation.spring(response: 0.42, dampingFraction: 0.82)
    static let softSpring = Animation.spring(response: 0.6, dampingFraction: 0.9)
}

/// Haptikus visszajelzés.
enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func select() { UISelectionFeedbackGenerator().selectionChanged() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
}

/// Háttér — sötét alap, finom rács, egyetlen fényfolt. Nincs fotó, nincs AI-art.
struct PhantomBackdrop: View {
    @AppStorage("ui.reduceMotion") private var reduceMotion = false
    @State private var drift = false

    var body: some View {
        ZStack {
            Theme.bg

            // rács — műszerfal-érzet
            Canvas { ctx, size in
                let step: CGFloat = 30
                var path = Path()
                var x: CGFloat = 0
                while x < size.width { path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height)); x += step }
                var y: CGFloat = 0
                while y < size.height { path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y)); y += step }
                ctx.stroke(path, with: .color(.white.opacity(0.028)), lineWidth: 0.5)
            }

            // egyetlen, lassan lebegő fényfolt — visszafogott
            GeometryReader { geo in
                RadialGradient(colors: [Theme.vio.opacity(0.16), .clear], center: .center, startRadius: 0,
                               endRadius: max(geo.size.width, geo.size.height) * 0.6)
                    .offset(x: -geo.size.width * 0.22, y: -geo.size.height * 0.26)
                    .blur(radius: 30)
                    .offset(y: drift && !reduceMotion ? -16 : 8)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 12).repeatForever(autoreverses: true), value: drift)
            }

            // olvashatóság
            LinearGradient(colors: [.clear, Theme.bg.opacity(0.45)], startPoint: .center, endPoint: .bottom)
        }
        .ignoresSafeArea()
        .onAppear { drift = true }
    }
}

/// CoreMark — a márkajel VETOROSAN, kézművesen: gyűrű + beosztások + hexmag.
struct CoreMark: View {
    var size: CGFloat = 64
    var working: Bool = true
    @AppStorage("ui.reduceMotion") private var reduceMotion = false
    @State private var spin = false
    @State private var pulse = false

    var body: some View {
        ZStack {
            // külső gyűrű
            Circle()
                .strokeBorder(Theme.line2, lineWidth: 1)
                .frame(width: size, height: size)
            // beosztások — 12 darab, műszer
            ForEach(0..<12, id: \.self) { i in
                Capsule()
                    .fill(i % 3 == 0 ? Theme.vio.opacity(0.75) : Theme.line2)
                    .frame(width: 1.5, height: size * (i % 3 == 0 ? 0.10 : 0.055))
                    .offset(y: -size * 0.5 + size * 0.045)
                    .rotationEffect(.degrees(Double(i) / 12 * 360))
            }
            // forgó kiemelő ív
            Circle()
                .trim(from: 0, to: 0.22)
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: size * 0.82, height: size * 0.82)
                .rotationEffect(.degrees(spin && !reduceMotion ? 360 : 0))
                .animation(reduceMotion ? nil : .linear(duration: 7).repeatForever(autoreverses: false), value: spin)
            // hexmag
            HexShape()
                .fill(Theme.accent)
                .frame(width: size * 0.34, height: size * 0.34)
                .shadow(color: Theme.vio.opacity(0.55), radius: pulse ? 12 : 6)
                .scaleEffect(pulse && !reduceMotion ? 1.06 : 1.0)
            HexShape()
                .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                .frame(width: size * 0.46, height: size * 0.46)
        }
        .frame(width: size, height: size)
        .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: pulse)
        .onAppear { spin = true; pulse = true }
    }
}

struct HexShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        for i in 0..<6 {
            let a = Double(i) * .pi / 3 - .pi / 2
            let pt = CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

/// Élő gyűrű — az agent „arca" a fejlécben (finom, műszer-jellegű).
struct LiveRing: View {
    let working: Bool
    var size: CGFloat = 30
    @AppStorage("ui.reduceMotion") private var reduceMotion = false
    @State private var pulse = false
    @State private var spin = false

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [(working ? Theme.pink : Theme.vio).opacity(working ? 0.28 : 0.12), .clear],
                    center: .center, startRadius: 0, endRadius: size * 0.85))
                .frame(width: size * 1.6, height: size * 1.6)
                .opacity(pulse && !reduceMotion ? 1 : 0.6)
            Circle()
                .strokeBorder(Theme.line2, lineWidth: 1)
                .frame(width: size, height: size)
            Circle()
                .trim(from: 0, to: 0.25)
                .stroke(working ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.vio.opacity(0.55)),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: size * 0.86, height: size * 0.86)
                .rotationEffect(.degrees(spin && !reduceMotion ? 360 : 0))
                .animation(reduceMotion ? nil : .linear(duration: working ? 4 : 12).repeatForever(autoreverses: false), value: spin)
            if working {
                Circle()
                    .fill(Theme.pink.opacity(0.92))
                    .frame(width: size * 0.26, height: size * 0.26)
                    .scaleEffect(pulse && !reduceMotion ? 1.2 : 0.9)
                    .shadow(color: Theme.pink.opacity(0.8), radius: 5)
            } else {
                HexShape()
                    .fill(Theme.accent)
                    .frame(width: size * 0.30, height: size * 0.30)
            }
        }
        .frame(width: size, height: size)
        .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: pulse)
        .onAppear { pulse = true; spin = true }
    }
}

/// Főgomb — gradiens, takarékos fény.
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
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.rSm, style: .continuous))
            .shadow(color: Theme.vio.opacity(pressed ? 0.15 : 0.4), radius: pressed ? 4 : 10, y: 4)
            .scaleEffect(pressed ? 0.96 : 1)
        }
    }
}

/// Állapot-pill — kompakt, téglalap, nem kapszula.
struct StatusPill: View {
    let status: AgentStatus
    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(status.isWorking ? Theme.pink : Theme.txt3)
                .frame(width: 7, height: 7)
                .shadow(color: status.isWorking ? Theme.pink.opacity(0.8) : .clear, radius: 4)
            Text(AgentState(rawValue: status.state)?.label ?? "Idle")
                .font(Theme.ui(11)).fontWeight(.semibold)
                .foregroundStyle(Theme.txt2)
            if status.isWorking && status.at > 0 {
                Text(status.since, style: .timer)
                    .font(Theme.mono)
                    .foregroundStyle(Theme.txt3)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Theme.surf2, in: RoundedRectangle(cornerRadius: Theme.rSm, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.rSm, style: .continuous).stroke(Theme.line, lineWidth: 1))
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

/// Induló képernyő — CoreMark + wordmark, aztán elolvad.
struct IntroOverlay: View {
    @State private var on = false
    var body: some View {
        ZStack {
            Theme.bg
            PhantomBackdrop()
            VStack(spacing: 20) {
                CoreMark(size: 84, working: true)
                    .scaleEffect(on ? 1 : 0.72)
                Text("Cortex Phantom Agent")
                    .font(Theme.display(25)).fontWeight(.bold)
                    .foregroundStyle(Theme.accent)
                    .opacity(on ? 1 : 0)
                    .offset(y: on ? 0 : 12)
                Text("AGENT CONSOLE")
                    .font(Theme.ui(11)).fontWeight(.semibold)
                    .kerning(3)
                    .foregroundStyle(Theme.txt3)
                    .opacity(on ? 1 : 0)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.8)) { on = true }
        }
    }
}

// ── felület-építők ──

struct CardSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surf, in: RoundedRectangle(cornerRadius: Theme.rMd, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.rMd, style: .continuous)
                    .stroke(Theme.line, lineWidth: 1)
            )
    }
}

extension View {
    func cardSurface() -> some View { modifier(CardSurface()) }

    func cardEntrance(_ index: Int, appeared: Bool) -> some View {
        opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 12)
            .animation(.spring(response: 0.5, dampingFraction: 0.82).delay(Double(index) * 0.05), value: appeared)
    }
}

struct SectionLabel: View {
    let icon: String
    let title: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.pink)
            Text(title)
                .font(Theme.ui(11)).fontWeight(.semibold)
                .kerning(1)
                .textCase(.uppercase)
                .foregroundStyle(Theme.txt3)
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
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(Theme.bg.opacity(0.6), in: RoundedRectangle(cornerRadius: Theme.rSm, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.rSm, style: .continuous).stroke(Theme.line, lineWidth: 1))
    }
}
