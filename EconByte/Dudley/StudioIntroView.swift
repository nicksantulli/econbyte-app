import SwiftUI

// MARK: - Dudley Studio Kit — launch attribution intro
//
// A brief, tasteful studio signature shown AFTER launch (not the LaunchScreen —
// Apple HIG requires the launch screen to mimic the first real screen, so the
// branded moment happens in-app). Design: DUD-146.
//
// App-Review / best-practice guardrails (DUD-147):
//   • IN-APP, transitions to the home screen — never the LaunchScreen storyboard.
//   • SHORT: 1.35s total, ≤1.5s hard cap, auto-dismisses.
//   • SKIPPABLE on tap.
//   • COLD-LAUNCH ONLY — never on resume/foreground (see StudioIntroGate), so it
//     never nags returning users or dents retention.
//   • Real content loads behind it (the host mounts the app under the overlay),
//     so it is not dead time.

/// The animated studio card. Drives its own timeline and calls `onComplete`
/// when finished (or when tapped to skip).
struct StudioIntroView: View {
    var onComplete: () -> Void

    @State private var monogramOpacity: Double = 0
    @State private var monogramScale: CGFloat = 0.92
    @State private var wordmarkOpacity: Double = 0
    @State private var containerOpacity: Double = 1
    @State private var finished = false

    var body: some View {
        ZStack {
            DudleyBrand.navy.ignoresSafeArea()

            VStack(spacing: 14) {
                DudleyMonogram(size: 72)
                    .opacity(monogramOpacity)
                    .scaleEffect(monogramScale)

                VStack(spacing: 4) {
                    Text("Dudley")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(DudleyBrand.wordmarkPrimary)
                        .tracking(-0.4)
                    Text("DEVELOPMENT")
                        .font(.system(size: 10, weight: .light))
                        .foregroundColor(DudleyBrand.wordmarkSecondary)
                        .tracking(4)
                }
                .opacity(wordmarkOpacity)
            }
            .offset(y: -16)
            .opacity(containerOpacity)
        }
        // Skippable: a tap fast-fades and dismisses.
        .contentShape(Rectangle())
        .onTapGesture { skip() }
        .accessibilityElement()
        .accessibilityLabel("Made by Dudley Development")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Double tap to skip the intro")
        .onAppear { runSequence() }
    }

    private func runSequence() {
        // Phase 1 — monogram appears (0 → 280ms).
        withAnimation(.easeOut(duration: 0.28)) {
            monogramOpacity = 1
            monogramScale = 1.0
        }
        // Phase 2 — wordmark reveal, offset 180ms for a two-beat read.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            withAnimation(.easeOut(duration: 0.3)) { wordmarkOpacity = 1 }
        }
        // Phase 3 — hold, then fade the whole card (900 → 1350ms).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            withAnimation(.easeIn(duration: 0.45)) { containerOpacity = 0 }
        }
        // Phase 4 — dismiss.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.35) { finish() }
    }

    /// Tap-to-skip: quick fade so the gesture feels responsive.
    private func skip() {
        guard !finished else { return }
        withAnimation(.easeIn(duration: 0.18)) { containerOpacity = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { finish() }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        onComplete()
    }
}

// MARK: - Cold-launch gate

/// Process-lifetime flag (lives outside the generic gate, since generic types
/// can't hold static stored properties). Resets only on a true cold start, so
/// the intro never reappears on foreground/resume within the same process.
private enum StudioIntroState {
    static var hasShownThisLaunch = false

    /// QA / UI-test escape hatch: launch with `-skipStudioIntro` to bypass.
    static var suppressedForTesting: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-skipStudioIntro") || args.contains("-uitestResult")
    }
}

/// Drop-in overlay that shows `StudioIntroView` exactly once per cold launch.
///
/// Usage — wrap the app's root once:
/// ```swift
/// StudioIntroGate { RootView() }
/// ```
struct StudioIntroGate<Content: View>: View {
    @ViewBuilder var content: Content

    @State private var showIntro: Bool = !StudioIntroState.hasShownThisLaunch

    var body: some View {
        ZStack {
            content   // real app mounts + loads behind the overlay
            if showIntro && !StudioIntroState.suppressedForTesting {
                StudioIntroView { showIntro = false }
                    .transition(.opacity)
                    .zIndex(100)
            }
        }
        .onAppear { StudioIntroState.hasShownThisLaunch = true }
    }
}

#Preview {
    StudioIntroView {}
}
