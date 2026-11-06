import CoreSpotlight
import SwiftUI
import UIKit

/// A háttérben befejezett modell-letöltés eseményeit a rendszer az app delegate-en
/// keresztül adja át. Enélkül a 4 GB-os letöltés nem fejeződne be háttérből.
final class CortexAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
    }
}

@main
struct CortexAIApp: App {
    @UIApplicationDelegateAdaptor(CortexAppDelegate.self) private var appDelegate
    @State private var state = AppState()

    init() {
        // A feladat-értesítésre koppintva a kérés a chatbe kerül.
        TaskNotificationDelegate.shared.install()
    }
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(state)
                .task { await AccountStore.shared.start() }
                .preferredColorScheme(.dark)
                .tint(Theme.violetSoft)
                .onOpenURL { url in
                    // A widgetből jött kérdés. Ha az app épp az onboardingot mutatja, itt
                    // eltesszük, és a ChatView a saját megjelenésekor veszi át.
                    guard url.scheme == "cortexai" else { return }
                    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                    if let q = items.first(where: { $0.name == "q" })?.value, !q.isEmpty {
                        UserDefaults.standard.set(q, forKey: PendingPromptKey)
                    }
                }
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    // Spotlight-találat: a megfelelő beszélgetés nyílik meg.
                    if let id = Spotlight.conversationID(from: activity) {
                        state.select(id)
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    // Everything said so far is written before the app can be killed.
                    if phase != .active { state.flush() }
                }
        }
    }
}

struct RootView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        ZStack {
            AuroraBackground()
            if state.hasOnboarded {
                ChatView()
                    .transition(.opacity)
            } else {
                OnboardingView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: state.hasOnboarded)
    }
}
