import Foundation
import SwiftUI
import UIKit

// MARK: - Interstitial adapter
//
// This type is a *provider adapter only*. Every eligibility rule — entitlement,
// region, placement, blockers, and caps — lives in `EconMonetization`, so ad
// policy is testable without the SDK.
//
// ATT does NOT live here. Version 1.1 removed the pathway 1.0 had in this file;
// 1.1.2 build 13 restores the prompt after App Review's 5.1.2(i) rejection of
// build 12, but as an ordering rule in `EconMonetization` rather than a call
// buried in the presentation path — build 8 (live 1.1.1) asked from
// `presentInterstitial()`, which is *after* the first ad request and therefore
// after the thing the guideline is about. The only file that may import the
// framework is `EconTrackingAuthorization.swift`, and
// `InstrumentationPrivacyTests` fails the build if any other one does.
//
// This adapter is a *provider adapter only* and it stays that way: it never
// asks, never decides, and never requests unless `EconMonetization` calls it —
// which that type will not do before the tracking decision.
//
// See `CONTENT-DECISIONS.md` D2 for what 1.0 did.
//
// Personalization (Owner decision 2026-09-15): a request is personalized only
// when `EconAdPersonalization` says so — a region known to be outside the
// EEA/UK/CH block list AND an ATT "Allow". Every other request is
// non-personalized (`npa=1`, `rdp=1`, SDK switch `.disabled`). The policy is
// rebuilt for every request, so a Tracking change in iOS Settings applies to
// the next one. Content rating stays `G` (EconByte is rated 4+).

#if canImport(GoogleMobileAds)
import GoogleMobileAds
#if canImport(FBAudienceNetwork)
import FBAudienceNetwork
#endif

/// Builds every ad request — interstitial and rewarded — from the policy, so the
/// SDK-level personalization switch, the per-request extras and the mediation
/// partners' tracking flags can never disagree.
@MainActor
enum EconAdRequestBuilder {
    static func makeRequest(policy: EconAdRequestPolicy) -> Request {
        applyPrivacy(policy)
        let request = Request()
        let extras = policy.extras
        if !extras.isEmpty {
            let networkExtras = Extras()
            networkExtras.additionalParameters = extras
            request.register(networkExtras)
        }
        return request
    }

    /// The process-wide half of the decision. Google's SDK default when the
    /// request may be personalized; `.disabled` otherwise.
    static func applyPrivacy(_ policy: EconAdRequestPolicy) {
        let configuration = MobileAds.shared.requestConfiguration
        configuration.maxAdContentRating = .general
        configuration.publisherPrivacyPersonalizationState = policy.usesPersonalizedAds ? .default : .disabled
        #if canImport(FBAudienceNetwork)
        // Meta Audience Network (AdMob mediation) reads its own flag rather
        // than Google's request: true only for a personalized request, which
        // already requires an ATT "Allow".
        FBAdSettings.setAdvertiserTrackingEnabled(policy.usesPersonalizedAds)
        #endif
    }
}

@MainActor
final class AdManager: NSObject, EconInterstitialAdapting {
    static let shared = AdManager()

    /// Raised on load or presentation failure so the caller can record a bounded
    /// diagnostic code. Failures are otherwise silent to the learning flow.
    var onFailure: ((EconDiagnosticCode, Error?) -> Void)?
    var onAdDismissed: ((Bool) -> Void)?

    private var interstitial: InterstitialAd?
    /// When the held interstitial loaded. Google expires a loaded interstitial
    /// after an hour; presenting an older one fails, so it is replaced first.
    private var loadedAt: Date?
    private var isLoading = false
    private var didStart = false
    private var pendingPolicy = EconAdRequestPolicy()

    /// Interstitials actually presented this app run. Reported as a bucketed
    /// ordinal only — never an ad unit id, never an advertising identifier.
    private(set) var impressionCount = 0

    var isAdLoaded: Bool { interstitial != nil && !isExpired }

    private var isExpired: Bool {
        guard let loadedAt else { return false }
        return Date().timeIntervalSince(loadedAt) > EconAdErrorClassifier.maximumInterstitialAge
    }

    func startSDK(policy: EconAdRequestPolicy) {
        guard !didStart else { return }
        didStart = true
        pendingPolicy = policy

        // Set before the SDK starts and again before every request.
        EconAdRequestBuilder.applyPrivacy(policy)

        MobileAds.shared.start { _ in
            Task { @MainActor in AdManager.shared.preload(policy: policy) }
        }
    }

