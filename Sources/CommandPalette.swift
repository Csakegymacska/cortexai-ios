import SwiftUI

// MARK: - Parancspaletta
//
// Minden, amit az app tud, egy helyen: beszélgetések, műveletek, beállítások.
// Nem kell végigkoppintani a menüket — ⌘K-szerű gyorskeresés, mobilon.
//
// A keresés saját pontozás: a cím eleji egyezés többet ér, mint a szó közbeni,
// és a rövid lekérdezésre a friss beszélgetések jönnek előbb.

struct CommandPalette: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var selection = 0
    @FocusState private var fieldFocused: Bool

    /// A paletta egy eleme. A `run` zárvány akkor fut, amikor a sorra koppintanak.
    struct Item: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let symbol: String
        let tint: Color
        let keywords: String
        let run: () -> Void
    }

    private var actions: [Item] {
        var out: [Item] = []

        out.append(Item(id: "new", title: "New chat", subtitle: "Blank conversation",
                        symbol: "square.and.pencil", tint: Theme.violet,
                        keywords: "uj beszelgetes chat new") {
            _ = state.newConversation()
            dismiss()
        })

        out.append(Item(id: "research", title: "Toggle deep research",
                        subtitle: "Several sources, numbered citations",
                        symbol: "binoculars", tint: Theme.cyan,
                        keywords: "kutatas research mely") {
            state.researchMode.toggle()
            dismiss()
        })

        out.append(Item(id: "agent", title: "Toggle agent mode",
                        subtitle: "The next message can use tools",
                        symbol: "point.3.connected.trianglepath.dotted", tint: Theme.magenta,
                        keywords: "ugynok agent eszkoz") {
            state.agentMode.toggle()
            dismiss()
        })

        out.append(Item(id: "compare", title: "Compare two tones",
                        subtitle: "One question, two answers side by side",
                        symbol: "rectangle.split.2x1", tint: Theme.violetSoft,
                        keywords: "osszehasonlit compare ket hangnem") {
            state.compareMode.toggle()
            dismiss()
        })

        out.append(Item(id: "plan", title: "Plan and usage",
                        subtitle: "Daily token allowance, Pro and Max",
                        symbol: "creditcard", tint: Theme.success,
                        keywords: "elofizetes plan quota keret token") {
            state.sheet = .subscription
        })

        out.append(Item(id: "prompts", title: "Saved prompts",
                        subtitle: "Your reusable instructions",
                        symbol: "text.book.closed", tint: Theme.cyan,
                        keywords: "utasitas prompt mentett sablon") {
            state.sheet = .prompts
        })

        out.append(Item(id: "export", title: "Export this chat",
                        subtitle: "Markdown, share sheet",
                        symbol: "square.and.arrow.up", tint: Theme.textMuted,
                        keywords: "export mentes markdown share") {
            state.sheet = .export
        })

        out.append(Item(id: "settings", title: "Settings",
                        subtitle: "Appearance, data, about",
                        symbol: "gearshape", tint: Theme.textMuted,
                        keywords: "beallitasok settings") {
            state.sheet = .settings
        })

        // A beszélgetések a lista alján: a műveletek mindig elöl vannak,
        // mert azokat keresi az ember a leggyakrabban.
        for conversation in state.sortedConversations.prefix(40) where !conversation.messages.isEmpty {
            out.append(Item(id: conversation.id.uuidString,
                            title: conversation.title,
                            subtitle: conversation.preview,
                            symbol: conversation.pinned ? "pin.fill" : "bubble.left",
                            tint: conversation.pinned ? Theme.magenta : Theme.textFaint,
                            keywords: "chat beszelgetes") {
                state.select(conversation.id)
                dismiss()
            })
        }
        return out
    }

    private var results: [Item] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return actions }
        return actions
            .compactMap { item -> (Item, Int)? in
                let title = item.title.lowercased()
                var score = 0
                if title.hasPrefix(q) { score = 100 }
                else if title.contains(q) { score = 70 }
                if item.subtitle.lowercased().contains(q) { score = max(score, 40) }
                if item.keywords.contains(q) { score = max(score, 35) }
                return score > 0 ? (item, score) : nil
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                Divider().overlay(Theme.hairline)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                                row(item, selected: index == selection)
                                    .id(index)
                                    .onTapGesture {
                                        Haptics.tap()
                                        item.run()
                                    }
                            }
                            if results.isEmpty {
                                VStack(spacing: 8) {
                                    Image(systemName: "magnifyingglass")
                                        .font(.system(size: 22, weight: .light))
                                    Text("Nothing matches “\(query)”")
                                        .font(Theme.body(14))
                                }
                                .foregroundStyle(Theme.textFaint)
                                .padding(.top, 44)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                    }
                    .onChange(of: selection) { _, new in
                        withAnimation(CortexMotion.snappy) { proxy.scrollTo(new, anchor: .center) }
                    }
                }
            }
            .background(Theme.ink)
            .navigationTitle("Commands")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .tint(Theme.textMuted)
                }
            }
        }
        .onAppear { fieldFocused = true }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "command")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.violetSoft)
            TextField("Search commands and chats…", text: $query)
                .focused($fieldFocused)
                .font(Theme.body(16))
                .foregroundStyle(Theme.text)
                .tint(Theme.violetSoft)
                .submitLabel(.go)
                .onSubmit {
                    if let item = results[safe: selection] { item.run() }
                }
                .onChange(of: query) { _, _ in selection = 0 }
            if !query.isEmpty {
                Button {
                    query = ""
                    fieldFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.textFaint)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .cortexGlass(RoundedRectangle(cornerRadius: 18, style: .continuous), interactive: true)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func row(_ item: Item, selected: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(item.tint)
                .frame(width: 32, height: 32)
                .background(item.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(item.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textFaint)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if selected {
                Image(systemName: "return")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.textFaint)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(selected ? Theme.surfaceRaised : Color.clear)
        }
        .gradientEdge(radius: 11, strength: selected ? 0.14 : 0)
        .contentShape(Rectangle())
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
