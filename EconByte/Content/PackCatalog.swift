import Foundation

// MARK: - Topic packs (1.1.3)
//
// `Resources/packs-v1.json` carries the purchasable topic packs: two packs of
// four topics × eight cards, in EXACTLY the core card schema (`CurriculumCard`,
// `CurriculumTopic`) with `access: "pack"`. Each pack names its own
// non-consumable product id; a pack's topics are readable only behind a
// verified StoreKit entitlement for that id (`PurchaseManager`), and — by
// decision D18 — `com.nsantulli.econbyte.unlockall` does NOT include them.
//
// Same contract as `CurriculumCatalog`: decoding and validation fail closed,
// and the validator runs against the loaded core catalog so a pack can never
// reuse a core topic or card identifier (bookmarks and per-card state are keyed
// on `cardID`). Packs are additive: if this resource is defective the core
// curriculum still serves and no pack is offered — the content tests fail
// first, so a shipped build should never reach that state.

public struct CurriculumPack: Codable, Hashable, Identifiable {
    public let packID: String
    public let name: String
    /// The App Store Connect non-consumable that unlocks this pack.
    public let productID: String
    /// SF Symbol name.
    public let icon: String
    public let summary: String
    public let topics: [CurriculumTopic]

    public var id: String { packID }
    public var allCards: [CurriculumCard] { topics.flatMap(\.cards) }
}

public struct PackCurriculum: Codable, Hashable {
    public let schemaVersion: Int
    public let catalogVersion: String
    public let verifiedOn: String
    public let disclaimer: String
    public let editorialPolicy: String
    public let packs: [CurriculumPack]

    public var allTopics: [CurriculumTopic] { packs.flatMap(\.topics) }
    public var allCards: [CurriculumCard] { allTopics.flatMap(\.cards) }

    public func pack(withID id: String) -> CurriculumPack? {
        packs.first { $0.packID == id }
    }

    public func pack(containingTopic topicID: String) -> CurriculumPack? {
        packs.first { $0.topics.contains { $0.topicID == topicID } }
    }
}

public enum PackCatalog {

    public static let resourceName = "packs-v1"
    public static let expectedPackCount = 2
    public static let expectedTopicsPerPack = 4
    public static let expectedCardsPerTopic = 8
    public static var expectedCardCount: Int {
        expectedPackCount * expectedTopicsPerPack * expectedCardsPerTopic
    }
    /// A locked offer previews this many cards.
    public static let previewCount = 3

    /// Ordered pack contract: content id → App Store Connect product id
    /// (both created 2026-09-14, Phase 2 lane).
    public static let expectedPacks: [(packID: String, productID: String)] = [
        ("markets", "com.nsantulli.econbyte.pack.markets"),
        ("personal", "com.nsantulli.econbyte.pack.personal"),
    ]

    public static var expectedProductIDs: [String] { expectedPacks.map(\.productID) }

