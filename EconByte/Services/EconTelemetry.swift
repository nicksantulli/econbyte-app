import Foundation

// MARK: - Product analytics
//
// EconByte's analytics are deliberately small, deliberately manual, and
// deliberately unable to carry card content. Three layers enforce that, in
// order:
//
//   1. `TelemetrySchema`     — the only events and properties that exist.
//   2. `TelemetryValidator`  — drops anything undeclared, prohibited, or free
//                              form BEFORE it reaches the queue.
//   3. `TelemetryQueue`      — a bounded, expiring, FIFO buffer; nothing is
//                              retained indefinitely and nothing is sent twice.
//
// The vendor SDK sits behind `TelemetryTransporting`; the PostHog adapter is in
// Services/PostHogTelemetryTransport.swift.
//
// COLLECTION POSTURE (1.1.2, Owner-authorised 2026-09-04 — "turn EconByte on the
// same way once 1.1.1 clears"): analytics are ON by default and the user turns
// them OFF in Settings. What makes that defensible is not a consent sheet — it
// is the three layers above: nothing free-form can be captured, so "on" can only
// ever mean bucketed counts of which topics and modes get used. The opt-out is
// stored as `ebAnalyticsOptOut` (absent == not opted out == on), which is why an
// upgrading 1.1.1 install with no stored answer is enabled rather than stuck off.
//
// RELATIONSHIP TO ADMOB: EconByte declares `NSPrivacyTracking = true` and lists
// `googleads.g.doubleclick.net` because the ad SDK tracks; that is unchanged and
// unrelated. Nothing in THIS file is tracking: no advertising identifier is read,
// no data is joined with third-party data, and the analytics identity is a random
// per-install id that never leaves the PostHog project.
//
// IDENTITY (corrected 2026-09-05): the identity is PostHog's OWN anonymous id,
// read back from the SDK — not an id this app mints. It used to be an app-minted
// UUID handed to `identify()`, which posthog-ios 3.71.4 silently IGNORES when
// `personProfiles == .never` (PostHogSDK.identify → requirePersonProcessing).
// Events were therefore keyed by the SDK's anonymous id while Settings displayed
// the app's UUID and promised deletion by it — a deletion request quoting that
// id would have matched nothing. The app no longer mints an id at all.
//
// CREDENTIAL POSTURE — read before touching this file: the key is injected at
// build time from a gitignored xcconfig into Info.plist and read at runtime. A
// missing/blank key makes the whole subsystem inert: no identity is minted, no
// event is queued, no transport is started. Never embed a key in source, and
// never borrow another Dudley app's key — cross-app identity separation depends
// on the projects being distinct.

// MARK: - Values

/// The only value shapes an event property may take. There is no `.any` case
/// and no free-form dictionary: a value that cannot be expressed here cannot be
/// captured at all.
enum TelemetryValue: Equatable {
    case string(String)
    case int(Int)
    case bool(Bool)

    var displayValue: String {
        switch self {
        case let .string(value): return value
        case let .int(value):    return String(value)
        case let .bool(value):   return value ? "true" : "false"
        }
    }
}

struct TelemetryEvent: Equatable {
    let name: String
    let properties: [String: TelemetryValue]

    init(_ name: String, _ properties: [String: TelemetryValue] = [:]) {
        self.name = name
        self.properties = properties
    }
}

// MARK: - Schema

/// How a declared property is constrained. Every property is constrained by
/// one of these — none is an open string.
enum TelemetryPropertyKind: Equatable {
    /// A closed vocabulary. Anything outside it is rejected.
    case enumerated(Set<String>)
    /// A short version-shaped token (`1.1.2 (9)`). Length- and charset-limited
    /// so prose cannot be smuggled through it.
    case token(maxLength: Int)
    /// A small integer with a hard ceiling (ad ordinals, impression counts).
    case smallCount(ClosedRange<Int>)
    /// A boolean flag.
    case flag
}

