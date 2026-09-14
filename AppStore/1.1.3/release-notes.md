# EconByte 1.1.3 — release notes

## What's New (en-US) — set on the 1.1.3 appStoreVersion by the 2026-09-14 growth lane

Honest and number-free, per the manager-loop brief. Every line is checkable
against this tree:

> • On first open, EconByte now asks once whether to share anonymous usage
> analytics. Your answer is always changeable in Settings → Privacy & Data.
> • Ad placement tuning: a small banner on the home screen and under cards.
> Ads still never interrupt a card.
> • The rating request now waits until you have come back and finished a set.
> • New topic packs: Markets & Investing Basics and Personal Economics — four
> topics each, every card sourced the same way, each pack a one-time purchase
> shown on the home screen with a preview before you decide.
> • Fixes.

| Line | Where it is true |
|---|---|
| first-open analytics question | `FirstOpenConsentPolicy`, `AnalyticsConsentCard`, `EconByteApp` — keyed builds only; `GrowthAuditTests` |
| always changeable in Settings | `SettingsView.privacySection` (unchanged) |
| banner on Home and under cards | `AdBannerSlot` mounted in `HomeView` and `CardModeView` |
| ads never interrupt a card | the interstitial's only placement is the set exit (`EconAdPlacement`) |
| rating request waits for the second open + a finished set | `ReviewRequestPolicy` review-rules-v2; `GrowthSystemsTests` §9 |
| two topic packs, four topics each, sourced the same way, preview on Home, one-time purchase | `Resources/packs-v1.json` (2 × 4 × 8, validated by `PackCatalog` + `PackCatalogTests` under the core editorial rules); `PackOfferView` on Home; `com.nsantulli.econbyte.pack.markets` / `.pack.personal` non-consumables (ASC, 2026-09-14) |

What the copy deliberately does not say: any count, cap or percentage; anything
about App Tracking Transparency (unchanged from build 13, still asked once from
the session-complete exit); anything about crash reporting defaults (unchanged,
opt-in).

## Build

| Build | Marketing | Notes |
|---|---|---|
| 14 | 1.1.3 | build 13 (live) + first-open consent card, Release key gate, review-rules-v2, anchored banner, interstitial pacing audit |
| 15 | 1.1.3 | build 14 + two topic packs (64 sourced cards) and their two non-consumable IAPs; Unlock All unchanged and does not include packs (CONTENT-DECISIONS D18) |

Not submitted for review by either lane. Attaching the build to the version is the
lane's last ASC write; `reviewSubmission` is an Owner gate.
