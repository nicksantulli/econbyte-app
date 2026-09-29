# EconByte 1.1.7 — release notes

## What's New (en-US) — set on the 1.1.7 appStoreVersion

> Fewer, better-placed ads.

Plain and number-free on purpose. Every word is checkable against this tree:

| Claim | Where it is true |
|---|---|
| fewer | the anchored banner on Home, Browse and under a card session is gone (`AdBannerSlot.swift` and `GoogleBannerView` deleted; `AdRetune117Tests.testNoAppSourceBuildsLoadsOrMeasuresABanner`); no format was added and no cap was loosened (`AdRetune117Tests.testInterstitialThresholdsAreExactlyTheOnesShippedIn116`) |
| better-placed | what remains sits only at natural breaks — the set exit and the halfway break between two cards — or is opt-in (the rewarded pack trial) (`EconAdPlacement`, `EconAdSurface.allowsInterstitial`, `RewardedPackOfferButton`) |

What the copy deliberately does not say: any count, cap or eCPM; anything about
tracking or personalization (unchanged); anything about the rewarded offer
(unchanged since 1.1.6).

1.1.6 carries one App Store localization (en-US, read from ASC 2026-09-28), so
this is the only What's New to set.

## Build

| Build | Marketing | Notes |
|---|---|---|
| 24 | 1.1.7 | 1.1.6 build 23 (live) minus the banner (view, unit, requests, telemetry); interstitial + rewarded rules unchanged |

Not uploaded or submitted by this lane (no xcodebuild slot). See `BUILD-READY.md`
at the repo root for the build, test and App Store Connect steps.
