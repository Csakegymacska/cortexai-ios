// NativeChatView — teljesen natív chat a hivatalos Arena API-n (api.arena.ai).
// Animált buborékok, élő stream-caret, gradiens háttér — WebView nélkül.
import SwiftUI

struct NativeChatView: View {
    @StateObject private var session = ChatSession()
    @State private var input = ""
    @State private var streamText = ""
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            AuroraBackground()

            VStack(spacing: 0) {
                messages
                providerBar
                inputBar
            }
        }
    }

    // ── provider-váltó: Cortex Phantom (a mi AI-nk) / Arena API ──
    private var providerBar: some View {
        HStack(spacing: 6) {
            ForEach(ProviderKind.allCases) { p in
                let on = session.provider == p
                Button {
                    withAnimation(Theme.spring) { session.select(p) }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: p == .phantom ? "sparkles" : "cpu")
                            .font(.caption2)
                        Text(p.label)
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(on ? .white : Theme.txt2)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background {
                        if on {
                            Capsule().fill(Theme.accent)
                                .shadow(color: Theme.vio.opacity(0.45), radius: 8, y: 2)
                        } else {
                            Capsule().fill(Theme.surf2)
                                .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
                        }
                    }
                    .scaleEffect(on ? 1 : 0.94)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 14)
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
                                    .font(.body)
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

    // ── üres állapot ──
    private var emptyState: some View {
        VStack(spacing: 18) {
            LiveRing(working: false, size: 64)
                .padding(.top, 60)
            Text("Cortex Phantom Agent")
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.txt)
            Text(session.provider == .phantom
                 ? "Our own AI — the Phantom Core 2 pipeline.\nAsk anything to begin."
                 : "Frontier models through the Arena API.\nAsk anything to begin.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.txt2)
                .animation(Theme.softSpring, value: session.provider)
            HStack(spacing: 8) {
                ForEach(["Explain a concept", "Write code", "Plan a project"], id: \.self) { s in
                    Button {
                        input = s
                        send()
                    } label: {
                        Text(s)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.txt2)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Theme.surf2, in: Capsule())
                            .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
                    }
                }
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
    }

    // ── beviteli sáv ──
    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Message", text: $input, axis: .vertical)
                .lineLimit(1...5)
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(Theme.surf, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(focused ? Theme.vio.opacity(0.6) : Theme.line, lineWidth: 1))
                .focused($focused)
                .animation(Theme.softSpring, value: focused)

            Button {
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
        withAnimation(Theme.spring) {
            // az üzenet a session-ba kerül
        }
        Task {
            await session.send(text) { delta in
                streamText += delta
            }
            streamText = ""
        }
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
                .font(.body)
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
