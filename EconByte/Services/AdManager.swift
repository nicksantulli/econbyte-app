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

// MARK: - Banner adapter (1.1.3)
//
// Same rule as the interstitial adapter: this is SDK plumbing only. Whether a
// banner may be on screen at all is decided by `AdBannerSlot` from the policy
// layer (`EconMonetization.canRequestAds`: entitlement, DUD-224 region, and the
// build-13 ATT ordering gate), so an entitled reader, an EEA/UK reader, or a
// reader who has not yet answered ATT never constructs this view and the SDK is
// never asked for a banner. Every request carries the same non-personalized
// extras (`npa=1`, `rdp=1`) the interstitial carries.

#if canImport(GoogleMobileAds)
struct GoogleBannerView: UIViewRepresentable {
    let adUnitID: String
    let width: CGFloat
    let policy: EconAdRequestPolicy
    /// Called with the ad's height once one has actually loaded, and with 0 on
    /// failure — the slot reserves no space for an ad that is not there.
    let onLoadedHeight: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onLoadedHeight: onLoadedHeight) }

    func makeUIView(context: Context) -> BannerView {
        let size = currentOrientationAnchoredAdaptiveBanner(width: max(width, 320))
        let view = BannerView(adSize: size)
        view.adUnitID = adUnitID
        view.delegate = context.coordinator
        view.load(Self.makeRequest(policy: policy))
        return view
    }

    func updateUIView(_ view: BannerView, context: Context) {
        let size = currentOrientationAnchoredAdaptiveBanner(width: max(width, 320))
        guard abs(view.adSize.size.width - size.size.width) > 1 else { return }
        view.adSize = size
        view.load(Self.makeRequest(policy: policy))
    }

    private static func makeRequest(policy: EconAdRequestPolicy) -> Request {
        let request = Request()
        let extras = Extras()
        extras.additionalParameters = policy.extras
        request.register(extras)
        return request
    }

    final class Coordinator: NSObject, BannerViewDelegate {
        let onLoadedHeight: (CGFloat) -> Void
        init(onLoadedHeight: @escaping (CGFloat) -> Void) { self.onLoadedHeight = onLoadedHeight }

        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            onLoadedHeight(bannerView.adSize.size.height)
        }

        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            // No-fill and load failures are silent to the reader by design; the
            // SDK's error string is a third-party message and never leaves.
            NSLog("[Ads] banner load failed")
            onLoadedHeight(0)
        }
    }
}
#else
/// Compiles the app without the SDK linked: no banner can ever load.
struct GoogleBannerView: View {
    let adUnitID: String
    let width: CGFloat
    let policy: EconAdRequestPolicy
    let onLoadedHeight: (CGFloat) -> Void
    var body: some View { Color.clear.frame(height: 0) }
}
#endif
