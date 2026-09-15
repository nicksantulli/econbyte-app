import StoreKit
import SwiftUI

/// StoreKit 2 purchase manager for EconByte's products.
///
/// Non-consumables (all APPROVED or READY_TO_SUBMIT in App Store Connect):
///   • `com.nsantulli.econbyte.unlockall` — unlocks every locked core topic
///   • `com.nsantulli.econbyte.removeads`  — hides all ads
///   • `com.nsantulli.econbyte.pack.<packID>` — one topic pack each (D18)
///   • `com.nsantulli.econbyte.pack.bundle` — the All Packs Bundle (1.1.4):
///     every topic pack, nothing else
///
/// Auto-renewable subscriptions (1.1.4, subscription group "EconByte Pro"):
///   • `com.nsantulli.econbyte.pro.annual`  — 1 year, 7-day free trial (level 1)
///   • `com.nsantulli.econbyte.pro.monthly` — 1 month, no introductory offer (level 2)
///
/// US prices (`econbyte-pricing-2026-09-15.md`) live ONLY in App Store Connect
/// and `EconByte.storekit`: annual $39.99, monthly $9.99, bundle $5.99, pack
/// $1.99, Unlock All $2.99, Remove Ads $1.99. No view ever shows a literal; every
/// price on screen is StoreKit's `displayPrice` (or derived from `price` with
/// the product's own `priceFormatStyle`, see `StoreOffer`).
///
/// Phase 11 audit (2026-09-14) — what this type guarantees, each with a test in
/// `StoreEntitlementsTests` / `StoreKitSessionTests`:
///   • Access comes ONLY from verified StoreKit data: `Transaction.currentEntitlements`
///     plus the subscription group's statuses, resolved by `EntitlementResolver`.
///     The UserDefaults mirrors are read for one thing — keeping ads OFF for a
///     paying reader in the second before StoreKit answers on a cold launch.
///     They never open a topic, a pack, a course or the brief.
///   • Grace period and billing retry keep Pro; refunds and revocations remove
///     access on the next refresh (the `Transaction.updates` listener starts at
///     launch, from `EconByteApp`'s `@StateObject`).
///   • Every transaction is finished, verified or not; an unverified one never
///     grants anything.
///   • `.pending` (Ask to Buy) is remembered for the run so the buy control
///     reads "Waiting for approval" instead of inviting a second request.
///   • Restore distinguishes restored / nothing to restore / cancelled / failed.
///   • App Store promoted purchases (`PurchaseIntent`) are handled.
///   • Product loading is single-flight and retried on foreground.

/// How a purchase control reads while StoreKit has not delivered a price.
///
/// There is no fallback price literal anywhere in the UI. A hardcoded "$0.99" is
/// wrong in every non-US storefront, wrong the moment the tier changes, and
/// wrong when the product is simply unavailable — and it is exactly the shape
/// App Review has objected to on a Dudley build before. When there is no price
/// the control says so in words ("Loading price…" / the action alone, disabled,
/// with "Prices unavailable — Try again" beside it); it never renders a bare
/// placeholder dash (Phase 11: "Subscribe for —", "Unlock X — —").
enum PurchasePresentation {

    /// Legacy placeholder. Kept only so older tests can prove it is not a
    /// currency string; no view renders it any more.
    static let unavailablePrice = "—"

    static let loadingPriceText = "Loading price…"
    static let pricesUnavailableText = "Prices unavailable"
    static let retryText = "Try again"
    static let unavailableShortText = "Unavailable"
    static let waitingForApprovalText = "Waiting for approval"

    /// What StoreKit has told us about one product's price.
    enum PriceState: Equatable {
        case loading
        case unavailable
        case ready(String)

        var displayPrice: String? {
            if case .ready(let price) = self { return price }
            return nil
        }
    }

    static func priceText(_ displayPrice: String?) -> String {
        guard let displayPrice, !displayPrice.isEmpty else { return unavailablePrice }
        return displayPrice
    }

