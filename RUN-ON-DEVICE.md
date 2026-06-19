# Run EconByte in the Simulator (and on your iPhone)

EconByte is a SwiftUI economics card app. The iOS Simulator shows the complete
experience — swipe through cards, flip for examples, earn a streak. This is a
plain Xcode run, **not** TestFlight — nothing gets submitted to Apple.

## Simulator — the 30-second version (recommended first test)

1. `cd ~/Documents/GitHub/econbyte-app && git checkout main && git pull`
2. **Open the project:** `open EconByte.xcodeproj`
3. In Xcode's destination dropdown (next to the ▶︎ Run button) pick any
   **iPhone simulator** (e.g. iPhone 16 or 17).
4. Press **⌘R**.

That's it — home screen → today's 8-card set → swipe through cards → tap to
flip for real-world examples → after 5 cards a **Google Test Ad** fires.

## 👉 What to check
- Today's Set shows 8 cards; progress bar tracks as you advance.
- Tapping a card flips it to the real-world example + source.
- After 5 forward swipes, Google **Test Ad** fires (labeled "Test Ad"). The
  app never blocks on an ad — if none is ready, the next card just loads.
- Long-pressing a card bookmarks it; Bookmarks view shows saved cards.
- Browse Topics grid shows all 10 topics; tapping a topic enters a card session
  for that topic.
- Streak counter increments after ≥3 cards in a session.
- All cards show the disclaimer: "For educational purposes only — not financial
  or investment advice."
- Settings → toggle notifications → ATT dialog fires on first ad.

## Run on a real iPhone (optional)
1. Plug in + unlock your iPhone, tap **Trust This Computer**.
2. In Xcode: select the **EconByte** target → **Signing & Capabilities** →
   set **Team** to your Apple Developer team (`Q2DM9FSRL4`) with **Automatic**
   signing.
3. Pick your iPhone in the destination dropdown → **⌘R**.
4. First launch only: **Settings → General → VPN & Device Management →
   Developer App → Trust** the cert, then reopen the app.

## What this build is
Complete v1 of the app with the AdMob interstitial **wired and live on the
test unit**. 80 cards across 10 topics (starter deck — Owner reviews and
expands to 150 cards across 20 topics before submission). DEBUG/TestFlight
use **Google's public TEST unit** (safe — never your real account). Verified:
builds green for `iphonesimulator`; launches with no crash and logs
`[AdManager] interstitial loaded`; `GoogleMobileAds.framework` +
`PrivacyInfo.xcprivacy` present in built `.app`.

## Content note
The starter deck has 80 cards across 10 topics. Target before submission:
150 cards / 20 topics. Write cards using the workflow in `vault/ideas/specs/econbyte.md §9`.
Cards go in `EconByte/Content/cards.json` — the app reads the bundle at launch;
no server, no update needed. Add the 10 remaining topics following the same JSON
schema already in the file.

## Going live with ads — the 2 IDs you must supply
Real Dudley AdMob IDs are wired for RELEASE builds:

| # | What | Where | Value |
|---|---|---|---|
| 1 | AdMob App ID | `EconByte/Info.plist` → `GADApplicationIdentifier` | `ca-app-pub-9950526548980224~6219329532` |
| 2 | Interstitial ad unit | `EconByte/Services/AdManager.swift` (Release) | `ca-app-pub-9950526548980224/9740067293` |

DEBUG builds always use Google's public test unit — intentional.

## Resubmit after IAP rejection (build 3+)

Apple rejected build 2 (Guideline 2.1) because IAP taps appeared unresponsive.
Code fixes in build 3:

- All IAP entry points show loading, retry, and error alerts (no silent failures).
- Settings → **Unlock All Topics** is now tappable (opens paywall).
- Paywall disables the buy button until StoreKit products load.
- Interstitials present from the key window's root VC (iPad-safe).

### Owner checklist before resubmitting

1. **Paid Apps Agreement** — Account Holder accepts it in ASC → Agreements, Tax, and Banking.
2. **Both IAP products exist and are complete** in ASC → In-App Purchases:
   - `com.nsantulli.econbyte.unlockall` — Unlock All Topics ($0.99 non-consumable)
   - `com.nsantulli.econbyte.removeads` — Remove Ads ($0.99 non-consumable)
3. **IAP review screenshot uploaded for each product** (paywall for unlockall; Settings Remove Ads row for removeads).
4. **Attach both IAPs to version 1.0** on the version page before submitting build 3.
5. **Sandbox test** on a real device: tap locked topic → paywall → Unlock All → purchase sheet appears; Settings → Remove Ads → purchase sheet appears; Restore Purchases works.
6. **App Review Notes** (paste into ASC):
   ```
   EconByte is freemium: Inflation + Interest Rates are free. Two $0.99 non-consumable IAPs:
   • Unlock All Topics — tap any locked topic in Browse Topics, or Settings → Unlock All Topics
   • Remove Ads — Settings → EconByte Pro → Remove Ads
   Restore Purchases is in Settings and on the paywall. Paid Apps Agreement is active.
   ```
7. Archive **build 3** from `main`, upload, submit for review.

Full ASC field values: `~/Documents/GitHub/Dudley-Development/vault/launch/econbyte/runbook.md`
