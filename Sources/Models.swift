import Foundation

// MARK: - Images

/// Egy csatolt kép, ahogy a workernek megy: base64 és MIME-típus. Csak a kérés
/// élettartamáig él a memóriában — nem kerül a beszélgetés mentett példányába.
struct ChatImage: Identifiable, Hashable {
    var id: UUID = UUID()
    var mime: String
    var data: String

    var dataURL: String { "data:\(mime);base64,\(data)" }
}

/// Az ügynök egy lépése: mit tett, mit talált, mennyi ideig tartott.
struct AgentStep: Codable, Hashable, Identifiable {
    var id = UUID()
    var label: String
    var detail: String
    var ms: Int
    var ok: Bool
}

/// Egy csatolt dokumentum. A kliens olvassa ki a szöveget (PDF, TXT, MD, CSV),
/// a worker csak szöveget kap — így nem kell PDF-motort tartania.
struct ChatFile: Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var text: String
}

/// Két hangnem: ugyanaz a kérdés két stílusban. Egy motor, két profil.
struct TwoUpAnswer: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var label: String
    var text: String
}

// MARK: - Messages

struct ChatMessage: Identifiable, Codable, Hashable {
    enum Role: String, Codable { case user, assistant, system }

    var id: UUID = UUID()
    var role: Role
    var text: String
    var createdAt: Date = Date()
    /// Set while a reply is still streaming in.
    var isStreaming: Bool = false
    var failed: Bool = false
    /// Where the answer came from and how long it took — filled in from the stream's
    /// final event. Optional so conversations stored by older builds still decode.
    var layer: String? = nil
    var sources: [String]? = nil
    var latencyMS: Int? = nil
    /// How many times the reply actually ran code in the sandbox before answering.
    var runs: Int? = nil
    /// A következő kérdés javaslatai — a válasz alatt jelennek meg koppintható lapkaként.
    var suggestions: [String]? = nil
    /// Két hangnem: ha ki van töltve, a buborék két oszlopban jelenik meg.
    var twoUp: [TwoUpAnswer]? = nil
    /// Ügynök mód: a megtett lépések, sorrendben.
    var steps: [AgentStep]? = nil

    var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Host names for the chips, de-duplicated and in the order the worker sent them.
    var sourceHosts: [String] {
        var seen = Set<String>()
        return (sources ?? []).compactMap { raw in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let host = URL(string: trimmed)?.host ?? trimmed
            let clean = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            return seen.insert(clean).inserted ? clean : nil
        }
    }

    /// The full URLs behind the chips.
    var sourceLinks: [URL] {
        (sources ?? []).compactMap { URL(string: $0) }.filter { $0.scheme == "https" || $0.scheme == "http" }
    }
}

// MARK: - Conversations

struct Conversation: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String = "New chat"
    var messages: [ChatMessage] = []
    var profileID: UUID
    var tier: String = CortexTier.void.id
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var pinned: Bool = false
    /// Melyik projekthez tartozik. Régi mentésnél nil — az „Általános”.
    var projectID: UUID? = nil

    var preview: String {
        messages.last(where: { $0.role == .user })?.text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces) ?? "No messages yet"
    }

    var isEmpty: Bool { messages.isEmpty }

    /// Derives a short title from the first user message.
    static func title(from text: String) -> String {
        let clean = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        return clean.count <= 42 ? clean : String(clean.prefix(42)).trimmingCharacters(in: .whitespaces) + "…"
    }
}

// MARK: - Profiles (the "profile system")

struct PersonaProfile: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var glyph: String          // SF Symbol name
    var tintHex: UInt32
    var style: String          // "Direct", "Friendly", "Analytical"…
    var instructions: String   // free-form extra guidance sent with every message
    var tier: String           // default model tier
    var isDefault: Bool = false

    var tint: UInt32 { tintHex }

    static let builtIns: [PersonaProfile] = [
        PersonaProfile(
            name: "Personal", glyph: "person.fill", tintHex: 0x8B5CF6, style: "Balanced",
            instructions: "Beszélj velem magyarul, baráti, de lényegre törő stílusban.",
            tier: CortexTier.phantom.id, isDefault: true
        ),
        PersonaProfile(
            name: "Code", glyph: "chevron.left.forwardslash.chevron.right", tintHex: 0x22D3EE, style: "Engineer",
            instructions: "You are a senior software engineer. Prefer complete, runnable code with short explanations. Point out pitfalls.",
            tier: CortexTier.phantom.id
        ),
        PersonaProfile(
            name: "Anime", glyph: "sparkles", tintHex: 0xE879F9, style: "Curator",
            instructions: "Ajánlj animéket röviden, indoklással, Spoiler nélkül. Ha kérdeznek egy sorozatról, említs hasonló címeket.",
            tier: CortexTier.void.id
        ),
        PersonaProfile(
            name: "Study", glyph: "book.closed.fill", tintHex: 0x34D399, style: "Tutor",
            instructions: "Taníts lépésről lépésre, kérdezz vissza, ha valami hiányzik. Használj példákat.",
            tier: CortexTier.void.id
        )
    ]
}

