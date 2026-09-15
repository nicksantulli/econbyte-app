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
///  2. The prompt is asked at most once per install, and the record of having
///     asked survives a relaunch.
///  3. Every outcome moves the app forward: authorized, denied, restricted, and
///     a prompt iOS declined to present.
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

    /// And once across relaunches — including the state iOS actually leaves
    /// behind when it declines to present the dialog, where the status is still
    /// `.notDetermined` afterwards and a status-only guard would ask forever.
    func testThePromptIsNotRepeatedOnTheNextLaunchEvenIfItWasNeverPresented() async {
        let log = CallLog()
        let firstTracking = StubTracking(status: .notDetermined, resolvesTo: .notDetermined, log: log)
        let first = makeMonetization(log,
                                     tracking: firstTracking,
                                     adapter: LoggingAdapter(log: log))
        await first.resolveTrackingAuthorizationIfNeeded()
        XCTAssertEqual(firstTracking.requestCount, 1)

        // A new process, same install: same UserDefaults, status still undecided.
        let secondTracking = StubTracking(status: .notDetermined, resolvesTo: .notDetermined, log: log)
        let second = makeMonetization(log,
                                      tracking: secondTracking,
                                      adapter: LoggingAdapter(log: log))
        XCTAssertTrue(second.didRequestTrackingPrompt,
                      "the record of having asked must survive the process")
        XCTAssertFalse(second.shouldRequestTrackingAuthorization)
        await second.resolveTrackingAuthorizationIfNeeded()
        XCTAssertEqual(secondTracking.requestCount, 0, "never a second prompt")
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

    // MARK: - 3. Every outcome moves the app forward

    func testEveryOutcomeUnblocksTheAdRequest() async {
        for outcome in [EconTrackingStatus.authorized, .denied, .restricted, .notDetermined] {
            // Each pass is a separate install: the "already asked" record is
            // persisted, and this test is about the four first-ask outcomes.
            EconMonetization.resetPersistedState(in: defaults)
            let log = CallLog()
            let adapter = LoggingAdapter(log: log)
            let tracking = StubTracking(status: .notDetermined, resolvesTo: outcome, log: log)
            let monetization = makeMonetization(log, tracking: tracking, adapter: adapter)

            await monetization.resolveTrackingAuthorizationIfNeeded()

            XCTAssertTrue(monetization.adRequestsPermitted,
                          "resolving to \(outcome) must not leave ads silenced forever")
            XCTAssertEqual(adapter.startCount, 1,
                           "the ad SDK starts once the prompt has been answered or dismissed")
            XCTAssertEqual(log.entries.first, "att.request")
        }
    }

    // MARK: - 4. Ads that will never be served are never prompted for

    /// A Remove Ads owner sees no ads, so there is nothing to ask them about.
    func testRemoveAdsOwnersAreNeverPrompted() async {
        let log = CallLog()
        let adapter = LoggingAdapter(log: log)
        let tracking = StubTracking(status: .notDetermined, resolvesTo: .authorized, log: log)
        let monetization = makeMonetization(log, tracking: tracking, adapter: adapter)
        monetization.update(entitlements: EconEntitlements(removeAds: true))

        XCTAssertFalse(monetization.shouldRequestTrackingAuthorization)
        await monetization.resolveTrackingAuthorizationIfNeeded()
        XCTAssertEqual(tracking.requestCount, 0)
        XCTAssertEqual(adapter.startCount, 0)
    }

    /// DUD-224: no ads in the EEA/UK, so no ATT prompt there either — and no
    /// prompt when the region cannot be determined, which fails closed the same
    /// way the ad gate does.
    func testAdRestrictedRegionsAreNeverPrompted() async {
        for region in [EconAdRegionState.restricted, .unknown] {
            let log = CallLog()
            let adapter = LoggingAdapter(log: log)
            let tracking = StubTracking(status: .notDetermined, resolvesTo: .authorized, log: log)
            let monetization = makeMonetization(log,
                                                tracking: tracking,
                                                adapter: adapter,
                                                region: region)

            XCTAssertFalse(monetization.shouldRequestTrackingAuthorization,
                           "\(region) serves no ads, so it must not ask for tracking")
            await monetization.resolveTrackingAuthorizationIfNeeded()
            XCTAssertEqual(tracking.requestCount, 0)
            XCTAssertTrue(log.entries.isEmpty)
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
