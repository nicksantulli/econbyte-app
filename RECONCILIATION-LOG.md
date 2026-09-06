# EconByte lineage reconciliation — resolution log (1.1.2, build 11)

Branch `release/econbyte-1.1.2` in `workspaces/econbyte-ios`, the canonical repo.
Merge: **lineage A into a branch based on lineage A**, taking lineage C's delta as
the second parent — `git merge --no-ff refs/lineage/C` from `3ff4f83`.

| Lineage | Ref | Tip | What it is |
|---|---|---|---|
| **A** | `workspaces/econbyte-ios` `codex/econbyte-1.1` | `3ff4f83` | The real 1.1 product: 15 topics / 120 cards, growth stack, VoiceOver + Reduce Motion, unit-test target, ATT removed. Approved and released as build 6. |
| **B** | `~/Documents/GitHub/econbyte-app` `main` | `5714fea` | The stale line that shipped **live 1.1.1 build 8**: v1.0 content, grocery line, ATT back, `googleads.g.doubleclick.net` declared. |
| **C** | `feat/econbyte-instrumentation` | `857f043` | 1.1.2 instrumentation (PostHog + Sentry, 8 correctness items, build-10 tracking coherence), branched off **B**, so it carries B's content regression. |

Fork point for A and B is `42df3dc` (2026-06-19). `origin/main` on GitHub is still
that commit; nothing since has ever been pushed, which is the mechanism of the split.

**Conflicts: 18 files, 38 `<<<<<<<` hunks plus one modify/delete** — exactly the
shape the investigation measured. Every one was resolved by hand. Nothing was
regenerated: **xcodegen was never run**, and `project.yml` is documentation only.

---

## The two-word summary of the merge

**A owns product policy; C owns transport.** Where both lineages define a type of
the same name, the one that is a *transport* keeps the name and C's implementation;
the same-named *policy* type from A is renamed to say what it is, and its call
sites move with it. Where A measured something C could not (it had no notification
primer, no consent primer, no review policy, no Session Complete screen), the event
is ported into C's `_v1` vocabulary rather than dropped.

---

## File-by-file

### 1. `EconByte/Resources/PrivacyInfo.xcprivacy` — **C**
C already carries A's posture (`NSPrivacyTracking = false`, `NSPrivacyTrackingDomains = []`,
Device ID `Tracking = false`) *and* the three data types the instrumentation actually
collects (User ID, Crash Data, Product Interaction). It is a strict superset of A's
manifest with an identical tracking stance, so there is nothing of A's to preserve.
**B's `googleads.g.doubleclick.net` addition is dropped** — build 10 had already
dropped it, and A had solved the same ITMS-91064 the other way in `c911b16`.

### 2. `EconByte/Info.plist` — **C**
Byte-identical to A except for the three instrumentation keys
(`EBPostHogAPIKey`, `EBPostHogHost`, `EBSentryDSN`, all `$(…)` placeholders) and the
absence of `NSUserTrackingUsageDescription`, which is A's posture too.

### 3. `EconByte/Models/ContentStore.swift` — **A, plus a rewritten highlight**
A's loader wins outright: it reads `curriculum-v1.1.json` through
`CurriculumCatalog.loadValidated()` (15 topics / 120 cards, fail-closed) instead of
the v1.0 `cards.json` C inherited. **This single file is the content regression fix.**

`groceryHighlight` — the 1.1.1 hotfix — was rewritten. C keyed it on a *phrase*:
find card `inf-001`, string-search its example for the literal `"A grocery run"`,
slice to the next period. The 1.1 catalog re-sourced `inf-001` (BLS free text →
FRED/CPIAUCSL structured, new prose) and that phrase does not exist, so on the
restored content the search returns `nil` and **the Home line renders nothing** — no
crash, no log, no failing test. It now keys on `ContentStore.homeHighlightCardID`
(`"inf-001"`, which the catalog pins via `supersedes: econbyte-1.0:inf-001`) and
slices the first sentence. Four unit tests in `CurriculumCatalogTests` and the
existing `-exposeGroceryBinding` UI test hold it there.

