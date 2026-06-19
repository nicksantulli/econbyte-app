import SwiftUI
import StoreKit

/// Paywall shown when a free user taps a locked topic. Sells the
/// `com.nsantulli.econbyte.unlockall` non-consumable ($0.99). Price is read
/// from StoreKit (`product.displayPrice`) — never hardcoded — per DUD-186.
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: PurchaseManager
    @State private var working = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false

    private var product: Product? { store.product(for: .unlockAll) }

    private var lockedTopicCount: Int {
        let topics = ContentStore.shared.topics
        return topics.filter { !ContentStore.shared.isTopicFree($0.id) }.count
    }

    private var canBuy: Bool {
        store.productsReady && !working
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
                            featureRow("infinity", "All current and future card packs")
                            featureRow("icloud.and.arrow.down.fill", "Restores across your devices")
                        }
                        .padding(.horizontal, 28)

                        if store.isUnlockAllPurchased {
                            Text("Already unlocked ✓")
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                .foregroundColor(Econ.sky)
                                .padding(.top, 8)
                        } else {
                            if store.isLoadingProducts {
                                ProgressView("Loading purchase options…")
                                    .tint(Econ.sky)
                                    .foregroundColor(Econ.white.opacity(0.8))
                                    .padding(.top, 8)
                            } else if !store.productsReady {
                                VStack(spacing: 12) {
                                    Text(store.productsLoadError ?? "Purchases are temporarily unavailable.")
                                        .font(.system(size: 14, design: .rounded))
                                        .foregroundColor(Econ.white.opacity(0.7))
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 28)
                                    Button("Try Again") {
                                        Task { await store.loadProducts() }
                                    }
                                    .buttonStyle(SecondaryButton())
                                    .padding(.horizontal, 28)
                                }
                                .padding(.top, 8)
                            }

                            Button {
                                buy()
                            } label: {
                                if working {
                                    ProgressView().tint(Econ.ink)
                                } else {
                                    Text("Unlock All — \(product?.displayPrice ?? "$0.99")")
                                }
                            }
                            .buttonStyle(PrimaryButton())
                            .disabled(!canBuy)
                            .opacity(canBuy ? 1 : 0.55)
                            .padding(.horizontal, 28)
                            .padding(.top, 8)
                            .accessibilityIdentifier("paywallUnlockButton")

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
            .navigationTitle("EconByte Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") { dismiss() }.foregroundColor(Econ.sky)
                }
            }
            .onChange(of: store.isUnlockAllPurchased) { unlocked in
                if unlocked { dismiss() }
            }
            .alert(alertTitle, isPresented: $showAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
        }
        .tint(Econ.sky)
        .task { await store.loadProducts() }
    }

    private func featureRow(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(Econ.amber)
                .frame(width: 24)
            Text(text)
                .font(.system(size: 15, design: .rounded))
                .foregroundColor(Econ.white.opacity(0.9))
            Spacer()
        }
    }

    private func buy() {
        working = true
        Task {
            let result = await store.purchase(.unlockAll)
            working = false
            handlePurchaseResult(result, successTitle: "Unlocked")
        }
    }

    private func restore() {
        working = true
        Task {
            let result = await store.restorePurchases()
            working = false
            handlePurchaseResult(result, successTitle: "Restored")
        }
    }

    private func handlePurchaseResult(_ result: PurchaseManager.PurchaseResult, successTitle: String) {
        switch result {
        case .success:
            if !store.isUnlockAllPurchased {
                presentAlert(title: successTitle, message: "Your purchase is processing. If topics stay locked, tap Restore Purchases.")
            }
        case .cancelled:
            break
        case .pending:
            presentAlert(title: "Purchase Pending", message: "Your purchase needs approval. You'll get access once it's approved.")
        case .productUnavailable:
            presentAlert(
                title: "Purchase Unavailable",
                message: store.productsLoadError ?? "We couldn't reach the App Store. Check your connection and try again."
            )
            Task { await store.loadProducts() }
        case .failed(let message):
            presentAlert(title: "Something Went Wrong", message: message)
        }
    }

    private func presentAlert(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showAlert = true
    }
}
