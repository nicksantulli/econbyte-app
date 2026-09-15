import XCTest
import UserNotifications
@testable import EconByte

/// Task 5 gate: purchases, ads, telemetry, diagnostics, review, notifications,
/// and the version 1.1 catalog runtime switch.
///
/// Every rule asserted here comes from
/// `docs/superpowers/specs/2026-08-28-econbyte-return-growth-design.md` sections
/// 6 through 11, reconciled with the owner's DUD-224 decision (no EEA/UK ads via
/// geo-restriction, no Google UMP) recorded in `CONTENT-DECISIONS.md`.
final class GrowthSystemsTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        suiteName = "econbyte.growth.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - Helpers

    @MainActor
    private final class SpyInterstitialAdapter: EconInterstitialAdapting {
        var isAdLoaded = true
        var onAdDismissed: ((Bool) -> Void)?

        /// Stands in for the provider's dismissal delegate callback.
        func simulateDismissal(presentedCleanly: Bool) {
            onAdDismissed?(presentedCleanly)
        }

        var startCount = 0
        var preloadCount = 0
        var discardCount = 0
        var presentCount = 0
        var presentSucceeds = true
        var lastPolicy: EconAdRequestPolicy?

        func startSDK(policy: EconAdRequestPolicy) {
            startCount += 1
            lastPolicy = policy
        }

        func preload(policy: EconAdRequestPolicy) {
            preloadCount += 1
            lastPolicy = policy
        }

        func discardLoadedAd() {
            discardCount += 1
            isAdLoaded = false
        }

        func present() async -> Bool {
            presentCount += 1
            return presentSucceeds
        }
    }

    /// Every ad test in this file predates ATT and is about a reader who has
    /// already answered. `.denied` is used deliberately rather than
    /// `.authorized`: it is the majority real-world answer, it is a decided
    /// status (so the 1.1.2 build-13 gate lets the ad SDK start), and it is the
    /// outcome under which the request must still be non-personalized — which
    /// is what every assertion below was written against. The prompt's own
    /// ordering rules live in `TrackingAuthorizationTests`.
    @MainActor
    private final class DecidedTracking: EconTrackingAuthorizing {
        var status: EconTrackingStatus
        init(_ status: EconTrackingStatus = .denied) { self.status = status }
        func requestAuthorization() async -> EconTrackingStatus { status }
    }

    private func date(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let parsed = formatter.date(from: iso) else {
            XCTFail("bad fixture date \(iso)")
            return Date()
        }
        return parsed
    }

    private var shippedThresholds: EconAdThresholds { EconAdThresholds() }

    /// A state that satisfies every eligibility rule, so a test can break exactly
    /// one condition at a time.
    private func eligibleState(now: Date, dayKey: String) -> EconAdState {
        var state = EconAdState()
        state.completedSetsLifetime = 5
        state.setsSinceLastAd = 3
        state.lastShownAt = now.addingTimeInterval(-3600)
        state.shownThisSession = 0
        state.shownToday = 0
        state.dayKey = dayKey
        state.foregroundSessionsLifetime = 5
        return state
    }

    private func decide(state: EconAdState,
                        entitlements: EconEntitlements = EconEntitlements(),
                        region: EconAdRegionState = .allowed,
                        completedNormally: Bool = true,
                        blockers: Set<EconAdBlocker> = [],
                        now: Date,
                        dayKey: String) -> EconAdDecision {
        EconAdPolicy(thresholds: shippedThresholds)
            .decide(placement: .dailySetExit,
                    state: state,
                    entitlements: entitlements,
                    region: region,
                    setCompletedNormally: completedNormally,
                    blockers: blockers,
                    now: now,
                    dayKey: dayKey)
    }

    // MARK: - 1. Approved IAP preservation (spec section 8)

    /// The two approved non-consumables are permanent. Renaming, dropping, or
    /// merging either identifier breaks an already-approved App Store product.
    func testBothApprovedProductIdentifiersArePreservedExactly() {
        XCTAssertEqual(PurchaseManager.ProductID.unlockAll.rawValue,
                       "com.nsantulli.econbyte.unlockall")
        XCTAssertEqual(PurchaseManager.ProductID.removeAds.rawValue,
                       "com.nsantulli.econbyte.removeads")
        XCTAssertEqual(PurchaseManager.ProductID.packMarkets.rawValue,
                       "com.nsantulli.econbyte.pack.markets")
        XCTAssertEqual(PurchaseManager.ProductID.packPersonal.rawValue,
                       "com.nsantulli.econbyte.pack.personal")
        XCTAssertEqual(PurchaseManager.ProductID.allCases.count, 11,
                       "two approved non-consumables + six topic packs + the All Packs Bundle + the two EconByte Pro subscriptions (1.1.4)")
        XCTAssertEqual(PurchaseManager.ProductID.packBundle.rawValue, "com.nsantulli.econbyte.pack.bundle")
        XCTAssertFalse(PurchaseManager.ProductID.packBundle.isPack, "the bundle is not itself a pack row")
        XCTAssertFalse(PurchaseManager.ProductID.packBundle.isSubscription)
        XCTAssertEqual(PurchaseManager.ProductID.packs,
                       [.packMarkets, .packPersonal, .packHistory, .packWorld, .packSystems, .packPersonalFinance])
        XCTAssertEqual(PurchaseManager.ProductID.subscriptions, [.proMonthly, .proAnnual])
        XCTAssertEqual(PurchaseManager.ProductID.proMonthly.rawValue, "com.nsantulli.econbyte.pro.monthly")
        XCTAssertEqual(PurchaseManager.ProductID.proAnnual.rawValue, "com.nsantulli.econbyte.pro.annual")
        for id in PurchaseManager.ProductID.subscriptions {
            XCTAssertTrue(id.isSubscription, id.rawValue)
            XCTAssertFalse(id.isPack, id.rawValue)
        }
        XCTAssertFalse(PurchaseManager.ProductID.unlockAll.isPack)
        XCTAssertFalse(PurchaseManager.ProductID.removeAds.isPack)
        XCTAssertEqual(PurchaseManager.ProductID.packs.map(\.rawValue), PackCatalog.expectedProductIDs,
                       "the store's pack SKUs are exactly the catalog's pack SKUs, in order")
    }

    // MARK: - Topic packs (1.1.3, D18)

    /// Unlock All opens the core curriculum only. A pack topic is readable
    /// solely behind its own pack — unknown pack ids and Unlock All never do.
    @MainActor
    func testPackTopicsAreLockedWithoutTheirPackAndNeverOpenedByUnlockAll() throws {
        let store = ContentStore.shared
        XCTAssertNil(store.packLoadError, "packs-v1.json must load: \(String(describing: store.packLoadError))")
        XCTAssertEqual(store.packs.count, PackCatalog.expectedPackCount)
        for pack in store.packs {
            XCTAssertEqual(pack.topics.count, 4, pack.id)
            XCTAssertEqual(pack.cards.count, 48, pack.id)
            XCTAssertEqual(pack.preview.count, 3, pack.id)
            for topic in pack.topics {
                XCTAssertTrue(store.isPackTopic(topic.id))
                XCTAssertFalse(store.isTopicFree(topic.id), "\(topic.id) is never free")
                XCTAssertTrue(store.cards(for: topic.id, unlockedAll: true, ownedPackIDs: []).isEmpty,
                              "\(topic.id): Unlock All must not open a pack topic")
                XCTAssertTrue(store.cards(for: topic.id, unlockedAll: false, ownedPackIDs: ["mystery"]).isEmpty,
                              "\(topic.id): an unknown pack id unlocks nothing")
                XCTAssertEqual(store.cards(for: topic.id, unlockedAll: false, ownedPackIDs: [pack.id]).count, 12,
                               "\(topic.id) opens with its own pack")
                XCTAssertEqual(store.accessState(for: topic.id, unlockedAll: true), .locked)
                XCTAssertEqual(store.accessState(for: topic.id, unlockedAll: false, ownedPackIDs: [pack.id]), .unlocked)
                XCTAssertEqual(store.pack(forTopic: topic.id)?.id, pack.id)
                XCTAssertEqual(store.topicName(for: topic.id), topic.name)
            }
        }
        XCTAssertNil(store.pack(forTopic: "gdp"), "a core topic belongs to no pack")
        XCTAssertFalse(store.isPackTopic("inflation"))
    }

    /// The daily pool grows by exactly the OWNED packs' cards and never by an
    /// unowned pack's, with or without Unlock All.
    @MainActor
    func testDailySetIncludesPackCardsOnlyWhenTheirPackIsOwned() throws {
        let store = ContentStore.shared
        let packIDs = Set(store.packCards.map(\.id))
        XCTAssertEqual(packIDs.count, PackCatalog.expectedCardCount)
        for unlockedAll in [false, true] {
            let pool = store.dailySet(count: 500, unlockedAll: unlockedAll, ownedPackIDs: [])
            XCTAssertTrue(pool.allSatisfy { !packIDs.contains($0.id) },
                          "no pack card may enter the daily set without its pack (unlockedAll=\(unlockedAll))")
        }
        let markets = try XCTUnwrap(store.pack(id: "markets"))
        let personal = try XCTUnwrap(store.pack(id: "personal"))
        let withMarkets = store.dailySet(count: 500, unlockedAll: false, ownedPackIDs: [markets.id])
        let marketsIDs = Set(markets.cards.map(\.id))
        let personalIDs = Set(personal.cards.map(\.id))
        XCTAssertEqual(Set(withMarkets.map(\.id)).intersection(marketsIDs).count, 48,
                       "every Markets card is eligible once Markets is owned")
        XCTAssertTrue(Set(withMarkets.map(\.id)).isDisjoint(with: personalIDs),
                      "owning Markets does not admit Personal Economics cards")
    }

    /// The core totals the listing states are untouched by the packs.
    @MainActor
    func testCoreTotalsAreUnchangedByThePacks() {
        let store = ContentStore.shared
        XCTAssertEqual(store.topics.count, 15)
        // 1.1.4 Phase 13: 15 x 12 core, 24 pack topics x 12.
        XCTAssertEqual(store.allCards.count, 180)
        XCTAssertEqual(store.packTopics.count, 24)
        XCTAssertEqual(store.packCards.count, 288)
        XCTAssertEqual(store.everyCard.count, 468)
        let ids = store.everyCard.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "no pack card id collides with a core card id")
        XCTAssertTrue(Set(store.packTopics.map(\.id)).isDisjoint(with: Set(store.topics.map(\.id))))
    }

    /// `pack_shown_v1` is family + entry point only; the per-pack families are
    /// declared; nothing that identifies a product, price, or topic may ride.
    func testPackShownEventIsDeclaredWithFamilyAndEntryPointOnly() {
        XCTAssertEqual(TelemetrySchema.allowedProperties["pack_shown_v1"], ["product_family", "entry_point"])
        let families = TelemetrySchema.allowedValues["product_family"] ?? []
        XCTAssertEqual(families, ["unlock_all", "remove_ads", "pack_markets", "pack_personal", "pack_history",
                                  "pack_world", "pack_systems", "pack_personalfinance", "pack_bundle",
                                  "pro_monthly", "pro_annual"])
        XCTAssertEqual(TelemetryValidator.validate(TelemetryEvent("pack_shown_v1", [
            "product_family": .string("pack_markets"), "entry_point": .string("home"),
        ])), .accepted)
        XCTAssertEqual(TelemetryValidator.validate(TelemetryEvent("purchase_started_v1", [
            "product_family": .string("pack_personal"), "entry_point": .string("settings"),
        ])), .accepted)
        for property in ["product_id", "price", "topic_id", "pack_id"] {
            XCTAssertNotEqual(TelemetryValidator.validate(TelemetryEvent("pack_shown_v1", [
                "product_family": .string("pack_markets"), "entry_point": .string("home"),
                property: .string("x"),
            ])), .accepted, property)
        }
    }

    /// Independent products: neither purchase implies the other.
    func testEntitlementsAreIndependent() {
        let unlockOnly = EconEntitlements(unlockAll: true, removeAds: false)
        XCTAssertTrue(unlockOnly.paidTopicsUnlocked)
        XCTAssertFalse(unlockOnly.adsSuppressed,
                       "Unlock All Topics must not remove ads")

        let removeOnly = EconEntitlements(unlockAll: false, removeAds: true)
        XCTAssertFalse(removeOnly.paidTopicsUnlocked,
                       "Remove Ads must not unlock topics")
        XCTAssertTrue(removeOnly.adsSuppressed)

        let neither = EconEntitlements()
        XCTAssertFalse(neither.paidTopicsUnlocked)
        XCTAssertFalse(neither.adsSuppressed)
    }

    /// Revocation and refund win over stale cached ownership (spec section 8).
    func testRevocationWinsOverCachedOwnership() {
        let cached = EconEntitlements(unlockAll: true, removeAds: true)
        let verified = EconEntitlements(unlockAll: false, removeAds: false)
        let reconciled = EconEntitlements.reconciled(cached: cached, verified: verified)
        XCTAssertEqual(reconciled, verified,
                       "verified StoreKit truth must override the local cache")
    }

    /// A verified purchase seen only by StoreKit still grants immediately.
    func testVerifiedGrantOverridesEmptyCache() {
        let reconciled = EconEntitlements.reconciled(
            cached: EconEntitlements(),
            verified: EconEntitlements(unlockAll: true, removeAds: false))
        XCTAssertTrue(reconciled.paidTopicsUnlocked)
        XCTAssertFalse(reconciled.adsSuppressed)
    }

    /// A Remove Ads transition must reach the ad layer on the same turn.
    @MainActor
    func testRemoveAdsPurchaseImmediatelySuppressesAdsAndNeverStartsTheSDK() {
        let adapter = SpyInterstitialAdapter()
        let monetization = EconMonetization(adapter: adapter,
                                            defaults: defaults,
                                            now: { self.date("2026-09-01T12:00:00Z") },
                                            region: { .allowed },
                                            tracking: DecidedTracking())
        monetization.update(entitlements: EconEntitlements(unlockAll: false, removeAds: true))
        monetization.startAdsIfPermitted()

        XCTAssertEqual(adapter.startCount, 0,
                       "no ad SDK initialization once Remove Ads is owned")
        XCTAssertEqual(adapter.preloadCount, 0)
        XCTAssertEqual(monetization.decisionAtSetExit(), .suppressedEntitled)
    }

    /// A refund/revocation restores ad eligibility without an app restart.
    @MainActor
    func testRevocationRestoresAdEligibility() {
        let adapter = SpyInterstitialAdapter()
        let monetization = EconMonetization(adapter: adapter,
                                            defaults: defaults,
                                            now: { self.date("2026-09-01T12:00:00Z") },
                                            region: { .allowed },
                                            tracking: DecidedTracking())
        monetization.update(entitlements: EconEntitlements(removeAds: true))
        XCTAssertEqual(monetization.decisionAtSetExit(), .suppressedEntitled)

        monetization.update(entitlements: EconEntitlements(removeAds: false))
        XCTAssertNotEqual(monetization.decisionAtSetExit(), .suppressedEntitled)
        monetization.startAdsIfPermitted()
        XCTAssertEqual(adapter.startCount, 1)
    }

    // MARK: - 2. Region gate (DUD-224)

    /// Owner 2026-09-15: EEA (EU 27 + IS/LI/NO + the EU territories with their
    /// own codes) + GB + CH. Identical to Table Talk's `AdRegion`.
    func testRestrictedRegionsAreTheEEAUnitedKingdomAndSwitzerland() {
        for code in ["DE", "FR", "IE", "IT", "ES", "NL", "SE", "PL", "NO", "IS", "LI", "GB", "CH",
                     "GP", "MQ", "GF", "RE", "YT", "MF"] {
            XCTAssertEqual(EconAdRegion.state(for: code), .restricted,
                           "\(code) must be ad-restricted")
        }
        XCTAssertEqual(EconAdRegion.restrictedRegionCodes.count, 41,
                       "EU 27 + 9 EU territories with their own codes + Iceland, Liechtenstein, "
                        + "Norway + UK + Switzerland")
        XCTAssertEqual(EconAdRegion.restrictedStorefrontCodes.count, 39,
                       "the same territories in alpha-3, less IC and EA, which have no alpha-3 form")
        for code in ["DEU", "FRA", "GBR", "CHE", "NOR", "REU", "MAF", "GLP", "ALA"] {
            XCTAssertEqual(EconAdRegion.state(for: code), .restricted, "\(code) storefront")
        }
    }

    /// Phase 27 (2026-09-15): Åland, the Canary Islands and Ceuta & Melilla are
    /// EU territory (Finland and Spain) that iOS reports under their OWN ISO
    /// codes, so the EU-27 codes never covered them. They were missing from the
    /// block list until this build, which meant an ad request in the EEA
    /// whenever the storefront was unreadable and the device region was one of
    /// the three. `monetization-policy.json` rev 4 names all three.
    func testTheEUTerritoriesWithTheirOwnCodesAreBlocked() {
        for code in ["AX", "IC", "EA", "GP", "MQ", "GF", "RE", "YT", "MF"] {
            XCTAssertEqual(EconAdRegion.state(for: code), .restricted,
                           "\(code) is EU territory where the GDPR applies")
        }
        XCTAssertEqual(EconAdRegion.state(for: "ALA"), .restricted, "Åland's alpha-3")
        // IC and EA have no alpha-3 form; their storefronts report ESP, and
        // Åland's reports FIN. Both are blocked in their own right.
        XCTAssertEqual(EconAdRegion.state(for: "ESP"), .restricted)
        XCTAssertEqual(EconAdRegion.state(for: "FIN"), .restricted)
        XCTAssertEqual(EconAdRegion.restrictedStorefrontCodes.count + 2,
                       EconAdRegion.restrictedRegionCodes.count,
                       "the alpha-3 list is the alpha-2 list less exactly IC and EA")
    }

    /// Jersey, Guernsey, the Isle of Man and Gibraltar are served (Owner list;
    /// documented at `EconAdRegion`).
    func testCrownDependenciesAndGibraltarGetAds() {
        for code in ["JE", "GG", "IM", "GI", "JEY", "GGY", "IMN", "GIB"] {
            XCTAssertEqual(EconAdRegion.state(for: code), .allowed, "\(code) is not on the block list")
        }
    }

    /// The other side of the Phase 27 sweep: territories that look European but
    /// are NOT EU/EEA territory keep their ads, per the Owner's "everywhere else
    /// gets ads". Greenland and the Faroes (Denmark) and the French OCTs are
    /// overseas countries and territories, which the EU treaties do not cover.
    func testOverseasTerritoriesOutsideTheEUGetAds() {
        for code in ["GL", "FO", "BL", "PM", "PF", "NC", "WF",
                     "GRL", "FRO", "BLM", "SPM", "PYF", "NCL", "WLF"] {
            XCTAssertEqual(EconAdRegion.state(for: code), .allowed,
                           "\(code) is an overseas country or territory, not EU territory")
        }
    }

    func testAllowedRegionIsAllowed() {
        XCTAssertEqual(EconAdRegion.state(for: "US"), .allowed)
        XCTAssertEqual(EconAdRegion.state(for: "us"), .allowed)
        XCTAssertEqual(EconAdRegion.state(for: "USA"), .allowed)
        XCTAssertEqual(EconAdRegion.state(for: " ng "), .allowed)
    }

    /// Phase 25: an undeterminable region is SERVED, but never personalized.
    func testAnUnknownRegionIsServedButNeverPersonalized() {
        for code in [nil, "", "419", "001", "U", "USAA", "U1"] as [String?] {
            XCTAssertEqual(EconAdRegion.state(for: code), .unknown, "\(String(describing: code))")
        }
        XCTAssertTrue(EconAdRegionState.unknown.permitsAdRequests)
        XCTAssertFalse(EconAdRegionState.unknown.permitsPersonalizedAds)
        XCTAssertFalse(EconAdRegionState.restricted.permitsAdRequests)
        XCTAssertTrue(EconAdRegionState.allowed.permitsAdRequests)
        XCTAssertTrue(EconAdRegionState.allowed.permitsPersonalizedAds)
    }

    /// Storefront first, then the device region, else unknown.
    func testTheRegionResolverPrefersTheStorefrontThenTheLocale() {
        XCTAssertEqual(EconAdRegion.resolve(storefrontCountryCode: "DEU", localeRegionCode: "US"),
                       EconAdRegionResolution(state: .restricted, source: .storefront))
        XCTAssertEqual(EconAdRegion.resolve(storefrontCountryCode: "USA", localeRegionCode: "DE"),
                       EconAdRegionResolution(state: .allowed, source: .storefront),
                       "a US App Store account travelling in Germany is served")
        XCTAssertEqual(EconAdRegion.resolve(storefrontCountryCode: nil, localeRegionCode: "CH"),
                       EconAdRegionResolution(state: .restricted, source: .locale))
        XCTAssertEqual(EconAdRegion.resolve(storefrontCountryCode: "", localeRegionCode: "NG"),
                       EconAdRegionResolution(state: .allowed, source: .locale))
        XCTAssertEqual(EconAdRegion.resolve(storefrontCountryCode: "12", localeRegionCode: "GB"),
                       EconAdRegionResolution(state: .restricted, source: .locale),
                       "an unreadable storefront falls through to the locale")
        XCTAssertEqual(EconAdRegion.resolve(storefrontCountryCode: nil, localeRegionCode: "419"),
                       EconAdRegionResolution(state: .unknown, source: .none))
    }

    // MARK: - 2b. Personalization decision (Owner 2026-09-15)

    /// Region × ATT → npa/rdp. Personalized only for a known allowed region AND
    /// an ATT "Allow"; otherwise both `npa=1` and `rdp=1`.
    func testThePersonalizationMatrix() {
        for region in [EconAdRegionState.allowed, .restricted, .unknown] {
            for status in EconTrackingStatus.allCases {
                let decision = EconAdPersonalization.decide(region: region, tracking: status)
                let expected = region == .allowed && status == .authorized
                XCTAssertEqual(decision.personalized, expected, "\(region) × \(status)")
                XCTAssertEqual(decision.extras, expected ? [:] : ["npa": "1", "rdp": "1"],
                               "\(region) × \(status)")
                let policy = EconAdRequestPolicy(trackingStatus: status, region: region)
                XCTAssertEqual(policy.usesPersonalizedAds, expected)
                XCTAssertEqual(policy.extras, decision.extras)
            }
        }
    }

    @MainActor
    func testTheCoordinatorBuildsItsRequestFromTheLiveRegionAndStatus() {
        let tracking = DecidedTracking(.authorized)
        var region = EconAdRegionState.allowed
        let monetization = EconMonetization(adapter: SpyInterstitialAdapter(), defaults: defaults,
                                            region: { region }, tracking: tracking)
        XCTAssertTrue(monetization.currentRequestPolicy.usesPersonalizedAds)
        region = .unknown
        XCTAssertEqual(monetization.currentRequestPolicy.extras, ["npa": "1", "rdp": "1"],
                       "an unknown region forces non-personalized even after Allow")
        region = .allowed
        tracking.status = .denied
        XCTAssertEqual(monetization.currentRequestPolicy.extras, ["npa": "1", "rdp": "1"])
    }

    /// Turning Tracking off (or on) in iOS Settings reaches the next request on
    /// the next foreground, without a relaunch; a held ad requested under the
    /// old answer is replaced.
    @MainActor
    func testATrackingChangeOnForegroundUpdatesTheNextRequest() {
        let adapter = SpyInterstitialAdapter()
        let tracking = DecidedTracking(.authorized)
        let monetization = EconMonetization(adapter: adapter, defaults: defaults,
                                            region: { .allowed }, tracking: tracking)
        monetization.startAdsIfPermitted()
        XCTAssertEqual(adapter.lastPolicy?.usesPersonalizedAds, true)
        XCTAssertEqual(adapter.preloadCount, 1)

        // Same answer on foreground: nothing is discarded or re-requested.
        monetization.refreshRequestPolicyForForeground()
        XCTAssertEqual(adapter.discardCount, 0)
        XCTAssertEqual(adapter.preloadCount, 1)

        tracking.status = .denied
        monetization.refreshRequestPolicyForForeground()
        XCTAssertEqual(monetization.observedTrackingStatus, .denied)
        XCTAssertEqual(adapter.discardCount, 1, "the personalized ad is not shown after a revocation")
        XCTAssertEqual(adapter.preloadCount, 2)
        XCTAssertEqual(adapter.lastPolicy?.extras, ["npa": "1", "rdp": "1"])

        tracking.status = .authorized
        monetization.refreshRequestPolicyForForeground()
        XCTAssertEqual(adapter.preloadCount, 3)
        XCTAssertEqual(adapter.lastPolicy?.extras, [:], "Allow again: the next request is personalized")
    }

    @MainActor
    func testRestrictedRegionNeverStartsTheAdSDK() {
        let adapter = SpyInterstitialAdapter()
        let monetization = EconMonetization(adapter: adapter,
                                            defaults: defaults,
                                            now: { self.date("2026-09-01T12:00:00Z") },
                                            region: { .restricted },
                                            tracking: DecidedTracking())
        monetization.startAdsIfPermitted()
        XCTAssertEqual(adapter.startCount, 0)
        XCTAssertEqual(monetization.decisionAtSetExit(), .suppressedRegion(.restricted))
    }

    // MARK: - 3. Ad request configuration (spec section 9.1, DUD-224)

    /// Contextual only — still. 1.1.2 build 13 restores the ATT prompt (App
    /// Review 5.1.2(i)), so `requestsAppTrackingAuthorization` flips; the
    /// *request* does not. Non-personalized on every outcome, which
    /// `TrackingAuthorizationTests` asserts for all four statuses.
    func testAdRequestPolicyIsContextualAndDeclaresTheRestoredATTPrompt() {
        let policy = EconAdRequestPolicy()
        XCTAssertFalse(policy.usesPersonalizedAds)
        XCTAssertTrue(policy.requestsAppTrackingAuthorization,
                      "1.1.2 build 13 restores the ATT prompt the label requires")
        XCTAssertEqual(policy.extras["npa"], "1",
                       "non-personalized ads flag must be set on every request")
        XCTAssertEqual(policy.trackingStatus, .notDetermined,
                       "a policy built with no decision must not imply one")
    }

    func testAdRequestPolicyBlocksSensitiveCategoriesAndCapsContentRating() {
        let policy = EconAdRequestPolicy()
        XCTAssertEqual(policy.maxAdContentRating, "G")
        XCTAssertFalse(policy.blockedSensitiveCategories.isEmpty,
                       "sensitive categories are deny-by-default for a finance-education app")
        for category in ["financial-services", "gambling", "cryptocurrency", "loans", "politics"] {
            XCTAssertTrue(policy.blockedSensitiveCategories.contains(category),
                          "\(category) must be declared blocked")
        }
    }

    /// The shipped 1.0 Release ad unit is reused exactly. No invented IDs.
    func testAdUnitIdentifiersMatchTheShippedConfiguration() {
        XCTAssertEqual(EconAdUnit.release, "ca-app-pub-9950526548980224/9740067293")
        XCTAssertEqual(EconAdUnit.debug, "ca-app-pub-3940256099942544/4411468910",
                       "Debug builds use Google's public test interstitial unit")
        #if DEBUG
        XCTAssertEqual(EconAdUnit.current, EconAdUnit.debug)
        #else
        XCTAssertEqual(EconAdUnit.current, EconAdUnit.release)
        #endif
    }

    // MARK: - 4. Placement and caps (spec section 9.3)

    func testTheOnlyPlacementIsDailySetExit() {
        XCTAssertEqual(EconAdPlacement.allCases, [.dailySetExit])
        XCTAssertEqual(EconAdPlacement.dailySetExit.rawValue, "daily_set_exit")
    }

    /// Phase 11 pacing audit (see `EconAdThresholds`), bounded by the portfolio
    /// cap policy EconByte declares no override for: no interstitial in the
    /// install's first session, two completed sets first, one per foreground
    /// session, 15 minutes apart, two per calendar day AND per rolling 24 h.
    func testShippedThresholdsMatchThePhase11PacingAudit() {
        let thresholds = EconAdThresholds()
        XCTAssertEqual(thresholds.minimumCompletedSets, 2,
                       "a fresh install's first set exit stays ad-free")
        XCTAssertEqual(thresholds.initialSessionInterstitials, 0, "portfolio initialSessionInterstitials")
        XCTAssertEqual(thresholds.setsSinceLastAd, 1)
        XCTAssertEqual(thresholds.minimumInterval, 15 * 60,
                       "the retention guardrail: never two interstitials within 15 minutes")
        XCTAssertEqual(thresholds.perSession, 1, "portfolio maximumInterstitialsPerForegroundSession")
        XCTAssertEqual(thresholds.perDay, 2,
                       "the other guardrail: never more than two in a day")
        XCTAssertEqual(thresholds.rollingWindow, 24 * 60 * 60, "portfolio maximumInterstitialsPer24Hours")
    }

    func testTheInstallsFirstForegroundSessionCarriesNoInterstitial() {
        let now = date("2026-09-01T12:00:00Z")
        var state = eligibleState(now: now, dayKey: "2026-09-01")
        state.foregroundSessionsLifetime = 1
        XCTAssertEqual(decide(state: state, now: now, dayKey: "2026-09-01"), .initialSession)
        state.foregroundSessionsLifetime = 2
        XCTAssertEqual(decide(state: state, now: now, dayKey: "2026-09-01"), .eligible)
    }

    @MainActor
    func testAnUpgraderIsNotTreatedAsAFirstSession() {
        defaults.set(4, forKey: "econ.ads.completedSetsLifetime")
        let monetization = EconMonetization(adapter: SpyInterstitialAdapter(), defaults: defaults,
                                            now: { self.date("2026-09-01T12:00:00Z") },
                                            region: { .allowed }, tracking: DecidedTracking())
        monetization.noteForegroundSessionBegan()
        XCTAssertEqual(monetization.state.foregroundSessionsLifetime, 2)
    }

    func testTheDailyCapIsAlsoARolling24HourWindowAcrossMidnight() {
        let now = date("2026-09-02T00:20:00Z")
        var state = eligibleState(now: now, dayKey: "2026-09-02")
        state.lastShownAt = date("2026-09-01T23:50:00Z").addingTimeInterval(-3600)
        state.shownToday = 0
        state.recentShownAt = [date("2026-09-01T22:30:00Z"), date("2026-09-01T23:00:00Z")]
        XCTAssertEqual(decide(state: state, now: now, dayKey: "2026-09-02"), .dailyCapReached,
                       "two in the last 24 hours caps the exit even on a new calendar day")
        let later = date("2026-09-02T22:31:00Z")
        XCTAssertEqual(decide(state: state, now: later, dayKey: "2026-09-02"), .eligible,
                       "the window rolls off")
    }

    @MainActor
    func testRecentImpressionsPersistForTheRollingCap() async {
        let adapter = SpyInterstitialAdapter()
        let monetization = EconMonetization(adapter: adapter, defaults: defaults,
                                            now: { self.date("2026-09-01T12:00:00Z") },
                                            region: { .allowed }, tracking: DecidedTracking())
        monetization.noteForegroundSessionBegan()
        monetization.noteForegroundSessionBegan()
        for _ in 0..<3 { monetization.noteSetCompleted(normally: true) }
        do { let awaited = await monetization.presentIfEligibleAtSetExit(); XCTAssertEqual(awaited, .presented) }
        let reborn = EconMonetization(adapter: SpyInterstitialAdapter(), defaults: defaults,
                                      now: { self.date("2026-09-01T12:00:00Z") },
                                      region: { .allowed }, tracking: DecidedTracking())
        XCTAssertEqual(reborn.state.recentShownAt.count, 1)
    }

    /// Phase 11: nothing starts the ad SDK — so no banner or interstitial can
    /// be requested — while the first-launch prompts are still owed.
    @MainActor
    func testTheLaunchPermissionHoldBlocksTheAdSDKUntilReleased() {
        let adapter = SpyInterstitialAdapter()
        let monetization = EconMonetization(adapter: adapter, defaults: defaults,
                                            now: { self.date("2026-09-01T12:00:00Z") },
                                            region: { .allowed }, tracking: DecidedTracking())
        monetization.setLaunchPermissionsHold(true)
        monetization.noteForegroundSessionBegan()
        monetization.startAdsIfPermitted()
        XCTAssertEqual(adapter.startCount, 0, "held: no SDK start under a system prompt")
        XCTAssertFalse(monetization.canRequestAds, "held: no banner may be constructed")

        monetization.setLaunchPermissionsHold(false)
        XCTAssertTrue(monetization.canRequestAds)
        monetization.startAdsIfPermitted()
        XCTAssertEqual(adapter.startCount, 1)
        XCTAssertEqual(adapter.preloadCount, 1)
    }

    /// The placement matrix: banners only on Home, Browse at rest and under a
    /// card session; the interstitial only at the set exit.
    func testThePlacementMatrix() {
        let bannerSurfaces = EconAdSurface.allCases.filter { $0.bannerPlacement != nil }
        XCTAssertEqual(Set(bannerSurfaces), [.home, .browse, .cardMode])
        XCTAssertEqual(EconAdSurface.home.bannerPlacement, .bannerHome)
        XCTAssertEqual(EconAdSurface.browse.bannerPlacement, .bannerBrowse)
        XCTAssertEqual(EconAdSurface.cardMode.bannerPlacement, .bannerCard)
        for never in [EconAdSurface.search, .newsBrief, .newsArchive, .proTab, .courseLesson, .quiz,
                      .bookmarks, .bookmarksReview, .setComplete, .paywall, .settings, .firstLaunch] {
            XCTAssertNil(never.bannerPlacement, "\(never) must never carry a banner")
        }
        XCTAssertEqual(EconAdSurface.allCases.filter(\.allowsInterstitial), [.setComplete])
    }

    func testDeclaredCategoryBlocksCoverThePortfolioPolicy() {
        let declared = Set(EconAdRequestPolicy().blockedSensitiveCategories)
        for category in ["adult-sexual", "controlled-substances", "dating", "gambling", "politics",
                         "religion", "simulated-gambling", "violence"] {
            XCTAssertTrue(declared.contains(category), category)
        }
    }

    func testFullyEligibleStateIsEligible() {
        let now = date("2026-09-01T12:00:00Z")
        XCTAssertEqual(decide(state: eligibleState(now: now, dayKey: "2026-09-01"),
                              now: now, dayKey: "2026-09-01"),
                       .eligible)
    }

    func testFirstCompletedSetsAreBelowTheLifetimeThreshold() {
        let now = date("2026-09-01T12:00:00Z")
        var state = eligibleState(now: now, dayKey: "2026-09-01")
        state.completedSetsLifetime = 1
        XCTAssertEqual(decide(state: state, now: now, dayKey: "2026-09-01"),
                       .belowLifetimeSetThreshold(2))
    }

    func testAbandonedSetIsNotEligible() {
        let now = date("2026-09-01T12:00:00Z")
        XCTAssertEqual(decide(state: eligibleState(now: now, dayKey: "2026-09-01"),
                              completedNormally: false,
                              now: now, dayKey: "2026-09-01"),
                       .setNotCompletedNormally)
    }

    func testOneCompletedSetMustElapseBetweenInterstitials() {
        let now = date("2026-09-01T12:00:00Z")
        var state = eligibleState(now: now, dayKey: "2026-09-01")
        state.setsSinceLastAd = 0
        XCTAssertEqual(decide(state: state, now: now, dayKey: "2026-09-01"),
                       .belowSetsSinceLastAd(1))
        state.setsSinceLastAd = 1
        XCTAssertEqual(decide(state: state, now: now, dayKey: "2026-09-01"),
                       .eligible, "every completed set after the second is an eligible exit")
    }

    func testFifteenMinutesMustElapseBetweenInterstitials() {
        let now = date("2026-09-01T12:00:00Z")
        var state = eligibleState(now: now, dayKey: "2026-09-01")
        state.lastShownAt = now.addingTimeInterval(-600)
        XCTAssertEqual(decide(state: state, now: now, dayKey: "2026-09-01"),
                       .belowTimeThreshold(15 * 60))
    }

    func testOneInterstitialPerForegroundSession() {
        let now = date("2026-09-01T12:00:00Z")
        var state = eligibleState(now: now, dayKey: "2026-09-01")
        state.shownThisSession = 0
        XCTAssertEqual(decide(state: state, now: now, dayKey: "2026-09-01"), .eligible)
        state.shownThisSession = 1
        XCTAssertEqual(decide(state: state, now: now, dayKey: "2026-09-01"),
                       .sessionCapReached, "portfolio cap: one per foreground session")
    }

    func testTwoInterstitialsPerCalendarDay() {
        let now = date("2026-09-01T12:00:00Z")
        var state = eligibleState(now: now, dayKey: "2026-09-01")
        state.shownToday = 2
        XCTAssertEqual(decide(state: state, now: now, dayKey: "2026-09-01"),
                       .dailyCapReached)
    }

    /// Yesterday's two impressions must not spill into today.
    func testDailyCapRollsOverAtTheLocalCalendarDay() {
        let now = date("2026-09-02T12:00:00Z")
        var state = eligibleState(now: now, dayKey: "2026-09-01")
        state.shownToday = 2
        XCTAssertEqual(decide(state: state, now: now, dayKey: "2026-09-02"),
                       .eligible)
    }

    /// No ad over a purchase, restore, consent, review, notification, paywall,
    /// error, or system moment.
    func testEveryBlockerSuppressesTheAd() {
        let now = date("2026-09-01T12:00:00Z")
        for blocker in EconAdBlocker.allCases {
            XCTAssertEqual(decide(state: eligibleState(now: now, dayKey: "2026-09-01"),
                                  blockers: [blocker],
                                  now: now, dayKey: "2026-09-01"),
                           .blocked(blocker),
                           "\(blocker.rawValue) must suppress the interstitial")
        }
    }

    /// Entitlement beats every other reason, so a Remove Ads owner never even
    /// produces an eligibility signal.
    func testEntitlementIsCheckedBeforeEverythingElse() {
        let now = date("2026-09-01T12:00:00Z")
        var state = eligibleState(now: now, dayKey: "2026-09-01")
        state.completedSetsLifetime = 0
        XCTAssertEqual(decide(state: state,
                              entitlements: EconEntitlements(removeAds: true),
                              region: .restricted,
                              completedNormally: false,
                              blockers: [.purchase],
                              now: now, dayKey: "2026-09-01"),
                       .suppressedEntitled)
    }

    // MARK: - 5. Ad presentation behaviour

    @MainActor
    func testFreshInstallCompletingItsFirstSetSeesNoAd() async {
        let adapter = SpyInterstitialAdapter()
        let monetization = EconMonetization(adapter: adapter,
                                            defaults: defaults,
                                            now: { self.date("2026-09-01T12:00:00Z") },
                                            region: { .allowed },
                                            tracking: DecidedTracking())
        monetization.noteForegroundSessionBegan()
        monetization.noteSetCompleted(normally: true)
        let outcome = await monetization.presentIfEligibleAtSetExit()
        XCTAssertEqual(outcome, .notEligible(.belowLifetimeSetThreshold(2)))
        XCTAssertEqual(adapter.presentCount, 0)
    }

    @MainActor
    func testPresentationFailureIsSilentAndDoesNotConsumeTheCap() async {
        let adapter = SpyInterstitialAdapter()
        adapter.presentSucceeds = false
        let monetization = EconMonetization(adapter: adapter,
                                            defaults: defaults,
                                            now: { self.date("2026-09-01T12:00:00Z") },
                                            region: { .allowed },
                                            tracking: DecidedTracking())
        // Phase 11: a second foreground session — the install's first carries
        // no interstitial (portfolio `initialSessionInterstitials: 0`).
        monetization.noteForegroundSessionBegan()
        monetization.noteForegroundSessionBegan()
        for _ in 0..<3 { monetization.noteSetCompleted(normally: true) }

        let outcome = await monetization.presentIfEligibleAtSetExit()
        XCTAssertEqual(outcome, .presentationFailed)
        XCTAssertEqual(monetization.state.shownThisSession, 0,
                       "a failed presentation is not an impression")
        XCTAssertEqual(monetization.state.shownToday, 0)
    }

    @MainActor
    func testSuccessfulPresentationRecordsTheImpressionAndResetsTheSetCounter() async {
        let adapter = SpyInterstitialAdapter()
        let monetization = EconMonetization(adapter: adapter,
                                            defaults: defaults,
                                            now: { self.date("2026-09-01T12:00:00Z") },
                                            region: { .allowed },
                                            tracking: DecidedTracking())
        // Phase 11: a second foreground session — the install's first carries
        // no interstitial (portfolio `initialSessionInterstitials: 0`).
        monetization.noteForegroundSessionBegan()
        monetization.noteForegroundSessionBegan()
        for _ in 0..<3 { monetization.noteSetCompleted(normally: true) }

        let first = await monetization.presentIfEligibleAtSetExit()
        XCTAssertEqual(first, .presented)
        XCTAssertEqual(monetization.state.shownThisSession, 1)
        XCTAssertEqual(monetization.state.shownToday, 1)
        XCTAssertEqual(monetization.state.setsSinceLastAd, 0)

        // The very next completed set is an eligible exit under the 1.1.3
        // pacing, so what now holds the second interstitial back is the
        // 15-minute floor — the retention guardrail that did not move.
        monetization.noteSetCompleted(normally: true)
        let second = await monetization.presentIfEligibleAtSetExit()
        XCTAssertEqual(second, .notEligible(.belowTimeThreshold(15 * 60)))
    }

    @MainActor
    func testNoLoadedAdIsSilentAndDoesNotConsumeTheCap() async {
        let adapter = SpyInterstitialAdapter()
        adapter.isAdLoaded = false
        let monetization = EconMonetization(adapter: adapter,
                                            defaults: defaults,
                                            now: { self.date("2026-09-01T12:00:00Z") },
                                            region: { .allowed },
                                            tracking: DecidedTracking())
        // Phase 11: a second foreground session — the install's first carries
        // no interstitial (portfolio `initialSessionInterstitials: 0`).
        monetization.noteForegroundSessionBegan()
        monetization.noteForegroundSessionBegan()
        for _ in 0..<3 { monetization.noteSetCompleted(normally: true) }
        let outcome = await monetization.presentIfEligibleAtSetExit()
        XCTAssertEqual(outcome, .noAdAvailable)
        XCTAssertEqual(adapter.presentCount, 0)
        XCTAssertEqual(monetization.state.shownToday, 0)
    }

    @MainActor
    func testCompletedSetCountPersistsAcrossCoordinatorLifetimes() {
        let makeCoordinator = {
            EconMonetization(adapter: SpyInterstitialAdapter(),
                             defaults: self.defaults,
                             now: { self.date("2026-09-01T12:00:00Z") },
                             region: { .allowed },
                             tracking: DecidedTracking())
        }
        let first = makeCoordinator()
        first.noteSetCompleted(normally: true)
        first.noteSetCompleted(normally: true)
        XCTAssertEqual(first.state.completedSetsLifetime, 2)

        let second = makeCoordinator()
        XCTAssertEqual(second.state.completedSetsLifetime, 2,
                       "lifetime completed-set count survives a relaunch")
        XCTAssertEqual(second.state.shownThisSession, 0,
                       "the per-session cap resets on a new process")
    }

    /// `ad_eligible` and `ad_dismissed` are required section 15.2 launch
    /// metrics: without them the ad funnel has no denominator and no close.
    @MainActor
    func testAdEligibilityAndDismissalAreObservable() async {
        let adapter = SpyInterstitialAdapter()
        var eligible: [(EconAdPlacement, Int)] = []
        var dismissed: [(EconAdPlacement, EconResultClass)] = []

        let monetization = EconMonetization(adapter: adapter,
                                            defaults: defaults,
                                            now: { self.date("2026-09-01T12:00:00Z") },
                                            region: { .allowed },
                                            tracking: DecidedTracking())
        monetization.onAdEligible = { eligible.append(($0, $1)) }
        monetization.onAdDismissed = { dismissed.append(($0, $1)) }

        // Phase 11: a second foreground session — the install's first carries
        // no interstitial (portfolio `initialSessionInterstitials: 0`).
        monetization.noteForegroundSessionBegan()
        monetization.noteForegroundSessionBegan()
        for _ in 0..<3 { monetization.noteSetCompleted(normally: true) }

        let outcome = await monetization.presentIfEligibleAtSetExit()
        XCTAssertEqual(outcome, .presented)
        XCTAssertEqual(eligible.count, 1, "eligibility is signalled exactly once per exit")
        XCTAssertEqual(eligible.first?.0, .dailySetExit)
        XCTAssertEqual(eligible.first?.1, 3,
                       "sets_since_last_ad is captured before the counter resets")

        adapter.simulateDismissal(presentedCleanly: true)
        XCTAssertEqual(dismissed.count, 1)
        XCTAssertEqual(dismissed.first?.1, .success)

        adapter.simulateDismissal(presentedCleanly: false)
        XCTAssertEqual(dismissed.last?.1, .provider,
                       "a failed presentation closes the funnel as a provider result")
    }

    /// An ineligible exit must not fabricate an eligibility signal.
    @MainActor
    func testNoEligibilitySignalWhenTheExitIsIneligible() async {
        let adapter = SpyInterstitialAdapter()
        var eligible = 0
        let monetization = EconMonetization(adapter: adapter,
                                            defaults: defaults,
                                            now: { self.date("2026-09-01T12:00:00Z") },
                                            region: { .allowed },
                                            tracking: DecidedTracking())
        monetization.onAdEligible = { _, _ in eligible += 1 }
        monetization.noteForegroundSessionBegan()
        monetization.noteSetCompleted(normally: true)
        _ = await monetization.presentIfEligibleAtSetExit()
        XCTAssertEqual(eligible, 0)
    }

    // MARK: - 5b. Set-exit hand-off (Phase 25)
    //
    // 1.1.2–1.1.5 presented the interstitial from the card-mode cover and then
    // dismissed that cover on the same turn, tearing the ad down. The exit is
    // now armed on the completion screen and presented only after the cover is
    // gone. These doubles model the cover and record the order of events.

    @MainActor
    private final class CoverEnvironment: EconAdPresentationEnvironment {
        var coverIsUp = true
        var log: [String] = []
        var isReadyToPresentInterstitial: Bool { !coverIsUp }
    }

    @MainActor
    private final class OrderedAdapter: EconInterstitialAdapting {
        var isAdLoaded = true
        var onAdDismissed: ((Bool) -> Void)?
        let environment: CoverEnvironment
        private(set) var presentCount = 0
        private(set) var presentedWhileCoverWasUp: Bool?
        init(environment: CoverEnvironment) { self.environment = environment }
        func startSDK(policy: EconAdRequestPolicy) {}
        func preload(policy: EconAdRequestPolicy) {}
        func discardLoadedAd() { isAdLoaded = false }
        func present() async -> Bool {
            presentCount += 1
            presentedWhileCoverWasUp = environment.coverIsUp
            environment.log.append("ad.present")
            return true
        }
    }

    /// An install at an eligible set exit, in its second foreground session.
    @MainActor
    private func eligibleExit(adapter: EconInterstitialAdapting,
                              now: @escaping () -> Date,
                              sleep: @escaping @MainActor (TimeInterval) async -> Void) -> EconMonetization {
        let monetization = EconMonetization(adapter: adapter, defaults: defaults, now: now,
                                            region: { .allowed }, tracking: DecidedTracking(),
                                            presentationSleep: sleep)
        monetization.noteForegroundSessionBegan()
        monetization.noteForegroundSessionBegan()
        for _ in 0..<3 { monetization.noteSetCompleted(normally: true) }
        return monetization
    }

    @MainActor
    func testTheSetExitAdIsPresentedOnlyAfterTheDismissingCoverIsGone() async {
        let environment = CoverEnvironment()
        let adapter = OrderedAdapter(environment: environment)
        var sleeps = 0
        let monetization = eligibleExit(adapter: adapter,
                                        now: { self.date("2026-09-01T12:00:00Z") },
                                        sleep: { _ in
                                            sleeps += 1
                                            // The cover's dismissal animation ends a few polls in.
                                            if sleeps == 4 {
                                                environment.log.append("cover.dismissed")
                                                environment.coverIsUp = false
                                            }
                                        })

        // The completion screen decides and arms — nothing is presented yet.
        XCTAssertEqual(monetization.armSetExitBreak(), .eligible)
        XCTAssertNotNil(monetization.pendingSetExitBreak)
        XCTAssertEqual(adapter.presentCount, 0, "arming must never present")
        environment.log.append("cover.dismiss")

        // The shell resolves the break once the cover's session has ended.
        let outcome = await monetization.presentPendingSetExitBreak(environment: environment)
        XCTAssertEqual(outcome, .presented)
        XCTAssertEqual(environment.log, ["cover.dismiss", "cover.dismissed", "ad.present"],
                       "the ad request is presented only after the dismissing view is gone")
        XCTAssertEqual(adapter.presentedWhileCoverWasUp, false)
        XCTAssertEqual(monetization.state.shownThisSession, 1)
        XCTAssertNil(monetization.pendingSetExitBreak)

        let again = await monetization.presentPendingSetExitBreak(environment: environment)
        XCTAssertNil(again, "a break is presented at most once")
        XCTAssertEqual(adapter.presentCount, 1)
    }

    @MainActor
    func testAPresenterThatNeverSettlesShowsNothingAndConsumesNoCap() async {
        let environment = CoverEnvironment()
        let adapter = OrderedAdapter(environment: environment)
        var slept: TimeInterval = 0
        let monetization = eligibleExit(adapter: adapter,
                                        now: { self.date("2026-09-01T12:00:00Z") },
                                        sleep: { slept += $0 })
        monetization.armSetExitBreak()
        let outcome = await monetization.presentPendingSetExitBreak(environment: environment)
        XCTAssertEqual(outcome, .notEligible(.presenterUnavailable))
        XCTAssertEqual(adapter.presentCount, 0)
        XCTAssertEqual(monetization.state.shownThisSession, 0)
        XCTAssertEqual(monetization.state.shownToday, 0)
        XCTAssertLessThanOrEqual(slept, EconMonetization.presenterReadyTimeout + 0.1,
                                 "the wait is bounded")
    }

    /// A rating request (or consent offer, or notification prompt) raised on the
    /// completion screen still suppresses the ad even though the screen clears
    /// its blockers before the cover is dismissed.
    @MainActor
    func testABlockerOnTheCompletionScreenStillSuppressesTheHandedOffAd() async {
        let environment = CoverEnvironment()
        environment.coverIsUp = false
        let adapter = OrderedAdapter(environment: environment)
        let monetization = eligibleExit(adapter: adapter,
                                        now: { self.date("2026-09-01T12:00:00Z") },
                                        sleep: { _ in })
        monetization.setBlocker(.review, active: true)
        XCTAssertEqual(monetization.armSetExitBreak(), .blocked(.review))
        monetization.setBlocker(.review, active: false)
        let outcome = await monetization.presentPendingSetExitBreak(environment: environment)
        XCTAssertNil(outcome, "nothing was armed")
        XCTAssertEqual(adapter.presentCount, 0)
    }

    /// A purchase that lands between the exit and the presentation wins.
    @MainActor
    func testAPurchaseBetweenArmingAndPresentingSuppressesTheAd() async {
        let environment = CoverEnvironment()
        environment.coverIsUp = false
        let adapter = OrderedAdapter(environment: environment)
        let monetization = eligibleExit(adapter: adapter,
                                        now: { self.date("2026-09-01T12:00:00Z") },
                                        sleep: { _ in })
        XCTAssertEqual(monetization.armSetExitBreak(), .eligible)
        monetization.update(entitlements: EconEntitlements(removeAds: true))
        let outcome = await monetization.presentPendingSetExitBreak(environment: environment)
        XCTAssertEqual(outcome, .notEligible(.suppressedEntitled))
        XCTAssertEqual(adapter.presentCount, 0)
    }

    /// An armed break never surfaces late: not after the app left the
    /// foreground, and not after it went stale.
    @MainActor
    func testAnArmedBreakIsDroppedByANewSessionOrWhenStale() async {
        let environment = CoverEnvironment()
        environment.coverIsUp = false
        let adapter = OrderedAdapter(environment: environment)
        var clock = date("2026-09-01T12:00:00Z")
        let monetization = eligibleExit(adapter: adapter, now: { clock }, sleep: { _ in })

        XCTAssertEqual(monetization.armSetExitBreak(), .eligible)
        monetization.noteForegroundSessionBegan()
        let afterBackground = await monetization.presentPendingSetExitBreak(environment: environment)
        XCTAssertNil(afterBackground)

        monetization.noteSetCompleted(normally: true)
        XCTAssertEqual(monetization.armSetExitBreak(), .eligible)
        clock = clock.addingTimeInterval(EconMonetization.pendingBreakLifetime + 60)
        let stale = await monetization.presentPendingSetExitBreak(environment: environment)
        XCTAssertEqual(stale, .notEligible(.presenterUnavailable))
        XCTAssertEqual(adapter.presentCount, 0)
    }

    /// Eligibility is reported once, at the exit, before any provider call.
    @MainActor
    func testArmingReportsEligibilityOnceAndPreloadsAMissingAd() {
        let adapter = SpyInterstitialAdapter()
        adapter.isAdLoaded = false
        var eligible = 0
        let monetization = EconMonetization(adapter: adapter, defaults: defaults,
                                            now: { self.date("2026-09-01T12:00:00Z") },
                                            region: { .allowed }, tracking: DecidedTracking())
        monetization.onAdEligible = { _, _ in eligible += 1 }
        monetization.noteForegroundSessionBegan()
        monetization.noteForegroundSessionBegan()
        for _ in 0..<3 { monetization.noteSetCompleted(normally: true) }
        monetization.startAdsIfPermitted()
        let preloads = adapter.preloadCount
        XCTAssertEqual(monetization.armSetExitBreak(), .eligible)
        XCTAssertEqual(eligible, 1)
        XCTAssertEqual(adapter.preloadCount, preloads + 1,
                       "the dismissal window is used to fetch a missing ad")
        XCTAssertEqual(adapter.presentCount, 0)
    }

    // MARK: - 6/7. Telemetry schema and consent — MOVED, not dropped
    //
    // RECONCILED (1.1.2): sections 6 and 7 tested lineage A's `EconTelemetry` —
    // an allowlisted event vocabulary with a queue and a no-op sink that never
    // transmitted anything, because no provider token existed when 1.1 shipped.
    // The reconciled app has exactly one telemetry pipeline, the transport-backed
    // one from the 1.1.2 instrumentation lineage, so the type these tests
    // exercised no longer exists. Their subject matter did not disappear with
    // them: `EconTelemetryTests` and `InstrumentationPrivacyTests` cover the
    // same ground against the pipeline that actually ships — the closed event
    // allowlist, the prohibited-property list (which is strictly larger: it
    // rejects `card_id`, `topic_id` and `set_id`, which lineage A's schema
    // ALLOWED), oversized values, bounded queue, consent default, opt-out
    // deletion, and the provider posture switches, each now asserted against the
    // vendor object rather than against a struct.

    // MARK: - 8. Diagnostics (spec section 10.3)

    func testDiagnosticCodesMatchTheSpecification() {
        XCTAssertEqual(Set(EconDiagnosticCode.allCases.map(\.rawValue)),
                       ["content_catalog_invalid", "store_products_unavailable",
                        "transaction_unverified", "restore_failed",
                        "consent_update_failed", "ad_load_failed",
                        "ad_present_failed", "notification_schedule_failed"])
    }

    func testDiagnosticsConsentDefaultsOffAndIsSeparateFromAnalytics() {
        let log = EconDiagnosticLog(defaults: defaults)
        XCTAssertFalse(log.isEnabled)
        XCTAssertFalse(log.capture(.adLoadFailed))
        XCTAssertTrue(log.queue.isEmpty)
        XCTAssertNil(log.installationID)

        // RECONCILED (1.1.2): analytics consent now lives on the shipped
        // telemetry facade's key. Granting it must still leave diagnostics off —
        // the two choices are separate, which is what the App Store notes say.
        defaults.set(true, forKey: EconTelemetry.Key.consent)
        XCTAssertFalse(EconDiagnosticLog(defaults: defaults).isEnabled,
                       "analytics consent must not enable diagnostics")
        XCTAssertFalse(defaults.bool(forKey: EconDiagnostics.consentDefaultsKey),
                       "analytics consent must not enable crash reporting either")
    }

    func testDiagnosticsUsesAFreshInstallationIdentifierOnEveryOptIn() {
        let log = EconDiagnosticLog(defaults: defaults)
        log.setEnabled(true)
        let first = log.installationID
        XCTAssertNotNil(first)
        log.setEnabled(false)
        XCTAssertNil(log.installationID)
        log.setEnabled(true)
        XCTAssertNotNil(log.installationID)
        XCTAssertNotEqual(log.installationID, first,
                          "opting out deletes the identifier; opting back in must not resurrect it")
    }

    func testDisablingDiagnosticsClearsQueuedReports() {
        let log = EconDiagnosticLog(defaults: defaults)
        log.setEnabled(true)
        XCTAssertTrue(log.capture(.restoreFailed))
        XCTAssertFalse(log.queue.isEmpty)
        log.setEnabled(false)
        XCTAssertTrue(log.queue.isEmpty)
        XCTAssertNil(log.installationID)
    }

    func testDiagnosticsOptionsExcludePIIReplayAndAttachments() {
        let options = EconDiagnosticLogConfiguration.options
        XCTAssertFalse(options.sendDefaultPII)
        XCTAssertFalse(options.attachScreenshots)
        XCTAssertFalse(options.attachViewHierarchy)
        XCTAssertFalse(options.sessionReplayEnabled)
        XCTAssertFalse(options.capturesNetworkBodies)
        XCTAssertEqual(options.tracesSampleRate, 0)
        XCTAssertEqual(options.maximumBreadcrumbs, 0,
                       "no navigation breadcrumbs, which could carry card content")
        XCTAssertNil(EconDiagnosticLogConfiguration.sentryDSN,
                     "no diagnostics DSN is embedded in the repository")
    }

    func testScrubberRedactsEmailsURLsAndLongDigitRuns() {
        let scrubbed = EconDiagnosticScrubber.scrub(
            "failed for reader@example.com at https://fred.stlouisfed.org/series/CPIAUCSL?token=9 id 4111111111111111")
        XCTAssertFalse(scrubbed.contains("reader@example.com"))
        XCTAssertFalse(scrubbed.contains("fred.stlouisfed.org"))
        XCTAssertFalse(scrubbed.contains("4111111111111111"))
        XCTAssertTrue(scrubbed.contains(EconDiagnosticScrubber.redaction))
    }

    func testScrubberCapsLength() {
        let long = String(repeating: "x", count: EconDiagnosticScrubber.maximumLength * 2)
        XCTAssertLessThanOrEqual(EconDiagnosticScrubber.scrub(long).count,
                                 EconDiagnosticScrubber.maximumLength)
    }

    func testDiagnosticDetailCarriesNoProse() {
        let error = NSError(domain: "EconByteTests",
                            code: 42,
                            userInfo: [NSLocalizedDescriptionKey: "card inf-001 said prices rose"])
        let detail = EconDiagnosticDetail(error)
        XCTAssertEqual(detail.errorDomain, "EconByteTests")
        XCTAssertEqual(detail.errorCode, 42)
    }

    func testDiagnosticsQueueIsBounded() {
        XCTAssertEqual(EconDiagnosticLog.maximumQueuedReports, 50)
        let diagnostics = EconDiagnosticLog(defaults: defaults)
        diagnostics.setEnabled(true)
        for _ in 0..<(EconDiagnosticLog.maximumQueuedReports + 10) {
            diagnostics.capture(.adLoadFailed)
        }
        XCTAssertEqual(diagnostics.queue.count, EconDiagnosticLog.maximumQueuedReports)
    }

    // MARK: - 9. Review requests (review-rules-v2, Owner order 2026-09-14)
    //
    // 1.1 asked after 3 completed sets and 7 days. 1.1.3 ports Table Talk's
    // rules-v2: never on the first open; from the second open, the first
    // completed session of 5+ cards is the moment; once per version, 120 days
    // apart, at most 2 a year; deferred by an ad, a purchase, the consent card,
    // a system prompt, or an error in the same session.

    private func satisfiedReviewState() -> ReviewRequestState {
        var state = ReviewRequestState()
        state.launchCount = 2
        state.completedSetCount = 1
        state.currentSessionCompletedSet = true
        state.currentSessionCards = 8
        return state
    }

    func testReviewThresholdsMatchRulesV2() {
        let thresholds = ReviewRequestPolicy.thresholds
        XCTAssertEqual(thresholds.minimumLaunches, 2, "never on the first open; the second is the earliest")
        XCTAssertEqual(thresholds.minimumCompletedSets, 1)
        XCTAssertEqual(thresholds.minimumCardsInSession, 5)
        XCTAssertEqual(thresholds.minimumDaysBetweenAttempts, 120)
        XCTAssertEqual(thresholds.maximumAttemptsPerYear, 2)
        XCTAssertEqual(ReviewRequestPolicy.ruleVersion, "review-rules-v2")
    }

    func testReviewIsEligibleOnTheSecondOpenAfterAFullSet() {
        let now = date("2026-09-14T12:00:00Z")
        XCTAssertEqual(ReviewRequestPolicy.decide(state: satisfiedReviewState(),
                                                  currentVersion: "1.1.3",
                                                  now: now),
                       .eligible)
    }

    func testReviewIsNeverAskedOnTheFirstOpen() {
        let now = date("2026-09-14T12:00:00Z")
        var state = satisfiedReviewState()
        state.launchCount = 1
        XCTAssertEqual(ReviewRequestPolicy.decide(state: state, currentVersion: "1.1.3", now: now),
                       .belowLaunchCount(1))
        state.launchCount = 0
        XCTAssertEqual(ReviewRequestPolicy.decide(state: state, currentVersion: "1.1.3", now: now),
                       .belowLaunchCount(0))
    }

    func testReviewNeedsACompletedSet() {
        let now = date("2026-09-14T12:00:00Z")
        var state = satisfiedReviewState()
        state.completedSetCount = 0
        XCTAssertEqual(ReviewRequestPolicy.decide(state: state, currentVersion: "1.1.3", now: now),
                       .insufficientCompletedSets(1))
    }

    func testReviewNeedsTheCurrentSessionToHaveCompletedASet() {
        let now = date("2026-09-14T12:00:00Z")
        var state = satisfiedReviewState()
        state.currentSessionCompletedSet = false
        XCTAssertEqual(ReviewRequestPolicy.decide(state: state, currentVersion: "1.1.3", now: now),
                       .sessionNotCompleted)
    }

    /// A three-card saved-cards replay is a completed set for the lifetime
    /// counters, but not a moment to ask.
    func testReviewNeedsAtLeastFiveCardsInTheSessionThatJustEnded() {
        let now = date("2026-09-14T12:00:00Z")
        var state = satisfiedReviewState()
        state.currentSessionCards = 3
        XCTAssertEqual(ReviewRequestPolicy.decide(state: state, currentVersion: "1.1.3", now: now),
                       .belowSessionCards(3))
        state.currentSessionCards = 5
        XCTAssertEqual(ReviewRequestPolicy.decide(state: state, currentVersion: "1.1.3", now: now),
                       .eligible, "five cards is the moment")
    }

    func testAnyNegativeSessionEventSuppressesTheReviewRequest() {
        let now = date("2026-09-14T12:00:00Z")
        for event in EconNegativeSessionEvent.allCases {
            var state = satisfiedReviewState()
            state.negativeSessionEvents = [event]
            XCTAssertEqual(ReviewRequestPolicy.decide(state: state, currentVersion: "1.1.3", now: now),
                           .negativeSession(event),
                           "\(event.rawValue) in the session must defer the prompt")
        }
        // The 1.1.3 additions are present by name: an ad, a purchase or restore,
        // the consent card, a system prompt (notifications or ATT), an error.
        for required in [EconNegativeSessionEvent.ad, .purchase, .restore, .consentForm,
                         .notificationPrompt, .trackingPrompt, .errorShown] {
            XCTAssertTrue(EconNegativeSessionEvent.allCases.contains(required))
        }
    }

    func testReviewIsAttemptedAtMostOncePerAppVersion() {
        let now = date("2026-09-14T12:00:00Z")
        var state = satisfiedReviewState()
        state.attemptedVersions = ["1.1.3"]
        state.attemptDates = [now.addingTimeInterval(-200 * 86_400)]
        XCTAssertEqual(ReviewRequestPolicy.decide(state: state, currentVersion: "1.1.3", now: now),
                       .alreadyRequestedForVersion("1.1.3"))

        state.attemptedVersions = ["1.1.2"]
        XCTAssertEqual(ReviewRequestPolicy.decide(state: state, currentVersion: "1.1.3", now: now),
                       .eligible, "a new version may attempt once more")
    }

    func testAttemptsAreAtLeast120DaysApart() {
        let now = date("2026-09-14T12:00:00Z")
        var state = satisfiedReviewState()
        state.attemptedVersions = ["1.1.2"]
        state.attemptDates = [now.addingTimeInterval(-30 * 86_400)]
        XCTAssertEqual(ReviewRequestPolicy.decide(state: state, currentVersion: "1.1.3", now: now),
                       .tooSoonSincePreviousAttempt(30))
        state.attemptDates = [now.addingTimeInterval(-121 * 86_400)]
        XCTAssertEqual(ReviewRequestPolicy.decide(state: state, currentVersion: "1.1.3", now: now),
                       .eligible)
    }

    func testAtMostTwoAttemptsInAnyYear() {
        let now = date("2026-09-14T12:00:00Z")
        var state = satisfiedReviewState()
        state.attemptedVersions = ["1.1.1", "1.1.2"]
        state.attemptDates = [now.addingTimeInterval(-200 * 86_400),
                              now.addingTimeInterval(-330 * 86_400)]
        XCTAssertEqual(ReviewRequestPolicy.decide(state: state, currentVersion: "1.1.3", now: now),
                       .annualCapReached(2))
        state.attemptDates = [now.addingTimeInterval(-400 * 86_400),
                              now.addingTimeInterval(-500 * 86_400)]
        XCTAssertEqual(ReviewRequestPolicy.decide(state: state, currentVersion: "1.1.3", now: now),
                       .eligible, "attempts older than a year fall out of the cap")
    }

    /// Settings must deep-link to the App Store review sheet, not the website.
    func testRateLinkIsTheDirectAppStoreReviewURL() {
        XCTAssertEqual(ReviewRequestPolicy.appStoreID, "6780714383")
        let url = ReviewRequestPolicy.reviewURL.absoluteString
        XCTAssertTrue(url.contains("id6780714383"), "review URL must target app ID 6780714383")
        XCTAssertTrue(url.contains("action=write-review"))
        XCTAssertFalse(url.contains("dudleyapps.com"),
                       "the Dudley homepage is not a review destination")
    }

    /// The coordinator reads the launch counter `EBEvents.recordLaunch` keeps.
    func testTheCoordinatorAndTheLaunchEventShareOneLaunchCounter() {
        XCTAssertEqual(ReviewRequestPolicy.launchCountDefaultsKey, "ebLaunchCount")
    }

    @MainActor
    func testCoordinatorRecordsEligibilityBeforeCallingTheSystemAPIAndOnlyOnce() {
        var callCount = 0
        let now = date("2026-09-14T12:00:00Z")
        defaults.set(2, forKey: ReviewRequestPolicy.launchCountDefaultsKey)

        let coordinator = ReviewRequestCoordinator(defaults: defaults,
                                                   currentVersion: "1.1.3",
                                                   now: { now },
                                                   requestReview: { callCount += 1 })
        coordinator.noteForegroundSessionBegan()
        coordinator.noteSetCompleted(cardsViewed: 8)

        XCTAssertEqual(coordinator.requestReviewIfEligible(), .eligible)
        XCTAssertEqual(callCount, 1)
        XCTAssertTrue(coordinator.didCallSystemAPI)

        XCTAssertEqual(coordinator.requestReviewIfEligible(),
                       .alreadyRequestedForVersion("1.1.3"))
        XCTAssertEqual(callCount, 1, "the system API is called at most once per version")
    }

    @MainActor
    func testCoordinatorNeverAsksOnTheFirstLaunch() {
        var callCount = 0
        let now = date("2026-09-14T12:00:00Z")
        defaults.set(1, forKey: ReviewRequestPolicy.launchCountDefaultsKey)
        let coordinator = ReviewRequestCoordinator(defaults: defaults,
                                                   currentVersion: "1.1.3",
                                                   now: { now },
                                                   requestReview: { callCount += 1 })
        coordinator.noteForegroundSessionBegan()
        coordinator.noteSetCompleted(cardsViewed: 8)
        XCTAssertEqual(coordinator.requestReviewIfEligible(), .belowLaunchCount(1))
        XCTAssertEqual(callCount, 0)
    }

    @MainActor
    func testCoordinatorSuppressesAfterAnAdOrPurchaseInTheSameSessionOnly() {
        let now = date("2026-09-14T12:00:00Z")
        defaults.set(2, forKey: ReviewRequestPolicy.launchCountDefaultsKey)
        var callCount = 0
        let coordinator = ReviewRequestCoordinator(defaults: defaults,
                                                   currentVersion: "1.1.3",
                                                   now: { now },
                                                   requestReview: { callCount += 1 })
        coordinator.noteForegroundSessionBegan()
        coordinator.noteSetCompleted(cardsViewed: 8)
        coordinator.noteNegativeSessionEvent(.ad)
        XCTAssertEqual(coordinator.requestReviewIfEligible(), .negativeSession(.ad))
        coordinator.noteNegativeSessionEvent(.purchase)
        XCTAssertEqual(coordinator.requestReviewIfEligible(), .negativeSession(.purchase))
        XCTAssertEqual(callCount, 0)

        // A new foreground session lifts the deferral; the attempt was never spent.
        coordinator.noteForegroundSessionBegan()
        coordinator.noteSetCompleted(cardsViewed: 8)
        XCTAssertEqual(coordinator.requestReviewIfEligible(), .eligible)
        XCTAssertEqual(callCount, 1)
    }

    /// The attempt ledger survives a relaunch: the version is spent, and the
    /// next version has to wait 120 days.
    @MainActor
    func testCoordinatorPersistsTheAttemptLedgerAcrossLaunches() {
        let now = date("2026-09-14T12:00:00Z")
        defaults.set(2, forKey: ReviewRequestPolicy.launchCountDefaultsKey)
        let first = ReviewRequestCoordinator(defaults: defaults, currentVersion: "1.1.3",
                                             now: { now }, requestReview: {})
        first.noteForegroundSessionBegan()
        first.noteSetCompleted(cardsViewed: 8)
        XCTAssertEqual(first.requestReviewIfEligible(), .eligible)

        let sameVersion = ReviewRequestCoordinator(defaults: defaults, currentVersion: "1.1.3",
                                                   now: { now.addingTimeInterval(86_400) }, requestReview: {})
        sameVersion.noteForegroundSessionBegan()
        sameVersion.noteSetCompleted(cardsViewed: 8)
        XCTAssertEqual(sameVersion.requestReviewIfEligible(), .alreadyRequestedForVersion("1.1.3"))

        let nextVersion = ReviewRequestCoordinator(defaults: defaults, currentVersion: "1.1.4",
                                                   now: { now.addingTimeInterval(10 * 86_400) }, requestReview: {})
        nextVersion.noteForegroundSessionBegan()
        nextVersion.noteSetCompleted(cardsViewed: 8)
        XCTAssertEqual(nextVersion.requestReviewIfEligible(), .tooSoonSincePreviousAttempt(10))
    }

    /// An install that was asked under 1.1's single-slot ledger is not asked
    /// again for that version after the update.
    @MainActor
    func testALegacyRequestedVersionStillCountsAsASpentAttempt() {
        let now = date("2026-09-14T12:00:00Z")
        defaults.set(2, forKey: ReviewRequestPolicy.launchCountDefaultsKey)
        defaults.set("1.1.2", forKey: ReviewRequestPolicy.lastRequestedVersionDefaultsKey)
        let coordinator = ReviewRequestCoordinator(defaults: defaults, currentVersion: "1.1.2",
                                                   now: { now }, requestReview: {})
        coordinator.noteForegroundSessionBegan()
        coordinator.noteSetCompleted(cardsViewed: 8)
        XCTAssertEqual(coordinator.requestReviewIfEligible(), .alreadyRequestedForVersion("1.1.2"))
    }

    /// Eligibility is recorded locally *before* the system API is called, so
    /// `review_prompt_eligible` and `review_request_attempted` are distinct.
    @MainActor
    func testReviewEligibilityIsSignalledBeforeTheSystemAPI() {
        let now = date("2026-09-14T12:00:00Z")
        defaults.set(2, forKey: ReviewRequestPolicy.launchCountDefaultsKey)
        var order: [String] = []
        let coordinator = ReviewRequestCoordinator(defaults: defaults,
                                                   currentVersion: "1.1.3",
                                                   now: { now },
                                                   requestReview: { order.append("requested") })
        coordinator.onEligible = { order.append("eligible") }
        coordinator.noteForegroundSessionBegan()
        coordinator.noteSetCompleted(cardsViewed: 8)

        XCTAssertEqual(coordinator.requestReviewIfEligible(), .eligible)
        XCTAssertEqual(order, ["eligible", "requested"])

        XCTAssertEqual(coordinator.requestReviewIfEligible(),
                       .alreadyRequestedForVersion("1.1.3"))
        XCTAssertEqual(order, ["eligible", "requested"],
                       "an ineligible attempt signals nothing")
    }

    func testStreakBucketIsAClosedVocabulary() {
        XCTAssertEqual(ReviewRequestPolicy.streakBucket(0), "0-2")
        XCTAssertEqual(ReviewRequestPolicy.streakBucket(5), "3-7")
        XCTAssertEqual(ReviewRequestPolicy.streakBucket(12), "8-29")
        XCTAssertEqual(ReviewRequestPolicy.streakBucket(400), "30-plus")
    }

    // MARK: - 9b. Consent presentation (spec section 10.1)

    func testConsentChoicesArePresentedAfterTheFirstCompletedSetAndOnlyOnce() {
        XCTAssertFalse(ConsentPromptPolicy.eligible(completedSetCount: 0, alreadyShown: false),
                       "never on first launch")
        XCTAssertTrue(ConsentPromptPolicy.eligible(completedSetCount: 1, alreadyShown: false))
        XCTAssertFalse(ConsentPromptPolicy.eligible(completedSetCount: 4, alreadyShown: true),
                       "the contextual offer is made once")
    }

    /// The one-offer gate is persisted, and reads and writes the injected suite
    /// rather than a global, so it is testable and resettable.
    func testConsentPromptShownFlagRoundTripsThroughTheInjectedDefaults() {
        XCTAssertFalse(ConsentPromptPolicy.wasShown(in: defaults))
        XCTAssertTrue(ConsentPromptPolicy.eligible(
            completedSetCount: 1,
            alreadyShown: ConsentPromptPolicy.wasShown(in: defaults)))

        ConsentPromptPolicy.noteShown(in: defaults)

        XCTAssertTrue(ConsentPromptPolicy.wasShown(in: defaults))
        XCTAssertFalse(ConsentPromptPolicy.eligible(
            completedSetCount: 1,
            alreadyShown: ConsentPromptPolicy.wasShown(in: defaults)),
            "the contextual offer is never repeated")
        XCTAssertFalse(ConsentPromptPolicy.wasShown(in: UserDefaults(suiteName: suiteName + ".other")!),
                       "the flag is scoped to the suite it was written to")
    }

    /// Two unrelated asks must not land on one screen: the reminder primer waits
    /// a set while the consent choices are presented.
    func testReminderPrimerDefersWhileTheConsentPromptIsPresented() {
        XCTAssertFalse(NotificationPolicy.primerEligible(completedSetCount: 1,
                                                         primerAlreadyShown: false,
                                                         remindersEnabled: false,
                                                         consentPromptVisible: true))
        XCTAssertTrue(NotificationPolicy.primerEligible(completedSetCount: 2,
                                                        primerAlreadyShown: false,
                                                        remindersEnabled: false,
                                                        consentPromptVisible: false))
    }

    // MARK: - 10. Notifications (spec section 11.1)

    @MainActor
    private final class SpyNotificationCenter: EconNotificationScheduling {
        var authorization: EconNotificationAuthorization = .notDetermined
        var grantAuthorization = true
        var authorizationRequests = 0
        var added: [UNNotificationRequest] = []
        var addError: Error?
        var removedPending: [String] = []
        var removedDelivered: [String] = []

        nonisolated func econRequestAuthorization(_ completion: @escaping (Bool, Error?) -> Void) {
            Task { @MainActor in
                self.authorizationRequests += 1
                self.authorization = self.grantAuthorization ? .authorized : .denied
                completion(self.grantAuthorization, nil)
            }
        }

        nonisolated func econAuthorizationStatus(_ completion: @escaping (EconNotificationAuthorization) -> Void) {
            Task { @MainActor in completion(self.authorization) }
        }

        nonisolated func econAdd(_ request: UNNotificationRequest, completion: @escaping (Error?) -> Void) {
            Task { @MainActor in
                if let error = self.addError {
                    completion(error)
                    return
                }
                self.added.append(request)
                completion(nil)
            }
        }

        nonisolated func econRemovePendingRequests(withIdentifiers identifiers: [String]) {
            Task { @MainActor in
                self.removedPending.append(contentsOf: identifiers)
                self.added.removeAll { identifiers.contains($0.identifier) }
            }
        }

        nonisolated func econRemoveDeliveredNotifications(withIdentifiers identifiers: [String]) {
            Task { @MainActor in self.removedDelivered.append(contentsOf: identifiers) }
        }

        nonisolated func econPendingRequestIdentifiers(_ completion: @escaping ([String]) -> Void) {
            Task { @MainActor in completion(self.added.map(\.identifier)) }
        }
    }

    @MainActor
    private func settle() async {
        for _ in 0..<40 { await Task.yield() }
    }

    func testReminderIsScheduledForSevenPMLocalDaily() {
        XCTAssertEqual(NotificationPolicy.reminderHour, 19)
        XCTAssertEqual(NotificationPolicy.reminderMinute, 0)
        XCTAssertEqual(NotificationPolicy.reminderIdentifier, "econbyte.daily-reminder")

        let request = NotificationPolicy.makeReminderRequest()
        XCTAssertEqual(request.identifier, "econbyte.daily-reminder")
        guard let trigger = request.trigger as? UNCalendarNotificationTrigger else {
            return XCTFail("the reminder must use a repeating calendar trigger")
        }
        XCTAssertTrue(trigger.repeats)
        XCTAssertEqual(trigger.dateComponents.hour, 19)
        XCTAssertEqual(trigger.dateComponents.minute, 0)
    }

    /// No financial claim, urgency, or streak-loss pressure (spec section 11.1).
    /// Version 1.0 shipped "Your streak is at risk"; 1.1 must not.
    func testReminderCopyCarriesNoFinancialClaimUrgencyOrStreakPressure() {
        XCTAssertFalse(NotificationPolicy.prohibitedCopyTerms.isEmpty)
        for term in ["risk", "streak", "urgent", "hurry", "last chance", "don't lose",
                     "invest", "money", "returns", "market", "rate"] {
            XCTAssertTrue(NotificationPolicy.prohibitedCopyTerms.contains(term),
                          "\(term) belongs on the prohibited-copy list")
        }
        XCTAssertTrue(NotificationPolicy.copyIsCompliant(NotificationPolicy.reminderBody),
                      "shipped body copy must pass its own gate")
        XCTAssertTrue(NotificationPolicy.copyIsCompliant(NotificationPolicy.reminderTitle))
        XCTAssertFalse(NotificationPolicy.copyIsCompliant("Your streak is at risk 🔥"),
                       "the 1.0 reminder copy must now fail the gate")
        XCTAssertFalse(NotificationPolicy.copyIsCompliant("Hurry — rates change today"))
    }

    func testPrimerAppearsOnlyAfterTheFirstCompletedSetAndOnlyOnce() {
        XCTAssertFalse(NotificationPolicy.primerEligible(completedSetCount: 0,
                                                         primerAlreadyShown: false,
                                                         remindersEnabled: false))
        XCTAssertTrue(NotificationPolicy.primerEligible(completedSetCount: 1,
                                                        primerAlreadyShown: false,
                                                        remindersEnabled: false))
        XCTAssertFalse(NotificationPolicy.primerEligible(completedSetCount: 4,
                                                         primerAlreadyShown: true,
                                                         remindersEnabled: false))
        XCTAssertFalse(NotificationPolicy.primerEligible(completedSetCount: 4,
                                                         primerAlreadyShown: false,
                                                         remindersEnabled: true))
    }

    @MainActor
    func testRemindersDefaultOffAndDoNotPromptOnLaunch() async {
        let center = SpyNotificationCenter()
        let coordinator = NotificationCoordinator(center: center, defaults: defaults)
        await settle()
        XCTAssertFalse(coordinator.remindersEnabled, "reminders default off")
        XCTAssertEqual(center.authorizationRequests, 0,
                       "the system dialog must not appear without an explicit opt-in")
        XCTAssertTrue(center.added.isEmpty)
    }

    @MainActor
    func testEnablingRemindersRequestsAuthorizationThenSchedulesExactlyOne() async {
        let center = SpyNotificationCenter()
        let coordinator = NotificationCoordinator(center: center, defaults: defaults)
        coordinator.enableReminders()
        await settle()

        XCTAssertEqual(center.authorizationRequests, 1)
        XCTAssertTrue(coordinator.remindersEnabled)
        XCTAssertEqual(center.added.count, 1)
        XCTAssertEqual(center.added.first?.identifier, NotificationPolicy.reminderIdentifier)

        coordinator.reconcileOnForeground()
        await settle()
        XCTAssertEqual(center.added.count, 1, "reconciling must not duplicate the request")
    }

    @MainActor
    func testDisablingRemovesPendingAndDeliveredReminders() async {
        let center = SpyNotificationCenter()
        let coordinator = NotificationCoordinator(center: center, defaults: defaults)
        coordinator.enableReminders()
        await settle()
        coordinator.disableReminders()
        await settle()

        XCTAssertFalse(coordinator.remindersEnabled)
        XCTAssertTrue(center.removedPending.contains(NotificationPolicy.reminderIdentifier))
        XCTAssertTrue(center.removedDelivered.contains(NotificationPolicy.reminderIdentifier))
        XCTAssertTrue(center.added.isEmpty)
    }

    /// The result reported is the system dialog's, not the toggle's intent.
    @MainActor
    func testAuthorizationOutcomeIsReportedFromTheDialogNotTheToggle() async {
        let center = SpyNotificationCenter()
        center.grantAuthorization = false
        let coordinator = NotificationCoordinator(center: center, defaults: defaults)

        var results: [Bool] = []
        coordinator.enableReminders { results.append($0) }
        await settle()

        XCTAssertEqual(results, [false],
                       "a denied dialog must not be recorded as a success")
        XCTAssertFalse(coordinator.remindersEnabled)
    }

    /// Paths where iOS presents no dialog must report nothing: reporting them
    /// is the intent-vs-outcome conflation the event contract exists to avoid.
    @MainActor
    func testPathsThatPresentNoDialogReportNoAuthorizationResult() async {
        // Already authorized: iOS returns immediately and shows nothing.
        let authorized = SpyNotificationCenter()
        authorized.authorization = .authorized
        let a = NotificationCoordinator(center: authorized, defaults: defaults)
        await settle()
        var aResults: [Bool] = []
        a.enableReminders { aResults.append($0) }
        await settle()
        XCTAssertTrue(a.remindersEnabled, "an authorized reader still gets reminders on")
        XCTAssertTrue(aResults.isEmpty, "no dialog resolved, so nothing is reported")

        // Already denied: iOS never re-presents.
        let denied = SpyNotificationCenter()
        denied.authorization = .denied
        let d = NotificationCoordinator(center: denied,
                                        defaults: UserDefaults(suiteName: suiteName + ".denied")!)
        await settle()
        var dResults: [Bool] = []
        d.enableReminders { dResults.append($0) }
        await settle()
        XCTAssertEqual(denied.authorizationRequests, 0)
        XCTAssertTrue(dResults.isEmpty)

        // Already enabled: nothing happens at all.
        var eResults: [Bool] = []
        a.enableReminders { eResults.append($0) }
        await settle()
        XCTAssertTrue(eResults.isEmpty)
    }

    /// A 1.0 upgrader who denied notifications must not be shown a primer whose
    /// button cannot do anything.
    func testPrimerIsSuppressedForAReaderWhoAlreadyDeniedNotifications() {
        XCTAssertFalse(NotificationPolicy.primerEligible(completedSetCount: 3,
                                                         primerAlreadyShown: false,
                                                         remindersEnabled: false,
                                                         consentPromptVisible: false,
                                                         authorizationDenied: true))
        XCTAssertTrue(NotificationPolicy.primerEligible(completedSetCount: 3,
                                                        primerAlreadyShown: false,
                                                        remindersEnabled: false,
                                                        consentPromptVisible: false,
                                                        authorizationDenied: false))
    }

    @MainActor
    func testScheduleFailureRaisesADiagnosticCode() async {
        let center = SpyNotificationCenter()
        center.addError = NSError(domain: "UNErrorDomain", code: 1)
        let coordinator = NotificationCoordinator(center: center, defaults: defaults)

        var failures: [Error] = []
        coordinator.onScheduleFailure = { failures.append($0) }
        coordinator.enableReminders()
        await settle()

        XCTAssertEqual(failures.count, 1,
                       "a scheduling failure must surface notification_schedule_failed")
        XCTAssertEqual((failures.first as NSError?)?.domain, "UNErrorDomain")
    }

    @MainActor
    func testAuthorizationDenialLeavesRemindersOffAndDoesNotRePrompt() async {
        let center = SpyNotificationCenter()
        center.grantAuthorization = false
        let coordinator = NotificationCoordinator(center: center, defaults: defaults)
        coordinator.enableReminders()
        await settle()

        XCTAssertFalse(coordinator.remindersEnabled)
        XCTAssertEqual(coordinator.authorization, .denied)
        XCTAssertTrue(center.added.isEmpty)

        coordinator.enableReminders()
        await settle()
        XCTAssertEqual(center.authorizationRequests, 1,
                       "a denied user is linked to Settings, never re-prompted")
    }

    // MARK: - 11. Catalog runtime switch (plan Task 5)

    /// Task 4 shipped the validated 15-topic catalog but deliberately left the
    /// runtime on the stale 10-topic `cards.json`. Task 5 completes the switch.
    @MainActor
    func testContentStoreServesTheValidatedVersion11Catalog() {
        let store = ContentStore.shared
        XCTAssertEqual(store.topics.count, 15)
        XCTAssertEqual(store.allCards.count, CurriculumCatalog.expectedCardCount)
        XCTAssertEqual(Array(store.topics.prefix(3).map(\.id)),
                       ["inflation", "interest-rates", "gdp"])
    }

    /// Bookmarks and per-card state are keyed on `cardID`, so every shipped 1.0
    /// identifier must still resolve after the update.
    @MainActor
    func testEveryShippedCardIdentifierStillResolvesAfterTheCatalogSwitch() throws {
        let catalog = try CurriculumCatalog.loadValidated()
        let runtimeIDs = Set(ContentStore.shared.allCards.map(\.id))
        for card in catalog.allCards {
            XCTAssertTrue(runtimeIDs.contains(card.cardID),
                          "\(card.cardID) must be reachable from the runtime store")
        }
        let prefixes = ["inf", "ir", "gdp", "sd", "lm", "tt", "hm", "cb", "rec", "dd"]
        for prefix in prefixes {
            for index in 1...8 {
                let id = String(format: "%@-%03d", prefix, index)
                XCTAssertTrue(runtimeIDs.contains(id),
                              "1.0 card \(id) must survive so saved bookmarks keep resolving")
            }
        }
    }

    @MainActor
    func testCardStatePersistenceKeyIsUnchanged() {
        XCTAssertEqual(ContentStore.cardStatesDefaultsKey,
                       "com.nsantulli.econbyte.cardStates",
                       "changing this key would silently discard every saved bookmark")
    }

    @MainActor
    func testFreeAndPaidPartitionMatchesTheCatalog() throws {
        let catalog = try CurriculumCatalog.loadValidated()
        let store = ContentStore.shared
        XCTAssertEqual(Set(catalog.freeTopicIDs), ContentStore.freeTopicIds)
        for topic in catalog.topics {
            XCTAssertEqual(store.isTopicFree(topic.topicID), topic.isFree,
                           "\(topic.topicID) access classification drifted")
        }
        XCTAssertEqual(catalog.topics.filter(\.isFree).count, 2)
        XCTAssertEqual(catalog.topics.filter { !$0.isFree }.count, 13)
    }

    @MainActor
    func testFreeUsersOnlyEverSeeFreeTopicCards() {
        let store = ContentStore.shared
        let free = store.dailySet(count: 8, unlockedAll: false)
        XCTAssertFalse(free.isEmpty)
        for card in free {
            XCTAssertTrue(store.isTopicFree(card.topicId),
                          "\(card.id) leaked into the free daily pool")
        }
        XCTAssertTrue(store.cards(for: "gdp", unlockedAll: false).isEmpty)
        XCTAssertEqual(store.cards(for: "gdp", unlockedAll: true).count, CurriculumCatalog.expectedCardsPerTopic)
        XCTAssertEqual(store.cards(for: "economic-indicators", unlockedAll: true).count, CurriculumCatalog.expectedCardsPerTopic,
                       "the five new 1.1 topics must be reachable with Unlock All")
    }

    /// The stale 80-card 1.0 content file must no longer ship inside the binary.
    func testStaleCardsJSONIsNoLongerBundled() {
        XCTAssertNil(Bundle.curriculumBundle.url(forResource: "cards", withExtension: "json"),
                     "cards.json is superseded by curriculum-v1.1.json")
    }

    @MainActor
    func testCardCopySurfacesTheSourcedExampleAndDisclaimer() throws {
        let catalog = try CurriculumCatalog.loadValidated()
        guard let first = catalog.allCards.first,
              let runtime = ContentStore.shared.allCards.first(where: { $0.id == first.cardID })
        else { return XCTFail("card mapping missing") }
        XCTAssertEqual(runtime.concept, first.title)
        XCTAssertEqual(runtime.conceptBody, first.definition)
        XCTAssertEqual(runtime.exampleBody, first.example)
        XCTAssertTrue(runtime.source.contains(first.source.organization))
        XCTAssertEqual(runtime.difficulty, first.difficulty.rawValue)
    }
}