The visible **source label changes with the content**, from "Bureau of Labor
Statistics" to "Federal Reserve Bank of St. Louis (FRED) — Consumer Price Index…".
That is correct: the line is a verbatim slice of the card, so the attribution has to
be the card's.

### 4. `EconByte/Services/EconTelemetry.swift` (add/add) — **C, extended**
Two entirely different designs shared one name. C's 695-line version wins: it has
real transports, the `_v1` event names the factory policy mirror declares, a
validator, a bounded expiring queue, and proven ingestion (PostHog `econbyte` 594265).
A's 357-line version had a no-op sink and **transmitted nothing**, so keeping both
would have shipped two pipelines, one of them dead.

Extended for A's subsystems: five events C's vocabulary could not name
(`notification_primer_viewed_v1`, `review_prompt_eligible_v1`,
`analytics_consent_changed_v1`, `diagnostics_consent_changed_v1`, `ad_dismissed_v1`),
plus `topic_opened_v1` so `topic_locked_tapped_v1` has a denominator; the `placement`,
`access_state` and `enabled` property kinds; and `session_complete` in the
`entry_point` vocabulary.

`difficulty` went from two declared tiers to **three** (`intro`, `intermediate`,
`advanced`). C declared two because the v1.0 `cards.json` it was cut from only had
two; the restored 1.1 catalog has three, and `testDeclaredDifficultiesMatchTheBundledCatalog`
would otherwise fail — correctly.

### 5. Consent default — **A's, and this is the one place the lineages contradict each other**
C ships analytics and crash reporting **on by default**, storing the negative
(`ebAnalyticsOptOut`, absent == on). Version 1.1's App Store release notes, published
and readable today, say: *"Usage analytics and crash diagnostics are separate opt-in
choices, both off by default."* A's consent primer, its Settings toggles and its
`GrowthFlowTests` are all built on that.

Shipping C's default would have **silently reversed a published privacy promise on
update** — the same class of defect as the live 1.1.1 binary requesting ATT under a
"Used to Track You: No" label, which is the reason this lane exists. So:

* `EconTelemetry` stores the positive under A's key `econ.telemetry.consent`
  (a 1.1 install that already opted in stays opted in);
* `EconDiagnostics` gained `econ.diagnostics.consent` and only installs the Sentry
  handler at construction when it is set;
* four of C's tests were re-expressed (`testAnalyticsIsOffUntilTheUserOptsIn`,
  `testOptingInSurvivesRelaunch`, `testConsentStillSendsNothingWithoutAKey`,
  `testDiagnosticsStartsOnConsentWhenADSNIsConfigured`, plus
  `testDiagnosticsConsentSurvivesRelaunch`).

**Consequence, stated plainly:** PostHog and Sentry volume from 1.1.2 will be a small
fraction of what an opt-out build would produce. That is the cost of keeping the
promise. It is an Owner-reversible decision, and reversing it means changing the
published 1.1 notes too, not just the code.

### 6. `EconByte/Services/EconDiagnostics.swift` (add/add) — **C**, and A's renamed to `EconDiagnosticLog`
Same name, different jobs. C's is a real crash reporter (Sentry, crash-only, filtered).
A's is a bounded, scrubbed, **local-only** log of the app's own enumerated failure
codes (`ad_load_failed`, `notification_schedule_failed`, `content_catalog_invalid`)
that has no DSN and never transmits. Both survive: `EconDiagnostics` is the crash
reporter, `EconDiagnosticLog` (new file, A's code, mechanical rename of the class,
options, configuration and sink types) is the local log, exactly as it shipped in the
approved build 6. Routing those codes into Sentry as scrubbed messages is a
deliberate follow-up, not something this merge invented.

