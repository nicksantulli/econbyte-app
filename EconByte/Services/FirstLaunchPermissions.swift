import Foundation
import UIKit

// MARK: - First-launch permissions (1.1.3 build 16 — App Review 2.1 fix, 2026-09-15)
//
// WHY THIS FILE EXISTS. See `docs/audit/2026-09-15-att-rejection.md`.
//
// App Review rejected 1.1.3 build 15 under Guideline 2.1 (Information Needed):
// on iOS 27.0 and iPadOS 27.0 the reviewer completed a session and tapped both
// "Done" and "Browse More Topics" and never saw the App Tracking Transparency
// prompt. Build 15 asked ATT at most once per install, only at a completed
// set's exit, only when ads were reachable (no Remove Ads, device Region
// outside the EEA/UK), and it recorded the prompt as spent BEFORE iOS had shown
// anything — so one silent no-show suppressed it for the rest of the install.
//
// Build 16 asks the way the Owner has ordered for every Dudley app (ported
// narrowly from the 1.1.4 line's `FirstLaunchPermissions.swift`). It replaces
// the 1.1.3 first-open analytics consent card and the at-set-exit ATT ask.
//
//   1. After the studio intro has gone, once the scene is foreground-active
//      and nothing is presented over the root (no sheet, no cover, no
//      transition): Apple's standard ATT prompt
//      (`ATTrackingManager.requestTrackingAuthorization`, reached only through
//      `EconTrackingAuthorization`).
//   2. Then Apple's standard notifications prompt (through
//      `NotificationCoordinator`). No custom pre-prompt screen.
//
// Mapping (Owner): ATT `.authorized` ⇒ usage analytics + crash reports ON;
// denied or restricted ⇒ both OFF. Notifications granted ⇒ the daily reminder
// ON at 7:00 p.m.; denied ⇒ OFF. Settings remains the control for all three
// (analytics may be switched on after an ATT denial — it is first-party and is
// not tracking).
//
// What build 15 got wrong, and what replaces it:
//
//   * ATT is owed while — and only while — iOS reports `.notDetermined`. No
//     "asked once" flag exists that a prompt iOS never showed can spend.
//   * iOS returns `.notDetermined` WITHOUT showing anything when asked while the
//     app is not active or while a presentation is in flight. The coordinator
//     asks only when `EconPromptPresentationEnvironment.isReadyForSystemPrompt`,
//     tries a non-presented ask up to three times one second apart, and
//     otherwise defers to the next time the scene becomes active (the app calls
//     `runIfNeeded` again on every `.active`).
//   * ATT is asked regardless of region and purchases. The binary links an ad
//     SDK whose privacy manifest declares tracking and the App Privacy label
//     says the app tracks, so the prompt must be findable on every review
//     device and every sandbox account. Ads themselves are still never served
//     in the EEA/UK (DUD-224) or to Remove Ads owners.
//   * Notifications are never asked before ATT has an answer, and a
//     notifications ask iOS did not present is retried the same way.
//
// Upgraders from 1.1.2 keep what they answered: an analytics answer given
// anywhere (Settings, the 1.1 session-complete offer, the unreleased 1.1.3
// card) is never overwritten by the ATT mapping; a reader who already saw the
// reminder primer, has reminders on, or whose notification status iOS already
// decided is not asked for notifications. A 1.1.2 install whose set-exit ATT
// ask iOS never presented (status still `.notDetermined`) IS asked now.
//
// Ads: no provider call precedes an ATT answer (`EconMonetization
// .adRequestsPermitted` is status-only), and the SDK starts only after the flow
// has run (`isHeldForLaunchPermissions`). Requests stay `npa=1`/`rdp=1` for
// every answer — personalization is a portfolio policy revision.

enum FirstLaunchPermissionPolicy {

    /// Launch arguments that stand the whole flow down (UI tests, screenshot
    /// runs). `-EBSkipConsentPrompt` is the 1.1.3 argument every existing UI
    /// test already passes; both are `InstrumentationContext` automation markers.
    static let skipArgument = "-EBSkipPermissionPrompts"
    static let legacySkipArgument = "-EBSkipConsentPrompt"

    /// Set once iOS has actually presented the notifications prompt from this
    /// flow (evidence only; the gate is the system status).
    static let notificationsAskedKey = "econ.permissions.notificationsAsked"

    /// The unreleased 1.1.3 first-open consent card's stored answer (builds 14
    /// and 15, TestFlight/review only). Read only to honour an answer it
    /// already collected.
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

    /// Notifications are owed while iOS has no answer, the reminder is off,
    /// and the 1.1 session-complete reminder primer was never shown.
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
/// non-nil `presentedViewController` is exactly "a sheet or cover is up".
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

/// Runs the two system prompts in order, applies the mapping, and can be called
/// on every activation: anything already answered is skipped, and a run iOS
/// could not present is reported `deferred` and simply runs again next time.
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
