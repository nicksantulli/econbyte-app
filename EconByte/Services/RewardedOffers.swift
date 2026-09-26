import Foundation

// MARK: - Rewarded pack trial (1.1.6)
//
// Owner, 2026-09-26: rewarded ads ("watch an ad to unlock something"). A reader
// who has not bought a topic pack may watch one rewarded ad to read that pack
// free for 24 hours. It is opt-in — the ad only ever plays after the reader
// taps "Watch an ad" — so it is not an interruption and is never counted
// against the interstitial caps (it only spaces the next interstitial, see
// `EconMonetization.noteRewardedAdShown`).
//
// Gates, all upstream of any provider call:
//   * the same request gate as every other ad (`EconMonetization.canRequestAds`:
//     not Remove Ads / Pro, not an EEA/UK/CH region, ATT answered, launch
//     prompts resolved) and a started SDK;
//   * at most `maximumGrantsPer24Hours` unlocks in any rolling 24 hours — the
//     `maximumRewardedOffersPer24Hours` cap EconByte declares in
//     `config/app-factory/monetization-policy.json`.
//
// The unlock itself lives in `PurchaseManager.rewardedPackUnlocks`, beside the
// purchase entitlements it deliberately does not become.

@MainActor
public protocol EconRewardedAdapting: AnyObject {
    var isAdLoaded: Bool { get }
    /// Raised whenever `isAdLoaded` may have changed.
    var onLoadStateChanged: (() -> Void)? { get set }
    func preload(policy: EconAdRequestPolicy)
    /// Presents the loaded ad. Returns once it is gone: true only when the
    /// provider reported that the reader earned the reward.
    func presentForReward() async -> Bool
}

public enum EconRewardedOutcome: Equatable {
    case rewarded
    case notRewarded
    case noAdAvailable
    case notOffered
}

@MainActor
final class EconRewardedOffers: ObservableObject {

    static let maximumGrantsPer24Hours = 2
    static let grantsKey = "econ.rewarded.grantDates"

    /// Published so the offer button appears the moment an ad has loaded.
    @Published private(set) var isAdReady = false
    @Published private(set) var isPresenting = false

    private let adapter: EconRewardedAdapting
    private let defaults: UserDefaults
    private let now: () -> Date

    init(adapter: EconRewardedAdapting,
         defaults: UserDefaults = .standard,
         now: @escaping () -> Date = Date.init) {
        self.adapter = adapter
        self.defaults = defaults
        self.now = now
        adapter.onLoadStateChanged = { [weak self] in
            guard let self else { return }
            self.isAdReady = self.adapter.isAdLoaded
        }
    }

    /// Unlocks granted in the last 24 hours.
    var grantsInLast24Hours: Int {
        let moment = now()
        return grantDates.filter { moment.timeIntervalSince($0) < 24 * 60 * 60 }.count
    }

    private var grantDates: [Date] {
        (defaults.array(forKey: Self.grantsKey) as? [Double] ?? []).map(Date.init(timeIntervalSince1970:))
    }

    /// May the offer be made at all (independent of whether an ad has loaded)?
    func mayOffer(monetization: EconMonetization) -> Bool {
        monetization.canRequestAds && monetization.didStartSDK
            && grantsInLast24Hours < Self.maximumGrantsPer24Hours
    }

    /// Every rewarded request goes through here, behind the shared ad gate.
    func preloadIfPermitted(monetization: EconMonetization) {
        guard mayOffer(monetization: monetization) else { return }
        adapter.preload(policy: monetization.currentRequestPolicy)
        isAdReady = adapter.isAdLoaded
    }

    /// Plays the ad the reader asked for and, if it was watched to the end,
    /// opens the pack for 24 hours.
    func watch(forPackProductID productID: String,
               family: EBProductFamily?,
               monetization: EconMonetization,
               store: PurchaseManager) async -> EconRewardedOutcome {
        guard mayOffer(monetization: monetization), !isPresenting else { return .notOffered }
        guard adapter.isAdLoaded else {
            preloadIfPermitted(monetization: monetization)
            return .noAdAvailable
        }
        isPresenting = true
        let earned = await adapter.presentForReward()
        isPresenting = false
        isAdReady = adapter.isAdLoaded
        monetization.noteRewardedAdShown()
        guard earned else {
            preloadIfPermitted(monetization: monetization)
            return .notRewarded
        }
        let moment = now()
        let kept = (grantDates + [moment])
            .filter { moment.timeIntervalSince($0) < 24 * 60 * 60 }
            .map(\.timeIntervalSince1970)
        defaults.set(kept, forKey: Self.grantsKey)
        store.grantRewardedPackUnlock(packProductID: productID, now: moment)
        if let family { EBEvents.rewardedUnlockGranted(family: family) }
        preloadIfPermitted(monetization: monetization)
        return .rewarded
    }

    #if DEBUG
    static func resetPersistedState(in defaults: UserDefaults) {
        defaults.removeObject(forKey: grantsKey)
        defaults.removeObject(forKey: PurchaseManager.rewardedUnlocksKey)
    }
    #endif
}
