import Foundation

// MARK: - First-open analytics consent (Dudley factory pattern)
//
// Owner order 2026-09-14: analytics consent is asked ONCE, on first open, as a
// card revealed when the StudioIntro fades — not only in Settings, and not only
// after the first completed set. Ported from Table Talk 1.1.5
// (`AnalyticsConsentPrompt.swift` + `AnalyticsConsentCard.swift`) and adapted to
// EconByte's facades (`EconTelemetry.isConfigured` / `setAnalyticsConsent`,
// `EconDiagnostics.isConfigured` / `setDiagnosticsConsent`).
//
// Rules:
//   * Shown only when there is somewhere to send: a PostHog key and/or a Sentry
//     DSN resolved for THIS process. An unkeyed build — and every Debug, unit
//     test or UI-test process, which `InstrumentationContext` keeps unkeyed —
//     has nothing to consent to and shows nothing. Never an empty promise.
//   * Both answers are equal-weight buttons and both are persisted. "Not now"
//     is a real answer, not a dismissal; the card never nags again for this
//     prompt version.
//   * One answer sets both vendor consents (analytics, and crash diagnostics
//     when a DSN is present). Settings → Privacy & Data stays the per-vendor
//     control afterwards.
//   * An install that already answered the 1.1 / 1.1.2 session-complete primer
//     (`ConsentPromptPolicy.wasShown`) is never asked again — one question, one
//     answer, whichever surface asked it. Answering this card also marks that
//     primer as shown, so the two surfaces can never both ask.
//   * Nothing about the decision itself is measured beyond the existing,
//     declared `analytics_consent_changed_v1` the Settings switch already
//     emits; `consent_state` stays a prohibited telemetry property.
//   * This is NOT the App Tracking Transparency prompt. ATT (1.1.2 build 13) is
//     asked later, once, from the session-complete exit by `EconMonetization`.
//     This card is product analytics only, and its copy says so.

enum FirstOpenConsentPolicy {

    /// Bump when the copy or the scope of the ask changes materially; every
    /// install is asked again once.
    static let promptVersion = 1

    static let answeredVersionKey = "ebAnalyticsConsentPromptVersion"

    /// Launch argument that suppresses the card (UI tests, screenshot runs).
    /// Honoured in every configuration so a test harness never depends on a
    /// DEBUG-only branch. It is also an `InstrumentationContext` automation
    /// marker, so a launch carrying it can never reach the live projects.
    static let skipArgument = "-EBSkipConsentPrompt"

    static func shouldPresent(isConfigured: Bool,
                              legacyPrimerAnswered: Bool,
                              defaults: UserDefaults,
                              arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        guard isConfigured else { return false }
        guard !arguments.contains(skipArgument) else { return false }
        // The DEBUG smoke grants consent programmatically; asking on top of
        // that would be two answers to one question.
        guard !arguments.contains("-EBInstrumentationSmoke") else { return false }
        // The 1.1 / 1.1.2 session-complete primer already asked this install.
        guard !legacyPrimerAnswered else { return false }
        return defaults.integer(forKey: answeredVersionKey) < promptVersion
    }

    /// Persist that this prompt version was answered (either way).
    static func recordAnswered(defaults: UserDefaults) {
        defaults.set(promptVersion, forKey: answeredVersionKey)
    }

    static func reset(defaults: UserDefaults) {
        defaults.removeObject(forKey: answeredVersionKey)
    }
}

/// The exact words on the card. Kept as data so a test can hold them to the
/// same facts Settings → Privacy & Data states (anonymous, bucketed, 90 days,
/// ID reset) and can prove the card never reads as an ad-tracking prompt.
enum FirstOpenConsentCopy {
    static let title = "Help improve EconByte?"
    static let body = "Share anonymous usage analytics: bucketed counts of which topics and modes get used. Never a card, a definition, a bookmark, a price, or anything you type — and never an advertising identifier."
    static let diagnosticsAddendum = "The same choice also turns on crash reports, which carry a stack trace and nothing personal."
    static let footer = "Sent events are kept 90 days. Your random analytics ID resets whenever you turn this off in Settings → Privacy & Data."
    static let accept = "Share anonymous analytics"
    static let decline = "Not now"

    static var allSlots: [String] { [title, body, diagnosticsAddendum, footer, accept, decline] }
}
