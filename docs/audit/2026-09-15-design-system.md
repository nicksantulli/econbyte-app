# EconByte 1.1.5 — design-system audit (Phase 19, 2026-09-15)

Owner: "audit every design layer and standardize elements like purchase packs so all the buttons are the same size
and clearly labelled with how much they cost … I only want app copy that is necessary."

Base: `main` @ b0c4f9e (1.1.4 build 16, in App Review). Branch `claude/econbyte-115-design-story`.
Evidence: `~/dudley-evidence-retention/econbyte/1.1.5/phase19/` — `shots/before-*` (1.1.4 code) and `shots/after-*`
(1.1.5 code), captured by the same walk (`EconByteUITests/DesignAuditScreenshotTests.swift`) on iPhone 17 (iOS 26.5)
in system dark, system light and at the largest accessibility text size (AX5, set on the simulator with `simctl ui content_size`).

## 1. Inventory

| Surface | Files | Components |
|---|---|---|
| Shell: top bar, tab bar | `Views/Shell/EconShell.swift` | wordmark, gear, 4 tabs, section label, tab scaffold |
| Home | `Views/Shell/HomeTabView.swift` | today's cards card, streak row, brief card, course card, featured pack (OfferCard) |
| Browse | `Views/Shell/BrowseTabView.swift` | search field + results, bookmarks row, topic tiles, bundle + pack OfferCards |
| News / Daily Brief | `Views/Shell/NewsTabView.swift`, `Views/BriefView.swift` | brief document, released item cards, schedule, concept card, teaser lock, archive rows, methodology sheet, archive sheet, empty state |
| Pro + paywall | `Views/Shell/ProTabView.swift`, `Views/ProPaywallView.swift` | Pro OfferCard, plan tiles, trial line, benefits, legal, course rows, subscriber rows |
| Unlock All paywall | `Views/PaywallView.swift` | OfferCard, prices-unavailable notice |
| Packs / bundle | `Views/PackOfferView.swift` | OfferCard, topic line, 3-card preview, topic grid |
| Purchase controls | `Views/Purchase/PurchaseControls.swift`, `Services/StoreOffers.swift` | PurchaseButton, OfferCard, PurchaseButtonModel |
| Course list | `Views/Courses/CourseView.swift` | header, progress, lesson rows |
| Lesson | `Views/Courses/LessonView.swift`, `ChartBlockView.swift`, `DiagramView.swift` | (1.1.4) article blocks → (1.1.5) story |
| Card mode | `Views/CardModeView.swift`, `Views/CardView.swift`, `Views/SessionCompleteView.swift` | nav, progress, flip card, Next, session complete, consent + reminder primers |
| Bookmarks | `Views/BookmarksView.swift` | empty state, review button, list |
| Settings | `Views/SettingsView.swift` | Pro rows, purchase OfferCards, reminders, privacy toggles + analytics ID, links, sources policy sheet |
| First launch | `Dudley/StudioIntroView.swift`, `Services/FirstLaunchPermissions.swift` | studio intro (shared Dudley kit), Apple ATT + notification prompts (system UI) |
| Ads | `Views/AdBannerSlot.swift` | anchored banner slot (no own styling) |

## 2. Findings (before, 1.1.4)

