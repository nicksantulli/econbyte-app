# EconByte 1.1.2 — release notes

## Shipped copy (What's New, en-US) — REWRITTEN for build 11

Set on App Store Connect (`appStoreVersionLocalization
74dcd360-68af-4d27-b225-e6fda92406f5`, en-US) and read back on 2026-09-06:

> All 15 topics and 120 cards are back, including the five topics the previous
> update left out.
>
> • Usage analytics and crash diagnostics are separate, optional choices in
> Settings — both off unless you turn them on.
> • No tracking-permission pop-up: EconByte doesn't track you.
> • VoiceOver announces each card's topic, position and face, and card flips
> respect Reduce Motion.
> • The highlight on the home screen now matches its refreshed source data.

### Why the approved copy had to change

The previous string —

> Adds anonymous crash reporting and usage analytics, with an opt-out in Settings.

— was accurate for build 10 and is **false for build 11**, in two ways:

1. **"with an opt-out" is backwards.** Build 11 restores version 1.1's posture:
   analytics and crash diagnostics are two separate switches, both **off** until
   the user turns them on. Version 1.1's published notes promise exactly that,
   and shipping an opt-out under this copy would reverse a published privacy
   promise on update.
2. **It says nothing about the content that comes back.** Live 1.1.1 (build 8)
   was cut from a lineage that never had the 1.1 curriculum: it serves **10
   topics / 80 cards**, verified in that tree's `EconByte/Content/cards.json`.
   Build 11 serves **15 topics / 120 cards** from
   `EconByte/Resources/curriculum-v1.1.json`. For every user on the live build,
   five whole topics and forty cards reappearing is the largest user-visible
   change in this release, and the notes did not mention it.

Each line above is checkable against the tree this build was archived from:
the counts against the catalog and `CurriculumCatalogTests`; the consent shape
against `SettingsView.privacySection` and `GrowthFlowTests`; the absent ATT
prompt against `InstrumentationPrivacyTests` (source scan **and** Mach-O load
command); VoiceOver and Reduce Motion against `AccessibilityTests`.

**To revert**, PATCH the same localization `whatsNew` back to the one-line
string quoted above. Nothing was submitted, so a revert costs nothing.

## Builds

| Build | State | Ships? |
|---|---|---|
| 9 (`d388298c-2a63-47b2-a1c5-4c174ccac9e2`) | VALID, uploaded 2026-09-05 14:59 PT | **No.** Declared `NSPrivacyTracking = true`, named `googleads.g.doubleclick.net` as a tracking domain, carried `NSUserTrackingUsageDescription`, and called `ATTrackingManager.requestTrackingAuthorization()` — all four contradict the App Privacy label staged for this version. |
| 10 (`ec3f55b9-1f86-4511-9ecb-08c22bbeeaca`) | VALID, uploaded 2026-09-05 21:03 PT | **No** — superseded. Tracking coherence fixed, but it still carried the stale lineage's product: 10 topics / 80 cards, no growth stack, no VoiceOver card flip. |
| **11** (`12c220ef-f9b5-4577-a000-830e130bda68`) | VALID, uploaded 2026-09-06 | **Yes.** Build 10's instrumentation and tracking posture on top of the real 1.1 product (15 topics / 120 cards, growth stack, VoiceOver, Reduce Motion), consent restored to opt-in. |

Build 11 is attached to appStoreVersion `3efb2d70-c6f8-4bbc-95c4-fcbc18f75f72`
(read back at `/v1/appStoreVersions/3efb2d70-…/build` → build 11, VALID). The
version remains `PREPARE_FOR_SUBMISSION`.

## Submission is still gated, for an unchanged reason

Nothing was submitted and no `reviewSubmission` was created or altered — the
pre-existing empty container `af2657f5-300b-4b1b-b287-1ee54c53e343` is still
`READY_FOR_REVIEW`, `submittedDate: null`, 0 items.

The gate is the same one recorded before build 10: the App Privacy label edit is
web-UI only. The seven new rows in `app-privacy-answers.md` must be published
**before** 1.1.2 is submitted, or the submission understates collection.

A second gate is new with this build: `release/econbyte-1.1.2` **has not been
pushed**. `origin/main` is still `42df3dc`, which is the mechanism that produced
the two lineages in the first place. See `RECONCILIATION-LOG.md`.
