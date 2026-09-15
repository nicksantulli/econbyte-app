import Foundation
import StoreKit

// MARK: - Store offers and plan copy (1.1.4 release scope, 2026-09-15)
//
// Every price a purchase surface shows is derived here from a `StoreOffer`: a
// value copy of what StoreKit reported for one product (its `displayPrice`,
// `price`, `priceFormatStyle`, billing period and introductory free trial).
// Views never touch `Product` directly and never contain a price literal, so
// the App Review 3.1.2 rules (`econbyte-subscription-review-checklist.md`
// section A) are pure functions with unit tests:
//
//   A1  the billed price in words ("$39.99 per year") is the primary price;
//       the per-month equivalent and "Save X%" are derived and subordinate.
//   A2  the trial line exists only for an eligible reader and is complete.
//   A3  two plan tiles, the CTA names the selected plan's action.
//   A9  prices only from StoreKit (`displayPrice` / `priceFormatStyle`).
//   A10 a subscriber sees "Current plan" and switches through StoreKit.

/// A billing or trial period in plain words.
struct BillingTerm: Equatable {
    enum Unit: String, Equatable { case day, week, month, year }

    let unit: Unit
    let value: Int

    init(unit: Unit, value: Int) {
        self.unit = unit
        self.value = max(1, value)
    }

    init?(_ period: Product.SubscriptionPeriod) {
        switch period.unit {
        case .day: self.init(unit: .day, value: period.value)
        case .week: self.init(unit: .week, value: period.value)
        case .month: self.init(unit: .month, value: period.value)
        case .year: self.init(unit: .year, value: period.value)
        @unknown default: return nil
        }
    }

    /// "per year", "per month", "every 3 months".
    var perPhrase: String {
        value == 1 ? "per \(unit.rawValue)" : "every \(value) \(unit.rawValue)s"
    }

    /// "7-day" (a one-week trial is said in days), "3-day", "1-month".
    var adjective: String {
        switch unit {
        case .day: return "\(value)-day"
        case .week: return "\(value * 7)-day"
        case .month, .year: return "\(value)-\(unit.rawValue)"
        }
    }

    /// "7 days", "1 day", "1 month", "2 months".
    var duration: String {
        switch unit {
        case .day: return value == 1 ? "1 day" : "\(value) days"
        case .week: return "\(value * 7) days"
        case .month, .year: return value == 1 ? "1 \(unit.rawValue)" : "\(value) \(unit.rawValue)s"
        }
    }

    /// Months in the period, for a per-month equivalent. `nil` below a month.
    var months: Int? {
        switch unit {
        case .year: return value * 12
        case .month: return value
        case .day, .week: return nil
        }
    }
}

/// What StoreKit reported for one product, as a value.
struct StoreOffer: Equatable {
    let id: PurchaseManager.ProductID
    /// StoreKit's own localized price string, shown verbatim.
    let displayPrice: String
    let price: Decimal
    /// The storefront's currency format, used for every derived amount.
    let priceFormatStyle: Decimal.FormatStyle.Currency
    /// Subscriptions only.
    let period: BillingTerm?
    /// The introductory offer, when it is a free trial.
    let freeTrial: BillingTerm?

    func format(_ amount: Decimal) -> String { amount.formatted(priceFormatStyle) }
}

extension StoreOffer {
    init?(product: Product) {
        guard let id = PurchaseManager.ProductID(rawValue: product.id) else { return nil }
        var trial: BillingTerm?
        if let intro = product.subscription?.introductoryOffer, intro.paymentMode == .freeTrial {
            trial = BillingTerm(intro.period)
        }
        self.init(id: id,
                  displayPrice: product.displayPrice,
                  price: product.price,
                  priceFormatStyle: product.priceFormatStyle,
                  period: product.subscription.flatMap { BillingTerm($0.subscriptionPeriod) },
                  freeTrial: trial)
    }
}

/// The copy every plan tile, trial line and subscribe button uses.
enum PlanCopy {

    static func planName(_ id: PurchaseManager.ProductID) -> String {
        // Matches the App Store Connect display names "EconByte Pro Annual" /
        // "EconByte Pro Monthly" (Lane C, 2026-09-15).
        id == .proAnnual ? "Annual" : "Monthly"
    }

    /// The billed price in words: "$39.99 per year". A one-time product is its
    /// display price alone.
    static func billedPrice(_ offer: StoreOffer) -> String {
        guard let period = offer.period else { return offer.displayPrice }
        return "\(offer.displayPrice) \(period.perPhrase)"
    }

