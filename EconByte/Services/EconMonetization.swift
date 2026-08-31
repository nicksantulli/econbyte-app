import Foundation
import StoreKit
import UIKit

// MARK: - Region policy (DUD-224)
//
// Owner decision (DUD-224, 2026-06-14): do NOT serve ads to EEA/UK users.
// Suppressing the ad request in those regions sidesteps GDPR consent entirely —
// no consent form, no Google UMP SDK call. Version 1.1 keeps that decision; see
// `CONTENT-DECISIONS.md` D1 for the divergence from the written design, which
// specified UMP. The check uses the device's *region setting* (privacy-friendly:
// no location permission, no IP lookup) and fails CLOSED — an undeterminable
// region is treated as restricted.

public enum EconAdRegionState: Equatable {
    case allowed
    case restricted
    case unknown

    public var permitsAdRequests: Bool { self == .allowed }
}

public enum EconAdRegion {
    /// EEA member states plus the United Kingdom.
    public static let restrictedRegionCodes: Set<String> = [
        // EU 27
        "AT", "BE", "BG", "HR", "CY", "CZ", "DK", "EE", "FI", "FR", "DE", "GR",
        "HU", "IE", "IT", "LV", "LT", "LU", "MT", "NL", "PL", "PT", "RO", "SK",
        "SI", "ES", "SE",
        // EEA (non-EU)
        "IS", "LI", "NO",
        // United Kingdom
        "GB",
    ]

    public static func state(for code: String?) -> EconAdRegionState {
        guard let code = code?.trimmingCharacters(in: .whitespacesAndNewlines),
              !code.isEmpty
        else { return .unknown }
        return restrictedRegionCodes.contains(code.uppercased()) ? .restricted : .allowed
    }

    public static var current: EconAdRegionState {
        if #available(iOS 16, *) {
            return state(for: Locale.current.region?.identifier)
        }
        return state(for: Locale.current.regionCode)
    }
}

// MARK: - Request configuration

/// Every 1.1 ad request is contextual. No ATT prompt, no IDFA, no advertising
/// profile — see `CONTENT-DECISIONS.md` D2 for what 1.0 actually did and why the
/// tracking pathway was removed.
public struct EconAdRequestPolicy: Equatable {
    public var usesPersonalizedAds = false
    public var requestsAppTrackingAuthorization = false
    public var maxAdContentRating = "G"

    /// Declared deny-list for a finance-education audience. AdMob enforces
    /// category blocks console-side; this list is the app's declaration of intent
    /// and the checklist the Owner verifies before submission (D6).
    public var blockedSensitiveCategories: [String] = [
        "financial-services",
        "gambling",
        "cryptocurrency",
        "loans",
        "politics",
        "alcohol",
        "dating",
        "get-rich-quick",
    ]

    /// `npa` requests non-personalized delivery; `rdp` restricts data processing.
    public var extras: [String: String] { ["npa": "1", "rdp": "1"] }

    public init() {}
}

public enum EconAdUnit {
    /// Google's public test interstitial unit.
    public static let debug = "ca-app-pub-3940256099942544/4411468910"
    /// The unit that shipped in 1.0. Reused exactly; Owner-unconfirmed (D6).
    public static let release = "ca-app-pub-9950526548980224/9740067293"

    public static var current: String {
        #if DEBUG
        return debug
        #else
        return release
        #endif
    }
}

// MARK: - Placement vocabulary

/// Version 1.1 has exactly one interstitial placement: the return from a
/// completed set to Home (design section 9.3).
public enum EconAdPlacement: String, CaseIterable, Equatable {
    case dailySetExit = "daily_set_exit"
}

/// Moments an ad may never interrupt.
public enum EconAdBlocker: String, CaseIterable, Equatable {
    case purchase, restore, consent, review, notification, paywall, error, systemPrompt
}

public enum EconAdDecision: Equatable {
    case eligible
    case suppressedEntitled
    case suppressedRegion(EconAdRegionState)
    case setNotCompletedNormally
    case belowLifetimeSetThreshold(Int)
    case belowSetsSinceLastAd(Int)
    case belowTimeThreshold(TimeInterval)
    case sessionCapReached
    case dailyCapReached
    case blocked(EconAdBlocker)
}

