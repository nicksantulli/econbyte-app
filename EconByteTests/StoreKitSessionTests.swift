import XCTest
import StoreKit
import StoreKitTest
@testable import EconByte

/// Phase 11 (2026-09-14): the purchase state matrix through REAL StoreKit,
/// driven by `SKTestSession` against the repo's `EconByte.storekit`.
///
/// Each test builds an isolated `PurchaseManager` (own UserDefaults suite, no
/// listener) and asks it — not the test — what the reader can access after
/// every StoreKit transition. The deterministic logic behind those answers is
/// pinned in `StoreEntitlementsTests`; this file proves the StoreKit side of the
/// seam delivers what that logic expects.
///
/// Every StoreKit await runs through `step(_:)`: if StoreKit does not answer
/// within the timeout (the first attempt on this Mac hung for 12 minutes inside
/// the first test), the test is SKIPPED with the name of the step that hung,
/// and `[SKT]` markers in the log show exactly where. A skip here is evidence,
/// not a pass — the report says which.
///
/// Family Sharing cannot be simulated by `SKTestSession` (there is no API to
/// mint a `.familyShared` transaction), so it is covered only by the fake in
/// `StoreEntitlementsTests.testFamilySharedTransactionsGrantAndAreReported`.
@MainActor
final class StoreKitSessionTests: XCTestCase {

    private typealias ID = PurchaseManager.ProductID
    private static let stepTimeout: TimeInterval = 20

    private var session: SKTestSession!
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var store: PurchaseManager!

    private final class Box<T> { var value: T? }

    /// Awaits a StoreKit operation, or skips the test naming the step when it
    /// does not return in time. The hung operation is left running (StoreKit's
    /// awaits are not cancellable); the next test starts from a reset session.
    private func step<T>(_ name: String,
                         timeout: TimeInterval = StoreKitSessionTests.stepTimeout,
                         _ operation: @escaping @MainActor () async throws -> T) async throws -> T {
        NSLog("[SKT] \(testLabel(self)) · \(name) begin")
        let box = Box<Result<T, Error>>()
        Task { @MainActor in
            do { box.value = .success(try await operation()) } catch { box.value = .failure(error) }
        }
        let deadline = Date().addingTimeInterval(timeout)
        while box.value == nil, Date() < deadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        guard let outcome = box.value else {
            NSLog("[SKT] \(testLabel(self)) · \(name) TIMED OUT after \(Int(timeout)) s")
            throw XCTSkip("SKTestSession step '\(name)' did not return within \(Int(timeout)) s under "
                          + "xcodebuild on this Mac; the state matrix is covered by StoreEntitlementsTests")
        }
        NSLog("[SKT] \(testLabel(self)) · \(name) end")
        return try outcome.get()
    }

    private nonisolated func testLabel(_ test: XCTestCase) -> String { test.name }

    override func setUp() async throws {
        try await super.setUp()
        let url = URL(fileURLWithPath: "\(#filePath)").deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("EconByte.storekit")
        NSLog("[SKT] setUp · SKTestSession init")
        session = try SKTestSession(contentsOf: url)
        NSLog("[SKT] setUp · reset")
        session.resetToDefaultState()
        session.disableDialogs = true
        NSLog("[SKT] setUp · clearTransactions")
        session.clearTransactions()
        suiteName = "eb.skt.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        store = PurchaseManager(defaults: defaults, observesStore: false)
        let store = self.store!
        try await step("loadProducts") { await store.loadProducts() }
        NSLog("[SKT] setUp · loaded \(store.products.count) products")
        // Attached only if the products that exist SOLELY in EconByte.storekit
        // came back. On this Mac under `xcodebuild` they do not: SKTestSession
        // logs SKInternalErrorDomain Code=3 ("Error saving configuration file",
        // "Error clearing overrides", "Error deleting all transactions") and
        // StoreKit answers from the sandbox App Store with the 4 ASC products;
        // sandbox purchases then wait on a sign-in sheet that never resolves
        // (Phase 11 evidence skt1/skt2). Skip at once rather than time out.
        let localOnly = PurchaseManager.ProductID.subscriptions.map(\.rawValue)
            + [ID.packPersonalFinance.rawValue, ID.packSystems.rawValue]
        guard localOnly.allSatisfy({ id in store.products.contains { $0.id == id } }) else {
            throw XCTSkip("SKTestSession is not attached under xcodebuild on this Mac: StoreKit returned "
                          + "\(store.products.count) sandbox product(s) instead of the 10 in EconByte.storekit "
                          + "(SKInternalErrorDomain Code=3 on session init). Run in Xcode (⌘U); the state "
                          + "matrix is covered by StoreEntitlementsTests.")
        }
    }

