import Foundation

// MARK: - First-launch permissions (1.1.4 shell redesign, Owner order 2026-09-14)
//
// Replaces the 1.1.3 custom analytics consent card and the at-first-set-exit
// ATT ask. After the studio intro fades, the app asks Apple's two standard
// system prompts, in this order and with no custom pre-prompt screen:
//
//   1. App Tracking Transparency (`ATTrackingManager.requestTrackingAuthorization`,
//      reached only through `EconTrackingAuthorization`).
//   2. Notifications (`UNUserNotificationCenter.requestAuthorization`, reached
//      only through `NotificationCoordinator`).
//
// Mapping (Owner: "If they opt in then we should auto toggle on notifications
// and analytics"):
//
//   * ATT `.authorized`  ⇒ usage analytics + crash reports ON.
//     ATT denied/restricted ⇒ both OFF. A prompt iOS declined to present
//     (status still `.notDetermined`) writes nothing.
//   * Notifications granted ⇒ the daily reminder ON at the stored time
//     (default 7:00 p.m.); denied ⇒ OFF.
//   * Both stay user-controllable in Settings. Analytics can be switched on
//     even after an ATT denial — it is first-party and is not tracking.
//
// Once per install, and never over an earlier answer:
//
//   * ATT is asked only while `EconMonetization.shouldRequestTrackingAuthorization`
//     holds — status `.notDetermined`, never requested before (the 1.1.2–1.1.3
//     set-exit ask shares the same persisted flag), and ads actually reachable
//     for this reader (no Remove Ads / Pro entitlement, not EEA/UK — DUD-224).
//     An install where ads are unreachable is not asked; its analytics stays
//     at its stored answer (default off) and Settings remains the control.
//   * The ATT answer is mapped onto analytics ONLY when this install has never
//     given an analytics answer: the Settings switch (stored key present), the
//     1.1 session-complete primer, or the 1.1.3 first-open card. An upgrader
//     who already said yes or no keeps that answer.
//   * Notifications are asked only while iOS reports `.notDetermined`, the
//     reminder is off, the 1.1 session-complete reminder primer was never
//     shown, and this flow has not asked before.
//   * Answering here marks the matching 1.1 session-complete primer as shown,
//     so no install is ever asked the same question twice.
//
// Ads: no provider call precedes the ATT answer (5.1.2(i)); the `.systemPrompt`
// blocker is held for the whole flow and the SDK is started only after the
// second prompt resolves. Requests stay `npa=1`/`rdp=1` for every answer —
// personalization is a portfolio policy revision, not an EconByte edit.
//
// GDPR note (flagged for the Owner, not decided here): an ATT "Allow" is
// Apple's tracking permission, not necessarily GDPR/ePrivacy consent for
// analytics. EEA/UK readers are not shown ATT at all (no ads there), so their
// analytics stays opt-in via Settings or the session-complete primer.

enum FirstLaunchPermissionPolicy {

    /// Launch arguments that stand the whole flow down (UI tests, screenshot
    /// runs). `-EBSkipConsentPrompt` is the 1.1.3 argument every existing UI test
    /// already passes; both are `InstrumentationContext` automation markers.
    static let skipArgument = "-EBSkipPermissionPrompts"
    static let legacySkipArgument = "-EBSkipConsentPrompt"

    /// Set the moment this flow asks for notifications (before awaiting), so a
    /// prompt interrupted by a kill is still "asked once".
    static let notificationsAskedKey = "econ.permissions.notificationsAsked"

    /// The 1.1.3 first-open consent card's stored answer. The card is gone in
    /// 1.1.4; the key is read only to honour an answer it already collected.
    static let legacyFirstOpenConsentKey = "ebAnalyticsConsentPromptVersion"

    static func isSkipped(arguments: [String]) -> Bool {
        arguments.contains(skipArgument)
            || arguments.contains(legacySkipArgument)
            // The DEBUG instrumentation smoke grants consent programmatically.
            || arguments.contains("-EBInstrumentationSmoke")
    }

    /// Whether this install already answered the analytics question anywhere.
    static func analyticsAlreadyAnswered(defaults: UserDefaults) -> Bool {
        defaults.object(forKey: EconTelemetry.Key.consent) != nil
            || ConsentPromptPolicy.wasShown(in: defaults)
            || defaults.integer(forKey: legacyFirstOpenConsentKey) > 0
    }

    /// The analytics + crash-report consent to write after the ATT prompt, or
    /// `nil` to leave the stored answer untouched.
    static func analyticsConsent(afterTracking status: EconTrackingStatus,
                                 promptWasAsked: Bool,
                                 analyticsAlreadyAnswered: Bool) -> Bool? {
        guard promptWasAsked, !analyticsAlreadyAnswered else { return nil }
        switch status {
        case .authorized: return true
        case .denied, .restricted: return false
        case .notDetermined: return nil      // iOS showed nothing; no answer to map
        }
    }

