import XCTest
import StoreKit
import SwiftUI
@testable import EconByte

/// Phase 11 (ads + IAP audit, 2026-09-14): the purchase state matrix against a
/// protocol-free seam — StoreKit snapshots in, resolved access out — plus the
/// purchase copy every surface shows and the ad provider classification.
///
/// These run everywhere and are deterministic. `StoreKitSessionTests` runs the
/// same transitions through real StoreKit against `EconByte.storekit`.
@MainActor
final class StoreEntitlementsTests: XCTestCase {

    private typealias ID = PurchaseManager.ProductID
    private let catalog = PurchaseManager.ProductID.catalog
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private var day: TimeInterval { 24 * 60 * 60 }

    private func tx(_ id: ID, verified: Bool = true, revoked: Bool = false,
                    expiresIn: TimeInterval? = nil, upgraded: Bool = false,
                    ownership: StoreOwnership = .purchased) -> StoreTransactionSnapshot {
        StoreTransactionSnapshot(productID: id.rawValue, isVerified: verified,
                                 revocationDate: revoked ? now.addingTimeInterval(-60) : nil,
                                 expirationDate: expiresIn.map { now.addingTimeInterval($0) },
                                 isUpgraded: upgraded, ownership: ownership)
    }

    private func status(_ state: StoreSubscriptionState, _ id: ID, verified: Bool = true,
                        expiresIn: TimeInterval? = nil, willAutoRenew: Bool? = true,
                        renewsInto: ID? = nil, revoked: Bool = false) -> StoreSubscriptionStatusSnapshot {
        StoreSubscriptionStatusSnapshot(state: state, productID: id.rawValue, isVerified: verified,
                                        expirationDate: expiresIn.map { now.addingTimeInterval($0) },
                                        revocationDate: revoked ? now.addingTimeInterval(-60) : nil,
                                        willAutoRenew: willAutoRenew,
                                        autoRenewProductID: (renewsInto ?? id).rawValue)
    }

    private func resolve(_ transactions: [StoreTransactionSnapshot],
                         _ statuses: [StoreSubscriptionStatusSnapshot]? = nil) -> ResolvedEntitlements {
        EntitlementResolver.resolve(transactions: transactions, statuses: statuses, catalog: catalog, now: now)
    }

    // MARK: - Purchase, verification, refund

    func testAVerifiedPurchaseGrantsExactlyItsOwnProduct() {
        let packs = resolve([tx(.packMarkets)])
        XCTAssertTrue(packs.hasAccess(packProductID: ID.packMarkets.rawValue))
        XCTAssertFalse(packs.hasAccess(packProductID: ID.packHistory.rawValue))
        XCTAssertFalse(packs.coreTopicsUnlocked)
        XCTAssertFalse(packs.adsSuppressed)
        XCTAssertFalse(packs.isProActive)
    }

    func testAnUnverifiedTransactionNeverGrants() {
        for id in ID.allCases {
            let resolved = resolve([tx(id, verified: false, expiresIn: 30 * day)])
            XCTAssertFalse(resolved.ownsAnything, "\(id) unverified must grant nothing")
        }
    }

    func testARefundOrRevocationRemovesAccess() {
        for id in ID.allCases {
            let resolved = resolve([tx(id, revoked: true, expiresIn: 30 * day)])
            XCTAssertFalse(resolved.ownsAnything, "\(id) revoked must grant nothing")
        }
    }

    // MARK: - Entitlement precedence (D18, D19)

