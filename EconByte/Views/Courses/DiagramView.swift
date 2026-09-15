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
            case .rebalanceBands:        RebalanceBandsDiagram()
            case .trendlineAnchors:      TrendlineAnchorsDiagram()
            case .baseRateGrid:          BaseRateGridDiagram()
            case .creditSpreadStack:     CreditSpreadStackDiagram()
            case .breakevenSplit:        BreakevenSplitDiagram()
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
        case .rebalanceBands:
            return "Diagram of one category's share of a mix over time: a dashed target line inside a shaded tolerance band. The share drifts up to the top of the band, is rebalanced back to the target, and then drifts again."
        case .trendlineAnchors:
            return "Diagram of a rising price path with three marked lows. Line A runs through lows 1 and 2; the shallower Line B runs through lows 1 and 3. At the right the price dips below Line A but not below Line B."
        case .baseRateGrid:
            return "Diagram of 100 illustrative past cases as dots. 20 are ringed because a pattern appeared, and 11 of those were followed by a higher price. Of the other 80, 44 were also followed by a higher price: 55 percent either way."
        case .creditSpreadStack:
            return "Diagram of three yield bars: a Treasury, a higher-rated company and a lower-rated company. Each has the same Treasury yield at the bottom; the company bars add a credit spread on top, larger for the lower-rated company."
        case .breakevenSplit:
            return "Diagram of two yield bars for the same maturity: a taller nominal Treasury yield and a shorter TIPS real yield, with the gap between them marked as breakeven inflation, approximately nominal minus real."
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

// MARK: - 10. Rebalance bands (Phase 13)

private struct RebalanceBandsDiagram: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let x0: CGFloat = 34, x1 = w - 12
            let yBottom = h - 30, yTop: CGFloat = 16
            let point: (CGFloat, CGFloat) -> CGPoint = { t, level in
                CGPoint(x: x0 + (x1 - x0) * t, y: yBottom - (yBottom - yTop) * level)
            }
            let target: CGFloat = 0.42, half: CGFloat = 0.17
            let drift: [CGPoint] = [(0, 0.42), (0.1, 0.47), (0.2, 0.45), (0.3, 0.52), (0.4, 0.55), (0.5, 0.59)]
                .map { point($0.0, $0.1) }
            let after: [CGPoint] = [(0.5, 0.42), (0.62, 0.46), (0.74, 0.44), (0.87, 0.50), (1.0, 0.53)]
                .map { point($0.0, $0.1) }
            ZStack(alignment: .topLeading) {
                Axes(xLabel: "Time", yLabel: "Share of the mix")
                Rectangle()
                    .fill(Econ.sky.opacity(0.14))
                    .frame(width: x1 - x0, height: point(0, target - half).y - point(0, target + half).y)
                    .position(x: (x0 + x1) / 2, y: point(0, target).y)
                Path { p in p.move(to: point(0, target)); p.addLine(to: point(1, target)) }
                    .stroke(Econ.sky, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                Path { p in p.move(to: drift[0]); for pt in drift.dropFirst() { p.addLine(to: pt) } }
                    .stroke(Econ.white.opacity(0.9), lineWidth: 2)
                Path { p in p.move(to: point(0.5, 0.59)); p.addLine(to: point(0.5, target)) }
                    .stroke(Econ.amber, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                Path { p in p.move(to: after[0]); for pt in after.dropFirst() { p.addLine(to: pt) } }
                    .stroke(Econ.white.opacity(0.9), lineWidth: 2)
                Circle().fill(Econ.amber).frame(width: 8, height: 8).position(point(0.5, 0.59))
                DiagramLabel(text: "Tolerance band", color: Econ.sky)
                    .position(x: x0 + 52, y: point(0, target + half).y - 9)
                DiagramLabel(text: "Target share", color: Econ.sky)
                    .position(x: x0 + 44, y: point(0, target).y + 12)
                DiagramLabel(text: "Rebalanced", color: Econ.amberLight)
                    .position(x: point(0.5, 0.59).x + 40, y: point(0.5, 0.59).y - 10)
            }
        }
    }
}

