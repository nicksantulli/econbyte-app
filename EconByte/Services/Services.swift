import StoreKit
import UIKit

enum ReviewPrompt {
    static func registerLaunch() {
        let key = "com.nsantulli.econbyte.launchCount"
        let count = UserDefaults.standard.integer(forKey: key) + 1
        UserDefaults.standard.set(count, forKey: key)
        if [5, 20, 50].contains(count) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
                    SKStoreReviewController.requestReview(in: scene)
                }
            }
        }
    }
}
