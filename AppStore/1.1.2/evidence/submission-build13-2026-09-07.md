# EconByte 1.1.2 build 13 — App Review submission evidence (2026-09-07)

Owner authorization: "do whatever you need to do to re-submit econ"; build 13 approved
"as long as we think we'll pass review" (2026-09-07). Executed by an ops lane: no build,
no code change, nothing pushed. Raw API responses and step timestamps are retained at
`~/dudley-evidence-retention/econbyte/1.1.2-build13-submission/` with `SHA256SUMS`.

## Identifiers

| Object | Value |
|---|---|
| App | EconByte: Daily Economics, app id `6780714383`, bundle `com.nsantulli.econbyte` |
| App Store version | 1.1.2, id `3efb2d70-c6f8-4bbc-95c4-fcbc18f75f72`, platform IOS, releaseType **MANUAL** |
| Build | number **13**, id `09ac0ed6-6bea-4f6e-845c-6079ec716d80` (VALID, uploaded 2026-09-07T11:13:01-07:00, not expired) |
| Review submission | `af2657f5-300b-4b1b-b287-1ee54c53e343` — the **existing** container, resubmitted; not a new one |
| Review submission item | `YWYyNjU3ZjUtMzAwYi00YjFiLWIyODctMWVlNTRjNTNlMzQzfDZ8ODkwODg5Mjk1` (appStoreVersion 1.1.2) |
| Review details | `44fd6b81-3540-43f7-91d2-4a44ce9b030d` |
| en-US localization | `74dcd360-68af-4d27-b225-e6fda92406f5` |
| Source | `release/econbyte-1.1.2` @ `20308d5` (unpushed) |

## Timeline (UTC)

| Time | Step | Result |
|---|---|---|
| 19:34:57 | Pre-flight reads | version 1.1.2 **REJECTED**, build **12** attached; build 13 VALID; open submission `af2657f5` **UNRESOLVED_ISSUES**, 1 item (state REJECTED); appInfo `1534e181` REJECTED |
| 19:36:50 | Resolution Center follow-up reply posted (web UI) | thread went Messages (2) → (3); ASC header "Nick Santulli Today 1:36 PM" |
| 19:38:52 | App Privacy: Advertising Data → Used for tracking purposes **No → Yes**, Published (web UI) | header "Published a few seconds ago"; tracking rows now exactly Device ID + Advertising Data |
| 19:39 | PATCH `/v1/appStoreReviewDetails/44fd6b81-…` `notes` | set; read back **byte-identical** to `AppStore/1.1.2/review-notes.md` (2,194 chars) |
| 19:40 | PATCH `/v1/appStoreVersionLocalizations/74dcd360-…` `whatsNew` | set; read back identical (518 chars) |
| 19:41 | PATCH `/v1/appStoreVersions/3efb2d70-…/relationships/build` → build 13 | attached; read back **13, VALID**; version state moved REJECTED → PREPARE_FOR_SUBMISSION |
| 19:41 | POST `/v1/reviewSubmissions` (new container) | created `acfaeb58-…`, READY_FOR_REVIEW, 0 items |
| 19:42 | POST `/v1/reviewSubmissionItems` (version → new container) | **409 ITEM_PART_OF_ANOTHER_SUBMISSION** — the version still belongs to `af2657f5` |
| 19:42 | PATCH `af2657f5` `submitted:true` | **409 STATE_ERROR** "Version is not ready to be submitted yet, please try again later" (retried 19:45, same) |
| 19:43 | PATCH `acfaeb58` `canceled:true` | 409 "Resource is not in cancellable state" (an unsubmitted, empty container cannot be cancelled by API) |
| 19:44 | POST `/v1/reviewSubmissionItems` (appInfo → `af2657f5`) | **409 RELATIONSHIP.UNKNOWN** — `appInfo` is not a relationship on `reviewSubmissionItems` in the public API |
| 19:44 | Web UI: Draft Submissions → **Delete Submission** | the empty `acfaeb58` removed (later reads 404) |
| 19:45 | Web UI: version page → **Update Review** → **Continue** | item on `af2657f5` moved to **Ready for Review**; "Resubmit to App Review" became enabled |
| **19:46:02.489** | Web UI: **Resubmit to App Review** | submission `af2657f5` → **WAITING_FOR_REVIEW** |
| 19:46 | Read-backs | version **WAITING_FOR_REVIEW**, build **13 VALID**, 1 item, MANUAL release |

## 1. Resolution Center — the standing reply was retracted before submitting

Review finding I-1: the reply of 2026-09-07T17:11Z told App Review the app does not
track, promised to mark Device ID not-tracking, and asked for **build 12** to be approved
as a bug-fix — three claims build 13 contradicts, plus an open request that could have
shipped build 12. A follow-up was posted on the same thread, verbatim as briefed:

