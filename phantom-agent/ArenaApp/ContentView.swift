// ContentView — az app háza: natív chat VAGY agent-workspace (web), élő állapot-pill.
import SwiftUI

struct ContentView: View {
    @StateObject private var status = StatusClient()
    @State private var isLoading = false
    @State private var showSettings = false
    @AppStorage("arena.url") private var arenaURL = "https://arena.ai/"
    @AppStorage("engine.kind") private var engineRaw = ChatEngineKind.native.rawValue

    private var webURL: URL { URL(string: arenaURL) ?? URL(string: "https://arena.ai/")! }
    private var engine: ChatEngineKind { ChatEngineKind(rawValue: engineRaw) ?? .native }

    var body: some View {
        ZStack {
            AuroraBackground()

            VStack(spacing: 0) {
                header
                ZStack {
                    switch engine {
                    case .native:
                        NativeChatView()
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    case .agentWeb:
                        WebView(isLoading: $isLoading, url: webURL)
                            .ignoresSafeArea(edges: .bottom)
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    }
                    if isLoading && engine == .agentWeb {
                        ProgressView().controlSize(.large).tint(Theme.pink)
                    }
                }
                statusBar
            }
        }
        .preferredColorScheme(.dark)
        .animation(Theme.softSpring, value: engineRaw)
        .sheet(isPresented: $showSettings) { SettingsView() }
        .onAppear {
            status.start(poll: 5)
            ActivityManager.shared.sync(with: status.status)
        }
        .onChange(of: status.status) { _, s in
            if s.isWorking {
                ActivityManager.shared.sync(with: s)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            status.refresh()
        }
    }

    // ── fejléc ──
    private var header: some View {
        HStack(spacing: 12) {
            LiveRing(working: status.status.isWorking, size: 30)

            VStack(alignment: .leading, spacing: 1) {
                Text("Cortex Phantom Agent").font(.headline)
                Text(engine == .native ? "Arena API" : "Agent workspace")
                    .font(.caption2)
                    .foregroundStyle(Theme.txt3)
                    .animation(Theme.softSpring, value: engineRaw)
            }
            Spacer()
            StatusPill(status: status.status)
            Button { showSettings = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(Theme.txt2)
                    .frame(width: 34, height: 34)
                    .background(Theme.surf2, in: Circle())
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Theme.bg.opacity(0.92))
        .overlay(Rectangle().fill(Theme.line).frame(height: 1), alignment: .bottom)
    }

    // ── alsó sáv: a lépések — "mit bash-elek" élőben ──
    private var statusBar: some View {
        HStack(spacing: 10) {
            if status.status.isWorking {
                ProgressView().controlSize(.mini).tint(Theme.pink)
                Text(status.status.step.isEmpty ? "Working…" : status.status.step)
                    .font(Theme.mono)
                    .foregroundStyle(Theme.txt2)
                    .lineLimit(1)
                    .id(status.status.step)
                    .transition(.opacity)
            } else {
                Image(systemName: "moon.zzz").font(.caption).foregroundStyle(Theme.txt3)
                Text("Ready when you are").font(.caption).foregroundStyle(Theme.txt3)
            }
            Spacer()
            Button { status.refresh() } label: {
                Image(systemName: "arrow.clockwise").font(.caption).foregroundStyle(Theme.txt3)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Theme.surf.opacity(0.9))
        .overlay(Rectangle().fill(Theme.line).frame(height: 1), alignment: .top)
        .animation(Theme.softSpring, value: status.status.step)
    }
}
