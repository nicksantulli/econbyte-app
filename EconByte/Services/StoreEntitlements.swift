import Foundation
import StoreKit

// MARK: - Store seam (Phase 11 ads + IAP audit, 2026-09-14)
//
// Every access decision `PurchaseManager` makes is a pure function of two
// snapshot lists: the transactions StoreKit reports in
// `Transaction.currentEntitlements`, and — once the subscription products have
// loaded — the subscription group's `Product.SubscriptionInfo.Status` values.
// StoreKit's own types cannot be constructed in a unit test, so they are copied
// into the value types below at the one boundary that touches StoreKit
// (`PurchaseManager`), and every rule here is tested against fakes in
// `StoreEntitlementsTests`. The StoreKit side of the boundary is exercised
// against `EconByte.storekit` with `SKTestSession` in `StoreKitSessionTests`.
//
// Rules (audit doc `docs/audit/2026-09-14-ads-iap-audit.md`, IAP table):
//   * Only a VERIFIED, UNREVOKED transaction grants anything. A refund or a
//     revocation (`revocationDate`) removes access on the next refresh.
//   * An upgraded-away subscription transaction (`isUpgraded`) grants nothing;
//     its replacement does.
//   * Pro is active while the group status is `subscribed`, `inGracePeriod` or
//     `inBillingRetryPeriod` (Owner brief: grace and billing retry keep access)
//     — or while a current, unexpired entitlement transaction exists, so an
//     offline launch without statuses still opens Pro.
//   * Family-shared transactions grant exactly like purchased ones (every
//     EconByte product is `familyShareable: false` today; if the Owner turns it
//     on in App Store Connect nothing here has to change).
//   * Precedence: Pro ⇒ core topics + every pack + no ads; Unlock All ⇒ core
//     topics only (D18); a pack ⇒ that pack; Remove Ads ⇒ no ads.
//   * UserDefaults mirrors never grant access (see `PurchaseManager`).

enum StoreOwnership: String, Equatable {
    case purchased
    case familyShared
}

struct StoreTransactionSnapshot: Equatable {
    var productID: String
    var isVerified: Bool
    var revocationDate: Date? = nil
    var expirationDate: Date? = nil
    var isUpgraded: Bool = false
    var ownership: StoreOwnership = .purchased
}

enum StoreSubscriptionState: String, Equatable {
    case subscribed
    case expired
    case inBillingRetryPeriod
    case inGracePeriod
    case revoked
    case unknown
}

struct StoreSubscriptionStatusSnapshot: Equatable {
    var state: StoreSubscriptionState
    var productID: String
    /// Both the status's transaction and its renewal info verified.
    var isVerified: Bool
    var expirationDate: Date? = nil
    var revocationDate: Date? = nil
    /// `nil` when the renewal info did not verify.
    var willAutoRenew: Bool? = nil
    /// The product the subscription renews into (a pending plan change when it
    /// differs from `productID`).
    var autoRenewProductID: String? = nil
    var gracePeriodExpirationDate: Date? = nil
    var ownership: StoreOwnership = .purchased
}

/// Why a Pro subscriber has access right now.
enum ProAccessState: String, Equatable {
    case active
    /// Apple could not charge the renewal and the grace period is running:
    /// the subscriber keeps access and should update their payment method.
    case gracePeriod
    /// Apple is still retrying the charge after the period ended. EconByte keeps
    /// access (Owner brief) and asks the subscriber to fix the payment.
    case billingRetry

    var hasBillingIssue: Bool { self != .active }
}

struct ProEntitlement: Equatable {
    var productID: String
    var state: ProAccessState
    var expirationDate: Date?
    /// `nil` when no verified renewal info was available (offline launch).
    var willAutoRenew: Bool?
    var renewalProductID: String?
    var ownership: StoreOwnership = .purchased

    /// The plan the subscription switches to at renewal, when that is a
    /// different plan (monthly ↔ annual downgrade/crossgrade scheduled).
    var pendingPlanChangeProductID: String? {
        guard willAutoRenew != false, let renewalProductID, renewalProductID != productID else { return nil }
        return renewalProductID
    }
}

/// The product identifiers the resolver sorts transactions into.
struct StoreCatalogIDs: Equatable {
    var unlockAll: String
    var removeAds: String
    var packs: Set<String>
    var subscriptions: Set<String>
}

struct ResolvedEntitlements: Equatable {
    var unlockAll = false
    var removeAds = false
    var packProductIDs: Set<String> = []
    var pro: ProEntitlement?
    /// Non-consumables this Apple ID holds through Family Sharing.
    var familySharedProductIDs: Set<String> = []

