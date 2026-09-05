# EconByte: Daily Economics

A SwiftUI iOS card app — bite-sized economics concepts (inflation, interest
rates, GDP, trade) as swipeable daily cards. Educational only; not financial
advice.

- Bundle id: `com.nsantulli.econbyte` · ASC app id `6780714383`
- Current version in this tree: **1.1.2 (build 9)**
- Freemium: Inflation + Interest Rates free; the other 8 topics behind
  **Unlock All Topics** (`com.nsantulli.econbyte.unlockall`, $0.99). **Remove
  Ads** (`com.nsantulli.econbyte.removeads`, $0.99) is a separate purchase.
- To run it: see [RUN-ON-DEVICE.md](RUN-ON-DEVICE.md).

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
- **Crash diagnostics → Sentry**, project **`econbyte`** (crash-only; no session
  replay, no tracing, no profiling).

Never reuse another Dudley app's project. Table Talk's projects are
`table-talk` / `tabletalk` and are separate on purpose — cross-app identity
separation depends on the projects being distinct.

### Defaults (1.1.2)

| | Default | User control | Where |
|---|---|---|---|
| PostHog usage analytics | **ON** | opt-out switch | Settings → Privacy → "Share Anonymous Usage Analytics" |
| Sentry crash reports | **ON** | none | — |

Analytics ship on because what ships is small enough to defend: only a typed,
allowlisted event set can reach PostHog (see
`EconByte/Services/EconTelemetry.swift`) — bucketed, anonymous counts of which
topics and modes get used, never a card, a definition, a bookmark, a price, or
an exact timestamp. The validator drops anything undeclared *before* it is
queued, so "on" cannot come to mean more than it means today without a schema
change and a review.

Crash reports have no switch on purpose: the envelope is a stack trace with the
user object and every breadcrumb stripped, and a crash reporter most people
leave off reports nothing. Settings says out loud that they are sent.

Switching analytics off stops capture before the call returns, clears the local
queue, tears the SDK down, resets the per-install id, and persists
(`ebAnalyticsOptOut` — absent means "never answered", which is ON). Switching it
back on mints a **new** id, so the two sides of an opt-out cannot be stitched
together.

Fail-soft: **no key/DSN → the SDK is never initialised**, whatever the defaults
say. A checkout without `Config/Secrets.xcconfig` collects nothing, and Settings
then says "Off — nothing is collected" instead of offering a switch that does
nothing.

### Proving it, without shipping a switch

`-EBInstrumentationSmoke YES` forces analytics on for one run and logs the
resolved state; `-EBInstrumentationCrash YES` crashes the app on purpose three
seconds after launch so the next launch uploads a Sentry report. Both are
**DEBUG-only** and compiled out of Release.

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

### App Privacy

The three data types 1.1.2 adds (User ID, Crash Data, Product Interaction) are
all **not linked** and **not used for tracking**. The ad-side declarations
(`NSPrivacyTracking`, the googleads tracking domain, the ATT prompt) are
unchanged. The exact ASC edits are in
[`AppStore/1.1.2/app-privacy-answers.md`](AppStore/1.1.2/app-privacy-answers.md).
