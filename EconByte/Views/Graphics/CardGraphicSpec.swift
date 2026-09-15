import Foundation

// MARK: - Card graphics (1.1.5)
//
// A card may carry one optional `graphic`: a small typed spec the app draws
// natively (`CardGraphicView`) — no image assets. The contract, including the
// accuracy rules every number must satisfy, is
// `docs/content/CARD-GRAPHICS-1.1.5.md`; `scripts/card_graphics.mjs` checks
// the content against the card prose and `CardGraphicsTests` is the build gate.
//
// Decoding is strict on `kind`/`basis` (an unknown value fails the catalog
// closed, exactly like an unknown difficulty) and tolerant of extra keys, so
// the provenance fields the content script keeps (`recipe`, `compute`) are
// carried in the JSON without being modeled here.

public enum CardGraphicKind: String, Codable, Hashable, CaseIterable {
    case bars, line, diagram, flow, compare, timeline, formula, proportion, icons
}

/// Why the graphic's numbers can be trusted — printed under the graphic.
public enum CardGraphicBasis: String, Codable, Hashable, CaseIterable {
    /// A mechanism or a set of named parts. Carries no numbers at all.
    case conceptual
    /// Restates figures the card's own (audited, sourced) prose states.
    case fromCard
    /// A series computed exactly from a stated formula and the card's inputs.
    case computed
    /// Real data resolved from FRED or the World Bank, cited in `source`.
    case sourced
    /// Invented shapes or numbers that teach a mechanism.
    case illustrative
}

public struct CardGraphicSource: Codable, Hashable {
    public let organization: String
    public let title: String
    public let url: String
    public let period: String
    public let retrieved: String
}

public struct CardGraphicDerived: Codable, Hashable {
    public let value: Double
    public let expr: String
}

public struct GraphicUnit: Codable, Hashable {
    public let prefix: String?
    public let suffix: String?
}

// MARK: Payloads

public struct BarsGraphic: Codable, Hashable {
    public struct Item: Codable, Hashable {
        public let label: String
        public let value: Double
        public let display: String?
        public let emphasis: Bool?
    }
    public let unit: GraphicUnit?
    public let decimals: Int?
    public let items: [Item]
}

public struct LineGraphic: Codable, Hashable {
    public enum XFormat: String, Codable, Hashable { case year, month, number }
    public struct Series: Codable, Hashable {
        public let name: String
        /// `[x, y]` pairs.
        public let points: [[Double]]
    }
    public struct Marker: Codable, Hashable {
        public let x: Double
        public let label: String
    }
    public struct Reference: Codable, Hashable {
        public let y: Double
        public let label: String
    }
    public let xLabel: String
    public let yLabel: String
    public let xFormat: XFormat
    public let unit: GraphicUnit?
    public let decimals: Int?
    public let series: [Series]
    public let markers: [Marker]?
    public let references: [Reference]?
}

public struct DiagramGraphic: Codable, Hashable {
    public enum Style: String, Codable, Hashable { case solid, dashed }
    public enum Tone: String, Codable, Hashable { case primary, accent, muted }
    public enum Axis: String, Codable, Hashable { case x, y }
    public struct Curve: Codable, Hashable {
        public let label: String?
        /// `[x, y]` pairs in unit space, origin bottom-left.
        public let points: [[Double]]
        public let style: Style?
        public let tone: Tone?
    }
    public struct Dot: Codable, Hashable {
        public let x: Double
        public let y: Double
        public let label: String?
    }
    public struct Guide: Codable, Hashable {
        public let axis: Axis
        public let at: Double
        public let label: String?
    }
    public struct Arrow: Codable, Hashable {
        public let from: [Double]
        public let to: [Double]
        public let label: String?
    }
    public let xLabel: String
    public let yLabel: String
    public let curves: [Curve]
    public let dots: [Dot]?
    public let guides: [Guide]?
    public let arrows: [Arrow]?
}

public struct FlowGraphic: Codable, Hashable {
    public enum Layout: String, Codable, Hashable { case chain, cycle }
    public struct Step: Codable, Hashable {
        public let title: String
        public let detail: String?
    }
    public let layout: Layout
    public let steps: [Step]
}

public struct CompareGraphic: Codable, Hashable {
    public struct Row: Codable, Hashable {
        public let label: String
        public let values: [String]
    }
    public let columns: [String]
    public let rows: [Row]
}

public struct TimelineGraphic: Codable, Hashable {
    public struct Event: Codable, Hashable {
        public let when: String
        public let label: String
    }
    public let events: [Event]
}

