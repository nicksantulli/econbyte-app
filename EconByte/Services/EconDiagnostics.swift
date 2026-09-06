import Foundation

// MARK: - Crash diagnostics
//
// Sentry in EconByte is crash-only. It is the app's single crash owner (PostHog
// error tracking stays off), and it is configured so that a crash report
// contains a stack trace and six coarse tags — nothing else. No user object, no
// screenshots, no view hierarchy, no replay, no traces, no profiles, no network
// breadcrumbs, and no app breadcrumb describing which card the user was reading.
//
// COLLECTION POSTURE (1.1.2, Owner-authorised 2026-09-04): crash reporting is ON
// whenever a DSN is configured. There is deliberately no consent gate and no
// Settings switch for it — an anonymous stack trace with no user object, no
// breadcrumbs and no PII is not personal data to trade for a toggle, and a crash
// reporter that most users leave off reports nothing. The privacy footer in
// Settings still SAYS this happens; see Views/SettingsView.swift.
//
// CREDENTIAL POSTURE: the DSN is injected at build time from a gitignored
// xcconfig into Info.plist. Without it `DiagnosticsCredentials.current` is `nil`
// and the subsystem is inert — nothing starts, nothing is sent.

// MARK: - Configuration

/// What the Sentry adapter must apply. Held as plain data so the crash-only
/// posture is asserted by a unit test rather than by reading the SDK's defaults
/// and hoping.
struct DiagnosticsConfiguration: Equatable {
    // Personal data
    var sendDefaultPii = false
    var attachScreenshot = false
    var attachViewHierarchy = false
    var scrubServerSideIP = true

    // Performance / replay / profiling — all off
    var enableSessionReplay = false
    var tracesSampleRate: Double = 0
    var profilesSampleRate: Double = 0
    var enableAutoPerformanceTracing = false
    var enableUserInteractionTracing = false
    var enableAppLaunchProfiling = false

    /// Sessions — off. sentry-cocoa defaults this to YES, and a session envelope
    /// is not a crash: it is a per-launch record of who opened the app and for
    /// how long, sent on every foreground/background transition whether or not
    /// anything went wrong. Settings and the App Store answers both say EconByte
    /// sends crash reports, so sessions must not leave. This is the field the
    /// crash-only claim actually rests on.
    var enableAutoSessionTracking = false

    /// App hangs and watchdog terminations — off. Both are "the app was slow or
    /// the OS killed it" telemetry rather than crashes, and watchdog tracking
    /// persists scope to disk between launches. Held as fields (rather than
    /// literals in the adapter) so the configuration scan covers them.
    var enableAppHangTracking = false
    var enableWatchdogTerminationTracking = false

    // Breadcrumbs and logs — all off
    var enableAutoBreadcrumbTracking = false
    var enableNetworkBreadcrumbs = false
    var enableCaptureFailedRequests = false
    var captureLogs = false
    var maxBreadcrumbs = 0

    // Swizzling stays off; a crash handler and a stack trace are the point.
    var enableSwizzling = false
    var enableCrashHandler = true
    var attachStacktrace = true

    /// Server-side retention, recorded here because the privacy policy and the
    /// App Store privacy answers must state the same number the project is
    /// configured with.
    var rawRetentionDays = 30
}

/// Release, build, environment, OS major version, device-class bucket, and app
/// lifecycle state are the only custom tags.
enum DiagnosticsTag: String, CaseIterable {
    case release = "release"
    case build = "build"
    case environment = "environment"
    case osMajor = "os_major"
    case deviceClass = "device_class"
    case lifecycleState = "lifecycle_state"
}

// MARK: - beforeSend filter

/// The shape of an outgoing envelope, reduced to the parts the filter judges.
struct DiagnosticEvent: Equatable {
    var tags: [String: String] = [:]
    var breadcrumbs: [String] = []
    var userID: String?
    var attachments: [String] = []
    var serverIP: String?
}

enum DiagnosticsRejection: Equatable {
    case userIdentity
    case attachment(String)
    case disallowedTag(String)
}

enum DiagnosticsScreening: Equatable {
    case send(DiagnosticEvent)
    case drop(DiagnosticsRejection)
}

/// A `beforeSend` filter that rejects events with disallowed fields and strips
/// free-form app breadcrumbs. Rejection is preferred to redaction where the
/// presence of the field is itself the bug — a user object or an attachment
/// means something upstream is wrong, and dropping the event is the safe answer.
enum DiagnosticsFilter {

    private static let allowedTags = Set(DiagnosticsTag.allCases.map(\.rawValue))

    static func beforeSend(_ event: DiagnosticEvent) -> DiagnosticsScreening {
        if event.userID != nil { return .drop(.userIdentity) }
        if let attachment = event.attachments.sorted().first {
            return .drop(.attachment(attachment))
        }
        if let disallowed = event.tags.keys.sorted().first(where: { !allowedTags.contains($0) }) {
            return .drop(.disallowedTag(disallowed))
        }

        var scrubbed = event
        scrubbed.breadcrumbs = []     // free-form app breadcrumbs never leave
        scrubbed.serverIP = nil       // server-side IP storage disabled/scrubbed
        return .send(scrubbed)
    }
}

// MARK: - Credentials

enum DiagnosticsCredentials {
    /// Intentionally `nil`, permanently — same rule as the analytics key.
    static let embeddedDSN: String? = nil

    static let infoPlistKey = "EBSentryDSN"