/// Owner decision #25 — the About sheet refers users to every other money app.
///
/// The defect this closes: `DudleyApps.all` left Table Talk, EconByte and Last
/// Human at `appStoreID: nil`, and carried no row at all for Last Human, so
/// `DudleyApps.crossPromo` — which drops any row without an id — collapsed to
/// Powell Prowl in every app. "More by Dudley" listed one app.
///
/// The ids are written out in full rather than read back from `DudleyApps`: a
/// test that rebuilds its expectation from the value under test follows a typo
/// instead of catching it.
final class DudleyCrossPromoLiveIDTests: XCTestCase {

    /// Apps that must carry a live App Store id today (decision #26: Last Human
    /// stays in `all` with nil until the storefront resolves).
    private static let liveIDs: [String: String] = [
        "powellprowl": "6775539250",
        "viberater": "6780704282",
        "tabletalk": "6780714565",
        "econbyte": "6780714383",
    ]

    private static let pendingStorefrontKey = "lasthuman"

    /// `crossPromo` excludes this app by matching `current` against a row id.
    /// If `current` names no row the filter quietly matches nothing — which is
    /// the shape Last Human shipped, with `current` "lasthuman" and no
    /// "lasthuman" row — so the app would have promoted itself the moment one
    /// was added.
    func testThisAppsCurrentIdNamesARealPortfolioRow() {
        XCTAssertTrue(DudleyApps.all.contains { $0.id == DudleyApps.current },
                      "DudleyApps.current is \"\(DudleyApps.current)\" but no row carries that id")
        XCTAssertNotNil(Self.liveIDs[DudleyApps.current],
                        "DudleyApps.current is \"\(DudleyApps.current)\", not a known studio app")
    }

