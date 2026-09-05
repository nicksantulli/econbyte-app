import Foundation

// MARK: - The vocabulary, as types
//
// Every enumerated value the schema declares is produced HERE, as an explicit
// raw value, and nowhere else — call sites pass a case, not a string. Two things
// follow from that:
//
//  * a call site cannot invent a value the schema has not declared, and
//  * `EconTelemetryTests.testEveryEnumeratedValueIsProducibleBySomeCallSite`
//    can scan the app sources (excluding the schema's own declaration) and prove
//    that every declared value has a producer. A value with no producer reads as
//    coverage that does not exist, which is the same defect as an event with no
//    call site.
//
// Raw values are written out longhand (`case daily = "daily"`) rather than left
// to Swift's synthesis precisely so the scan can see them.

/// Which deck the user is in.
enum EBMode: String {
    case daily = "daily"
    case topic = "topic"
    case bookmarks = "bookmarks"
}

/// Where a flow was entered from.
enum EBEntryPoint: String {
    case home = "home"
    case homeHighlight = "home_highlight"
    case topicGrid = "topic_grid"
    case bookmarks = "bookmarks"
    case settings = "settings"
    case paywall = "paywall"
}

enum EBDirection: String {
    case forward = "forward"
    case back = "back"
}

/// Why a card session ended.
enum EBEndReason: String {
    case completed = "completed"
    case userExit = "user_exit"
}

enum EBBookmarkAction: String {
    case added = "added"
    case removed = "removed"
}

/// One vocabulary shared by every "how did it go" property.
enum EBOutcome: String {
    case completed = "completed"
    case cancelled = "cancelled"
    case pending = "pending"
    case failed = "failed"
    case unavailable = "unavailable"
    case loaded = "loaded"
    case filled = "filled"
    case noFill = "no_fill"
    case nothingToRestore = "nothing_to_restore"
}

enum EBProductFamily: String {
    case unlockAll = "unlock_all"
    case removeAds = "remove_ads"
}

/// Why an ad was not requested or not shown. Named `suppression` rather than
/// `reason` so it cannot share a vocabulary with the session-end reason.
enum EBSuppression: String {
    case regionRestricted = "region_restricted"
    case adsRemoved = "ads_removed"
}

// MARK: - Emission

/// The single place the app talks to telemetry. Views and services call these;
/// none of them constructs a `TelemetryEvent` itself, so the property names and
/// bucket functions cannot drift apart across twenty call sites.
///
/// Everything here is fail-soft by construction: `EconTelemetry.capture`
/// validates and then discards unless analytics is both configured and enabled,
/// so calling any of these in a build with no PostHog key does nothing at all.
@MainActor
enum EconGrowth {

    private enum Key {
        static let installDate = "ebInstallDate"
        static let launchCount = "ebLaunchCount"
    }

