import Foundation

// MARK: - Rating requests (review-rules-v2, Owner order 2026-09-14)
//
// Version 1.0 asked on the 5th, 20th, and 50th *launch* regardless of whether
// anything went well. Version 1.1 asked after 3 completed sets and 7 days.
// 1.1.3 ports Table Talk's `review-rules-v2`: the ask lands on the SECOND open.
// The first open is never asked; from the second launch on, the first completed
// card session of 5+ cards is the moment. At most once per app version, attempts
// at least 120 days apart, and at most 2 in any 365 days — all stricter than
// Apple's own three-per-year throttle, which stays the outer cap.
//
// Anything that makes the current foreground session a bad moment DEFERS the ask
// to a later healthy session and never consumes the version's one attempt: an
// interstitial, a purchase or restore (and their failures), the app's own consent
// card, a system prompt (notifications, App Tracking Transparency), an error
// alert, a paywall, a crash recovery.
//
// Two things this deliberately does NOT do (see `CONTENT-DECISIONS.md` D9):
//   * There is no sentiment pre-prompt. `requestReview` is called directly,
//     which is the only Apple-sanctioned shape and the only one that cannot be
//     used to filter for praise.
//   * Settings' "Rate EconByte" does not call the system API; it opens Apple's
//     public write-review URL (`reviewURL`), so a reader who goes looking for
//     the rating control always gets one, which the throttled sheet cannot promise.
//
// Apple may silently decline to show the sheet (it always does in TestFlight, and
// it does under its own annual caps). The app records an *attempt*, never a
// display, and never infers whether a review was written.

/// Anything that makes the current session a bad moment to ask for a rating.
public enum EconNegativeSessionEvent: String, CaseIterable, Equatable {
    case crash
    case purchase
    case purchaseFailure = "purchase_failure"
    case restore
    case restoreFailure = "restore_failure"
    case consentForm = "consent_form"
    case notificationPrompt = "notification_prompt"
    case trackingPrompt = "tracking_prompt"
    case paywall
    case ad
    case errorShown = "error_shown"
}

public enum ReviewRequestDecision: Equatable {
    case eligible
    /// Launches so far, counting the current one — below the second open.
    case belowLaunchCount(Int)
    /// The required lifetime count.
    case insufficientCompletedSets(Int)
    case sessionNotCompleted
    /// Cards in the session that just ended — fewer than the moment needs.
    case belowSessionCards(Int)
    case negativeSession(EconNegativeSessionEvent)
    case alreadyRequestedForVersion(String)
    /// Days since the previous attempt.
    case tooSoonSincePreviousAttempt(Int)
    /// Attempts in the trailing 365 days.
    case annualCapReached(Int)
}

public struct ReviewRequestState: Equatable {
    /// Cold launches so far, including the current one (`EBEvents.recordLaunch`).
    public var launchCount = 0
    public var completedSetCount = 0
    public var currentSessionCompletedSet = false
    /// Cards in the set the current session just completed.
    public var currentSessionCards = 0
    public var negativeSessionEvents: Set<EconNegativeSessionEvent> = []
    /// Every app version that has already spent its one attempt.
    public var attemptedVersions: [String] = []
    /// When each attempt was made (rolling two years).
    public var attemptDates: [Date] = []
    public init() {}
}

public struct ReviewRequestThresholds: Equatable {
    /// The second time the app is opened, counting the current launch.
    public var minimumLaunches = 2
    /// Including the set that just ended.
    public var minimumCompletedSets = 1
    /// The set that just ended must have been a real session, not a three-card
    /// saved-cards replay.
    public var minimumCardsInSession = 5
    public var minimumDaysBetweenAttempts = 120
    public var maximumAttemptsPerYear = 2
    public init() {}
}

public enum ReviewRequestPolicy {

    public static let appStoreID = "6780714383"

    /// Bumped whenever the thresholds change, so a measurement readout can tell
    /// one rule set from another without carrying the rules themselves.
    public static let ruleVersion = "review-rules-v2"

    public static let completedSetsDefaultsKey = "econ.progress.completedSetCount"
    /// 1.1's install date. No longer a gate (the second open is), still recorded
    /// so nothing that reads it breaks, and cleared by the DEBUG reset.
    public static let firstLaunchDefaultsKey = "econ.progress.firstLaunchDate"
    /// 1.1's single-slot ledger. Still READ, so an install that was asked on
    /// 1.1.2 is not asked again on 1.1.2; no longer written.
    public static let lastRequestedVersionDefaultsKey = "econ.review.lastRequestedVersion"
    public static let attemptedVersionsDefaultsKey = "econ.review.attemptedVersions"
    public static let attemptDatesDefaultsKey = "econ.review.attemptDates"
    /// Shared with `EBEvents.recordLaunch`, which increments it once per cold
    /// launch — the same counter `app_opened_v1` buckets, so the two agree.
    public static let launchCountDefaultsKey = "ebLaunchCount"

