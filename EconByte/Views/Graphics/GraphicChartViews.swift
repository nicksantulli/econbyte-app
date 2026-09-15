import SwiftUI
import Charts

// MARK: - Bars

/// Horizontal labelled bars: label, bar, value on one row each.
struct BarsGraphicView: View {
    let bars: BarsGraphic
    let size: GraphicSize
    let palette: GraphicPalette
    // Fixed columns: at large text the label wraps instead of squeezing the bar.
    private let labelWidth: CGFloat = 100
    private let valueWidth: CGFloat = 80

    var body: some View {
        let maxValue = max(bars.items.map(\.value).max() ?? 1, 1e-9)
        VStack(alignment: .leading, spacing: size == .regular ? 7 : 4) {
            ForEach(Array(bars.items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 8) {
                    Text(item.label)
                        .font(.system(size == .regular ? .caption : .caption2, design: .rounded))
                        .foregroundColor(palette.ink)
                        .lineLimit(3)
                        .minimumScaleFactor(0.8)
                        .frame(width: labelWidth, alignment: .leading)
                    GeometryReader { geo in
                        let width = max(3, geo.size.width * CGFloat(item.value / maxValue))
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(item.emphasis == true ? palette.accent : palette.primary)
                            .frame(width: width, height: geo.size.height)
                            .frame(maxHeight: .infinity, alignment: .center)
                    }
                    .frame(height: size == .regular ? 12 : 9)
                    Text(item.display ?? GraphicFormat.value(item.value, unit: bars.unit, decimals: bars.decimals))
                        .font(.system(size == .regular ? .caption : .caption2, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                        .foregroundColor(palette.ink)
                        .lineLimit(1)
                        // "~$952.38" at the largest standard size needs ~84 pt; shrink rather than truncate.
                        .minimumScaleFactor(0.6)
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
                            RoundedRectangle(cornerRadius: 1.5)
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
            .background(RoundedRectangle(cornerRadius: 3).fill(palette.plateOpaque))
    }
}

extension GraphicPalette {
    /// Tags sit over lines; the light plate is translucent, so give them an
    /// opaque backing that matches the card surface.
    var plateOpaque: Color { self.ink == Econ.ink ? Econ.page : Econ.ocean }
}

// MARK: - Proportion

struct ProportionGraphicView: View {
    let proportion: ProportionGraphic
    let size: GraphicSize
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
        }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: size == .regular ? 4 : 2) {
            ForEach(shares) { share in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2).fill(share.color).frame(width: 10, height: 10)
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
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            .frame(height: size == .regular ? 20 : 14)
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
        let gridHeight = size == .regular ? min(height, CGFloat(rows) * 14) : min(height * 0.9, CGFloat(rows) * 9)
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
