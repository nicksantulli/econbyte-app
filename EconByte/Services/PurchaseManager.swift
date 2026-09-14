import StoreKit
import SwiftUI

/// StoreKit 2 purchase manager for EconByte's two non-consumable IAPs.
///
/// Products (see Dudley vault DUD-186 §5 / EconByte runbook §2e; the Owner
/// requested these split into two distinct $0.99 unlocks):
///   • `com.nsantulli.econbyte.unlockall` — unlocks every locked topic
///   • `com.nsantulli.econbyte.removeads`  — hides all interstitial ads
///
/// Entitlements are read from `Transaction.currentEntitlements` (the source of
/// truth, restored automatically across devices via the Apple ID) and mirrored
/// into UserDefaults so gating decisions are synchronous on cold launch before
/// StoreKit finishes its async refresh.
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
        /// Topic packs (1.1.3, created in ASC 2026-09-14). Each unlocks its own
        /// four topics and nothing else; Unlock All does not include them (D18).
        case packMarkets  = "com.nsantulli.econbyte.pack.markets"
        case packPersonal = "com.nsantulli.econbyte.pack.personal"

        static let packs: [ProductID] = [.packMarkets, .packPersonal]
        var isPack: Bool { Self.packs.contains(self) }

        /// The bucketed family name analytics is allowed to see. The product id
        /// itself is a prohibited property — a StoreKit identifier never leaves.
        var family: EBProductFamily {
            switch self {
            case .unlockAll:    return .unlockAll
            case .removeAds:    return .removeAds
            case .packMarkets:  return .packMarkets
            case .packPersonal: return .packPersonal
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
    @Published private(set) var products: [Product] = []
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var productsLoadError: String?

    private let unlockAllKey = "iap.unlockAll.purchased"
    private let removeAdsKey  = "iap.removeAds.purchased"
    private let ownedPacksKey = "iap.packs.purchased"

    private var updates: Task<Void, Never>?
    /// Restore is single-flight: `AppStore.sync()` is only ever called from an
    /// explicit user action, and never twice concurrently (design section 8).
    private var restoreTask: Task<PurchaseResult, Never>?

    /// Raised on an unverified transaction so the caller can record a bounded
    /// diagnostic code. Never carries transaction data.
    var onDiagnostic: ((EconDiagnosticCode) -> Void)?

    var productsReady: Bool { !products.isEmpty }

    /// True only for a known pack product with a verified entitlement.
    func isPackPurchased(productID: String) -> Bool {
        ownedPackProductIDs.contains(productID)
    }

    private init() {
        // Synchronous seed from cache so the first render gates correctly.
        isUnlockAllPurchased = UserDefaults.standard.bool(forKey: unlockAllKey)
        isRemoveAdsPurchased  = UserDefaults.standard.bool(forKey: removeAdsKey)
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

    // MARK: - Purchase

    /// `entryPoint` is where the user tapped buy, so the funnel can be read
    /// without ever learning what they bought beyond its family. Emission lives
    /// here rather than at the two call sites so a future third buy button
    /// cannot ship unmeasured.
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
                if isUnlockAllPurchased || isRemoveAdsPurchased || !ownedPackProductIDs.isEmpty {
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
        let packIDs = Set(ProductID.packs.map(\.rawValue))
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard transaction.revocationDate == nil else { continue }
            switch transaction.productID {
            case ProductID.unlockAll.rawValue: unlockAll = true
            case ProductID.removeAds.rawValue:  removeAds = true
            case let id where packIDs.contains(id): packs.insert(id)
            default: break
            }
        }
        isUnlockAllPurchased = unlockAll
        isRemoveAdsPurchased  = removeAds
        ownedPackProductIDs   = packs
        UserDefaults.standard.set(unlockAll, forKey: unlockAllKey)
        UserDefaults.standard.set(removeAds, forKey: removeAdsKey)
        UserDefaults.standard.set(packs.sorted(), forKey: ownedPacksKey)
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

#if DEBUG
extension PurchaseManager {
    /// DEBUG-only: flip entitlements without a real StoreKit purchase, so the
    /// gated/unlocked experience is testable in the plain Simulator (where the
    /// local .storekit config doesn't attach outside an Xcode scheme run).
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
}
#endif
