import Foundation
import UIKit

enum AdConfig {
    static let cardsPerAd = 5
    static let maxAdsPerSession = 3
    static let minimumIntervalSeconds: TimeInterval = 60

    /// Every ad request is non-personalized, unconditionally and everywhere.
    /// `config/app-factory/monetization-policy.json` sets
    /// `adsPolicy.personalizedAdsMode = "disabled"` portfolio-wide; this is the
    /// per-request half of it. The SDK-level switch in `AdManager.start()` is
    /// the other half, so dropping either one cannot silently re-enable
    /// personalization.
    static let nonPersonalizedRequestExtras: [String: String] = ["npa": "1"]
}

// MARK: - AdRegion (DUD-224 — EEA/UK ad geo-restriction)
//
// Owner decision (Jun 14): do NOT serve ads to EEA/UK users. Suppressing ad
// requests in those regions sidesteps GDPR / Google UMP consent entirely — no
// consent form, no UMP SDK call. The check uses the device's *region setting*
// (privacy-friendly, no location permission) and fails CLOSED: an unknown region
// is treated as restricted (no ads).
//
// Nothing here asks for App Tracking Transparency. EconByte does not track: ads
// are non-personalized in every region that gets them, so the prompt would buy
// no fill and cost a great deal — see InstrumentationPrivacyTests.
enum AdRegion {
    /// EEA member states + the United Kingdom.
    static let restrictedRegionCodes: Set<String> = [
        // EU 27
        "AT", "BE", "BG", "HR", "CY", "CZ", "DK", "EE", "FI", "FR", "DE", "GR",
        "HU", "IE", "IT", "LV", "LT", "LU", "MT", "NL", "PL", "PT", "RO", "SK",
        "SI", "ES", "SE",
        // EEA (non-EU)
        "IS", "LI", "NO",
        // United Kingdom
        "GB",
    ]

    /// True when ads must be suppressed: the device region is in the EEA/UK, or
    /// it can't be determined (fail closed).
    static var isAdRestricted: Bool {
        let code: String?
        if #available(iOS 16, *) {
            code = Locale.current.region?.identifier
        } else {
            code = Locale.current.regionCode
        }
        guard let code, !code.isEmpty else { return true }
        return restrictedRegionCodes.contains(code.uppercased())
    }
}

#if canImport(GoogleMobileAds)
import GoogleMobileAds

@MainActor
final class AdManager: NSObject, ObservableObject {
    static let shared = AdManager()

    private var adUnitID: String {
        #if DEBUG
        "ca-app-pub-3940256099942544/4411468910"
        #else
        "ca-app-pub-9950526548980224/9740067293"   // ← Owner provides real unit
        #endif
    }

    private var interstitial: InterstitialAd?
    private var isLoading = false

    private var sessionCardCount = 0
    private var sessionAdCount = 0
    private var lastShownAt: Date?

    /// When true (Remove Ads IAP owned), no interstitials are requested or shown.
    /// Synced from `PurchaseManager` via `setAdsDisabled(_:)`.
    @Published private(set) var adsDisabled = false

    /// Interstitials actually presented this app run. Read by the card session
    /// so it can report how many an individual session saw — a small bucketed
    /// count, never an ad unit id and never an advertising identifier.
    @Published private(set) var impressionCount = 0

    func setAdsDisabled(_ disabled: Bool) { adsDisabled = disabled }

    static let testDeviceIdentifiers = ["ef5558e3631904432fb53d8a5955da9d"]

    func start() {
        // DUD-224: never serve ads in the EEA/UK (Owner decision) — bail before
        // the SDK starts or any ad is requested, which sidesteps GDPR/UMP.
        guard !AdRegion.isAdRestricted else {
            NSLog("[AdManager] EEA/UK region — ads disabled")
            EconGrowth.adSuppressed(.regionRestricted)
            return
        }
        let configuration = MobileAds.shared.requestConfiguration
        // The SDK-level switch that makes every request non-personalized, so a
        // dropped `npa` extra can't silently re-enable personalization.
        configuration.publisherPrivacyPersonalizationState = .disabled
        configuration.testDeviceIdentifiers = Self.testDeviceIdentifiers
        MobileAds.shared.start { _ in
            Task { @MainActor in AdManager.shared.loadAd() }
        }
    }

