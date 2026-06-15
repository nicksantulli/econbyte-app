import SwiftUI

@main
struct EconByteApp: App {
    @StateObject private var content = ContentStore.shared
    @StateObject private var streak = StreakManager.shared
    @StateObject private var ads = AdManager.shared
    @StateObject private var store = PurchaseManager.shared

    var body: some Scene {
        WindowGroup {
            StudioIntroGate {
                HomeView()
                    .environmentObject(content)
                    .environmentObject(streak)
                    .environmentObject(ads)
                    .environmentObject(store)
            }
            .preferredColorScheme(.dark)
            .task {
                ads.start()
                ads.setAdsDisabled(store.isRemoveAdsPurchased)
                ReviewPrompt.registerLaunch()
            }
            // Keep the ad gate in sync the moment Remove Ads is purchased/restored.
            .onChange(of: store.isRemoveAdsPurchased) { disabled in
                ads.setAdsDisabled(disabled)
            }
        }
    }
}
