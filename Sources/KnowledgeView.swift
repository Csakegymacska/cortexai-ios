import SwiftUI

/// Tudásbázis: mi van meg a Cortexben a katalógusról, és kereshető formában.
/// Nem chat — itt adatot lehet nézni: stúdió, rendező, évad, pontszám, részek.
struct KnowledgeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var state

    @State private var status: Status?
    @State private var query = ""
    @State private var results: [Row] = []
    @State private var loading = false
    @State private var selected: Row?

    struct Status: Decodable {
        let ok: Bool
        let series: Int?
        let withStudio: Int?
        let withDirector: Int?
        let withSynopsis: Int?
        let withNext: Int?
        let wiki: Int?
        let facts: Int?
    }

    struct Row: Decodable, Identifiable, Hashable {
        let id: Int
        let title: String
        let hu: String?
        let year: Int?
        let studio: String?
        let director: String?
        let format: String?
        let episodes: Int?
        let score: Double?
        let genres: [String]?
        let huSub: Bool?
        let url: String?
        let wiki: Bool?
    }

    private struct SearchReply: Decodable { let ok: Bool; let items: [Row]? }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    statsCard
                    searchField
                    if loading {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small).tint(Theme.textMuted)
                            Text("Keresés…").font(.system(size: 12.5)).foregroundStyle(Theme.textFaint)
                        }
                        .padding(.top, 4)
                    }
                    ForEach(results) { row in
                        resultRow(row)
                    }
                    if !results.isEmpty {
                        Text("Koppints egy sorozatra — a kérdés a chatbe kerül.")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textFaint)
                    }
                }
                .padding(Theme.gutter)
            }
            .background(Theme.ink)
            .navigationTitle("Tudásbázis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Kész") { dismiss() } } }
            .task { await loadStatus() }
            .onChange(of: query) { _, value in
                Task { await search(value) }
            }
            .sheet(item: $selected) { row in
                seriesSheet(row)
                    .presentationBackground(Theme.ink)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: Pieces

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.violetSoft)
                Text("AMIT A CORTEX TUD")
                    .font(.system(size: 10.5, weight: .heavy))
                    .tracking(1)
                    .foregroundStyle(Theme.textFaint)
                Spacer(minLength: 0)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(format(status?.series ?? 0))
                    .font(.system(size: 30, weight: .heavy))
                    .foregroundStyle(Theme.text)
                    .contentTransition(.numericText())
                Text("sorozat")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textMuted)
            }
            HStack(spacing: 14) {
                stat("stúdió", status?.withStudio)
                stat("rendező", status?.withDirector)
                stat("szinopszis", status?.withSynopsis)
                stat("wikipédia", status?.wiki)
            }
            if let facts = status?.facts, facts > 0 {
                Text("\(format(facts)) köthető tény, motor nélkül")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textFaint)
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

    private func stat(_ label: String, _ value: Int?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(format(value ?? 0))
                .font(.system(size: 13.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(Theme.textMuted)
            Text(label)
                .font(.system(size: 9.5))
                .foregroundStyle(Theme.textFaint)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textFaint)
            TextField("Cím, stúdió vagy rendező…", text: $query)
                .font(.system(size: 14))
                .foregroundStyle(Theme.text)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button {
                    query = ""
                    results = []
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textFaint)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
    }

    private func resultRow(_ row: Row) -> some View {
        Button {
            selected = row
            Haptics.tap()
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Text([row.studio, row.year.map(String.init), row.episodes.map { "\($0) rész" }]
                        .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textFaint)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if let score = row.score, score > 0 {
                    Text(String(format: "%.1f", score))
                        .font(.system(size: 12, weight: .bold).monospacedDigit())
                        .foregroundStyle(Theme.violetSoft)
                }
            }
            .padding(12)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func seriesSheet(_ row: Row) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(row.title)
                    .font(.system(size: 19, weight: .heavy))
                    .foregroundStyle(Theme.text)
                Text([row.studio, row.director, row.year.map(String.init), row.format]
                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textMuted)
                HStack(spacing: 8) {
                    if let score = row.score, score > 0 { pill("★ \(String(format: "%.1f", score))") }
                    if let eps = row.episodes { pill("\(eps) rész") }
                    if row.huSub == true { pill("magyar felirat") }
                    if row.wiki == true { pill("wikipédia") }
                }
                if let genres = row.genres, !genres.isEmpty {
                    Text(genres.joined(separator: " · "))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textFaint)
                }
                Button {
                    let q = "Mesélj bővebben erről: \(row.title)"
                    dismiss()
                    state.send(q)
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "bubble.left.and.text.bubble.right")
                        Text("Kérdezz erről a chatben")
                    }
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(Theme.gutter)
        }
        .background(Theme.ink)
    }

    private func pill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.textMuted)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Theme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
    }

    // MARK: Data

    private func loadStatus() async {
        guard let url = URL(string: "https://cortanime.eu/api/cortexai/kb/status") else { return }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }
        status = try? JSONDecoder().decode(Status.self, from: data)
    }

    private func search(_ text: String) async {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count >= 2 else { results = []; return }
        loading = true
        defer { loading = false }
        guard let encoded = clean.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://cortanime.eu/api/cortexai/kb/search?limit=12&q=\(encoded)"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let reply = try? JSONDecoder().decode(SearchReply.self, from: data) else {
            results = []
            return
        }
        results = reply.items ?? []
    }

    private func format(_ value: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = " "
        return f.string(from: NSNumber(value: value)) ?? String(value)
    }
}
