import Foundation

// MARK: - Growth vocabulary (lineage A, EconByte 1.1)
//
// RECONCILED (1.1.2): these types lived in lineage A's `EconTelemetry.swift`
// alongside a second, transport-less telemetry pipeline (`EconEvent`,
// `EconEventSchema`, `EconTelemetry`). The reconciliation keeps ONE pipeline —
// lineage C's transport-backed `EconTelemetry` with the `_v1` vocabulary the
// factory policy mirror declares — so A's pipeline is gone. What survives here
// is everything that was never about transport: the shared enumerations the
// views and the growth policies speak, the environment description, and the
// consent-primer presentation rule (design section 10.1).

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
    /// 1.1.4: the Pro paywall's two content entry points.
    case course
    case brief
}

public enum EconLaunchType: String, CaseIterable, Equatable {
    case cold, warm
}

public enum EconSessionSource: String, CaseIterable, Equatable {
    case direct, notification
}

public enum EconAccessState: String, CaseIterable, Equatable {
    // Raw values written longhand rather than left to Swift's synthesis, the
    // same convention the `EB…` vocabularies use: the telemetry schema declares
    // these three as an enumerated vocabulary, and
    // `testEveryEnumeratedValueIsProducibleBySomeCallSite` proves each declared
    // value has a producer by scanning the app sources for the literal.
    case free = "free"
    case unlocked = "unlocked"
    case locked = "locked"
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

// MARK: - Consent presentation

/// Design section 10.1: each consent choice is presented after the first
/// completed set, never on first launch. Both remain reachable in Settings
/// forever; this only governs the one contextual offer.
public enum ConsentPromptPolicy {
    public static let shownDefaultsKey = "econ.consent.promptShown"

    public static func eligible(completedSetCount: Int, alreadyShown: Bool) -> Bool {
        completedSetCount >= 1 && !alreadyShown
    }

    public static func wasShown(in defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: shownDefaultsKey)
    }

    public static func noteShown(in defaults: UserDefaults) {
        defaults.set(true, forKey: shownDefaultsKey)
    }
}

// MARK: - Bridge to the shipped telemetry vocabulary

extension EconEntryPoint {
    /// RECONCILED (1.1.2): the growth systems speak lineage A's `EconEntryPoint`;
    /// the shipped telemetry schema speaks lineage C's `EBEntryPoint`. Raw values
    /// are identical for every case both lineages have, so this is a total,
    /// lossless mapping rather than a lookup that can fail.
    var ebEntryPoint: EBEntryPoint {
        switch self {
        case .home:            return .home
        case .topicGrid:       return .topicGrid
        case .settings:        return .settings
        case .sessionComplete: return .sessionComplete
        case .paywall:         return .paywall
        case .bookmarks:       return .bookmarks
        case .course:          return .course
        case .brief:           return .brief
        }
    }
}
