import Foundation

// MARK: - Event vocabulary (design section 10.2)
//
// Manual, allowlisted events only. No autocapture, no replay, no person
// profiles, no free text. No provider token exists yet, so nothing is ever
// transmitted — see `CONTENT-DECISIONS.md` D5.

public enum EconEvent: String, CaseIterable, Equatable {
    case appOpened = "app_opened"
    case dailySetStarted = "daily_set_started"
    case cardViewed = "card_viewed"
    case cardFlipped = "card_flipped"
    case cardBookmarkChanged = "card_bookmark_changed"
    case dailySetCompleted = "daily_set_completed"
    case topicOpened = "topic_opened"
    case lockedTopicTapped = "locked_topic_tapped"
    case paywallViewed = "paywall_viewed"
    case purchaseStarted = "purchase_started"
    case purchaseCompleted = "purchase_completed"
    case purchaseFailed = "purchase_failed"
    case restoreStarted = "restore_started"
    case restoreCompleted = "restore_completed"
    case restoreFailed = "restore_failed"
    case adEligible = "ad_eligible"
    case adImpression = "ad_impression"
    case adDismissed = "ad_dismissed"
    case notificationPrimerViewed = "notification_primer_viewed"
    case notificationPermissionResult = "notification_permission_result"
    case reviewPromptEligible = "review_prompt_eligible"
    case reviewPromptRequested = "review_prompt_requested"
    case analyticsConsentChanged = "analytics_consent_changed"
    case diagnosticsConsentChanged = "diagnostics_consent_changed"
}

public enum EconResultClass: String, CaseIterable, Equatable {
    case success, cancelled, pending, unavailable, network, provider, unverified, revoked
}

public enum EconEntryPoint: String, CaseIterable, Equatable {
    case home
    case topicGrid = "topic_grid"
    case settings
    case sessionComplete = "session_complete"
    case paywall
    case bookmarks
}

public enum EconLaunchType: String, CaseIterable, Equatable {
    case cold, warm
}

public enum EconSessionSource: String, CaseIterable, Equatable {
    case direct, notification
}

public enum EconAccessState: String, CaseIterable, Equatable {
    case free, unlocked, locked
}

// MARK: - Property values

/// A closed value shape. There is no free-text case: values are short enum
/// tokens, integers, or booleans, and tokens are length-capped.
public enum EconPropertyValue: Equatable {
    case token(String)
    case int(Int)
    case bool(Bool)

    public var isWithinTokenBudget: Bool {
        guard case .token(let text) = self else { return true }
        return text.count <= EconEventSchema.maximumTokenLength
    }
}

// MARK: - Schema

public enum EconEventValidation: Equatable {
    case accepted([String: EconPropertyValue])
    case rejectedUndeclaredProperty(String)
    case rejectedProhibitedProperty(String)
    case rejectedOversizedValue(String)
}

public enum EconEventSchema {

    public static let schemaVersion = 1

    public static let commonProperties: [String] = [
        "app_version", "build_number", "os_major", "locale_language",
        "session_source", "day",
    ]

    /// Never acceptable, on any event, however anyone declares them.
    public static let prohibitedProperties: Set<String> = [
        "card_text", "definition", "example", "explanation", "answer", "prose",
        "source_url", "url", "link",
        "price", "display_price", "amount", "revenue",
        "transaction_id", "original_transaction_id", "receipt",
        "advertising_id", "idfa", "idfv", "device_id",
        "ip", "ip_address", "email", "name",
        "user_text", "query", "search", "note", "bookmark_list",
    ]

    /// Tokens are short closed-vocabulary values (identifiers, enums, buckets).
    public static let maximumTokenLength = 64

