import Foundation
import SwiftUI

// MARK: - Mentett utasítások
//
// A napi használatban ugyanaz a 5-6 utasítás megy mindig: „fordítsd le magyarra",
// „csinálj belőle pontokba szedett összefoglalót", „nézd át nyelvtanilag". Ezeket
// eddig minden alkalommal begépelte az ember. Itt egyszer elmenti, onnantól egy
// koppintás — a szöveg a composerba kerül, nem küldi el magától.
//
// A store ugyanabba a könyvtárba ír, mint a beszélgetések, és ugyanazt a mintát
// követi: séma-verzió nélküli JSON, hibánál csendben üres lista.

struct SavedPrompt: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var body: String
    var symbol: String = "text.quote"
    var createdAt: Date = Date()
    var uses: Int = 0
}

@MainActor
final class PromptStore: ObservableObject {
    static let shared = PromptStore()
    @Published private(set) var prompts: [SavedPrompt] = []

    private let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("cortex-saved-prompts.json")
    }()

    private init() {
        load()
        if prompts.isEmpty { prompts = Self.starters }
    }

    /// Kezdő készlet: a leggyakoribb kérések, hogy ne üres listával induljon.
    static let starters: [SavedPrompt] = [
        .init(title: "Summarise in 5 bullets",
              body: "Summarise the following in exactly five bullet points, each under 15 words.",
              symbol: "list.bullet"),
        .init(title: "Translate to Hungarian",
              body: "Translate the following into natural, idiomatic Hungarian. Keep names and technical terms as they are.",
              symbol: "character.book.closed"),
        .init(title: "Fix grammar",
              body: "Correct the grammar and phrasing of the following, then list what you changed and why.",
              symbol: "checkmark.seal"),
        .init(title: "Explain simply",
              body: "Explain the following to a smart 12-year-old, in under 150 words, with one concrete analogy.",
              symbol: "lightbulb"),
        .init(title: "Code review",
              body: "Review the following code. List real bugs first, then style, then anything that would break under load. Be specific and cite line numbers.",
              symbol: "chevron.left.forwardslash.chevron.right"),
    ]

    func add(_ prompt: SavedPrompt) {
        prompts.insert(prompt, at: 0)
        save()
    }

    func update(_ prompt: SavedPrompt) {
        if let i = prompts.firstIndex(where: { $0.id == prompt.id }) {
            prompts[i] = prompt
            save()
        }
    }

    func delete(_ prompt: SavedPrompt) {
        prompts.removeAll { $0.id == prompt.id }
        save()
    }

    /// Használatkor nő a számláló: a lista magától a gyakran használtakat tolja előre.
    func registerUse(_ prompt: SavedPrompt) {
        if let i = prompts.firstIndex(where: { $0.id == prompt.id }) {
            prompts[i].uses += 1
            save()
        }
    }

    var byUsage: [SavedPrompt] {
        prompts.sorted { ($0.uses, $0.createdAt) > ($1.uses, $1.createdAt) }
    }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let rows = try? JSONDecoder().decode([SavedPrompt].self, from: data) else { return }
        prompts = rows
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(prompts) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

// MARK: - Kezelő felület

@MainActor
struct PromptsView: View {
    @StateObject private var store = PromptStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var editing: SavedPrompt?
    @State private var draftTitle = ""
    @State private var draftBody = ""
    @State private var showingEditor = false

    let onPick: (String) -> Void

    init(onPick: @escaping (String) -> Void) {
        self.onPick = onPick
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.byUsage) { prompt in
                        Button {
                            store.registerUse(prompt)
                            Haptics.tap()
                            onPick(prompt.body)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: prompt.symbol)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Theme.violetSoft)
                                    .frame(width: 30, height: 30)
                                    .background(Theme.violet.opacity(0.12),
                                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(prompt.title)
                                        .font(.system(size: 14.5, weight: .semibold))
                                        .foregroundStyle(Theme.text)
                                    Text(prompt.body)
                                        .font(.system(size: 12))
                                        .foregroundStyle(Theme.textFaint)
                                        .lineLimit(2)
                                }
                                Spacer(minLength: 0)
                                if prompt.uses > 0 {
                                    Text("\(prompt.uses)×")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(Theme.textFaint)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                store.delete(prompt)
                            } label: { Label("Delete", systemImage: "trash") }
                            Button {
                                editing = prompt
                                draftTitle = prompt.title
                                draftBody = prompt.body
                                showingEditor = true
                            } label: { Label("Edit", systemImage: "pencil") }
                            .tint(Theme.violet)
                        }
                    }
                } footer: {
                    Text("Tap one to drop it into the composer. It does not send by itself.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.ink)
            .navigationTitle("Saved prompts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editing = nil
                        draftTitle = ""
                        draftBody = ""
                        showingEditor = true
                    } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showingEditor) {
                editor
            }
        }
    }

    private var editor: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Weekly summary", text: $draftTitle)
                }
                Section("Instruction") {
                    TextEditor(text: $draftBody)
                        .frame(minHeight: 140)
                        .font(.system(size: 14))
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.ink)
            .navigationTitle(editing == nil ? "New prompt" : "Edit prompt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingEditor = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let cleanTitle = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        let cleanBody = draftBody.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !cleanBody.isEmpty else { showingEditor = false; return }
                        if var existing = editing {
                            existing.title = cleanTitle.isEmpty ? "Untitled" : cleanTitle
                            existing.body = cleanBody
                            store.update(existing)
                        } else {
                            store.add(SavedPrompt(title: cleanTitle.isEmpty ? "Untitled" : cleanTitle,
                                                  body: cleanBody))
                        }
                        showingEditor = false
                    }
                    .disabled(draftBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationBackground(Theme.ink)
    }
}
