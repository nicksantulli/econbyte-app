import SwiftUI
import StoreKit

/// The EconByte Pro subscription paywall (1.1.4).
///
/// Built to App Review 3.1.2: the billed price is the most prominent element on
/// the screen (the large figure in the plan card and the subscribe button); the
/// free-trial line is smaller, sits under it, and appears ONLY when StoreKit
/// says this Apple ID is eligible for the introductory offer; the title of the
/// subscription, what the subscriber gets, the duration and price per period,
/// auto-renewal terms, Terms of Use (Apple's standard EULA), Privacy Policy,
/// and Restore are all on the page. Prices are StoreKit `displayPrice` values,
/// never literals. While StoreKit fetches, the tiles and the button say
/// "Loading price…"; if it gave no price they say "Price unavailable" /
/// "Subscribe" (disabled) with "Prices unavailable — Try again" (Phase 11 — no
/// bare "—" and never "Subscribe for —").
///
/// The Unlock All paywall (`PaywallView`) is untouched and still titled
/// "Purchases": the one-time products remain independent of each other (D4)
/// and of Pro (D19). A pack bought outright stays owned after Pro lapses.
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
                        .padding(.bottom, 40)
                }
            }
            .navigationTitle("EconByte Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") { dismiss() }.foregroundColor(Econ.sky)
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

