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

    /// Pinned from the shipped 1.0 catalog at commit 42df3dc
    /// (`EconByte/Content/cards.json`): the concept each card identifier
    /// taught, plus tokens that concept cannot be expressed without.
    private static let legacyConcepts: [String: (concept: String, tokens: [String])] = [
        "inf-001": ("What is Inflation?", ["purchasing power", "prices"]),
        "inf-002": ("The Consumer Price Index (CPI)", ["consumer price index", "basket"]),
        "inf-003": ("Core vs. Headline Inflation", ["core", "headline"]),
        "inf-004": ("Demand-Pull Inflation", ["demand-pull"]),
        "inf-005": ("Cost-Push Inflation", ["cost-push"]),
        "inf-006": ("Hyperinflation", ["hyperinflation"]),
        "inf-007": ("Deflation: The Opposite Problem", ["deflation"]),
        "inf-008": ("The Fed's 2% Inflation Target", ["2 percent"]),
        "ir-001": ("What is an Interest Rate?", ["interest rate", "borrowing"]),
        "ir-002": ("The Federal Funds Rate", ["federal funds rate"]),
        "ir-003": ("Real vs. Nominal Interest Rates", ["real", "nominal"]),
        "ir-004": ("How Rates Cool Inflation", ["borrowing costs", "demand"]),
        "ir-005": ("The Yield Curve", ["yield curve", "inverted"]),
        "ir-006": ("Zero Interest Rate Policy (ZIRP)", ["lower bound", "zero"]),
        "ir-007": ("Credit Card Rates vs. The Fed", ["revolving"]),
        "ir-008": ("Negative Interest Rates", ["below zero", "policy rate"]),
        "gdp-001": ("What is GDP?", ["gross domestic product", "produced"]),
        "gdp-002": ("The Four Components of GDP", ["consumption", "net exports"]),
        "gdp-003": ("Real vs. Nominal GDP", ["nominal", "real"]),
        "gdp-004": ("GDP Per Capita", ["per capita", "population"]),
        "gdp-005": ("Recession: Two Quarters of Negative GDP", ["two consecutive quarters"]),
        "gdp-006": ("GDP Growth Rate", ["annual rate"]),
        "gdp-007": ("GDP vs. GNP", ["gross national product", "borders"]),
        "gdp-008": ("What GDP Misses", ["market transactions"]),
        "sd-001": ("The Law of Demand", ["higher price", "less"]),
        "sd-002": ("The Law of Supply", ["higher price", "more"]),
        "sd-003": ("Equilibrium Price", ["equilibrium"]),
        "sd-004": ("Price Elasticity", ["elastic"]),
        "sd-005": ("Supply Shocks", ["supply shock"]),
        "sd-006": ("Price Ceilings", ["price ceiling", "maximum"]),
        "sd-007": ("Price Floors", ["price floor", "minimum wage"]),
        "sd-008": ("Substitutes and Complements", ["substitutes", "complements"]),
        "lm-001": ("The Unemployment Rate", ["unemployment rate", "labor force"]),
        "lm-002": ("The Labor Force Participation Rate", ["participation rate"]),
        "lm-003": ("Frictional Unemployment", ["frictional"]),
        "lm-004": ("Structural Unemployment", ["structural"]),
        "lm-005": ("The Phillips Curve", ["phillips curve"]),
        "lm-006": ("The Gig Economy", ["contractors", "freelancers"]),
        "lm-007": ("Wage Growth and Inflation", ["wage growth", "productivity"]),
        "lm-008": ("The Jobs Report", ["household", "payroll"]),
        "tt-001": ("Why Countries Trade", ["specializing", "opportunity cost"]),
        "tt-002": ("What is a Tariff?", ["tariff", "tax on imported"]),
        "tt-003": ("Trade Deficits", ["trade deficit", "imported more"]),
        "tt-004": ("Free Trade Agreements", ["free trade agreement", "barriers"]),
        "tt-005": ("The WTO", ["world trade organization", "disputes"]),
        "tt-006": ("Protectionism", ["protection", "domestic industry"]),
        "tt-007": ("Currency and Trade", ["currency", "exports"]),
        "tt-008": ("Supply Chain Reshoring", ["resilience", "production"]),
        "hm-001": ("Why Housing is Different", ["consumption good", "asset"]),
        "hm-002": ("Mortgage Rates and Affordability", ["mortgage payment", "rate"]),
        "hm-003": ("Housing Supply Shortage", ["supply", "construction"]),
        "hm-004": ("The 2008 Housing Crash", ["credit standards", "defaults"]),
        "hm-005": ("The Lock-In Effect", ["lock", "fixed-rate"]),
        "hm-006": ("Rent vs. Own", ["renting", "owning"]),
        "hm-007": ("Institutional Investors in Housing", ["landlords", "institutional"]),
        "hm-008": ("Housing Starts", ["housing starts", "leading indicator"]),
        "cb-001": ("What Does a Central Bank Do?", ["central bank", "lender of last resort"]),
        "cb-002": ("Monetary Policy", ["monetary policy"]),
        "cb-003": ("Quantitative Easing (QE)", ["longer-term securities", "balance sheet"]),
        "cb-004": ("Central Bank Independence", ["independence"]),
        "cb-005": ("The Lender of Last Resort", ["lender of last resort", "panic"]),
        "cb-006": ("The ECB and the Eurozone", ["currency union", "single policy rate"]),
        "cb-007": ("Forward Guidance", ["forward guidance"]),
        "cb-008": ("Digital Currencies (CBDCs)", ["digital"]),
        "rec-001": ("What is a Recession?", ["nber", "decline"]),
        "rec-002": ("Leading Indicators", ["leading indicators"]),
        "rec-003": ("The Business Cycle", ["expansion", "trough"]),
        "rec-004": ("Fiscal Stimulus During Recessions", ["spending increases", "tax cuts"]),
        "rec-005": ("Automatic Stabilizers", ["automatic", "unemployment insurance"]),
        "rec-006": ("Recessions and Jobs", ["lagging indicator", "unemployment"]),
        "rec-007": ("Soft Landing vs. Hard Landing", ["soft landing", "hard landing"]),
        "rec-008": ("K-Shaped Recoveries", ["diverge", "letter k"]),
        "dd-001": ("Deficit vs. Debt", ["deficit", "debt"]),
        "dd-002": ("Debt-to-GDP Ratio", ["gross domestic product", "denominator"]),
        "dd-003": ("Who Holds US Debt?", ["by the public", "trust funds"]),
        "dd-004": ("The Debt Ceiling", ["debt limit", "borrowing"]),
        "dd-005": ("Can Government Debt Be Bad?", ["threshold", "growth"]),
        "dd-006": ("Modern Monetary Theory (MMT)", ["own currency", "default"]),
        "dd-007": ("Entitlements and Long-Term Debt", ["retirement", "interest costs"]),
        "dd-008": ("Interest on the National Debt", ["service", "rates rise"]),
    ]

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
        XCTAssertEqual(catalog.allCards.filter { $0.supersedes != nil }.count, 80)
    }

    /// The real ID-stability guarantee. Preserving an identifier is worthless if
    /// the concept behind it moved: a reader's saved bookmark on `rec-005` must
    /// still open the lesson `rec-005` taught in 1.0, not the one that happened
    /// to land in that slot. Any deliberate reassignment has to be declared in
    /// `supersedesNote` rather than made silently.
    func testEveryLegacyIdentifierStillTeachesItsOriginalConcept() throws {
        let catalog = try loadCatalog()
        let byID = Dictionary(uniqueKeysWithValues: catalog.allCards.map { ($0.cardID, $0) })
        XCTAssertEqual(Self.legacyConcepts.count, 80,
                       "the fixture must pin all 80 shipped identifiers")

        for (cardID, pinned) in Self.legacyConcepts {
            guard let card = byID[cardID] else {
                XCTFail("shipped identifier \(cardID) is missing from 1.1")
                continue
            }
            let haystack = "\(card.title) \(card.definition)".lowercased()
            let missing = pinned.tokens.filter { !haystack.contains($0) }
            if missing.isEmpty { continue }

            let note = card.supersedesNote?.trimmingCharacters(in: .whitespaces) ?? ""
            XCTAssertFalse(
                note.isEmpty,
                """
                \(cardID) no longer teaches its 1.0 concept "\(pinned.concept)" \
                (missing: \(missing)) and carries no supersedesNote explaining the \
                reassignment. A bookmark saved on this id would now open a different lesson.
                """)
        }
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

    func testDifficultySplitIsExactlyAsIntended() throws {
        let catalog = try loadCatalog()
        var counts: [CurriculumDifficulty: Int] = [:]
        for card in catalog.allCards {
            counts[card.difficulty, default: 0] += 1
        }
        // Pinned deliberately: a drift here means cards were reclassified
        // without anyone deciding to reclassify them.
        XCTAssertEqual(counts[.intro], 39)
        XCTAssertEqual(counts[.intermediate], 67)
        XCTAssertEqual(counts[.advanced], 14)
        XCTAssertEqual(counts.values.reduce(0, +), 120)
        for topic in catalog.topics {
            XCTAssertTrue(topic.cards.contains { $0.difficulty == .intro },
                          "topic \(topic.topicID) needs at least one intro card")
        }
    }

    // MARK: - Concrete examples

    /// Guards the regression this catalog was reviewed for: examples that only
    /// said which agency publishes a series, rather than showing the idea
    /// happening to someone. Every example must carry at least one concrete
    /// particular - a date, a quantity, a count - so a source pointer alone
    /// cannot pass.
    func testExamplesAreConcreteRatherThanSourcePointers() throws {
        let catalog = try loadCatalog()
        let digit = try NSRegularExpression(pattern: "\\d")
        for card in catalog.allCards {
            let range = NSRange(card.example.startIndex..., in: card.example)
            XCTAssertNotNil(
                digit.firstMatch(in: card.example, range: range),
                "\(card.cardID) example has no concrete particular - it reads as a source pointer")
        }
    }

    func testClaimKindMatchesWhatThePeriodActuallySays() throws {
        let catalog = try loadCatalog()
        let year = try NSRegularExpression(pattern: "\\b(1[89]\\d{2}|20\\d{2})\\b")
        for card in catalog.allCards {
            guard let claim = card.claim else { continue }
            let period = claim.observationPeriod
            let range = NSRange(period.startIndex..., in: period)
            switch claim.claimKind {
            case .observation:
                XCTAssertNotNil(
                    year.firstMatch(in: period, range: range),
                    "\(card.cardID) claims to be an observation but names no period: \(period)")
            case .illustration:
                XCTAssertTrue(
                    claim.units.lowercased().contains("illustrative"),
                    "\(card.cardID) is an illustration and its units must say so")
            }
        }
    }

    // MARK: - Fail-closed validation

    private func catalogJSONObject() throws -> [String: Any] {
        let url = try XCTUnwrap(
            Bundle.curriculumBundle.url(forResource: CurriculumCatalog.resourceName,
                                        withExtension: "json"))
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func decoded(_ object: [String: Any]) throws -> Curriculum {
        let data = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(Curriculum.self, from: data)
    }

    /// Mutates the shipped catalog into a specific defect and asserts the
    /// validator refuses it. A validator nobody has watched reject anything is
    /// not known to work.
    private func assertRejected(_ description: String,
                                file: StaticString = #filePath, line: UInt = #line,
                                _ mutate: (inout [String: Any]) -> Void) throws {
        var object = try catalogJSONObject()
        mutate(&object)
        let broken = try decoded(object)
        XCTAssertThrowsError(try CurriculumCatalog.validate(broken),
                             "validator accepted \(description)", file: file, line: line)
    }

    func testValidatorRejectsAnUnsupportedSchemaVersion() throws {
        try assertRejected("an unsupported schemaVersion") { $0["schemaVersion"] = 99 }
    }

    func testValidatorRejectsADuplicateCardIdentifier() throws {
        try assertRejected("a duplicate card identifier") { object in
            guard var topics = object["topics"] as? [[String: Any]],
                  var cards = topics[0]["cards"] as? [[String: Any]] else { return }
            cards[1]["cardID"] = cards[0]["cardID"]
            topics[0]["cards"] = cards
            object["topics"] = topics
        }
    }

    func testValidatorRejectsTopicOrderDrift() throws {
        try assertRejected("a topic whose declared order does not match its position") { object in
            guard var topics = object["topics"] as? [[String: Any]] else { return }
            topics[3]["order"] = 11
            object["topics"] = topics
        }
    }

    func testValidatorRejectsFreePaidClassificationDrift() throws {
        try assertRejected("a paid topic promoted to free") { object in
            guard var topics = object["topics"] as? [[String: Any]] else { return }
            topics[5]["access"] = "free"
            object["topics"] = topics
        }
    }

    func testValidatorRejectsAWrongCardCount() throws {
        try assertRejected("a topic with seven cards") { object in
            guard var topics = object["topics"] as? [[String: Any]],
                  var cards = topics[2]["cards"] as? [[String: Any]] else { return }
            cards.removeLast()
            topics[2]["cards"] = cards
            object["topics"] = topics
        }
    }

    func testValidatorRejectsADroppedTopic() throws {
        try assertRejected("a catalog with fourteen topics") { object in
            guard var topics = object["topics"] as? [[String: Any]] else { return }
            topics.removeLast()
            object["topics"] = topics
        }
    }

    func testLoaderThrowsWhenTheResourceIsMissing() {
        // The test bundle does not carry the curriculum; the app bundle does.
        let testBundle = Bundle(for: CurriculumCatalogTests.self)
        XCTAssertThrowsError(try CurriculumCatalog.loadValidated(in: testBundle)) { error in
            guard case CurriculumError.resourceMissing = error else {
                return XCTFail("expected resourceMissing, got \(error)")
            }
        }
    }
}