| # | Layer | Finding | Evidence |
|---|---|---|---|
| F1 | Type | **No Dynamic Type.** 160 `.font(.system(size:))` calls across 20 view files (BriefView 32, LessonView 25, HomeTabView 15, SettingsView 13, BrowseTabView 12, SessionCompleteView 12, CourseView 10, …). A font given as a fixed point size never scales with the reader's text-size setting, by construction. | code inventory. (The first AX5 walks passed `-UIPreferredContentSizeCategoryName` as a launch argument, which iOS 26 ignored in both the before and after runs, so those frames are at default size and are not evidence; the after-AX5 set was re-shot with the simulator's own text-size setting.) |
| F2 | Type | ~22 distinct sizes in use (9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 20, 21, 22, 24, 28, 40, 48, 60 …) with no scale. | grep inventory |
| F3 | Colour | **Secondary text fails WCAG AA.** `Econ.subtext` #5A7A8A is **2.53:1** on the navy ground and **2.13:1** on the raised surface (AA needs 4.5:1); used 81 times for captions, metadata, section labels, legal fine print, chart axes. On the light card face it was 4.34:1 (also below AA for small text). | contrast calc in `DesignSystemTests.testEveryTextTokenMeetsWCAGAAOnEveryGround` |
| F4 | Colour | 12 different white opacities for text (0.55 … 0.92, 47 uses); locked tiles at 0.55 were 3.94:1 on a surface. | grep |
| F5 | Shape | 56 literal corner radii in views (3, 4, 5, 7, 8, 10, 12, 14, 16). Buttons 14, cards 12/14/16, rows 10/12. | grep |
| F6 | Space | ~30 distinct padding values (2 … 60), card padding 14/16/18/20 depending on screen. | grep |
| F7 | Purchase | Buttons were one component (Lane A2) but **not the same size**: the Pro CTA "Start 7-day free trial · then $39.99 per year" wraps to two lines and is taller than every pack/bundle/Unlock All/Remove Ads button; at AX sizes the others would wrap unpredictably too. | `before-dark-15-paywall-cover` vs `before-dark-06-browse-pack-card` |
| F8 | Purchase | Price and action share one line, so on narrow widths the price is the part that wraps away from its action. | same |
| F9 | Buttons | `PrimaryButton` / `SecondaryButton` had no minimum height (padding-sized, ~49 pt) while `PurchaseButton` was 52 pt: three button heights on one screen (Home Start, pack Unlock, paywall CTA). | Theme.swift before |
| F10 | A11y | Card-mode close was a "✕" text glyph (hit area widened by frame); the course/tab "Close" buttons, copy-ID and Retry had < 44 pt heights; brief schedule used a fixed 84-pt date column that clips at large sizes. | code |
| F11 | Lessons | Lessons were articles: 80–110-word paragraphs, key-term lists, a captioned chart and quiz buried mid-scroll, completion behind a button at the very end. | `before-dark-22-lesson-1`, `-23-lesson-*` |
| F12 | Copy | Duplicate actions and filler: session complete had "Browse More Topics" doing exactly what "Done" does; "Read the brief →" row inside an already tappable card; "Unlock to view" under a lock icon; "First lesson free" twice on the Pro tab; course summary paragraph (~60 words) above every lesson list; Settings footers restating the obvious. | §6 |
| F13 | Depth | Card faces had a 0.15 shadow, everything else flat with 5 different tint opacities (0.06, 0.10, 0.12, 0.13, 0.15, 0.18) standing in for elevation. | code |
| F14 | Appearance | The app is brand-locked dark (`.preferredColorScheme(.dark)`); system Light renders the same UI. No light palette exists or is needed (see §7 J1). | `before-light-*` = `before-dark-*` |

## 3. Tokens (Theme.swift)

- **Type (`EconType`)** — all Dynamic Type text styles, SF Rounded: `display` largeTitle heavy · `title` title2 heavy ·
  `title3` title3 bold · `story` title3 medium (beat text) · `headline` · `body` · `bodyEmphasis` · `subheadline` ·
  `subheadlineEmphasis` · `footnote` · `caption` (medium) · `overline` caption bold + 1.2 tracking · `micro` caption2
  bold · `figure` title2 heavy.
- **Space (`EconSpace`)** — 4 · 8 · 12 · 16 · 20 · 24 · 32; `gutter` 20, `section` 24. Cards pad 16, rows 12.
- **Radii (`EconRadius`)** — `badge` 6 · `control` 12 (rows, tiles, fields, buttons, choices, insets) · `card` 16 ·
  `mark` 3 (bars/swatches inside drawings).
- **Size (`EconSize`)** — `tapTarget` 44; `buttonHeight` 60 (scaled) for every full-width button.
- **Colour (`EconColor`)** — grounds `background`, `surface` (tide 12 %), `surfaceRaised` (18 %), `surfaceInset`,
  `cardFace`; text `textPrimary` 11.6:1, `textSecondary` 7.2:1, `textTertiary` #A3BFCC 6.0:1 (5.1 on raised),
  `accentText` amberLight; card face `onCardPrimary` 15.0:1, `onCardSecondary` #4E6B79 5.4:1; `accent` amber +
  `onAccent` ink 7.1:1; `interactive` sky 5.8:1; `divider`, `outline`, `accentOutline`.
