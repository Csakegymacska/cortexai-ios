// SettingsView — a beállítások saját kártyás dizájnnal. Full natív, semmi webes.
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var feed: AgentFeed
    @AppStorage("status.url") private var statusURL = "https://cortanime.eu/api/cortexai/agent/status"
    @AppStorage("ui.reduceMotion") private var reduceMotion = false

    @State private var appeared = false

    var body: some View {
        NavigationStack {
            ZStack {
                PhantomBackdrop()

                ScrollView {
                    VStack(spacing: 12) {
                        brainCard.cardEntrance(0, appeared: appeared)
                        runtimeCard.cardEntrance(1, appeared: appeared)
                        bridgeCard.cardEntrance(2, appeared: appeared)
                        appearanceCard.cardEntrance(3, appeared: appeared)
                        aboutCard.cardEntrance(4, appeared: appeared)
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
                    .buttonStyle(PressableStyle())
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationBackground(Theme.bg)
        .onAppear { appeared = true }
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

    // ── Agent runtime — a Linux runner élőben ──
    private var runtimeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(icon: "server.rack", title: "Agent runtime")
            HStack(spacing: 8) {
                Circle()
                    .fill(feed.online ? Theme.ok : Theme.err)
                    .frame(width: 8, height: 8)
                    .shadow(color: feed.online ? Theme.ok.opacity(0.7) : .clear, radius: 4)
                Text(feed.online ? "Runner link: live" : "Runner link: offline")
                    .font(Theme.ui(14)).fontWeight(.semibold)
                    .foregroundStyle(Theme.txt)
                Spacer()
                Text(feed.log.task.state.uppercased())
                    .font(Theme.ui(10)).fontWeight(.bold)
                    .kerning(1)
                    .foregroundStyle(Theme.txt3)
            }
            if !feed.log.task.title.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape.2")
                        .font(.caption)
                        .foregroundStyle(Theme.pink)
                    Text(feed.log.task.title)
                        .font(Theme.ui(12))
                        .foregroundStyle(Theme.txt2)
                        .lineLimit(1)
                    Spacer()
                }
            }
            Text("The Linux runner executes agent tasks and streams every step to this device.")
                .font(Theme.ui(11))
                .foregroundStyle(Theme.txt3)
            HStack(spacing: 6) {
                Image(systemName: "terminal")
                Text("python3 phantom_runner.py")
                    .font(Theme.mono)
            }
            .foregroundStyle(Theme.txt3)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.bg.opacity(0.6), in: RoundedRectangle(cornerRadius: Theme.rSm, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.rSm, style: .continuous).stroke(Theme.line, lineWidth: 1))
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
            Text("Everything in this app is ours — the brain, the runner, the design. Fully native.")
                .font(Theme.ui(11))
                .foregroundStyle(Theme.txt3)
        }
        .cardSurface()
    }
}
