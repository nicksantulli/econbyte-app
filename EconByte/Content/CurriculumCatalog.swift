import Foundation

// MARK: - Model

/// Access classification for a topic. Version 1.1 ships two free topics; the
/// other thirteen are covered by the already-approved
/// `com.nsantulli.econbyte.unlockall` non-consumable at no additional charge.
public enum CurriculumAccess: String, Codable, Hashable {
    case free
    case paid
    /// A topic sold inside a topic pack (1.1.3, `PackCatalog`). Never appears
    /// in the core catalog; unlocked only by the pack's own product id.
    case pack
}

public enum CurriculumDifficulty: String, Codable, Hashable {
    case intro
    case intermediate
    case advanced
}

/// How the `publicationDate` on a source was established. Continuously updated
/// publisher pages carry no publication date of their own, so the field records
/// the date the page was observed and this enum says so explicitly rather than
/// implying a publication event that did not happen.
public enum CurriculumDatePrecision: String, Codable, Hashable {
    case observedLastModified = "observed-last-modified"
    case statedOnPage = "stated-on-page"
    case observedOnVerificationDate = "observed-on-verification-date"
}

public struct CurriculumSource: Codable, Hashable {
    public let organization: String
    public let documentTitle: String
    public let url: String
    public let publicationDate: String
    public let datePrecision: CurriculumDatePrecision
    public let verificationDate: String
}

/// Whether a claim reports something measured or something illustrated.
/// An `observation` is a dated reading a reader can reproduce from the cited
/// source; an `illustration` is worked arithmetic that teaches the mechanism
/// and is not a measurement of anything. Conflating the two is how a textbook
/// example turns into a fake statistic.
public enum CurriculumClaimKind: String, Codable, Hashable {
    case observation
    case illustration
}

/// Present only on cards whose prose carries a quantitative claim.
public struct CurriculumClaim: Codable, Hashable {
    public let units: String
    public let geography: String
    public let claimKind: CurriculumClaimKind
    public let observationPeriod: String
    public let retrievalDate: String
}

public struct CurriculumEditorial: Codable, Hashable {
    public let status: String
    public let reviewer: String
}

public struct CurriculumCard: Codable, Hashable, Identifiable {
    public let cardID: String
    public let topicID: String
    public let title: String
    public let definition: String
    public let example: String
    public let disclaimer: String
    public let difficulty: CurriculumDifficulty
    public let source: CurriculumSource
    public let editorial: CurriculumEditorial
    public let claim: CurriculumClaim?
    /// Reference to the 1.0 card this entry re-sources and replaces, if any.
    public let supersedes: String?
    /// Required only when a re-sourced card no longer teaches the same concept
    /// its 1.0 identifier taught. Bookmarks and per-card state are keyed on
    /// `cardID`, so a silent concept swap would send a saved bookmark to a
    /// different lesson; this field forces any such change to be declared.
    public let supersedesNote: String?

    public var id: String { cardID }
}

public struct CurriculumTopic: Codable, Hashable, Identifiable {
    public let topicID: String
    public let name: String
    /// SF Symbol name.
    public let icon: String
    public let order: Int
    public let access: CurriculumAccess
    public let summary: String
    public let cards: [CurriculumCard]

    public var id: String { topicID }
    public var isFree: Bool { access == .free }
}

public struct Curriculum: Codable, Hashable {
    public let schemaVersion: Int
    public let catalogVersion: String
    public let verifiedOn: String
    public let disclaimer: String
    public let editorialPolicy: String
    public let topics: [CurriculumTopic]

    public var allCards: [CurriculumCard] { topics.flatMap(\.cards) }

    public func topic(withID id: String) -> CurriculumTopic? {
        topics.first { $0.topicID == id }
    }

    /// Topic IDs the user can read without the Unlock All Topics entitlement.
    public var freeTopicIDs: [String] {
        topics.filter(\.isFree).map(\.topicID)
    }
}

// MARK: - Errors

public enum CurriculumError: Error, CustomStringConvertible {
    case resourceMissing(String)
    case decodingFailed(String)
    case validationFailed(String)

    public var description: String {
        switch self {
        case .resourceMissing(let name):
            return "bundled curriculum resource \(name) is missing"
        case .decodingFailed(let reason):
            return "curriculum could not be decoded: \(reason)"
        case .validationFailed(let reason):
            return "curriculum failed validation: \(reason)"
        }
    }
}

// MARK: - Loader