public enum EconAdOutcome: Equatable {
    case presented
    case presentationFailed
    case noAdAvailable
    case notEligible(EconAdDecision)
}

// MARK: - Entitlements

/// The two approved non-consumables are independent: buying one never implies
/// the other (design section 8, `CONTENT-DECISIONS.md` D4).
public struct EconEntitlements: Equatable {
    public var unlockAll: Bool
    public var removeAds: Bool

    public init(unlockAll: Bool = false, removeAds: Bool = false) {
        self.unlockAll = unlockAll
        self.removeAds = removeAds
    }

    public var paidTopicsUnlocked: Bool { unlockAll }
    public var adsSuppressed: Bool { removeAds }

    /// Verified StoreKit truth always wins, so a refund or revocation takes
    /// effect immediately rather than waiting for the cache to expire.
    public static func reconciled(cached: EconEntitlements,
                                  verified: EconEntitlements) -> EconEntitlements {
        verified
    }
}

// MARK: - Ad policy

public struct EconAdThresholds: Equatable {
    public var minimumCompletedSets = 2
    public var setsSinceLastAd = 2
    public var minimumInterval: TimeInterval = 15 * 60
    public var perSession = 1
    public var perDay = 2
    public init() {}
}

public struct EconAdState: Equatable {
    public var completedSetsLifetime = 0
    public var setsSinceLastAd = 0
    public var lastShownAt: Date?
    /// Process-scoped: never persisted, so the per-session cap resets on relaunch.
    public var shownThisSession = 0
    public var shownToday = 0
    public var dayKey = ""
    public init() {}

    public static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d",
                      parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

/// Pure, deterministic eligibility. Every rule in design section 9.3, in the
/// order the design states them, so a suppression reason is always the most
/// important one.
public struct EconAdPolicy {
    public var thresholds: EconAdThresholds

    public init(thresholds: EconAdThresholds = EconAdThresholds()) {
        self.thresholds = thresholds
    }

    public func decide(placement: EconAdPlacement,
                       state: EconAdState,
                       entitlements: EconEntitlements,
                       region: EconAdRegionState,
                       setCompletedNormally: Bool,
                       blockers: Set<EconAdBlocker>,
                       now: Date,
                       dayKey: String) -> EconAdDecision {
        if entitlements.adsSuppressed { return .suppressedEntitled }
        guard region.permitsAdRequests else { return .suppressedRegion(region) }
        for blocker in EconAdBlocker.allCases where blockers.contains(blocker) {
            return .blocked(blocker)
        }
        guard setCompletedNormally else { return .setNotCompletedNormally }
        guard state.completedSetsLifetime >= thresholds.minimumCompletedSets else {
            return .belowLifetimeSetThreshold(thresholds.minimumCompletedSets)
        }
        guard state.setsSinceLastAd >= thresholds.setsSinceLastAd else {
            return .belowSetsSinceLastAd(thresholds.setsSinceLastAd)
        }
        if let last = state.lastShownAt,
           now.timeIntervalSince(last) < thresholds.minimumInterval {
            return .belowTimeThreshold(thresholds.minimumInterval)
        }
        guard state.shownThisSession < thresholds.perSession else { return .sessionCapReached }
        if state.dayKey == dayKey, state.shownToday >= thresholds.perDay {
            return .dailyCapReached
        }
        return .eligible
    }
}

// MARK: - Adapter seam

@MainActor
public protocol EconInterstitialAdapting: AnyObject {
    var isAdLoaded: Bool { get }
    /// Raised when a presented interstitial goes away. The flag is false when the
    /// provider failed to present it rather than the reader dismissing it.
    var onAdDismissed: ((Bool) -> Void)? { get set }
    func startSDK(policy: EconAdRequestPolicy)
    func preload(policy: EconAdRequestPolicy)
    func discardLoadedAd()
    func present() async -> Bool
}

// MARK: - Coordinator

@MainActor
public final class EconMonetization: ObservableObject {

    public static let defaultsPrefix = "econ.ads."

    private enum Key {
        static let completedSets = "econ.ads.completedSetsLifetime"
        static let setsSinceLastAd = "econ.ads.setsSinceLastAd"
        static let lastShownAt = "econ.ads.lastShownAt"
        static let dayKey = "econ.ads.dayKey"
        static let shownToday = "econ.ads.shownToday"
    }

