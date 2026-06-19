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
@MainActor
final class PurchaseManager: ObservableObject {
    static let shared = PurchaseManager()

    enum ProductID: String, CaseIterable {
        case unlockAll = "com.nsantulli.econbyte.unlockall"
        case removeAds  = "com.nsantulli.econbyte.removeads"
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
    @Published private(set) var products: [Product] = []
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var productsLoadError: String?

    private let unlockAllKey = "iap.unlockAll.purchased"
    private let removeAdsKey  = "iap.removeAds.purchased"

    private var updates: Task<Void, Never>?

    var productsReady: Bool { !products.isEmpty }

    private init() {
        // Synchronous seed from cache so the first render gates correctly.
        isUnlockAllPurchased = UserDefaults.standard.bool(forKey: unlockAllKey)
        isRemoveAdsPurchased  = UserDefaults.standard.bool(forKey: removeAdsKey)
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
            } else {
                NSLog("[PurchaseManager] loaded \(loaded.count) product(s): \(loaded.map(\.id).joined(separator: ", "))")
            }
        } catch {
            products = []
            productsLoadError = error.localizedDescription
            NSLog("[PurchaseManager] product load failed: \(error)")
        }
    }

    // MARK: - Purchase

    @discardableResult
    func purchase(_ id: ProductID) async -> PurchaseResult {
        if products.isEmpty { await loadProducts() }
        guard let product = product(for: id) else {
            NSLog("[PurchaseManager] no product for \(id.rawValue)")
            return .productUnavailable
        }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await updatePurchasedProducts()
                await transaction.finish()
                return .success
            case .userCancelled:
                return .cancelled
            case .pending:
                return .pending
            @unknown default:
                return .failed("Purchase could not be completed.")
            }
        } catch {
            NSLog("[PurchaseManager] purchase failed: \(error)")
            return .failed(error.localizedDescription)
        }
    }

    // MARK: - Restore

    func restorePurchases() async -> PurchaseResult {
        do {
            try await AppStore.sync()
            await updatePurchasedProducts()
            if isUnlockAllPurchased || isRemoveAdsPurchased {
                return .success
            }
            return .failed("No previous purchases were found for this Apple ID.")
        } catch {
            NSLog("[PurchaseManager] restore failed: \(error)")
            return .failed(error.localizedDescription)
        }
    }

    // MARK: - Entitlements

    func updatePurchasedProducts() async {
        var unlockAll = false
        var removeAds = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard transaction.revocationDate == nil else { continue }
            switch transaction.productID {
            case ProductID.unlockAll.rawValue: unlockAll = true
            case ProductID.removeAds.rawValue:  removeAds = true
            default: break
            }
        }
        isUnlockAllPurchased = unlockAll
        isRemoveAdsPurchased  = removeAds
        UserDefaults.standard.set(unlockAll, forKey: unlockAllKey)
        UserDefaults.standard.set(removeAds, forKey: removeAdsKey)
    }

    // MARK: - Transaction listener

    private func listenForTransactions() async {
        for await result in Transaction.updates {
            guard case .verified(let transaction) = result else { continue }
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
}
#endif
