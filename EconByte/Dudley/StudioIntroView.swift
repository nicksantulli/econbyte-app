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
//   • SHORT: ~3.4s total — the final reveal lingers ~1.5s longer; skippable, auto-dismisses.
//   • SKIPPABLE on tap.
//   • COLD-LAUNCH ONLY — never on resume/foreground (see StudioIntroGate), so it
//     never nags returning users or dents retention.
//   • REDUCE MOTION: collapses to a simple cross-fade of the final mark+wordmark.
//   • Real content loads behind it (the host mounts the app under the overlay),
//     so it is not dead time.
//
// DUD-241 POLISH ("a bit glitchy" → buttery): the timeline was driven by a pile
// of overlapping `DispatchQueue.asyncAfter` + `withAnimation` calls whose
// durations didn't meet at the seams, so a few properties snapped between
// phases (iron-glow pulse killed in 0.05s, markGlow/markOpacity set with no
// animation, a hard 3px shake jump, smoke Canvas redrawing every frame for the
// whole intro). This version drives everything off a single normalised clock
// (`clock`, 0→1) using a TimelineView, so every value is a continuous function
// of time — no phase-handoff pops are possible. The shake is a damped decaying
// sine, the glow pulse is a smooth cosine, and the smoke Canvas only renders
// during its active window. Same creative concept + brand look, smooth exec.

/// The animated studio card. Drives its own single-clock timeline and calls
/// `onComplete` when finished (or when tapped to skip).
struct StudioIntroView: View {
    var onComplete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Single source of truth for the whole animation: a normalised clock driven
    // continuously from 0→1 by one spring. Every visual property below is a pure
    // function of `clock`, so there are no discrete phase hand-offs to glitch.
    @State private var clock: Double = 0
    @State private var startDate = Date()

    @State private var containerOpacity: Double = 1
    @State private var finished = false
    @State private var started = false

    // Total animated wall-clock duration of the main sequence (the clock maps
    // 0→1 across this many seconds). Hold + fade happen after clock reaches 1.
    private let runtime: Double = 1.50

    // Mark display size — 280×156pt preserves the 1150:640 ratio (storyboard).
    private let markWidth: CGFloat = 280
    private var markHeight: CGFloat { markWidth * 640.0 / 1150.0 }

