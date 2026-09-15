import XCTest
import UserNotifications
@testable import EconByte

/// First-launch permissions (1.1.4 shell redesign, Owner order 2026-09-14):
/// Apple's ATT prompt, then Apple's notifications prompt, once per install,
/// with ATT `.authorized` ⇒ analytics + crash reports ON (anything else OFF)
/// and notifications granted ⇒ the daily reminder ON (denied ⇒ OFF).
///
/// Neither system prompt can appear in a test process, so the ordering, the
/// mapping and every upgrade rule are asserted against doubles for the tracking
/// framework, the ad adapter and the notification centre.
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

    @MainActor
    private final class StubTracking: EconTrackingAuthorizing {
        var status: EconTrackingStatus
        let resolvesTo: EconTrackingStatus
        private(set) var requests = 0
        let log: Log

        init(status: EconTrackingStatus, resolvesTo: EconTrackingStatus, log: Log) {
            self.status = status
            self.resolvesTo = resolvesTo
            self.log = log
        }

        func requestAuthorization() async -> EconTrackingStatus {
            requests += 1
            log.entries.append("att.request")
            status = resolvesTo
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

    @MainActor
    private final class SpyCenter: EconNotificationScheduling {
        var authorization: EconNotificationAuthorization
        let grant: Bool
        private(set) var requests = 0
        var added: [UNNotificationRequest] = []
        let log: Log

        init(authorization: EconNotificationAuthorization, grant: Bool, log: Log) {
            self.authorization = authorization
            self.grant = grant
            self.log = log
        }

        nonisolated func econRequestAuthorization(_ completion: @escaping (Bool, Error?) -> Void) {
            Task { @MainActor in
                self.requests += 1
                self.log.entries.append("notifications.request")
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

    private final class Recorder {
        var analytics: [Bool] = []
        var negativeEvents: [EconNegativeSessionEvent] = []
        var notificationResults: [Bool] = []
    }

    private struct Fixture {
        let log: Log
        let tracking: StubTracking
        let adapter: LoggingAdapter
        let center: SpyCenter
        let monetization: EconMonetization
        let notifications: NotificationCoordinator
        let coordinator: FirstLaunchPermissionsCoordinator
        let recorder: Recorder
    }

    private func makeFixture(tracking status: EconTrackingStatus = .notDetermined,
                             resolvesTo: EconTrackingStatus = .authorized,
                             notifications notificationStatus: EconNotificationAuthorization = .notDetermined,
                             grant: Bool = true,
                             region: EconAdRegionState = .allowed,
                             entitlements: EconEntitlements = EconEntitlements()) -> Fixture {
        let log = Log()
        let tracking = StubTracking(status: status, resolvesTo: resolvesTo, log: log)
        let adapter = LoggingAdapter(log: log)
        let center = SpyCenter(authorization: notificationStatus, grant: grant, log: log)
        let monetization = EconMonetization(adapter: adapter,
                                            defaults: defaults,
                                            now: { Date(timeIntervalSince1970: 1_789_000_000) },
                                            region: { region },
                                            tracking: tracking)
        monetization.update(entitlements: entitlements)
        let notifications = NotificationCoordinator(center: center, defaults: defaults)
        let recorder = Recorder()
        let coordinator = FirstLaunchPermissionsCoordinator(
            monetization: monetization,
            notifications: notifications,
            defaults: defaults,
            applyAnalyticsConsent: { recorder.analytics.append($0) },
            noteNegativeSessionEvent: { recorder.negativeEvents.append($0) },
            recordNotificationResult: { recorder.notificationResults.append($0) })
        return Fixture(log: log, tracking: tracking, adapter: adapter, center: center,
                       monetization: monetization, notifications: notifications,
                       coordinator: coordinator, recorder: recorder)
    }

    private func settle() async {
        for _ in 0..<40 { await Task.yield() }
    }

    private let noArguments = ["EconByte"]

    // MARK: - 1. The mapping

    func testAllowOnBothPromptsTurnsOnAnalyticsCrashReportsAndTheDailyReminder() async {
        let f = makeFixture(resolvesTo: .authorized, grant: true)
        let outcome = await f.coordinator.runIfNeeded(arguments: noArguments)
        await settle()

        XCTAssertTrue(outcome.askedTracking)
        XCTAssertEqual(outcome.trackingStatus, .authorized)
        XCTAssertEqual(outcome.analyticsConsentApplied, true)
        XCTAssertEqual(f.recorder.analytics, [true], "ATT Allow ⇒ analytics + crash reports on")

        XCTAssertTrue(outcome.askedNotifications)
        XCTAssertEqual(outcome.notificationsGranted, true)
        XCTAssertTrue(f.notifications.remindersEnabled, "notifications granted ⇒ reminder on")
        XCTAssertTrue(defaults.bool(forKey: NotificationPolicy.enabledDefaultsKey))
        let reminder = f.center.added.first { $0.identifier == NotificationPolicy.reminderIdentifier }
        let trigger = reminder?.trigger as? UNCalendarNotificationTrigger
        XCTAssertEqual(trigger?.dateComponents.hour, 19, "scheduled at the existing default time")
        XCTAssertEqual(trigger?.dateComponents.minute, 0)
        XCTAssertEqual(f.recorder.notificationResults, [true],
                       "a dialog iOS presented is recorded as notification_permission_result")
    }

    func testDenyingBothLeavesAnalyticsAndTheReminderOff() async {
        let f = makeFixture(resolvesTo: .denied, grant: false)
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
        let f = makeFixture(resolvesTo: .restricted)
        let outcome = await f.coordinator.runIfNeeded(arguments: noArguments)
        XCTAssertEqual(outcome.analyticsConsentApplied, false)
    }

    /// iOS declines to present ATT when the app is not active; the status stays
    /// `.notDetermined`. That is not an answer, so nothing is written.
    func testAPromptIOSDidNotPresentWritesNoAnalyticsAnswer() async {
        let f = makeFixture(resolvesTo: .notDetermined)
        let outcome = await f.coordinator.runIfNeeded(arguments: noArguments)
        XCTAssertTrue(outcome.askedTracking)
        XCTAssertNil(outcome.analyticsConsentApplied)
        XCTAssertTrue(f.recorder.analytics.isEmpty)
        XCTAssertFalse(ConsentPromptPolicy.wasShown(in: defaults),
                       "with no answer the session-complete offer stays available")
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
        await f.coordinator.runIfNeeded(arguments: noArguments)

        let att = try? XCTUnwrap(f.log.index("att.request"))
        let notifications = try? XCTUnwrap(f.log.index("notifications.request"))
        let adStart = try? XCTUnwrap(f.log.index("ad.start"))
        XCTAssertNotNil(att); XCTAssertNotNil(notifications); XCTAssertNotNil(adStart)
        if let att, let notifications, let adStart {
            XCTAssertLessThan(att, notifications, "ATT first, then notifications")
            XCTAssertLessThan(notifications, adStart, "the ad SDK starts only after both prompts")
        }
        XCTAssertEqual(f.adapter.starts, 1)
        XCTAssertFalse(f.monetization.activeBlockers.contains(.systemPrompt),
                       "the system-prompt blocker is released when the flow ends")
    }

    func testBothPromptsDeferTheRatingAsk() async {
        let f = makeFixture()
        await f.coordinator.runIfNeeded(arguments: noArguments)
        XCTAssertEqual(f.recorder.negativeEvents, [.trackingPrompt, .notificationPrompt])
    }

    // MARK: - 3. Once per install

    func testTheFlowRunsOncePerProcessAndOncePerInstall() async {
        let first = makeFixture(resolvesTo: .notDetermined, grant: true)
        await first.coordinator.runIfNeeded(arguments: noArguments)
        await first.coordinator.runIfNeeded(arguments: noArguments)
        XCTAssertEqual(first.tracking.requests, 1)
        XCTAssertEqual(first.center.requests, 1)

        // Next launch, same install. Even though iOS left ATT `.notDetermined`
        // (it showed nothing) and the centre is reset to `.notDetermined`, the
        // persisted flags hold: neither prompt is attempted again.
        let second = makeFixture(tracking: .notDetermined, notifications: .notDetermined)
        let outcome = await second.coordinator.runIfNeeded(arguments: noArguments)
        XCTAssertFalse(outcome.askedTracking)
        XCTAssertFalse(outcome.askedNotifications)
        XCTAssertEqual(second.tracking.requests, 0)
        XCTAssertEqual(second.center.requests, 0)
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

    // MARK: - 4. Upgrades from 1.1.x keep their answers

    func testAnUpgraderWhoAnsweredBothIsNotPromptedAndKeepsTheirAnswers() async {
        defaults.set(false, forKey: EconTelemetry.Key.consent)
        ConsentPromptPolicy.noteShown(in: defaults)
        defaults.set(true, forKey: NotificationPolicy.primerShownDefaultsKey)
        let f = makeFixture(tracking: .authorized, notifications: .denied)

        let outcome = await f.coordinator.runIfNeeded(arguments: noArguments)
        XCTAssertFalse(outcome.askedTracking)
        XCTAssertFalse(outcome.askedNotifications)
        XCTAssertEqual(f.tracking.requests, 0)
        XCTAssertEqual(f.center.requests, 0)
        XCTAssertTrue(f.recorder.analytics.isEmpty, "a stored analytics answer is not rewritten")
        XCTAssertFalse(defaults.bool(forKey: EconTelemetry.Key.consent))
        XCTAssertEqual(f.adapter.starts, 1, "an already-decided ATT status lets ads start")
    }

    /// 1.1.2–1.1.3 asked ATT at a set exit and persisted that it did; iOS may
    /// have shown nothing. Either way it is not asked again.
    func testAnUpgraderAskedAtASetExitIsNotAskedATTAgain() async {
        defaults.set(true, forKey: "econ.ads.trackingPromptRequested")
        let f = makeFixture(tracking: .notDetermined)
        let outcome = await f.coordinator.runIfNeeded(arguments: noArguments)
        XCTAssertFalse(outcome.askedTracking)
        XCTAssertEqual(f.tracking.requests, 0)
        XCTAssertTrue(f.recorder.analytics.isEmpty)
    }

    /// An upgrader who never reached a set exit was never asked ATT; they are
    /// asked now. But if they already answered analytics (Settings switch, the
    /// 1.1 primer, or the 1.1.3 first-open card), that answer stands.
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
            let f = makeFixture(tracking: .notDetermined, resolvesTo: .authorized)
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

    // MARK: - 5. Readers without ads

    /// DUD-224 region and ad-free entitlements: no ads ⇒ no ATT prompt ⇒ no
    /// mapping (analytics stays at its stored answer, default off) — but the
    /// notifications prompt is still asked.
    func testReadersWithoutAdsAreNotShownATTButAreAskedForNotifications() async {
        let cases: [(String, EconAdRegionState, EconEntitlements)] = [
            ("EEA/UK", .restricted, EconEntitlements()),
            ("region unknown", .unknown, EconEntitlements()),
            ("Pro", .allowed, EconEntitlements(pro: true)),
            ("Remove Ads", .allowed, EconEntitlements(removeAds: true)),
        ]
        for (name, region, entitlements) in cases {
            defaults.removePersistentDomain(forName: suiteName)
            let f = makeFixture(region: region, entitlements: entitlements)
            let outcome = await f.coordinator.runIfNeeded(arguments: noArguments)
            XCTAssertFalse(outcome.askedTracking, name)
            XCTAssertEqual(f.tracking.requests, 0, name)
            XCTAssertNil(outcome.analyticsConsentApplied, name)
            XCTAssertTrue(outcome.askedNotifications, name)
            XCTAssertEqual(f.adapter.starts, 0, "\(name): no ad SDK")
        }
    }

    // MARK: - 6. One question, one answer

    func testAnsweringMarksTheSessionCompletePrimersAsShown() async {
        let f = makeFixture()
        await f.coordinator.runIfNeeded(arguments: noArguments)
        XCTAssertTrue(ConsentPromptPolicy.wasShown(in: defaults),
                      "the 1.1 session-complete analytics offer never asks the same question again")
        XCTAssertTrue(f.notifications.primerAlreadyShown,
                      "the 1.1 session-complete reminder primer never asks again")
        XCTAssertTrue(defaults.bool(forKey: FirstLaunchPermissionPolicy.notificationsAskedKey))
    }

    // MARK: - 7. Reminder time (Settings)

    func testReminderTimePersistsReschedulesAndRejectsInvalidValues() async {
        defaults.set(true, forKey: NotificationPolicy.enabledDefaultsKey)
        let f = makeFixture(notifications: .authorized)
        XCTAssertEqual(f.notifications.reminderHour, NotificationPolicy.reminderHour)
        XCTAssertEqual(f.notifications.reminderMinute, NotificationPolicy.reminderMinute)

        f.notifications.setReminderTime(hour: 7, minute: 30)
        await settle()
        let trigger = f.center.added.last?.trigger as? UNCalendarNotificationTrigger
        XCTAssertEqual(trigger?.dateComponents.hour, 7)
        XCTAssertEqual(trigger?.dateComponents.minute, 30)
        XCTAssertEqual(f.center.added.filter { $0.identifier == NotificationPolicy.reminderIdentifier }.count, 1,
                       "moving the time never leaves a duplicate reminder")

        f.notifications.setReminderTime(hour: 25, minute: 0)
        f.notifications.setReminderTime(hour: 8, minute: 60)
        XCTAssertEqual(f.notifications.reminderHour, 7, "out-of-range values are ignored")

        let relaunched = NotificationCoordinator(center: f.center, defaults: defaults)
        XCTAssertEqual(relaunched.reminderHour, 7)
        XCTAssertEqual(relaunched.reminderMinute, 30)
    }
}
