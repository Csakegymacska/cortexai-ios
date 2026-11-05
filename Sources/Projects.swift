import SwiftUI

/// Egy projekt: saját utasítás és saját tudás. A beszélgetések egy projekthez
/// tartozhatnak, és ilyenkor a projekt szövege minden kérésben ott van.
/// Ez ugyanaz, amit a nagy chatek „Projects” néven csinálnak — csak helyben tárolva.
struct Project: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var instruction: String = ""
    var knowledge: String = ""
    var tintHex: UInt32 = 0x8B5CF6
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    /// Amit a kéréshez adunk. Rövid, mert a token-keret véges.
    var brief: String {
        var parts: [String] = []
        let ins = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let know = knowledge.trimmingCharacters(in: .whitespacesAndNewlines)
        if !ins.isEmpty { parts.append("Projekt utasítás: " + ins) }
        if !know.isEmpty { parts.append("Projekt tudás:\n" + know) }
        guard !parts.isEmpty else { return "" }
        let text = parts.joined(separator: "\n\n")
        return text.count <= 6_000 ? text : String(text.prefix(6_000))
    }

    var isBlank: Bool { instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && knowledge.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

/// Projektlista + szerkesztő. Egy lapon, mert kevés van belőle és gyorsan kell váltani.
struct ProjectsView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var editing: Project?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    generalCard
                    ForEach(state.projects) { project in
                        row(project)
                    }
                    Button {
                        editing = Project(name: "", instruction: "", knowledge: "",
                                          tintHex: Palette.next(state.projects.count))
                        Haptics.tap()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                            Text("Új projekt")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.violetSoft)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                                .strokeBorder(Theme.hairline, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)

                    Text("A projekt utasítása és tudása minden üzenetnél ott van a kérésben. A beszélgetések nem keverednek.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textFaint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
                .padding(Theme.gutter)
            }
            .background(Theme.ink)
            .navigationTitle("Projektek")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Kész") { dismiss() } }
            }
            .sheet(item: $editing) { project in
                ProjectEditor(project: project, isNew: state.projects.contains(where: { $0.id == project.id }) == false)
                    .presentationBackground(Theme.ink)
            }
        }
    }

    private var generalCard: some View {
        Button {
            state.selectProject(nil)
            Haptics.tap()
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "circle.dashed")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
                    .frame(width: 34, height: 34)
                    .background(Theme.surfaceRaised, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Általános")
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text("Nincs projekt — a beszélgetés szabad.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textFaint)
                }
                Spacer(minLength: 0)
                if state.activeProjectID == nil {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.success)
                }
            }
            .padding(12)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                    .strokeBorder(state.activeProjectID == nil ? Theme.violet.opacity(0.5) : Theme.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func row(_ project: Project) -> some View {
        Button {
            state.selectProject(project.id)
            Haptics.tap()
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color(hex: project.tintHex))
                    .frame(width: 10, height: 10)
                    .padding(12)
                    .background(Theme.surfaceRaised, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text(project.isBlank ? "Nincs utasítás" : project.instruction)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textFaint)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if state.activeProjectID == project.id {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.success)
                }
            }
            .padding(12)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                    .strokeBorder(state.activeProjectID == project.id ? Theme.violet.opacity(0.5) : Theme.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { editing = project } label: { Label("Szerkesztés", systemImage: "pencil") }
            Button(role: .destructive) {
                state.deleteProject(project.id)
            } label: { Label("Törlés", systemImage: "trash") }
        }
    }
}

/// A projekt szerkesztője. Két mező: mit kell mindig tudnia, és milyen tudásból dolgozzon.
struct ProjectEditor: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    @State private var draft: Project
    private let isNew: Bool

    init(project: Project, isNew: Bool) {
        _draft = State(initialValue: project)
        self.isNew = isNew
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    field("Név") {
                        TextField("Például: Anime fordítás", text: $draft.name)
                            .textFieldStyle(.plain)
                    }
                    field("Utasítás — minden válaszban érvényes") {
                        TextEditor(text: $draft.instruction)
                            .frame(minHeight: 90)
                            .scrollContentBackground(.hidden)
                    }
                    field("Tudás — szószedet, stíluslap, szabályok") {
                        TextEditor(text: $draft.knowledge)
                            .frame(minHeight: 140)
                            .scrollContentBackground(.hidden)
                    }
                    HStack(spacing: 10) {
                        Text("Szín").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.textFaint)
                        ForEach(Palette.all, id: \.self) { hex in
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 22, height: 22)
                                .overlay(
                                    Circle().strokeBorder(draft.tintHex == hex ? Color.white.opacity(0.9) : .clear, lineWidth: 2)
                                )
                                .onTapGesture { draft.tintHex = hex; Haptics.tap() }
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(Theme.gutter)
            }
            .background(Theme.ink)
            .navigationTitle(isNew ? "Új projekt" : "Projekt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Mégsem") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Mentés") {
                        var value = draft
                        value.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        if value.name.isEmpty { value.name = "Névtelen projekt" }
                        value.updatedAt = Date()
                        state.upsert(value)
                        state.selectProject(value.id)
                        Haptics.success()
                        dismiss()
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.violetSoft)
                }
            }
        }
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 10.5, weight: .heavy))
                .tracking(0.7)
                .foregroundStyle(Theme.textFaint)
                .textCase(.uppercase)
            content()
                .font(.system(size: 14))
                .foregroundStyle(Theme.text)
                .padding(12)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                        .strokeBorder(Theme.hairline, lineWidth: 1)
                )
        }
    }
}

enum Palette {
    static let all: [UInt32] = [0x8B5CF6, 0x22D3EE, 0xE879F9, 0x34D399, 0xFBBF24]
    static func next(_ count: Int) -> UInt32 { all[count % all.count] }
}
