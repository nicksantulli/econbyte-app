import SwiftUI
import StoreKit

struct SettingsView: View {
    /// Called when the user taps Unlock All; Settings dismisses first so the
    /// paywall is not a nested sheet (nested sheets break StoreKit on iPad).
    var onRequestPaywall: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @AppStorage("notificationsEnabled") private var notificationsEnabled = false
    @EnvironmentObject private var streak: StreakManager
    @EnvironmentObject private var store: PurchaseManager
    @State private var workingRemoveAds = false
    @State private var workingRestore = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false

    private var removeAdsProduct: Product? { store.product(for: .removeAds) }
    private var unlockAllProduct: Product? { store.product(for: .unlockAll) }
    private var anyWorking: Bool { workingRemoveAds || workingRestore }

    var body: some View {
        NavigationStack {
            ZStack {
                Econ.ocean.ignoresSafeArea()
                List {
                    Section {
                        Toggle("Daily Streak Reminder", isOn: $notificationsEnabled)
                            .onChange(of: notificationsEnabled) { val in
                                if val { streak.requestNotificationPermission() }
                            }
                            .tint(Econ.amber)
                    } header: {
                        Text("Notifications")
                    }
                    Section {
                        if store.isRemoveAdsPurchased {
                            HStack {
                                Text("Remove Ads")
                                Spacer()
                                Text("Purchased ✓").foregroundColor(Econ.sky)
                            }
                        } else {
                            Button {
                                purchaseRemoveAds()
                            } label: {
                                HStack {
                                    Text("Remove Ads")
                                    Spacer()
                                    if workingRemoveAds {
                                        ProgressView()
                                    } else {
                                        Text(removeAdsProduct?.displayPrice ?? "$0.99")
                                            .foregroundColor(Econ.amber)
                                    }
                                }
                            }
                            .disabled(anyWorking || store.isLoadingProducts)
                            .accessibilityIdentifier("settingsRemoveAdsButton")
                        }
                        if !store.isUnlockAllPurchased {
                            Button {
                                onRequestPaywall?()
                                dismiss()
                            } label: {
                                HStack {
                                    Text("Unlock All Topics")
                                    Spacer()
                                    Text(unlockAllProduct?.displayPrice ?? "$0.99")
                                        .foregroundColor(Econ.amber)
                                }
                            }
                            .disabled(anyWorking)
                            .accessibilityIdentifier("settingsUnlockAllButton")
                        } else {
                            HStack {
                                Text("Unlock All Topics")
                                Spacer()
                                Text("Purchased ✓").foregroundColor(Econ.sky)
                            }
                        }
                        Button("Restore Purchases") {
                            restorePurchases()
                        }
                        .disabled(anyWorking)
                        .accessibilityIdentifier("settingsRestoreButton")
                    } header: {
                        Text("EconByte Pro")
                    } footer: {
                        if store.isLoadingProducts {
                            Text("Loading purchase options from the App Store…")
                        } else if let error = store.productsLoadError, !store.productsReady {
                            Text(error)
                        } else {
                            Text("One-time purchases. Restore re-syncs anything you've bought with your Apple ID across devices.")
                        }
                    }
                    #if DEBUG
                    Section {
                        Toggle("🧪 Unlock All Topics", isOn: Binding(
                            get: { store.isUnlockAllPurchased },
                            set: { store.debugSetUnlockAll($0) }))
                            .tint(Econ.amber)
                        Toggle("🧪 Remove Ads", isOn: Binding(
                            get: { store.isRemoveAdsPurchased },
                            set: { store.debugSetRemoveAds($0) }))
                            .tint(Econ.amber)
                    } header: {
                        Text("Debug — test only")
                    } footer: {
                        Text("DEBUG builds only. Flips entitlements without a real purchase so you can test locked vs unlocked in the Simulator. Stripped from release builds.")
                    }
                    #endif
                    Section {
                        Link("Rate EconByte", destination: URL(string: "https://dudleyapps.com")!)
                        Link("Privacy Policy", destination: URL(string: "https://dudleyapps.com/privacy/")!)
                        DudleyAboutRow()
                    } header: {
                        Text("About")
                    }
                }
                .scrollContentBackground(.hidden)
                .foregroundColor(Econ.white)
            }
            .task { await store.loadProducts() }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(Econ.sky)
                }
            }
            .alert(alertTitle, isPresented: $showAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
        }
        .tint(Econ.sky)
    }

    private func purchaseRemoveAds() {
        workingRemoveAds = true
        Task {
            let result = await store.purchase(.removeAds)
            workingRemoveAds = false
            handlePurchaseResult(result, purchased: store.isRemoveAdsPurchased)
        }
    }

    private func restorePurchases() {
        workingRestore = true
        Task {
            let result = await store.restorePurchases()
            workingRestore = false
            handlePurchaseResult(result, purchased: store.isUnlockAllPurchased || store.isRemoveAdsPurchased)
        }
    }

    private func handlePurchaseResult(_ result: PurchaseManager.PurchaseResult, purchased: Bool) {
        switch result {
        case .success:
            if !purchased {
                presentAlert(title: "Restore Complete", message: "No previous purchases were found for this Apple ID.")
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
