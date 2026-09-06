# EconByte 1.1.2 — App Review submission evidence (2026-09-06)

Owner authorization: Owner explicitly authorized this submission (relayed via the S3 store-submission
track, MANAGER-LOOP-2026-09-06.md, decision #15b). GitHub pushes for this release were completed and
verified by a prior lane earlier the same day (remote main = `5670310` = `release/econbyte-1.1.2`;
`codex/econbyte-1.1` @ `3ff4f83`; lineage-B main also `5670310`) — this lane did not push anything.
App Privacy label rows entered in the ASC web UI (Chrome, browser "Mac Mini", Owner signed into App
Store Connect there) per `chrome-queue-2026-09-05.md`; the review submission itself was completed via
the App Store Connect API using `scripts/asc_api.mjs` from the Dudley-Development monorepo (the script
handles auth itself; no key, token, or key path appears here).

## Identifiers

| Object | Value |
|---|---|
| App | EconByte: Daily Economics, app id `6780714383` |
| App Store version | 1.1.2, id `3efb2d70-c6f8-4bbc-95c4-fcbc18f75f72`, releaseType MANUAL, platform IOS |
| Build | number **12**, id `ae5bb802-5e8f-4076-9f20-0c706bb80645` (processingState VALID, uploaded 2026-09-06T01:30:16-07:00, not expired) |
| Review submission (container) | id `af2657f5-300b-4b1b-b287-1ee54c53e343` — pre-existing, found open (READY_FOR_REVIEW, 0 items) and reused per the brief |
| Review submission item | id `YWYyNjU3ZjUtMzAwYi00YjFiLWIyODctMWVlNTRjNTNlMzQzfDZ8ODkwODg5Mjk1` (appStoreVersion → `3efb2d70-...`) |
| appInfo | id `1534e181-59d1-43d6-bd8e-68b32a67f5f7` — left `PREPARE_FOR_SUBMISSION`, now `WAITING_FOR_REVIEW` (the rename on appInfoLocalization `e86da0a4-...` travels with the version, confirmed by the state transition) |
| Worktree | `~/dudley-worktrees/econbyte-reconcile` on `release/econbyte-1.1.2` @ `5670310` (before this evidence commit) |

## App Privacy label (web UI)

Entered the 7 new rows from `chrome-queue-2026-09-05.md` in ASC → App Privacy (app 6780714383), using
the Chrome extension attached to the "Mac Mini" browser (deviceId `0565e901-f450-464a-a2ad-
f96abbd6208b`), already signed into App Store Connect as Nick Santulli. Privacy Policy URL was already
`https://dudleyapps.com/privacy` (unchanged). This app's App Privacy page was already published (build
build 9/earlier release), so each new data type's setup wizard ended in its own "Publish" click that
committed just that one row immediately — there was no single final page-level Publish gating all 9
rows together (unlike a brand-new, never-published version). Read the page back with `get_page_text`
after finishing all 7 new rows and compared it line by line to the brief — exact match, no corrections
needed. Existing Device ID and Advertising Data rows were left untouched (confirmed unchanged in the
read-back) and no duplicate Advertising Data row was created.

| Data type | Purposes entered | Linked | Tracking | Status |
|---|---|---|---|---|
| User ID | Analytics | Not Linked | No | NEW |
| Product Interaction | Analytics | Not Linked | No | NEW |
| Other Usage Data | Analytics | Not Linked | No | NEW |
| Crash Data | App Functionality, Analytics | Not Linked | No | NEW |
| Performance Data | App Functionality | Not Linked | No | NEW |
| Other Diagnostic Data | App Functionality | Not Linked | No | NEW |
| Coarse Location | App Functionality | Not Linked | No | NEW |
| Device ID | Third-Party Advertising | Not Linked | **Yes** | EXISTING, untouched |
| Advertising Data | Third-Party Advertising | Not Linked | No | EXISTING, untouched |

Post-publish banner read "Published a few seconds ago by Nick Santulli" throughout. Screenshot
evidence captured via the Chrome automation tool's screenshot action (id `ss_72322lfbm`); the binary
image was not retrievable through this run's file-system sandbox, so the full on-screen text was
captured verbatim instead (see `20-privacy-readback.txt` in the retention directory) and matches the
table above exactly.

## Timeline (UTC)