- **Elevation (`EconElevation`)** — `flat` (surface tone), `outlined` (amber hairline: an offer still for sale),
  `floating` (the flip card only).
- **Components** — `.econCard()`, `.econRow()`, `.econInset()`, `PrimaryButton`, `SecondaryButton`, `EconLinkButton`,
  `EconIconButton` (44×44 + required label), `EconBadge`, `EconSectionLabel`, `TopicChip`, `CardFaceChip`.
- **Gate** — `DesignSystemTests.testViewsUseTokensNotAdHocTypeRadiiOrLowContrastColour` fails the build on any
  `.system(size:)`, numeric corner radius or `Econ.subtext` under `EconByte/Views`.
- **Not migrated (deliberately)** — `EconWordmark` (fixed-size brand lockup, Owner-approved constant size),
  `Dudley/StudioIntroView`, `DudleyAboutSheet`, `DudleyMonogram` (shared Dudley studio kit across all apps, cream
  brand ground), the system ATT / notification prompts.

## 4. The one purchase button

Every pack, the All Packs Bundle, Unlock All, Remove Ads and Pro use `PurchaseButton` inside `OfferCard`:

- **Same size everywhere**: full width, minimum height `EconSize.buttonHeight` scaled with Dynamic Type, `control`
  radius, amber fill (owned: outlined).
- **Always labelled with its price**: action on the first line, StoreKit price on the second — "Unlock / $1.99",
  "Remove ads / $1.99", "Start 7-day free trial / then $39.99 per year", "Subscribe / $9.99 per month",
  "Switch to Monthly / $9.99 per month". Every priced button has two lines, so they are identical in height;
  VoiceOver reads the joined label ("Unlock · $1.99"), which is what the existing UI tests assert.
- **States**: loading ("Loading price…" + spinner), unavailable (action + "Prices unavailable — Try again"),
  pending ("Waiting for approval"), working (spinner), owned ("Owned" / "Family Sharing" / "Included with Pro" /
  "Current plan").
- **Same placement**: last in its card, Restore Purchases (44 pt link) directly under it; Settings purchase cards
  omit the per-card Restore because Settings has one Restore row for everything.
- **Prices only from StoreKit** (`PurchaseManager.offer(for:)` → `displayPrice`); the Lane A2 literal-price scan still
  passes.

### Subscription compliance (checklist A) — unchanged
Two plan tiles, Annual preselected, no toggle (A3); billed price in words is the largest price text (`EconType.title`),
per-month (`footnote`) and "Save 66%" badge smaller (A1); trial line only when eligible, complete (A2); auto-renew
disclosure, Terms of Use, Privacy Policy, Restore, Close, Manage Subscription, Current plan all present with the same
words and identifiers (A4, A6–A8, A10); benefits counted at runtime (A5). Legal text moved from the failing grey to
`textSecondary` (7.2:1) — more legible, not less.

## 5. Accessibility

- Dynamic Type across every migrated view (F1). Layouts that would clip now reflow: Browse topic grid → one column,
  brief schedule and released-item header stack, flip-card faces scroll, flow/compare story figures stack vertically.
- **AX5 walk findings (after the first token pass), all fixed:**
  - Header rows that could not shrink pushed their card past the screen edge (Home "Today's cards", brief and course headers).
  - A plan tile's "Annual" collapsed to one letter per line beside its badge.
  - The Pro-tab course row, the Settings "EconByte Pro" row and the brief's date + SAMPLE header squeezed their titles into narrow columns.
  - The offer-card header squeezed "EconByte Pro" beside "Active ✓".
  - Story flow steps would not wrap and ran off the side.
  - **Fix:** `EconAdaptiveRow` lays a row out side by side when it fits and stacks it vertically when it does not. It is used on all of those headers and rows. Badges and flow steps now wrap. Chrome stops growing: the top-bar gear at xxxLarge; the story progress, close button and Back/Next at accessibility2. The reading content keeps the screen.
- Fixed-geometry drawings (the 14 diagrams, Swift Charts plots) cap their own labels at `xLarge` so they stay inside
  the artwork; their meaning is also in the VoiceOver description and in the beat text beside them.