    func testPrecedenceMatrix() {
        let pro = resolve([tx(.proMonthly, expiresIn: 20 * day)])
        XCTAssertTrue(pro.isProActive)
        XCTAssertTrue(pro.coreTopicsUnlocked, "Pro ⇒ core topics")
        XCTAssertTrue(pro.adsSuppressed, "Pro ⇒ no ads")
        for pack in ID.packs {
            XCTAssertTrue(pro.hasAccess(packProductID: pack.rawValue), "Pro ⇒ \(pack)")
        }
        XCTAssertFalse(pro.unlockAll || pro.removeAds || !pro.packProductIDs.isEmpty,
                       "Pro does not write the one-time flags — a lapse leaves them as bought")

        let unlockAll = resolve([tx(.unlockAll)])
        XCTAssertTrue(unlockAll.coreTopicsUnlocked, "Unlock All ⇒ core topics")
        XCTAssertFalse(unlockAll.adsSuppressed, "Unlock All does not remove ads")
        for pack in ID.packs {
            XCTAssertFalse(unlockAll.hasAccess(packProductID: pack.rawValue), "Unlock All never opens \(pack) (D18)")
        }

        let removeAds = resolve([tx(.removeAds)])
        XCTAssertTrue(removeAds.adsSuppressed, "Remove Ads ⇒ no ads")
        XCTAssertFalse(removeAds.coreTopicsUnlocked, "Remove Ads opens nothing")

        let lapsedProWithPack = resolve([tx(.proAnnual, expiresIn: -day), tx(.packWorld)])
        XCTAssertFalse(lapsedProWithPack.isProActive)
        XCTAssertTrue(lapsedProWithPack.hasAccess(packProductID: ID.packWorld.rawValue),
                      "a pack bought outright survives Pro lapsing")
        XCTAssertFalse(lapsedProWithPack.hasAccess(packProductID: ID.packMarkets.rawValue))
    }

    // MARK: - Family sharing

    func testFamilySharedTransactionsGrantAndAreReported() {
        let resolved = resolve([tx(.unlockAll, ownership: .familyShared),
                                tx(.proAnnual, expiresIn: 100 * day, ownership: .familyShared)])
        XCTAssertTrue(resolved.coreTopicsUnlocked)
        XCTAssertTrue(resolved.isProActive)
        XCTAssertEqual(resolved.familySharedProductIDs, [ID.unlockAll.rawValue])
        XCTAssertEqual(resolved.pro?.ownership, .familyShared)
        XCTAssertTrue(ProStatusCopy.rows(for: resolved.pro!).contains(ProStatusRow(title: "Shared by", value: "Family Sharing")))
    }

    // MARK: - Subscription states

    func testAnActiveSubscriptionWorksOfflineWithoutStatuses() {
        let resolved = resolve([tx(.proMonthly, expiresIn: 10 * day)], nil)
        XCTAssertEqual(resolved.pro?.state, .active)
        XCTAssertNil(resolved.pro?.willAutoRenew, "no renewal info offline")
        XCTAssertEqual(ProStatusCopy.rows(for: resolved.pro!).map(\.title), ["Plan", "Current period ends"])
    }

    func testAnExpiredSubscriptionGrantsNothing() {
        XCTAssertNil(resolve([tx(.proMonthly, expiresIn: -60)]).pro)
        XCTAssertNil(resolve([], [status(.expired, .proMonthly, expiresIn: -day)]).pro)
    }

    func testARevokedSubscriptionGrantsNothingEvenWithAStaleTransaction() {
        XCTAssertNil(resolve([], [status(.revoked, .proAnnual, expiresIn: 200 * day)]).pro)
        XCTAssertNil(resolve([tx(.proAnnual, expiresIn: 200 * day)],
                             [status(.revoked, .proAnnual, expiresIn: 200 * day)]).pro,
                     "a revoked group status overrides the entitlement transaction")
    }

    func testGracePeriodKeepsAccessAndSaysPaymentIssue() {
        let resolved = resolve([tx(.proMonthly, expiresIn: 3 * day)],
                               [status(.inGracePeriod, .proMonthly, expiresIn: 3 * day)])
        XCTAssertTrue(resolved.isProActive, "grace period keeps Pro")
        XCTAssertEqual(resolved.pro?.state, .gracePeriod)
        XCTAssertTrue(ProStatusCopy.rows(for: resolved.pro!).contains(ProStatusRow(title: "Status", value: "Payment issue")))
        XCTAssertEqual(ProStatusCopy.footer(for: resolved.pro), "Update your payment method in Manage Subscription to keep Pro.")
    }

    func testBillingRetryKeepsAccessFromTheStatusAlone() {
        // The period ended, so `currentEntitlements` no longer carries it.
        let resolved = resolve([], [status(.inBillingRetryPeriod, .proAnnual, expiresIn: -2 * day)])
        XCTAssertTrue(resolved.isProActive, "billing retry keeps Pro (Owner brief)")
        XCTAssertEqual(resolved.pro?.state, .billingRetry)
        XCTAssertTrue(resolved.adsSuppressed)
        XCTAssertFalse(ProStatusCopy.rows(for: resolved.pro!).contains { $0.title == "Renews" },
                       "no renewal date for a period that already ended")
    }

