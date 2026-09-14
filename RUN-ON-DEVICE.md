# Run EconByte in the Simulator (and on your iPhone)

EconByte is a SwiftUI economics card app: a short daily set of cards, plain
language on the front, a sourced real-world example on the back. The iOS
Simulator shows the complete experience. This is a plain Xcode run, **not**
TestFlight — nothing gets submitted to Apple.

> **Which version this describes.** This guide describes the **1.1 growth
> branch** (`codex/econbyte-1.1`), which is what is in this working copy. The
> project still declares `MARKETING_VERSION 1.0` / build `3`; bumping the version
> and build number is Task 6's job, not something to change while testing.

## Simulator — the 30-second version (recommended first test)

1. `cd ~/Documents/GitHub/Dudley-Development/workspaces/econbyte-ios`
2. `git checkout codex/econbyte-1.1`
3. **Open the project:** `open EconByte.xcodeproj`
4. In Xcode's destination dropdown (next to the ▶︎ Run button) pick any
   **iPhone simulator**.
5. Press **⌘R**.

The scheme already points at `EconByte.storekit`, so you can buy and restore
both in-app purchases in the Simulator without App Store Connect.

That's it — Dudley studio intro → home screen → today's 8-card set → advance
through cards → tap a card to flip it for the sourced example.

## 👉 What to check

**Core loop**
- Today's Set shows 8 cards; the progress bar tracks as you advance.
- Tapping a card flips it to the real-world example plus its source.
- The **bookmark icon** in the card's top-right corner saves a card (it is a
  button — there is no long-press gesture). Bookmarks view lists saved cards and
  can replay them as a deck.
- Browse Topics shows **15 topics**. Inflation and Interest Rates are free;
  the other 13 show a lock and open the paywall until Unlock All Topics is owned.
- The streak counter credits a day once you have seen **3 cards that day**.
- Every card shows the disclaimer: "For educational purposes only — not
  financial or investment advice."

**Ads** (design section 9.3, plus the 1.1.3 banner)
- **No interstitial ever interrupts a card.** The one interstitial placement is
  the return from a **completed set** to Home. The earliest one can appear is
  the exit of your **second** completed set, because a fresh install must
  complete two sets before any interstitial is eligible.
- Interstitial caps (audited 2026-09-14): at most two per foreground session,
  two per calendar day, fifteen minutes apart, and one completed set apart.
- **Anchored banner (1.1.3):** a small adaptive banner sits at the bottom of
  Home and under the card in a card session. It reserves no space until an ad
  has loaded, so a no-fill is invisible rather than a blank strip.
- DEBUG builds use Google's public **test** units (interstitial and banner), so
  anything you see is labelled "Test Ad" and never touches the real account.
- No fill or a load failure is silent — you just land back on Home.
- **App Tracking Transparency (1.1.2 build 13):** the system tracking dialog
  is asked **once per install**, from the exit of your **first completed set**
  (tap Done or Browse More Topics), and never at launch. No ad — not even the
  banner, not even an SDK start — is requested before you have answered. Every
  answer moves the app forward; every ad request stays non-personalized
  whatever you answer. See `CONTENT-DECISIONS.md` D2 addendum.
- Buy **Remove Ads** and the ad SDK is never started at all — no interstitial,
  no banner, no tracking dialog. Same for a device whose region is in the EEA/UK
  (DUD-224).
- A fresh Simulator run therefore shows **no banner until after your first
  completed set** (the tracking decision comes first); from the next launch on,
  the banner is on Home as soon as Google's test unit fills.

**Consent, reminders, and rating**
- **First open (1.1.3, keyed builds only):** as the Dudley studio intro fades,
  a card asks once whether to share anonymous usage analytics (and crash
  reports, when the build carries a Sentry DSN). Two equal buttons; "Not now"
  is a real, remembered answer. Both toggles stay in Settings → Privacy & Data
  permanently. A plain Simulator run is unkeyed by design
  (`InstrumentationContext`) and shows **no card**; to see it, launch with
  `-AllowAnalyticsInDebug` on an erased simulator. `-EBSkipConsentPrompt`
  suppresses it for UI tests and screenshots.
- No permission dialog appears on first launch — notifications and tracking are
  asked later, in context.
- If the build is unkeyed (so the first-open card did not ask), Session
  Complete offers the two data choices after your **first completed set** as
  separate toggles, both off — the 1.1 primer. It never asks an install the
  first-open card already asked, and vice versa.
- After your **next completed set**, the reminder primer appears. The iOS
  notification dialog appears only if you tap **Turn On Reminders** (or the
  Settings toggle). Enabling schedules one reminder at 7:00 p.m. local; turning
  it off removes it immediately.
- The rating prompt (review-rules-v2, 1.1.3) is **never asked on the first
  open**. From the **second launch** on, the first completed set of five or
  more cards is the moment — unless the same session carried an ad, a purchase
  or restore, the consent card or primer, a system prompt (notifications or
  tracking), a paywall, an error alert, or a crash recovery, in which case it
  waits for a later session. Once per app version, attempts at least 120 days
  apart, at most two a year. A UI-test or unit-test process never shows the
  sheet at all.
- Settings → **Rate EconByte** opens the App Store review sheet for app ID
  `6780714383`.

**Purchases**
- Settings → **Remove Ads** and **Unlock All Topics** are two independent
  one-time purchases. Buying one must not affect the other.
