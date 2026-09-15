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

/// Builds every ad request — interstitial and banner — from the policy, so the
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

    func present() async -> Bool {
        // Phase 25: only ever from a stable root. Presenting on a view
        // controller that is itself about to be dismissed (the card cover, in
        // 1.1.2–1.1.5) tears the ad down as it appears.
        guard let ad = interstitial, let presenter = LiveAdPresentationEnvironment.stableRoot() else {
            return false
        }
        do {
            try ad.canPresent(from: presenter)
        } catch {
            interstitial = nil
            loadedAt = nil
            onFailure?(.adPresentFailed, error)
            EBEvents.adDismissed(placement: .dailySetExit, outcome: .failed)
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
        EBEvents.adClicked(placement: .dailySetExit)
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
    let placement: EBAdPlacement
    /// Called with the ad's height once one has actually loaded, and with 0 on
    /// failure — the slot reserves no space for an ad that is not there.
    let onLoadedHeight: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(placement: placement, onLoadedHeight: onLoadedHeight) }

    func makeUIView(context: Context) -> BannerView {
        let size = currentOrientationAnchoredAdaptiveBanner(width: max(width, 320))
        let view = BannerView(adSize: size)
        view.adUnitID = adUnitID
        view.delegate = context.coordinator
        context.coordinator.requestedPersonalized = policy.usesPersonalizedAds
        view.load(EconAdRequestBuilder.makeRequest(policy: policy))
        return view
    }

    func updateUIView(_ view: BannerView, context: Context) {
        let size = currentOrientationAnchoredAdaptiveBanner(width: max(width, 320))
        let resized = abs(view.adSize.size.width - size.size.width) > 1
        // Phase 25: a Tracking change in iOS Settings flips the decision; the
        // strip reloads with the new request instead of refreshing the old one.
        let policyChanged = context.coordinator.requestedPersonalized != policy.usesPersonalizedAds
        guard resized || policyChanged else { return }
        if resized { view.adSize = size }
        context.coordinator.requestedPersonalized = policy.usesPersonalizedAds
        view.load(EconAdRequestBuilder.makeRequest(policy: policy))
    }

    @MainActor
    final class Coordinator: NSObject, BannerViewDelegate {
        let placement: EBAdPlacement
        let onLoadedHeight: (CGFloat) -> Void
        /// Whether the strip's current request was personalized.
        var requestedPersonalized: Bool?
        /// The slot's last reported fill outcome; `banner_load_finished_v1` is
        /// emitted when it changes, not on every 60-second refresh.
        private var lastOutcome: EBOutcome?

        init(placement: EBAdPlacement, onLoadedHeight: @escaping (CGFloat) -> Void) {
            self.placement = placement
            self.onLoadedHeight = onLoadedHeight
        }

        private func report(_ outcome: EBOutcome) {
            guard outcome != lastOutcome else { return }
            lastOutcome = outcome
            EBEvents.bannerLoadFinished(placement: placement, outcome: outcome)
        }

        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            onLoadedHeight(bannerView.adSize.size.height)
            report(.filled)
        }

        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            // No-fill and load failures are silent to the reader by design; the
            // SDK's error string is a third-party message and never leaves.
            NSLog("[Ads] banner load failed")
            onLoadedHeight(0)
            report(EconAdErrorClassifier.outcome(for: error))
        }

        func bannerViewDidRecordImpression(_ bannerView: BannerView) {
            EBEvents.bannerImpression(placement: placement)
        }

        func bannerViewDidRecordClick(_ bannerView: BannerView) {
            EBEvents.adClicked(placement: placement)
        }
    }
}
#else
/// Compiles the app without the SDK linked: no banner can ever load.
struct GoogleBannerView: View {
    let adUnitID: String
    let width: CGFloat
    let policy: EconAdRequestPolicy
    let placement: EBAdPlacement
    let onLoadedHeight: (CGFloat) -> Void
    var body: some View { Color.clear.frame(height: 0) }
}
#endif

// MARK: - Presenter (Phase 25)

/// The live `EconAdPresentationEnvironment`: the foreground-active key window's
/// root view controller, with nothing presented over it and no transition
/// running. Outside the SDK conditional so it compiles either way.
@MainActor
final class LiveAdPresentationEnvironment: EconAdPresentationEnvironment {
    static let shared = LiveAdPresentationEnvironment()

    var isReadyToPresentInterstitial: Bool { Self.stableRoot() != nil }

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
