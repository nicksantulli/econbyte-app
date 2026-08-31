import Foundation

// MARK: - Diagnostics (design section 10.3)
//
// Minimal, consent-gated, and scrubbed. No PII, no screenshots, no view
// hierarchy, no replay, no traces, no breadcrumbs (which could carry card
// content). No DSN exists yet, so nothing is transmitted — see
// `CONTENT-DECISIONS.md` D5.

public enum EconDiagnosticCode: String, CaseIterable, Equatable {
    case contentCatalogInvalid = "content_catalog_invalid"
    case storeProductsUnavailable = "store_products_unavailable"
    case transactionUnverified = "transaction_unverified"
    case restoreFailed = "restore_failed"
    case consentUpdateFailed = "consent_update_failed"
    case adLoadFailed = "ad_load_failed"
    case adPresentFailed = "ad_present_failed"
    case notificationScheduleFailed = "notification_schedule_failed"
}

/// Bounded, machine-readable failure detail. There is deliberately no free-text
/// case, so card prose, URLs, and user input cannot reach a diagnostic report.
public struct EconDiagnosticDetail: Equatable {
    public var errorDomain: String
    public var errorCode: Int

    public init(errorDomain: String = "", errorCode: Int = 0) {
        self.errorDomain = EconDiagnosticScrubber.scrub(errorDomain)
        self.errorCode = errorCode
    }

    /// Takes only the domain and code. `localizedDescription` is discarded
    /// because it routinely interpolates user- or content-derived text.
    public init(_ error: Error) {
        let ns = error as NSError
        self.init(errorDomain: ns.domain, errorCode: ns.code)
    }
}

public struct EconDiagnosticReport: Equatable {
    public let code: EconDiagnosticCode
    public let appVersion: String
    public let buildNumber: String
    public let osMajor: Int
    public let detail: EconDiagnosticDetail?

    public init(code: EconDiagnosticCode,
                appVersion: String,
                buildNumber: String,
                osMajor: Int,
                detail: EconDiagnosticDetail?) {
        self.code = code
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.osMajor = osMajor
        self.detail = detail
    }
}

/// Defensive backstop for any string that reaches a diagnostic payload.
public enum EconDiagnosticScrubber {
    public static let redaction = "[redacted]"
    public static let maximumLength = 4096

    private static let patterns: [String] = [
        // Email addresses.
        #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#,
        // Anything with a scheme, which could carry a query string.
        #"[A-Za-z][A-Za-z0-9+.\-]*://\S+"#,
        // Bare hostnames.
        #"\b[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+\.(?:com|org|net|gov|edu|io|app|co)\b"#,
        // Long digit runs: identifiers, receipts, card-like numbers.
        #"\d{6,}"#,
    ]

    public static func scrub(_ input: String) -> String {
        var output = input
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            output = regex.stringByReplacingMatches(
                in: output,
                range: NSRange(output.startIndex..., in: output),
                withTemplate: redaction)
        }
        if output.count > maximumLength {
            output = String(output.prefix(maximumLength))
        }
        return output
    }
}

public struct EconDiagnosticsOptions: Equatable {
    public var sendDefaultPII = false
    public var attachScreenshots = false
    public var attachViewHierarchy = false
    public var sessionReplayEnabled = false
    public var tracesSampleRate: Double = 0
    public var capturesNetworkBodies = false
    public var maximumBreadcrumbs = 0
    public init() {}
}

public enum EconDiagnosticsConfiguration {
    /// Supplied through build configuration at provider-enablement time;
    /// deliberately absent from the committed Info.plist.
    public static let providerInfoPlistKey = "EconSentryDSN"

    public static var sentryDSN: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: providerInfoPlistKey) as? String,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return value
    }

    public static var options: EconDiagnosticsOptions { EconDiagnosticsOptions() }
}

public protocol EconDiagnosticsSink: AnyObject {
    var isConfigured: Bool { get }
    func send(_ reports: [EconDiagnosticReport])
    func reset()
}

public final class EconNoOpDiagnosticsSink: EconDiagnosticsSink {
    public init() {}
    public var isConfigured: Bool { false }
    public func send(_ reports: [EconDiagnosticReport]) {}
    public func reset() {}
}

public final class EconDiagnostics {

    public static let consentDefaultsKey = "econ.diagnostics.consent"
    public static let installationIDDefaultsKey = "econ.diagnostics.installationID"
    public static let maximumQueuedReports = 50

    public private(set) var isEnabled: Bool
    public private(set) var queue: [EconDiagnosticReport] = []

    private let defaults: UserDefaults
    private let appVersion: String
    private let buildNumber: String
    private let osMajor: Int
    private let sink: EconDiagnosticsSink

    public init(defaults: UserDefaults = .standard,
                appVersion: String = "",
                buildNumber: String = "",
                osMajor: Int = 0,
                sink: EconDiagnosticsSink = EconNoOpDiagnosticsSink()) {
        self.defaults = defaults
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.osMajor = osMajor
        self.sink = sink
        self.isEnabled = defaults.bool(forKey: Self.consentDefaultsKey)
    }

    public convenience init(defaults: UserDefaults = .standard,
                            environment: EconTelemetryEnvironment,
                            sink: EconDiagnosticsSink = EconNoOpDiagnosticsSink()) {
        self.init(defaults: defaults,
                  appVersion: environment.appVersion,
                  buildNumber: environment.buildNumber,
                  osMajor: environment.osMajor,
                  sink: sink)
    }

    public var isProviderConfigured: Bool { sink.isConfigured }

    public var installationID: String? {
        guard isEnabled else { return nil }
        return defaults.string(forKey: Self.installationIDDefaultsKey)
    }

    public static func makeInstallationID() -> String { UUID().uuidString }

    @discardableResult
    public func capture(_ code: EconDiagnosticCode,
                        detail: EconDiagnosticDetail? = nil) -> Bool {
        guard isEnabled else { return false }
        queue.append(EconDiagnosticReport(code: code,
                                          appVersion: appVersion,
                                          buildNumber: buildNumber,
                                          osMajor: osMajor,
                                          detail: detail))
        if queue.count > Self.maximumQueuedReports {
            queue.removeFirst(queue.count - Self.maximumQueuedReports)
        }
        return true
    }

    public func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        defaults.set(enabled, forKey: Self.consentDefaultsKey)
        isEnabled = enabled
        if enabled {
            defaults.set(Self.makeInstallationID(), forKey: Self.installationIDDefaultsKey)
        } else {
            queue.removeAll()
            defaults.removeObject(forKey: Self.installationIDDefaultsKey)
            sink.reset()
        }
    }

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
