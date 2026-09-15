import Foundation
import StoreKit
import UIKit

// MARK: - Region policy (DUD-224, revised by the Owner 2026-09-15)
//
// Owner decision DUD-224 (2026-06-14): do NOT serve ads in the EEA/UK.
// Suppressing the request there sidesteps GDPR consent entirely — no consent
// form, no Google UMP SDK. See `CONTENT-DECISIONS.md` D1.
//
// Revised 2026-09-15 (Phase 25, Owner: "no ads in EEA/UK/CH, literally
// everywhere else gets ads"):
//   * The block list is the EEA — EU 27 + Iceland, Liechtenstein, Norway, and
//     the EU outermost regions that carry their own ISO 3166 codes
//     (Guadeloupe GP, Martinique MQ, French Guiana GF, Réunion RE, Mayotte YT,
//     Saint-Martin MF) — plus the United Kingdom (GB) and Switzerland (CH).
//     Table Talk carries the identical list (`AdRegion`).
//   * Jersey (JE), Guernsey (GG), the Isle of Man (IM) and Gibraltar (GI) are
//     NOT blocked. Each has its own GDPR-style data-protection law, but none is
//     on the Owner's list and none is covered by the UK or EEA codes above, so
//     they are served (non-personalized unless the reader allowed tracking).
//     Revisit if counsel advises otherwise.
//   * The region is read from the App Store storefront first (the country of
//     the reader's App Store account, which is what the store's own legal
//     posture follows) and only then from the device's region setting. No
//     location permission, no IP lookup.
//   * An UNKNOWN region no longer blocks ads. It is served, but every request
//     is forced non-personalized (`npa=1`, `rdp=1`), whatever the ATT answer.

public enum EconAdRegionState: Equatable {
    case allowed
    case restricted
    case unknown

    /// Only a region KNOWN to be on the block list stops ad requests.
    public var permitsAdRequests: Bool { self != .restricted }

    /// Personalized requests need a region known to be outside the block list.
    public var permitsPersonalizedAds: Bool { self == .allowed }
}

/// Where a resolved region came from (diagnostics and tests only).
public enum EconAdRegionSource: String, Equatable {
    case storefront
    case locale
    case none
}

public struct EconAdRegionResolution: Equatable {
    public var state: EconAdRegionState
    public var source: EconAdRegionSource
}

public enum EconAdRegion {
    /// ISO 3166-1 alpha-2 codes of the no-ads territories (38).
    public static let restrictedRegionCodes: Set<String> = [
        // EU 27
        "AT", "BE", "BG", "HR", "CY", "CZ", "DK", "EE", "FI", "FR", "DE", "GR",
        "HU", "IE", "IT", "LV", "LT", "LU", "MT", "NL", "PL", "PT", "RO", "SK",
        "SI", "ES", "SE",
        // EU outermost regions with their own ISO codes
        "GP", "MQ", "GF", "RE", "YT", "MF",
        // EEA (non-EU)
        "IS", "LI", "NO",
        // United Kingdom
        "GB",
        // Switzerland (added to EconByte 2026-09-15; Table Talk had it since 1.1)
        "CH",
    ]

    /// The same territories as ISO 3166-1 alpha-3, which is what the App Store
    /// storefront reports (`Storefront.countryCode`, e.g. "USA", "DEU").
    public static let restrictedStorefrontCodes: Set<String> = [
        "AUT", "BEL", "BGR", "HRV", "CYP", "CZE", "DNK", "EST", "FIN", "FRA", "DEU", "GRC",
        "HUN", "IRL", "ITA", "LVA", "LTU", "LUX", "MLT", "NLD", "POL", "PRT", "ROU", "SVK",
        "SVN", "ESP", "SWE",
        "GLP", "MTQ", "GUF", "REU", "MYT", "MAF",
        "ISL", "LIE", "NOR",
        "GBR",
        "CHE",
    ]

    /// Classifies one code. Two ASCII letters are read as alpha-2, three as
    /// alpha-3; anything else (empty, numeric UN M49 regions such as "419")
    /// is `.unknown`.
    public static func state(for code: String?) -> EconAdRegionState {
        guard let raw = code?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
              raw.allSatisfy({ $0.isASCII && $0.isLetter })
        else { return .unknown }
        switch raw.count {
        case 2: return restrictedRegionCodes.contains(raw) ? .restricted : .allowed
        case 3: return restrictedStorefrontCodes.contains(raw) ? .restricted : .allowed
        default: return .unknown
        }
    }

