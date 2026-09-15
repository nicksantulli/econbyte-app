import XCTest
import UserNotifications
@testable import EconByte

/// First-launch permissions (1.1.3 build 16 — App Review Guideline 2.1 fix,
/// 2026-09-15; ported from the 1.1.4 line): Apple's ATT prompt, then Apple's
/// notifications prompt, with ATT `.authorized` ⇒ analytics + crash reports ON
/// (anything else OFF) and notifications granted ⇒ the daily reminder ON.
///
/// What build 15 got wrong is asserted here too: a prompt iOS did not present is
/// not an answer and is asked again (same run, then the next activation); the
/// flow only asks when the app could actually show a system dialog; and the
/// prompt is owed to every install whatever its region or purchases.
///
/// Neither system prompt can appear in a test process, so everything is asserted
/// against doubles for the tracking framework, the ad adapter, the notification
/// centre and the presentation environment.
@MainActor
final class FirstLaunchPermissionsTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "eb.first-launch.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - Doubles

    private final class Log {
        var entries: [String] = []
        func index(_ entry: String) -> Int? { entries.firstIndex(of: entry) }
    }

    /// Resolves each request to the next queued status (the last one repeats).
    /// `.notDetermined` models iOS declining to present the dialog.
    @MainActor
    private final class StubTracking: EconTrackingAuthorizing {
        var status: EconTrackingStatus
        var resolutions: [EconTrackingStatus]
        private(set) var requests = 0
        let log: Log

        init(status: EconTrackingStatus, resolutions: [EconTrackingStatus], log: Log) {
            self.status = status
            self.resolutions = resolutions
            self.log = log
        }

        func requestAuthorization() async -> EconTrackingStatus {
            guard status == .notDetermined else { return status }
            requests += 1
            log.entries.append("att.request")
            await Task.yield()
            if resolutions.count > 1 {
                status = resolutions.removeFirst()
            } else if let last = resolutions.first {
                status = last
            }
            return status
        }
    }

    @MainActor
    private final class LoggingAdapter: EconInterstitialAdapting {
        var isAdLoaded = false
        var onAdDismissed: ((Bool) -> Void)?
        private(set) var starts = 0
        let log: Log
        init(log: Log) { self.log = log }
        func startSDK(policy: EconAdRequestPolicy) { starts += 1; log.entries.append("ad.start") }
        func preload(policy: EconAdRequestPolicy) { log.entries.append("ad.preload") }
        func discardLoadedAd() {}
        func present() async -> Bool { false }
    }

    /// `presents: false` models iOS returning from the request without showing
    /// anything (the status stays `.notDetermined`).
    @MainActor
    private final class SpyCenter: EconNotificationScheduling {
        var authorization: EconNotificationAuthorization
        var grant: Bool
        var presents: Bool
        private(set) var requests = 0
        var added: [UNNotificationRequest] = []
        let log: Log

        init(authorization: EconNotificationAuthorization, grant: Bool, presents: Bool, log: Log) {
            self.authorization = authorization
            self.grant = grant
            self.presents = presents
            self.log = log
        }

        nonisolated func econRequestAuthorization(_ completion: @escaping (Bool, Error?) -> Void) {
            Task { @MainActor in
                self.requests += 1
                self.log.entries.append("notifications.request")
                guard self.presents else { completion(false, nil); return }
                self.authorization = self.grant ? .authorized : .denied
                completion(self.grant, nil)
            }
        }

        nonisolated func econAuthorizationStatus(_ completion: @escaping (EconNotificationAuthorization) -> Void) {
            Task { @MainActor in completion(self.authorization) }
        }

        nonisolated func econAdd(_ request: UNNotificationRequest, completion: @escaping (Error?) -> Void) {
            Task { @MainActor in
                self.added.append(request)
                completion(nil)
            }
        }

        nonisolated func econRemovePendingRequests(withIdentifiers identifiers: [String]) {
            Task { @MainActor in self.added.removeAll { identifiers.contains($0.identifier) } }
        }

        nonisolated func econRemoveDeliveredNotifications(withIdentifiers identifiers: [String]) {}

        nonisolated func econPendingRequestIdentifiers(_ completion: @escaping ([String]) -> Void) {
            Task { @MainActor in completion(self.added.map(\.identifier)) }
        }
    }

    /// Answers each readiness read from a queue (the last value repeats).
    @MainActor
    private final class StubEnvironment: EconPromptPresentationEnvironment {
        var readiness: [Bool]
        private(set) var reads = 0
        init(_ readiness: [Bool]) { self.readiness = readiness }
        var isReadyForSystemPrompt: Bool {
            reads += 1
            if readiness.count > 1 { return readiness.removeFirst() }
            return readiness.first ?? true
        }
    }

    private final class Recorder {
        var analytics: [Bool] = []
        var negativeEvents: [EconNegativeSessionEvent] = []
        var notificationResults: [Bool] = []
        var pauses = 0
    }

    private struct Fixture {
        let log: Log
        let tracking: StubTracking
        let adapter: LoggingAdapter
        let center: SpyCenter
        let environment: StubEnvironment
        let monetization: EconMonetization
        let notifications: NotificationCoordinator
        let coordinator: FirstLaunchPermissionsCoordinator
        let recorder: Recorder
    }

    private func makeFixture(tracking status: EconTrackingStatus = .notDetermined,
                             resolutions: [EconTrackingStatus] = [.authorized],
                             notifications notificationStatus: EconNotificationAuthorization = .notDetermined,
                             grant: Bool = true,
                             notificationsPresent: Bool = true,
                             ready: [Bool] = [true],
                             region: EconAdRegionState = .allowed,
                             entitlements: EconEntitlements = EconEntitlements()) -> Fixture {
        let log = Log()
        let tracking = StubTracking(status: status, resolutions: resolutions, log: log)
        let adapter = LoggingAdapter(log: log)
        let center = SpyCenter(authorization: notificationStatus, grant: grant,
                               presents: notificationsPresent, log: log)
        let environment = StubEnvironment(ready)
        let monetization = EconMonetization(adapter: adapter,
                                            defaults: defaults,
                                            now: { Date(timeIntervalSince1970: 1_789_000_000) },
                                            region: { region },
                                            tracking: tracking)
        monetization.update(entitlements: entitlements)
        // Exactly what `EconGrowth.init` does for a non-automation launch.
        monetization.setLaunchPermissionsHold(true)
        let notifications = NotificationCoordinator(center: center, defaults: defaults)
        let recorder = Recorder()
        let coordinator = FirstLaunchPermissionsCoordinator(
            monetization: monetization,
            notifications: notifications,
            defaults: defaults,
            environment: environment,
            pause: { _ in recorder.pauses += 1; await Task.yield() },
            applyAnalyticsConsent: { recorder.analytics.append($0) },
            noteNegativeSessionEvent: { recorder.negativeEvents.append($0) },
            recordNotificationResult: { recorder.notificationResults.append($0) })
        return Fixture(log: log, tracking: tracking, adapter: adapter, center: center,
                       environment: environment, monetization: monetization,
                       notifications: notifications, coordinator: coordinator, recorder: recorder)
    }

    private func settle() async {
        for _ in 0..<40 { await Task.yield() }
    }

    private let noArguments = ["EconByte"]

    // MARK: - 1. The mapping

    func testAllowOnBothPromptsTurnsOnAnalyticsCrashReportsAndTheDailyReminder() async {
        let f = makeFixture(resolutions: [.authorized], grant: true)
        let outcome = await f.coordinator.runIfNeeded(arguments: noArguments)
        await settle()

        XCTAssertTrue(outcome.askedTracking)
        XCTAssertFalse(outcome.deferred)
        XCTAssertEqual(outcome.trackingAttempts, 1)
        XCTAssertEqual(outcome.trackingStatus, .authorized)
        XCTAssertEqual(outcome.analyticsConsentApplied, true)
        XCTAssertEqual(f.recorder.analytics, [true], "ATT Allow ⇒ analytics + crash reports on")

        XCTAssertTrue(outcome.askedNotifications)
        XCTAssertEqual(outcome.notificationsGranted, true)
        XCTAssertTrue(f.notifications.remindersEnabled, "notifications granted ⇒ reminder on")
        XCTAssertTrue(defaults.bool(forKey: NotificationPolicy.enabledDefaultsKey))
        let reminder = f.center.added.first { $0.identifier == NotificationPolicy.reminderIdentifier }
        let trigger = reminder?.trigger as? UNCalendarNotificationTrigger
        XCTAssertEqual(trigger?.dateComponents.hour, 19, "scheduled at the existing 7:00 p.m. time")
        XCTAssertEqual(trigger?.dateComponents.minute, 0)
        XCTAssertEqual(f.recorder.notificationResults, [true],
                       "a dialog iOS presented is recorded as notification_permission_result")
    }

    func testDenyingBothLeavesAnalyticsAndTheReminderOff() async {
        let f = makeFixture(resolutions: [.denied], grant: false)
        let outcome = await f.coordinator.runIfNeeded(arguments: noArguments)
        await settle()

        XCTAssertEqual(outcome.analyticsConsentApplied, false)
        XCTAssertEqual(f.recorder.analytics, [false], "anything but Allow ⇒ off")
        XCTAssertEqual(outcome.notificationsGranted, false)
        XCTAssertFalse(f.notifications.remindersEnabled, "notifications denied ⇒ reminder off")
        XCTAssertTrue(f.center.added.isEmpty, "no reminder is scheduled for a denial")
        XCTAssertEqual(f.recorder.notificationResults, [false])
    }

    func testRestrictedTrackingMapsToOff() async {
        let f = makeFixture(resolutions: [.restricted])
        let outcome = await f.coordinator.runIfNeeded(arguments: noArguments)
        XCTAssertEqual(outcome.analyticsConsentApplied, false)
    }

    func testTheMappingPolicyMatrix() {
        for status in EconTrackingStatus.allCases {
            let expected: Bool? = {
                switch status {
                case .authorized: return true
                case .denied, .restricted: return false
                case .notDetermined: return nil
                }
            }()
            XCTAssertEqual(FirstLaunchPermissionPolicy.analyticsConsent(
                afterTracking: status, promptWasAsked: true, analyticsAlreadyAnswered: false), expected,
                           "\(status)")
            XCTAssertNil(FirstLaunchPermissionPolicy.analyticsConsent(
                afterTracking: status, promptWasAsked: false, analyticsAlreadyAnswered: false),
                         "\(status): no prompt this launch, no mapping")
            XCTAssertNil(FirstLaunchPermissionPolicy.analyticsConsent(
                afterTracking: status, promptWasAsked: true, analyticsAlreadyAnswered: true),
                         "\(status): an earlier analytics answer is never overridden")
        }
    }

    // MARK: - 2. Ordering and ads

    func testTrackingIsAskedBeforeNotificationsAndNoAdIsRequestedBeforeBothResolve() async {
        let f = makeFixture()
        XCTAssertFalse(f.monetization.canRequestAds, "no ad before the ATT answer")
        f.monetization.startAdsIfPermitted()
        XCTAssertEqual(f.adapter.starts, 0, "the launch hold keeps the SDK stopped")
        await f.coordinator.runIfNeeded(arguments: noArguments)

        let att = f.log.index("att.request")
        let notifications = f.log.index("notifications.request")
        let adStart = f.log.index("ad.start")
        XCTAssertNotNil(att); XCTAssertNotNil(notifications); XCTAssertNotNil(adStart)
        if let att, let notifications, let adStart {
            XCTAssertLessThan(att, notifications, "ATT first, then notifications")
            XCTAssertLessThan(notifications, adStart, "the ad SDK starts only after both prompts")
        }
        XCTAssertEqual(f.log.entries.first, "att.request", "nothing precedes the ATT prompt")
        XCTAssertEqual(f.adapter.starts, 1)
        XCTAssertFalse(f.monetization.isHeldForLaunchPermissions)
        XCTAssertFalse(f.monetization.activeBlockers.contains(.systemPrompt),
                       "the system-prompt blocker is released when the flow ends")
    }

    func testBothPromptsDeferTheRatingAsk() async {
        let f = makeFixture()
        await f.coordinator.runIfNeeded(arguments: noArguments)
        XCTAssertEqual(f.recorder.negativeEvents, [.trackingPrompt, .notificationPrompt])
    }

    // MARK: - 3. What build 15 got wrong: a prompt iOS did not show is not an answer

    /// iOS returns `.notDetermined` without UI when the app is not active or a
    /// presentation is in flight. The run tries three times, then defers: no
    /// mapping, no notifications prompt out of order, no ad.
    func testAPromptIOSDidNotPresentIsRetriedThenDeferredWithNothingWrittenAndNoAd() async {
        let f = makeFixture(resolutions: [.notDetermined])
        let outcome = await f.coordinator.runIfNeeded(arguments: noArguments)

        XCTAssertTrue(outcome.askedTracking)
        XCTAssertTrue(outcome.deferred)
        XCTAssertEqual(outcome.trackingAttempts, FirstLaunchPermissionPolicy.maxTrackingAttemptsPerRun)
        XCTAssertEqual(f.tracking.requests, 3, "asked three times in the run")
        XCTAssertEqual(f.recorder.pauses, 2, "one pause before each retry")
        XCTAssertNil(outcome.analyticsConsentApplied)
        XCTAssertTrue(f.recorder.analytics.isEmpty)
        XCTAssertFalse(ConsentPromptPolicy.wasShown(in: defaults),
                       "with no answer the session-complete offer stays available")
        XCTAssertFalse(outcome.askedNotifications, "notifications never jump ahead of ATT")
        XCTAssertEqual(f.center.requests, 0)
        XCTAssertEqual(f.adapter.starts, 0, "no ad without an ATT answer")
        XCTAssertFalse(f.monetization.canRequestAds)
        XCTAssertFalse(f.monetization.activeBlockers.contains(.systemPrompt))
    }

    func testANonPresentedAskThatSucceedsOnRetryCompletesInTheSameRun() async {
        let f = makeFixture(resolutions: [.notDetermined, .authorized])
        let outcome = await f.coordinator.runIfNeeded(arguments: noArguments)
        XCTAssertFalse(outcome.deferred)
        XCTAssertEqual(outcome.trackingAttempts, 2)
        XCTAssertEqual(outcome.trackingStatus, .authorized)
        XCTAssertEqual(outcome.analyticsConsentApplied, true)
        XCTAssertTrue(outcome.askedNotifications)
        XCTAssertEqual(f.adapter.starts, 1)
    }

    /// The retry on the next `.active` — in the same process, and after a relaunch.
    func testADeferredRunIsAskedAgainOnTheNextActivationAndAfterARelaunch() async {
        let f = makeFixture(resolutions: [.notDetermined])
        let first = await f.coordinator.runIfNeeded(arguments: noArguments)
        XCTAssertTrue(first.deferred)

        // Next activation, same process: iOS presents this time.
        f.tracking.resolutions = [.denied]
        let second = await f.coordinator.runIfNeeded(arguments: noArguments)
        XCTAssertFalse(second.deferred)
        XCTAssertEqual(second.trackingStatus, .denied)
        XCTAssertEqual(second.analyticsConsentApplied, false)
        XCTAssertTrue(second.askedNotifications)
        XCTAssertEqual(f.adapter.starts, 1)

        // A relaunch of an install whose earlier asks were never presented
        // (the persisted "asked" record exists): still asked.
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(true, forKey: "econ.ads.trackingPromptRequested")
        let relaunch = makeFixture(resolutions: [.authorized])
        let outcome = await relaunch.coordinator.runIfNeeded(arguments: noArguments)
        XCTAssertTrue(outcome.askedTracking, "a persisted flag never hides a prompt iOS never showed")
        XCTAssertEqual(outcome.trackingStatus, .authorized)
    }

    /// The flow never asks while iOS would not show a dialog: not active, a
    /// sheet or cover presented, or a transition in flight.
    func testNothingIsAskedWhileTheAppCannotPresentASystemPrompt() async {
        let f = makeFixture(ready: [false])
        let outcome = await f.coordinator.runIfNeeded(arguments: noArguments)
        XCTAssertTrue(outcome.deferred)
        XCTAssertFalse(outcome.askedTracking)
        XCTAssertEqual(outcome.trackingAttempts, 0)
        XCTAssertEqual(f.tracking.requests, 0)
        XCTAssertEqual(f.center.requests, 0)
        XCTAssertEqual(f.adapter.starts, 0)

        // Becomes ready (the sheet was dismissed) on the next activation.
        f.environment.readiness = [true]
        let next = await f.coordinator.runIfNeeded(arguments: noArguments)
        XCTAssertFalse(next.deferred)
        XCTAssertEqual(f.tracking.requests, 1)
        XCTAssertEqual(f.center.requests, 1)
    }

    func testReadinessThatArrivesWithinTheRunIsUsed() async {
        let f = makeFixture(ready: [false, true])
        let outcome = await f.coordinator.runIfNeeded(arguments: noArguments)
        XCTAssertFalse(outcome.deferred)
        XCTAssertEqual(outcome.trackingAttempts, 1)
        XCTAssertEqual(f.recorder.pauses, 1)
    }

    func testANotificationsAskIOSDidNotPresentIsDeferredAndRetried() async {
        let f = makeFixture(resolutions: [.authorized], notificationsPresent: false)
        let first = await f.coordinator.runIfNeeded(arguments: noArguments)
        await settle()
        XCTAssertTrue(first.deferred)
        XCTAssertNil(first.notificationsGranted)
        XCTAssertFalse(f.notifications.remindersEnabled, "nothing persisted for a dialog never shown")
        XCTAssertFalse(f.notifications.primerAlreadyShown)
        XCTAssertTrue(f.recorder.notificationResults.isEmpty)
        XCTAssertFalse(defaults.bool(forKey: FirstLaunchPermissionPolicy.notificationsAskedKey))

        f.center.presents = true
        let second = await f.coordinator.runIfNeeded(arguments: noArguments)
        await settle()
        XCTAssertFalse(second.deferred)
        XCTAssertFalse(second.askedTracking, "ATT already answered")
        XCTAssertNil(second.analyticsConsentApplied, "the ATT answer is mapped once, not twice")
        XCTAssertEqual(second.notificationsGranted, true)
        XCTAssertTrue(f.notifications.remindersEnabled)
        XCTAssertEqual(f.recorder.analytics, [true])
    }

    // MARK: - 4. Idempotent, one run at a time, skippable

    func testACompletedFlowAsksNothingOnLaterActivations() async {
        let f = makeFixture()
        await f.coordinator.runIfNeeded(arguments: noArguments)
        for _ in 0..<3 {
            let outcome = await f.coordinator.runIfNeeded(arguments: noArguments)
            XCTAssertFalse(outcome.askedTracking)
            XCTAssertFalse(outcome.askedNotifications)
            XCTAssertFalse(outcome.deferred)
        }
        XCTAssertEqual(f.tracking.requests, 1)
        XCTAssertEqual(f.center.requests, 1)
        XCTAssertEqual(f.adapter.starts, 1)
        XCTAssertEqual(f.recorder.analytics, [true])
    }

    /// An ATT answer re-activates the scene while the first run is still
    /// awaiting; the second call must not ask again.
    func testOverlappingRunsAskOnce() async {
        let f = makeFixture()
        async let a = f.coordinator.runIfNeeded(arguments: noArguments)
        async let b = f.coordinator.runIfNeeded(arguments: noArguments)
        _ = await (a, b)
        XCTAssertEqual(f.tracking.requests, 1)
        XCTAssertEqual(f.center.requests, 1)
    }

    func testSkipArgumentsAskNothingAndRequestNoAd() async {
        for argument in [FirstLaunchPermissionPolicy.skipArgument,
                         FirstLaunchPermissionPolicy.legacySkipArgument,
                         "-EBInstrumentationSmoke"] {
            let f = makeFixture()
            let outcome = await f.coordinator.runIfNeeded(arguments: ["EconByte", argument])
            XCTAssertTrue(outcome.skipped, argument)
            XCTAssertEqual(f.tracking.requests, 0, argument)
            XCTAssertEqual(f.center.requests, 0, argument)
            XCTAssertFalse(f.monetization.isHeldForLaunchPermissions, "\(argument): the hold is released")
            f.monetization.startAdsIfPermitted()
            XCTAssertEqual(f.adapter.starts, 0, "\(argument): still no ad before an ATT answer")
            defaults.removePersistentDomain(forName: suiteName)
        }
        XCTAssertEqual(FirstLaunchPermissionPolicy.skipArgument, "-EBSkipPermissionPrompts")
        XCTAssertEqual(FirstLaunchPermissionPolicy.legacySkipArgument, "-EBSkipConsentPrompt")
        for argument in [FirstLaunchPermissionPolicy.skipArgument, FirstLaunchPermissionPolicy.legacySkipArgument] {
            XCTAssertTrue(InstrumentationContext.automationArguments.contains(argument),
                          "a launch that skips the prompts must also be recognised as automation")
        }
    }

    // MARK: - 5. Upgrades from 1.1.2 keep their answers

    func testAnUpgraderWhoAnsweredBothIsNotPromptedAndKeepsTheirAnswers() async {
        defaults.set(false, forKey: EconTelemetry.Key.consent)
        ConsentPromptPolicy.noteShown(in: defaults)
        defaults.set(true, forKey: NotificationPolicy.primerShownDefaultsKey)
        let f = makeFixture(tracking: .authorized, notifications: .denied)

        let outcome = await f.coordinator.runIfNeeded(arguments: noArguments)
        XCTAssertFalse(outcome.askedTracking)
        XCTAssertFalse(outcome.askedNotifications)
        XCTAssertFalse(outcome.deferred)
        XCTAssertEqual(f.tracking.requests, 0)
        XCTAssertEqual(f.center.requests, 0)
        XCTAssertTrue(f.recorder.analytics.isEmpty, "a stored analytics answer is not rewritten")
        XCTAssertFalse(defaults.bool(forKey: EconTelemetry.Key.consent))
        XCTAssertEqual(f.adapter.starts, 1, "an already-decided ATT status lets ads start")
    }

    /// 1.1.2 asked ATT at a set exit; if iOS actually answered, it is not asked again.
    func testAnUpgraderWhoAnsweredATTAtASetExitIsNotAskedAgain() async {
        defaults.set(true, forKey: "econ.ads.trackingPromptRequested")
        let f = makeFixture(tracking: .denied)
        let outcome = await f.coordinator.runIfNeeded(arguments: noArguments)
        XCTAssertFalse(outcome.askedTracking)
        XCTAssertEqual(f.tracking.requests, 0)
        XCTAssertTrue(f.recorder.analytics.isEmpty, "no ATT prompt this launch, no mapping")
    }

    /// An earlier analytics answer (Settings switch, the 1.1 session-complete
    /// offer, or the unreleased 1.1.3 card) stands even when ATT is now allowed.
    func testAnEarlierAnalyticsAnswerIsNotOverriddenByANewAllow() async {
        let signals: [(String, (UserDefaults) -> Void)] = [
            ("settings switch", { $0.set(false, forKey: EconTelemetry.Key.consent) }),
            ("1.1 session-complete primer", { ConsentPromptPolicy.noteShown(in: $0) }),
            ("1.1.3 first-open card", { $0.set(1, forKey: FirstLaunchPermissionPolicy.legacyFirstOpenConsentKey) }),
        ]
        for (name, seed) in signals {
            defaults.removePersistentDomain(forName: suiteName)
            seed(defaults)
            XCTAssertTrue(FirstLaunchPermissionPolicy.analyticsAlreadyAnswered(defaults: defaults), name)
            let f = makeFixture(tracking: .notDetermined, resolutions: [.authorized])
            let outcome = await f.coordinator.runIfNeeded(arguments: noArguments)
            XCTAssertTrue(outcome.askedTracking, "\(name): ATT itself was never answered, so it is asked")
            XCTAssertNil(outcome.analyticsConsentApplied, "\(name): the earlier analytics answer stands")
            XCTAssertTrue(f.recorder.analytics.isEmpty, name)
        }
        defaults.removePersistentDomain(forName: suiteName)
        XCTAssertFalse(FirstLaunchPermissionPolicy.analyticsAlreadyAnswered(defaults: defaults),
                       "a fresh install has no analytics answer")
    }

    func testAnUpgraderWhoSawTheReminderPrimerIsNotAskedForNotifications() async {
        defaults.set(true, forKey: NotificationPolicy.primerShownDefaultsKey)
        let f = makeFixture(notifications: .notDetermined)
        let outcome = await f.coordinator.runIfNeeded(arguments: noArguments)
        XCTAssertFalse(outcome.askedNotifications)
        XCTAssertEqual(f.center.requests, 0)
        XCTAssertFalse(f.notifications.remindersEnabled, "their reminder stays as it was")
    }

    func testRemindersAlreadyOnOrAnAlreadyDecidedSystemStatusIsNotAsked() async {
        defaults.set(true, forKey: NotificationPolicy.enabledDefaultsKey)
        let on = makeFixture(notifications: .notDetermined)
        await on.coordinator.runIfNeeded(arguments: noArguments)
        XCTAssertEqual(on.center.requests, 0, "reminders already on")
        XCTAssertTrue(on.notifications.remindersEnabled)

        for status in [EconNotificationAuthorization.authorized, .denied] {
            defaults.removePersistentDomain(forName: suiteName)
            let f = makeFixture(notifications: status)
            let outcome = await f.coordinator.runIfNeeded(arguments: noArguments)
            XCTAssertFalse(outcome.askedNotifications, "\(status): iOS would show nothing")
            XCTAssertEqual(f.center.requests, 0)
            XCTAssertFalse(f.notifications.remindersEnabled, "\(status): the stored reminder state is kept")
        }
    }

    // MARK: - 6. Every install is asked; ads are still not served everywhere

    /// Build 15 skipped these readers, which is invisible to a reviewer. Build
    /// 16 asks them both prompts; DUD-224 and Remove Ads still mean no ad SDK.
    func testReadersWithoutAdsAreStillAskedBothPromptsButGetNoAd() async {
        let cases: [(String, EconAdRegionState, EconEntitlements)] = [
            ("EEA/UK", .restricted, EconEntitlements()),
            ("region unknown", .unknown, EconEntitlements()),
            ("Remove Ads", .allowed, EconEntitlements(removeAds: true)),
        ]
        for (name, region, entitlements) in cases {
            defaults.removePersistentDomain(forName: suiteName)
            let f = makeFixture(region: region, entitlements: entitlements)
            let outcome = await f.coordinator.runIfNeeded(arguments: noArguments)
            XCTAssertTrue(outcome.askedTracking, name)
            XCTAssertEqual(f.tracking.requests, 1, name)
            XCTAssertEqual(outcome.analyticsConsentApplied, true, name)
            XCTAssertTrue(outcome.askedNotifications, name)
            XCTAssertEqual(f.adapter.starts, 0, "\(name): no ad SDK")
        }
    }

    // MARK: - 7. One question, one answer

    func testAnsweringMarksTheSessionCompletePrimersAsShown() async {
        let f = makeFixture()
        await f.coordinator.runIfNeeded(arguments: noArguments)
        XCTAssertTrue(ConsentPromptPolicy.wasShown(in: defaults),
                      "the 1.1 session-complete analytics offer never asks the same question again")
        XCTAssertTrue(f.notifications.primerAlreadyShown,
                      "the 1.1 session-complete reminder primer never asks again")
        XCTAssertTrue(defaults.bool(forKey: FirstLaunchPermissionPolicy.notificationsAskedKey))
    }
}