    /// Direct write-a-review URL. Version 1.0's Settings link pointed at the
    /// Dudley homepage, which is not a review destination.
    public static var reviewURL: URL {
        URL(string: "https://apps.apple.com/app/id\(appStoreID)?action=write-review")!
    }

    public static var thresholds: ReviewRequestThresholds { ReviewRequestThresholds() }

    /// May this *process* put the system review sheet on screen at all?
    ///
    /// RECONCILED (1.1.2): ported from lineage C's `bea7834`, which found the
    /// real cause of an intermittent UI failure — `SKStoreReviewController`
    /// covers Home about two seconds after launch, a UI suite relaunches the
    /// app once per test, so one test lands under the sheet and fails, and
    /// *which* test depends on how many times that simulator has ever opened
    /// the app. The guard is about the *process*, not the policy: `decide`
    /// stays a pure function of the reader's progress, so the eligibility tests
    /// keep running inside XCTest. A plain Debug run still sees the sheet.
    static func mayShowSystemReviewSheet(
        in context: InstrumentationContext = .current) -> Bool {
        !context.isUnitTestRun && !context.isAutomationRun
    }

    /// Coarse streak bucket. Telemetry never carries the raw streak length as a
    /// free value; this is the closed vocabulary both emission sites use.
    public static func streakBucket(_ streak: Int) -> String {
        switch streak {
        case ..<3: return "0-2"
        case 3..<8: return "3-7"
        case 8..<30: return "8-29"
        default: return "30-plus"
        }
    }

    /// Every rule, in order, so a suppression reason is always the most
    /// important one.
    public static func decide(state: ReviewRequestState,
                              currentVersion: String,
                              now: Date,
                              calendar: Calendar = .current,
                              thresholds: ReviewRequestThresholds = thresholds) -> ReviewRequestDecision {
        guard state.launchCount >= thresholds.minimumLaunches else {
            return .belowLaunchCount(state.launchCount)
        }
        guard state.completedSetCount >= thresholds.minimumCompletedSets else {
            return .insufficientCompletedSets(thresholds.minimumCompletedSets)
        }
        guard state.currentSessionCompletedSet else { return .sessionNotCompleted }
        guard state.currentSessionCards >= thresholds.minimumCardsInSession else {
            return .belowSessionCards(state.currentSessionCards)
        }
        for event in EconNegativeSessionEvent.allCases
        where state.negativeSessionEvents.contains(event) {
            return .negativeSession(event)
        }
        if state.attemptedVersions.contains(currentVersion) {
            return .alreadyRequestedForVersion(currentVersion)
        }
        if let latest = state.attemptDates.max() {
            let gap = days(from: latest, to: now, calendar: calendar)
            guard gap >= thresholds.minimumDaysBetweenAttempts else {
                return .tooSoonSincePreviousAttempt(gap)
            }
        }
        let recent = state.attemptDates.filter { days(from: $0, to: now, calendar: calendar) < 365 }.count
        guard recent < thresholds.maximumAttemptsPerYear else { return .annualCapReached(recent) }
        return .eligible
    }

    /// Elapsed whole days between two instants — up to a day more conservative
    /// than a calendar-day reading, never less. Erring toward asking later is
    /// the right direction.
    static func days(from start: Date, to end: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }
}

// MARK: - Coordinator

@MainActor
public final class ReviewRequestCoordinator: ObservableObject {

    public private(set) var lastDecision: ReviewRequestDecision?
    public private(set) var didCallSystemAPI = false

    /// Raised when the local rules pass, before the system API is called, so the
    /// eligible -> requested funnel is measurable separately.
    public var onEligible: (() -> Void)?

    private let defaults: UserDefaults
    private let currentVersion: String
    private let now: () -> Date
    private let calendar: Calendar
    private let requestReview: () -> Void

    // Foreground-session state (never persisted).
    private var currentSessionCompletedSet = false
    private var currentSessionCards = 0
    private var negativeSessionEvents: Set<EconNegativeSessionEvent> = []

    public init(defaults: UserDefaults = .standard,
                currentVersion: String = "",
                now: @escaping () -> Date = Date.init,
                calendar: Calendar = .current,
                requestReview: @escaping () -> Void = {}) {
        self.defaults = defaults
        self.currentVersion = currentVersion
        self.now = now
        self.calendar = calendar
        self.requestReview = requestReview
    }

