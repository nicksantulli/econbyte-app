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

/// Every ad request is contextual. 1.1.2 build 13 restores the ATT prompt (App
/// Review 5.1.2(i); see `EconTrackingAuthorization.swift` for why), but the
/// *request* is unchanged: `npa=1` and `rdp=1` on every one of them, whatever
/// the reader answered. Personalizing for authorized readers is a portfolio
/// policy revision, not an EconByte edit — see
/// `EconTrackingStatus.providerWouldPermitPersonalizedAds`.
public struct EconAdRequestPolicy: Equatable {
    /// What the reader answered, carried so the request is a function of the
    /// decision rather than of when it happened to be built.
    public var trackingStatus: EconTrackingStatus = .notDetermined
    public var usesPersonalizedAds = false
    public var requestsAppTrackingAuthorization = true
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

    /// `npa` requests non-personalized delivery; `rdp` restricts data
    /// processing. Both are set on EVERY request, including an ATT-authorized
    /// one — the portfolio invariant is non-personalized everywhere, and it is
    /// gate-enforced outside this repo. Asserted for all four statuses in
    /// `TrackingAuthorizationTests`, so relaxing it here cannot pass unnoticed.
    public var extras: [String: String] { ["npa": "1", "rdp": "1"] }

    public init(trackingStatus: EconTrackingStatus = .notDetermined) {
        self.trackingStatus = trackingStatus
    }
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

    // Anchored adaptive banner (Home + card session), added 2026-09-14 (1.1.3).
    /// Google's public adaptive-banner test unit.
    public static let debugBanner = "ca-app-pub-3940256099942544/2435281174"
    /// The production banner unit, created in the AdMob console by the Owner on
    /// 2026-09-14 (MANAGER-LOOP-2026-09-14 log). An empty value would hide the
    /// slot entirely, so a build can never request a placeholder unit.
    public static let releaseBanner = "ca-app-pub-9950526548980224/4084037009"