> Update and correction: our previous reply was inaccurate about tracking, and we withdraw
> the request to approve build 12 as a bug-fix. The currently live version 1.1.1 does
> request tracking permission through App Tracking Transparency, and the Google Mobile Ads
> SDK declares the device identifier as used for tracking. Build 12 had removed that
> prompt, which made the binary inconsistent with our App Privacy answers. We have uploaded
> build 13 of version 1.1.2, which restores the App Tracking Transparency request (shown
> once, after the user's first completed session and before any ad request) and declares
> tracking in its privacy manifest. Our App Privacy answers now mark Device ID and
> Advertising Data as used to track; no other data type is used for tracking, and ads
> remain non-personalized regardless of the user's choice. Please review build 13; the
> review notes describe exactly where the prompt appears. Thank you.

925 of 4,000 characters, no attachment, posted 2026-09-07T19:36:50Z as Nick Santulli.
The submission was then **resubmitted on this same thread**, so the reviewer opening the
case reads the rejection, the superseded reply, and the retraction in order — I-1 closed.

## 2. App Privacy label — one row, published

Exactly one field changed: `Usage Data > Advertising Data` → *Used for tracking purposes:*
**No → Yes**. Purposes (Third-Party Advertising) and linkage (No) untouched; `Identifiers
> Device ID` was never opened (it already read Yes); the seven 1.1.2 rows untouched.

Read back from the live page after Publish:

```
Data Used to Track You:  Usage Data, Identifiers
Data Not Linked to You:  Identifiers, Diagnostics, Usage Data, Location

Device ID          Used for Third-Party Advertising / Used for tracking purposes
Advertising Data   Used for Third-Party Advertising / Used for tracking purposes
User ID            Used for Analytics
Product Interaction / Other Usage Data     Used for Analytics
Crash Data         Used for Analytics, and App Functionality
Performance Data / Other Diagnostic Data   Used for App Functionality
Coarse Location    Used for App Functionality
```

Exactly two rows carry "Used for tracking purposes", matching build 13's
`PrivacyInfo.xcprivacy` (tracking rows = Device ID + Advertising Data) row for row.

## 3. Review notes and What's New

* **Review notes** were replaced with the verbatim block from
  `AppStore/1.1.2/review-notes.md` and read back byte-identical. Worth recording: the
  previous notes (written for 1.1) contained the sentence *"The app does not request App
  Tracking Transparency authorization and does not use the advertising identifier"*, which
  is false of build 13 — leaving it would have reproduced the contradiction that caused
  the rejection. The replacement is shorter and covers only what App Review asked for
  (where the prompt is, the regional difference) plus the two IAPs and the no-account fact;
  the older free-reviewer-path walkthrough is not carried over.
* **What's New** (en-US): only the third bullet changed, exactly as
  `AppStore/1.1.2/release-notes.md` specifies —
  *"• No tracking-permission pop-up: EconByte doesn't track you."* →
  *"• After your first finished set, EconByte asks once whether ads may be measured.
  Either answer is fine — ads are never personalized."* Every other line is unchanged.

## 4. What Apple's UI demanded beyond the plan

The API could not complete the submission. `PATCH submitted:true` on the rejected
version's container returned only *"Version is not ready to be submitted yet"*; the reason
turned out to be a **pending change to the shared app information** — the app **Name**
(en-US) is pending as *"EconByte: Daily Economics"* while the live name is *"EconByte"*.
App Store Connect will not review the version without that change included, and
`reviewSubmissionItems` has **no `appInfo` relationship** in the public API, so the item
cannot be added programmatically. The submission therefore had to go through the version
page's **Update Review** flow, whose confirmation dialog states plainly:

> The submission includes the following changes to the shared app information:
> • Name (English (U.S.))

**Consequence, recorded deliberately:** `appInfo 1534e181-59d1-43d6-bd8e-68b32a67f5f7`
moved **REJECTED → WAITING_FOR_REVIEW**. The brief expected it to stay REJECTED; that was
not achievable. The rename is pre-existing pending state (it rode along with the build-12
submission that was rejected), was not created or edited by this lane, and the only way to
exclude it would have been to revert the pending name — out of scope. The live 1.1.1 app
name is unaffected until 1.1.2 is approved and released.

One further artefact: a review submission container `acfaeb58-9b82-4843-bb49-6ad4a12f0d5e`
was created by the API attempt, could not be cancelled by the API while empty, and was
deleted through the web UI's Draft Submission panel. It now 404s; the app has exactly one
open submission.

## 5. Final state (read back 2026-09-07T19:46Z)

| Object | State |
|---|---|
| reviewSubmission `af2657f5-…` | **WAITING_FOR_REVIEW**, submittedDate `2026-09-07T19:46:02.489Z`, 1 item |
| appStoreVersion 1.1.2 | **WAITING_FOR_REVIEW** (appStoreState and appVersionState), releaseType **MANUAL** |
| Attached build | **13**, VALID, not expired |
| appInfo `1534e181-…` (pending Name) | **WAITING_FOR_REVIEW** (see §4) |
| appInfo `aa64e644-…` (live) | READY_FOR_DISTRIBUTION / READY_FOR_SALE — untouched |
| Other review submissions | 5, all COMPLETE — untouched |

## Not done, by design

No push, no build, no xcodebuild, no code change. No pricing, availability, screenshots,
description, keywords, in-app purchase or other-app change. Live 1.1.1 untouched. Release
is **MANUAL**: after approval the Owner (or a gated lane) must release 1.1.2 explicitly.
