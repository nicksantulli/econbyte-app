# EconByte 1.1.3 (build 15) — App Review rejection, Guideline 2.1: ATT prompt not found

Date: 2026-09-15. Lane: manager-loop Phase 14. Status of 1.1.3: **not resubmitted** — Owner decision
(2026-09-15): EconByte waits for 1.1.4, so the fix landed on the 1.1.4 line (`claude/econbyte-114-pro`).
A narrow 1.1.3 port exists on `claude/econbyte-113-att-fix` and is parked (never built for upload, never uploaded).

## What App Review said

Guideline 2.1 – Information Needed. The app uses AppTrackingTransparency, but the reviewer could not locate
the permission request on **iPadOS 27.0 and iOS 27.0** (iPad Air 11-inch (M3), iPhone 17 Pro Max).
Completing a session and tapping **"Done"** or **"Browse More Topics"** did not trigger it. For future
submissions Apple wants a physical-device screen recording, from a fresh install, showing the ATT prompt
before any tracking data is collected and the flow after it, attached to the App Review notes.

## What build 15 actually did

Build 15 (`claude/econbyte-packs` @ 3413f83) had exactly one ATT call site:
`SessionCompleteView.finish()` → `EconMonetization.resolveTrackingAuthorizationIfNeeded()` →
`EconTrackingAuthorization.requestAuthorization()` → `ATTrackingManager.requestTrackingAuthorization`.

The prompt appeared only if **all** of these held at the moment the reader left a completed set:

| # | Condition (build 15) | Where | Visible to a reviewer? |
|---|---|---|---|
| 1 | A card set had been completed and "Done"/"Browse More Topics" tapped | `SessionCompleteView.finish()` | yes |
| 2 | `econ.ads.trackingPromptRequested` not yet set — **written before awaiting iOS and never cleared**, even when iOS showed nothing | `EconMonetization.resolveTrackingAuthorizationIfNeeded` | no |
| 3 | No verified Remove Ads entitlement (`Transaction.currentEntitlements`, which follows the Apple ID / sandbox account across reinstalls) | `shouldRequestTrackingAuthorization` → `entitlements.adsSuppressed` | no |
| 4 | Device Region outside the EEA/UK and determinable (DUD-224; unknown fails closed) | `shouldRequestTrackingAuthorization` → `region().permitsAdRequests` | no |
| 5 | iOS actually presented the dialog when asked. It returns `.notDetermined` **without UI** when the app is not foreground-active or a presentation/transition is in flight; the call was made from a button inside the card-mode `fullScreenCover`, on the same turn the screen hides its primers and just before the cover is dismissed | `SessionCompleteView.finish()` | no |

Upgrade note: the build-13/15 gate `adRequestsPermitted = status.isDecided || didRequestTrackingPrompt` also let the
ad SDK start after an ask iOS never presented — i.e. with no answer on file.

## Reproduction (this Mac)

- Build-15 source, Debug, fresh install + `xcrun simctl privacy <udid> reset all com.nsantulli.econbyte`, US region,
  no purchases. UI test `testReproReviewerFlowATTAtSetExit` (throwaway worktree, never committed): launch → complete a
  set → tap Done → wait for the springboard ATT alert.
- **iPhone 17 (iOS 26.5): the ATT alert appeared.** **iPad Air 11-inch (M3) (iOS 26.5, iPhone-compatibility mode —
  EconByte is `TARGETED_DEVICE_FAMILY = 1`): the ATT alert appeared.** Evidence:
  `~/dudley-evidence-retention/econbyte/1.1.3-att-fix/repro-b15-{iphone17,ipadair11m3}.{log,xcresult}` and
  `repro-b15-screens/`.
- No iOS/iPadOS 27 simulator runtime is installed (Xcode 26.5, iOS 26.5 only), so the reviewer's OS could not be
  reproduced.

So the code path works in the clean case; what failed on the review devices was one of the invisible conditions.

## Root cause

**The prompt was not guaranteed to appear on a fresh install.** It was deferred to a later moment (a set exit) and
made conditional on runtime state App Review cannot see (rows 2–5), and one miss was permanent (row 2). The rejection
text cannot tell us which condition fired; each of these produces exactly what the reviewer reported, including "both
Done and Browse More Topics" (the second exit is silent by design once the first has been spent or skipped):

