# EconByte 1.1.2 — real-ingestion proof (PostHog + Sentry)

This IS the ingestion proof that `instrumentation-smoke.md` said was still
outstanding. Real credentials, live projects, one Simulator, verified by reading
the data back out of both vendors rather than by trusting a local log.

- Build under test: `EconByte.app`, `CFBundleShortVersionString 1.1.2`,
  `CFBundleVersion 9`, **Debug**, iOS Simulator, from `feat/econbyte-instrumentation`
  at commit `1452288`
- Simulator: `EB-Instr-17` / `E1CA852C-DAC0-4E63-BB48-8CC46B5755C4`, iPhone 17,
  iOS 26.5 — erased before the run
- Date: 2026-09-05 · Xcode 26.5 (17F42)
- Projects: PostHog `econbyte` (**594265**), Sentry `econbyte`
  (org `dudley-development`)
- Launch arguments: `-EBInstrumentationSmoke YES -AllowAnalyticsInDebug YES`

`-AllowAnalyticsInDebug` is required from 1.1.2: without it a Debug build
resolves no credentials at all and both SDKs stay dormant. Passing it is the
whole point of the flag — see README "No production analytics from test runs".

Raw console logs are sealed under
`~/dudley-evidence-retention/econbyte/1.1.2/ingestion/`.

---

## Run 1 — analytics (7 events, sent and acknowledged)

Resolved state, logged by the app itself:

```
[EB][smoke] context: allowFlag=true unitTest=false automation=false debugBuild=true suppressed=false
[EB][smoke] analytics configured=true enabled=true distinctId=01a07372-0694-7a1e-bc95-e8f1213452e3; diagnostics configured=true enabled=true
```

The app was driven by hand (dismiss the rating prompt → Start → flip a card →
Next) and then backgrounded, which is what flushes the queue. PostHog's own
debug log:

```
[PostHog] Queued event 'app_opened_v1'. Depth: 1
[PostHog] Queued event 'products_loaded_v1'. Depth: 2
[PostHog] Queued event 'review_request_attempted_v1'. Depth: 3
[PostHog] Queued event 'ad_load_finished_v1'. Depth: 4
[PostHog] Queued event 'session_started_v1'. Depth: 5
[PostHog] Queued event 'card_flipped_v1'. Depth: 6
[PostHog] Queued event 'card_advanced_v1'. Depth: 7
[PostHog] Sending batch of 7 records to PostHog
[PostHog] batch sent successfully.
```

- **Sent at** ~2026-09-05 **21:27:5x UTC** (15:27:5x MDT)
- **distinct_id on the wire**: `01a07372-0694-7a1e-bc95-e8f1213452e3`

Three things this settles beyond "events arrived":

1. **The id is real.** That distinct id is PostHog's own anonymous id, read back
   with `getDistinctId()` and displayed verbatim in Settings → Privacy. It has
   the same shape as the ids the review observed on the wire for Table Talk
   (`01a06e5a-…`) and Last Human (`01a06e9a-…`) — i.e. the SDK's id, which is
   what the previous build was NOT showing.
2. **The batch is exactly ours.** Seven events, all allowlisted, nothing else.
   No `$pageview`, no "Application Opened", no autocapture of any kind — the
   `TelemetryConfiguration` switches are doing what they claim on a live SDK.
3. Integrations the config disables really are skipped:
   `PostHogRageClickIntegration`, `PostHogPushNotificationSubscriptionIntegration`
   and `PostHogPushNotificationOpenIntegration` all logged
   "requires swizzling but enableSwizzling is disabled in config".

> Not exercised: `session_ended_v1` (the deck was backgrounded rather than
> finished) and the purchase/ad-impression events, which need a real StoreKit
> sheet and a real ad fill.

## Run 2 — the deliberate crash

Launched with `-EBInstrumentationCrash YES -AllowAnalyticsInDebug YES`:

```
[EB][smoke] deliberate test crash in 3s (DEBUG only)
[EB][smoke] crashing now
EconByte/EconByteApp.swift:88: Fatal error: EBInstrumentationCrash: deliberate crash to verify Sentry ingestion
```

The Sentry startup log in the same run carries the crash-only proof that
matters most, because this is the switch 1.1.2 fixed:

```
[Sentry] Not going to enable SentryAutoSessionTrackingIntegration because enableAutoSessionTracking is disabled.
[Sentry] Not going to enable SentrySessionReplayIntegration because sessionReplaySettings is disabled.
[Sentry] [SentryCrashIntegrationSessionHandler] No current session found to end.
```

**No session envelope is created or sent in any of the three runs.**

## Run 3 — relaunch uploads the crash

```
[Sentry] [SentryCrash:333] Sending 1 crash reports
[Sentry] [SentryHttpTransport:424] Envelope sent successfully!
[Sentry] [SentryHttpTransport:379] Deleting envelope and sending next.
[Sentry] [SentryHttpTransport:335] No envelopes left to send.
```

### Read back from Sentry

| | |
|---|---|
| Issue | **ECONBYTE-1** |
| Event id | **`d0384c04e4f8450686e5bfb035aed840`** |
| Title | `EXC_BREAKPOINT: EconByte/EconByteApp.swift:88: Fatal error: EBInstrumentationCrash: deliberate crash to verify Sentry ingestion` |
| Occurred | 2026-09-05T21:28:21Z |
| Release / dist | `com.nsantulli.econbyte@1.1.2+9` / `9` |
| Occurrences | 1 |
| **Users impacted** | **0** |
| Stack trace | present, 21 threads, crashed thread identified |

**Users impacted = 0, and neither `user.id` nor `user.ip` is stored** — the
live `beforeSend` really does remove the installation id sentry-cocoa stamps on
every event before the callback runs. No breadcrumbs, no extras, no screenshot,
no view hierarchy on the event.

### Two things the read-back turned up — see `app-privacy-answers.md`

1. Sentry stored `user.geo` (**US, Colorado Springs**), derived server-side from
   the request IP despite `infer_ip: never`. Probably a **Coarse Location**
   answer, and the label as drafted is silent on it.
2. Sentry adds its own tags during ingest (`app.device` device hash, `device`,
   `os`, `dist`, …) that no client-side allowlist can remove.

Both are pre-existing Sentry behaviour, not 1.1.2 code, and both are written up
in `app-privacy-answers.md` for the labels pass.

## Cleanup

App uninstalled, simulator erased and shut down, DerivedData removed. No
credential appears in any sealed log (checked for `phc_`, the DSN host and any
`projectToken`/`apiKey` echo).