    var isProActive: Bool { pro != nil }
    /// Unlock All ∨ Pro (D18, D19).
    var coreTopicsUnlocked: Bool { unlockAll || isProActive }
    /// Remove Ads ∨ Pro.
    var adsSuppressed: Bool { removeAds || isProActive }
    /// The pack bought outright ∨ Pro. Unlock All never opens a pack (D18).
    func hasAccess(packProductID: String) -> Bool {
        packProductIDs.contains(packProductID) || isProActive
    }
    var ownsAnything: Bool { unlockAll || removeAds || !packProductIDs.isEmpty || isProActive }
}

enum EntitlementResolver {

    static func resolve(transactions: [StoreTransactionSnapshot],
                        statuses: [StoreSubscriptionStatusSnapshot]?,
                        catalog: StoreCatalogIDs,
                        now: Date) -> ResolvedEntitlements {
        var resolved = ResolvedEntitlements()

        // One-time products.
        for transaction in transactions where transaction.isVerified && transaction.revocationDate == nil {
            let id = transaction.productID
            let isNonConsumable: Bool
            switch id {
            case catalog.unlockAll: resolved.unlockAll = true; isNonConsumable = true
            case catalog.removeAds: resolved.removeAds = true; isNonConsumable = true
            case let pack where catalog.packs.contains(pack):
                resolved.packProductIDs.insert(pack); isNonConsumable = true
            default: isNonConsumable = false
            }
            if isNonConsumable, transaction.ownership == .familyShared {
                resolved.familySharedProductIDs.insert(id)
            }
        }

        // Verified statuses by product, for the state label and renewal info.
        let usableStatuses = (statuses ?? []).filter {
            $0.isVerified && catalog.subscriptions.contains($0.productID)
        }
        let statusByProduct = Dictionary(usableStatuses.map { ($0.productID, $0) },
                                         uniquingKeysWith: { first, _ in first })

        var candidates: [ProEntitlement] = []

        // Current entitlement transactions (offline-safe path).
        for transaction in transactions
        where transaction.isVerified && transaction.revocationDate == nil && !transaction.isUpgraded
            && catalog.subscriptions.contains(transaction.productID) {
            if let expires = transaction.expirationDate, expires <= now { continue }
            let status = statusByProduct[transaction.productID]
            if status?.state == .revoked { continue }
            var state = ProAccessState.active
            switch status?.state {
            case .inGracePeriod?: state = .gracePeriod
            case .inBillingRetryPeriod?: state = .billingRetry
            default: break
            }
            candidates.append(ProEntitlement(productID: transaction.productID,
                                             state: state,
                                             expirationDate: transaction.expirationDate,
                                             willAutoRenew: status?.willAutoRenew,
                                             renewalProductID: status?.autoRenewProductID,
                                             ownership: transaction.ownership))
        }

        // Group statuses: billing retry is not in `currentEntitlements`, so it
        // is only visible here.
        for status in usableStatuses where status.revocationDate == nil {
            let state: ProAccessState
            switch status.state {
            case .subscribed: state = .active
            case .inGracePeriod: state = .gracePeriod
            case .inBillingRetryPeriod: state = .billingRetry
            case .expired, .revoked, .unknown: continue
            }
            candidates.append(ProEntitlement(productID: status.productID,
                                             state: state,
                                             expirationDate: status.expirationDate,
                                             willAutoRenew: status.willAutoRenew,
                                             renewalProductID: status.autoRenewProductID,
                                             ownership: status.ownership))
        }

        resolved.pro = candidates.min { lhs, rhs in
            let l = rank(lhs.state), r = rank(rhs.state)
            if l != r { return l < r }
            // Same state: the later expiration is the current period.
            return (lhs.expirationDate ?? .distantFuture) > (rhs.expirationDate ?? .distantFuture)
        }
        return resolved
    }

    private static func rank(_ state: ProAccessState) -> Int {
        switch state {
        case .active: return 0
        case .gracePeriod: return 1
        case .billingRetry: return 2
        }
    }
}

// MARK: - Failure copy

/// Why a purchase or restore did not complete, reduced from StoreKit's errors
/// to something a reader can act on. StoreKit's `localizedDescription` is never
/// shown: it is third-party text, often technical, and sometimes empty.
enum PurchaseFailureReason: String, Equatable, CaseIterable {
    case network
    case notAllowed
    case notAvailableInStorefront
    case productUnavailable
    case verification
    case unknown

    /// `nil` means the reader cancelled — not a failure, nothing to show.
    static func classify(_ error: Error) -> PurchaseFailureReason? {
        if let storeKit = error as? StoreKitError {
            switch storeKit {
            case .userCancelled: return nil
            case .networkError: return .network
            case .notAvailableInStorefront: return .notAvailableInStorefront
            case .notEntitled: return .notAllowed
            case .systemError, .unknown: return .unknown
            @unknown default: return .unknown
            }
        }
        if let purchase = error as? Product.PurchaseError {
            switch purchase {
            case .purchaseNotAllowed: return .notAllowed
            case .productUnavailable: return .productUnavailable
            default: return .unknown
            }
        }
        if error is PurchaseManager.StoreError { return .verification }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain { return .network }
        return .unknown
    }

