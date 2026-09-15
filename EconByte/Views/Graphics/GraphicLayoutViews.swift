import SwiftUI

// MARK: - Flow

struct FlowGraphicView: View {
    let flow: FlowGraphic
    let size: GraphicSize
    let palette: GraphicPalette
    let height: CGFloat

    var body: some View {
        switch flow.layout {
        case .chain:
            if flow.steps.count <= 3 && flow.steps.allSatisfy({ $0.detail == nil }) {
                horizontalChain
            } else {
                verticalChain
            }
        case .cycle:
            FlowCycleView(steps: flow.steps.map(\.title), palette: palette)
                .frame(height: size == .regular ? max(height, 128) : max(height, 104))
        }
    }

    private var horizontalChain: some View {
        HStack(spacing: 4) {
            ForEach(Array(flow.steps.enumerated()), id: \.offset) { index, step in
                Text(step.title)
                    .font(.system(size == .regular ? .caption : .caption2, design: .rounded).weight(.semibold))
                    .foregroundColor(palette.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .minimumScaleFactor(0.85)
                    .padding(.horizontal, 6)
                    .padding(.vertical, size == .regular ? 10 : 6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(index == flow.steps.count - 1 ? palette.accent.opacity(0.22) : palette.chip))
                if index < flow.steps.count - 1 {
                    Image(systemName: "arrow.right")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(palette.primary)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var verticalChain: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(flow.steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle()
                        .fill(index == flow.steps.count - 1 ? palette.accent : palette.primary)
                        .frame(width: 6, height: 6)
                        .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + 3 }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(step.title)
                            .font(.system(size == .regular ? .caption : .caption2, design: .rounded).weight(.semibold))
                            .foregroundColor(palette.ink)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        if let detail = step.detail, size == .regular {
                            Text(detail)
                                .font(.system(.caption2, design: .rounded))
                                .foregroundColor(palette.secondary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, size == .regular ? 5 : 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(palette.chip))
                if index < flow.steps.count - 1 {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(palette.primary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

/// 3–4 steps around an ellipse, clockwise from the top, joined by arcs that
/// stop at each chip's edge.
private struct FlowCycleView: View {
    let steps: [String]
    let palette: GraphicPalette

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let center = CGPoint(x: w / 2, y: h / 2)
            let chip = CGSize(width: min(128, w * 0.38), height: 34)
            let rx = max(10, w / 2 - chip.width / 2 - 2)
            let ry = max(10, h / 2 - chip.height / 2 - 1)
            let angles = steps.indices.map { -CGFloat.pi / 2 + 2 * .pi * CGFloat($0) / CGFloat(steps.count) }
            let position: (CGFloat) -> CGPoint = { a in CGPoint(x: center.x + rx * cos(a), y: center.y + ry * sin(a)) }
            ZStack {
                ForEach(steps.indices, id: \.self) { i in
                    let rects = [i, (i + 1) % steps.count].map { j -> CGRect in
                        let p = position(angles[j])
                        return CGRect(x: p.x - chip.width / 2 - 4, y: p.y - chip.height / 2 - 4,
                                      width: chip.width + 8, height: chip.height + 8)
                    }
                    Self.arc(from: angles[i], to: angles[i] + 2 * .pi / CGFloat(steps.count),
                             position: position, avoiding: rects)
                        .stroke(palette.primary, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                }
                ForEach(steps.indices, id: \.self) { i in
                    Text(steps[i])
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .foregroundColor(palette.ink)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 6)
                        .frame(width: chip.width, height: chip.height)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(palette.chip))
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(palette.plateOpaque))
                        .position(position(angles[i]))
                }
            }
        }
    }

    static func arc(from start: CGFloat, to end: CGFloat, position: (CGFloat) -> CGPoint, avoiding rects: [CGRect]) -> Path {
        let samples = 48
        let points = (0...samples).map { position(start + (end - start) * CGFloat($0) / CGFloat(samples)) }
            .filter { point in !rects.contains { $0.contains(point) } }
        var path = Path()
        guard points.count >= 2, let first = points.first, let last = points.last else { return path }
        path.move(to: first)
        points.dropFirst().forEach { path.addLine(to: $0) }
        let previous = points[points.count - 2]
        let angle = atan2(last.y - previous.y, last.x - previous.x)
        for delta in [CGFloat.pi * 0.8, -CGFloat.pi * 0.8] {
            path.move(to: last)
            path.addLine(to: CGPoint(x: last.x + 6 * cos(angle + delta), y: last.y + 6 * sin(angle + delta)))
        }
        return path
    }
}

// MARK: - Compare

struct CompareGraphicView: View {
    let compare: CompareGraphic
    let size: GraphicSize
    let palette: GraphicPalette

    private var hasLabels: Bool { compare.rows.contains { !$0.label.isEmpty } }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: size == .regular ? 5 : 3) {
            GridRow {
                if hasLabels { Color.clear.gridCellUnsizedAxes([.horizontal, .vertical]) }
                ForEach(Array(compare.columns.enumerated()), id: \.offset) { index, column in
                    Text(column)
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundColor(palette.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Rectangle()
                .fill(palette.grid)
                .frame(height: 1)
                .gridCellColumns(compare.columns.count + (hasLabels ? 1 : 0))
            ForEach(Array(compare.rows.enumerated()), id: \.offset) { _, row in
                GridRow(alignment: .firstTextBaseline) {
                    if hasLabels {
                        Text(row.label)
                            .font(.system(.caption2, design: .rounded).weight(.semibold))
                            .foregroundColor(palette.secondary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(Array(row.values.enumerated()), id: \.offset) { _, value in
                        Text(value)
                            .font(.system(.caption2, design: .rounded))
                            .foregroundColor(palette.ink)
                            .lineLimit(size == .regular ? 3 : 2)
                            .minimumScaleFactor(0.9)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
}

// MARK: - Timeline

struct TimelineGraphicView: View {
    let timeline: TimelineGraphic
    let size: GraphicSize
    let palette: GraphicPalette
    private let whenWidth: CGFloat = 88

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(timeline.events.enumerated()), id: \.offset) { index, event in
                HStack(alignment: .center, spacing: 8) {
                    Text(event.when)
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .foregroundColor(palette.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(width: whenWidth, alignment: .trailing)
                    VStack(spacing: 0) {
                        Rectangle().fill(index == 0 ? Color.clear : palette.grid).frame(width: 1.5)
                        Circle()
                            .fill(index == timeline.events.count - 1 ? palette.accent : palette.primary)
                            .frame(width: 8, height: 8)
                        Rectangle().fill(index == timeline.events.count - 1 ? Color.clear : palette.grid).frame(width: 1.5)
                    }
                    .frame(width: 8)
                    Text(event.label)
                        .font(.system(size == .regular ? .caption : .caption2, design: .rounded))
                        .foregroundColor(palette.ink)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, size == .regular ? 3 : 1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Formula

struct FormulaGraphicView: View {
    let formula: FormulaGraphic
    let size: GraphicSize
    let palette: GraphicPalette

    var body: some View {
        VStack(alignment: .leading, spacing: size == .regular ? 6 : 4) {
            Text(formula.expression)
                .font(.system(size == .regular ? .body : .subheadline, design: .rounded).weight(.semibold))
                .foregroundColor(palette.ink)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .padding(.vertical, size == .regular ? 7 : 4)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(palette.chip))
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(formula.terms.enumerated()), id: \.offset) { _, term in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(term.symbol)
                            .font(.system(.caption, design: .rounded).weight(.bold))
                            .foregroundColor(palette.primary)
                            .lineLimit(1)
                            .fixedSize()
                            .frame(minWidth: 34, alignment: .leading)
                        Text(term.meaning)
                            .font(.system(.caption2, design: .rounded))
                            .foregroundColor(palette.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                }
            }
            if let example = formula.example, size == .regular {
                Text(example)
                    .font(.system(.caption2, design: .rounded).weight(.medium))
                    .italic()
                    .foregroundColor(palette.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Icons

struct IconsGraphicView: View {
    let icons: IconsGraphic
    let size: GraphicSize
    let palette: GraphicPalette
    @ScaledMetric(relativeTo: .caption) private var chipSize: CGFloat = 44

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            ForEach(Array(icons.items.enumerated()), id: \.offset) { index, item in
                VStack(spacing: 5) {
                    Image(systemName: item.symbol)
                        .font(.system(size == .regular ? .title3 : .body))
                        .foregroundColor(palette.primary)
                        .frame(width: size == .regular ? chipSize : chipSize * 0.75,
                               height: size == .regular ? chipSize : chipSize * 0.75)
                        .background(Circle().fill(palette.chip))
                    Text(item.label)
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .foregroundColor(palette.ink)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                if index < icons.items.count - 1 {
                    connector
                        .frame(height: size == .regular ? chipSize : chipSize * 0.75)
                }
            }
        }
    }

    @ViewBuilder
    private var connector: some View {
        switch icons.connector {
        case .plus:   Image(systemName: "plus").font(.caption.weight(.bold)).foregroundColor(palette.secondary)
        case .arrow:  Image(systemName: "arrow.right").font(.caption.weight(.bold)).foregroundColor(palette.secondary)
        case .equals: Image(systemName: "equal").font(.caption.weight(.bold)).foregroundColor(palette.secondary)
        case .versus:
            Text("vs")
                .font(.system(.caption2, design: .rounded).weight(.bold))
                .foregroundColor(palette.secondary)
        case .none:   EmptyView()
        }
    }
}