    public static func allowedProperties(for event: EconEvent) -> Set<String> {
        switch event {
        case .appOpened: return ["launch_type"]
        case .dailySetStarted: return ["set_id", "eligible_card_count"]
        case .cardViewed: return ["card_id", "topic_id", "difficulty", "position"]
        case .cardFlipped: return ["card_id", "topic_id", "position"]
        case .cardBookmarkChanged: return ["card_id", "topic_id", "is_bookmarked"]
        case .dailySetCompleted: return ["set_id", "card_count", "duration_bucket", "streak_day"]
        case .topicOpened: return ["topic_id", "access_state"]
        case .lockedTopicTapped: return ["topic_id", "entry_point"]
        case .paywallViewed: return ["entry_point", "products_available"]
        case .purchaseStarted: return ["product_id", "entry_point"]
        case .purchaseCompleted: return ["product_id", "entry_point"]
        case .purchaseFailed: return ["product_id", "result_class"]
        case .restoreStarted: return ["entry_point"]
        case .restoreCompleted: return ["restored_product_count"]
        case .restoreFailed: return ["result_class"]
        case .adEligible: return ["placement", "sets_since_last_ad"]
        case .adImpression: return ["placement"]
        case .adDismissed: return ["placement", "result_class"]
        case .notificationPrimerViewed: return ["entry_point"]
        case .notificationPermissionResult: return ["result_class"]
        case .reviewPromptEligible: return ["completed_set_count", "streak_bucket"]
        case .reviewPromptRequested: return ["completed_set_count", "streak_bucket"]
        case .analyticsConsentChanged: return ["enabled", "entry_point"]
        case .diagnosticsConsentChanged: return ["enabled", "entry_point"]
        }
    }

    public static func validate(_ event: EconEvent,
                                properties: [String: EconPropertyValue]) -> EconEventValidation {
        let allowed = allowedProperties(for: event)
        for key in properties.keys.sorted() where prohibitedProperties.contains(key) {
            return .rejectedProhibitedProperty(key)
        }
        for key in properties.keys.sorted() where !allowed.contains(key) {
            return .rejectedUndeclaredProperty(key)
        }
        for key in properties.keys.sorted() where !(properties[key]?.isWithinTokenBudget ?? true) {
            return .rejectedOversizedValue(key)
        }
        return .accepted(properties)
    }
}

// MARK: - Environment

public struct EconTelemetryEnvironment: Equatable {
    public var appVersion: String
    public var buildNumber: String
    public var osMajor: Int
    public var localeLanguage: String
    public var sessionSource: EconSessionSource

    public init(appVersion: String = "",
                buildNumber: String = "",
                osMajor: Int = 0,
                localeLanguage: String = "",
                sessionSource: EconSessionSource = .direct) {
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.osMajor = osMajor
        self.localeLanguage = localeLanguage
        self.sessionSource = sessionSource
    }

    public static var current: EconTelemetryEnvironment {
        let info = Bundle.main.infoDictionary
        let language: String
        if #available(iOS 16, *) {
            language = Locale.current.language.languageCode?.identifier ?? "und"
        } else {
            language = Locale.current.languageCode ?? "und"
        }
        return EconTelemetryEnvironment(
            appVersion: info?["CFBundleShortVersionString"] as? String ?? "0",
            buildNumber: info?["CFBundleVersion"] as? String ?? "0",
            osMajor: ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
            localeLanguage: language,
            sessionSource: .direct)
    }
}

// MARK: - Provider configuration

public struct EconProviderOptions: Equatable {
    public var autocaptureEnabled = false
    public var sessionReplayEnabled = false
    public var personProfilesEnabled = false
    public var heatmapsEnabled = false
    public var surveysEnabled = false
    public var featureFlagsEnabled = false
    public init() {}
}

public enum EconTelemetryConfiguration {
    /// Supplied through build configuration at provider-enablement time. It is
    /// deliberately absent from the committed Info.plist, so this resolves to
    /// nil and the app runs with a no-op sink.
    public static let providerInfoPlistKey = "EconPostHogAPIKey"

    public static var postHogAPIKey: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: providerInfoPlistKey) as? String,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return value
    }

    public static var providerOptions: EconProviderOptions { EconProviderOptions() }
}

// MARK: - Sink

