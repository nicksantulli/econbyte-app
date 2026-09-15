import SwiftUI

/// The SwiftUI drawings a lesson may reference by `DiagramID` (1.1.4).
///
/// Every diagram is a schematic — labelled shapes that explain a mechanism —
/// never a rendering of real data. Nothing animates (Reduce Motion is moot),
/// every label is real text so Dynamic Type applies, and the whole frame is one
/// accessibility element whose label says what the picture shows.
struct DiagramView: View {
    let id: DiagramID

    var body: some View {
        Group {
            switch id {
            case .candleAnatomy:         CandleAnatomyDiagram()
            case .riskReturnLadder:      RiskReturnLadderDiagram()
            case .diversificationBasket: DiversificationBasketDiagram()
            case .priceYieldSeesaw:      PriceYieldSeesawDiagram()
            case .yieldCurveShapes:      YieldCurveShapesDiagram()
            case .allocationPie:         AllocationPieDiagram()
            case .supportResistance:     SupportResistanceDiagram()
            case .feeDrag:               FeeDragDiagram()
            case .trendChannel:          TrendChannelDiagram()
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 220)
        .padding(12)
        .background(Econ.ocean.opacity(0.7))
        .cornerRadius(12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(Self.accessibilityDescription(for: id)))
        .accessibilityAddTraits(.isImage)
    }

    static func accessibilityDescription(for id: DiagramID) -> String {
        switch id {
        case .candleAnatomy:
            return "Diagram of one candlestick: a thin line marks the high at the top and the low at the bottom; a thicker body spans the opening and closing prices."
        case .riskReturnLadder:
            return "Diagram of four steps rising from left to right, labelled cash, government bonds, corporate bonds, and stocks, with expected return and variability both rising along the steps."
        case .diversificationBasket:
            return "Diagram comparing one basket holding a single egg with a row of many baskets each holding one egg; a shock to one basket removes only one egg on the right."
        case .priceYieldSeesaw:
            return "Diagram of a seesaw with price on one end and yield on the other: when price goes up, yield goes down."
        case .yieldCurveShapes:
            return "Diagram of three yield curves plotted by maturity: normal sloping up, flat, and inverted sloping down."
        case .allocationPie:
            return "Diagram of an illustrative pie chart split into stocks, bonds, and cash, labelled as an illustration rather than a recommendation."
        case .supportResistance:
            return "Diagram of a price path bouncing between an upper band labelled resistance and a lower band labelled support."
        case .feeDrag:
            return "Diagram of two growth curves starting at the same point; the one paying a yearly fee ends lower, and the gap widens over time."
        case .trendChannel:
            return "Diagram of an up-sloping channel with the price making higher highs and higher lows between two parallel lines."
        }
    }
}

// MARK: - Shared helpers

private struct DiagramLabel: View {
    let text: String
    var color: Color = Econ.white.opacity(0.85)
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundColor(color)
            .lineLimit(2)
            .minimumScaleFactor(0.7)
    }
}

private struct Axes: View {
    var xLabel: String
    var yLabel: String
    var body: some View {
        GeometryReader { geo in
            Path { p in
                p.move(to: CGPoint(x: 28, y: 8))
                p.addLine(to: CGPoint(x: 28, y: geo.size.height - 22))
                p.addLine(to: CGPoint(x: geo.size.width - 6, y: geo.size.height - 22))
            }
            .stroke(Econ.mist.opacity(0.5), lineWidth: 1)
            Text(xLabel)
                .font(.system(size: 10, design: .rounded)).foregroundColor(Econ.subtext)
                .position(x: geo.size.width / 2 + 10, y: geo.size.height - 8)
            Text(yLabel)
                .font(.system(size: 10, design: .rounded)).foregroundColor(Econ.subtext)
                .rotationEffect(.degrees(-90))
                .position(x: 10, y: geo.size.height / 2 - 6)
        }
    }
}

private func smoothPath(_ points: [CGPoint]) -> Path {
    var path = Path()
    guard let first = points.first else { return path }
    path.move(to: first)
    for (i, point) in points.enumerated().dropFirst() {
        let previous = points[i - 1]
        let mid = CGPoint(x: (previous.x + point.x) / 2, y: (previous.y + point.y) / 2)
        path.addQuadCurve(to: mid, control: CGPoint(x: (previous.x + mid.x) / 2, y: previous.y))
        path.addQuadCurve(to: point, control: CGPoint(x: (mid.x + point.x) / 2, y: point.y))
    }
    return path
}

// MARK: - 1. Candle anatomy