enum TelemetrySchema {

    /// The keys of this table are the complete list of events the app is
    /// permitted to capture. Every one of them has a real emission call site in
    /// the app — `EconTelemetryTests.testEveryDeclaredEventHasAnEmissionCallSite`
    /// fails the build if one does not.
    static let allowedProperties: [String: Set<String>] = [
        "app_opened_v1": ["app_version", "install_age_bucket", "launch_count_bucket"],
        "session_started_v1": ["mode", "entry_point", "deck_size_bucket"],
        "card_advanced_v1": ["mode", "direction", "depth_bucket"],
        "card_flipped_v1": ["mode", "difficulty"],
        "session_ended_v1": ["mode", "reason", "cards_viewed_bucket", "duration_bucket",
                             "had_bookmark", "ad_impressions_count"],
        "bookmark_changed_v1": ["action", "bookmark_count_bucket"],
        "topic_locked_tapped_v1": ["entry_point"],
        "paywall_viewed_v1": ["entry_point", "products_ready"],
        "products_loaded_v1": ["outcome"],
        "purchase_started_v1": ["product_family", "entry_point"],
        "purchase_finished_v1": ["product_family", "outcome"],
        "restore_finished_v1": ["outcome", "entry_point"],
        "ad_eligibility_reached_v1": ["depth_bucket"],
        "ad_load_finished_v1": ["outcome"],
        "ad_impression_v1": ["ordinal"],
        "ad_suppressed_v1": ["suppression"],
        "streak_day_credited_v1": ["streak_bucket"],
        "notification_permission_result_v1": ["granted"],
        "review_request_attempted_v1": ["app_version", "launch_count_bucket"],
    ]

    static var allowedEventNames: Set<String> { Set(allowedProperties.keys) }

    /// Allowed enum values and bucket boundaries, defined in source beside the
    /// typed event schema and unit-tested. A property name has ONE vocabulary
    /// across every event that uses it — that is why, for example, the session
    /// end reason is `reason` and the ad-suppression reason is `suppression`.
    static let propertyKinds: [String: TelemetryPropertyKind] = [
        "mode": .enumerated(["daily", "topic", "bookmarks"]),
        "entry_point": .enumerated(["home", "home_highlight", "topic_grid",
                                    "bookmarks", "settings", "paywall"]),
        "direction": .enumerated(["forward", "back"]),
        "reason": .enumerated(["completed", "user_exit"]),
        "action": .enumerated(["added", "removed"]),
        // The bundled catalog ships exactly two difficulty tiers. Declaring a
        // third that no card carries would read as coverage that does not exist;
        // `testDeclaredDifficultiesMatchTheBundledCatalog` keeps the two in step,
        // so adding an "advanced" tier to cards.json fails here first.
        "difficulty": .enumerated(["intro", "intermediate"]),
        "outcome": .enumerated(["completed", "cancelled", "pending", "failed",
                                "unavailable", "loaded", "filled", "no_fill",
                                "nothing_to_restore"]),
        "product_family": .enumerated(["unlock_all", "remove_ads"]),
        "suppression": .enumerated(["region_restricted", "ads_removed"]),

        "install_age_bucket": .enumerated(Bucket.installAge),
        "launch_count_bucket": .enumerated(Bucket.launchCount),
        "depth_bucket": .enumerated(Bucket.depth),
        "cards_viewed_bucket": .enumerated(Bucket.depth),
        "deck_size_bucket": .enumerated(Bucket.deckSize),
        "duration_bucket": .enumerated(Bucket.duration),
        "bookmark_count_bucket": .enumerated(Bucket.bookmarkCount),
        "streak_bucket": .enumerated(Bucket.streak),

        "app_version": .token(maxLength: 32),

        "ordinal": .smallCount(0...9),
        "ad_impressions_count": .smallCount(0...9),

        "had_bookmark": .flag,
        "products_ready": .flag,
        "granted": .flag,
    ]

