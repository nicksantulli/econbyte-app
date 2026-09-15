import SwiftUI
import Charts

/// Renders a lesson's `chart` block with Swift Charts (1.1.4).
///
/// Every series comes from the block itself — synthetic, hand-designed numbers
/// the validator requires to be labelled as such — so the app carries no
/// market-data dependency and can never show a stale or licensed quote. The
/// `dataNote` ("Synthetic …") is always printed under the chart.
struct ChartBlockView: View {
    let spec: ChartSpec
    /// 1.1.5 story beats say what the chart shows in the beat text; the caption
    /// stays the chart's VoiceOver description.
    var showsCaption = true

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
                .frame(height: 220 + markerHeadroom)
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
        .econInset()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chart-\(spec.chartID)")
    }

    @ViewBuilder
    private var chart: some View {
        switch spec.kind {
        case .candlestick: candlestick
        case .line:        lines
        case .bar:         bars
        }
    }

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
            markers
        }
        .chartYScale(domain: yDomain)
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
            markers
        }
        .chartForegroundStyleScale(range: palette)
        .chartLegend((spec.series?.count ?? 0) > 1 ? .visible : .hidden)
        .modifier(ChartStyle(xLabel: spec.xLabel, yLabel: spec.yLabel))
    }

    private var bars: some View {
        Chart {
            ForEach(spec.series ?? [], id: \.name) { series in
                ForEach(series.points, id: \.x) { point in
                    BarMark(x: .value(spec.xLabel, point.x), y: .value(spec.yLabel, point.y))
                        .foregroundStyle(by: .value("Series", series.name))
                        .cornerRadius(EconRadius.mark)
                }
            }
            markers
        }
        .chartForegroundStyleScale(range: palette)
        .chartLegend((spec.series?.count ?? 0) > 1 ? .visible : .hidden)
        .modifier(ChartStyle(xLabel: spec.xLabel, yLabel: spec.yLabel))
    }

    /// Extra space above the plot for marker labels: one row, or two when
    /// several markers alternate rows so neighboring labels do not collide.
    private var markerHeadroom: CGFloat {
        let count = spec.markers?.count ?? 0
        return count == 0 ? 0 : (count > 1 ? 30 : 14)
    }

    /// Labels for markers in the right half of the plot extend leftward so they
    /// stay inside the chart (iOS 16 has no annotation overflow resolution).
    private func markerAlignment(for x: Double) -> Alignment {
        let xs = (spec.candles?.map(\.x) ?? []) + (spec.series ?? []).flatMap { $0.points.map(\.x) }
        guard let low = xs.min(), let high = xs.max(), high > low else { return .leading }
        return (x - low) / (high - low) > 0.5 ? .trailing : .leading
    }

    @ChartContentBuilder
    private var markers: some ChartContent {
        ForEach(Array((spec.markers ?? []).enumerated()), id: \.offset) { index, marker in
            RuleMark(x: .value("Marker", marker.x))
                .foregroundStyle(Econ.mist.opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .annotation(position: .top, alignment: markerAlignment(for: marker.x),
                            spacing: index % 2 == 1 ? 16 : 2) {
                    Text(marker.label)
                        .font(EconType.micro)
                        .foregroundColor(Econ.mist)
                        .padding(.horizontal, 4)
                        .background(EconColor.background.opacity(0.85))
                        .cornerRadius(EconRadius.mark)
                }
        }
    }

    private var palette: [Color] { [Econ.sky, Econ.amber, Econ.mist, Econ.amberLight] }

    /// Candles are padded a little so wicks never touch the plot edge.
    private var yDomain: ClosedRange<Double> {
        let candles = spec.candles ?? []
        guard let low = candles.map(\.low).min(), let high = candles.map(\.high).max(), high > low else {
            return 0...1
        }
        let pad = (high - low) * 0.08
        return (low - pad)...(high + pad)
    }

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

    private static func short(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
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
