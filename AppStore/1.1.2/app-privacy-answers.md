# EconByte 1.1.2 — App Privacy answers to set in App Store Connect

**Status: NOT ENTERED.** This file is the instruction set for whoever opens the
App Store Connect web UI. Nothing here has been submitted. The App Privacy
section **cannot be edited through the ASC API** — it is web-UI only, so no lane
can do this for you.

- App: `com.nsantulli.econbyte` (ASC app id `6780714383`)
- Version: **1.1.2** (build **9** — ASC's highest existing build is 8, read back
  from `/v1/apps/6780714383/builds` on 2026-09-05)
- Prepared: 2026-09-05, from the `feat/econbyte-instrumentation` source tree
- Prepared by reading: the app's own `EconByte/Resources/PrivacyInfo.xcprivacy`,
  the pinned SDK versions (posthog-ios 3.71.4, sentry-cocoa 8.58.4), the typed
  event schema in `EconByte/Services/EconTelemetry.swift`, and the live-label
  state recorded for the 1.1 release (2026-09-01).

---

## Why the label changes at all

1.1 and 1.1.1 shipped with **no analytics and no crash reporting** — the only
thing collecting anything was the ad SDK. 1.1.2 turns on the app's own
instrumentation: a typed, allowlisted, bucketed PostHog event set (project
`econbyte`) and crash-only Sentry (project `econbyte`).

Everything below is the difference between "an ad SDK collects things" and "the
app itself now also measures itself". **It is purely additive** — no existing
row is edited, removed, or re-scoped.

---

## The starting point (what is live today)

Per the 1.1 release record: on **2026-09-01** the Advertising Data tracking
answer was flipped to **No** and published, leaving the public label reading
**"Data Not Linked to You" only** — i.e. **Used to Track You = No on every row**.

| Data type | Purposes | Linked | Tracking |
|---|---|---|---|
| Identifiers → Device ID | Third-Party Advertising | No | No |
| Usage Data → Advertising Data | Third-Party Advertising | No | No |

> **Read the live label before you edit anything.** The table above is a record,
> not an observation — this lane cannot read App Privacy through the API. Open
> App Store Connect → EconByte → App Privacy and confirm what is actually there.
> If a row below already exists with different purposes, **add** the purpose;
> do not replace what is there.

---

## The 1.1.2 delta — the only edits to make

**Seven additions. Nothing else is touched** — in particular **do not touch**
Device ID or Advertising Data, and do not change any "Used to Track You" answer.

Every one of the seven is **Collected: Yes · Linked to the user: No · Used for
tracking: No**. Two existing rows + seven new rows = the **nine-type portfolio
union** that Table Talk's live label already carries for the same SDK set
(posthog-ios + sentry-cocoa + Google Mobile Ads). EconByte was the outlier; after
this edit the instrumented apps in the portfolio declare the same shape.

| # | Data type | Purposes | Linked | Tracking |
|---|---|---|---|---|
| 1 | Identifiers → User ID | Analytics | No | No |
| 2 | Usage Data → Product Interaction | Analytics | No | No |
| 3 | Usage Data → Other Usage Data | Analytics | No | No |
| 4 | Diagnostics → Crash Data | App Functionality, Analytics | No | No |
| 5 | Diagnostics → Performance Data | App Functionality | No | No |
| 6 | Diagnostics → Other Diagnostic Data | App Functionality | No | No |
| 7 | Location → Coarse Location | App Functionality | No | No |

> **Correction — an earlier revision of this file said "Three additions."**
> That was wrong, and it was the single gate failure recorded against 1.1.2. It
> counted only the rows the app's own client code sets *deliberately*, and
> ignored two whole categories: (a) the envelope and context fields every
> PostHog/Sentry event carries whether or not the app asks for them, and (b) the
> geo Sentry's ingest derives server-side, which a real ingested crash
> (**ECONBYTE-1**, evidenced below) proved is actually stored. The correct delta
> is **seven**.

### 1. Identifiers → User ID — NEW, declare it

- Collected: **Yes** · Purposes: **Analytics**
- Linked to the user: **No** · Used for tracking: **No**
- What it is: PostHog's own anonymous per-install id (a random UUID the SDK
  mints and stores under the app's Application Support container). It is the
  `distinct_id` on every analytics event, and it is shown to the user in
  Settings so they can quote it in a deletion request.
