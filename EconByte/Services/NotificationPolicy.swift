import Foundation
import UserNotifications

// MARK: - Notifications (design section 11.1)
//
// Default off. 1.1–1.1.3 showed the system dialog only after an explicit opt-in
// from the Session Complete primer or Settings (1.0 prompted one second after
// Home first appeared). 1.1.4 asks Apple's standard dialog once at first launch,
// after the studio intro (`FirstLaunchPermissionsCoordinator`); a grant turns the
// reminder on at the stored time, a denial leaves it off. The reminder carries no financial claim,
// urgency, or streak-loss pressure; 1.0's copy did. See `CONTENT-DECISIONS.md` D8.

public enum EconNotificationAuthorization: Equatable {
    case notDetermined
    case authorized
    case denied
}

/// Test seam over `UNUserNotificationCenter`.
public protocol EconNotificationScheduling: AnyObject {
    func econRequestAuthorization(_ completion: @escaping (Bool, Error?) -> Void)
    func econAuthorizationStatus(_ completion: @escaping (EconNotificationAuthorization) -> Void)
    func econAdd(_ request: UNNotificationRequest, completion: @escaping (Error?) -> Void)
    func econRemovePendingRequests(withIdentifiers identifiers: [String])
    func econRemoveDeliveredNotifications(withIdentifiers identifiers: [String])
    func econPendingRequestIdentifiers(_ completion: @escaping ([String]) -> Void)
}

extension UNUserNotificationCenter: EconNotificationScheduling {
    public func econRequestAuthorization(_ completion: @escaping (Bool, Error?) -> Void) {
        requestAuthorization(options: [.alert, .sound], completionHandler: completion)
    }

    public func econAuthorizationStatus(_ completion: @escaping (EconNotificationAuthorization) -> Void) {
        getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined: completion(.notDetermined)
            case .denied: completion(.denied)
            default: completion(.authorized)
            }
        }
    }

    public func econAdd(_ request: UNNotificationRequest, completion: @escaping (Error?) -> Void) {
        add(request, withCompletionHandler: completion)
    }

    public func econRemovePendingRequests(withIdentifiers identifiers: [String]) {
        removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    public func econRemoveDeliveredNotifications(withIdentifiers identifiers: [String]) {
        removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    public func econPendingRequestIdentifiers(_ completion: @escaping ([String]) -> Void) {
        getPendingNotificationRequests { completion($0.map(\.identifier)) }
    }
}

public enum NotificationPolicy {

    public static let reminderIdentifier = "econbyte.daily-reminder"
    public static let enabledDefaultsKey = "econ.notifications.enabled"
    public static let primerShownDefaultsKey = "econ.notifications.primerShown"
    /// The default reminder time; Settings can move it (1.1.4).
    public static let reminderHour = 19
    public static let reminderMinute = 0
    public static let reminderHourDefaultsKey = "econ.notifications.hour"
    public static let reminderMinuteDefaultsKey = "econ.notifications.minute"

    public static var reminderTitle: String { "EconByte" }
    public static var reminderBody: String { "Today's cards are ready when you are." }

    public static var primerHeadline: String { "A quiet daily nudge?" }
    public static var primerBody: String {
        "We can remind you at 7:00 p.m. that today's cards are waiting. You can turn it off any time in Settings."
    }

    /// Words the reminder copy may never contain: financial claims, urgency, or
    /// streak-loss pressure. Matched at word starts, so "rate" also catches
    /// "rates" and "invest" catches "investing".
    public static let prohibitedCopyTerms: [String] = [
        "risk", "streak", "urgent", "hurry", "last chance", "don't lose", "dont lose",
        "invest", "money", "returns", "market", "rate", "act now", "expires",
        "losing", "lose your", "guaranteed", "profit", "stocks", "crypto",
        "limited time", "final warning",
    ]

    public static func copyIsCompliant(_ text: String) -> Bool {
        let lowered = text.lowercased()
        for term in prohibitedCopyTerms {
            if term.contains(" ") {
                if lowered.contains(term) { return false }
            } else {
                let pattern = "\\b" + NSRegularExpression.escapedPattern(for: term)
                guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
                let range = NSRange(lowered.startIndex..., in: lowered)
                if regex.firstMatch(in: lowered, range: range) != nil { return false }
            }
        }
        return true
    }

    public static func makeReminderRequest(hour: Int = reminderHour,
                                           minute: Int = reminderMinute) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = reminderTitle
        content.body = reminderBody
        content.sound = .default

        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

        return UNNotificationRequest(identifier: reminderIdentifier,
                                     content: content,
                                     trigger: trigger)
    }

    /// The primer is contextual: it appears after a completed set, once, and
    /// never when reminders are already on.
    ///
    /// `consentPromptVisible` defers it by one completed set when the analytics
    /// and diagnostics choices are occupying the same moment, so a reader is
    /// never asked two unrelated questions on one screen. See
    /// `CONTENT-DECISIONS.md` D10.
    ///
    /// `authorizationDenied` suppresses it entirely: a reader who already denied
    /// notifications — including anyone upgrading from 1.0, which prompted
    /// automatically on first launch — would otherwise get a primer whose button
    /// can do nothing, because iOS never re-presents the dialog.
    public static func primerEligible(completedSetCount: Int,
                                      primerAlreadyShown: Bool,
                                      remindersEnabled: Bool,
                                      consentPromptVisible: Bool = false,
                                      authorizationDenied: Bool = false) -> Bool {
        completedSetCount >= 1 && !primerAlreadyShown && !remindersEnabled
            && !consentPromptVisible && !authorizationDenied
    }
}

