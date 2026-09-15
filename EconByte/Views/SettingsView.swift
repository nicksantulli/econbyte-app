import SwiftUI
import StoreKit
import UIKit

/// Settings (1.1.4 overhaul, Owner order 2026-09-14: "a substantial overhaul —
/// design, the copy we MUST include … cut it down to what's actually
/// important").
///
/// Opened from the gear in the shared top bar. Grouped and compact, in
/// EconByte's navy/amber, with only: EconByte Pro (status, period end, Manage
/// Subscription, Restore), Purchases (one line each), Notifications (reminder
/// + time), Privacy (analytics, crash reports, the analytics ID with copy and
/// reset — the deletion handle `AppStore/1.1.2/app-privacy-answers.md` §1
/// promises — Privacy Policy, Terms of Use), and About (not-advice line,
/// sources & editorial policy, support, rating, version). Every footer is one
/// short sentence. The Debug section exists only in DEBUG builds.
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
    @State private var alert: PurchaseAlertCopy.Alert?
    @State private var showManageSubscriptions = false
    @State private var analyticsEnabled = false
    @State private var diagnosticsEnabled = false
    /// The anonymous analytics id the transport is actually stamping on events,
    /// read back from `EconTelemetry` rather than minted here. `nil` renders as
    /// "not available" (an unkeyed build sends nothing, so there is no id).
    @State private var analyticsIdentity: String?
    @State private var showSources = false
    @State private var showStudio = false

    static let privacyPolicyURL = URL(string: "https://dudleyapps.com/privacy/")!
    static let supportURL = URL(string: "mailto:support@dudleyapps.com")!

    private var anyWorking: Bool { workingRemoveAds || workingRestore || workingPack != nil }

    var body: some View {
        NavigationStack {
            List {
                proSection
                purchasesSection
                SettingsRemindersSection(
                    notifications: growth.notifications,
                    onWillPrompt: { growth.review.noteNegativeSessionEvent(.notificationPrompt) },
                    onResult: { growth.recordNotificationAuthorizationResult(granted: $0) })
                privacySection
                aboutSection
                #if DEBUG
                debugSection
                #endif
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Econ.ocean.ignoresSafeArea())
            .environment(\.defaultMinListRowHeight, 46)
            .task {
                analyticsEnabled = growth.telemetry.analyticsChoice
                diagnosticsEnabled = growth.diagnostics.diagnosticsChoice
                analyticsIdentity = growth.telemetry.analyticsIdentity
                growth.notifications.refreshAuthorization()
                await store.loadProducts()
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Econ.ocean, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(Econ.sky)
                }
            }
            .purchaseAlert($alert)
            .manageSubscriptions(isPresented: $showManageSubscriptions, store: store)
            .sheet(isPresented: $showSources) { SourcesPolicyView() }
            .sheet(isPresented: $showStudio) { DudleyAboutSheet() }
        }
        .tint(Econ.sky)
    }

    // MARK: - EconByte Pro

    private var proSection: some View {
        Section {
            if store.isProActive, let pro = store.proEntitlement {
                HStack {
                    SettingsRowLabel(title: "EconByte Pro", icon: "graduationcap.fill", tint: Econ.amber)
                    Spacer()
                    // Identifier on the leaf value, not the row: a List row's
                    // container identifier is not reliably exposed to XCUITest.
                    Text(pro.state.hasBillingIssue ? "Payment issue" : "Active ✓")
                        .foregroundColor(pro.state.hasBillingIssue ? Econ.amber : Econ.sky)
                        .accessibilityIdentifier("settingsProStatusRow")
                }
                .settingsRow()
                // Plan, Renews / Ends, a scheduled plan change, Family Sharing.
                ForEach(ProStatusCopy.rows(for: pro).filter { $0.title != "Status" }) { row in
                    SettingsValueRow(title: row.title, value: row.value)
                }
                // Apple's in-app sheet (`showManageSubscriptions`): change plan,
                // cancel, resubscribe — entitlements refresh when it closes.
                Button {
                    showManageSubscriptions = true
                } label: {
                    SettingsRowLabel(title: "Manage Subscription", icon: "creditcard.fill", tint: Econ.tide)
                }
                .settingsRow()
                .accessibilityIdentifier("settingsManageSubscriptionLink")
            } else {
                Button {
                    onRequestProPaywall?()
                    dismiss()
                } label: {
                    HStack {
                        SettingsRowLabel(title: "EconByte Pro", icon: "graduationcap.fill", tint: Econ.amber)
                        Spacer()
                        proPriceAccessory
                    }
                }
                .disabled(anyWorking)
                .settingsRow()
                .accessibilityIdentifier("settingsProButton")
            }
            Button {
                restorePurchases()
            } label: {
                HStack {
                    SettingsRowLabel(title: "Restore Purchases", icon: "arrow.clockwise", tint: Econ.tide)
                    Spacer()
                    if workingRestore { ProgressView() }
                }
            }
            .disabled(anyWorking)
            .settingsRow()
            .accessibilityIdentifier("settingsRestoreButton")
        } header: {
            SettingsHeader(text: "EconByte Pro")
        } footer: {
            SettingsFooter(text: ProStatusCopy.footer(for: store.isProActive ? store.proEntitlement : nil))
        }
    }

    /// The Pro row's trailing text. The row opens the paywall (which has its
    /// own retry), so without a price it says "See plans" — never a dash.
    @ViewBuilder
    private var proPriceAccessory: some View {
        switch store.priceState(for: .proMonthly) {
        case .ready(let monthly):
            Text("from \(monthly)/mo").foregroundColor(Econ.amber)
        case .loading:
            ProgressView()
        case .unavailable:
            Text("See plans").foregroundColor(Econ.subtext)
        }
    }

    // MARK: - Purchases

    private var oneTimeIDs: [PurchaseManager.ProductID] { [.removeAds, .unlockAll] + PurchaseManager.ProductID.packs }

    /// A completed fetch left at least one unowned one-time product unpriced.
    private var someOneTimePriceUnavailable: Bool {
        oneTimeIDs.contains { id in
            !isOwned(id) && store.priceState(for: id) == .unavailable
        }
    }

    private func isOwned(_ id: PurchaseManager.ProductID) -> Bool {
        switch id {
        case .removeAds: return store.isRemoveAdsPurchased
        case .unlockAll: return store.isUnlockAllPurchased
        default: return store.isPackPurchased(productID: id.rawValue)
        }
    }

    /// Deliberately not labelled "Pro": the one-time products are independent
    /// purchases, not a bundle (design section 8, D18, D19).
    private var purchasesSection: some View {
        Section {
            if store.isRemoveAdsPurchased {
                ownedRow("Remove Ads", icon: "rectangle.slash", productID: PurchaseManager.ProductID.removeAds.rawValue)
            } else {
                let state = store.priceState(for: .removeAds)
                let pending = store.isPending(.removeAds)
                Button {
                    purchaseRemoveAds()
                } label: {
                    priceRow("Remove Ads", icon: "rectangle.slash",
                             state: state, working: workingRemoveAds, pending: pending)
                }
                .disabled(pending || !PurchasePresentation.canPurchase(
                    displayPrice: state.displayPrice, isWorking: anyWorking, isLoading: store.isLoadingProducts))
                .settingsRow()
                .accessibilityIdentifier("settingsRemoveAdsButton")
            }

            if store.isUnlockAllPurchased {
                ownedRow("Unlock All Topics", icon: "lock.open.fill", productID: PurchaseManager.ProductID.unlockAll.rawValue)
            } else {
                Button {
                    EBEvents.lockedTopicTapped(entryPoint: .settings)
                    onRequestPaywall?()
                    dismiss()
                } label: {
                    priceRow("Unlock All Topics", icon: "lock.open.fill",
                             state: store.priceState(for: .unlockAll), working: false,
                             pending: store.isPending(.unlockAll))
                }
                .disabled(anyWorking)
                .settingsRow()
                .accessibilityIdentifier("settingsUnlockAllButton")
            }

            // Topic packs (1.1.3) — separate from Unlock All (D18).
            ForEach(ContentStore.shared.packs) { pack in
                packRow(pack)
            }
        } header: {
            SettingsHeader(text: "Purchases")
        } footer: {
            if store.isLoadingProducts && !store.productsReady {
                SettingsFooter(text: "Loading prices from the App Store…")
            } else if store.hasAttemptedProductLoad && !store.isLoadingProducts && someOneTimePriceUnavailable {
                PricesUnavailableNotice(identifier: "settingsPricesUnavailable") {
                    Task { await store.loadProducts() }
                }
            } else {
                SettingsFooter(text: "One-time purchases; packs are separate from Unlock All.")
            }
        }
    }

    private func ownedRow(_ title: String, icon: String, productID: String) -> some View {
        HStack {
            SettingsRowLabel(title: title, icon: icon, tint: Econ.tide)
            Spacer()
            Text(store.familySharedProductIDs.contains(productID) ? "Family Sharing ✓" : "Purchased ✓")
                .foregroundColor(Econ.sky)
        }
        .settingsRow()
    }

    /// Price, "Loading…" spinner, "Unavailable", or "Waiting for approval" —
    /// never a bare placeholder.
    private func priceRow(_ title: String, icon: String,
                          state: PurchasePresentation.PriceState,
                          working: Bool, pending: Bool) -> some View {
        HStack {
            SettingsRowLabel(title: title, icon: icon, tint: Econ.tide)
            Spacer()
            if working {
                ProgressView()
            } else if pending {
                Text(PurchasePresentation.waitingForApprovalText).foregroundColor(Econ.subtext)
            } else {
                switch state {
                case .ready(let price):
                    Text(price).foregroundColor(Econ.amber)
                case .loading:
                    ProgressView()
                        .accessibilityLabel(Text(PurchasePresentation.loadingPriceText))
                case .unavailable:
                    Text(PurchasePresentation.unavailableShortText).foregroundColor(Econ.subtext)
                }
            }
        }
    }

    @ViewBuilder
    private func packRow(_ pack: EconPack) -> some View {
        if store.isPackPurchased(productID: pack.productID) {
            ownedRow(pack.name, icon: pack.icon, productID: pack.productID)
                .accessibilityIdentifier("settingsPack-\(pack.id)-owned")
        } else if let productID = PurchaseManager.ProductID(rawValue: pack.productID) {
            let state = store.priceState(for: productID)
            let pending = store.isPending(productID)
            Button {
                purchasePack(productID)
            } label: {
                priceRow(pack.name, icon: pack.icon, state: state,
                         working: workingPack == productID, pending: pending)
            }
            .disabled(pending || !PurchasePresentation.canPurchase(
                displayPrice: state.displayPrice, isWorking: anyWorking, isLoading: store.isLoadingProducts))
            .settingsRow()
            .accessibilityIdentifier("settingsPack-\(pack.id)-buy")
            .onAppear { EBEvents.packShown(family: productID.family, entryPoint: .settings) }
        }
    }

    // MARK: - Privacy

    private var privacySection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { analyticsEnabled },
                set: { value in
                    analyticsEnabled = value
                    growth.setAnalyticsEnabled(value, entryPoint: .settings)
                    // Read back AFTER the transport has been told, so the row
                    // shows the id the SDK will really send (or nothing).
                    analyticsIdentity = growth.telemetry.analyticsIdentity
                })) {
                SettingsRowLabel(title: "Usage analytics", icon: "chart.bar.fill", tint: Econ.tide)
            }
            .tint(Econ.amber)
            .settingsRow()
            .accessibilityIdentifier("settingsAnalyticsToggle")

            // The deletion handle: only meaningful while analytics is on, so it
            // appears with the opt-in and leaves with it.
            if analyticsEnabled {
                analyticsIdentityRow
            }

            Toggle(isOn: Binding(
                get: { diagnosticsEnabled },
                set: { value in
                    diagnosticsEnabled = value
                    growth.setDiagnosticsEnabled(value, entryPoint: .settings)
                })) {
                SettingsRowLabel(title: "Crash reports", icon: "ant.fill", tint: Econ.tide)
            }
            .tint(Econ.amber)
            .settingsRow()
            .accessibilityIdentifier("settingsDiagnosticsToggle")

            Link(destination: Self.privacyPolicyURL) {
                SettingsRowLabel(title: "Privacy Policy", icon: "hand.raised.fill", tint: Econ.tide)
            }
            .settingsRow()
            .accessibilityIdentifier("settingsPrivacyPolicyButton")

            Link(destination: PurchaseManager.termsOfUseURL) {
                SettingsRowLabel(title: "Terms of Use", icon: "doc.text.fill", tint: Econ.tide)
            }
            .settingsRow()
            .accessibilityIdentifier("settingsTermsOfUseLink")
        } header: {
            SettingsHeader(text: "Privacy")
        } footer: {
            SettingsFooter(text: "Anonymous; quote your Analytics ID to support to delete your data.")
        }
    }

    private var analyticsIdentityRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 14) {
                SettingsIconSpacer()
                Text("Analytics ID")
                    .font(.system(size: 16, design: .rounded))
                    .foregroundColor(Econ.white)
                Spacer(minLength: 8)
                Button {
                    UIPasteboard.general.string = analyticsIdentity ?? ""
                } label: {
                    Image(systemName: "doc.on.doc").foregroundColor(Econ.sky)
                }
                .buttonStyle(.borderless)
                .disabled(analyticsIdentity == nil)
                .accessibilityLabel(Text("Copy analytics ID"))
                .accessibilityIdentifier("analyticsIdentityCopyButton")
                Button("Reset") {
                    growth.resetAnalyticsIdentity()
                    analyticsIdentity = growth.telemetry.analyticsIdentity
                }
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .buttonStyle(.borderless)
                .disabled(analyticsIdentity == nil)
                .accessibilityLabel(Text("Reset analytics ID"))
                .accessibilityIdentifier("analyticsIdentityResetButton")
            }
            HStack(spacing: 14) {
                SettingsIconSpacer()
                // The identifier sits on the VALUE, not the row, so a test can
                // assert what is displayed (a container's id would win).
                Text(analyticsIdentity ?? "not available")
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundColor(Econ.subtext)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("analyticsIdentityRow")
            }
        }
        .padding(.vertical, 4)
        .settingsRow()
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            SettingsRowLabel(title: "Educational content, not financial advice.",
                             icon: "info.circle.fill", tint: Econ.tide)
                .settingsRow()
                .accessibilityIdentifier("settingsEducationalNotice")

            Button { showSources = true } label: {
                HStack {
                    SettingsRowLabel(title: "Sources & editorial policy", icon: "checkmark.shield.fill", tint: Econ.tide)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Econ.subtext)
                        .accessibilityHidden(true)
                }
            }
            .settingsRow()
            .accessibilityIdentifier("settingsSourcesButton")

            Link(destination: Self.supportURL) {
                SettingsRowLabel(title: "Contact support", icon: "envelope.fill", tint: Econ.tide)
            }
            .settingsRow()
            .accessibilityIdentifier("settingsSupportLink")

            Link(destination: ReviewRequestPolicy.reviewURL) {
                SettingsRowLabel(title: "Rate EconByte", icon: "star.fill", tint: Econ.amber)
            }
            .settingsRow()
            .accessibilityIdentifier("settingsRateButton")

            Button { showStudio = true } label: {
                HStack {
                    SettingsRowLabel(title: "Version", icon: "hammer.fill", tint: Econ.tide)
                    Spacer()
                    Text("\(Bundle.main.shortVersion) (\(Bundle.main.buildNumber))")
                        .foregroundColor(Econ.subtext)
                }
            }
            .settingsRow()
            .accessibilityIdentifier("settingsVersionRow")
        } header: {
            SettingsHeader(text: "About")
        } footer: {
            SettingsFooter(text: "Made by Dudley Development.")
        }
    }

    #if DEBUG
    private var debugSection: some View {
        Section {
            Toggle("🧪 Unlock All Topics", isOn: Binding(
                get: { store.isUnlockAllPurchased },
                set: { store.debugSetUnlockAll($0) }))
                .tint(Econ.amber)
                .settingsRow()
            Toggle("🧪 Remove Ads", isOn: Binding(
                get: { store.isRemoveAdsPurchased },
                set: { store.debugSetRemoveAds($0) }))
                .tint(Econ.amber)
                .settingsRow()
            Toggle("🧪 EconByte Pro", isOn: Binding(
                get: { store.isProActive },
                set: { store.debugSetPro($0) }))
                .tint(Econ.amber)
                .settingsRow()
                .accessibilityIdentifier("debugProToggle")
        } header: {
            SettingsHeader(text: "Debug — test only")
        } footer: {
            SettingsFooter(text: "DEBUG builds only; stripped from Release.")
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
            handlePurchaseResult(result, kind: .purchase, accessGranted: store.isRemoveAdsPurchased)
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
            handlePurchaseResult(result, kind: .purchase, accessGranted: store.isPackPurchased(productID: id.rawValue))
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
            handlePurchaseResult(result, kind: .restore, accessGranted: true)
        }
    }

    /// The purchase events themselves are emitted inside `PurchaseManager`,
    /// where the StoreKit id is reduced to its family. What stays here is the
    /// part that is not telemetry — a failed purchase is a bad moment to ask
    /// for a rating.
    private func recordPurchaseTelemetry(_ result: PurchaseManager.PurchaseResult,
                                         productID: PurchaseManager.ProductID) {
        switch result {
        case .success:
            break
        case .cancelled, .pending, .productUnavailable, .nothingToRestore, .failed:
            growth.review.noteNegativeSessionEvent(.purchaseFailure)
        }
    }

    private func handlePurchaseResult(_ result: PurchaseManager.PurchaseResult,
                                      kind: PurchaseAlertCopy.Kind,
                                      accessGranted: Bool) {
        if result == .productUnavailable {
            growth.diagnosticLog.capture(.storeProductsUnavailable)
            Task { await store.loadProducts() }
        }
        guard let next = PurchaseAlertCopy.alert(for: result, kind: kind, accessGranted: accessGranted) else { return }
        // A user-facing error is a bad moment to ask for a rating (rules-v2).
        growth.review.noteNegativeSessionEvent(.errorShown)
        alert = next
    }
}

