import SwiftUI

/// The one quiet line under a finished answer.
///
/// The worker tells every reply which layer produced it — its own brain (instant), the
/// store it has learned from, the catalogue search, or the model — how many milliseconds
/// it took, and where the facts came from. Showing that is what turns a black box into
/// something the reader can check, and it costs a row of small type.
struct ReplyFooter: View {
    let message: ChatMessage
    @Environment(\.openURL) private var openURL

    private struct Chip: Identifiable {
        let id = UUID()
        let host: String
        let url: URL?
    }

    private var badge: (text: String, symbol: String, tint: Color)? {
        switch message.layer {
        case "brain": return ("instant", "bolt.fill", Theme.success)
        case "knowledge": return ("learned", "book.closed.fill", Theme.cyan)
        case "search": return ("catalogue", "magnifyingglass", Theme.violetSoft)
        case "sandbox":
            let runs = message.runs ?? 0
            return (runs > 1 ? "computed ×\(runs)" : "computed", "terminal.fill", Theme.cyan)
        case "engine": return ("reasoned", "sparkles", Theme.textFaint)
        default: return nil
        }
    }

    private var chips: [Chip] {
        let links = message.sourceLinks
        var seen = Set<String>()
        var result: [Chip] = []
        for raw in message.sources ?? [] {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let host = URL(string: trimmed)?.host ?? trimmed
            let clean = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            guard seen.insert(clean).inserted else { continue }
            result.append(Chip(host: clean, url: links.first { $0.host?.contains(clean) == true }))
            if result.count == 3 { break }
        }
        return result
    }

    private var latency: String? {
        guard let ms = message.latencyMS, ms > 0 else { return nil }
        return ms < 1_000 ? "\(ms) ms" : String(format: "%.1f s", Double(ms) / 1_000)
    }

    var body: some View {
        let ready = badge != nil || latency != nil || !chips.isEmpty
        if ready {
            HStack(spacing: 6) {
                if let badge {
                    Label(badge.text, systemImage: badge.symbol)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(badge.tint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background(badge.tint.opacity(0.12), in: Capsule())
                }

                ForEach(chips) { chip in
                    Button {
                        if let url = chip.url { openURL(url) }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "link")
                                .font(.system(size: 8, weight: .bold))
                            Text(chip.host)
                                .font(.system(size: 10, weight: .medium))
                                .lineLimit(1)
                        }
                        .foregroundStyle(Theme.textMuted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background(Theme.surfaceRaised, in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(chip.url == nil)
                }

                if let latency {
                    Text(latency)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.textFaint)
                        .monospacedDigit()
                }

                Spacer(minLength: 0)
            }
            .padding(.top, 2)
            .transition(.opacity)
        }
    }
}
