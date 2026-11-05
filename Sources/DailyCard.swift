import SwiftUI

/// A napi kártya: mi jön ki ma, és mi történt a hírekben. Az üres chat képernyőn
/// jelenik meg — ez ad okot arra, hogy az ember beszélgessen, ne csak nézze.
struct DailyCard: View {
    let daily: CortexClient.Daily
    let onAsk: (String) -> Void

    private var nextFirst: CortexClient.Daily.Episode? { (daily.next ?? []).first }
    private var news: [CortexClient.Daily.Headline] { daily.news ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.violetSoft)
                Text("MA")
                    .font(.system(size: 10.5, weight: .heavy))
                    .tracking(1)
                    .foregroundStyle(Theme.textFaint)
                Spacer(minLength: 0)
                Text(daily.date)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Theme.textFaint)
            }

            Text(daily.line)
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)

            if let next = daily.next, !next.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(next.prefix(3)) { episode in
                        HStack(spacing: 8) {
                            Text(time(episode.at))
                                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                                .foregroundStyle(Theme.cyan)
                                .frame(width: 42, alignment: .leading)
                            Text(episode.title)
                                .font(.system(size: 12.5))
                                .foregroundStyle(Theme.textMuted)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Text("\(episode.ep). rész")
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(Theme.textFaint)
                        }
                    }
                }
            }

            if !news.isEmpty {
                Divider().overlay(Theme.hairline)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(news.prefix(3)) { item in
                        Button {
                            onAsk("Mesélj erről bővebben: \(item.title)")
                        } label: {
                            HStack(alignment: .top, spacing: 8) {
                                Circle().fill(Theme.violetSoft.opacity(0.7)).frame(width: 4, height: 4).padding(.top, 6)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.title)
                                        .font(.system(size: 12.5))
                                        .foregroundStyle(Theme.textMuted)
                                        .multilineTextAlignment(.leading)
                                        .lineLimit(2)
                                    if let source = item.source, !source.isEmpty {
                                        Text(source + (item.date.map { " · " + $0 } ?? ""))
                                            .font(.system(size: 10))
                                            .foregroundStyle(Theme.textFaint)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if let first = nextFirst {
                Button {
                    onAsk("Mennyi ideig tart megnézni a(z) \(first.title) sorozatot?")
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "bubble.left.and.bubble.right")
                        Text("Kérdezz erről")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.violetSoft)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
    }

    /// ISO időpont → helyi óra:perc. Ha nem olvasható, üres.
    private func time(_ raw: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
        guard let date else { return "" }
        let out = DateFormatter()
        out.dateFormat = "HH:mm"
        return out.string(from: date)
    }
}
