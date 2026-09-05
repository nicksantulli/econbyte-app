import StoreKit
import UIKit

/// The "rate EconByte" ask, on the 5th, 20th and 50th launch.
///
/// **Never under automation.** `SKStoreReviewController` puts a system sheet
/// over Home two seconds after launch, and a UI suite relaunches the app once
/// per test — so exactly one test lands on a milestone launch and fails when
/// Home is covered, and *which* test it is depends on how many times the
/// simulator has ever opened the app. That is what made
/// `testCardModeCloseReturnsHome` fail intermittently on 2026-09-05: not a
/// scroll bug, a review sheet.
///
/// A review prompt is also a production side-effect in its own right — the same
/// reason a test run may not reach the live analytics projects (see
/// `InstrumentationContext`) applies to asking a robot to rate the app.
enum ReviewPrompt {

    /// Launches at which a real user is asked.
    static let milestones: Set<Int> = [5, 20, 50]

    private static let launchCountKey = "com.nsantulli.econbyte.launchCount"

    /// The whole decision, as a pure function so it is testable without a
    /// window scene. Debug builds are deliberately NOT excluded: a developer
    /// running in the Simulator should still be able to see the sheet.
    static func shouldRequestReview(launchCount: Int,
                                    context: InstrumentationContext) -> Bool {
        guard !context.isUnitTestRun, !context.isAutomationRun else { return false }
        return milestones.contains(launchCount)
    }

    static func registerLaunch() {
        let count = UserDefaults.standard.integer(forKey: launchCountKey) + 1
        UserDefaults.standard.set(count, forKey: launchCountKey)

        guard shouldRequestReview(launchCount: count, context: .current) else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
                // Bucketed launch count only — never the exact number, and
                // never anything about what was read before the ask.
                Task { @MainActor in EconGrowth.reviewRequestAttempted(launchCount: count) }
                SKStoreReviewController.requestReview(in: scene)
            }
        }
    }
}