public struct EconRecordedEvent: Equatable {
    public let name: String
    public let properties: [String: EconPropertyValue]
    public init(name: String, properties: [String: EconPropertyValue]) {
        self.name = name
        self.properties = properties
    }
}

public protocol EconTelemetrySink: AnyObject {
    var isConfigured: Bool { get }
    func send(_ events: [EconRecordedEvent])
    func reset()
}

/// The shipping sink while no provider token exists. Never transmits anything.
public final class EconNoOpTelemetrySink: EconTelemetrySink {
    public init() {}
    public var isConfigured: Bool { false }
    public func send(_ events: [EconRecordedEvent]) {}
    public func reset() {}
}

// MARK: - Telemetry

public final class EconTelemetry {

    public static let consentDefaultsKey = "econ.telemetry.consent"
    public static let installationIDDefaultsKey = "econ.telemetry.installationID"
    public static let maximumQueuedEvents = 200

    public private(set) var isEnabled: Bool
    public private(set) var queue: [EconRecordedEvent] = []

    private let defaults: UserDefaults
    private let environment: EconTelemetryEnvironment
    private let sink: EconTelemetrySink
    private let now: () -> Date

    public init(defaults: UserDefaults = .standard,
                environment: EconTelemetryEnvironment = EconTelemetryEnvironment(),
                sink: EconTelemetrySink = EconNoOpTelemetrySink(),
                now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.environment = environment
        self.sink = sink
        self.now = now
        self.isEnabled = defaults.bool(forKey: Self.consentDefaultsKey)
    }

    public var isProviderConfigured: Bool { sink.isConfigured }

    public var installationID: String? {
        guard isEnabled else { return nil }
        return defaults.string(forKey: Self.installationIDDefaultsKey)
    }

    public static func makeInstallationID() -> String { UUID().uuidString }

    @discardableResult
    public func capture(_ event: EconEvent,
                        properties: [String: EconPropertyValue] = [:]) -> EconEventValidation {
        let validation = EconEventSchema.validate(event, properties: properties)
        guard case .accepted(let accepted) = validation else { return validation }
        guard isEnabled else { return validation }

        var merged = accepted
        merged["app_version"] = .token(environment.appVersion)
        merged["build_number"] = .token(environment.buildNumber)
        merged["os_major"] = .int(environment.osMajor)
        merged["locale_language"] = .token(environment.localeLanguage)
        merged["session_source"] = .token(environment.sessionSource.rawValue)
        merged["day"] = .token(EconAdState.dayKey(for: now()))

        queue.append(EconRecordedEvent(name: event.rawValue, properties: merged))
        if queue.count > Self.maximumQueuedEvents {
            queue.removeFirst(queue.count - Self.maximumQueuedEvents)
        }
        return validation
    }

    public func setEnabled(_ enabled: Bool, entryPoint: EconEntryPoint) {
        guard enabled != isEnabled else { return }
        defaults.set(enabled, forKey: Self.consentDefaultsKey)
        isEnabled = enabled

        if enabled {
            defaults.set(Self.makeInstallationID(), forKey: Self.installationIDDefaultsKey)
            capture(.analyticsConsentChanged,
                    properties: ["enabled": .bool(true),
                                 "entry_point": .token(entryPoint.rawValue)])
        } else {
            // Opting out withdraws consent for the record of opting out too: the
            // queue is dropped, the identifier removed, the client reset.
            queue.removeAll()
            defaults.removeObject(forKey: Self.installationIDDefaultsKey)
            sink.reset()
        }
    }

    /// Hands the bounded queue to the sink. With no provider token the sink is a
    /// no-op, so this drains locally and transmits nothing.
    public func flush() {
        guard isEnabled, sink.isConfigured, !queue.isEmpty else { return }
        sink.send(queue)
        queue.removeAll()
    }

    #if DEBUG
    public static func resetPersistedState(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: consentDefaultsKey)
        defaults.removeObject(forKey: installationIDDefaultsKey)
    }
    #endif
}