    /// The enumerated vocabularies, exposed for tests and for the privacy
    /// documentation that has to state exactly what is collected.
    static var allowedValues: [String: Set<String>] {
        propertyKinds.compactMapValues { kind in
            if case let .enumerated(values) = kind { return values }
            return nil
        }
    }

    /// The prohibited list, named field by field. The undeclared-property rule
    /// already rejects all of these, but naming them means a future schema
    /// addition cannot quietly admit one and means a rejection says *why*.
    static let prohibitedProperties: Set<String> = [
        // card and catalog content — the thing EconByte must never transmit
        "card_id", "card_ids", "card_text", "concept", "concept_body",
        "example_body", "definition", "example", "explanation", "prose",
        "topic_id", "topic_ids", "topic_name", "set_id", "source", "source_url",
        "url", "link", "title", "text",
        // bookmarks and history
        "bookmark_ids", "bookmark_list", "bookmarks", "card_history", "history",
        // exact times and counts where a bucket exists
        "session_started_at", "session_ended_at", "timestamp", "started_at",
        "ended_at", "duration_seconds", "duration", "cards_viewed", "card_count",
        "install_date", "streak_days",
        // StoreKit and money
        "price", "display_price", "amount", "revenue", "product_id",
        "transaction_id", "original_transaction_id", "receipt", "account_id",
        "app_account_token",
        // advertising and consent
        "advertising_id", "idfa", "idfv", "ad_unit_id", "ad_id", "consent_string",
        "consent_state", "att_status",
        // network- and device-derived
        "ip", "ip_address", "latitude", "longitude", "location", "region",
        "user_agent", "device_fingerprint", "device_id", "device_name",
        // anything the user typed or holds
        "contacts", "support_text", "clipboard", "photo", "photos", "user_text",
        "email", "name", "query", "search", "note",
        // third-party error strings
        "sdk_error", "sdk_error_description", "error_description", "error_message",
        "stack_trace",
    ]

    /// Bucket vocabularies. Kept beside the schema so a bucket function and its
    /// declared vocabulary cannot drift apart.
    enum Bucket {
        static let installAge: Set<String> = ["d0", "d1_2", "d3_6", "d7_29", "d30_89", "d90_plus"]
        static let launchCount: Set<String> = ["1", "2_3", "4_10", "11_50", "51_plus"]
        static let depth: Set<String> = ["0", "1_4", "5_9", "10_14", "15_29", "30_plus"]
        static let deckSize: Set<String> = ["0", "1_4", "5_9", "10_14", "15_29", "30_plus"]
        static let duration: Set<String> = ["lt_30s", "30s_2m", "2m_5m", "5m_15m", "15m_plus"]
        static let bookmarkCount: Set<String> = ["0", "1_4", "5_9", "10_24", "25_plus"]
        static let streak: Set<String> = ["1", "2_3", "4_6", "7_29", "30_plus"]
    }
}

// MARK: - Buckets
//
// Exact session timestamps and precise duration/card counts are prohibited when
// a defined bucket exists. These are the defined buckets; nothing else in the
// app may report a raw count.

enum TelemetryBucket {

    static func installAge(days: Int) -> String {
        switch days {
        case ..<1:   return "d0"
        case ..<3:   return "d1_2"
        case ..<7:   return "d3_6"
        case ..<30:  return "d7_29"
        case ..<90:  return "d30_89"
        default:     return "d90_plus"
        }
    }

    static func launchCount(_ launches: Int) -> String {
        switch launches {
        case ..<2:   return "1"
        case ..<4:   return "2_3"
        case ..<11:  return "4_10"
        case ..<51:  return "11_50"
        default:     return "51_plus"
        }
    }