private struct CandleAnatomyDiagram: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let cx = w * 0.42
            let high = h * 0.10, open = h * 0.30, close = h * 0.70, low = h * 0.92
            ZStack(alignment: .topLeading) {
                Path { p in p.move(to: CGPoint(x: cx, y: high)); p.addLine(to: CGPoint(x: cx, y: low)) }
                    .stroke(Econ.sky, lineWidth: 2)
                RoundedRectangle(cornerRadius: 3)
                    .fill(Econ.amber)
                    .frame(width: 44, height: close - open)
                    .position(x: cx, y: (open + close) / 2)
                Group {
                    DiagramLabel(text: "High — top of the wick").position(x: cx + 120, y: high + 4)
                    DiagramLabel(text: "Open").position(x: cx + 70, y: open)
                    DiagramLabel(text: "Body: open to close", color: Econ.amberLight).position(x: cx + 105, y: (open + close) / 2)
                    DiagramLabel(text: "Close").position(x: cx + 70, y: close)
                    DiagramLabel(text: "Low — bottom of the wick").position(x: cx + 120, y: low - 4)
                    DiagramLabel(text: "Wick", color: Econ.sky).position(x: cx - 40, y: high + 22)
                }
                Path { p in
                    for y in [high, open, close, low] {
                        p.move(to: CGPoint(x: cx + 24, y: y)); p.addLine(to: CGPoint(x: cx + 44, y: y))
                    }
                }
                .stroke(Econ.mist.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
    }
}

// MARK: - 2. Risk / return ladder

private struct RiskReturnLadderDiagram: View {
    private let steps = ["Cash", "Gov. bonds", "Corp. bonds", "Stocks"]
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let stepW = (w - 40) / CGFloat(steps.count)
            ZStack(alignment: .topLeading) {
                Axes(xLabel: "Higher variability →", yLabel: "Expected return →")
                ForEach(Array(steps.enumerated()), id: \.offset) { i, name in
                    let height = CGFloat(i + 1) * (h - 60) / CGFloat(steps.count)
                    let x = 34 + CGFloat(i) * stepW
                    VStack(spacing: 4) {
                        DiagramLabel(text: name)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Econ.tide.opacity(0.35 + 0.15 * Double(i)))
                            .frame(width: stepW - 10, height: height)
                    }
                    .position(x: x + stepW / 2 - 4, y: h - 22 - height / 2 - 6)
                }
                Path { p in
                    p.move(to: CGPoint(x: 40, y: h - 40))
                    p.addLine(to: CGPoint(x: w - 16, y: 30))
                }
                .stroke(Econ.amber, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                DiagramLabel(text: "More return only comes with more ups and downs", color: Econ.amberLight)
                    .frame(width: 170)
                    .position(x: w - 105, y: 18)
            }
        }
    }
}

// MARK: - 3. Diversification basket

private struct DiversificationBasketDiagram: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            HStack(spacing: 0) {
                VStack(spacing: 8) {
                    DiagramLabel(text: "One holding")
                    ZStack {
                        Basket(width: 90)
                        Circle().fill(Econ.amber).frame(width: 30, height: 30).offset(y: -6)
                    }
                    .frame(height: 70)
                    DiagramLabel(text: "One shock → everything", color: Econ.amberLight).frame(width: 110)
                }
                .frame(width: w * 0.42)
                Rectangle().fill(Econ.mist.opacity(0.3)).frame(width: 1, height: h * 0.7)
                VStack(spacing: 8) {
                    DiagramLabel(text: "Many holdings")
                    HStack(spacing: 6) {
                        ForEach(0..<5, id: \.self) { i in
                            ZStack {
                                Basket(width: 30)
                                if i != 2 {
                                    Circle().fill(Econ.amber).frame(width: 12, height: 12).offset(y: -2)
                                } else {
                                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                                        .foregroundColor(Econ.amberLight).offset(y: -2)
                                }
                            }
                        }
                    }
                    .frame(height: 70)
                    DiagramLabel(text: "One shock → one part", color: Econ.sky).frame(width: 120)
                }
                .frame(width: w * 0.56)
            }
            .frame(width: w, height: h)
        }
    }

    private struct Basket: View {
        let width: CGFloat
        var body: some View {
            Path { p in
                p.move(to: CGPoint(x: 0, y: 0))
                p.addLine(to: CGPoint(x: width * 0.15, y: width * 0.45))
                p.addLine(to: CGPoint(x: width * 0.85, y: width * 0.45))
                p.addLine(to: CGPoint(x: width, y: 0))
            }
            .stroke(Econ.sky, lineWidth: 2)
            .frame(width: width, height: width * 0.45)
            .offset(y: width * 0.1)
        }
    }
}

