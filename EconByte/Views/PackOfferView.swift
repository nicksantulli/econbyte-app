import SwiftUI
import StoreKit

/// One topic pack (1.1.3; Home's featured pack and the Browse tab in 1.1.4).
///
/// Locked: the pack's name and summary, its four topic names, a three-card
/// preview (title + first sentence of each definition, verbatim from the
/// catalog), a buy button carrying the localized StoreKit price, and Restore
/// (App Review: Restore wherever a purchase is offered). No price literal
/// anywhere — `PurchasePresentation` renders "—" and disables the control
/// until StoreKit has supplied one.
///
/// Owned: the pack's four topics as tiles, opened exactly like core topics.
///
/// Access is read from `PurchaseManager.hasAccess(packProductID:)` — a verified
/// StoreKit entitlement for the pack itself, or an active Pro subscription
/// (D19). Unlock All never opens a pack (D18).
struct PackOfferView: View {
    let pack: EconPack
    /// Where the offer is shown, for `pack_shown_v1`.
    var entryPoint: EBEntryPoint = .home
    let onOpenTopic: (EconTopic) -> Void

    @EnvironmentObject private var content: ContentStore
    @EnvironmentObject private var store: PurchaseManager
    @EnvironmentObject private var growth: EconGrowth

    @State private var working = false
    @State private var didRecordShown = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false

    private var productID: PurchaseManager.ProductID? {
        PurchaseManager.ProductID(rawValue: pack.productID)
    }
    private var product: Product? { productID.flatMap { store.product(for: $0) } }
    /// Owned outright (verified entitlement for this pack's own product).
    private var ownedOutright: Bool { store.isPackPurchased(productID: pack.productID) }
    /// Readable: owned outright or included by an active Pro subscription (D19).
    private var owned: Bool { store.hasAccess(packProductID: pack.productID) }
    private var canBuy: Bool {
        productID != nil && PurchasePresentation.canPurchase(
            displayPrice: product?.displayPrice, isWorking: working, isLoading: store.isLoadingProducts)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Text(pack.summary)
                .font(.system(size: 14, design: .rounded))
                .foregroundColor(Econ.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)

            if owned {
                topicGrid
            } else {
                topicLine
                preview
                buyRow
            }
        }
        .padding(18)
        .background(Econ.tide.opacity(owned ? 0.15 : 0.10))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Econ.amber.opacity(owned ? 0 : 0.35), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pack-\(pack.id)")
        .onAppear { recordShownOnce() }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    // MARK: Pieces

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: pack.icon)
                .font(.title3)
                .foregroundColor(owned ? Econ.sky : Econ.amber)
                .accessibilityHidden(true)
            Text(pack.name)
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundColor(Econ.white)
            Spacer()
            Text(ownedOutright ? "Owned ✓" : (owned ? "Included with Pro ✓" : "\(pack.cards.count) cards"))
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(owned ? Econ.sky : Econ.subtext)
        }
    }

    private var topicLine: some View {
        Text(pack.topics.map(\.name).joined(separator: " · "))
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundColor(Econ.subtext)
            .tracking(0.5)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel("Topics: \(pack.topics.map(\.name).joined(separator: ", "))")
    }

    /// Three cards, one from each of the first three topics — the card's own
    /// title and the first sentence of its own definition, never paraphrased.
    private var preview: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(pack.preview) { card in
                VStack(alignment: .leading, spacing: 3) {
                    Text(card.concept)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(Econ.white)
                    Text(ContentStore.firstSentence(of: card.conceptBody))
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(Econ.white.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(12)
        .background(Econ.ocean.opacity(0.6))
        .cornerRadius(12)
        .accessibilityIdentifier("pack-\(pack.id)-preview")
    }

    private var buyRow: some View {
        VStack(spacing: 10) {
            Button {
                buy()
            } label: {
                if working {
                    ProgressView().tint(Econ.ink)
                } else {
                    Text("Unlock \(pack.name) — \(PurchasePresentation.priceText(product?.displayPrice))")
                }
            }
            .buttonStyle(PrimaryButton())
            .disabled(!canBuy)
            .opacity(canBuy ? 1 : 0.55)
            .accessibilityIdentifier("pack-\(pack.id)-buy")

            Button("Restore Purchases") { restore() }
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(Econ.sky)
                .disabled(working)
                .accessibilityIdentifier("pack-\(pack.id)-restore")
        }
    }

    private var topicGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(pack.topics) { topic in
                Button {
                    onOpenTopic(topic)
                } label: {
                    TopicTile(topic: topic, locked: false)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("topic-\(topic.id)")
            }
        }
    }

    // MARK: Plumbing (mirrors SettingsView / PaywallView)

    private func recordShownOnce() {
        guard !owned, !didRecordShown, let productID else { return }
        didRecordShown = true
        EBEvents.packShown(family: productID.family, entryPoint: entryPoint)
    }

    private func buy() {
        guard let productID else { return }
        working = true
        growth.monetization.setBlocker(.purchase, active: true)
        growth.review.noteNegativeSessionEvent(.purchase)
        Task {
            let result = await store.purchase(productID, from: .home)
            working = false
            growth.monetization.setBlocker(.purchase, active: false)
            growth.syncEntitlements(from: store)
            if case .success = result {
                // `purchase_finished_v1` already recorded the outcome.
            } else {
                growth.review.noteNegativeSessionEvent(.purchaseFailure)
            }
            handle(result, successTitle: "Unlocked")
        }
    }

    private func restore() {
        working = true
        growth.monetization.setBlocker(.restore, active: true)
        growth.review.noteNegativeSessionEvent(.restore)
        Task {
            let result = await store.restorePurchases(from: .home)
            working = false
            growth.monetization.setBlocker(.restore, active: false)
            growth.syncEntitlements(from: store)
            if case .failed = result {
                growth.review.noteNegativeSessionEvent(.restoreFailure)
                growth.diagnosticLog.capture(.restoreFailed)
            }
            handle(result, successTitle: "Restored")
        }
    }

    private func handle(_ result: PurchaseManager.PurchaseResult, successTitle: String) {
        switch result {
        case .success:
            if !owned {
                present(title: successTitle,
                        message: "Your purchase is processing. If the pack stays locked, tap Restore Purchases.")
            }
        case .cancelled:
            break
        case .pending:
            present(title: "Purchase Pending",
                    message: "Your purchase needs approval. You'll get access once it's approved.")
        case .productUnavailable:
            present(title: "Purchase Unavailable",
                    message: store.productsLoadError ?? "We couldn't reach the App Store. Check your connection and try again.")
            Task { await store.loadProducts() }
        case .failed(let message):
            present(title: "Something Went Wrong", message: message)
        }
    }

    private func present(title: String, message: String) {
        growth.review.noteNegativeSessionEvent(.errorShown)
        alertTitle = title
        alertMessage = message
        showAlert = true
    }
}
