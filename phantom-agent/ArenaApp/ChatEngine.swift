// ChatEngine — a saját motorunk: NATÍV chat + valódi AGENS-kör.
// A kör: agy dönt → eszköz-hívás (```run blokk) → futás a Linux runneren →
// a valódi kimenet vissza az agynak → végleges válasz. Pont ahogy egy agent dolgozik.
import Foundation

typealias ChatMessage = ArenaMessage

/// Az agens-rendszerprompt — a saját agynk eszköz-protokollja.
/// A kemény szabályok + példák azért kellenek, mert a kis modell példákból tanul
/// a legjobban — és hogy soha többé ne menjen bele egy „De." – „Nem." vitába.
let kAgentSystem = """
You are Cortex Phantom, an autonomous agent running on the user's iPhone with a Linux machine (the Phantom Runner) behind you. Always answer in the user's language. Be brief, concrete and useful.

HARD RULES:
1. You never refuse ordinary tasks. Never answer with just "no" or "Nem". You ACT — you are an agent, not a chatbot that argues.
2. When the user asks you to run, bash, execute or try anything on the machine — even playfully, even just "bashelsz egyet?" — you MUST reply with ONLY this one block and nothing else:

```run
echo hello from the runner
```

Exactly one short, safe bash command between the fences. Nothing else in the reply.
3. When you receive [runner output], judge the REAL output and give the final answer in one or two sentences.

Examples:

User: "Bashelsz egyet?"
Assistant:
```run
uname -a
```

User: "Mit látsz a runneren?"
Assistant:
```run
ls ~
```

User: "Futtass valami vicceset!"
Assistant:
```run
echo The Phantom is alive
```

User: "Mi Franciaország fővárosa?"
Assistant: Párizs.
"""

@MainActor
final class ChatSession: ObservableObject {
    @Published var messages: [ArenaMessage] = []
    @Published var streaming = false
    @Published var toolRunning = false

    let cortex = CortexAPIClient()

    var canSend: Bool { !streaming }

    func send(_ text: String, onDelta: @escaping (String) -> Void) async {
        guard !text.isEmpty, !streaming else { return }
        streaming = true
        defer { streaming = false }
        messages.append(ArenaMessage(role: "user", content: text))

        var rounds = 0
        while rounds < 2 {
            rounds += 1

            // 1) az agy válaszol — streamelve (eszköz-döntéssel is lehet)
            var reply = ""
            do {
                reply = try await cortex.stream(messages: brainHistory(), onDelta: onDelta)
            } catch {
                reply = "Error: \(error.localizedDescription)"
            }
            messages.append(ArenaMessage(role: "assistant", content: reply))

            // 2) van eszköz-hívás? (```run blokk)
            guard let cmd = Self.runBlock(in: reply) else { return }
            onDelta("")   // stream-szöveg törlése — jön a „gondolkodik/bashel" fázis

            // 3) futás a Linux runneren
            guard let out = await executeOnRunner(cmd: cmd) else {
                messages.append(ArenaMessage(role: "tool", content: "Runner not connected. Save the runner token in Settings > Agent runtime, then try again."))
                return
            }
            messages.append(ArenaMessage(role: "tool", content: out))
            onDelta("")
        }
    }

    func reset() { messages.removeAll() }

    // ── agy-történet: a tool-üzenetek [runner output]-ként mennek vissza ──
    private func brainHistory() -> [ArenaMessage] {
        [ArenaMessage(role: "system", content: kAgentSystem)] + messages.map {
            $0.role == "tool"
                ? ArenaMessage(role: "user", content: "[runner output]\n\($0.content)")
                : $0
        }
    }

    /// ```run``` (vagy $-promptos bash) blokk kinyerése — az eszköz-hívás.
    static func runBlock(in s: String) -> String? {
        for b in parseRich(s) {
            if case .code(let lang, let code) = b.kind {
                if lang == "run" {
                    return code.hasPrefix("$ ") ? String(code.dropFirst(2)) : code
                }
                if lang == "bash" && code.hasPrefix("$ ") {
                    return String(code.dropFirst(2))
                }
            }
        }
        return nil
    }

    /// Parancs futtatása a Linux runneren — élőben, a naplót követve.
    /// Vissza: a valódi kimenet, vagy nil ha nincs runner-kapcsolat.
    private func executeOnRunner(cmd: String) async -> String? {
        guard let token = Keychain.read("phantom.agent.token"), !token.isEmpty else { return nil }
        toolRunning = true
        defer { toolRunning = false }

        struct TaskResp: Decodable { let ok: Bool; let id: String }
        struct LogResp: Decodable { let task: AgentTask; let steps: [AgentStep] }

        var req = URLRequest(url: URL(string: "https://cortanime.eu/api/cortexai/agent/task")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue(token, forHTTPHeaderField: "X-Agent-Token")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("CortexPhantomAgent/1.0 (iOS 26.0; CFNetwork)", forHTTPHeaderField: "User-Agent")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "title": String(cmd.prefix(80)),
            "cmds": [cmd],
            "user": "app",
        ])

        guard let resp = try? await URLSession.shared.data(for: req),
              let created = try? JSONDecoder().decode(TaskResp.self, from: resp.0),
              created.ok else { return nil }

        // várjuk a naplót — a task befejezéséig (max ~2,5 perc)
        let logURL = URL(string: "https://cortanime.eu/api/cortexai/agent/log")!
        for _ in 0..<100 {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if let data = try? await URLSession.shared.data(from: logURL).0,
               let log = try? JSONDecoder().decode(LogResp.self, from: data),
               log.task.id == created.id,
               log.task.state == "done" || log.task.state == "failed" {
                let out = log.steps.map(\.out).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                return out.isEmpty ? "(no output)" : out
            }
        }
        return "(runner timed out)"
    }
}