- Contrast: every text token ≥ 4.5:1 on every ground (unit-tested).
- 44 pt: `EconIconButton` for every icon-only control (gear, card close, story close, copy ID, clear search), link
  buttons, Retry, Reset, Terms/Privacy.
- VoiceOver: icon buttons labelled; story progress bar reads "Page N of M"; story pages post a screen-changed
  notification; custom actions "Next page" / "Previous page"; quick-check choices announce correct / your answer.
- Reduce Motion: story slide → cross-fade (flip card already cross-fades).

## 6. Copy removed or changed

| # | Where | Before | After |
|---|---|---|---|
| 1 | Home streak | "N more card(s) to keep your streak." | "N more today" |
| 2 | Home streak | "Today's goal reached ✓" | "Goal reached ✓" |
| 3 | Home today's cards | "Start →" / "Review →" | "Start" / "Review" |
| 4 | Home brief card | "Read the brief →" row | removed (whole card is the button; chevron) |
| 5 | Home course card | "N lessons with charts and quizzes" | "N lessons" |
| 6 | Browse topic tile (locked) | "Unlock to view" | removed (lock icon) |
| 7 | Pro tab courses header | "First lesson free" | removed (each row says it) |
| 8 | Brief teaser lock | "The rest of the brief is part of EconByte Pro" | "The full brief is part of Pro" |
| 9 | Settings About footer | "Made by Dudley Development." | removed |
| 10 | Settings Notifications footer | "One quiet nudge a day; nothing else." | removed (denied-state footer kept) |
| 11 | Settings Purchases footer | "One-time purchases. Single packs are in Browse." | "Single packs are in Browse." |
| 12 | Card mode | "✕" glyph · "Next →" | xmark icon (label "Close") · "Next" |
| 13 | Session complete | "You finished \"X\" — N cards done." | "X · N cards" |
| 14 | Session complete | "Browse More Topics" button (same action as Done) | removed |
| 15 | Flip card front | "Tap to see example →" | "Tap to flip" |
| 16 | Course screen | course summary paragraph (~60 words) | removed (title, counts, lesson titles) |
| 17 | Course screen | "about N min" · "N of M lessons complete" / "Course complete ✓" | "N min" · "N/M" |
| 18 | Lesson rows | "· Free preview" + chart icon | "Free" badge (chart icon meaningless: every lesson is visual) |
| 19 | Lesson | header course overline + title + summary + "N min" above the text | one cover page |
| 20 | Lesson | "KEY TERMS", "TAKEAWAYS", "QUICK CHECK" block labels, "SOURCES" list inline | term beats, "Recap", "Quick check", "Sources (N)" sheet |
| 21 | Lesson | "Mark complete, next lesson →" / "Next lesson →" / "Mark course complete" / "Completed ✓" | "Next lesson" / "Done" (reaching the recap completes the lesson) |
| 22 | Lesson charts | caption printed under every chart | not printed; its facts are the beat text (caption stays the VoiceOver description) |
| 23 | News archive | "LATEST" | "Latest" badge |

Kept as necessary (legal or safety): paywall auto-renew disclosure, trial line, not-advice line (lesson recap, card
session end, brief, paywall), Terms/Privacy, analytics consent + reminder primer explanations, analytics-ID deletion
footer, Sources & editorial policy, the brief's disclaimer and methodology.

## 7. Judgment calls

- **J1 Dark only.** The palette is one set of dark-ground tokens; the app stays `.preferredColorScheme(.dark)` because
  the Owner-approved wordmark (white "Econ", gold "Byte") and every brand surface are designed on navy. A light theme
  would be a new brand decision, not an audit fix. Light-mode screenshots prove the system setting changes nothing.
- **J2 Two-line purchase button** (action over price) instead of "Unlock · $1.99" on one line: it is the only layout
  in which the Pro CTA (which must keep its billed price, checklist A2/A3) is the same size as a $1.99 pack button.
  The spoken label is unchanged.
- **J3 One button height** (60 pt scaled) for purchase, primary and secondary buttons.
- **J4 No SE-size simulator** exists on this Mac (only iPhone 17, 17 Pro Max, an iPad and a Beat rebuild sim) and disk
  was below the floor for creating one; the AX5 walk on iPhone 17 is the small-space stress test instead.
- **J5 Drawings cap text at xLarge** (fixed geometry); everything else scales to AX5.

