import SwiftUI

/// Profile system: each profile carries a name, glyph, tint, tone and standing instructions,
/// plus the default model tier for chats started from it.
struct ProfilesView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var editing: PersonaProfile?

    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground(intensity: 0.7)
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(state.profiles) { profile in
                            card(profile)
                        }
                        Button {
                            editing = PersonaProfile(name: "New profile", glyph: "person.crop.circle", tintHex: 0x8B5CF6,
                                                     style: "Balanced", instructions: "", tier: CortexTier.void.id)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "plus")
                                Text("New profile").font(.system(size: 14, weight: .semibold))
                                Spacer()
                            }
                            .padding(14)
                            .foregroundStyle(Theme.violetSoft)
                            .background(Theme.violet.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous).strokeBorder(Theme.violet.opacity(0.35), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Profiles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
            .sheet(item: $editing) { profile in
                ProfileEditor(profile: profile)
                    .presentationBackground(Theme.ink)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func card(_ profile: PersonaProfile) -> some View {
        Button { editing = profile } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(hex: profile.tintHex).opacity(0.18))
                        Image(systemName: profile.glyph)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color(hex: profile.tintHex))
                    }
                    .frame(width: 42, height: 42)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 7) {
                            Text(profile.name)
                                .font(.system(size: 15.5, weight: .semibold))
                                .foregroundStyle(Theme.text)
                            if profile.isDefault {
                                Text("DEFAULT")
                                    .font(.system(size: 9, weight: .heavy))
                                    .tracking(0.8)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Theme.magenta.opacity(0.16), in: Capsule())
                                    .foregroundStyle(Theme.magenta)
                            }
                        }
                        Text("\(profile.style) · \(CortexTier.named(profile.tier).label)")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.textFaint)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textFaint)
                }
                if !profile.instructions.isEmpty {
                    Text(profile.instructions)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.textMuted)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { state.makeDefault(profile) } label: { Label("Make default", systemImage: "star") }
            Button(role: .destructive) { state.deleteProfile(profile) } label: { Label("Delete", systemImage: "trash") }
        }
    }
}

struct ProfileEditor: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State var profile: PersonaProfile

    private let glyphs = ["person.fill", "chevron.left.forwardslash.chevron.right", "sparkles", "book.closed.fill",
                          "gamecontroller.fill", "leaf.fill", "moon.stars.fill", "chart.bar.fill"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Identity") {
                    TextField("Name", text: $profile.name)
                    Picker("Glyph", selection: $profile.glyph) {
                        ForEach(glyphs, id: \.self) { glyph in
                            Label(glyph, systemImage: glyph).tag(glyph)
                        }
                    }
                    TextField("Tone", text: $profile.style)
                }

                Section("Model") {
                    Picker("Default tier", selection: $profile.tier) {
                        ForEach(CortexTier.all) { tier in Text(tier.label).tag(tier.id) }
                    }
                }

                Section("Standing instructions") {
                    TextEditor(text: $profile.instructions)
                        .frame(minHeight: 110)
                        .font(Theme.body(14))
                }

                Section {
                    Toggle("Make this the default profile", isOn: Binding(
                        get: { profile.isDefault },
                        set: { newValue in profile.isDefault = newValue }
                    ))
                }
            }
            .scrollContentBackground(.hidden)
            .background(AuroraBackground(intensity: 0.55))
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        if profile.isDefault { state.makeDefault(profile) }
                        state.upsert(profile)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
