import Foundation
#if canImport(PostHog)
import PostHog
#endif

// MARK: - Where posthog-ios keeps its files
//
// The SDK writes everything for one project under
// `<Application Support>/<bundle id>/<project token>/` (PostHogStorage
// `getAppFolderUrl`), including the offline event queue.
//
// This matters because `reset()` and `close()` DO NOT delete that queue:
// PostHogStorage.reset explicitly skips `.queue` / `.replayQeueue` / `.logsQueue`
// ("each queue manages its own disk state"), so an opt-out that only calls them
// leaves finished-but-unsent events on disk which the SDK sends the moment
// analytics is switched back on. Deleting the directory is the only way to make
// the Settings promise ("stops sending straight away, clears the queue on this
// device") true.
//
// Deleting the whole project directory rather than the queue files alone is
// deliberate and load-bearing in a second way: `optOut()` persists
// `posthog.optOut = true`, and `setup()` reads that flag back on the next start
// (PostHogSDK.setup). Leaving it behind would make re-enabling analytics
// silently dead. Removing the directory removes the flag and the anonymous id
// together, which is exactly the "fresh, unjoinable identity" the opt-out
// promises.
enum PostHogLocalStore {

    /// The keys PostHogStorage.reset() leaves on disk. Not read by the app —
    /// the purge removes the whole directory — but named here because they are
    /// the reason the purge exists, and the suite builds its fixture from them.
    static let survivesResetAndClose = [
        "posthog.queueFolder.uuid",
        "posthog.queueFolder",
        "posthog.queue.plist",
        "posthog.replayFolder.uuid",
        "posthog.replayBufferFolder",
        "posthog.logsFolder",
        "posthog.anonymousId",
    ]

    /// iOS keeps this per app container; the SDK's own base directory.
    static var applicationSupportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
    }

    static func projectDirectory(base: URL,
                                 bundleIdentifier: String,
                                 projectToken: String) -> URL {
        base.appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent(projectToken, isDirectory: true)
    }

    /// Removes the directory. An absent directory is a success, not a failure —
    /// nothing left to leak is the outcome we want either way.
    @discardableResult
    static func purge(directory: URL, fileManager: FileManager = .default) -> Bool {
        guard fileManager.fileExists(atPath: directory.path) else { return true }
        do {
            try fileManager.removeItem(at: directory)
            return true
        } catch {
            return false
        }
    }
}

// MARK: - PostHog adapter (the vendor surface behind TelemetryTransporting)
//
// This is the ONLY file in the app that imports PostHog. Everything that
// protects the user — the typed event allowlist, the validator, the bounded
// queue, the opt-out gate — lives ABOVE this seam in EconTelemetry.swift and
// runs before a single call reaches here. The adapter's whole job is: apply the
// reviewed configuration, hand PostHog an already-validated event, report the
// id the SDK is really using, and never do anything on its own.
//
// FAIL-SOFT: this transport is only ever constructed when a non-nil PostHog key
// exists (see EconTelemetry.init); with no key the facade uses
// NoOpTelemetryTransport and this file's SDK is never touched. If PostHog is not
// linked for some reason (`!canImport`), every method degrades to a no-op —
// still no crash.
//
// PRIVACY POSTURE enforced here, matching TelemetryConfiguration field for
// field (InstrumentationPrivacyTests asserts that none is left unapplied):
//   * no autocapture (lifecycle, screen views, element interactions) — off
//   * no session replay, no surveys, no feature flags, no error tracking
//   * no logs, no tracing headers, no swizzling — several of these default to
//     ON in the SDK, so they are set explicitly rather than assumed
//   * personProfiles = never  → anonymous, no person profiles server-side
//   * the distinct id is PostHog's own anonymous per-install id; no device
//     identifier, no advertising identifier, no PII, ever.
//
// IDENTITY: the adapter does NOT call `identify`. Under
// `personProfiles = .never` posthog-ios 3.71.4 ignores it outright
// (PostHogSDK.identify bails at `requirePersonProcessing`), so calling it
// achieved nothing except to make the app believe it had chosen the id. The id
// is read back with `getDistinctId()` instead, and that is the value Settings
// shows and a deletion request can quote.
final class PostHogTelemetryTransport: TelemetryTransporting {

    /// PostHog ingest host (US cloud by default; EU projects override via the
    /// secrets xcconfig). Never `nil` — resolved by TelemetryCredentials.
    private let host: String

    /// Held from construction so teardown can find the SDK's directory even in a
    /// process where `start` was never called.
    private var projectToken: String
    private let storageBase: URL
    private let bundleIdentifier: String
    private let fileManager: FileManager

    private(set) var isStarted = false

    /// True when the last teardown actually removed the SDK's directory. Read by
    /// the suite; a false here would mean the opt-out copy is overstating.
    private(set) var didPurgeLocalState = false

