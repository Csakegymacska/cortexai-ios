// SettingsView — az app beállításai: Arena API, motorválasztás, állapot-híd, megjelenés.
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("arena.url") private var arenaURL = "https://arena.ai/"
    @AppStorage("status.url") private var statusURL = "https://cortanime.eu/api/cortexai/agent/status"
    @AppStorage("engine.kind") private var engineRaw = ChatEngineKind.native.rawValue
    @AppStorage("arena.model") private var model = "coding-router-preview"
    @AppStorage("ui.reduceMotion") private var reduceMotion = false

    @State private var apiKey = ""
    @State private var keySaved = false

    private var engine: Binding<ChatEngineKind> {
        Binding(
            get: { ChatEngineKind(rawValue: engineRaw) ?? .native },
            set: { engineRaw = $0.rawValue }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Chat engine", selection: engine) {
                        ForEach(ChatEngineKind.allCases) { kind in
                            Text(kind.label).tag(kind)
                        }
                    }
                } footer: {
                    Text(ChatEngineKind(rawValue: engineRaw)?.subtitle ?? "")
                }

                Section("Native provider") {
                    Picker("Provider", selection: Binding(
                        get: { ProviderKind(rawValue: UserDefaults.standard.string(forKey: "chat.provider") ?? "") ?? .phantom },
                        set: { UserDefaults.standard.set($0.rawValue, forKey: "chat.provider") }
                    )) {
                        ForEach(ProviderKind.allCases) { p in
                            Text(p.label).tag(p)
                        }
                    }
                    Text("Cortex Phantom is our own AI (cortanime.eu). Arena API uses your key below.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Arena API") {
                    SecureField(keySaved ? "Key saved — replace to change" : "API key (arena-...)", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    HStack {
                        Button("Save key") {
                            let k = apiKey.trimmingCharacters(in: .whitespaces)
                            guard !k.isEmpty else { return }
                            Keychain.save(k, for: "arena.api.key")
                            apiKey = ""
                            keySaved = true
                        }
                        .buttonStyle(.borderedProminent)
                        if keySaved {
                            Button("Remove", role: .destructive) {
                                Keychain.delete("arena.api.key")
                                keySaved = false
                            }
                        }
                    }
                    TextField("Model", text: $model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text("Get a key at platform.arena.ai -> Keys. The key is stored in the iOS Keychain only.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Agent status bridge") {
                    TextField("Status endpoint", text: $statusURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    LabeledContent("Shows", value: "Dynamic Island, widget, status bar")
                }

                Section("Agent workspace (web)") {
                    TextField("Arena URL", text: $arenaURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }

                Section("Appearance") {
                    Toggle("Reduce motion", isOn: $reduceMotion)
                }

                Section {
                    LabeledContent("Version", value: "1.0 (arena-native v1)")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { keySaved = Keychain.read("arena.api.key") != nil }
    }
}
