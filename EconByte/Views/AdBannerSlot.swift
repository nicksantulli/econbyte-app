import SwiftUI

// MARK: - Banner slot (Home + card session), 1.1.3
//
// Added 2026-09-14 on the Owner's revenue order (Dudley factory pattern from
// Table Talk 1.1.5 `AdBannerSlot`). EconByte's only ad surface used to be the
// set-exit interstitial, which needs a completed set — and, from build 13, an
// answered ATT prompt — before it can fire even once. The banner is the steady
// surface: anchored to the bottom of Home and of a card session, sized by
// Google's adaptive rule for the width it gets, non-personalized (`npa=1`,
// `rdp=1`) like every other request in the app.
//
// It is policy-gated exactly like the interstitial. The view is not even
// constructed for a Remove Ads owner, for a reader in the EEA/UK (DUD-224), or
// before the tracking decision (`EconMonetization.canRequestAds`, the build-13
// 5.1.2(i) ordering gate), so for them no banner is ever requested and the ad
// SDK is never touched. It reserves no space until an ad has actually loaded —
// a no-fill is invisible rather than a blank strip.

struct AdBannerSlot: View {
    /// `.bannerHome` or `.bannerCard`; measurement only.
    let placement: EBAdPlacement

    @ObservedObject var monetization: EconMonetization
    @ObservedObject private var purchases = PurchaseManager.shared
    @State private var loadedHeight: CGFloat = 0

    var body: some View {
        if let unit = EconAdUnit.banner,
           !purchases.isRemoveAdsPurchased,
           monetization.didStartSDK,
           monetization.canRequestAds {
            GeometryReader { geo in
                GoogleBannerView(adUnitID: unit,
                                 width: geo.size.width,
                                 policy: monetization.currentRequestPolicy,
                                 onLoadedHeight: { height in
                                     let wasHidden = loadedHeight == 0
                                     withAnimation(.easeOut(duration: 0.2)) { loadedHeight = height }
                                     if wasHidden, height > 0 {
                                         EBEvents.bannerImpression(placement: placement)
                                     }
                                 })
                    .frame(width: geo.size.width, height: loadedHeight)
            }
            .frame(height: loadedHeight)
            .background(Econ.ocean)
            .accessibilityHidden(loadedHeight == 0)
            .accessibilityLabel("Advertisement")
            .accessibilityIdentifier("ad.banner.\(placement.rawValue)")
        }
    }
}