    /// Every live money app appears once with its id; Last Human stays nil (#26).
    func testEveryMoneyAppIsPresentOnceWithItsLiveAppStoreID() {
        XCTAssertEqual(Set(DudleyApps.all.map(\.id)).count, DudleyApps.all.count,
                       "a duplicate row lists the same app twice in the sheet")
        XCTAssertEqual(DudleyApps.all.count, Self.liveIDs.count + 1,
                       "portfolio should be the live apps plus pending Last Human")

        for (key, expected) in Self.liveIDs.sorted(by: { $0.key < $1.key }) {
            guard let row = DudleyApps.all.first(where: { $0.id == key }) else {
                XCTFail("the portfolio has no row for \"\(key)\"")
                continue
            }
            XCTAssertNotNil(row.appStoreID, "\"\(key)\" is back to appStoreID: nil")
            XCTAssertEqual(row.appStoreID, expected, "\"\(key)\" carries the wrong App Store id")
        }

        guard let lh = DudleyApps.all.first(where: { $0.id == Self.pendingStorefrontKey }) else {
            return XCTFail("the portfolio has no row for \"\(Self.pendingStorefrontKey)\"")
        }
        XCTAssertNil(lh.appStoreID,
                     "Last Human must stay appStoreID: nil until the storefront is live (#26)")
    }

