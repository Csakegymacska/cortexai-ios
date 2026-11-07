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
                            if streamText.isEmpty {
                                // gondolkodás / bash — élő jelzés
                                HStack(spacing: 10) {
                                    TypingDots(color: session.toolRunning ? Theme.ok : Theme.pink)
                                    Text(session.toolRunning ? "Bashing on the runner" : "Thinking")
                                        .font(Theme.ui(13))
                                        .foregroundStyle(Theme.txt3)
                                }
                                .padding(.horizontal, 16).padding(.vertical, 14)
                                .background(Theme.surf, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .sweepBorder(true)
                                .transition(.opacity)
                            } else {
                                VStack(alignment: .leading, spacing: 6) {
                                    RichMessageView(content: streamText, streaming: true)
                                    HStack(spacing: 0) {
                                        BlinkingCaret()
                                        Spacer(minLength: 0)
                                    }
                                }
                                .padding(12)
                                .background(Theme.surf, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line, lineWidth: 1))
                                .sweepBorder(true)
                            }
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

    // ── üres állapot — CoreMark a hős, agent-ízű javaslatokkal ──
    private var emptyState: some View {
        VStack(spacing: 16) {
            CoreMark(size: 96, working: true)
                .padding(.top, 16)
            Text("Cortex Phantom Agent")
                .font(Theme.display(23)).fontWeight(.bold)
                .foregroundStyle(Theme.accent)
            Text("Our own AI — the Phantom Core 2 pipeline.\nGive it a task or ask anything.")
                .font(Theme.ui(14))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.txt2)
            HStack(spacing: 8) {
                ForEach(["Plan a project", "Write code", "Run research"], id: \.self) { s in
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
                    .buttonStyle(PressableStyle())
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
            .buttonStyle(PressableStyle())
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

/// Üzenet-buborék — a user gradiens, az asszisztens sötét felület, gazdag tartalommal.
struct BubbleView: View {
    let message: ArenaMessage
    var isUser: Bool { message.role == "user" }

    var body: some View {
        if message.role == "tool" {
            // megfigyelés-kártya — a runner valódi kimenete
            HStack(spacing: 8) {
                Image(systemName: "terminal")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.ok)
                Text(message.content)
                    .font(Theme.mono)
                    .foregroundStyle(Theme.txt3)
                    .lineLimit(4)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(Theme.bg.opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.ok.opacity(0.25), lineWidth: 1))
        } else {
            HStack {
                if isUser { Spacer(minLength: 64) }
                Group {
                    if isUser {
                        Text(message.content)
                            .font(Theme.ui(15))
                            .foregroundStyle(.white)
                    } else {
                        RichMessageView(content: message.content)
                    }
                }
                .textSelection(.enabled)
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background {
                    if isUser {
                        RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.accent)
                    } else {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Theme.surf)
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line, lineWidth: 1))
                    }
                }
                .shadow(color: isUser ? Theme.vio.opacity(0.24) : .clear, radius: 8, y: 3)
                if !isUser { Spacer(minLength: 28) }
            }
        }
    }
}
