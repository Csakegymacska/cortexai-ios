// NativeChatView — teljesen natív chat a SAJÁT AI-nkkal (Cortex Phantom / Phantom Core 2).
// Animált buborékok, élő stream-caret, nebula-háttér — minden a miénk.
import SwiftUI

struct NativeChatView: View {
    @StateObject private var session = ChatSession()
    @State private var input = ""
    @State private var streamText = ""
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                messages
                brainChip
                inputBar
            }
        }
    }

    // ── agy-címke: mivel beszélsz — saját jelkép, nem választó ──
    private var brainChip: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.pink)
            Text("Phantom Core 2")
                .font(Theme.ui(11)).fontWeight(.semibold)
                .foregroundStyle(Theme.txt2)
            Circle().fill(Theme.vio.opacity(0.5)).frame(width: 3, height: 3)
            Text("our own brain")
                .font(Theme.ui(10))
                .foregroundStyle(Theme.txt3)
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 8)
    }

    // ── üzenetfolyam ──
    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    if session.messages.isEmpty {
                        emptyState
                    }
                    ForEach(Array(session.messages.enumerated()), id: \.offset) { _, m in
                        BubbleView(message: m)
                            .transition(.asymmetric(
                                insertion: .move(edge: m.role == "user" ? .trailing : .leading).combined(with: .opacity),
                                removal: .opacity))
                    }
                    if session.streaming {
                        HStack(alignment: .bottom, spacing: 10) {
                            LiveRing(working: true, size: 26)
                            HStack(alignment: .bottom, spacing: 3) {
                                Text(streamText)
                                    .font(Theme.ui(15))
                                    .foregroundStyle(Theme.txt)
                                BlinkingCaret()
                            }
                            .padding(12)
                            .background(Theme.surf, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.line, lineWidth: 1))
                            Spacer(minLength: 40)
                        }
                        .id("streaming")
                        .transition(.opacity)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: streamText) { _, _ in
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: session.messages.count) { _, _ in
                withAnimation(Theme.softSpring) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }

    // ── üres állapot — a Phantom Orb a hős ──
    private var emptyState: some View {
        VStack(spacing: 16) {
            PhantomOrbView()
                .padding(.top, 12)
            Text("Cortex Phantom Agent")
                .font(Theme.display(23)).fontWeight(.bold)
                .foregroundStyle(Theme.accent)
            Text("Our own AI — the Phantom Core 2 pipeline.\nAsk anything to begin.")
                .font(Theme.ui(14))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.txt2)
            HStack(spacing: 8) {
                ForEach(["Explain a concept", "Write code", "Plan a project"], id: \.self) { s in
                    Button {
                        Haptics.tap()
                        input = s
                        send()
                    } label: {
                        Text(s)
                            .font(Theme.ui(12)).fontWeight(.medium)
                            .foregroundStyle(Theme.txt2)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Theme.surf2, in: Capsule())
                            .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
                    }
                }
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
    }

    // ── beviteli sáv ──
    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Message", text: $input, axis: .vertical)
                .font(Theme.ui(15))
                .lineLimit(1...5)
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(Theme.surf, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(focused ? Theme.vio.opacity(0.6) : Theme.line, lineWidth: 1))
                .focused($focused)
                .animation(Theme.softSpring, value: focused)

            Button {
                Haptics.tap()
                send()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(canSend ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.surf2), in: Circle())
                    .shadow(color: canSend ? Theme.vio.opacity(0.5) : .clear, radius: 8, y: 3)
                    .scaleEffect(canSend ? 1 : 0.92)
            }
            .disabled(!canSend)
            .animation(Theme.spring, value: canSend)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.bg.opacity(0.86))
        .overlay(Rectangle().fill(Theme.line).frame(height: 1), alignment: .top)
    }

    private var canSend: Bool {
        !input.trimmingCharacters(in: .whitespaces).isEmpty && !session.streaming && session.canSend
    }

    private func send() {
        guard canSend else { return }
        let text = input
        input = ""
        streamText = ""
        focused = false
        Task {
            await session.send(text) { delta in
                streamText += delta
            }
            streamText = ""
        }
    }
}

/// A Phantom Orb — beépített grafika, lebegő-animációval, sötét háttéren úszó fénnyel.
struct PhantomOrbView: View {
    var size: CGFloat = 160
    @AppStorage("ui.reduceMotion") private var reduceMotion = false
    @State private var float = false

    var body: some View {
        Image("PhantomOrb")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .blendMode(.screen)
            .scaleEffect(float && !reduceMotion ? 1.04 : 1.0)
            .offset(y: float && !reduceMotion ? -8 : 4)
            .animation(reduceMotion ? nil : .easeInOut(duration: 3.2).repeatForever(autoreverses: true), value: float)
            .onAppear { float = true }
            .accessibilityHidden(true)
    }
}

/// Üzenet-buborék — a user gradiens, az asszisztens sötét felület.
struct BubbleView: View {
    let message: ArenaMessage
    var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 48) }
            Text(message.content)
                .font(Theme.ui(15))
                .foregroundStyle(isUser ? .white : Theme.txt)
                .textSelection(.enabled)
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background {
                    if isUser {
                        RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.accent)
                    } else {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Theme.surf)
                            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.line, lineWidth: 1))
                    }
                }
                .shadow(color: isUser ? Theme.vio.opacity(0.28) : .clear, radius: 10, y: 4)
            if !isUser { Spacer(minLength: 48) }
        }
    }
}
