import SwiftUI

// MARK: - Banner slot (Home + card session 1.1.3; Browse 1.1.4 Phase 11)
//
// Added 2026-09-14 on the Owner's revenue order (Dudley factory pattern from
// Table Talk 1.1.5 `AdBannerSlot`). EconByte's only ad surface used to be the
// set-exit interstitial, which needs a completed set — and, from build 13, an
// answered ATT prompt — before it can fire even once. The banner is the steady
// surface: anchored to the bottom of a list surface (above the tab bar) or of
// a card session (above the home indicator), sized by Google's adaptive rule
// for the width it gets, non-personalized (`npa=1`, `rdp=1`) like every other
// request in the app.
//
// It is policy-gated exactly like the interstitial. The view is not even
// constructed on a surface the placement matrix (`EconAdSurface`) excludes,
// for a Remove Ads owner or an EconByte Pro subscriber (1.1.4, D19), for a
// reader in the EEA/UK (DUD-224), before the tracking decision, or while the
// first-launch permission prompts are still owed
// (`EconMonetization.canRequestAds`), so for them no banner is ever requested
// and the ad SDK is never touched. It reserves no space until an ad has
// actually loaded — a no-fill is invisible rather than a blank strip. When a
// surface turns sensitive (Browse starts a search) the slot is REMOVED, not
// hidden: a hidden live banner would still be requested and counted.

struct AdBannerSlot: View {
    /// Where the slot sits; decides whether a banner may exist at all.
    let surface: EconAdSurface

    @ObservedObject var monetization: EconMonetization
    @ObservedObject private var purchases = PurchaseManager.shared
    @State private var loadedHeight: CGFloat = 0

    var body: some View {
        Group {
            if let placement = surface.bannerPlacement,
               let unit = EconAdUnit.banner,
               !purchases.adsSuppressed,
               monetization.didStartSDK,
               monetization.canRequestAds {
                GeometryReader { geo in
                    GoogleBannerView(adUnitID: unit,
                                     width: geo.size.width,
                                     policy: monetization.currentRequestPolicy,
                                     placement: placement,
                                     onLoadedHeight: { height in
                                         withAnimation(.easeOut(duration: 0.2)) { loadedHeight = height }
                                     })
                        .frame(width: geo.size.width, height: loadedHeight)
                }
                .frame(height: loadedHeight)
                .background(Econ.ocean)
                .accessibilityElement(children: .contain)
                .accessibilityHidden(loadedHeight == 0)
                .accessibilityLabel("Advertisement")
                .accessibilityIdentifier("ad.banner.\(placement.rawValue)")
            }
        }
        // A removed slot must not come back reserving the old ad's height.
        .onChange(of: surface) { _ in loadedHeight = 0 }
    }
}