- **Corrected 2026-09-05:** this used to be described as an app-minted UUID in
  `UserDefaults` (`ebAnalyticsIdentity`). The app no longer mints one — under
  `personProfiles = .never` posthog-ios ignores `identify`, so that UUID was
  never on the wire and Settings was showing an id no deletion request could
  match. Nothing about the *category* of the answer changes: it is still one
  random, app-scoped, per-install identifier and nothing else.
- Why **User ID** and not Device ID: it is assigned by the app's analytics SDK
  and stored in the app's own container, is per-install (a reinstall produces a
  new one), and is regenerated whenever the user switches analytics off and back
  on — the opt-out deletes the SDK's storage directory. It is not the device ID,
  not the advertising ID, and not any other device-level identifier.
- Why not linked: there is no account, no server of ours, and no user record of
  any kind to link it to.
- Why not tracking: it never leaves the `econbyte` PostHog project, is never
  joined with third-party data, and is never combined with the advertising
  identifier. `personProfiles` is set to `.never`, so PostHog builds no person
  profile from it.

### 2. Usage Data → Product Interaction — NEW, declare it

- Collected: **Yes** · Purposes: **Analytics**
- Linked to the user: **No** · Used for tracking: **No**
- What it is: 19 allowlisted, bucketed events — which mode was entered, a card
  advanced or flipped, a session ended, a bookmark added or removed, a paywall
  viewed, a purchase outcome, an ad outcome, a streak day credited. Counts and
  durations are **bucketed** (`5_9`, `30s_2m`), never exact.
- What it can never be: the schema in `EconByte/Services/EconTelemetry.swift`
  has no free-form value type. Card text, definitions, topic names, bookmark
  contents, prices, transaction ids, exact timestamps, IP, location and the
  advertising identifier are all on a named prohibited list, and the validator
  drops anything undeclared **before** it is queued.
- Matches posthog-ios 3.71.4's own privacy manifest, which declares Product
  Interaction for Analytics, not linked, not tracking.

> If the live label already carries **Product Interaction** for Third-Party
> Advertising (from the ad SDK), do **not** create a second row — add
> **Analytics** to the existing row's purposes and leave Third-Party Advertising
> in place.

### 3. Usage Data → Other Usage Data — NEW, declare it

- Collected: **Yes** · Purposes: **Analytics**
- Linked to the user: **No** · Used for tracking: **No**
- What it is: the **envelope** PostHog attaches to every event before the app's
  own allowlist ever sees it — SDK name and version (`$lib`, `$lib_version`),
  app version and build, OS name and version, device model class, locale,
  timezone offset, screen dimensions, and the SDK's own lifecycle events
  (application opened / backgrounded / installed / updated).
- Why it needs its own row: none of that is a *product interaction* — it is not
  the user doing something in the app — but it is still usage-shaped data leaving
  the device, and Apple has no narrower bucket for it. Declaring it under
  **Other Usage Data** is the honest placement.
- Why it is not covered by row 2: the client-side allowlist in
  `EconTelemetry.swift` governs the **properties the app sets**. It cannot and
  does not strip the SDK's own envelope. Row 2 describes what we choose to send;
  this row describes what the SDK sends regardless.
- Nothing here is free-form, personal, or user-authored.

### 4. Diagnostics → Crash Data — NEW, declare it

- Collected: **Yes** · Purposes: **App Functionality, Analytics**
- Linked to the user: **No** · Used for tracking: **No**
- What it is: Sentry, crash-only. A stack trace plus at most six coarse tags
  (release, build, environment, OS major version, device-class bucket, lifecycle
  state). **No sessions**, no app-hang or watchdog reports, no user object, no
  screenshots, no view hierarchy, no session replay, no traces, no profiles, no
  network breadcrumbs, no free-form extras, and no app breadcrumb describing
  which card was on screen — all off in
  `EconByte/Services/SentryDiagnosticsTransport.swift`, and asserted by
  `InstrumentationPrivacyTests` against the live `beforeSend` rather than a copy
  of it.
- The SDK stamps its own installation id onto every event before `beforeSend`
  runs; the live filter removes it, so no identifier of any kind rides on a
  crash report.
- Matches sentry-cocoa 8.58.4's own privacy manifest, which declares Crash Data
  for App Functionality, not linked, not tracking. **Analytics** is added because
  crash volume is read as a release-health rate (crash-free %), not only to fix
  individual crashes.

### 5. Diagnostics → Performance Data — NEW, declare it

