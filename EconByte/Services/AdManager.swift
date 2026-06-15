import Foundation
import AppTrackingTransparency

enum AdConfig {
    static let cardsPerAd = 5
    static let maxAdsPerSession = 3
    static let minimumIntervalSeconds: TimeInterval = 60
}

#if canImport(GoogleMobileAds)
import GoogleMobileAds
import UserMessagingPlatform

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
        // DUD-224: gather Google UMP (EEA/UK GDPR) consent, THEN ATT, BEFORE the
        // SDK starts or any ad is requested. Outside regulated regions this is a
        // no-op that returns immediately. `canRequestAds` is false only when a
        // regulated user declined — in which case we request no ads at all.
        ConsentManager.gather(testDeviceIdentifiers: Self.testDeviceIdentifiers) { canRequestAds in
            guard canRequestAds else { return }
            MobileAds.shared.start { _ in
                Task { @MainActor in AdManager.shared.loadAd() }
            }
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
        // ATT is requested up-front by ConsentManager (UMP→ATT) at launch, so
        // the consent flow is fully settled before the first ad ever loads.
        guard let ad = interstitial else { return }
        sessionAdCount += 1
        lastShownAt = Date()
        interstitial = nil
        ad.present(from: nil)
        loadAd()
    }
}

// MARK: - ConsentManager (DUD-224 — Google UMP GDPR/EEA consent)
//
// Google UMP (User Messaging Platform) consent gate. Runs ONCE at app launch,
// BEFORE the first ad is requested, in the order UMP → ATT — the sequence
// required by App Store Guideline 5.1.1 and AdMob's EEA/UK consent policy.
// Shared verbatim across all five Dudley ad apps.
//
// Flow:
//   1. requestConsentInfoUpdate — refreshes the user's consent state (must run
//      every session; synchronously restores the previous session's status).
//   2. loadAndPresentIfRequired — presents the consent form ONLY when consent
//      is required (EEA/UK). A no-op that returns immediately everywhere else.
//   3. ATT — request App Tracking Transparency after UMP settles, so the GDPR
//      form never competes with the ATT system alert on screen.
//   4. onComplete(canRequestAds) — the cue to start the Mobile Ads SDK + load.
//      `canRequestAds` is false only when a regulated user declined consent.
//
// Fails OPEN: a UMP network error never blocks the app — it falls through to
// ATT and lets `canRequestAds` (false on error) decide whether ads load.
@MainActor
enum ConsentManager {
    static func gather(testDeviceIdentifiers: [String],
                       onComplete: @escaping (_ canRequestAds: Bool) -> Void) {
        let parameters = RequestParameters()
        #if DEBUG
        // Force the EEA consent form on registered test devices so the flow can
        // be verified without being in Europe. Compiled out of Release, where
        // real users always get their true geography.
        let debug = DebugSettings()
        debug.geography = .EEA
        debug.testDeviceIdentifiers = testDeviceIdentifiers
        parameters.debugSettings = debug
        #endif

        ConsentInformation.shared.requestConsentInfoUpdate(with: parameters) { error in
            if let error {
                #if DEBUG
                NSLog("[ConsentManager] info update failed: %@", error.localizedDescription)
                #endif
                Self.requestATT { onComplete(ConsentInformation.shared.canRequestAds) }
                return
            }
            // Presents only if UMPConsentStatus == .required (EEA/UK); otherwise
            // calls back on the next run loop having shown nothing.
            ConsentForm.loadAndPresentIfRequired(from: nil) { formError in
                #if DEBUG
                if let formError {
                    NSLog("[ConsentManager] form error: %@", formError.localizedDescription)
                }
                #endif
                Self.requestATT { onComplete(ConsentInformation.shared.canRequestAds) }
            }
        }
    }

    /// Request ATT once (if undetermined), then invoke `next` on the main actor.
    private static func requestATT(_ next: @escaping () -> Void) {
        guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else {
            next(); return
        }
        ATTrackingManager.requestTrackingAuthorization { _ in
            Task { @MainActor in next() }
        }
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
