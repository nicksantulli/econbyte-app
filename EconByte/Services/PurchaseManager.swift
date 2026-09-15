import StoreKit
import SwiftUI

/// StoreKit 2 purchase manager for EconByte's products.
///
/// Non-consumables (all APPROVED or READY_TO_SUBMIT in App Store Connect):
///   • `com.nsantulli.econbyte.unlockall` — unlocks every locked core topic
///   • `com.nsantulli.econbyte.removeads`  — hides all ads
///   • `com.nsantulli.econbyte.pack.<packID>` — one topic pack each (D18)
///
/// Auto-renewable subscriptions (1.1.4, subscription group "EconByte Pro";
/// exist only in `EconByte.storekit` until the Owner creates them in ASC — the
/// ids below are the contract, so no code changes when that happens):
///   • `com.nsantulli.econbyte.pro.monthly` — $4.99 / month, 7-day free trial
///   • `com.nsantulli.econbyte.pro.annual`  — $29.99 / year, 7-day free trial
///
/// Entitlements are read from `Transaction.currentEntitlements` (the source of
/// truth, restored automatically across devices via the Apple ID) and mirrored
/// into UserDefaults so gating decisions are synchronous on cold launch before
/// StoreKit finishes its async refresh. For the subscription, StoreKit's
/// current-entitlements stream already accounts for grace periods and billing
/// retry — a transaction that is present and unrevoked means Pro is active.
/// How a purchase control reads while StoreKit has not delivered a price.
///
/// There is no fallback price literal anywhere in the UI. A hardcoded "$0.99" is
/// wrong in every non-US storefront, wrong the moment the tier changes, and
/// wrong when the product is simply unavailable — and it is exactly the shape
/// App Review has objected to on a Dudley build before. When there is no price
/// there is no price shown, and the control that would spend money is disabled.
enum PurchasePresentation {

    /// Shown in place of a price that StoreKit has not supplied. Deliberately
    /// not a currency string: it must be impossible to read as an amount.
    static let unavailablePrice = "—"

    static func priceText(_ displayPrice: String?) -> String {
        guard let displayPrice, !displayPrice.isEmpty else { return unavailablePrice }
        return displayPrice
    }

    /// A buy control may only be live when there is a real, StoreKit-formatted
    /// price to charge and nothing else is in flight.
    static func canPurchase(displayPrice: String?, isWorking: Bool, isLoading: Bool) -> Bool {
        guard let displayPrice, !displayPrice.isEmpty else { return false }
        return !isWorking && !isLoading
    }
}

@MainActor
final class PurchaseManager: ObservableObject {
    static let shared = PurchaseManager()

    enum ProductID: String, CaseIterable {
        case unlockAll = "com.nsantulli.econbyte.unlockall"
        case removeAds  = "com.nsantulli.econbyte.removeads"
        /// Topic packs. Each unlocks its own four topics and nothing else;
        /// Unlock All does not include them (D18). Pro does (D19).
        case packMarkets  = "com.nsantulli.econbyte.pack.markets"
        case packPersonal = "com.nsantulli.econbyte.pack.personal"
        case packHistory  = "com.nsantulli.econbyte.pack.history"
        case packWorld    = "com.nsantulli.econbyte.pack.world"
        case packSystems  = "com.nsantulli.econbyte.pack.systems"
        case packPersonalFinance = "com.nsantulli.econbyte.pack.personalfinance"
        /// EconByte Pro (1.1.4). One subscription group, two durations.
        case proMonthly = "com.nsantulli.econbyte.pro.monthly"
        case proAnnual  = "com.nsantulli.econbyte.pro.annual"

        static let packs: [ProductID] = [.packMarkets, .packPersonal, .packHistory,
                                         .packWorld, .packSystems, .packPersonalFinance]
        static let subscriptions: [ProductID] = [.proMonthly, .proAnnual]
        var isPack: Bool { Self.packs.contains(self) }
        var isSubscription: Bool { Self.subscriptions.contains(self) }

        /// The bucketed family name analytics is allowed to see. The product id
        /// itself is a prohibited property — a StoreKit identifier never leaves.
        var family: EBProductFamily {
            switch self {
            case .unlockAll:    return .unlockAll
            case .removeAds:    return .removeAds
            case .packMarkets:  return .packMarkets
            case .packPersonal: return .packPersonal
            case .packHistory:  return .packHistory
            case .packWorld:    return .packWorld
            case .packSystems:  return .packSystems
            case .packPersonalFinance: return .packPersonalFinance
            case .proMonthly:   return .proMonthly
            case .proAnnual:    return .proAnnual
            }
        }
    }

    enum PurchaseResult: Equatable {
        case success
        case cancelled
        case pending
        case productUnavailable
        case failed(String)
    }

