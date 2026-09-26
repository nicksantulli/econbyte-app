import SwiftUI

// MARK: - Rewarded pack trial controls (1.1.6)

/// "Watch an ad to read free for 24 hours" on a locked pack's offer card. Shown
/// only when the shared ad gate allows a request, the reader is under the
/// rolling 24-hour cap, and an ad has actually loaded — so tapping it always
/// plays an ad rather than a spinner. Nothing is shown otherwise; the paid
/// Unlock button beside it is unchanged.
struct RewardedPackOfferButton: View {
    let pack: EconPack

    @EnvironmentObject private var store: PurchaseManager
    @ObservedObject private var offers: EconRewardedOffers = EconGrowth.shared.rewarded
    /// Observed so the offer is requested the moment the ad SDK may start (after
    /// the first-launch prompts) and hidden the moment ads are removed.
    @ObservedObject private var monetization: EconMonetization = EconGrowth.shared.monetization

    @State private var message: String?

    private var family: EBProductFamily? {
        PurchaseManager.ProductID(rawValue: pack.productID)?.family
    }

    var body: some View {
        Group {
            if offers.mayOffer(monetization: monetization) && offers.isAdReady {
                Button {
                    Task { await watch() }
                } label: {
                    Label("Watch an ad · read free for 24 hours", systemImage: "play.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButton())
                .disabled(offers.isPresenting)
                .accessibilityIdentifier("pack-\(pack.id)-watchAd")
                .accessibilityHint("Plays a short ad, then opens this pack for 24 hours")
            }
        }
        .onAppear { offers.preloadIfPermitted(monetization: monetization) }
        .onChange(of: monetization.didStartSDK) { started in
            if started { offers.preloadIfPermitted(monetization: monetization) }
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }

    private func watch() async {
        let outcome = await offers.watch(forPackProductID: pack.productID,
                                         family: family,
                                         monetization: monetization,
                                         store: store)
        switch outcome {
        case .rewarded, .notOffered:
            break
        case .notRewarded:
            message = "The ad closed before it finished, so the pack is still locked."
        case .noAdAvailable:
            message = "No ad is available right now. Try again in a little while."
        }
    }
}

/// On a pack opened by a rewarded ad: when the free read ends.
struct RewardedUnlockNote: View {
    let end: Date

    var body: some View {
        Label("Free until \(end.formatted(.dateTime.weekday(.abbreviated).hour().minute()))",
              systemImage: "clock")
            .font(EconType.caption)
            .foregroundColor(EconColor.textSecondary)
            .accessibilityIdentifier("pack-rewardedUnlockNote")
    }
}