public struct FormulaGraphic: Codable, Hashable {
    public struct Term: Codable, Hashable {
        public let symbol: String
        public let meaning: String
    }
    public let expression: String
    public let terms: [Term]
    public let example: String?
}

public struct ProportionGraphic: Codable, Hashable {
    public enum Style: String, Codable, Hashable { case bar, waffle }
    public struct Segment: Codable, Hashable {
        public let label: String
        public let value: Double
    }
    public let style: Style
    public let total: Double
    public let unitLabel: String?
    public let segments: [Segment]
    public let remainderLabel: String?

    public var remainder: Double { max(0, total - segments.reduce(0) { $0 + $1.value }) }
}

public struct IconsGraphic: Codable, Hashable {
    public enum Connector: String, Codable, Hashable { case plus, arrow, versus, equals, none }
    public struct Item: Codable, Hashable {
        public let symbol: String
        public let label: String
    }
    public let connector: Connector
    public let items: [Item]
}

// MARK: - Spec

public struct CardGraphicSpec: Codable, Hashable {
    public let kind: CardGraphicKind
    public let title: String
    public let basis: CardGraphicBasis
    public let note: String?
    public let source: CardGraphicSource?
    public let derived: [CardGraphicDerived]?

    public let bars: BarsGraphic?
    public let line: LineGraphic?
    public let diagram: DiagramGraphic?
    public let flow: FlowGraphic?
    public let compare: CompareGraphic?
    public let timeline: TimelineGraphic?
    public let formula: FormulaGraphic?
    public let proportion: ProportionGraphic?
    public let icons: IconsGraphic?

    /// The footnote the app prints under the graphic: what the numbers rest on,
    /// then the author's note.
    public var footnote: String? {
        let basisLine: String?
        switch basis {
        case .conceptual:   basisLine = nil
        case .fromCard:     basisLine = "Figures from this card's source"
        case .computed:     basisLine = "Computed from this card's figures"
        case .sourced:      basisLine = source.map { "Source: \($0.organization), \($0.period)" }
        case .illustrative: basisLine = "Illustrative, not real data"
        }
        let parts = [basisLine, note].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Whether the payload for `kind` is present and has the minimum shape the
    /// renderer needs. The full content contract is `validationProblems()`;
    /// this runtime guard only keeps a malformed spec from drawing garbage.
    public var isRenderable: Bool {
        switch kind {
        case .bars:       return (bars?.items.count ?? 0) >= 1
        case .line:       return (line?.series.contains { $0.points.filter { $0.count == 2 }.count >= 2 }) ?? false
        case .diagram:    return (diagram?.curves.contains { $0.points.count >= 2 }) ?? false
        case .flow:       return (flow?.steps.count ?? 0) >= 2
        case .compare:    return (compare.map { $0.columns.count >= 2 && !$0.rows.isEmpty }) ?? false
        case .timeline:   return (timeline?.events.count ?? 0) >= 1
        case .formula:    return !(formula?.expression.isEmpty ?? true)
        case .proportion: return (proportion.map { $0.total > 0 && !$0.segments.isEmpty }) ?? false
        case .icons:      return (icons?.items.count ?? 0) >= 1
        }
    }
}

// MARK: - Validation (mirrors scripts/card_graphics.mjs structure checks)

public extension CardGraphicSpec {

    static let approvedSourceHosts: Set<String> = ["fred.stlouisfed.org", "data.worldbank.org"]

    enum Limit {
        static let title = 56, note = 90, barLabel = 26, barDisplay = 16, markerLabel = 18, diagramLabel = 18
        static let axisLabel = 24, flowTitle = 34, flowDetail = 48, compareHead = 16, compareLabel = 16
        static let compareValue = 24, when = 14, eventLabel = 40, expression = 40, symbol = 8, meaning = 32
        static let example = 60, segLabel = 22, unitLabel = 34, iconLabel = 18, seriesName = 28
    }

