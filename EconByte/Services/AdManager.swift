import Foundation
import AppTrackingTransparency

enum AdConfig {
    static let cardsPerAd = 5
    static let maxAdsPerSession = 3
    static let minimumIntervalSeconds: TimeInterval = 60
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
        "ca-app-pub-XXXXXXXXXXXXXXXX/YYYYYYYYYY"   // ← Owner provides real unit
        #endif
    }

    private var interstitial: InterstitialAd?
    private var isLoading = false

    private var sessionCardCount = 0
    private var sessionAdCount = 0
    private var lastShownAt: Date?

    static let testDeviceIdentifiers = ["ef5558e3631904432fb53d8a5955da9d"]

    func start() {
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
        sessionCardCount += 1
        guard sessionCardCount % AdConfig.cardsPerAd == 0, canShow else { return }
        await presentInterstitial()
    }

    private func presentInterstitial() async {
        if ATTrackingManager.trackingAuthorizationStatus == .notDetermined {
            _ = await ATTrackingManager.requestTrackingAuthorization()
        }
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

    private var canShow: Bool {
        guard sessionAdCount < AdConfig.maxAdsPerSession else { return false }
        if let last = lastShownAt { return Date().timeIntervalSince(last) >= AdConfig.minimumIntervalSeconds }
        return true
    }

    func start() { NSLog("[AdManager:MOCK] start()") }

    func noteCardSwipe() async {
        sessionCardCount += 1
        guard sessionCardCount % AdConfig.cardsPerAd == 0, canShow else { return }
        if ATTrackingManager.trackingAuthorizationStatus == .notDetermined {
            _ = await ATTrackingManager.requestTrackingAuthorization()
        }
        sessionAdCount += 1
        lastShownAt = Date()
        NSLog("[AdManager:MOCK] interstitial #\(sessionAdCount) at card \(sessionCardCount)")
        try? await Task.sleep(nanoseconds: 600_000_000)
    }
}

#endif