    static func shouldAskNotifications(status: EconNotificationAuthorization,
                                       remindersEnabled: Bool,
                                       primerAlreadyShown: Bool,
                                       alreadyAsked: Bool) -> Bool {
        status == .notDetermined && !remindersEnabled && !primerAlreadyShown && !alreadyAsked
    }
}

/// Runs the two system prompts once, in order, and applies the mapping. Every
/// dependency is injected so the ordering and the upgrade rules are unit-tested
/// against doubles (neither system prompt can appear in a test process).
@MainActor
final class FirstLaunchPermissionsCoordinator {

    struct Outcome: Equatable {
        var skipped = false
        var askedTracking = false
        var trackingStatus: EconTrackingStatus = .notDetermined
        /// The analytics + crash-report consent written, or nil when untouched.
        var analyticsConsentApplied: Bool?
        var askedNotifications = false
        /// Whether iOS granted notifications, or nil when not asked.
        var notificationsGranted: Bool?
    }

    private let monetization: EconMonetization
    private let notifications: NotificationCoordinator
    private let defaults: UserDefaults
    private let applyAnalyticsConsent: (Bool) -> Void
    private let noteNegativeSessionEvent: (EconNegativeSessionEvent) -> Void
    private let recordNotificationResult: (Bool) -> Void

    private(set) var isRunning = false
    private var didRunThisProcess = false

    init(monetization: EconMonetization,
         notifications: NotificationCoordinator,
         defaults: UserDefaults,
         applyAnalyticsConsent: @escaping (Bool) -> Void,
         noteNegativeSessionEvent: @escaping (EconNegativeSessionEvent) -> Void = { _ in },
         recordNotificationResult: @escaping (Bool) -> Void = { _ in }) {
        self.monetization = monetization
        self.notifications = notifications
        self.defaults = defaults
        self.applyAnalyticsConsent = applyAnalyticsConsent
        self.noteNegativeSessionEvent = noteNegativeSessionEvent
        self.recordNotificationResult = recordNotificationResult
    }

    /// Call once the studio intro has gone and the scene is active. Safe to
    /// call on every cold launch: anything already answered is skipped.
    @discardableResult
    func runIfNeeded(arguments: [String] = ProcessInfo.processInfo.arguments) async -> Outcome {
        var outcome = Outcome()
        guard !FirstLaunchPermissionPolicy.isSkipped(arguments: arguments) else {
            outcome.skipped = true
            return outcome
        }
        guard !didRunThisProcess, !isRunning else { return outcome }
        didRunThisProcess = true
        isRunning = true
        monetization.setBlocker(.systemPrompt, active: true)

        // 1. App Tracking Transparency.
        let analyticsAnswered = FirstLaunchPermissionPolicy.analyticsAlreadyAnswered(defaults: defaults)
        if monetization.shouldRequestTrackingAuthorization {
            outcome.askedTracking = true
            noteNegativeSessionEvent(.trackingPrompt)
            outcome.trackingStatus = await monetization.resolveTrackingAuthorizationIfNeeded(startingAds: false)
        } else {
            outcome.trackingStatus = monetization.currentRequestPolicy.trackingStatus
        }
        if let consent = FirstLaunchPermissionPolicy.analyticsConsent(
            afterTracking: outcome.trackingStatus,
            promptWasAsked: outcome.askedTracking,
            analyticsAlreadyAnswered: analyticsAnswered) {
            applyAnalyticsConsent(consent)
            outcome.analyticsConsentApplied = consent
            // The 1.1 session-complete consent offer must not ask again.
            ConsentPromptPolicy.noteShown(in: defaults)
        }

        // 2. Notifications.
        let status = await notifications.currentAuthorization()
        if FirstLaunchPermissionPolicy.shouldAskNotifications(
            status: status,
            remindersEnabled: notifications.remindersEnabled,
            primerAlreadyShown: notifications.primerAlreadyShown,
            alreadyAsked: defaults.bool(forKey: FirstLaunchPermissionPolicy.notificationsAskedKey)) {
            outcome.askedNotifications = true
            defaults.set(true, forKey: FirstLaunchPermissionPolicy.notificationsAskedKey)
            // The 1.1 session-complete reminder primer must not ask again.
            notifications.notePrimerShown()
            noteNegativeSessionEvent(.notificationPrompt)
            let result = await notifications.requestAuthorizationForFirstLaunch()
            outcome.notificationsGranted = result.granted
            if result.presented { recordNotificationResult(result.granted) }
        }

        // Only now may an ad be requested.
        monetization.setBlocker(.systemPrompt, active: false)
        monetization.startAdsIfPermitted()
        isRunning = false
        return outcome
    }

    #if DEBUG
    static func resetPersistedState(in defaults: UserDefaults) {
        defaults.removeObject(forKey: FirstLaunchPermissionPolicy.notificationsAskedKey)
        defaults.removeObject(forKey: FirstLaunchPermissionPolicy.legacyFirstOpenConsentKey)
    }
    #endif
}
