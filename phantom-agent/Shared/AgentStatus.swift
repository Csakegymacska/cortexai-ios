// ArenaShared — az agent állapot-modell, megosztva az app és a widget kiterjesztés között.
import Foundation

public struct AgentStatus: Codable, Equatable {
    public var state: String      // "working" | "idle" | "waiting"
    public var step: String       // pl. "bash: python3 tools/phantom_mix.py"
    public var at: Int            // unix idő
    public var turn: Int

    public init(state: String = "idle", step: String = "", at: Int = 0, turn: Int = 0) {
        self.state = state
        self.step = step
        self.at = at
        self.turn = turn
    }

    public var isWorking: Bool { state == "working" }
    public var since: Date { Date(timeIntervalSince1970: TimeInterval(at)) }
}

public enum AgentState: String {
    case working, idle, waiting

    /// A Dynamic Island címkéi — angol UI, ahogy a kötés kívánja.
    public var label: String {
        switch self {
        case .working: return "Working"
        case .waiting: return "Waiting for you"
        case .idle: return "Idle"
        }
    }
}
