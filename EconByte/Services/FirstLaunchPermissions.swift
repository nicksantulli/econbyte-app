import Foundation
import UIKit

// MARK: - First-launch permissions (1.1.4 shell redesign, Owner order 2026-09-14;
//         hardened after the 1.1.3 App Review 2.1 rejection, 2026-09-15)
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
// HARDENING (Phase 14, `docs/audit/2026-09-15-att-rejection.md`). App Review
// could not find 1.1.3 build 15's ATT prompt on iOS/iPadOS 27. Build 15 asked
// once, at a set exit, only for readers with ads reachable, and marked the
// prompt spent before iOS had shown anything. This flow must never repeat that:
//
//   * ATT is owed while — and only while — iOS reports `.notDetermined`
//     (`EconMonetization.shouldRequestTrackingAuthorization`). No persisted
//     "asked" flag can hide a prompt iOS never showed.
//   * iOS returns `.notDetermined` WITHOUT UI when asked while the app is not
//     active or while a presentation is in flight. The coordinator asks only
//     when `EconPromptPresentationEnvironment.isReadyForSystemPrompt` (scene
//     `.active`, key window, nothing presented over the root, no transition),
//     retries a non-presented ask up to three times one second apart, and
//     otherwise defers: the app runs it again on every `.active`.
//   * Every install is asked, whatever its region or purchases (Remove Ads,
//     Pro, EEA/UK, unknown region): the binary links an ad SDK that declares
//     tracking and the App Privacy label says the app tracks, so a reviewer on
//     any device and any sandbox account must see the prompt. Ads themselves
//     are still never served in the EEA/UK or to Remove Ads / Pro readers.
//   * Notifications are never asked before ATT has an answer, and a
//     notifications ask iOS did not present is retried the same way.
//
// Upgraders keep what they answered:
//
//   * The ATT answer is mapped onto analytics ONLY when this install has never
//     given an analytics answer: the Settings switch (stored key present), the
//     1.1 session-complete primer, or the 1.1.3 first-open card. An upgrader
//     who already said yes or no keeps that answer.
//   * An upgrader whose ATT status iOS already decided is not asked; one whose
//     1.1.2 set-exit ask iOS never presented (still `.notDetermined`) IS asked.
//   * Notifications are asked only while iOS reports `.notDetermined`, the
//     reminder is off, and the 1.1 session-complete reminder primer was never
//     shown.
//   * Answering here marks the matching 1.1 session-complete primer as shown,
//     so no install is ever asked the same question twice.
//
// Ads: no provider call precedes the ATT answer (5.1.2(i); `adRequestsPermitted`
// is status-only); the `.systemPrompt` blocker is held for the whole flow and
// the SDK is started only after it has run. Phase 25: an "Allow" (outside the
// EEA/UK/CH, in a known region) makes ad requests personalized; every other
// answer keeps them `npa=1`/`rdp=1` (`EconAdPersonalization`).
//
// GDPR note (flagged for the Owner, not decided here): an ATT "Allow" is
// Apple's tracking permission, not necessarily GDPR/ePrivacy consent for
// analytics. Since the Phase 14 hardening EEA/UK readers ARE shown ATT, so an
// Allow there also turns analytics on (the purpose string says so).

enum FirstLaunchPermissionPolicy {

    /// Launch arguments that stand the whole flow down (UI tests, screenshot
    /// runs). `-EBSkipConsentPrompt` is the 1.1.3 argument every existing UI test
    /// already passes; both are `InstrumentationContext` automation markers.
    static let skipArgument = "-EBSkipPermissionPrompts"
    static let legacySkipArgument = "-EBSkipConsentPrompt"

    /// Set once iOS has actually presented the notifications prompt from this
    /// flow (evidence only; the gate is the system status).
    static let notificationsAskedKey = "econ.permissions.notificationsAsked"

    /// The 1.1.3 first-open consent card's stored answer. The card is gone in
    /// 1.1.4; the key is read only to honour an answer it already collected.
    static let legacyFirstOpenConsentKey = "ebAnalyticsConsentPromptVersion"