// MARK: - 4. Price / yield seesaw

private struct PriceYieldSeesawDiagram: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let pivot = CGPoint(x: w / 2, y: h * 0.62)
            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: pivot.x - 22, y: h * 0.92))
                    p.addLine(to: pivot)
                    p.addLine(to: CGPoint(x: pivot.x + 22, y: h * 0.92))
                    p.closeSubpath()
                }
                .fill(Econ.tide.opacity(0.6))
                Rectangle()
                    .fill(Econ.mist)
                    .frame(width: w * 0.78, height: 6)
                    .rotationEffect(.degrees(-14))
                    .position(pivot)
                VStack(spacing: 2) {
                    Image(systemName: "arrow.up").font(.system(size: 14, weight: .bold)).foregroundColor(Econ.amber)
                    DiagramLabel(text: "Price", color: Econ.amberLight)
                }
                .position(x: pivot.x - w * 0.34, y: pivot.y - h * 0.34)
                VStack(spacing: 2) {
                    DiagramLabel(text: "Yield", color: Econ.sky)
                    Image(systemName: "arrow.down").font(.system(size: 14, weight: .bold)).foregroundColor(Econ.sky)
                }
                .position(x: pivot.x + w * 0.34, y: pivot.y + h * 0.05)
                DiagramLabel(text: "A fixed coupon paid on a higher price is a smaller percentage")
                    .frame(width: w * 0.8)
                    .multilineTextAlignment(.center)
                    .position(x: w / 2, y: h * 0.12)
            }
        }
    }
}

// MARK: - 5. Yield curve shapes

private struct YieldCurveShapesDiagram: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let x0: CGFloat = 34, x1 = w - 12
            let yTop: CGFloat = 20, yBottom = h - 30
            let point: (CGFloat, CGFloat) -> CGPoint = { t, level in
                CGPoint(x: x0 + (x1 - x0) * t, y: yBottom - (yBottom - yTop) * level)
            }
            ZStack(alignment: .topLeading) {
                Axes(xLabel: "Maturity: 3 months → 30 years", yLabel: "Yield")
                smoothPath([point(0, 0.25), point(0.3, 0.5), point(0.6, 0.65), point(1, 0.75)])
                    .stroke(Econ.sky, lineWidth: 2.5)
                smoothPath([point(0, 0.5), point(0.5, 0.51), point(1, 0.52)])
                    .stroke(Econ.mist, style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                smoothPath([point(0, 0.75), point(0.3, 0.55), point(0.6, 0.42), point(1, 0.35)])
                    .stroke(Econ.amber, lineWidth: 2.5)
                DiagramLabel(text: "Normal", color: Econ.sky).position(x: x1 - 24, y: point(1, 0.75).y - 12)
                DiagramLabel(text: "Flat", color: Econ.mist).position(x: x1 - 24, y: point(1, 0.52).y - 12)
                DiagramLabel(text: "Inverted", color: Econ.amberLight).position(x: x1 - 28, y: point(1, 0.35).y + 12)
            }
        }
    }
}

// MARK: - 6. Allocation pie (illustrative)

private struct AllocationPieDiagram: View {
    private struct Slice { let name: String; let fraction: Double; let color: Color }
    private let slices = [
        Slice(name: "Stocks", fraction: 0.55, color: Econ.tide),
        Slice(name: "Bonds", fraction: 0.35, color: Econ.amber),
        Slice(name: "Cash", fraction: 0.10, color: Econ.mist),
    ]
    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            HStack(spacing: 20) {
                ZStack {
                    ForEach(Array(slices.enumerated()), id: \.offset) { i, slice in
                        let start = slices[..<i].reduce(0) { $0 + $1.fraction }
                        PieSlice(start: start, end: start + slice.fraction).fill(slice.color)
                    }
                }
                .frame(width: h * 0.72, height: h * 0.72)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(slices.enumerated()), id: \.offset) { _, slice in
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 3).fill(slice.color).frame(width: 14, height: 14)
                            DiagramLabel(text: slice.name)
                        }
                    }
                    DiagramLabel(text: "Illustration only — a mix, not a recommendation", color: Econ.subtext)
                        .frame(width: 130, alignment: .leading)
                        .padding(.top, 6)
                }
            }
            .frame(width: geo.size.width, height: h)
        }
    }

    private struct PieSlice: Shape {
        let start: Double, end: Double
        func path(in rect: CGRect) -> Path {
            var p = Path()
            let c = CGPoint(x: rect.midX, y: rect.midY)
            p.move(to: c)
            p.addArc(center: c, radius: rect.width / 2,
                     startAngle: .degrees(start * 360 - 90), endAngle: .degrees(end * 360 - 90), clockwise: false)
            p.closeSubpath()
            return p
        }
    }
}