extension PurchaseManager.PurchaseResult {
    /// Maps a StoreKit outcome onto the closed telemetry `result_class` enum.
    var econResultClass: EconResultClass {
        switch self {
        case .success: return .success
        case .cancelled: return .cancelled
        case .pending: return .pending
        case .productUnavailable, .nothingToRestore: return .unavailable
        case .failed: return .provider
        }
    }
}

// MARK: - Notifications section

/// Observes the coordinator directly so the toggle and the time picker update
/// the moment the system dialog resolves.
struct SettingsRemindersSection: View {
    @ObservedObject var notifications: NotificationCoordinator
    let onWillPrompt: () -> Void
    let onResult: (Bool) -> Void

    private var denied: Bool { notifications.authorization == .denied }

    var body: some View {
        Section {
            Toggle(isOn: Binding(
                get: { notifications.remindersEnabled },
                set: { setEnabled($0) })) {
                SettingsRowLabel(title: "Daily reminder", icon: "bell.fill", tint: Color(hex: "D9534F"))
            }
            .tint(Econ.amber)
            .disabled(denied && !notifications.remindersEnabled)
            .settingsRow()
            .accessibilityIdentifier("settingsRemindersToggle")

            if notifications.remindersEnabled {
                DatePicker(selection: timeBinding, displayedComponents: .hourAndMinute) {
                    HStack(spacing: 14) {
                        SettingsIconSpacer()
                        Text("Time").font(.system(size: 16, design: .rounded)).foregroundColor(Econ.white)
                    }
                }
                .settingsRow()
                .accessibilityIdentifier("settingsReminderTimePicker")
            } else if denied {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    SettingsRowLabel(title: "Allow in iOS Settings", icon: "gearshape.fill", tint: Econ.tide)
                }
                .settingsRow()
                .accessibilityIdentifier("settingsOpenSystemSettingsButton")
            }
        } header: {
            SettingsHeader(text: "Notifications")
        } footer: {
            SettingsFooter(text: denied && !notifications.remindersEnabled
                           ? "Notifications are off for EconByte in iOS Settings."
                           : "One quiet nudge a day; nothing else.")
        }
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: notifications.reminderHour,
                                      minute: notifications.reminderMinute,
                                      second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                notifications.setReminderTime(hour: parts.hour ?? NotificationPolicy.reminderHour,
                                              minute: parts.minute ?? NotificationPolicy.reminderMinute)
            })
    }

    private func setEnabled(_ enabled: Bool) {
        guard enabled else {
            // Turning reminders off resolves no system dialog, so it emits no
            // `notification_permission_result`.
            notifications.disableReminders()
            return
        }
        onWillPrompt()
        notifications.enableReminders { granted in onResult(granted) }
    }
}

