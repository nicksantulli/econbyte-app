import SwiftUI

// MARK: - Dudley Studio Kit — launch attribution intro (longhorn-D reveal)
//
// A brief, tasteful studio signature shown AFTER launch (not the LaunchScreen —
// Apple HIG requires the launch screen to mimic the first real screen, so the
// branded moment happens in-app). Design: DUD-146 / animation DUD-193.
//
// The animation is the "Longhorn-D Reveal" short version from
// vault/design/brand/dudley/final/animation-storyboard-longhorn-d.md:
//   1. Warm cowhide field fades in.
//   2. A branding iron (the DudleyMark shape, glowing amber) descends.
//   3. It contacts the hide — camera shake, white smoke jets from the mark,
//      the hide scorches dark under the mark.
//   4. The iron lifts away; the mark glows hot amber beneath rising smoke.
//   5. Smoke clears, background settles to brand cream, the DudleyMark fades
//      in crisp with the "Dudley DEVELOPMENT" wordmark below.
// Total ≈ 1.6s, hard-capped, auto-dismisses.
//
// App-Review / best-practice guardrails (DUD-147):
//   • IN-APP, transitions to the home screen — never the LaunchScreen storyboard.
//   • SHORT: ~1.6s total, ≤1.9s hard cap, auto-dismisses.
//   • SKIPPABLE on tap.
//   • COLD-LAUNCH ONLY — never on resume/foreground (see StudioIntroGate), so it
//     never nags returning users or dents retention.
//   • REDUCE MOTION: collapses to a simple cross-fade of the final mark+wordmark.
//   • Real content loads behind it (the host mounts the app under the overlay),
//     so it is not dead time.

/// The animated studio card. Drives its own timeline and calls `onComplete`
/// when finished (or when tapped to skip).
struct StudioIntroView: View {
    var onComplete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Background: hide tone → cream.
    @State private var hideOpacity: Double = 0      // cowhide field fade-in
    @State private var creamReveal: Double = 0      // 0 = hide, 1 = clean cream

    // Branding iron.
    @State private var ironOffset: CGFloat = -340   // descends from above
    @State private var ironGlow: Double = 0         // pulsing tip glow
    @State private var ironOpacity: Double = 0
    @State private var shake: CGFloat = 0           // 1f camera shake on contact

    // Scorch + reveal of the final mark.
    @State private var scorchOpacity: Double = 0    // dark brand under the iron
    @State private var markGlow: Double = 0         // hot amber glow on the mark
    @State private var markOpacity: Double = 0      // final crisp mark
    @State private var smoke: Double = 0            // smoke wisps drive (0→1)

    @State private var wordmarkOpacity: Double = 0
    @State private var containerOpacity: Double = 1
    @State private var finished = false

    // Mark display size — 280×156pt preserves the 1150:640 ratio (storyboard).
    private let markWidth: CGFloat = 280
    private var markHeight: CGFloat { markWidth * 640.0 / 1150.0 }