    /// Cards advanced — used for `depth_bucket`, `cards_viewed_bucket` and
    /// `deck_size_bucket` (the three share one vocabulary on purpose: they are
    /// all "how many cards", read at different moments).
    static func cards(_ count: Int) -> String {
        switch count {
        case ..<1:   return "0"
        case ..<5:   return "1_4"
        case ..<10:  return "5_9"
        case ..<15:  return "10_14"
        case ..<30:  return "15_29"
        default:     return "30_plus"
        }
    }

    static func duration(seconds: TimeInterval) -> String {
        switch seconds {
        case ..<30:   return "lt_30s"
        case ..<120:  return "30s_2m"
        case ..<300:  return "2m_5m"
        case ..<900:  return "5m_15m"
        default:      return "15m_plus"
        }
    }

    static func bookmarkCount(_ count: Int) -> String {
        switch count {
        case ..<1:   return "0"
        case ..<5:   return "1_4"
        case ..<10:  return "5_9"
        case ..<25:  return "10_24"
        default:     return "25_plus"
        }
    }

    static func streak(_ days: Int) -> String {
        switch days {
        case ..<2:   return "1"
        case ..<4:   return "2_3"
        case ..<7:   return "4_6"
        case ..<30:  return "7_29"
        default:     return "30_plus"
        }
    }
}

// MARK: - Validation

enum TelemetryRejection: Equatable {
    case unknownEvent(String)
    case prohibitedProperty(event: String, property: String)
    case undeclaredProperty(event: String, property: String)
    case disallowedValue(event: String, property: String, value: String)
}

enum TelemetryValidation: Equatable {
    case accepted
    case rejected(TelemetryRejection)
}

/// An adapter-level validator that drops undeclared events or properties before
/// enqueueing. This is the only way into the queue.
enum TelemetryValidator {

    /// Characters a `.token` property may contain. Deliberately excludes `?`,
    /// `'` and every other character a sentence of card copy would need.
    private static let tokenCharacters = CharacterSet(charactersIn:
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 ._()-+")

    static func validate(_ event: TelemetryEvent) -> TelemetryValidation {
        guard let declared = TelemetrySchema.allowedProperties[event.name] else {
            return .rejected(.unknownEvent(event.name))
        }

        // Sorted passes, so a given malformed event always fails the same way
        // and a test can name the reason.
        let keys = event.properties.keys.sorted()

        for key in keys where TelemetrySchema.prohibitedProperties.contains(key) {
            return .rejected(.prohibitedProperty(event: event.name, property: key))
        }
        for key in keys where !declared.contains(key) {
            return .rejected(.undeclaredProperty(event: event.name, property: key))
        }
        for key in keys {
            guard let value = event.properties[key] else { continue }
            if let failure = check(value, against: TelemetrySchema.propertyKinds[key]) {
                return .rejected(.disallowedValue(event: event.name, property: key, value: failure))
            }
        }
        return .accepted
    }

    /// Returns the offending display value, or `nil` when the value is allowed.
    /// A property with no declared kind is always rejected — a declared property
    /// without a constraint would be an open string.
    private static func check(_ value: TelemetryValue,
                              against kind: TelemetryPropertyKind?) -> String? {
        guard let kind else { return value.displayValue }
        switch (kind, value) {
        case let (.enumerated(allowed), .string(text)):
            return allowed.contains(text) ? nil : text
        case let (.token(maxLength), .string(text)):
            guard !text.isEmpty, text.count <= maxLength,
                  text.rangeOfCharacter(from: tokenCharacters.inverted) == nil else { return text }
            return nil
        case let (.smallCount(range), .int(number)):
            return range.contains(number) ? nil : String(number)
        case (.flag, .bool):
            return nil
        default:
            return value.displayValue
        }
    }
}

// MARK: - Configuration

enum TelemetryPersonProfiles: String, Equatable {
    /// Identified person profiles disabled — every event is anonymous.
    case never
}

/// The configuration the PostHog adapter must apply, expressed as plain data so
/// it can be asserted in a unit test without reading the SDK's defaults and
/// hoping. `InstrumentationPrivacyTests` fails the build if a field declared
/// here is never handed to the vendor object.
struct TelemetryConfiguration: Equatable {
    var captureApplicationLifecycleEvents = false
    var captureScreenViews = false
    var captureElementInteractions = false
    var sessionReplay = false
    var surveys = false
    var featureFlags = false
    var errorTracking = false
    var captureLogs = false
    var sendTracingHeaders = false
    var swizzling = false
    var personProfiles: TelemetryPersonProfiles = .never

