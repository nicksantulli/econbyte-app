import SwiftUI

/// Draws a card's `graphic` (1.1.5) on the concept face.
///
/// The plate owns its background, so it reads on any card surface in light and
/// dark. It is one accessibility element whose label is the generated summary.
///
/// The concept face scrolls (1.1.5 design system), so the plate always renders
/// in full at its natural height: there is no smaller plate and no "show
/// graphic" button. The face's stack supplies the side gutter, so the plate
/// adds none of its own.
struct CardGraphicView: View {
    let spec: CardGraphicSpec

    var body: some View {
        if spec.isRenderable {
            GraphicPlate(spec: spec)
        }
    }
}

// MARK: - Plate

/// One graphic, on a card face (`host: .card`) or on a story-lesson beat
/// (`host: .lesson`, Phase 24). A lesson plate sits on the navy lesson ground
/// with the lesson surface tone, a slightly larger title and a taller chart; a
/// lesson's centerpiece (`prominent`) is taller again.
struct GraphicPlate: View {
    /// Graphic text scales with Dynamic Type up to this size. A ~314 pt plate
    /// cannot hold accessibility-size chart labels without clipping them; the
    /// card's own title and definition keep scaling around it.
    static let largestTypeSize = DynamicTypeSize.xxxLarge
    let spec: CardGraphicSpec
    var host: GraphicHost = .card
    var prominent = false

    var body: some View {
        // The cap wraps the content, so every scaled metric inside it (the
        // chart height included) also stops growing at `largestTypeSize`.
        GraphicPlateContent(spec: spec, host: host, prominent: prominent)
            .dynamicTypeSize(...GraphicPlate.largestTypeSize)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(spec.accessibilitySummary(in: host)))
            .accessibilityAddTraits(.isImage)
            .accessibilityIdentifier(host == .card ? "cardGraphic-\(spec.kind.rawValue)" : "lessonGraphic-\(spec.kind.rawValue)")
    }
}

