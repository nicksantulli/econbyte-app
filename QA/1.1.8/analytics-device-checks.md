# EconByte 1.1.8 (25) — analytics device checks

Run 2026-10-01 17:55–17:59 UTC on the iPhone 17 Pro Max simulator (iOS 26.5), Debug build of
`release/econbyte-1.1.8` @ bbf9178 (the submitted source), launched with
`-EBInstrumentationSmoke -AllowAnalyticsInDebug` against the live PostHog project. Fresh simulator
(erased first). PostHog distinct id: `01a0f89b-d5bc-77a4-b7fc-724752ea5f94`.

**Delivery proof is device-side**: the PostHog SDK debug log (`Sending batch of N records` →
`batch sent successfully`) plus the app's DEBUG `[EB][telemetry] handed to PostHog:` line. The
PostHog-side query was **not** run from this lane (no PostHog MCP or personal API key in the lane's
session). To confirm in PostHog, filter the distinct id above between 17:55 and 17:59 UTC.

| # | Check | Result | Evidence |
|---|---|---|---|
| 0 | First launch: ATT prompt, then notifications prompt | PASS | ATT on first launch; after Allow, Apple's notifications prompt followed. |
| 1 | Long session (>40 events) | PASS | One process, 17:55:57–17:57:48Z: **44 events** handed. Today's set (8 cards, 18 bookmark toggles, a flip) ended with the rating ask: the set-end flush drained **36 queued events in one flush (20 + 16)**, including `session_ended_v1`, `review_prompt_eligible_v1` and `review_request_attempted_v1` — the late-session events that through 1.1.7 sat behind the first 20. SDK sent 20 + 16 + 8, each `batch sent successfully`. |
| 2 | Force-quit (background, then kill) and relaunch | PASS | Review set: 4 bookmarks + 3 cards in memory, Home, `simctl terminate` at 17:57:48Z. The background flush handed all 8 (`session_started_v1`, 4 × `bookmark_changed_v1`, 3 × `card_advanced_v1`) and the SDK sent them (`Sending batch of 8` → success) before the kill. Relaunch: same distinct id. |
| 3 | Offline, then online | PASS for an outage spanning a background (see caveat) | Outage simulated without touching the Mac's network: the same Debug app re-signed ad hoc with `EBPostHogHost = http://127.0.0.1:9`. 9 events (launch, `session_started_v1`, 2 bookmarks, 2 cards) handed at 17:58:24.9Z on background; 2 failed sends, then the app was suspended; 9 records stayed on disk with their **capture** timestamps (17:58:07.623Z … 17:58:23.432Z, not the hand-off time). Reinstalled the real build (same container), relaunched at 17:58:55Z: `Sending batch of 9 records` → `batch sent successfully`; queue empty. |
| 3 caveat | Longer outage with the app open | Not covered | PostHog SDK 3.71.4 drops its whole queue on the 4th consecutive failed send to a reachable-but-failing host (seen in the Last Human run the same day). A true offline state pauses the queue without counting retries, per the SDK source, but turning the simulator's network off needs a change to the Mac's network settings that this lane may not make. Pre-existing SDK behaviour, not changed by this update. |

Simulator erased after the checks.