    func preload(policy: EconAdRequestPolicy) {
        pendingPolicy = policy
        if isExpired {
            interstitial = nil
            loadedAt = nil
        }
        guard didStart, !isLoading, interstitial == nil else { return }
        isLoading = true
        Task { @MainActor in
            do {
                let ad = try await InterstitialAd.load(with: EconAdUnit.current,
                                                       request: EconAdRequestBuilder.makeRequest(policy: policy))
                self.interstitial = ad
                self.loadedAt = Date()
                self.isLoading = false
                EBEvents.adLoadFinished(outcome: .filled)
            } catch {
                self.isLoading = false
                self.onFailure?(.adLoadFailed, error)
                // Outcome only. The SDK's error string is a third-party message
                // and `sdk_error_description` is a prohibited property name.
                // Phase 11: a real no-fill is told apart from any other error.
                EBEvents.adLoadFinished(outcome: EconAdErrorClassifier.outcome(for: error))
            }
        }
    }

    func discardLoadedAd() {
        interstitial = nil
        loadedAt = nil
    }

    /// The placement on screen, for click and failure events (1.1.6).
    private var presentedPlacement: EconAdPlacement = .dailySetExit

    func present() async -> Bool { await present(for: .dailySetExit) }

    func present(for placement: EconAdPlacement) async -> Bool {
        // Phase 25: the set exit only ever presents from a stable root.
        // Presenting on a view controller that is itself about to be dismissed
        // (the card cover, in 1.1.2–1.1.5) tears the ad down as it appears.
        // 1.1.6: the halfway break presents over the card session, which stays.
        let presenter = placement == .setMidpoint
            ? LiveAdPresentationEnvironment.stableTopmost()
            : LiveAdPresentationEnvironment.stableRoot()
        guard let ad = interstitial, let presenter else {
            return false
        }
        presentedPlacement = placement
        do {
            try ad.canPresent(from: presenter)
        } catch {
            interstitial = nil
            loadedAt = nil
            onFailure?(.adPresentFailed, error)
            EBEvents.adDismissed(placement: EBAdPlacement(placement), outcome: .failed)
            return false
        }
        interstitial = nil
        loadedAt = nil
        ad.fullScreenContentDelegate = self
        ad.present(from: presenter)
        // `ad_impression_v1` moved to `adDidRecordImpression` (Phase 11): the
        // SDK's recorded impression, not the call to present.
        return true
    }

}

extension AdManager: FullScreenContentDelegate {
    func adDidRecordImpression(_ ad: FullScreenPresentingAd) {
        impressionCount += 1
        EBEvents.adImpression(ordinal: impressionCount)
    }

    func adDidRecordClick(_ ad: FullScreenPresentingAd) {
        EBEvents.adClicked(placement: EBAdPlacement(presentedPlacement))
    }

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        onAdDismissed?(true)
        preload(policy: pendingPolicy)
    }

    func ad(_ ad: FullScreenPresentingAd,
            didFailToPresentFullScreenContentWithError error: Error) {
        onFailure?(.adPresentFailed, error)
        onAdDismissed?(false)
        preload(policy: pendingPolicy)
    }
}

// MARK: - Rewarded adapter (1.1.6)

/// SDK plumbing for the rewarded pack trial. Every rule — who may be offered
/// it, how often, what it unlocks — lives in `EconRewardedOffers`.
@MainActor
final class RewardedAdManager: NSObject, EconRewardedAdapting {
    static let shared = RewardedAdManager()

    var onLoadStateChanged: (() -> Void)?

    private var rewarded: RewardedAd?
    private var loadedAt: Date?
    private var isLoading = false
    private var earned = false
    private var finish: CheckedContinuation<Bool, Never>?

    var isAdLoaded: Bool {
        guard rewarded != nil, let loadedAt else { return false }
        return Date().timeIntervalSince(loadedAt) <= EconAdErrorClassifier.maximumInterstitialAge
    }

    func preload(policy: EconAdRequestPolicy) {
        if rewarded != nil, !isAdLoaded { rewarded = nil; loadedAt = nil }
        guard !isLoading, rewarded == nil, let unit = EconAdUnit.rewarded else { return }
        isLoading = true
        Task { @MainActor in
            do {
                let ad = try await RewardedAd.load(with: unit,
                                                   request: EconAdRequestBuilder.makeRequest(policy: policy))
                self.rewarded = ad
                self.loadedAt = Date()
            } catch {
                NSLog("[Ads] rewarded load failed")
            }
            self.isLoading = false
            self.onLoadStateChanged?()
        }
    }

    func presentForReward() async -> Bool {
        guard let ad = rewarded, isAdLoaded,
              let presenter = LiveAdPresentationEnvironment.stableTopmost() else { return false }
        rewarded = nil
        loadedAt = nil
        onLoadStateChanged?()
        do {
            try ad.canPresent(from: presenter)
        } catch {
            EBEvents.adDismissed(placement: .packTrial, outcome: .failed)
            return false
        }
        earned = false
        ad.fullScreenContentDelegate = self
        return await withCheckedContinuation { continuation in
            finish = continuation
            ad.present(from: presenter) { [weak self] in
                self?.earned = true
            }
        }
    }

    private func complete() {
        let result = earned
        earned = false
        finish?.resume(returning: result)
        finish = nil
    }
}