    /// Loads the bundled packs and fails closed on any structural defect or any
    /// collision with the core catalog.
    public static func loadValidated(in bundle: Bundle = .curriculumBundle,
                                     core: Curriculum) throws -> PackCurriculum {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json") else {
            throw CurriculumError.resourceMissing("\(resourceName).json")
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw CurriculumError.resourceMissing("\(resourceName).json (\(error))")
        }
        let packs: PackCurriculum
        do {
            packs = try JSONDecoder().decode(PackCurriculum.self, from: data)
        } catch {
            throw CurriculumError.decodingFailed(String(describing: error))
        }
        try validate(packs, core: core)
        return packs
    }

    /// Structural validation. Editorial validation (source hosts, claim
    /// freshness, prohibited framing) lives in `EconByteTests` exactly as it
    /// does for the core catalog.
    static func validate(_ catalog: PackCurriculum, core: Curriculum) throws {
        func fail(_ reason: String) throws -> Never {
            throw CurriculumError.validationFailed(reason)
        }

        guard catalog.schemaVersion == 1 else {
            try fail("unsupported packs schemaVersion \(catalog.schemaVersion)")
        }
        guard catalog.disclaimer == core.disclaimer else {
            try fail("packs disclaimer differs from the core catalog")
        }
        guard !catalog.editorialPolicy.isEmpty, !catalog.verifiedOn.isEmpty else {
            try fail("packs catalog is missing its editorial policy or verification date")
        }
        guard catalog.packs.count == expectedPackCount else {
            try fail("expected \(expectedPackCount) packs, found \(catalog.packs.count)")
        }

        var seenTopicIDs = Set(core.topics.map(\.topicID))
        var seenCardIDs = Set(core.allCards.map(\.cardID))
        var seenProductIDs = Set<String>()

        for (pack, expected) in zip(catalog.packs, expectedPacks) {
            guard pack.packID == expected.packID, pack.productID == expected.productID else {
                try fail("unexpected pack \(pack.packID)/\(pack.productID)")
            }
            guard seenProductIDs.insert(pack.productID).inserted else {
                try fail("duplicate pack product id \(pack.productID)")
            }
            guard !pack.name.isEmpty, !pack.icon.isEmpty, !pack.summary.isEmpty else {
                try fail("pack \(pack.packID) is missing a name, icon, or summary")
            }
            guard pack.topics.count == expectedTopicsPerPack else {
                try fail("pack \(pack.packID) carries \(pack.topics.count) topics, expected \(expectedTopicsPerPack)")
            }
            for (index, topic) in pack.topics.enumerated() {
                guard !topic.topicID.isEmpty, !topic.name.isEmpty, !topic.summary.isEmpty, !topic.icon.isEmpty else {
                    try fail("pack \(pack.packID) topic at position \(index) is missing an identifier, name, icon, or summary")
                }
                guard seenTopicIDs.insert(topic.topicID).inserted else {
                    try fail("topic identifier \(topic.topicID) collides with the core catalog or another pack")
                }
                guard topic.access == .pack else {
                    try fail("pack topic \(topic.topicID) must declare access pack, not \(topic.access.rawValue)")
                }
                guard topic.order == index + 1 else {
                    try fail("pack topic \(topic.topicID) declares order \(topic.order) at position \(index + 1)")
                }
                guard topic.cards.count == expectedCardsPerTopic else {
                    try fail("pack topic \(topic.topicID) carries \(topic.cards.count) cards, expected \(expectedCardsPerTopic)")
                }
                for card in topic.cards {
                    guard !card.cardID.isEmpty else {
                        try fail("pack topic \(topic.topicID) contains a card with no identifier")
                    }
                    guard seenCardIDs.insert(card.cardID).inserted else {
                        try fail("card identifier \(card.cardID) collides with the core catalog or another pack")
                    }
                    guard card.topicID == topic.topicID else {
                        try fail("card \(card.cardID) declares topic \(card.topicID) inside \(topic.topicID)")
                    }
                    guard card.supersedes == nil, card.supersedesNote == nil else {
                        try fail("pack card \(card.cardID) is new and cannot supersede a 1.0 card")
                    }
                    guard !card.title.isEmpty, !card.definition.isEmpty,
                          !card.example.isEmpty, !card.disclaimer.isEmpty else {
                        try fail("card \(card.cardID) is missing required prose")
                    }
                    guard card.disclaimer == core.disclaimer else {
                        try fail("card \(card.cardID) does not carry the canonical disclaimer")
                    }
                    guard !card.source.url.isEmpty, !card.source.organization.isEmpty,
                          !card.source.documentTitle.isEmpty else {
                        try fail("card \(card.cardID) is missing source attribution")
                    }
                }
            }
        }

        guard catalog.allCards.count == expectedCardCount else {
            try fail("expected \(expectedCardCount) pack cards, found \(catalog.allCards.count)")
        }
    }
}