    /// The marketing version and build, as one short token (`1.1.2 (9)`). Inside
    /// the `.token` charset — no `/`, no punctuation a sentence would need.
    static var appVersionToken: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }

    /// Called once per launch, from `EconByteApp`. Records the install date on
    /// first launch (a date this app already had no reason to keep, kept only so
    /// the *bucket* can be computed — the date itself is never transmitted, and
    /// `install_date` is a prohibited property name).
    static func recordLaunch(defaults: UserDefaults = .standard) {
        let installed: Date
        if let stored = defaults.object(forKey: Key.installDate) as? Date {
            installed = stored
        } else {
            installed = Date()
            defaults.set(installed, forKey: Key.installDate)
        }
        let launches = defaults.integer(forKey: Key.launchCount) + 1
        defaults.set(launches, forKey: Key.launchCount)

        let ageDays = Calendar.current.dateComponents([.day], from: installed, to: Date()).day ?? 0

        EconTelemetry.shared.capture(TelemetryEvent("app_opened_v1", [
            "app_version": .string(appVersionToken),
            "install_age_bucket": .string(TelemetryBucket.installAge(days: max(0, ageDays))),
            "launch_count_bucket": .string(TelemetryBucket.launchCount(launches)),
        ]))
    }

    // MARK: Card sessions

    static func sessionStarted(mode: EBMode, entryPoint: EBEntryPoint, deckSize: Int) {
        EconTelemetry.shared.capture(TelemetryEvent("session_started_v1", [
            "mode": .string(mode.rawValue),
            "entry_point": .string(entryPoint.rawValue),
            "deck_size_bucket": .string(TelemetryBucket.cards(deckSize)),
        ]))
    }

    static func cardAdvanced(mode: EBMode, direction: EBDirection, depth: Int) {
        EconTelemetry.shared.capture(TelemetryEvent("card_advanced_v1", [
            "mode": .string(mode.rawValue),
            "direction": .string(direction.rawValue),
            "depth_bucket": .string(TelemetryBucket.cards(depth)),
        ]))
    }

    /// `difficulty` is the card's own tier, which comes from the bundled catalog
    /// at runtime rather than from a literal anywhere in the app — the schema's
    /// declared set is checked against the catalog by
    /// `testDeclaredDifficultiesMatchTheBundledCatalog`. A card carrying an
    /// undeclared tier is rejected by the validator, not sent.
    static func cardFlipped(mode: EBMode, difficulty: String) {
        EconTelemetry.shared.capture(TelemetryEvent("card_flipped_v1", [
            "mode": .string(mode.rawValue),
            "difficulty": .string(difficulty),
        ]))
    }

    static func sessionEnded(mode: EBMode,
                             reason: EBEndReason,
                             cardsViewed: Int,
                             duration: TimeInterval,
                             hadBookmark: Bool,
                             adImpressions: Int) {
        EconTelemetry.shared.capture(TelemetryEvent("session_ended_v1", [
            "mode": .string(mode.rawValue),
            "reason": .string(reason.rawValue),
            "cards_viewed_bucket": .string(TelemetryBucket.cards(cardsViewed)),
            "duration_bucket": .string(TelemetryBucket.duration(seconds: duration)),
            "had_bookmark": .bool(hadBookmark),
            "ad_impressions_count": .int(min(max(0, adImpressions), 9)),
        ]))
    }

    static func bookmarkChanged(action: EBBookmarkAction, bookmarkCount: Int) {
        EconTelemetry.shared.capture(TelemetryEvent("bookmark_changed_v1", [
            "action": .string(action.rawValue),
            "bookmark_count_bucket": .string(TelemetryBucket.bookmarkCount(bookmarkCount)),
        ]))
    }

    // MARK: Monetisation

    static func lockedTopicTapped(entryPoint: EBEntryPoint) {
        EconTelemetry.shared.capture(TelemetryEvent("topic_locked_tapped_v1", [
            "entry_point": .string(entryPoint.rawValue),
        ]))
    }

    static func paywallViewed(entryPoint: EBEntryPoint, productsReady: Bool) {
        EconTelemetry.shared.capture(TelemetryEvent("paywall_viewed_v1", [
            "entry_point": .string(entryPoint.rawValue),
            "products_ready": .bool(productsReady),
        ]))
    }

    static func productsLoaded(outcome: EBOutcome) {
        EconTelemetry.shared.capture(TelemetryEvent("products_loaded_v1", [
            "outcome": .string(outcome.rawValue),
        ]))
    }

    static func purchaseStarted(family: EBProductFamily, entryPoint: EBEntryPoint) {
        EconTelemetry.shared.capture(TelemetryEvent("purchase_started_v1", [
            "product_family": .string(family.rawValue),
            "entry_point": .string(entryPoint.rawValue),
        ]))
    }

    static func purchaseFinished(family: EBProductFamily, outcome: EBOutcome) {
        EconTelemetry.shared.capture(TelemetryEvent("purchase_finished_v1", [
            "product_family": .string(family.rawValue),
            "outcome": .string(outcome.rawValue),
        ]))
    }

    static func restoreFinished(outcome: EBOutcome, entryPoint: EBEntryPoint) {
        EconTelemetry.shared.capture(TelemetryEvent("restore_finished_v1", [
            "outcome": .string(outcome.rawValue),
            "entry_point": .string(entryPoint.rawValue),
        ]))
    }

    // MARK: Ads

    static func adEligibilityReached(depth: Int) {
        EconTelemetry.shared.capture(TelemetryEvent("ad_eligibility_reached_v1", [
            "depth_bucket": .string(TelemetryBucket.cards(depth)),
        ]))
    }

    static func adLoadFinished(outcome: EBOutcome) {
        EconTelemetry.shared.capture(TelemetryEvent("ad_load_finished_v1", [
            "outcome": .string(outcome.rawValue),
        ]))
    }

    static func adImpression(ordinal: Int) {
        EconTelemetry.shared.capture(TelemetryEvent("ad_impression_v1", [
            "ordinal": .int(min(max(0, ordinal), 9)),
        ]))
    }

    static func adSuppressed(_ suppression: EBSuppression) {
        EconTelemetry.shared.capture(TelemetryEvent("ad_suppressed_v1", [
            "suppression": .string(suppression.rawValue),
        ]))
    }

    // MARK: Retention

    static func streakDayCredited(streak: Int) {
        EconTelemetry.shared.capture(TelemetryEvent("streak_day_credited_v1", [
            "streak_bucket": .string(TelemetryBucket.streak(streak)),
        ]))
    }

    static func notificationPermissionResult(granted: Bool) {
        EconTelemetry.shared.capture(TelemetryEvent("notification_permission_result_v1", [
            "granted": .bool(granted),
        ]))
    }

    static func reviewRequestAttempted(launchCount: Int) {
        EconTelemetry.shared.capture(TelemetryEvent("review_request_attempted_v1", [
            "app_version": .string(appVersionToken),
            "launch_count_bucket": .string(TelemetryBucket.launchCount(launchCount)),
        ]))
    }

    // MARK: Delivery

    /// Hands whatever is queued to the transport. Called at the end of a card
    /// session and when the app leaves the foreground — often enough that a
    /// crash does not lose a day of counts, rarely enough that it is not a
    /// per-tap network call.
    static func flush() {
        Task { await EconTelemetry.shared.flush() }
    }
}