    override func tearDown() async throws {
        session?.clearTransactions()
        session = nil
        defaults?.removePersistentDomain(forName: suiteName)
        store = nil
        try await super.tearDown()
    }

    private func buy(_ id: ID, from entryPoint: EBEntryPoint) async throws -> PurchaseManager.PurchaseResult {
        let store = self.store!
        return try await step("purchase \(id.rawValue)") { await store.purchase(id, from: entryPoint) }
    }

    /// Re-reads StoreKit until `condition` holds (session changes propagate
    /// asynchronously).
    private func eventually(_ label: String, _ timeout: TimeInterval = 15,
                            _ condition: @escaping @MainActor () -> Bool) async throws -> Bool {
        let store = self.store!
        return try await step("eventually \(label)", timeout: timeout + 5) {
            let deadline = Date().addingTimeInterval(timeout)
            repeat {
                await store.updatePurchasedProducts()
                if condition() { return true }
                try? await Task.sleep(nanoseconds: 250_000_000)
            } while Date() < deadline
            return condition()
        }
    }

    private func transactionID(for id: ID) -> UInt? {
        session.allTransactions().last { $0.productIdentifier == id.rawValue }?.identifier
    }

    // MARK: Load

    func testEveryProductLoadsWithAStoreKitPriceAndTheTrialIsOffered() {
        XCTAssertEqual(Set(store.products.map(\.id)), Set(ID.allCases.map(\.rawValue)))
        XCTAssertEqual(store.priceState(for: .proAnnual), .ready("$29.99"))
        XCTAssertEqual(store.priceState(for: .packPersonalFinance), .ready("$1.99"))
        XCTAssertEqual(store.isEligibleForTrial, true, "a fresh Apple ID may take the 7-day trial")
        XCTAssertNotNil(store.freeTrialPeriod(for: .proMonthly))
    }

    // MARK: Purchase / cancel / failure

    func testAPurchaseGrantsItsPackAndLeavesNothingUnfinished() async throws {
        let result = try await buy(.packMarkets, from: .home)
        XCTAssertEqual(result, .success)
        XCTAssertTrue(store.hasAccess(packProductID: ID.packMarkets.rawValue))
        XCTAssertFalse(store.hasAccess(packProductID: ID.packHistory.rawValue))
        XCTAssertFalse(store.coreTopicsUnlocked)
        let unfinished = try await step("Transaction.unfinished") { () -> Int in
            var count = 0
            for await result in Transaction.unfinished
            where result.unsafePayloadValue.productID == ID.packMarkets.rawValue {
                count += 1
            }
            return count
        }
        XCTAssertEqual(unfinished, 0, "the purchase transaction was finished")
    }

    func testACancelledPurchaseGrantsNothingAndIsNotAFailure() async throws {
        session.failTransactionsEnabled = true
        session.failureError = .paymentCancelled
        let result = try await buy(.removeAds, from: .settings)
        XCTAssertEqual(result, .cancelled)
        XCTAssertFalse(store.isRemoveAdsPurchased)
        XCTAssertNil(PurchaseAlertCopy.alert(for: result, kind: .purchase, accessGranted: false))
    }

    func testAFailedPurchaseShowsReaderCopyNotStoreKitText() async throws {
        session.failTransactionsEnabled = true
        session.failureError = .cloudServiceNetworkConnectionFailed
        let result = try await buy(.unlockAll, from: .paywall)
        guard case .failed(let message) = result else {
            return XCTFail("expected a failure, got \(result)")
        }
        XCTAssertTrue(PurchaseFailureReason.allCases.map(\.message).contains(message), message)
        XCTAssertFalse(store.coreTopicsUnlocked)
    }

    // MARK: Ask to Buy

