# EconByte: Daily Economics

A SwiftUI iOS card app — bite-sized economics concepts (inflation, interest
rates, GDP, trade) as swipeable daily cards. Educational only; not financial
advice.

- Bundle id: `com.nsantulli.econbyte` · ASC app id `6780714383`
- Current version in this tree: **1.1.4 (build 16)** — live is 1.1.2 build 13;
  1.1.3 build 15 is in review. **1.1.4 has had no App Store Connect writes:** the
  subscription and the four new pack products exist only in `EconByte.storekit`
  until the Owner creates them (same ids, no code change needed).
- Freemium: Inflation + Interest Rates free; the other 13 topics behind
  **Unlock All Topics** (`com.nsantulli.econbyte.unlockall`, $0.99). **Remove
  Ads** (`com.nsantulli.econbyte.removeads`, $0.99) is a separate purchase.
  Six **topic packs** at $1.99 each, four topics × twelve sourced cards each in
  `Resources/packs-v1.json`: Markets & Investing Basics (`pack.markets`),
  Personal Economics (`pack.personal`) from 1.1.3, plus Economic History
  (`pack.history`), Economies Around the World (`pack.world`), Economic Systems
  (`pack.systems`) and Personal Finance (`pack.personalfinance`) from 1.1.4.
  Unlock All does **not** include packs (CONTENT-DECISIONS D18).
- **EconByte Pro** (1.1.4, D19): an auto-renewable subscription —
  `com.nsantulli.econbyte.pro.monthly` $4.99/month, `…pro.annual` $29.99/year,
  7-day free trial as an introductory offer — that unlocks three **courses**
  (`Resources/courses-v1.json`), the **Daily Economic Brief**, every pack and
  core topic, and removes ads while active. Packs bought outright stay owned
  after a lapse. See "EconByte Pro" below.
- To run it: see [RUN-ON-DEVICE.md](RUN-ON-DEVICE.md).

## EconByte Pro (1.1.4)

**Entitlement.** `PurchaseManager.isProActive` is true when
`Transaction.currentEntitlements` carries a verified, unrevoked, unexpired
transaction for either subscription id (StoreKit already excludes lapsed
subscriptions and includes grace/billing-retry). It is mirrored to
`iap.pro.active` for synchronous cold-launch gating, rechecked on launch, on
foreground, and on `Transaction.updates`. `hasAccess(packProductID:)` = owned ∨
Pro; `coreTopicsUnlocked` = Unlock All ∨ Pro; `adsSuppressed` = Remove Ads ∨ Pro.
`EconEntitlements.pro` carries it into the ad policy, so a subscriber never has
the ad SDK started or the ATT prompt asked.