    @Published private(set) var isUnlockAllPurchased = false
    @Published private(set) var isRemoveAdsPurchased = false
    /// Pack product ids with a verified, unrevoked entitlement. Mirrored to
    /// UserDefaults like the other two so cold-launch gating is synchronous.
    @Published private(set) var ownedPackProductIDs: Set<String> = []
    /// EconByte Pro: a verified, unrevoked auto-renewable transaction is in
    /// `Transaction.currentEntitlements` (that stream already excludes expired
    /// subscriptions and includes grace/billing-retry periods).
    @Published private(set) var isProActive = false
    /// The current period's expiration, when StoreKit reports one. Display only.
    @Published private(set) var proExpiration: Date?
    /// Which Pro product is active (monthly or annual), for Settings.
    @Published private(set) var proProductID: String?
    /// Whether this Apple ID may still take the introductory free trial. `nil`
    /// until StoreKit has answered; the paywall shows the trial line only on a
    /// definite `true` (App Review 3.1.2: never advertise a trial to someone
    /// who cannot get it).
    @Published private(set) var isEligibleForTrial: Bool?
    @Published private(set) var products: [Product] = []
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var productsLoadError: String?

    private let unlockAllKey = "iap.unlockAll.purchased"
    private let removeAdsKey  = "iap.removeAds.purchased"
    private let ownedPacksKey = "iap.packs.purchased"
    private let proActiveKey  = "iap.pro.active"

    private var updates: Task<Void, Never>?
    /// Restore is single-flight: `AppStore.sync()` is only ever called from an
    /// explicit user action, and never twice concurrently (design section 8).
    private var restoreTask: Task<PurchaseResult, Never>?

    /// Raised on an unverified transaction so the caller can record a bounded
    /// diagnostic code. Never carries transaction data.
    var onDiagnostic: ((EconDiagnosticCode) -> Void)?

    var productsReady: Bool { !products.isEmpty }

    /// True only for a known pack product with a verified entitlement of its
    /// own. Pro is NOT consulted here — see `hasAccess(packProductID:)`.
    func isPackPurchased(productID: String) -> Bool {
        ownedPackProductIDs.contains(productID)
    }

    /// Access to a pack: owned outright ∨ Pro active (D19). A pack bought
    /// outright stays owned after Pro lapses; Pro access ends with it.
    func hasAccess(packProductID: String) -> Bool {
        isPackPurchased(productID: packProductID) || isProActive
    }

    /// The core curriculum: Unlock All ∨ Pro (D19).
    var coreTopicsUnlocked: Bool { isUnlockAllPurchased || isProActive }

    /// Ads are off for a Remove Ads owner and for an active Pro subscriber.
    var adsSuppressed: Bool { isRemoveAdsPurchased || isProActive }

    #if DEBUG
    /// DEBUG-only: `-econDebugPro` (or the Settings debug toggle) reports Pro as
    /// active regardless of StoreKit, so the Pro surfaces can be exercised in a
    /// plain Simulator run or on a device installed with `devicectl`, where the
    /// local `.storekit` configuration is not attached. Compiled out of Release.
    private var debugForcedPro = ProcessInfo.processInfo.arguments.contains("-econDebugPro")
    #endif

    private init() {
        // Synchronous seed from cache so the first render gates correctly.
        isUnlockAllPurchased = UserDefaults.standard.bool(forKey: unlockAllKey)
        isRemoveAdsPurchased  = UserDefaults.standard.bool(forKey: removeAdsKey)
        isProActive = UserDefaults.standard.bool(forKey: proActiveKey)
        #if DEBUG
        if debugForcedPro { isProActive = true }
        #endif
        // Only ids the catalog still sells are honoured from the cache.
        let cachedPacks = Set(UserDefaults.standard.stringArray(forKey: ownedPacksKey) ?? [])
        ownedPackProductIDs = cachedPacks.intersection(ProductID.packs.map(\.rawValue))
        updates = Task { [weak self] in await self?.listenForTransactions() }
        Task { [weak self] in
            await self?.loadProducts()
            await self?.updatePurchasedProducts()
        }
    }

    deinit { updates?.cancel() }

    func product(for id: ProductID) -> Product? {
        products.first { $0.id == id.rawValue }
    }

    // MARK: - Load

