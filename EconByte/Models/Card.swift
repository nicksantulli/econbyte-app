import Foundation

struct EconTopic: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let icon: String      // SF Symbol name
    var cards: [EconCard]
}

struct EconCard: Codable, Identifiable, Hashable {
    let id: String
    let topicId: String
    let concept: String
    let conceptBody: String
    let exampleBody: String
    let source: String
    let difficulty: String  // "intro" | "intermediate" | "advanced"
}

/// A purchasable topic pack (1.1.3). Plays exactly like four core topics once
/// its product is owned; never part of `ContentStore.topics`.
struct EconPack: Identifiable, Hashable {
    let id: String          // packID
    let name: String
    let productID: String
    let icon: String        // SF Symbol name
    let summary: String
    let topics: [EconTopic]

    var cards: [EconCard] { topics.flatMap(\.cards) }

    /// The cards a locked offer may preview: the first card of each of the
    /// first `PackCatalog.previewCount` topics, so the preview spans the pack.
    var preview: [EconCard] {
        topics.prefix(PackCatalog.previewCount).compactMap { $0.cards.first }
    }
}

struct CardState: Codable {
    var lastSeen: Date?
    var isBookmarked: Bool
    var flipCount: Int
}