    @Published public private(set) var entitlements = EconEntitlements()

    public private(set) var state = EconAdState()
    public var policy: EconAdPolicy
    public private(set) var didStartSDK = false

    /// Raised once per exit when every local eligibility rule passes, before any
    /// provider call. Carries the set counter as it stood *before* the reset.
    public var onAdEligible: ((EconAdPlacement, Int) -> Void)?

    /// Raised when a presented interstitial closes, cleanly or otherwise.
    public var onAdDismissed: ((EconAdPlacement, EconResultClass) -> Void)?

    private let adapter: EconInterstitialAdapting
    private let defaults: UserDefaults
    private let calendar: Calendar
    private let now: () -> Date
    private let region: () -> EconAdRegionState
    private let requestPolicy = EconAdRequestPolicy()
    private var blockers: Set<EconAdBlocker> = []
    private var setCompletedNormally = false

    public init(adapter: EconInterstitialAdapting,
                defaults: UserDefaults = .standard,
                calendar: Calendar = .current,
                now: @escaping () -> Date = Date.init,
                region: @escaping () -> EconAdRegionState = { EconAdRegion.current },
                thresholds: EconAdThresholds = EconAdThresholds()) {
        self.adapter = adapter
        self.defaults = defaults
        self.calendar = calendar
        self.now = now
        self.region = region
        self.policy = EconAdPolicy(thresholds: thresholds)

        state.completedSetsLifetime = defaults.integer(forKey: Key.completedSets)
        state.setsSinceLastAd = defaults.integer(forKey: Key.setsSinceLastAd)
        state.lastShownAt = defaults.object(forKey: Key.lastShownAt) as? Date
        state.dayKey = defaults.string(forKey: Key.dayKey) ?? ""
        state.shownToday = defaults.integer(forKey: Key.shownToday)
        state.shownThisSession = 0
        rollDayIfNeeded()

        adapter.onAdDismissed = { [weak self] presentedCleanly in
            self?.onAdDismissed?(.dailySetExit, presentedCleanly ? .success : .provider)
        }
    }

    // MARK: Entitlements

    public func update(entitlements: EconEntitlements) {
        guard entitlements != self.entitlements else { return }
        self.entitlements = entitlements
        if entitlements.adsSuppressed {
            // Remove Ads owners get no loaded ad held in memory either.
            adapter.discardLoadedAd()
        }
    }

    // MARK: SDK lifecycle

    /// Initializes the ad SDK at most once, and only when both the entitlement
    /// and the region gate permit an ad request.
    public func startAdsIfPermitted() {
        guard !didStartSDK else { return }
        guard !entitlements.adsSuppressed else { return }
        guard region().permitsAdRequests else { return }
        didStartSDK = true
        adapter.startSDK(policy: requestPolicy)
        adapter.preload(policy: requestPolicy)
    }

    public func noteForegroundSessionBegan() {
        state.shownThisSession = 0
        rollDayIfNeeded()
    }

    // MARK: Session signals

    public func noteSetCompleted(normally: Bool) {
        setCompletedNormally = normally
        guard normally else { return }
        state.completedSetsLifetime += 1
        state.setsSinceLastAd += 1
        persist()
    }

    public func setBlocker(_ blocker: EconAdBlocker, active: Bool) {
        if active { blockers.insert(blocker) } else { blockers.remove(blocker) }
    }

    public var activeBlockers: Set<EconAdBlocker> { blockers }

    // MARK: Decision and presentation

    public func decisionAtSetExit() -> EconAdDecision {
        let moment = now()
        return policy.decide(placement: .dailySetExit,
                             state: state,
                             entitlements: entitlements,
                             region: region(),
                             setCompletedNormally: setCompletedNormally,
                             blockers: blockers,
                             now: moment,
                             dayKey: EconAdState.dayKey(for: moment, calendar: calendar))
    }