    func loadProducts() async {
        isLoadingProducts = true
        productsLoadError = nil
        defer { isLoadingProducts = false }

        do {
            let loaded = try await Product.products(for: ProductID.allCases.map(\.rawValue))
            products = loaded
            if loaded.isEmpty {
                productsLoadError = "Store products are not available right now. Check your connection and try again."
                NSLog("[PurchaseManager] product load returned empty set")
                EBEvents.productsLoaded(outcome: .unavailable)
            } else {
                NSLog("[PurchaseManager] loaded \(loaded.count) product(s): \(loaded.map(\.id).joined(separator: ", "))")
                EBEvents.productsLoaded(outcome: .loaded)
                await refreshTrialEligibility()
            }
        } catch {
            products = []
            productsLoadError = error.localizedDescription
            NSLog("[PurchaseManager] product load failed: \(error)")
            // Outcome only — never `error.localizedDescription`, which is a
            // third-party string and a prohibited property.
            EBEvents.productsLoaded(outcome: .failed)
        }
    }

    /// Intro-offer eligibility is per subscription GROUP, so asking either
    /// product answers for both. Stays `nil` if no subscription product loaded
    /// (for example, before the ASC products exist) — then no trial is shown.
    func refreshTrialEligibility() async {
        guard let subscription = ProductID.subscriptions.compactMap({ product(for: $0) }).first,
              let info = subscription.subscription else {
            isEligibleForTrial = nil
            return
        }
        isEligibleForTrial = await info.isEligibleForIntroOffer
    }

    // MARK: - Purchase

    /// `entryPoint` is where the user tapped buy, so the funnel can be read
    /// without ever learning what they bought beyond its family. Emission lives
    /// here rather than at the call sites so a future buy button cannot ship
    /// unmeasured. A subscription purchase additionally records whether it
    /// started as a free trial or a paid period (`pro_trial_started_v1` /
    /// `pro_subscribed_v1`), read from the transaction's own offer type.
    @discardableResult
    func purchase(_ id: ProductID, from entryPoint: EBEntryPoint) async -> PurchaseResult {
        EBEvents.purchaseStarted(family: id.family, entryPoint: entryPoint)
        if products.isEmpty { await loadProducts() }
        guard let product = product(for: id) else {
            NSLog("[PurchaseManager] no product for \(id.rawValue)")
            EBEvents.purchaseFinished(family: id.family, outcome: .unavailable)
            return .productUnavailable
        }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await updatePurchasedProducts()
                await transaction.finish()
                EBEvents.purchaseFinished(family: id.family, outcome: .completed)
                if id.isSubscription {
                    if Self.isIntroductoryTrial(transaction) {
                        EBEvents.proTrialStarted(family: id.family)
                    } else {
                        EBEvents.proSubscribed(family: id.family)
                    }
                    await refreshTrialEligibility()
                }
                return .success
            case .userCancelled:
                EBEvents.purchaseFinished(family: id.family, outcome: .cancelled)
                return .cancelled
            case .pending:
                EBEvents.purchaseFinished(family: id.family, outcome: .pending)
                return .pending
            @unknown default:
                EBEvents.purchaseFinished(family: id.family, outcome: .failed)
                return .failed("Purchase could not be completed.")
            }
        } catch {
            NSLog("[PurchaseManager] purchase failed: \(error)")
            EBEvents.purchaseFinished(family: id.family, outcome: .failed)
            return .failed(error.localizedDescription)
        }
    }

    /// Whether a subscription transaction began as the introductory free trial.
    /// `offer` replaced `offerType` in iOS 17.2; both are consulted so the
    /// answer is the same on the 16.6 deployment floor.
    static func isIntroductoryTrial(_ transaction: StoreKit.Transaction) -> Bool {
        if #available(iOS 17.2, *) {
            return transaction.offer?.type == .introductory
        }
        return transaction.offerType == .introductory
    }

    // MARK: - Restore

    /// The three restore outcomes are distinguished HERE, where the branch is
    /// known, rather than by matching on a user-facing message at the call site.
    /// Restore stays single-flight (lineage A, design section 8): `AppStore.sync()`
    /// is only ever called from an explicit user action and never twice
    /// concurrently, so a second tap joins the first rather than starting a
    /// second sync — and therefore does not emit a second outcome either.
    func restorePurchases(from entryPoint: EBEntryPoint) async -> PurchaseResult {
        if let inFlight = restoreTask { return await inFlight.value }
        let task = Task { () -> PurchaseResult in
            do {
                try await AppStore.sync()
                await updatePurchasedProducts()
                if isUnlockAllPurchased || isRemoveAdsPurchased || !ownedPackProductIDs.isEmpty || isProActive {
                    EBEvents.restoreFinished(outcome: .completed, entryPoint: entryPoint)
                    return .success
                }
                EBEvents.restoreFinished(outcome: .nothingToRestore, entryPoint: entryPoint)
                return .failed("No previous purchases were found for this Apple ID.")
            } catch {
                NSLog("[PurchaseManager] restore failed: \(error)")
                onDiagnostic?(.restoreFailed)
                EBEvents.restoreFinished(outcome: .failed, entryPoint: entryPoint)
                return .failed(error.localizedDescription)
            }
        }
        restoreTask = task
        let result = await task.value
        restoreTask = nil
        return result
    }

    // MARK: - Entitlements

    func updatePurchasedProducts() async {
        var unlockAll = false
        var removeAds = false
        var packs = Set<String>()
        var pro = false
        var expiration: Date?
        var proID: String?
        let packIDs = Set(ProductID.packs.map(\.rawValue))
        let subscriptionIDs = Set(ProductID.subscriptions.map(\.rawValue))
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard transaction.revocationDate == nil else { continue }
            switch transaction.productID {
            case ProductID.unlockAll.rawValue: unlockAll = true
            case ProductID.removeAds.rawValue:  removeAds = true
            case let id where packIDs.contains(id): packs.insert(id)
            case let id where subscriptionIDs.contains(id):
                // Belt and braces: the stream should not carry an expired
                // subscription, but a stale expiration date is never honoured.
                if let expires = transaction.expirationDate, expires <= Date() { continue }
                pro = true
                proID = id
                if let expires = transaction.expirationDate {
                    expiration = max(expiration ?? .distantPast, expires)
                }
            default: break
            }
        }
        #if DEBUG
        if debugForcedPro { pro = true; proID = proID ?? ProductID.proMonthly.rawValue }
        #endif
        isUnlockAllPurchased = unlockAll
        isRemoveAdsPurchased  = removeAds
        ownedPackProductIDs   = packs
        isProActive = pro
        proExpiration = pro ? expiration : nil
        proProductID = pro ? proID : nil
        UserDefaults.standard.set(unlockAll, forKey: unlockAllKey)
        UserDefaults.standard.set(removeAds, forKey: removeAdsKey)
        UserDefaults.standard.set(packs.sorted(), forKey: ownedPacksKey)
        UserDefaults.standard.set(pro, forKey: proActiveKey)
    }

    // MARK: - Transaction listener

    private func listenForTransactions() async {
        for await result in Transaction.updates {
            guard case .verified(let transaction) = result else {
                // Unverified transactions never grant an entitlement.
                onDiagnostic?(.transactionUnverified)
                continue
            }
            await updatePurchasedProducts()
            await transaction.finish()
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified: throw StoreError.failedVerification
        case .verified(let value): return value
        }
    }

    enum StoreError: Error { case failedVerification }
}

