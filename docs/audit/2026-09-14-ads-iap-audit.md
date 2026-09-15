# EconByte 1.1.4 — Ads + IAP deep audit (Phase 11, 2026-09-14)

Branch `claude/econbyte-114-pro`. Audited by reading the code at `55ca689`
(Phase 10 head) end to end: `EconMonetization.swift`, `AdManager.swift`,
`AdBannerSlot.swift`, `FirstLaunchPermissions.swift`, `EconTrackingAuthorization.swift`,
`EconByteApp.swift`, every tab in `Views/Shell`, `CardModeView`, `SessionCompleteView`,
`BookmarksView`, `Courses/*`, `BriefView`, `PurchaseManager.swift`, `PaywallView`,
`ProPaywallView`, `PackOfferView`, `SettingsView`, `EconByte.storekit`, and the
portfolio policy it ships under (`Dudley-Development/config/app-factory/monetization-policy.json`
rev 3, `scripts/release_evidence_gate.mjs`). No App Store Connect writes.

Severity: **Critical** (money or access wrong for a paying user / review rejection risk) ·
**High** (visible defect or policy breach) · **Medium** (wrong in an edge state or
unmeasured) · **Low** (hygiene, copy, declaration).

## 1. Findings

### 1a. Ads

| # | Finding (evidence) | Sev | Fix | Test / evidence |
|---|---|---|---|---|
| A1 | Interstitial caps exceeded the portfolio cap policy EconByte declares no override for: `perSession = 2` (policy: 1 per foreground session) and nothing stopped an interstitial in the install's **first** session (policy `initialSessionInterstitials: 0`) — a fresh install finishing two sets in one sitting met an ad at its second exit. | High | `EconAdThresholds`: `perSession` 2→1, new `initialSessionInterstitials = 0` with persisted `foregroundSessionsLifetime` (upgraders with completed sets are not treated as first-session); new `EconAdDecision.initialSession`. | `GrowthSystemsTests.testShippedThresholdsMatchThePhase11PacingAudit`, `testTheInstallsFirstForegroundSessionCarriesNoInterstitial`, `testAnUpgraderIsNotTreatedAsAFirstSession`, `testOneInterstitialPerForegroundSession` |
| A2 | The daily cap was a **calendar-day** cap: 2 at 23:30 + 2 after midnight = 4 in ~1 h (policy: `maximumInterstitialsPer24Hours: 2`). | Medium | Rolling 24-h window on top of the calendar cap (`recentShownAt`, persisted). | `testTheDailyCapIsAlsoARolling24HourWindowAcrossMidnight`, `testRecentImpressionsPersistForTheRollingCap` |
| A3 | Ads could load under a first-launch system prompt: `applicationDidBecomeActive()` calls `startAdsIfPermitted()` **before** `FirstLaunchPermissionsCoordinator.runIfNeeded()`. For an upgrader whose ATT is already decided (or `.restricted`) but whose notifications prompt is still owed, the SDK started at launch and the Home banner could load behind Apple's notifications dialog. | High | `EconMonetization.isHeldForLaunchPermissions`: set in `EconGrowth.init` unless the flow is skipped; `startAdsIfPermitted` and `canRequestAds` honour it; released only when the coordinator finishes (or is skipped / the launch task cannot run). A separate flag, not the `.systemPrompt` blocker, so the 5.1.2(i) ordering tests keep their meaning. | `testTheLaunchPermissionHoldBlocksTheAdSDKUntilReleased`; existing `TrackingAuthorizationTests` (13) + `FirstLaunchPermissionsTests` still green |
| A4 | No request before the ATT answer — **verified, no defect**. SDK start, preload, re-preload and banner construction all pass `adRequestsPermitted` (status decided ∨ prompt already spent). | — | — | `TrackingAuthorizationTests.testTheAdSDKIsNotStartedWhileTheTrackingDecisionIsOutstanding`, `testThePromptPrecedesTheFirstAdRequest` |
| A5 | Placement matrix incomplete against the redesign: banner only on Home and card mode; Browse (a list surface) had none; a **bookmarks review** (portfolio sensitive surface `saved_reading`) carried the card-mode banner. No single place said which surface may show what. | Medium | New `EconAdSurface` matrix (§2) — the only way a view gets a banner. Added the Browse banner (at rest only); removed the banner from bookmarks review; News stays banner-free (brief = `article_body`). | `testThePlacementMatrix`; UI `ShellRedesignTests.testBannersSitAboveTheTabBarAndHomeIndicatorAndLeaveSearch` |
| A6 | A banner on a search screen would ride the keyboard up over the results (`.safeAreaInset(edge: .bottom)` follows the keyboard) and search is a sensitive surface (`search_result`, `financial_or_policy_search`). | Medium | Browse passes `.search` while the field is focused or holds a query → the slot is **removed** (not hidden: a hidden live banner is still requested/counted). | UI test above (banner absent while typing) |
| A7 | Banner telemetry counted loads, not impressions (`banner_impression_v1` on first `didReceiveAd` per slot); banner no-fill/failure and every click were unmeasured. | Medium | `banner_impression_v1` on `bannerViewDidRecordImpression`; new `banner_load_finished_v1 {placement, outcome: filled/no_fill/failed}` on outcome change per slot; new `ad_clicked_v1 {placement}` (banner + interstitial). | `EconTelemetryTests` declared-event/producer scans (every new event and value has a producer) |
| A8 | Interstitial `ad_impression_v1` fired on the call to `present(from:)`, not on the SDK's recorded impression; every load error was reported as `no_fill`; a `canPresent` failure emitted nothing. | Medium | Impression moved to `adDidRecordImpression`; click on `adDidRecordClick`; `EconAdErrorClassifier` separates `GADErrorNoFill` (domain `com.google.admob`, code 1) from other failures; `canPresent` failure emits `ad_dismissed_v1 outcome=failed`. | `StoreEntitlementsTests.testAdErrorsSeparateNoFillFromFailure` |
| A9 | A preloaded interstitial was held forever; Google expires them after 1 h, so a reader who finished a set more than an hour after launch hit a dead ad (silent `presentationFailed`) at the one placement. | Medium | `loadedAt`; `isAdLoaded` false after 55 min and `preload` replaces it. | `testAdErrorsSeparateNoFillFromFailure` (age constant); behaviour is SDK-bound |
| A10 | Declared category blocks (`blockedSensitiveCategories`) did not include the portfolio's `providerCategoryBlocks` (adult/sexual, controlled substances, religion, simulated gambling, violence). Console-enforced, but the app's declaration is the Owner's checklist. | Low | Union declared. | `testDeclaredCategoryBlocksCoverThePortfolioPolicy` |
| A11 | Remove Ads / Pro entitled readers never request — **verified**. The banner view is not constructed and the SDK never starts for `adsSuppressed`; with Phase 11's mirror change a paying reader also stays ad-free in the second before StoreKit answers on a cold launch. | — | (see I3) | `testRemoveAdsPurchaseImmediatelySuppressesAdsAndNeverStartsTheSDK`, `testUserDefaultsMirrorsNeverGrantAccessAndOnlyHoldAdsOffUntilVerified` |
| A12 | Banner layout: `.safeAreaInset(edge: .bottom)` on the tab scaffold / card VStack — sits above the tab bar and above the home indicator, reserves 0 pt until filled. **Verified by UI test with Google's test unit (filled on the iPhone 17 simulator):** Home strip y 728–791 pt (63 pt) with the iOS 26 tab bar starting at 791 pt; Browse strip above the tab bar; no banner while searching; card-session strip above the home indicator and below Next. The element's accessibility frame runs on through the bottom safe area (maxY 874), so the test measures the visible strip via a DEBUG height value. Screenshots `phase11/p11-10…13`. | — | — | `testBannersSitAboveTheTabBarAndHomeIndicatorAndLeaveSearch` |
| A13 | `EconByte.storekit` Remove Ads description said "Remove all interstitial ads" — banners are removed too. Local config only; the **ASC** description of the approved product should be checked by the Owner. | Low | Local text fixed. Owner item. | — |
| A14 | The portfolio policy declares one EconByte banner placement (`feed_footer_banner`); the app now has three banner slots (Home, Browse, card). Declaration drift, not a code defect. | Low | Recommendation: add `browse_footer_banner` + `card_session_banner` to `policies[econByte].placements` in a control-plane change. | Report §Owner |

