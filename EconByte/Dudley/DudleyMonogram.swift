import SwiftUI

// MARK: - Dudley Studio Kit
//
// Shared, drop-in studio-branding component used across every Dudley app
// (Vibe Rater, Powell Prowl, and the default for all future apps).
//
// This file has ZERO app-specific dependencies — copy the whole `Dudley/`
// folder into any Dudley app and it compiles as-is. The canonical source of
// truth lives in the Dudley vault under `vault/engineering/dudley-studio-kit/`.
//
// Why a native Canvas instead of a baked PNG (per DUD-146 design handoff):
// the monogram is a handful of vector primitives, so rendering it natively
// scales crisply at every point size with no @1x/@2x/@3x asset duplication
// and no SVG→PNG build tooling (rsvg/cairo are not on the build box). The
// geometry below is a faithful translation of the canonical
// `monogram.svg` (1024×1024 master).

/// The Dudley Development monogram: a white geometric "D" with a cyan
/// "cursor" accent on a deep-navy tile. Renders at any `size` (square).
struct DudleyMonogram: View {
    /// Edge length in points. The tile is always square.
    var size: CGFloat
    /// Continuous corner radius. Defaults to the brand ratio (16pt @ 72pt).
    var cornerRadius: CGFloat? = nil

    private var corner: CGFloat { cornerRadius ?? size * (16.0 / 72.0) }

    var body: some View {
        Canvas { ctx, sz in
            let s = sz.width / 1024.0
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }

            // Background — subtle navy gradient (#12243E apex → #080E1A base).
            ctx.fill(
                Path(CGRect(origin: .zero, size: sz)),
                with: .linearGradient(
                    Gradient(colors: [
                        Color(red: 0.071, green: 0.141, blue: 0.243),
                        Color(red: 0.031, green: 0.055, blue: 0.102),
                    ]),
                    startPoint: CGPoint(x: sz.width / 2, y: 0),
                    endPoint: CGPoint(x: sz.width / 2, y: sz.height)
                )
            )

            // The "D": stem + right-pointing bowl, with an inner counter void.
            // Arcs are exact bezier approximations of the SVG's elliptical
            // arcs (quarter-ellipse kappa = 0.5523).
            let k: CGFloat = 0.5523
            var d = Path()
            // Outer D (clockwise): stem top → bowl → stem bottom.
            d.move(to: p(220, 160))
            d.addLine(to: p(340, 160))
            d.addCurve(to: p(800, 512),
                       control1: p(340 + 460 * k, 160),
                       control2: p(800, 512 - 352 * k))
            d.addCurve(to: p(340, 864),
                       control1: p(800, 512 + 352 * k),
                       control2: p(340 + 460 * k, 864))
            d.addLine(to: p(220, 864))
            d.closeSubpath()
            // Inner counter (punched out via even-odd fill).
            d.move(to: p(340, 295))
            d.addCurve(to: p(680, 512),
                       control1: p(340 + 340 * k, 295),
                       control2: p(680, 512 - 217 * k))
            d.addCurve(to: p(340, 729),
                       control1: p(680, 512 + 217 * k),
                       control2: p(340 + 340 * k, 729))
            d.closeSubpath()
            ctx.fill(d, with: .color(.white), style: FillStyle(eoFill: true))

            // Cyan "cursor blink" accent inside the upper-right of the counter.
            let accent = CGRect(x: 543 * s, y: 410 * s, width: 82 * s, height: 82 * s)
            ctx.fill(
                Path(roundedRect: accent, cornerRadius: 15 * s),
                with: .color(Color(red: 0.0, green: 0.784, blue: 0.831))  // #00C8D4
            )
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .accessibilityHidden(true)
    }
}

// MARK: - Brand tokens

enum DudleyBrand {
    /// Studio intro background — exactly matches the monogram tile base so the
    /// mark appears to materialise from the screen (#0B1829 / dd-navy).
    static let navy = Color(red: 0.043, green: 0.094, blue: 0.161)
    /// Intro wordmark primary (#E8EEFF).
    static let wordmarkPrimary = Color(red: 0.910, green: 0.933, blue: 1.0)
    /// Intro wordmark secondary — "DEVELOPMENT" (#8899BB).
    static let wordmarkSecondary = Color(red: 0.533, green: 0.600, blue: 0.733)
    /// Cyan accent (#00C8D4).
    static let cyan = Color(red: 0.0, green: 0.784, blue: 0.831)

    static let siteURL = URL(string: "https://dudleyapps.com")!
    static let tagline = "Making small apps you'll actually use."
}

#Preview("Monogram sizes") {
    VStack(spacing: 24) {
        DudleyMonogram(size: 72)
        DudleyMonogram(size: 56)
        DudleyMonogram(size: 28, cornerRadius: 6)
    }
    .padding()
    .background(Color.black)
}
