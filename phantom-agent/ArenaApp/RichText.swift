// RichText — chat-üzenetek renderelése: szöveg, inline kód, kód-blokk, terminál.
// A bash-blokk ÉLŐ animáció: a parancs kigépelődik, futás-jelzés, majd a kimenet
// soronként csúszik be — ez a „tud bash" pillanat. Emoji sehol, UI-szöveg angol.
import SwiftUI
import UIKit

// ── blokk-modell ──

struct RichBlock: Identifiable {
    enum Kind {
        case text(String)
        case code(lang: String, code: String)
    }
    let id: Int
    let kind: Kind
}

/// ```kerítés``` feldolgozása blokkokra — stream közben is működik (nyitott kerítés is).
func parseRich(_ s: String) -> [RichBlock] {
    var blocks: [RichBlock] = []
    var text = ""
    var idx = 0
    var inCode = false
    var lang = ""
    var buf: [String] = []

    func flushText() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty {
            blocks.append(RichBlock(id: idx, kind: .text(text)))
            idx += 1
        }
        text = ""
    }

    for line in s.components(separatedBy: "\n") {
        if line.hasPrefix("```") {
            if inCode {
                blocks.append(RichBlock(id: idx, kind: .code(lang: lang, code: buf.joined(separator: "\n"))))
                idx += 1
                buf = []
                inCode = false
                lang = ""
            } else {
                flushText()
                inCode = true
                lang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces).lowercased()
            }
        } else if inCode {
            buf.append(line)
        } else {
            text += line + "\n"
        }
    }
    if inCode {
        blocks.append(RichBlock(id: idx, kind: .code(lang: lang, code: buf.joined(separator: "\n"))))
    } else {
        flushText()
    }
    return blocks
}

let shellLangs: Set<String> = ["bash", "sh", "shell", "zsh", "console", "terminal"]

/// Terminál-blokk lesz-e: shell-nyelv ÉS dolláros prompt az első soron.
private func isTerminal(_ lang: String, _ code: String) -> Bool {
    guard shellLangs.contains(lang) else { return false }
    return code.hasPrefix("$ ") || code.contains("\n$ ")
}

// ── fő nézet ──

struct RichMessageView: View {
    let content: String
    var streaming = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(parseRich(content)) { block in
                switch block.kind {
                case .text(let t):
                    InlineRichText(t)
                case .code(let lang, let code):
                    if lang == "run" {
                        // eszköz-hívás — terminál-animációval
                        TerminalBlockView(code: code.hasPrefix("$ ") ? code : "$ " + code, live: streaming)
                    } else if isTerminal(lang, code) {
                        TerminalBlockView(code: code, live: streaming)
                    } else {
                        CodeBlockView(lang: lang, code: code)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeOut(duration: 0.2), value: content.count)
    }
}

/// Szöveg `inline kóddal` — a kód rózsaszín, mono, enyhén kiemelt háttéren.
struct InlineRichText: View {
    let raw: String
    init(_ raw: String) { self.raw = raw }

    var body: some View {
        Text(attributed)
            .font(Theme.ui(15))
            .foregroundStyle(Theme.txt)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var attributed: AttributedString {
        var out = AttributedString()
        var rest = Substring(raw)
        while let tick = rest.firstIndex(of: "`") {
            out += AttributedString(String(rest[rest.startIndex..<tick]))
            rest = rest[rest.index(after: tick)...]
            if let close = rest.firstIndex(of: "`") {
                var seg = AttributedString(String(rest[rest.startIndex..<close]))
                seg.font = Theme.mono
                seg.foregroundColor = Theme.pink
                seg.backgroundColor = Theme.surf2.opacity(0.8)
                out += seg
                rest = rest[rest.index(after: close)...]
            } else {
                out += AttributedString("`" + String(rest))
                rest = ""
            }
        }
        out += AttributedString(String(rest))
        return out
    }
}

// ── kód-blokk — panel, nyelv, másolás, sorszám ──

struct CodeBlockView: View {
    let lang: String
    let code: String
    @State private var copied = false

