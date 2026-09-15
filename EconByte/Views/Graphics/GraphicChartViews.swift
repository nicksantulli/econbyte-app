import SwiftUI
import Charts

// MARK: - Bars

/// Horizontal labelled bars: label, bar, value on one row each.
struct BarsGraphicView: View {
    let bars: BarsGraphic
    let palette: GraphicPalette
    /// Estimated width of one caption character; scales with Dynamic Type.
    @ScaledMetric(relativeTo: .caption) private var charWidth: CGFloat = 6.4

    private func text(for item: BarsGraphic.Item) -> String {
        item.display ?? GraphicFormat.value(item.value, unit: bars.unit, decimals: bars.decimals)
    }

    /// The value column fits this graphic's longest value; the label column
    /// takes what is left, never so much that the bar track drops below ~70 pt
    /// of the ~290 pt plate content (iPhone 17). At large text labels wrap instead of squeezing bars.
    private var valueWidth: CGFloat {
        let longest = CGFloat(bars.items.map { text(for: $0).count }.max() ?? 4)
        return min(max(longest * charWidth + 6, 44), 132)
    }
    private var labelWidth: CGFloat { max(72, 212 - valueWidth) }

    var body: some View {
        let maxValue = max(bars.items.map(\.value).max() ?? 1, 1e-9)
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(bars.items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 8) {
                    Text(item.label)
                        .font(.system(.caption, design: .rounded))
                        .foregroundColor(palette.ink)
                        .lineLimit(3)
                        .minimumScaleFactor(0.8)
                        .frame(width: labelWidth, alignment: .leading)
                    GeometryReader { geo in
                        let width = max(3, geo.size.width * CGFloat(item.value / maxValue))
                        RoundedRectangle(cornerRadius: EconRadius.mark, style: .continuous)
                            .fill(item.emphasis == true ? palette.accent : palette.primary)
                            .frame(width: width, height: geo.size.height)
                            .frame(maxHeight: .infinity, alignment: .center)
                    }
                    .frame(height: 12)
                    Text(text(for: item))
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                        .foregroundColor(palette.ink)
                        .lineLimit(1)
                        // The column is sized for the longest value; this only absorbs estimate error.
                        .minimumScaleFactor(0.8)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: valueWidth, alignment: .trailing)
                }
            }
        }
    }
}

// MARK: - Line

/// Swift Charts line chart with explicit, readable ticks.
struct LineGraphicView: View {
    let line: LineGraphic
    let palette: GraphicPalette

    private struct Point: Identifiable {
        let id: String
        let series: String
        let index: Int
        let x: Double
        let y: Double
    }

    private var points: [Point] {
        line.series.enumerated().flatMap { index, series in
            series.points.filter { $0.count == 2 }.enumerated().map { j, p in
                Point(id: "\(index)-\(j)", series: series.name, index: index, x: p[0], y: p[1])
            }
        }
    }

    private var xRange: ClosedRange<Double> {
        let xs = points.map(\.x)
        guard let lo = xs.min(), let hi = xs.max(), hi > lo else { return 0...1 }
        return lo...hi
    }

    private var yRange: ClosedRange<Double> {
        let ys = points.map(\.y) + (line.references ?? []).map(\.y)
        guard var lo = ys.min(), var hi = ys.max() else { return 0...1 }
        if lo >= 0 { lo = 0 }
        if hi <= 0 { hi = 0 }
        if hi == lo { hi = lo + 1 }
        let pad = (hi - lo) * 0.08
        return (lo < 0 ? lo - pad : lo)...(hi + pad)
    }