    var maxQueueSize = 200
    var maxBatchSize = 20
    var eventExpiry: TimeInterval = 7 * 24 * 60 * 60

    /// Server-side retention, recorded here because the privacy policy and the
    /// App Store privacy answers must state the same numbers the project is
    /// configured with.
    var rawEventRetentionDays = 90
    var aggregateRetentionMonths = 13
}

// MARK: - Credentials

enum TelemetryCredentials {
    /// Intentionally `nil`, permanently. The key belongs in the build's
    /// Info.plist (injected from an Owner-held secret at archive time), never in
    /// source control.
    static let embeddedAPIKey: String? = nil

    static let infoPlistKey = "EBPostHogAPIKey"
    /// The PostHog ingest host, injected the same way. Optional: an empty value
    /// falls back to PostHog US cloud in the transport.
    static let hostInfoPlistKey = "EBPostHogHost"

    /// PostHog US cloud — the default when no host is configured. EU projects
    /// set POSTHOG_HOST explicitly in the secrets xcconfig.
    static let defaultHost = "https://us.i.posthog.com"

    static func apiKey(from info: [String: Any]?) -> String? {
        guard let raw = info?[infoPlistKey] as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The configured host, or `defaultHost` when the Info.plist value is
    /// missing/blank. Never `nil`, so the transport always has a valid endpoint.
    static func host(from info: [String: Any]?) -> String {
        guard let raw = info?[hostInfoPlistKey] as? String else { return defaultHost }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultHost : trimmed
    }

    /// Resolved from Info.plist at runtime. Non-nil from 1.1.2 onward, where the
    /// archive injects the real `econbyte` project key; `nil` in any build made
    /// without the gitignored secrets xcconfig, which keeps that build inert.
    static var current: String? {
        apiKey(from: Bundle.main.infoDictionary) ?? embeddedAPIKey
    }

    /// The key this *process* may use. A unit-test host, a UI-test launch, or
    /// any Debug build resolves to `nil` — see InstrumentationContext — so a
    /// test relaunch cannot write into the production project. The ingestion
    /// proof passes `-AllowAnalyticsInDebug` to lift it deliberately.
    static func resolved(_ credential: String?, in context: InstrumentationContext) -> String? {
        context.suppressesLiveTransports ? nil : credential
    }

    static var currentHost: String {
        host(from: Bundle.main.infoDictionary)
    }
}

// MARK: - Transport seam

protocol TelemetryTransporting: AnyObject {
    var isStarted: Bool { get }

    /// The id the vendor SDK actually stamps on the events it sends, read back
    /// from the SDK rather than assumed. `nil` before `start` and whenever the
    /// SDK cannot answer. This is what Settings displays, because it is the only
    /// id a deletion request can match.
    var distinctID: String? { get }

