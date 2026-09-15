import SwiftUI
import StoreKit

/// One topic pack as an `OfferCard` (Home's featured pack and the Browse tab).
///
/// Locked: name, topic and card counts, the four topic names, a three-card
/// preview (title + first sentence of each definition, verbatim from the
/// catalog), the `PurchaseButton` ("Unlock · $1.99") and Restore.
/// Readable: the four topics as tiles, opened exactly like core topics, and the
/// button in its owned state — "Owned" (bought, or via the All Packs Bundle) or
/// "Included with Pro".
///
/// Access is `PurchaseManager.hasAccess(packProductID:)`: a verified
/// entitlement for the pack or the bundle, or an active Pro subscription (D19).
/// Unlock All never opens a pack (D18).
struct PackOfferView: View {
    let pack: EconPack
    /// Where the offer is shown, for `pack_shown_v1` and the purchase funnel.
    var entryPoint: EBEntryPoint = .home
    let onOpenTopic: (EconTopic) -> Void

    @EnvironmentObject private var content: ContentStore
    @EnvironmentObject private var store: PurchaseManager
    @EnvironmentObject private var growth: EconGrowth

    @State private var working = false
    @State private var didRecordShown = false
    @State private var alert: PurchaseAlertCopy.Alert?

    private var productID: PurchaseManager.ProductID? {
        PurchaseManager.ProductID(rawValue: pack.productID)
    }
    private var readable: Bool { store.hasAccess(packProductID: pack.productID) }

    static func ownedLabel(ownsOutright: Bool, familyShared: Bool, readable: Bool) -> String? {
        if ownsOutright { return familyShared ? "Family Sharing" : "Owned" }
        return readable ? "Included with Pro" : nil
    }

    private var model: PurchaseButtonModel {
        let owned = Self.ownedLabel(ownsOutright: store.ownsPack(productID: pack.productID),
                                    familyShared: store.familySharedProductIDs.contains(pack.productID)
                                        || (store.isPackBundlePurchased
                                            && store.familySharedProductIDs.contains(PurchaseManager.ProductID.packBundle.rawValue)),
                                    readable: readable)
        return PurchaseButtonModel.make(action: "Unlock",
                                        price: productID.map { store.priceState(for: $0) } ?? .unavailable,
                                        ownedLabel: owned,
                                        pending: productID.map { store.isPending($0) } ?? false,
                                        working: working,
                                        isLoadingProducts: store.isLoadingProducts)
    }

    var body: some View {
        OfferCard(icon: pack.icon,
                  title: pack.name,
                  subtitle: "\(pack.topics.count) topics · \(pack.cards.count) cards",
                  highlighted: !readable,
                  identifier: "pack-\(pack.id)",
                  button: PurchaseButton(model: model,
                                         identifier: "pack-\(pack.id)-buy",
                                         unavailableIdentifier: "pack-\(pack.id)-pricesUnavailable",
                                         onRetry: { Task { await store.loadProducts() } },
                                         action: buy),
                  restoreIdentifier: "pack-\(pack.id)-restore",
                  onRestore: readable ? nil : restore,
                  restoreDisabled: working) {
            if readable {
                topicGrid
            } else {
                topicLine
                preview
            }
        }
        .onAppear { recordShownOnce() }
        .purchaseAlert($alert)
    }

    // MARK: Pieces

    private var topicLine: some View {
        Text(pack.topics.map(\.name).joined(separator: " · "))
            .font(EconType.caption)
            .foregroundColor(EconColor.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel("Topics: \(pack.topics.map(\.name).joined(separator: ", "))")
    }

    /// Three cards, one from each of the first three topics — the card's own
    /// title and the first sentence of its own definition, never paraphrased.
    private var preview: some View {
        VStack(alignment: .leading, spacing: EconSpace.xs) {
            ForEach(pack.preview) { card in
                VStack(alignment: .leading, spacing: EconSpace.xxs) {
                    Text(card.concept)
                        .font(EconType.subheadlineEmphasis)
                        .foregroundColor(EconColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(ContentStore.firstSentence(of: card.conceptBody))
                        .font(EconType.footnote)
                        .foregroundColor(EconColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
        .econInset()
        .accessibilityIdentifier("pack-\(pack.id)-preview")
    }

    private var topicGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: EconSpace.s) {
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

    // MARK: Plumbing

    private func recordShownOnce() {
        guard !readable, !didRecordShown, let productID else { return }
        didRecordShown = true
        EBEvents.packShown(family: productID.family, entryPoint: entryPoint)
    }

    private func buy() {
        guard let productID else { return }
        working = true
        Task {
            let next = await PurchaseFlow.buy(productID, from: entryPoint, store: store, growth: growth,
                                              accessGranted: { store.hasAccess(packProductID: pack.productID) })
            working = false
            alert = next
        }
    }

    private func restore() {
        working = true
        Task {
            let next = await PurchaseFlow.restore(from: entryPoint, store: store, growth: growth)
            working = false
            alert = next
        }
    }
}

/// The All Packs Bundle (`com.nsantulli.econbyte.pack.bundle`, 1.1.4): every
/// topic pack in one non-consumable. Shown above the packs on Browse while at
/// least one pack is still locked, and as "Owned" once bought. Not offered to
/// a Pro subscriber who has every pack through Pro.
struct PackBundleOfferView: View {
    var entryPoint: EBEntryPoint = .topicGrid

    @EnvironmentObject private var content: ContentStore
    @EnvironmentObject private var store: PurchaseManager
    @EnvironmentObject private var growth: EconGrowth

    @State private var working = false
    @State private var didRecordShown = false
    @State private var alert: PurchaseAlertCopy.Alert?

    static func isOffered(bundleOwned: Bool, allPacksReadable: Bool) -> Bool {
        bundleOwned || !allPacksReadable
    }

    private var owned: Bool { store.isPackBundlePurchased }

    var body: some View {
        let id = PurchaseManager.ProductID.packBundle
        let model = PurchaseButtonModel.make(
            action: "Unlock",
            price: store.priceState(for: id),
            ownedLabel: owned ? (store.familySharedProductIDs.contains(id.rawValue) ? "Family Sharing" : "Owned") : nil,
            pending: store.isPending(id),
            working: working,
            isLoadingProducts: store.isLoadingProducts)
        return OfferCard(icon: "square.stack.3d.up.fill",
                         title: "All Packs Bundle",
                         subtitle: "All \(content.packs.count) packs · \(content.packCards.count) cards",
                         highlighted: !owned,
                         identifier: "packBundle",
                         button: PurchaseButton(model: model,
                                                identifier: "packBundle-buy",
                                                unavailableIdentifier: "packBundle-pricesUnavailable",
                                                onRetry: { Task { await store.loadProducts() } },
                                                action: buy),
                         restoreIdentifier: "packBundle-restore",
                         onRestore: owned ? nil : restore,
                         restoreDisabled: working)
            .onAppear {
                guard !owned, !didRecordShown else { return }
                didRecordShown = true
                EBEvents.packShown(family: .packBundle, entryPoint: entryPoint)
            }
            .purchaseAlert($alert)
    }

    private func buy() {
        working = true
        Task {
            let next = await PurchaseFlow.buy(.packBundle, from: entryPoint, store: store, growth: growth,
                                              accessGranted: { store.isPackBundlePurchased })
            working = false
            alert = next
        }
    }

    private func restore() {
        working = true
        Task {
            let next = await PurchaseFlow.restore(from: entryPoint, store: store, growth: growth)
            working = false
            alert = next
        }
    }
}
