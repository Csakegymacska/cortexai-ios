// AgentActivityAttributes — a Live Activity közös attribútumai (app + widget kiterjesztés).
// A ContentState minimális: a teljes APNs-payload 4KB alatt maradjon.
import ActivityKit

public struct AgentActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Equatable {
        public var state: String
        public var step: String
        public var at: Int
        public init(state: String = "idle", step: String = "", at: Int = 0) {
            self.state = state; self.step = step; self.at = at
        }
        public init(_ s: AgentStatus) {
            self.state = s.state
            self.step = String(s.step.prefix(120))
            self.at = s.at
        }
    }
    public var name: String
    public init(name: String = "Cortex Agent") { self.name = name }
}