// MARK: - 7. Support / resistance

private struct SupportResistanceDiagram: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let top = h * 0.28, bottom = h * 0.72
            let xs: [CGFloat] = stride(from: 0.0, through: 1.0, by: 0.125).map { 34 + (w - 46) * CGFloat($0) }
            let ys: [CGFloat] = [bottom - 8, top + 6, bottom - 4, top + 10, bottom - 10, top + 4, bottom - 6, top + 8, h * 0.5]
            ZStack(alignment: .topLeading) {
                Axes(xLabel: "Time", yLabel: "Price")
                Rectangle().fill(Econ.amber.opacity(0.18)).frame(width: w - 46, height: 14).position(x: 34 + (w - 46) / 2, y: top)
                Rectangle().fill(Econ.sky.opacity(0.18)).frame(width: w - 46, height: 14).position(x: 34 + (w - 46) / 2, y: bottom)
                smoothPath(zip(xs, ys).map { CGPoint(x: $0, y: $1) })
                    .stroke(Econ.white.opacity(0.9), lineWidth: 2)
                DiagramLabel(text: "Resistance — sellers have appeared here before", color: Econ.amberLight)
                    .frame(width: 210).position(x: 34 + 110, y: top - 18)
                DiagramLabel(text: "Support — buyers have appeared here before", color: Econ.sky)
                    .frame(width: 210).position(x: 34 + 110, y: bottom + 18)
            }
        }
    }
}

// MARK: - 8. Fee drag

private struct FeeDragDiagram: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let x0: CGFloat = 34, x1 = w - 12
            let yBottom = h - 30, yTop: CGFloat = 16
            let point: (CGFloat, CGFloat) -> CGPoint = { t, level in
                CGPoint(x: x0 + (x1 - x0) * t, y: yBottom - (yBottom - yTop) * level)
            }
            let steps: [CGFloat] = stride(from: 0, through: 1, by: 0.1).map { CGFloat($0) }
            ZStack(alignment: .topLeading) {
                Axes(xLabel: "Years", yLabel: "Value")
                smoothPath(steps.map { point($0, 0.12 + 0.85 * pow($0, 1.9)) }).stroke(Econ.sky, lineWidth: 2.5)
                smoothPath(steps.map { point($0, 0.12 + 0.58 * pow($0, 1.9)) }).stroke(Econ.amber, lineWidth: 2.5)
                DiagramLabel(text: "No annual fee", color: Econ.sky).position(x: x1 - 40, y: point(1, 0.97).y + 12)
                DiagramLabel(text: "With a yearly fee", color: Econ.amberLight).position(x: x1 - 48, y: point(1, 0.70).y + 12)
                DiagramLabel(text: "The gap compounds", color: Econ.white.opacity(0.85)).position(x: x1 - 52, y: point(1, 0.84).y)
            }
        }
    }
}

// MARK: - 9. Trend channel

private struct TrendChannelDiagram: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let x0: CGFloat = 34, x1 = w - 12
            let yBottom = h - 30, yTop: CGFloat = 16
            let point: (CGFloat, CGFloat) -> CGPoint = { t, level in
                CGPoint(x: x0 + (x1 - x0) * t, y: yBottom - (yBottom - yTop) * level)
            }
            let zig: [CGPoint] = [(0, 0.12), (0.14, 0.42), (0.28, 0.24), (0.42, 0.56), (0.56, 0.38),
                                  (0.7, 0.72), (0.84, 0.54), (1, 0.88)].map { point($0.0, $0.1) }
            ZStack(alignment: .topLeading) {
                Axes(xLabel: "Time", yLabel: "Price")
                Path { p in p.move(to: point(0, 0.34)); p.addLine(to: point(1, 1.0)) }
                    .stroke(Econ.amber.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                Path { p in p.move(to: point(0, 0.04)); p.addLine(to: point(1, 0.70)) }
                    .stroke(Econ.sky.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                Path { p in p.move(to: zig[0]); for pt in zig.dropFirst() { p.addLine(to: pt) } }
                    .stroke(Econ.white.opacity(0.9), lineWidth: 2)
                DiagramLabel(text: "Higher highs", color: Econ.amberLight).position(x: x0 + 70, y: point(0.14, 0.42).y - 22)
                DiagramLabel(text: "Higher lows", color: Econ.sky).position(x: x0 + 140, y: point(0.56, 0.38).y + 22)
            }
        }
    }
}