    func testAnUnverifiedStatusIsIgnored() {
        XCTAssertNil(resolve([], [status(.subscribed, .proMonthly, verified: false, expiresIn: 20 * day)]).pro)
    }

    func testActiveBeatsAProblemStateAcrossPlans() {
        let resolved = resolve([tx(.proAnnual, expiresIn: 300 * day)],
                               [status(.inBillingRetryPeriod, .proMonthly, expiresIn: -day),
                                status(.subscribed, .proAnnual, expiresIn: 300 * day)])
        XCTAssertEqual(resolved.pro?.productID, ID.proAnnual.rawValue)
        XCTAssertEqual(resolved.pro?.state, .active)
    }

    // MARK: - Upgrade, downgrade, auto-renew

    func testAnUpgradedAwayTransactionGrantsNothingAndItsReplacementDoes() {
        let resolved = resolve([tx(.proMonthly, expiresIn: 20 * day, upgraded: true),
                                tx(.proAnnual, expiresIn: 365 * day)])
        XCTAssertEqual(resolved.pro?.productID, ID.proAnnual.rawValue, "monthly → annual upgrade is immediate")
        XCTAssertNil(resolve([tx(.proMonthly, expiresIn: 20 * day, upgraded: true)]).pro)
    }

    func testAScheduledDowngradeIsShownAsAPlanChange() {
        let resolved = resolve([tx(.proAnnual, expiresIn: 40 * day)],
                               [status(.subscribed, .proAnnual, expiresIn: 40 * day, renewsInto: .proMonthly)])
        XCTAssertEqual(resolved.pro?.pendingPlanChangeProductID, ID.proMonthly.rawValue)
        let rows = ProStatusCopy.rows(for: resolved.pro!, formatDate: { _ in "DATE" })
        XCTAssertEqual(rows, [ProStatusRow(title: "Plan", value: "Yearly"),
                              ProStatusRow(title: "Renews", value: "DATE"),
                              ProStatusRow(title: "Switches to", value: "Monthly")])
    }

    func testACancelledSubscriptionShowsItsEndDateAndNoPlanChange() {
        let resolved = resolve([tx(.proMonthly, expiresIn: 5 * day)],
                               [status(.subscribed, .proMonthly, expiresIn: 5 * day,
                                       willAutoRenew: false, renewsInto: .proAnnual)])
        XCTAssertNil(resolved.pro?.pendingPlanChangeProductID, "nothing renews, so nothing switches")
        let rows = ProStatusCopy.rows(for: resolved.pro!, formatDate: { _ in "DATE" })
        XCTAssertEqual(rows.map(\.title), ["Plan", "Ends"])
        XCTAssertEqual(ProStatusCopy.footer(for: resolved.pro), "Pro stays on until the end date; resubscribe anytime.")
    }

    // MARK: - Mirrors never grant

    func testUserDefaultsMirrorsNeverGrantAccessAndOnlyHoldAdsOffUntilVerified() {
        let suite = "eb.store.mirror.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: PurchaseManager.proMirrorKey)
        defaults.set(true, forKey: PurchaseManager.removeAdsMirrorKey)
        defaults.set(true, forKey: "iap.unlockAll.purchased")
        defaults.set([ID.packMarkets.rawValue], forKey: "iap.packs.purchased")

        let store = PurchaseManager(defaults: defaults, observesStore: false)
        XCTAssertFalse(store.isProActive, "a mirror is not a subscription")
        XCTAssertFalse(store.coreTopicsUnlocked, "a mirror is not Unlock All")
        XCTAssertFalse(store.hasAccess(packProductID: ID.packMarkets.rawValue), "a mirror is not a pack")
        XCTAssertTrue(store.adsSuppressed, "…but a paying reader sees no ad before StoreKit answers")
        XCTAssertTrue(store.provisionalAdsSuppression)

        store.apply(ResolvedEntitlements())
        XCTAssertTrue(store.hasVerifiedEntitlements)
        XCTAssertFalse(store.adsSuppressed, "StoreKit said nothing is owned: ads return")
        XCTAssertFalse(defaults.bool(forKey: PurchaseManager.proMirrorKey))
        XCTAssertFalse(defaults.bool(forKey: PurchaseManager.removeAdsMirrorKey))

        store.apply(ResolvedEntitlements(removeAds: true))
        XCTAssertTrue(store.adsSuppressed)
        XCTAssertTrue(defaults.bool(forKey: PurchaseManager.removeAdsMirrorKey))
    }

