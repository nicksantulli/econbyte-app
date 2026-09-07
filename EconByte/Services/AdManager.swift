import Foundation
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
// See `CONTENT-DECISIONS.md` D2 for what 1.0 did. Requests remain
// non-personalized (`npa=1`, `rdp=1`) for every ATT outcome, authorized
// included, and capped at a `G` content rating.

#if canImport(GoogleMobileAds)
import GoogleMobileAds

@MainActor
final class AdManager: NSObject, EconInterstitialAdapting {
    static let shared = AdManager()

    /// Raised on load or presentation failure so the caller can record a bounded
    /// diagnostic code. Failures are otherwise silent to the learning flow.
    var onFailure: ((EconDiagnosticCode, Error?) -> Void)?
    var onAdDismissed: ((Bool) -> Void)?

    private var interstitial: InterstitialAd?
    private var isLoading = false
    private var didStart = false
    private var pendingPolicy = EconAdRequestPolicy()

    /// Interstitials actually presented this app run. Reported as a bucketed
    /// ordinal only — never an ad unit id, never an advertising identifier.
    private(set) var impressionCount = 0

    var isAdLoaded: Bool { interstitial != nil }

    func startSDK(policy: EconAdRequestPolicy) {
        guard !didStart else { return }
        didStart = true
        pendingPolicy = policy

        let configuration = MobileAds.shared.requestConfiguration
        configuration.maxAdContentRating = .general
        // Belt and braces alongside the per-request `npa` extra: this forces
        // non-personalized treatment for every request in the process.
        configuration.publisherPrivacyPersonalizationState = .disabled

        MobileAds.shared.start { _ in
            Task { @MainActor in AdManager.shared.preload(policy: policy) }
        }
    }

    func preload(policy: EconAdRequestPolicy) {
        pendingPolicy = policy
        guard didStart, !isLoading, interstitial == nil else { return }
        isLoading = true
        Task { @MainActor in
            do {
                let ad = try await InterstitialAd.load(with: EconAdUnit.current,
                                                       request: Self.makeRequest(policy: policy))
                self.interstitial = ad
                self.isLoading = false
                EBEvents.adLoadFinished(outcome: .filled)
            } catch {
                self.isLoading = false
                self.onFailure?(.adLoadFailed, error)
                // Outcome only. The SDK's error string is a third-party message
                // and `sdk_error_description` is a prohibited property name.
                EBEvents.adLoadFinished(outcome: .noFill)
            }
        }
    }

    func discardLoadedAd() {
        interstitial = nil
    }

    func present() async -> Bool {
        guard let ad = interstitial, let presenter = Self.topViewController() else {
            return false
        }
        do {
            try ad.canPresent(from: presenter)
        } catch {
            interstitial = nil
            onFailure?(.adPresentFailed, error)
            return false
        }
        interstitial = nil
        ad.fullScreenContentDelegate = self
        ad.present(from: presenter)
        impressionCount += 1
        EBEvents.adImpression(ordinal: impressionCount)
        return true
    }

    private static func makeRequest(policy: EconAdRequestPolicy) -> Request {
        let request = Request()
        let extras = Extras()
        extras.additionalParameters = policy.extras
        request.register(extras)
        return request
    }

    /// Walks the key window's root VC chain so interstitials present correctly on
    /// iPhone and in iPad compatibility mode. `present(from: nil)` is unreliable.
    private static func topViewController() -> UIViewController? {
        let root = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
        var top = root
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

extension AdManager: FullScreenContentDelegate {
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

#else

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
