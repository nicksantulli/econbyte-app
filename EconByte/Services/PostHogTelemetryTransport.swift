import Foundation
#if canImport(PostHog)
import PostHog
#endif

// MARK: - PostHog adapter (the vendor surface behind TelemetryTransporting)
//
// This is the ONLY file in the app that imports PostHog. Everything that
// protects the user — the typed event allowlist, the validator, the bounded
// queue, the opt-out gate, the anonymous identity — lives ABOVE this seam in
// EconTelemetry.swift and runs before a single call reaches here. The adapter's
// whole job is: apply the reviewed configuration, hand PostHog an
// already-validated event, and never do anything on its own.
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
//   * the distinct id is the app-scoped random UUID minted by the facade; no
//     device identifier, no advertising identifier, no PII, ever.
final class PostHogTelemetryTransport: TelemetryTransporting {

    /// PostHog ingest host (US cloud by default; EU projects override via the
    /// secrets xcconfig). Never `nil` — resolved by TelemetryCredentials.
    private let host: String

    private(set) var isStarted = false

    init(host: String) {
        self.host = host
    }

    func start(apiKey: String, configuration: TelemetryConfiguration, distinctID: String) {
        guard !isStarted else { return }
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
        // Route the app-scoped random UUID as the distinct id. With
        // personProfiles = .never this creates no person profile; it only labels
        // events with our anonymous, rotate-able id.
        PostHogSDK.shared.identify(distinctID)
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

    func stopAndClearLocalState() {
        #if canImport(PostHog)
        // Forget the local identity and any queued/persisted events, then tear
        // the SDK down so re-enabling starts clean.
        PostHogSDK.shared.reset()
        PostHogSDK.shared.close()
        #endif
        isStarted = false
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
