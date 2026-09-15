import SwiftUI
import StoreKit
import UIKit

struct SettingsView: View {
    /// Called when the user taps Unlock All; Settings dismisses first so the
    /// paywall is not a nested sheet (nested sheets break StoreKit on iPad).
    var onRequestPaywall: (() -> Void)? = nil
    /// Same pattern for the EconByte Pro paywall (1.1.4).
    var onRequestProPaywall: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var streak: StreakManager
    @EnvironmentObject private var store: PurchaseManager
    @EnvironmentObject private var growth: EconGrowth

    @State private var workingRemoveAds = false
    @State private var workingRestore = false
    @State private var workingPack: PurchaseManager.ProductID?
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var analyticsEnabled = false
    @State private var diagnosticsEnabled = false
    /// The anonymous analytics id the transport is actually stamping on events,
    /// read back from `EconTelemetry` rather than minted here. Refreshed on
    /// appear and whenever the consent switch moves, so the row can never show
    /// an id the SDK is not using. `nil` renders as "not available".
    @State private var analyticsIdentity: String?

    private var removeAdsProduct: Product? { store.product(for: .removeAds) }
    private var unlockAllProduct: Product? { store.product(for: .unlockAll) }
    private var anyWorking: Bool { workingRemoveAds || workingRestore || workingPack != nil }

