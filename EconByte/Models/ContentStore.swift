import Foundation

@MainActor
final class ContentStore: ObservableObject {
    static let shared = ContentStore()

    let topics: [EconTopic]
    let allCards: [EconCard]
    private let stateKey = "com.nsantulli.econbyte.cardStates"

    @Published private(set) var cardStates: [String: CardState] = [:]

    private init() {
        guard let url = Bundle.main.url(forResource: "cards", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([EconTopic].self, from: data)
        else {
            topics = []
            allCards = []
            return
        }
        // inject topicId into cards
        var enriched: [EconTopic] = []
        var flat: [EconCard] = []
        for var topic in decoded {
            topic.cards = topic.cards.map { card in
                EconCard(id: card.id, topicId: topic.id, concept: card.concept,
                         conceptBody: card.conceptBody, exampleBody: card.exampleBody,
                         source: card.source, difficulty: card.difficulty)
            }
            enriched.append(topic)
            flat.append(contentsOf: topic.cards)
        }
        topics = enriched
        allCards = flat
        loadStates()
    }

    private func loadStates() {
        if let data = UserDefaults.standard.data(forKey: stateKey),
           let decoded = try? JSONDecoder().decode([String: CardState].self, from: data) {
            cardStates = decoded
        }
    }

    private func saveStates() {
        if let data = try? JSONEncoder().encode(cardStates) {
            UserDefaults.standard.set(data, forKey: stateKey)
        }
    }

    func markSeen(_ cardId: String) {
        var s = cardStates[cardId] ?? CardState(lastSeen: nil, isBookmarked: false, flipCount: 0)
        s.lastSeen = Date()
        cardStates[cardId] = s
        saveStates()
    }

    func markFlipped(_ cardId: String) {
        var s = cardStates[cardId] ?? CardState(lastSeen: nil, isBookmarked: false, flipCount: 0)
        s.flipCount += 1
        cardStates[cardId] = s
        saveStates()
    }

    func toggleBookmark(_ cardId: String) {
        var s = cardStates[cardId] ?? CardState(lastSeen: nil, isBookmarked: false, flipCount: 0)
        s.isBookmarked.toggle()
        cardStates[cardId] = s
        saveStates()
    }

    func isBookmarked(_ cardId: String) -> Bool {
        cardStates[cardId]?.isBookmarked ?? false
    }

    var bookmarkedCards: [EconCard] {
        allCards.filter { isBookmarked($0.id) }
    }

    func dailySet(count: Int = 8) -> [EconCard] {
        // Unseen cards first, then least recently seen
        let sorted = allCards.sorted { a, b in
            let sa = cardStates[a.id]?.lastSeen
            let sb = cardStates[b.id]?.lastSeen
            switch (sa, sb) {
            case (nil, nil): return false
            case (nil, _):   return true
            case (_, nil):   return false
            default:         return sa! < sb!
            }
        }
        return Array(sorted.prefix(count))
    }

    func cards(for topicId: String) -> [EconCard] {
        allCards.filter { $0.topicId == topicId }.shuffled()
    }
}