    /// Every displayed string, for house-rule scans.
    var displayStrings: [String] {
        var out = [title]
        if let note { out.append(note) }
        switch kind {
        case .bars:
            out += (bars?.items ?? []).flatMap { [$0.label, $0.display].compactMap { $0 } }
            out += [bars?.unit?.prefix, bars?.unit?.suffix].compactMap { $0 }
        case .line:
            if let line {
                out += [line.xLabel, line.yLabel] + line.series.map(\.name)
                out += (line.markers ?? []).map(\.label) + (line.references ?? []).map(\.label)
            }
        case .diagram:
            if let diagram {
                out += [diagram.xLabel, diagram.yLabel] + diagram.curves.compactMap(\.label)
                out += (diagram.dots ?? []).compactMap(\.label) + (diagram.guides ?? []).compactMap(\.label)
                out += (diagram.arrows ?? []).compactMap(\.label)
            }
        case .flow:
            out += (flow?.steps ?? []).flatMap { [$0.title, $0.detail].compactMap { $0 } }
        case .compare:
            if let compare { out += compare.columns + compare.rows.flatMap { [$0.label] + $0.values } }
        case .timeline:
            out += (timeline?.events ?? []).flatMap { [$0.when, $0.label] }
        case .formula:
            if let formula {
                out += [formula.expression] + formula.terms.flatMap { [$0.symbol, $0.meaning] }
                if let example = formula.example { out.append(example) }
            }
        case .proportion:
            if let proportion {
                out += proportion.segments.map(\.label) + [proportion.unitLabel, proportion.remainderLabel].compactMap { $0 }
            }
        case .icons:
            out += (icons?.items ?? []).map(\.label)
        }
        return out
    }

