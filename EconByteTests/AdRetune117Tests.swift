import XCTest
@testable import EconByte

/// 1.1.7 ad retune (Owner, 2026-09-28). AdMob showed the banner at a $0.70
/// eCPM over 45 impressions against $12.66 for the interstitial over 4, and the
/// portfolio policy for ad-supported apps is now: rewarded (opt-in) plus
/// interstitials at natural breaks (capped, never in the first session) — no
/// banners.
///
///  1. No banner path is left: no slot, no adapter, no unit, no request, no
///     accessibility identifier, no telemetry event or placement.
///  2. The interstitial rules are exactly the 1.1.6 ones — removing the banner
///     is not a reason to loosen them.
///  3. The rewarded pack trial keeps its unit, its 2-a-day cap (which survives
///     a relaunch) and its 24-hour expiry.
@MainActor
final class AdRetune117Tests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "AdRetune117Tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    // MARK: - Fakes

    @MainActor
    private final class Interstitials: EconInterstitialAdapting {
        var isAdLoaded = true
        var onAdDismissed: ((Bool) -> Void)?
        private(set) var presented: [EconAdPlacement] = []
        func startSDK(policy: EconAdRequestPolicy) {}
        func preload(policy: EconAdRequestPolicy) {}
        func discardLoadedAd() {}
        func present() async -> Bool { await present(for: .dailySetExit) }
        func present(for placement: EconAdPlacement) async -> Bool {
            presented.append(placement)
            return true
        }
    }

    @MainActor
    private final class Rewarded: EconRewardedAdapting {
        var isAdLoaded = true
        var onLoadStateChanged: (() -> Void)?
        private(set) var presentCount = 0
        func preload(policy: EconAdRequestPolicy) {}
        func presentForReward() async -> Bool {
            presentCount += 1
            return true
        }
    }

    @MainActor
    private final class Decided: EconTrackingAuthorizing {
        var status: EconTrackingStatus = .denied
        func requestAuthorization() async -> EconTrackingStatus { status }
    }

    private let noon = ISO8601DateFormatter().date(from: "2026-09-28T12:00:00Z")!

    /// UTC, so "the same day" never depends on the machine running the tests.
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func makeMonetization(_ adapter: EconInterstitialAdapting,
                                  now: @escaping () -> Date,
                                  sessions: Int) -> EconMonetization {
        let monetization = EconMonetization(adapter: adapter, defaults: defaults, calendar: utc,
                                            now: now, region: { .allowed }, tracking: Decided(),
                                            presentationSleep: { _ in })
        for _ in 0..<sessions { monetization.noteForegroundSessionBegan() }
        monetization.startAdsIfPermitted()
        return monetization
    }

    // MARK: - 1. No banner path

    func testTheBannerSlotIsGone() {
        let slot = repoRoot.appendingPathComponent("EconByte/Views/AdBannerSlot.swift")
        XCTAssertFalse(FileManager.default.fileExists(atPath: slot.path),
                       "1.1.7 removed the anchored banner slot")
    }

    /// Every Swift file in the app, comments stripped, is scanned for anything
    /// that could construct, load, identify or measure a banner. The retired
    /// production unit (…/4084037009) and Google's banner test unit
    /// (…/2435281174) may not appear anywhere in code.
    func testNoAppSourceBuildsLoadsOrMeasuresABanner() throws {
        let app = repoRoot.appendingPathComponent("EconByte")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil))
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
        XCTAssertGreaterThan(files.count, 20, "source scan found too few files — check the app root")

        let forbidden = ["AdBannerSlot", "BannerView", "AnchoredAdaptiveBanner", "adaptiveBanner",
                         "bannerPlacement", "EconAdUnit.banner", "releaseBanner", "debugBanner",
                         "4084037009", "2435281174", "ad.banner.",
                         "banner_impression_v1", "banner_load_finished_v1",
                         "bannerImpression(", "bannerLoadFinished("]
        for file in files {
            let code = InstrumentationPrivacyTests.strippingComments(try String(contentsOf: file, encoding: .utf8))
            for token in forbidden {
                XCTAssertFalse(code.contains(token),
                               "\(file.lastPathComponent) still contains \(token) — 1.1.7 has no banner")
            }
        }
    }

    func testNoBannerEventOrPlacementIsDeclared() {
        XCTAssertNil(TelemetrySchema.allowedProperties["banner_impression_v1"])
        XCTAssertNil(TelemetrySchema.allowedProperties["banner_load_finished_v1"])
        XCTAssertFalse(TelemetrySchema.allowedEventNames.contains { $0.hasPrefix("banner_") })
        if case .accepted = TelemetryValidator.validate(TelemetryEvent("banner_impression_v1",
                                                                       ["placement": .string("home")])) {
            XCTFail("an undeclared banner event must be rejected")
        }
        XCTAssertEqual(TelemetrySchema.allowedValues["placement"],
                       ["daily_set_exit", "set_midpoint", "pack_trial"])
        for retired in ["home", "card", "browse"] {
            if case .accepted = TelemetryValidator.validate(TelemetryEvent("ad_clicked_v1",
                                                                           ["placement": .string(retired)])) {
                XCTFail("the retired banner placement \(retired) must be rejected")
            }
        }
    }

    /// The telemetry placements are exactly the full-screen ones: the two
    /// interstitial placements and the rewarded offer.
    func testEveryAdPlacementIsAFullScreenFormat() {
        XCTAssertEqual(Set(EBAdPlacement.allCases.map(\.rawValue)),
                       Set(TelemetrySchema.allowedValues["placement"] ?? []))
        XCTAssertEqual(Set(EconAdPlacement.allCases.map { EBAdPlacement($0) }), [.dailySetExit, .setMidpoint])
        XCTAssertEqual(EBAdPlacement.allCases.count, 3, "two interstitial placements + the rewarded offer")
    }

    // MARK: - 2. Interstitial rules unchanged from 1.1.6

    func testInterstitialThresholdsAreExactlyTheOnesShippedIn116() {
        let t = EconAdThresholds()
        XCTAssertEqual(t.minimumCompletedSets, 1, "one finished set first")
        XCTAssertEqual(t.initialSessionInterstitials, 0, "never in the install's first session")
        XCTAssertEqual(t.setsSinceLastAd, 1)
        XCTAssertEqual(t.minimumInterval, 10 * 60, "10 minutes apart")
        XCTAssertEqual(t.perSession, 2, "2 per session")
        XCTAssertEqual(t.perDay, 4, "4 per day")
        XCTAssertEqual(t.rollingWindow, 24 * 60 * 60, "4 in any rolling 24 hours too")
        XCTAssertEqual(t.minimumMidpointDeckSize, 6, "the halfway break needs a 6+ card set")
        XCTAssertEqual(EconAdPlacement.allCases, [.dailySetExit, .setMidpoint])
    }

    /// A fresh install's first sitting stays ad-free however many sets it finishes.
    func testNoInterstitialInTheInstallsFirstSession() async {
        let adapter = Interstitials()
        var clock = noon
        let monetization = makeMonetization(adapter, now: { clock }, sessions: 1)
        for _ in 0..<5 {
            monetization.noteSetCompleted(normally: true)
            let outcome = await monetization.presentIfEligibleAtSetExit()
            XCTAssertEqual(outcome, .notEligible(.initialSession))
            let midpoint = await monetization.presentMidpointBreakIfEligible(
                deckSize: 8, environment: EconImmediatePresentationEnvironment())
            XCTAssertEqual(midpoint, .notEligible(.initialSession))
            clock = clock.addingTimeInterval(20 * 60)
        }
        XCTAssertTrue(adapter.presented.isEmpty)
    }

    /// The caps bind exactly as in 1.1.6: 10 minutes apart, 2 a session, 4 a day.
    func testTheSessionAndDailyCapsBindAsIn116() async {
        let adapter = Interstitials()
        var clock = noon
        let monetization = makeMonetization(adapter, now: { clock }, sessions: 2)

        func finishASet(after minutes: Double) async -> EconAdOutcome {
            clock = clock.addingTimeInterval(minutes * 60)
            monetization.noteSetCompleted(normally: true)
            return await monetization.presentIfEligibleAtSetExit()
        }

        var outcome = await finishASet(after: 0)
        XCTAssertEqual(outcome, .presented, "one finished set, second session: eligible")
        outcome = await finishASet(after: 9)
        XCTAssertEqual(outcome, .notEligible(.belowTimeThreshold(10 * 60)), "10 minutes apart")
        outcome = await finishASet(after: 2)
        XCTAssertEqual(outcome, .presented)
        outcome = await finishASet(after: 11)
        XCTAssertEqual(outcome, .notEligible(.sessionCapReached), "2 per session")

        monetization.noteForegroundSessionBegan()
        outcome = await finishASet(after: 11)
        XCTAssertEqual(outcome, .presented)
        outcome = await finishASet(after: 11)
        XCTAssertEqual(outcome, .presented)
        XCTAssertEqual(monetization.state.shownToday, 4)

        monetization.noteForegroundSessionBegan()
        outcome = await finishASet(after: 11)
        XCTAssertEqual(outcome, .notEligible(.dailyCapReached), "4 per day")
        XCTAssertEqual(adapter.presented.count, 4)
    }

    // MARK: - 3. Rewarded pack trial unchanged

    func testTheRewardedUnitsAreUnchanged() {
        XCTAssertEqual(EconAdUnit.releaseRewarded, "ca-app-pub-9950526548980224/7378501919")
        XCTAssertEqual(EconAdUnit.debugRewarded, "ca-app-pub-3940256099942544/1712485313")
        #if DEBUG
        XCTAssertEqual(EconAdUnit.rewarded, EconAdUnit.debugRewarded)
        #else
        XCTAssertEqual(EconAdUnit.rewarded, EconAdUnit.releaseRewarded)
        #endif
        XCTAssertEqual(EconRewardedOffers.maximumGrantsPer24Hours, 2)
        XCTAssertEqual(PurchaseManager.rewardedUnlockDuration, 24 * 60 * 60)
    }

    /// The 2-a-day cap is persisted: relaunching does not hand out a third.
    func testTheRewardedCapSurvivesARelaunch() async {
        var clock = noon
        let monetization = makeMonetization(Interstitials(), now: { clock }, sessions: 2)
        let store = PurchaseManager(defaults: defaults, observesStore: false)
        let first = EconRewardedOffers(adapter: Rewarded(), defaults: defaults, now: { clock })
        for id in ["com.nsantulli.econbyte.pack.markets", "com.nsantulli.econbyte.pack.history"] {
            let outcome = await first.watch(forPackProductID: id, family: nil,
                                            monetization: monetization, store: store)
            XCTAssertEqual(outcome, .rewarded)
        }

        let rewarded = Rewarded()
        let relaunched = EconRewardedOffers(adapter: rewarded, defaults: defaults, now: { clock })
        XCTAssertEqual(relaunched.grantsInLast24Hours, 2)
        XCTAssertFalse(relaunched.mayOffer(monetization: monetization))
        let third = await relaunched.watch(forPackProductID: "com.nsantulli.econbyte.pack.world", family: nil,
                                           monetization: monetization, store: store)
        XCTAssertEqual(third, .notOffered)
        XCTAssertEqual(rewarded.presentCount, 0, "no ad is played past the cap")

        clock = clock.addingTimeInterval(24 * 60 * 60 + 1)
        XCTAssertTrue(relaunched.mayOffer(monetization: monetization), "the rolling window lets one back in")
    }

    /// A rewarded unlock lasts exactly 24 hours, then the pack is locked again.
    func testARewardedUnlockExpiresAtTwentyFourHours() {
        let pack = "com.nsantulli.econbyte.pack.markets"
        let store = PurchaseManager(defaults: defaults, observesStore: false)
        store.grantRewardedPackUnlock(packProductID: pack, now: noon)
        let end = noon.addingTimeInterval(24 * 60 * 60)
        XCTAssertEqual(store.rewardedUnlockEnd(packProductID: pack, now: end.addingTimeInterval(-1)), end)
        XCTAssertNil(store.rewardedUnlockEnd(packProductID: pack, now: end), "ends at the 24-hour mark")
        XCTAssertFalse(store.hasPaidAccess(packProductID: pack), "never an entitlement")
    }
}
