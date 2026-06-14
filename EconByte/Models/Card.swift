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

struct CardState: Codable {
    var lastSeen: Date?
    var isBookmarked: Bool
    var flipCount: Int
}
