import Foundation
#if canImport(Sentry)
import Sentry
#endif

// MARK: - The envelope, as the live filter sees it
//
// `DiagnosticsFilter` is the reviewed model of what may leave. Until 1.1.2 it
// was only ever run against a hand-built `DiagnosticEvent` in the suite, while
// the real `beforeSend` did its own two-line strip — so the model could pass
// every test while the live path did something else. This protocol is the join:
// the closure the SDK calls runs `DiagnosticsFilter` over a real envelope, and
// the suite runs the SAME closure over a stand-in. Only the vendor object is
// substituted; the code under test is the code that ships.
protocol DiagnosticsEnvelope: AnyObject {
    /// Custom tags, the one field the filter is allowed to keep.
    var scrubbableTags: [String: String]? { get set }
    /// After `stripIdentifyingFields()` this must be false. It is checked, not
    /// assumed — see `screen`.
    var carriesUserObject: Bool { get }
    /// Free-form app breadcrumbs and `extra`. Never sent.
    var carriesBreadcrumbs: Bool { get }
    var carriesExtra: Bool { get }
    /// Remove the user object, the breadcrumbs and the extras.
    func stripIdentifyingFields()
}

// `SentryEvent` is exposed to Swift as `Sentry.Event` (NS_SWIFT_NAME) in
// sentry-cocoa 8.58.4; the ObjC name is what the SDK's own sources call it.
#if canImport(Sentry)
extension Sentry.Event: DiagnosticsEnvelope {
    var scrubbableTags: [String: String]? {
        get { tags }
        set { tags = newValue }
    }
    var carriesUserObject: Bool { user != nil }
    var carriesBreadcrumbs: Bool { !(breadcrumbs ?? []).isEmpty }
    var carriesExtra: Bool { !(extra ?? [:]).isEmpty }
    func stripIdentifyingFields() {
        user = nil
        breadcrumbs = nil
        extra = nil
    }
}
#endif

// MARK: - Sentry adapter (the vendor surface behind DiagnosticsTransporting)
//
// The ONLY file in the app that imports Sentry. Crash-only. The policy that
// decides whether diagnostics may run at all — the Release cache-removal
// precondition, the DiagnosticsFilter — lives ABOVE this seam in
// EconDiagnostics.swift. This adapter applies the reviewed crash-only options
// and nothing else: no sessions, no app-hang or watchdog reports, no session
// replay, no tracing, no profiling, no logs, no network/app breadcrumbs, no user
// object, no screenshots, no view hierarchy, no server-side IP. Every field of
// DiagnosticsConfiguration is applied here; InstrumentationPrivacyTests fails
// the build if one is not.
//
// FAIL-SOFT: only constructed when a non-nil DSN exists. If Sentry is not linked
// (`!canImport`), every method is a no-op and `guaranteesLocalCacheRemoval` is
// false, which keeps Release diagnostics off.
//
// LOCAL CACHE: Sentry persists unsent envelopes on disk. We point its cache at a
// known directory we own so that disabling diagnostics can delete it —
// `guaranteesLocalCacheRemoval` answers `true` only because
// `clearLocalEnvelopeCache()` can actually remove that directory.
final class SentryDiagnosticsTransport: DiagnosticsTransporting {

    private(set) var isStarted = false

