import SwiftUI
import StoreKit

/// The EconByte Pro subscription paywall (1.1.4), built to App Review 3.1.2 and
/// `econbyte-subscription-review-checklist.md` section A:
///
///   * two plan tiles, the annual plan preselected — no trial toggle (A3);
///   * each tile's largest price is the full billed amount in words
///     ("$39.99 per year"); the per-month equivalent and "Save X%" are smaller,
///     after it, and computed from StoreKit prices (A1, A9);
///   * the trial line appears only when StoreKit says the reader is eligible,
///     and is complete (A2); the button names the selected plan's action and
///     carries its price (A3);
///   * auto-renewal disclosure, Terms of Use and Privacy Policy links, and
///     Restore are on the page (A4, A6, A7); what Pro includes is counted from
///     the bundled catalogs at runtime (A5);
///   * a subscriber sees "Current plan" on their tile and switches plans
///     through StoreKit, or opens Manage Subscription (A10).
///
/// The full-screen cover has a visible Close button (A8); the Pro tab shows the
/// same content inline.
struct ProPaywallView: View {
    var entryPoint: EconEntryPoint = .home

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: PurchaseManager

    var body: some View {
        NavigationStack {
            ZStack {
                EconColor.background.ignoresSafeArea()
                ScrollView {
                    ProPaywallContent(entryPoint: entryPoint)
                        .padding(.horizontal, EconSpace.gutter)
                        .padding(.top, EconSpace.xs)
                        .padding(.bottom, EconSpace.xxl)
                }
            }
            .navigationTitle("EconByte Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") { dismiss() }
                        .font(EconType.headline)
                        .foregroundColor(EconColor.interactive)
                        .accessibilityIdentifier("proPaywallCloseButton")
                }
            }
        }
        .tint(EconColor.interactive)
        .onChange(of: store.isProActive) { active in
            if active { dismiss() }
        }
    }
}

/// The paywall itself, shared by the full-screen cover and the Pro tab.
/// `interlude` sits between the offer and the benefits (the Pro tab puts the
/// course list there).
struct ProPaywallContent<Interlude: View>: View {
    let entryPoint: EconEntryPoint
    let interlude: () -> Interlude

    @EnvironmentObject private var store: PurchaseManager
    @EnvironmentObject private var growth: EconGrowth
    @State private var selected: PurchaseManager.ProductID = .proAnnual
    @State private var working = false
    @State private var alert: PurchaseAlertCopy.Alert?
    @State private var showManageSubscriptions = false

    init(entryPoint: EconEntryPoint, @ViewBuilder interlude: @escaping () -> Interlude) {
        self.entryPoint = entryPoint
        self.interlude = interlude
    }

    static var plans: [PurchaseManager.ProductID] { [.proAnnual, .proMonthly] }

    private var priceState: PurchasePresentation.PriceState { store.priceState(for: selected) }
    private var pending: Bool { PurchaseManager.ProductID.subscriptions.contains { store.isPending($0) } }
    private var subscribed: Bool { store.isProActive }

    private var trialLine: String? {
        guard !subscribed, priceState.displayPrice != nil else { return nil }
        return PlanCopy.trialLine(store.offer(for: selected), eligible: store.isEligibleForTrial)
    }

    var body: some View {
        VStack(spacing: EconSpace.l) {
            offer
            interlude()
            benefits
            legal
        }
        .purchaseAlert($alert)
        .manageSubscriptions(isPresented: $showManageSubscriptions, store: store)
        .onAppear {
            if let current = store.currentPlan { selected = current }
            growth.monetization.setBlocker(.paywall, active: true)
            growth.review.noteNegativeSessionEvent(.paywall)
        }
        .onChange(of: store.currentPlan) { current in
            if let current { selected = current }
        }
        .onDisappear { growth.monetization.setBlocker(.paywall, active: false) }
        .task {
            await store.loadProducts()
            await store.refreshTrialEligibility()
            EBEvents.proPaywallShown(entryPoint: entryPoint.ebEntryPoint,
                                     productsReady: store.productsReady,
                                     trialEligible: store.isEligibleForTrial)
        }
    }

    // MARK: Offer