    private var xTicks: [Double] {
        switch line.xFormat {
        case .month:
            let xs = Array(Set(points.map(\.x))).sorted()
            if xs.count <= 4 { return xs }
            let months = GraphicFormat.ticks(xRange.lowerBound * 12, xRange.upperBound * 12, desired: 4, integerOnly: true)
            return months.map { $0 / 12 }
        case .year:
            return GraphicFormat.ticks(xRange.lowerBound, xRange.upperBound, desired: 4, integerOnly: true)
        case .number:
            return GraphicFormat.ticks(xRange.lowerBound, xRange.upperBound, desired: 4)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if line.series.count > 1 {
                HStack(spacing: 10) {
                    ForEach(Array(line.series.enumerated()), id: \.offset) { index, series in
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: EconRadius.mark)
                                .fill(palette.series[index % palette.series.count])
                                .frame(width: 12, height: 3)
                            Text(series.name)
                                .font(.system(.caption2, design: .rounded))
                                .foregroundColor(palette.ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                }
            }
            Text(line.yLabel)
                .font(.system(.caption2, design: .rounded))
                .foregroundColor(palette.secondary)
                .lineLimit(1)
            chart
                .padding(.top, markerHeadroom)
            if line.xFormat == .number {
                Text(line.xLabel)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundColor(palette.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var chart: some View {
        Chart {
            ForEach(points) { point in
                LineMark(x: .value(line.xLabel, point.x),
                         y: .value(line.yLabel, point.y),
                         series: .value("Series", point.series))
                    .foregroundStyle(palette.series[point.index % palette.series.count])
                    .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            }
            if points.count <= 16 {
                ForEach(points) { point in
                    PointMark(x: .value(line.xLabel, point.x), y: .value(line.yLabel, point.y))
                        .foregroundStyle(palette.series[point.index % palette.series.count])
                        .symbolSize(16)
                }
            }
            ForEach(Array((line.references ?? []).enumerated()), id: \.offset) { _, reference in
                RuleMark(y: .value("Reference", reference.y))
                    .foregroundStyle(palette.muted)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .annotation(position: referenceIsHigh(reference.y) ? .bottom : .top, alignment: .leading, spacing: 1) {
                        GraphicTag(text: reference.label, palette: palette)
                    }
            }
            ForEach(Array((line.markers ?? []).enumerated()), id: \.offset) { index, marker in
                RuleMark(x: .value("Marker", marker.x))
                    .foregroundStyle(palette.accent.opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, alignment: markerAlignment(marker.x), spacing: index % 2 == 1 ? 17 : 1) {
                        GraphicTag(text: marker.label, palette: palette)
                    }
            }
        }
        .chartLegend(.hidden)
        .chartXScale(domain: xRange)
        .chartYScale(domain: yRange)
        .chartXAxis {
            AxisMarks(preset: .aligned, values: xTicks) { value in
                AxisGridLine().foregroundStyle(palette.grid)
                AxisValueLabel {
                    if let x = value.as(Double.self) {
                        Text(GraphicFormat.x(x, format: line.xFormat))
                            .font(.system(.caption2, design: .rounded))
                            .foregroundColor(palette.secondary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: GraphicFormat.ticks(yRange.lowerBound, yRange.upperBound, desired: 3)) { value in
                AxisGridLine().foregroundStyle(palette.grid)
                AxisValueLabel {
                    if let y = value.as(Double.self) {
                        Text(GraphicFormat.axis(y, unit: line.unit))
                            .font(.system(.caption2, design: .rounded))
                            .foregroundColor(palette.secondary)
                    }
                }
            }
        }
    }

    /// Room above the plot for marker tags: one row, or two when markers stagger.
    private var markerHeadroom: CGFloat {
        switch line.markers?.count ?? 0 {
        case 0: return 0
        case 1: return 12
        default: return 28
        }
    }

    private func referenceIsHigh(_ y: Double) -> Bool {
        let span = yRange.upperBound - yRange.lowerBound
        return span > 0 && (y - yRange.lowerBound) / span > 0.6
    }

    /// Markers in the right half extend leftward so the tag stays in the plot.
    private func markerAlignment(_ x: Double) -> Alignment {
        let span = xRange.upperBound - xRange.lowerBound
        guard span > 0 else { return .center }
        let t = (x - xRange.lowerBound) / span
        return t > 0.6 ? .trailing : (t < 0.4 ? .leading : .center)
    }
}

/// A small label chip used for markers, references and diagram labels.
struct GraphicTag: View {
    let text: String
    let palette: GraphicPalette
    var color: Color?

    var body: some View {
        Text(text)
            .font(.system(.caption2, design: .rounded).weight(.semibold))
            .foregroundColor(color ?? palette.ink)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: EconRadius.mark).fill(palette.plateOpaque))
    }
}

extension GraphicPalette {
    /// Tags sit over lines; the light plate is translucent, so give them an
    /// opaque backing that matches the plate's surface.
    var plateOpaque: Color { backing }
}

// MARK: - Proportion

struct ProportionGraphicView: View {
    let proportion: ProportionGraphic
    let palette: GraphicPalette
    let height: CGFloat

    private struct Share: Identifiable {
        let id: Int
        let label: String
        let value: Double
        let color: Color
    }

    private var shares: [Share] {
        var out = proportion.segments.enumerated().map { index, segment in
            Share(id: index, label: segment.label, value: segment.value, color: palette.series[index % 3])
        }
        if proportion.remainder > 1e-9 {
            out.append(Share(id: out.count, label: proportion.remainderLabel ?? "Other",
                             value: proportion.remainder, color: palette.remainder))
        }
        return out
    }

    var body: some View {
        switch proportion.style {
        case .bar:    barView
        case .waffle: waffleView
        case .donut:  donutView
        }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(shares) { share in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: EconRadius.mark).fill(share.color).frame(width: 10, height: 10)
                    Text(share.label)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundColor(palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 4)
                    Text(GraphicFormat.number(share.value))
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                        .foregroundColor(palette.ink)
                }
            }
            if let unit = proportion.unitLabel {
                Text(unit)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundColor(palette.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var barView: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                let gap: CGFloat = 2
                let usable = geo.size.width - gap * CGFloat(max(0, shares.count - 1))
                HStack(spacing: gap) {
                    ForEach(shares) { share in
                        Rectangle()
                            .fill(share.color)
                            .frame(width: max(2, usable * CGFloat(share.value / proportion.total)))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: EconRadius.badge, style: .continuous))
            }
            .frame(height: 20)
            legend
        }
    }

    /// A ring (Phase 24): segments clockwise from the top, the remainder last,
    /// with the legend beside it (below it when the text is large).
    private var donutView: some View {
        let ring = min(max(height, 96), 132)
        let total = max(proportion.total, 1e-9)
        var start = 0.0
        let arcs: [(Share, Double, Double)] = shares.map { share in
            defer { start += share.value / total }
            return (share, start, start + share.value / total)
        }
        let donut = ZStack {
            ForEach(arcs, id: \.0.id) { share, from, to in
                Circle()
                    .trim(from: from, to: max(from, to - (arcs.count > 1 ? 0.004 : 0)))
                    .stroke(share.color, style: StrokeStyle(lineWidth: ring * 0.2, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
        }
        .padding(ring * 0.1)
        .frame(width: ring, height: ring)
        return EconAdaptiveRow(spacing: 14) {
            donut
            legend
        }
    }

    private var waffleView: some View {
        let total = Int(proportion.total)
        let columns = 10
        let rows = max(1, total / columns)
        let colors: [Color] = {
            var out: [Color] = []
            for share in shares { out += Array(repeating: share.color, count: Int(share.value.rounded())) }
            return Array((out + Array(repeating: palette.remainder, count: max(0, total - out.count))).prefix(total))
        }()
        let gridHeight = min(height, CGFloat(rows) * 14)
        let cell = (gridHeight - CGFloat(rows - 1) * 2) / CGFloat(rows)
        return HStack(alignment: .center, spacing: 14) {
            VStack(spacing: 2) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: 2) {
                        ForEach(0..<columns, id: \.self) { column in
                            RoundedRectangle(cornerRadius: cell * 0.22)
                                .fill(colors[row * columns + column])
                                .frame(width: cell, height: cell)
                        }
                    }
                }
            }
            .fixedSize()
            legend
        }
    }
}

// MARK: - Candles

/// A textbook candlestick drawing (Phase 24). Each candle's thin wick spans its
/// low to its high and its body spans open to close; a candle that closes above
/// its open is drawn in the primary (sky) tone, one that closes below in amber,
/// and the legend says so. An optional highlight bands and names a pattern,
/// `annotate: .ohlc` labels one candle's four prices, and up to two reference
/// lines mark levels such as support and resistance. Prices are not printed on
/// an axis: the drawing teaches shapes, and every figure a lesson states is in
/// its text.
struct CandlesGraphicView: View {
    let candles: CandlesGraphic
    let palette: GraphicPalette
    let height: CGFloat
    @ScaledMetric(relativeTo: .caption2) private var tagRow: CGFloat = 18
    @ScaledMetric(relativeTo: .caption2) private var annotationWidth: CGFloat = 50

    private var annotated: CandlesGraphic.Candle? {
        guard candles.annotate == .ohlc, let h = candles.highlight, h.from == h.to,
              candles.candles.indices.contains(h.from - 1) else { return nil }
        return candles.candles[h.from - 1]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(candles.yLabel)
                .font(.system(.caption2, design: .rounded))
                .foregroundColor(palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            GeometryReader { geo in plot(in: geo.size) }
                .frame(height: height)
            Text(candles.xLabel)
                .font(.system(.caption2, design: .rounded))
                .foregroundColor(palette.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
            EconAdaptiveRow(spacing: 12) {
                legendItem(color: palette.primary, text: "Closed above open")
                legendItem(color: palette.accent, text: "Closed below open")
            }
        }
    }

    private func legendItem(color: Color, text: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: EconRadius.mark).fill(color).frame(width: 8, height: 12)
            Text(text)
                .font(.system(.caption2, design: .rounded))
                .foregroundColor(palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func plot(in size: CGSize) -> some View {
        let list = candles.candles
        let top: CGFloat = candles.highlight == nil ? 4 : tagRow + 4
        let bottom: CGFloat = 4
        let plotWidth = max(40, size.width - (annotated == nil ? 0 : annotationWidth))
        let slot = plotWidth / CGFloat(max(list.count, 1))
        let bodyWidth = max(3, min(slot * 0.58, 26))
        let domain = candles.yDomain
        let span = domain.upperBound - domain.lowerBound
        let y: (Double) -> CGFloat = { v in top + CGFloat(1 - (v - domain.lowerBound) / span) * (size.height - top - bottom) }
        let x: (Int) -> CGFloat = { i in slot * (CGFloat(i) + 0.5) }

        return ZStack(alignment: .topLeading) {
            if let h = candles.highlight, h.from >= 1, h.to <= list.count {
                let minX = x(h.from - 1) - slot / 2 + 1
                let maxX = x(h.to - 1) + slot / 2 - 1
                RoundedRectangle(cornerRadius: EconRadius.badge, style: .continuous)
                    .fill(palette.accent.opacity(0.14))
                    .overlay(RoundedRectangle(cornerRadius: EconRadius.badge, style: .continuous)
                        .stroke(palette.accent.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                    .frame(width: maxX - minX, height: size.height - top + 2)
                    .offset(x: minX, y: top - 2)
                GraphicTag(text: h.label, palette: palette, color: palette.accent)
                    .position(x: min(max((minX + maxX) / 2, 44), size.width - 44), y: tagRow / 2)
            }
            ForEach(Array((candles.references ?? []).enumerated()), id: \.offset) { _, reference in
                Path { p in
                    p.move(to: CGPoint(x: 0, y: y(reference.y)))
                    p.addLine(to: CGPoint(x: plotWidth, y: y(reference.y)))
                }
                .stroke(palette.muted, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                GraphicTag(text: reference.label, palette: palette)
                    .fixedSize()
                    .offset(x: 2, y: y(reference.y) - (y(reference.y) > size.height / 2 ? 16 : -2))
            }
            ForEach(Array(list.enumerated()), id: \.offset) { index, candle in
                let color = candle.isUp ? palette.primary : palette.accent
                Path { p in
                    p.move(to: CGPoint(x: x(index), y: y(candle.high)))
                    p.addLine(to: CGPoint(x: x(index), y: y(candle.low)))
                }
                .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                let bodyTop = y(max(candle.open, candle.close))
                let bodyHeight = max(1.5, y(min(candle.open, candle.close)) - bodyTop)
                Rectangle()
                    .fill(color)
                    .frame(width: bodyWidth, height: bodyHeight)
                    .offset(x: x(index) - bodyWidth / 2, y: bodyTop)
            }
            if let candle = annotated, let h = candles.highlight {
                let cx = x(h.from - 1)
                ForEach(Array(Self.annotationRows(for: candle, y: y, minGap: tagRow - 4).enumerated()), id: \.offset) { _, row in
                    Path { p in
                        p.move(to: CGPoint(x: cx + bodyWidth / 2 + 2, y: row.anchor))
                        p.addLine(to: CGPoint(x: plotWidth + 4, y: row.label))
                    }
                    .stroke(palette.muted, lineWidth: 0.8)
                    Text(row.text)
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .foregroundColor(palette.ink)
                        .lineLimit(1)
                        .fixedSize()
                        .position(x: plotWidth + 6 + annotationWidth / 2 - 4, y: row.label)
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    /// Open/High/Low/Close labels, top to bottom, nudged apart so none overlap.
    static func annotationRows(for candle: CandlesGraphic.Candle, y: (Double) -> CGFloat, minGap: CGFloat)
        -> [(text: String, anchor: CGFloat, label: CGFloat)] {
        var rows: [(text: String, anchor: CGFloat, label: CGFloat)] = [
            ("High", y(candle.high), y(candle.high)),
            (candle.isUp ? "Close" : "Open", y(max(candle.open, candle.close)), y(max(candle.open, candle.close))),
            (candle.isUp ? "Open" : "Close", y(min(candle.open, candle.close)), y(min(candle.open, candle.close))),
            ("Low", y(candle.low), y(candle.low)),
        ]
        for i in rows.indices.dropFirst() where rows[i].label - rows[i - 1].label < minGap {
            rows[i].label = rows[i - 1].label + minGap
        }
        return rows
    }
}