    /// What the user actually sees: every other *live* app, never this one, never LH.
    func testCrossPromoOffersEveryOtherMoneyAppAndNeverThisOne() {
        let promoted = Set(DudleyApps.crossPromo.map(\.id))

        XCTAssertFalse(promoted.contains(DudleyApps.current),
                       "\"\(DudleyApps.current)\" promotes itself")
        XCTAssertFalse(promoted.contains(Self.pendingStorefrontKey),
                       "Last Human must stay hidden until live (#26)")
        XCTAssertEqual(promoted, Set(Self.liveIDs.keys).subtracting([DudleyApps.current]),
                       "the cross-promo list is not the rest of the live portfolio")
        XCTAssertEqual(DudleyApps.crossPromo.count,
                       Self.liveIDs.keys.filter { $0 != DudleyApps.current }.count)
    }

    /// A promoted row whose `storeURL` is nil is a dead tile: `DudleyAboutSheet`
    /// falls back to dudleyapps.com, so the tap leaves the App Store entirely
    /// and the referral the Owner asked for never happens.
    func testEveryPromotedAppOpensItsOwnStorePage() {
        for app in DudleyApps.crossPromo {
            guard let id = app.appStoreID else {
                XCTFail("\"\(app.id)\" is promoted with a nil appStoreID")
                continue
            }
            XCTAssertEqual(app.storeURL?.absoluteString,
                           "itms-apps://apps.apple.com/app/id\(id)",
                           "\"\(app.id)\" does not open its own store page")
        }
    }
}
