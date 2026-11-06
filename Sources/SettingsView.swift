import SwiftUI
import PhotosUI

struct SettingsView: View {
    @Environment(AppState.self) private var state
    @State private var showFeatures = false
    @Environment(\.dismiss) private var dismiss
    @State private var confirmErase = false
    @State private var health: CortexClient.Health?
    @State private var newMemory = ""
    @State private var showLogin = false
    @State private var avatarItem: PhotosPickerItem?
    @State private var avatarImage: UIImage?
    @StateObject private var account = AccountStore.shared

    private var orderedMemories: [MemoryNote] {
        state.memories.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        @Bindable var state = state
        NavigationStack {
            ZStack {
                AuroraBackground(intensity: 0.6)
                Form {
                    Section("Account") {
                        if account.isLoggedIn {
                            HStack(spacing: 12) {
                                PhotosPicker(selection: $avatarItem, matching: .images) {
                                    if let img = avatarImage {
                                        Image(uiImage: img)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 40, height: 40)
                                            .clipShape(Circle())
                                    } else {
                                        Image(systemName: "person.crop.circle.fill")
                                            .font(.system(size: 26))
                                            .foregroundStyle(Theme.violetSoft)
                                    }
                                }
                                .onChange(of: avatarItem) { _, item in
                                    Task {
                                        if let data = try? await item?.loadTransferable(type: Data.self) {
                                            avatarImage = UIImage(data: data)
                                            _ = await account.uploadAvatar(data)
                                        }
                                    }
                                }
                                .task {
                                    if avatarImage == nil, let d = await account.fetchAvatar() {
                                        avatarImage = UIImage(data: d)
                                    }
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(account.displayName).font(.system(size: 14.5, weight: .semibold))
                                    Text(account.user?.email ?? "")
                                        .font(.system(size: 11.5)).foregroundStyle(Theme.textFaint)
                                }
                                Spacer()
                                Button("Sign Out") {
                                    Task { await account.logout() }
                                }
                                .font(.system(size: 13))
                                .tint(Theme.violetSoft)
                            }
                        } else {
                            Button {
                                showLogin = true
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "person.crop.circle.badge.plus")
                                        .frame(width: 26)
                                        .foregroundStyle(Theme.violetSoft)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Sign in or create an account")
                                            .font(.system(size: 14.5, weight: .semibold))
                                        Text("Syncs your subscription, API keys and AI profile")
                                            .font(.system(size: 11.5))
                                            .foregroundStyle(Theme.textFaint)
                                            .multilineTextAlignment(.leading)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Theme.textFaint)
                                }
                            }
                        }
                    }
                    Section("Model") {
                        ForEach(CortexTier.all) { tier in
                            Button {
                                state.settings.defaultTier = tier.id
                                state.save()
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: tier.symbol)
                                        .frame(width: 26)
                                        .foregroundStyle(Theme.violetSoft)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(tier.label).font(.system(size: 14.5, weight: .semibold))
                                        Text(tier.blurb)
                                            .font(.system(size: 11.5))
                                            .foregroundStyle(Theme.textFaint)
                                            .multilineTextAlignment(.leading)
                                    }
                                    Spacer()
                                    if state.settings.defaultTier == tier.id {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.violetSoft)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Section {
                        NavigationLink {
                            SubscriptionView()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "sparkles.rectangle.stack")
                                    .frame(width: 26)
                                    .foregroundStyle(Theme.violetSoft)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Subscription")
                                        .font(.system(size: 14.5, weight: .semibold))
                                    Text(SubscriptionStore.shared.tier.blurb)
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(Theme.textFaint)
                                }
                                Spacer()
                                Text(SubscriptionStore.shared.tier.label)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Theme.cyan)
                            }
                        }
                    } header: {
                        Text("Csomag")
                    }

                    Section("Cortex Void Core") {
                        CorePanel()
                    }

                    Section {
                        Toggle("Remember useful details", isOn: Binding(
                            get: { state.settings.memoryEnabled },
                            set: { state.setMemoryEnabled($0) }
                        ))
                        HStack(spacing: 10) {
                            TextField("Add a note — e.g. A nevem Bence.", text: $newMemory)
                                .textInputAutocapitalization(.sentences)
                                .onSubmit(addNote)
                            Button("Add", action: addNote)
                                .disabled(newMemory.trimmingCharacters(in: .whitespaces).count < 3)
                        }
                        if orderedMemories.isEmpty {
                            Text("Nothing yet. Tell Cortex something about yourself and it stays with the conversation.")
                                .font(.system(size: 11.5))
                                .foregroundStyle(Theme.textFaint)
                        }
                        ForEach(orderedMemories) { note in
                            HStack(spacing: 10) {
                                Image(systemName: note.automatic ? "sparkles" : "pin.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.violetSoft)
                                Text(note.text)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.text)
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets { state.removeMemory(orderedMemories[index]) }
                        }
                        if !orderedMemories.isEmpty {
                            Button("Forget everything I said", role: .destructive) {
                                state.clearMemories()
                            }
                        }
                    } header: {
                        Text("Memory")
                    } footer: {
                        Text("Cortex carries these with every message, across chats and app restarts. Delete anything you do not want it to use.")
                    }

                    Section("Chat") {
                        Toggle("Stream replies", isOn: $state.settings.streamReplies)
                        Toggle("Haptics", isOn: $state.settings.hapticsEnabled)
                        Toggle("Show timestamps", isOn: $state.settings.showTimestamps)
                    }

                    Section {
                        NavigationLink {
                            InstallView()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "square.and.arrow.down")
                                    .frame(width: 26)
                                    .foregroundStyle(Theme.violetSoft)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Install on another phone")
                                        .font(.system(size: 14.5, weight: .semibold))
                                    Text("AltStore source, the IPA, and how to sign it")
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(Theme.textFaint)
                                }
                                Spacer()
                            }
                        }
                    } header: {
                        Text("Get Cortex AI")
                    }

                    Section("What's new") {
                        Button {
                            showFeatures = true
                        } label: {
                            Label("What's new in this version", systemImage: "sparkles")
                                .foregroundStyle(Theme.text)
                        }
                    }

                    Section("Data") {
                        Button("Delete all chats and reset settings", role: .destructive) { confirmErase = true }
                    }

                    Section("About") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 10) {
                                CortexMark(size: 26)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Cortex AI").font(.system(size: 15, weight: .bold))
                                    Text("Cortex Void · OmegaTech × CortexAnime")
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(Theme.textFaint)
                                }
                            }
                            Text("Version \(Bundle.main.shortVersion) (\(Bundle.main.buildNumber))")
                                .font(.system(size: 11.5))
                                .foregroundStyle(Theme.textFaint)
                            if let health {
                                Label("Backend online · \(health.model)", systemImage: "dot.radiowaves.left.and.right")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(Theme.success)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .alert("Erase everything?", isPresented: $confirmErase) {
                Button("Erase", role: .destructive) {
                    state.eraseEverything()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Every chat and setting on this device is deleted. This cannot be undone.")
            }
            .task {
                health = try? await CortexClient.shared.health()
            }
        }
        .sheet(isPresented: $showFeatures) {
            FeaturesView().presentationBackground(Theme.ink)
        }
        .sheet(isPresented: $showLogin) {
            LoginView()
        }
        .preferredColorScheme(.dark)
    }

    private func addNote() {
        let clean = newMemory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count >= 3 else { return }
        state.addMemory(clean)
        newMemory = ""
    }
}