// MARK: - 11. Trend line anchors (Phase 13)

private struct TrendlineAnchorsDiagram: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let x0: CGFloat = 34, x1 = w - 12
            let yBottom = h - 30, yTop: CGFloat = 16
            let point: (CGFloat, CGFloat) -> CGPoint = { t, level in
                CGPoint(x: x0 + (x1 - x0) * t, y: yBottom - (yBottom - yTop) * level)
            }
            // Lows 1 (0.04, 0.10), 2 (0.42, 0.44) and 3 (0.86, 0.52). Line A runs
            // through lows 1 and 2; Line B through lows 1 and 3. Every point of the
            // path stays on or above Line A until the dip to low 3, which is below
            // Line A and on Line B.
            let lows: [(CGFloat, CGFloat)] = [(0.04, 0.10), (0.42, 0.44), (0.86, 0.52)]
            let path: [CGPoint] = [(0, 0.16), (0.04, 0.10), (0.18, 0.40), (0.28, 0.36), (0.42, 0.44),
                                   (0.56, 0.74), (0.68, 0.70), (0.78, 0.88), (0.86, 0.52), (1.0, 0.66)]
                .map { point($0.0, $0.1) }
            let slopeA = (lows[1].1 - lows[0].1) / (lows[1].0 - lows[0].0)
            let slopeB = (lows[2].1 - lows[0].1) / (lows[2].0 - lows[0].0)
            let lineA: (CGFloat) -> CGPoint = { t in point(t, lows[0].1 + slopeA * (t - lows[0].0)) }
            let lineB: (CGFloat) -> CGPoint = { t in point(t, lows[0].1 + slopeB * (t - lows[0].0)) }
            ZStack(alignment: .topLeading) {
                Axes(xLabel: "Time", yLabel: "Price")
                Path { p in p.move(to: lineA(0.0)); p.addLine(to: lineA(1.0)) }
                    .stroke(Econ.amber.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                Path { p in p.move(to: lineB(0.0)); p.addLine(to: lineB(1.0)) }
                    .stroke(Econ.sky.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                Path { p in p.move(to: path[0]); for pt in path.dropFirst() { p.addLine(to: pt) } }
                    .stroke(Econ.white.opacity(0.9), lineWidth: 2)
                ForEach(Array(lows.enumerated()), id: \.offset) { i, low in
                    let pt = point(low.0, low.1)
                    Circle().stroke(Econ.white, lineWidth: 1.5).frame(width: 9, height: 9).position(pt)
                    DiagramLabel(text: "\(i + 1)").position(x: pt.x + (i == 0 ? 10 : 0), y: pt.y + 13)
                }
                DiagramLabel(text: "Line A", color: Econ.amberLight)
                    .position(x: x1 - 22, y: lineA(1.0).y + 12)
                DiagramLabel(text: "Line B", color: Econ.sky)
                    .position(x: x1 - 22, y: lineB(1.0).y + 12)
                DiagramLabel(text: "A break of one line, not the other", color: Econ.white.opacity(0.85))
                    .frame(width: 130)
                    .multilineTextAlignment(.center)
                    .position(x: point(0.62, 0).x, y: point(0, 0.14).y)
            }
        }
    }
}

// MARK: - 12. Base-rate grid (Phase 13)

/// The fixed, illustrative counts `BaseRateGridDiagram` draws. Pinned by test so
/// the lesson caption ("11 of 20 … 44 of 80") always matches the picture.
enum BaseRateGrid {
    static let caseCount = 100
    /// Cases where the pattern appeared: every fifth dot, 20 in all.
    static let patternIndices: [Int] = (0..<caseCount).filter { $0 % 5 == 2 }
    static let patternRoseCount = 11
    static let otherRoseCount = 44