1. **A silent non-presentation spent the one ask (rows 2 + 5).** If iOS 27 declined to present at the first exit
   (presentation in flight / not yet active after the cover interaction), build 15 recorded the prompt as asked and
   never asked again. Plausible on a new OS; not reproducible on 26.5.
2. **The review account owned Remove Ads (row 3).** App Review has had EconByte's Remove Ads IAP since 1.1 and 1.1.3
   was submitted together with new IAPs; a sandbox account that bought it on any earlier review keeps the entitlement
   on a fresh install, and build 15 then never asks by design.
3. **The review device's Region was EEA/UK or undeterminable (row 4)** — never asks by design.

**Contributing: stale App Review notes.** The 1.1.3 version carried build 13's notes verbatim ("Build 13 adds the App
Tracking Transparency request…", read back from ASC `appStoreReviewDetails` 9b887c28): they sent the reviewer to the
set exit and relegated the region/Remove Ads exceptions to a paragraph.

**Ruled out:** iPad compatibility mode (repro passed; no idiom-specific code in the gate); the 1.1.3 first-open
consent card (it never calls ATT and is dismissed before Home is usable); the anchored banner (gated behind the ATT
decision).

## Fix (Owner-ordered pattern, hardened) — landed on the 1.1.4 line

`EconByte/Services/FirstLaunchPermissions.swift` (1.1.4 already moved ATT to first launch in Phase 10; this lane
hardens it against every row above):

- **When:** after the studio intro, only when `EconPromptPresentationEnvironment.isReadyForSystemPrompt` — app
  `.active`, a foreground-active scene with a key window, **no view controller presented over the root, no transition
  in flight** (SwiftUI sheets/covers/alerts present through UIKit).
- **Retry, same run:** an ask that returns `.notDetermined` (iOS showed nothing) is retried up to 3 times, 1 s apart.
- **Retry, next activation:** the app calls the coordinator on every `scenePhase == .active` once the intro has gone;
  anything answered is a no-op, anything still `.notDetermined` is asked.
- **No spendable flag:** `shouldRequestTrackingAuthorization` is `status == .notDetermined`; the persisted
  `econ.ads.trackingPromptRequested` is evidence only.
- **Every install is asked** (regardless of Remove Ads, Pro, EEA/UK or unknown region): the binary links an ad SDK
  whose privacy manifest declares tracking and the App Privacy label says "used to track", so the prompt must be
  findable on every review device and account. Ads themselves are still never served in the EEA/UK or to Remove
  Ads/Pro readers.
- **Ads wait for a real answer:** `adRequestsPermitted` is status-only, and the launch hold keeps the SDK stopped until
  the flow has run; notifications are never asked before ATT has an answer.
- Notifications: asked right after ATT; an ask iOS did not present (status still `.notDetermined` afterwards) writes
  nothing and is retried the same way.

## For the 1.1.4 submission (orchestrator / Owner)

- Replace the App Review notes entirely (the build-13 text must not ride again). Suggested text:
  > The App Tracking Transparency request appears on first launch of a fresh install, about four seconds after the
  > app opens (after the short "Made by Dudley Development" animation), before any content is opened and before
  > any ad is requested. Apple's notification permission request follows it. No sign-in is needed. If it does not
  > appear, check Settings > Privacy & Security > Tracking > "Allow Apps to Request to Track" is on (when it is off,
  > iOS answers for the app without showing the dialog). A screen recording from a physical device is attached.
- Record on the Owner's iPhone: delete EconByte, install the 1.1.4 build, confirm the Tracking toggle above is on,
  start the recording, open the app, let the intro finish, show the ATT prompt, answer, show the notifications
  prompt, answer, then open a card and Settings.

## Verification

See `~/dudley-lane-briefs/reports/phase14-econbyte-113-att-fix.md` for the test runs (unit counts, fresh-install
UI runs on iPhone 17 and iPad Air 11-inch (M3) simulators) of the 1.1.4 hardening.
