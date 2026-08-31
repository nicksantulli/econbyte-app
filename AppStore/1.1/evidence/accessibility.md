# EconByte 1.1 — accessibility verification

**Version under test:** marketing version 1.1, build 6.
**Code state:** commit `edd00ae` (accessibility fixes) for the app target; the
storefront and evidence commits that follow it change no app source.
**Environment:** iPhone 17 Pro Max simulator, iOS 26.5 (23F77), 1320×2868 —
the 6.9" iPhone display class. Xcode 26.5 (17F42).
**Automated evidence:** `EconByteUITests/AccessibilityTests.swift`, five tests,
all passing; raw audit output retained at
`<retention>/accessibility-audit-raw.txt` (see `release-packet.json` for the
retention path).

Every row states the method actually used. Where a condition could not be
verified on this host, the row says so and names the owner — no condition is
marked pass on inspection alone when it needed a run.

---

## 1. Conditions from design section 12

| # | Release condition | Result | Method |
|---|---|---|---|
| 1 | Card flip is a named accessibility action with announced front/back state, title, topic, position and source availability | **PASS (after fix)** | Was a **failure**: the flip was a bare `onTapGesture` on a container, so VoiceOver could not turn a card over at all. The card is now one accessibility element with `.isButton`, a default activation action and a named "Flip card" action. Asserted by `testCardAnnouncesFaceTopicAndPositionAndCanBeFlipped`, which reads the live label: `Inflation, card 1 of 8. Concept. What Inflation Measures. …` and, after activation, `… Real-world example. … Source: …` |
| 2 | Bookmark, close, Settings, purchase, restore, privacy and reminder controls have explicit labels, traits and values | **PASS (after fix)** | Settings gear and card-mode Close were icon/glyph-only with no label; the bookmark control had none. All three now carry labels ("Settings", "Close", "Bookmark card"/"Remove bookmark"). Asserted by `testIconOnlyControlsAreLabelled`; the remaining controls (Unlock All, Remove Ads, Restore Purchases, Privacy Policy, Daily Learning Reminder, both consent toggles) are text-labelled SwiftUI controls and are exercised by the audit test on the Settings screen. |
| 3 | Reading order: header, progress, card, source, actions, navigation | **PASS** | XCTest accessibility audit over Home, card front, card back and Settings reports no element-detection or ordering issues. The card is a single element, so its internal order is the announcement order asserted in row 1. |
| 4 | Dynamic Type works through accessibility sizes without clipped card content or hidden purchase disclosures | **PARTIAL — recorded, not changed** | See §3.1. The core loop and the purchase controls are proven operable at `UICTContentSizeCategoryAccessibilityXXXL` (`testCoreLoopSurvivesAccessibilityExtraExtraExtraLarge`, `testPurchaseControlsOperableAtLargestTextSize`), but the app's type is fixed-point and does not scale. |
| 5 | Reduce Motion replaces 3D card rotation with a cross-fade and suppresses decorative motion | **PASS (after fix)** | Was unimplemented. `CardView` now reads `\.accessibilityReduceMotion`: the rotation is dropped (`rotation3DEffect` degrees forced to 0) and the two faces cross-fade over 0.25s. The only other motion in the app is the button press scale (0.97) and the studio intro, neither of which is vestibular-triggering. Verified by code path plus a Reduce Motion simulator run (§2.3). |
| 6 | VoiceOver, Switch Control, Voice Control, keyboard navigation and Full Keyboard Access can complete the core flow | **PARTIAL** | VoiceOver-equivalent reachability is proven: every control in the core flow is an accessibility element with a label, and the one gesture-only interaction (the flip) is now an action. Switch Control, Voice Control and Full Keyboard Access were **not** driven end to end — they need an interactive session that this host cannot script. Owner/6b item, see §4. |
| 7 | Text and interactive controls meet contrast requirements | **FAIL — recorded, not changed** | See §3.2. Measured, not estimated. |
| 8 | No meaning depends on colour, motion or audio alone | **PASS** | Locked topics carry a lock glyph **and** the text "Unlock to view"; purchased rows read "Purchased ✓" in text; completion is stated in words ("Done", "You finished …"); the app plays no audio and no state is signalled by colour alone. |
| 9 | Touch targets are at least 44×44 points | **PASS (after fix)** | The audit flagged the card-mode Close glyph. Close and the card Bookmark control now carry `minWidth/minHeight: 44` with `contentShape(Rectangle())`. Remaining audit hit-region findings are the two non-interactive `ProgressView` indicators (§3.3). |
| 10 | Purchase and restore controls remain operable at the largest text size | **PASS** | `testPurchaseControlsOperableAtLargestTextSize` launches with `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL`, opens Settings and asserts Remove Ads is hittable and Restore Purchases reachable. |
| 11 | No App Store accessibility-label claim until the complete install-to-purchase task is manually verified | **HELD** | No accessibility claim appears in `AppStore/1.1/metadata.json` beyond describing the VoiceOver flip and Reduce Motion behaviour, both of which are verified above. No "accessible to everyone" style claim is made, and no ASC accessibility nutrition label is being requested in 6a. |

