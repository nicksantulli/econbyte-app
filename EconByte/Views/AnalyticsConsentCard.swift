import SwiftUI

// MARK: - First-open consent card (Owner order 2026-09-14; factory pattern)
//
// Mounted by `EconByteApp` as an in-ZStack overlay (not a sheet) so it sits
// UNDER the cold-launch StudioIntro overlay (zIndex 100) and is revealed when the
// intro fades — no race with the splash, no sheet popping over the brand beat.
// While it is up no ad may present (`EconAdBlocker.consent`) and the rating ask
// is deferred for the session (`EconNegativeSessionEvent.consentForm`).

struct AnalyticsConsentCard: View {
    let showsDiagnosticsAddendum: Bool
    let onDecision: (Bool) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var titleFocused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 16) {
                Label(FirstOpenConsentCopy.title, systemImage: "chart.bar.fill")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundColor(Econ.white)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($titleFocused)

                Text(FirstOpenConsentCopy.body)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(Econ.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)

                if showsDiagnosticsAddendum {
                    Text(FirstOpenConsentCopy.diagnosticsAddendum)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(Econ.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(FirstOpenConsentCopy.footer)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(Econ.subtext)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 10) {
                    Button(FirstOpenConsentCopy.accept) { onDecision(true) }
                        .buttonStyle(PrimaryButton())
                        .accessibilityIdentifier("consentAcceptButton")

                    Button(FirstOpenConsentCopy.decline) { onDecision(false) }
                        .buttonStyle(SecondaryButton())
                        .accessibilityIdentifier("consentDeclineButton")
                }
                .padding(.top, 4)
            }
            .padding(24)
            .frame(maxWidth: 420)
            .background(Econ.ocean)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Econ.tide.opacity(0.6), lineWidth: 1)
            )
            .padding(20)
        }
        .accessibilityIdentifier("analyticsConsentCard")
        .transition(reduceMotion ? .identity : .opacity)
        .onAppear { titleFocused = true }
    }
}
