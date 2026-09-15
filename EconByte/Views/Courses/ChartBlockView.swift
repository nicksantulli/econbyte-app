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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(spec.title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(Econ.white)
            chart
                .frame(height: 220)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("\(spec.title). \(spec.caption)"))
                .accessibilityValue(Text(accessibilitySummary))
            Text(spec.caption)
                .font(.system(size: 13, design: .rounded))
                .foregroundColor(Econ.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
            Text(spec.dataNote)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .italic()
                .foregroundColor(Econ.subtext)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("chart-\(spec.chartID)-note")
        }
        .padding(14)
        .background(Econ.ocean.opacity(0.7))
        .cornerRadius(12)
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
                        .cornerRadius(3)
                }
            }
            markers
        }
        .chartForegroundStyleScale(range: palette)
        .chartLegend((spec.series?.count ?? 0) > 1 ? .visible : .hidden)
        .modifier(ChartStyle(xLabel: spec.xLabel, yLabel: spec.yLabel))
    }

    @ChartContentBuilder
    private var markers: some ChartContent {
        ForEach(spec.markers ?? [], id: \.x) { marker in
            RuleMark(x: .value("Marker", marker.x))
                .foregroundStyle(Econ.mist.opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .annotation(position: .top, alignment: .leading) {
                    Text(marker.label)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(Econ.mist)
                        .padding(.horizontal, 4)
                        .background(Econ.ocean.opacity(0.8))
                        .cornerRadius(3)
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
                    AxisValueLabel().foregroundStyle(Econ.subtext)
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine().foregroundStyle(Econ.mist.opacity(0.15))
                    AxisValueLabel().foregroundStyle(Econ.subtext)
                }
            }
            .foregroundStyle(Econ.subtext)
    }
}
