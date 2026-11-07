// AgentFeed — az élő lépés-napló (step ledger) kliense.
// A Linux runner (tools/phantom_runner.py) tölti; az app Activity-fülje
// és a Console ezt jeleníti meg. Frissítés: 4 mp poll.
import Foundation
import Combine

struct AgentStep: Codable, Identifiable, Equatable {
    var id: Int { n }
    var n: Int
    var title: String
    var detail: String
    var state: String          // pending | working | done | failed
    var out: String
    var sec: Double
    var at: Int
}

struct AgentTask: Codable, Equatable {
    var id: String
    var title: String
    var state: String          // queued | working | done | failed | idle
    var at: Int
}

struct AgentLog: Codable, Equatable {
    var task: AgentTask
    var steps: [AgentStep]
    var at: Int
}

@MainActor
final class AgentFeed: ObservableObject {
    @Published var log = AgentLog(task: AgentTask(id: "", title: "", state: "idle", at: 0), steps: [], at: 0)
    @Published var online = false

    private var timer: AnyCancellable?
    private let endpoint = URL(string: "https://cortanime.eu/api/cortexai/agent/log")!

    func start(poll seconds: Double = 4) {
        refresh()
        timer = Timer.publish(every: seconds, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        Task {
            do {
                var req = URLRequest(url: endpoint)
                req.timeoutInterval = 15
                req.setValue("CortexPhantomAgent/1.0 (iOS 26.0; CFNetwork)", forHTTPHeaderField: "User-Agent")
                let (data, _) = try await URLSession.shared.data(for: req)
                let decoded = try JSONDecoder().decode(AgentLog.self, from: data)
                if decoded != log { log = decoded }
                online = true
            } catch {
                online = false
            }
        }
    }

    var isWorking: Bool { log.task.state == "working" || log.task.state == "queued" }
}
