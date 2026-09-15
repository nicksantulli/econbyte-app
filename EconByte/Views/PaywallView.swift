import SwiftUI
import StoreKit

/// Paywall shown when a free user taps a locked topic. Sells the
/// `com.nsantulli.econbyte.unlockall` non-consumable through the shared
/// `OfferCard` + `PurchaseButton` ("Unlock · $2.99"; StoreKit price, never a
/// literal — DUD-186; Phase 11 loading / unavailable states from
/// `PurchaseButtonModel`).
struct PaywallView: View {
    /// Where the reader came from, so `paywall_viewed` and the purchase events
    /// carry a real entry point rather than an assumed one.
    var entryPoint: EconEntryPoint = .topicGrid

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: PurchaseManager
    @EnvironmentObject private var growth: EconGrowth
    @State private var working = false
    @State private var alert: PurchaseAlertCopy.Alert?

    private var lockedTopicCount: Int {
        let content = ContentStore.shared
        return content.topics.filter { !content.isTopicFree($0.id) }.count
    }

    private var lockedCardCount: Int {
        let content = ContentStore.shared
        return content.allCards.filter { !content.isTopicFree($0.topicId) }.count
    }

    private var model: PurchaseButtonModel {
        PurchaseButtonModel.make(action: "Unlock",
                                 price: store.priceState(for: .unlockAll),
                                 ownedLabel: store.isUnlockAllPurchased ? "Owned" : nil,
                                 pending: store.isPending(.unlockAll),
                                 working: working,
                                 isLoadingProducts: store.isLoadingProducts)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Econ.ocean.ignoresSafeArea()
                ScrollView {
                    // D18: Unlock All is the core curriculum. Topic packs are
                    // separate purchases and are not promised here.
                    OfferCard(icon: "lock.open.fill",
                              title: "Unlock All Topics",
                              subtitle: "\(lockedTopicCount) more core topics, \(lockedCardCount) cards. One-time purchase.",
                              highlighted: !store.isUnlockAllPurchased,
                              identifier: "unlockAllOffer",
                              button: PurchaseButton(model: model,
                                                     identifier: "paywallUnlockButton",
                                                     unavailableIdentifier: "paywallPricesUnavailable",
                                                     onRetry: { Task { await store.loadProducts() } },
                                                     action: buy),
                              restoreIdentifier: "paywallRestoreButton",
                              onRestore: store.isUnlockAllPurchased ? nil : restore,
                              restoreDisabled: working)
                        .padding(20)
                }
            }
            // Deliberately not "EconByte Pro": the one-time products are
            // separate purchases, not a bundle (design section 8).
            .navigationTitle("Purchases")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") { dismiss() }
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(Econ.sky)
                        .accessibilityIdentifier("paywallCloseButton")
                }
            }
            .onChange(of: store.isUnlockAllPurchased) { unlocked in
                if unlocked { dismiss() }
            }
            .purchaseAlert($alert)
        }
        .tint(Econ.sky)
        .task {
            growth.monetization.setBlocker(.paywall, active: true)
            growth.review.noteNegativeSessionEvent(.paywall)
            await store.loadProducts()
            EBEvents.paywallViewed(entryPoint: entryPoint.ebEntryPoint,
                                   productsReady: store.productsReady)
        }
        .onDisappear { growth.monetization.setBlocker(.paywall, active: false) }
    }

    // RECONCILED (1.1.2): purchase telemetry lives INSIDE `PurchaseManager`,
    // where the StoreKit product id is reduced to its family before anything
    // leaves. The view passes only where the tap happened.
    private func buy() {
        working = true
        Task {
            let next = await PurchaseFlow.buy(.unlockAll, from: entryPoint.ebEntryPoint, store: store, growth: growth,
                                              accessGranted: { store.isUnlockAllPurchased })
            working = false
            alert = next
        }
    }

    private func restore() {
        working = true
        Task {
            let next = await PurchaseFlow.restore(from: entryPoint.ebEntryPoint, store: store, growth: growth)
            working = false
            alert = next
        }
    }
}

// MARK: - Shared purchase UI (Phase 11)

/// "Prices unavailable — Try again": shown wherever a buy control has no
/// StoreKit price after a completed fetch. The buy control itself stays
/// readable and disabled beside it.
struct PricesUnavailableNotice: View {
    let identifier: String
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundColor(Econ.amber)
                .accessibilityHidden(true)
            Text("\(PurchasePresentation.pricesUnavailableText) —")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(Econ.white.opacity(0.8))
            Button(PurchasePresentation.retryText, action: onRetry)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(Econ.sky)
                .buttonStyle(.borderless)
                .accessibilityIdentifier("\(identifier)RetryButton")
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}

extension View {
    /// Presents a `PurchaseAlertCopy.Alert`.
    func purchaseAlert(_ alert: Binding<PurchaseAlertCopy.Alert?>) -> some View {
        self.alert(alert.wrappedValue?.title ?? "",
                   isPresented: Binding(get: { alert.wrappedValue != nil },
                                        set: { if !$0 { alert.wrappedValue = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alert.wrappedValue?.message ?? "")
        }
    }
}
