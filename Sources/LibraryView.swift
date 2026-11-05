import SwiftUI

/// The chat library: search, pinned chats, swipe actions, new chat.
struct LibraryView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    let onPick: (UUID) -> Void

    @State private var query = ""

    private var results: [Conversation] {
        guard !query.isEmpty else { return state.sortedConversations }
        return state.sortedConversations.filter {
            $0.title.localizedCaseInsensitiveContains(query) || $0.preview.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground(intensity: 0.7)
                ScrollView {
                    VStack(spacing: 14) {
                        searchField
                        ForEach(results) { conversation in
                            row(conversation)
                        }
                        if results.isEmpty {
                            Text("No chats match “\(query)”.")
                                .font(Theme.body(14))
                                .foregroundStyle(Theme.textFaint)
                                .padding(.top, 30)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Chats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        let conversation = state.newConversation()
                        onPick(conversation.id)
                    } label: {
                        Label("New chat", systemImage: "square.and.pencil")
                    }
                }
            }
            .toolbarBackground(Theme.ink, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textFaint)
            TextField("Search chats", text: $query)
                .font(Theme.body(15))
                .foregroundStyle(Theme.text)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textFaint)
                }
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
    }

    private func row(_ conversation: Conversation) -> some View {
        Button { onPick(conversation.id) } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Theme.violet.opacity(0.16))
                    Image(systemName: state.profile(for: conversation).glyph)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.violetSoft)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        if conversation.pinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.magenta)
                        }
                        Text(conversation.title)
                            .font(.system(size: 14.5, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                    }
                    Text(conversation.preview)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textFaint)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(conversation.updatedAt, format: .relative(presentation: .named))
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textFaint)
            }
            .padding(12)
            .background(
                conversation.id == state.activeConversationID ? Theme.violet.opacity(0.10) : Theme.surface,
                in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                    .strokeBorder(conversation.id == state.activeConversationID ? Theme.violet.opacity(0.45) : Theme.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                state.togglePin(conversation)
            } label: { Label(conversation.pinned ? "Unpin" : "Pin", systemImage: "pin") }
            Button(role: .destructive) {
                state.delete(conversation)
            } label: { Label("Delete", systemImage: "trash") }
        }
    }
}