    var body: some View {
        ZStack {
            // Background crossfades from a warm hide brown to brand cream.
            ZStack {
                hideField.opacity(1 - creamReveal)
                DudleyBrand.cream.opacity(creamReveal)
            }
            .opacity(hideOpacity)
            .ignoresSafeArea()

            ZStack {
                // (a) Scorched brand left under the mark as the iron presses.
                Image("DudleyMark")
                    .resizable().renderingMode(.template)
                    .aspectRatio(contentMode: .fit)
                    .foregroundColor(DudleyBrand.darkBrown)
                    .frame(width: markWidth, height: markHeight)
                    .opacity(scorchOpacity)
                    .blur(radius: 2 * (1 - markOpacity))

                // (b) The final crisp mark, with a fading hot-amber glow.
                Image("DudleyMark")
                    .resizable().renderingMode(.original)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: markWidth, height: markHeight)
                    .opacity(markOpacity)
                    .shadow(color: DudleyBrand.amber.opacity(markGlow),
                            radius: 22 * markGlow)
                    .shadow(color: DudleyBrand.rust.opacity(markGlow * 0.7),
                            radius: 40 * markGlow)

                // (c) Smoke wisps rising from the mark edges on contact.
                SmokeWisps(progress: smoke)
                    .frame(width: markWidth + 40, height: markHeight + 120)
                    .offset(y: -markHeight * 0.35)
                    .allowsHitTesting(false)

                // (d) The branding iron — the mark shape, glowing, descending.
                Image("DudleyMark")
                    .resizable().renderingMode(.template)
                    .aspectRatio(contentMode: .fit)
                    .foregroundColor(DudleyBrand.darkBrown)
                    .frame(width: markWidth, height: markHeight)
                    .shadow(color: DudleyBrand.rust.opacity(ironGlow),
                            radius: 18 * ironGlow)
                    .shadow(color: DudleyBrand.amber.opacity(ironGlow),
                            radius: 30 * ironGlow)
                    .opacity(ironOpacity)
                    .offset(y: ironOffset)
            }
            .offset(x: shake)

            // Wordmark below the mark.
            VStack(spacing: 4) {
                Text("Dudley")
                    .font(.system(size: 19, weight: .semibold, design: .serif))
                    .foregroundColor(DudleyBrand.wordmarkPrimary)
                    .tracking(-0.2)
                Text("DEVELOPMENT")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(DudleyBrand.wordmarkSecondary)
                    .tracking(4)
            }
            .opacity(wordmarkOpacity)
            .offset(y: markHeight / 2 + 44)
        }
        .opacity(containerOpacity)
        // Skippable: a tap fast-fades and dismisses.
        .contentShape(Rectangle())
        .onTapGesture { skip() }
        .accessibilityElement()
        .accessibilityLabel("Made by Dudley Development")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Double tap to skip the intro")
        .onAppear { reduceMotion ? runReduced() : runSequence() }
    }

    /// A warm cowhide-toned field (brown gradient with soft mottling) — stands
    /// in for the hide texture without shipping a photographic asset.
    private var hideField: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.42, green: 0.27, blue: 0.15),
                    Color(red: 0.27, green: 0.16, blue: 0.08),
                ],
                startPoint: .top, endPoint: .bottom
            )
            RadialGradient(
                colors: [Color.white.opacity(0.10), .clear],
                center: .center, startRadius: 0, endRadius: 380
            )
        }
    }

    // MARK: Timeline (storyboard short version, retimed for an in-app splash)

    private func runSequence() {
        // Frame 1 — hide fades in (0 → 0.18s).
        withAnimation(.easeOut(duration: 0.18)) { hideOpacity = 1 }

        // Frame 2 — iron descends + glow ignites (0.12 → 0.55s).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.easeIn(duration: 0.40)) {
                ironOpacity = 1
                ironOffset = 0
            }
            withAnimation(.easeInOut(duration: 0.20).repeatForever(autoreverses: true)) {
                ironGlow = 1
            }
        }

        // Frame 3 — CONTACT (~0.55s): camera shake, smoke jets, hide scorches.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            cameraShake()
            withAnimation(.easeOut(duration: 0.12)) { scorchOpacity = 1 }
            withAnimation(.easeOut(duration: 0.70)) { smoke = 1 }
        }

        // Frame 4 — iron lifts away, the mark glows hot amber (0.70 → 1.0s).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.70) {
            withAnimation(.easeInOut(duration: 0.05)) { ironGlow = 0 } // stop pulse
            withAnimation(.easeIn(duration: 0.30)) {
                ironOffset = -360
                ironOpacity = 0
            }
            markGlow = 1
            markOpacity = 1
            withAnimation(.easeOut(duration: 0.35)) { markGlow = 0 }
        }

        // Frame 5 — background settles to cream, wordmark fades in (1.0 → 1.4s).
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.00) {
            withAnimation(.easeInOut(duration: 0.40)) { creamReveal = 1 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.15) {
            withAnimation(.easeOut(duration: 0.30)) { wordmarkOpacity = 1 }
        }

        // Hold, then fade the whole card out and dismiss.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.60) {
            withAnimation(.easeIn(duration: 0.30)) { containerOpacity = 0 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.90) { finish() }
    }

    /// Reduce Motion: no iron / smoke / shake — just a calm cross-fade of the
    /// final cream + mark + wordmark, then dismiss.
    private func runReduced() {
        creamReveal = 1
        withAnimation(.easeOut(duration: 0.35)) {
            hideOpacity = 1
            markOpacity = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
            withAnimation(.easeOut(duration: 0.30)) { wordmarkOpacity = 1 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.20) {
            withAnimation(.easeIn(duration: 0.30)) { containerOpacity = 0 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.55) { finish() }
    }

    /// One sharp 2px lateral camera shake on iron contact.
    private func cameraShake() {
        withAnimation(.linear(duration: 0.04)) { shake = 3 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
            withAnimation(.linear(duration: 0.04)) { shake = -3 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
                withAnimation(.linear(duration: 0.05)) { shake = 0 }
            }
        }
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

// MARK: - Smoke wisps

/// A handful of cream smoke wisps that rise and fade as `progress` goes 0→1.
/// Built from quad-curve bezier paths per the storyboard's smoke note.
private struct SmokeWisps: View {
    var progress: Double

    var body: some View {
        Canvas { ctx, size in
            guard progress > 0 else { return }
            let count = 5
            let rise = CGFloat(progress) * size.height * 0.9
            // Wisps appear, rise, and fade out over the second half of progress.
            let fade = 1.0 - max(0, (progress - 0.4) / 0.6)
            for i in 0..<count {
                let t = CGFloat(i) / CGFloat(count - 1)
                let baseX = size.width * (0.15 + 0.7 * t)
                let baseY = size.height - 8
                let sway: CGFloat = (i % 2 == 0 ? 14 : -14)
                var path = Path()
                path.move(to: CGPoint(x: baseX, y: baseY))
                path.addQuadCurve(
                    to: CGPoint(x: baseX + sway * 0.5, y: baseY - rise),
                    control: CGPoint(x: baseX + sway, y: baseY - rise * 0.5)
                )
                let width = 6.0 + 4.0 * Double(progress)
                ctx.stroke(
                    path,
                    with: .color(Color(red: 0.96, green: 0.93, blue: 0.86)
                        .opacity(0.55 * fade)),
                    style: StrokeStyle(lineWidth: width, lineCap: .round)
                )
            }
        }
        .blur(radius: 3)
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