public enum CurriculumCatalog {

    public static let resourceName = "curriculum-v1.1"
    public static let expectedTopicCount = 15
    /// 1.1 shipped 8 cards per topic (120); 1.1.4 Phase 13 (content growth)
    /// grows every topic to 12 (180). New cards continue each topic's id
    /// sequence (`inf-009`…); no shipped id is renumbered.
    public static let expectedCardCount = 180
    public static let expectedCardsPerTopic = 12
    public static let expectedFreeTopicIDs = ["inflation", "interest-rates"]

    /// Loads the bundled catalog and fails closed on any structural defect.
    ///
    /// Task 4 delivers the catalog, its validator, and its tests only. The
    /// runtime still reads `cards.json` through `ContentStore`; wiring the
    /// views to this catalog is Task 5's job, per the implementation plan.
    public static func loadValidated(in bundle: Bundle = .curriculumBundle) throws -> Curriculum {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json") else {
            throw CurriculumError.resourceMissing("\(resourceName).json")
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw CurriculumError.resourceMissing("\(resourceName).json (\(error))")
        }

        let catalog: Curriculum
        do {
            catalog = try JSONDecoder().decode(Curriculum.self, from: data)
        } catch {
            // A missing field, an unknown difficulty value, or an unknown date
            // precision all land here. Fail closed rather than degrade.
            throw CurriculumError.decodingFailed(String(describing: error))
        }

        try validate(catalog)
        return catalog
    }

    /// Structural validation. Editorial validation (source resolvability, claim
    /// freshness, prohibited framing) lives in `EconByteTests` and runs at build
    /// time; this check is the runtime backstop that keeps a malformed catalog
    /// from ever reaching the learning flow.
    static func validate(_ catalog: Curriculum) throws {
        func fail(_ reason: String) throws -> Never {
            throw CurriculumError.validationFailed(reason)
        }

        guard catalog.schemaVersion == 1 else {
            try fail("unsupported schemaVersion \(catalog.schemaVersion)")
        }
        guard catalog.topics.count == expectedTopicCount else {
            try fail("expected \(expectedTopicCount) topics, found \(catalog.topics.count)")
        }

        var seenTopicIDs = Set<String>()
        var seenCardIDs = Set<String>()

        for (index, topic) in catalog.topics.enumerated() {
            guard !topic.topicID.isEmpty, !topic.name.isEmpty, !topic.summary.isEmpty else {
                try fail("topic at position \(index) is missing an identifier, name, or summary")
            }
            guard seenTopicIDs.insert(topic.topicID).inserted else {
                try fail("duplicate topic identifier \(topic.topicID)")
            }
            guard topic.order == index + 1 else {
                try fail("topic \(topic.topicID) declares order \(topic.order) at position \(index + 1)")
            }
            guard topic.cards.count == expectedCardsPerTopic else {
                try fail("topic \(topic.topicID) carries \(topic.cards.count) cards, expected \(expectedCardsPerTopic)")
            }
            for card in topic.cards {
                guard !card.cardID.isEmpty else {
                    try fail("topic \(topic.topicID) contains a card with no identifier")
                }
                guard seenCardIDs.insert(card.cardID).inserted else {
                    try fail("duplicate card identifier \(card.cardID)")
                }
                guard card.topicID == topic.topicID else {
                    try fail("card \(card.cardID) declares topic \(card.topicID) inside \(topic.topicID)")
                }
                guard !card.title.isEmpty, !card.definition.isEmpty,
                      !card.example.isEmpty, !card.disclaimer.isEmpty else {
                    try fail("card \(card.cardID) is missing required prose")
                }
                guard !card.source.url.isEmpty, !card.source.organization.isEmpty,
                      !card.source.documentTitle.isEmpty else {
                    try fail("card \(card.cardID) is missing source attribution")
                }
            }
        }

        guard seenCardIDs.count == expectedCardCount else {
            try fail("expected \(expectedCardCount) cards, found \(seenCardIDs.count)")
        }

        let free = catalog.topics.filter(\.isFree).map(\.topicID)
        guard free == expectedFreeTopicIDs else {
            try fail("free-topic classification drifted: \(free)")
        }
    }
}

extension Bundle {
    private final class BundleToken {}

    /// The bundle that carries the curriculum resource. Resolves to the app
    /// bundle both in the app and in a host-application unit test run.
    public static var curriculumBundle: Bundle {
        Bundle(for: BundleToken.self)
    }
}
