import Foundation

/// Runtime content store for the learning flow.
///
/// Version 1.1 reads the validated 15-topic / 120-card catalog
/// (`curriculum-v1.1.json`) through `CurriculumCatalog.loadValidated()`. Task 4
/// shipped that catalog but deliberately left the runtime on the stale 10-topic
/// `cards.json`; Task 5 completes the switch and `cards.json` is gone. See
/// `CONTENT-DECISIONS.md` D7 for the state-preservation analysis.
@MainActor
final class ContentStore: ObservableObject {
    static let shared = ContentStore()

    let topics: [EconTopic]
    let allCards: [EconCard]

    /// Non-nil when the bundled catalog failed to load or validate. The runtime
    /// then serves nothing (fail closed) and the caller raises
    /// `content_catalog_invalid`. The build-time catalog test fails first, so a
    /// shipped build should never reach this state.
    let loadError: Error?

    /// Per-card state (last seen, bookmark, flip count) is persisted under this
    /// key and dictionary-keyed on `cardID`. Changing either would silently
    /// discard every saved bookmark on update, so both are pinned by test.
    static let cardStatesDefaultsKey = "com.nsantulli.econbyte.cardStates"
    private var stateKey: String { Self.cardStatesDefaultsKey }

    /// Topics that are always free (Inflation + Interest Rates). The other 13 are
    /// covered by the already-approved `com.nsantulli.econbyte.unlockall`
    /// entitlement at no additional charge. Matched by topic id, falling back to
    /// ordinal position.
    static let freeTopicIds: Set<String> = ["inflation", "interest-rates"]
    private static let freeTopicCount = 2

    /// Whether a topic is free regardless of purchase state.
    func isTopicFree(_ topicId: String) -> Bool {
        if Self.freeTopicIds.contains(topicId) { return true }
        if let idx = topics.firstIndex(where: { $0.id == topicId }) {
            return idx < Self.freeTopicCount
        }
        return false
    }

    @Published private(set) var cardStates: [String: CardState] = [:]

    private init() {
        var loadedTopics: [EconTopic] = []
        var failure: Error?
        do {
            let catalog = try CurriculumCatalog.loadValidated()
            loadedTopics = catalog.topics.map(Self.viewModel(for:))
        } catch {
            failure = error
        }
        topics = loadedTopics
        allCards = loadedTopics.flatMap(\.cards)
        loadError = failure
        loadStates()
    }

    /// Maps a validated catalog topic onto the view models the SwiftUI layer
    /// already uses. Identifiers pass through untouched, which is what keeps
    /// saved bookmarks and per-card state resolving across the update.
    private static func viewModel(for topic: CurriculumTopic) -> EconTopic {
        EconTopic(
            id: topic.topicID,
            name: topic.name,
            icon: topic.icon,
            cards: topic.cards.map { card in
                EconCard(id: card.cardID,
                         topicId: topic.topicID,
                         concept: card.title,
                         conceptBody: card.definition,
                         exampleBody: card.example,
                         source: "\(card.source.organization) — \(card.source.documentTitle)",
                         difficulty: card.difficulty.rawValue)
            })
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

    func dailySet(count: Int = 8, unlockedAll: Bool = false) -> [EconCard] {
        // Only serve cards from free topics unless the user owns Unlock All.
        let pool = unlockedAll
            ? allCards
            : allCards.filter { isTopicFree($0.topicId) }
        // Unseen cards first, then least recently seen.
        let sorted = pool.sorted { a, b in
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

    func cards(for topicId: String, unlockedAll: Bool = false) -> [EconCard] {
        guard unlockedAll || isTopicFree(topicId) else { return [] }
        return allCards.filter { $0.topicId == topicId }.shuffled()
    }

    func topicName(for topicId: String) -> String {
        topics.first(where: { $0.id == topicId })?.name ?? topicId
    }

    func accessState(for topicId: String, unlockedAll: Bool) -> EconAccessState {
        if isTopicFree(topicId) { return .free }
        return unlockedAll ? .unlocked : .locked
    }

    /// The id of the card whose example is surfaced as the Home highlight.
    ///
    /// The 1.1.1 implementation string-searched the example prose for the
    /// literal `"A grocery run"`. The 1.1 catalog re-sourced `inf-001` (BLS
    /// free-text → FRED/CPIAUCSL structured source) and the phrase is gone, so
    /// that search returns `nil` on this catalog and the Home line silently
    /// disappears. The dependency is now on the **card id**, which the catalog
    /// pins (`supersedes: econbyte-1.0:inf-001`), not on a sentence fragment.
    static let homeHighlightCardID = "inf-001"

    /// The grocery-inflation highlight surfaced on Home (introduced in 1.1.1,
    /// re-expressed here against the 1.1 catalog).
    ///
    /// The `line` is *extracted verbatim* from card `inf-001`'s example — never
    /// hand-typed into the view — so the figure shown on Home is provably the
    /// card's own sourced content and cannot silently drift from the catalog.
    /// The full `exampleBody` is returned too so a test can prove the displayed
    /// line is contained within it. `nil` only if the card is missing, which on
    /// a validated catalog cannot happen (the catalog test fails first).
    var groceryHighlight: (line: String, source: String, exampleBody: String)? {
        guard let card = allCards.first(where: { $0.id == Self.homeHighlightCardID })
        else { return nil }
        let body = card.exampleBody
        // First sentence, inclusive of its terminating period.
        let line: String
        if let dot = body.firstIndex(of: ".") {
            line = String(body[...dot])
        } else {
            line = body
        }
        return (line: line, source: card.source, exampleBody: body)
    }
}
