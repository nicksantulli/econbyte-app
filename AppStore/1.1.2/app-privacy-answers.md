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

**Three additions. Nothing else is touched** — in particular **do not touch**
Device ID or Advertising Data, and do not change any "Used to Track You" answer.

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

### 2. Diagnostics → Crash Data — NEW, declare it

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
  for App Functionality, not linked, not tracking.

### 3. Usage Data → Product Interaction — NEW, declare it

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

---

## What does NOT change

- **Ad-side declarations stay exactly as they are.** Device ID and Advertising
  Data keep their purposes and their answers.
- **The binary's tracking posture is unchanged.** `PrivacyInfo.xcprivacy` still
  carries `NSPrivacyTracking = true`, `NSPrivacyTrackingDomains =
  [googleads.g.doubleclick.net]`, and Info.plist still carries
  `NSUserTrackingUsageDescription` (the ATT prompt at first ad load). None of
  the three types added above touches any of that.
- No new permission, no new prompt, no new user-facing consent sheet.

---

## ⚠️ Pre-existing inconsistency to settle before submitting — Owner decision

This is **not** introduced by 1.1.2, but 1.1.2 is the next chance to fix it, and
it should be looked at before the build is submitted:

- The **binary** says the app tracks: `NSPrivacyTracking = true`, a tracking
  domain of `googleads.g.doubleclick.net`, and an ATT usage string.
- The **App Store label** says it does not: since the 2026-09-01 flip, every row
  reads **Used to Track You = No**.

Those two artifacts now disagree. Apple reads both. Either the label understates
what the ad SDK does post-ATT, or the manifest overstates it. **This lane has
not changed either, and is not the right place to decide.** Flag it to the Owner
with the 1.1 release record (the flip was made deliberately, on the Owner's
instruction, after ASC blocked the change while the 1.0 binary was live) and get
a ruling before submitting 1.1.2.

---

## How to verify after entering

1. The three rows above appear under App Privacy with the answers as written.
2. The public label still reads **"Data Not Linked to You"** — none of these
   additions is linked or tracking, so the label's top-level shape must not
   change to "Data Used to Track You".
3. Nothing under Device ID or Advertising Data was altered in passing.