    /// Presents the one allowed interstitial if every rule passes. Failure and
    /// no-fill are silent, return straight to Home, and never consume a cap.
    public func presentIfEligibleAtSetExit() async -> EconAdOutcome {
        let decision = decisionAtSetExit()
        guard decision == .eligible else { return .notEligible(decision) }
        // Every local rule passed. Recorded before any provider call, so the
        // eligible -> impression -> dismissed funnel has a real denominator
        // (design section 15.2).
        onAdEligible?(.dailySetExit, state.setsSinceLastAd)
        guard adapter.isAdLoaded else {
            adapter.preload(policy: requestPolicy)
            return .noAdAvailable
        }
        guard await adapter.present() else {
            adapter.preload(policy: requestPolicy)
            return .presentationFailed
        }
        let moment = now()
        rollDayIfNeeded()
        state.shownThisSession += 1
        state.shownToday += 1
        state.lastShownAt = moment
        state.setsSinceLastAd = 0
        persist()
        adapter.preload(policy: requestPolicy)
        return .presented
    }

    // MARK: Persistence

    private func rollDayIfNeeded() {
        let key = EconAdState.dayKey(for: now(), calendar: calendar)
        guard state.dayKey != key else { return }
        state.dayKey = key
        state.shownToday = 0
        persist()
    }

    private func persist() {
        defaults.set(state.completedSetsLifetime, forKey: Key.completedSets)
        defaults.set(state.setsSinceLastAd, forKey: Key.setsSinceLastAd)
        defaults.set(state.shownToday, forKey: Key.shownToday)
        defaults.set(state.dayKey, forKey: Key.dayKey)
        if let last = state.lastShownAt {
            defaults.set(last, forKey: Key.lastShownAt)
        } else {
            defaults.removeObject(forKey: Key.lastShownAt)
        }
    }

    /// DEBUG-only reset used by the UI-test harness so every rendered-flow run
    /// starts from a fresh-install posture. Compiled out of Release.
    #if DEBUG
    public static func resetPersistedState(in defaults: UserDefaults = .standard) {
        for key in [Key.completedSets, Key.setsSinceLastAd, Key.lastShownAt,
                    Key.dayKey, Key.shownToday] {
            defaults.removeObject(forKey: key)
        }
    }
    #endif
}

// MARK: - Composition root

/// Wires the five growth systems together and owns the app-lifecycle signals
/// they need. Everything it holds is independently testable; this type only
/// connects them.
@MainActor
final class EconGrowth: ObservableObject {

    static let shared = EconGrowth()

    let environment: EconTelemetryEnvironment
    let telemetry: EconTelemetry
    let diagnostics: EconDiagnostics
    let monetization: EconMonetization
    let review: ReviewRequestCoordinator
    let notifications: NotificationCoordinator

    private var didStartFirstSession = false
    private let defaults: UserDefaults

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-econResetGrowthState") {
            EconGrowth.resetPersistedState(in: defaults)
        }
        #endif

        let environment = EconTelemetryEnvironment.current
        self.environment = environment
        self.telemetry = EconTelemetry(defaults: defaults, environment: environment)
        self.diagnostics = EconDiagnostics(defaults: defaults, environment: environment)
        self.monetization = EconMonetization(adapter: AdManager.shared,
                                             defaults: defaults,
                                             region: EconGrowth.regionSource())
        self.review = ReviewRequestCoordinator(defaults: defaults,
                                               currentVersion: environment.appVersion,
                                               requestReview: { EconGrowth.requestSystemReview() })
        self.notifications = NotificationCoordinator(defaults: defaults)

        AdManager.shared.onFailure = { [weak self] code, error in
            self?.diagnostics.capture(code, detail: error.map(EconDiagnosticDetail.init))
        }
        PurchaseManager.shared.onDiagnostic = { [weak self] code in
            self?.diagnostics.capture(code)
        }