| Time | Step | Result |
|---|---|---|
| 2026-09-06T22:56Z (prior lane) | GitHub pushes + pre-flight reads | pushes verified; version PREPARE_FOR_SUBMISSION/MANUAL; build 12 VALID; container `af2657f5-...` open (READY_FOR_REVIEW, 0 items) |
| 2026-09-06T~23:12Z | App Privacy: entered 7 new rows in ASC web UI, each Published individually, read back | all 9 rows match brief exactly; existing 2 rows untouched |
| 2026-09-06T23:18Z | Pre-flight re-check (this lane) | version still PREPARE_FOR_SUBMISSION; build 12 still VALID; container still open (READY_FOR_REVIEW, 0 items) |
| 2026-09-06T23:19:0xZ | POST /v1/reviewSubmissionItems (appStoreVersion) into existing container | item created, state READY_FOR_REVIEW |
| 2026-09-06T23:19:0xZ | GET items | exactly 1 item, appStoreVersion 1.1.2 |
| 2026-09-06T23:19:11Z | PATCH submitted:true | HTTP OK; state WAITING_FOR_REVIEW |
| 2026-09-06T23:19:1xZ | Read-back | submission **WAITING_FOR_REVIEW**; version appVersionState/appStoreState **WAITING_FOR_REVIEW**; appInfo `1534e181-...` **WAITING_FOR_REVIEW** (left PREPARE_FOR_SUBMISSION) |

Retries: none. Errors: none.

## Exact commands run

All from `/Users/nicksantulli/Documents/GitHub/Dudley-Development`.

```sh
# Pre-flight re-checks
node scripts/asc_api.mjs raw "/v1/appStoreVersions/3efb2d70-c6f8-4bbc-95c4-fcbc18f75f72?fields[appStoreVersions]=versionString,appVersionState,appStoreState,releaseType,platform,createdDate"
node scripts/asc_api.mjs raw "/v1/appStoreVersions/3efb2d70-c6f8-4bbc-95c4-fcbc18f75f72/build?fields[builds]=version,processingState,uploadedDate,expired"
node scripts/asc_api.mjs raw "/v1/reviewSubmissions/af2657f5-300b-4b1b-b287-1ee54c53e343"
node scripts/asc_api.mjs raw "/v1/reviewSubmissions/af2657f5-300b-4b1b-b287-1ee54c53e343/items"

# Attach version 1.1.2 as the item in the existing container
ASC_OWNER_WRITE_APPROVED=1 node scripts/asc_api.mjs post /v1/reviewSubmissionItems \
  '{"data":{"type":"reviewSubmissionItems","relationships":{"reviewSubmission":{"data":{"type":"reviewSubmissions","id":"af2657f5-300b-4b1b-b287-1ee54c53e343"}},"appStoreVersion":{"data":{"type":"appStoreVersions","id":"3efb2d70-c6f8-4bbc-95c4-fcbc18f75f72"}}}}}' --owner-approved

# Confirm exactly one item
node scripts/asc_api.mjs raw "/v1/reviewSubmissions/af2657f5-300b-4b1b-b287-1ee54c53e343/items?include=appStoreVersion&fields[appStoreVersions]=versionString,appVersionState"

# Submit
ASC_OWNER_WRITE_APPROVED=1 node scripts/asc_api.mjs patch /v1/reviewSubmissions/af2657f5-300b-4b1b-b287-1ee54c53e343 \
  '{"data":{"type":"reviewSubmissions","id":"af2657f5-300b-4b1b-b287-1ee54c53e343","attributes":{"submitted":true}}}' --owner-approved

# Read back
node scripts/asc_api.mjs raw "/v1/reviewSubmissions/af2657f5-300b-4b1b-b287-1ee54c53e343"
node scripts/asc_api.mjs raw "/v1/appStoreVersions/3efb2d70-c6f8-4bbc-95c4-fcbc18f75f72?fields[appStoreVersions]=versionString,appVersionState,appStoreState,releaseType,platform"
node scripts/asc_api.mjs raw "/v1/apps/6780714383/appInfos?fields[appInfos]=appStoreState,appStoreAgeRating,state"
```

## Raw responses

Retained (with SHA256SUMS) at `~/dudley-evidence-retention/econbyte/1.1.2-submission-2026-09-06/`:
`00`–`07` (prior lane's push verification), `10`–`16` (prior lane's pre-flight), `20-privacy-
readback.txt`, `30`–`34` (this lane's pre-flight re-check), `40`–`47` (add-item/submit/read-back), plus
`*.utc` step timestamps and `SHA256SUMS`.

## Not done (by design)

No push (already done by the prior lane and verified only), no xcodebuild, no listing/pricing/
availability change, no territory-toggle change (that is phase S4, not S3), no other version or app
touched. Release is MANUAL: after Apple's approval the Owner (or a gated lane) must release 1.1.2
explicitly.
