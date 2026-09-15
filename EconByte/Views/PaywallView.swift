import SwiftUI
import StoreKit

/// Paywall shown when a free user taps a locked topic. Sells the
/// `com.nsantulli.econbyte.unlockall` non-consumable. Price is read from
/// StoreKit (`product.displayPrice`) — never hardcoded — per DUD-186. While
/// StoreKit is fetching, the button reads "Loading price…"; when it gave no
/// price, the button reads "Unlock All" (disabled) with "Prices unavailable —
/// Try again" under it (Phase 11 — no bare placeholder dash).
struct PaywallView: View {
    /// Where the reader came from, so `paywall_viewed` and the purchase events
    /// carry a real entry point rather than an assumed one.
    var entryPoint: EconEntryPoint = .topicGrid

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: PurchaseManager
    @EnvironmentObject private var growth: EconGrowth
    @State private var working = false
    @State private var alert: PurchaseAlertCopy.Alert?

    private var priceState: PurchasePresentation.PriceState { store.priceState(for: .unlockAll) }
    private var pending: Bool { store.isPending(.unlockAll) }

    private var lockedTopicCount: Int {
        let topics = ContentStore.shared.topics
        return topics.filter { !ContentStore.shared.isTopicFree($0.id) }.count
    }

    private var canBuy: Bool {
        !pending && PurchasePresentation.canPurchase(displayPrice: priceState.displayPrice,
                                                     isWorking: working, isLoading: store.isLoadingProducts)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Econ.ocean.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 24) {
                        Image(systemName: "lock.open.fill")
                            .font(.system(size: 52))
                            .foregroundColor(Econ.amber)
                            .padding(.top, 24)
                            .accessibilityHidden(true)

                        Text("Unlock All Topics")
                            .font(.system(size: 26, weight: .heavy, design: .rounded))
                            .foregroundColor(Econ.white)

                        Text("Inflation and Interest Rates are free. Unlock the remaining \(lockedTopicCount) topics — GDP, Labor Markets, Trade & Tariffs, Recessions and more — with a one-time purchase.")
                            .font(.system(size: 15, design: .rounded))
                            .foregroundColor(Econ.white.opacity(0.75))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)

                        VStack(spacing: 12) {
                            featureRow("checkmark.circle.fill", "Every topic, unlocked forever")
                            // D18 (1.1.3): Unlock All is the core curriculum. Topic
                            // packs are separate purchases and are not promised here.
                            featureRow("books.vertical.fill", "The full core curriculum, every topic in Browse Topics")
                            featureRow("icloud.and.arrow.down.fill", "Restores across your devices")
                        }
                        .padding(.horizontal, 28)

                        if store.isUnlockAllPurchased {
                            Text("Already unlocked ✓")
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                .foregroundColor(Econ.sky)
                                .padding(.top, 8)
                        } else {
                            Button {
                                buy()
                            } label: {
                                if working {
                                    ProgressView().tint(Econ.ink)
                                } else {
                                    Text(PurchasePresentation.buyTitle("Unlock All", priceState, pending: pending))
                                }
                            }
                            .buttonStyle(PrimaryButton())
                            .disabled(!canBuy)
                            .opacity(canBuy ? 1 : 0.55)
                            .padding(.horizontal, 28)
                            .padding(.top, 8)
                            .accessibilityIdentifier("paywallUnlockButton")

                            if priceState == .unavailable {
                                PricesUnavailableNotice(identifier: "paywallPricesUnavailable") {
                                    Task { await store.loadProducts() }
                                }
                            }

                            Button("Restore Purchases") { restore() }
                                .buttonStyle(SecondaryButton())
                                .disabled(working)
                                .padding(.horizontal, 28)
                                .accessibilityIdentifier("paywallRestoreButton")
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
            // Deliberately not "EconByte Pro": the two products are separate
            // one-time purchases, not a bundle (design section 8).
            .navigationTitle("Purchases")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") { dismiss() }.foregroundColor(Econ.sky)
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

    private func featureRow(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(Econ.amber)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: 15, design: .rounded))
                .foregroundColor(Econ.white.opacity(0.9))
            Spacer()
        }
    }

    private func buy() {
        working = true
        growth.monetization.setBlocker(.purchase, active: true)
        growth.review.noteNegativeSessionEvent(.purchase)
        // RECONCILED (1.1.2): purchase telemetry moved INTO `PurchaseManager`,
        // where the branch is known and the StoreKit product id can be reduced
        // to its family before anything leaves — the id itself is a prohibited
        // property. The view passes only where the tap happened.
        Task {
            let result = await store.purchase(.unlockAll, from: entryPoint.ebEntryPoint)
            working = false
            growth.monetization.setBlocker(.purchase, active: false)
            growth.syncEntitlements(from: store)
            if case .success = result {} else {
                growth.review.noteNegativeSessionEvent(.purchaseFailure)
            }
            show(result, kind: .purchase)
        }
    }

    private func restore() {
        working = true
        growth.monetization.setBlocker(.restore, active: true)
        growth.review.noteNegativeSessionEvent(.restore)
        Task {
            let result = await store.restorePurchases(from: entryPoint.ebEntryPoint)
            working = false
            growth.monetization.setBlocker(.restore, active: false)
            growth.syncEntitlements(from: store)
            if case .failed = result {
                growth.review.noteNegativeSessionEvent(.restoreFailure)
                growth.diagnosticLog.capture(.restoreFailed)
            }
            show(result, kind: .restore)
        }
    }

    private func show(_ result: PurchaseManager.PurchaseResult, kind: PurchaseAlertCopy.Kind) {
        if result == .productUnavailable { Task { await store.loadProducts() } }
        guard let next = PurchaseAlertCopy.alert(for: result, kind: kind,
                                                 accessGranted: store.isUnlockAllPurchased) else { return }
        // A user-facing error is a bad moment to ask for a rating (rules-v2).
        growth.review.noteNegativeSessionEvent(.errorShown)
        alert = next
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