    static func priceState(displayPrice: String?, isLoading: Bool, hasAttemptedLoad: Bool) -> PriceState {
        if let displayPrice, !displayPrice.isEmpty { return .ready(displayPrice) }
        return (isLoading || !hasAttemptedLoad) ? .loading : .unavailable
    }

    /// A buy control may only be live when there is a real, StoreKit-formatted
    /// price to charge and nothing else is in flight.
    static func canPurchase(displayPrice: String?, isWorking: Bool, isLoading: Bool) -> Bool {
        guard let displayPrice, !displayPrice.isEmpty else { return false }
        return !isWorking && !isLoading
    }

    /// The label of a buy button: "Unlock Markets — $1.99" when priced,
    /// "Loading price…" while fetching, and the bare action (disabled) when the
    /// App Store gave no price. Never a dangling or doubled dash.
    static func buyTitle(_ action: String, _ state: PriceState, pending: Bool = false) -> String {
        if pending { return waitingForApprovalText }
        switch state {
        case .ready(let price): return "\(action) — \(price)"
        case .loading: return loadingPriceText
        case .unavailable: return action
        }
    }

    /// The subscribe button: "Subscribe for $29.99 / year" when priced,
    /// "Loading price…" while fetching, "Subscribe" (disabled) without a price.
    static func subscribeTitle(_ state: PriceState, period: String, pending: Bool = false) -> String {
        if pending { return waitingForApprovalText }
        switch state {
        case .ready(let price):
            return "Subscribe for \(price) \(period)".trimmingCharacters(in: .whitespaces)
        case .loading: return loadingPriceText
        case .unavailable: return "Subscribe"
        }
    }

    /// A plan's contracted billing period, for when StoreKit has not loaded the
    /// product. A duration, never a price.
    static func periodSuffix(for id: PurchaseManager.ProductID) -> String {
        id == .proAnnual ? "/ year" : "/ month"
    }

    /// A price shown on its own (a Settings row, a plan tile).
    static func priceLabel(_ state: PriceState) -> String {
        switch state {
        case .ready(let price): return price
        case .loading: return loadingPriceText
        case .unavailable: return unavailableShortText
        }
    }
}

@MainActor
final class PurchaseManager: ObservableObject {
    /// When the app is only the host process for the unit-test bundle, the
    /// shared instance stays inert: no product load, no listener, no
    /// entitlement read at launch. StoreKit binds the process to an environment
    /// on its first call, and a host that has already talked to the sandbox
    /// App Store would shadow the tests' `SKTestSession` (Phase 11).
    static let shared: PurchaseManager = {
        let unitTestHost = InstrumentationContext.current.isUnitTestRun
        return PurchaseManager(observesStore: !unitTestHost, inertUnitTestHost: unitTestHost)
    }()

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
        /// The All Packs Bundle (1.1.4): every pack in `packs`. Not itself a
        /// pack (`isPack` is false) — it never appears as a pack row.
        case packBundle = "com.nsantulli.econbyte.pack.bundle"
        /// EconByte Pro (1.1.4). One subscription group, two durations.
        case proMonthly = "com.nsantulli.econbyte.pro.monthly"
        case proAnnual  = "com.nsantulli.econbyte.pro.annual"

        static let packs: [ProductID] = [.packMarkets, .packPersonal, .packHistory,
                                         .packWorld, .packSystems, .packPersonalFinance]
        static let subscriptions: [ProductID] = [.proMonthly, .proAnnual]
        var isPack: Bool { Self.packs.contains(self) }
        var isSubscription: Bool { Self.subscriptions.contains(self) }

