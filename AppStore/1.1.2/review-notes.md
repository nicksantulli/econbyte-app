# EconByte 1.1.2 (build 13) — App Review notes

**Status: DRAFT, not applied.** This lane writes the text; the orchestrator sets
it on the App Store Connect version (`appStoreVersions/3efb2d70-c6f8-4bbc-95c4-fcbc18f75f72`,
attribute `reviewDetails.notes` via `/v1/appStoreReviewDetails`). Nothing here has
been submitted.

Written because App Review asked for it by name. The 2026-09-07 rejection of
build 12 under Guideline 5.1.2(i) ends with:

> If the app tracks users on all supported platforms, the app must use App
> Tracking Transparency to request permission before collecting data used to
> track. **When resubmitting, indicate in the Review Notes where the permission
> request is located.**

---

## The text to set (verbatim)

```
WHERE THE APP TRACKING TRANSPARENCY PROMPT APPEARS (Guideline 5.1.2(i), build 12)

Thank you for the guidance on build 12. Build 13 adds the App Tracking
Transparency request, and it appears here:

  Screen:  the session-complete screen ("Streak: N days — You finished
           <topic>"), which is reached only after finishing a card set.
  Trigger: tapping "Done" or "Browse More Topics" on that screen.
  When:    once per install, the first time the reader leaves a completed
           set. It is never shown at launch and never shown twice.

To reach it from a fresh install:
  1. Launch the app and tap any topic on the home screen.
  2. Swipe or tap through the cards to the end of the set.
  3. On the session-complete screen, tap "Done".
  4. The system tracking-permission alert appears at that point.

No ad request of any kind is made before the reader answers. The ad SDK is not
initialised and no ad is loaded until the prompt has been answered or dismissed,
so nothing is collected for tracking beforehand.

REGIONAL DIFFERENCE, as requested in the "behaves differently in different
countries or regions" note: EconByte serves no ads at all in the EEA and the
United Kingdom (a deliberate decision, made instead of a consent-management
platform). Because no ads are served there, no tracking permission is requested
there either. The check uses the device Region setting only — no location
permission and no IP lookup — and it fails closed: a region the app cannot
determine is treated as ad-restricted. To see the prompt, set Settings > General
> Language & Region > Region to the United States (or any region outside the
EEA/UK) before step 1. Readers who have purchased "Remove Ads" also see no ads
and are not asked.

Ads remain non-personalized in every region and for every answer to the prompt:
each request carries npa=1 and rdp=1, and the SDK-level personalization state is
disabled. Authorization is used for ad measurement, which is what the
tracking-permission string says.

IN-APP PURCHASES: two non-consumables, "Unlock All Topics" and "Remove Ads".
Both are restorable from Settings > Restore Purchases. No account and no sign-in
is required anywhere in the app.
```

---

## Why each claim above is true, and where it is enforced

| Claim in the notes | Where it is enforced | Test |
|---|---|---|
| Prompt is on the session-complete screen's exit path | `EconByte/Views/SessionCompleteView.swift` → `finish()` calls `resolveTrackingAuthorizationIfNeeded()` before the ad decision | `TrackingAuthorizationTests.testThePromptPrecedesTheFirstAdRequest` |
| Never at launch | `EconGrowth.applicationDidBecomeActive` calls only `startAdsIfPermitted()`, which never prompts | `testNothingHappensAtLaunchWithNoCompletedSession` |
| Once per install, surviving relaunch | `econ.ads.trackingPromptRequested` in `UserDefaults`, written before the await | `testThePromptIsAskedOnceWithinASession`, `testThePromptIsNotRepeatedOnTheNextLaunchEvenIfItWasNeverPresented` |
| No ad request precedes the answer | `EconMonetization.adRequestsPermitted` gates `startSDK`, `preload` and every re-preload | `testTheAdSDKIsNotStartedWhileTheTrackingDecisionIsOutstanding` |
| Never over a consent screen | `finish()` dismisses the analytics/diagnostics card and the reminder primer before awaiting the prompt | reviewed by inspection; the cards are `@State` flags cleared on the same turn |
| No ads and no prompt in the EEA/UK | `EconAdRegion.restrictedRegionCodes` (EU 27 + IS/LI/NO + GB), fails closed on `.unknown` | `testAdRestrictedRegionsAreNeverPrompted`, `testRestrictedRegionsCoverTheEEAAndUnitedKingdom` |
| Remove Ads owners are not asked | `shouldRequestTrackingAuthorization` returns false when `entitlements.adsSuppressed` | `testRemoveAdsOwnersAreNeverPrompted` |
| npa=1 / rdp=1 on every answer | `EconAdRequestPolicy.extras`, plus `publisherPrivacyPersonalizationState = .disabled` | `testEveryRequestIsNonPersonalizedForEveryTrackingOutcome`, `testEveryAdRequestIsNonPersonalized` |

## What is deliberately NOT claimed

- Nothing about "we do not track". The app's published App Privacy label answers
  **Device ID and Advertising Data: used to track you — Yes**, and build 13's
  privacy manifest says the same. Telling App Review the app does not track,
  after asking them to accept a tracking prompt, is the contradiction that
  produced this rejection in the first place.
- Nothing about personalized ads being enabled. They are not.
- No demo account, because the app has no accounts.
