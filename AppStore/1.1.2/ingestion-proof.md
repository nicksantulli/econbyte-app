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

---

# Addendum — build 11 re-proof (2026-09-06)

The proof above was run from `feat/econbyte-instrumentation`, where analytics
shipped **on**. The reconciled build is **opt-in**, so the smoke hook was
changed to force consent on rather than merely clear a stored opt-out
(`EconByteApp.applyInstrumentationSmokeIfRequested`) — which means the proof had
to be re-run, or it would have been proving a code path that no longer exists.

- Build under test: `EconByte.app`, `1.1.2` / **build 11**, **Debug**, iOS
  Simulator, from `release/econbyte-1.1.2`
- Simulator: `EB11-smoke`, iPhone 17, iOS 26.5 — created for this run and
  deleted immediately after
- Launch arguments: `-skipStudioIntro -EBInstrumentationSmoke YES
  -AllowAnalyticsInDebug YES` (plus `-EBInstrumentationCrash YES` for run 2)

## Run 1 — consent forced on, transports live

The app's own resolved-state line, from `log stream` on the simulator:

```
[EB][smoke] instrumentation smoke: forcing analytics on for this run
[EB][smoke] context: allowFlag=true unitTest=false automation=true debugBuild=true suppressed=false
[EB][smoke] analytics configured=true enabled=true distinctId=<redacted>; diagnostics configured=true enabled=true
```

`automation=true` (from `-skipStudioIntro`) with `suppressed=false` is the
important pair: the explicit allow flag is the only thing lifting suppression,
exactly as `InstrumentationContext` documents.

The app then opened an HTTPS connection to `us.i.posthog.com` and issued
`POST /batch`, observed at the network layer in the same log.

**What this does not prove:** that PostHog *stored* the batch. The earlier proof
read PostHog's own `batch sent successfully` line out of the Xcode console; that
line is `print`ed by the SDK and does not reach `log stream`, and **no PostHog
MCP server is available in this session**, so the vendor side could not be read
back. The Sentry half below was read back through the vendor's own API.

## Run 2 — deliberate crash, ingested and read back through Sentry

```
[EB][smoke] deliberate test crash in 3s (DEBUG only)
[EB][smoke] crashing now
```

The process died; the next launch uploaded the report to
`o4511700939833344.ingest.us.sentry.io`. Read back through the Sentry MCP
against org `dudley-development`, project `econbyte`:

- Issue **ECONBYTE-1** — `EXC_BREAKPOINT: EconByteApp.swift:113: Fatal error:
  EBInstrumentationCrash: deliberate crash to verify Sentry ingestion`
- 2 events (the build-10 lane's, and this one), last seen at the moment of the
  run

The issue was then **resolved** through the same MCP, with the reason recorded
on its activity feed, so the project's unresolved queue means real user impact
again. The crash path is `#if DEBUG` only and is compiled out of the shipped
archive.