- Collected: **Yes** · Purposes: **App Functionality**
- Linked to the user: **No** · Used for tracking: **No**
- What it is: the device and app **context blocks** sentry-cocoa attaches to
  every event it sends — free/used memory, free/total storage, device boot time,
  app start time, battery and orientation state, and the runtime's own launch
  measurements. These ride along on a crash event; they are performance
  measurements, not the crash trace itself.
- Note what is **off**: performance monitoring proper is disabled — no
  transactions, no traces (`tracesSampleRate` unset), no profiling, no app-hang
  or watchdog reporting, no session tracking. This row is about the context of a
  crash, not about a performance product.
- Why declare it anyway: Apple's category is defined by *what leaves the device*,
  not by which SDK feature flag produced it. The context blocks leave the device
  on every crash; a label silent on them would be inaccurate.

### 6. Diagnostics → Other Diagnostic Data — NEW, declare it

- Collected: **Yes** · Purposes: **App Functionality**
- Linked to the user: **No** · Used for tracking: **No**
- What it is: the tags Sentry's **ingest** derives server-side from the event's
  device and app contexts — proven present on the real ingested crash
  ECONBYTE-1: `app.device` (`device_app_hash`, an install-scoped hash),
  `device` (`iPhone18,1`), `device.class`, `device.family`, `os`, `os.build`,
  `dist`, `release`, `level`, `handled`, `mechanism`, `interface_type`,
  `environment`.
- Why it is a separate row from Crash Data: these are neither the stack trace nor
  performance measurements. They are diagnostic metadata, and several of them
  (`app.device` in particular) are added *after* the client's `beforeSend` has
  already run.
- Why the client allowlist does not cover it: `DiagnosticsTag` +
  `DiagnosticsFilter` govern tags **we** set. They cannot remove tags Sentry
  derives during ingest. This was the second finding from the ECONBYTE-1 payload
  inspection.
- `app.device` is scoped to this app's install, not to the device, and is not the
  IDFV or the IDFA — it does not belong on, and is not being added to, the
  existing **Device ID** row, which stays exactly as it is (Third-Party
  Advertising only).

### 7. Location → Coarse Location — NEW, declare it

- Collected: **Yes** · Purposes: **App Functionality**
- Linked to the user: **No** · Used for tracking: **No**
- What it is: a city-level geo Sentry's ingest derives from the request IP and
  stores on the event. Evidenced on ECONBYTE-1: `user.geo` = **US, Colorado
  Springs, United States**.
- **The app never asks for location.** There is no `CoreLocation` import, no
  location permission, no location usage string, and no location property in the
  telemetry schema — location is on the schema's named prohibited list. This is
  entirely server-side derivation from the connection, at coarse city
  granularity, on crash events only.
- The client already does everything available to it: `sendDefaultPii = false`
  (serialised by sentry-cocoa 8.58.4 as `sdk.settings.infer_ip = "never"` in
  `SentrySDKSettings.swift`), and the live `beforeSend` removes the user object
  outright. Users Impacted on ECONBYTE-1 came back **0**, and neither `user.id`
  nor `user.ip` was stored — but the derived `user.geo` was.

#### Why declare the geo instead of relying on the Sentry console switch

Sentry offers an org/project setting (*Security & Privacy → Prevent Storing of IP
Addresses*) that might suppress this. **We are declaring the row rather than
flipping that switch and staying silent**, deliberately:

1. **A console setting is not a release artifact.** It lives in a third-party
   web console, outside the repo. No build, no test, and no sealed evidence
   bundle can assert its state, and any org admin can change it later without a
   code change, a new build, or a new submission. The label would silently become
   wrong with nothing in our process able to notice.
2. **The label must hold for the life of the version, not for the moment it was
   entered.** Apple's declaration is about what the app collects while it is on
   the store — a claim that is only true while a remote toggle happens to be set
   correctly is not a claim we can stand behind for months.
3. **The switch is documented for IP *storage*, not for derived geo.** Whether it
   also suppresses `user.geo` has never been re-tested here with a fresh ingested
   crash. Declaring is correct under either outcome; not declaring is correct
   under only one of them, and we have not proven which.
4. **Declaring costs nothing.** Coarse Location, App Functionality, not linked,
   not tracking. It does not change the public summary (see verification below),
   it adds no prompt, and it triggers no ATT requirement.
5. **The asymmetry favours declaring.** An over-declaration can be removed on a
   later version once a fresh ingested event proves the geo is gone. An
   under-declaration discovered in review is a rejection, and discovered after
   release is a misstatement to users.

