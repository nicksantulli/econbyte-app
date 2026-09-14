# EconByte 1.1 — implementation decisions requiring Owner ratification

**Status:** PENDING OWNER RATIFICATION. Every entry below is a decision an
implementer took because the written design and the owner's standing portfolio
decisions disagreed, or because the design assumed infrastructure that does not
exist. Nothing here is settled until the Owner says so.

**Scope:** Task 5 of `docs/superpowers/plans/2026-08-28-econbyte-return-growth.md`
("Integrate purchases, ads, telemetry, diagnostics, review, and notifications"),
implemented on `codex/econbyte-1.1`.

**Design of record:**
`docs/superpowers/specs/2026-08-28-econbyte-return-growth-design.md`.

---

## D1 — Google UMP is not adopted; the DUD-224 geo-restriction is kept

**The design says** (sections 6, 9.2, 14.1) to integrate Google's User Messaging
Platform: update consent information every launch, present a consent form, expose
"Privacy choices" in Settings, and gate every ad request on `canRequestAds`.

**The owner's standing decision (DUD-224, 2026-06-14) says** the opposite: do not
serve ads to EEA/UK users at all, and do not integrate UMP. Suppressing the ad
request in those regions sidesteps GDPR consent entirely — no consent form, no
UMP SDK call. This pattern is already shipping in all five Dudley apps, EconByte
1.0 included (`EconByte/Services/AdManager.swift` at commit `28a16e0`).

**What was implemented.** The owner decision wins. `EconAdRegion` in
`EconByte/Services/EconMonetization.swift` classifies the device *region setting*
(no location permission, no IP lookup) into three states:

| State | Meaning | Ads |
|---|---|---|
| `allowed` | region code present and not in the restricted set | may request |
| `restricted` | EU 27 + Iceland, Liechtenstein, Norway, United Kingdom | never |
| `unknown` | region code absent or empty | never (fail closed) |

The composite can-request gate is: **entitlement → region → blockers → placement
eligibility → caps.** A `restricted` or `unknown` region prevents Mobile Ads SDK
initialization, not merely presentation, so no ad request ever leaves the device
in those regions. The 31 restricted codes are pinned by test
(`testRestrictedRegionsCoverTheEEAAndUnitedKingdom`).

**Divergence recorded:** the spec's UMP requirements in sections 6.1 (steps 4–5),
9.2, and 14.1 are **not implemented**. The release packet cannot record "UMP
message state" or "privacy options entry point" because neither exists. If the
Owner later wants EEA/UK ad revenue, UMP becomes a separate scoped change with
its own consent QA — it is not a refactor of this code.

**Consequence for public copy:** the privacy policy and App Store answers must
describe geo-restriction, not consent management. They must not claim a consent
form exists.

### D1a — Switzerland: EconByte and Table Talk currently disagree

EconByte's restricted set is EU 27 + Iceland, Liechtenstein, Norway, and the
United Kingdom. **Switzerland (`CH`) is not in it.** That matches EconByte 1.0
and the portfolio pattern shipped across all five apps: the spec's Switzerland
clause (section 9.2) is scoped to UMP coverage, and under D1 there is no UMP.

However, **Table Talk's Task 4 just added `CH` to its restricted set**, per its
own spec. The two apps therefore now ship different EEA/UK geo-gates for the
same owner decision. Neither is obviously wrong — Switzerland has its own FADP
rather than GDPR — but they should not diverge by accident.

**Owner action:** rule once, for the whole portfolio, and have both apps adopt
the ruling. Until then, treat any statement of "the Dudley ad geo-gate" as
app-specific.

### D1b — `consent_update_failed` is unraised, and that is correct here

Design section 10.3 requires a `consent_update_failed` diagnostic code. The code
is declared in `EconDiagnosticCode` for schema completeness, but nothing raises
it, because the only operation that could fail that way is a UMP consent-info
update — which does not exist under D1. There is no local consent operation that
can fail: the region gate is a synchronous locale read, and the analytics and
diagnostics toggles are local writes.

It is left declared rather than deleted so that adopting UMP later does not
require a schema change. Every other declared code has a live raise site.

---

## D2 — App Tracking Transparency is removed from the ad path

### What 1.0 actually does (investigated, not assumed)

Reading the shipped source at `28a16e0`:

1. `EconByte/Services/AdManager.swift` imports `AppTrackingTransparency` and, in
   `presentInterstitial()`, calls
   `ATTrackingManager.requestTrackingAuthorization()` whenever the status is
   `.notDetermined` — **immediately before showing an interstitial**, on every
   non-EEA/UK device. The mock (non-`GoogleMobileAds`) path does the same in
   `noteCardSwipe()`. So **1.0 does prompt**, in the US and rest of world, at the
   fifth card swipe.
