# EconByte 1.1.7 (build 24) — build-ready handoff

Branch `claude/econbyte-117-ad-retune`, cut from the live 1.1.6 source
(`claude/econbyte-116-ads-reviews` @ `3a00177`, build 23, READY_FOR_SALE).
Worktree: `~/dudley-worktrees/econbyte-117`.

**What changed (Owner, 2026-09-28):** the anchored banner is gone (Home, Browse,
under a card session): view, SDK adapter, unit, requests, telemetry. Interstitial
rules, the rewarded pack trial and the region/ATT rules are unchanged. No second
rewarded surface (reason: `CONTENT-DECISIONS.md` D26). Version 1.1.7, build 24
(ASC's highest build is 23, read 2026-09-28).

**Not done in this lane:** no xcodebuild of any kind, so nothing below has run
on a simulator or been archived. What was checked: the app module and both test
targets' sources typecheck with `swiftc -typecheck` against the iOS 26.5
simulator SDK (without the vendor packages, so the `canImport(GoogleMobileAds)`
branch was not compiled; in that branch the only change is deleting
`GoogleBannerView`). DudleyCore `swift test` passed (520).

---

## 0. Pre-flight (every xcodebuild)

```sh
cd ~/dudley-worktrees/econbyte-117
git log --oneline -1                      # claude/econbyte-117-ad-retune tip
out=$(DUDLEY_IGNORE_MARKET_HOURS=1 ~/.local/bin/host-capacity-check.sh 2>&1)
echo "$out" | grep -q BLOCK && { echo "$out"; exit 1; }   # it exits 0 on BLOCK
pgrep -x xcodebuild | wc -l               # at most 1 other lane
test -f Config/Secrets.xcconfig && echo keyed   # gitignored; copied from ../econbyte-116
```

Use a dedicated DerivedData and simulator (never share across projects):

```sh
DD=~/Library/Developer/Xcode/DerivedData-econbyte-117
xcrun simctl create EB117 com.apple.CoreSimulator.SimDeviceType.iPhone-17 \
  com.apple.CoreSimulator.SimRuntime.iOS-26-5            # prints the UDID
SIM=<that UDID>
OUT=~/dudley-evidence-retention/econbyte/1.1.7 && mkdir -p "$OUT"
```

## 1. Unit tests

```sh
xcodebuild test -project EconByte.xcodeproj -scheme EconByte \
  -destination "platform=iOS Simulator,id=$SIM" \
  -derivedDataPath "$DD" -resultBundlePath "$OUT/unit.xcresult" \
  -only-testing:EconByteTests
```

**Expected: 426 run, 0 failures, 9 known StoreKit skips** (1.1.6 was 418 / 0 / 9):

| Suite | Delta | Why |
|---|---|---|
| `AdRetune117Tests` (new) | +10 | no banner file/source/unit/identifier/telemetry; `EBAdPlacement` = 3 full-screen placements; interstitial thresholds pinned to 1.1.6; first session never gets one; 10 min / 2 per session / 4 per day bind as in 1.1.6; rewarded units unchanged; rewarded 2-a-day cap survives a relaunch; unlock ends at exactly 24 h |
| `GrowthAuditTests` | −2 | removed the banner-unit test and the `banner_impression_v1` schema test; the version test is now `testProjectIsStampedOneOneSevenBuildTwentyFour`; the four gate tests are renamed from "banner" to "ad" (same bodies); the adapter test now expects 2 `makeRequest` sites (interstitial + rewarded), was 4 |
| `GrowthSystemsTests` | 0 | `testThePlacementMatrix` asserts interstitial surfaces only (no `bannerPlacement` exists) |
| `EconTelemetryTests` | 0 | still green: the banner events and the `home`/`card`/`browse` placements were removed from the schema together with their emitters |
| `AdsAndReviews116Tests` | 0 | untouched (halfway break, rewarded trial, rating ask) |

Quick targeted re-run if something fails:

```sh
xcodebuild test -project EconByte.xcodeproj -scheme EconByte \
  -destination "platform=iOS Simulator,id=$SIM" -derivedDataPath "$DD" \
  -only-testing:EconByteTests/AdRetune117Tests -only-testing:EconByteTests/GrowthAuditTests \
  -only-testing:EconByteTests/GrowthSystemsTests -only-testing:EconByteTests/EconTelemetryTests \
  -only-testing:EconByteTests/AdsAndReviews116Tests
```

## 2. UI tests (network needed for Google's test fills)

```sh
xcodebuild test -project EconByte.xcodeproj -scheme EconByte \
  -destination "platform=iOS Simulator,id=$SIM" \
  -derivedDataPath "$DD" -resultBundlePath "$OUT/ui.xcresult" \
  -only-testing:EconByteUITests/ShellRedesignTests \
  -only-testing:EconByteUITests/GrowthFlowTests
```

Expected: `ShellRedesignTests/testNoBannerOnHomeBrowseOrACardSession` (new,
replaces `testBannersSitAboveTheTabBarAndHomeIndicatorAndLeaveSearch`) passes;
the set-exit interstitial, halfway break and rewarded pack trial tests in
`GrowthFlowTests` pass as in 1.1.6 (video creatives may take the close-control
skip, as before). The 3 Settings consent tests that failed identically on the
1.1.5 tip on this simulator are pre-existing, not a regression.
`CardGraphicsEvidenceTests/testFreeReaderWithBannerSlot` is renamed
`testFreeReaderWithAdsOn` (evidence capture only).

Eyeball check on the sim (Debug): Home, Browse and a card session have **no strip
at the bottom**; Next sits above the home indicator with nothing below it.

## 3. Archive + upload (Release, keyed)

```sh
set -a; . ~/.doright/dudley-secrets.env; set +a     # ASC_KEY_PATH / ASC_KEY_ID / ASC_ISSUER_ID — never echo them
xcodebuild archive -project EconByte.xcodeproj -scheme EconByte -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath "$DD" \
  -archivePath "$OUT/EconByte-1.1.7-build24.xcarchive" \
  DEVELOPMENT_TEAM=Q2DM9FSRL4 CODE_SIGN_STYLE=Automatic -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"
# The Release key gate fails the archive if POSTHOG_API_KEY is empty: Config/Secrets.xcconfig must be present.

xcodebuild -exportArchive -archivePath "$OUT/EconByte-1.1.7-build24.xcarchive" \
  -exportOptionsPlist AppStore/1.1.7/exportOptions.plist -exportPath "$OUT/export" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"
```

Before exporting, confirm the archive's Info.plist says 1.1.7 / 24 and that
`GoogleMobileAds` is still linked (interstitial + rewarded need it):
`/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' -c 'Print CFBundleVersion' "$OUT/EconByte-1.1.7-build24.xcarchive/Products/Applications/EconByte.app/Info.plist"`.

## 4. App Store Connect (app 6780714383) — `scripts/asc_api.mjs` in the monorepo

Writes need `ASC_OWNER_WRITE_APPROVED=1` and `--owner-approved`; read each one back.

1. **Create 1.1.7:** `post /v1/appStoreVersions` `{platform:"IOS", versionString:"1.1.7"}` + app
   relationship. Localizations inherit from 1.1.6 (en-US is the only one).
2. **What's New (en-US):** `patch /v1/appStoreVersionLocalizations/<locId>` `whatsNew` =
   `Fewer, better-placed ads.` (source + claim table: `AppStore/1.1.7/release-notes.md`).
3. **Wait for build 24:** `raw "/v1/builds?filter[app]=6780714383&sort=-uploadedDate&limit=3"` until
   `version "24"` is `VALID` (Info.plist declares `ITSAppUsesNonExemptEncryption`, so no compliance prompt).
4. **Attach:** `patch /v1/appStoreVersions/<verId>/relationships/build` `{data:{type:"builds",id:"<build24Id>"}}`,
   then read the version's `build` relationship back and confirm it is 24 (not 23).
5. **Submit (Owner gate — confirm first):** `post /v1/reviewSubmissions` → `post /v1/reviewSubmissionItems`
   (the 1.1.7 appStoreVersion) → `patch /v1/reviewSubmissions/<id>` `{attributes:{submitted:true}}`.
   Success = `WAITING_FOR_REVIEW`. Release type follows 1.1.6 (`AFTER_APPROVAL`) unless the Owner says otherwise.

No App Privacy change: same SDKs, same tracking declaration, same data types (the
banner used the same Google SDK and request policy). No IAP or subscription change.

## 5. Policy branches (unmerged, local only — neither repo branch is pushed)

| Repo | Branch | Commit | Stacked on |
|---|---|---|---|
| Dudley-Development (monorepo) | `claude/econbyte-117-ad-policy` (worktree `~/dudley-worktrees/econbyte-117-ad-policy`) | `b925cbd5` | `claude/econbyte-116-ad-policy` @ `6548a386` (unmerged) |
| workspaces/dudley-core-ios | `claude/econbyte-117-ad-policy` (worktree `~/dudley-worktrees/dudley-core-econbyte-117`) | `4e377e2` | `claude/econbyte-116-ad-policy` @ `36fba95` (unmerged) |

EconByte's entry: placements `daily_set_midpoint_break`, `daily_set_return_to_feed`,
`pack_trial_rewarded`; `prohibitedPlacements` `browse_footer_banner`, `card_session_banner`,
`feed_footer_banner`; `adCapOverrides` unchanged; rationale updated. The two are byte-identical:
`validateCanonicalPolicy` (monorepo gate) against the core branch → valid, no findings.
Merge order when approved: core 116 → 117, then monorepo 116 → 117, then advance the live
`workspaces/dudley-core-ios` checkout, or the gate's default-path run reports `POLICY_SWIFT_DRIFT`.

## Risks

- **Not compiled with the vendor SDKs.** Only the SDK-less branch was typechecked. The SDK
  branch lost `GoogleBannerView` and nothing else; `EconAdRequestBuilder`, `AdManager` and
  `RewardedAdManager` are unchanged. The first real build is step 1.
- **Revenue dips before it rises.** The banner was the only ad a reader could see in their
  first session. From 1.1.7 a new install sees no ad until its second session (first-session
  rule, unchanged) and only after a finished set, or when they opt into a rewarded ad. Total
  impressions will fall. The bet is on the eCPM gap (the interstitial figure is 4 impressions).
  Watch AdMob interstitial + rewarded eCPM and fill for 14 days after release.
- **Dashboards:** `banner_impression_v1` / `banner_load_finished_v1` stop arriving from 1.1.7 on
  purpose. Any PostHog insight built on them goes flat. `ad_clicked_v1` can no longer carry
  `home`/`card`/`browse`.
- **AdMob console:** the banner unit `ca-app-pub-9950526548980224/4084037009` is no longer
  requested by 1.1.7. 1.1.6 installs keep requesting it until they update, so do not archive
  it straight away.
- **Store screenshots** are inherited from 1.1.6. If any of them shows the bottom banner strip,
  replace it with a designed screenshot. Never use a raw capture (Owner rule, 2026-09-25).
- **Policy branches are unmerged and not pushed** (the same state as the 1.1.6 ones). The app
  does not read them at runtime. They only matter to the release-evidence gate.
- **Pre-existing:** 3 Settings consent UI tests fail on this simulator exactly as on 1.1.5/1.1.6.