    /// How many times one run asks for ATT when iOS returns without an answer.
    static let maxTrackingAttemptsPerRun = 3
    /// The pause before a retry (and before re-checking readiness).
    static let retryDelayNanoseconds: UInt64 = 1_000_000_000

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

    /// Notifications are owed while iOS has no answer, the reminder is off, and
    /// the 1.1 session-complete reminder primer was never shown.
    static func shouldAskNotifications(status: EconNotificationAuthorization,
                                       remindersEnabled: Bool,
                                       primerAlreadyShown: Bool) -> Bool {
        status == .notDetermined && !remindersEnabled && !primerAlreadyShown
    }
}

/// Whether iOS would actually present a system prompt right now. Injected so
/// the defer-and-retry rules are unit-tested (no system prompt can appear in a
/// test process).
@MainActor
protocol EconPromptPresentationEnvironment: AnyObject {
    var isReadyForSystemPrompt: Bool { get }
}

/// The live check: the app is active, a foreground-active window scene has a
/// key window, and nothing is presented over (or transitioning on) its root.
/// SwiftUI `.sheet` / `.fullScreenCover` / `.alert` present through UIKit, so a
/// non-nil `presentedViewController` is exactly "a sheet or cover is up". The
/// same holds for an iPhone-only app running in compatibility mode on iPad.
@MainActor
final class LivePromptPresentationEnvironment: EconPromptPresentationEnvironment {
    static let shared = LivePromptPresentationEnvironment()

    var isReadyForSystemPrompt: Bool {
        guard UIApplication.shared.applicationState == .active else { return false }
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let window = scene.windows.first(where: { $0.isKeyWindow }),
              let root = window.rootViewController
        else { return false }
        if root.presentedViewController != nil { return false }
        if root.transitionCoordinator != nil { return false }
        return true
    }
}

/// Runs the two system prompts in order and applies the mapping. Safe to call
/// on every activation: anything already answered is skipped, and a run iOS
/// could not present reports `deferred` and simply runs again next time. Every
/// dependency is injected so the ordering, the retries and the upgrade rules are
/// unit-tested against doubles.
@MainActor
final class FirstLaunchPermissionsCoordinator {

    struct Outcome: Equatable {
        var skipped = false
        /// A prompt was owed but iOS could not show it this run (not active,
        /// something presented, or it returned without an answer). The flow
        /// runs again the next time the scene becomes active.
        var deferred = false
        var askedTracking = false
        var trackingAttempts = 0
        var trackingStatus: EconTrackingStatus = .notDetermined
        /// The analytics + crash-report consent written, or nil when untouched.
        var analyticsConsentApplied: Bool?
        var askedNotifications = false
        /// Whether iOS granted notifications, or nil when no dialog was shown.
        var notificationsGranted: Bool?
    }

    private let monetization: EconMonetization
    private let notifications: NotificationCoordinator
    private let defaults: UserDefaults
    private let environment: EconPromptPresentationEnvironment
    private let pause: (UInt64) async -> Void
    private let applyAnalyticsConsent: (Bool) -> Void
    private let noteNegativeSessionEvent: (EconNegativeSessionEvent) -> Void
    private let recordNotificationResult: (Bool) -> Void

    private(set) var isRunning = false

    init(monetization: EconMonetization,
         notifications: NotificationCoordinator,
         defaults: UserDefaults,
         environment: EconPromptPresentationEnvironment,
         pause: @escaping (UInt64) async -> Void = { try? await Task.sleep(nanoseconds: $0) },
         applyAnalyticsConsent: @escaping (Bool) -> Void,
         noteNegativeSessionEvent: @escaping (EconNegativeSessionEvent) -> Void = { _ in },
         recordNotificationResult: @escaping (Bool) -> Void = { _ in }) {
        self.monetization = monetization
        self.notifications = notifications
        self.defaults = defaults
        self.environment = environment
        self.pause = pause
        self.applyAnalyticsConsent = applyAnalyticsConsent
        self.noteNegativeSessionEvent = noteNegativeSessionEvent
        self.recordNotificationResult = recordNotificationResult
    }