    var body: some View {
        // One TimelineView gives us a smooth, frame-synced sample of elapsed
        // time. We derive `t` (0→1) from it during the run; the `clock` spring
        // is kept in lock-step so tap-to-skip / reduce-motion paths can short
        // circuit cleanly. Continuous sampling means no asyncAfter seams.
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: finished)) { tl in
            let t = reduceMotion ? reducedProgress(tl.date) : progress(tl.date)
            content(t: t)
        }
        .opacity(containerOpacity)
        .contentShape(Rectangle())
        .onTapGesture { skip() }
        .accessibilityElement()
        .accessibilityLabel("Made by Dudley Development")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Double tap to skip the intro")
        .onAppear(perform: start)
    }

    // MARK: Derived, continuous animation values (pure functions of t ∈ [0,1])

    @ViewBuilder
    private func content(t: Double) -> some View {
        // --- Phase windows (all overlapping & continuous; eased internally) ---
        // hide fade-in:        0.00 → 0.14
        // iron descent:        0.06 → 0.40   (contact at 0.40)
        // contact shake/smoke: 0.40 → ~0.70
        // iron lift:           0.42 → 0.66
        // mark glow flare:     0.40 → 0.74
        // cream settle:        0.62 → 0.86
        // wordmark fade:       0.74 → 0.94

        let hideOpacity   = 1.0   // opaque from frame 0 — the app behind must NEVER flash through
        // Iron eases down with a slight overshoot-free settle into contact.
        let descend       = easeInOut(smoothstep(0.06, 0.40, t))
        let ironOffset    = lerp(-340, 0, descend)
        let ironDescOpac  = smoothstep(0.06, 0.20, t)
        // Iron lifts after contact and fades as it leaves.
        let lift          = easeInOut(smoothstep(0.42, 0.66, t))
        let ironOffsetAll = lerp(ironOffset, -360, lift)
        let ironOpacity   = ironDescOpac * (1 - smoothstep(0.42, 0.62, t))
        // Smooth glow pulse on the descending iron (cosine, no repeatForever pop).
        let pulse         = 0.5 - 0.5 * cos(t * 18.0)          // ~1.4 cycles over descent
        let ironGlow      = ironOpacity * lerpD(0.45, 1.0, pulse)

        // Contact: scorch appears, mark glows hot then cools, smoke rises.
        let scorchOpacity = smoothstep(0.40, 0.50, t)
        let glowFlare     = bump(0.40, 0.74, t)                // 0→1→0 hot flare
        let markGlow      = glowFlare
        let markOpacity   = smoothstep(0.40, 0.58, t)
        // Smoke active only within its window; 0 outside ⇒ Canvas early-outs.
        let smokeRaw      = smoothstep(0.40, 1.00, t)
        let smoke         = (t > 0.40 && t < 0.96) ? smokeRaw : 0
        let creamReveal   = easeInOut(smoothstep(0.62, 0.86, t))
        let wordmark      = smoothstep(0.74, 0.94, t)

        // Damped decaying shake on contact (a few cycles easing to 0), not a jump.
        let shake         = shakeOffset(t)

        ZStack {
            // Background crossfades from a warm hide brown to brand cream.
            // Opaque hide from frame 0 (see start()) prevents any launch flash.
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
                    .offset(y: ironOffsetAll)
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
            .opacity(wordmark)
            .offset(y: markHeight / 2 + 44)
        }
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

    // MARK: Single-clock timeline

    /// Main-sequence progress 0→1 across `runtime`, then clamps at 1 while the
    /// card holds and fades. Continuous — sampled every frame by TimelineView.
    private func progress(_ now: Date) -> Double {
        guard started else { return 0 }
        let elapsed = now.timeIntervalSince(startDate)
        // Slow (never freeze) the smoke-rise window so it lingers smoothly —
        // time is stretched continuously across [tA,tB]; the clock keeps moving.
        let tA = 0.40, tB = 0.64, extra = 0.8
        let rtA = tA * runtime
        let segStretched = (tB - tA) * runtime + extra
        if elapsed <= rtA { return elapsed / runtime }
        if elapsed <= rtA + segStretched {
            let frac = (elapsed - rtA) / segStretched
            return tA + frac * (tB - tA)
        }
        return min(1, max(0, (elapsed - extra) / runtime))
    }

    /// Reduce-Motion progress: just a calm fade-in of cream + mark + wordmark.
    private func reducedProgress(_ now: Date) -> Double {
        guard started else { return 0 }
        let elapsed = now.timeIntervalSince(startDate)
        return min(1, max(0, elapsed / 0.65))
    }

    private func start() {
        guard !started else { return }   // fire exactly once
        started = true
        startDate = Date()

        // Schedule the single hold→fade→dismiss tail off the same clock origin.
        // (One timer for the tail; the visuals themselves are all continuous.)
        let holdEnd: Double = reduceMotion ? 2.75 : 3.9
        let fadeOut: Double = 0.30
        DispatchQueue.main.asyncAfter(deadline: .now() + holdEnd) {
            guard !finished else { return }
            withAnimation(.easeInOut(duration: fadeOut)) { containerOpacity = 0 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + holdEnd + fadeOut) {
            finish()
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

    // MARK: Easing / shaping helpers (keep the timeline buttery & continuous)

    /// Smooth 0→1 ramp between edges `a` and `b` (Hermite smoothstep, C¹).
    private func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
        guard b > a else { return x >= b ? 1 : 0 }
        let u = min(1, max(0, (x - a) / (b - a)))
        return u * u * (3 - 2 * u)
    }

    /// Extra ease on an already-normalised 0→1 value.
    private func easeInOut(_ u: Double) -> Double { u * u * (3 - 2 * u) }

    /// Symmetric 0→1→0 bump across [a,b] — used for the hot-glow flare.
    private func bump(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let u = smoothstep(a, b, x)
        return sin(u * Double.pi)   // 0 at edges, 1 at centre, smooth
    }

    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat {
        a + (b - a) * CGFloat(t)
    }
    private func lerpD(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }

    /// Damped decaying lateral camera shake centred on contact (t≈0.40).
    /// A few cycles of a sine enveloped by an exponential decay → eases to 0,
    /// never a hard jump. Amplitude ~3.5px, fully settled by t≈0.62.
    private func shakeOffset(_ t: Double) -> CGFloat {
        let start = 0.40, span = 0.22
        guard t >= start, t <= start + span else { return 0 }
        let local = (t - start) / span          // 0→1 across the shake window
        let decay = exp(-5.5 * local)            // envelope → 0
        let osc = sin(local * Double.pi * 6.0)   // ~3 cycles
        return CGFloat(3.5 * decay * osc)
    }
}

// MARK: - Smoke wisps

/// A handful of cream smoke wisps that rise and fade as `progress` goes 0→1.
/// Built from quad-curve bezier paths per the storyboard's smoke note.
///
/// DUD-241: the host only feeds a non-zero `progress` during the smoke window
/// (≈0.40→0.96 of the intro), so this Canvas is dormant — and returns
/// immediately on the `progress <= 0` guard — outside that span rather than
/// redrawing every frame for the whole intro. Wisp count trimmed 5→4 to keep
/// first-launch frames cheap while the app is still warming.
private struct SmokeWisps: View {
    var progress: Double

    var body: some View {
        // Drawing nothing (progress 0) is a cheap no-op; SwiftUI won't churn the
        // Canvas when its only input is unchanged at 0.
        Canvas { ctx, size in
            guard progress > 0 else { return }
            let count = 4
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
        .opacity(progress > 0 ? 1 : 0)   // fully detached visually when dormant
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
///
/// DUD-241: `showIntro` is seeded once from `StudioIntroState` and the flag is
/// flipped synchronously in `init` (not `.onAppear`), so even if the gate's body
/// re-evaluates on a state change the intro can never re-trigger. The brown hide
/// field is painted under the overlay opaquely from the first frame to match the
/// LaunchScreen background (no white/black FOUC at hand-off).
struct StudioIntroGate<Content: View>: View {
    @ViewBuilder var content: Content

    @State private var showIntro: Bool

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
        // Decide-and-latch exactly once, synchronously, at gate construction.
        let shouldShow = !StudioIntroState.hasShownThisLaunch
                         && !StudioIntroState.suppressedForTesting
        StudioIntroState.hasShownThisLaunch = true
        _showIntro = State(initialValue: shouldShow)
    }

    var body: some View {
        ZStack {
            content   // real app mounts + loads behind the overlay
            if showIntro {
                StudioIntroView { showIntro = false }
                    .transition(.opacity)
                    .zIndex(100)
            }
        }
    }
}

#Preview {
    StudioIntroView {}
}