    /// "$3.33 per month" for a plan billed less often than monthly, in the
    /// storefront's currency; `nil` for a monthly (or shorter) plan.
    static func perMonth(_ offer: StoreOffer) -> String? {
        guard let months = offer.period?.months, months > 1 else { return nil }
        var value = offer.price / Decimal(months)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 2, .plain)
        return "\(offer.format(rounded)) per month"
    }

    /// Whole percent saved by the longer plan against paying the shorter one
    /// for the same time, ROUNDED DOWN so the claim is never overstated
    /// ($39.99 vs 12 × $9.99 = 66.6% → 66). `nil` unless both are priced in the
    /// same currency and the saving is at least 1%.
    static func savingsPercent(plan: StoreOffer, comparedWith shorter: StoreOffer) -> Int? {
        guard let planMonths = plan.period?.months, let shorterMonths = shorter.period?.months,
              planMonths > shorterMonths, shorter.price > 0,
              plan.priceFormatStyle.currencyCode == shorter.priceFormatStyle.currencyCode else { return nil }
        let sameSpan = shorter.price * Decimal(planMonths) / Decimal(shorterMonths)
        let saved = (sameSpan - plan.price) / sameSpan * 100
        let percent = Int(floor(NSDecimalNumber(decimal: saved).doubleValue))
        return percent >= 1 ? percent : nil
    }

    static func savingsBadge(plan: StoreOffer, comparedWith shorter: StoreOffer) -> String? {
        savingsPercent(plan: plan, comparedWith: shorter).map { "Save \($0)%" }
    }

    static let trialCancelSentence = "Cancel anytime in Settings at least 24 hours before the trial ends."

    /// The complete trial line — only for a reader StoreKit says is eligible
    /// (`isEligibleForIntroOffer == true`) and a plan that has a free trial.
    static func trialLine(_ offer: StoreOffer?, eligible: Bool?) -> String? {
        guard eligible == true, let offer, let trial = offer.freeTrial, offer.period != nil else { return nil }
        return "Free for \(trial.duration), then \(billedPrice(offer)). \(trialCancelSentence)"
    }

    /// The subscribe control for the selected plan: its action and the price
    /// text that follows it. `ownedLabel` is set when the plan is the reader's
    /// current subscription.
    struct Action: Equatable {
        let action: String
        let priceText: String?
        let ownedLabel: String?
    }

    static func subscribeAction(for id: PurchaseManager.ProductID, offer: StoreOffer?,
                                eligible: Bool?, currentPlan: PurchaseManager.ProductID?) -> Action {
        let billed = offer.map(billedPrice)
        if let currentPlan {
            if currentPlan == id { return Action(action: "Current plan", priceText: nil, ownedLabel: "Current plan") }
            return Action(action: "Switch to \(planName(id))", priceText: billed, ownedLabel: nil)
        }
        if let offer, let trial = offer.freeTrial, eligible == true, let billed {
            return Action(action: "Start \(trial.adjective) free trial", priceText: "then \(billed)", ownedLabel: nil)
        }
        return Action(action: "Subscribe", priceText: billed, ownedLabel: nil)
    }

    /// Auto-renewal disclosure (checklist A4), shown on the paywall itself. The
    /// trial clause appears only alongside the trial line (A2: no trial wording
    /// for a reader who cannot take the trial).
    static func autoRenewDisclosure(trial: Bool) -> String {
        let charged = trial
            ? "Payment is charged to your Apple ID account when the free trial ends."
            : "Payment is charged to your Apple ID account when you confirm the purchase."
        return "\(charged) The subscription renews automatically at the same price and period unless you cancel at least 24 hours before the current period ends. Manage or cancel in Settings → Apple ID → Subscriptions."
    }

    static let notAdvice = "Educational content, not financial advice."
}

/// What Pro includes, counted from the bundled catalogs at runtime (A5).
struct PaywallBenefits: Equatable {
    var courses: Int
    var lessons: Int
    var packs: Int
    var packCards: Int
    var coreTopics: Int
    var briefCadence: String

    @MainActor
    static func current(content: ContentStore = .shared) -> PaywallBenefits {
        PaywallBenefits(courses: content.courses?.courses.count ?? 0,
                        lessons: content.courses?.allLessons.count ?? 0,
                        packs: content.packs.count,
                        packCards: content.packCards.count,
                        coreTopics: content.topics.count,
                        briefCadence: BriefStore.cadenceDescription)
    }

    struct Row: Equatable, Identifiable {
        let icon: String
        let text: String
        var id: String { text }
    }

