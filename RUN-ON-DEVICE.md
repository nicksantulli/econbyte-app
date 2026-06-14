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
The app ships with **placeholder** ad IDs. Before the RELEASE build serves
*real* ads (and earns), create these in your AdMob console and hand them back:

| # | What to create in AdMob | Where it goes | Current placeholder |
|---|---|---|---|
| 1 | **AdMob App ID** for "EconByte" (`ca-app-pub-…~…`) | `EconByte/Info.plist` → `GADApplicationIdentifier` | Google TEST app id `…3940256099942544~1458002511` |
| 2 | **Interstitial ad unit ID** (`ca-app-pub-…/…`) | `EconByte/Services/AdManager.swift` → RELEASE branch of `adUnitID` | `ca-app-pub-XXXXXXXXXXXXXXXX/YYYYYYYYYY` |

Until you swap #1 and #2 in, RELEASE builds show **test** ads (fine for
review, earns $0). DEBUG/TestFlight always use the test unit — intentional.