    /// A deterministic scatter so filled dots are not bunched in reading order.
    private static func scattered(_ indices: [Int]) -> [Int] {
        indices.sorted { ($0 * 37) % 101 < ($1 * 37) % 101 }
    }

    static var patternRoseIndices: Set<Int> { Set(scattered(patternIndices).prefix(patternRoseCount)) }
    static var otherRoseIndices: Set<Int> {
        let pattern = Set(patternIndices)
        return Set(scattered((0..<caseCount).filter { !pattern.contains($0) }).prefix(otherRoseCount))
    }
}

private struct BaseRateGridDiagram: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let side = min(h - 34, w * 0.55)
            let step = side / 10
            let pattern = Set(BaseRateGrid.patternIndices)
            let rose = BaseRateGrid.patternRoseIndices.union(BaseRateGrid.otherRoseIndices)
            VStack(spacing: 8) {
                HStack(alignment: .center, spacing: 16) {
                    ZStack(alignment: .topLeading) {
                        ForEach(0..<BaseRateGrid.caseCount, id: \.self) { i in
                            let center = CGPoint(x: step * (CGFloat(i % 10) + 0.5), y: step * (CGFloat(i / 10) + 0.5))
                            Circle()
                                .fill(rose.contains(i) ? Econ.sky : Econ.mist.opacity(0.22))
                                .frame(width: step * 0.5, height: step * 0.5)
                                .position(center)
                            if pattern.contains(i) {
                                Circle().stroke(Econ.amber, lineWidth: 1.5)
                                    .frame(width: step * 0.85, height: step * 0.85)
                                    .position(center)
                            }
                        }
                    }
                    .frame(width: side, height: side)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Circle().stroke(Econ.amber, lineWidth: 1.5).frame(width: 13, height: 13)
                            DiagramLabel(text: "Pattern appeared")
                        }
                        HStack(spacing: 8) {
                            Circle().fill(Econ.sky).frame(width: 9, height: 9).frame(width: 13)
                            DiagramLabel(text: "Price higher afterward")
                        }
                        HStack(spacing: 8) {
                            Circle().fill(Econ.mist.opacity(0.22)).frame(width: 9, height: 9).frame(width: 13)
                            DiagramLabel(text: "Not higher")
                        }
                    }
                }
                DiagramLabel(text: "Illustrative: 11 of 20 with the pattern (55%) vs 44 of 80 without it (55%)",
                             color: Econ.amberLight)
                    .multilineTextAlignment(.center)
            }
            .frame(width: w, height: h)
        }
    }
}

// MARK: - 13. Credit spread stack (Phase 13)

private struct CreditSpreadStackDiagram: View {
    private struct Bar { let name: String; let spread: CGFloat }
    private let bars = [
        Bar(name: "Treasury", spread: 0),
        Bar(name: "Higher-rated company", spread: 0.18),
        Bar(name: "Lower-rated company", spread: 0.42),
    ]
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let plotBottom = h - 40, plotTop: CGFloat = 10
            let unit = plotBottom - plotTop
            let base: CGFloat = 0.48
            let slot = (w - 40) / CGFloat(bars.count)
            ZStack(alignment: .topLeading) {
                Path { p in
                    p.move(to: CGPoint(x: 28, y: plotTop))
                    p.addLine(to: CGPoint(x: 28, y: plotBottom))
                    p.addLine(to: CGPoint(x: w - 6, y: plotBottom))
                }
                .stroke(Econ.mist.opacity(0.5), lineWidth: 1)
                Text("Yield")
                    .font(.system(size: 10, design: .rounded)).foregroundColor(Econ.subtext)
                    .rotationEffect(.degrees(-90))
                    .position(x: 10, y: (plotTop + plotBottom) / 2)
                ForEach(Array(bars.enumerated()), id: \.offset) { i, bar in
                    let cx = 34 + slot * (CGFloat(i) + 0.5)
                    let barW = min(slot - 14, 96)
                    let baseH = unit * base
                    let spreadH = unit * bar.spread
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Econ.tide.opacity(0.75))
                        .frame(width: barW, height: baseH)
                        .position(x: cx, y: plotBottom - baseH / 2)
                    DiagramLabel(text: "Treasury yield")
                        .frame(width: barW - 4)
                        .multilineTextAlignment(.center)
                        .position(x: cx, y: plotBottom - baseH / 2)
                    if bar.spread > 0 {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Econ.amber.opacity(0.85))
                            .frame(width: barW, height: spreadH)
                            .position(x: cx, y: plotBottom - baseH - spreadH / 2)
                        DiagramLabel(text: "Credit spread", color: Econ.ink)
                            .frame(width: barW - 4)
                            .multilineTextAlignment(.center)
                            .position(x: cx, y: plotBottom - baseH - spreadH / 2)
                    }
                    DiagramLabel(text: bar.name)
                        .frame(width: slot - 4)
                        .multilineTextAlignment(.center)
                        .position(x: cx, y: plotBottom + 18)
                }
            }
        }
    }
}

