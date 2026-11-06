// ArenaApp — belépési pont. A háttér-frissítés tartja életben a Dynamic Islandet
// akkor is, ha az app a háttérben van (BGAppRefresh → Activity.update).
import SwiftUI
import BackgroundTasks
import ActivityKit

@main
struct ArenaApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "eu.cortex.phantom.status", using: nil) { task in
            Self.handleRefresh(task: task as! BGAppRefreshTask)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { Self.scheduleRefresh() }
        }
    }

    /// Háttér-frissítés: lekéri az állapotot és frissíti a Live Activityt.
    private static func handleRefresh(task: BGAppRefreshTask) {
        scheduleRefresh()
        let client = StatusClient()
        client.start(poll: 0)     // egyszeri lekérés
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            let s = await client.status
            if s.isWorking {
                ActivityManager.shared.sync(with: s)
            }
            task.setTaskCompleted(success: true)
        }
    }

    private static func scheduleRefresh() {
        let req = BGAppRefreshTaskRequest(identifier: "eu.cortex.phantom.status")
        req.earliestBeginDate = Date().addingTimeInterval(60)
        try? BGTaskScheduler.shared.submit(req)
    }
}