        monetization.onAdEligible = { [weak self] placement, setsSinceLastAd in
            self?.telemetry.capture(.adEligible, properties: [
                "placement": .token(placement.rawValue),
                "sets_since_last_ad": .int(setsSinceLastAd),
            ])
        }
        monetization.onAdDismissed = { [weak self] placement, resultClass in
            self?.telemetry.capture(.adDismissed, properties: [
                "placement": .token(placement.rawValue),
                "result_class": .token(resultClass.rawValue),
            ])
        }
        review.onEligible = { [weak self] in
            guard let self else { return }
            self.telemetry.capture(.reviewPromptEligible, properties: [
                "completed_set_count": .int(self.review.state.completedSetCount),
                "streak_bucket": .token(
                    ReviewRequestPolicy.streakBucket(StreakManager.shared.currentStreak)),
            ])
        }
        notifications.onScheduleFailure = { [weak self] error in
            self?.diagnostics.capture(.notificationScheduleFailed,
                                      detail: EconDiagnosticDetail(error))
        }
    }

    // MARK: Lifecycle

    func applicationDidBecomeActive() {
        let launchType: EconLaunchType = didStartFirstSession ? .warm : .cold
        didStartFirstSession = true

        monetization.noteForegroundSessionBegan()
        review.noteForegroundSessionBegan()
        notifications.reconcileOnForeground()
        monetization.startAdsIfPermitted()
        telemetry.capture(.appOpened, properties: ["launch_type": .token(launchType.rawValue)])
    }

    /// Entitlement changes must reach ad behaviour and content access on the same
    /// turn, in either direction (purchase, restore, refund, revocation).
    func syncEntitlements(from store: PurchaseManager) {
        monetization.update(entitlements: EconEntitlements(
            unlockAll: store.isUnlockAllPurchased,
            removeAds: store.isRemoveAdsPurchased))
    }

    func reportContentLoadFailureIfNeeded(_ store: ContentStore) {
        guard let error = store.loadError else { return }
        diagnostics.capture(.contentCatalogInvalid, detail: EconDiagnosticDetail(error))
    }

    // MARK: Consent

    func setAnalyticsEnabled(_ enabled: Bool, entryPoint: EconEntryPoint) {
        telemetry.setEnabled(enabled, entryPoint: entryPoint)
    }

    func setDiagnosticsEnabled(_ enabled: Bool, entryPoint: EconEntryPoint) {
        diagnostics.setEnabled(enabled)
        telemetry.capture(.diagnosticsConsentChanged,
                          properties: ["enabled": .bool(enabled),
                                       "entry_point": .token(entryPoint.rawValue)])
    }

    // MARK: Review

    /// The region gate the monetization coordinator consults.
    ///
    /// DEBUG builds honour `-econDisableAds`, which reports the device as
    /// ad-restricted. That routes through the real DUD-224 suppression path — the
    /// ad SDK is never started and no request is ever made — so a UI test can
    /// assert non-ad behaviour at a genuinely ad-eligible moment without racing a
    /// live fill from Google's test unit. It is a launch argument, not a build
    /// setting, and does not exist in Release.
    private static func regionSource() -> () -> EconAdRegionState {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-econDisableAds") {
            return { .restricted }
        }
        #endif
        return { EconAdRegion.current }
    }

    private static func requestSystemReview() {
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        else { return }
        if #available(iOS 16, *) {
            SKStoreReviewController.requestReview(in: scene)
        }
    }

    var consentPromptShown: Bool {
        ConsentPromptPolicy.wasShown(in: defaults)
    }

    func noteConsentPromptShown() {
        ConsentPromptPolicy.noteShown(in: defaults)
    }

    /// Records the outcome of the *system* authorization dialog. Callers pass
    /// what the dialog actually returned, never the toggle's intent.
    func recordNotificationAuthorizationResult(granted: Bool) {
        telemetry.capture(.notificationPermissionResult, properties: [
            "result_class": .token(granted ? EconResultClass.success.rawValue
                                           : EconResultClass.cancelled.rawValue),
        ])
    }

    #if DEBUG
    static func resetPersistedState(in defaults: UserDefaults) {
        EconMonetization.resetPersistedState(in: defaults)
        EconTelemetry.resetPersistedState(in: defaults)
        EconDiagnostics.resetPersistedState(in: defaults)
        ReviewRequestCoordinator.resetPersistedState(in: defaults)
        NotificationCoordinator.resetPersistedState(in: defaults)
        defaults.removeObject(forKey: ContentStore.cardStatesDefaultsKey)
        for key in ["currentStreak", "lastStreakDate", "cardsTodayCount",
                    "cardsTodayDate", "seenOnboarding"] {
            defaults.removeObject(forKey: key)
        }
    }
    #endif
}
