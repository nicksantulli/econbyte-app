import Foundation

/// Number, axis and spoken formatting shared by the graphic views, the
/// accessibility summaries and the tests. Fixed to en_US: the content is
/// written in U.S. English with "$" prefixes.
enum GraphicFormat {

    private static let locale = Locale(identifier: "en_US")

    /// Grouped number. `decimals` nil: whole numbers print whole, others with
    /// up to two decimals and no trailing zeros.
    static func number(_ value: Double, decimals: Int? = nil) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        if let decimals {
            formatter.minimumFractionDigits = decimals
            formatter.maximumFractionDigits = decimals
        } else {
            formatter.minimumFractionDigits = 0
            formatter.maximumFractionDigits = value == value.rounded() ? 0 : 2
        }
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    static func value(_ value: Double, unit: GraphicUnit?, decimals: Int?) -> String {
        let sign = value < 0 ? "−" : ""
        return sign + (unit?.prefix ?? "") + number(abs(value), decimals: decimals) + (unit?.suffix ?? "")
    }

    /// Axis label: the full grouped number with the series unit. Never scaled
    /// to K/M/B, because many series are already in millions or billions (the
    /// y-axis label says so) and "$625K" would misstate "$625,000 million".
    static func axis(_ value: Double, unit: GraphicUnit?) -> String {
        let decimals = value == value.rounded() ? 0 : (abs(value) < 10 ? 1 : 0)
        return self.value(value, unit: unit, decimals: decimals)
    }

    private static let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// x = year + (month − 1) / 12 → "Feb 2020".
    static func month(_ x: Double) -> String {
        let totalMonths = Int((x * 12).rounded())
        let year = totalMonths / 12
        let month = totalMonths - year * 12
        return "\(monthNames[max(0, min(11, month))]) \(year)"
    }

    static func x(_ x: Double, format: LineGraphic.XFormat) -> String {
        switch format {
        case .year:   return String(Int(x.rounded()))
        case .month:  return month(x)
        case .number: return number(x)
        }
    }

    /// Up to `desired` "nice" tick values across lo...hi (1, 2, 2.5 or 5 × 10^k).
    static func ticks(_ lo: Double, _ hi: Double, desired: Int, integerOnly: Bool = false) -> [Double] {
        guard hi > lo, desired > 1 else { return [lo] }
        let rough = (hi - lo) / Double(desired - 1)
        let exponent = floor(log10(rough))
        let base = pow(10, exponent)
        let candidates = [1, 2, 2.5, 5, 10].map { $0 * base }
        var step = candidates.first { $0 >= rough } ?? candidates.last!
        if integerOnly { step = max(1, step.rounded(.up)) }
        var ticks: [Double] = []
        var tick = (lo / step).rounded(.up) * step
        while tick <= hi + step * 1e-9 {
            ticks.append(abs(tick) < step * 1e-9 ? 0 : tick)
            tick += step
        }
        return ticks
    }

    /// Reads an expression aloud: "GDP = C + I" → "GDP equals C plus I".
    static func spoken(_ expression: String) -> String {
        var s = expression
        for (symbol, word) in [("=", " equals "), ("×", " times "), ("÷", " divided by "), ("−", " minus "),
                               ("+", " plus "), ("≈", " approximately equals "), ("/", " divided by ")] {
            s = s.replacingOccurrences(of: symbol, with: word)
        }
        return s.split(separator: " ").joined(separator: " ")
    }
}

// MARK: - Accessibility summaries

extension CardGraphicSpec {