2. Ad requests are built with a bare `Request()` — no `npa` extra. So when a user
   granted ATT, **1.0 could serve personalized ads and Google could use the
   IDFA**. Nothing in 1.0 forced non-personalized delivery.
3. `EconByte/Info.plist` carries `NSUserTrackingUsageDescription`
   ("EconByte uses this to show relevant ads and measure ad performance").
4. `EconByte/Resources/PrivacyInfo.xcprivacy` declares `NSPrivacyTracking = true`
   and a `DeviceID` collection with `NSPrivacyCollectedDataTypeTracking = true`
   for `ThirdPartyAdvertising`.

The 1.0 comment "ATT is kept for US / rest-of-world" is therefore accurate and
load-bearing, not vestigial.

### What 1.1 does

The portfolio decision and the design (section 4.2, section 9.1) both say version
1.1 is contextual/non-personalized only, with **no ATT prompt and no IDFA**.
Contextual ads need no tracking authorization, so the ATT pathway has no
remaining purpose.

- `import AppTrackingTransparency` and both `requestTrackingAuthorization()` call
  sites are **removed** from `AdManager.swift`.
- Every ad request now carries the non-personalized extras
  (`npa=1`, `rdp=1`) and a `G` max ad content rating, via
  `EconAdRequestPolicy`. Pinned by
  `testAdRequestPolicyIsContextualAndNeverRequestsTracking`.

### Verification that nothing else depended on ATT

`ATTrackingManager` appeared in exactly two places, both inside `AdManager`
(`presentInterstitial()` and the mock `noteCardSwipe()`). Nothing read
`trackingAuthorizationStatus` for gating, entitlement, analytics, or UI state; no
view, purchase path, content path, or test referenced it. `SKAdNetworkItems` in
`Info.plist` are install-attribution identifiers and are unaffected by ATT
removal — they are left in place. The removal is therefore behaviour-complete at
the source level.

### What is deliberately NOT done in Task 5

Design section 9.1 sequences the manifest work explicitly: *"The app must remove
the ATT prompt and unused tracking usage description **only after** the archive
privacy report confirms that the configured SDK path does not access tracking
permission or IDFA."* An archive privacy report cannot be produced from a
simulator build, and Task 5 is barred from archiving.

So the following remain **unchanged** and are handed to Task 6 as required
pre-submission actions:

| Artifact | Current (1.0) value | Required 1.1 action |
|---|---|---|
| `Info.plist` → `NSUserTrackingUsageDescription` | present | remove after the archive privacy report shows no tracking-permission access |
| `PrivacyInfo.xcprivacy` → `NSPrivacyTracking` | `true` | set `false` after the same report |
| `PrivacyInfo.xcprivacy` → `DeviceID` collected type | tracking, third-party advertising | re-derive from the final archive privacy report |
| ASC App Privacy answers | 1.0 tracking answers | re-answer against the 1.1 binary |

**This is a submission blocker, not a nicety.** Shipping 1.1 with the 1.0
manifest would declare tracking the binary no longer performs.

### RESOLVED in Task 6a (2026-08-30) — Option B, applied

**Status: CLOSED.** The blocker above is discharged. All four rows are now done
or assigned, and the manifests in this repository carry the new values.

#### What the archive privacy report actually found

The report was derived from the build 6 archive (aggregate of every
`PrivacyInfo.xcprivacy` in the archive, plus Mach-O inspection of every shipped
binary). Full artifact:
`AppStore/1.1/evidence/privacy-report-build6.json`.

1. **Our own code is clean.** The repository contains no ATT or IDFA reference —
   the only hit is the comment in `AdManager.swift` recording the 1.0 removal.
   No first-party code requests tracking authorization, and no ATT dialog
   appeared in any of the simulator launches across the Task 6a test runs.
