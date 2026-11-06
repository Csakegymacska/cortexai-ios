// StatusClient — az agent állapotának pollolása a cortanime.eu hídról.
// A válasz: { ok, state, step, at, turn, age } — lásd ARENA-NATIVE.md.
import Foundation

@MainActor
final class StatusClient: ObservableObject {
    @Published var status = AgentStatus()
    // A saját szerverünk ad otthont az állapot-hídnak (a titok a Settings-ben).
    @Published var endpoint = "https://cortanime.eu/api/cortexai/agent/status"

    private var timer: Timer?
    private let session = URLSession(configuration: .ephemeral)

    func start(poll: TimeInterval = 5) {
        stop()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: poll, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stop() { timer?.invalidate(); timer = nil }

    func refresh() {
        guard let url = URL(string: endpoint) else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 6
        Task {
            do {
                let (data, _) = try await session.data(for: req)
                if let j = try? JSONDecoder().decode(Raw.self, from: data) {
                    self.status = AgentStatus(state: j.state, step: j.step, at: j.at, turn: j.turn ?? 0)
                }
            } catch { /* hálózat nélkül marad az utolsó ismert állapot */ }
        }
    }

    private struct Raw: Decodable {
        let state: String
        let step: String
        let at: Int
        let turn: Int?
    }
}
