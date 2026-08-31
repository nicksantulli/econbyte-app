import Foundation
import UserNotifications

// MARK: - Notifications (design section 11.1)
//
// Default off. The system dialog appears only after an explicit opt-in from the
// Session Complete primer or Settings — version 1.0 prompted automatically one
// second after first Home appearance. The reminder carries no financial claim,
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
    public static let reminderHour = 19
    public static let reminderMinute = 0

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

    public static func makeReminderRequest() -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = reminderTitle
        content.body = reminderBody
        content.sound = .default

        var components = DateComponents()
        components.hour = reminderHour
        components.minute = reminderMinute
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
    public static func primerEligible(completedSetCount: Int,
                                      primerAlreadyShown: Bool,
                                      remindersEnabled: Bool,
                                      consentPromptVisible: Bool = false) -> Bool {
        completedSetCount >= 1 && !primerAlreadyShown && !remindersEnabled
            && !consentPromptVisible
    }
}

@MainActor
public final class NotificationCoordinator: ObservableObject {

    @Published public private(set) var remindersEnabled: Bool
    @Published public private(set) var authorization: EconNotificationAuthorization = .notDetermined
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
        refreshAuthorization()
    }

    public func refreshAuthorization() {
        center.econAuthorizationStatus { status in
            Task { @MainActor in self.authorization = status }
        }
    }

    /// The only path to the system dialog. A previously denied user is linked to
    /// system settings by the caller rather than prompted again.
    /// `completion` reports the *system dialog's* outcome, not the toggle's
    /// intent, so callers record `notification_permission_result` from what
    /// actually happened.
    public func enableReminders(completion: ((Bool) -> Void)? = nil) {
        guard !remindersEnabled else {
            completion?(true)
            return
        }
        guard authorization != .denied else {
            completion?(false)
            return
        }
        didRequestAuthorization = true
        center.econRequestAuthorization { granted, _ in
            Task { @MainActor in
                self.authorization = granted ? .authorized : .denied
                guard granted else {
                    self.persist(false)
                    completion?(false)
                    return
                }
                self.persist(true)
                self.schedule()
                completion?(true)
            }
        }
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
        center.econAdd(NotificationPolicy.makeReminderRequest()) { error in
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
    }
    #endif
}