**Paywall** (`Views/ProPaywallView.swift`, App Review 3.1.2): the billed price
is the largest element (plan cards + subscribe button); the "7-day free trial,
then $X / period" line is smaller, beneath it, and shown **only** when
`Product.SubscriptionInfo.isEligibleForIntroOffer` is true; what you get; the
auto-renewal terms; Terms of Use (Apple's standard EULA) and Privacy Policy
links; Restore. Prices are StoreKit `displayPrice`, never literals. The Unlock
All paywall (`PaywallView`, "Purchases") is unchanged.

**Courses** (`Content/CourseCatalog.swift`, `Resources/courses-v1.json`): three
courses — Investing Approaches (9 lessons), Reading Price Charts (9), Bonds,
Rates and the Yield Curve (9) — each lesson an ordered list of blocks
(`paragraph`, `callout`, `keyTerms`, `diagram`, `chart`, `quiz`, `takeaways`).
Charts are Swift Charts over **synthetic, labelled series** bundled in the block
(no market data anywhere); diagrams are the fourteen SwiftUI drawings in
`Views/Courses/DiagramView.swift`. The first lesson of every course is free.
Progress is local (`CourseProgressStore`). Loader and validator fail closed;
editorial rules (approved hosts, no advice/prediction framing, no named
securities or brands, no stale wording) are enforced by `ProCoursesBriefTests`
and mirrored in `scripts/validate_content.mjs` for writers.

**Daily Brief** (`Content/DailyBrief.swift`, `Services/BriefStore.swift`,
`Views/BriefView.swift`): a per-business-day JSON document produced server-side
**from official releases only** (BLS, BEA, Census, Treasury, Federal Reserve,
CBO and open-licence peers — the complete list is `DailyBrief.allowedHosts`),
never a news site. The app fetches
`https://dudleyapps.com/econbyte/brief/latest.json` (may 404 until the job
exists), validates it fail-closed, caches the newest 30, and otherwise shows the
newest of the five bundled samples `Resources/brief-sample-YYYY-MM-DD.json`
(labeled SAMPLE, one per recent business day; the older four fill the archive). Free readers see the headline and first item; Pro
readers see everything. Server job spec: `docs/daily-brief/SERVER.md`.

**Telemetry** (allowlisted, bucketed, tested): `pro_paywall_shown_v1`,
`pro_trial_started_v1`, `pro_subscribed_v1`, `course_lesson_completed_v1`
(`course_family` ∈ investing/charts/bonds + `quiz_correct`), `brief_opened_v1`
(`access_state`, `brief_source`). No product id, price, expiry, lesson id, or
headline can ride.

**Content tooling:** `node scripts/validate_content.mjs packs|courses|brief
<file> [--fragment] [--net]` — the writer-facing mirror of the Swift gates;
contract in `docs/content/CONTENT-SCHEMA-1.1.4.md`.

## Build and test

```
xcodebuild test -project EconByte.xcodeproj -scheme EconByte \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:EconByteTests
```

`EconByteTests` is the unit target (schema, queue, privacy posture);
`EconByteUITests` drives the app. The project is generated from `project.yml`
via xcodegen, but `EconByte.xcodeproj` is committed and authoritative.

---

## Instrumentation (analytics & diagnostics)

Two vendor SDKs are linked behind the `TelemetryTransporting` /
`DiagnosticsTransporting` seams. **Live from 1.1.2**; 1.1 and 1.1.1 had no
analytics and no crash reporting at all.

- **Product analytics → PostHog**, project **`econbyte`**.
- **Crash diagnostics → Sentry**, project **`econbyte`** (crash-only: no
  sessions, no app-hang or watchdog reports, no session replay, no tracing, no
  profiling). `enableAutoSessionTracking` defaults to ON in sentry-cocoa and is
  explicitly OFF here — a session envelope is a per-launch usage record, not a
  crash, and the app's copy says crash reports.

Never reuse another Dudley app's project. Table Talk's projects are
`table-talk` / `tabletalk` and are separate on purpose — cross-app identity
separation depends on the projects being distinct.

### Defaults (1.1.2 → 1.1.3)

| | Default | User control | Where |
|---|---|---|---|
| PostHog usage analytics | **OFF** (opt-in) | first-open card, then a switch | Settings → Privacy & Data → "Share Usage Analytics" |
| Sentry crash reports | **OFF** (opt-in) | first-open card, then a switch | Settings → Privacy & Data → "Share Crash Diagnostics" |

Both are opt-in because that is what version 1.1's published App Store notes
promise ("separate opt-in choices, both off by default"); the 1.1.2
reconciliation kept that posture rather than reverse a published promise on
update (`RECONCILIATION-LOG.md` §5).

**First-launch permissions (1.1.4; replaces the 1.1.3 first-open consent card
and the at-first-set-exit ATT ask).** After the studio intro fades the app asks
Apple's standard App Tracking Transparency prompt, then Apple's standard
notifications prompt — no custom pre-prompt screens. ATT "Allow" turns usage
analytics and crash reports on (any other answer leaves them off);
notifications granted turns the daily reminder on at the stored time (default
7:00 p.m.). Both stay switchable in Settings. Once per install; an upgrader's
earlier answers are honoured (never re-prompted, never re-mapped). Readers
who cannot see ads (Remove Ads, Pro, EEA/UK) are not shown ATT. Code:
`EconByte/Services/FirstLaunchPermissions.swift` (tests:
`FirstLaunchPermissionsTests`). `-EBSkipPermissionPrompts` or the older
`-EBSkipConsentPrompt` stands both prompts down (every UI test passes one).
See `CONTENT-DECISIONS.md` D22, including the open GDPR question.

What ships when analytics is on is small enough to defend: only a typed,
allowlisted event set can reach PostHog (see
`EconByte/Services/EconTelemetry.swift`) — bucketed, anonymous counts of which
topics and modes get used, never a card, a definition, a bookmark, a price, or
an exact timestamp. The validator drops anything undeclared *before* it is
queued, so "on" cannot come to mean more than it means today without a schema
change and a review.

Switching analytics off stops capture before the call returns, clears this app's
queue, calls the SDK's own `optOut()`, tears the SDK down, **deletes the SDK's
storage directory**, and persists the answer (`econ.telemetry.consent`, absent
means "never answered", which is OFF). Switching it back on gets a **new** id,
so the two sides of an opt-out cannot be stitched together.

The directory deletion is not belt-and-braces, it is the fix: posthog-ios
`PostHogStorage.reset()` deliberately skips the event queue, so `reset()` +
`close()` alone leave unsent events on disk that ship the moment analytics is
re-enabled — after the user was told the queue was cleared. Removing the
directory also clears the SDK's persisted `optOut` flag, without which
re-enabling would be silently dead.

### The Analytics ID

Settings shows **PostHog's own distinct id**, read back with `getDistinctId()`.
The app mints no id of its own. It used to: an app UUID was handed to
`identify()`, which posthog-ios **ignores** under `personProfiles = .never`
(`PostHogSDK.identify` bails at `requirePersonProcessing`), so events were keyed
by the SDK's anonymous id while Settings displayed something else and promised
deletion by it. A support request quoting the old displayed id would have
matched nothing. When the SDK cannot answer, the row reads **"not available"** —
never a placeholder a user could quote.

Fail-soft: **no key/DSN → the SDK is never initialised**, whatever the defaults
say. A checkout without `Config/Secrets.xcconfig` collects nothing, and Settings
then says "Off — nothing is collected" instead of offering a switch that does
nothing.

### No production analytics from test runs

A **unit-test host**, a **UI-test / automation launch**, or **any Debug build**
resolves *no credentials at all* and therefore configures neither SDK — see
`EconByte/Services/InstrumentationContext.swift`. Test relaunches were writing
`app_opened_v1` into the production project and a deliberate test crash could
have reached production Sentry; ingested test traffic is indistinguishable from
user traffic and PostHog has no delete-by-property, so the only fix is not to
send it.

The single deliberate way in is the launch argument **`-AllowAnalyticsInDebug`**,
which the ingestion proof passes and nothing else does. Release is unaffected:
none of the three markers exists in a shipped run.

> **Analysts:** sim/test events reached PostHog project `econbyte` (594265) and
> the `econbyte` Sentry project during the 1.1.2 instrumentation work on
> **2026-09-04 and 2026-09-05**. Exclude that window; from this change on,
> only a run carrying `-AllowAnalyticsInDebug` can produce it.

### Proving it, without shipping a switch

`-EBInstrumentationSmoke YES` forces analytics on for one run and logs the
resolved state and the SDK's distinct id; `-EBInstrumentationCrash YES` crashes
the app on purpose three seconds after launch so the next launch uploads a
Sentry report. Both are **DEBUG-only** and compiled out of Release, and from
1.1.2 both need **`-AllowAnalyticsInDebug`** alongside them to reach the live
projects:

```
xcrun simctl launch <sim> com.nsantulli.econbyte \
  -EBInstrumentationSmoke YES -AllowAnalyticsInDebug YES
```

### How config is supplied (names only — never keys/DSNs in git)

Credentials come from a **gitignored** xcconfig, surfaced into Info.plist and
read at runtime. Nothing secret is ever committed.

```
Config/
├── Instrumentation.xcconfig     # committed base: empty defaults + #include? of secrets
├── Secrets.xcconfig.example     # committed template (empty placeholders)
└── Secrets.xcconfig             # GITIGNORED — the real values live here
```

Keys: `POSTHOG_API_KEY`, `POSTHOG_HOST` (optional; defaults to PostHog US
cloud), `SENTRY_DSN` → Info.plist `EBPostHogAPIKey` / `EBPostHogHost` /
`EBSentryDSN`. An empty or absent value = the SDK never initializes. To
configure: `cp Config/Secrets.xcconfig.example Config/Secrets.xcconfig` and fill
it in out of band. **Note the xcconfig `//` gotcha for URLs — see the comments
in the example file.**

### Release key gate (1.1.3)

Table Talk 1.1.4 shipped with an empty `POSTHOG_API_KEY` because the archive Mac
had no `Config/Secrets.xcconfig`. EconByte now closes that at the project level:
the first build phase of the app target, **"Instrumentation key gate"**
(`KG0000000000000000000001` in the committed pbxproj), fails any **Release +
iphoneos** build (archive / device install) whose `POSTHOG_API_KEY` is empty,
and warns when `SENTRY_DSN` is empty. Simulator and Debug builds are untouched.
To ship unkeyed on purpose pass `EB_ALLOW_UNKEYED_RELEASE=YES`. Pinned by
`GrowthAuditTests.testProjectCarriesTheInstrumentationKeyGate`.

### App Privacy

The three data types 1.1.2 adds (User ID, Crash Data, Product Interaction) are
all **not linked** and **not used for tracking**. The ad-side declarations
(`NSPrivacyTracking`, the googleads tracking domain, the ATT prompt) are
unchanged. The exact ASC edits are in
[`AppStore/1.1.2/app-privacy-answers.md`](AppStore/1.1.2/app-privacy-answers.md).

---

## Ads (1.1.3)

Two surfaces, one policy layer (`EconByte/Services/EconMonetization.swift`):

- **Interstitial** — one placement, the return from a completed set to Home.
  Pacing audited 2026-09-14: first interstitial no earlier than the **second**
  completed set; then every completed set is an eligible exit; at most **two
  per foreground session**, **two per calendar day**, **fifteen minutes apart**.
  The reasoning is in the `EconAdThresholds` doc comment.
- **Anchored adaptive banner** (`EconByte/Views/AdBannerSlot.swift`) at the
  bottom of Home and under the card in a card session. Reserves no space until
  an ad has loaded. Production unit `ca-app-pub-9950526548980224/4084037009`
  (AdMob console, 2026-09-14); Debug can only select Google's public test banner
  unit. Measured as `banner_impression_v1` with a `placement` of `home`/`card`.

Both surfaces are gated identically before any request: no Remove Ads
entitlement, region not in the EEA/UK (DUD-224, fail-closed on unknown), and the
1.1.2 build 13 ATT ordering gate (`adRequestsPermitted`) — nothing, not even an
SDK start, precedes the tracking decision. Every request is non-personalized
(`npa=1`, `rdp=1`) whatever the reader answered.

## Rating requests (review-rules-v2, 1.1.3)

`EconByte/Services/ReviewRequestPolicy.swift`. Never on the first open; from the
second launch, the first completed set of 5+ cards is the moment; once per app
version, attempts at least 120 days apart, at most two a year. Deferred — never
spent — by an ad, a purchase or restore, the consent card or primer, a system
prompt (notifications or ATT), a paywall, an error alert, or a crash recovery in
the same session. No sentiment pre-prompt; Settings' "Rate EconByte" opens the
public write-review URL. Test and automation processes never show the sheet.