    var body: some View {
        NavigationStack {
            ZStack {
                Econ.ocean.ignoresSafeArea()
                List {
                    remindersSection
                    proSection
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
                analyticsEnabled = growth.telemetry.isAnalyticsEnabled
                diagnosticsEnabled = growth.diagnostics.isDiagnosticsEnabled
                analyticsIdentity = growth.telemetry.analyticsIdentity
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
        guard enabled else {
            // Turning reminders off does not resolve a system authorization, so
            // it emits no `notification_permission_result`.
            growth.notifications.disableReminders()
            return
        }
        growth.review.noteNegativeSessionEvent(.notificationPrompt)
        growth.notifications.enableReminders { granted in
            growth.recordNotificationAuthorizationResult(granted: granted)
        }
    }

    // MARK: - EconByte Pro (1.1.4)

    /// Subscription status and the standard Manage link; or the way in. The
    /// one-time purchases below stay their own section (D4/D18/D19).
    private var proSection: some View {
        Section {
            if store.isProActive {
                HStack {
                    Text("EconByte Pro")
                    Spacer()
                    Text("Active ✓").foregroundColor(Econ.sky)
                }
                .accessibilityIdentifier("settingsProStatusRow")
                if let plan = store.proProductID {
                    HStack {
                        Text("Plan")
                        Spacer()
                        Text(plan == PurchaseManager.ProductID.proAnnual.rawValue ? "Yearly" : "Monthly")
                            .foregroundColor(Econ.subtext)
                    }
                }
                if let expiration = store.proExpiration {
                    HStack {
                        Text("Current period ends")
                        Spacer()
                        Text(expiration.formatted(date: .abbreviated, time: .omitted))
                            .foregroundColor(Econ.subtext)
                    }
                }
                Link("Manage Subscription", destination: PurchaseManager.manageSubscriptionsURL)
                    .accessibilityIdentifier("settingsManageSubscriptionLink")
            } else {
                Button {
                    onRequestProPaywall?()
                    dismiss()
                } label: {
                    HStack {
                        Text("EconByte Pro")
                        Spacer()
                        if let monthly = store.product(for: .proMonthly)?.displayPrice {
                            Text("from \(monthly) / month").foregroundColor(Econ.amber)
                        } else {
                            Text(PurchasePresentation.unavailablePrice).foregroundColor(Econ.amber)
                        }
                    }
                }
                .disabled(anyWorking)
                .accessibilityIdentifier("settingsProButton")
            }
            Link("Terms of Use", destination: PurchaseManager.termsOfUseURL)
                .accessibilityIdentifier("settingsTermsOfUseLink")
        } header: {
            Text("EconByte Pro")
        } footer: {
            Text(store.isProActive
                 ? "While Pro is active you have the courses, the Daily Brief, every topic pack and every core topic, and no ads. Cancel any time from Manage Subscription; access continues to the end of the paid period. Packs you bought separately stay yours."
                 : "A subscription with the three courses, the Daily Brief, every topic pack and core topic, and no ads. Renews automatically until cancelled. The first lesson of each course and the first item of each brief are free.")
        }
    }

    // MARK: - Purchases

    /// Deliberately not labelled "Pro": the one-time products are independent
    /// purchases, not a bundle (design section 8). Pro is its own section.
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
                            Text(PurchasePresentation.priceText(removeAdsProduct?.displayPrice))
                                .foregroundColor(Econ.amber)
                        }
                    }
                }
                .disabled(anyWorking || store.isLoadingProducts)
                .accessibilityIdentifier("settingsRemoveAdsButton")
            }

            if !store.isUnlockAllPurchased {
                Button {
                    EBEvents.lockedTopicTapped(entryPoint: .settings)
                    onRequestPaywall?()
                    dismiss()
                } label: {
                    HStack {
                        Text("Unlock All Topics")
                        Spacer()
                        Text(PurchasePresentation.priceText(unlockAllProduct?.displayPrice))
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

            // Topic packs (1.1.3) — separate from Unlock All (D18).
            ForEach(ContentStore.shared.packs) { pack in
                packRow(pack)
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
                Text("Separate one-time purchases: Remove Ads does not unlock topics; Unlock All Topics opens every core topic and does not include the topic packs; each pack is its own unlock and stays yours whether or not you subscribe to Pro. Restore re-syncs all of them.")
            }
        }
    }

    @ViewBuilder
    private func packRow(_ pack: EconPack) -> some View {
        if store.isPackPurchased(productID: pack.productID) {
            HStack {
                Text(pack.name)
                Spacer()
                Text("Purchased ✓").foregroundColor(Econ.sky)
            }
            .accessibilityIdentifier("settingsPack-\(pack.id)-owned")
        } else if let productID = PurchaseManager.ProductID(rawValue: pack.productID) {
            let price = store.product(for: productID)?.displayPrice
            Button {
                purchasePack(productID)
            } label: {
                HStack {
                    Text(pack.name)
                    Spacer()
                    if workingPack == productID {
                        ProgressView()
                    } else {
                        Text(PurchasePresentation.priceText(price))
                            .foregroundColor(Econ.amber)
                    }
                }
            }
            .disabled(anyWorking || !PurchasePresentation.canPurchase(
                displayPrice: price, isWorking: anyWorking, isLoading: store.isLoadingProducts))
            .accessibilityIdentifier("settingsPack-\(pack.id)-buy")
            .onAppear { EBEvents.packShown(family: productID.family, entryPoint: .settings) }
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
                    // Read back AFTER the transport has been told, so the row
                    // shows the id the SDK will really send (or nothing at all
                    // once consent is withdrawn).
                    analyticsIdentity = growth.telemetry.analyticsIdentity
                }))
                .tint(Econ.amber)
                .accessibilityIdentifier("settingsAnalyticsToggle")

            // The deletion handle. `AppStore/1.1.2/app-privacy-answers.md` §1
            // tells App Review that the analytics identifier "is shown to the
            // user in Settings so they can quote it in a deletion request" —
            // this row is that promise. It is only meaningful while analytics
            // is on, so it appears with the opt-in and leaves with it.
            if analyticsEnabled {
                HStack(alignment: .firstTextBaseline) {
                    Text("Analytics ID")
                        .foregroundColor(Econ.white)
                    Spacer(minLength: 12)
                    // The identifier sits on the VALUE, not on the enclosing
                    // HStack: SwiftUI propagates a container's identifier down
                    // onto its children and it wins over theirs, so an id on the
                    // stack would make every element in the row answer to the
                    // same name and no test could assert what is displayed.
                    Text(analyticsIdentity ?? "not available")
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundColor(Econ.subtext)
                        .multilineTextAlignment(.trailing)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("analyticsIdentityRow")
                    Button {
                        UIPasteboard.general.string = analyticsIdentity ?? ""
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .foregroundColor(Econ.sky)
                    }
                    .buttonStyle(.borderless)
                    .disabled(analyticsIdentity == nil)
                    .accessibilityLabel(Text("Copy analytics ID"))
                    .accessibilityIdentifier("analyticsIdentityCopyButton")
                }
            }

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
            Text("Both are off unless you turn them on, and they are separate choices. Neither affects your cards, streak, bookmarks, purchases, or ads. What you read or save is never shared. While usage analytics is on, the anonymous ID above is the only handle we have on your data — quote it to support to have it deleted.")
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
            Toggle("🧪 EconByte Pro", isOn: Binding(
                get: { store.isProActive },
                set: { store.debugSetPro($0) }))
                .tint(Econ.amber)
                .accessibilityIdentifier("debugProToggle")
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
        growth.review.noteNegativeSessionEvent(.purchase)
        Task {
            let result = await store.purchase(.removeAds, from: .settings)
            workingRemoveAds = false
            growth.monetization.setBlocker(.purchase, active: false)
            growth.syncEntitlements(from: store)
            recordPurchaseTelemetry(result, productID: .removeAds)
            handlePurchaseResult(result, purchased: store.isRemoveAdsPurchased)
        }
    }

    private func purchasePack(_ id: PurchaseManager.ProductID) {
        guard id.isPack else { return }
        workingPack = id
        growth.monetization.setBlocker(.purchase, active: true)
        growth.review.noteNegativeSessionEvent(.purchase)
        Task {
            let result = await store.purchase(id, from: .settings)
            workingPack = nil
            growth.monetization.setBlocker(.purchase, active: false)
            growth.syncEntitlements(from: store)
            recordPurchaseTelemetry(result, productID: id)
            handlePurchaseResult(result, purchased: store.isPackPurchased(productID: id.rawValue))
        }
    }

    private func restorePurchases() {
        workingRestore = true
        growth.monetization.setBlocker(.restore, active: true)
        growth.review.noteNegativeSessionEvent(.restore)
        Task {
            let result = await store.restorePurchases(from: .settings)
            workingRestore = false
            growth.monetization.setBlocker(.restore, active: false)
            growth.syncEntitlements(from: store)
            if case .failed = result {
                growth.review.noteNegativeSessionEvent(.restoreFailure)
                growth.diagnosticLog.capture(.restoreFailed)
            }
            handlePurchaseResult(result, purchased: store.isUnlockAllPurchased || store.isRemoveAdsPurchased
                                     || !store.ownedPackProductIDs.isEmpty)
        }
    }

    /// RECONCILED (1.1.2): the purchase events themselves are emitted inside
    /// `PurchaseManager`, where the StoreKit id is reduced to its family before
    /// anything leaves. What stays here is the part that is not telemetry — a
    /// failed purchase is a bad moment to ask for a rating.
    private func recordPurchaseTelemetry(_ result: PurchaseManager.PurchaseResult,
                                         productID: PurchaseManager.ProductID) {
        switch result {
        case .success:
            break
        case .cancelled, .pending, .productUnavailable, .failed:
            growth.review.noteNegativeSessionEvent(.purchaseFailure)
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
            growth.diagnosticLog.capture(.storeProductsUnavailable)
            Task { await store.loadProducts() }
        case .failed(let message):
            presentAlert(title: "Something Went Wrong", message: message)
        }
    }

    private func presentAlert(title: String, message: String) {
        // A user-facing error is a bad moment to ask for a rating (rules-v2).
        growth.review.noteNegativeSessionEvent(.errorShown)
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