private struct GraphicPlateContent: View {
    let spec: CardGraphicSpec
    let host: GraphicHost
    let prominent: Bool
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .caption) private var chartHeight: CGFloat = 132

    /// Lesson plates are ~340 pt wide on iPhone 17 (the card plate is ~290), so
    /// their plots get proportionally more height; a centerpiece more again.
    private var plotHeight: CGFloat {
        switch (host, prominent) {
        case (.card, _): return chartHeight
        case (.lesson, false): return chartHeight * 1.25
        case (.lesson, true): return chartHeight * 1.65
        }
    }

    var body: some View {
        let palette = host == .lesson ? GraphicPalette.lesson : GraphicPalette.palette(for: colorScheme)
        VStack(alignment: .leading, spacing: host == .lesson ? EconSpace.xs : 6) {
            // Title and footnote wrap in full: the face scrolls, so nothing here
            // is ever cut short (the footnote carries the basis and the hedges).
            Text(spec.title)
                .font(host == .lesson ? EconType.subheadlineEmphasis : EconType.footnote.weight(.semibold))
                .foregroundColor(palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            GraphicBody(spec: spec, palette: palette, chartHeight: plotHeight)
            if let footnote = spec.footnote(in: host) {
                Text(footnote)
                    .font(.system(.caption2, design: .rounded))
                    .italic()
                    .foregroundColor(palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, EconSpace.s)
        .padding(.vertical, host == .lesson ? EconSpace.s : 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: EconRadius.control, style: .continuous).fill(palette.plate))
        .overlay(RoundedRectangle(cornerRadius: EconRadius.control, style: .continuous).stroke(palette.rim, lineWidth: 1))
    }
}

/// Switches to the drawing for `spec.kind`.
struct GraphicBody: View {
    let spec: CardGraphicSpec
    let palette: GraphicPalette
    let chartHeight: CGFloat

    var body: some View {
        switch spec.kind {
        case .bars:
            if let bars = spec.bars { BarsGraphicView(bars: bars, palette: palette) }
        case .line:
            if let line = spec.line { LineGraphicView(line: line, palette: palette).frame(height: chartHeight) }
        case .diagram:
            // A schematic's labels need room; it never shrinks below 120 pt.
            if let diagram = spec.diagram { DiagramGraphicView(diagram: diagram, palette: palette).frame(height: max(chartHeight, 120)) }
        case .flow:
            if let flow = spec.flow { FlowGraphicView(flow: flow, palette: palette, height: chartHeight) }
        case .compare:
            if let compare = spec.compare { CompareGraphicView(compare: compare, palette: palette) }
        case .timeline:
            if let timeline = spec.timeline { TimelineGraphicView(timeline: timeline, palette: palette) }
        case .formula:
            if let formula = spec.formula { FormulaGraphicView(formula: formula, palette: palette) }
        case .proportion:
            if let proportion = spec.proportion {
                ProportionGraphicView(proportion: proportion, palette: palette, height: chartHeight)
            }
        case .icons:
            if let icons = spec.icons { IconsGraphicView(icons: icons, palette: palette) }
        case .candles:
            if let candles = spec.candles { CandlesGraphicView(candles: candles, palette: palette, height: max(chartHeight, 132)) }
        }
    }
}

// MARK: - Palette

/// The graphic's colors, drawn from the existing `Econ` tokens only.
struct GraphicPalette {
    let plate: Color
    let rim: Color
    let ink: Color
    let secondary: Color
    let grid: Color
    let primary: Color
    let accent: Color
    let muted: Color
    let chip: Color
    let third: Color
    let remainder: Color
    /// An opaque color matching the plate, behind tags that sit over lines.
    let backing: Color

    static func palette(for scheme: ColorScheme) -> GraphicPalette {
        scheme == .dark ? dark : light
    }

    static let light = GraphicPalette(
        plate: Econ.tide.opacity(0.07), rim: Econ.tide.opacity(0.14), ink: Econ.ink, secondary: EconColor.onCardSecondary,
        grid: EconColor.onCardSecondary.opacity(0.22), primary: Econ.tide, accent: Econ.amber, muted: EconColor.onCardSecondary.opacity(0.7),
        chip: Econ.tide.opacity(0.12), third: Econ.sky, remainder: EconColor.onCardSecondary.opacity(0.2), backing: Econ.page)

    static let dark = GraphicPalette(
        plate: Econ.ocean, rim: Econ.tide.opacity(0.45), ink: Econ.white, secondary: Econ.mist.opacity(0.78),
        grid: Econ.mist.opacity(0.16), primary: Econ.sky, accent: Econ.amber, muted: Econ.mist.opacity(0.62),
        chip: Econ.tide.opacity(0.42), third: Econ.amberLight, remainder: Econ.mist.opacity(0.2), backing: Econ.ocean)

    /// Story lessons (Phase 24): the plate is the lesson surface tone on the navy
    /// ground, borderless like the lesson's other pictures; secondary text is the
    /// AA tertiary token (5.1:1 on this surface).
    static let lesson = GraphicPalette(
        plate: EconColor.surface, rim: .clear, ink: Econ.white, secondary: EconColor.textTertiary,
        grid: Econ.mist.opacity(0.16), primary: Econ.sky, accent: Econ.amber, muted: Econ.mist.opacity(0.62),
        chip: Econ.tide.opacity(0.42), third: Econ.amberLight, remainder: Econ.mist.opacity(0.2), backing: Color(hex: "10455C"))

    /// Series / segment colors in order.
    var series: [Color] { [primary, accent, third, muted] }

    static func symbol(for kind: CardGraphicKind) -> String {
        switch kind {
        case .bars:       return "chart.bar"
        case .line:       return "chart.line.uptrend.xyaxis"
        case .diagram:    return "chart.xyaxis.line"
        case .flow:       return "arrow.triangle.branch"
        case .compare:    return "tablecells"
        case .timeline:   return "calendar"
        case .formula:    return "function"
        case .proportion: return "chart.pie"
        case .icons:      return "square.grid.2x2"
        case .candles:    return "chart.bar.xaxis"
        }
    }
}