    /// A directory we control, so teardown can delete every persisted envelope.
    /// Under Caches (purgeable, never backed up), namespaced to this app.
    private let cacheDirectory: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("eb-sentry", isDirectory: true)
    }()

    /// True: we set a cache path we own and can delete it below. (Only meaningful
    /// when Sentry is linked; false otherwise so Release never starts.)
    var guaranteesLocalCacheRemoval: Bool {
        #if canImport(Sentry)
        return true
        #else
        return false
        #endif
    }

    // MARK: The live beforeSend
    //
    // Read the order carefully, because getting it wrong silently deletes crash
    // reporting rather than breaking a build.
    //
    // sentry-cocoa 8.58.4 stamps its OWN installation id onto every event before
    // any callback runs: `SentryClient.processEvent` calls
    // `setUserIdIfNoUserSet:` (SentryClient.m, right after the scope is applied)
    // and only then invokes `options.beforeSend`. So by the time this closure is
    // reached, `event.user` is ALWAYS non-nil even though nothing in EconByte
    // ever sets a user. Judging the envelope before stripping it would therefore
    // drop 100% of crashes — the filter rejects on a user object by design.
    //
    // Hence: strip first, then judge what remains. The user check afterwards is a
    // post-condition — it proves the strip worked rather than describing an error
    // path — and the tag check is the live one: an app tag outside
    // `DiagnosticsTag` drops the envelope instead of shipping it.

    /// The closure `options.beforeSend` installs, factored out so the suite can
    /// exercise the shipped code path directly. Returns `nil` to drop.
    @discardableResult
    static func screen<Envelope: DiagnosticsEnvelope>(_ event: Envelope) -> Envelope? {
        event.stripIdentifyingFields()

        let model = DiagnosticEvent(
            tags: event.scrubbableTags ?? [:],
            breadcrumbs: event.carriesBreadcrumbs ? ["present"] : [],
            userID: event.carriesUserObject ? "present" : nil,
            attachments: event.carriesExtra ? ["extra"] : [],
            serverIP: nil
        )

        guard case let .send(scrubbed) = DiagnosticsFilter.beforeSend(model) else { return nil }
        event.scrubbableTags = scrubbed.tags.isEmpty ? nil : scrubbed.tags
        return event
    }

    func start(dsn: String, configuration: DiagnosticsConfiguration) {
        guard !isStarted else { return }
        #if canImport(Sentry)
        SentrySDK.start { options in
            options.dsn = dsn
            options.cacheDirectoryPath = self.cacheDirectory.path

            // Personal data — off.
            //
            // `scrubServerSideIP` has no switch of its own: sentry-cocoa derives
            // the envelope's `settings.infer_ip` from sendDefaultPii (`"never"`
            // when it is false), and that field is what stops the Sentry backend
            // backfilling the client IP from the request. So the scrub is
            // expressed as a veto over sendDefaultPii — flip sendDefaultPii on in
            // a later change and the IP still stays off until someone also drops
            // the scrub, on purpose.
            options.sendDefaultPii = configuration.sendDefaultPii
                && !configuration.scrubServerSideIP
            options.attachScreenshot = configuration.attachScreenshot
            options.attachViewHierarchy = configuration.attachViewHierarchy

            // Sessions — off. The SDK default is ON, and a session envelope is
            // not a crash; leaving this at its default is what made the previous
            // build send per-launch usage to a project the copy calls crash-only.
            options.enableAutoSessionTracking = configuration.enableAutoSessionTracking

            // Performance / profiling — off.
            options.tracesSampleRate = NSNumber(value: configuration.tracesSampleRate)
            options.enableAutoPerformanceTracing = configuration.enableAutoPerformanceTracing
            options.enableUserInteractionTracing = configuration.enableUserInteractionTracing
            options.enableAppHangTracking = configuration.enableAppHangTracking
            options.enableWatchdogTerminationTracking = configuration.enableWatchdogTerminationTracking
            // `configureProfiling` is 8.58's live profiling switch and is left at
            // its default of nil — nil means no profiler is ever constructed.
            // `profilesSampleRate` and `enableAppLaunchProfiling` are deprecated
            // in 8.58 but still read by the SDK, and a switch that still works is
            // a switch that has to be set — deprecated is not inert. The two
            // deprecation warnings this raises are deliberate: when Sentry 9
            // deletes these properties the build fails loudly instead of quietly
            // inheriting whatever the new defaults are.
            options.profilesSampleRate = NSNumber(value: configuration.profilesSampleRate)
            options.enableAppLaunchProfiling = configuration.enableAppLaunchProfiling

            // Session replay is configured by sample rate, not by a flag: both
            // rates at zero is the off switch. Set explicitly so an SDK bump that
            // changes a default cannot start recording the screen.
            if !configuration.enableSessionReplay {
                options.sessionReplay.sessionSampleRate = 0
                options.sessionReplay.onErrorSampleRate = 0
            }

            // Structured logs — off at the source. (`beforeSendLog` is compiled
            // out of the SPM distribution, so this flag is the only gate.)
            options.experimental.enableLogs = configuration.captureLogs

            // Breadcrumbs / logs / network — off. No app breadcrumb describing
            // which card the user was reading ever leaves.
            options.enableNetworkBreadcrumbs = configuration.enableNetworkBreadcrumbs
            options.enableAutoBreadcrumbTracking = configuration.enableAutoBreadcrumbTracking
            options.enableCaptureFailedRequests = configuration.enableCaptureFailedRequests
            options.maxBreadcrumbs = UInt(max(0, configuration.maxBreadcrumbs))

            // Swizzling off; a crash handler + stack trace is the entire point.
            options.enableSwizzling = configuration.enableSwizzling
            options.enableCrashHandler = configuration.enableCrashHandler
            options.attachStacktrace = configuration.attachStacktrace

            // Attachments: the two the SDK can produce on its own are already
            // disabled above, and these veto them a second time at the moment of
            // capture. An attachment is the one thing that could carry a picture
            // of a card, so it gets both belts.
            options.beforeCaptureScreenshot = { _ in false }
            options.beforeCaptureViewHierarchy = { _ in false }

            #if DEBUG
            // DEBUG-ONLY, and only for a run that explicitly asked: the
            // ingestion proof has to be able to say WHICH envelope left and
            // under which event id, rather than asserting that one probably
            // did. Compiled out of Release entirely, so no shipped build can
            // turn the vendor's logging on.
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("-EBInstrumentationSmoke")
                || arguments.contains("-EBInstrumentationCrash") {
                options.debug = true
                options.diagnosticLevel = .debug
            }
            #endif

            // Defence in depth at the SDK boundary.
            options.beforeBreadcrumb = { _ in nil }
            options.beforeSend = { event in
                SentryDiagnosticsTransport.screen(event)
            }
        }
        #endif
        isStarted = true
    }

    func close() {
        #if canImport(Sentry)
        SentrySDK.close()
        #endif
        isStarted = false
    }

    /// Remove the SDK's local envelope cache on teardown. We own the directory,
    /// so this is a real deletion, not a hope.
    @discardableResult
    func clearLocalEnvelopeCache() -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: cacheDirectory.path) else { return true }
        do {
            try fm.removeItem(at: cacheDirectory)
            return true
        } catch {
            return false
        }
    }
}
