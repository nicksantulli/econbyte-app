# EconByte 1.1.2 — instrumentation configuration smoke

**This is NOT the ingestion proof.** No real PostHog key or Sentry DSN was used,
and nothing was sent to either vendor. What this run proves is narrower and
worth proving on its own: the same source tree behaves correctly *with* and
*without* a configuration, and neither state crashes the app.

The ingestion proof — a Debug build carrying the real `econbyte` key and DSN,
driven by hand, with drained local queues and console verification — is the
orchestrator's next step, and is what `-EBInstrumentationSmoke YES` /
`-EBInstrumentationCrash YES` exist for.

- Build under test: `EconByte.app`, `CFBundleShortVersionString 1.1.2`,
  `CFBundleVersion 9`, Debug, iOS Simulator
- Simulator: `EB-Instr-17` / `E1CA852C-DAC0-4E63-BB48-8CC46B5755C4`
- Date: 2026-09-05 · Xcode 26.5 (17F42)

## A — empty config (a fresh checkout, or CI without secrets)

No `Config/Secrets.xcconfig` present. The committed
`Config/Instrumentation.xcconfig` supplies empty defaults.

- Installed app's Info.plist: `EBPostHogAPIKey`, `EBPostHogHost`, `EBSentryDSN`
  all **empty strings**.
- Launched with `-EBInstrumentationSmoke YES`, which forces consent on — the
  hardest case for fail-soft, because the only thing left to stop the SDKs is
  the missing credential. App log:

  ```
  [EB][smoke] analytics configured=false enabled=false; diagnostics configured=false enabled=false
  ```

- **No SDK initialised. No crash.** App ran to the home screen and stayed up.
- Settings → Privacy rendered the unconfigured shape: **"Off — nothing is
  collected"**, no toggle, and a footer stating that this version collects no
  analytics and no crash reports.

## B — placeholder config (a configured build)

A throwaway `Config/Secrets.xcconfig` was written with an obviously-fake PostHog
key and Sentry DSN, both pointed at the local discard port (`127.0.0.1:9`) so
that nothing could leave the machine. **The file was deleted after the run**;
it is gitignored and never existed in git.

- Installed app's Info.plist carried all three non-empty values.
- Launched with `-EBInstrumentationSmoke YES`. App log:

  ```
  [EB][smoke] analytics configured=true enabled=true; diagnostics configured=true enabled=true
  ```

- **Both SDKs initialised. No crash**, with both endpoints refusing connections —
  which is the point: an unreachable ingest host must not take the app down.
- Both wrote to the directories the app expects, which is what makes the
  teardown promises honest rather than hopeful:
  - PostHog → `Library/Application Support/com.nsantulli.econbyte/<key>/`
    (`posthog.anonymousId`, `posthog.queueFolder.uuid`, …)
  - Sentry → `Library/Caches/eb-sentry/` (`SentryCrash/`, `io.sentry/`), the
    app-owned directory `clearLocalEnvelopeCache()` deletes, which is why
    `guaranteesLocalCacheRemoval` may answer `true`.
- Settings → Privacy rendered the configured shape: **"Share Anonymous Usage
  Analytics" ON**, the Analytics ID beneath it, **no** crash-report switch, and
  a footer covering both what analytics carry and that crash reports are sent.

## Cleanup

Placeholder secrets file deleted, app uninstalled, simulator shut down,
DerivedData removed. A residual scan for the placeholder strings across the
worktree came back empty.