- Tapping a locked topic opens the paywall; **Restore Purchases** is on both the
  paywall and in Settings.
- DEBUG builds also expose a "Debug — test only" section with entitlement
  toggles, so you can see the locked vs unlocked experience without a purchase.
  That section is compiled out of Release.

## Useful launch arguments (DEBUG only)

Add these under Product → Scheme → Edit Scheme → Run → Arguments:

| Argument | Effect |
|---|---|
| `-skipStudioIntro` | Skips the ~4s Dudley studio intro |
| `-econResetGrowthState` | Resets to a fresh-install posture: consent, reminders, ad counters, review progress, card state, and streak |

Both are used by the UI test suite. Neither exists in a Release build.

## Run on a real iPhone (optional)

1. Plug in and unlock your iPhone, tap **Trust This Computer**.
2. In Xcode: select the **EconByte** target → **Signing & Capabilities** →
   set **Team** to your Apple Developer team (`Q2DM9FSRL4`) with **Automatic**
   signing.
3. Pick your iPhone in the destination dropdown → **⌘R**.
4. First launch only: **Settings → General → VPN & Device Management →
   Developer App → Trust** the cert, then reopen the app.

Real StoreKit purchases need a sandbox Apple ID; the local `.storekit` file only
applies to Simulator runs launched from this scheme.

## Content

The 1.1 release will ship exactly **120 cards across 15 topics** — two free
(Inflation, Interest Rates) and thirteen covered by the existing Unlock All
Topics entitlement at no extra charge.

Cards live in `EconByte/Resources/curriculum-v1.1.json` and are loaded through
`CurriculumCatalog.loadValidated()`. The app reads the bundle at launch — no
server, no content update needed. The old `EconByte/Content/cards.json` (the
80-card 1.0 deck) was **deleted** in the 1.1 growth commit; do not recreate it.

Editing content:

1. Follow the schema in `EconByte/Content/CurriculumCatalog.swift` — every card
   needs stable `cardID`/`topicID`, prose, disclaimer, difficulty, a full
   `source` block, and `editorial` status plus reviewer.
2. **Never reuse a `cardID` for a different concept.** Bookmarks and per-card
   state are keyed on it. If a re-sourced card changes what it teaches, set
   `supersedes` and `supersedesNote`.
3. Run `EconByteTests/CurriculumCatalogTests` — it is the machine validator and
   fails closed on counts, duplicate IDs, access drift, stale claims, and
   prohibited financial-advice framing.

Any change to the 120/15 counts or the free/paid split is a product decision,
not an editing task.

## Running the tests

```
xcodebuild test -project EconByte.xcodeproj -scheme EconByte \
  -destination 'platform=iOS Simulator,name=<your simulator>'
```

- `EconByteTests/CurriculumCatalogTests` — content validator.
- `EconByteTests/GrowthSystemsTests` — purchases, ads, telemetry, diagnostics,
  review, notifications, and the catalog runtime switch.
- `EconByteUITests` — core-loop smoke.
- `EconByteUITests/GrowthFlowTests` — consent, reminders, purchase controls, and
  the completed-set exit.

Never run two `xcodebuild` invocations at once on this machine.

## Ad identifiers

The Release identifiers carried over from 1.0 unchanged. Nothing was invented.

| # | What | Where | Value |
|---|---|---|---|
| 1 | AdMob App ID | `EconByte/Info.plist` → `GADApplicationIdentifier` | `ca-app-pub-9950526548980224~6219329532` |
| 2 | Interstitial unit (Release) | `EconByte/Services/EconMonetization.swift` → `EconAdUnit.release` | `ca-app-pub-9950526548980224/9740067293` |
| 3 | Interstitial unit (Debug) | `EconAdUnit.debug` | Google's public test unit |

**These Release IDs are format-valid but have never been confirmed against the
AdMob console.** Confirming them, and confirming the console frequency caps are
at least as conservative as the in-app caps, is a pre-submission Owner action —
see `CONTENT-DECISIONS.md` D6.

## Before any submission

`CONTENT-DECISIONS.md` records every decision where the implementation diverges
from the written design, and lists the items the Owner must rule on. Two are
submission blockers:

1. **Privacy manifest and App Store privacy answers** still describe 1.0's
   tracking behaviour. They must be re-derived from the 1.1 archive privacy
   report before submitting (D2).
2. **AdMob identifiers** must be confirmed against the console (D6).

App Review notes should state the 2-free/13-paid model, that the two one-time
purchases are independent, the exact paths to both purchase buttons and Restore
Purchases, the single contextual ad placement, the privacy choices, and the
notification opt-in path.

Full ASC field values and the release runbook:
`~/Documents/GitHub/Dudley-Development/vault/launch/econbyte/runbook.md`

## History — the 1.0 build 3 IAP rejection

Kept for context. Apple rejected build 2 under Guideline 2.1 because IAP taps
appeared unresponsive. The fixes shipped in build 3 and still hold in 1.1:

- All IAP entry points show loading, retry, and error alerts — no silent failures.
- Settings → Unlock All Topics is tappable and opens the paywall.
- The paywall disables the buy button until StoreKit products load.
- Interstitials present from the key window's root view controller (iPad-safe).

One label changed in 1.1: the Settings purchases section and the paywall title
are no longer "EconByte Pro". An umbrella label implies the two products are a
bundle, which the design forbids — the section is now "Purchases" (D4). Review
notes written against the old wording need updating.