### 7. `EconByte/Services/EconTelemetryWiring.swift` — **C**, facade renamed `EBEvents`
C's `EconGrowth` enum (event emission) collided with A's `EconGrowth` class (the
growth composition root injected into every view and exercised by 87 of A's tests).
The composition root keeps the name; the emission facade becomes `EBEvents`, matching
the `EB…` prefix its own vocabulary enums already use. New emitters added for the
ported events, plus `EBAdPlacement` and `recordedLaunchCount()`.

### 8. `EconByte/Services/Services.swift` — **deleted (A)**
48 lines holding v1.0's `ReviewPrompt` — "ask on the 5th / 20th / 50th launch". A
deleted it and replaced the behaviour with `ReviewRequestPolicy` (ask only after a
genuinely good session, once per app version, suppressed by negative-session events).
C's `bea7834` had patched it so a UI-test runner is never asked to rate the app;
**that guard is ported**, as `ReviewRequestPolicy.mayShowSystemReviewSheet(in:)`,
called from `EconGrowth.requestSystemReview()`. Deliberately a property of the
*process*, not of the decision, so `decide` stays a pure function that A's
eligibility tests can still run inside XCTest. C's four `ReviewPrompt` tests were
re-expressed against it, plus one new test proving the policy still decides inside a
test run.

### 9. `EconByte/Services/AdManager.swift` — **A**, plus C's ad telemetry
A's is a *provider adapter only*: entitlement, region (DUD-224 EEA/UK, fails closed),
placement, blockers and caps all live in `EconMonetization`, which is what makes ad
policy testable without the SDK. C had folded all of that back into the adapter as
inline constants. A's structure wins.

Everything build 10 added is already present or preserved:
`publisherPrivacyPersonalizationState = .disabled` (A had it), `npa=1` per request
(A's `EconAdRequestPolicy.extras`, which also carries `rdp=1` — C dropped that),
no ATT import and no call sites. Added from C: `ad_load_finished_v1` on fill/no-fill
and `ad_impression_v1` at the moment of presentation, plus an impression counter for
`session_ended_v1`.

`testEveryAdRequestIsNonPersonalized` was updated accordingly: it still requires
`publisherPrivacyPersonalizationState = .disabled` and `request.register(extras)` in
the adapter, and now looks for the `"npa": "1"` (and `"rdp": "1"`) literals in
`EconMonetization.swift`, where the policy is actually written. Both halves are
asserted — a policy nobody registers is as useless as a registration with no policy.

### 10. `EconByte/Services/EconMonetization.swift` — **A**, composition root rewired
The `EconGrowth` composition root now holds `EconTelemetry.shared` and
`EconDiagnostics.shared` alongside its own `EconDiagnosticLog`, and every
`telemetry.capture(.someAEvent, …)` became the corresponding `EBEvents` call.
`applicationDidBecomeActive` emits `app_opened_v1` via `EBEvents.recordLaunch()` on
**cold launches only** — a warm foreground is not a launch, and the event carries
install-age and launch-count buckets that only make sense per launch.

### 11. `EconByte/Services/PurchaseManager.swift` — **A**, plus C's presentation + telemetry
A's single-flight restore (`restoreTask`) and its `onDiagnostic` hook are kept; C
had dropped both. Added: `PurchasePresentation` (no hardcoded price literal, buy
control disabled without a real StoreKit price), `ProductID.family`, and purchase /
restore / products-loaded events emitted **inside** the manager, where the branch is
known and the StoreKit id can be reduced to its family — the id itself is a
prohibited property.

### 12. `EconByte/Models/StreakManager.swift` — **A**, plus one line
A's version, with `EBEvents.streakDayCredited(streak:)` added. C's
`requestNotificationPermission` / `scheduleStreakReminder` were **not** taken back:
that is v1.0's auto-prompt with "Your streak is at risk 🔥" copy, which
`CONTENT-DECISIONS.md` D8 prohibits and `NotificationPolicy` replaced.

### 13. `EconByte/EconByteApp.swift` — **A**, plus C's hooks
A's entitlement-before-ads ordering and its scene-phase reconciliation are kept
(C had neither). Added: early `EconDiagnostics.shared` construction, the DEBUG-only
`-EBInstrumentationSmoke` / `-EBInstrumentationCrash` hooks, and `EBEvents.flush()`
when the app leaves the foreground.

### 14. Views — **A**, with C's call sites and C's stricter property rules
`HomeView`, `CardView`, `CardModeView`, `PaywallView`, `SettingsView` all take A's
1.1 versions (VoiceOver card flip, Reduce Motion cross-fade, consent and reminder
controls, Session Complete flow). Layered on:

* **the grocery line**, re-expressed (see 3);
* `session_started_v1` / `session_ended_v1` / `card_advanced_v1` / `card_flipped_v1`
  / `bookmark_changed_v1` / `paywall_viewed_v1` / `topic_opened_v1`;
* `PurchasePresentation` in place of **three hardcoded `"$0.99"` fallbacks** that A
  still carried — a literal that is wrong in every non-US storefront. C's
  `testNoViewFallsBackToAHardcodedPrice` scans for it and would have failed.

A's events lost properties on the way across, in every case because **C's prohibited
list is strictly stricter than A's schema**: `card_id`, `topic_id`, `set_id`,
`product_id`, exact counts and exact durations were all *allowed* by A's schema and
are *rejected* by the shipped one. Nothing that identifies content or a transaction
travels any more.

### 15. `EconByte.xcodeproj/project.pbxproj` — **C**, hand-merged additively
Both lineages independently created an `EconByteTests` target with different UUIDs.
C's target is the base (it also carries the two SPM dependencies, the
`Config/Instrumentation.xcconfig` base configuration, and the exact-version pin for
GoogleMobileAds that `testEveryVendorSDKIsPinnedToAnExactVersion` requires). Added by
hand: A's `CurriculumCatalogTests.swift` and `GrowthSystemsTests.swift` into that
target's group and Sources phase, A's `GrowthFlowTests` / `AccessibilityTests` /
`ScreenshotTests` into the UI-test target, and A's fuller test build settings
(`SUPPORTED_PLATFORMS`, `TEST_HOST` via `$(BUNDLE_EXECUTABLE_FOLDER_PATH)`).
`MARKETING_VERSION = 1.1.2`, `CURRENT_PROJECT_VERSION = 11`. `plutil -lint`: OK.
**The unit-test target survives, carrying both lineages' unit tests.**

### 16. `project.yml` — union
Documentation only for a committed-pbxproj app. C's packages and xcconfig entries,
A's `ENABLE_TESTABILITY` and test-host settings, build 11, and an explicit note that
xcodegen must never be run here.

### 17. `EconByte.xcodeproj/…/EconByte.xcscheme` — **C**
Both schemes list the same two testables; C's carries the target UUIDs that exist in
the merged pbxproj.

### 18. `EconByte/Services/InstrumentationContext.swift` — extended
`automationArguments` gained `-econResetGrowthState` and `-econDisableAds`, the 1.1
UI suite's harness arguments. They were invisible to lineage C because it did not
have the 1.1 growth stack — and without them the restored suite would relaunch the
real app with the real key and write test traffic into the live projects, which is
precisely the defect that file exists to prevent.

---

## Tests

* `EconByteTests/GrowthSystemsTests.swift` — sections 6 and 7 (lineage A's telemetry
  schema and consent, ~20 tests) were **removed, not lost**: they exercised a type
  that no longer exists, and `EconTelemetryTests` / `InstrumentationPrivacyTests`
  cover the same ground against the pipeline that actually ships, with a stricter
  prohibited list. A comment at the seam records exactly that. Section 8's
  diagnostics tests were renamed onto `EconDiagnosticLog`.
* `EconByteTests/CurriculumCatalogTests.swift` — four new tests for the Home
  highlight and the restored 15/120 catalog at the runtime store.
* `EconByteUITests/EconByteUITests.swift` — the grocery assertion no longer looks for
  `"$117"`, which is superseded v1.0 content.

## Not done here, by design

* **No push.** `origin/main` is still `42df3dc`; that is the root cause of the split
  and fixing it is an Owner gate.
* **No `reviewSubmission`.** Owner gate.
* **App Privacy label rows** remain web-UI only and unpublished.
