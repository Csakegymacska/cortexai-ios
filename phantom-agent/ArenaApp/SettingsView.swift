// SettingsView — az app beállításai saját kártyás dizájnnal. Semmi külső szolgáltatás.
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("web.url") private var webURLString = "https://cortanime.eu/ai"
    @AppStorage("status.url") private var statusURL = "https://cortanime.eu/api/cortexai/agent/status"
    @AppStorage("engine.kind") private var engineRaw = ChatEngineKind.native.rawValue
    @AppStorage("ui.reduceMotion") private var reduceMotion = false

    @State private var appeared = false

    private var engine: Binding<ChatEngineKind> {
        Binding(
            get: { ChatEngineKind(rawValue: engineRaw) ?? .native },
            set: {
                Haptics.select()
                engineRaw = $0.rawValue
            }
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PhantomBackdrop()

                ScrollView {
                    VStack(spacing: 14) {
                        engineCard.cardEntrance(0, appeared: appeared)
                        brainCard.cardEntrance(1, appeared: appeared)
                        workspaceCard.cardEntrance(2, appeared: appeared)
                        bridgeCard.cardEntrance(3, appeared: appeared)
                        appearanceCard.cardEntrance(4, appeared: appeared)
                        aboutCard.cardEntrance(5, appeared: appeared)
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
                    Button {
                        Haptics.tap()
                        dismiss()
                    } label: {
                        Text("Done")
                            .font(Theme.ui(15)).fontWeight(.semibold)
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
        .onAppear { appeared = true }
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
                                .font(Theme.ui(13)).fontWeight(.semibold)
                            Text(kind == .native ? "Built-in chat" : "Browser")
                                .font(Theme.ui(10))
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
                .font(Theme.ui(11))
                .foregroundStyle(Theme.txt3)
        }
        .cardSurface()
    }

    // ── A saját agyunk ──
    private var brainCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(icon: "brain.head.profile", title: "The brain")
            HStack(spacing: 12) {
                CoreMark(size: 56, working: false)
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Phantom Core 2")
                        .font(Theme.display(16)).fontWeight(.bold)
                        .foregroundStyle(Theme.txt)
                    Text("Our own AI pipeline — multi-candidate with a constitutional reviewer. Runs on our servers, answers instantly.")
                        .font(Theme.ui(11))
                        .foregroundStyle(Theme.txt3)
                }
            }
        }
        .cardSurface()
    }

    // ── Saját web-munkaterület ──
    private var workspaceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(icon: "globe", title: "Web workspace")
            FieldBox {
                TextField("Workspace URL", text: $webURLString)
                    .keyboardType(.URL)
            }
            Text("Our own workspace at cortanime.eu/ai — full agent sessions in the browser engine.")
                .font(Theme.ui(11))
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
                    .font(Theme.ui(11))
                    .foregroundStyle(Theme.txt3)
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
                    .font(Theme.ui(15))
                    .foregroundStyle(Theme.txt)
                Spacer()
                Toggle("", isOn: $reduceMotion)
                    .labelsHidden()
                    .tint(Theme.vio)
                    .onChange(of: reduceMotion) { _, _ in Haptics.select() }
            }
        }
        .cardSurface()
    }

    // ── About ──
    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "info.circle")
                    .font(.callout)
                    .foregroundStyle(Theme.txt3)
                Text("Cortex Phantom Agent")
                    .font(Theme.ui(15))
                    .foregroundStyle(Theme.txt2)
                Spacer()
                Text("1.0 (build 1) · iOS 26+")
                    .font(Theme.mono)
                    .foregroundStyle(Theme.txt3)
            }
            Text("Everything in this app is ours — the brain, the workspace, the design. cortanime.eu")
                .font(Theme.ui(11))
                .foregroundStyle(Theme.txt3)
        }
        .cardSurface()
    }
}