    func start(apiKey: String, configuration: TelemetryConfiguration)
    func send(_ events: [TelemetryEvent]) async -> Bool
    func stopAndClearLocalState()
}

/// The transport used when no key exists. It exists so the policy layer above it
/// is exercised identically whether or not a project is configured. It reports
/// no distinct id because it sends nothing that could carry one.
final class NoOpTelemetryTransport: TelemetryTransporting {
    private(set) var isStarted = false
    var distinctID: String? { nil }
    func start(apiKey: String, configuration: TelemetryConfiguration) {
        isStarted = true
    }
    func send(_ events: [TelemetryEvent]) async -> Bool { true }
    func stopAndClearLocalState() { isStarted = false }
}

// MARK: - Bounded offline queue

struct QueuedTelemetryEvent: Equatable {
    let event: TelemetryEvent
    let enqueuedAt: Date
}

/// A FIFO buffer with three hard limits: 200 events, batches of 20, and a
/// seven-day expiry. A batch that is in flight cannot be checked out twice, and
/// a failed send returns it to the front rather than dropping it.
final class TelemetryQueue {
    let capacity: Int
    let batchSize: Int
    let expiry: TimeInterval

    private(set) var pending: [QueuedTelemetryEvent] = []
    private var inFlight: [QueuedTelemetryEvent] = []

    init(capacity: Int = 200, batchSize: Int = 20, expiry: TimeInterval = 7 * 24 * 60 * 60) {
        self.capacity = capacity
        self.batchSize = batchSize
        self.expiry = expiry
    }

    var count: Int { pending.count + inFlight.count }
    var hasBatchInFlight: Bool { !inFlight.isEmpty }

    func enqueue(_ event: TelemetryEvent, at date: Date) {
        pending.append(QueuedTelemetryEvent(event: event, enqueuedAt: date))
        let overflow = count - capacity
        if overflow > 0 { pending.removeFirst(min(overflow, pending.count)) }
    }

    func expire(now: Date) {
        pending.removeAll { now.timeIntervalSince($0.enqueuedAt) > expiry }
    }

    /// Takes the next batch, or nothing at all when a batch is already in
    /// flight — the duplicate-flush guard.
    func checkoutBatch(now: Date) -> [TelemetryEvent] {
        guard inFlight.isEmpty else { return [] }
        expire(now: now)
        guard !pending.isEmpty else { return [] }
        inFlight = Array(pending.prefix(batchSize))
        pending.removeFirst(inFlight.count)
        return inFlight.map(\.event)
    }

    func commitBatch() { inFlight.removeAll() }

    func rollbackBatch() {
        guard !inFlight.isEmpty else { return }
        pending.insert(contentsOf: inFlight, at: 0)
        inFlight.removeAll()
    }

    func removeAll() {
        pending.removeAll()
        inFlight.removeAll()
    }
}

// MARK: - Facade

@MainActor
final class EconTelemetry: ObservableObject {

    static let shared = EconTelemetry()

    private enum Key {
        /// The 1.1.2 control. `true` == the user opted out in Settings. Absent
        /// means "never answered", which is ON — that is the whole point of
        /// storing the negative rather than an opt-in.
        static let optOut = "ebAnalyticsOptOut"
    }

    /// The *effective* state: a destination is configured AND the user has not
    /// opted out.
    @Published private(set) var isAnalyticsEnabled = false

    /// PostHog's own anonymous distinct id for this install, read back from the
    /// SDK after it starts and shown in Settings so a user can quote it in a
    /// deletion request. `nil` whenever analytics is off, and `nil` when the SDK
    /// cannot answer — in which case Settings says so rather than showing an id
    /// that is not on the wire.
    @Published private(set) var analyticsIdentity: String?

    /// The most recent validator rejection — surfaced in DEBUG builds so a
    /// mis-declared event fails loudly during development rather than silently.
    private(set) var lastRejection: TelemetryRejection?

    let configuration = TelemetryConfiguration()

    /// True when there is a project to send to at all.
    var isConfigured: Bool { apiKey != nil }

    private let transport: TelemetryTransporting
    private let apiKey: String?
    private let defaults: UserDefaults
    private let now: () -> Date
    private let queue: TelemetryQueue