    /// Structural problems with this spec; empty when it satisfies the contract.
    func validationProblems() -> [String] {
        var problems: [String] = []
        func fail(_ message: String) { problems.append(message) }
        func check(_ where_: String, _ text: String?, max: Int, required: Bool = true) {
            guard let text else { if required { fail("\(where_) is required") }; return }
            if required && text.trimmingCharacters(in: .whitespaces).isEmpty { fail("\(where_) is empty") }
            if text.count > max { fail("\(where_) is \(text.count) characters, limit \(max)") }
        }
        func inUnit(_ where_: String, _ v: Double?) {
            guard let v, v >= 0, v <= 1 else { fail("\(where_) must be in [0, 1]"); return }
        }

        check("title", title, max: Limit.title)
        if title.hasSuffix(".") { fail("title ends with a period") }
        if let note { check("note", note, max: Limit.note) }

        let payloads: [(CardGraphicKind, Bool)] = [
            (.bars, bars != nil), (.line, line != nil), (.diagram, diagram != nil), (.flow, flow != nil),
            (.compare, compare != nil), (.timeline, timeline != nil), (.formula, formula != nil),
            (.proportion, proportion != nil), (.icons, icons != nil),
        ]
        for (k, present) in payloads {
            if k == kind && !present { fail("\(k.rawValue) payload is missing") }
            if k != kind && present { fail("\(k.rawValue) payload present on a \(kind.rawValue) graphic") }
        }

        switch kind {
        case .bars:
            guard let bars else { break }
            if !(2...6).contains(bars.items.count) { fail("bars: 2–6 items") }
            for (i, item) in bars.items.enumerated() {
                check("bars.items[\(i)].label", item.label, max: Limit.barLabel)
                if item.display != nil { check("bars.items[\(i)].display", item.display, max: Limit.barDisplay) }
                if !(item.value.isFinite && item.value >= 0) { fail("bars.items[\(i)].value must be ≥ 0") }
            }
            if bars.items.filter({ $0.emphasis == true }).count > 2 { fail("bars: at most 2 emphasized") }
            if bars.items.allSatisfy({ $0.value == 0 }) { fail("bars: all values are zero") }
            if let d = bars.decimals, !(0...3).contains(d) { fail("bars.decimals 0–3") }
        case .line:
            guard let line else { break }
            check("line.xLabel", line.xLabel, max: Limit.axisLabel)
            check("line.yLabel", line.yLabel, max: Limit.axisLabel)
            if !(1...3).contains(line.series.count) { fail("line: 1–3 series") }
            var xs: [Double] = []
            for (i, series) in line.series.enumerated() {
                check("line.series[\(i)].name", series.name, max: Limit.seriesName)
                if !(2...60).contains(series.points.count) { fail("line.series[\(i)]: 2–60 points") }
                if series.points.contains(where: { $0.count != 2 || !$0[0].isFinite || !$0[1].isFinite }) {
                    fail("line.series[\(i)]: every point is [x, y]")
                    continue
                }
                for j in series.points.indices.dropFirst() where !(series.points[j][0] > series.points[j - 1][0]) {
                    fail("line.series[\(i)]: x must strictly increase")
                    break
                }
                xs += series.points.map { $0[0] }
            }
            if (line.markers?.count ?? 0) > 2 { fail("line: at most 2 markers") }
            if (line.references?.count ?? 0) > 2 { fail("line: at most 2 references") }
            if let lo = xs.min(), let hi = xs.max() {
                for (i, m) in (line.markers ?? []).enumerated() {
                    check("line.markers[\(i)].label", m.label, max: Limit.markerLabel)
                    if m.x < lo || m.x > hi { fail("line.markers[\(i)] outside the x range") }
                }
            }
            for (i, r) in (line.references ?? []).enumerated() { check("line.references[\(i)].label", r.label, max: Limit.markerLabel) }
            if let d = line.decimals, !(0...3).contains(d) { fail("line.decimals 0–3") }
        case .diagram:
            guard let diagram else { break }
            if basis != .conceptual && basis != .illustrative { fail("a diagram is conceptual or illustrative") }
            check("diagram.xLabel", diagram.xLabel, max: Limit.axisLabel)
            check("diagram.yLabel", diagram.yLabel, max: Limit.axisLabel)
            if !(1...4).contains(diagram.curves.count) { fail("diagram: 1–4 curves") }
            for (i, c) in diagram.curves.enumerated() {
                check("diagram.curves[\(i)].label", c.label, max: Limit.diagramLabel, required: false)
                if !(2...12).contains(c.points.count) { fail("diagram.curves[\(i)]: 2–12 points") }
                for (j, p) in c.points.enumerated() {
                    if p.count != 2 { fail("diagram.curves[\(i)].points[\(j)] is not [x, y]"); continue }
                    inUnit("diagram.curves[\(i)].points[\(j)].x", p[0]); inUnit("diagram.curves[\(i)].points[\(j)].y", p[1])
                }
            }
            if (diagram.dots?.count ?? 0) > 3 { fail("diagram: at most 3 dots") }
            for (i, d) in (diagram.dots ?? []).enumerated() {
                inUnit("diagram.dots[\(i)].x", d.x); inUnit("diagram.dots[\(i)].y", d.y)
                check("diagram.dots[\(i)].label", d.label, max: Limit.diagramLabel, required: false)
            }
            if (diagram.guides?.count ?? 0) > 3 { fail("diagram: at most 3 guides") }
            for (i, g) in (diagram.guides ?? []).enumerated() {
                inUnit("diagram.guides[\(i)].at", g.at)
                check("diagram.guides[\(i)].label", g.label, max: Limit.diagramLabel, required: false)
            }
            if (diagram.arrows?.count ?? 0) > 2 { fail("diagram: at most 2 arrows") }
            for (i, a) in (diagram.arrows ?? []).enumerated() {
                if a.from.count != 2 || a.to.count != 2 { fail("diagram.arrows[\(i)] needs from/to pairs"); continue }
                (a.from + a.to).forEach { inUnit("diagram.arrows[\(i)]", $0) }
                check("diagram.arrows[\(i)].label", a.label, max: Limit.diagramLabel, required: false)
            }
        case .flow:
            guard let flow else { break }
            let range = flow.layout == .cycle ? 3...4 : 2...4
            if !range.contains(flow.steps.count) { fail("flow \(flow.layout.rawValue): \(range.lowerBound)–\(range.upperBound) steps") }
            if flow.layout == .chain && flow.steps.count == 4 && flow.steps.contains(where: { $0.detail != nil }) {
                fail("flow: a 4-step chain has no details")
            }
            for (i, s) in flow.steps.enumerated() {
                check("flow.steps[\(i)].title", s.title, max: Limit.flowTitle)
                if let detail = s.detail {
                    check("flow.steps[\(i)].detail", detail, max: Limit.flowDetail)
                    if flow.layout == .cycle { fail("flow.steps[\(i)]: a cycle step has no detail") }
                }
            }
        case .compare:
            guard let compare else { break }
            if !(2...3).contains(compare.columns.count) { fail("compare: 2–3 columns") }
            if !(2...4).contains(compare.rows.count) { fail("compare: 2–4 rows") }
            for (i, c) in compare.columns.enumerated() { check("compare.columns[\(i)]", c, max: Limit.compareHead) }
            for (i, r) in compare.rows.enumerated() {
                check("compare.rows[\(i)].label", r.label, max: Limit.compareLabel, required: false)
                if r.values.count != compare.columns.count { fail("compare.rows[\(i)] needs \(compare.columns.count) values") }
                for (j, v) in r.values.enumerated() { check("compare.rows[\(i)].values[\(j)]", v, max: Limit.compareValue) }
            }
        case .timeline:
            guard let timeline else { break }
            if !(2...5).contains(timeline.events.count) { fail("timeline: 2–5 events") }
            var previous: Int?
            for (i, e) in timeline.events.enumerated() {
                check("timeline.events[\(i)].when", e.when, max: Limit.when)
                check("timeline.events[\(i)].label", e.label, max: Limit.eventLabel)
                guard let key = Self.dateKey(e.when) else { fail("timeline.events[\(i)].when has no four-digit year"); continue }
                if let previous, key < previous { fail("timeline.events[\(i)] is out of order") }
                previous = key
            }
        case .formula:
            guard let formula else { break }
            check("formula.expression", formula.expression, max: Limit.expression)
            if !(1...5).contains(formula.terms.count) { fail("formula: 1–5 terms") }
            for (i, t) in formula.terms.enumerated() {
                check("formula.terms[\(i)].symbol", t.symbol, max: Limit.symbol)
                check("formula.terms[\(i)].meaning", t.meaning, max: Limit.meaning)
            }
            if let example = formula.example { check("formula.example", example, max: Limit.example) }
        case .proportion:
            guard let proportion else { break }
            if !(proportion.total.isFinite && proportion.total > 0) { fail("proportion.total must be > 0") }
            if !(1...4).contains(proportion.segments.count) { fail("proportion: 1–4 segments") }
            for (i, s) in proportion.segments.enumerated() {
                check("proportion.segments[\(i)].label", s.label, max: Limit.segLabel)
                if !(s.value.isFinite && s.value >= 0) { fail("proportion.segments[\(i)].value must be ≥ 0") }
            }
            let sum = proportion.segments.reduce(0) { $0 + $1.value }
            if sum > proportion.total * (1 + 1e-9) { fail("proportion: segments sum above total") }
            if sum < proportion.total - 1e-9 { check("proportion.remainderLabel", proportion.remainderLabel, max: Limit.segLabel) }
            if let unit = proportion.unitLabel { check("proportion.unitLabel", unit, max: Limit.unitLabel) }
            if proportion.style == .waffle {
                if ![10, 20, 50, 100].contains(proportion.total) { fail("proportion: waffle total ∈ {10, 20, 50, 100}") }
                if proportion.segments.contains(where: { $0.value != $0.value.rounded() }) { fail("proportion: waffle values are integers") }
            }
        case .icons:
            guard let icons else { break }
            if !(2...4).contains(icons.items.count) { fail("icons: 2–4 items") }
            for (i, item) in icons.items.enumerated() {
                check("icons.items[\(i)].label", item.label, max: Limit.iconLabel)
                if item.symbol.isEmpty { fail("icons.items[\(i)].symbol is empty") }
            }
        }

        // Basis rules.
        if basis == .conceptual {
            for text in displayStrings where text.rangeOfCharacter(from: .decimalDigits) != nil {
                fail("a conceptual graphic shows no numbers: \"\(text)\"")
            }
            if derived != nil { fail("a conceptual graphic has no derived values") }
        }
        if basis == .sourced {
            if let source {
                for (name, value) in [("organization", source.organization), ("title", source.title),
                                      ("period", source.period), ("retrieved", source.retrieved)] where value.isEmpty {
                    fail("source.\(name) is empty")
                }
                if let url = URL(string: source.url) {
                    if url.scheme != "https" { fail("source.url is not https") }
                    if !Self.approvedSourceHosts.contains(url.host ?? "") { fail("source.url host is not approved") }
                    if url.query != nil || url.fragment != nil { fail("source.url has a query or fragment") }
                } else {
                    fail("source.url is not a URL")
                }
            } else {
                fail("a sourced graphic needs a source")
            }
            if kind != .line { fail("sourced applies to line graphics only") }
        } else if source != nil {
            fail("only a sourced graphic carries a source")
        }
        if basis == .computed && kind != .line { fail("computed applies to line graphics only") }
        return problems
    }

    /// Sortable key for a timeline `when`: year × 10000 + month × 100 + day.
    static func dateKey(_ when: String) -> Int? {
        let lower = when.lowercased()
        guard let yearRange = lower.range(of: #"\d{4}"#, options: .regularExpression),
              let year = Int(lower[yearRange]) else { return nil }
        let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
        var month = 0
        let words = lower.split(whereSeparator: { !$0.isLetter }).map(String.init)
        for word in words {
            if let index = months.firstIndex(where: { word.hasPrefix($0) && word.count >= 3 }) { month = index + 1; break }
        }
        var day = 0
        if month > 0 {
            let rest = lower.replacingCharacters(in: yearRange, with: " ")
            if let dayRange = rest.range(of: #"\b\d{1,2}\b"#, options: .regularExpression), let d = Int(rest[dayRange]) {
                day = d
            }
        }
        return year * 10000 + month * 100 + day
    }
}