// MARK: - Tiers

struct CortexTier: Identifiable, Hashable {
    let id: String
    let label: String
    let blurb: String
    let symbol: String

    /// The flagship. It does not answer in one shot: a draft, a critique and a final pass
    /// run behind it, so hard questions, code and long text come out better.
    static let phantom = CortexTier(id: "phantom", label: "Cortex Phantom", blurb: "The flagship. Thinks in three passes before it answers — code, maths, long questions.", symbol: "atom")
    static let void = CortexTier(id: "void", label: "Cortex Void", blurb: "The everyday model. Fast, conversational, good with long context.", symbol: "circle.hexagongrid.fill")
    static let deep = CortexTier(id: "void-deep", label: "Cortex Void Deep", blurb: "Takes longer, thinks harder. Code, maths, planning.", symbol: "brain.head.profile")
    static let fast = CortexTier(id: "void-fast", label: "Cortex Void Fast", blurb: "Short answers, minimal waiting.", symbol: "bolt.fill")

    static let all: [CortexTier] = [.phantom, .void, .deep, .fast]
    static func named(_ id: String) -> CortexTier { all.first { $0.id == id } ?? .phantom }
}

// MARK: - Memory

/// Something the app remembers about the user and sends with every request.
/// It is a plain sentence, not an embedding — the model reads it as context.
struct MemoryNote: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var text: String
    var createdAt: Date = Date()
    var automatic: Bool = true
}

/// Pulls durable facts out of a message: names, favourites, plans.
/// Deliberately conservative — a wrong memory is worse than a missing one.
enum MemoryExtractor {
    static let maxLength = 180

    private static let triggers = [
        "a nevem", "nevem ", "jegyezd", "emlékezz", "emlekezz", "ne felejtsd",
        "hívj", "hivj ", "szólíts", "szolits", "kedvenc", "szeretem", "utálom", "utalom",
        "vagyok ", "dolgozom", "tanulok", "célom", "celom", "lakom", "születtem", "szulettem",
        "a barát", "a barat", "a kutyám", "a macskám", "a húgom", "a bátyám",
    ]

    private static let questionStarts = [
        "mi ", "ki ", "mit ", "hol ", "mikor ", "hogyan ", "miért ", "miert ",
        "mennyi ", "melyik ", "van-e ", "tudsz ",
    ]

    static func notes(from text: String) -> [String] {
        let clean = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count >= 6, !clean.hasSuffix("?") else { return [] }
        let low = clean.lowercased()
        guard !questionStarts.contains(where: { low.hasPrefix($0) }) else { return [] }
        guard triggers.contains(where: { low.contains($0) }) else { return [] }
        let clipped = String(clean.prefix(maxLength)).trimmingCharacters(in: .whitespaces)
        return [clipped]
    }
}

// MARK: - Settings

struct CortexSettings: Codable, Equatable {
    var defaultTier: String = CortexTier.phantom.id
    var hapticsEnabled: Bool = true
    var streamReplies: Bool = true
    var showTimestamps: Bool = false
    var language: String = "hu"   // the reply language hint, not the UI language
    var memoryEnabled: Bool = true
    /// Offline mód: a válaszok a telefonon készülnek, a worker érintése nélkül.

    static let `default` = CortexSettings()

    /// Missing keys fall back to the default instead of failing the whole store —
    /// that is what used to wipe every chat when a new version added a setting.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let base = CortexSettings()
        defaultTier = try c.decodeIfPresent(String.self, forKey: .defaultTier) ?? base.defaultTier
        hapticsEnabled = try c.decodeIfPresent(Bool.self, forKey: .hapticsEnabled) ?? base.hapticsEnabled
        streamReplies = try c.decodeIfPresent(Bool.self, forKey: .streamReplies) ?? base.streamReplies
        showTimestamps = try c.decodeIfPresent(Bool.self, forKey: .showTimestamps) ?? base.showTimestamps
        language = try c.decodeIfPresent(String.self, forKey: .language) ?? base.language
        memoryEnabled = try c.decodeIfPresent(Bool.self, forKey: .memoryEnabled) ?? base.memoryEnabled
    }

    init() {}

    init(defaultTier: String, hapticsEnabled: Bool, streamReplies: Bool,
         showTimestamps: Bool, language: String, memoryEnabled: Bool) {
        self.defaultTier = defaultTier
        self.hapticsEnabled = hapticsEnabled
        self.streamReplies = streamReplies
        self.showTimestamps = showTimestamps
        self.language = language
        self.memoryEnabled = memoryEnabled
    }
}
