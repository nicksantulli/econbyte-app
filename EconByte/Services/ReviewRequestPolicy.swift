import Foundation

// MARK: - Rating requests (design section 11.2)
//
// Version 1.0 asked on the 5th, 20th, and 50th *launch* regardless of whether
// anything went well. Version 1.1 asks only after a genuinely good session, at
// most once per app version, and never after a sentiment pre-prompt (there is
// none). See `CONTENT-DECISIONS.md` D9.

/// Anything that makes the current session a bad moment to ask for a rating.
public enum EconNegativeSessionEvent: String, CaseIterable, Equatable {
    case crash
    case purchaseFailure = "purchase_failure"
    case restoreFailure = "restore_failure"
    case consentForm = "consent_form"
    case notificationPrompt = "notification_prompt"
    case paywall
    case ad
}

public enum ReviewRequestDecision: Equatable {
    case eligible
    case insufficientCompletedSets(Int)
    case insufficientDaysSinceFirstLaunch(Int)
    case sessionNotCompleted
    case negativeSession(EconNegativeSessionEvent)
    case alreadyRequestedForVersion(String)
}

public struct ReviewRequestState: Equatable {
    public var completedSetCount = 0
    public var firstLaunchDate: Date?
    public var lastRequestedVersion: String?
    public var currentSessionCompletedSet = false
    public var negativeSessionEvents: Set<EconNegativeSessionEvent> = []
    public init() {}
}

public struct ReviewRequestThresholds: Equatable {
    public var minimumCompletedSets = 3
    public var minimumDaysSinceFirstLaunch = 7
    public init() {}
}

public enum ReviewRequestPolicy {

    public static let appStoreID = "6780714383"

    public static let completedSetsDefaultsKey = "econ.progress.completedSetCount"
    public static let firstLaunchDefaultsKey = "econ.progress.firstLaunchDate"
    public static let lastRequestedVersionDefaultsKey = "econ.review.lastRequestedVersion"

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
    /// the app. C fixed it inside v1.0's launch-milestone `ReviewPrompt`, which
    /// version 1.1 had already deleted; the guard belongs here instead.
    ///
    /// It is deliberately about the *process*, not the policy: `decide` stays a
    /// pure function of the user's progress, so the eligibility tests keep
    /// running inside XCTest. Only the moment of actually showing Apple's sheet
    /// is suppressed. A plain Debug run still sees it — a developer in the
    /// Simulator needs to be able to check the thing works.
    /// Internal rather than `public` like its neighbours: `InstrumentationContext`
    /// is internal, and widening it merely to widen this would be the tail
    /// wagging the dog. Nothing outside the module consumes any of this.
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

    public static func decide(state: ReviewRequestState,
                              currentVersion: String,
                              now: Date,
                              calendar: Calendar = .current,
                              thresholds: ReviewRequestThresholds = thresholds) -> ReviewRequestDecision {
        if let last = state.lastRequestedVersion, last == currentVersion {
            return .alreadyRequestedForVersion(last)
        }
        guard state.completedSetCount >= thresholds.minimumCompletedSets else {
            return .insufficientCompletedSets(thresholds.minimumCompletedSets)
        }
        let days = daysSinceFirstLaunch(state.firstLaunchDate, now: now, calendar: calendar)
        guard days >= thresholds.minimumDaysSinceFirstLaunch else {
            return .insufficientDaysSinceFirstLaunch(thresholds.minimumDaysSinceFirstLaunch)
        }
        guard state.currentSessionCompletedSet else { return .sessionNotCompleted }
        for event in EconNegativeSessionEvent.allCases
        where state.negativeSessionEvents.contains(event) {
            return .negativeSession(event)
        }
        return .eligible
    }

    private static func daysSinceFirstLaunch(_ firstLaunch: Date?,
                                             now: Date,
                                             calendar: Calendar) -> Int {
        guard let firstLaunch else { return 0 }
        let from = calendar.startOfDay(for: firstLaunch)
        let to = calendar.startOfDay(for: now)
        return calendar.dateComponents([.day], from: from, to: to).day ?? 0
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

    private var currentSessionCompletedSet = false
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
        state.completedSetCount = defaults.integer(forKey: ReviewRequestPolicy.completedSetsDefaultsKey)
        state.firstLaunchDate = defaults.object(forKey: ReviewRequestPolicy.firstLaunchDefaultsKey) as? Date
        state.lastRequestedVersion = defaults.string(forKey: ReviewRequestPolicy.lastRequestedVersionDefaultsKey)
        state.currentSessionCompletedSet = currentSessionCompletedSet
        state.negativeSessionEvents = negativeSessionEvents
        return state
    }

    public func noteFirstLaunchIfNeeded() {
        guard defaults.object(forKey: ReviewRequestPolicy.firstLaunchDefaultsKey) == nil else { return }
        defaults.set(now(), forKey: ReviewRequestPolicy.firstLaunchDefaultsKey)
    }

    public func noteSetCompleted() {
        let count = defaults.integer(forKey: ReviewRequestPolicy.completedSetsDefaultsKey) + 1
        defaults.set(count, forKey: ReviewRequestPolicy.completedSetsDefaultsKey)
        currentSessionCompletedSet = true
    }

    public func noteNegativeSessionEvent(_ event: EconNegativeSessionEvent) {
        negativeSessionEvents.insert(event)
    }

    public func noteForegroundSessionBegan() {
        currentSessionCompletedSet = false
        negativeSessionEvents.removeAll()
        noteFirstLaunchIfNeeded()
    }

    /// Records local eligibility before calling the system API. Apple, not the
    /// app, decides whether a prompt is actually shown.
    @discardableResult
    public func requestReviewIfEligible() -> ReviewRequestDecision {
        let decision = ReviewRequestPolicy.decide(state: state,
                                                  currentVersion: currentVersion,
                                                  now: now(),
                                                  calendar: calendar)
        lastDecision = decision
        guard decision == .eligible else { return decision }
        onEligible?()
        defaults.set(currentVersion, forKey: ReviewRequestPolicy.lastRequestedVersionDefaultsKey)
        didCallSystemAPI = true
        requestReview()
        return decision
    }

    #if DEBUG
    public static func resetPersistedState(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: ReviewRequestPolicy.completedSetsDefaultsKey)
        defaults.removeObject(forKey: ReviewRequestPolicy.firstLaunchDefaultsKey)
        defaults.removeObject(forKey: ReviewRequestPolicy.lastRequestedVersionDefaultsKey)
    }
    #endif
}