    private var statusText: String? {
        guard subscribed else { return nil }
        return store.proEntitlement?.state.hasBillingIssue == true ? "Payment issue" : "Active ✓"
    }

    private var offer: some View {
        OfferCard(icon: "graduationcap.fill",
                  title: "EconByte Pro",
                  status: statusText,
                  statusIdentifier: "proActiveBadge",
                  highlighted: !subscribed,
                  identifier: "proOfferCard",
                  button: subscribeButton,
                  restoreIdentifier: "proPaywallRestoreButton",
                  onRestore: restore,
                  restoreDisabled: working) {
            VStack(spacing: EconSpace.xs) {
                ForEach(Self.plans, id: \.self) { planTile($0) }
            }
            .accessibilityElement(children: .contain)
            if let trialLine {
                Text(trialLine)
                    .font(EconType.footnote)
                    .foregroundColor(EconColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("proPaywallTrialLine")
            }
            if subscribed {
                subscriberDetails
            }
        }
    }

    private var subscribeButton: PurchaseButton {
        let action = PlanCopy.subscribeAction(for: selected, offer: store.offer(for: selected),
                                              eligible: store.isEligibleForTrial,
                                              currentPlan: store.currentPlan)
        let model = PurchaseButtonModel.make(action: action.action, price: priceState,
                                             priceText: action.priceText, ownedLabel: action.ownedLabel,
                                             pending: pending, working: working,
                                             isLoadingProducts: store.isLoadingProducts)
        return PurchaseButton(model: model,
                              identifier: "proPaywallSubscribeButton",
                              unavailableIdentifier: "proPaywallPricesUnavailable",
                              onRetry: {
                                  Task {
                                      await store.loadProducts()
                                      await store.refreshTrialEligibility()
                                  }
                              },
                              action: subscribe)
    }

    private var savingsBadge: String? {
        guard let annual = store.offer(for: .proAnnual), let monthly = store.offer(for: .proMonthly) else { return nil }
        return PlanCopy.savingsBadge(plan: annual, comparedWith: monthly)
    }

    private func planTile(_ id: PurchaseManager.ProductID) -> some View {
        let offer = store.offer(for: id)
        let state = store.priceState(for: id)
        let isSelected = selected == id
        let isCurrent = store.currentPlan == id
        let billed = offer.map(PlanCopy.billedPrice)
        let perMonth = offer.flatMap(PlanCopy.perMonth)
        let badge: String? = isCurrent ? "Current plan" : (id == .proAnnual ? savingsBadge : nil)
        return Button {
            selected = id
        } label: {
            HStack(alignment: .center, spacing: EconSpace.s) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(EconType.title3)
                    .foregroundColor(isSelected ? EconColor.accent : EconColor.textTertiary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: EconSpace.xxs) {
                    EconAdaptiveRow {
                        Text(PlanCopy.planName(id))
                            .font(EconType.subheadlineEmphasis)
                            .foregroundColor(EconColor.textPrimary)
                        if let badge {
                            EconBadge(text: badge, style: isCurrent ? .interactive : .accent)
                        }
                    }
                    switch state {
                    case .ready:
                        // The billed price in words: the largest price text on the page.
                        Text(billed ?? "")
                            .font(EconType.title)
                            .foregroundColor(EconColor.textPrimary)
                            .minimumScaleFactor(0.75)
                            .fixedSize(horizontal: false, vertical: true)
                        if let perMonth {
                            Text(perMonth)
                                .font(EconType.footnote)
                                .foregroundColor(EconColor.textSecondary)
                        }
                    case .loading:
                        HStack(spacing: EconSpace.xxs) {
                            ProgressView().tint(EconColor.interactive).scaleEffect(0.8)
                            Text(PurchasePresentation.loadingPriceText)
                                .font(EconType.subheadline)
                                .foregroundColor(EconColor.textSecondary)
                        }
                    case .unavailable:
                        Text("Price unavailable")
                            .font(EconType.subheadlineEmphasis)
                            .foregroundColor(EconColor.textSecondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(EconSpace.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(EconColor.surfaceInset)
            .clipShape(RoundedRectangle(cornerRadius: EconRadius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: EconRadius.control, style: .continuous)
                .stroke(isSelected ? EconColor.accent : EconColor.outline, lineWidth: isSelected ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: EconRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("proPaywallPlan-\(id == .proAnnual ? "annual" : "monthly")")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityLabel(Text(Self.planAccessibilityLabel(PlanCopy.planName(id), state,
                                                            billed: billed, perMonth: perMonth, badge: badge)))
    }

    /// "Annual plan, $39.99 per year, $3.33 per month, Save 66%" ·
    /// "Annual plan, Loading price…" · "Annual plan, Price unavailable".
    static func planAccessibilityLabel(_ name: String, _ state: PurchasePresentation.PriceState,
                                       billed: String?, perMonth: String?, badge: String?) -> String {
        switch state {
        case .ready(let price):
            return (["\(name) plan", billed ?? price, perMonth, badge] as [String?]).compactMap { $0 }.joined(separator: ", ")
        case .loading: return "\(name) plan, \(PurchasePresentation.loadingPriceText)"
        case .unavailable: return "\(name) plan, Price unavailable"
        }
    }

    @ViewBuilder
    private var subscriberDetails: some View {
        if let pro = store.proEntitlement {
            VStack(alignment: .leading, spacing: EconSpace.xxs) {
                ForEach(ProStatusCopy.rows(for: pro).filter { $0.title != "Status" && $0.title != "Plan" }) { row in
                    HStack {
                        Text(row.title).foregroundColor(EconColor.textSecondary)
                        Spacer()
                        Text(row.value).foregroundColor(EconColor.textPrimary)
                    }
                    .font(EconType.subheadline)
                    .accessibilityElement(children: .combine)
                }
                Text(ProStatusCopy.footer(for: pro))
                    .font(EconType.caption)
                    .foregroundColor(EconColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        Button("Manage Subscription") { showManageSubscriptions = true }
            .buttonStyle(EconLinkButton())
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("proManageSubscriptionLink")
    }

    // MARK: Benefits, legal

    private var benefits: some View {
        VStack(alignment: .leading, spacing: EconSpace.s) {
            EconSectionLabel(text: subscribed ? "INCLUDED" : "WHAT YOU GET")
            ForEach(PaywallBenefits.current().rows) { row in
                HStack(alignment: .top, spacing: EconSpace.s) {
                    Image(systemName: row.icon)
                        .font(EconType.subheadline)
                        .foregroundColor(EconColor.accent)
                        .frame(width: EconSpace.xl)
                        .accessibilityHidden(true)
                    Text(row.text)
                        .font(EconType.subheadline)
                        .foregroundColor(EconColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
        .econCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("proPaywallBenefits")
    }

    private var legal: some View {
        VStack(spacing: EconSpace.xs) {
            Text(PlanCopy.autoRenewDisclosure(trial: trialLine != nil))
                .font(EconType.caption)
                .foregroundColor(EconColor.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("proPaywallAutoRenewDisclosure")
            Text(PlanCopy.notAdvice)
                .font(EconType.caption)
                .foregroundColor(EconColor.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("proPaywallNotAdvice")
            HStack(spacing: EconSpace.m) {
                Link("Terms of Use", destination: PurchaseManager.termsOfUseURL)
                    .accessibilityIdentifier("proPaywallTermsLink")
                Link("Privacy Policy", destination: PurchaseManager.privacyPolicyURL)
                    .accessibilityIdentifier("proPaywallPrivacyLink")
            }
            .font(EconType.subheadlineEmphasis)
            .foregroundColor(EconColor.interactive)
            .frame(minHeight: EconSize.tapTarget)
        }
    }

    // MARK: Plumbing

    private func subscribe() {
        let plan = selected
        working = true
        Task {
            let next = await PurchaseFlow.buy(plan, from: entryPoint.ebEntryPoint, store: store, growth: growth,
                                              accessGranted: { store.currentPlan == plan })
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

extension ProPaywallContent where Interlude == EmptyView {
    init(entryPoint: EconEntryPoint) {
        self.init(entryPoint: entryPoint) { EmptyView() }
    }
}
