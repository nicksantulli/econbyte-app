import Foundation

enum AdConfig {
    static let cardsPerAd = 5
    static let maxAdsPerSession = 3
    static let minimumIntervalSeconds: TimeInterval = 60
}

// MARK: - AdRegion (DUD-224 — EEA/UK ad geo-restriction)
//
// Owner decision (Jun 14): do NOT serve ads to EEA/UK users. Suppressing ad
// requests in those regions sidesteps GDPR / Google UMP consent entirely — no
// consent form, no UMP SDK call. ATT is kept for US / rest-of-world. The check
// uses the device's *region setting* (privacy-friendly, no location permission)
// and fails CLOSED: an unknown region is treated as restricted (no ads).
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

    func setAdsDisabled(_ disabled: Bool) { adsDisabled = disabled }

    static let testDeviceIdentifiers = ["ef5558e3631904432fb53d8a5955da9d"]

    func start() {
        // DUD-224: never serve ads in the EEA/UK (Owner decision) — bail before
        // the SDK starts or any ad is requested, which sidesteps GDPR/UMP.
        guard !AdRegion.isAdRestricted else {
            NSLog("[AdManager] EEA/UK region — ads disabled")
            return
        }
        MobileAds.shared.requestConfiguration.testDeviceIdentifiers = Self.testDeviceIdentifiers
        MobileAds.shared.start { _ in
            Task { @MainActor in AdManager.shared.loadAd() }
        }
    }

    private func loadAd() {
        guard !isLoading, interstitial == nil else { return }
        isLoading = true
        Task {
            do {
                let ad = try await InterstitialAd.load(with: adUnitID, request: Request())
                self.interstitial = ad
                self.isLoading = false
                NSLog("[AdManager] interstitial loaded")
            } catch {
                self.isLoading = false
                NSLog("[AdManager] load failed: \(error)")
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
        guard !adsDisabled else { return }
        sessionCardCount += 1
        guard sessionCardCount % AdConfig.cardsPerAd == 0, canShow else { return }
        await presentInterstitial()
    }

    private func presentInterstitial() async {
        // DUD-224: no ads in the EEA/UK.
        guard !AdRegion.isAdRestricted else { return }
        guard let ad = interstitial else { return }
        sessionAdCount += 1
        lastShownAt = Date()
        interstitial = nil
        ad.present(from: nil)
        loadAd()
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
    func setAdsDisabled(_ disabled: Bool) { adsDisabled = disabled }

    private var canShow: Bool {
        guard sessionAdCount < AdConfig.maxAdsPerSession else { return false }
        if let last = lastShownAt { return Date().timeIntervalSince(last) >= AdConfig.minimumIntervalSeconds }
        return true
    }

    func start() { NSLog("[AdManager:MOCK] start()") }

    func noteCardSwipe() async {
        guard !adsDisabled else { return }
        sessionCardCount += 1
        guard sessionCardCount % AdConfig.cardsPerAd == 0, canShow else { return }
        sessionAdCount += 1
        lastShownAt = Date()
        NSLog("[AdManager:MOCK] interstitial #\(sessionAdCount) at card \(sessionCardCount)")
        try? await Task.sleep(nanoseconds: 600_000_000)
    }
}

#endif
