import SwiftUI

/// Draws a card's `graphic` (1.1.5) on the concept face.
///
/// The plate owns its background, so it reads on any card surface in light and
/// dark. It is one accessibility element whose label is the generated summary.
/// If the card's text leaves too little room, the plate first drops to a
/// compact size, then collapses to a one-line button that opens the full
/// graphic in a sheet, so the definition is never pushed off the card.
struct CardGraphicView: View {
    let spec: CardGraphicSpec
    @State private var showsSheet = false

    var body: some View {
        if spec.isRenderable {
            ViewThatFits(in: .vertical) {
                GraphicPlate(spec: spec, size: .regular)
                GraphicPlate(spec: spec, size: .compact)
                collapsed
            }
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .sheet(isPresented: $showsSheet) {
                GraphicSheet(spec: spec)
            }
            .padding(.horizontal, 20)
            // Last, so the card's stack sees it: the card's own text is measured
            // first and the graphic takes what is left (full, compact, or the
            // one-line button).
            .layoutPriority(-1)
        }
    }

    private var collapsed: some View {
        Button { showsSheet = true } label: {
            GraphicCollapsedLabel(spec: spec)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Show graphic: \(spec.title)"))
        .accessibilityIdentifier("cardGraphicCollapsed")
    }
}

// MARK: - Plate

enum GraphicSize { case regular, compact }

struct GraphicPlate: View {
    let spec: CardGraphicSpec
    let size: GraphicSize
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .caption) private var chartHeight: CGFloat = 132
    @ScaledMetric(relativeTo: .caption) private var compactChartHeight: CGFloat = 100

    var body: some View {
        let palette = GraphicPalette.palette(for: colorScheme)
        VStack(alignment: .leading, spacing: 6) {
            Text(spec.title)
                .font(.system(.footnote, design: .rounded).weight(.semibold))
                .foregroundColor(palette.ink)
                .lineLimit(size == .regular ? 2 : 1)
                .fixedSize(horizontal: false, vertical: true)
            GraphicBody(spec: spec, size: size, palette: palette,
                        chartHeight: size == .regular ? chartHeight : compactChartHeight)
            if let footnote = spec.footnote {
                Text(footnote)
                    .font(.system(.caption2, design: .rounded))
                    .italic()
                    .foregroundColor(palette.secondary)
                    .lineLimit(size == .regular ? 3 : 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, size == .regular ? 10 : 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(palette.plate))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(palette.rim, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(spec.accessibilitySummary))
        .accessibilityAddTraits(.isImage)
        .accessibilityIdentifier("cardGraphic-\(spec.kind.rawValue)")
    }
}

/// Switches to the drawing for `spec.kind`.
struct GraphicBody: View {
    let spec: CardGraphicSpec
    let size: GraphicSize
    let palette: GraphicPalette
    let chartHeight: CGFloat

    var body: some View {
        switch spec.kind {
        case .bars:
            if let bars = spec.bars { BarsGraphicView(bars: bars, size: size, palette: palette) }
        case .line:
            if let line = spec.line { LineGraphicView(line: line, palette: palette).frame(height: chartHeight) }
        case .diagram:
            // A schematic's labels need room; it never shrinks below 120 pt.
            if let diagram = spec.diagram { DiagramGraphicView(diagram: diagram, palette: palette).frame(height: max(chartHeight, 120)) }
        case .flow:
            if let flow = spec.flow { FlowGraphicView(flow: flow, size: size, palette: palette, height: chartHeight) }
        case .compare:
            if let compare = spec.compare { CompareGraphicView(compare: compare, size: size, palette: palette) }
        case .timeline:
            if let timeline = spec.timeline { TimelineGraphicView(timeline: timeline, size: size, palette: palette) }
        case .formula:
            if let formula = spec.formula { FormulaGraphicView(formula: formula, size: size, palette: palette) }
        case .proportion:
            if let proportion = spec.proportion {
                ProportionGraphicView(proportion: proportion, size: size, palette: palette, height: chartHeight)
            }
        case .icons:
            if let icons = spec.icons { IconsGraphicView(icons: icons, size: size, palette: palette) }
        }
    }
}

private struct GraphicCollapsedLabel: View {
    let spec: CardGraphicSpec
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = GraphicPalette.palette(for: colorScheme)
        HStack(spacing: 8) {
            Image(systemName: GraphicPalette.symbol(for: spec.kind))
                .foregroundColor(palette.primary)
            Text(spec.title)
                .font(.system(.footnote, design: .rounded).weight(.semibold))
                .foregroundColor(palette.ink)
                .lineLimit(1)
            Spacer(minLength: 4)
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.caption)
                .foregroundColor(palette.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(palette.plate))
        .contentShape(Rectangle())
    }
}

private struct GraphicSheet: View {
    let spec: CardGraphicSpec
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Graphic")
                    .font(.system(.headline, design: .rounded))
                Spacer()
                Button("Done") { dismiss() }
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .accessibilityIdentifier("cardGraphicSheetDone")
            }
            GraphicPlate(spec: spec, size: .regular)
            Spacer(minLength: 0)
        }
        .padding(20)
        .presentationDetents([.medium, .large])
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

    static func palette(for scheme: ColorScheme) -> GraphicPalette {
        scheme == .dark ? dark : light
    }

    static let light = GraphicPalette(
        plate: Econ.tide.opacity(0.07), rim: Econ.tide.opacity(0.14), ink: Econ.ink, secondary: Econ.subtext,
        grid: Econ.subtext.opacity(0.22), primary: Econ.tide, accent: Econ.amber, muted: Econ.subtext.opacity(0.7),
        chip: Econ.tide.opacity(0.12), third: Econ.sky, remainder: Econ.subtext.opacity(0.2))

    static let dark = GraphicPalette(
        plate: Econ.ocean, rim: Econ.tide.opacity(0.45), ink: Econ.white, secondary: Econ.mist.opacity(0.78),
        grid: Econ.mist.opacity(0.16), primary: Econ.sky, accent: Econ.amber, muted: Econ.mist.opacity(0.62),
        chip: Econ.tide.opacity(0.42), third: Econ.amberLight, remainder: Econ.mist.opacity(0.2))

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
        }
    }
}
