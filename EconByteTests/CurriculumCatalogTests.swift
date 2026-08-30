import XCTest
@testable import EconByte

/// Task 4 gate for the version 1.1 curriculum.
///
/// These tests are the machine validator described in the design spec: they
/// reject missing fields, duplicate identifiers, broken topic counts,
/// unsupported difficulty values, free/paid classification drift, unsourced or
/// stale claims, and any financial-advice framing. Anything they cannot verify
/// fails closed.
final class CurriculumCatalogTests: XCTestCase {

    // MARK: - Fixtures

    /// The ten topics that shipped in version 1.0, in their shipped order.
    /// These identifiers are load-bearing: card state, bookmarks, and the
    /// free-topic entitlement are all keyed on them.
    private static let shippedTopicIDs = [
        "inflation", "interest-rates", "gdp", "supply-demand", "labor-markets",
        "trade-tariffs", "housing-market", "central-banks", "recessions", "debt-deficits",
    ]

    private static let shippedTopicNames = [
        "inflation": "Inflation",
        "interest-rates": "Interest Rates",
        "gdp": "GDP",
        "supply-demand": "Supply & Demand",
        "labor-markets": "Labor Markets",
        "trade-tariffs": "Trade & Tariffs",
        "housing-market": "Housing Market",
        "central-banks": "Central Banks",
        "recessions": "Recessions",
        "debt-deficits": "Debt & Deficits",
    ]

    /// The 80 card identifiers that shipped in version 1.0. Every one of them
    /// must survive into 1.1 so that saved bookmarks and per-card state keep
    /// resolving after the update.
    private static let shippedCardIDPrefixes: [String: String] = [
        "inflation": "inf", "interest-rates": "ir", "gdp": "gdp",
        "supply-demand": "sd", "labor-markets": "lm", "trade-tariffs": "tt",
        "housing-market": "hm", "central-banks": "cb", "recessions": "rec",
        "debt-deficits": "dd",
    ]

    private static var shippedCardIDs: Set<String> {
        var ids = Set<String>()
        for topicID in shippedTopicIDs {
            guard let prefix = shippedCardIDPrefixes[topicID] else { continue }
            for index in 1...8 {
                ids.insert(String(format: "%@-%03d", prefix, index))
            }
        }
        return ids
    }

    /// Topics added in 1.1, in the order the spec lists them.
    private static let newTopicIDs = [
        "exchange-rates", "consumer-spending", "taxes", "fiscal-policy", "economic-indicators",
    ]

    /// Publishers whose pages are acceptable as a primary source for this app.
    private static let approvedSourceHosts: Set<String> = [
        "www.federalreserve.gov", "www.federalreservehistory.org",
        "www.newyorkfed.org", "www.philadelphiafed.org", "fred.stlouisfed.org",
        "www.bls.gov", "www.bea.gov", "www.census.gov",
        "fiscaldata.treasury.gov", "home.treasury.gov", "www.treasurydirect.gov",
        "www.irs.gov", "www.ssa.gov", "www.fdic.gov",
        "www.nber.org", "www.conference-board.org", "www.freddiemac.com",
        "www.wto.org", "ustr.gov", "data.worldbank.org", "www.worldbank.org",
        "www.ecb.europa.eu", "www.boj.or.jp", "www.bis.org",
        "www.oecd.org", "www.bundesbank.de",
    ]

    private static let canonicalDisclaimer =
        "Educational content only. EconByte does not provide financial, investment, or tax advice."

    /// Wording that would make a card stale the moment it shipped. The design
    /// spec bans "currently", "today" and equivalents outright.
    private static let staleTemporalWords = [
        "currently", "today", "nowadays", "recently", "at present",
        "these days", "this year", "last year", "right now", "as of now",
    ]

    /// Financial-advice framing. None of this belongs in an educational card.
    private static let prohibitedAdvicePhrases = [
        "you should buy", "you should sell", "you should invest",
        "should buy", "should sell", "invest in", "buy now", "sell now",
        "guaranteed return", "risk-free return", "financial advice",
        "investment advice", "we recommend", "best investment",
        "will outperform", "get rich", "hot stock", "price target",
        "portfolio allocation", "beat the market", "sure thing", "act fast",
    ]

    private func loadCatalog() throws -> Curriculum {
        try CurriculumCatalog.loadValidated()
    }