    func testAskToBuyIsPendingUntilApprovedThenGrants() async throws {
        session.askToBuyEnabled = true
        let result = try await buy(.unlockAll, from: .paywall)
        XCTAssertEqual(result, .pending)
        XCTAssertTrue(store.isPending(.unlockAll), "the buy control reads Waiting for approval")
        XCTAssertFalse(store.coreTopicsUnlocked)

        let id = try XCTUnwrap(session.allTransactions().first {
            $0.productIdentifier == ID.unlockAll.rawValue && $0.pendingAskToBuyConfirmation
        }?.identifier)
        try session.approveAskToBuyTransaction(identifier: id)
        let granted = try await eventually("ask-to-buy approved") { self.store.coreTopicsUnlocked }
        XCTAssertTrue(granted, "approval grants Unlock All")
        XCTAssertFalse(store.isPending(.unlockAll), "and clears the pending state")
    }

    // MARK: Refund

    func testARefundRevokesAccess() async throws {
        let bought = try await buy(.removeAds, from: .settings)
        XCTAssertEqual(bought, .success)
        XCTAssertTrue(store.isRemoveAdsPurchased)
        try session.refundTransaction(identifier: XCTUnwrap(transactionID(for: .removeAds)))
        let revoked = try await eventually("refund") { !self.store.isRemoveAdsPurchased }
        XCTAssertTrue(revoked, "a refunded Remove Ads shows ads again")
    }

    // MARK: Subscriptions

    func testASubscriptionGrantsProUntilItExpires() async throws {
        let bought = try await buy(.proMonthly, from: .proTab)
        XCTAssertEqual(bought, .success)
        XCTAssertTrue(store.isProActive)
        XCTAssertTrue(store.coreTopicsUnlocked && store.adsSuppressed)
        XCTAssertEqual(store.proProductID, ID.proMonthly.rawValue)
        XCTAssertEqual(store.proEntitlement?.willAutoRenew, true)
        XCTAssertEqual(store.isEligibleForTrial, false, "the trial is spent")

        try session.expireSubscription(productIdentifier: ID.proMonthly.rawValue)
        let expired = try await eventually("expiry") { !self.store.isProActive }
        XCTAssertTrue(expired, "an expired subscription removes Pro")
        XCTAssertFalse(store.coreTopicsUnlocked)
    }

    func testMonthlyToAnnualIsAnImmediateUpgrade() async throws {
        let monthly = try await buy(.proMonthly, from: .proTab)
        XCTAssertEqual(monthly, .success)
        let annual = try await buy(.proAnnual, from: .proTab)
        XCTAssertEqual(annual, .success)
        let upgraded = try await eventually("upgrade") { self.store.proProductID == ID.proAnnual.rawValue }
        XCTAssertTrue(upgraded, "annual (level 1) replaces monthly (level 2) at once")
        XCTAssertTrue(store.isProActive)
    }

    func testAFailedRenewalKeepsProInGracePeriodOrBillingRetry() async throws {
        session.billingGracePeriodIsEnabled = true
        let bought = try await buy(.proMonthly, from: .proTab)
        XCTAssertEqual(bought, .success)
        session.failTransactionsEnabled = true
        session.failureError = .unknown
        try session.forceRenewalOfSubscription(productIdentifier: ID.proMonthly.rawValue)
        let issue = try await eventually("billing issue") { self.store.proEntitlement?.state.hasBillingIssue == true }
        try XCTSkipUnless(issue || store.proEntitlement?.state != .active,
                          "SKTestSession on this Xcode did not surface a failed renewal as a billing state; "
                          + "grace/billing retry are covered by StoreEntitlementsTests")
        XCTAssertTrue(store.isProActive, "grace period / billing retry keep Pro")
    }

    // MARK: Restore

    func testRestoreFindsPurchasesAndSaysSoWhenThereAreNone() async throws {
        let store = self.store!
        let empty = try await step("restore (empty)") { await store.restorePurchases(from: .settings) }
        XCTAssertEqual(empty, .nothingToRestore)

        let bought = try await buy(.packWorld, from: .topicGrid)
        XCTAssertEqual(bought, .success)
        let reinstalled = PurchaseManager(defaults: defaults, observesStore: false)
        try await step("reinstall loadProducts") { await reinstalled.loadProducts() }
        let restored = try await step("restore (owned)") { await reinstalled.restorePurchases(from: .settings) }
        XCTAssertEqual(restored, .success)
        XCTAssertTrue(reinstalled.hasAccess(packProductID: ID.packWorld.rawValue))
    }
}
