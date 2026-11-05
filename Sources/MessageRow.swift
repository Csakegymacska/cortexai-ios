import SwiftUI
import UIKit

/// One bubble. User messages are a compact violet capsule on the right; Cortex answers run
/// full width with the sigil, markdown text and a copy action.
struct MessageRow: View {
    @Environment(AppState.self) private var state
    let message: ChatMessage
    var showTimestamp: Bool = false
    /// Position in the transcript, used for the staggered entrance.
    var index: Int = 0

    var body: some View {
        Group {
            if message.role == .user {
                userBubble
            } else {
                assistantBlock
            }
        }
        .cortexEntrance(index: index)
    }

    private var userBubble: some View {
        HStack {
            Spacer(minLength: 40)
            VStack(alignment: .trailing, spacing: 5) {
                if !state.images(for: message.id).isEmpty {
                    HStack(spacing: 6) {
                        ForEach(state.images(for: message.id)) { image in
                            CachedImage(base64: image.data, key: image.id.uuidString)
                        }
                    }
                }
                if !state.files(for: message.id).isEmpty {
                    VStack(alignment: .trailing, spacing: 4) {
                        ForEach(state.files(for: message.id)) { file in
                            HStack(spacing: 6) {
                                Image(systemName: "doc.text.fill").font(.system(size: 10, weight: .semibold))
                                Text(file.name)
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.14), in: Capsule())
                        }
                    }
                }
                if !message.text.isEmpty {
                    Text(message.text)
                        .font(Theme.body(15.5))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if showTimestamp {
                    Text(message.createdAt, format: .dateTime.hour().minute())
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 11)
            .background(Theme.bubbleUser, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                // A vékony fehér keret helyett felülről lefelé halványuló fény:
                // ez adja a „üveg" érzést anélkül, hogy a buborék világosabb lenne.
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [Color.white.opacity(0.26),
                                                Color.white.opacity(0.06),
                                                Color.white.opacity(0.12)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1
                    )
            )
            // A buborék alatt vékony ibolya derengés — a háttérből emeli ki, nem kell hozzá
            // erős árnyék, ami sötét háttéren koszosnak látszana.
            .shadow(color: Theme.violet.opacity(0.30), radius: 14, x: 0, y: 6)
        }
    }

    private var assistantBlock: some View {
        // 7.0: a válasz egy lebegő üveg kártyán ül, mellette a jelvény — a régi,
        // teljes szélességű „dokumentum" elrendezés helyett valódi beszélgetés-ritmus.
        HStack(alignment: .top, spacing: 12) {
            CortexMark(size: 18)
                .cortexBreathing(message.isStreaming)
                .frame(width: 38, height: 38)
                .background(Circle().fill(Theme.violet.opacity(0.15)))
                .overlay(Circle().strokeBorder(Theme.violet.opacity(0.32), lineWidth: 1))
                .shadow(color: Theme.violet.opacity(message.isStreaming ? 0.45 : 0.18), radius: 8, y: 3)
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text("Cortex Void")
                    .font(.system(size: 12, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(Theme.textMuted)
                if message.isStreaming {
                    PhaseDots()
                }
                Spacer(minLength: 0)
            }

            if let rows = message.twoUp, !rows.isEmpty {
                TwoUpGrid(rows: rows)
            } else if message.isEmpty && message.isStreaming {
                SkeletonLines()
                    .padding(.vertical, 2)
            } else {
                MarkdownText(text: message.text)
                if message.isStreaming {
                    StreamCursor()
                        .padding(.top, 2)
                        .transition(.opacity)
                }
            }

            if let steps = message.steps, !steps.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(steps) { step in
                        HStack(spacing: 6) {
                            Image(systemName: step.ok ? "checkmark" : "minus")
                                .font(.system(size: 8, weight: .heavy))
                                .foregroundStyle(step.ok ? Theme.success : Theme.textFaint)
                                .frame(width: 10)
                            Text(step.label)
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(Theme.textMuted)
                            if !step.detail.isEmpty {
                                Text(step.detail)
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(Theme.textFaint)
                                    .lineLimit(1)
                            }
                            if step.ms > 300 {
                                Text("\(step.ms) ms")
                                    .font(.system(size: 9.5).monospacedDigit())
                                    .foregroundStyle(Theme.textFaint.opacity(0.8))
                            }
                        }
                    }
                }
                .padding(.leading, 2)
                .transition(.opacity)
            }

            if !message.isStreaming && (!message.isEmpty || !(message.twoUp ?? []).isEmpty) {
                MessageActionsBar(message: message)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                ReplyFooter(message: message)
                if let suggestions = message.suggestions, !suggestions.isEmpty {
                    SuggestionChips(suggestions: suggestions)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Theme.surface.opacity(0.55))
            }
            .cortexGlass(RoundedRectangle(cornerRadius: 24, style: .continuous), tint: Theme.violet.opacity(0.05))
            .gradientEdge(radius: 24, strength: 0.13)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(CortexMotion.fade, value: message.isStreaming)
    }

}

/// Markdown that survives streaming: code fences become copyable panels, the rest renders as
/// styled text. Kept deliberately simple so partial fences never throw.
struct MarkdownText: View {
    let text: String