    // MARK: - Price presentation (Phase 11 orchestrator finding)

    func testPriceStateIsLoadingUntilAFetchCompletesThenUnavailableOrReady() {
        XCTAssertEqual(PurchasePresentation.priceState(displayPrice: nil, isLoading: false, hasAttemptedLoad: false), .loading)
        XCTAssertEqual(PurchasePresentation.priceState(displayPrice: nil, isLoading: true, hasAttemptedLoad: true), .loading)
        XCTAssertEqual(PurchasePresentation.priceState(displayPrice: nil, isLoading: false, hasAttemptedLoad: true), .unavailable)
        XCTAssertEqual(PurchasePresentation.priceState(displayPrice: "", isLoading: false, hasAttemptedLoad: true), .unavailable)
        XCTAssertEqual(PurchasePresentation.priceState(displayPrice: "1,99 €", isLoading: true, hasAttemptedLoad: true), .ready("1,99 €"))
    }

    func testNoPurchaseLabelEverShowsARawOrDoubledPlaceholder() {
        let states: [PurchasePresentation.PriceState] = [.loading, .unavailable, .ready("$1.99"), .ready("¥300")]
        var labels: [String] = []
        for state in states {
            for pending in [false, true] {
                labels.append(PurchasePresentation.buyTitle("Unlock Personal Finance", state, pending: pending))
                labels.append(PurchasePresentation.subscribeTitle(state, period: "/ year", pending: pending))
            }
            labels.append(PurchasePresentation.priceLabel(state))
            labels.append(ProPaywallContent<EmptyView>.planAccessibilityLabel("Pro Yearly", state, period: "/ year"))
        }
        for label in labels {
            XCTAssertFalse(label.contains("— —"), "doubled dash: \(label)")
            XCTAssertFalse(label.hasSuffix("—"), "dangling dash: \(label)")
            XCTAssertNotEqual(label.trimmingCharacters(in: .whitespaces), "—", "bare placeholder")
            XCTAssertFalse(label.isEmpty)
            XCTAssertFalse(label.contains("$0.99"), "no price literal")
        }
        XCTAssertEqual(PurchasePresentation.buyTitle("Unlock Personal Finance", .ready("$1.99")), "Unlock Personal Finance — $1.99")
        XCTAssertEqual(PurchasePresentation.buyTitle("Unlock Personal Finance", .loading), "Loading price…")
        XCTAssertEqual(PurchasePresentation.buyTitle("Unlock Personal Finance", .unavailable), "Unlock Personal Finance",
                       "without a price the disabled button still says what it does")
        XCTAssertEqual(PurchasePresentation.buyTitle("Unlock All", .ready("$0,99"), pending: true), "Waiting for approval")
        XCTAssertEqual(PurchasePresentation.subscribeTitle(.ready("$29.99"), period: "/ year"), "Subscribe for $29.99 / year")
        XCTAssertEqual(PurchasePresentation.subscribeTitle(.unavailable, period: "/ year"), "Subscribe")
        XCTAssertEqual(PurchasePresentation.priceLabel(.unavailable), "Unavailable")
        XCTAssertEqual(PurchasePresentation.periodSuffix(for: .proAnnual), "/ year")
        XCTAssertEqual(PurchasePresentation.periodSuffix(for: .proMonthly), "/ month")
    }

    /// Source scan: no view interpolates the legacy placeholder any more.
    func testNoViewRendersTheLegacyPlaceholder() throws {
        let appRoot = URL(fileURLWithPath: "\(#filePath)").deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("EconByte")
        let walker = try XCTUnwrap(FileManager.default.enumerator(at: appRoot, includingPropertiesForKeys: nil))
        var scanned = 0
        for case let url as URL in walker where url.pathExtension == "swift" && url.pathComponents.contains("Views") {
            let code = InstrumentationPrivacyTests.strippingComments(try String(contentsOf: url, encoding: .utf8))
            XCTAssertFalse(code.contains("priceText("), "\(url.lastPathComponent) renders the bare placeholder")
            XCTAssertFalse(code.contains("unavailablePrice"), "\(url.lastPathComponent) renders the bare placeholder")
            scanned += 1
        }
        XCTAssertGreaterThan(scanned, 10)
    }

    // MARK: - Failure copy