    var rows: [Row] {
        var rows: [Row] = []
        if courses > 0 {
            rows.append(Row(icon: "book.fill",
                            text: "\(courses) courses, \(lessons) lessons with charts and quizzes"))
        }
        rows.append(Row(icon: "newspaper.fill", text: "The Daily Brief, \(briefCadence)"))
        if packs > 0 {
            rows.append(Row(icon: "square.stack.3d.up.fill",
                            text: "All \(packs) topic packs (\(packCards) cards) and all \(coreTopics) core topics"))
        }
        rows.append(Row(icon: "rectangle.slash", text: "No ads"))
        rows.append(Row(icon: "icloud.and.arrow.down.fill", text: "On every device with your Apple ID"))
        return rows
    }
}

// MARK: - The one purchase button model

/// Everything a `PurchaseButton` shows, decided in one place so every pack,
/// the bundle, Unlock All, Remove Ads and Pro read alike:
///   * priced:       "Unlock · $1.99" (enabled)
///   * loading:      "Loading price…" with a spinner (disabled)
///   * unavailable:  the action alone, disabled, with "Prices unavailable — Try again"
///   * pending:      "Waiting for approval" (disabled)
///   * working:      the action with a spinner (disabled)
///   * owned:        "Owned" / "Current plan" (disabled, outlined)
struct PurchaseButtonModel: Equatable {
    enum Style: Equatable { case primary, owned }

    let label: String
    let isEnabled: Bool
    let showsSpinner: Bool
    let showsPricesUnavailable: Bool
    let style: Style

    static let separator = " · "

    static func make(action: String,
                     price: PurchasePresentation.PriceState,
                     priceText: String? = nil,
                     ownedLabel: String? = nil,
                     pending: Bool = false,
                     working: Bool = false,
                     isLoadingProducts: Bool = false) -> PurchaseButtonModel {
        if let ownedLabel {
            return PurchaseButtonModel(label: ownedLabel, isEnabled: false, showsSpinner: false,
                                       showsPricesUnavailable: false, style: .owned)
        }
        if pending {
            return PurchaseButtonModel(label: PurchasePresentation.waitingForApprovalText, isEnabled: false,
                                       showsSpinner: false, showsPricesUnavailable: false, style: .primary)
        }
        switch price {
        case .ready(let displayPrice):
            let text = (priceText?.isEmpty == false) ? priceText! : displayPrice
            return PurchaseButtonModel(label: "\(action)\(separator)\(text)",
                                       isEnabled: !working && !isLoadingProducts,
                                       showsSpinner: working, showsPricesUnavailable: false, style: .primary)
        case .loading:
            return PurchaseButtonModel(label: PurchasePresentation.loadingPriceText, isEnabled: false,
                                       showsSpinner: true, showsPricesUnavailable: false, style: .primary)
        case .unavailable:
            return PurchaseButtonModel(label: action, isEnabled: false, showsSpinner: working,
                                       showsPricesUnavailable: !working, style: .primary)
        }
    }
}

// MARK: - DEBUG store scenarios

#if DEBUG
/// DEBUG-only: `-econDebugStore eligible|ineligible|subscribed|failed` makes
/// `PurchaseManager` report fixed US offers (the `EconByte.storekit` prices)
/// without StoreKit, so the paywall states can be rendered and UI-tested on a
/// simulator where `xcodebuild` does not attach the StoreKit configuration
/// (Phase 8/11 proof). Compiled out of Release: a shipped build only ever shows
/// StoreKit's own prices.
enum DebugStoreScenario: String {
    case eligible, ineligible, subscribed, failed

    static let argument = "-econDebugStore"

    static var current: DebugStoreScenario? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: argument), i + 1 < args.count else { return nil }
        return DebugStoreScenario(rawValue: args[i + 1])
    }

    var trialEligible: Bool? {
        switch self {
        case .eligible: return true
        case .ineligible, .subscribed: return false
        case .failed: return nil
        }
    }

    func offer(for id: PurchaseManager.ProductID) -> StoreOffer? {
        guard self != .failed else { return nil }
        let usd = Decimal.FormatStyle.Currency(code: "USD", locale: Locale(identifier: "en_US"))
        func make(_ cents: Int, _ period: BillingTerm? = nil, trial: BillingTerm? = nil) -> StoreOffer {
            let price = Decimal(cents) / 100
            return StoreOffer(id: id, displayPrice: price.formatted(usd), price: price,
                              priceFormatStyle: usd, period: period, freeTrial: trial)
        }
        switch id {
        case .proAnnual: return make(3999, BillingTerm(unit: .year, value: 1), trial: BillingTerm(unit: .week, value: 1))
        case .proMonthly: return make(999, BillingTerm(unit: .month, value: 1))
        case .packBundle: return make(599)
        case .unlockAll: return make(299)
        case .removeAds: return make(199)
        default: return make(199)
        }
    }
}
#endif