2. **The Google SDK path is not clean, and cannot be made clean by us.** The
   GoogleMobileAds SPM binary target statically links the SDK into the app
   executable (the embedded `GoogleMobileAds.framework` binary is a 51 KB stub
   carrying resources and the SDK's manifest). That statically linked code links
   `AdSupport.framework`, carries an undefined
   `_OBJC_CLASS_$_ASIdentifierManager`, and contains the `ATTrackingManager` and
   `trackingAuthorizationStatus` API strings.
3. **Google's own manifest declares tracking.** `GoogleMobileAds.framework`'s
   `PrivacyInfo.xcprivacy` declares `NSPrivacyCollectedDataTypeDeviceID` with
   `NSPrivacyCollectedDataTypeTracking = true` and `Linked = true`.

So the literal precondition in design section 9.1 — "the configured SDK path
does not access tracking permission or IDFA" — is **not** satisfied, and Task 6a
initially declined to make the change on its own authority.

#### The ruling

**Option B, ruled 2026-08-30** under the Owner's standing blanket approval, with
a precedent check by the controller. The deciding fact was not an argument, it
was a shipped, reviewed app:

**Table Talk — approved by App Review and live in the US, with the same
statically linked GoogleMobileAds SDK — already ships exactly this posture.**
Verified directly at
`workspaces/table-talk-ios/TableTalk/Resources/PrivacyInfo.xcprivacy`:

| Key | Table Talk's shipped value |
|---|---|
| `NSPrivacyTracking` | `false` |
| `NSPrivacyTrackingDomains` | empty array |
| `NSPrivacyCollectedDataType` | `NSPrivacyCollectedDataTypeDeviceID` |
| `NSPrivacyCollectedDataTypeTracking` | `false` |
| `NSPrivacyCollectedDataTypeLinked` | `false` |
| `NSPrivacyCollectedDataTypePurposes` | `NSPrivacyCollectedDataTypePurposeThirdPartyAdvertising` |
| `Info.plist` → `NSUserTrackingUsageDescription` | **absent entirely** |

Option B is therefore not a novel declaration being tried out on EconByte. It
aligns EconByte with the portfolio posture Apple has already reviewed and
approved. EconByte's manifest is now byte-identical to Table Talk's.

The declaration describes the binary **as configured**, which is the accurate
reading: the app declares what it does, not what a bundled SDK is capable of
doing under a configuration this app never uses. Removing
`NSUserTrackingUsageDescription` makes an ATT prompt impossible rather than
merely absent — iOS requires the key for a prompt to appear at all — so no
dependency can start prompting in a future SDK bump without a deliberate
Info.plist change.

#### What changed

| Artifact | Was | Now |
|---|---|---|
| `EconByte/Info.plist` → `NSUserTrackingUsageDescription` | present | **removed** |
| `PrivacyInfo.xcprivacy` → `NSPrivacyTracking` | `true` | **`false`** |
| `PrivacyInfo.xcprivacy` → `DeviceID` → `Tracking` | `true` | **`false`** |
| `PrivacyInfo.xcprivacy` → `DeviceID` → `Linked`, purpose | `false`, ThirdPartyAdvertising | unchanged |
| `PrivacyInfo.xcprivacy` → `NSPrivacyTrackingDomains` | empty | unchanged (empty) |
| `PrivacyInfo.xcprivacy` → `NSPrivacyAccessedAPITypes` | UserDefaults `CA92.1` | **preserved** |
| `Info.plist` → `SKAdNetworkItems` | 50 entries | **preserved** (install attribution, unaffected by ATT) |

The app was then **re-archived** so the shipped archive carries the corrected
manifests, and the privacy report was re-run against the new archive to confirm
the app-level declarations.

**Expected and accepted delta:** the aggregate report still shows
`GoogleMobileAds.framework`'s own manifest declaring DeviceID with
`Tracking = true`. That is Google's declaration of its SDK's capability across
all host apps and cannot be edited by us. Apple's report aggregates both; the
app-level manifest is the one that describes this app's configuration. The same
delta exists in the approved Table Talk build.

#### ASC App Privacy answers (binding)

The answers must be the **configuration-level** ones:

- **Identifiers → Device ID:** Collected · purpose Third-Party Advertising ·
  **not used for tracking** · **not linked to the user's identity**.
- **Usage Data → Advertising Data:** same treatment.
- **Everything else: Not Collected** while the analytics and diagnostics
  providers are dormant (no PostHog key, no Sentry DSN — see D5). If either
  provider is later enabled, these answers must be re-derived before that build
  ships.

Draft answers are in `AppStore/1.1/metadata.json` under `appPrivacy`; the
evidence trail is in `AppStore/1.1/evidence/release-packet.json`.

---

## D3 — DudleyCore v2 is not adopted in this repository

**The design/plan says** (Task 5, step 2) "Adopt DudleyCore v2".

**At `28a16e0` this repository has no DudleyCore dependency of any kind** — no
package in `project.yml`, no `XCRemoteSwiftPackageReference`, no import, no
mention anywhere in the tree. `workspaces/dudley-core-ios` exists as a separate
local package but has never been consumed here, and its monetization module is
itself an in-flight deliverable of the separate
`2026-08-28-dudley-monetization-release-standard` plan.

**Decision: deferred.** Reasons:

1. Adding a cross-repository Swift package to an app whose 1.0 lineage is already
   under a provenance investigation (plan Tasks 1–2) introduces a second
   unresolved source dependency into the exact artifact whose reproducibility is
   in question.
2. The dependency graph is pinned in
   `EconByte.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
   and forms part of the Gate A provenance record. Task 5 is not authorized to
   change the release dependency set.
3. DudleyCore's monetization surface is not frozen, so adopting it now would
   couple EconByte's 1.1 release date to another plan's completion.

**What was done instead.** The policy layer is implemented locally in
`EconByte/Services/EconMonetization.swift` with the spec's cap semantics —
region states, composite gate, placement vocabulary, blocker set, thresholds, and
an `EconInterstitialAdapting` adapter seam. The types are deliberately shaped so
that a later swap to DudleyCore is a mechanical rename rather than a rewrite.
Table Talk Task 4 reached the same conclusion independently.

---

## D4 — Both approved IAPs are preserved exactly; no product scope changed

`com.nsantulli.econbyte.unlockall` and `com.nsantulli.econbyte.removeads` are
both APPROVED non-consumables in App Store Connect. Neither identifier, type,
nor meaning is touched.

- `PurchaseManager.ProductID` still declares exactly those two raw values, pinned
  by `testBothApprovedProductIdentifiersArePreservedExactly`.
- `EconByte.storekit` (local test configuration only, never bundled) still
  declares both.
- Independence is enforced in code and by test: Unlock All does not suppress ads,
  Remove Ads does not unlock topics.
- Purchase, restore, refund, and revocation all flow through
  `Transaction.currentEntitlements`, and a verified revocation beats stale cached
  ownership. A change to either entitlement updates ad behaviour **and** content
  access in the same turn.
- The 13 paid topics of the 1.1 curriculum are covered by the existing
  `unlockall` entitlement at no additional charge, per design section 7.1.
- No real purchase was made. All purchase testing used the local StoreKit test
  configuration and the DEBUG-only entitlement toggles, which are compiled out of
  Release.

### Copy correction

Design section 8 forbids an umbrella "Pro" label implying the two products are
bundled. 1.0 used "EconByte Pro" as both the paywall navigation title and the
Settings section header. Both are corrected to purchase-specific wording.

---

## D5 — Provider tokens: none exist, none are embedded

The design names PostHog and Sentry. **Neither an EconByte-specific PostHog
project nor an EconByte Sentry DSN exists yet**, and the Owner controls both
(design section 16).

**Decision: production-safe, token-free.**

- `EconTelemetryConfiguration.postHogAPIKey` and
  `EconDiagnosticsConfiguration.sentryDSN` read from an Info.plist key that is
  not present, so both resolve to `nil`. No token is embedded, and no other
  Dudley app's token (including VibeRater's) is reused.
- With no token the sinks are `EconNoOpTelemetrySink` / `EconNoOpDiagnosticsSink`:
  events are still schema-validated and bounded locally, and **nothing is ever
  transmitted**.
- Neither the PostHog nor the Sentry SDK is added to the package graph in Task 5.
  Adding either changes the release dependency set and the archive's compiled-SDK
  inventory, which belongs with the Owner-enabled provider work, not here.
- Prohibited provider features (autocapture, session replay, heatmaps, surveys,
  feature flags, person profiles) are declared off in
  `EconProviderOptions`; Sentry options declare no default PII, no screenshots,
  no view hierarchy, no replay, no network bodies, zero trace sampling, and zero
  breadcrumbs.
- Analytics and diagnostics are separate opt-ins, both default off, each with its
  own random installation identifier that is rotated on opt-out.

**Owner action required before any data flows:** create the two projects, set the
retention windows from design section 10.1 (90-day raw product events, 13-month
de-identified aggregates), and supply the token/DSN through build configuration —
never a committed file.

---

## D6 — AdMob identifiers are reused, and remain Owner-unconfirmed

Version 1.1 reuses the exact identifiers already shipping in 1.0. No identifier
was invented.

| Purpose | Value | Source |
|---|---|---|
| AdMob app ID | `ca-app-pub-9950526548980224~6219329532` | `EconByte/Info.plist` at `28a16e0` (unchanged) |
| Release interstitial unit | `ca-app-pub-9950526548980224/9740067293` | `AdManager.swift` at `28a16e0` (unchanged) |
| Debug interstitial unit | `ca-app-pub-3940256099942544/4411468910` | Google's public test unit |

**Caveat, carried forward from the DUD-242 record:** these Release identifiers
are *format-valid* but have never been confirmed against the AdMob console by the
Owner. They pass a structural check; that is not the same as being correct.

**Also removed:** 1.0's `AdManager` carried a hard-coded
`testDeviceIdentifiers` entry (a hashed advertising identifier for one physical
device). It is gone. Debug builds already use Google's public test interstitial
unit, which serves test ads without any registered test device, so the constant
bought nothing and put a device-derived identifier in the repository. This
follows the redact-before-first-commit lesson from the app-factory checkpoint.

**Pre-submission check (Task 6):** confirm the app ID and interstitial unit ID
against the AdMob console, confirm console frequency caps are at least as
conservative as the in-app caps (1 per foreground session, 2 per calendar day),
and confirm `app-ads.txt`. Do not submit on the strength of the format check.

---

## D7 — The runtime catalog switch was done here, in Task 5

**Reading.** The plan's Task 5 file list does not name `ContentStore.swift`, but
the assignment is unambiguous from two other places:

1. Task 4's own deliverable says so in a source comment
   (`EconByte/Content/CurriculumCatalog.swift`): *"Task 4 delivers the catalog,
   its validator, and its tests only. The runtime still reads `cards.json`
   through `ContentStore`; wiring the views to this catalog is Task 5's job, per
   the implementation plan."*
2. Task 5 owns access control, and the 2-free/13-paid access map is a property of
   the 15-topic catalog. Enforcing `unlockall` against a 10-topic runtime would
   leave the five new 1.1 topics unreachable. Task 6 is accessibility, creative,
   and release — it cannot be the switch.

**What was done.** `ContentStore` now loads `CurriculumCatalog.loadValidated()`
and maps it into the existing `EconTopic`/`EconCard` view models.

**User-state preservation, verified before the switch:**

- Per-card state persists under `com.nsantulli.econbyte.cardStates`, a dictionary
  keyed on `cardID`. Neither the key nor the keying changed; both are pinned by
  test.
- The 1.1 catalog preserves all 80 shipped card identifiers, all 10 shipped topic
  identifiers, their order, display names, and SF Symbol icons. Bookmarks, last-seen
  timestamps, and flip counts therefore migrate with no migration code at all.
  Task 4's `supersedes` / `supersedesNote` fields already forced any concept
  change on a reused identifier to be declared.
- `StreakManager` keys (`currentStreak`, `lastStreakDate`, `cardsTodayCount`,
  `cardsTodayDate`) are untouched, so streaks survive.
- `ContentStore.freeTopicIds` is asserted equal to the catalog's free topic set,
  so the free/paid partition cannot drift silently.

**`cards.json` was deleted.** The design (section 7.1) makes the 1.1 catalog the
re-sourced replacement of those same 80 cards, and section 14.4 requires a single
content checksum in the release packet. Shipping a second, stale, unsourced copy
of the content inside the binary would defeat the editorial gate and give a
runtime fallback that silently degrades to unverified claims. Failure is closed
instead: an invalid catalog yields an empty runtime, and the build-time test
fails first.

---

## D8 — Notification copy rewritten; launch-time prompt removed

1.0 requested notification authorization automatically one second after the first
Home appearance (`HomeView.onAppear`), and scheduled a reminder reading *"Your
streak is at risk 🔥 · 3 cards = 90 seconds."*

Both violate design section 11.1 (notifications default off; the system dialog
appears only after an explicit opt-in; the reminder carries no urgency or
streak-loss pressure). Both are removed. The system dialog is now reachable only
from the Session Complete primer or the Settings toggle, and the reminder copy is
gated by `NotificationPolicy.copyIsCompliant`, which rejects the 1.0 string.

---

## D9 — Rating request rebuilt

1.0 called `SKStoreReviewController.requestReview` on the 5th, 20th, and 50th
*launch*, regardless of whether anything went well, and Settings' "Rate EconByte"
linked to `https://dudleyapps.com`.

1.1 implements design section 11.2 exactly: at least 3 completed sets, at least 7
days since first launch, the current session completed a set, no crash, purchase
failure, restore failure, consent form, notification prompt, paywall, or ad in
the session, and at most one attempt per app version. Eligibility is recorded
locally before the system API is called. Settings now links to
`https://apps.apple.com/app/id6780714383?action=write-review`.

---

## D10 — Consent choices are presented at the first completed set

Design section 10.1 requires each consent choice to be presented after the first
completed set, never on first launch. Round 1 shipped the toggles in Settings
only, which met the "default off, separate, reversible" half of the requirement
but not the "presented" half.

**Now implemented.** Session Complete offers both choices, once, after the first
completed set: two independent toggles, both off, with a plain-language note that
declining changes nothing about cards, streak, bookmarks, purchases, or ads. The
offer is non-blocking, prompts no system dialog, and is recorded as shown so it
is never repeated. Both toggles remain in Settings permanently.

**Deliberate sequencing deviation.** Section 11.1 puts the reminder primer at the
same moment. Asking a reader two unrelated questions on one screen is a worse
experience than either ask alone, so the reminder primer defers by one completed
set while the consent offer is on screen (`primerEligible(consentPromptVisible:)`,
pinned by test). The consent offer is the one the spec ties to a legal posture, so
it goes first. If the Owner prefers both on one screen, that is a one-line change.

An ad is also blocked at that exit (`EconAdBlocker.consent`), so no interstitial
can ever follow a consent question.

---

## D11 — "Completed set" is broader than "daily set"

Section 9.3 names the placement `daily_set_exit`. In the shipped app,
`CardModeView` drives three deck types through the same completion screen: the
daily set, a single-topic deck, and Saved Cards. All three currently count as a
completed set for ad eligibility, the review threshold, the consent offer, and
the reminder primer.

**Decision: keep the broader definition.** Reasons:

1. The reader's experience is identical in all three — a finished deck of cards
   at the same completion screen. Showing an interstitial after the daily set but
   never after a topic deck would be arbitrary from the reader's side.
2. The caps, not the placement breadth, are what protect the experience: one
   interstitial per foreground session, two per calendar day, fifteen minutes
   apart, two completed sets apart, and two completed sets before the first ad
   ever. Broadening the trigger cannot exceed those.
3. The `daily_set_completed` and `ad_*` telemetry carries `set_id` and
   `card_count`, so the dashboards can still separate deck types after the fact.

**Consequence to state plainly:** an ad may follow a topic-deck or Saved Cards
completion, not only the daily set. If the Owner wants the literal reading, the
narrowing is a single parameter on `noteSetCompleted`. Flagged for ratification.

---

## D12 — Event emission completeness

All 24 declared section 10.2 events now have a live emission site. Round 1
declared the full schema but left five unemitted: `card_flipped`,
`card_bookmark_changed`, `ad_eligible`, `ad_dismissed`, and
`review_prompt_eligible`.

`ad_eligible` and `ad_dismissed` are required section 15.2 launch metrics —
"eligible ad sessions, fill, impressions" cannot be computed without them, so a
declared-but-unemitted schema would have made the ad funnel unmeasurable the day
a PostHog token is configured. `ad_eligible` is raised before any provider call,
carrying `sets_since_last_ad` as it stood *before* the reset, so the funnel has a
true denominator. `review_prompt_eligible` is raised where the coordinator
records local eligibility, before the system API call, keeping "we asked Apple"
distinct from "Apple showed something".

---

## D13 — Interruption blockers are raised before the dialog is certain

When a reader taps **Turn On Reminders**, the app raises the `.notification` ad
blocker and records `.notificationPrompt` as a negative session event *before*
iOS has decided whether to present a dialog at all. On the paths where no dialog
appears — authorization already granted, or already denied — the blocker and the
disqualifier were still raised.

**This is deliberate and is not being changed.** The two mechanisms have opposite
failure costs:

- **Blockers and the rating disqualifier** are suppression mechanisms. Erring
  toward suppression costs at most one skipped ad impression or one deferred
  rating request. Erring the other way shows an interstitial over a permission
  moment, which is exactly what design section 9.3 forbids. Raising them on
  intent is the conservative direction.
- **`notification_permission_result`** is a *measurement*. Recording it on intent
  would report dialogs that never happened and corrupt the section 15.2
  authorization rate. That one is gated on a freshly read authorization status
  and fires only when a dialog actually resolved.

So the asymmetry is intentional: suppress on intent, measure on outcome.

---

## D14 — DEBUG-only test harness arguments

Three launch arguments exist in DEBUG builds only and are compiled out of
Release (Gate B item 11 requires no debug controls in the release UI); a fourth
(1.1.3) is honoured in every configuration because a test harness must never
depend on a DEBUG-only branch, and it only ever *suppresses* a prompt:

| Argument | Effect | Why it exists |
|---|---|---|
| `-skipStudioIntro` | Skips the studio intro animation | Pre-existing from 1.0 |
| `-econResetGrowthState` | Clears consent, reminders, ad counters, review progress, card state, and streak | UI tests need a fresh-install posture |
| `-econDisableAds` | Reports the device as ad-restricted | See below |
| `-EBSkipConsentPrompt` | Suppresses the 1.1.3 first-open analytics consent card (all configurations) | UI tests and screenshot runs; also an `InstrumentationContext` automation marker |

`-econDisableAds` routes through the real DUD-224 region gate, so the ad SDK is
never started and no request is made. It exists because one UI test drives the
app through two completed sets to prove the reminder primer arrives on the
second — and that second set-exit is the one moment where every ad gate passes.
In DEBUG the app uses Google's public test unit, which fills whenever the
machine has network, so without this the test would race a live interstitial and
pass or fail on network conditions rather than on the behaviour under test.

The ad path itself is still exercised for real: the first-set-exit UI test runs
without the flag and asserts that policy suppresses the ad, and the unit suite
covers fill, no-fill, and presentation failure deterministically with a spy
adapter.

---

## Open items for the Owner

1. Ratify D1 (no UMP) or fund a UMP integration as separate scope.
2. ~~Ratify D2 and schedule the Task 6 privacy-manifest and ASC privacy
   re-answer against the 1.1 archive privacy report.~~ **CLOSED 2026-08-30** —
   ruled Option B under the Owner's standing blanket approval on the Table Talk
   precedent, and applied in Task 6a; the manifests now match the approved
   portfolio posture and the archive was rebuilt on them. The ASC App Privacy
   answers remain a Task 6b entry action, using the configuration-level answers
   recorded in D2.
3. Ratify D3 (DudleyCore deferral).
4. Confirm the AdMob app and unit IDs in D6 against the console. **Submission
   blocker.**
5. Create the PostHog project and Sentry project in D5 and supply the credentials
   through build configuration.
6. Confirm the D4 paywall copy correction and the D8/D9 behaviour changes are
   acceptable for an update to an already-approved app.
7. Rule on Switzerland (D1a) for the whole portfolio — EconByte and Table Talk
   currently ship different restricted sets.
8. Ratify D10's one-set sequencing of the consent offer ahead of the reminder
   primer.
9. Ratify D11 — an ad can follow a topic-deck or Saved Cards completion, not only
   the daily set.

---

## D2 addendum — ATT is back in 1.1.2 build 13 (2026-09-07)

D2 above records why version 1.1 removed the AppTrackingTransparency pathway,
and the reasoning stands on its own terms: contextual, non-personalized ads do
not need the advertising identifier, and a declared tracking domain is blocked at
the network layer for every reader who declines. Nothing in that analysis was
wrong. What it did not account for is that the **App Privacy label is an
app-level record, and is not ours alone to set**.

Three facts, each verified rather than reasoned about, retire the decision:

1. **App Review rejected 1.1.2 build 12 on 2026-09-07 under Guideline
   5.1.2(i).** The published label answers "Identifiers > Device ID: used for
   tracking purposes", and the binary never asks.
2. **App Store Connect refuses to move that answer.** Setting Device ID to
   not-tracking was attempted and refused verbatim — *"Your app contains
   NSUserTrackingUsageDescription…"* — because the LIVE 1.1.1 (build 8) carries
   the key. The dialog was cancelled, not falsified. Recorded in
   `~/dudley-evidence-retention/econbyte/1.1.2-resubmission-2026-09-07/`.
3. **The ad SDK declares the tracking itself.** `GoogleMobileAds.framework`'s own
   `PrivacyInfo.xcprivacy` (12.14.0, read out of the built app rather than out of
   its documentation) declares `NSPrivacyCollectedDataTypeDeviceID` with
   `Tracking = true`. The aggregated privacy report Apple reads therefore says
   the app tracks regardless of what the app's own manifest says — so build 12's
   `NSPrivacyTracking = false` was the incoherent half, not the label.

So the binary moves to the label, which is Apple's own third remedy. What is
**not** reversed: ads stay non-personalized on every ATT answer, authorized
included. The portfolio invariant `adsPolicy.personalizedAdsMode: "disabled"` is
enforced outside this repo, so turning personalization on for authorized readers
is a policy revision across the portfolio, not an EconByte edit. Until that
happens, the prompt buys ad *measurement* and nothing more — which is exactly
what the usage-description string promises, and no more than it promises.

The cost D2 correctly identified is real and is accepted knowingly: readers who
decline will have `googleads.g.doubleclick.net` blocked, and will see no ads. That
is already true of the live 1.1.1 build 8, so build 13 is not a regression against
what is shipping today — but it IS a regression against build 12, and it is the
strongest argument for the personalization follow-up.

---

## D15 — First-open analytics consent card (1.1.3, Owner order 2026-09-14)

D10 put the two consent choices on the Session Complete screen after the first
completed set, on the design's "never on first launch" rule. The Owner's
2026-09-14 order for the whole portfolio is the opposite: analytics consent is
asked **once, on first open**, as a card revealed under the studio intro — the
Dudley factory pattern first shipped in Table Talk 1.1.5.

**What was implemented.** `FirstOpenConsentPolicy` + `AnalyticsConsentCard`,
mounted by `EconByteApp` in the same ZStack as Home, under the intro overlay.
Shown only when this process has a PostHog key and/or a Sentry DSN (an unkeyed
build — and every Debug/test process — shows nothing); two equal buttons, both
answers persisted; one answer sets both vendor consents through the same facade
paths Settings uses. While it is up no ad may present (`EconAdBlocker.consent`)
and the rating ask is deferred (`EconNegativeSessionEvent.consentForm`).

**D10 is not deleted, it is subordinated.** The Session Complete primer still
exists for the case where the first-open card did not ask (an unkeyed build),
and the two surfaces share one "answered" record: the card marks
`ConsentPromptPolicy.noteShown`, and an install the primer already asked is
never shown the card. One question, one answer, whichever surface asked it —
so a 1.1.2 upgrader who answered the primer is not asked again on update.

**Not the ATT prompt.** The card is product analytics only and its copy says so.
The tracking dialog (D2 addendum) stays where build 13 put it: once, from the
session-complete exit, before the first ad request.

---

## D16 — Anchored banner and interstitial pacing audit (1.1.3)

**Banner.** EconByte's only ad surface was the set-exit interstitial, which
needs two completed sets and (since build 13) an answered ATT prompt before it
can fire even once. 1.1.3 adds an anchored adaptive banner at the bottom of Home
and under the card in a card session (`AdBannerSlot`, `GoogleBannerView`),
production unit `ca-app-pub-9950526548980224/4084037009` created by the Owner in
the AdMob console on 2026-09-14; Debug can only select Google's public test
banner unit. It is gated by the same three checks as the interstitial before a
view is even constructed — entitlement, DUD-224 region, and the build-13 ATT
ordering (`EconMonetization.canRequestAds`) — so an entitled reader, an EEA/UK
reader, or a reader who has not yet answered ATT never has a banner requested,
and the SDK is never touched. It reserves no space until an ad has loaded.
Measured as `banner_impression_v1` (`placement` ∈ `home`, `card`).

**Interstitial pacing.** Audited against the lane's per-card target (no ad
before the 4th card, ~1 per 6 cards, ≤3 per session). EconByte paces by
completed sets, so the mapping and the two values that moved are recorded in
the `EconAdThresholds` doc comment: `setsSinceLastAd` 2 → 1 and `perSession`
1 → 2; `minimumCompletedSets` 2, `minimumInterval` 15 min and `perDay` 2 are
unchanged and are the retention guardrails. EconByte has no D1/D7 retention
series yet (Phase 7 of the 2026-09-14 loop builds it), so nothing beyond that
was spent. The release packet's statement "at most one interstitial per session"
(`AppStore/1.1/evidence/release-packet.json`) now reads "two"; the packet is
1.1's and is left as the historical record of that release.

**D11 still holds:** a topic-deck or Saved Cards completion counts as a set.

---

## D17 — Rating requests move to review-rules-v2 (1.1.3)

D9's rule (3 completed sets, 7 days since first launch, once per version) is
replaced by Table Talk's `review-rules-v2` on the Owner's 2026-09-14 order:
never on the first open; from the second launch, the first completed set of 5+
cards is the moment; once per app version; attempts at least 120 days apart; at
most two in any 365 days. The deferral list grows from D9's seven to eleven —
an ad, a purchase, a purchase failure, a restore, a restore failure, the consent
card/primer, a notification prompt, the ATT prompt, a paywall, an error alert,
a crash recovery — and a deferral never spends the version's one attempt.
The 1.1 single-slot ledger (`econ.review.lastRequestedVersion`) is still read,
so an install asked on 1.1.2 is not asked again for 1.1.2. The launch counter is
the one `app_opened_v1` buckets (`ebLaunchCount`), so the two cannot disagree
about what a launch is. No sentiment pre-prompt, as before.
