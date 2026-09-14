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

    /// Topic packs (1.1.3). Empty when `packs-v1.json` failed to load — the
    /// core curriculum above is unaffected and no pack is offered.
    let packs: [EconPack]
    /// Non-nil when the packs resource failed to load or validate. Additive:
    /// never empties `topics`/`allCards`.
    let packLoadError: Error?

    /// Every pack card, in pack order. Kept apart from `allCards` (the core
    /// 120) so the core totals the listing states stay pinned.
    var packCards: [EconCard] { packs.flatMap(\.cards) }
    var packTopics: [EconTopic] { packs.flatMap(\.topics) }
    /// Core + packs. Bookmarks and per-card state resolve against this.
    var everyCard: [EconCard] { allCards + packCards }

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
        var loadedPacks: [EconPack] = []
        var failure: Error?
        var packFailure: Error?
        do {
            let catalog = try CurriculumCatalog.loadValidated()
            loadedTopics = catalog.topics.map(Self.viewModel(for:))
            do {
                let packCatalog = try PackCatalog.loadValidated(core: catalog)
                loadedPacks = packCatalog.packs.map { pack in
                    EconPack(id: pack.packID,
                             name: pack.name,
                             productID: pack.productID,
                             icon: pack.icon,
                             summary: pack.summary,
                             topics: pack.topics.map(Self.viewModel(for:)))
                }
            } catch {
                // Additive content: log and serve the core curriculum alone.
                NSLog("[ContentStore] topic packs failed to load: \(error)")
                packFailure = error
            }
        } catch {
            failure = error
        }
        topics = loadedTopics
        allCards = loadedTopics.flatMap(\.cards)
        packs = loadedPacks
        loadError = failure
        packLoadError = packFailure
        loadStates()
    }

    // MARK: Packs

    func pack(id: String) -> EconPack? { packs.first { $0.id == id } }

    /// The pack that sells `topicId`, or `nil` for a core (or unknown) topic.
    func pack(forTopic topicId: String) -> EconPack? {
        packs.first { $0.topics.contains { $0.id == topicId } }
    }

    func isPackTopic(_ topicId: String) -> Bool { pack(forTopic: topicId) != nil }

    /// Fail-closed: a pack topic is readable only when its own pack id is in
    /// `ownedPackIDs`. Unlock All never opens a pack topic (D18); an unknown
    /// topic is never readable.
    private func isPackTopicReadable(_ topicId: String, ownedPackIDs: Set<String>) -> Bool {
        guard let pack = pack(forTopic: topicId) else { return false }
        return ownedPackIDs.contains(pack.id)
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
        everyCard.filter { isBookmarked($0.id) }
    }

    /// Today's set. The pool is the free topics, plus every core topic with
    /// Unlock All, plus the cards of each OWNED pack (never an unowned one).
    func dailySet(count: Int = 8, unlockedAll: Bool = false,
                  ownedPackIDs: Set<String> = []) -> [EconCard] {
        // Only serve cards from free topics unless the user owns Unlock All.
        var pool = unlockedAll
            ? allCards
            : allCards.filter { isTopicFree($0.topicId) }
        pool += packCards.filter { isPackTopicReadable($0.topicId, ownedPackIDs: ownedPackIDs) }
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

    func cards(for topicId: String, unlockedAll: Bool = false,
               ownedPackIDs: Set<String> = []) -> [EconCard] {
        if isPackTopic(topicId) {
            guard isPackTopicReadable(topicId, ownedPackIDs: ownedPackIDs) else { return [] }
            return packCards.filter { $0.topicId == topicId }.shuffled()
        }
        guard unlockedAll || isTopicFree(topicId) else { return [] }
        return allCards.filter { $0.topicId == topicId }.shuffled()
    }

    func topicName(for topicId: String) -> String {
        (topics + packTopics).first(where: { $0.id == topicId })?.name ?? topicId
    }

    func accessState(for topicId: String, unlockedAll: Bool,
                     ownedPackIDs: Set<String> = []) -> EconAccessState {
        if isPackTopic(topicId) {
            return isPackTopicReadable(topicId, ownedPackIDs: ownedPackIDs) ? .unlocked : .locked
        }
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
        return (line: Self.firstSentence(of: body), source: card.source, exampleBody: body)
    }

    /// The first sentence of `body`, inclusive of its terminating period.
    ///
    /// M-4: the naive version took `body.firstIndex(of: ".")`, which is wrong the
    /// moment the sourced prose carries a decimal. "…rose 9.1 percent in June."
    /// would have been sliced to "…rose 9." — a *different number*, rendered on
    /// Home as if it were the card's own figure. The catalog re-sources these
    /// examples, so a decimal appearing here is a matter of when, not whether.
    ///
    /// Two rules, both conservative:
    ///  * a period between two digits is a decimal point, never a terminator;
    ///  * a terminator is followed by whitespace or by nothing at all, so
    ///    periods inside a token ("fred.stlouisfed.org") do not end a sentence.
    ///
    /// Anything unmatched falls back to the whole body, which is the safe
    /// direction: showing too much of the card's own sourced prose, never a
    /// truncated number. (Sentence-medial abbreviations such as "U.S. city" are
    /// out of scope; the editorial policy spells such terms out.)
    static func firstSentence(of body: String) -> String {
        let characters = Array(body)
        for (index, character) in characters.enumerated() where character == "." {
            let previous = index > 0 ? characters[index - 1] : nil
            let next = index + 1 < characters.count ? characters[index + 1] : nil
            if let previous, let next, previous.isNumber, next.isNumber { continue }
            if let next, !next.isWhitespace { continue }
            return String(characters[...index])
        }
        return body
    }
}