    static func dsn(from info: [String: Any]?) -> String? {
        guard let raw = info?[infoPlistKey] as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static var current: String? {
        dsn(from: Bundle.main.infoDictionary) ?? embeddedDSN
    }

    /// The DSN this *process* may use. Same rule as the analytics key: a
    /// unit-test host, a UI-test launch, or any Debug build gets `nil`, so a
    /// deliberate test crash cannot land in the production Sentry project. The
    /// ingestion proof passes `-AllowAnalyticsInDebug` to lift it deliberately.
    static func resolved(_ credential: String?, in context: InstrumentationContext) -> String? {
        context.suppressesLiveTransports ? nil : credential
    }
}

// MARK: - Transport seam

protocol DiagnosticsTransporting: AnyObject {
    var isStarted: Bool { get }
    /// A *precondition* for shipping diagnostics: if the SDK version cannot
    /// guarantee removal of its local envelope cache, diagnostics stays disabled
    /// in Release.
    var guaranteesLocalCacheRemoval: Bool { get }
    func start(dsn: String, configuration: DiagnosticsConfiguration)
    func close()
    @discardableResult func clearLocalEnvelopeCache() -> Bool
}

/// The transport used when no DSN exists. `guaranteesLocalCacheRemoval` is true
/// because a no-op transport writes no cache to begin with; the real adapter
/// answers honestly for its own SDK version.
final class NoOpDiagnosticsTransport: DiagnosticsTransporting {
    private(set) var isStarted = false
    var guaranteesLocalCacheRemoval: Bool { true }
    func start(dsn: String, configuration: DiagnosticsConfiguration) { isStarted = true }
    func close() { isStarted = false }
    @discardableResult func clearLocalEnvelopeCache() -> Bool { true }
}

// MARK: - Facade

@MainActor
final class EconDiagnostics: ObservableObject {

    static let shared = EconDiagnostics()

    enum Refusal: Equatable {
        /// No Sentry project is configured for this build.
        case noDSNConfigured
        /// The SDK cannot promise to delete its local envelope cache on
        /// teardown, so Release must not collect.
        case cacheRemovalNotGuaranteed
    }

    @Published private(set) var isDiagnosticsEnabled = false
    private(set) var lastRefusal: Refusal?

    let configuration = DiagnosticsConfiguration()

    /// True when there is a Sentry project to send to.
    var isConfigured: Bool { dsn != nil }

    /// RECONCILED (1.1.2): crash diagnostics is a **separate opt-in choice,
    /// off until the user turns it on** — lineage A's posture, and the one the
    /// live 1.1 App Store notes state. Lineage C started the crash handler at
    /// construction unconditionally; that is a better crash-catch story but it
    /// silently reverses a published promise, so the switch is honoured here
    /// and the key is lineage A's, which keeps a 1.1 opt-in across the update.
    static let consentDefaultsKey = "econ.diagnostics.consent"

    private let transport: DiagnosticsTransporting
    private let dsn: String?
    private let defaults: UserDefaults
    private let isReleaseBuild: Bool

    convenience init() {
        #if DEBUG
        let release = false
        #else
        let release = true
        #endif
        // A test/automation/Debug process resolves to no DSN at all, so a test
        // crash can never reach the live project (see InstrumentationContext).
        let dsn = DiagnosticsCredentials.resolved(DiagnosticsCredentials.current, in: .current)
        // Fail-soft transport selection: with no DSN the vendor SDK is never
        // touched (NoOp) and nothing below can start it. A real DSN wires the
        // Sentry adapter, which the designated init then starts.
        let transport: DiagnosticsTransporting = dsn == nil
            ? NoOpDiagnosticsTransport()
            : SentryDiagnosticsTransport()
        self.init(transport: transport,
                  dsn: dsn,
                  defaults: .standard,
                  isReleaseBuild: release)
    }

    init(transport: DiagnosticsTransporting,
         dsn: String?,
         defaults: UserDefaults,
         isReleaseBuild: Bool = false) {
        self.transport = transport
        self.dsn = dsn
        self.defaults = defaults
        self.isReleaseBuild = isReleaseBuild

        // OFF until the user opts in. When they have, the crash handler is
        // installed here, at construction, so it is in place before the first
        // line of app code that could crash. The two guards inside still apply
        // — no DSN, or an SDK that cannot promise to delete its own envelope
        // cache, and nothing starts.
        if defaults.bool(forKey: Self.consentDefaultsKey) {
            setDiagnosticsConsent(true)
        }
    }

    // MARK: Enablement

    /// Turns crash reporting on or off. The user-facing control is the
    /// "Crash diagnostics" switch in Settings; the choice is persisted here so
    /// construction can honour it on the next launch.
    ///
    /// Sentry receives no PostHog identifier and no advertising state; the only
    /// thing this call passes it is the DSN and the crash-only configuration
    /// above. Calling it twice must not start the SDK twice.
    func setDiagnosticsConsent(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.consentDefaultsKey)
        guard enabled else {
            stop()
            return
        }
        guard !isDiagnosticsEnabled else { return }

        guard let dsn else {
            lastRefusal = .noDSNConfigured
            isDiagnosticsEnabled = false
            return
        }
        guard !isReleaseBuild || transport.guaranteesLocalCacheRemoval else {
            lastRefusal = .cacheRemovalNotGuaranteed
            isDiagnosticsEnabled = false
            return
        }

        lastRefusal = nil
        isDiagnosticsEnabled = true
        transport.start(dsn: dsn, configuration: configuration)
    }

    /// Disabling stops future envelopes and removes the SDK's local envelope
    /// cache before teardown.
    private func stop() {
        isDiagnosticsEnabled = false
        guard transport.isStarted else { return }
        transport.clearLocalEnvelopeCache()
        transport.close()
    }
}
