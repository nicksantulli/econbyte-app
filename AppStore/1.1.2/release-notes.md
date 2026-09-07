# EconByte 1.1.2 — release notes

## Shipped copy (What's New, en-US) — REWRITTEN for build 11, unchanged for build 12

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
| 11 (`12c220ef-f9b5-4577-a000-830e130bda68`) | VALID, uploaded 2026-09-06 | **No** — superseded. Build 10's instrumentation and tracking posture on top of the real 1.1 product (15 topics / 120 cards, growth stack, VoiceOver, Reduce Motion), consent restored to opt-in — but the reconciliation merge dropped the Settings "Analytics ID" row that `app-privacy-answers.md` §1 tells App Review is there. Failed review on that one Important. |

| **12** (`ae5bb802-5e8f-4076-9f20-0c706bb80645`) | VALID, uploaded 2026-09-06 | **Yes.** Build 11 plus the Settings "Analytics ID" row the App Privacy answers promise (dropped in the reconciliation merge), a decimal-safe first-sentence slice for the Home highlight, and a two-line cap on its source label. |

Build 12 is attached to appStoreVersion `3efb2d70-c6f8-4bbc-95c4-fcbc18f75f72`
(read back at `/v1/appStoreVersions/3efb2d70-…/build` → build 12, VALID). The
version remains `PREPARE_FOR_SUBMISSION`.

### Does the What's New copy still hold for build 12?

Yes, unchanged, and it was re-read rather than assumed. Build 12 changes nothing
the notes describe: the catalog is the same 15 topics / 120 cards, both consent
switches are still separate and still off by default, there is still no
tracking-permission prompt, and VoiceOver and Reduce Motion behave as before. The
restored Analytics ID row is *inside* the consent posture the notes already
describe, not a new user-facing feature, so no line was added for it.

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

---

# Build 13 (2026-09-07) — the shipped What's New is now FALSE and must change

Build 13 restores the App Tracking Transparency prompt (App Review rejected
build 12 under Guideline 5.1.2(i); see `AppStore/1.1.2/review-notes.md` and the
supersession box at the top of `app-privacy-answers.md`). The What's New text
currently set on the version says the opposite:

> • No tracking-permission pop-up: EconByte doesn't track you.

That line was true of builds 10-12 and is **false of build 13**. Shipping it
would tell every updating reader there is no permission pop-up, immediately
before showing them one — the same class of defect (an artefact contradicting
the binary) that caused the rejection. It must be replaced before submission.

## Replacement copy (en-US) — to set on `appStoreVersionLocalization 74dcd360-68af-4d27-b225-e6fda92406f5`

Only the third bullet changes; every other line is unchanged and still true.

```
All 15 topics and 120 cards are back, including the five topics the previous
update left out.

• Usage analytics and crash diagnostics are separate, optional choices in
Settings — both off unless you turn them on.
• After your first finished set, EconByte asks once whether ads may be
measured. Either answer is fine — ads are never personalized.
• VoiceOver announces each card's topic, position and face, and card flips
respect Reduce Motion.
• The highlight on the home screen now matches its refreshed source data.
```

Why this wording:

* **"asks once"** and **"after your first finished set"** are literally what the
  binary does, and are the same two facts the review notes give App Review.
* **"whether ads may be measured"** matches the tracking-permission string in
  `Info.plist` ("Allows the ads that keep EconByte free to be measured. EconByte
  does not personalize ads."). A reader who taps through should recognise the
  sentence.
* **"Either answer is fine"** is true and is worth saying: declining costs the
  reader nothing in this app, because the ads were never personalized either way.
* It does not say "we don't track". The published label says the app does, and
  build 13 agrees with the label.

## What is unchanged in build 13

Content, consent posture, VoiceOver, Reduce Motion, the analytics identity row,
pricing, the two in-app purchases, and every ad eligibility rule. The diff from
build 12 is the ATT prompt, the ordering gate in front of the ad request, the
privacy manifest, the usage-description string, and the build number.

## Not applied by this lane

Neither this copy nor the review notes has been written to App Store Connect.
Build 13 is uploaded but **not attached to the version and not submitted** — an
independent review comes first.