    func testStoreKitErrorsAreClassifiedAndCancelIsNotAFailure() {
        XCTAssertNil(PurchaseFailureReason.classify(StoreKitError.userCancelled))
        XCTAssertEqual(PurchaseFailureReason.classify(StoreKitError.networkError(URLError(.notConnectedToInternet))), .network)
        XCTAssertEqual(PurchaseFailureReason.classify(StoreKitError.notAvailableInStorefront), .notAvailableInStorefront)
        XCTAssertEqual(PurchaseFailureReason.classify(StoreKitError.notEntitled), .notAllowed)
        XCTAssertEqual(PurchaseFailureReason.classify(Product.PurchaseError.purchaseNotAllowed), .notAllowed)
        XCTAssertEqual(PurchaseFailureReason.classify(Product.PurchaseError.productUnavailable), .productUnavailable)
        XCTAssertEqual(PurchaseFailureReason.classify(PurchaseManager.StoreError.failedVerification), .verification)
        XCTAssertEqual(PurchaseFailureReason.classify(URLError(.timedOut)), .network)
        XCTAssertEqual(PurchaseFailureReason.classify(NSError(domain: "x", code: 9)), .unknown)
        for reason in PurchaseFailureReason.allCases {
            XCTAssertFalse(reason.message.isEmpty)
            XCTAssertFalse(reason.message.contains("Error Domain"), "no raw NSError text")
            XCTAssertFalse(reason.message.contains("$"))
        }
    }

    func testEveryResultMapsToOneConsistentAlert() {
        typealias Copy = PurchaseAlertCopy
        XCTAssertNil(Copy.alert(for: .cancelled, kind: .purchase, accessGranted: false), "cancel is silent")
        XCTAssertNil(Copy.alert(for: .cancelled, kind: .restore, accessGranted: false), "cancelled restore sign-in is silent")
        XCTAssertNil(Copy.alert(for: .success, kind: .purchase, accessGranted: true))
        XCTAssertEqual(Copy.alert(for: .success, kind: .purchase, accessGranted: false)?.title, "Purchase processing")
        XCTAssertEqual(Copy.alert(for: .success, kind: .restore, accessGranted: true)?.title, "Purchases restored")
        XCTAssertEqual(Copy.alert(for: .nothingToRestore, kind: .restore, accessGranted: false)?.title, "Nothing to restore",
                       "nothing to restore is not 'Something Went Wrong'")
        XCTAssertEqual(Copy.alert(for: .pending, kind: .purchase, accessGranted: false)?.title, "Waiting for approval")
        XCTAssertEqual(Copy.alert(for: .productUnavailable, kind: .purchase, accessGranted: false)?.title, "Purchase unavailable")
        XCTAssertEqual(Copy.alert(for: .failed("m"), kind: .purchase, accessGranted: false),
                       Copy.Alert(title: "Purchase didn't go through", message: "m"))
        XCTAssertEqual(Copy.alert(for: .failed("m"), kind: .restore, accessGranted: false)?.title, "Restore didn't finish")
    }

    // MARK: - Subscription group configuration

    /// Annual is level 1 and monthly level 2, so monthly → annual is an
    /// immediate upgrade and annual → monthly a downgrade at renewal (the
    /// ranking the Owner must mirror in App Store Connect).
    func testTheLocalConfigurationRanksAnnualAboveMonthly() throws {
        let url = URL(fileURLWithPath: "\(#filePath)").deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("EconByte.storekit")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let groups = try XCTUnwrap(json["subscriptionGroups"] as? [[String: Any]])
        let subs = try XCTUnwrap(groups.first?["subscriptions"] as? [[String: Any]])
        func level(_ id: ID) -> Int? { subs.first { $0["productID"] as? String == id.rawValue }?["groupNumber"] as? Int }
        XCTAssertEqual(level(.proAnnual), 1)
        XCTAssertEqual(level(.proMonthly), 2)
    }

    // MARK: - Ad provider classification

    func testAdErrorsSeparateNoFillFromFailure() {
        XCTAssertEqual(EconAdErrorClassifier.outcome(for: NSError(domain: "com.google.admob", code: 1)), .noFill)
        XCTAssertEqual(EconAdErrorClassifier.outcome(for: NSError(domain: "com.google.admob", code: 2)), .failed)
        XCTAssertEqual(EconAdErrorClassifier.outcome(for: NSError(domain: NSURLErrorDomain, code: 1)), .failed)
        XCTAssertEqual(EconAdErrorClassifier.maximumInterstitialAge, 55 * 60)
    }
}