    public var state: ReviewRequestState {
        var state = ReviewRequestState()
        state.launchCount = defaults.integer(forKey: ReviewRequestPolicy.launchCountDefaultsKey)
        state.completedSetCount = defaults.integer(forKey: ReviewRequestPolicy.completedSetsDefaultsKey)
        state.currentSessionCompletedSet = currentSessionCompletedSet
        state.currentSessionCards = currentSessionCards
        state.negativeSessionEvents = negativeSessionEvents
        var versions = defaults.stringArray(forKey: ReviewRequestPolicy.attemptedVersionsDefaultsKey) ?? []
        // The 1.1 / 1.1.2 single-slot ledger still counts as a spent attempt.
        if let legacy = defaults.string(forKey: ReviewRequestPolicy.lastRequestedVersionDefaultsKey),
           !versions.contains(legacy) {
            versions.append(legacy)
        }
        state.attemptedVersions = versions
        state.attemptDates = (defaults.array(forKey: ReviewRequestPolicy.attemptDatesDefaultsKey) as? [Double] ?? [])
            .map(Date.init(timeIntervalSince1970:))
        return state
    }

    public func noteFirstLaunchIfNeeded() {
        guard defaults.object(forKey: ReviewRequestPolicy.firstLaunchDefaultsKey) == nil else { return }
        defaults.set(now(), forKey: ReviewRequestPolicy.firstLaunchDefaultsKey)
    }

    /// One card set has been completed on the completion screen. `cardsViewed`
    /// is the size of the deck the reader actually finished: every completion
    /// counts toward the lifetime total, but only a session of
    /// `minimumCardsInSession` or more is a moment at which to ask.
    public func noteSetCompleted(cardsViewed: Int) {
        let count = defaults.integer(forKey: ReviewRequestPolicy.completedSetsDefaultsKey) + 1
        defaults.set(count, forKey: ReviewRequestPolicy.completedSetsDefaultsKey)
        currentSessionCompletedSet = true
        currentSessionCards = cardsViewed
    }

    public func noteNegativeSessionEvent(_ event: EconNegativeSessionEvent) {
        negativeSessionEvents.insert(event)
    }

    /// A new foreground session: suppressions from the previous one are lifted.
    public func noteForegroundSessionBegan() {
        currentSessionCompletedSet = false
        currentSessionCards = 0
        negativeSessionEvents.removeAll()
        noteFirstLaunchIfNeeded()
    }

    /// Records local eligibility before calling the system API. Apple, not the
    /// app, decides whether a prompt is actually shown — and the attempt is
    /// recorded either way, or a silently-declined request would retry forever.
    @discardableResult
    public func requestReviewIfEligible() -> ReviewRequestDecision {
        let decision = ReviewRequestPolicy.decide(state: state,
                                                  currentVersion: currentVersion,
                                                  now: now(),
                                                  calendar: calendar)
        lastDecision = decision
        guard decision == .eligible else { return decision }
        onEligible?()
        recordAttempt()
        didCallSystemAPI = true
        requestReview()
        return decision
    }

    // MARK: Attempt ledger

    private func recordAttempt() {
        let versions = (defaults.stringArray(forKey: ReviewRequestPolicy.attemptedVersionsDefaultsKey) ?? [])
            + [currentVersion]
        defaults.set(versions, forKey: ReviewRequestPolicy.attemptedVersionsDefaultsKey)
        // Keep only a rolling two years; the annual cap never looks further.
        let moment = now()
        let kept = (state.attemptDates + [moment])
            .filter { ReviewRequestPolicy.days(from: $0, to: moment, calendar: calendar) < 730 }
            .map(\.timeIntervalSince1970)
        defaults.set(kept, forKey: ReviewRequestPolicy.attemptDatesDefaultsKey)
    }

    #if DEBUG
    public static func resetPersistedState(in defaults: UserDefaults = .standard) {
        for key in [ReviewRequestPolicy.completedSetsDefaultsKey,
                    ReviewRequestPolicy.firstLaunchDefaultsKey,
                    ReviewRequestPolicy.lastRequestedVersionDefaultsKey,
                    ReviewRequestPolicy.attemptedVersionsDefaultsKey,
                    ReviewRequestPolicy.attemptDatesDefaultsKey,
                    ReviewRequestPolicy.launchCountDefaultsKey] {
            defaults.removeObject(forKey: key)
        }
    }
    #endif
}
