// ActivityManager — a Live Activity indítása/frissítése.
// V1: helyi frissítés az app polljából (BGAppRefresh is frissíti a háttérben).
// V2: APNs liveactivity push a szerverről — lásd ARENA-NATIVE.md.
@preconcurrency import ActivityKit
import Foundation

@MainActor
final class ActivityManager {
    static let shared = ActivityManager()
    private var activity: Activity<AgentActivityAttributes>?

    /// Indítás vagy frissítés — ha már fut, csak a ContentState-et cseréli.
    func sync(with status: AgentStatus) {
        let state = AgentActivityAttributes.ContentState(status)
        if let activity, activity.activityState == .active {
            let content = ActivityContent(state: state, staleDate: nil)
            Task { await activity.update(content) }
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(60 * 60 * 8))
        let attrs = AgentActivityAttributes(name: "Cortex Agent")
        activity = try? Activity.request(attributes: attrs, content: content, pushType: nil)
    }

    /// Befejezés — az island eltűnik.
    func end() {
        guard let activity else { return }
        let state = AgentActivityAttributes.ContentState(state: "idle", step: "", at: Int(Date().timeIntervalSince1970))
        Task { await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .after(Date().addingTimeInterval(60))) }
        self.activity = nil
    }
}