    public static var banner: String? {
        #if DEBUG
        return debugBanner
        #else
        return releaseBanner.isEmpty ? nil : releaseBanner
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

/// Interstitial pacing, audited 2026-09-14 (1.1.3 growth lane).
///
/// EconByte paces by completed SETS, not by cards: the one interstitial
/// placement is the return from a completed set to Home, so no ad can ever
/// interrupt reading. Against that model the lane's per-card target (an ad no
/// earlier than the 4th card, about one per six cards, three per session) maps
/// as follows, and the two loosened values are the only ones that moved:
///
///   * `minimumCompletedSets` 2 — UNCHANGED. The first interstitial still
///     cannot appear before the second completed set (16 cards). The first
///     set's exit is where the reader meets the consent primer, the reminder
///     primer and (build 13) the ATT dialog; a fresh install's first exit is the
///     highest-retention-risk moment in the app and it stays ad-free.
///   * `setsSinceLastAd` 2 → 1. Every completed set after the second is now an
///     eligible exit rather than every other one. With 8-card sets this is one
///     interstitial per ~8 cards, still coarser than the per-card target, and
///     always at a natural break behind the completion screen.
///   * `perSession` 1 → 2. A reader who finishes two topic decks in one sitting
///     may see a second interstitial — but only if `minimumInterval` has also
///     elapsed, so in practice this bites only in sittings longer than 15 min.
///   * `minimumInterval` 15 min and `perDay` 2 — UNCHANGED. These two are the
///     retention guardrails; nothing here can exceed two interstitials in a
///     calendar day for anyone.
///
/// Why not go further: EconByte has no D1/D7 retention series yet (PostHog
/// ingestion started with 1.1.2, and ads-exposed vs entitled splits are Phase 7
/// of this loop), so there is no evidence to spend. The steady revenue surface
/// added in 1.1.3 is the anchored banner (`AdBannerSlot`), not more
/// interstitials. Re-audit when Phase 7's dashboards exist.
public struct EconAdThresholds: Equatable {
    public var minimumCompletedSets = 2
    public var setsSinceLastAd = 1
    public var minimumInterval: TimeInterval = 15 * 60
    public var perSession = 2
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
        /// Set the moment the ATT prompt is asked for, so "once per install"
        /// survives a relaunch even in the states where iOS leaves the status
        /// `.notDetermined` (it declines to present the prompt when the app is
        /// not active). Without it, a prompt that could not be shown would be
        /// re-attempted at every session exit forever.
        static let trackingPromptRequested = "econ.ads.trackingPromptRequested"
    }

    @Published public private(set) var entitlements = EconEntitlements()

    public private(set) var state = EconAdState()
    public var policy: EconAdPolicy
    /// Published so the anchored banner slot can appear the moment the SDK is
    /// allowed to start (after the ATT decision on a fresh install) without the
    /// hosting view having to be recomposed by something else.
    @Published public private(set) var didStartSDK = false

    /// Whether this install has ever asked iOS for the ATT prompt. Persisted.
    /// Evidence only since 1.1.3 build 16: it no longer gates the prompt or the
    /// ad request (an ask iOS never presented must not count as an answer).
    public private(set) var didRequestTrackingPrompt: Bool

    /// Held from app launch until the first-launch permission flow has run (or
    /// been skipped), so no ad SDK start — and therefore no banner or
    /// interstitial request — can land under Apple's ATT or notifications
    /// prompt, including for an upgrader whose ATT is already decided but whose
    /// notifications prompt is still owed (ported from the 1.1.4 line).
    public private(set) var isHeldForLaunchPermissions = false

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
    private let tracking: EconTrackingAuthorizing
    private var blockers: Set<EconAdBlocker> = []
    private var setCompletedNormally = false

    /// The request configuration as it stands right now. Rebuilt per call so it
    /// always carries the *current* tracking decision rather than the one that
    /// held when the coordinator was constructed.
    private var requestPolicy: EconAdRequestPolicy {
        EconAdRequestPolicy(trackingStatus: tracking.status)
    }

    public init(adapter: EconInterstitialAdapting,
                defaults: UserDefaults = .standard,
                calendar: Calendar = .current,
                now: @escaping () -> Date = Date.init,
                region: @escaping () -> EconAdRegionState = { EconAdRegion.current },
                tracking: EconTrackingAuthorizing = EconTrackingAuthorization.shared,
                thresholds: EconAdThresholds = EconAdThresholds()) {
        self.adapter = adapter
        self.defaults = defaults
        self.calendar = calendar
        self.now = now
        self.region = region
        self.tracking = tracking
        self.policy = EconAdPolicy(thresholds: thresholds)
        self.didRequestTrackingPrompt = defaults.bool(forKey: Key.trackingPromptRequested)

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

    /// Whether a request may reach the provider at all.
    ///
    /// This is the 5.1.2(i) gate, and it is deliberately upstream of every
    /// provider call — SDK start, preload, and re-preload alike. An app whose
    /// label says it tracks may not touch the ad network before the reader has
    /// answered ATT. Build 8 (live 1.1.1) preloaded at launch and prompted at
    /// the first interstitial, which is exactly the ordering the guideline is
    /// about.
    ///
    /// 1.1.3 build 16 (App Review 2.1, 2026-09-15): status-only. Builds 13–15
    /// also accepted "the prompt was asked", so an ask iOS never presented let
    /// the SDK start with no answer on file. iOS leaves `.notDetermined` after
    /// an ask only transiently (the app was not active, or a presentation was
    /// in flight — a device with tracking requests switched off reports
    /// `.denied`), and `FirstLaunchPermissionsCoordinator` asks again on the next
    /// activation, so ads wait for a real answer instead.
    public var adRequestsPermitted: Bool {
        tracking.status.isDecided
    }

    /// The request-side gate for the anchored banner (1.1.3): may this install
    /// ask for ANY ad right now? Entitlement, region (DUD-224) and the ATT
    /// ordering gate — the same three checks `startAdsIfPermitted` makes,
    /// exposed so a view can decide whether to construct a banner at all. An
    /// entitled reader, an EEA/UK reader, or a reader whose tracking decision
    /// is still outstanding never has a banner requested on their behalf.
    public var canRequestAds: Bool {
        !entitlements.adsSuppressed && region().permitsAdRequests && adRequestsPermitted
            && !isHeldForLaunchPermissions
    }

    /// See `isHeldForLaunchPermissions`. Released by
    /// `FirstLaunchPermissionsCoordinator` when the flow ends or is skipped.
    public func setLaunchPermissionsHold(_ held: Bool) {
        isHeldForLaunchPermissions = held
    }

    /// The live ATT status (through the injected seam).
    public var trackingStatus: EconTrackingStatus { tracking.status }

    /// The request configuration a banner must use: the same non-personalized
    /// extras, carrying the live tracking status.
    public var currentRequestPolicy: EconAdRequestPolicy { requestPolicy }

    /// Whether the ATT prompt is still owed: exactly while iOS has no answer.
    ///
    /// 1.1.3 build 16 (App Review 2.1): builds 13–15 also skipped Remove Ads
    /// owners, EEA/UK or unknown device regions, and any install that had asked
    /// once — even when iOS showed nothing. Each of those states is invisible to
    /// a reviewer, who then cannot find the prompt. The binary links an ad SDK
    /// whose privacy manifest declares tracking, so the prompt is owed to every
    /// install until answered. Ads are still never served in the EEA/UK or to
    /// Remove Ads owners (`canRequestAds`, `startAdsIfPermitted`).
    public var shouldRequestTrackingAuthorization: Bool {
        tracking.status == .notDetermined
    }

    /// Presents the ATT prompt if it is still owed, then (by default) lets the
    /// ad SDK start.
    ///
    /// Builds 13–15 called this from the session-complete exit. Build 16 calls
    /// it only from `FirstLaunchPermissionsCoordinator`, after the studio intro,
    /// with `startingAds: false`, because the notifications prompt follows and
    /// no ad may load under a system dialog. It marks `.systemPrompt` for the
    /// caller to clear.
    @discardableResult
    public func resolveTrackingAuthorizationIfNeeded(startingAds: Bool = true) async -> EconTrackingStatus {
        guard shouldRequestTrackingAuthorization else {
            if startingAds { startAdsIfPermitted() }
            return tracking.status
        }
        setBlocker(.systemPrompt, active: true)
        // A record of the ask, not a gate: an ask iOS did not present leaves
        // `.notDetermined`, and the coordinator asks again.
        didRequestTrackingPrompt = true
        defaults.set(true, forKey: Key.trackingPromptRequested)
        let resolved = await tracking.requestAuthorization()
        if startingAds { startAdsIfPermitted() }
        return resolved
    }

    /// Initializes the ad SDK at most once, and only when the entitlement, the
    /// region gate, and the tracking decision all permit an ad request.
    public func startAdsIfPermitted() {
        guard !didStartSDK else { return }
        guard !isHeldForLaunchPermissions else { return }
        guard !entitlements.adsSuppressed else { return }
        guard region().permitsAdRequests else { return }
        guard adRequestsPermitted else { return }
        didStartSDK = true
        let policy = requestPolicy
        adapter.startSDK(policy: policy)
        adapter.preload(policy: policy)
    }

    /// Every re-preload in this type goes through here, so the gate cannot be
    /// bypassed by a path that only wants "one more" request.
    private func preloadIfPermitted() {
        guard didStartSDK, adRequestsPermitted else { return }
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
            preloadIfPermitted()
            return .noAdAvailable
        }
        guard await adapter.present() else {
            preloadIfPermitted()
            return .presentationFailed
        }
        let moment = now()
        rollDayIfNeeded()
        state.shownThisSession += 1
        state.shownToday += 1
        state.lastShownAt = moment
        state.setsSinceLastAd = 0
        persist()
        preloadIfPermitted()
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
                    Key.dayKey, Key.shownToday, Key.trackingPromptRequested] {
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
    /// RECONCILED (1.1.2): the transport-backed telemetry facade from the 1.1.2
    /// instrumentation lineage. It is a shared singleton because the vendor SDK
    /// behind it is one per process; the growth systems below still hand it
    /// nothing but validated, allowlisted events through `EBEvents`.
    let telemetry: EconTelemetry
    /// Crash reporting (Sentry, crash-only, opt-in). Distinct from
    /// `diagnosticLog` below, which is this app's own bounded failure codes and
    /// never leaves the device.
    let diagnostics: EconDiagnostics
    let diagnosticLog: EconDiagnosticLog
    let monetization: EconMonetization
    let review: ReviewRequestCoordinator
    let notifications: NotificationCoordinator

    private var didStartFirstSession = false
    private let defaults: UserDefaults

    /// First-launch ATT + notifications prompts and their mapping (1.1.3 build 16).
    private(set) lazy var permissions = FirstLaunchPermissionsCoordinator(
        monetization: monetization,
        notifications: notifications,
        defaults: defaults,
        environment: LivePromptPresentationEnvironment.shared,
        applyAnalyticsConsent: { [weak self] granted in self?.applyFirstLaunchAnalyticsConsent(granted) },
        noteNegativeSessionEvent: { [weak self] event in self?.review.noteNegativeSessionEvent(event) },
        recordNotificationResult: { granted in EBEvents.notificationPermissionResult(granted: granted) })

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-econResetGrowthState") {
            EconGrowth.resetPersistedState(in: defaults)
        }
        #endif

        let environment = EconTelemetryEnvironment.current
        self.environment = environment
        self.telemetry = EconTelemetry.shared
        self.diagnostics = EconDiagnostics.shared
        self.diagnosticLog = EconDiagnosticLog(defaults: defaults, environment: environment)
        self.monetization = EconMonetization(adapter: AdManager.shared,
                                             defaults: defaults,
                                             region: EconGrowth.regionSource())
        self.review = ReviewRequestCoordinator(defaults: defaults,
                                               currentVersion: environment.appVersion,
                                               requestReview: { EconGrowth.requestSystemReview() })
        self.notifications = NotificationCoordinator(defaults: defaults)

        // No ad SDK start before the first-launch prompts have run.
        if !FirstLaunchPermissionPolicy.isSkipped(arguments: ProcessInfo.processInfo.arguments) {
            monetization.setLaunchPermissionsHold(true)
        }

        AdManager.shared.onFailure = { [weak self] code, error in
            self?.diagnosticLog.capture(code, detail: error.map(EconDiagnosticDetail.init))
        }
        PurchaseManager.shared.onDiagnostic = { [weak self] code in
            self?.diagnosticLog.capture(code)
        }

        monetization.onAdEligible = { _, setsSinceLastAd in
            EBEvents.adEligibilityReached(depth: setsSinceLastAd)
        }
        monetization.onAdDismissed = { _, resultClass in
            EBEvents.adDismissed(placement: .dailySetExit,
                                 outcome: resultClass == .success ? .completed : .failed)
        }
        review.onEligible = {
            EBEvents.reviewPromptEligible(streak: StreakManager.shared.currentStreak)
        }
        notifications.onScheduleFailure = { [weak self] error in
            self?.diagnosticLog.capture(.notificationScheduleFailed,
                                        detail: EconDiagnosticDetail(error))
        }
    }