    private var lines: [String] { code.components(separatedBy: "\n") }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(lang.isEmpty ? "code" : lang)
                    .font(Theme.ui(10)).fontWeight(.semibold)
                    .kerning(0.8).textCase(.uppercase)
                    .foregroundStyle(Theme.txt3)
                Spacer()
                Button {
                    UIPasteboard.general.string = code
                    Haptics.success()
                    withAnimation(Theme.spring) { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                        withAnimation(Theme.spring) { copied = false }
                    }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(copied ? Theme.ok : Theme.txt3)
                }
                .buttonStyle(PressableStyle())
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Theme.bg.opacity(0.55))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .trailing, spacing: 2) {
                        ForEach(0..<max(lines.count, 1), id: \.self) { i in
                            Text("\(i + 1)")
                                .font(Theme.mono)
                                .foregroundStyle(Theme.txt3.opacity(0.45))
                        }
                    }
                    Text(code)
                        .font(Theme.mono)
                        .foregroundStyle(Theme.txt2)
                        .textSelection(.enabled)
                }
                .padding(12)
            }
        }
        .background(Theme.bg.opacity(0.5), in: RoundedRectangle(cornerRadius: Theme.rSm, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.rSm, style: .continuous).stroke(Theme.line, lineWidth: 1))
    }
}

// ── terminál-blokk — a „tud bash" élő animációval ──

struct TerminalBlockView: View {
    let code: String
    var live = false
    @AppStorage("ui.reduceMotion") private var reduceMotion = false
    @State private var typed = 0
    @State private var outShown = 0
    @State private var running = false

    private var cmd: String {
        let first = code.components(separatedBy: "\n").first ?? ""
        return first.hasPrefix("$ ") ? String(first.dropFirst(2)) : first
    }
    private var outputLines: [String] {
        Array(code.components(separatedBy: "\n").dropFirst())
    }

    var body: some View {
        VStack(spacing: 0) {
            // terminál-fejléc
            HStack(spacing: 6) {
                Circle().fill(Theme.err).frame(width: 7, height: 7)
                Circle().fill(Theme.warn).frame(width: 7, height: 7)
                Circle().fill(Theme.ok).frame(width: 7, height: 7)
                Text("bash")
                    .font(Theme.ui(10)).fontWeight(.bold).kerning(1)
                    .foregroundStyle(Theme.txt3)
                Spacer()
                if live {
                    HStack(spacing: 4) {
                        Circle().fill(Theme.pink).frame(width: 5, height: 5)
                        Text("LIVE").font(Theme.ui(9)).fontWeight(.bold).kerning(1)
                            .foregroundStyle(Theme.pink)
                    }
                } else if running {
                    TypingDots(color: Theme.ok)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Theme.bg.opacity(0.6))

            // tartalom
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 3) {
                    // parancs — kigépelődik
                    HStack(alignment: .top, spacing: 6) {
                        Text("$")
                            .font(Theme.mono).fontWeight(.bold)
                            .foregroundStyle(Theme.ok)
                        HStack(spacing: 0) {
                            Text(String(cmd.prefix(typed)))
                                .font(Theme.mono)
                                .foregroundStyle(Theme.txt)
                            if typed < cmd.count || (!live && !running && outShown < outputLines.count) {
                                BlinkingCaret()
                                    .frame(height: 11)
                            }
                        }
                    }
                    // kimenet — soronként csúszik be
                    ForEach(Array(outputLines.enumerated()), id: \.offset) { i, line in
                        if i < outShown {
                            Text(line.isEmpty ? " " : line)
                                .font(Theme.mono)
                                .foregroundStyle(Theme.txt2)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: 460, alignment: .leading)
            }
        }
        .background(Theme.bg.opacity(0.72), in: RoundedRectangle(cornerRadius: Theme.rSm, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.rSm, style: .continuous).stroke(Theme.line2.opacity(0.6), lineWidth: 1))
        .task(id: code) {
            if live || reduceMotion {
                typed = cmd.count
                outShown = outputLines.count
                running = false
                return
            }
            // gépelés → futás → kimenet
            typed = 0
            outShown = 0
            running = false
            let charDelay = max(8, min(24, 1100 / max(cmd.count, 1)))
            for i in 0...cmd.count {
                typed = i
                try? await Task.sleep(nanoseconds: UInt64(charDelay) * 1_000_000)
            }
            running = true
            try? await Task.sleep(nanoseconds: 380_000_000)
            running = false
            withAnimation(.easeOut(duration: 0.18)) { outShown = 0 }
            for i in 0...outputLines.count {
                withAnimation(.easeOut(duration: 0.18)) { outShown = i }
                try? await Task.sleep(nanoseconds: 55_000_000)
            }
        }
    }
}