    var message: String {
        switch self {
        case .network:
            return "We couldn't reach the App Store. Check your connection and try again."
        case .notAllowed:
            return "Purchases aren't allowed on this device. Check Screen Time → Content & Privacy Restrictions."
        case .notAvailableInStorefront:
            return "This item isn't available in your country's App Store."
        case .productUnavailable:
            return "This item isn't available right now. Please try again later."
        case .verification:
            return "The App Store couldn't verify this purchase, so it wasn't unlocked. If you were charged, tap Restore Purchases or contact support."
        case .unknown:
            return "The purchase couldn't be completed. Please try again."
        }
    }
}

/// The one alert every purchase surface shows for a result, so the paywalls,
/// the pack offers and Settings can never disagree about what happened.
enum PurchaseAlertCopy {
    enum Kind: Equatable { case purchase, restore }

    struct Alert: Equatable {
        let title: String
        let message: String
    }

    /// `accessGranted`: whether the thing the reader was buying is now
    /// readable (used only for a `.success` purchase that StoreKit has not
    /// reflected yet).
    static func alert(for result: PurchaseManager.PurchaseResult,
                      kind: Kind,
                      accessGranted: Bool) -> Alert? {
        switch (result, kind) {
        case (.success, .purchase):
            return accessGranted ? nil : Alert(
                title: "Purchase processing",
                message: "Your purchase is being confirmed. If it stays locked, tap Restore Purchases.")
        case (.success, .restore):
            return Alert(title: "Purchases restored",
                         message: "Everything bought with this Apple ID is unlocked again.")
        case (.nothingToRestore, _):
            return Alert(title: "Nothing to restore",
                         message: "No previous purchases were found for this Apple ID.")
        case (.cancelled, _):
            return nil
        case (.pending, _):
            return Alert(title: "Waiting for approval",
                         message: "This purchase needs approval, for example from a family organizer. You'll get access as soon as it's approved.")
        case (.productUnavailable, _):
            return Alert(title: "Purchase unavailable",
                         message: PurchaseFailureReason.productUnavailable.message)
        case (.failed(let message), .purchase):
            return Alert(title: "Purchase didn't go through", message: message)
        case (.failed(let message), .restore):
            return Alert(title: "Restore didn't finish", message: message)
        }
    }
}

// MARK: - Subscription status copy

struct ProStatusRow: Equatable, Identifiable {
    let title: String
    let value: String
    var id: String { title }
}

enum ProStatusCopy {

    static func planName(_ productID: String?) -> String {
        productID == PurchaseManager.ProductID.proAnnual.rawValue ? "Yearly" : "Monthly"
    }

    /// Settings and the Pro tab show the same rows: plan, a billing problem if
    /// there is one, when it renews or ends, a scheduled plan change, and
    /// Family Sharing when it applies.
    static func rows(for pro: ProEntitlement,
                     formatDate: (Date) -> String = { $0.formatted(date: .abbreviated, time: .omitted) }) -> [ProStatusRow] {
        var rows = [ProStatusRow(title: "Plan", value: planName(pro.productID))]
        if pro.state.hasBillingIssue {
            rows.append(ProStatusRow(title: "Status", value: "Payment issue"))
        }
        if let date = pro.expirationDate {
            switch (pro.state, pro.willAutoRenew) {
            case (.billingRetry, _):
                break // the period already ended; Apple is retrying the charge
            case (_, true?):
                rows.append(ProStatusRow(title: "Renews", value: formatDate(date)))
            case (_, false?):
                rows.append(ProStatusRow(title: "Ends", value: formatDate(date)))
            case (_, nil):
                rows.append(ProStatusRow(title: "Current period ends", value: formatDate(date)))
            }
        }
        if let next = pro.pendingPlanChangeProductID {
            rows.append(ProStatusRow(title: "Switches to", value: planName(next)))
        }
        if pro.ownership == .familyShared {
            rows.append(ProStatusRow(title: "Shared by", value: "Family Sharing"))
        }
        return rows
    }

    /// One short sentence.
    static func footer(for pro: ProEntitlement?) -> String {
        guard let pro else { return "Courses, the Daily Brief, every pack, and no ads." }
        if pro.state.hasBillingIssue {
            return "Update your payment method in Manage Subscription to keep Pro."
        }
        if pro.willAutoRenew == false {
            return "Pro stays on until the end date; resubscribe anytime."
        }
        return "Change plan or cancel anytime in Manage Subscription."
    }
}
