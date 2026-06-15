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

    @Published private(set) var isUnlockAllPurchased = false
    @Published private(set) var isRemoveAdsPurchased = false
    @Published private(set) var products: [Product] = []

    private let unlockAllKey = "iap.unlockAll.purchased"
    private let removeAdsKey  = "iap.removeAds.purchased"

    private var updates: Task<Void, Never>?

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
        do {
            products = try await Product.products(for: ProductID.allCases.map(\.rawValue))
        } catch {
            NSLog("[PurchaseManager] product load failed: \(error)")
        }
    }

    // MARK: - Purchase

    @discardableResult
    func purchase(_ id: ProductID) async -> Bool {
        if products.isEmpty { await loadProducts() }
        guard let product = product(for: id) else {
            NSLog("[PurchaseManager] no product for \(id.rawValue)")
            return false
        }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await updatePurchasedProducts()
                await transaction.finish()
                return true
            case .userCancelled, .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            NSLog("[PurchaseManager] purchase failed: \(error)")
            return false
        }
    }

    // MARK: - Restore

    func restorePurchases() async {
        try? await AppStore.sync()
        await updatePurchasedProducts()
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