extension RewardedAdManager: FullScreenContentDelegate {
    func adDidRecordClick(_ ad: FullScreenPresentingAd) {
        EBEvents.adClicked(placement: .packTrial)
    }

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        EBEvents.adDismissed(placement: .packTrial, outcome: earned ? .completed : .cancelled)
        complete()
    }

    func ad(_ ad: FullScreenPresentingAd,
            didFailToPresentFullScreenContentWithError error: Error) {
        EBEvents.adDismissed(placement: .packTrial, outcome: .failed)
        complete()
    }
}

#else

/// Simulator/CI fallback when the Google package is unavailable.
@MainActor
final class RewardedAdManager: NSObject, EconRewardedAdapting {
    static let shared = RewardedAdManager()
    var onLoadStateChanged: (() -> Void)?
    var isAdLoaded: Bool { false }
    func preload(policy: EconAdRequestPolicy) {}
    func presentForReward() async -> Bool { false }
}

/// Simulator/CI fallback when the Google package is unavailable. Loads nothing,
/// presents nothing — the policy layer is exercised the same way either side.
@MainActor
final class AdManager: NSObject, EconInterstitialAdapting {
    static let shared = AdManager()

    var onFailure: ((EconDiagnosticCode, Error?) -> Void)?
    var onAdDismissed: ((Bool) -> Void)?

    private(set) var impressionCount = 0

    var isAdLoaded: Bool { false }
    func startSDK(policy: EconAdRequestPolicy) {}
    func preload(policy: EconAdRequestPolicy) {}
    func discardLoadedAd() {}
    func present() async -> Bool { false }
}

#endif

// MARK: - No banner adapter (1.1.7)
//
// 1.1.3–1.1.6 carried an anchored adaptive banner (`GoogleBannerView`, mounted
// by `AdBannerSlot` on Home, Browse and under a card session). 1.1.7 removes it
// (Owner, 2026-09-28: banner eCPM $0.70 vs interstitial $12.66 in AdMob; the
// portfolio policy for ad-supported apps is now rewarded + capped
// interstitials at natural breaks, no banners). No banner view, unit or
// request exists in the app; `AdRetune117Tests` keeps it that way.

// MARK: - Presenter (Phase 25)

/// The live `EconAdPresentationEnvironment`: the foreground-active key window's
/// root view controller, with nothing presented over it and no transition
/// running. Outside the SDK conditional so it compiles either way.
@MainActor
final class LiveAdPresentationEnvironment: EconAdPresentationEnvironment {
    static let shared = LiveAdPresentationEnvironment()

    var isReadyToPresentInterstitial: Bool { Self.stableRoot() != nil }

    /// 1.1.6: the halfway break's environment — the top of the presentation
    /// stack (the card session) must be settled, whatever is under it.
    static let midSession = LiveMidSessionPresentationEnvironment()

    /// The top of the key window's presentation stack, when nothing is being
    /// presented or dismissed. The card session for the halfway break; the root
    /// (or a sheet over it) for the rewarded offer. Never an alert.
    static func stableTopmost() -> UIViewController? {
        guard var top = stableKeyRoot() else { return nil }
        while let next = top.presentedViewController { top = next }
        guard top.transitionCoordinator == nil,
              !top.isBeingDismissed, !top.isBeingPresented,
              !(top is UIAlertController)
        else { return nil }
        return top
    }

    private static func stableKeyRoot() -> UIViewController? {
        guard UIApplication.shared.applicationState == .active else { return nil }
        return UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .filter({ $0.activationState == .foregroundActive })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
    }

    static func stableRoot() -> UIViewController? {
        guard UIApplication.shared.applicationState == .active,
              let root = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .filter({ $0.activationState == .foregroundActive })
                .flatMap(\.windows)
                .first(where: \.isKeyWindow)?
                .rootViewController,
              root.presentedViewController == nil,
              root.transitionCoordinator == nil,
              !root.isBeingDismissed
        else { return nil }
        return root
    }
}

@MainActor
final class LiveMidSessionPresentationEnvironment: EconAdPresentationEnvironment {
    var isReadyToPresentInterstitial: Bool { LiveAdPresentationEnvironment.stableTopmost() != nil }
}

// MARK: - Provider error classification (Phase 11)

/// Pure helpers the adapters share, outside the SDK conditional so they are
/// unit-tested without Google's framework.
enum EconAdErrorClassifier {
    /// `GADErrorDomain` in GoogleMobileAds 12 (`GADRequestError.h`).
    static let googleErrorDomain = "com.google.admob"
    /// `GADErrorNoFill`.
    static let noFillCode = 1
    /// Google expires a loaded interstitial after one hour; replace it at 55
    /// minutes so the one placement never tries to present a dead ad.
    static let maximumInterstitialAge: TimeInterval = 55 * 60

    static func outcome(for error: Error) -> EBOutcome {
        let ns = error as NSError
        return (ns.domain == googleErrorDomain && ns.code == noFillCode) ? .noFill : .failed
    }
}
