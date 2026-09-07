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
        XCTAssertEqual(PurchaseManager.ProductID.allCases.count, 2,
                       "EconByte ships exactly the two approved non-consumables")
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

    func testRestrictedRegionsCoverTheEEAAndUnitedKingdom() {
        for code in ["DE", "FR", "IE", "IT", "ES", "NL", "SE", "PL", "NO", "IS", "LI", "GB"] {
            XCTAssertEqual(EconAdRegion.state(for: code), .restricted,
                           "\(code) must be ad-restricted under DUD-224")
        }
        XCTAssertEqual(EconAdRegion.restrictedRegionCodes.count, 31,
                       "EU 27 + Iceland, Liechtenstein, Norway + United Kingdom")
    }

    func testAllowedRegionIsAllowed() {
        XCTAssertEqual(EconAdRegion.state(for: "US"), .allowed)
        XCTAssertEqual(EconAdRegion.state(for: "us"), .allowed)
    }

    /// An undeterminable region fails closed — no ads rather than an untested
    /// consent posture.
    func testUnknownRegionFailsClosed() {
        XCTAssertEqual(EconAdRegion.state(for: nil), .unknown)
        XCTAssertEqual(EconAdRegion.state(for: ""), .unknown)
        XCTAssertFalse(EconAdRegionState.unknown.permitsAdRequests)
        XCTAssertFalse(EconAdRegionState.restricted.permitsAdRequests)
        XCTAssertTrue(EconAdRegionState.allowed.permitsAdRequests)
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

    func testShippedThresholdsMatchTheSpecification() {
        let thresholds = EconAdThresholds()
        XCTAssertEqual(thresholds.minimumCompletedSets, 2)
        XCTAssertEqual(thresholds.setsSinceLastAd, 2)
        XCTAssertEqual(thresholds.minimumInterval, 15 * 60)
        XCTAssertEqual(thresholds.perSession, 1)
        XCTAssertEqual(thresholds.perDay, 2)
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

    func testTwoCompletedSetsMustElapseBetweenInterstitials() {
        let now = date("2026-09-01T12:00:00Z")
        var state = eligibleState(now: now, dayKey: "2026-09-01")
        state.setsSinceLastAd = 1
        XCTAssertEqual(decide(state: state, now: now, dayKey: "2026-09-01"),
                       .belowSetsSinceLastAd(2))
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
        state.shownThisSession = 1
        XCTAssertEqual(decide(state: state, now: now, dayKey: "2026-09-01"),
                       .sessionCapReached)
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
        monetization.noteForegroundSessionBegan()
        for _ in 0..<3 { monetization.noteSetCompleted(normally: true) }

        let first = await monetization.presentIfEligibleAtSetExit()
        XCTAssertEqual(first, .presented)
        XCTAssertEqual(monetization.state.shownThisSession, 1)
        XCTAssertEqual(monetization.state.shownToday, 1)
        XCTAssertEqual(monetization.state.setsSinceLastAd, 0)

        monetization.noteSetCompleted(normally: true)
        let second = await monetization.presentIfEligibleAtSetExit()
        XCTAssertEqual(second, .notEligible(.belowSetsSinceLastAd(2)))
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

    // MARK: - 9. Review requests (spec section 11.2)

    private func satisfiedReviewState(now: Date) -> ReviewRequestState {
        var state = ReviewRequestState()
        state.completedSetCount = 3
        state.firstLaunchDate = now.addingTimeInterval(-8 * 86_400)
        state.currentSessionCompletedSet = true
        return state
    }

    func testReviewThresholdsMatchTheSpecification() {
        XCTAssertEqual(ReviewRequestPolicy.thresholds.minimumCompletedSets, 3)
        XCTAssertEqual(ReviewRequestPolicy.thresholds.minimumDaysSinceFirstLaunch, 7)
    }

    func testReviewIsEligibleWhenEveryConditionHolds() {
        let now = date("2026-09-10T12:00:00Z")
        XCTAssertEqual(ReviewRequestPolicy.decide(state: satisfiedReviewState(now: now),
                                                  currentVersion: "1.1",
                                                  now: now),
                       .eligible)
    }

    func testReviewNeedsThreeCompletedSets() {
        let now = date("2026-09-10T12:00:00Z")
        var state = satisfiedReviewState(now: now)
        state.completedSetCount = 2
        XCTAssertEqual(ReviewRequestPolicy.decide(state: state, currentVersion: "1.1", now: now),
                       .insufficientCompletedSets(3))
    }

    func testReviewNeedsSevenDaysSinceFirstLaunch() {
        let now = date("2026-09-10T12:00:00Z")
        var state = satisfiedReviewState(now: now)
        state.firstLaunchDate = now.addingTimeInterval(-3 * 86_400)
        XCTAssertEqual(ReviewRequestPolicy.decide(state: state, currentVersion: "1.1", now: now),
                       .insufficientDaysSinceFirstLaunch(7))
    }

    func testReviewNeedsACompletedSessionSet() {
        let now = date("2026-09-10T12:00:00Z")
        var state = satisfiedReviewState(now: now)
        state.currentSessionCompletedSet = false
        XCTAssertEqual(ReviewRequestPolicy.decide(state: state, currentVersion: "1.1", now: now),
                       .sessionNotCompleted)
    }

    func testAnyNegativeSessionEventSuppressesTheReviewRequest() {
        let now = date("2026-09-10T12:00:00Z")
        for event in EconNegativeSessionEvent.allCases {
            var state = satisfiedReviewState(now: now)
            state.negativeSessionEvents = [event]
            XCTAssertEqual(ReviewRequestPolicy.decide(state: state, currentVersion: "1.1", now: now),
                           .negativeSession(event),
                           "\(event.rawValue) in the session must suppress the prompt")
        }
    }

    func testReviewIsAttemptedAtMostOncePerAppVersion() {
        let now = date("2026-09-10T12:00:00Z")
        var state = satisfiedReviewState(now: now)
        state.lastRequestedVersion = "1.1"
        XCTAssertEqual(ReviewRequestPolicy.decide(state: state, currentVersion: "1.1", now: now),
                       .alreadyRequestedForVersion("1.1"))

        state.lastRequestedVersion = "1.0"
        XCTAssertEqual(ReviewRequestPolicy.decide(state: state, currentVersion: "1.1", now: now),
                       .eligible, "a new version may attempt once more")
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

    @MainActor
    func testCoordinatorRecordsEligibilityBeforeCallingTheSystemAPIAndOnlyOnce() {
        var callCount = 0
        let now = date("2026-09-10T12:00:00Z")
        defaults.set(now.addingTimeInterval(-9 * 86_400),
                     forKey: ReviewRequestPolicy.firstLaunchDefaultsKey)

        let coordinator = ReviewRequestCoordinator(defaults: defaults,
                                                   currentVersion: "1.1",
                                                   now: { now },
                                                   requestReview: { callCount += 1 })
        coordinator.noteForegroundSessionBegan()
        for _ in 0..<3 { coordinator.noteSetCompleted() }

        XCTAssertEqual(coordinator.requestReviewIfEligible(), .eligible)
        XCTAssertEqual(callCount, 1)
        XCTAssertTrue(coordinator.didCallSystemAPI)

        XCTAssertEqual(coordinator.requestReviewIfEligible(),
                       .alreadyRequestedForVersion("1.1"))
        XCTAssertEqual(callCount, 1, "the system API is called at most once per version")
    }

    @MainActor
    func testCoordinatorSuppressesAfterAnAdOrPurchaseFailureInTheSameSession() {
        let now = date("2026-09-10T12:00:00Z")
        defaults.set(now.addingTimeInterval(-9 * 86_400),
                     forKey: ReviewRequestPolicy.firstLaunchDefaultsKey)
        var callCount = 0
        let coordinator = ReviewRequestCoordinator(defaults: defaults,
                                                   currentVersion: "1.1",
                                                   now: { now },
                                                   requestReview: { callCount += 1 })
        coordinator.noteForegroundSessionBegan()
        for _ in 0..<3 { coordinator.noteSetCompleted() }
        coordinator.noteNegativeSessionEvent(.ad)

        XCTAssertEqual(coordinator.requestReviewIfEligible(), .negativeSession(.ad))
        XCTAssertEqual(callCount, 0)
    }

    /// Eligibility is recorded locally *before* the system API is called, so
    /// `review_prompt_eligible` and `review_prompt_requested` are distinct.
    @MainActor
    func testReviewEligibilityIsSignalledBeforeTheSystemAPI() {
        let now = date("2026-09-10T12:00:00Z")
        defaults.set(now.addingTimeInterval(-9 * 86_400),
                     forKey: ReviewRequestPolicy.firstLaunchDefaultsKey)
        var order: [String] = []
        let coordinator = ReviewRequestCoordinator(defaults: defaults,
                                                   currentVersion: "1.1",
                                                   now: { now },
                                                   requestReview: { order.append("requested") })
        coordinator.onEligible = { order.append("eligible") }
        coordinator.noteForegroundSessionBegan()
        for _ in 0..<3 { coordinator.noteSetCompleted() }

        XCTAssertEqual(coordinator.requestReviewIfEligible(), .eligible)
        XCTAssertEqual(order, ["eligible", "requested"])

        XCTAssertEqual(coordinator.requestReviewIfEligible(),
                       .alreadyRequestedForVersion("1.1"))
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
        XCTAssertEqual(store.allCards.count, 120)
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
        XCTAssertEqual(store.cards(for: "gdp", unlockedAll: true).count, 8)
        XCTAssertEqual(store.cards(for: "economic-indicators", unlockedAll: true).count, 8,
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