    convenience init() {
        // A test/automation/Debug process resolves to no key at all, so nothing
        // below this line can reach the live project (see InstrumentationContext).
        let apiKey = TelemetryCredentials.resolved(TelemetryCredentials.current,
                                                   in: .current)
        // Fail-soft transport selection: with no key we never touch the vendor
        // SDK at all (NoOp). A real key wires the PostHog adapter, which starts
        // at construction unless the user has opted out (see startAnalytics).
        // Either way a missing/blank key can never initialize or send anything.
        let transport: TelemetryTransporting = apiKey.map {
            PostHogTelemetryTransport(apiKey: $0, host: TelemetryCredentials.currentHost)
        } ?? NoOpTelemetryTransport()
        self.init(transport: transport, apiKey: apiKey, defaults: .standard)
    }

    init(transport: TelemetryTransporting,
         apiKey: String?,
         defaults: UserDefaults,
         now: @escaping () -> Date = Date.init) {
        self.transport = transport
        self.apiKey = apiKey
        self.defaults = defaults
        self.now = now
        let limits = TelemetryConfiguration()
        self.queue = TelemetryQueue(capacity: limits.maxQueueSize,
                                    batchSize: limits.maxBatchSize,
                                    expiry: limits.eventExpiry)

        // ON by default: start unless the user opted out — but only in a build
        // that has somewhere to send. Without a key nothing starts, however the
        // user answered before.
        if apiKey != nil, !Self.isOptedOut(defaults) {
            startAnalytics()
        }
    }

    var queuedEventCount: Int { queue.count }

    // MARK: Opt-out

    /// Whether the user has switched analytics off. Absent == never answered ==
    /// on.
    private static func isOptedOut(_ defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: Key.optOut)
    }

    /// The Settings toggle, expressed as it reads to the user: `true` == share
    /// analytics. Turning it off stops capture, clears this app's queue, and
    /// tells the transport to opt out and delete the vendor SDK's own persisted
    /// state — all before this call returns — and persists across launches.
    /// Turning it back on leaves the SDK to mint a fresh anonymous id, because
    /// the old one was deleted with everything else.
    func setAnalyticsConsent(_ enabled: Bool) {
        defaults.set(!enabled, forKey: Key.optOut)
        if enabled {
            guard apiKey != nil else { return }   // nothing to turn on
            startAnalytics()
        } else {
            stopAnalytics()
        }
    }

    /// Idempotent: a second call while already running must not re-start the
    /// vendor SDK.
    ///
    /// The displayed identity is read back from the transport AFTER the SDK is
    /// up, so it is the id the SDK will actually stamp on events rather than one
    /// this app hoped it would use.
    private func startAnalytics() {
        guard let apiKey, !isAnalyticsEnabled else { return }
        isAnalyticsEnabled = true
        transport.start(apiKey: apiKey, configuration: configuration)
        analyticsIdentity = transport.distinctID
    }

    private func stopAnalytics() {
        isAnalyticsEnabled = false
        queue.removeAll()
        analyticsIdentity = nil
        // The transport opts out at the vendor SDK and deletes the SDK's own
        // persisted queue and identity, so re-enabling starts from nothing and
        // cannot be joined to previously transmitted events.
        transport.stopAndClearLocalState()
    }

    // MARK: Capture

    /// Validates first, always — so a schema violation is caught even in a
    /// build with analytics off — then enqueues only if there is consent and a
    /// destination.
    @discardableResult
    func capture(_ event: TelemetryEvent) -> TelemetryValidation {
        let validation = TelemetryValidator.validate(event)
        if case let .rejected(reason) = validation {
            lastRejection = reason
            #if DEBUG
            NSLog("[EB] telemetry rejected: \(reason)")
            #endif
            return validation
        }
        guard isAnalyticsEnabled else { return validation }
        queue.enqueue(event, at: now())
        return validation
    }

    func flush() async {
        guard isAnalyticsEnabled else { return }
        let batch = queue.checkoutBatch(now: now())
        guard !batch.isEmpty else { return }
        if await transport.send(batch) {
            queue.commitBatch()
        } else {
            queue.rollbackBatch()
        }
    }
}
