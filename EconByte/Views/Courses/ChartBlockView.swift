import SwiftUI
import Charts

/// Renders a lesson's synthetic `chart` with Swift Charts (1.1.4; Phase 24 layout fixes).
///
/// Every series comes from the chart itself — synthetic, hand-designed numbers
/// the validator requires to be labelled as such — so the app carries no
/// market-data dependency and can never show a stale or licensed quote. The
/// `dataNote` ("Synthetic …") is always printed under the chart.
///
/// Phase 24:
/// - Line and candlestick plots are scaled to their own data, so a series that
///   moves between 100 and 104 is not drawn flat against a zero baseline, and
///   the x axis spans exactly the plotted range.
/// - Bars keep a zero baseline. Several series are drawn side by side and never
///   stacked: stacking a nominal yield on an inflation rate, or one fund's value
///   on another's, would draw a total that means nothing.
/// - A bar chart with a dozen or fewer x positions uses them as categories. When a
///   marker names every category (P/E ranges by style), the names become the axis
///   labels instead of colliding annotations.
/// - Title and data note stop growing at xxxLarge, like a graphic plate; the
///   plot's own labels stop at xLarge.
struct ChartBlockView: View {
    let spec: ChartSpec
    /// 1.1.5 story beats say what the chart shows in the beat text; the caption
    /// stays the chart's VoiceOver description.
    var showsCaption = true
    /// Plot height before marker headroom; a story beat passes a compact or
    /// centerpiece size.
    var plotHeight: CGFloat = 220

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(spec.title)
                .font(EconType.subheadlineEmphasis)
                .foregroundColor(EconColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            chart
                // Marker labels sit above the plot; reserve their rows so they never
                // cover the title (two rows when labels alternate).
                .padding(.top, markerHeadroom)
                .frame(height: plotHeight + markerHeadroom)
                .dynamicTypeSize(...DynamicTypeSize.xLarge)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("\(spec.title). \(spec.caption)"))
                .accessibilityValue(Text(accessibilitySummary))
            if showsCaption {
                Text(spec.caption)
                    .font(EconType.footnote)
                    .foregroundColor(EconColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(spec.dataNote)
                .font(EconType.caption)
                .italic()
                .foregroundColor(EconColor.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("chart-\(spec.chartID)-note")
        }
        .padding(EconSpace.s)
        .lessonSurface()
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chart-\(spec.chartID)")
    }

    @ViewBuilder
    private var chart: some View {
        switch spec.kind {
        case .candlestick: candlestick
        case .line:        lines
        case .bar:         isCategorical ? AnyView(categoricalBars) : AnyView(numericBars)
        }
    }

    // MARK: Geometry

    private var allX: [Double] {
        (spec.candles?.map(\.x) ?? []) + (spec.series ?? []).flatMap { $0.points.map(\.x) }
    }

    private var distinctX: [Double] { Array(Set(allX)).sorted() }

    private var xDomain: ClosedRange<Double> {
        guard let lo = allX.min(), let hi = allX.max(), hi > lo else { return 0...1 }
        return lo...hi
    }

    /// Smallest gap between neighboring x positions (for bar and candle padding).
    private var xStep: Double {
        let xs = distinctX
        guard xs.count > 1 else { return 1 }
        return zip(xs, xs.dropFirst()).map { $1 - $0 }.min() ?? 1
    }

    /// A line's y range: its own data (and zero only when the data crosses it), padded.
    private var lineYDomain: ClosedRange<Double> {
        let ys = (spec.series ?? []).flatMap { $0.points.map(\.y) }
        guard let lo = ys.min(), let hi = ys.max() else { return 0...1 }
        let span = max(hi - lo, abs(hi) * 0.02, 1e-6)
        return (lo - span * 0.1)...(hi + span * 0.1)
    }

    /// A bar's y range always includes the zero baseline.
    private var barYDomain: ClosedRange<Double> {
        let ys = (spec.series ?? []).flatMap { $0.points.map(\.y) }
        let lo = min(0, ys.min() ?? 0), hi = max(0, ys.max() ?? 1)
        let span = max(hi - lo, 1e-6)
        return (lo < 0 ? lo - span * 0.06 : 0)...(hi + span * 0.08)
    }

    /// Candles are padded a little so wicks never touch the plot edge.
    private var candleYDomain: ClosedRange<Double> {
        let candles = spec.candles ?? []
        guard let low = candles.map(\.low).min(), let high = candles.map(\.high).max(), high > low else {
            return 0...1
        }
        let pad = (high - low) * 0.08
        return (low - pad)...(high + pad)
    }

    // MARK: Kinds

    private var candlestick: some View {
        Chart {
            ForEach(spec.candles ?? [], id: \.x) { candle in
                RectangleMark(x: .value(spec.xLabel, candle.x),
                              yStart: .value("Low", candle.low),
                              yEnd: .value("High", candle.high),
                              width: .fixed(1.5))
                    .foregroundStyle(candle.isUp ? Econ.sky : Econ.amber)
                RectangleMark(x: .value(spec.xLabel, candle.x),
                              yStart: .value("Open", min(candle.open, candle.close)),
                              yEnd: .value("Close", max(candle.open, candle.close)),
                              width: .ratio(0.6))
                    .foregroundStyle(candle.isUp ? Econ.sky : Econ.amber)
            }
            numericMarkers
        }
        .chartXScale(domain: (xDomain.lowerBound - xStep * 0.6)...(xDomain.upperBound + xStep * 0.6))
        .chartYScale(domain: candleYDomain)
        .modifier(ChartStyle(xLabel: spec.xLabel, yLabel: spec.yLabel))
    }

    private var lines: some View {
        Chart {
            ForEach(spec.series ?? [], id: \.name) { series in
                ForEach(series.points, id: \.x) { point in
                    LineMark(x: .value(spec.xLabel, point.x), y: .value(spec.yLabel, point.y))
                        .foregroundStyle(by: .value("Series", series.name))
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2.2))
                }
            }
            numericMarkers
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: lineYDomain)
        .chartForegroundStyleScale(range: palette)
        .chartLegend((spec.series?.count ?? 0) > 1 ? .visible : .hidden)
        .modifier(ChartStyle(xLabel: spec.xLabel, yLabel: spec.yLabel))
    }

    /// Many bars (a daily volume series): a numeric x axis.
    private var numericBars: some View {
        Chart {
            ForEach(spec.series ?? [], id: \.name) { series in
                ForEach(series.points, id: \.x) { point in
                    BarMark(x: .value(spec.xLabel, point.x), y: .value(spec.yLabel, point.y),
                            width: .ratio(0.7))
                        .foregroundStyle(by: .value("Series", series.name))
                        .position(by: .value("Series", series.name))
                        .cornerRadius(EconRadius.mark)
                }
            }
            numericMarkers
        }
        .chartXScale(domain: (xDomain.lowerBound - xStep * 0.6)...(xDomain.upperBound + xStep * 0.6))
        .chartYScale(domain: barYDomain)
        .chartForegroundStyleScale(range: palette)
        .chartLegend((spec.series?.count ?? 0) > 1 ? .visible : .hidden)
        .modifier(ChartStyle(xLabel: spec.xLabel, yLabel: spec.yLabel))
    }

    // MARK: Categorical bars

    private var isCategorical: Bool { spec.kind == .bar && distinctX.count <= 12 }

    /// Marker labels that name every category exactly (and nothing else).
    private var categoryNames: [Double: String]? {
        guard let markers = spec.markers, !markers.isEmpty else { return nil }
        let names = Dictionary(markers.map { ($0.x, $0.label) }, uniquingKeysWith: { first, _ in first })
        return Set(names.keys) == Set(distinctX) ? names : nil
    }

    private func category(_ x: Double) -> String {
        if let name = categoryNames?[x] { return name }
        return Self.short(x)
    }

    private var categoricalBars: some View {
        Chart {
            ForEach(spec.series ?? [], id: \.name) { series in
                ForEach(series.points, id: \.x) { point in
                    BarMark(x: .value(spec.xLabel, category(point.x)), y: .value(spec.yLabel, point.y))
                        .foregroundStyle(by: .value("Series", series.name))
                        .position(by: .value("Series", series.name))
                        .cornerRadius(EconRadius.mark)
                }
            }
            if categoryNames == nil {
                ForEach(Array((spec.markers ?? []).enumerated()), id: \.offset) { index, marker in
                    let nearest = distinctX.min { abs($0 - marker.x) < abs($1 - marker.x) } ?? marker.x
                    RuleMark(x: .value("Marker", category(nearest)))
                        .foregroundStyle(Econ.mist.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .annotation(position: .top, alignment: markerAlignment(for: nearest),
                                    spacing: index % 2 == 1 ? 16 : 2) {
                            markerTag(marker.label)
                        }
                }
            }
        }
        .chartXScale(domain: distinctX.map(category))
        .chartYScale(domain: barYDomain)
        .chartForegroundStyleScale(range: palette)
        .chartLegend((spec.series?.count ?? 0) > 1 ? .visible : .hidden)
        .modifier(ChartStyle(xLabel: categoryNames == nil ? spec.xLabel : "", yLabel: spec.yLabel))
    }

    // MARK: Markers

    /// Extra space above the plot for marker labels: one row, or two when
    /// several markers alternate rows so neighboring labels do not collide.
    private var markerHeadroom: CGFloat {
        if isCategorical && categoryNames != nil { return 0 }
        let count = spec.markers?.count ?? 0
        return count == 0 ? 0 : (count > 1 ? 30 : 14)
    }

    /// Labels for markers in the right half of the plot extend leftward so they
    /// stay inside the chart (iOS 16 has no annotation overflow resolution).
    private func markerAlignment(for x: Double) -> Alignment {
        let range = xDomain
        guard range.upperBound > range.lowerBound else { return .leading }
        return (x - range.lowerBound) / (range.upperBound - range.lowerBound) > 0.5 ? .trailing : .leading
    }

    private func markerTag(_ label: String) -> some View {
        Text(label)
            .font(EconType.micro)
            .foregroundColor(Econ.mist)
            .padding(.horizontal, 4)
            .background(EconColor.background.opacity(0.85))
            .cornerRadius(EconRadius.mark)
    }

    @ChartContentBuilder
    private var numericMarkers: some ChartContent {
        ForEach(Array((spec.markers ?? []).enumerated()), id: \.offset) { index, marker in
            RuleMark(x: .value("Marker", marker.x))
                .foregroundStyle(Econ.mist.opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .annotation(position: .top, alignment: markerAlignment(for: marker.x),
                            spacing: index % 2 == 1 ? 16 : 2) {
                    markerTag(marker.label)
                }
        }
    }

    private var palette: [Color] { [Econ.sky, Econ.amber, Econ.mist, Econ.amberLight] }

    /// A short spoken summary so VoiceOver users get the shape of the data.
    private var accessibilitySummary: String {
        switch spec.kind {
        case .candlestick:
            let candles = spec.candles ?? []
            guard let first = candles.first, let last = candles.last else { return "No data." }
            let direction = last.close >= first.open ? "higher" : "lower"
            return "\(candles.count) synthetic candles, ending \(direction) than they began."
        case .line, .bar:
            let series = spec.series ?? []
            let parts = series.map { s -> String in
                guard let first = s.points.first, let last = s.points.last else { return s.name }
                let direction = last.y > first.y ? "rises" : (last.y < first.y ? "falls" : "stays level")
                return "\(s.name) \(direction) from \(Self.short(first.y)) to \(Self.short(last.y))"
            }
            return parts.joined(separator: "; ") + ". Synthetic data."
        }
    }

    static func short(_ value: Double) -> String {
        if value == value.rounded() { return String(Int(value)) }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}

/// Axis labels and the muted grid the ocean palette needs.
private struct ChartStyle: ViewModifier {
    let xLabel: String
    let yLabel: String
    func body(content: Content) -> some View {
        content
            .chartXAxisLabel(xLabel, alignment: .center)
            .chartYAxisLabel(yLabel, position: .leading)
            .chartXAxis {
                AxisMarks { _ in
                    AxisGridLine().foregroundStyle(Econ.mist.opacity(0.15))
                    AxisValueLabel().foregroundStyle(EconColor.textTertiary)
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine().foregroundStyle(Econ.mist.opacity(0.15))
                    AxisValueLabel().foregroundStyle(EconColor.textTertiary)
                }
            }
            .foregroundStyle(EconColor.textTertiary)
    }
}
