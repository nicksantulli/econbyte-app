import SwiftUI

/// A schematic plot in unit space: curves, dots, guides and arrows over two
/// labelled axes with no numbers. Always conceptual or illustrative.
struct DiagramGraphicView: View {
    let diagram: DiagramGraphic
    let palette: GraphicPalette

    var body: some View {
        GeometryReader { geo in
            let plot = CGRect(x: 18, y: 12, width: max(10, geo.size.width - 24), height: max(10, geo.size.height - 30))
            let map: ([Double]) -> CGPoint = { p in
                CGPoint(x: plot.minX + CGFloat(p[0]) * plot.width, y: plot.maxY - CGFloat(p[1]) * plot.height)
            }
            ZStack(alignment: .topLeading) {
                // Axes.
                Path { path in
                    path.move(to: CGPoint(x: plot.minX, y: plot.minY - 4))
                    path.addLine(to: CGPoint(x: plot.minX, y: plot.maxY))
                    path.addLine(to: CGPoint(x: plot.maxX + 2, y: plot.maxY))
                }
                .stroke(palette.secondary.opacity(0.7), lineWidth: 1)
                Text(diagram.yLabel)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundColor(palette.secondary)
                    .lineLimit(1)
                    .fixedSize()
                    .rotationEffect(.degrees(-90))
                    .position(x: 7, y: plot.midY)
                Text(diagram.xLabel)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundColor(palette.secondary)
                    .lineLimit(1)
                    .fixedSize()
                    .position(x: plot.midX, y: plot.maxY + 11)

                // Guides.
                ForEach(Array((diagram.guides ?? []).enumerated()), id: \.offset) { _, guide in
                    Path { path in
                        if guide.axis == .y {
                            let y = plot.maxY - CGFloat(guide.at) * plot.height
                            path.move(to: CGPoint(x: plot.minX, y: y)); path.addLine(to: CGPoint(x: plot.maxX, y: y))
                        } else {
                            let x = plot.minX + CGFloat(guide.at) * plot.width
                            path.move(to: CGPoint(x: x, y: plot.minY)); path.addLine(to: CGPoint(x: x, y: plot.maxY))
                        }
                    }
                    .stroke(palette.muted, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    if let label = guide.label {
                        if guide.axis == .y {
                            anchored(GraphicTag(text: label, palette: palette, color: palette.secondary), alignment: .bottomLeading)
                                .position(x: plot.minX + 4, y: plot.maxY - CGFloat(guide.at) * plot.height - 2)
                        } else {
                            anchored(GraphicTag(text: label, palette: palette, color: palette.secondary), alignment: .topLeading)
                                .position(x: plot.minX + CGFloat(guide.at) * plot.width + 3, y: plot.minY)
                        }
                    }
                }

                // Curves.
                ForEach(Array(diagram.curves.enumerated()), id: \.offset) { _, curve in
                    let points = curve.points.filter { $0.count == 2 }.map(map)
                    Self.smooth(points)
                        .stroke(color(for: curve.tone), style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round,
                                                                            dash: curve.style == .dashed ? [6, 4] : []))
                }

                // Arrows.
                ForEach(Array((diagram.arrows ?? []).enumerated()), id: \.offset) { _, arrow in
                    if arrow.from.count == 2, arrow.to.count == 2 {
                        let from = map(arrow.from), to = map(arrow.to)
                        Self.arrowPath(from: from, to: to)
                            .stroke(palette.accent, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                        if let label = arrow.label {
                            GraphicTag(text: label, palette: palette, color: palette.ink)
                                .position(x: (from.x + to.x) / 2, y: min(from.y, to.y) - 10)
                        }
                    }
                }

                // Curve labels at their last point.
                ForEach(Array(diagram.curves.enumerated()), id: \.offset) { _, curve in
                    if let label = curve.label, let last = curve.points.last(where: { $0.count == 2 }) {
                        let point = map(last)
                        let alignment: Alignment = last[0] > 0.6
                            ? (last[1] > 0.8 ? .topTrailing : .bottomTrailing)
                            : (last[1] > 0.8 ? .topLeading : .bottomLeading)
                        anchored(GraphicTag(text: label, palette: palette, color: color(for: curve.tone, text: true)),
                                 alignment: alignment)
                            .position(x: point.x + (last[0] > 0.6 ? -2 : 4), y: point.y + (last[1] > 0.8 ? 4 : -4))
                    }
                }

                // Dots.
                ForEach(Array((diagram.dots ?? []).enumerated()), id: \.offset) { _, dot in
                    let point = map([dot.x, dot.y])
                    Circle()
                        .fill(palette.ink)
                        .frame(width: 7, height: 7)
                        .overlay(Circle().stroke(palette.plateOpaque, lineWidth: 1.5))
                        .position(point)
                    if let label = dot.label {
                        let alignment: Alignment = dot.x > 0.75 ? .bottomTrailing : (dot.x < 0.25 ? .bottomLeading : .bottom)
                        anchored(GraphicTag(text: label, palette: palette), alignment: alignment)
                            .position(x: point.x, y: point.y - 6)
                    }
                }
            }
        }
    }

    /// Places `content` so that its `alignment` point sits on the position.
    private func anchored<Content: View>(_ content: Content, alignment: Alignment) -> some View {
        Color.clear
            .frame(width: 1, height: 1)
            .overlay(content.fixedSize(), alignment: alignment.opposite)
    }

    private func color(for tone: DiagramGraphic.Tone?, text: Bool = false) -> Color {
        switch tone ?? .primary {
        case .primary: return palette.primary
        case .accent:  return text ? palette.ink : palette.accent
        case .muted:   return text ? palette.secondary : palette.muted
        }
    }

    /// Catmull-Rom through the points (straight for two).
    static func smooth(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 2 else {
            points.dropFirst().forEach { path.addLine(to: $0) }
            return path
        }
        for i in 0..<(points.count - 1) {
            let p0 = points[max(0, i - 1)], p1 = points[i], p2 = points[i + 1], p3 = points[min(points.count - 1, i + 2)]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        return path
    }

    static func arrowPath(from: CGPoint, to: CGPoint) -> Path {
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        let angle = atan2(to.y - from.y, to.x - from.x)
        let head: CGFloat = 7
        for delta in [CGFloat.pi * 0.82, -CGFloat.pi * 0.82] {
            path.move(to: to)
            path.addLine(to: CGPoint(x: to.x + head * cos(angle + delta), y: to.y + head * sin(angle + delta)))
        }
        return path
    }
}

private extension Alignment {
    /// The alignment on the far side, so an overlay grows away from the anchor.
    var opposite: Alignment {
        switch self {
        case .topLeading:     return .bottomTrailing
        case .top:            return .bottom
        case .topTrailing:    return .bottomLeading
        case .leading:        return .trailing
        case .trailing:       return .leading
        case .bottomLeading:  return .topTrailing
        case .bottom:         return .top
        case .bottomTrailing: return .topLeading
        default:              return .center
        }
    }
}