## 2. Task-specific verifications

### 2.1 Layout at the current iPhone width — PASS
Every primary state was rendered at 440×956 points (1320×2868) on iPhone 17 Pro
Max and inspected: Home (new and returning), the topic grid including locked
tiles, card front, card back, session complete with the consent offer, Home
after completion, and Bookmarks. The captures are the storefront screenshots in
`AppStore/1.1/screenshots/` with their hashes in `manifest.json`. No clipping,
no overlap, no truncated control.

### 2.2 Layout at 320 points — NOT VERIFIED ON THIS HOST
No 320-point device exists for iOS 16.6+: the narrowest supported iPhone is
375 points (SE 2nd/3rd generation, iPhone 13 mini), and 320 points is reachable
only through Display Zoom on those devices. Only one simulator device is
installed on this shared host (the 6.9" device), and the host was operating
against its 8 GiB build floor for the whole task, so adding a second runtime
device was not available. Static review found no fixed pixel widths in the
layout — the grid is two flexible columns, cards use `maxWidth: .infinity`, and
all body text is multiline — so no structural 320-point failure is expected, but
that is an expectation, not a measurement. **Owner/6b item.**

### 2.3 Dynamic Type and Reduce Motion runs
- Dynamic Type: the app was launched at `AccessibilityXXXL` twice (core loop and
  Settings) through the documented `-UIPreferredContentSizeCategoryName`
  override. Both flows completed; see §3.1 for what the runs prove and what they
  do not.
- Reduce Motion: exercised through the `accessibilityReduceMotion` environment
  path added in `edd00ae`. The cross-fade branch and the rotation branch keep
  `rotation` and `isFlipped` in step, so the announced face and the drawn face
  cannot disagree in either mode.

### 2.4 Offline, relaunch and migration
- **Offline / provider failure:** all 120 cards and 15 topics ship inside the
  binary (`curriculum-v1.1.json`, loaded by `CurriculumCatalog.loadValidated()`),
  so reading needs no network. The only network callers are StoreKit and the ad
  SDK, and both fail closed: the paywall renders a stated
  "Purchases are temporarily unavailable" message with a Try Again action rather
  than an empty screen, and the ad gate refuses to request when its
  preconditions are not met. Verified by running the release build with no
  StoreKit configuration attached, which is the same product-load failure the
  app sees offline.
- **Relaunch:** the app was relaunched repeatedly across the accessibility and
  screenshot runs; streak, card state and bookmarks persisted, and no launch
  showed a permission dialog (asserted by
  `GrowthFlowTests.testRemindersDefaultOffAndNoPermissionDialogOnLaunch`).
- **Migration from 1.0 content:** all 80 shipped 1.0 card identifiers and all 10
  topic identifiers are present in the 1.1 catalog, in the same topic order
  (checked directly against `EconByte/Content/cards.json` at `28a16e0`). Card
  state is keyed on `cardID` under an unchanged defaults key, so bookmarks,
  last-seen timestamps and flip counts carry over with no migration code.
  Pinned by `CurriculumCatalogTests.testShippedIdentifiersArePreserved`,
  `GrowthSystemsTests.testEveryShippedCardIdentifierStillResolvesAfterTheCatalogSwitch`
  and `GrowthSystemsTests.testCardStatePersistenceKeyIsUnchanged`.
  A real upgrade-over-build-5 install on a physical device remains a 6b item.

## 3. Findings recorded rather than changed

These are judgement calls or design decisions. They are reported, not silently
altered, because each one is either a palette change or an app-wide typography
change days before a release.

### 3.1 Fixed-point type does not scale with Dynamic Type — significant
Every text style in the app is `Font.system(size:)`, which is an absolute point
size and does not respond to the user's text size. The XCTest audit reports
"Dynamic Type font sizes are unsupported" for 22 elements on Home, 8 on the card
front, 7 on the card back, and "partially unsupported" for 4 Settings rows —
including the card definition, the card example, the streak line and the
Start/Next buttons.

What the AccessibilityXXXL runs prove: nothing is clipped, hidden or made
unreachable at the largest accessibility size, and purchases stay operable.
What they do not prove: that a reader who needs larger text gets it. They do
not, except in the system-drawn parts of Settings.

The fix is to move the type scale onto relative sizing
(`.font(.system(.body, design: .rounded))` or
`relativeTo:` in a custom scale) across roughly a hundred call sites in seven
views, then re-verify every layout at every size. That is a scoped change with
its own layout review, not a release-eve edit. **Recommended as the first
follow-up after 1.1 ships.** No accessibility claim in the storefront metadata
depends on it.

### 3.2 Contrast: the subtext colour misses the small-text ratio in both directions
Measured against WCAG 2.1 (sRGB relative luminance, 4.5:1 for text below 18pt /
14pt bold):

| Pair | Ratio | Where | Verdict |
|---|---|---|---|
| `subtext #5A7A8A` on `ocean #0F3D52` | **2.53:1** | Home section headers ("TODAY'S CARDS", "BROWSE TOPICS"), the "8 cards" count, topic tile counts, "Unlock to view", the card-mode counter | fails |
| `subtext #5A7A8A` on `page #F7F9FC` | **4.34:1** | card disclaimer, "Tap to see example" | fails (marginally) |
| `tide #1A7EA6` on `page #F7F9FC` | **4.35:1** | card back "Real World" label | fails (marginally) |
| `ink #0D2533` on `page #F7F9FC` | 14.98:1 | card concept and example body | passes |
| `white` on `ocean` | 11.60:1 | Home body text | passes |
| `sky #5BC4E0` on `ocean` | 5.76:1 | links, secondary buttons | passes |
| `amber #E8A020` on `ocean` | 5.24:1 | streak headline | passes |
| `ink` on `amber` | 7.13:1 | primary button label | passes |

The XCTest audit independently reports "Contrast failed" for 11 Home elements,
2 card-front and 3 card-back elements, and "nearly passed" for 8 more — the same
set.

This cannot be fixed by nudging one constant: `Econ.subtext` is used on both the
dark app background and the light card, so a value that fixes one direction
worsens the other. The correct fix is two tokens (a dark-surface secondary and a
light-surface secondary), each chosen against its own background — a palette
decision. **Owner item.** The content that carries meaning (card definitions,
examples, buttons, headlines) passes; what fails is secondary and supporting
text, none of which is the only carrier of any meaning (§1 row 8).

### 3.3 Remaining audit findings that are accepted
- **Hit area on `ProgressView`** (Home set progress, card-mode "Set progress").
  Both are non-interactive indicators. The 44-point minimum applies to controls;
  making a progress bar 44 points tall would be a visual regression for no
  interaction gain.
- **"Text clipped" on the card-mode counter.** The visible text is `1 / 8` while
  the accessibility label is the longer "Card 1 of 8"; the audit heuristic
  compares label length against drawn bounds. Removing the label would trade a
  real VoiceOver improvement for a heuristic. Kept.

## 4. Not verifiable on this host — 6b / Owner items

1. 320-point layout (§2.2) — needs a 375-point device in Display Zoom, or a
   second simulator device once the host has disk headroom.
2. Switch Control, Voice Control and Full Keyboard Access end-to-end runs — these
   need an interactive session; XCUITest cannot drive them.
3. Physical-device VoiceOver completion of the whole install-to-purchase task,
   which design section 12 requires before any App Store accessibility claim.
4. iPad compatibility mode — the app is iPhone-only, but it still runs on iPad in
   compatibility mode and the spec's rendered-UX matrix asks for it.

## 5. Changes made in this task

Commit `edd00ae` — `fix: close the card-flip and labelling accessibility gaps`:

| Change | File | Why it was a clear violation |
|---|---|---|
| Card becomes one accessibility element with label, value, hint, `.isButton`, a default action and a named "Flip card" action | `EconByte/Views/CardView.swift` | VoiceOver could not flip a card at all — the core interaction was unreachable |
| Reduce Motion cross-fade instead of 3D rotation | `EconByte/Views/CardView.swift` | Named release condition with a named remedy |
| Bookmark label ("Bookmark card" / "Remove bookmark") and 44×44 target | `EconByte/Views/CardView.swift` | Icon-only control with no label |
| Close label and 44×44 target | `EconByte/Views/CardModeView.swift` | The label was the glyph "✕"; hit area was below the minimum |
| "Card N of M" label on the counter; "Set progress" on the progress bar | `EconByte/Views/CardModeView.swift` | Progress conveyed only as "1 / 8" |
| Settings label on the gear; decorative symbols hidden | `EconByte/Views/HomeView.swift`, `PaywallView.swift`, `BookmarksView.swift` | The audit read "newspaper.fill" aloud as content |
| Card announcement carries the set size | `EconByte/Views/CardModeView.swift` → `CardView(cardCount:)` | Position was announced without its denominator |
