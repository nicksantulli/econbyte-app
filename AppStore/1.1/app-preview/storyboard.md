# EconByte 1.1 — App Preview storyboard

**Status:** storyboard only. The video is **DEFERRED** — Task 6a did not produce
an `.mov`. See "Production status" below.

**Source of truth:** design section 13.3. Every beat below is a real screen of
the 1.1 release candidate (marketing version 1.1, build 6), captured on the same
device class as the storefront screenshots (iPhone 17 Pro Max, 1320×2868,
portrait).

**Hard constraints carried from the spec**

- Portrait, 20–25 seconds, App Store preview specification for the 6.9" iPhone
  class (1080×1920 or 886×1920 accepted; capture at device resolution and
  conform).
- Actual UI only. No mock frames, no composited screens, no motion the app
  cannot perform, no simulated taps that do not correspond to real gestures.
- Readable burned-in captions; the preview must work with sound off, and audio
  carries no information the captions do not.
- No ad, no payment sheet, no permission prompt, no rating prompt on screen.
- No investment or performance claim, in caption, voice or on-screen text.

## Beats

| Time | Screen (real app state) | On-screen caption | Notes |
|---|---|---|---|
| 0–3s | Card front, Inflation card 1 of 8 ("What Inflation Measures") | "Why does the same cart cost more?" | Open on a real question tied to an audited card. No logo card, no title screen — the app is on screen from frame one. |
| 3–8s | Home → tap **Start →** → card mode opens at 1 / 8 | "Start today's set. Eight cards." | Shows the daily-learning job, not the card count. Real tap, real transition. |
| 8–13s | Card flips to the back: the grocery-cart example and the FRED CPI source line | "Flip for a real example — with its source." | The source line must stay legible for at least 2 seconds; this is the differentiating claim. |
| 13–18s | Tap **Next** through the last cards → session complete with streak | "Finish the set. Keep the streak." | Capture with the consent panel already dismissed (it appears once, after the first completed set) so the frame is the plain completion state. |
| 18–25s | Home scrolled to **BROWSE TOPICS**, showing free and locked tiles, ending on the grid | "15 topics. Two free." then "Learn economics in five minutes." | Locked tiles must remain visible and readable: the preview must not imply that all 15 topics are free. Close on the closing line held for ~2 seconds. |

## Truth checks before the preview may be published

1. Topic tiles on screen show exactly 15 topics, with Inflation and Interest
   Rates unlocked and the remaining 13 showing the lock and "Unlock to view".
2. The counter reads `1 / 8`, matching the eight-cards-per-topic curriculum.
3. The card back shows a real source line from `curriculum-v1.1.json`; it is not
   a placeholder or an edited string.
4. No frame shows a debug control, a StoreKit test purchase sheet, an
   interstitial, or a notification permission dialog.
5. The educational-use disclaimer is visible in at least the two card beats.

## Production status

Not produced in Task 6a. Producing it needs a screen recording of the release
candidate plus caption compositing, which is a separate media pass with its own
review. Recorded as an open item for Task 6b / the Owner:

- **Deferred:** record the five beats from build 6 on the 6.9" simulator
  (`xcrun simctl io <udid> recordVideo`), conform to the App Store preview
  specification, add the captions above, and attach one preview per localized
  product page.
- A preview is optional for submission. Version 1.1 can ship with screenshots
  alone; the preview can be added to the live listing afterwards without a new
  binary.
