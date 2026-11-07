// ContentView — az agent-konzol háza: Chat / Activity / Console fülek,
// élő misszió-sáv, állapot. Minden a miénk.
import SwiftUI

struct ContentView: View {
    @StateObject private var status = StatusClient()
    @StateObject private var feed = AgentFeed()
    @State private var isLoading = false
    @State private var showSettings = false
    @State private var showIntro = true
    @State private var tab = 0
    @AppStorage("web.url") private var webURLString = "https://cortanime.eu/ai"
    @AppStorage("engine.kind") private var engineRaw = ChatEngineKind.native.rawValue

    private var webURL: URL { URL(string: webURLString) ?? URL(string: "https://cortanime.eu/ai")! }
    private var engine: ChatEngineKind { ChatEngineKind(rawValue: engineRaw) ?? .native }

    var body: some View {
        ZStack {
            PhantomBackdrop()

            VStack(spacing: 0) {
                header

                if engine == .agentWeb {
                    WebView(isLoading: $isLoading, url: webURL)
                        .ignoresSafeArea(edges: .bottom)
                    if isLoading { ProgressView().controlSize(.large).tint(Theme.pink) }
                } else {
                    MissionStrip(log: feed.log)
                    AgentTabs(tab: $tab)
                    ZStack {
                        switch tab {
                        case 0:
                            NativeChatView()
                                .transition(.opacity.combined(with: .scale(scale: 0.99)))
                        case 1:
                            ActivityView(feed: feed)
                                .transition(.opacity)
                        default:
                            ConsoleView(feed: feed)
                                .transition(.opacity)
                        }
                    }
                    .animation(Theme.softSpring, value: tab)
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
            feed.start(poll: 4)
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
            feed.refresh()
        }
    }

    // ── fejléc ──
    private var header: some View {
        HStack(spacing: 13) {
            LiveRing(working: status.status.isWorking || feed.isWorking, size: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text("Cortex Phantom Agent")
                    .font(Theme.display(17)).fontWeight(.bold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                HStack(spacing: 5) {
                    Image(systemName: "terminal")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.pink)
                    Text(engine == .native ? "Agent console · our own brain" : "Web workspace · cortanime.eu")
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
                    .background(Theme.surf2, in: RoundedRectangle(cornerRadius: Theme.rSm, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.rSm, style: .continuous).stroke(Theme.line, lineWidth: 1))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
        .background(Theme.bg.opacity(0.92))
        .overlay(Rectangle().fill(Theme.line).frame(height: 1), alignment: .bottom)
    }

    // ── alsó sáv ──
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
            Button { status.refresh(); feed.refresh() } label: {
                Image(systemName: "arrow.clockwise").font(.caption).foregroundStyle(Theme.txt3)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Theme.surf.opacity(0.9))
        .overlay(Rectangle().fill(Theme.line).frame(height: 1), alignment: .top)
        .animation(Theme.softSpring, value: status.status.step)
    }
}
