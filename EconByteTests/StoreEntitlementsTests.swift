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
        XCTAssertEqual(rows, [ProStatusRow(title: "Plan", value: "Annual"),
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

    // MARK: - All Packs Bundle (1.1.4)

    func testTheBundleOpensEveryPackAndNothingElse() {
        let resolved = resolve([tx(.packBundle)])
        for pack in ID.packs {
            XCTAssertTrue(resolved.hasAccess(packProductID: pack.rawValue), pack.rawValue)
        }
        XCTAssertFalse(resolved.coreTopicsUnlocked, "the bundle is packs only, not Unlock All")
        XCTAssertFalse(resolved.adsSuppressed, "the bundle does not remove ads")
        XCTAssertFalse(resolved.isProActive)
        XCTAssertTrue(resolved.ownsAnything, "restore reports the bundle as restored")
        XCTAssertTrue(resolved.packProductIDs.isEmpty, "no individual pack is recorded as bought")
    }

    func testARefundedOrUnverifiedBundleGrantsNothing() {
        XCTAssertFalse(resolve([tx(.packBundle, revoked: true)]).ownsAnything, "a refund removes the bundle")
        XCTAssertFalse(resolve([tx(.packBundle, verified: false)]).hasAccess(packProductID: ID.packHistory.rawValue))
    }

    func testBundlePacksSurviveAProLapseAndTheStorePublishesThem() {
        let lapsed = resolve([tx(.packBundle), tx(.proMonthly, expiresIn: -day)],
                             [status(.expired, .proMonthly, expiresIn: -day)])
        XCTAssertFalse(lapsed.isProActive)
        XCTAssertTrue(lapsed.hasAccess(packProductID: ID.packWorld.rawValue), "bought packs outlive Pro")

        let suite = "eb.bundle.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PurchaseManager(defaults: defaults, observesStore: false)
        store.apply(lapsed)
        XCTAssertTrue(store.isPackBundlePurchased)
        for pack in ID.packs {
            XCTAssertTrue(store.ownsPack(productID: pack.rawValue), pack.rawValue)
            XCTAssertFalse(store.isPackPurchased(productID: pack.rawValue), "owned via the bundle, not bought alone")
        }
        XCTAssertFalse(store.ownsPack(productID: ID.unlockAll.rawValue))
        XCTAssertTrue(store.allPacksReadable)
        XCTAssertFalse(store.coreTopicsUnlocked)
        XCTAssertFalse(store.adsSuppressed)
        XCTAssertFalse(PackBundleOfferView.isOffered(bundleOwned: false, allPacksReadable: true),
                       "no bundle offer when every pack is already readable")
        XCTAssertTrue(PackBundleOfferView.isOffered(bundleOwned: true, allPacksReadable: true), "shown as Owned")
        XCTAssertTrue(PackBundleOfferView.isOffered(bundleOwned: false, allPacksReadable: false))

        store.apply(ResolvedEntitlements())
        XCTAssertFalse(store.allPacksReadable, "a refund removes the bundle on the next refresh")
    }

    func testPackOwnedLabels() {
        XCTAssertEqual(PackOfferView.ownedLabel(ownsOutright: true, familyShared: false, readable: true), "Owned")
        XCTAssertEqual(PackOfferView.ownedLabel(ownsOutright: true, familyShared: true, readable: true), "Family Sharing")
        XCTAssertEqual(PackOfferView.ownedLabel(ownsOutright: false, familyShared: false, readable: true), "Included with Pro")
        XCTAssertNil(PackOfferView.ownedLabel(ownsOutright: false, familyShared: false, readable: false))
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
            labels.append(ProPaywallContent<EmptyView>.planAccessibilityLabel(
                "Annual", state, billed: state.displayPrice.map { "\($0) per year" }, perMonth: nil, badge: nil))
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

// MARK: - Pricing copy and the one purchase button (1.1.4 release scope)

/// Checklist A lines 1, 2, 3, 5, 9, 10 as pure functions.
@MainActor
final class PricingAndPurchaseButtonTests: XCTestCase {

    private typealias ID = PurchaseManager.ProductID
    private let usd = Decimal.FormatStyle.Currency(code: "USD", locale: Locale(identifier: "en_US"))

    private func offer(_ id: ID, _ price: String, period: BillingTerm? = nil, trial: BillingTerm? = nil,
                       style: Decimal.FormatStyle.Currency? = nil) -> StoreOffer {
        let value = Decimal(string: price, locale: Locale(identifier: "en_US_POSIX"))!
        let format = style ?? usd
        return StoreOffer(id: id, displayPrice: value.formatted(format), price: value,
                          priceFormatStyle: format, period: period, freeTrial: trial)
    }
    private var annual: StoreOffer {
        offer(.proAnnual, "39.99", period: BillingTerm(unit: .year, value: 1), trial: BillingTerm(unit: .week, value: 1))
    }
    private var monthly: StoreOffer { offer(.proMonthly, "9.99", period: BillingTerm(unit: .month, value: 1)) }

    func testBilledPriceIsTheFullAmountAndPeriodInWords() {
        XCTAssertEqual(PlanCopy.billedPrice(annual), "$39.99 per year")
        XCTAssertEqual(PlanCopy.billedPrice(monthly), "$9.99 per month")
        XCTAssertEqual(PlanCopy.billedPrice(offer(.packBundle, "5.99")), "$5.99")
        XCTAssertEqual(BillingTerm(unit: .month, value: 3).perPhrase, "every 3 months")
        for text in [PlanCopy.billedPrice(annual), PlanCopy.billedPrice(monthly)] {
            XCTAssertFalse(text.contains("/"), "no abbreviated period: \(text)")
        }
    }

    func testPerMonthAndSavingsAreDerivedFromStoreKitPricesAndNeverOverstated() {
        XCTAssertEqual(PlanCopy.perMonth(annual), "$3.33 per month")
        XCTAssertNil(PlanCopy.perMonth(monthly), "a monthly plan shows no per-month equivalent")
        XCTAssertEqual(PlanCopy.savingsPercent(plan: annual, comparedWith: monthly), 66,
                       "$39.99 vs 12 × $9.99 saves 66.6% — rounded down, never overstated")
        XCTAssertEqual(PlanCopy.savingsBadge(plan: annual, comparedWith: monthly), "Save 66%")
        XCTAssertNil(PlanCopy.savingsPercent(plan: monthly, comparedWith: annual))

        let eur = Decimal.FormatStyle.Currency(code: "EUR", locale: Locale(identifier: "de_DE"))
        let annualEUR = offer(.proAnnual, "39.99", period: BillingTerm(unit: .year, value: 1), style: eur)
        XCTAssertNil(PlanCopy.savingsPercent(plan: annualEUR, comparedWith: monthly), "different currencies are never compared")
        XCTAssertEqual(PlanCopy.perMonth(annualEUR)?.contains("3,33"), true, "the storefront's own currency format")

        // A price change in App Store Connect changes the copy with no code change.
        let cheaper = offer(.proAnnual, "29.99", period: BillingTerm(unit: .year, value: 1))
        XCTAssertEqual(PlanCopy.perMonth(cheaper), "$2.50 per month")
        XCTAssertEqual(PlanCopy.savingsPercent(plan: cheaper, comparedWith: monthly), 74)
        let noSaving = offer(.proAnnual, "119.88", period: BillingTerm(unit: .year, value: 1))
        XCTAssertNil(PlanCopy.savingsPercent(plan: noSaving, comparedWith: monthly))
    }

    func testTrialLineOnlyForEligibleReadersAndAlwaysComplete() {
        XCTAssertEqual(PlanCopy.trialLine(annual, eligible: true),
                       "Free for 7 days, then $39.99 per year. Cancel anytime in Settings at least 24 hours before the trial ends.")
        XCTAssertNil(PlanCopy.trialLine(annual, eligible: false), "not eligible: no trial wording")
        XCTAssertNil(PlanCopy.trialLine(annual, eligible: nil), "unknown eligibility: no trial wording")
        XCTAssertNil(PlanCopy.trialLine(monthly, eligible: true), "monthly has no trial")
        XCTAssertNil(PlanCopy.trialLine(nil, eligible: true), "no product: no trial wording")
        XCTAssertEqual(BillingTerm(unit: .day, value: 3).duration, "3 days")
        XCTAssertEqual(BillingTerm(unit: .month, value: 1).adjective, "1-month")
    }

    func testSubscribeActionReflectsPlanEligibilityAndCurrentPlan() {
        typealias Action = PlanCopy.Action
        XCTAssertEqual(PlanCopy.subscribeAction(for: .proAnnual, offer: annual, eligible: true, currentPlan: nil),
                       Action(action: "Start 7-day free trial", priceText: "then $39.99 per year", ownedLabel: nil))
        XCTAssertEqual(PlanCopy.subscribeAction(for: .proAnnual, offer: annual, eligible: false, currentPlan: nil),
                       Action(action: "Subscribe", priceText: "$39.99 per year", ownedLabel: nil))
        XCTAssertEqual(PlanCopy.subscribeAction(for: .proMonthly, offer: monthly, eligible: true, currentPlan: nil),
                       Action(action: "Subscribe", priceText: "$9.99 per month", ownedLabel: nil))
        XCTAssertEqual(PlanCopy.subscribeAction(for: .proAnnual, offer: annual, eligible: false, currentPlan: .proAnnual),
                       Action(action: "Current plan", priceText: nil, ownedLabel: "Current plan"))
        XCTAssertEqual(PlanCopy.subscribeAction(for: .proMonthly, offer: monthly, eligible: false, currentPlan: .proAnnual),
                       Action(action: "Switch to Monthly", priceText: "$9.99 per month", ownedLabel: nil))
        XCTAssertEqual(PlanCopy.subscribeAction(for: .proAnnual, offer: nil, eligible: true, currentPlan: nil),
                       Action(action: "Subscribe", priceText: nil, ownedLabel: nil))
    }

    func testOnePurchaseButtonModelForEveryProductAndState() {
        let ready = PurchaseButtonModel.make(action: "Unlock", price: .ready("$1.99"))
        XCTAssertEqual(ready.label, "Unlock · $1.99")
        XCTAssertTrue(ready.isEnabled)
        XCTAssertEqual(ready.style, .primary)
        XCTAssertFalse(ready.showsPricesUnavailable)

        let loading = PurchaseButtonModel.make(action: "Unlock", price: .loading)
        XCTAssertEqual(loading.label, "Loading price…")
        XCTAssertFalse(loading.isEnabled)
        XCTAssertTrue(loading.showsSpinner)

        let unavailable = PurchaseButtonModel.make(action: "Unlock", price: .unavailable)
        XCTAssertEqual(unavailable.label, "Unlock", "without a price the disabled button still says what it does")
        XCTAssertFalse(unavailable.isEnabled)
        XCTAssertTrue(unavailable.showsPricesUnavailable, "Prices unavailable — Try again")

        XCTAssertEqual(PurchaseButtonModel.make(action: "Unlock", price: .ready("$1.99"), pending: true).label,
                       "Waiting for approval")
        let working = PurchaseButtonModel.make(action: "Unlock", price: .ready("$1.99"), working: true)
        XCTAssertFalse(working.isEnabled)
        XCTAssertTrue(working.showsSpinner)
        XCTAssertFalse(PurchaseButtonModel.make(action: "Unlock", price: .ready("$1.99"), isLoadingProducts: true).isEnabled)

        let owned = PurchaseButtonModel.make(action: "Unlock", price: .ready("$1.99"), ownedLabel: "Owned")
        XCTAssertEqual(owned.label, "Owned")
        XCTAssertFalse(owned.isEnabled)
        XCTAssertEqual(owned.style, .owned)

        XCTAssertEqual(PurchaseButtonModel.make(action: "Start 7-day free trial", price: .ready("$39.99"),
                                                priceText: "then $39.99 per year").label,
                       "Start 7-day free trial · then $39.99 per year")

        for state in [PurchasePresentation.PriceState.loading, .unavailable, .ready("$5.99"), .ready("¥800")] {
            for pending in [false, true] {
                for isWorking in [false, true] {
                    let label = PurchaseButtonModel.make(action: "Unlock", price: state,
                                                         pending: pending, working: isWorking).label
                    XCTAssertFalse(label.isEmpty)
                    XCTAssertFalse(label.contains("—"), "no placeholder dash: \(label)")
                    XCTAssertFalse(label.hasSuffix("·"), "no dangling separator: \(label)")
                }
            }
        }
    }

    func testPaywallBenefitsAreCountedFromTheBundledCatalogs() {
        let content = ContentStore.shared
        let benefits = PaywallBenefits.current(content: content)
        XCTAssertEqual(benefits.courses, CourseCatalog.expectedCourseCount)
        XCTAssertEqual(benefits.lessons, CourseCatalog.expectedCourseCount * CourseCatalog.expectedLessonsPerCourse)
        XCTAssertEqual(benefits.packs, PackCatalog.expectedPackCount)
        XCTAssertEqual(benefits.packCards, PackCatalog.expectedCardCount)
        XCTAssertEqual(benefits.coreTopics, content.topics.count)
        let texts = benefits.rows.map(\.text)
        XCTAssertTrue(texts.contains("\(benefits.courses) courses, \(benefits.lessons) lessons with charts and quizzes"))
        XCTAssertTrue(texts.contains("All \(benefits.packs) topic packs (\(benefits.packCards) cards) and all \(benefits.coreTopics) core topics"))
        XCTAssertTrue(texts.contains("The Daily Brief, \(BriefStore.cadenceDescription)"))
        XCTAssertTrue(texts.contains("No ads"))
        var grown = benefits
        grown.courses = 4
        grown.lessons = 36
        XCTAssertTrue(grown.rows.map(\.text).contains("4 courses, 36 lessons with charts and quizzes"),
                      "the copy follows the catalog, it is never hard-coded")
    }

    func testAutoRenewDisclosureCoversChargeRenewalAndCancellation() {
        for phrase in ["Apple ID", "renews automatically", "at least 24 hours", "Settings → Apple ID → Subscriptions"] {
            XCTAssertTrue(PlanCopy.autoRenewDisclosure(trial: true).contains(phrase), phrase)
            XCTAssertTrue(PlanCopy.autoRenewDisclosure(trial: false).contains(phrase), phrase)
        }
        XCTAssertTrue(PlanCopy.autoRenewDisclosure(trial: true).contains("when the free trial ends"))
        XCTAssertTrue(PlanCopy.autoRenewDisclosure(trial: false).contains("when you confirm the purchase"))
        XCTAssertFalse(PlanCopy.autoRenewDisclosure(trial: false).localizedCaseInsensitiveContains("trial"),
                       "no trial wording for a reader who cannot take the trial (A2)")
    }

    /// No purchase surface carries a price literal or a trial toggle.
    func testPurchaseViewsHaveNoPriceLiteralAndThePaywallHasNoToggle() throws {
        let views = URL(fileURLWithPath: "\(#filePath)").deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("EconByte/Views")
        let walker = try XCTUnwrap(FileManager.default.enumerator(at: views, includingPropertiesForKeys: nil))
        let literal = try NSRegularExpression(pattern: "\\$\\s?[0-9]+[.,][0-9]{2}")
        var scanned = 0
        for case let url as URL in walker where url.pathExtension == "swift" {
            let code = InstrumentationPrivacyTests.strippingComments(try String(contentsOf: url, encoding: .utf8))
            let range = NSRange(code.startIndex..., in: code)
            XCTAssertEqual(literal.numberOfMatches(in: code, range: range), 0, "\(url.lastPathComponent) has a price literal")
            if url.lastPathComponent == "ProPaywallView.swift" {
                XCTAssertFalse(code.contains("Toggle("), "no toggle paywall (checklist A3)")
            }
            scanned += 1
        }
        XCTAssertGreaterThan(scanned, 10)
    }
}