// MARK: - 14. Breakeven split (Phase 13)

private struct BreakevenSplitDiagram: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let plotBottom = h - 34, plotTop: CGFloat = 12
            let unit = plotBottom - plotTop
            let nominalH = unit * 0.86, realH = unit * 0.38
            let barW = min(w * 0.2, 84)
            let nominalX = 34 + w * 0.16, realX = 34 + w * 0.42
            let bracketX = realX + barW / 2 + 12
            ZStack(alignment: .topLeading) {
                Path { p in
                    p.move(to: CGPoint(x: 28, y: plotTop))
                    p.addLine(to: CGPoint(x: 28, y: plotBottom))
                    p.addLine(to: CGPoint(x: w - 6, y: plotBottom))
                }
                .stroke(Econ.mist.opacity(0.5), lineWidth: 1)
                Text("Yield, same maturity")
                    .font(.system(size: 10, design: .rounded)).foregroundColor(Econ.subtext)
                    .rotationEffect(.degrees(-90))
                    .position(x: 10, y: (plotTop + plotBottom) / 2)
                RoundedRectangle(cornerRadius: 3).fill(Econ.tide.opacity(0.8))
                    .frame(width: barW, height: nominalH)
                    .position(x: nominalX, y: plotBottom - nominalH / 2)
                RoundedRectangle(cornerRadius: 3).fill(Econ.sky.opacity(0.8))
                    .frame(width: barW, height: realH)
                    .position(x: realX, y: plotBottom - realH / 2)
                // Guide from the nominal bar's top across to the bracket.
                Path { p in
                    p.move(to: CGPoint(x: nominalX + barW / 2, y: plotBottom - nominalH))
                    p.addLine(to: CGPoint(x: bracketX, y: plotBottom - nominalH))
                }
                .stroke(Econ.mist.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                Path { p in
                    let top = plotBottom - nominalH, bottom = plotBottom - realH
                    p.move(to: CGPoint(x: bracketX - 6, y: top)); p.addLine(to: CGPoint(x: bracketX, y: top))
                    p.addLine(to: CGPoint(x: bracketX, y: bottom)); p.addLine(to: CGPoint(x: bracketX - 6, y: bottom))
                }
                .stroke(Econ.amber, lineWidth: 2)
                DiagramLabel(text: "Breakeven inflation ≈ nominal − real", color: Econ.amberLight)
                    .frame(width: max(w - bracketX - 16, 80), alignment: .leading)
                    .position(x: bracketX + 8 + max(w - bracketX - 16, 80) / 2, y: plotBottom - (nominalH + realH) / 2)
                DiagramLabel(text: "Nominal Treasury")
                    .frame(width: barW + 30).multilineTextAlignment(.center)
                    .position(x: nominalX, y: plotBottom + 14)
                DiagramLabel(text: "TIPS real yield")
                    .frame(width: barW + 30).multilineTextAlignment(.center)
                    .position(x: realX, y: plotBottom + 14)
            }
        }
    }
}
