import SwiftUI

/// „Újdonságok” — a szerverről jön, hogy a régi build is lássa, mi az új.
/// Ha a hálózat nem megy, a beépített lista marad: sose legyen üres lap.
struct FeaturesView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var board: CortexClient.FeatureBoard?
    @State private var failed = false
    @State private var appeared = false

    private let fallback: [CortexClient.Feature] = [
        .init(key: "research", title: "Deep research", body: "Multiple sources, numbered references — the sources sit under the answer."),
        .init(key: "documents", title: "Dokumentumok", body: "PDF, TXT, MD, CSV csatolása; a válasz a dokumentumból dolgozik."),
        .init(key: "suggestions", title: "Next question", body: "Tappable suggestions under the answer, so you never have to guess what to ask next."),
        .init(key: "branch", title: "New branch", body: "Start a new conversation from any message, keeping the earlier ones."),
        .init(key: "chats74", title: "Chats, felfedezve", body: "A beszélgetéslista mostantól egyértelmű Chats gombon nyílik, kereséssel, rögzítéssel és számlálóval."),
        .init(key: "aurora74", title: "Élő auróra-háttér", body: "A háttér fényfoltjai finoman úsznak — a mozgásérzékenység-beállítást az app tiszteletben tartja."),
        .init(key: "auth74", title: "Megbízható bejelentkezés", body: "A munkamenet mostantól védetten, több rétegben tárolódik — a bejelentkezés nem vész el újraindítás után."),
    ]

    private var items: [CortexClient.Feature] { board?.items ?? (failed ? fallback : []) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            CortexMark(size: 30)
                            Text("Cortex AI " + (board?.version ?? Bundle.main.shortVersion))
                                .font(.system(size: 22, weight: .heavy))
                                .foregroundStyle(Theme.text)
                        }
                        Text("All of this is in now — and in the browser too, with the same knowledge.")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textMuted)
                    }
                    .padding(.top, 6)

                    if items.isEmpty && !failed {
                        HStack(spacing: 10) {
                            ProgressView().tint(Theme.textMuted)
                            Text("Loading…").font(.system(size: 13)).foregroundStyle(Theme.textFaint)
                        }
                        .padding(.vertical, 20)
                    }

                    VStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: icon(for: item.key))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Theme.violetSoft)
                                    .frame(width: 32, height: 32)
                                    .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .strokeBorder(Theme.hairline, lineWidth: 1)
                                    )
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title)
                                        .font(.system(size: 14.5, weight: .semibold))
                                        .foregroundStyle(Theme.text)
                                    Text(item.body)
                                        .font(.system(size: 12.5))
                                        .foregroundStyle(Theme.textMuted)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 12)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 8)
                            .animation(CortexMotion.gentle.delay(Double(index) * 0.05), value: appeared)

                            if item.id != items.last?.id {
                                Divider().overlay(Theme.hairline)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                            .strokeBorder(Theme.hairline, lineWidth: 1)
                    )
                }
                .padding(20)
            }
            .background(Theme.ink)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.violetSoft)
                }
            }
            .task {
                appeared = true
                do { board = try await CortexClient.shared.features() } catch { failed = true }
            }
        }
    }

    private func icon(for key: String) -> String {
        switch key {
        case "projects": return "square.stack.3d.up.fill"
        case "canvas": return "sidebar.right"
        case "research": return "binoculars.fill"
        case "documents": return "doc.text.fill"
        case "memory": return "brain.head.profile"
        case "branch": return "arrow.triangle.branch"
        case "compare": return "rectangle.split.2x1"
        case "templates": return "square.grid.2x2"
        case "share": return "link"
        case "incognito": return "eye.slash"
        case "suggestions": return "sparkle"
        default: return "sparkles"
        }
    }
}
