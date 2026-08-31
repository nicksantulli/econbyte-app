import SwiftUI
import StoreKit

struct SettingsView: View {
    /// Called when the user taps Unlock All; Settings dismisses first so the
    /// paywall is not a nested sheet (nested sheets break StoreKit on iPad).
    var onRequestPaywall: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var streak: StreakManager
    @EnvironmentObject private var store: PurchaseManager
    @EnvironmentObject private var growth: EconGrowth

    @State private var workingRemoveAds = false
    @State private var workingRestore = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var analyticsEnabled = false
    @State private var diagnosticsEnabled = false

    private var removeAdsProduct: Product? { store.product(for: .removeAds) }
    private var unlockAllProduct: Product? { store.product(for: .unlockAll) }
    private var anyWorking: Bool { workingRemoveAds || workingRestore }

    var body: some View {
        NavigationStack {
            ZStack {
                Econ.ocean.ignoresSafeArea()
                List {
                    remindersSection
                    purchasesSection
                    privacySection
                    #if DEBUG
                    debugSection
                    #endif
                    aboutSection
                }
                .scrollContentBackground(.hidden)
                .foregroundColor(Econ.white)
            }
            .task {
                analyticsEnabled = growth.telemetry.isEnabled
                diagnosticsEnabled = growth.diagnostics.isEnabled
                growth.notifications.refreshAuthorization()
                await store.loadProducts()
            }
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

    // MARK: - Reminders

    private var remindersSection: some View {
        Section {
            Toggle("Daily Learning Reminder", isOn: Binding(
                get: { growth.notifications.remindersEnabled },
                set: { setRemindersEnabled($0) }))
                .tint(Econ.amber)
                .accessibilityIdentifier("settingsRemindersToggle")
                .disabled(growth.notifications.authorization == .denied
                          && !growth.notifications.remindersEnabled)
        } header: {
            Text("Notifications")
        } footer: {
            if growth.notifications.authorization == .denied {
                Text("Notifications are turned off for EconByte in iOS Settings. Enable them there to use reminders.")
            } else {
                Text("One reminder a day at 7:00 p.m. that today's cards are waiting. Turning this off removes it immediately.")
            }
        }
    }

    private func setRemindersEnabled(_ enabled: Bool) {
        if enabled {
            growth.review.noteNegativeSessionEvent(.notificationPrompt)
            growth.notifications.enableReminders()
        } else {
            growth.notifications.disableReminders()
        }
        growth.telemetry.capture(.notificationPermissionResult, properties: [
            "result_class": .token(enabled ? EconResultClass.success.rawValue
                                           : EconResultClass.cancelled.rawValue),
        ])
    }

    // MARK: - Purchases

    /// Deliberately not labelled "Pro": the two products are independent
    /// one-time purchases, not a bundle (design section 8).
    private var purchasesSection: some View {
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
                    growth.telemetry.capture(.lockedTopicTapped, properties: [
                        "topic_id": .token("all"),
                        "entry_point": .token(EconEntryPoint.settings.rawValue),
                    ])
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

            Button("Restore Purchases") { restorePurchases() }
                .disabled(anyWorking)
                .accessibilityIdentifier("settingsRestoreButton")
        } header: {
            Text("Purchases")
        } footer: {
            if store.isLoadingProducts {
                Text("Loading purchase options from the App Store…")
            } else if let error = store.productsLoadError, !store.productsReady {
                Text(error)
            } else {
                Text("Two separate one-time purchases: Remove Ads does not unlock topics, and Unlock All Topics does not remove ads. Restore re-syncs both.")
            }
        }
    }

    // MARK: - Privacy and data (design section 10.1)

    private var privacySection: some View {
        Section {
            Toggle("Share Usage Analytics", isOn: Binding(
                get: { analyticsEnabled },
                set: { value in
                    analyticsEnabled = value
                    growth.setAnalyticsEnabled(value, entryPoint: .settings)
                }))
                .tint(Econ.amber)
                .accessibilityIdentifier("settingsAnalyticsToggle")

            Toggle("Share Crash Diagnostics", isOn: Binding(
                get: { diagnosticsEnabled },
                set: { value in
                    diagnosticsEnabled = value
                    growth.setDiagnosticsEnabled(value, entryPoint: .settings)
                }))
                .tint(Econ.amber)
                .accessibilityIdentifier("settingsDiagnosticsToggle")

            Link("Privacy Policy", destination: URL(string: "https://dudleyapps.com/privacy/")!)
                .accessibilityIdentifier("settingsPrivacyPolicyButton")
        } header: {
            Text("Privacy & Data")
        } footer: {
            Text("Both are off unless you turn them on, and they are separate choices. Neither affects your cards, streak, bookmarks, purchases, or ads. What you read or save is never shared.")
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            Link("Rate EconByte", destination: ReviewRequestPolicy.reviewURL)
                .accessibilityIdentifier("settingsRateButton")
            DudleyAboutRow()
        } header: {
            Text("About")
        }
    }

    #if DEBUG
    private var debugSection: some View {
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
    }
    #endif

    // MARK: - Purchase plumbing

    private func purchaseRemoveAds() {
        workingRemoveAds = true
        growth.monetization.setBlocker(.purchase, active: true)
        growth.telemetry.capture(.purchaseStarted, properties: [
            "product_id": .token(PurchaseManager.ProductID.removeAds.rawValue),
            "entry_point": .token(EconEntryPoint.settings.rawValue),
        ])
        Task {
            let result = await store.purchase(.removeAds)
            workingRemoveAds = false
            growth.monetization.setBlocker(.purchase, active: false)
            growth.syncEntitlements(from: store)
            recordPurchaseTelemetry(result, productID: .removeAds)
            handlePurchaseResult(result, purchased: store.isRemoveAdsPurchased)
        }
    }

    private func restorePurchases() {
        workingRestore = true
        growth.monetization.setBlocker(.restore, active: true)
        growth.telemetry.capture(.restoreStarted,
                                 properties: ["entry_point": .token(EconEntryPoint.settings.rawValue)])
        Task {
            let result = await store.restorePurchases()
            workingRestore = false
            growth.monetization.setBlocker(.restore, active: false)
            growth.syncEntitlements(from: store)
            if case .failed = result {
                growth.review.noteNegativeSessionEvent(.restoreFailure)
                growth.diagnostics.capture(.restoreFailed)
                growth.telemetry.capture(.restoreFailed,
                                         properties: ["result_class": .token(EconResultClass.unavailable.rawValue)])
            } else {
                let restored = (store.isUnlockAllPurchased ? 1 : 0) + (store.isRemoveAdsPurchased ? 1 : 0)
                growth.telemetry.capture(.restoreCompleted,
                                         properties: ["restored_product_count": .int(restored)])
            }
            handlePurchaseResult(result, purchased: store.isUnlockAllPurchased || store.isRemoveAdsPurchased)
        }
    }

    private func recordPurchaseTelemetry(_ result: PurchaseManager.PurchaseResult,
                                         productID: PurchaseManager.ProductID) {
        switch result {
        case .success:
            growth.telemetry.capture(.purchaseCompleted, properties: [
                "product_id": .token(productID.rawValue),
                "entry_point": .token(EconEntryPoint.settings.rawValue),
            ])
        case .cancelled, .pending, .productUnavailable, .failed:
            growth.review.noteNegativeSessionEvent(.purchaseFailure)
            growth.telemetry.capture(.purchaseFailed, properties: [
                "product_id": .token(productID.rawValue),
                "result_class": .token(result.econResultClass.rawValue),
            ])
        }
    }

    private func handlePurchaseResult(_ result: PurchaseManager.PurchaseResult, purchased: Bool) {
        switch result {
        case .success:
            if !purchased {
                presentAlert(title: "Restore Complete",
                             message: "No previous purchases were found for this Apple ID.")
            }
        case .cancelled:
            break
        case .pending:
            presentAlert(title: "Purchase Pending",
                         message: "Your purchase needs approval. You'll get access once it's approved.")
        case .productUnavailable:
            presentAlert(
                title: "Purchase Unavailable",
                message: store.productsLoadError ?? "We couldn't reach the App Store. Check your connection and try again."
            )
            growth.diagnostics.capture(.storeProductsUnavailable)
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

extension PurchaseManager.PurchaseResult {
    /// Maps a StoreKit outcome onto the closed telemetry `result_class` enum.
    var econResultClass: EconResultClass {
        switch self {
        case .success: return .success
        case .cancelled: return .cancelled
        case .pending: return .pending
        case .productUnavailable: return .unavailable
        case .failed: return .provider
        }
    }
}
