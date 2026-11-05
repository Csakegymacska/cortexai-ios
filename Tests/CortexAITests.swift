import XCTest
@testable import CortexAI

final class CortexAITests: XCTestCase {
    func testConversationTitleIsShortened() {
        let long = String(repeating: "a", count: 90)
        let title = Conversation.title(from: long)
        XCTAssertLessThanOrEqual(title.count, 45)
        XCTAssertTrue(title.hasSuffix("…"))
    }

    func testConversationTitleKeepsShortText() {
        XCTAssertEqual(Conversation.title(from: "Szia Cortex"), "Szia Cortex")
    }

    func testTierLookupFallsBackToDefault() {
        XCTAssertEqual(CortexTier.named("void-deep").id, "void-deep")
        XCTAssertEqual(CortexTier.named("nonsense").id, "phantom")
    }

    func testPhantomIsTheFlagshipAndTheDefault() {
        XCTAssertEqual(CortexTier.all.first?.id, "phantom")
        XCTAssertEqual(CortexTier.phantom.label, "Cortex Phantom")
        XCTAssertEqual(CortexSettings().defaultTier, "phantom")
        XCTAssertEqual(PersonaProfile.builtIns.first(where: { $0.isDefault })?.tier, "phantom")
    }

    func testBuiltInProfilesHaveExactlyOneDefault() {
        let defaults = PersonaProfile.builtIns.filter { $0.isDefault }
        XCTAssertEqual(defaults.count, 1)
    }

    func testEmptyAssistantBubbleIsEmpty() {
        XCTAssertTrue(ChatMessage(role: .assistant, text: "   ").isEmpty)
    }

    func testMemoryExtractorKeepsAFact() {
        XCTAssertEqual(MemoryExtractor.notes(from: "A nevem Bence.").first, "A nevem Bence.")
    }

    func testMemoryExtractorSkipsQuestions() {
        XCTAssertTrue(MemoryExtractor.notes(from: "Mi a kedvenc animéd?").isEmpty)
        XCTAssertTrue(MemoryExtractor.notes(from: "Ki vagy te?").isEmpty)
    }

    func testMemoryExtractorSkipsSmallTalk() {
        XCTAssertTrue(MemoryExtractor.notes(from: "Szia, mizu van").isEmpty)
    }

    func testMemoryExtractorClipsLongMessages() {
        let long = "A kedvenc animém a Frieren, " + String(repeating: "nagyon ", count: 60)
        let note = MemoryExtractor.notes(from: long).first ?? ""
        XCTAssertLessThanOrEqual(note.count, MemoryExtractor.maxLength)
    }

    /// Older stores lack keys that newer versions added — they must still load.
    func testSettingsDecodeToleratesOlderStores() throws {
        let legacy = Data(#"{"defaultTier":"void-deep"}"#.utf8)
        let settings = try JSONDecoder().decode(CortexSettings.self, from: legacy)
        XCTAssertEqual(settings.defaultTier, "void-deep")
        XCTAssertTrue(settings.memoryEnabled)
        XCTAssertTrue(settings.streamReplies)
    }
}