    init(apiKey: String,
         host: String,
         storageBase: URL = PostHogLocalStore.applicationSupportDirectory,
         bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "",
         fileManager: FileManager = .default) {
        self.projectToken = apiKey
        self.host = host
        self.storageBase = storageBase
        self.bundleIdentifier = bundleIdentifier
        self.fileManager = fileManager
    }

    /// The id on the wire, straight from the SDK. Empty means the SDK has no
    /// storage manager yet, which is reported as "no id" rather than "".
    var distinctID: String? {
        guard isStarted else { return nil }
        #if canImport(PostHog)
        let identifier = PostHogSDK.shared.getDistinctId()
        return identifier.isEmpty ? nil : identifier
        #else
        return nil
        #endif
    }

    func start(apiKey: String, configuration: TelemetryConfiguration) {
        guard !isStarted else { return }
        projectToken = apiKey
        #if canImport(PostHog)
        let config = PostHogConfig(projectToken: apiKey, host: host)

        // Autocapture — all off. Nothing about which card the user is reading.
        config.captureApplicationLifecycleEvents = configuration.captureApplicationLifecycleEvents
        config.captureScreenViews = configuration.captureScreenViews
        config.captureElementInteractions = configuration.captureElementInteractions

        // Replay / surveys / flags — all off.
        config.sessionReplay = configuration.sessionReplay
        config.surveys = configuration.surveys
        config.sendFeatureFlagEvent = configuration.featureFlags
        config.preloadFeatureFlags = configuration.featureFlags

        // Error tracking — off. Sentry is this app's single crash owner; two
        // crash handlers fighting over the same signals is how you get neither.
        config.errorTrackingConfig.autoCapture = configuration.errorTracking

        // Logs — off. PostHog's log subsystem is capture-on-demand (there is no
        // enable flag), so "off" is enforced at the only gate the SDK offers: a
        // beforeSend chain that drops every record. A future `captureLog` call
        // anywhere in the app therefore still sends nothing.
        if !configuration.captureLogs {
            config.logs.setBeforeSend { _ in nil }
        }

        // Tracing headers — off. When set, PostHog swizzles URLSession and
        // stamps X-POSTHOG-DISTINCT-ID onto outbound requests, which would leak
        // our anonymous id to third-party hosts — including, in this app, the ad
        // stack. `nil` == never injected.
        if !configuration.sendTracingHeaders {
            config.tracingHeaders = nil
        }

        // Swizzling — off. The SDK default is `true`.
        config.enableSwizzling = configuration.swizzling

        // Anonymous: no identified person profiles. Mapped from the reviewed
        // configuration rather than hardcoded, and mapped with an exhaustive
        // switch — the SDK default is `.identifiedOnly`, so if a future change
        // adds a case to TelemetryPersonProfiles this stops compiling instead of
        // silently sending the wrong one.
        switch configuration.personProfiles {
        case .never: config.personProfiles = .never
        }

        // Bounded delivery mirrors the facade's own queue limits.
        config.maxBatchSize = configuration.maxBatchSize
        config.maxQueueSize = configuration.maxQueueSize

        PostHogSDK.shared.setup(config)
        #endif
        isStarted = true
    }

    /// Hands an already-validated batch to PostHog. Returns `true` once handed
    /// off — PostHog then owns network delivery and its own retry. The facade's
    /// durable queue sits in front of this, so a pre-start call cannot lose data
    /// (it simply is not sent).
    func send(_ events: [TelemetryEvent]) async -> Bool {
        guard isStarted else { return false }
        #if canImport(PostHog)
        for event in events {
            PostHogSDK.shared.capture(event.name, properties: Self.properties(from: event))
        }
        PostHogSDK.shared.flush()
        #endif
        return true
    }

    /// Opt out at the SDK, tear it down, then delete everything it persisted.
    ///
    /// Order matters. `optOut()` stops further capture, `close()` stops the
    /// queues and their timers, and only then is the directory removed — so the
    /// SDK cannot rewrite a file between the delete and the teardown.
    func stopAndClearLocalState() {
        #if canImport(PostHog)
        PostHogSDK.shared.optOut()
        PostHogSDK.shared.reset()
        PostHogSDK.shared.close()
        #endif
        didPurgeLocalState = PostHogLocalStore.purge(directory: localStateDirectory,
                                                     fileManager: fileManager)
        isStarted = false
    }

    /// The directory this transport owns on disk, exposed so the suite can put
    /// a queue in it and watch the opt-out remove it.
    var localStateDirectory: URL {
        PostHogLocalStore.projectDirectory(base: storageBase,
                                           bundleIdentifier: bundleIdentifier,
                                           projectToken: projectToken)
    }

    /// Maps the closed TelemetryValue set to PostHog's `[String: Any]`. Only the
    /// three primitive shapes the schema permits can appear — there is no path
    /// for a free-form object.
    static func properties(from event: TelemetryEvent) -> [String: Any] {
        var out: [String: Any] = [:]
        for (key, value) in event.properties {
            switch value {
            case let .string(text): out[key] = text
            case let .int(number):  out[key] = number
            case let .bool(flag):   out[key] = flag
            }
        }
        return out
    }
}