## 8. Story lessons (Part 2) — design notes

- One idea per screen: `docs/content/STORY-SCHEMA-1.1.5.md`; 27 lessons → 653 beats, 32 quick checks, 439 beats with a
  visual, ≤ 35 words per screen (Swift `CourseCatalog.validate`, `StoryLessonsTests`, `validate_content.mjs courses`).
- Chrome per page: segmented progress bar (one segment per page) · course overline · close (44 pt) · the page
  (scrolls if a large text size needs it) · Back (60 pt) + Next/Start/Continue/Next lesson/Done (`PrimaryButton`).
- Taps: right two-thirds forward, left third back; swipes; an unanswered check ignores page taps (Next still works).
- Visuals: the 14 lesson drawings, the 28 synthetic charts (caption becomes the VoiceOver description), and four
  data-driven figures (`stat`, `flow`, `compare`, decorative `symbol`) drawn with the same tokens.

## 9. Flip card scroll (merge contract with the Phase 20 card-graphics lane)

The card face (`CardView.face`) is a fixed header (topic chip + bookmark), a body that **always** scrolls vertically —
centred when shorter than the card, scrolling when taller — and a fixed footer ("Tap to flip"). The scroll view
proposes unlimited height, so a card graphic is never squeezed or collapsed. The graphic hook goes first in the front
face's body stack, above the concept title (`PHASE 20 GRAPHIC SLOT`). Card mode's swipe now follows only mostly
horizontal drags (minimum 20 pt), leaving vertical drags to the card. `DesignSystemTests.testCardFaceAlwaysScrollsAndKeepsTheGraphicSlot`
pins all three.

## 10. Phase 24 — Pro lessons polish (same tokens, less chrome)

Owner, after testing 1.1.5 (20): "continue improving the new lessons/courses under pro with additional graphics and
tightening up the UI." No new tokens; every change uses §3.

| Surface | Change | Why |
|---|---|---|
| Story chrome | One row: segmented progress plus close (44 pt). The course overline moved to the cover, as "Course · Lesson N of M". | Less chrome on every beat; the picture gets the space |
| Cover | No Back button, so Start is full width. Smaller icon (56 pt). Overline with the course and lesson number. | Nothing to go back to |
| Beat layout | Idea and term beats sit centered, picture above text. Checks and the recap start at the top. A bottom fade and scroll-indicator flash when a page scrolls. | Short beats read as one composition; long pages say "more below" |
| Pictures | Lesson graphics (the Phase 20 spec on a lesson plate), diagrams, charts, stats and compare cards all sit on `EconColor.surface` with `EconRadius.control`. The centerpiece is taller. | One ground for every picture; the key concept is emphasized |
| Quick check | The picture sits above the question at a compact size (diagram 200 pt, chart 170 pt). Feedback is an inset card with a verdict icon. After a tap the page scrolls to the feedback once it exists, so it always clears the fixed Next button. | The answered-check picture and explanation had sat under the controls |
| Recap | A "Recap" title with a seal icon. Items in a card. Sources and the not-advice notice grouped under it. | Clearer end of the lesson |
| Lesson charts | Line and candle plots scale to their data. Multi-series bars are grouped, never stacked. Categories appear as axis labels. Title and data note cap at xxxLarge. | Flat lines on a zero baseline; stacked bars drew meaningless totals; overlapping marker labels |
| Course detail | The header card no longer repeats the title (the navigation bar has it). It shows a progress ring, "N of M lessons" and minutes, plus one primary action: Start, Continue, Next lesson, Start free lesson, Read again or See EconByte Pro. Rows say "In progress". | A single obvious next step |
| Pro tab | A subscriber sees "Your courses" first and the unchanged plan card after it. A subscriber's course row shows "N/M · Next: lesson". A non-subscriber sees the offer first, as before. | A subscriber came for the courses; paywall content and compliance items are untouched |

Accessibility:
- Graphic plates, diagrams and charts are each one VoiceOver element with a generated summary.
- The centerpiece container keeps the picture's own identifier.
- Plates cap their text at xxxLarge, diagram labels at xLarge; story text scales to AX5.
- Reduce Motion keeps the cross-fade.
- The progress fill animates only without Reduce Motion.