    private func loadAd() {
        guard !isLoading, interstitial == nil else { return }
        isLoading = true
        Task {
            do {
                let request = Request()
                let extras = Extras()
                extras.additionalParameters = AdConfig.nonPersonalizedRequestExtras
                request.register(extras)
                let ad = try await InterstitialAd.load(with: adUnitID, request: request)
                self.interstitial = ad
                self.isLoading = false
                NSLog("[AdManager] interstitial loaded")
                EconGrowth.adLoadFinished(outcome: .filled)
            } catch {
                self.isLoading = false
                NSLog("[AdManager] load failed: \(error)")
                // Outcome only. The SDK's error string is a third-party message
                // and `sdk_error_description` is a prohibited property name.
                EconGrowth.adLoadFinished(outcome: .noFill)
            }
        }
    }

    private var canShow: Bool {
        guard sessionAdCount < AdConfig.maxAdsPerSession else { return false }
        if let last = lastShownAt {
            return Date().timeIntervalSince(last) >= AdConfig.minimumIntervalSeconds
        }
        return true
    }

    func noteCardSwipe() async {
        guard !adsDisabled else {
            EconGrowth.adSuppressed(.adsRemoved)
            return
        }
        sessionCardCount += 1
        guard sessionCardCount % AdConfig.cardsPerAd == 0, canShow else { return }
        EconGrowth.adEligibilityReached(depth: sessionCardCount)
        await presentInterstitial()
    }

    private func presentInterstitial() async {
        // DUD-224: no ads in the EEA/UK.
        guard !AdRegion.isAdRestricted else {
            EconGrowth.adSuppressed(.regionRestricted)
            return
        }
        guard let ad = interstitial else { return }
        guard let presenter = Self.topViewController() else {
            NSLog("[AdManager] no root view controller — skipping interstitial")
            return
        }
        sessionAdCount += 1
        impressionCount += 1
        lastShownAt = Date()
        interstitial = nil
        ad.present(from: presenter)
        EconGrowth.adImpression(ordinal: sessionAdCount)
        loadAd()
    }

    /// Walks the key window's root VC chain so interstitials present correctly
    /// on iPhone and iPad (compatibility mode). `present(from: nil)` is unreliable.
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

#else

@MainActor
final class AdManager: NSObject, ObservableObject {
    static let shared = AdManager()
    private var sessionCardCount = 0
    private var sessionAdCount = 0
    private var lastShownAt: Date?

    @Published private(set) var adsDisabled = false
    @Published private(set) var impressionCount = 0
    func setAdsDisabled(_ disabled: Bool) { adsDisabled = disabled }

    private var canShow: Bool {
        guard sessionAdCount < AdConfig.maxAdsPerSession else { return false }
        if let last = lastShownAt { return Date().timeIntervalSince(last) >= AdConfig.minimumIntervalSeconds }
        return true
    }

    func start() {
        NSLog("[AdManager:MOCK] start()")
        if AdRegion.isAdRestricted { EconGrowth.adSuppressed(.regionRestricted) }
    }

    func noteCardSwipe() async {
        guard !adsDisabled else {
            EconGrowth.adSuppressed(.adsRemoved)
            return
        }
        sessionCardCount += 1
        guard sessionCardCount % AdConfig.cardsPerAd == 0, canShow else { return }
        EconGrowth.adEligibilityReached(depth: sessionCardCount)
        sessionAdCount += 1
        impressionCount += 1
        lastShownAt = Date()
        NSLog("[AdManager:MOCK] interstitial #\(sessionAdCount) at card \(sessionCardCount)")
        EconGrowth.adImpression(ordinal: sessionAdCount)
        try? await Task.sleep(nanoseconds: 600_000_000)
    }
}

#endif