    // MARK: - Totals

    func testCatalogLoadsWithExpectedTotals() throws {
        let catalog = try loadCatalog()
        XCTAssertEqual(catalog.schemaVersion, 1)
        XCTAssertEqual(catalog.catalogVersion, "1.1")
        XCTAssertEqual(catalog.topics.count, 15, "version 1.1 ships exactly 15 topics")
        XCTAssertEqual(catalog.allCards.count, 120, "version 1.1 ships exactly 120 cards")
        for topic in catalog.topics {
            XCTAssertEqual(topic.cards.count, 8,
                           "topic \(topic.topicID) must carry exactly 8 cards")
        }
    }

    // MARK: - Identifier stability

    func testCardIdentifiersAreUniqueAndNonEmpty() throws {
        let catalog = try loadCatalog()
        let ids = catalog.allCards.map(\.cardID)
        XCTAssertEqual(Set(ids).count, ids.count, "card identifiers must be unique")
        XCTAssertEqual(ids.count, 120)
        for id in ids {
            XCTAssertFalse(id.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        let topicIDs = catalog.topics.map(\.topicID)
        XCTAssertEqual(Set(topicIDs).count, topicIDs.count, "topic identifiers must be unique")
    }

    func testShippedIdentifiersArePreserved() throws {
        let catalog = try loadCatalog()
        let cardIDs = Set(catalog.allCards.map(\.cardID))
        let missing = Self.shippedCardIDs.subtracting(cardIDs).sorted()
        XCTAssertTrue(missing.isEmpty,
                      "version 1.0 card identifiers must survive into 1.1; missing: \(missing)")

        let topicIDs = Set(catalog.topics.map(\.topicID))
        let missingTopics = Set(Self.shippedTopicIDs).subtracting(topicIDs).sorted()
        XCTAssertTrue(missingTopics.isEmpty,
                      "version 1.0 topic identifiers must survive into 1.1; missing: \(missingTopics)")

        for topic in catalog.topics where Self.shippedTopicIDs.contains(topic.topicID) {
            XCTAssertEqual(topic.name, Self.shippedTopicNames[topic.topicID],
                           "shipped display name for \(topic.topicID) must not drift")
            XCTAssertFalse(topic.icon.isEmpty, "topic \(topic.topicID) needs an SF Symbol")
        }
    }

    func testResourcedCardsCarrySupersessionReferences() throws {
        let catalog = try loadCatalog()
        for card in catalog.allCards {
            if Self.shippedCardIDs.contains(card.cardID) {
                XCTAssertEqual(card.supersedes, "econbyte-1.0:\(card.cardID)",
                               "\(card.cardID) re-sources a 1.0 claim and must say so")
            } else {
                XCTAssertNil(card.supersedes,
                             "\(card.cardID) is new in 1.1 and supersedes nothing")
            }
        }
        let superseding = catalog.allCards.filter { $0.supersedes != nil }
        XCTAssertEqual(superseding.count, 80)
    }

    // MARK: - Ordering

    func testTopicOrderIsExplicitAndStable() throws {
        let catalog = try loadCatalog()
        for (index, topic) in catalog.topics.enumerated() {
            XCTAssertEqual(topic.order, index + 1,
                           "topic \(topic.topicID) order must match its position")
        }
        let ordered = catalog.topics.map(\.topicID)
        XCTAssertEqual(Array(ordered.prefix(10)), Self.shippedTopicIDs,
                       "shipped topics keep their 1.0 order")
        XCTAssertEqual(Array(ordered.suffix(5)), Self.newTopicIDs,
                       "new topics append in the order the spec lists them")
    }

    // MARK: - Access map

    func testAccessMapIsTwoFreeAndThirteenPaid() throws {
        let catalog = try loadCatalog()
        let free = catalog.topics.filter(\.isFree)
        let paid = catalog.topics.filter { !$0.isFree }
        XCTAssertEqual(free.count, 2, "exactly two topics stay free")
        XCTAssertEqual(paid.count, 13, "the other thirteen sit behind the existing unlock")
        XCTAssertEqual(free.map(\.topicID), CurriculumCatalog.expectedFreeTopicIDs,
                       "Inflation and Interest Rates are the free topics")
        XCTAssertEqual(catalog.freeTopicIDs, ["inflation", "interest-rates"])
        // The free topics must also be the first two, so the free daily pool is
        // the head of the ordered catalog.
        XCTAssertEqual(free.map(\.order), [1, 2])
    }

    @MainActor
    func testFreeTopicsMatchTheShippedEntitlementModel() throws {
        let catalog = try loadCatalog()
        XCTAssertEqual(Set(catalog.freeTopicIDs), ContentStore.freeTopicIds,
                       "the 1.1 access map must not move the shipped free-tier boundary")
    }

    // MARK: - Sources

    func testEveryCardCitesAnApprovedCanonicalSource() throws {
        let catalog = try loadCatalog()
        for card in catalog.allCards {
            let source = card.source
            XCTAssertFalse(source.organization.trimmingCharacters(in: .whitespaces).isEmpty,
                           "\(card.cardID) needs a named publisher")
            XCTAssertFalse(source.documentTitle.trimmingCharacters(in: .whitespaces).isEmpty,
                           "\(card.cardID) needs a document title")

            guard let url = URL(string: source.url) else {
                XCTFail("\(card.cardID) has an unparseable source URL: \(source.url)")
                continue
            }
            XCTAssertEqual(url.scheme, "https", "\(card.cardID) must cite an https URL")
            let host = url.host ?? ""
            XCTAssertTrue(Self.approvedSourceHosts.contains(host),
                          "\(card.cardID) cites \(host), which is not an approved primary source")
            XCTAssertNil(url.query, "\(card.cardID) must cite a stable URL with no query string")
            XCTAssertNil(url.fragment, "\(card.cardID) must cite a stable URL with no fragment")
        }
    }

    func testSourceDatesAreWellFormedAndNotInTheFuture() throws {
        let catalog = try loadCatalog()
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"

        guard let verifiedOn = formatter.date(from: catalog.verifiedOn) else {
            return XCTFail("catalog verifiedOn is not an ISO date: \(catalog.verifiedOn)")
        }

        for card in catalog.allCards {
            let source = card.source
            XCTAssertEqual(source.verificationDate, catalog.verifiedOn,
                           "\(card.cardID) must be verified in the same pass as the catalog")
            guard let published = formatter.date(from: source.publicationDate) else {
                XCTFail("\(card.cardID) publicationDate is not an ISO date: \(source.publicationDate)")
                continue
            }
            XCTAssertLessThanOrEqual(published, verifiedOn,
                                     "\(card.cardID) cannot cite a document published after verification")

            if let claim = card.claim {
                XCTAssertEqual(claim.retrievalDate, catalog.verifiedOn,
                               "\(card.cardID) numeric claim must record when it was retrieved")
                XCTAssertFalse(claim.units.isEmpty, "\(card.cardID) claim needs units")
                XCTAssertFalse(claim.geography.isEmpty, "\(card.cardID) claim needs a geography")
                XCTAssertFalse(claim.observationPeriod.isEmpty,
                               "\(card.cardID) claim needs an observation period")
            }
        }
    }

    // MARK: - Claim freshness

    func testNoCardUsesStaleTemporalWording() throws {
        let catalog = try loadCatalog()
        for card in catalog.allCards {
            let prose = "\(card.title) \(card.definition) \(card.example)".lowercased()
            for word in Self.staleTemporalWords {
                XCTAssertFalse(prose.contains(word),
                               "\(card.cardID) uses \"\(word)\", which goes stale on the shelf")
            }
        }
    }

    func testNoCardReferencesAYearAfterVerification() throws {
        let catalog = try loadCatalog()
        let verificationYear = Int(catalog.verifiedOn.prefix(4)) ?? 0
        XCTAssertGreaterThan(verificationYear, 2000)

        let detector = try NSRegularExpression(pattern: "\\b(1[89]\\d{2}|20\\d{2})\\b")
        for card in catalog.allCards {
            let prose = "\(card.title) \(card.definition) \(card.example)"
            let range = NSRange(prose.startIndex..., in: prose)
            for match in detector.matches(in: prose, range: range) {
                guard let r = Range(match.range, in: prose),
                      let year = Int(prose[r]) else { continue }
                XCTAssertLessThanOrEqual(year, verificationYear,
                                         "\(card.cardID) cites year \(year), after verification")
            }
        }
    }

    // MARK: - Question / explanation consistency

    func testCardProseIsCompleteAndInternallyConsistent() throws {
        let catalog = try loadCatalog()
        for topic in catalog.topics {
            XCTAssertFalse(topic.summary.trimmingCharacters(in: .whitespaces).isEmpty,
                           "topic \(topic.topicID) needs a summary")
            for card in topic.cards {
                XCTAssertEqual(card.topicID, topic.topicID,
                               "\(card.cardID) is filed under the wrong topic")
                XCTAssertFalse(card.title.trimmingCharacters(in: .whitespaces).isEmpty)
                XCTAssertGreaterThanOrEqual(card.definition.count, 60,
                                            "\(card.cardID) definition is too thin to teach anything")
                XCTAssertGreaterThanOrEqual(card.example.count, 40,
                                            "\(card.cardID) example is too thin to illustrate anything")
                XCTAssertNotEqual(card.definition, card.example,
                                  "\(card.cardID) example must add something the definition did not")
                XCTAssertFalse(card.example.localizedCaseInsensitiveContains(card.definition),
                               "\(card.cardID) example merely restates the definition")
                XCTAssertEqual(card.disclaimer, Self.canonicalDisclaimer,
                               "\(card.cardID) must carry the education-only disclaimer verbatim")
                XCTAssertEqual(card.editorial.status, "verified",
                               "\(card.cardID) has not cleared editorial review")
                XCTAssertFalse(card.editorial.reviewer.isEmpty,
                               "\(card.cardID) needs a named reviewer")
            }
        }
    }

    func testQuantitativeClaimsAreDeclaredAndSourced() throws {
        let catalog = try loadCatalog()
        // A magnitude in the prose is a factual assertion, and every factual
        // assertion needs a declared claim block with units and a period.
        let magnitude = try NSRegularExpression(
            pattern: "(\\$\\s?\\d)|(\\d[\\d,\\.]*\\s*(percent|trillion|billion|million))",
            options: [.caseInsensitive])
        let anyQuantity = try NSRegularExpression(
            pattern: "\\d|\\b(one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\\b",
            options: [.caseInsensitive])

        for card in catalog.allCards {
            let prose = "\(card.title) \(card.definition) \(card.example)"
            let range = NSRange(prose.startIndex..., in: prose)
            let hasMagnitude = magnitude.firstMatch(in: prose, range: range) != nil
            if hasMagnitude {
                XCTAssertNotNil(card.claim,
                                "\(card.cardID) states a magnitude but declares no sourced claim")
            }
            if card.claim != nil {
                let exampleRange = NSRange(card.example.startIndex..., in: card.example)
                XCTAssertNotNil(anyQuantity.firstMatch(in: card.example, range: exampleRange),
                                "\(card.cardID) declares a claim its example never makes")
            }
        }
    }

    // MARK: - Prohibited financial advice

    func testNoCardGivesFinancialAdvice() throws {
        let catalog = try loadCatalog()
        for card in catalog.allCards {
            // The disclaimer is deliberately excluded: it is the one place the
            // words "investment advice" are supposed to appear.
            let prose = "\(card.title) \(card.definition) \(card.example)".lowercased()
            for phrase in Self.prohibitedAdvicePhrases {
                XCTAssertFalse(prose.contains(phrase),
                               "\(card.cardID) contains prohibited advice framing: \"\(phrase)\"")
            }
        }
    }

    func testCatalogDeclaresItsEditorialPolicyAndDisclaimer() throws {
        let catalog = try loadCatalog()
        XCTAssertEqual(catalog.disclaimer, Self.canonicalDisclaimer)
        XCTAssertGreaterThan(catalog.editorialPolicy.count, 80,
                             "the catalog must state how its claims were verified")
    }

    // MARK: - Difficulty

    func testDifficultyValuesAreSupportedAndMixed() throws {
        let catalog = try loadCatalog()
        var counts: [CurriculumDifficulty: Int] = [:]
        for card in catalog.allCards {
            counts[card.difficulty, default: 0] += 1
        }
        XCTAssertGreaterThan(counts[.intro] ?? 0, 0, "every level needs an on-ramp")
        XCTAssertGreaterThan(counts[.intermediate] ?? 0, 0)
        XCTAssertEqual(counts.values.reduce(0, +), 120)
        for topic in catalog.topics {
            XCTAssertTrue(topic.cards.contains { $0.difficulty == .intro },
                          "topic \(topic.topicID) needs at least one intro card")
        }
    }
}