    /// Storefront first, then the device region setting, else unknown.
    public static func resolve(storefrontCountryCode: String?,
                               localeRegionCode: String?) -> EconAdRegionResolution {
        let storefront = state(for: storefrontCountryCode)
        if storefront != .unknown { return EconAdRegionResolution(state: storefront, source: .storefront) }
        let locale = state(for: localeRegionCode)
        if locale != .unknown { return EconAdRegionResolution(state: locale, source: .locale) }
        return EconAdRegionResolution(state: .unknown, source: .none)
    }

    public static var localeRegionCode: String? {
        Locale.current.region?.identifier
    }

    public static var current: EconAdRegionState {
        resolve(storefrontCountryCode: EconStorefrontRegion.shared.countryCode,
                localeRegionCode: localeRegionCode).state
    }
}

/// The App Store storefront's country, cached. `Storefront.current` is async, so
/// it is read once at launch and kept current from `Storefront.updates`; until
/// it has answered, the region falls back to the device setting.
public final class EconStorefrontRegion: @unchecked Sendable {
    public static let shared = EconStorefrontRegion()

    private let lock = NSLock()
    private var cached: String?
    private var observing = false

    public var countryCode: String? {
        lock.lock(); defer { lock.unlock() }
        return cached
    }

    func store(_ code: String?) {
        lock.lock(); defer { lock.unlock() }
        if let code, !code.isEmpty { cached = code }
    }

    /// Idempotent. Never blocks the caller.
    public func startObserving() {
        lock.lock()
        let already = observing
        observing = true
        lock.unlock()
        guard !already else { return }
        Task.detached(priority: .utility) { [weak self] in
            if let code = await Storefront.current?.countryCode { self?.store(code) }
            for await storefront in Storefront.updates { self?.store(storefront.countryCode) }
        }
    }
}

// MARK: - Personalization (Owner decision 2026-09-15)

/// The one place that decides whether an ad request may be personalized.
///
/// Apple's ATT prompt is the only opt-in (Owner: "use an iOS native pop up for
/// opt in"). A request is personalized only when the region is KNOWN to be
/// outside the block list AND the reader tapped Allow. Denied, restricted, not
/// determined, or an unknown region: non-personalized, `npa=1` + `rdp=1`.
/// The status is read live for every request, so turning Tracking on or off in
/// iOS Settings takes effect on the next request without a relaunch.
public struct EconAdPersonalization: Equatable {
    public let personalized: Bool

    public static func decide(region: EconAdRegionState,
                              tracking: EconTrackingStatus) -> EconAdPersonalization {
        EconAdPersonalization(personalized: region.permitsPersonalizedAds
                                && tracking.providerWouldPermitPersonalizedAds)
    }

    /// `npa` requests non-personalized delivery; `rdp` restricts data
    /// processing (US state privacy laws). Both, or neither.
    public var extras: [String: String] {
        personalized ? [:] : ["npa": "1", "rdp": "1"]
    }
}

// MARK: - Request configuration

