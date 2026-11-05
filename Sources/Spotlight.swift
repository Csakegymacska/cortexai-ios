import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

/// A beszélgetések bekerülnek a rendszer keresőjébe (Spotlight).
///
/// Nem küldünk semmit sehova: a CoreSpotlight helyben indexel, a találat koppintására az app
/// nyílik meg a megfelelő beszélgetéssel. Az index a mentéssel együtt frissül, késleltetve,
/// hogy folyó válasz közben ne dolgozzon feleslegesen.
@MainActor
enum Spotlight {
    private nonisolated static let domain = "hu.cortex.ai.conversations"
    private static var pendingTask: Task<Void, Never>?
    private static var lastSignature = ""

    /// A rendszer ezt a típust küldi, amikor egy Spotlight-találatra koppintanak.
    nonisolated static let activityType = CSSearchableItemActionType

    static func schedule(_ conversations: [Conversation]) {
        let signature = "\(conversations.count)|\(conversations.reduce(0) { $0 + $1.messages.count })|"
            + (conversations.first?.updatedAt.timeIntervalSince1970.description ?? "")
        guard signature != lastSignature else { return }
        lastSignature = signature

        pendingTask?.cancel()
        let copy = conversations.prefix(60).map { conversation in
            Indexed(
                id: conversation.id.uuidString,
                title: conversation.title,
                text: conversation.messages.suffix(6).map(\.text).joined(separator: " "),
                date: conversation.updatedAt
            )
        }
        pendingTask = Task.detached(priority: .background) { [copy] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            Spotlight.index(copy)
        }
    }

    private struct Indexed: Sendable {
        let id: String
        let title: String
        let text: String
        let date: Date
    }

    nonisolated private static func index(_ rows: [Indexed]) {
        let items: [CSSearchableItem] = rows.map { row in
            let attributes = CSSearchableItemAttributeSet(contentType: .text)
            attributes.title = row.title
            attributes.contentDescription = String(row.text.prefix(220))
            attributes.keywords = ["Cortex", "chat", "beszélgetés"]
            return CSSearchableItem(
                uniqueIdentifier: row.id,
                domainIdentifier: domain,
                attributeSet: attributes
            )
        }
        let index = CSSearchableIndex(name: "cortexai", protectionClass: .completeUntilFirstUserAuthentication)
        index.deleteSearchableItems(withDomainIdentifiers: [domain]) { _ in
            guard !items.isEmpty else { return }
            index.indexSearchableItems(items) { _ in
                // Ha az indexelés nem megy (pl. korlátozott mód), az app működik tovább.
            }
        }
    }

    /// A Spotlight-találatból jött azonosító.
    nonisolated static func conversationID(from activity: NSUserActivity) -> UUID? {
        guard activity.activityType == CSSearchableItemActionType,
              let raw = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return nil }
        return UUID(uuidString: raw)
    }
}
