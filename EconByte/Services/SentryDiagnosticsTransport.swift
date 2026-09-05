import Foundation
#if canImport(Sentry)
import Sentry
#endif

// MARK: - Sentry adapter (the vendor surface behind DiagnosticsTransporting)
//
// The ONLY file in the app that imports Sentry. Crash-only. The policy that
// decides whether diagnostics may run at all — the Release cache-removal
// precondition, the DiagnosticsFilter — lives ABOVE this seam in
// EconDiagnostics.swift. This adapter applies the reviewed crash-only options
// and nothing else: no session replay, no tracing, no profiling, no logs, no
// network/app breadcrumbs, no user object, no screenshots, no view hierarchy,
// no server-side IP. Every field of DiagnosticsConfiguration is applied here;
// InstrumentationPrivacyTests fails the build if one is not.
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

            // Performance / profiling — off.
            options.tracesSampleRate = NSNumber(value: configuration.tracesSampleRate)
            options.enableAutoPerformanceTracing = configuration.enableAutoPerformanceTracing
            options.enableUserInteractionTracing = configuration.enableUserInteractionTracing
            options.enableAppHangTracking = false
            options.enableWatchdogTerminationTracking = false
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

            // Defence in depth at the SDK boundary: strip every breadcrumb and
            // drop the user object before anything is sent. This mirrors
            // DiagnosticsFilter.beforeSend, which is unit-tested on our own model.
            options.beforeBreadcrumb = { _ in nil }
            options.beforeSend = { event in
                event.user = nil
                event.breadcrumbs = nil
                return event
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