    /// What VoiceOver says for the graphic: title, then the content in words,
    /// then the basis footnote. Generated from the payload, so it can never
    /// disagree with the drawing.
    public var accessibilitySummary: String {
        var parts = ["Graphic: \(title)."]
        switch kind {
        case .bars:
            if let bars {
                parts.append(bars.items.map { item in
                    "\(item.label), \(item.display ?? GraphicFormat.value(item.value, unit: bars.unit, decimals: bars.decimals))"
                }.joined(separator: "; ") + ".")
            }
        case .line:
            if let line {
                for series in line.series {
                    let points = series.points.filter { $0.count == 2 }
                    guard let first = points.first, let last = points.last else { continue }
                    let fmt = { (v: Double) in GraphicFormat.value(v, unit: line.unit, decimals: line.decimals) }
                    let high = points.max { $0[1] < $1[1] }!
                    let low = points.min { $0[1] < $1[1] }!
                    // "in Jun 2022" for dates; "at year 20" for a counted axis.
                    let when = { (x: Double) -> String in
                        line.xFormat == .number
                            ? "at \(line.xLabel.lowercased()) \(GraphicFormat.x(x, format: .number))"
                            : "in \(GraphicFormat.x(x, format: line.xFormat))"
                    }
                    var sentence = "\(series.name): \(fmt(first[1])) \(when(first[0])), \(fmt(last[1])) \(when(last[0]))"
                    if high[1] > max(first[1], last[1]) {
                        sentence += ", peaking at \(fmt(high[1])) \(when(high[0]))"
                    }
                    if low[1] < min(first[1], last[1]) {
                        sentence += ", lowest at \(fmt(low[1])) \(when(low[0]))"
                    }
                    parts.append(sentence + ".")
                }
                for marker in line.markers ?? [] { parts.append("Marked: \(marker.label).") }
                for reference in line.references ?? [] { parts.append("Reference line: \(reference.label).") }
            }
        case .diagram:
            if let diagram {
                parts.append("Diagram with \(diagram.xLabel) across and \(diagram.yLabel) up.")
                let curves = diagram.curves.compactMap { curve -> String? in
                    guard let label = curve.label, let first = curve.points.first, let last = curve.points.last,
                          first.count == 2, last.count == 2 else { return nil }
                    let slope = last[1] > first[1] + 0.05 ? "rising" : (last[1] < first[1] - 0.05 ? "falling" : "level")
                    return "\(label), \(slope)\(curve.style == .dashed ? ", dashed" : "")"
                }
                if !curves.isEmpty { parts.append("Lines: " + curves.joined(separator: "; ") + ".") }
                let dots = (diagram.dots ?? []).compactMap(\.label)
                if !dots.isEmpty { parts.append("Points: " + dots.joined(separator: "; ") + ".") }
                let guides = (diagram.guides ?? []).compactMap(\.label)
                if !guides.isEmpty { parts.append("Guide lines: " + guides.joined(separator: "; ") + ".") }
                let arrows = (diagram.arrows ?? []).compactMap(\.label)
                if !arrows.isEmpty { parts.append("Arrows: " + arrows.joined(separator: "; ") + ".") }
            }
        case .flow:
            if let flow {
                let steps = flow.steps.map { step in step.detail.map { "\(step.title) (\($0))" } ?? step.title }
                if flow.layout == .cycle {
                    parts.append("A cycle: " + steps.joined(separator: ", then ") + ", and back to \(flow.steps.first?.title ?? "the start").")
                } else {
                    parts.append("In sequence: " + steps.joined(separator: ", then ") + ".")
                }
            }
        case .compare:
            if let compare {
                parts.append("Comparing \(compare.columns.joined(separator: " and ")).")
                for row in compare.rows {
                    let cells = zip(compare.columns, row.values).map { "\($0): \($1)" }.joined(separator: "; ")
                    parts.append(row.label.isEmpty ? "\(cells)." : "\(row.label): \(cells).")
                }
            }
        case .timeline:
            if let timeline {
                parts.append(timeline.events.map { "\($0.when): \($0.label)" }.joined(separator: "; ") + ".")
            }
        case .formula:
            if let formula {
                parts.append(GraphicFormat.spoken(formula.expression) + ".")
                if !formula.terms.isEmpty {
                    parts.append("Where " + formula.terms.map { "\($0.symbol) is \($0.meaning)" }.joined(separator: "; ") + ".")
                }
                if let example = formula.example { parts.append(GraphicFormat.spoken(example) + ".") }
            }
        case .proportion:
            if let proportion {
                var shares = proportion.segments.map { "\($0.label), \(GraphicFormat.number($0.value))" }
                if proportion.remainder > 1e-9, let label = proportion.remainderLabel {
                    shares.append("\(label), \(GraphicFormat.number(proportion.remainder))")
                }
                let whole = proportion.unitLabel ?? "of \(GraphicFormat.number(proportion.total))"
                parts.append(shares.joined(separator: "; ") + " \(whole).")
            }
        case .icons:
            if let icons {
                let joiner: String
                switch icons.connector {
                case .plus:   joiner = " plus "
                case .arrow:  joiner = " leads to "
                case .versus: joiner = " versus "
                case .equals: joiner = " equals "
                case .none:   joiner = ", "
                }
                parts.append(icons.items.map(\.label).joined(separator: joiner) + ".")
            }
        }
        if let footnote { parts.append(footnote + ".") }
        return parts.joined(separator: " ")
    }
}