The Sentry-side switch is still worth turning on as defence in depth — but as a
data-minimisation step, **not** as a substitute for this row, and not before
1.1.2 ships.

---

## Evidence: what a REAL ingested crash actually carried

Rows 5, 6 and 7 exist because of this, not because of a reading of the SDK docs.

On 2026-09-05 a deliberate DEBUG-only crash was sent from a Simulator build of
1.1.2 (build 9) to the live `econbyte` Sentry project and then read back **from
Sentry as stored**. That is the first time this app's crash payload has been
inspected as the server keeps it rather than as the client intends it.

- Issue **ECONBYTE-1**, event id `d0384c04e4f8450686e5bfb035aed840`
- Release `com.nsantulli.econbyte@1.1.2+9`, 2026-09-05T21:28:21Z
- Users Impacted: **0** — the user object `beforeSend` strips is genuinely
  absent; neither `user.id` nor `user.ip` came back
- `user.geo` **present**: US, Colorado Springs, United States → row 7
- Server-derived tags present (`app.device`, `device`, `device.class`,
  `device.family`, `os`, `os.build`, `dist`, `handled`, `mechanism`,
  `interface_type`, `environment`) → row 6
- Device/app context blocks present (memory, storage, boot time, app start) →
  row 5

**Neither finding is caused by 1.1.2's code; both are how Sentry's server treats
any event.** Both are now declared rather than argued about.

---

## What does NOT change

- **Ad-side declarations stay exactly as they are.** Device ID and Advertising
  Data keep their purposes (Third-Party Advertising) and their answers. Nine
  types total = these two, untouched, plus the seven above.
- **The binary's tracking posture is unchanged.** `PrivacyInfo.xcprivacy` still
  carries `NSPrivacyTracking = true`, `NSPrivacyTrackingDomains =
  [googleads.g.doubleclick.net]`, and Info.plist still carries
  `NSUserTrackingUsageDescription` (the ATT prompt at first ad load). None of
  the seven types added above touches any of that.
- No new permission, no new prompt, no new user-facing consent sheet. In
  particular **row 7 adds no location permission** — nothing about the app's
  runtime behaviour changes.

---

## Owner follow-up, carried to 1.1.3 — the tracking-manifest vs label mismatch

**This does not block 1.1.2** and no lane should treat it as a blocker for this
submission. It is pre-existing, it predates the instrumentation work, and 1.1.2
neither creates nor worsens it. It is recorded here so it is not lost.

- The **binary** says the app tracks: `NSPrivacyTracking = true`, a tracking
  domain of `googleads.g.doubleclick.net`, and an ATT usage string.
- The **App Store label** says it does not: since the 2026-09-01 flip, every row
  reads **Used to Track You = No** — and the seven additions above keep it that
  way.

Those two artifacts disagree, and Apple reads both. Either the label understates
what the ad SDK does post-ATT consent, or the manifest overstates it while the
app is geo-restricted away from consent-gated regions.

**Owner decision required, targeted at 1.1.3:**

- **Option A — align the manifest to the label.** If the ad configuration
  genuinely does not track (non-personalised ads, geo-restricted, no ATT-gated
  data flow in practice), set `NSPrivacyTracking = false`, drop
  `NSPrivacyTrackingDomains`, and remove `NSUserTrackingUsageDescription` so the
  ATT prompt stops appearing. Requires a code change and a build.
- **Option B — align the label to the manifest.** Flip the Advertising Data /
  Device ID rows back to **Used to Track You = Yes**. Costs the "Data Not Linked
  to You"-only public summary and re-introduces the tracking disclosure.

Bring the 1.1 release record with it: the 2026-09-01 flip to No was made
deliberately, on the Owner's instruction, after ASC blocked the change while the
1.0 binary was live. **This lane has not changed either artifact and is not the
right place to decide.**

---

## How to verify after entering

1. **Nine data types** appear under App Privacy: the two pre-existing ad rows
   (Device ID, Advertising Data) plus the seven above, each with the purposes as
   written.
2. Every row reads **Linked to You: No** and **Used to Track You: No**.
3. The public label still reads **"Data Not Linked to You"** — none of these
   additions is linked or tracking, so the summary must **not** gain a "Data Used
   to Track You" section. If it does, one of the seven was answered wrong.
4. Nothing under Device ID or Advertising Data was altered in passing — purposes
   still read Third-Party Advertising, answers still read No / No.
5. The changes are **Published**, not left in a draft state. Screenshot the
   published label into the evidence bundle.