// MARK: - Sources & editorial policy

struct SourcesPolicyView: View {
    @Environment(\.dismiss) private var dismiss

    private let sections: [(String, String)] = [
        ("Cards and packs",
         "Every card names the primary or official source it is built on — agencies such as the Bureau of Labor Statistics, the Bureau of Economic Analysis and the Federal Reserve — and shows it on the card."),
        ("The Daily Brief",
         "Built only from official public releases on a fixed list of official statistics agencies, central banks and international organizations, never from news articles. Every figure links to its release and says when it was read."),
        ("Courses",
         "Charts that illustrate a concept use synthetic data and say so. Quizzes check the lesson, not the market."),
        ("Not advice",
         "EconByte is educational. Nothing in it is investment, tax or financial advice, and nothing in it predicts prices."),
        ("Corrections",
         "Spot something wrong? Email support@dudleyapps.com and we will check it against the source."),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Econ.ocean.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(sections, id: \.0) { title, body in
                            VStack(alignment: .leading, spacing: 6) {
                                EconSectionLabel(text: title)
                                Text(body)
                                    .font(.system(size: 15, design: .rounded))
                                    .foregroundColor(Econ.white.opacity(0.9))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Sources & editorial policy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Econ.ocean, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }.foregroundColor(Econ.sky)
                }
            }
        }
        .tint(Econ.sky)
        .accessibilityIdentifier("sourcesPolicyView")
    }
}

// MARK: - Row styling

struct SettingsRowLabel: View {
    let title: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(tint == Econ.amber ? Econ.ink : Econ.white)
                .frame(width: 28, height: 28)
                .background(tint)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 16, design: .rounded))
                .foregroundColor(Econ.white)
        }
    }
}

/// Keeps text rows without an icon aligned with the ones that have one.
struct SettingsIconSpacer: View {
    var body: some View { Color.clear.frame(width: 28, height: 1).accessibilityHidden(true) }
}

struct SettingsValueRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 14) {
            SettingsIconSpacer()
            Text(title).font(.system(size: 16, design: .rounded)).foregroundColor(Econ.white)
            Spacer()
            Text(value).font(.system(size: 16, design: .rounded)).foregroundColor(Econ.subtext)
        }
        .accessibilityElement(children: .combine)
        .settingsRow()
    }
}

struct SettingsHeader: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundColor(Econ.subtext)
            .tracking(1.2)
    }
}

struct SettingsFooter: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 12, design: .rounded))
            .foregroundColor(Econ.subtext)
    }
}

extension View {
    func settingsRow() -> some View {
        listRowBackground(Econ.tide.opacity(0.18))
    }
}
