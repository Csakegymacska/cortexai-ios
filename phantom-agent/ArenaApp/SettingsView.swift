// SettingsView — az app beállításai saját kártyás dizájnnal: motor, provider, Arena API,
// állapot-híd, munkaterület, megjelenés. UI-szöveg angolul, emoji sehol.
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("arena.url") private var arenaURL = "https://arena.ai/"
    @AppStorage("status.url") private var statusURL = "https://cortanime.eu/api/cortexai/agent/status"
    @AppStorage("engine.kind") private var engineRaw = ChatEngineKind.native.rawValue
    @AppStorage("chat.provider") private var providerRaw = ProviderKind.phantom.rawValue
    @AppStorage("arena.model") private var model = "coding-router-preview"
    @AppStorage("ui.reduceMotion") private var reduceMotion = false

    @State private var apiKey = ""
    @State private var keySaved = false
    @State private var appeared = false

    private var engine: Binding<ChatEngineKind> {
        Binding(
            get: { ChatEngineKind(rawValue: engineRaw) ?? .native },
            set: { engineRaw = $0.rawValue }
        )
    }

    private var provider: Binding<ProviderKind> {
        Binding(
            get: { ProviderKind(rawValue: providerRaw) ?? .phantom },
            set: {
                providerRaw = $0.rawValue
                NotificationCenter.default.post(name: Notification.Name("chat.provider.changed"), object: $0.rawValue)
            }
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground()

                ScrollView {
                    VStack(spacing: 14) {
                        engineCard.cardEntrance(0, appeared: appeared)
                        providerCard.cardEntrance(1, appeared: appeared)
                        arenaCard.cardEntrance(2, appeared: appeared)
                        bridgeCard.cardEntrance(3, appeared: appeared)
                        workspaceCard.cardEntrance(4, appeared: appeared)
                        appearanceCard.cardEntrance(5, appeared: appeared)
                        versionCard.cardEntrance(6, appeared: appeared)
                    }
                    .padding(16)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.bg.opacity(0.95), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Text("Done")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(Theme.accent, in: Capsule())
                            .shadow(color: Theme.vio.opacity(0.4), radius: 8, y: 3)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationBackground(Theme.bg)
        .onAppear {
            keySaved = Keychain.read("arena.api.key") != nil
            appeared = true
        }
    }

    // ── Chat engine ──
    private var engineCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(icon: "bubble.left.and.bubble.right.fill", title: "Chat engine")
            HStack(spacing: 8) {
                ForEach(ChatEngineKind.allCases) { kind in
                    let on = engine.wrappedValue == kind
                    Button {
                        withAnimation(Theme.spring) { engine.wrappedValue = kind }
                    } label: {
                        VStack(spacing: 3) {
                            Text(kind.label)
                                .font(.caption.weight(.semibold))
                            Text(kind == .native ? "Built-in chat" : "Browser")
                                .font(.system(size: 9))
                                .foregroundStyle(on ? .white.opacity(0.75) : Theme.txt3)
                        }
                        .foregroundStyle(on ? .white : Theme.txt2)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background {
                            if on {
                                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.accent)
                                    .shadow(color: Theme.vio.opacity(0.45), radius: 8, y: 3)
                            } else {
                                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surf2)
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 1))
                            }
                        }
                        .scaleEffect(on ? 1 : 0.97)
                    }
                }
            }
            Text(ChatEngineKind(rawValue: engineRaw)?.subtitle ?? "")
                .font(.caption2)
                .foregroundStyle(Theme.txt3)
        }
        .cardSurface()
    }

    // ── Native provider ──
    private var providerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(icon: "sparkles", title: "Native provider")
            HStack(spacing: 8) {
                ForEach(ProviderKind.allCases) { p in
                    let on = provider.wrappedValue == p
                    Button {
                        withAnimation(Theme.spring) { provider.wrappedValue = p }
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: p == .phantom ? "sparkles" : "cpu")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(on ? .white : Theme.pink)
                                Spacer()
                                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 14))
                                    .foregroundStyle(on ? .white : Theme.txt3)
                            }
                            Text(p.label)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(on ? .white : Theme.txt)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text(p == .phantom ? "Our own AI" : "Your API key")
                                .font(.system(size: 9))
                                .foregroundStyle(on ? .white.opacity(0.75) : Theme.txt3)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background {
                            if on {
                                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.accent)
                                    .shadow(color: Theme.vio.opacity(0.5), radius: 10, y: 4)
                            } else {
                                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surf2)
                                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line, lineWidth: 1))
                            }
                        }
                        .scaleEffect(on ? 1 : 0.97)
                    }
                }
            }
            Text("Cortex Phantom is our own AI (cortanime.eu). Arena API uses your key below.")
                .font(.caption2)
                .foregroundStyle(Theme.txt3)
        }
        .cardSurface()
    }

    // ── Arena API ──
    private var arenaCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(icon: "key.fill", title: "Arena API")

            FieldBox {
                SecureField(keySaved ? "Key saved — replace to change" : "API key (arena-...)", text: $apiKey)
                    .keyboardType(.URL)
            }

            HStack(spacing: 10) {
                GlowButton(title: "Save key", icon: "checkmark.shield") {
                    let k = apiKey.trimmingCharacters(in: .whitespaces)
                    guard !k.isEmpty else { return }
                    Keychain.save(k, for: "arena.api.key")
                    apiKey = ""
                    keySaved = true
                }
                if keySaved {
                    Button {
                        Keychain.delete("arena.api.key")
                        keySaved = false
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "trash")
                            Text("Remove").fontWeight(.semibold)
                        }
                        .font(.callout)
                        .foregroundStyle(Theme.pink)
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .background(Theme.surf2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.pink.opacity(0.35), lineWidth: 1))
                    }
                }
            }

            FieldBox {
                HStack(spacing: 10) {
                    Text("Model")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.txt3)
                        .textCase(.uppercase)
                        .kerning(0.6)
                    TextField("model", text: $model)
                }
            }

            Text("Get a key at platform.arena.ai -> Keys. The key is stored in the iOS Keychain only.")
                .font(.caption2)
                .foregroundStyle(Theme.txt3)
        }
        .cardSurface()
    }

    // ── Agent status bridge ──
    private var bridgeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(icon: "dot.radiowaves.left.and.right", title: "Agent status bridge")
            FieldBox {
                TextField("Status endpoint", text: $statusURL)
                    .keyboardType(.URL)
            }
            HStack(spacing: 8) {
                Image(systemName: "iphone.radiowaves.left.and.right")
                    .font(.caption)
                    .foregroundStyle(Theme.pink)
                Text("Shows: Dynamic Island, widget, status bar")
                    .font(.caption2)
                    .foregroundStyle(Theme.txt3)
            }
        }
        .cardSurface()
    }

    // ── Agent workspace (web) ──
    private var workspaceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(icon: "globe", title: "Agent workspace (web)")
            FieldBox {
                TextField("Workspace URL", text: $arenaURL)
                    .keyboardType(.URL)
            }
        }
        .cardSurface()
    }

    // ── Appearance ──
    private var appearanceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(icon: "wand.and.stars", title: "Appearance")
            HStack {
                Image(systemName: "wind")
                    .font(.callout)
                    .foregroundStyle(Theme.txt3)
                    .frame(width: 22)
                Text("Reduce motion")
                    .font(.callout)
                    .foregroundStyle(Theme.txt)
                Spacer()
                Toggle("", isOn: $reduceMotion)
                    .labelsHidden()
                    .tint(Theme.vio)
            }
        }
        .cardSurface()
    }

    // ── Version ──
    private var versionCard: some View {
        HStack {
            Image(systemName: "info.circle")
                .font(.callout)
                .foregroundStyle(Theme.txt3)
            Text("Cortex Phantom Agent")
                .font(.callout)
                .foregroundStyle(Theme.txt2)
            Spacer()
            Text("1.0 (build 1) · iOS 26+")
                .font(Theme.mono)
                .foregroundStyle(Theme.txt3)
        }
        .cardSurface()
    }
}