    /// Call once the studio intro has gone, and again on every `.active`.
    @discardableResult
    func runIfNeeded(arguments: [String] = ProcessInfo.processInfo.arguments) async -> Outcome {
        var outcome = Outcome()
        guard !FirstLaunchPermissionPolicy.isSkipped(arguments: arguments) else {
            outcome.skipped = true
            monetization.setLaunchPermissionsHold(false)
            return outcome
        }
        // One run at a time: an ATT answer re-activates the scene while the
        // first run is still awaiting.
        guard !isRunning else { return outcome }
        isRunning = true
        defer { isRunning = false }

        // 1. App Tracking Transparency.
        let analyticsAnswered = FirstLaunchPermissionPolicy.analyticsAlreadyAnswered(defaults: defaults)
        if monetization.shouldRequestTrackingAuthorization {
            monetization.setBlocker(.systemPrompt, active: true)
            var status = EconTrackingStatus.notDetermined
            for attempt in 1...FirstLaunchPermissionPolicy.maxTrackingAttemptsPerRun {
                if attempt > 1 { await pause(FirstLaunchPermissionPolicy.retryDelayNanoseconds) }
                guard environment.isReadyForSystemPrompt else { continue }
                if !outcome.askedTracking {
                    outcome.askedTracking = true
                    noteNegativeSessionEvent(.trackingPrompt)
                }
                outcome.trackingAttempts += 1
                status = await monetization.resolveTrackingAuthorizationIfNeeded(startingAds: false)
                if status.isDecided { break }
            }
            outcome.trackingStatus = status
            guard status.isDecided else {
                // No answer yet: nothing is mapped, notifications are not asked
                // out of order, and no ad may start. Retried on the next `.active`.
                monetization.setBlocker(.systemPrompt, active: false)
                outcome.deferred = true
                return outcome
            }
        } else {
            outcome.trackingStatus = monetization.trackingStatus
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

        // 2. Notifications — only once ATT has an answer.
        let notificationStatus = await notifications.currentAuthorization()
        if FirstLaunchPermissionPolicy.shouldAskNotifications(
            status: notificationStatus,
            remindersEnabled: notifications.remindersEnabled,
            primerAlreadyShown: notifications.primerAlreadyShown) {
            // The ATT alert's dismissal re-activates the scene a beat later.
            if !environment.isReadyForSystemPrompt {
                await pause(FirstLaunchPermissionPolicy.retryDelayNanoseconds)
            }
            if environment.isReadyForSystemPrompt {
                outcome.askedNotifications = true
                noteNegativeSessionEvent(.notificationPrompt)
                let result = await notifications.requestAuthorizationForFirstLaunch()
                if result.presented {
                    defaults.set(true, forKey: FirstLaunchPermissionPolicy.notificationsAskedKey)
                    // The 1.1 session-complete reminder primer must not ask again.
                    notifications.notePrimerShown()
                    outcome.notificationsGranted = result.granted
                    recordNotificationResult(result.granted)
                } else {
                    outcome.deferred = true
                }
            } else {
                outcome.deferred = true
            }
        }

        // Only now may an ad be requested (still gated on the ATT answer,
        // entitlement and region inside `startAdsIfPermitted`).
        monetization.setBlocker(.systemPrompt, active: false)
        monetization.setLaunchPermissionsHold(false)
        monetization.startAdsIfPermitted()
        return outcome
    }

    #if DEBUG
    static func resetPersistedState(in defaults: UserDefaults) {
        defaults.removeObject(forKey: FirstLaunchPermissionPolicy.notificationsAskedKey)
        defaults.removeObject(forKey: FirstLaunchPermissionPolicy.legacyFirstOpenConsentKey)
    }
    #endif
}
