import SwiftUI

@main
struct EconByteApp: App {
    @StateObject private var content = ContentStore.shared
    @StateObject private var streak = StreakManager.shared
    @StateObject private var ads = AdManager.shared

    var body: some Scene {
        WindowGroup {
            StudioIntroGate {
                HomeView()
                    .environmentObject(content)
                    .environmentObject(streak)
                    .environmentObject(ads)
            }
            .preferredColorScheme(.dark)
            .task {
                ads.start()
                ReviewPrompt.registerLaunch()
            }
        }
    }
}
