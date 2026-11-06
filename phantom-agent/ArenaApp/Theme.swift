// Theme — a Cortex Phantom Agent dizájnvonal: sötét/violet, élő fényekkel.
// Szabály: UI-szöveg angolul, emoji sehol — csak SF Symbols és vektor.
import SwiftUI

enum Theme {
    // Háttér-szintek
    static let bg = Color(red: 0.043, green: 0.043, blue: 0.071)        // #0B0B12
    static let surf = Color(red: 0.086, green: 0.082, blue: 0.137)      // #161523
    static let surf2 = Color(red: 0.125, green: 0.118, blue: 0.192)     // #201E31
    static let line = Color.white.opacity(0.08)

    // Violet gradiens
    static let vio = Color(red: 0.486, green: 0.361, blue: 0.965)       // #7C5CF6
    static let pink = Color(red: 0.910, green: 0.475, blue: 0.976)      // #E879F9
    static var accent: LinearGradient {
        LinearGradient(colors: [vio, pink], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static let txt = Color.white
    static let txt2 = Color.white.opacity(0.62)
    static let txt3 = Color.white.opacity(0.38)

    static let mono = Font.system(.caption, design: .monospaced).weight(.medium)

    // Animációs ívek
    static let spring = Animation.spring(response: 0.42, dampingFraction: 0.82)
    static let softSpring = Animation.spring(response: 0.6, dampingFraction: 0.9)
}

/// Aurora-háttér — két lebegő, elmosott gradiens-folt, lassan forog.
struct AuroraBackground: View {
    @State private var spin = false
    var body: some View {
        ZStack {
            Theme.bg
            GeometryReader { geo in
                let s = max(geo.size.width, geo.size.height) * 0.9
                RadialGradient(colors: [Theme.vio.opacity(0.22), .clear], center: .center, startRadius: 0, endRadius: s * 0.55)
                    .frame(width: s, height: s)
                    .offset(x: -s * 0.28, y: -s * 0.30)
                    .blur(radius: 40)
                RadialGradient(colors: [Theme.pink.opacity(0.14), .clear], center: .center, startRadius: 0, endRadius: s * 0.5)
                    .frame(width: s, height: s)
                    .offset(x: geo.size.width * 0.45, y: geo.size.height * 0.55)
                    .blur(radius: 46)
            }
            .rotationEffect(.degrees(spin ? 8 : -8))
            .animation(.easeInOut(duration: 14).repeatForever(autoreverses: true), value: spin)
        }
        .ignoresSafeArea()
        .onAppear { spin = true }
    }
}

/// Élő gyűrű — dolgozik: pulzáló gradiens; egyébként finom, statikus fény.
struct LiveRing: View {
    let working: Bool
    var size: CGFloat = 30
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(
                    AngularGradient(colors: working
                        ? [Theme.vio, Theme.pink, Theme.vio]
                        : [Theme.txt3.opacity(0.5)], center: .center),
                    lineWidth: max(2, size * 0.09)
                )
                .shadow(color: working ? Theme.pink.opacity(0.55) : .clear, radius: pulse ? 10 : 4)
                .scaleEffect(pulse && working ? 1.05 : 1.0)
            if working {
                Circle().fill(Theme.pink.opacity(0.9)).scaleEffect(0.38)
                    .scaleEffect(pulse ? 1.18 : 0.92)
            } else {
                Image(systemName: "sparkles")
                    .font(.system(size: size * 0.32, weight: .bold))
                    .foregroundStyle(Theme.txt2)
            }
        }
        .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: pulse)
        .onAppear { pulse = true }
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
            withAnimation(Theme.spring) { pressed = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(Theme.spring) { pressed = false }
            }
            action()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(title).fontWeight(.semibold)
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
                .font(.caption.weight(.semibold))
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
