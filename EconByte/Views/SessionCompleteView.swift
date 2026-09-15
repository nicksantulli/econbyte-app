import SwiftUI

struct SessionCompleteView: View {
    let title: String
    let cardsCount: Int
    /// False where the placement matrix allows no interstitial (a bookmarks
    /// review is saved reading), so nothing is armed at that exit.
    var offersSetExitAd = true
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
        VStack(spacing: EconSpace.xl) {
            Spacer()
            Text("🔥")
                .font(.system(.largeTitle))
                .accessibilityHidden(true)
            Text("Streak: \(streak.currentStreak) day\(streak.currentStreak == 1 ? "" : "s")")
                .font(EconType.title)
                .foregroundColor(EconColor.accentText)
                .multilineTextAlignment(.center)
            Text("\(title) · \(cardsCount) cards")
                .font(EconType.body)
                .foregroundColor(EconColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, EconSpace.xxl)
            // The one "not advice" line for a card session, at its end.
            Text(PlanCopy.notAdvice)
                .font(EconType.footnote)
                .foregroundColor(EconColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, EconSpace.xl)
                .accessibilityIdentifier("sessionNotAdvice")

            if showConsentPrompt { consentPrompt }
            if showPrimer { primer }

            Spacer()
            Button("Done") { finish() }
                .buttonStyle(PrimaryButton())
                .disabled(exiting)
                .accessibilityIdentifier("sessionCompleteDoneButton")
                .padding(.horizontal, EconSpace.xl)
                .padding(.bottom, EconSpace.xxl)
        }
        .task { await onAppearOnce() }
    }

    // MARK: Reminder primer (design section 11.1)

    /// Non-blocking, contextual, and it does not itself prompt: the system dialog
    /// appears only if the reader taps Turn On Reminders.
    private var primer: some View {
        VStack(spacing: EconSpace.xs) {
            Text(NotificationPolicy.primerHeadline)
                .font(EconType.headline)
                .foregroundColor(EconColor.textPrimary)
                .multilineTextAlignment(.center)
            Text(NotificationPolicy.primerBody)
                .font(EconType.footnote)
                .foregroundColor(EconColor.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: EconSpace.l) {
                Button("Not now") { showPrimer = false }
                    .font(EconType.subheadline)
                    .foregroundColor(EconColor.textSecondary)
                    .frame(minHeight: EconSize.tapTarget)
                    .accessibilityIdentifier("notificationPrimerDismissButton")
                Button("Turn On Reminders") { enableReminders() }
                    .buttonStyle(EconLinkButton())
                    .accessibilityIdentifier("notificationPrimerEnableButton")
            }
        }
        .frame(maxWidth: .infinity)
        .econCard()
        .padding(.horizontal, EconSpace.xl)
    }

    // MARK: Consent presentation (design section 10.1)

    /// Both choices, offered once, after the first completed set — never on
    /// first launch. Non-blocking and default off; declining changes nothing.
    private var consentPrompt: some View {
        VStack(spacing: EconSpace.xs) {
            Text("Help improve EconByte?")
                .font(EconType.headline)
                .foregroundColor(EconColor.textPrimary)
                .multilineTextAlignment(.center)
            Text("Two separate, optional choices. Both are off unless you turn them on, and neither affects your cards, streak, bookmarks, purchases, or ads. What you read or save is never shared.")
                .font(EconType.caption)
                .foregroundColor(EconColor.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Toggle("Share usage analytics", isOn: Binding(
                get: { analyticsEnabled },
                set: { value in
                    analyticsEnabled = value
                    growth.setAnalyticsEnabled(value, entryPoint: .sessionComplete)
                }))
                .font(EconType.subheadline)
                .foregroundColor(EconColor.textPrimary)
                .tint(EconColor.accent)
                .accessibilityIdentifier("consentPromptAnalyticsToggle")
            Toggle("Share crash diagnostics", isOn: Binding(
                get: { diagnosticsEnabled },
                set: { value in
                    diagnosticsEnabled = value
                    growth.setDiagnosticsEnabled(value, entryPoint: .sessionComplete)
                }))
                .font(EconType.subheadline)
                .foregroundColor(EconColor.textPrimary)
                .tint(EconColor.accent)
                .accessibilityIdentifier("consentPromptDiagnosticsToggle")
            Button("Done") { showConsentPrompt = false }
                .buttonStyle(EconLinkButton())
                .accessibilityIdentifier("consentPromptDoneButton")
        }
        .frame(maxWidth: .infinity)
        .econCard()
        .padding(.horizontal, EconSpace.xl)
    }

    // MARK: Behaviour

    private func onAppearOnce() async {
        growth.monetization.noteSetCompleted(normally: true)
        // review-rules-v2 (1.1.3): the size of the deck just finished decides
        // whether this completion is a moment to ask (5+ cards) or only counts.
        growth.review.noteSetCompleted(cardsViewed: cardsCount)
        // RECONCILED (1.1.2): lineage A's `daily_set_completed` carried a
        // `set_id`, an exact `card_count` and an exact `streak_day`, all three
        // prohibited by the shipped schema. The completion is now reported by
        // `CardModeView`'s `session_ended_v1` (bucketed cards, bucketed
        // duration), which fires for abandoned sessions too and therefore has a
        // denominator this event never had.

        // Decide the contextual offers BEFORE the rating ask, so a screen that is
        // about to carry the consent primer — or an exit that is about to carry
        // the ATT dialog (build 13) — is never also the moment we ask for a
        // rating. Both defer the ask to a later healthy session; neither spends it.
        let offersConsent = ConsentPromptPolicy.eligible(
            completedSetCount: growth.review.state.completedSetCount,
            alreadyShown: growth.consentPromptShown)
        if offersConsent {
            growth.review.noteNegativeSessionEvent(.consentForm)
        }

        // The rating request comes after the completion acknowledgement. If it
        // fires, no ad may follow it at this exit. `review_prompt_eligible` is
        // raised by the coordinator before it calls the system API.
        let decision = growth.review.requestReviewIfEligible()
        if decision == .eligible {
            // The attempt itself is emitted at the moment the system sheet is
            // actually requested (`EconGrowth.requestSystemReview`), so a run
            // that is suppressed for automation does not report an ask that
            // never happened.
            growth.monetization.setBlocker(.review, active: true)
        }

        let completedSets = growth.review.state.completedSetCount

        analyticsEnabled = growth.telemetry.isAnalyticsEnabled
        diagnosticsEnabled = growth.diagnostics.isDiagnosticsEnabled
        if offersConsent {
            showConsentPrompt = true
            growth.noteConsentPromptShown()
            growth.monetization.setBlocker(.consent, active: true)
        }

        if NotificationPolicy.primerEligible(
            completedSetCount: completedSets,
            primerAlreadyShown: growth.notifications.primerAlreadyShown,
            remindersEnabled: growth.notifications.remindersEnabled,
            consentPromptVisible: showConsentPrompt,
            authorizationDenied: growth.notifications.authorization == .denied) {
            showPrimer = true
            growth.notifications.notePrimerShown()
            growth.recordNotificationPrimerViewed(entryPoint: .sessionComplete)
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
    ///
    /// Phase 25: the exit is DECIDED here and PRESENTED by the shell. 1.1.2–1.1.5
    /// presented the interstitial from inside the card cover and then called
    /// `onDone()` (which dismisses that cover) on the same turn, so the ad was
    /// torn down as it appeared. Now the break is armed while this screen's
    /// blockers (a rating request, the consent offer, a notification prompt)
    /// still count, the blockers are cleared, the cover is dismissed, and
    /// `RootTabView` presents from the window's root once the cover has gone
    /// (`EconGrowth.resolvePendingSetExitBreak`).
    ///
    /// 1.1.4: ATT is asked at first launch, never here. An install that has not
    /// answered it still gets no ad: `startAdsIfPermitted` and the decision are
    /// both gated on it.
    private func finish() {
        guard !exiting else { return }
        exiting = true
        showConsentPrompt = false
        showPrimer = false
        growth.monetization.startAdsIfPermitted()
        if offersSetExitAd {
            growth.monetization.armSetExitBreak()
        }
        growth.monetization.setBlocker(.review, active: false)
        growth.monetization.setBlocker(.notification, active: false)
        growth.monetization.setBlocker(.consent, active: false)
        growth.monetization.setBlocker(.systemPrompt, active: false)
        onDone()
    }

}
