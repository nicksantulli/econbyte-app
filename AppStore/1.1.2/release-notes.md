# EconByte 1.1.2 — release notes

## Shipped copy (What's New, en-US)

This is the string already set on App Store Connect
(`appStoreVersionLocalization 74dcd360-68af-4d27-b225-e6fda92406f5`, en-US), and
it is still accurate for build 10:

> Adds anonymous crash reporting and usage analytics, with an opt-out in Settings.

**Not changed by this lane.** It was approved copy before build 10 existed, and
build 10 does not add or remove a feature it describes.

## Proposed addition — Owner's call, not applied

Build 10 removes the App Tracking Transparency prompt. Users on the **live
1.1.1** build do see that prompt today, so its disappearance is a real,
user-visible change for them — the only one in this release that is. If the
Owner wants it named:

> Adds anonymous crash reporting and usage analytics, with an opt-out in
> Settings. No more tracking-permission pop-up — EconByte doesn't track you.

Nothing was patched on App Store Connect. Customer-facing copy that has already
been approved is not something a lane rewrites on its own.

## Builds

| Build | State | Ships? |
|---|---|---|
| 9 (`d388298c-2a63-47b2-a1c5-4c174ccac9e2`) | VALID, uploaded 2026-09-05 14:59 PT | **No.** Declared `NSPrivacyTracking = true`, named `googleads.g.doubleclick.net` as a tracking domain, carried `NSUserTrackingUsageDescription`, and called `ATTrackingManager.requestTrackingAuthorization()` — all four contradict the App Privacy label staged for this version, on which every row reads "Used to Track You: No". |
| 10 (`ec3f55b9-1f86-4511-9ecb-08c22bbeeaca`) | VALID, uploaded 2026-09-05 21:03 PT | **Yes.** Same instrumentation work; tracking declaration, tracking domain, usage description and ATT call sites removed; non-personalized ads now explicit in code. |

Build 10 is attached to appStoreVersion `3efb2d70-c6f8-4bbc-95c4-fcbc18f75f72`
(read back at `/v1/appStoreVersions/3efb2d70-…/build` → build 10, VALID). The
version remains `PREPARE_FOR_SUBMISSION`.

## Submission is still gated, for an unchanged reason

Nothing was submitted and no `reviewSubmission` was created or altered — the
pre-existing empty container `af2657f5-300b-4b1b-b287-1ee54c53e343` is still
`READY_FOR_REVIEW`, `submittedDate: null`, 0 items.

The gate is the same one recorded before build 10: the App Privacy label edit is
web-UI only and App Store Connect is signed out in the box's browser. The seven
new rows in `app-privacy-answers.md` must be published **before** 1.1.2 is
submitted, or the submission understates collection. Build 10 does not change
that order; it only makes the label the submission will be judged against a
truthful description of the binary attached to it.