    // MARK: Lifecycle

    func applicationDidBecomeActive() {
        let isColdLaunch = !didStartFirstSession
        didStartFirstSession = true

        monetization.noteForegroundSessionBegan()
        review.noteForegroundSessionBegan()
        notifications.reconcileOnForeground()
        monetization.startAdsIfPermitted()
        // Cold launches only: `app_opened_v1` carries the install-age and
        // launch-count buckets that `EBEvents.recordLaunch` maintains, and a
        // warm foreground is not a launch.
        if isColdLaunch { EBEvents.recordLaunch() }
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
        diagnosticLog.capture(.contentCatalogInvalid, detail: EconDiagnosticDetail(error))
    }

    // MARK: Consent

    func setAnalyticsEnabled(_ enabled: Bool, entryPoint: EconEntryPoint) {
        // Order matters on the way IN and on the way OUT. Turning analytics ON
        // starts the transport first, so the consent event itself is captured;
        // turning it OFF captures the event first, because `setAnalyticsConsent`
        // clears the queue and the vendor's local state on the same turn.
        if enabled {
            telemetry.setAnalyticsConsent(true)
            EBEvents.analyticsConsentChanged(enabled: true, entryPoint: entryPoint.ebEntryPoint)
        } else {
            EBEvents.analyticsConsentChanged(enabled: false, entryPoint: entryPoint.ebEntryPoint)
            telemetry.setAnalyticsConsent(false)
        }
    }

