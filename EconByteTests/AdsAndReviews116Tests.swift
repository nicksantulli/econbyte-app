import XCTest
@testable import EconByte

/// 1.1.6 (Owner, 2026-09-26): the halfway ad break inside a card set, the
/// rewarded "read this pack free for 24 hours" offer, and the App Store rating
/// request after a finished lesson.
final class AdsAndReviews116Tests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "AdsAndReviews116Tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    // MARK: Fakes

    @MainActor
    private final class Interstitials: EconInterstitialAdapting {
        var isAdLoaded = true
        var onAdDismissed: ((Bool) -> Void)?
        var placements: [EconAdPlacement] = []
        func startSDK(policy: EconAdRequestPolicy) {}
        func preload(policy: EconAdRequestPolicy) {}
        func discardLoadedAd() { isAdLoaded = false }
        func present() async -> Bool { await present(for: .dailySetExit) }
        func present(for placement: EconAdPlacement) async -> Bool {
            placements.append(placement)
            return true
        }
    }

    @MainActor
    private final class Rewarded: EconRewardedAdapting {
        var isAdLoaded = true
        var onLoadStateChanged: (() -> Void)?
        var earns = true
        var presentCount = 0
        var preloadCount = 0
        func preload(policy: EconAdRequestPolicy) { preloadCount += 1 }
        func presentForReward() async -> Bool {
            presentCount += 1
            return earns
        }
    }

    @MainActor
    private final class Tracking: EconTrackingAuthorizing {
        var status: EconTrackingStatus = .denied
        func requestAuthorization() async -> EconTrackingStatus { status }
    }

    private let noon = ISO8601DateFormatter().date(from: "2026-09-26T12:00:00Z")!

    /// An install in its second foreground session with one finished set, SDK started.
    @MainActor
    private func monetization(_ adapter: EconInterstitialAdapting,
                              now: @escaping () -> Date,
                              region: EconAdRegionState = .allowed,
                              sessions: Int = 2) -> EconMonetization {
        let monetization = EconMonetization(adapter: adapter, defaults: defaults, now: now,
                                            region: { region }, tracking: Tracking(),
                                            presentationSleep: { _ in })
        for _ in 0..<sessions { monetization.noteForegroundSessionBegan() }
        monetization.noteSetCompleted(normally: true)
        monetization.startAdsIfPermitted()
        return monetization
    }

    // MARK: Halfway break

    func testTheHalfwayBreakNeedsASetOfSixOrMoreButNotAFinishedSet() {
        var state = EconAdState()
        state.completedSetsLifetime = 1
        state.setsSinceLastAd = 0
        state.foregroundSessionsLifetime = 2
        let policy = EconAdPolicy()
        func decide(_ size: Int) -> EconAdDecision {
            policy.decide(placement: .setMidpoint, state: state, entitlements: EconEntitlements(),
                          region: .allowed, setCompletedNormally: false, blockers: [],
                          now: noon, dayKey: "2026-09-26", deckSize: size)
        }
        XCTAssertEqual(decide(8), .eligible,
                       "inside a set: no finished-set or sets-since-last-ad rule")
        XCTAssertEqual(decide(5), .deckTooShort(6))
    }

    @MainActor
    func testTheHalfwayBreakPresentsOverTheSessionAndSharesTheCaps() async {
        let adapter = Interstitials()
        let monetization = monetization(adapter, now: { self.noon })
        let first = await monetization.presentMidpointBreakIfEligible(
            deckSize: 8, environment: EconImmediatePresentationEnvironment())
        XCTAssertEqual(first, .presented)
        XCTAssertEqual(adapter.placements, [.setMidpoint])
        XCTAssertEqual(monetization.state.shownThisSession, 1)

        // The same set's exit a couple of minutes later is inside the 10-minute floor.
        monetization.noteSetCompleted(normally: true)
        let exit = await monetization.presentIfEligibleAtSetExit()
        XCTAssertEqual(exit, .notEligible(.belowTimeThreshold(10 * 60)))
        XCTAssertEqual(adapter.placements, [.setMidpoint])
    }

    @MainActor
    func testTheHalfwayBreakIsNeverShownInTheInstallsFirstSession() async {
        let adapter = Interstitials()
        let monetization = monetization(adapter, now: { self.noon }, sessions: 1)
        let outcome = await monetization.presentMidpointBreakIfEligible(
            deckSize: 8, environment: EconImmediatePresentationEnvironment())
        XCTAssertEqual(outcome, .notEligible(.initialSession))
        XCTAssertTrue(adapter.placements.isEmpty)
    }

    @MainActor
    func testTheHalfwayBreakIsNeverShownToAnEntitledReaderOrInABlockedRegion() async {
        let adapter = Interstitials()
        let blocked = monetization(adapter, now: { self.noon }, region: .restricted)
        let outcome = await blocked.presentMidpointBreakIfEligible(
            deckSize: 8, environment: EconImmediatePresentationEnvironment())
        XCTAssertEqual(outcome, .notEligible(.suppressedRegion(.restricted)))

        let entitled = monetization(adapter, now: { self.noon })
        entitled.update(entitlements: EconEntitlements(removeAds: true))
        let suppressed = await entitled.presentMidpointBreakIfEligible(
            deckSize: 8, environment: EconImmediatePresentationEnvironment())
        XCTAssertEqual(suppressed, .notEligible(.suppressedEntitled))
        XCTAssertTrue(adapter.placements.isEmpty)
    }

    @MainActor
    func testAHalfwayBreakWithNoSettledPresenterShowsNothingAndSpendsNoCap() async {
        final class NeverReady: EconAdPresentationEnvironment {
            var isReadyToPresentInterstitial: Bool { false }
        }
        let adapter = Interstitials()
        let monetization = monetization(adapter, now: { self.noon })
        let outcome = await monetization.presentMidpointBreakIfEligible(deckSize: 8, environment: NeverReady())
        XCTAssertEqual(outcome, .notEligible(.presenterUnavailable))
        XCTAssertEqual(monetization.state.shownThisSession, 0)
    }

    func testTheHalfwayBreakIsACardModeInterstitialAndNeverABookmarksReview() {
        XCTAssertTrue(EconAdSurface.cardMode.allowsInterstitial)
        XCTAssertFalse(EconAdSurface.bookmarksReview.allowsInterstitial)
        XCTAssertFalse(EconAdSurface.courseLesson.allowsInterstitial)
    }

    // MARK: Rewarded pack trial

    private let pack = "com.nsantulli.econbyte.pack.markets"

    @MainActor
    func testWatchingARewardedAdToTheEndOpensThePackForADay() async {
        let rewarded = Rewarded()
        var clock = noon
        let offers = EconRewardedOffers(adapter: rewarded, defaults: defaults, now: { clock })
        let monetization = monetization(Interstitials(), now: { clock })
        let store = PurchaseManager(defaults: defaults, observesStore: false)
        XCTAssertFalse(store.hasAccess(packProductID: pack))

        let outcome = await offers.watch(forPackProductID: pack, family: .packMarkets,
                                         monetization: monetization, store: store)
        XCTAssertEqual(outcome, .rewarded)
        XCTAssertTrue(store.hasAccess(packProductID: pack), "readable for the day")
        XCTAssertFalse(store.hasPaidAccess(packProductID: pack), "never an entitlement")
        XCTAssertNotNil(store.rewardedUnlockEnd(packProductID: pack, now: clock.addingTimeInterval(23 * 3600)))
        XCTAssertNil(store.rewardedUnlockEnd(packProductID: pack, now: clock.addingTimeInterval(24 * 3600 + 1)))
        XCTAssertFalse(store.allPacksReadable)

        // A rewarded ad spaces the next interstitial but spends no cap.
        XCTAssertEqual(monetization.state.shownThisSession, 0)
        clock = clock.addingTimeInterval(60)
        monetization.noteSetCompleted(normally: true)
        XCTAssertEqual(monetization.decisionAtSetExit(), .belowTimeThreshold(10 * 60))
    }

    @MainActor
    func testAnUnlockSurvivesARelaunchButNotItsEnd() async {
        let offers = EconRewardedOffers(adapter: Rewarded(), defaults: defaults, now: { self.noon })
        let store = PurchaseManager(defaults: defaults, observesStore: false)
        _ = await offers.watch(forPackProductID: pack, family: .packMarkets,
                               monetization: monetization(Interstitials(), now: { self.noon }), store: store)
        let reloaded = PurchaseManager.loadRewardedUnlocks(from: defaults, now: noon.addingTimeInterval(3600))
        XCTAssertNotNil(reloaded[pack])
        XCTAssertTrue(PurchaseManager.loadRewardedUnlocks(from: defaults,
                                                          now: noon.addingTimeInterval(25 * 3600)).isEmpty)
    }

    func testAnEditedUnlockCannotLastLongerThanADay() {
        let now = noon
        defaults.set([pack: now.addingTimeInterval(30 * 24 * 3600).timeIntervalSince1970],
                     forKey: PurchaseManager.rewardedUnlocksKey)
        XCTAssertTrue(PurchaseManager.loadRewardedUnlocks(from: defaults, now: now).isEmpty)
    }

    @MainActor
    func testAnAdClosedEarlyUnlocksNothing() async {
        let rewarded = Rewarded()
        rewarded.earns = false
        let offers = EconRewardedOffers(adapter: rewarded, defaults: defaults, now: { self.noon })
        let store = PurchaseManager(defaults: defaults, observesStore: false)
        let outcome = await offers.watch(forPackProductID: pack, family: .packMarkets,
                                         monetization: monetization(Interstitials(), now: { self.noon }),
                                         store: store)
        XCTAssertEqual(outcome, .notRewarded)
        XCTAssertFalse(store.hasAccess(packProductID: pack))
        XCTAssertEqual(offers.grantsInLast24Hours, 0)
    }

    @MainActor
    func testAtMostTwoRewardedUnlocksInAnyTwentyFourHours() async {
        var clock = noon
        let rewarded = Rewarded()
        let offers = EconRewardedOffers(adapter: rewarded, defaults: defaults, now: { clock })
        let monetization = monetization(Interstitials(), now: { clock })
        let store = PurchaseManager(defaults: defaults, observesStore: false)
        for id in [pack, "com.nsantulli.econbyte.pack.history"] {
            let outcome = await offers.watch(forPackProductID: id, family: nil,
                                             monetization: monetization, store: store)
            XCTAssertEqual(outcome, .rewarded)
        }
        XCTAssertFalse(offers.mayOffer(monetization: monetization))
        let third = await offers.watch(forPackProductID: "com.nsantulli.econbyte.pack.world", family: nil,
                                       monetization: monetization, store: store)
        XCTAssertEqual(third, .notOffered)
        XCTAssertEqual(rewarded.presentCount, 2)

        clock = clock.addingTimeInterval(24 * 3600 + 1)
        XCTAssertTrue(offers.mayOffer(monetization: monetization), "the window rolls off")
    }

    @MainActor
    func testTheRewardedOfferIsBehindTheSharedAdGate() async {
        let rewarded = Rewarded()
        let offers = EconRewardedOffers(adapter: rewarded, defaults: defaults, now: { self.noon })
        let store = PurchaseManager(defaults: defaults, observesStore: false)

        let blocked = monetization(Interstitials(), now: { self.noon }, region: .restricted)
        XCTAssertFalse(offers.mayOffer(monetization: blocked))
        offers.preloadIfPermitted(monetization: blocked)
        XCTAssertEqual(rewarded.preloadCount, 0, "no request in the EEA/UK/CH")

        let entitled = monetization(Interstitials(), now: { self.noon })
        entitled.update(entitlements: EconEntitlements(removeAds: true))
        let outcome = await offers.watch(forPackProductID: pack, family: nil,
                                         monetization: entitled, store: store)
        XCTAssertEqual(outcome, .notOffered)
        XCTAssertEqual(rewarded.presentCount, 0)
    }

    func testPolicyDeclaresTheRewardedCapTheAppEnforces() {
        XCTAssertEqual(EconRewardedOffers.maximumGrantsPer24Hours, 2)
        XCTAssertEqual(PurchaseManager.rewardedUnlockDuration, 24 * 3600)
    }

    // MARK: Rating requests

    @MainActor
    private func review(launches: Int = 2, calls: @escaping () -> Void = {}) -> ReviewRequestCoordinator {
        defaults.set(launches, forKey: ReviewRequestPolicy.launchCountDefaultsKey)
        return ReviewRequestCoordinator(defaults: defaults, currentVersion: "1.1.6",
                                        now: { self.noon }, requestReview: calls)
    }

    @MainActor
    func testAFinishedLessonIsARatingMoment() {
        var asked = 0
        let coordinator = review(calls: { asked += 1 })
        coordinator.noteLessonCompleted()
        XCTAssertEqual(coordinator.requestReviewIfEligible(), .eligible)
        XCTAssertEqual(asked, 1)
        XCTAssertEqual(coordinator.requestReviewIfEligible(), .alreadyRequestedForVersion("1.1.6"))
        XCTAssertEqual(asked, 1, "once per version")
    }

    @MainActor
    func testTheFirstOpenIsNeverAskedEvenAfterALesson() {
        let coordinator = review(launches: 1)
        coordinator.noteLessonCompleted()
        XCTAssertEqual(coordinator.requestReviewIfEligible(), .belowLaunchCount(1))
    }

    @MainActor
    func testTheHalfwayBreakYieldsToAnUpcomingRatingRequest() {
        let coordinator = review()
        XCTAssertTrue(coordinator.wouldAskAtNextCompletion(cardsInSet: 8),
                      "the end of this set is the rating moment, so no halfway ad")
        XCTAssertFalse(coordinator.wouldAskAtNextCompletion(cardsInSet: 3), "a short replay is not a moment")
        coordinator.noteNegativeSessionEvent(.purchase)
        XCTAssertFalse(coordinator.wouldAskAtNextCompletion(cardsInSet: 8))
        XCTAssertNil(coordinator.lastDecision, "checking never spends the attempt")
    }
}
