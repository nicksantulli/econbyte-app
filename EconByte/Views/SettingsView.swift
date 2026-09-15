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
/// sources & editorial policy, support, rating, version). A footer appears only
/// where it says something necessary. The Debug section exists only in DEBUG builds.
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

    @State private var workingRestore = false
    /// The one-time product whose purchase is in flight.
    @State private var workingProduct: PurchaseManager.ProductID?
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

    private var anyWorking: Bool { workingRestore || workingProduct != nil }

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
            .background(EconColor.background.ignoresSafeArea())
            .environment(\.defaultMinListRowHeight, EconSize.tapTarget)
            .task {
                analyticsEnabled = growth.telemetry.analyticsChoice
                diagnosticsEnabled = growth.diagnostics.diagnosticsChoice
                analyticsIdentity = growth.telemetry.analyticsIdentity
                growth.notifications.refreshAuthorization()
                await store.loadProducts()
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(EconColor.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(EconType.headline)
                        .foregroundColor(EconColor.interactive)
                }
            }
            .purchaseAlert($alert)
            .manageSubscriptions(isPresented: $showManageSubscriptions, store: store)
            .sheet(isPresented: $showSources) { SourcesPolicyView() }
            .sheet(isPresented: $showStudio) { DudleyAboutSheet() }
        }
        .tint(EconColor.interactive)
    }

    // MARK: - EconByte Pro

    private var proSection: some View {
        Section {
            if store.isProActive, let pro = store.proEntitlement {
                HStack {
                    SettingsRowLabel(title: "EconByte Pro", icon: "graduationcap.fill", tint: EconColor.accent)
                    Spacer()
                    // Identifier on the leaf value, not the row: a List row's
                    // container identifier is not reliably exposed to XCUITest.
                    Text(pro.state.hasBillingIssue ? "Payment issue" : "Active ✓")
                        .font(EconType.body)
                        .foregroundColor(pro.state.hasBillingIssue ? EconColor.accentText : EconColor.interactive)
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
                        SettingsRowLabel(title: "EconByte Pro", icon: "graduationcap.fill", tint: EconColor.accent)
                        Spacer()
                        Text("See plans")
                            .font(EconType.body)
                            .foregroundColor(EconColor.accentText)
                        Image(systemName: "chevron.right")
                            .font(EconType.footnote.weight(.semibold))
                            .foregroundColor(EconColor.textTertiary)
                            .accessibilityHidden(true)
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

    // MARK: - Purchases

    /// The one-time products, each an `OfferCard` with the shared
    /// `PurchaseButton` (1.1.4). Individual packs are sold on Browse; the
    /// bundle covers all of them here. Restore is in the section above.
    private var purchasesSection: some View {
        Section {
            purchaseCard(.removeAds, icon: "rectangle.slash", title: "Remove Ads", action: "Remove ads",
                         owned: store.isRemoveAdsPurchased, identifier: "settingsRemoveAdsButton")
            purchaseCard(.unlockAll, icon: "lock.open.fill", title: "Unlock All Topics", action: "Unlock",
                         owned: store.isUnlockAllPurchased, identifier: "settingsUnlockAllButton")
            purchaseCard(.packBundle, icon: "square.stack.3d.up.fill", title: "All Packs Bundle", action: "Unlock",
                         owned: store.isPackBundlePurchased, identifier: "settingsPackBundleButton")
        } header: {
            SettingsHeader(text: "Purchases")
        } footer: {
            SettingsFooter(text: "Single packs are in Browse.")
        }
    }

    private func purchaseCard(_ id: PurchaseManager.ProductID, icon: String, title: String, action: String,
                              owned: Bool, identifier: String) -> some View {
        let ownedLabel = owned ? (store.familySharedProductIDs.contains(id.rawValue) ? "Family Sharing" : "Owned") : nil
        let model = PurchaseButtonModel.make(action: action,
                                             price: store.priceState(for: id),
                                             ownedLabel: ownedLabel,
                                             pending: store.isPending(id),
                                             working: workingProduct == id,
                                             isLoadingProducts: store.isLoadingProducts || (anyWorking && workingProduct != id))
        return OfferCard(icon: icon, title: title, highlighted: !owned, identifier: "\(identifier)Card",
                         button: PurchaseButton(model: model, identifier: identifier,
                                                unavailableIdentifier: "\(identifier)PricesUnavailable",
                                                onRetry: { Task { await store.loadProducts() } },
                                                action: { purchase(id) }))
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: EconSpace.xxs, leading: 0, bottom: EconSpace.xxs, trailing: 0))
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
            .tint(EconColor.accent)
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
            .tint(EconColor.accent)
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
        VStack(alignment: .leading, spacing: EconSpace.xxs) {
            HStack(spacing: EconSpace.s) {
                SettingsIconSpacer()
                Text("Analytics ID")
                    .font(EconType.body)
                    .foregroundColor(EconColor.textPrimary)
                Spacer(minLength: EconSpace.xs)
                EconIconButton(systemImage: "doc.on.doc", label: "Copy analytics ID") {
                    UIPasteboard.general.string = analyticsIdentity ?? ""
                }
                .buttonStyle(.borderless)
                .disabled(analyticsIdentity == nil)
                .accessibilityLabel(Text("Copy analytics ID"))
                .accessibilityIdentifier("analyticsIdentityCopyButton")
                Button("Reset") {
                    growth.resetAnalyticsIdentity()
                    analyticsIdentity = growth.telemetry.analyticsIdentity
                }
                .font(EconType.subheadlineEmphasis)
                .frame(minHeight: EconSize.tapTarget)
                .buttonStyle(.borderless)
                .disabled(analyticsIdentity == nil)
                .accessibilityLabel(Text("Reset analytics ID"))
                .accessibilityIdentifier("analyticsIdentityResetButton")
            }
            HStack(spacing: EconSpace.s) {
                SettingsIconSpacer()
                // The identifier sits on the VALUE, not the row, so a test can
                // assert what is displayed (a container's id would win).
                Text(analyticsIdentity ?? "not available")
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundColor(EconColor.textTertiary)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("analyticsIdentityRow")
            }
        }
        .padding(.vertical, EconSpace.xxs)
        .settingsRow()
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            Button { showSources = true } label: {
                HStack {
                    SettingsRowLabel(title: "Sources & editorial policy", icon: "checkmark.shield.fill", tint: Econ.tide)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(EconType.footnote.weight(.semibold))
                        .foregroundColor(EconColor.textTertiary)
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
                SettingsRowLabel(title: "Rate EconByte", icon: "star.fill", tint: EconColor.accent)
            }
            .settingsRow()
            .accessibilityIdentifier("settingsRateButton")

            Button { showStudio = true } label: {
                HStack {
                    SettingsRowLabel(title: "Version", icon: "hammer.fill", tint: Econ.tide)
                    Spacer()
                    Text("\(Bundle.main.shortVersion) (\(Bundle.main.buildNumber))")
                        .font(EconType.body)
                        .foregroundColor(EconColor.textTertiary)
                }
            }
            .settingsRow()
            .accessibilityIdentifier("settingsVersionRow")
        } header: {
            SettingsHeader(text: "About")
        }
    }

    #if DEBUG
    private var debugSection: some View {
        Section {
            Toggle("🧪 Unlock All Topics", isOn: Binding(
                get: { store.isUnlockAllPurchased },
                set: { store.debugSetUnlockAll($0) }))
                .tint(EconColor.accent)
                .settingsRow()
            Toggle("🧪 Remove Ads", isOn: Binding(
                get: { store.isRemoveAdsPurchased },
                set: { store.debugSetRemoveAds($0) }))
                .tint(EconColor.accent)
                .settingsRow()
            Toggle("🧪 EconByte Pro", isOn: Binding(
                get: { store.isProActive },
                set: { store.debugSetPro($0) }))
                .tint(EconColor.accent)
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

    private func purchase(_ id: PurchaseManager.ProductID) {
        workingProduct = id
        Task {
            let next = await PurchaseFlow.buy(id, from: .settings, store: store, growth: growth,
                                              accessGranted: {
                                                  switch id {
                                                  case .removeAds: return store.isRemoveAdsPurchased
                                                  case .unlockAll: return store.isUnlockAllPurchased
                                                  case .packBundle: return store.isPackBundlePurchased
                                                  default: return store.ownsPack(productID: id.rawValue)
                                                  }
                                              })
            workingProduct = nil
            alert = next
        }
    }

    private func restorePurchases() {
        workingRestore = true
        Task {
            let next = await PurchaseFlow.restore(from: .settings, store: store, growth: growth)
            workingRestore = false
            alert = next
        }
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
                SettingsRowLabel(title: "Daily reminder", icon: "bell.fill", tint: EconColor.accent)
            }
            .tint(EconColor.accent)
            .disabled(denied && !notifications.remindersEnabled)
            .settingsRow()
            .accessibilityIdentifier("settingsRemindersToggle")

            if notifications.remindersEnabled {
                DatePicker(selection: timeBinding, displayedComponents: .hourAndMinute) {
                    HStack(spacing: EconSpace.s) {
                        SettingsIconSpacer()
                        Text("Time").font(EconType.body).foregroundColor(EconColor.textPrimary)
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
            if denied && !notifications.remindersEnabled {
                SettingsFooter(text: "Notifications are off for EconByte in iOS Settings.")
            }
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
         "Built only from official releases on a fixed list of statistics agencies, central banks and international organizations, never from news articles. An AI model drafts it from the releases' own text; it is published only after automated checks of every link and number and a second fact-check. Every figure links to its release. Published each U.S. federal business day."),
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
                EconColor.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: EconSpace.m) {
                        ForEach(sections, id: \.0) { title, body in
                            VStack(alignment: .leading, spacing: EconSpace.xxs) {
                                EconSectionLabel(text: title)
                                Text(body)
                                    .font(EconType.subheadline)
                                    .foregroundColor(EconColor.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(EconSpace.gutter)
                }
            }
            .navigationTitle("Sources & editorial policy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(EconColor.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(EconType.headline)
                        .foregroundColor(EconColor.interactive)
                }
            }
        }
        .tint(EconColor.interactive)
        .accessibilityIdentifier("sourcesPolicyView")
    }
}

// MARK: - Row styling

/// Base size of the rounded icon tile (28 pt); scaled with Dynamic Type at use.
private let settingsIconTile: CGFloat = EconSize.tapTarget - EconSpace.m

struct SettingsRowLabel: View {
    let title: String
    let icon: String
    let tint: Color

    /// The icon tile grows with Dynamic Type so the glyph never outgrows it.
    @ScaledMetric(relativeTo: .body) private var tileSize: CGFloat = settingsIconTile

    var body: some View {
        HStack(spacing: EconSpace.s) {
            Image(systemName: icon)
                .font(EconType.footnote.weight(.semibold))
                .foregroundColor(tint == EconColor.accent ? EconColor.onAccent : EconColor.textPrimary)
                .frame(width: tileSize, height: tileSize)
                .background(tint)
                .clipShape(RoundedRectangle(cornerRadius: EconRadius.badge, style: .continuous))
                .accessibilityHidden(true)
            Text(title)
                .font(EconType.body)
                .foregroundColor(EconColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Keeps text rows without an icon aligned with the ones that have one.
struct SettingsIconSpacer: View {
    @ScaledMetric(relativeTo: .body) private var tileSize: CGFloat = settingsIconTile
    var body: some View { Color.clear.frame(width: tileSize, height: 1).accessibilityHidden(true) }
}

struct SettingsValueRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: EconSpace.s) {
            SettingsIconSpacer()
            Text(title).font(EconType.body).foregroundColor(EconColor.textPrimary)
            Spacer()
            Text(value)
                .font(EconType.body)
                .foregroundColor(EconColor.textTertiary)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
        .settingsRow()
    }
}

struct SettingsHeader: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(EconType.overline)
            .foregroundColor(EconColor.textTertiary)
            .tracking(EconType.overlineTracking)
    }
}

struct SettingsFooter: View {
    let text: String
    var body: some View {
        Text(text)
            .font(EconType.footnote)
            .foregroundColor(EconColor.textTertiary)
    }
}

extension View {
    func settingsRow() -> some View {
        listRowBackground(EconColor.surfaceRaised)
    }
}