    /// ATT "Allow" ⇒ analytics + crash reports on; any other answer ⇒ off.
    /// Through the same facade paths the Settings switches use, so they read
    /// back the same answer.
    func applyFirstLaunchAnalyticsConsent(_ granted: Bool) {
        setAnalyticsEnabled(granted, entryPoint: .home)
        setDiagnosticsEnabled(granted, entryPoint: .home)
        if granted { EBEvents.flush() }
    }

    func setDiagnosticsEnabled(_ enabled: Bool, entryPoint: EconEntryPoint) {
        diagnostics.setDiagnosticsConsent(enabled)
        diagnosticLog.setEnabled(enabled)
        EBEvents.diagnosticsConsentChanged(enabled: enabled, entryPoint: entryPoint.ebEntryPoint)
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
        // A review prompt is a production side-effect, and a robot should not be
        // asked to rate the app — the same reason a test run may not reach the
        // live analytics projects. See `ReviewRequestPolicy`.
        guard ReviewRequestPolicy.mayShowSystemReviewSheet() else { return }
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        else { return }
        EBEvents.reviewRequestAttempted(launchCount: EBEvents.recordedLaunchCount())
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
        EBEvents.notificationPermissionResult(granted: granted)
    }

    /// The contextual consent primer became visible. Separate from the
    /// authorization result above: one is what the app showed, the other is
    /// what the system dialog returned.
    func recordNotificationPrimerViewed(entryPoint: EconEntryPoint) {
        EBEvents.notificationPrimerViewed(entryPoint: entryPoint.ebEntryPoint)
    }

    #if DEBUG
    static func resetPersistedState(in defaults: UserDefaults) {
        EconMonetization.resetPersistedState(in: defaults)
        defaults.removeObject(forKey: EconTelemetry.Key.consent)
        defaults.removeObject(forKey: EconDiagnostics.consentDefaultsKey)
        defaults.removeObject(forKey: ConsentPromptPolicy.shownDefaultsKey)
        FirstLaunchPermissionsCoordinator.resetPersistedState(in: defaults)
        EconDiagnosticLog.resetPersistedState(in: defaults)
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
