// ContentView — az app háza: natív chat (Cortex Phantom) VAGY saját web-munkaterület.
// Minden a miénk — arena.ai sehol.
import SwiftUI

struct ContentView: View {
    @StateObject private var status = StatusClient()
    @State private var isLoading = false
    @State private var showSettings = false
    @State private var showIntro = true
    @AppStorage("web.url") private var webURLString = "https://cortanime.eu/ai"
    @AppStorage("engine.kind") private var engineRaw = ChatEngineKind.native.rawValue

    private var webURL: URL { URL(string: webURLString) ?? URL(string: "https://cortanime.eu/ai")! }
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

            if showIntro {
                IntroOverlay()
                    .transition(.opacity)
                    .allowsHitTesting(false)
                    .zIndex(2)
            }
        }
        .preferredColorScheme(.dark)
        .animation(Theme.softSpring, value: engineRaw)
        .sheet(isPresented: $showSettings) { SettingsView() }
        .onAppear {
            status.start(poll: 5)
            ActivityManager.shared.sync(with: status.status)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) {
                withAnimation(.easeOut(duration: 0.55)) { showIntro = false }
            }
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

    // ── fejléc: élő gyűrű + egysoros cím + állapot ──
    private var header: some View {
        HStack(spacing: 13) {
            LiveRing(working: status.status.isWorking, size: 46)

            VStack(alignment: .leading, spacing: 3) {
                Text("Cortex Phantom Agent")
                    .font(Theme.display(17)).fontWeight(.bold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                HStack(spacing: 5) {
                    Image(systemName: engine == .native ? "sparkles" : "globe")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.pink)
                    Text(engine == .native ? "Native chat · our own brain" : "Web workspace · cortanime.eu")
                        .font(Theme.ui(11))
                        .foregroundStyle(Theme.txt3)
                        .lineLimit(1)
                }
                .animation(Theme.softSpring, value: engineRaw)
            }

            Spacer(minLength: 8)

            StatusPill(status: status.status)

            Button {
                Haptics.tap()
                showSettings = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.txt2)
                    .frame(width: 34, height: 34)
                    .background(Theme.surf2, in: Circle())
                    .overlay(Circle().stroke(Theme.line, lineWidth: 1))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
        .background(
            LinearGradient(colors: [Theme.bg.opacity(0.96), Theme.bg.opacity(0.88)],
                           startPoint: .top, endPoint: .bottom)
        )
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
                Text("Ready when you are").font(Theme.ui(12)).foregroundStyle(Theme.txt3)
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