@MainActor
public final class NotificationCoordinator: ObservableObject {

    @Published public private(set) var remindersEnabled: Bool
    @Published public private(set) var authorization: EconNotificationAuthorization = .notDetermined
    /// The daily reminder's local time (1.1.4: user-set in Settings).
    @Published public private(set) var reminderHour: Int
    @Published public private(set) var reminderMinute: Int
    public private(set) var didRequestAuthorization = false

    /// Set when scheduling fails, so the caller can raise a diagnostic code.
    public private(set) var lastScheduleError: Error?

    /// Raised on a scheduling failure so the caller can record
    /// `notification_schedule_failed`.
    public var onScheduleFailure: ((Error) -> Void)?

    private let center: EconNotificationScheduling
    private let defaults: UserDefaults

    public init(center: EconNotificationScheduling = UNUserNotificationCenter.current(),
                defaults: UserDefaults = .standard) {
        self.center = center
        self.defaults = defaults
        self.remindersEnabled = defaults.bool(forKey: NotificationPolicy.enabledDefaultsKey)
        let storedHour = defaults.object(forKey: NotificationPolicy.reminderHourDefaultsKey) as? Int
        let storedMinute = defaults.object(forKey: NotificationPolicy.reminderMinuteDefaultsKey) as? Int
        self.reminderHour = (0...23).contains(storedHour ?? -1) ? storedHour! : NotificationPolicy.reminderHour
        self.reminderMinute = (0...59).contains(storedMinute ?? -1) ? storedMinute! : NotificationPolicy.reminderMinute
        refreshAuthorization()
    }

    public func refreshAuthorization() {
        center.econAuthorizationStatus { status in
            Task { @MainActor in self.authorization = status }
        }
    }

    /// The only path to the system dialog. A previously denied reader is linked
    /// to system settings by the caller rather than prompted again.
    ///
    /// `onAuthorizationResolved` fires **only when a system dialog actually
    /// resolved**, so `notification_permission_result` records what iOS did
    /// rather than what the reader intended. Paths where no dialog is presented —
    /// reminders already on, authorization already denied, or authorization
    /// already granted (iOS returns immediately and shows nothing) — report
    /// nothing at all.
    ///
    /// The decision reads a *fresh* status from the notification centre rather
    /// than the published cache, which `refreshAuthorization()` fills
    /// asynchronously. A stale `.notDetermined` cache on an already-authorized
    /// reader would otherwise emit a permission result for a dialog iOS never
    /// showed — exactly the conflation this guarantee exists to prevent.
    public func enableReminders(onAuthorizationResolved: ((Bool) -> Void)? = nil) {
        guard !remindersEnabled else { return }

        center.econAuthorizationStatus { status in
            Task { @MainActor in
                self.authorization = status
                guard status != .denied else { return }

                // iOS presents the dialog only from `.notDetermined`.
                let willPresentSystemDialog = (status == .notDetermined)
                self.didRequestAuthorization = true
                self.center.econRequestAuthorization { granted, _ in
                    Task { @MainActor in
                        self.authorization = granted ? .authorized : .denied
                        if granted {
                            self.persist(true)
                            self.schedule()
                        } else {
                            self.persist(false)
                        }
                        if willPresentSystemDialog { onAuthorizationResolved?(granted) }
                    }
                }
            }
        }
    }