public struct EconAdRequestPolicy: Equatable {
    /// What the reader answered, carried so the request is a function of the
    /// decision rather than of when it happened to be built.
    public var trackingStatus: EconTrackingStatus = .notDetermined
    /// The region the request is for. Defaults to `.unknown`, so a policy built
    /// without one can never be personalized.
    public var region: EconAdRegionState = .unknown
    public var requestsAppTrackingAuthorization = true
    /// EconByte is rated 4+ on the App Store (appInfo `appStoreAgeRating`
    /// FOUR_PLUS), so the ceiling stays "G" (`.general`).
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
        // Phase 11: the portfolio's `adsPolicy.providerCategoryBlocks`
        // (config/app-factory/monetization-policy.json) folded in, so the
        // app's declaration is a superset of the policy it ships under.
        "adult-sexual",
        "controlled-substances",
        "religion",
        "simulated-gambling",
        "violence",
    ]

    public var personalization: EconAdPersonalization {
        EconAdPersonalization.decide(region: region, tracking: trackingStatus)
    }

    public var usesPersonalizedAds: Bool { personalization.personalized }

    /// Registered on every request: `npa=1` + `rdp=1` unless personalized.
    public var extras: [String: String] { personalization.extras }

    public init(trackingStatus: EconTrackingStatus = .notDetermined,
                region: EconAdRegionState = .unknown) {
        self.trackingStatus = trackingStatus
        self.region = region
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

/// Every surface in the 1.1.4 shell and whether an ad may appear on it
/// (Phase 11 placement matrix; reasoning per row in
/// `docs/audit/2026-09-14-ads-iap-audit.md` §2). Views ask this type — a
/// surface that is not listed as a banner surface cannot construct a banner.
///
/// Banners: list/feed surfaces a reader browses (Home, Browse at rest) and the
/// strip under a card session. Never on the portfolio's sensitive surfaces for
/// EconByte — article body (the Daily Brief), search, saved reading
/// (bookmarks), quiz explanation (lessons/quizzes), purchase/restore (paywalls),
/// privacy/consent/permission (Settings, first launch).
/// Interstitial: only the set exit, after the completion screen.
enum EconAdSurface: String, CaseIterable {
    case home
    case browse
    case search
    case newsBrief
    case newsArchive
    case proTab
    case courseLesson
    case quiz
    case cardMode
    case bookmarks
    case bookmarksReview
    case setComplete
    case paywall
    case settings
    case firstLaunch

    /// The banner slot this surface may carry, or nil for no banner.
    var bannerPlacement: EBAdPlacement? {
        switch self {
        case .home: return .bannerHome
        case .browse: return .bannerBrowse
        case .cardMode: return .bannerCard
        case .search, .newsBrief, .newsArchive, .proTab, .courseLesson, .quiz,
             .bookmarks, .bookmarksReview, .setComplete, .paywall, .settings, .firstLaunch:
            return nil
        }
    }

    /// Only the set exit (the dismissal of the completion screen) may show the
    /// interstitial.
    var allowsInterstitial: Bool { self == .setComplete }
}

/// Moments an ad may never interrupt.
public enum EconAdBlocker: String, CaseIterable, Equatable {
    case purchase, restore, consent, review, notification, paywall, error, systemPrompt
}

public enum EconAdDecision: Equatable {
    case eligible
    /// Phase 25: an exit was eligible, but no stable screen to present from
    /// appeared in time after the card session closed (or the armed break went
    /// stale). Nothing is shown and no cap is consumed.
    case presenterUnavailable
    case suppressedEntitled
    case suppressedRegion(EconAdRegionState)
    case setNotCompletedNormally
    case belowLifetimeSetThreshold(Int)
    /// Phase 11: the install's first foreground session carries no
    /// interstitial (portfolio cap `initialSessionInterstitials: 0`).
    case initialSession
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
/// the other (design section 8, `CONTENT-DECISIONS.md` D4). EconByte Pro (1.1.4,
/// D19) is the one product that spans both: while it is active the core topics
/// are readable and no ad is requested, without touching either one-time flag.
public struct EconEntitlements: Equatable {
    public var unlockAll: Bool
    public var removeAds: Bool
    /// An active EconByte Pro subscription (verified, unrevoked, unexpired).
    public var pro: Bool

    public init(unlockAll: Bool = false, removeAds: Bool = false, pro: Bool = false) {
        self.unlockAll = unlockAll
        self.removeAds = removeAds
        self.pro = pro
    }

    public var paidTopicsUnlocked: Bool { unlockAll || pro }
    public var adsSuppressed: Bool { removeAds || pro }

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
///
/// Phase 11 (2026-09-14) re-audit against the portfolio cap policy
/// (`config/app-factory/monetization-policy.json` `adsPolicy.capPolicy`, which
/// EconByte declares no override for and `release_evidence_gate.mjs` bounds):
///
///   * `initialSessionInterstitials` 0 — NEW. The install's first foreground
///     session never carries an interstitial, even if the reader finishes two
///     sets in it. Before this a fresh install could meet an interstitial at
///     its second set exit in its first sitting (portfolio: 0).
///   * `perSession` 2 → 1. The portfolio base cap is one per foreground
///     session; the 1.1.3 loosening exceeded it. It only ever bound in a
///     sitting longer than 15 minutes with three or more completed sets.
///   * `perDay` 2 is now ALSO a rolling 24-hour cap (`rollingWindow`), so
///     23:50 + 00:10 can no longer make four in under an hour across midnight
///     (portfolio: `maximumInterstitialsPer24Hours` 2).
///   * `minimumInterval` 15 min (portfolio: 1 per 10 min) and
///     `minimumCompletedSets` 2 unchanged.
///
/// Retention guardrail (Phase 7 dashboards): if D1 retention of ad-eligible
/// installs drops more than 15% relative to entitled installs after 1.1.4,
/// set `minimumCompletedSets` to 3 and `setsSinceLastAd` to 2 (the spec83
/// pacing) before touching the banner.
public struct EconAdThresholds: Equatable {
    public var minimumCompletedSets = 2
    public var initialSessionInterstitials = 0
    public var setsSinceLastAd = 1
    public var minimumInterval: TimeInterval = 15 * 60
    public var perSession = 1
    public var perDay = 2
    public var rollingWindow: TimeInterval = 24 * 60 * 60
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
    /// Foreground sessions this install has begun, counting the current one.
    public var foregroundSessionsLifetime = 0
    /// When the most recent interstitials were shown, for the rolling cap.
    public var recentShownAt: [Date] = []
    public init() {}

    public func shownWithin(_ window: TimeInterval, of now: Date) -> Int {
        recentShownAt.filter { now.timeIntervalSince($0) < window }.count
    }

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
        if state.foregroundSessionsLifetime <= 1,
           state.shownThisSession >= thresholds.initialSessionInterstitials {
            return .initialSession
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
        if state.shownWithin(thresholds.rollingWindow, of: now) >= thresholds.perDay {
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

// MARK: - Presentation hand-off (Phase 25)

/// Whether an interstitial can be presented right now without being torn down:
/// the scene is active, nothing is presented over the window's root, and no
/// presentation transition is running.
///
/// 1.1.2–1.1.5 presented the set-exit interstitial from inside the card-mode
/// full-screen cover and then dismissed that cover on the same turn, which tore
/// the ad down as it appeared. The break is now ARMED on the completion screen
/// and PRESENTED by the shell once this environment reports the cover is gone.
@MainActor
public protocol EconAdPresentationEnvironment: AnyObject {
    var isReadyToPresentInterstitial: Bool { get }
}

/// For callers already on a stable presenter.
@MainActor
public final class EconImmediatePresentationEnvironment: EconAdPresentationEnvironment {
    public init() {}
    public var isReadyToPresentInterstitial: Bool { true }
}

/// A set exit that passed every rule and is waiting for a stable presenter.
public struct EconPendingSetExitBreak: Equatable {
    public let armedAt: Date
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
        static let foregroundSessions = "econ.ads.foregroundSessionsLifetime"
        static let recentShownAt = "econ.ads.recentShownAt"
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

    /// Whether this install has already been shown (or been offered) the ATT
    /// prompt. Persisted, because "once per install" outlives the process.
    public private(set) var didRequestTrackingPrompt: Bool

    /// Phase 11: held from app launch until the first-launch permission flow
    /// has run (or been skipped), so no ad SDK start — and therefore no banner
    /// or interstitial request — can land under Apple's ATT or notifications
    /// prompt, including for an upgrader whose ATT is already decided but whose
    /// notifications prompt is still owed.
    public private(set) var isHeldForLaunchPermissions = false

    /// Raised once per exit when every local eligibility rule passes, before any
    /// provider call. Carries the set counter as it stood *before* the reset.
    public var onAdEligible: ((EconAdPlacement, Int) -> Void)?

    /// Raised when a presented interstitial closes, cleanly or otherwise.
    public var onAdDismissed: ((EconAdPlacement, EconResultClass) -> Void)?

    /// Phase 25: the set exit armed on the completion screen, presented by the
    /// shell once the card cover has gone (`presentPendingSetExitBreak`).
    public private(set) var pendingSetExitBreak: EconPendingSetExitBreak?

    /// An armed break older than this is dropped rather than shown late on an
    /// unrelated screen.
    public nonisolated static let pendingBreakLifetime: TimeInterval = 15
    /// How long the shell waits for the cover's dismissal to finish.
    public nonisolated static let presenterReadyTimeout: TimeInterval = 5
    /// Once the presenter is stable, let Home's layout settle before the ad.
    public nonisolated static let presenterSettleDelay: TimeInterval = 0.35
    nonisolated static let presenterPollInterval: TimeInterval = 0.05

    /// The live ATT status as last observed, re-read on every foreground
    /// (`refreshRequestPolicyForForeground`). Published so a banner slot
    /// rebuilds its request when the reader changes Tracking in iOS Settings.
    @Published public private(set) var observedTrackingStatus: EconTrackingStatus

    /// The policy the most recent SDK start or preload carried.
    public private(set) var lastRequestedPolicy: EconAdRequestPolicy?

    #if DEBUG
    /// DEBUG-only probe for the set-exit UI test: idle → armed → presented →
    /// dismissed (or a failure word). Never compiled into Release.
    @Published public private(set) var debugSetExitAdState = "idle"
    #endif

    private let presentationSleep: @MainActor (TimeInterval) async -> Void

    private static func realSleep(_ seconds: TimeInterval) async {
        try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
    }

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
        EconAdRequestPolicy(trackingStatus: tracking.status, region: region())
    }

    public init(adapter: EconInterstitialAdapting,
                defaults: UserDefaults = .standard,
                calendar: Calendar = .current,
                now: @escaping () -> Date = Date.init,
                region: @escaping () -> EconAdRegionState = { EconAdRegion.current },
                tracking: EconTrackingAuthorizing = EconTrackingAuthorization.shared,
                thresholds: EconAdThresholds = EconAdThresholds(),
                presentationSleep: (@MainActor (TimeInterval) async -> Void)? = nil) {
        self.adapter = adapter
        self.defaults = defaults
        self.calendar = calendar
        self.now = now
        self.region = region
        self.tracking = tracking
        self.policy = EconAdPolicy(thresholds: thresholds)
        self.presentationSleep = presentationSleep ?? { await EconMonetization.realSleep($0) }
        self.observedTrackingStatus = tracking.status
        self.didRequestTrackingPrompt = defaults.bool(forKey: Key.trackingPromptRequested)

        state.completedSetsLifetime = defaults.integer(forKey: Key.completedSets)
        state.setsSinceLastAd = defaults.integer(forKey: Key.setsSinceLastAd)
        state.lastShownAt = defaults.object(forKey: Key.lastShownAt) as? Date
        state.dayKey = defaults.string(forKey: Key.dayKey) ?? ""
        state.shownToday = defaults.integer(forKey: Key.shownToday)
        state.recentShownAt = (defaults.array(forKey: Key.recentShownAt) as? [Date]) ?? []
        if defaults.object(forKey: Key.foregroundSessions) != nil {
            state.foregroundSessionsLifetime = defaults.integer(forKey: Key.foregroundSessions)
        } else if state.completedSetsLifetime > 0 {
            // An upgrader from 1.1.3 or earlier has certainly had a session.
            state.foregroundSessionsLifetime = 1
        }
        state.shownThisSession = 0
        rollDayIfNeeded()

        adapter.onAdDismissed = { [weak self] presentedCleanly in
            guard let self else { return }
            #if DEBUG
            self.debugSetExitAdState = presentedCleanly ? "dismissed" : "failed-to-present"
            #endif
            self.onAdDismissed?(.dailySetExit, presentedCleanly ? .success : .provider)
            // Re-preload with the request policy as it stands NOW (the ATT
            // answer can have changed since the last load). The adapter's own
            // follow-up preload is then a no-op while this one is loading.
            self.preloadIfPermitted()
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
    /// Phase 14 hardening (1.1.3 App Review 2.1 rejection, 2026-09-15):
    /// status-only. Builds 13–15 also accepted "the prompt was asked", so an ask
    /// iOS never presented let the SDK start with no answer on file. iOS leaves
    /// `.notDetermined` after an ask only transiently (the app was not active, or
    /// a presentation was in flight — a device with tracking requests switched
    /// off reports `.denied`), and `FirstLaunchPermissionsCoordinator` asks again
    /// on the next activation, so ads wait for a real answer instead.
    public var adRequestsPermitted: Bool {
        #if DEBUG
        if debugTrackingAnswered { return true }
        #endif
        return tracking.status.isDecided
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

    #if DEBUG
    /// DEBUG-only (`-econTrackingAnswered`): lets a UI test that skips the
    /// system prompts still reach a real (test-unit) banner, so banner layout
    /// can be asserted. In-memory only; never persisted.
    private var debugTrackingAnswered = false
    public func debugMarkTrackingPromptRequested() {
        didRequestTrackingPrompt = true
        debugTrackingAnswered = true
    }
    #endif

    /// The live ATT status (through the injected seam).
    public var trackingStatus: EconTrackingStatus { tracking.status }

    /// The request configuration a banner must use: the same non-personalized
    /// extras, carrying the live tracking status.
    public var currentRequestPolicy: EconAdRequestPolicy { requestPolicy }

    /// Whether the ATT prompt is still owed: exactly while iOS has no answer.
    ///
    /// Phase 14 hardening (1.1.3 App Review 2.1 rejection): this used to skip
    /// Remove Ads owners, Pro subscribers, EEA/UK or unknown device regions, and
    /// any install that had asked once — even when iOS showed nothing. Each of
    /// those states is invisible to a reviewer, who then cannot find the prompt.
    /// The binary links an ad SDK whose privacy manifest declares tracking, so
    /// the prompt is owed to every install until answered. Ads are still never
    /// served in the EEA/UK or to Remove Ads / Pro readers (`canRequestAds`,
    /// `startAdsIfPermitted`).
    public var shouldRequestTrackingAuthorization: Bool {
        tracking.status == .notDetermined
    }

    /// Presents the ATT prompt if it is still owed, then (by default) lets the
    /// ad SDK start.
    ///
    /// 1.1.2–1.1.3 called this from the session-complete exit. 1.1.4 calls it
    /// from `FirstLaunchPermissionsCoordinator` after the studio intro, with
    /// `startingAds: false`, because the notifications prompt follows and no ad
    /// may load under a system dialog; the coordinator starts ads when both
    /// prompts have resolved. It marks `.systemPrompt` for the caller to clear.
    @discardableResult
    public func resolveTrackingAuthorizationIfNeeded(startingAds: Bool = true) async -> EconTrackingStatus {
        guard shouldRequestTrackingAuthorization else {
            if startingAds { startAdsIfPermitted() }
            return tracking.status
        }
        setBlocker(.systemPrompt, active: true)
        // A record of the ask, not a gate (Phase 14): an ask iOS did not
        // present leaves `.notDetermined`, and the coordinator asks again.
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
        lastRequestedPolicy = policy
        adapter.startSDK(policy: policy)
        adapter.preload(policy: policy)
    }

    /// Every re-preload in this type goes through here, so the gate cannot be
    /// bypassed by a path that only wants "one more" request.
    private func preloadIfPermitted() {
        guard didStartSDK, adRequestsPermitted else { return }
        let policy = requestPolicy
        lastRequestedPolicy = policy
        adapter.preload(policy: policy)
    }

    /// Re-reads the ATT status on every foreground. If the reader changed
    /// Tracking in iOS Settings so that requests flip between personalized and
    /// non-personalized, a held interstitial requested under the old answer is
    /// discarded and the next request carries the new one — no relaunch.
    public func refreshRequestPolicyForForeground() {
        let live = tracking.status
        if observedTrackingStatus != live { observedTrackingStatus = live }
        guard didStartSDK, let last = lastRequestedPolicy else { return }
        guard last.usesPersonalizedAds != requestPolicy.usesPersonalizedAds else { return }
        adapter.discardLoadedAd()
        preloadIfPermitted()
    }

    public func noteForegroundSessionBegan() {
        // A break armed before the app left the foreground is never shown.
        pendingSetExitBreak = nil
        state.shownThisSession = 0
        state.foregroundSessionsLifetime += 1
        rollDayIfNeeded()
        persist()
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

    /// Step 1 of the set-exit hand-off, called on the completion screen BEFORE
    /// it is dismissed: decides with that screen's blockers (review request,
    /// consent offer, notification prompt) still active, and arms the break
    /// only if every rule passes. Nothing is presented here — the card cover is
    /// about to go away, and an ad presented on it would go with it.
    @discardableResult
    public func armSetExitBreak() -> EconAdDecision {
        pendingSetExitBreak = nil
        let decision = decisionAtSetExit()
        guard decision == .eligible else {
            #if DEBUG
            debugSetExitAdState = "not-eligible"
            #endif
            return decision
        }
        // Every local rule passed. Recorded before any provider call, so the
        // eligible -> impression -> dismissed funnel has a real denominator
        // (design section 15.2).
        onAdEligible?(.dailySetExit, state.setsSinceLastAd)
        pendingSetExitBreak = EconPendingSetExitBreak(armedAt: now())
        // The dismissal gives a missing ad a moment to arrive.
        if !adapter.isAdLoaded { preloadIfPermitted() }
        #if DEBUG
        debugSetExitAdState = "armed"
        #endif
        return decision
    }

    /// Step 2, called by the shell once the card cover has closed: waits
    /// (bounded) until nothing is presented over the root and no transition is
    /// running, lets the screen settle, re-checks the rules (a purchase or a
    /// paywall may have arrived in between), then presents. Returns nil when no
    /// break was armed. Failure and no-fill are silent and never consume a cap.
    public func presentPendingSetExitBreak(
        environment: EconAdPresentationEnvironment,
        settleDelay: TimeInterval = EconMonetization.presenterSettleDelay
    ) async -> EconAdOutcome? {
        guard let pending = pendingSetExitBreak else { return nil }
        pendingSetExitBreak = nil

        var waited: TimeInterval = 0
        var settled = false
        while true {
            if environment.isReadyToPresentInterstitial {
                if settled || settleDelay <= 0 { break }
                await presentationSleep(settleDelay)
                waited += settleDelay
                settled = true
                continue
            }
            settled = false
            guard waited < Self.presenterReadyTimeout else {
                return finishWithoutPresenting(.notEligible(.presenterUnavailable))
            }
            await presentationSleep(Self.presenterPollInterval)
            waited += Self.presenterPollInterval
        }

        guard now().timeIntervalSince(pending.armedAt) <= Self.pendingBreakLifetime + waited else {
            return finishWithoutPresenting(.notEligible(.presenterUnavailable))
        }
        let decision = decisionAtSetExit()
        guard decision == .eligible else { return finishWithoutPresenting(.notEligible(decision)) }
        return await presentLoadedInterstitial()
    }

    /// Arms and presents in one call, for a caller that is already on a stable
    /// presenter (the unit tests of the pacing rules). The app itself always
    /// goes through `armSetExitBreak` + `presentPendingSetExitBreak`.
    public func presentIfEligibleAtSetExit() async -> EconAdOutcome {
        let decision = armSetExitBreak()
        guard decision == .eligible else { return .notEligible(decision) }
        return await presentPendingSetExitBreak(environment: EconImmediatePresentationEnvironment(),
                                                settleDelay: 0) ?? .notEligible(.presenterUnavailable)
    }

    private func finishWithoutPresenting(_ outcome: EconAdOutcome) -> EconAdOutcome {
        #if DEBUG
        debugSetExitAdState = "not-presented"
        #endif
        return outcome
    }

    private func presentLoadedInterstitial() async -> EconAdOutcome {
        guard adapter.isAdLoaded else {
            preloadIfPermitted()
            #if DEBUG
            debugSetExitAdState = "no-ad"
            #endif
            return .noAdAvailable
        }
        guard await adapter.present() else {
            preloadIfPermitted()
            #if DEBUG
            debugSetExitAdState = "present-failed"
            #endif
            return .presentationFailed
        }
        #if DEBUG
        debugSetExitAdState = "presented"
        #endif
        let moment = now()
        rollDayIfNeeded()
        state.shownThisSession += 1
        state.shownToday += 1
        state.lastShownAt = moment
        state.recentShownAt = (state.recentShownAt + [moment])
            .filter { moment.timeIntervalSince($0) < policy.thresholds.rollingWindow }
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
        defaults.set(state.foregroundSessionsLifetime, forKey: Key.foregroundSessions)
        defaults.set(state.recentShownAt, forKey: Key.recentShownAt)
        if let last = state.lastShownAt {
            defaults.set(last, forKey: Key.lastShownAt)
        } else {
            defaults.removeObject(forKey: Key.lastShownAt)
        }
    }

    #if DEBUG
    /// DEBUG-only (`-econSeedAdEligibleInstall`): an install that has finished
    /// two sets in an earlier foreground session and never seen an ad, so one
    /// more completed set is an eligible set exit. Used by the set-exit
    /// interstitial UI test; compiled out of Release.
    public static func debugSeedAdEligibleInstall(in defaults: UserDefaults = .standard) {
        defaults.set(2, forKey: Key.completedSets)
        defaults.set(1, forKey: Key.setsSinceLastAd)
        defaults.set(1, forKey: Key.foregroundSessions)
    }
    #endif

    /// DEBUG-only reset used by the UI-test harness so every rendered-flow run
    /// starts from a fresh-install posture. Compiled out of Release.
    #if DEBUG
    public static func resetPersistedState(in defaults: UserDefaults = .standard) {
        for key in [Key.completedSets, Key.setsSinceLastAd, Key.lastShownAt,
                    Key.dayKey, Key.shownToday, Key.trackingPromptRequested,
                    Key.foregroundSessions, Key.recentShownAt] {
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
    private let defaultsForPermissions: UserDefaults

    /// First-launch ATT + notifications prompts and their mapping (1.1.4).
    private(set) lazy var permissions = FirstLaunchPermissionsCoordinator(
        monetization: monetization,
        notifications: notifications,
        defaults: defaultsForPermissions,
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
        if ProcessInfo.processInfo.arguments.contains("-econSeedAdEligibleInstall") {
            EconMonetization.debugSeedAdEligibleInstall(in: defaults)
            // The consent offer raises a blocker at the exit it appears on.
            ConsentPromptPolicy.noteShown(in: defaults)
        }
        #endif

        // Phase 25: the ad region is read from the App Store storefront first.
        EconStorefrontRegion.shared.startObserving()

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
        self.defaultsForPermissions = defaults

        // Phase 11: no ad SDK start before the first-launch prompts resolve.
        if !FirstLaunchPermissionPolicy.isSkipped(arguments: ProcessInfo.processInfo.arguments) {
            monetization.setLaunchPermissionsHold(true)
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-econTrackingAnswered") {
            monetization.debugMarkTrackingPromptRequested()
        }
        #endif

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
        // Phase 25: re-read ATT so a Tracking change in iOS Settings reaches
        // the next ad request without a relaunch.
        monetization.refreshRequestPolicyForForeground()
        monetization.startAdsIfPermitted()
        // Cold launches only: `app_opened_v1` carries the install-age and
        // launch-count buckets that `EBEvents.recordLaunch` maintains, and a
        // warm foreground is not a launch.
        if isColdLaunch { EBEvents.recordLaunch() }
    }

    /// Phase 25: presents the set-exit interstitial armed on the completion
    /// screen, from the window's root, once the card cover has finished
    /// dismissing. Called by the shell when the cover's session ends.
    func resolvePendingSetExitBreak(environment: EconAdPresentationEnvironment? = nil) async {
        let presenter = environment ?? LiveAdPresentationEnvironment.shared
        guard let outcome = await monetization.presentPendingSetExitBreak(environment: presenter) else { return }
        if outcome == .presented {
            // An ad disqualifies this session for a later rating request.
            review.noteNegativeSessionEvent(.ad)
        }
    }

    /// Entitlement changes must reach ad behaviour and content access on the same
    /// turn, in either direction (purchase, restore, refund, revocation).
    func syncEntitlements(from store: PurchaseManager) {
        // `provisionalAdsSuppression` keeps ads OFF (never content ON) for a
        // reader whose last verified state was entitled, until StoreKit's
        // first answer this run (Phase 11).
        monetization.update(entitlements: EconEntitlements(
            unlockAll: store.isUnlockAllPurchased,
            removeAds: store.isRemoveAdsPurchased || store.provisionalAdsSuppression,
            pro: store.isProActive))
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

    /// Settings → Privacy → Analytics ID → Reset: the vendor state and id are
    /// deleted and a fresh anonymous id is minted, without emitting a consent
    /// change (the reader's answer did not change).
    func resetAnalyticsIdentity() {
        guard telemetry.isAnalyticsEnabled else { return }
        telemetry.setAnalyticsConsent(false)
        telemetry.setAnalyticsConsent(true)
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
        CourseProgressStore.resetPersistedState(in: defaults)
        defaults.removeObject(forKey: ContentStore.cardStatesDefaultsKey)
        for key in ["currentStreak", "lastStreakDate", "cardsTodayCount",
                    "cardsTodayDate", "seenOnboarding"] {
            defaults.removeObject(forKey: key)
        }
    }
    #endif
}