### 1b. IAP

| # | Finding (evidence) | Sev | Fix | Test / evidence |
|---|---|---|---|---|
| I1 | **Raw placeholders** when products have not loaded (orchestrator, Phase 10 screenshots): Pro tiles "—", button "Subscribe for —", pack CTA "Unlock Personal Finance — —", Settings rows "—", Settings Pro row "from —/mo". | High | `PurchasePresentation.PriceState` (`loading` / `unavailable` / `ready`) per product; buttons read "Loading price…" while fetching, the bare action ("Subscribe", "Unlock Personal Finance") **disabled but readable** without a price, with a "Prices unavailable — Try again" notice (retry); Settings rows show a spinner / "Unavailable" / "See plans". No price literal anywhere. | `StoreEntitlementsTests.testNoPurchaseLabelEverShowsARawOrDoubledPlaceholder`, `testPriceStateIsLoading…`, `testNoViewRendersTheLegacyPlaceholder`; UI `ShellRedesignTests.testPurchaseControlsNeverShowARawPlaceholder` (+ screenshots) |
| I2 | **Billing retry lost Pro**: access came only from `Transaction.currentEntitlements`, which excludes a subscription in billing retry; no `Product.SubscriptionInfo.Status` was read, so grace period / billing retry / revoked were invisible and Settings could not say "Payment issue". | High | `EntitlementResolver` combines current entitlements with the group statuses: `subscribed`, `inGracePeriod`, `inBillingRetryPeriod` keep Pro (Owner brief); `expired`/`revoked` do not; unverified statuses ignored. Settings/Pro tab show "Payment issue" + "Update your payment method…". | `testGracePeriodKeepsAccessAndSaysPaymentIssue`, `testBillingRetryKeepsAccessFromTheStatusAlone`, `testARevokedSubscriptionGrantsNothing…`, `testAnUnverifiedStatusIsIgnored`; SKTestSession `testAFailedRenewalKeepsProInGracePeriodOrBillingRetry` |
| I3 | **UserDefaults mirrors granted access on their own**: `PurchaseManager.init` seeded `isUnlockAllPurchased`, `isProActive` and owned packs from UserDefaults, so every topic/pack/course/brief was open on a cold launch before (or without) StoreKit verification — a plist edit unlocked Pro. | High | Content access starts locked and comes only from verified StoreKit data (`hasVerifiedEntitlements`). The Remove Ads / Pro mirrors are read for one thing: `provisionalAdsSuppression` keeps ads **off** for a paying reader until StoreKit's first answer. Unlock All / pack mirrors are no longer written. | `testUserDefaultsMirrorsNeverGrantAccessAndOnlyHoldAdsOffUntilVerified` |
| I4 | Unverified transactions were **never finished** (listener `continue`d; `purchase()` threw before `finish()`), so StoreKit re-delivered them on every launch; the purchase path showed the raw `failedVerification` error text. | Medium | Unverified → diagnostic + `finish()`, never grants; reader copy "The App Store couldn't verify this purchase…". | `testAnUnverifiedTransactionNeverGrants`; SKTestSession `testAPurchaseGrantsItsPackAndLeavesNothingUnfinished` (no unfinished transaction) |
| I5 | Ask to Buy: after `.pending` the buy control went live again, inviting a duplicate request; nothing told the reader it was waiting. | Medium | `pendingProductIDs` (cleared by the approving transaction or on resolution): the control reads "Waiting for approval" and is disabled; alert "Waiting for approval". | SKTestSession `testAskToBuyIsPendingUntilApprovedThenGrants` |
| I6 | Restore: "nothing to restore" was returned as `.failed(…)` and shown as **"Something Went Wrong"** on the paywalls and pack offers; cancelling the Apple ID sheet (`StoreKitError.userCancelled`) was also shown as an error with StoreKit's text; a successful restore from a paywall said "Your purchase is processing". | Medium | `PurchaseResult.nothingToRestore`; cancel → silent; one `PurchaseAlertCopy` for every surface ("Purchases restored", "Nothing to restore", …). | `testEveryResultMapsToOneConsistentAlert`; SKTestSession `testRestoreFindsPurchasesAndSaysSoWhenThereAreNone` |
| I7 | Purchase errors showed `error.localizedDescription` (third-party, sometimes technical/empty); Screen Time purchase restrictions (`AppStore.canMakePayments == false`) were not detected. | Medium | `PurchaseFailureReason.classify` (network / not allowed / storefront / unavailable / verification / unknown) with reader copy; `canMakePayments` checked before buying. | `testStoreKitErrorsAreClassifiedAndCancelIsNotAFailure`; SKTestSession `testAFailedPurchaseShowsReaderCopyNotStoreKitText`, `testACancelledPurchaseGrantsNothingAndIsNotAFailure` |
| I8 | Monthly ↔ annual: both plans were `groupNumber: 1` in `EconByte.storekit` (a crossgrade at the same level), so monthly → annual was not an immediate upgrade; `isUpgraded` transactions were not excluded; `willAutoRenew` and the pending renewal product were never read, so Settings could not say "Renews" vs "Ends" or "Switches to Monthly". | Medium | Annual level 1, monthly level 2 (Owner must mirror in ASC); `isUpgraded` grants nothing; `ProStatusCopy` rows Plan / Renews·Ends·Current period ends / Switches to / Shared by. | `testTheLocalConfigurationRanksAnnualAboveMonthly`, `testAnUpgradedAwayTransactionGrantsNothing…`, `testAScheduledDowngradeIsShownAsAPlanChange`, `testACancelledSubscriptionShowsItsEndDate…`; SKTestSession `testMonthlyToAnnualIsAnImmediateUpgrade` |
| I9 | "Manage Subscription" opened `apps.apple.com/account/subscriptions` in Safari (leaves the app; no refresh on return). | Low | `manageSubscriptionsSheet` (Apple's `showManageSubscriptions`) in Settings, the Pro tab and the paywall's subscriber state; entitlements refresh when it closes. | Compile + UI (`settingsManageSubscriptionLink`, `proManageSubscriptionLink` still present) |
| I10 | Product loading was not single-flight: Settings, the paywall and `init` fetched concurrently, and the first to finish flipped `isLoadingProducts` off while others were running; a failed reload wiped prices that had loaded; nothing retried after an offline launch. | Medium | Single-flight `loadProducts`; failed reload keeps earlier products; reload on foreground when no prices. | Covered via `priceState` tests; SKTestSession `testEveryProductLoads…` |
| I11 | `PackOfferView` always reported purchases and restores `from: .home`, so every Browse pack purchase was attributed to Home. | Low | Uses its `entryPoint`. | Code read |
| I12 | App Store **promoted IAP** (`PurchaseIntent`) not handled — tapping a promoted product on the App Store launched the app and did nothing. | Low | `PurchaseIntent.intents` listener (iOS 16.4+) → `purchase(…, from: .appStorePromotion)`; new `entry_point` value. | `EconTelemetryTests` producer scan |
| I13 | Family Sharing — **verified, no defect in grants** (family-shared transactions are in `currentEntitlements`); ownership was not surfaced. All products are `familyShareable: false` today. | Low | `ownership` carried; Settings / pack show "Family Sharing ✓"; Pro row "Shared by". | `testFamilySharedTransactionsGrantAndAreReported` (SKTestSession cannot mint a family-shared transaction) |
| I14 | Entitlement precedence — **verified**, now pinned in one pure type: Pro ⇒ core topics + every pack + no ads (without writing the one-time flags); Unlock All ⇒ core only, never a pack (D18); pack ⇒ own pack; Remove Ads ⇒ no ads only; a pack bought outright survives Pro lapsing. | — | `ResolvedEntitlements` | `testPrecedenceMatrix` |
| I15 | `Transaction.updates` listener started at launch (`@StateObject PurchaseManager.shared` in `EconByteApp`) and refunds/revocations handled via `revocationDate` — **verified**; the listener now also clears pending state. Intro-offer eligibility gates the trial line — **verified**; the trial line now also requires a real price. | — | — | SKTestSession `testARefundRevokesAccess`, `testASubscriptionGrantsProUntilItExpires` (trial spent ⇒ `isEligibleForTrial == false`) |
| I16 | Paywall 3.1.2 copy: plan tiles said only "Yearly/Monthly" (no subscription title) and the terms omitted "charged for renewal within 24 hours before the period ends". | Low | Tiles "Pro Yearly / Pro Monthly"; terms name the auto-renewing subscription and the 24-hour renewal charge. | UI evidence `p11-01-pro-prices` |

**Counts (25 defects):** Critical 0 · High 5 (A1, A3, I1, I2, I3) · Medium 12 (A2, A5, A6, A7, A8, A9, I4, I5, I6, I7, I8, I10) · Low 8 (A10, A13, A14, I9, I11, I12, I13, I16) · plus 5 verified-no-defect rows (A4, A11, A12, I14, I15). All 25 fixed in code except A13 (ASC copy) and A14 (control-plane declaration), which are Owner items.

## 2. Placement matrix (after the 1.1.4 redesign)

| Surface | Banner | Interstitial | Decision and reasoning |
|---|---|---|---|
| Home tab | **Yes** — anchored above the tab bar | No | Feed of today's items, the most-visited list surface; the strip reserves no space until filled, so a no-fill costs nothing. |
| Browse tab (at rest) | **Yes** — anchored above the tab bar | No | Topic/pack grid is a browsing list — the portfolio's `feed_footer_banner` shape. New in Phase 11. |
| Browse search (field focused or has a query) | No (slot removed) | No | `search_result` / `financial_or_policy_search` are sensitive surfaces; the keyboard would also lift the strip over results. |
| News tab — Daily Brief (teaser or full) | No | No | The brief is `article_body`. Ad-eligible readers only ever see the teaser + Pro upsell; a banner there would sit inside the brief document and next to an offer whose headline benefit is "no ads". |
| News archive (Pro) | No | No | Pro-only; Pro never sees ads. |
| Pro tab (inline paywall + courses) | No | No | `purchase` surface (3.1.2 paywall); ads beside a subscription offer confuse the price hierarchy. |
| Course / lesson (incl. free first lessons) | No | No | Long-form learning and `quiz_explanation`; interrupting a lesson is the highest churn risk. Lesson-exit interstitial for free lessons evaluated and **not** added: at most 3 free lessons exist, and they are the Pro trial's funnel. |
| Quiz | No | No | `quiz_explanation`. |
| Card mode (topic / daily set) | **Yes** — under the Next button, above the home indicator | No | Established 1.1.3 surface; the strip never overlaps the card or Next. |
| Bookmarks list / bookmarks review | No | No | `saved_reading`. Phase 11 removed the card-mode banner from bookmark reviews. |
| Set complete screen | No | **Yes, on exit** (after Done / Browse More) | The one natural break. Pacing below. |
| Unlock All paywall / Pro paywall / pack offers | No | No (`.paywall`, `.purchase`, `.restore` blockers) | `purchase` / `restore`. |
| Settings (sheet) | No | No | `privacy` / `consent`. |
| Studio intro, ATT + notifications prompts | No | No | `onboarding` / `permission`; `isHeldForLaunchPermissions` keeps the SDK from starting until both prompts resolve. |

**Interstitial pacing (retention guardrails), `EconAdThresholds`:** none before the 2nd completed
set lifetime · none in the install's first foreground session · ≥1 completed set since the last ·
≥15 min apart · ≤1 per foreground session · ≤2 per calendar day and ≤2 per rolling 24 h · never
over a purchase, restore, paywall, consent, review request, notification prompt, error or system
prompt · no-fill/failure is silent and consumes no cap. **Guardrail:** if Phase 7 shows D1 of
ad-eligible installs >15 % below entitled installs after 1.1.4, move to `minimumCompletedSets 3`
and `setsSinceLastAd 2` before touching the banners.

**Request policy:** SDK start/preload only after the ATT answer and the launch-prompt hold;
`npa=1`, `rdp=1`, `publisherPrivacyPersonalizationState = .disabled` on every request whatever
the ATT answer; `maxAdContentRating = .general`; no ads in the EEA (EU27 + IS/LI/NO) or GB, or
when the region is unknown (DUD-224); none for Remove Ads or Pro.

## 3. Recommendations for the Owner (not shipped)

### (a) Personalized ads for readers who tapped Allow on ATT — **recommend: not now; revisit at ≥1,000 DAU**
- *Upside.* Only the ATT-authorized share of ad-eligible readers (industry 27–50 %; EconByte has no
  measured opt-in rate yet) would move from non-personalized to personalized eCPM. Vendor estimates of
  the NPA penalty range 20–80 % (single-vendor, contradictory). With the portfolio's own
  ceiling math (`growth-research-2026-09/04-ad-revenue.md`: ≈$0.005–0.010 ARPDAU realistic) and
  EconByte's current volume, the delta is cents per day.
- *Cost.* (1) Portfolio policy: `adsPolicy.personalizedAdsMode: "disabled"` is gate-enforced
  (`release_evidence_gate.mjs` POLICY_PERSONALIZATION, twice) and DudleyCore's
  `MonetizationPolicyRegistry` throws on `personalizedAdsEnabled` — a policy revision for every app,
  not an EconByte edit. (2) App Privacy label: already "Device ID — used to track you" (5.1.2(i),
  build 13), but personalization adds *Advertising Data / Product Interaction used for Third-Party
  Advertising* disclosures and a privacy-policy update. (3) US state privacy law (CCPA/CPRA
  "sharing" for cross-context behavioral advertising) needs an opt-out path; `rdp=1` would have to
  become conditional. (4) The ATT purpose string currently promises "EconByte does not personalize
  ads" — it would have to change, and readers who already said Allow under that promise should not
  be switched silently.
- *If approved later:* flip only `EconAdRequestPolicy.extras` for `trackingStatus == .authorized`
  (the seam `providerWouldPermitPersonalizedAds` exists), keep `rdp=1` for CA/US-state opt-outs,
  bump the policy revision, update the label + purpose string, and measure opt-in rate and eCPM
  split in Phase 7 dashboards first.

### (b) Rewarded ad ("watch an ad to unlock one locked card set / today's full brief for a day") — **recommend: no for the brief; maybe later for one locked core topic, behind a flag**
- *Brief:* **No.** The Daily Brief is Pro's headline benefit and the trial's hook; renting it for
  a 30-second video undercuts a $4.99/mo subscription for pennies of ad revenue, and puts an ad on
  the `article_body` surface.
- *One locked core topic for 24 h:* defensible under AdMob's rewarded policy (opt-in, disclosed,
  non-monetary reward, skipping leaves the app usable) and the portfolio cap allows
  `maximumRewardedOffersPer24Hours: 1`. But it competes with $0.99 Unlock All (the first-purchase
  product for new markets such as the Nigerian learner community) and needs a new rewarded unit, a
  new placement declaration, a new sensitive-surface review and UI. Revisit only when Phase 7 shows
  Unlock All paywall views with low conversion in ad-served regions — then test it as a
  paywall secondary action ("Watch an ad to read this topic today") for 10 % of installs.