        static let catalog = StoreCatalogIDs(unlockAll: ProductID.unlockAll.rawValue,
                                             removeAds: ProductID.removeAds.rawValue,
                                             packs: Set(packs.map(\.rawValue)),
                                             packBundle: ProductID.packBundle.rawValue,
                                             subscriptions: Set(subscriptions.map(\.rawValue)))

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
            case .packBundle:   return .packBundle
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
        /// Restore only: the sync worked and this Apple ID owns nothing.
        case nothingToRestore
        /// Carries reader-facing copy from `PurchaseFailureReason`, never
        /// StoreKit's own error text.
        case failed(String)
    }

    @Published private(set) var isUnlockAllPurchased = false
    @Published private(set) var isRemoveAdsPurchased = false
    /// Pack product ids with a verified, unrevoked entitlement.
    @Published private(set) var ownedPackProductIDs: Set<String> = []
    /// A verified, unrevoked All Packs Bundle entitlement (1.1.4).
    @Published private(set) var isPackBundlePurchased = false
    /// EconByte Pro: subscribed, in its grace period, or in billing retry.
    @Published private(set) var isProActive = false
    /// The resolved subscription (plan, state, renewal) when Pro is active.
    @Published private(set) var proEntitlement: ProEntitlement?
    @Published private(set) var familySharedProductIDs: Set<String> = []
    /// False until StoreKit has answered once this run. Until then content
    /// stays locked (mirrors never grant) and ads stay off for a reader whose
    /// last verified state was entitled.
    @Published private(set) var hasVerifiedEntitlements = false
    /// Products awaiting Ask to Buy approval, this run.
    @Published private(set) var pendingProductIDs: Set<String> = []
    /// Whether this Apple ID may still take the introductory free trial. `nil`
    /// until StoreKit has answered; the paywall shows the trial line only on a
    /// definite `true` (App Review 3.1.2: never advertise a trial to someone
    /// who cannot get it).
    @Published private(set) var isEligibleForTrial: Bool?
    @Published private(set) var products: [Product] = []
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var hasAttemptedProductLoad = false
    @Published private(set) var productsLoadError: String?

    var proExpiration: Date? { proEntitlement?.expirationDate }
    var proProductID: String? { proEntitlement?.productID }

    static let removeAdsMirrorKey = "iap.removeAds.purchased"
    static let proMirrorKey  = "iap.pro.active"

    private let defaults: UserDefaults
    /// The last verified ad-relevant state, read once at launch. Ads only.
    private let mirroredAdsSuppression: Bool

    private var updates: Task<Void, Never>?
    private var promotedPurchases: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
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

    /// Owned as a one-time purchase: the pack itself or the All Packs Bundle.
    /// Survives a Pro lapse.
    func ownsPack(productID: String) -> Bool {
        isPackPurchased(productID: productID)
            || (isPackBundlePurchased && ProductID.packs.contains { $0.rawValue == productID })
    }

    /// Access to a pack: owned outright ∨ the bundle ∨ Pro active (D19). A pack
    /// bought outright (or via the bundle) stays owned after Pro lapses; Pro
    /// access ends with it.
    func hasAccess(packProductID: String) -> Bool {
        ownsPack(productID: packProductID) || isProActive
    }

    /// Every pack is readable (bundle, all six bought, or Pro).
    var allPacksReadable: Bool {
        ProductID.packs.allSatisfy { hasAccess(packProductID: $0.rawValue) }
    }

    /// The core curriculum: Unlock All ∨ Pro (D19).
    var coreTopicsUnlocked: Bool { isUnlockAllPurchased || isProActive }

    /// Before StoreKit's first answer this run, the last verified ad state
    /// keeps a paying reader ad-free. It can only ever SUPPRESS ads.
    var provisionalAdsSuppression: Bool { !hasVerifiedEntitlements && mirroredAdsSuppression }

    /// Ads are off for a Remove Ads owner and for an active Pro subscriber.
    var adsSuppressed: Bool { isRemoveAdsPurchased || isProActive || provisionalAdsSuppression }

    func isPending(_ id: ProductID) -> Bool { pendingProductIDs.contains(id.rawValue) }

    func priceState(for id: ProductID) -> PurchasePresentation.PriceState {
        PurchasePresentation.priceState(displayPrice: offer(for: id)?.displayPrice,
                                        isLoading: isLoadingProducts,
                                        hasAttemptedLoad: hasAttemptedProductLoad)
    }

    #if DEBUG
    /// DEBUG-only: `-econDebugPro` (or the Settings debug toggle) reports Pro as
    /// active regardless of StoreKit, so the Pro surfaces can be exercised in a
    /// plain Simulator run or on a device installed with `devicectl`, where the
    /// local `.storekit` configuration is not attached. Compiled out of Release.
    private var debugForcedPro = ProcessInfo.processInfo.arguments.contains("-econDebugPro")
    /// DEBUG-only fixed offers for the paywall state screenshots (see
    /// `DebugStoreScenario`). `nil` in every normal run.
    private let debugStoreScenario = DebugStoreScenario.current
    /// DEBUG-only: `-econDebugOwnAll` reports Unlock All, Remove Ads and the
    /// All Packs Bundle as owned, for the "Owned" button state.
    private let debugOwnsAll = ProcessInfo.processInfo.arguments.contains("-econDebugOwnAll")
    #endif

    /// `observesStore: false` builds an inert instance for tests: no listener,
    /// no product load, no promoted-purchase handler.
    private let inertUnitTestHost: Bool

    init(defaults: UserDefaults = .standard, observesStore: Bool = true, inertUnitTestHost: Bool = false) {
        self.defaults = defaults
        self.inertUnitTestHost = inertUnitTestHost
        mirroredAdsSuppression = defaults.bool(forKey: Self.removeAdsMirrorKey)
            || defaults.bool(forKey: Self.proMirrorKey)
        #if DEBUG
        if let scenario = debugStoreScenario {
            hasAttemptedProductLoad = true
            isEligibleForTrial = scenario.trialEligible
            if scenario == .subscribed { debugForcedPro = true }
        }
        if debugForcedPro {
            isProActive = true
            proEntitlement = debugProEntitlement()
        }
        if debugOwnsAll {
            isUnlockAllPurchased = true
            isRemoveAdsPurchased = true
            isPackBundlePurchased = true
        }
        #endif
        guard observesStore else { return }
        updates = Task { [weak self] in await self?.listenForTransactions() }
        promotedPurchases = Task { [weak self] in await self?.listenForPromotedPurchases() }
        Task { [weak self] in
            await self?.loadProducts()
            await self?.updatePurchasedProducts()
        }
    }

    deinit {
        updates?.cancel()
        promotedPurchases?.cancel()
    }

    func product(for id: ProductID) -> Product? {
        products.first { $0.id == id.rawValue }
    }

    /// What StoreKit reported for a product, as a value (`StoreOffer`). Every
    /// price on screen comes from here.
    func offer(for id: ProductID) -> StoreOffer? {
        #if DEBUG
        if let debugStoreScenario { return debugStoreScenario.offer(for: id) }
        #endif
        return product(for: id).flatMap(StoreOffer.init(product:))
    }

    /// The subscription plan the reader is on, when Pro is active.
    var currentPlan: ProductID? {
        guard isProActive, let id = proEntitlement?.productID else { return nil }
        return ProductID(rawValue: id)
    }

    // MARK: - Load

    /// Single-flight: every surface calls this from its `.task`, and a second
    /// caller joins the fetch in flight instead of starting another one (which
    /// used to flip `isLoadingProducts` off while a fetch was still running).
    func loadProducts() async {
        #if DEBUG
        if debugStoreScenario != nil { hasAttemptedProductLoad = true; return }
        #endif
        if let loadTask {
            await loadTask.value
            return
        }
        let task = Task { await self.performProductLoad() }
        loadTask = task
        await task.value
        loadTask = nil
    }

    private func performProductLoad() async {
        isLoadingProducts = true
        productsLoadError = nil
        defer {
            isLoadingProducts = false
            hasAttemptedProductLoad = true
        }
        do {
            let loaded = try await Product.products(for: ProductID.allCases.map(\.rawValue))
            if loaded.isEmpty {
                // Keep anything loaded earlier this run rather than blanking
                // prices that were correct a minute ago.
                if products.isEmpty {
                    productsLoadError = PurchaseFailureReason.network.message
                }
                NSLog("[PurchaseManager] product load returned empty set")
                EBEvents.productsLoaded(outcome: .unavailable)
            } else {
                products = loaded
                NSLog("[PurchaseManager] loaded \(loaded.count) product(s)")
                EBEvents.productsLoaded(outcome: .loaded)
                await refreshTrialEligibility()
            }
        } catch {
            if products.isEmpty {
                productsLoadError = (PurchaseFailureReason.classify(error) ?? .network).message
            }
            NSLog("[PurchaseManager] product load failed")
            // Outcome only — never `error.localizedDescription`, which is a
            // third-party string and a prohibited property.
            EBEvents.productsLoaded(outcome: .failed)
        }
    }

    /// Intro-offer eligibility is per subscription GROUP, so asking either
    /// product answers for both. Stays `nil` if no subscription product loaded
    /// (for example, before the ASC products exist) — then no trial is shown.
    func refreshTrialEligibility() async {
        #if DEBUG
        if debugStoreScenario != nil { return }
        #endif
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
        guard AppStore.canMakePayments else {
            EBEvents.purchaseFinished(family: id.family, outcome: .failed)
            return .failed(PurchaseFailureReason.notAllowed.message)
        }
        if product(for: id) == nil { await loadProducts() }
        guard let product = product(for: id) else {
            NSLog("[PurchaseManager] no product for \(id.rawValue)")
            EBEvents.purchaseFinished(family: id.family, outcome: .unavailable)
            return .productUnavailable
        }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    pendingProductIDs.remove(id.rawValue)
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
                case .unverified(let transaction, _):
                    // Never grants. Finished so StoreKit stops re-delivering it.
                    onDiagnostic?(.transactionUnverified)
                    await transaction.finish()
                    EBEvents.purchaseFinished(family: id.family, outcome: .failed)
                    return .failed(PurchaseFailureReason.verification.message)
                }
            case .userCancelled:
                EBEvents.purchaseFinished(family: id.family, outcome: .cancelled)
                return .cancelled
            case .pending:
                pendingProductIDs.insert(id.rawValue)
                EBEvents.purchaseFinished(family: id.family, outcome: .pending)
                return .pending
            @unknown default:
                EBEvents.purchaseFinished(family: id.family, outcome: .failed)
                return .failed(PurchaseFailureReason.unknown.message)
            }
        } catch {
            NSLog("[PurchaseManager] purchase threw")
            guard let reason = PurchaseFailureReason.classify(error) else {
                EBEvents.purchaseFinished(family: id.family, outcome: .cancelled)
                return .cancelled
            }
            if reason == .productUnavailable || reason == .notAvailableInStorefront {
                EBEvents.purchaseFinished(family: id.family, outcome: .unavailable)
                return reason == .productUnavailable ? .productUnavailable : .failed(reason.message)
            }
            EBEvents.purchaseFinished(family: id.family, outcome: .failed)
            return .failed(reason.message)
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

    /// The four restore outcomes are distinguished HERE, where the branch is
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
                if isUnlockAllPurchased || isRemoveAdsPurchased || !ownedPackProductIDs.isEmpty
                    || isPackBundlePurchased || isProActive {
                    EBEvents.restoreFinished(outcome: .completed, entryPoint: entryPoint)
                    return .success
                }
                EBEvents.restoreFinished(outcome: .nothingToRestore, entryPoint: entryPoint)
                return .nothingToRestore
            } catch {
                guard let reason = PurchaseFailureReason.classify(error) else {
                    // The reader dismissed the Apple ID sign-in sheet.
                    EBEvents.restoreFinished(outcome: .cancelled, entryPoint: entryPoint)
                    return .cancelled
                }
                NSLog("[PurchaseManager] restore failed")
                onDiagnostic?(.restoreFailed)
                EBEvents.restoreFinished(outcome: .failed, entryPoint: entryPoint)
                return .failed(reason.message)
            }
        }
        restoreTask = task
        let result = await task.value
        restoreTask = nil
        return result
    }

    // MARK: - Entitlements

    /// Reads StoreKit's current entitlements and, when a subscription product
    /// has loaded, the group's statuses (the only place billing retry is
    /// visible), resolves them, and publishes the result.
    func updatePurchasedProducts() async {
        guard !inertUnitTestHost else { return }
        var snapshots: [StoreTransactionSnapshot] = []
        for await result in Transaction.currentEntitlements {
            snapshots.append(Self.snapshot(result))
        }
        let statuses = await subscriptionStatusSnapshots()
        apply(EntitlementResolver.resolve(transactions: snapshots,
                                          statuses: statuses,
                                          catalog: ProductID.catalog,
                                          now: Date()))
    }

    /// Publishes a resolution. Internal so tests can drive the published state
    /// (and the mirror rule) without StoreKit.
    func apply(_ resolved: ResolvedEntitlements) {
        var resolved = resolved
        #if DEBUG
        if debugForcedPro, resolved.pro == nil { resolved.pro = debugProEntitlement() }
        if debugOwnsAll {
            resolved.unlockAll = true
            resolved.removeAds = true
            resolved.packBundle = true
        }
        #endif
        isUnlockAllPurchased = resolved.unlockAll
        isRemoveAdsPurchased = resolved.removeAds
        ownedPackProductIDs = resolved.packProductIDs
        isPackBundlePurchased = resolved.packBundle
        isProActive = resolved.isProActive
        proEntitlement = resolved.pro
        familySharedProductIDs = resolved.familySharedProductIDs
        hasVerifiedEntitlements = true
        pendingProductIDs.subtract(ownedProductIDs(resolved))
        // Mirrors: ad state only. Nothing reads them to grant access.
        defaults.set(resolved.removeAds, forKey: Self.removeAdsMirrorKey)
        defaults.set(resolved.isProActive, forKey: Self.proMirrorKey)
    }

    private func ownedProductIDs(_ resolved: ResolvedEntitlements) -> Set<String> {
        var ids = resolved.packProductIDs
        if resolved.unlockAll { ids.insert(ProductID.unlockAll.rawValue) }
        if resolved.removeAds { ids.insert(ProductID.removeAds.rawValue) }
        if resolved.packBundle { ids.insert(ProductID.packBundle.rawValue) }
        if resolved.isProActive { ids.formUnion(ProductID.subscriptions.map(\.rawValue)) }
        return ids
    }

    private func subscriptionStatusSnapshots() async -> [StoreSubscriptionStatusSnapshot]? {
        guard let info = ProductID.subscriptions.lazy.compactMap({ self.product(for: $0)?.subscription }).first else {
            return nil
        }
        do {
            return try await info.status.map(Self.snapshot)
        } catch {
            return nil
        }
    }

    static func snapshot(_ result: VerificationResult<StoreKit.Transaction>) -> StoreTransactionSnapshot {
        let transaction = result.unsafePayloadValue
        var verified = false
        if case .verified = result { verified = true }
        return StoreTransactionSnapshot(productID: transaction.productID,
                                        isVerified: verified,
                                        revocationDate: transaction.revocationDate,
                                        expirationDate: transaction.expirationDate,
                                        isUpgraded: transaction.isUpgraded,
                                        ownership: transaction.ownershipType == .familyShared ? .familyShared : .purchased)
    }

    static func snapshot(_ status: Product.SubscriptionInfo.Status) -> StoreSubscriptionStatusSnapshot {
        let state: StoreSubscriptionState
        switch status.state {
        case .subscribed: state = .subscribed
        case .expired: state = .expired
        case .inBillingRetryPeriod: state = .inBillingRetryPeriod
        case .inGracePeriod: state = .inGracePeriod
        case .revoked: state = .revoked
        default: state = .unknown
        }
        let transaction = snapshot(status.transaction)
        var willAutoRenew: Bool?
        var autoRenewProductID: String?
        var graceEnds: Date?
        var renewalVerified = false
        if case .verified(let renewal) = status.renewalInfo {
            renewalVerified = true
            willAutoRenew = renewal.willAutoRenew
            autoRenewProductID = renewal.autoRenewPreference
            graceEnds = renewal.gracePeriodExpirationDate
        }
        return StoreSubscriptionStatusSnapshot(state: state,
                                               productID: transaction.productID,
                                               isVerified: transaction.isVerified && renewalVerified,
                                               expirationDate: transaction.expirationDate,
                                               revocationDate: transaction.revocationDate,
                                               willAutoRenew: willAutoRenew,
                                               autoRenewProductID: autoRenewProductID,
                                               gracePeriodExpirationDate: graceEnds,
                                               ownership: transaction.ownership)
    }

    // MARK: - Listeners

    private func listenForTransactions() async {
        for await result in Transaction.updates {
            await handle(transactionUpdate: result)
        }
    }

    /// Refunds, revocations, renewals, Ask to Buy approvals, purchases made on
    /// another device and family-sharing changes all arrive here.
    func handle(transactionUpdate result: VerificationResult<StoreKit.Transaction>) async {
        switch result {
        case .verified(let transaction):
            pendingProductIDs.remove(transaction.productID)
            await updatePurchasedProducts()
            await transaction.finish()
        case .unverified(let transaction, _):
            // Unverified transactions never grant an entitlement. Finished so
            // the queue does not replay it on every launch.
            onDiagnostic?(.transactionUnverified)
            await transaction.finish()
        }
    }

    /// A purchase started from the App Store product page (promoted IAP).
    private func listenForPromotedPurchases() async {
        guard #available(iOS 16.4, *) else { return }
        for await intent in PurchaseIntent.intents {
            guard let id = ProductID(rawValue: intent.product.id) else { continue }
            _ = await purchase(id, from: .appStorePromotion)
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
    /// Apple's account subscriptions page — the fallback when the in-app
    /// `manageSubscriptionsSheet` is unavailable.
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

/// Opens Apple's in-app Manage Subscriptions sheet (`showManageSubscriptions`)
/// and refreshes entitlements when it closes, so a cancellation, a plan change
/// or a resubscribe shows up without a relaunch.
struct ManageSubscriptionModifier: ViewModifier {
    @Binding var isPresented: Bool
    @ObservedObject var store: PurchaseManager

    func body(content: Content) -> some View {
        content
            .manageSubscriptionsSheet(isPresented: $isPresented)
            .onChange(of: isPresented) { showing in
                guard !showing else { return }
                Task { await store.updatePurchasedProducts() }
            }
    }
}

extension View {
    func manageSubscriptions(isPresented: Binding<Bool>, store: PurchaseManager) -> some View {
        modifier(ManageSubscriptionModifier(isPresented: isPresented, store: store))
    }
}

#if DEBUG
extension PurchaseManager {
    /// Monthly for `-econDebugPro`; yearly for `-econDebugStore subscribed`.
    func debugProEntitlement() -> ProEntitlement {
        let id: ProductID = debugStoreScenario == .subscribed ? .proAnnual : .proMonthly
        return ProEntitlement(productID: id.rawValue, state: .active,
                              expirationDate: Date().addingTimeInterval(30 * 24 * 60 * 60),
                              willAutoRenew: true, renewalProductID: id.rawValue)
    }

    /// DEBUG-only: flip entitlements without a real StoreKit purchase, so the
    /// gated/unlocked experience is testable in the plain Simulator (where the
    /// local .storekit config doesn't attach outside an Xcode scheme run) and
    /// on a device installed with `devicectl` rather than run from Xcode.
    func debugSetUnlockAll(_ value: Bool) {
        isUnlockAllPurchased = value
    }
    func debugSetRemoveAds(_ value: Bool) {
        isRemoveAdsPurchased = value
    }
    func debugSetPack(_ id: ProductID, _ value: Bool) {
        guard id.isPack else { return }
        if value { ownedPackProductIDs.insert(id.rawValue) } else { ownedPackProductIDs.remove(id.rawValue) }
    }
    func debugSetPackBundle(_ value: Bool) {
        isPackBundlePurchased = value
    }
    func debugSetPro(_ value: Bool) {
        debugForcedPro = value
        isProActive = value
        proEntitlement = value ? debugProEntitlement() : nil
    }
}
#endif
