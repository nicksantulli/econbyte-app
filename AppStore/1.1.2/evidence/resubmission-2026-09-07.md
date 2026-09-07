# 1.1.2 — App Review resubmission, 2026-09-07

Version 1.1.2 (build 12) was rejected under **Guideline 5.1.2(i)** on 2026-09-07:
the App Privacy label says Device ID is collected in order to track the user, but
the app presents no App Tracking Transparency prompt.

The rejection is correct about the mismatch, and it names the right fix. The fix
could not be applied, for a reason worth recording because it will recur.

## What was attempted, and what App Store Connect said

Editing **Identifiers > Device ID > "used for tracking purposes"** from Yes to No,
in the ASC web UI (the answer is not settable through the API). Every other row,
purpose and linkage answer was left untouched; the purposes step still reads
Third-Party Advertising only, and the linkage step still reads "not linked".

Publishing that single answer is refused:

> Your app contains NSUserTrackingUsageDescription, indicating that it may request
> permission to track users. To submit for review, update your App Privacy response
> to indicate that data collected from this app will be used for tracking purposes,
> or update your app binary and upload a new build.

The edit was **cancelled rather than falsified**, exactly as the same block was
handled for the Advertising Data row during 1.1. The published label is unchanged
and still reads "Used for tracking purposes" on Device ID.

## Why the block is right, even though build 12 does not track

The App Privacy label is **app-level**; ATT removal is **per-build**. Build 12 is
clean, and this tree proves it:

| Check | `release/econbyte-1.1.2` (build 12) | `main` — lineage B, shipped live 1.1.1 build 8 |
|---|---|---|
| `EconByte/Info.plist` → `NSUserTrackingUsageDescription` | absent | **present** |
| `AdManager.swift` → `import AppTrackingTransparency` | absent | **present** |
| `AdManager.swift` → `requestTrackingAuthorization()` | none | **2 call sites** |
| `PrivacyInfo.xcprivacy` → `NSPrivacyTracking` | `false` | **`true`** |

`RECONCILIATION-LOG.md` already described lineage B as "the stale line that shipped
live 1.1.1 build 8: v1.0 content, grocery line, **ATT back**,
`googleads.g.doubleclick.net` declared". Build 9 (`d388298c…`), still VALID and
unexpired, carries the key too.

So while 1.1.1 is the live version, "Device ID used to track = Yes" is the *accurate*
app-level answer, and ASC is right to hold it. **1.1.2 is the release that makes the
answer No.** That is the catch-22: the label cannot be corrected until the binary
that corrects it ships.

This has happened on this app once before. `AppStore/1.1/evidence/release-packet.json`
records the identical refusal on the Advertising Data row while 1.0 was live; it
cleared only once 1.1 build 6 went live, which is why Advertising Data reads
correctly today. Shipping 1.1.1 build 8 on 2026-09-04 re-armed the block before the
Device ID row was ever fixed.

## What was done instead

A reply was posted to the Resolution Center thread on submission
`af2657f5-300b-4b1b-b287-1ee54c53e343` at **2026-09-07T17:11Z**, which is the remedy
Apple's own message prescribes for this case — "If you are unable to change the
privacy label, reply to this message in App Store Connect" — and which also invokes
the Bug Fix Submission offer in the same message ("You do not need to resubmit your
app for us to proceed").

The reply states only what is verifiable: build 12 carries no ATT code, no
`NSUserTrackingUsageDescription` and `NSPrivacyTracking = false`, so no prompt is
possible and the advertising identifier is unavailable to the app or to Google Mobile
Ads; the label edit is refused, quoted verbatim; live 1.1.1 does still request
tracking permission; and the label will be corrected once 1.1.2 is live. Full text at
`~/dudley-evidence-retention/econbyte/1.1.2-resubmission-2026-09-07/25-resolution-center-reply.md`.

## No new reviewSubmission was created

State after the reply: version `3efb2d70…` **REJECTED**; container `af2657f5…`
**UNRESOLVED_ISSUES**; build **12** (`ae5bb802…`) still attached, VALID, unexpired;
in-flight appInfo `1534e181…` still REJECTED.

Resubmitting now would put the identical binary and the identical label back in front
of App Review — the exact 5.1.2(i) condition — and would risk superseding the pending
bug-fix request. The next move is Apple's. Ready-to-run resubmission commands, for
when the label conflict is actually resolved, are recorded in
`~/dudley-evidence-retention/econbyte/1.1.2-resubmission-2026-09-07/30-resubmission-DECISION.md`.

## The durable lesson

Ordering matters more than any single answer: **a not-tracking label can only be
published while no ATT-carrying binary is live.** Any future release cut from a
lineage that still calls ATT will re-arm this block and re-earn 5.1.2(i). Lineage B
must not ship again.

Nothing else on the listing, pricing, or any other app was touched. No build was
uploaded, expired, or altered.
