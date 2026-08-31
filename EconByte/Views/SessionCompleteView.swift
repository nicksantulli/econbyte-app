import SwiftUI

struct SessionCompleteView: View {
    let title: String
    let cardsCount: Int
    let onDone: () -> Void

    @EnvironmentObject private var streak: StreakManager
    @EnvironmentObject private var content: ContentStore
    @EnvironmentObject private var growth: EconGrowth

    @State private var showPrimer = false
    @State private var showConsentPrompt = false
    @State private var analyticsEnabled = false
    @State private var diagnosticsEnabled = false
    @State private var exiting = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Text("🔥")
                .font(.system(size: 60))
                .accessibilityHidden(true)
            Text("Streak: \(streak.currentStreak) day\(streak.currentStreak == 1 ? "" : "s")")
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundColor(Econ.amber)
            Text("You finished \"\(title)\" — \(cardsCount) cards done.")
                .font(.system(size: 17, design: .rounded))
                .foregroundColor(Econ.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if showConsentPrompt { consentPrompt }
            if showPrimer { primer }

            Spacer()
            VStack(spacing: 12) {
                Button("Browse More Topics") { finish() }
                    .buttonStyle(SecondaryButton())
                    .disabled(exiting)
                Button("Done") { finish() }
                    .buttonStyle(PrimaryButton())
                    .disabled(exiting)
                    .accessibilityIdentifier("sessionCompleteDoneButton")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .task { await onAppearOnce() }
    }

    // MARK: Reminder primer (design section 11.1)

    /// Non-blocking, contextual, and it does not itself prompt: the system dialog
    /// appears only if the reader taps Turn On Reminders.
    private var primer: some View {
        VStack(spacing: 10) {
            Text(NotificationPolicy.primerHeadline)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(Econ.white)
            Text(NotificationPolicy.primerBody)
                .font(.system(size: 13, design: .rounded))
                .foregroundColor(Econ.subtext)
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button("Not now") { showPrimer = false }
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(Econ.subtext)
                    .accessibilityIdentifier("notificationPrimerDismissButton")
                Button("Turn On Reminders") { enableReminders() }
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(Econ.sky)
                    .accessibilityIdentifier("notificationPrimerEnableButton")
            }
        }
        .padding(16)
        .background(Econ.tide.opacity(0.14))
        .cornerRadius(14)
        .padding(.horizontal, 24)
    }

    // MARK: Consent presentation (design section 10.1)

    /// Both choices, offered once, after the first completed set — never on
    /// first launch. Non-blocking and default off; declining changes nothing.
    private var consentPrompt: some View {
        VStack(spacing: 10) {
            Text("Help improve EconByte?")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(Econ.white)
            Text("Two separate, optional choices. Both are off unless you turn them on, and neither affects your cards, streak, bookmarks, purchases, or ads. What you read or save is never shared.")
                .font(.system(size: 12, design: .rounded))
                .foregroundColor(Econ.subtext)
                .multilineTextAlignment(.center)
            Toggle("Share usage analytics", isOn: Binding(
                get: { analyticsEnabled },
                set: { value in
                    analyticsEnabled = value
                    growth.setAnalyticsEnabled(value, entryPoint: .sessionComplete)
                }))
                .font(.system(size: 14, design: .rounded))
                .foregroundColor(Econ.white)
                .tint(Econ.amber)
                .accessibilityIdentifier("consentPromptAnalyticsToggle")
            Toggle("Share crash diagnostics", isOn: Binding(
                get: { diagnosticsEnabled },
                set: { value in
                    diagnosticsEnabled = value
                    growth.setDiagnosticsEnabled(value, entryPoint: .sessionComplete)
                }))
                .font(.system(size: 14, design: .rounded))
                .foregroundColor(Econ.white)
                .tint(Econ.amber)
                .accessibilityIdentifier("consentPromptDiagnosticsToggle")
            Button("Done") { showConsentPrompt = false }
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(Econ.sky)
                .accessibilityIdentifier("consentPromptDoneButton")
        }
        .padding(16)
        .background(Econ.tide.opacity(0.14))
        .cornerRadius(14)
        .padding(.horizontal, 24)
    }

    // MARK: Behaviour

    private func onAppearOnce() async {
        growth.monetization.noteSetCompleted(normally: true)
        growth.review.noteSetCompleted()
        growth.telemetry.capture(.dailySetCompleted, properties: [
            "set_id": .token(EconAdState.dayKey(for: Date())),
            "card_count": .int(cardsCount),
            "duration_bucket": .token(Self.durationBucket(cardsCount)),
            "streak_day": .int(streak.currentStreak),
        ])

        // The rating request comes after the completion acknowledgement. If it
        // fires, no ad may follow it at this exit. `review_prompt_eligible` is
        // raised by the coordinator before it calls the system API.
        let decision = growth.review.requestReviewIfEligible()
        if decision == .eligible {
            growth.telemetry.capture(.reviewPromptRequested, properties: [
                "completed_set_count": .int(growth.review.state.completedSetCount),
                "streak_bucket": .token(ReviewRequestPolicy.streakBucket(streak.currentStreak)),
            ])
            growth.monetization.setBlocker(.review, active: true)
        }

        let completedSets = growth.review.state.completedSetCount

        analyticsEnabled = growth.telemetry.isEnabled
        diagnosticsEnabled = growth.diagnostics.isEnabled
        if ConsentPromptPolicy.eligible(completedSetCount: completedSets,
                                        alreadyShown: growth.consentPromptShown) {
            showConsentPrompt = true
            growth.noteConsentPromptShown()
            growth.monetization.setBlocker(.consent, active: true)
        }

        if NotificationPolicy.primerEligible(
            completedSetCount: completedSets,
            primerAlreadyShown: growth.notifications.primerAlreadyShown,
            remindersEnabled: growth.notifications.remindersEnabled,
            consentPromptVisible: showConsentPrompt) {
            showPrimer = true
            growth.notifications.notePrimerShown()
            growth.telemetry.capture(.notificationPrimerViewed,
                                     properties: ["entry_point": .token(EconEntryPoint.sessionComplete.rawValue)])
        }
    }

    private func enableReminders() {
        // A system permission dialog is an interruption; no ad may follow it at
        // this exit, and it disqualifies the session for a rating request.
        growth.monetization.setBlocker(.notification, active: true)
        growth.review.noteNegativeSessionEvent(.notificationPrompt)
        growth.notifications.enableReminders { granted in
            growth.recordNotificationAuthorizationResult(granted: granted)
        }
        showPrimer = false
    }

    /// The one 1.1 interstitial placement: after the session-complete state and
    /// before returning to Home.
    private func finish() {
        guard !exiting else { return }
        exiting = true
        Task {
            let outcome = await growth.monetization.presentIfEligibleAtSetExit()
            switch outcome {
            case .presented:
                growth.review.noteNegativeSessionEvent(.ad)
                growth.telemetry.capture(.adImpression,
                                         properties: ["placement": .token(EconAdPlacement.dailySetExit.rawValue)])
            case .notEligible, .noAdAvailable, .presentationFailed:
                break
            }
            growth.monetization.setBlocker(.review, active: false)
            growth.monetization.setBlocker(.notification, active: false)
            growth.monetization.setBlocker(.consent, active: false)
            onDone()
        }
    }

    private static func durationBucket(_ cardsCount: Int) -> String {
        switch cardsCount {
        case ..<4: return "short"
        case 4..<9: return "medium"
        default: return "long"
        }
    }

}
