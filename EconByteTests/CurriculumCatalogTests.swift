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
    /// The tokens are deliberately discriminating - see
    /// `testLegacyConceptPinsCannotBeSatisfiedByAnotherCard`.
    private static let legacyConcepts: [String: (concept: String, tokens: [String])] = [
        "inf-001": ("What is Inflation?", ["purchasing power", "prices"]),
        "inf-002": ("The Consumer Price Index (CPI)", ["consumer price index", "basket"]),
        "inf-003": ("Core vs. Headline Inflation", ["core", "headline"]),
        "inf-004": ("Demand-Pull Inflation", ["demand-pull"]),
        "inf-005": ("Cost-Push Inflation", ["cost-push"]),
        "inf-006": ("Hyperinflation", ["hyperinflation"]),
        "inf-007": ("Deflation: The Opposite Problem", ["deflation", "sustained fall"]),
        "inf-008": ("The Fed's 2% Inflation Target", ["low but positive", "buffer"]),
        "ir-001": ("What is an Interest Rate?", ["price of borrowing", "lenders receive"]),
        "ir-002": ("The Federal Funds Rate", ["federal funds rate"]),
        "ir-003": ("Real vs. Nominal Interest Rates", ["nominal rate", "subtracts inflation"]),
        "ir-004": ("How Rates Cool Inflation", ["borrowing costs", "demand"]),
        "ir-005": ("The Yield Curve", ["yield curve", "inverted"]),
        "ir-006": ("Zero Interest Rate Policy (ZIRP)", ["lower bound", "physical cash"]),
        "ir-007": ("Credit Card Rates vs. The Fed", ["revolving credit", "reprice"]),
        "ir-008": ("Negative Interest Rates", ["below zero", "excess reserves"]),
        "gdp-001": ("What is GDP?", ["gross domestic product", "produced"]),
        "gdp-002": ("The Four Components of GDP", ["consumption", "net exports"]),
        "gdp-003": ("Real vs. Nominal GDP", ["nominal gdp", "base year"]),
        "gdp-004": ("GDP Per Capita", ["per capita", "population"]),
        "gdp-005": ("Recession: Two Quarters of Negative GDP", ["two consecutive quarters"]),
        "gdp-006": ("GDP Growth Rate", ["annual rate", "compounded"]),
        "gdp-007": ("GDP vs. GNP", ["gross national product", "borders"]),
        "gdp-008": ("What GDP Misses", ["market transactions"]),
        "sd-001": ("The Law of Demand", ["demand curve", "downward-sloping"]),
        "sd-002": ("The Law of Supply", ["supply curve", "upward-sloping"]),
        "sd-003": ("Equilibrium Price", ["equilibrium"]),
        "sd-004": ("Price Elasticity", ["elastic"]),
        "sd-005": ("Supply Shocks", ["supply shock"]),
        "sd-006": ("Price Ceilings", ["price ceiling", "maximum"]),
        "sd-007": ("Price Floors", ["price floor", "minimum wage"]),
        "sd-008": ("Substitutes and Complements", ["substitutes", "complements"]),
        "lm-001": ("The Unemployment Rate", ["unemployment rate", "four weeks"]),
        "lm-002": ("The Labor Force Participation Rate", ["participation rate"]),
        "lm-003": ("Frictional Unemployment", ["frictional", "churn"]),
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
        "cb-001": ("What Does a Central Bank Do?", ["lender of last resort", "supervises"]),
        "cb-002": ("Monetary Policy", ["monetary policy", "credit conditions"]),
        "cb-003": ("Quantitative Easing (QE)", ["longer-term securities", "balance sheet"]),
        "cb-004": ("Central Bank Independence", ["independence"]),
        "cb-005": ("The Lender of Last Resort", ["lender of last resort", "panic"]),
        "cb-006": ("The ECB and the Eurozone", ["currency union", "single policy rate"]),
        "cb-007": ("Forward Guidance", ["forward guidance"]),
        "cb-008": ("Digital Currencies (CBDCs)", ["digital form", "settle payments"]),
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
        // 1.1.4 Phase 13 (content growth): primary publishers already approved
        // for the packs — the CBO and IMF, the EIA and FHFA statistical series,
        // the CFPB, and the remaining Reserve Banks.
        "www.cbo.gov", "www.imf.org", "www.eia.gov", "www.fhfa.gov", "www.consumerfinance.gov",
        "www.stlouisfed.org", "www.clevelandfed.org", "www.atlantafed.org", "www.chicagofed.org",
        "www.kansascityfed.org", "www.bostonfed.org", "www.richmondfed.org", "www.dallasfed.org",
        "www.minneapolisfed.org", "www.frbsf.org",
    ]

    /// Every card's id prefix, by topic (1.0 topics plus the five added in 1.1).
    private static let cardIDPrefixes: [String: String] = shippedCardIDPrefixes.merging([
        "exchange-rates": "fx", "consumer-spending": "cs", "taxes": "tax",
        "fiscal-policy": "fp", "economic-indicators": "ei",
    ]) { current, _ in current }

    /// The earliest verification pass still carried by a core card. A card may
    /// record any pass from this date up to the catalog's `verifiedOn` (the most
    /// recent pass), so cards added later keep their real retrieval date.
    private static let verificationFloor = "2026-08-30"

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
        XCTAssertEqual(CurriculumCatalog.expectedCardsPerTopic, 12, "1.1.4 Phase 13 grows every topic to 12 cards")
        XCTAssertEqual(catalog.allCards.count, 180, "1.1.4 ships exactly 180 core cards")
        for topic in catalog.topics {
            XCTAssertEqual(topic.cards.count, 12,
                           "topic \(topic.topicID) must carry exactly 12 cards")
        }
    }

    /// New cards continue each topic's id sequence; nothing shipped is renumbered
    /// (bookmarks and per-card state are keyed on `cardID`).
    func testCardIdentifiersContinueEachTopicsSequence() throws {
        let catalog = try loadCatalog()
        for topic in catalog.topics {
            let prefix = try XCTUnwrap(Self.cardIDPrefixes[topic.topicID], topic.topicID)
            for (index, card) in topic.cards.enumerated() {
                XCTAssertEqual(card.cardID, String(format: "%@-%03d", prefix, index + 1),
                               "\(card.cardID) is out of sequence in \(topic.topicID)")
            }
        }
    }

    // MARK: - Identifier stability

    func testCardIdentifiersAreUniqueAndNonEmpty() throws {
        let catalog = try loadCatalog()
        let ids = catalog.allCards.map(\.cardID)
        XCTAssertEqual(Set(ids).count, ids.count, "card identifiers must be unique")
        XCTAssertEqual(ids.count, 180)
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

    /// A concept pin is only worth having if it identifies one card. If card B's
    /// prose satisfies card A's pin, then swapping A's content for B's would slip
    /// past the stability check above - the guarantee would look enforced while
    /// being satisfiable by the wrong lesson.
    func testLegacyConceptPinsCannotBeSatisfiedByAnotherCard() throws {
        let catalog = try loadCatalog()
        let prose = Dictionary(uniqueKeysWithValues: catalog.allCards.map {
            ($0.cardID, "\($0.title) \($0.definition)".lowercased())
        })

        for (cardID, pinned) in Self.legacyConcepts {
            for (otherID, otherProse) in prose where otherID != cardID {
                let satisfied = pinned.tokens.allSatisfy { otherProse.contains($0) }
                XCTAssertFalse(
                    satisfied,
                    "\(cardID)'s pin \(pinned.tokens) is fully satisfied by \(otherID); "
                    + "it does not identify the concept \"\(pinned.concept)\"")
            }
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
        XCTAssertLessThanOrEqual(verifiedOn, Date(), "verification cannot be in the future")

        for card in catalog.allCards {
            let source = card.source
            guard let verified = formatter.date(from: source.verificationDate) else {
                XCTFail("\(card.cardID) verificationDate is not an ISO date: \(source.verificationDate)")
                continue
            }
            XCTAssertTrue(source.verificationDate >= Self.verificationFloor && verified <= verifiedOn,
                          "\(card.cardID) must be verified in a recorded pass (\(Self.verificationFloor)…\(catalog.verifiedOn))")
            guard let published = formatter.date(from: source.publicationDate) else {
                XCTFail("\(card.cardID) publicationDate is not an ISO date: \(source.publicationDate)")
                continue
            }
            XCTAssertLessThanOrEqual(published, verified,
                                     "\(card.cardID) cannot cite a document published after verification")

            if let claim = card.claim {
                XCTAssertEqual(claim.retrievalDate, source.verificationDate,
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
        // 1.1 shipped 39 / 67 / 14 of 120; 1.1.4 Phase 13 added 60 cards.
        XCTAssertEqual(counts[.intro], 54)
        XCTAssertEqual(counts[.intermediate], 97)
        XCTAssertEqual(counts[.advanced], 29)
        XCTAssertEqual(counts.values.reduce(0, +), 180)
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

    // MARK: - The Home highlight survives the catalog swap (RECONCILED 1.1.2)
    //
    // The 1.1.1 hotfix put one sourced line on Home by finding card `inf-001`
    // and string-searching its example prose for the literal "A grocery run",
    // then slicing to the next period. That worked on the v1.0 content it was
    // written against. The 1.1 catalog re-sourced `inf-001` — BLS free text to
    // FRED/CPIAUCSL, new wording — and the phrase is simply not there, so the
    // search returns nil, `groceryHighlight` is nil, and the Home line renders
    // NOTHING. No crash, no log, no failing unit test: the feature would have
    // disappeared silently the moment the content came back.
    //
    // The dependency is now on the card ID, which the catalog pins
    // (`supersedes: econbyte-1.0:inf-001`). These tests are what stop it
    // regressing to a phrase again.

    @MainActor
    func testTheHomeHighlightResolvesOnTheRestoredCatalog() {
        let highlight = ContentStore.shared.groceryHighlight
        XCTAssertNotNil(highlight,
                        "the Home highlight must resolve against the 1.1 catalog — a nil here is "
                            + "the silent-disappearance defect the 1.1.1 phrase search would cause")
    }

    @MainActor
    func testTheHomeHighlightIsAVerbatimSliceOfTheCardItNames() throws {
        let store = ContentStore.shared
        let card = try XCTUnwrap(store.allCards.first { $0.id == ContentStore.homeHighlightCardID },
                                 "card \(ContentStore.homeHighlightCardID) must exist in the catalog")
        let highlight = try XCTUnwrap(store.groceryHighlight)

        XCTAssertTrue(card.exampleBody.contains(highlight.line),
                      "the displayed line must be a verbatim slice of the card's own example, "
                        + "never an invented figure. line=[\(highlight.line)]")
        XCTAssertEqual(highlight.exampleBody, card.exampleBody)
        XCTAssertEqual(highlight.source, card.source,
                       "the visible attribution is the card's own source, which changed with the "
                        + "catalog (BLS free text -> FRED/CPIAUCSL structured)")
        XCTAssertTrue(highlight.line.hasSuffix("."), "the slice ends at its own sentence")
    }

    /// M-4. The slice used to be `body.firstIndex(of: ".")`, which is correct
    /// only for as long as the sourced prose happens to carry no decimal. The
    /// catalog re-sources these examples every cycle; the first CPI print
    /// written as "9.1 percent" would have put "…rose 9." on the home screen —
    /// a *different figure* than the card's, presented as the card's own.
    @MainActor
    func testTheHighlightSliceSurvivesADecimalInTheProse() {
        let prose = "Grocery prices rose 9.1 percent over the year to June 2022. "
            + "Nothing in the cart had changed; the money had."
        XCTAssertEqual(ContentStore.firstSentence(of: prose),
                       "Grocery prices rose 9.1 percent over the year to June 2022.",
                       "a period between two digits is a decimal point, not a sentence end")
    }

    /// The companion rule: a period inside a token is not a terminator either,
    /// so a bare source URL in the prose cannot truncate the line.
    @MainActor
    func testTheHighlightSliceDoesNotEndInsideADottedToken() {
        let prose = "The series lives at fred.stlouisfed.org and updates monthly. Then this."
        XCTAssertEqual(ContentStore.firstSentence(of: prose),
                       "The series lives at fred.stlouisfed.org and updates monthly.")
    }

    /// And prose with no terminator at all returns whole, never empty — showing
    /// too much of the card's own sourced text is the safe failure direction.
    @MainActor
    func testTheHighlightSliceFallsBackToTheWholeBodyWithNoTerminator() {
        XCTAssertEqual(ContentStore.firstSentence(of: "A sentence with no period"),
                       "A sentence with no period")
    }

    /// The shipped catalog, through the same door the view uses.
    @MainActor
    func testTheShippedHighlightIsTheCardsWholeFirstSentence() throws {
        let highlight = try XCTUnwrap(ContentStore.shared.groceryHighlight)
        XCTAssertTrue(highlight.line.hasSuffix("."))
        XCTAssertFalse(highlight.line.hasSuffix(" ."))
        XCTAssertTrue(highlight.exampleBody.hasPrefix(highlight.line),
                      "the line is the body's own opening, not a slice from its middle")
    }

    /// The specific trap, named: the phrase the 1.1.1 implementation keyed on is
    /// GONE from the restored catalog. If this ever passes, someone has put v1.0
    /// content back.
    @MainActor
    func testTheOneOneOnePhraseIsAbsentFromTheRestoredCatalog() throws {
        let card = try XCTUnwrap(ContentStore.shared.allCards
            .first { $0.id == ContentStore.homeHighlightCardID })
        XCTAssertFalse(card.exampleBody.contains("A grocery run"),
                       "the 1.1 catalog re-sourced inf-001; any implementation that keys on this "
                        + "phrase silently renders nothing")
    }

    /// And the restoration itself, asserted at the runtime store rather than at
    /// the JSON: 15 topics, 120 cards, on the screen the user actually sees.
    @MainActor
    func testTheRuntimeStoreServesTheFullFifteenTopicCatalog() {
        let store = ContentStore.shared
        XCTAssertNil(store.loadError)
        XCTAssertEqual(store.topics.count, 15)
        XCTAssertEqual(store.allCards.count, 180)
    }
}

// MARK: - Topic packs (1.1.3)

/// The Task 4 gate applied to `Resources/packs-v1.json`: the same editorial
/// rules as the core catalog (sources, freshness, advice framing, concrete
/// examples, declared claims), plus the pack contract — two packs of four
/// topics of eight cards, `access: pack`, no collision with the core catalog,
/// and the App Store product ids the store sells.
final class PackCatalogTests: XCTestCase {

    /// The core approved-source list plus the public primary sources the
    /// packs draw on: the CBO and IMF the Phase 2 brief names, and the federal
    /// regulators and agencies that publish the consumer-facing primary
    /// material for markets and personal finance (SEC/investor.gov, FINRA,
    /// SIPC, CFPB, NCUA, DOL, Federal Student Aid, Medicare, HealthCare.gov,
    /// PBGC, FTC) and the remaining Reserve Banks.
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
        "www.cbo.gov", "www.imf.org", "www.sec.gov", "www.investor.gov",
        "www.consumerfinance.gov", "www.ncua.gov", "www.sipc.org", "www.finra.org",
        "www.dol.gov", "www.studentaid.gov", "studentaid.gov", "www.medicare.gov",
        "www.healthcare.gov", "www.fhfa.gov", "www.stlouisfed.org", "www.chicagofed.org",
        "www.clevelandfed.org", "www.atlantafed.org", "www.kansascityfed.org",
        "www.bostonfed.org", "www.richmondfed.org", "www.dallasfed.org",
        "www.minneapolisfed.org", "www.sf.frb.org", "www.frbsf.org", "www.pbgc.gov",
        "www.usa.gov", "www.ftc.gov", "consumer.ftc.gov", "www.mymoney.gov",
        // 1.1.4 (history / world / systems packs), each a primary publisher:
        "www.archives.gov",        // U.S. National Archives — the statutes and executive documents themselves
        "www.loc.gov",             // Library of Congress — primary historical documents and official country studies
        "www.bankofengland.co.uk", // Bank of England — central bank, Open Government Licence
        "ec.europa.eu",            // European Commission / Eurostat — official EU statistics and treaty texts
        "unctad.org",              // UN Trade and Development — UN statistical publications
        "www.stats.gov.cn",        // National Bureau of Statistics of China — the official statistical office
        "www.pbc.gov.cn",          // People's Bank of China — the central bank's own releases
    ]

    private static let canonicalDisclaimer =
        "Educational content only. EconByte does not provide financial, investment, or tax advice."

    private static let staleTemporalWords = [
        "currently", "today", "nowadays", "recently", "at present",
        "these days", "this year", "last year", "right now", "as of now",
    ]

    private static let prohibitedAdvicePhrases = [
        "you should buy", "you should sell", "you should invest",
        "should buy", "should sell", "invest in", "buy now", "sell now",
        "guaranteed return", "risk-free return", "financial advice",
        "investment advice", "we recommend", "best investment",
        "will outperform", "get rich", "hot stock", "price target",
        "portfolio allocation", "beat the market", "sure thing", "act fast",
    ]

    private func loadCore() throws -> Curriculum { try CurriculumCatalog.loadValidated() }
    private func loadPacks() throws -> PackCurriculum {
        try PackCatalog.loadValidated(core: try loadCore())
    }

    // MARK: - Contract

    func testPacksLoadWithTheExpectedShape() throws {
        let packs = try loadPacks()
        XCTAssertEqual(packs.schemaVersion, 1)
        XCTAssertEqual(packs.packs.map(\.packID), PackCatalog.expectedPacks.map(\.packID))
        XCTAssertEqual(packs.packs.map(\.productID), PackCatalog.expectedProductIDs)
        XCTAssertEqual(packs.allTopics.count, PackCatalog.expectedPackCount * 4)
        XCTAssertEqual(packs.allCards.count, PackCatalog.expectedCardCount)
        XCTAssertEqual(PackCatalog.expectedPackCount, 6, "1.1.4 ships six packs (two from 1.1.3 + four new)")
        XCTAssertEqual(PackCatalog.expectedCardsPerTopic, 12, "1.1.4 Phase 13 grows every pack topic to 12 cards")
        XCTAssertEqual(PackCatalog.expectedCardCount, 288)
        for pack in packs.packs {
            XCTAssertEqual(pack.topics.count, 4, pack.packID)
            XCTAssertFalse(pack.summary.isEmpty)
            XCTAssertFalse(pack.icon.isEmpty)
            for (index, topic) in pack.topics.enumerated() {
                XCTAssertEqual(topic.access, .pack, topic.topicID)
                XCTAssertEqual(topic.order, index + 1, topic.topicID)
                XCTAssertEqual(topic.cards.count, PackCatalog.expectedCardsPerTopic, topic.topicID)
                XCTAssertFalse(topic.icon.isEmpty, topic.topicID)
                XCTAssertTrue(topic.cards.contains { $0.difficulty == .intro },
                              "topic \(topic.topicID) needs at least one intro card")
            }
        }
        for id in PackCatalog.expectedProductIDs {
            XCTAssertTrue(id.hasPrefix("com.nsantulli.econbyte.pack."), id)
        }
    }

    func testPackIdentifiersNeverCollideWithTheCoreCatalog() throws {
        let core = try loadCore()
        let packs = try loadPacks()
        let coreTopics = Set(core.topics.map(\.topicID))
        let coreCards = Set(core.allCards.map(\.cardID))
        let corePrefixes = Set(core.allCards.map { $0.cardID.split(separator: "-").dropLast().joined(separator: "-") })
        var seenCards = Set<String>()
        var seenTopics = Set<String>()
        for topic in packs.allTopics {
            XCTAssertFalse(coreTopics.contains(topic.topicID), "\(topic.topicID) is a core topic id")
            XCTAssertTrue(seenTopics.insert(topic.topicID).inserted, "duplicate pack topic \(topic.topicID)")
            for (index, card) in topic.cards.enumerated() {
                XCTAssertFalse(coreCards.contains(card.cardID), "\(card.cardID) is a core card id")
                XCTAssertTrue(seenCards.insert(card.cardID).inserted, "duplicate pack card \(card.cardID)")
                let prefix = card.cardID.split(separator: "-").dropLast().joined(separator: "-")
                XCTAssertFalse(corePrefixes.contains(prefix), "\(card.cardID) borrows core prefix \(prefix)")
                XCTAssertEqual(card.cardID, String(format: "%@-%03d", prefix, index + 1),
                               "\(card.cardID) breaks the stable-ID sequence")
                XCTAssertEqual(card.topicID, topic.topicID)
                XCTAssertNil(card.supersedes, "\(card.cardID) is new and supersedes nothing")
                XCTAssertNil(card.supersedesNote)
            }
        }
    }

    // MARK: - Sources and claims (same bar as the core catalog)

    func testEveryPackCardCitesAnApprovedCanonicalSource() throws {
        for card in try loadPacks().allCards {
            let source = card.source
            XCTAssertFalse(source.organization.trimmingCharacters(in: .whitespaces).isEmpty, card.cardID)
            XCTAssertFalse(source.documentTitle.trimmingCharacters(in: .whitespaces).isEmpty, card.cardID)
            guard let url = URL(string: source.url) else {
                XCTFail("\(card.cardID) has an unparseable source URL: \(source.url)")
                continue
            }
            XCTAssertEqual(url.scheme, "https", "\(card.cardID) must cite an https URL")
            XCTAssertTrue(Self.approvedSourceHosts.contains(url.host ?? ""),
                          "\(card.cardID) cites \(url.host ?? "?"), which is not an approved primary source")
            XCTAssertNil(url.query, "\(card.cardID) must cite a stable URL with no query string")
            XCTAssertNil(url.fragment, "\(card.cardID) must cite a stable URL with no fragment")
        }
    }

    func testPackSourceDatesAreWellFormedAndNotInTheFuture() throws {
        let packs = try loadPacks()
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        let verifiedOn = try XCTUnwrap(formatter.date(from: packs.verifiedOn), "verifiedOn is not an ISO date")
        XCTAssertLessThanOrEqual(verifiedOn, Date(), "verification cannot be in the future")

        for card in packs.allCards {
            // Any recorded pass from the 1.1.4 pack audit (2026-09-14) up to the
            // catalog's most recent pass; cards added later keep their real date.
            let verified = try XCTUnwrap(formatter.date(from: card.source.verificationDate),
                                         "\(card.cardID) verificationDate is not an ISO date")
            XCTAssertTrue(card.source.verificationDate >= "2026-09-14" && verified <= verifiedOn,
                          "\(card.cardID) must be verified in a recorded pass of the packs catalog")
            let published = try XCTUnwrap(formatter.date(from: card.source.publicationDate),
                                          "\(card.cardID) publicationDate is not an ISO date")
            XCTAssertLessThanOrEqual(published, verified, card.cardID)
            if let claim = card.claim {
                XCTAssertEqual(claim.retrievalDate, card.source.verificationDate, card.cardID)
                XCTAssertFalse(claim.units.isEmpty, card.cardID)
                XCTAssertFalse(claim.geography.isEmpty, card.cardID)
                XCTAssertFalse(claim.observationPeriod.isEmpty, card.cardID)
            }
        }
    }

    func testPackCardProseIsCompleteConsistentAndFresh() throws {
        let packs = try loadPacks()
        XCTAssertEqual(packs.disclaimer, Self.canonicalDisclaimer)
        XCTAssertGreaterThan(packs.editorialPolicy.count, 80)
        let verificationYear = Int(packs.verifiedOn.prefix(4)) ?? 0
        let year = try NSRegularExpression(pattern: "\\b(1[89]\\d{2}|20\\d{2})\\b")
        let digit = try NSRegularExpression(pattern: "\\d")

        for card in packs.allCards {
            XCTAssertFalse(card.title.trimmingCharacters(in: .whitespaces).isEmpty, card.cardID)
            XCTAssertGreaterThanOrEqual(card.definition.count, 60, "\(card.cardID) definition is too thin")
            XCTAssertGreaterThanOrEqual(card.example.count, 40, "\(card.cardID) example is too thin")
            XCTAssertNotEqual(card.definition, card.example, card.cardID)
            XCTAssertFalse(card.example.localizedCaseInsensitiveContains(card.definition),
                           "\(card.cardID) example merely restates the definition")
            XCTAssertEqual(card.disclaimer, Self.canonicalDisclaimer, card.cardID)
            XCTAssertEqual(card.editorial.status, "verified", card.cardID)
            XCTAssertFalse(card.editorial.reviewer.isEmpty, card.cardID)

            let prose = "\(card.title) \(card.definition) \(card.example)"
            let lower = prose.lowercased()
            for word in Self.staleTemporalWords {
                XCTAssertFalse(lower.contains(word), "\(card.cardID) uses \"\(word)\", which goes stale")
            }
            for phrase in Self.prohibitedAdvicePhrases {
                XCTAssertFalse(lower.contains(phrase), "\(card.cardID) contains advice framing: \"\(phrase)\"")
            }
            let range = NSRange(prose.startIndex..., in: prose)
            for match in year.matches(in: prose, range: range) {
                guard let r = Range(match.range, in: prose), let y = Int(prose[r]) else { continue }
                XCTAssertLessThanOrEqual(y, verificationYear, "\(card.cardID) cites year \(y), after verification")
            }
            let exampleRange = NSRange(card.example.startIndex..., in: card.example)
            XCTAssertNotNil(digit.firstMatch(in: card.example, range: exampleRange),
                            "\(card.cardID) example has no concrete particular")
        }
    }

    func testPackQuantitativeClaimsAreDeclaredAndKindMatchesPeriod() throws {
        let magnitude = try NSRegularExpression(
            pattern: "(\\$\\s?\\d)|(\\d[\\d,\\.]*\\s*(percent|trillion|billion|million))",
            options: [.caseInsensitive])
        let anyQuantity = try NSRegularExpression(
            pattern: "\\d|\\b(one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\\b",
            options: [.caseInsensitive])
        let year = try NSRegularExpression(pattern: "\\b(1[89]\\d{2}|20\\d{2})\\b")

        for card in try loadPacks().allCards {
            let prose = "\(card.title) \(card.definition) \(card.example)"
            let range = NSRange(prose.startIndex..., in: prose)
            if magnitude.firstMatch(in: prose, range: range) != nil {
                XCTAssertNotNil(card.claim, "\(card.cardID) states a magnitude but declares no sourced claim")
            }
            guard let claim = card.claim else { continue }
            let exampleRange = NSRange(card.example.startIndex..., in: card.example)
            XCTAssertNotNil(anyQuantity.firstMatch(in: card.example, range: exampleRange),
                            "\(card.cardID) declares a claim its example never makes")
            let period = claim.observationPeriod
            switch claim.claimKind {
            case .observation:
                XCTAssertNotNil(year.firstMatch(in: period, range: NSRange(period.startIndex..., in: period)),
                                "\(card.cardID) claims an observation but names no period: \(period)")
            case .illustration:
                XCTAssertTrue(claim.units.lowercased().contains("illustrative"),
                              "\(card.cardID) is an illustration and its units must say so")
            }
        }
    }

    // MARK: - Fail closed

    private func packsJSONObject() throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle.curriculumBundle.url(forResource: PackCatalog.resourceName,
                                                             withExtension: "json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any])
    }

    private func assertRejected(_ description: String,
                                file: StaticString = #filePath, line: UInt = #line,
                                _ mutate: (inout [String: Any]) -> Void) throws {
        var object = try packsJSONObject()
        mutate(&object)
        let data = try JSONSerialization.data(withJSONObject: object)
        let broken = try JSONDecoder().decode(PackCurriculum.self, from: data)
        let core = try loadCore()
        XCTAssertThrowsError(try PackCatalog.validate(broken, core: core),
                             "validator accepted \(description)", file: file, line: line)
    }

    func testValidatorRejectsAnUnsupportedSchemaVersion() throws {
        try assertRejected("an unsupported schemaVersion") { $0["schemaVersion"] = 99 }
    }

    func testValidatorRejectsAPackTopicPromotedToFree() throws {
        try assertRejected("a pack topic marked free") { object in
            guard var packs = object["packs"] as? [[String: Any]],
                  var topics = packs[0]["topics"] as? [[String: Any]] else { return }
            topics[0]["access"] = "free"
            packs[0]["topics"] = topics
            object["packs"] = packs
        }
    }

    func testValidatorRejectsACardIdentifierBorrowedFromTheCore() throws {
        try assertRejected("a pack card reusing a core card id") { object in
            guard var packs = object["packs"] as? [[String: Any]],
                  var topics = packs[0]["topics"] as? [[String: Any]],
                  var cards = topics[0]["cards"] as? [[String: Any]] else { return }
            cards[0]["cardID"] = "inf-001"
            topics[0]["cards"] = cards
            packs[0]["topics"] = topics
            object["packs"] = packs
        }
    }

    func testValidatorRejectsAWrongCardCount() throws {
        try assertRejected("a pack topic with seven cards") { object in
            guard var packs = object["packs"] as? [[String: Any]],
                  var topics = packs[1]["topics"] as? [[String: Any]],
                  var cards = topics[2]["cards"] as? [[String: Any]] else { return }
            cards.removeLast()
            topics[2]["cards"] = cards
            packs[1]["topics"] = topics
            object["packs"] = packs
        }
    }

    func testValidatorRejectsAnUnexpectedProductID() throws {
        try assertRejected("a pack selling under an unlisted product id") { object in
            guard var packs = object["packs"] as? [[String: Any]] else { return }
            packs[0]["productID"] = "com.nsantulli.econbyte.pack.mystery"
            object["packs"] = packs
        }
    }

    func testLoaderThrowsWhenThePacksResourceIsMissing() throws {
        let core = try loadCore()
        XCTAssertThrowsError(try PackCatalog.loadValidated(in: Bundle(for: PackCatalogTests.self), core: core)) { error in
            guard case CurriculumError.resourceMissing = error else {
                return XCTFail("expected resourceMissing, got \(error)")
            }
        }
    }
}
