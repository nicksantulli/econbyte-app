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
                Econ.ocean.ignoresSafeArea()
                ScrollView {
                    ProPaywallContent(entryPoint: entryPoint)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 40)
                }
            }
            .navigationTitle("EconByte Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") { dismiss() }
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(Econ.sky)
                        .accessibilityIdentifier("proPaywallCloseButton")
                }
            }
        }
        .tint(Econ.sky)
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
        VStack(spacing: 20) {
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
            VStack(spacing: 10) {
                ForEach(Self.plans, id: \.self) { planTile($0) }
            }
            .accessibilityElement(children: .contain)
            if let trialLine {
                Text(trialLine)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundColor(Econ.white.opacity(0.85))
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
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(isSelected ? Econ.amber : Econ.subtext)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(PlanCopy.planName(id))
                            .font(.system(.subheadline, design: .rounded).weight(.bold))
                            .foregroundColor(Econ.white.opacity(0.85))
                        if let badge {
                            Text(badge)
                                .font(.system(.caption, design: .rounded).weight(.bold))
                                .foregroundColor(isCurrent ? Econ.ocean : Econ.ink)
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(isCurrent ? Econ.sky : Econ.amber)
                                .cornerRadius(5)
                        }
                    }
                    switch state {
                    case .ready:
                        // The billed price in words: the largest price text on the page.
                        Text(billed ?? "")
                            .font(.system(.title2, design: .rounded).weight(.heavy))
                            .foregroundColor(Econ.white)
                            .minimumScaleFactor(0.75)
                            .fixedSize(horizontal: false, vertical: true)
                        if let perMonth {
                            Text(perMonth)
                                .font(.system(.footnote, design: .rounded))
                                .foregroundColor(Econ.white.opacity(0.65))
                        }
                    case .loading:
                        HStack(spacing: 6) {
                            ProgressView().tint(Econ.sky).scaleEffect(0.8)
                            Text(PurchasePresentation.loadingPriceText)
                                .font(.system(.subheadline, design: .rounded).weight(.medium))
                                .foregroundColor(Econ.white.opacity(0.75))
                        }
                    case .unavailable:
                        Text("Price unavailable")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundColor(Econ.white.opacity(0.75))
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Econ.ocean.opacity(isSelected ? 0.6 : 0.3))
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(isSelected ? Econ.amber : Econ.mist.opacity(0.2), lineWidth: isSelected ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 14))
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
            VStack(alignment: .leading, spacing: 6) {
                ForEach(ProStatusCopy.rows(for: pro).filter { $0.title != "Status" && $0.title != "Plan" }) { row in
                    HStack {
                        Text(row.title).foregroundColor(Econ.white.opacity(0.8))
                        Spacer()
                        Text(row.value).foregroundColor(Econ.subtext)
                    }
                    .font(.system(.subheadline, design: .rounded))
                    .accessibilityElement(children: .combine)
                }
                Text(ProStatusCopy.footer(for: pro))
                    .font(.system(.caption, design: .rounded))
                    .foregroundColor(Econ.subtext)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        Button("Manage Subscription") { showManageSubscriptions = true }
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .foregroundColor(Econ.sky)
            .frame(maxWidth: .infinity, minHeight: 44)
            .buttonStyle(.borderless)
            .accessibilityIdentifier("proManageSubscriptionLink")
    }

    // MARK: Benefits, legal

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(subscribed ? "INCLUDED" : "WHAT YOU GET")
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundColor(Econ.subtext)
                .tracking(1.5)
                .accessibilityAddTraits(.isHeader)
            ForEach(PaywallBenefits.current().rows) { row in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: row.icon)
                        .foregroundColor(Econ.amber)
                        .frame(width: 24)
                        .accessibilityHidden(true)
                    Text(row.text)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundColor(Econ.white.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Econ.tide.opacity(0.10))
        .cornerRadius(14)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("proPaywallBenefits")
    }

    private var legal: some View {
        VStack(spacing: 10) {
            Text(PlanCopy.autoRenewDisclosure(trial: trialLine != nil))
                .font(.system(.caption, design: .rounded))
                .foregroundColor(Econ.white.opacity(0.62))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("proPaywallAutoRenewDisclosure")
            Text(PlanCopy.notAdvice)
                .font(.system(.caption, design: .rounded))
                .foregroundColor(Econ.white.opacity(0.62))
                .accessibilityIdentifier("proPaywallNotAdvice")
            HStack(spacing: 18) {
                Link("Terms of Use", destination: PurchaseManager.termsOfUseURL)
                    .accessibilityIdentifier("proPaywallTermsLink")
                Link("Privacy Policy", destination: PurchaseManager.privacyPolicyURL)
                    .accessibilityIdentifier("proPaywallPrivacyLink")
            }
            .font(.system(.subheadline, design: .rounded).weight(.medium))
            .foregroundColor(Econ.sky)
            .frame(minHeight: 44)
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