/// The paywall itself, shared by the full-screen cover and the Pro tab (1.1.4
/// shell), so both carry the same 3.1.2 elements: price primary, subordinate
/// trial line for eligible readers only, what you get, renewal terms, Terms of
/// Use, Privacy Policy, Restore. `interlude` sits between the purchase controls
/// and the benefits (the Pro tab puts the course list there).
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

    private var product: Product? { store.product(for: selected) }
    private var priceState: PurchasePresentation.PriceState { store.priceState(for: selected) }
    private var pending: Bool { PurchaseManager.ProductID.subscriptions.contains { store.isPending($0) } }
    private var trialPeriod: Product.SubscriptionPeriod? {
        guard store.isEligibleForTrial == true, priceState.displayPrice != nil else { return nil }
        return store.freeTrialPeriod(for: selected)
    }
    private var canBuy: Bool {
        !pending && PurchasePresentation.canPurchase(displayPrice: priceState.displayPrice,
                                                     isWorking: working, isLoading: store.isLoadingProducts)
    }

    var body: some View {
        VStack(spacing: 22) {
            header
            if store.isProActive {
                activeState
            } else {
                planPicker
                subscribeBlock
            }
            interlude()
            benefits
            legal
        }
        .purchaseAlert($alert)
        .manageSubscriptions(isPresented: $showManageSubscriptions, store: store)
        .onAppear {
            growth.monetization.setBlocker(.paywall, active: true)
            growth.review.noteNegativeSessionEvent(.paywall)
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

    // MARK: Pieces

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "graduationcap.fill")
                .font(.system(size: 44))
                .foregroundColor(Econ.amber)
                .padding(.top, 8)
                .accessibilityHidden(true)
            Text("Go further than the cards")
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundColor(Econ.white)
                .multilineTextAlignment(.center)
            Text("Three courses with charts and quizzes, a Daily Economic Brief built only from official releases, every topic pack, and no ads.")
                .font(.system(size: 15, design: .rounded))
                .foregroundColor(Econ.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
    }

    private var planPicker: some View {
        HStack(spacing: 12) {
            planCard(.proAnnual, badge: "Best value")
            planCard(.proMonthly, badge: nil)
        }
        .accessibilityElement(children: .contain)
    }

    private func planName(_ id: PurchaseManager.ProductID) -> String {
        id == .proAnnual ? "Pro Yearly" : "Pro Monthly"
    }

    private func planCard(_ id: PurchaseManager.ProductID, badge: String?) -> some View {
        let product = store.product(for: id)
        let state = store.priceState(for: id)
        let period = Self.perPeriod(product, fallback: id)
        let isSelected = selected == id
        return Button {
            selected = id
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(planName(id).uppercased())
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(Econ.subtext)
                        .tracking(0.8)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 4)
                    if let badge {
                        Text(badge)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(Econ.ink)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Econ.amber)
                            .cornerRadius(4)
                    }
                }
                switch state {
                case .ready(let price):
                    // The billed price: the largest text on the screen.
                    Text(price)
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .foregroundColor(Econ.white)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text(period)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(Econ.white.opacity(0.8))
                    if id == .proAnnual, let monthly = Self.monthlyEquivalent(product) {
                        Text("\(monthly) a month, billed once a year")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundColor(Econ.subtext)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                case .loading:
                    HStack(spacing: 6) {
                        ProgressView().tint(Econ.sky).scaleEffect(0.8)
                        Text(PurchasePresentation.loadingPriceText)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(Econ.white.opacity(0.75))
                    }
                    .frame(minHeight: 36, alignment: .leading)
                    Text(period == "/ year" ? "Billed yearly" : "Billed monthly")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(Econ.white.opacity(0.6))
                case .unavailable:
                    Text("Price unavailable")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(Econ.white.opacity(0.75))
                        .frame(minHeight: 36, alignment: .leading)
                    Text(period == "/ year" ? "Billed yearly" : "Billed monthly")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(Econ.white.opacity(0.6))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Econ.tide.opacity(isSelected ? 0.28 : 0.10))
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(isSelected ? Econ.amber : Econ.mist.opacity(0.2), lineWidth: isSelected ? 2 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("proPaywallPlan-\(id == .proAnnual ? "annual" : "monthly")")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityLabel(Text(Self.planAccessibilityLabel(planName(id), state, period: period)))
    }

    /// "Pro Yearly plan, $29.99 / year" · "Pro Yearly plan, Loading price…" ·
    /// "Pro Yearly plan, Price unavailable".
    static func planAccessibilityLabel(_ name: String, _ state: PurchasePresentation.PriceState, period: String) -> String {
        switch state {
        case .ready(let price): return "\(name) plan, \(price) \(period)"
        case .loading: return "\(name) plan, \(PurchasePresentation.loadingPriceText)"
        case .unavailable: return "\(name) plan, Price unavailable"
        }
    }

    private var subscribeBlock: some View {
        VStack(spacing: 10) {
            Button {
                subscribe()
            } label: {
                if working {
                    ProgressView().tint(Econ.ink)
                } else {
                    // Price first, again the largest element of the control.
                    Text(PurchasePresentation.subscribeTitle(priceState,
                                                             period: Self.perPeriod(product, fallback: selected),
                                                             pending: pending))
                }
            }
            .buttonStyle(PrimaryButton())
            .disabled(!canBuy)
            .opacity(canBuy ? 1 : 0.55)
            .accessibilityIdentifier("proPaywallSubscribeButton")

            if priceState == .unavailable {
                PricesUnavailableNotice(identifier: "proPaywallPricesUnavailable") {
                    Task {
                        await store.loadProducts()
                        await store.refreshTrialEligibility()
                    }
                }
            }

            // Subordinate trial line: smaller, under the price, eligible users only.
            if let trialPeriod, let price = priceState.displayPrice {
                Text("\(Self.trialText(trialPeriod)) free trial, then \(price) \(Self.perPeriod(product, fallback: selected)). Cancel anytime.")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(Econ.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("proPaywallTrialLine")
            }

            Button("Restore Purchases") { restore() }
                .buttonStyle(SecondaryButton())
                .disabled(working)
                .accessibilityIdentifier("proPaywallRestoreButton")
        }
    }

    private var activeState: some View {
        VStack(spacing: 10) {
            Text(store.proEntitlement?.state.hasBillingIssue == true
                 ? "Pro — payment issue" : "You're a Pro subscriber ✓")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundColor(store.proEntitlement?.state.hasBillingIssue == true ? Econ.amber : Econ.sky)
            if let pro = store.proEntitlement {
                ForEach(ProStatusCopy.rows(for: pro).filter { $0.title != "Status" }) { row in
                    Text("\(row.title): \(row.value)")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(Econ.white.opacity(0.7))
                }
            }
            Button("Manage Subscription") { showManageSubscriptions = true }
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundColor(Econ.sky)
        }
        .padding(.vertical, 8)
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("WHAT YOU GET")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(Econ.subtext)
                .tracking(1.5)
            benefitRow("book.fill", "Three courses — Investing Approaches, Reading Price Charts, Bonds, Rates and the Yield Curve — with charts, diagrams and quizzes")
            benefitRow("newspaper.fill", "The Daily Economic Brief: what official releases said, in plain English, with sources")
            benefitRow("square.stack.3d.up.fill", "Every topic pack and every core topic while you're subscribed")
            benefitRow("rectangle.slash", "No ads")
            benefitRow("icloud.and.arrow.down.fill", "Works on all your devices with the same Apple ID")
        }
        .padding(16)
        .background(Econ.tide.opacity(0.12))
        .cornerRadius(14)
    }

    private func benefitRow(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(Econ.amber)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: 14, design: .rounded))
                .foregroundColor(Econ.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private var legal: some View {
        VStack(spacing: 10) {
            Text("EconByte Pro is an auto-renewing subscription, billed monthly or yearly at the price shown. Payment is charged to your Apple ID account when you confirm the purchase, or when a free trial ends. The subscription renews automatically unless you cancel at least 24 hours before the end of the current period; your account is charged for renewal within 24 hours before the period ends. You can manage or cancel it in your Apple ID settings. Packs you bought separately stay yours whether or not you subscribe. Content is educational and is not investment advice.")
                .font(.system(size: 11, design: .rounded))
                .foregroundColor(Econ.subtext)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 18) {
                Link("Terms of Use", destination: PurchaseManager.termsOfUseURL)
                    .accessibilityIdentifier("proPaywallTermsLink")
                Link("Privacy Policy", destination: PurchaseManager.privacyPolicyURL)
                    .accessibilityIdentifier("proPaywallPrivacyLink")
            }
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundColor(Econ.sky)
        }
    }

    // MARK: Formatting

    static func perPeriod(_ product: Product?) -> String {
        guard let period = product?.subscription?.subscriptionPeriod else { return "" }
        switch (period.unit, period.value) {
        case (.year, 1):  return "/ year"
        case (.month, 1): return "/ month"
        case (.week, 1):  return "/ week"
        case (.day, 1):   return "/ day"
        case (.year, let n):  return "/ \(n) years"
        case (.month, let n): return "/ \(n) months"
        case (.week, let n):  return "/ \(n) weeks"
        case (.day, let n):   return "/ \(n) days"
        @unknown default:     return ""
        }
    }

    /// The period StoreKit reports, or the plan's contracted period when the
    /// product has not loaded (a duration, never a price).
    static func perPeriod(_ product: Product?, fallback id: PurchaseManager.ProductID) -> String {
        let reported = perPeriod(product)
        return reported.isEmpty ? PurchasePresentation.periodSuffix(for: id) : reported
    }

    static func trialText(_ period: Product.SubscriptionPeriod) -> String {
        switch (period.unit, period.value) {
        case (.week, 1): return "7-day"
        case (.day, let n): return "\(n)-day"
        case (.week, let n): return "\(n)-week"
        case (.month, let n): return n == 1 ? "1-month" : "\(n)-month"
        case (.year, let n): return n == 1 ? "1-year" : "\(n)-year"
        @unknown default: return "Free"
        }
    }

    /// The yearly price divided by twelve, in the product's own currency
    /// format. `nil` for anything that is not a one-year subscription.
    static func monthlyEquivalent(_ product: Product?) -> String? {
        guard let product, let period = product.subscription?.subscriptionPeriod,
              period.unit == .year, period.value == 1 else { return nil }
        let monthly = (product.price / 12) as Decimal
        var rounded = Decimal()
        var value = monthly
        NSDecimalRound(&rounded, &value, 2, .plain)
        return rounded.formatted(product.priceFormatStyle)
    }

    // MARK: Plumbing

    private func subscribe() {
        working = true
        growth.monetization.setBlocker(.purchase, active: true)
        growth.review.noteNegativeSessionEvent(.purchase)
        Task {
            let result = await store.purchase(selected, from: entryPoint.ebEntryPoint)
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
                                                 accessGranted: store.isProActive) else { return }
        growth.review.noteNegativeSessionEvent(.errorShown)
        alert = next
    }
}

extension ProPaywallContent where Interlude == EmptyView {
    init(entryPoint: EconEntryPoint) {
        self.init(entryPoint: entryPoint) { EmptyView() }
    }
}