// MARK: - Subscription presentation

extension PurchaseManager {
    /// Apple's account subscriptions page — the standard "Manage subscription"
    /// destination, which also lets a subscriber cancel.
    static let manageSubscriptionsURL = URL(string: "https://apps.apple.com/account/subscriptions")!
    /// Apple's standard EULA, the Terms of Use every paywall must link to
    /// (App Review 3.1.2) unless the app supplies its own.
    static let termsOfUseURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let privacyPolicyURL = URL(string: "https://dudleyapps.com/privacy")!

    /// The introductory offer StoreKit reports for a subscription product, if
    /// it is a free trial. `nil` when the product has no intro offer or it is
    /// not a free trial — then nothing about a trial is shown.
    func freeTrialPeriod(for id: ProductID) -> Product.SubscriptionPeriod? {
        guard let offer = product(for: id)?.subscription?.introductoryOffer,
              offer.paymentMode == .freeTrial else { return nil }
        return offer.period
    }
}

#if DEBUG
extension PurchaseManager {
    /// DEBUG-only: flip entitlements without a real StoreKit purchase, so the
    /// gated/unlocked experience is testable in the plain Simulator (where the
    /// local .storekit config doesn't attach outside an Xcode scheme run) and
    /// on a device installed with `devicectl` rather than run from Xcode.
    func debugSetUnlockAll(_ value: Bool) {
        isUnlockAllPurchased = value
        UserDefaults.standard.set(value, forKey: unlockAllKey)
    }
    func debugSetRemoveAds(_ value: Bool) {
        isRemoveAdsPurchased = value
        UserDefaults.standard.set(value, forKey: removeAdsKey)
    }
    func debugSetPack(_ id: ProductID, _ value: Bool) {
        guard id.isPack else { return }
        if value { ownedPackProductIDs.insert(id.rawValue) } else { ownedPackProductIDs.remove(id.rawValue) }
        UserDefaults.standard.set(ownedPackProductIDs.sorted(), forKey: ownedPacksKey)
    }
    func debugSetPro(_ value: Bool) {
        debugForcedPro = value
        isProActive = value
        proProductID = value ? ProductID.proMonthly.rawValue : nil
        proExpiration = value ? Date().addingTimeInterval(30 * 24 * 60 * 60) : nil
        UserDefaults.standard.set(value, forKey: proActiveKey)
    }
}
#endif