    private struct Block: Identifiable {
        let id = UUID()
        let isCode: Bool
        let language: String
        let content: String
    }

    private var blocks: [Block] {
        var result: [Block] = []
        var buffer = ""
        var inCode = false
        var language = ""

        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine
            if line.hasPrefix("```") {
                if inCode {
                    result.append(Block(isCode: true, language: language, content: buffer.trimmingCharacters(in: .newlines)))
                    buffer = ""
                    inCode = false
                    language = ""
                } else {
                    if !buffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        result.append(Block(isCode: false, language: "", content: buffer))
                    }
                    buffer = ""
                    inCode = true
                    language = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                }
                continue
            }
            buffer += (buffer.isEmpty ? "" : "\n") + line
        }
        if !buffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.append(Block(isCode: inCode, language: language, content: buffer))
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(blocks) { block in
                if block.isCode {
                    CodePanel(language: block.language, code: block.content)
                } else {
                    Text(attributed(block.content))
                        .font(Theme.body(15.5))
                        .foregroundStyle(Theme.text)
                        .lineSpacing(3.5)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
    }

    /// Inline markdown (**bold**, `code`, links, lists). Falls back to plain text.
    private func attributed(_ raw: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: raw, options: options)) ?? AttributedString(raw)
    }
}

/// Két hangnem egymás mellett: tömör és részletes. Kártyánként olvasható, másolható.
struct TwoUpGrid: View {
    let rows: [TwoUpAnswer]

    var body: some View {
        VStack(spacing: 10) {
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 6) {
                    Text(row.label.uppercased())
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(0.8)
                        .foregroundStyle(Theme.textFaint)
                    MarkdownText(text: row.text)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                        .strokeBorder(Theme.hairline, lineWidth: 1)
                )
            }
        }
    }
}

/// A válasz alatti koppintható kérdések. Egy koppintás — és megy, nem kell újra gépelni.
struct SuggestionChips: View {
    @Environment(AppState.self) private var state
    let suggestions: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(suggestions, id: \.self) { text in
                    Button {
                        Haptics.tap()
                        state.send(text)
                    } label: {
                        Text(text)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.textMuted)
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Theme.surfaceRaised, in: Capsule())
                            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 1)
        }
        .scrollClipDisabled()
    }
}

struct CodePanel: View {
    let language: String
    let code: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(language.isEmpty ? "code" : language)
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(0.8)
                    .foregroundStyle(Theme.textFaint)
                Spacer()
                Button {
                    UIPasteboard.general.string = code
                    Haptics.success()
                    copied = true
                    Task { try? await Task.sleep(for: .seconds(1.4)); copied = false }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(copied ? Theme.success : Theme.textMuted)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)

            Divider().overlay(Theme.hairline)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(Color(hex: 0xD7E0FF))
                    .textSelection(.enabled)
                    .padding(12)
            }
        }
        .background(Color(hex: 0x0B0B10), in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
    }
}

struct TypingDots: View {
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Theme.violetSoft)
                    .frame(width: 4.5, height: 4.5)
                    .opacity(phase == index ? 1 : 0.25)
            }
        }
        .onReceive(Timer.publish(every: 0.28, on: .main, in: .common).autoconnect()) { _ in
            phase = (phase + 1) % 3
        }
    }
}

enum Haptics {
    // UIKit feedback generators are main-actor only; every call site is a UI gesture,
    // so assuming the main actor here is both true and warning-free under Swift 6.
    static func tap() {
        MainActor.assumeIsolated { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    }
    static func success() {
        MainActor.assumeIsolated { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    }
}
