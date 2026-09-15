import SwiftUI

// MARK: - EconByte wordmark (1.1.4 shell redesign, Owner reference 2026-09-14)
//
// The Owner's reference: a bold, rounded geometric "EconByte" on the app's deep
// navy — "Econ" in white, "Byte" in warm amber — with a thin gold swoosh that
// starts low on the left beneath "Econ" and sweeps up and to the right, passing
// behind "Byte". Clean and premium, not playful.
//
// Drawn in SwiftUI (Text + a filled, tapered Path) rather than shipped as a
// bitmap, so it stays crisp at every size and Dynamic Type never resamples it.
// The same file renders the 1024×512 evidence preview on macOS
// (`EconWordmarkBanner`), which is why it depends on nothing but SwiftUI.

enum EconBrand {
    /// The icon's navy family (`Econ.ocean` is #0F3D52).
    static let navy = Color(red: 0x0F / 255, green: 0x3A / 255, blue: 0x4F / 255)
    static let navyDeep = Color(red: 0x0A / 255, green: 0x2A / 255, blue: 0x3A / 255)
    /// "Byte" and the swoosh: warm amber/gold.
    static let gold = Color(red: 0xF2 / 255, green: 0xB2 / 255, blue: 0x33 / 255)
    static let goldDeep = Color(red: 0xE0 / 255, green: 0x96 / 255, blue: 0x1A / 255)
    static let white = Color.white
}

/// The wordmark alone (transparent background), sized by its font size.
///
/// Accessibility: one element, read as "EconByte", with the header trait —
/// it is the app's title in the shared top bar.
struct EconWordmark: View {
    /// Point size of the letterforms. The top bar uses 30.
    var fontSize: CGFloat = 30

    var body: some View {
        letters(Text("\(Text("Econ").foregroundColor(EconBrand.white))\(Text("Byte").foregroundColor(EconBrand.gold))"))
            // Room under the baseline for the swoosh's low start, and to the
            // right for its tail, without the swoosh changing the layout box.
            .padding(.bottom, fontSize * 0.36)
            .padding(.trailing, fontSize * 0.38)
            .background(swooshLayer)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("EconByte")
            .accessibilityAddTraits(.isHeader)
    }

    private func letters(_ text: Text) -> some View {
        text
            .font(.system(size: fontSize, weight: .heavy, design: .rounded))
            .kerning(-0.025 * fontSize)
            .lineLimit(1)
            .fixedSize()
    }

    /// The swoosh, with a thin transparent gap cut around every letter where it
    /// passes behind them — so it reads as going *behind* "Byte" rather than
    /// striking through it, on any background.
    private var swooshLayer: some View {
        let gap = max(1, fontSize * 0.075)
        let offsets: [CGSize] = (0..<12).map { i in
            let a = Double(i) / 12 * 2 * .pi
            return CGSize(width: cos(a) * gap, height: sin(a) * gap)
        }
        return ZStack(alignment: .topLeading) {
            EconSwoosh()
                .fill(LinearGradient(colors: [EconBrand.goldDeep, EconBrand.gold],
                                     startPoint: .leading, endPoint: .trailing))
            // Only where the tail climbs behind the final "e": under the rest
            // of the word the arc passes clear, and a halo there would only
            // bite a notch out of it below the "y".
            ZStack(alignment: .topLeading) {
                ForEach(offsets.indices, id: \.self) { i in
                    letters(Text("EconByte").foregroundColor(.black))
                        .offset(offsets[i])
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .mask(
                GeometryReader { geo in
                    Rectangle()
                        .frame(width: geo.size.width * 0.27)
                        .offset(x: geo.size.width * 0.73)
                }
            )
            .blendMode(.destinationOut)
        }
        .compositingGroup()
        .accessibilityHidden(true)
    }
}

/// A thin, tapered arc: hair-fine at the lower left, fullest just past the
/// middle, fine again at the upper right. Coordinates are fractions of the
/// wordmark's padded box, so it scales with the letterforms.
struct EconSwoosh: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * w, y: rect.minY + y * h) }

        let start = p(0.0, 0.74)
        let end = p(1.0, 0.0)
        var path = Path()
        path.move(to: start)
        // Lower (outer) edge: runs under the whole word, clear of the "y"
        // descender, then climbs behind the end of "Byte".
        path.addCurve(to: end, control1: p(0.44, 1.07), control2: p(0.86, 1.00))
        // Upper (inner) edge back to the start, higher in the middle, which
        // gives the stroke its taper: hair-fine at both ends.
        path.addCurve(to: start, control1: p(0.845, 0.895), control2: p(0.43, 0.975))
        path.closeSubpath()
        return path
    }
}

/// The wordmark on its brand ground — navy with faint diagonal wave lines toward
/// the upper right. Used for the evidence PNG and anywhere a standalone lockup
/// is needed (not in the top bar, which is already navy).
struct EconWordmarkBanner: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(colors: [EconBrand.navyDeep, EconBrand.navy],
                               startPoint: .bottomLeading, endPoint: .topTrailing)
                EconWaveLines()
                    .stroke(Color.white.opacity(0.055), lineWidth: max(1, geo.size.width / 640))
                EconWordmark(fontSize: geo.size.width * 0.125)
            }
        }
    }
}

/// Faint parallel waves drifting up toward the upper-right corner.
struct EconWaveLines: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        // One wave, translated: parallel lines that never cross.
        for i in 0..<6 {
            let dx = CGFloat(i) * w * 0.05, dy = CGFloat(i) * h * 0.075
            path.move(to: CGPoint(x: w * 0.46 + dx, y: -h * 0.02 + dy))
            path.addCurve(to: CGPoint(x: w * 1.02 + dx, y: h * 0.34 + dy),
                          control1: CGPoint(x: w * 0.66 + dx, y: h * 0.16 + dy),
                          control2: CGPoint(x: w * 0.80 + dx, y: h * 0.06 + dy))
        }
        return path
    }
}