    /// A fresh read of the system status (the published cache fills
    /// asynchronously and may still say `.notDetermined`).
    public func currentAuthorization() async -> EconNotificationAuthorization {
        let status = await withCheckedContinuation { continuation in
            center.econAuthorizationStatus { continuation.resume(returning: $0) }
        }
        authorization = status
        return status
    }

    /// The first-launch ask (1.1.4). Unlike `enableReminders`, it always
    /// completes, and it reports whether a dialog was actually presented, so
    /// `notification_permission_result` still records only what iOS did.
    /// Granted ⇒ reminder on at the stored time; denied ⇒ reminder off.
    public func requestAuthorizationForFirstLaunch() async -> (presented: Bool, granted: Bool) {
        let status = await currentAuthorization()
        guard status == .notDetermined else {
            return (false, status == .authorized)
        }
        didRequestAuthorization = true
        let granted = await withCheckedContinuation { continuation in
            center.econRequestAuthorization { granted, _ in continuation.resume(returning: granted) }
        }
        authorization = granted ? .authorized : .denied
        persist(granted)
        if granted { schedule() }
        return (true, granted)
    }

    /// Moves the daily reminder. Persisted; reschedules at once when it is on.
    public func setReminderTime(hour: Int, minute: Int) {
        guard (0...23).contains(hour), (0...59).contains(minute) else { return }
        reminderHour = hour
        reminderMinute = minute
        defaults.set(hour, forKey: NotificationPolicy.reminderHourDefaultsKey)
        defaults.set(minute, forKey: NotificationPolicy.reminderMinuteDefaultsKey)
        if remindersEnabled { schedule() }
    }

    public func disableReminders() {
        persist(false)
        center.econRemovePendingRequests(withIdentifiers: [NotificationPolicy.reminderIdentifier])
        center.econRemoveDeliveredNotifications(withIdentifiers: [NotificationPolicy.reminderIdentifier])
    }

    /// Foreground, timezone, and daylight-saving changes reconcile the next
    /// reminder without ever leaving a duplicate request behind.
    public func reconcileOnForeground() {
        refreshAuthorization()
        guard remindersEnabled else {
            center.econRemovePendingRequests(withIdentifiers: [NotificationPolicy.reminderIdentifier])
            return
        }
        schedule()
    }

    private func schedule() {
        center.econRemovePendingRequests(withIdentifiers: [NotificationPolicy.reminderIdentifier])
        center.econAdd(NotificationPolicy.makeReminderRequest(hour: reminderHour, minute: reminderMinute)) { error in
            Task { @MainActor in
                self.lastScheduleError = error
                if let error { self.onScheduleFailure?(error) }
            }
        }
    }

    private func persist(_ enabled: Bool) {
        remindersEnabled = enabled
        defaults.set(enabled, forKey: NotificationPolicy.enabledDefaultsKey)
    }

    // MARK: Primer bookkeeping

    public var primerAlreadyShown: Bool {
        defaults.bool(forKey: NotificationPolicy.primerShownDefaultsKey)
    }

    public func notePrimerShown() {
        defaults.set(true, forKey: NotificationPolicy.primerShownDefaultsKey)
    }

    #if DEBUG
    public static func resetPersistedState(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: NotificationPolicy.enabledDefaultsKey)
        defaults.removeObject(forKey: NotificationPolicy.primerShownDefaultsKey)
        defaults.removeObject(forKey: NotificationPolicy.reminderHourDefaultsKey)
        defaults.removeObject(forKey: NotificationPolicy.reminderMinuteDefaultsKey)
    }
    #endif
}
