import XCTest
@testable import EconByte

/// App Tracking Transparency, restored in 1.1.2 build 13 after App Review
/// rejected build 12 under Guideline 5.1.2(i).
///
/// The rejection was not "you have no prompt" in the abstract — it was that the
/// published App Privacy label answers "Device ID: used to track you" while the
/// binary never asks. Restoring a prompt is therefore only half a fix; restoring
/// it in the WRONG ORDER reproduces the same defect with extra steps, which is
/// what live 1.1.1 build 8 does today (it preloads an ad at launch and asks at
/// the first interstitial, long after the first request has already gone out).
///
/// So this file asserts the ordering, not the existence:
///
///  1. No provider call — SDK start, preload, or re-preload — happens before the
///     tracking decision.
///  2. (Phase 14 hardening, after the 1.1.3 App Review 2.1 rejection) The
///     prompt is owed exactly while iOS has no answer: an ask iOS never
///     presented is asked again — on the next launch too — and an answered
///     status is never prompted.
///  3. Every answer moves the app forward (authorized, denied, restricted); a
///     prompt iOS declined to present keeps ads off until it is answered.
///  4. Every request stays non-personalized on every outcome.
///
/// ATT itself cannot be exercised here — there is no dialog in a unit test and
/// the status is process-global — so the framework sits behind
/// `EconTrackingAuthorizing` and the stub below stands in for it. The claim that
/// the app really links the framework and really carries the usage description
/// is made against the built artefacts in `InstrumentationPrivacyTests`.
@MainActor
final class TrackingAuthorizationTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "eb.att.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - Doubles

    /// One ordered log shared by the prompt and the ad adapter, so "before" is
    /// asserted as a position in a sequence rather than inferred from counters.
    private final class CallLog {
        private(set) var entries: [String] = []
        func record(_ entry: String) { entries.append(entry) }
        func firstIndex(of entry: String) -> Int? { entries.firstIndex(of: entry) }
        var adRequests: [String] { entries.filter { $0.hasPrefix("ad.") } }
    }

    @MainActor
    private final class StubTracking: EconTrackingAuthorizing {
        var status: EconTrackingStatus
        /// What the system dialog resolves to. `.notDetermined` models the case
        /// iOS really has: it declined to present the prompt at all.
        var resolvesTo: EconTrackingStatus
        private(set) var requestCount = 0
        private let log: CallLog

        init(status: EconTrackingStatus, resolvesTo: EconTrackingStatus? = nil, log: CallLog) {
            self.status = status
            self.resolvesTo = resolvesTo ?? status
            self.log = log
        }

        func requestAuthorization() async -> EconTrackingStatus {
            requestCount += 1
            log.record("att.request")
            status = resolvesTo
            return status
        }
    }

    @MainActor
    private final class LoggingAdapter: EconInterstitialAdapting {
        var isAdLoaded = false
        var onAdDismissed: ((Bool) -> Void)?
        private(set) var startCount = 0
        private(set) var preloadCount = 0
        private(set) var lastPolicy: EconAdRequestPolicy?
        private let log: CallLog

        init(log: CallLog) { self.log = log }

        func startSDK(policy: EconAdRequestPolicy) {
            startCount += 1
            lastPolicy = policy
            log.record("ad.startSDK")
        }

        func preload(policy: EconAdRequestPolicy) {
            preloadCount += 1
            lastPolicy = policy
            log.record("ad.preload")
        }

        func discardLoadedAd() { isAdLoaded = false }

        func present() async -> Bool {
            log.record("ad.present")
            return true
        }
    }

    private func makeMonetization(_ log: CallLog,
                                  tracking: StubTracking,
                                  adapter: LoggingAdapter,
                                  region: EconAdRegionState = .allowed) -> EconMonetization {
        EconMonetization(adapter: adapter,
                         defaults: defaults,
                         now: { Date(timeIntervalSince1970: 1_788_000_000) },
                         region: { region },
                         tracking: tracking)
    }

    // MARK: - 1. No ad request may precede the decision

    /// The gate itself. A fresh install has no answer, so the ad SDK must not
    /// even be initialised — `startSDK` opens a connection to the ad network,
    /// and 5.1.2(i) is about what happens before the reader is asked.
    func testTheAdSDKIsNotStartedWhileTheTrackingDecisionIsOutstanding() {
        let log = CallLog()
        let adapter = LoggingAdapter(log: log)
        let tracking = StubTracking(status: .notDetermined, log: log)
        let monetization = makeMonetization(log, tracking: tracking, adapter: adapter)

        monetization.startAdsIfPermitted()

        XCTAssertEqual(adapter.startCount, 0,
                       "the ad SDK must not start before the reader has answered ATT")
        XCTAssertEqual(adapter.preloadCount, 0)
        XCTAssertFalse(monetization.didStartSDK)
        XCTAssertTrue(log.adRequests.isEmpty, "no provider call may precede the decision")
    }

    /// The lifecycle path never prompts and never requests before the decision.
    /// 1.1.4 does ask ATT at first launch, but only from
    /// `FirstLaunchPermissionsCoordinator`, after the studio intro and in order
    /// with the notifications prompt (`FirstLaunchPermissionsTests`); the
    /// foreground hook itself must stay inert until the reader has answered.
    func testNothingHappensAtLaunchWithNoCompletedSession() {
        let log = CallLog()
        let adapter = LoggingAdapter(log: log)
        let tracking = StubTracking(status: .notDetermined, resolvesTo: .authorized, log: log)
        let monetization = makeMonetization(log, tracking: tracking, adapter: adapter)

        // Exactly what `EconGrowth.applicationDidBecomeActive` does.
        monetization.noteForegroundSessionBegan()
        monetization.startAdsIfPermitted()

        XCTAssertEqual(tracking.requestCount, 0, "the lifecycle hook must never present the ATT prompt")
        XCTAssertTrue(log.entries.isEmpty, "launch must neither prompt nor request")
    }

    /// The whole ordering, end to end: the prompt is answered, and only then
    /// does the first provider call happen.
    func testThePromptPrecedesTheFirstAdRequest() async {
        let log = CallLog()
        let adapter = LoggingAdapter(log: log)
        let tracking = StubTracking(status: .notDetermined, resolvesTo: .authorized, log: log)
        let monetization = makeMonetization(log, tracking: tracking, adapter: adapter)

        monetization.noteForegroundSessionBegan()
        monetization.startAdsIfPermitted()          // launch: gated, does nothing
        monetization.noteSetCompleted(normally: true)
        await monetization.resolveTrackingAuthorizationIfNeeded()

        let promptIndex = log.firstIndex(of: "att.request")
        let firstRequestIndex = log.entries.firstIndex { $0.hasPrefix("ad.") }
        XCTAssertNotNil(promptIndex, "the prompt must actually be presented")
        XCTAssertNotNil(firstRequestIndex, "ads must start once the decision exists")
        XCTAssertLessThan(promptIndex ?? .max, firstRequestIndex ?? .min,
                          "the ATT prompt must be answered before the first ad request: "
                           + log.entries.joined(separator: " -> "))
        XCTAssertEqual(log.entries.first, "att.request",
                       "nothing at all may precede the prompt")
    }

    /// The exit that carries the system dialog carries no interstitial. Same
    /// house rule the notification permission prompt already follows — a system
    /// dialog is an interruption, and two in a row is two too many.
    func testThePromptBlocksAnAdAtTheSameExit() async {
        let log = CallLog()
        let adapter = LoggingAdapter(log: log)
        let tracking = StubTracking(status: .notDetermined, resolvesTo: .authorized, log: log)
        let monetization = makeMonetization(log, tracking: tracking, adapter: adapter)

        monetization.noteForegroundSessionBegan()
        for _ in 0..<3 { monetization.noteSetCompleted(normally: true) }
        await monetization.resolveTrackingAuthorizationIfNeeded()

        XCTAssertTrue(monetization.activeBlockers.contains(.systemPrompt))
        XCTAssertEqual(monetization.decisionAtSetExit(), .blocked(.systemPrompt))
    }

    // MARK: - 2. Once per install

    func testThePromptIsAskedOnceWithinASession() async {
        let log = CallLog()
        let adapter = LoggingAdapter(log: log)
        let tracking = StubTracking(status: .notDetermined, resolvesTo: .denied, log: log)
        let monetization = makeMonetization(log, tracking: tracking, adapter: adapter)

        await monetization.resolveTrackingAuthorizationIfNeeded()
        await monetization.resolveTrackingAuthorizationIfNeeded()
        await monetization.resolveTrackingAuthorizationIfNeeded()

        XCTAssertEqual(tracking.requestCount, 1, "iOS offers one prompt per install")
        XCTAssertEqual(log.entries.filter { $0 == "att.request" }.count, 1)
    }

    /// Phase 14 (1.1.3 App Review 2.1, 2026-09-15): the state iOS leaves when it
    /// declines to present the dialog — status still `.notDetermined` — is NOT
    /// an answer. Builds 13–15 recorded it as spent, so one silent no-show hid
    /// the prompt for the rest of the install and let ads start unanswered.
    func testAPromptIOSNeverPresentedIsAskedAgainOnTheNextLaunchAndAdsWaitForTheAnswer() async {
        let log = CallLog()
        let firstTracking = StubTracking(status: .notDetermined, resolvesTo: .notDetermined, log: log)
        let firstAdapter = LoggingAdapter(log: log)
        let first = makeMonetization(log, tracking: firstTracking, adapter: firstAdapter)
        await first.resolveTrackingAuthorizationIfNeeded()
        XCTAssertEqual(firstTracking.requestCount, 1)
        XCTAssertTrue(first.didRequestTrackingPrompt, "the ask is still recorded, as evidence")
        XCTAssertFalse(first.adRequestsPermitted, "an ask iOS did not present is not an answer")
        XCTAssertEqual(firstAdapter.startCount, 0, "no ad SDK without an answer")
        XCTAssertTrue(first.shouldRequestTrackingAuthorization, "still owed in the same process")

        // A new process, same install: same UserDefaults, status still undecided.
        let secondTracking = StubTracking(status: .notDetermined, resolvesTo: .denied, log: log)
        let secondAdapter = LoggingAdapter(log: log)
        let second = makeMonetization(log, tracking: secondTracking, adapter: secondAdapter)
        XCTAssertTrue(second.didRequestTrackingPrompt)
        XCTAssertTrue(second.shouldRequestTrackingAuthorization,
                      "a persisted 'asked' flag must never hide a prompt iOS never showed")
        await second.resolveTrackingAuthorizationIfNeeded()
        XCTAssertEqual(secondTracking.requestCount, 1, "asked again")
        XCTAssertTrue(second.adRequestsPermitted)
        XCTAssertEqual(secondAdapter.startCount, 1, "ads start once there is an answer")
    }

    /// A reader who already answered on a previous version is never re-asked,
    /// and their ads are not held up waiting for a prompt that cannot happen.
    func testAnAlreadyDecidedStatusIsNeverPromptedAndNeverBlocked() {
        for status in [EconTrackingStatus.authorized, .denied, .restricted] {
            let log = CallLog()
            let adapter = LoggingAdapter(log: log)
            let tracking = StubTracking(status: status, log: log)
            let monetization = makeMonetization(log, tracking: tracking, adapter: adapter)

            XCTAssertFalse(monetization.shouldRequestTrackingAuthorization,
                           "\(status) is already an answer")
            XCTAssertTrue(monetization.adRequestsPermitted, "\(status) unblocks ad requests")
            monetization.startAdsIfPermitted()
            XCTAssertEqual(adapter.startCount, 1, "\(status) must let the ad SDK start")
        }
    }

    // MARK: - 3. Every answer moves the app forward; no answer does not

    func testEveryAnswerUnblocksTheAdRequestAndNoAnswerDoesNot() async {
        for outcome in [EconTrackingStatus.authorized, .denied, .restricted, .notDetermined] {
            EconMonetization.resetPersistedState(in: defaults)
            let log = CallLog()
            let adapter = LoggingAdapter(log: log)
            let tracking = StubTracking(status: .notDetermined, resolvesTo: outcome, log: log)
            let monetization = makeMonetization(log, tracking: tracking, adapter: adapter)

            await monetization.resolveTrackingAuthorizationIfNeeded()

            XCTAssertEqual(log.entries.first, "att.request")
            if outcome.isDecided {
                XCTAssertTrue(monetization.adRequestsPermitted, "\(outcome) is an answer")
                XCTAssertEqual(adapter.startCount, 1, "\(outcome): the ad SDK starts once answered")
            } else {
                XCTAssertFalse(monetization.adRequestsPermitted, "no answer, no ad request")
                XCTAssertEqual(adapter.startCount, 0)
                XCTAssertTrue(log.adRequests.isEmpty)
            }
        }
    }

    // MARK: - 4. The prompt is findable on every device; ads still are not served everywhere

    /// Phase 14: Remove Ads owners and Pro subscribers are asked too. App Review
    /// sandbox accounts can own Remove Ads from earlier reviews, and an unasked
    /// account is an "unable to locate the ATT prompt" rejection. They still
    /// never get an ad.
    func testAdFreeReadersAreAskedButNeverGetAnAd() async {
        for entitlements in [EconEntitlements(removeAds: true), EconEntitlements(pro: true)] {
            let log = CallLog()
            let adapter = LoggingAdapter(log: log)
            let tracking = StubTracking(status: .notDetermined, resolvesTo: .authorized, log: log)
            let monetization = makeMonetization(log, tracking: tracking, adapter: adapter)
            monetization.update(entitlements: entitlements)

            XCTAssertTrue(monetization.shouldRequestTrackingAuthorization, "\(entitlements)")
            await monetization.resolveTrackingAuthorizationIfNeeded()
            XCTAssertEqual(tracking.requestCount, 1)
            XCTAssertEqual(adapter.startCount, 0, "ad-free still means no ad SDK")
            XCTAssertFalse(monetization.canRequestAds)
        }
    }

    /// Phase 14: EEA/UK and unknown device regions are asked too (a review
    /// device's Region setting is invisible in a rejection), and DUD-224 still
    /// serves them no ads at all.
    func testAdRestrictedRegionsAreAskedButNeverRequestAnAd() async {
        for region in [EconAdRegionState.restricted, .unknown] {
            let log = CallLog()
            let adapter = LoggingAdapter(log: log)
            let tracking = StubTracking(status: .notDetermined, resolvesTo: .authorized, log: log)
            let monetization = makeMonetization(log, tracking: tracking, adapter: adapter, region: region)

            XCTAssertTrue(monetization.shouldRequestTrackingAuthorization, "\(region)")
            await monetization.resolveTrackingAuthorizationIfNeeded()
            XCTAssertEqual(tracking.requestCount, 1, "\(region)")
            XCTAssertTrue(log.adRequests.isEmpty, "\(region) must never request an ad")
            XCTAssertFalse(monetization.canRequestAds)
        }
    }

    // MARK: - 5. The request is non-personalized on every outcome

    /// `npa=1` and `rdp=1` on all four statuses — authorized included.
    ///
    /// This is the portfolio invariant `adsPolicy.personalizedAdsMode:
    /// "disabled"`, enforced outside this repo by
    /// `scripts/release_evidence_gate.mjs` (POLICY_PERSONALIZATION) and by
    /// DudleyCore's `MonetizationPolicyRegistry`. Personalizing for authorized
    /// readers is the change that collects the eCPM this prompt makes
    /// available, and it is a policy revision across the portfolio — not
    /// something EconByte may do on its own. Until then, this test is what
    /// stops an "obvious improvement" from shipping unilaterally.
    func testEveryRequestIsNonPersonalizedForEveryTrackingOutcome() {
        for status in EconTrackingStatus.allCases {
            let policy = EconAdRequestPolicy(trackingStatus: status)
            XCTAssertEqual(policy.extras["npa"], "1", "\(status) must request non-personalized ads")
            XCTAssertEqual(policy.extras["rdp"], "1", "\(status) must restrict data processing")
            XCTAssertFalse(policy.usesPersonalizedAds, "\(status)")
        }
        XCTAssertTrue(EconTrackingStatus.authorized.providerWouldPermitPersonalizedAds,
                      "the seam the portfolio revision will use must exist and be honest")
        XCTAssertFalse(EconTrackingStatus.denied.providerWouldPermitPersonalizedAds)
        XCTAssertFalse(EconTrackingStatus.notDetermined.providerWouldPermitPersonalizedAds)
        XCTAssertFalse(EconTrackingStatus.restricted.providerWouldPermitPersonalizedAds)
    }

    /// The policy actually handed to the provider carries the live decision, so
    /// a future personalization change reads the reader's real answer rather
    /// than a value frozen at construction time.
    func testTheAdapterReceivesThePolicyCarryingTheResolvedStatus() async {
        let log = CallLog()
        let adapter = LoggingAdapter(log: log)
        let tracking = StubTracking(status: .notDetermined, resolvesTo: .denied, log: log)
        let monetization = makeMonetization(log, tracking: tracking, adapter: adapter)

        await monetization.resolveTrackingAuthorizationIfNeeded()

        XCTAssertEqual(adapter.lastPolicy?.trackingStatus, .denied)
        XCTAssertEqual(adapter.lastPolicy?.extras["npa"], "1")
        XCTAssertTrue(adapter.lastPolicy?.requestsAppTrackingAuthorization ?? false,
                      "build 13 restores the prompt — the policy must say so")
    }

    // MARK: - 6. Status mapping

    func testDecidednessIsExactlyEverythingButNotDetermined() {
        XCTAssertFalse(EconTrackingStatus.notDetermined.isDecided)
        for status in [EconTrackingStatus.authorized, .denied, .restricted] {
            XCTAssertTrue(status.isDecided, "\(status) is an answer")
        }
    }
}