### (c) Add Switzerland (CH) to EconByte's no-ads region list — **recommend: yes (one-line change, tiny revenue cost)**
- Table Talk already restricts CH (revised FADP; its `restrictedRegionCodes` has 32 codes), the Phase
  10/11 brief says "EEA/UK/CH no ads", and EconByte's `EconAdRegion.restrictedRegionCodes` has 31
  (no CH). Swiss readers today get ads **and** the ATT prompt.
- Cost: CH is a rounding error in impressions at current volume. Benefit: one consent posture across
  the portfolio; no FADP question.
- Change when approved: add `"CH"` to `EconAdRegion.restrictedRegionCodes`, update
  `GrowthSystemsTests.testRestrictedRegionsCoverTheEEAAndUnitedKingdom` (31 → 32), note it in
  `CONTENT-DECISIONS.md` (DUD-224 addendum). CH readers would then also stop seeing ATT (no ads ⇒
  no prompt) and their analytics stays an explicit opt-in.

## 4. StoreKit Testing — `SKTestSession` cannot run under `xcodebuild` on this Mac (proof)

`EconByteTests/StoreKitSessionTests.swift` implements the full matrix with `SKTestSession(contentsOf:
EconByte.storekit)` — load + trial eligibility, purchase (no unfinished transaction), cancel, failure
copy, Ask to Buy pending → approve, refund, expiry, monthly → annual upgrade, failed renewal (grace /
billing retry), restore (nothing / restored). Under `xcodebuild test-without-building` on the iPhone 17
simulator (Xcode 26.5, 17F42) it does not attach:

1. **Run 1** (`phase11/unit1.log`): the first session test hung for 12 min inside `product.purchase()`.
2. **Run 2** (`phase11/skt1.log`, every StoreKit await behind a 30 s timeout with `[SKT]` markers):
   `SKTestSession` init/reset/clear returned, but `Product.products` returned **4** products — exactly
   the four that exist in App Store Connect (`unlockall`, `removeads`, `pack.markets`, `pack.personal`),
   not the 10 in `EconByte.storekit` — so StoreKit was answering from the **sandbox App Store**.
   Purchases of those sandbox products never returned (sandbox sheet); `pro.monthly` purchases
   returned `productUnavailable`; `expireSubscription` / `forceRenewalOfSubscription` threw
   `SKInternalErrorDomain Code=3`.
3. **Run 3** (`phase11/skt2.log`) with the test host's `PurchaseManager.shared` made inert (no StoreKit
   call before the session exists, to rule out the host binding the process to the sandbox first):
   identical — and `SKTestSession` itself now logs on init `Error saving configuration file`, `Error
   clearing overrides`, `Error setting value …`, `Error deleting all transactions`, all
   `SKInternalErrorDomain Code=3`. The StoreKit test daemon refuses the session; this is the same
   environment gap Phase 8 found for the scheme's `.storekit` under `xcodebuild`.

Consequence: `StoreKitSessionTests.setUp` detects the missing local-only products and **skips** with
that evidence (they will run in Xcode ⌘U, where the StoreKit test environment attaches), and the state
matrix is covered deterministically through the protocol-free seam (`StoreTransactionSnapshot` /
`StoreSubscriptionStatusSnapshot` → `EntitlementResolver`) in `StoreEntitlementsTests`: purchase,
unverified, refund/revocation, precedence, family sharing, offline subscription, expiry, revoked
status, grace period, billing retry, upgrade (`isUpgraded`), scheduled downgrade, cancelled
auto-renew, mirrors-never-grant, price states, error classification, alert copy, subscription ranking.
Not provable here: Ask to Buy's pending state, the unfinished-transaction check and real restore are
exercised only in the skipped session tests — they need an Xcode ⌘U run (or a sandbox Ask-to-Buy
account on a device).
