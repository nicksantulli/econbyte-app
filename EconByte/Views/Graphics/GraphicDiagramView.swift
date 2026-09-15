import SwiftUI

/// A schematic plot in unit space: curves, dots, guides and arrows over two
/// labelled axes with no numbers. Always conceptual or illustrative.
///
/// Labels are placed by `DiagramLabelLayout`: each label tries a short list of
/// candidate spots in order and takes the first that stays inside the plot and
/// clear of the labels and dots already placed, so no two labels overlap.
struct DiagramGraphicView: View {
    let diagram: DiagramGraphic
    let palette: GraphicPalette
    @ScaledMetric(relativeTo: .caption2) private var labelScale: CGFloat = 1

    var body: some View {
        GeometryReader { geo in
            let plot = DiagramLabelLayout.plotRect(in: geo.size)
            let map: ([Double]) -> CGPoint = { DiagramLabelLayout.point($0, in: plot) }
            let placed = DiagramLabelLayout.place(diagram, in: geo.size, scale: labelScale)
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
                            path.move(to: CGPoint(x: plot.minX, y: y))
                            path.addLine(to: CGPoint(x: plot.maxX, y: y))
                        } else {
                            let x = plot.minX + CGFloat(guide.at) * plot.width
                            path.move(to: CGPoint(x: x, y: plot.minY))
                            path.addLine(to: CGPoint(x: x, y: plot.maxY))
                        }
                    }
                    .stroke(palette.muted, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }

                // Curves.
                ForEach(Array(diagram.curves.enumerated()), id: \.offset) { _, curve in
                    Self.smooth(curve.points.filter { $0.count == 2 }.map(map))
                        .stroke(color(for: curve.tone), style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round,
                                                                            dash: curve.style == .dashed ? [6, 4] : []))
                }

                // Arrows.
                ForEach(Array((diagram.arrows ?? []).enumerated()), id: \.offset) { _, arrow in
                    if arrow.from.count == 2, arrow.to.count == 2 {
                        Self.arrowPath(from: map(arrow.from), to: map(arrow.to))
                            .stroke(palette.accent, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                    }
                }

                // Dots.
                ForEach(Array((diagram.dots ?? []).enumerated()), id: \.offset) { _, dot in
                    Circle()
                        .fill(palette.ink)
                        .frame(width: 7, height: 7)
                        .overlay(Circle().stroke(palette.plateOpaque, lineWidth: 1.5))
                        .position(map([dot.x, dot.y]))
                }

                // Labels, placed without overlap.
                ForEach(placed) { label in
                    GraphicTag(text: label.text, palette: palette, color: textColor(for: label.role))
                        .position(label.center)
                }
            }
        }
    }

    private func color(for tone: DiagramGraphic.Tone?) -> Color {
        switch tone ?? .primary {
        case .primary: return palette.primary
        case .accent:  return palette.accent
        case .muted:   return palette.muted
        }
    }

    private func textColor(for role: DiagramLabelLayout.Role) -> Color {
        switch role {
        case .curve(let tone):
            switch tone ?? .primary {
            case .primary: return palette.primary
            case .accent:  return palette.ink
            case .muted:   return palette.secondary
            }
        case .dot, .arrow: return palette.ink
        case .guide:       return palette.secondary
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

// MARK: - Label placement

/// Deterministic, collision-free placement of a diagram's labels. Pure, so the
/// test suite can prove that no two labels in any catalog diagram overlap.
enum DiagramLabelLayout {

    enum Role: Hashable {
        case curve(DiagramGraphic.Tone?)
        case dot
        case arrow
        case guide
    }

    struct Placed: Identifiable {
        let id: Int
        let text: String
        let role: Role
        let center: CGPoint
        let size: CGSize
        /// False when no candidate was free and the least-overlapping one was used.
        let isClear: Bool
        var rect: CGRect {
            CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
        }
    }

    enum Spot { case above, below, left, right, upLeft, upRight, downLeft, downRight }

    static func plotRect(in size: CGSize) -> CGRect {
        CGRect(x: 18, y: 12, width: max(10, size.width - 24), height: max(10, size.height - 30))
    }

    static func point(_ p: [Double], in plot: CGRect) -> CGPoint {
        CGPoint(x: plot.minX + CGFloat(p[0]) * plot.width, y: plot.maxY - CGFloat(p[1]) * plot.height)
    }

    /// Estimated tag size for caption2 semibold with 4 pt side padding.
    static func tagSize(_ text: String, scale: CGFloat) -> CGSize {
        CGSize(width: CGFloat(text.count) * 6.3 * scale + 10, height: 16 * scale)
    }

    /// Centers for a label of size `s` next to anchor `p`, in the given order.
    static func candidates(_ p: CGPoint, _ s: CGSize, _ order: [Spot]) -> [CGPoint] {
        let gap: CGFloat = 5
        return order.map { spot in
            switch spot {
            case .above:     return CGPoint(x: p.x, y: p.y - gap - s.height / 2)
            case .below:     return CGPoint(x: p.x, y: p.y + gap + s.height / 2)
            case .left:      return CGPoint(x: p.x - gap - s.width / 2, y: p.y)
            case .right:     return CGPoint(x: p.x + gap + s.width / 2, y: p.y)
            case .upLeft:    return CGPoint(x: p.x - s.width / 2, y: p.y - gap - s.height / 2)
            case .upRight:   return CGPoint(x: p.x + s.width / 2, y: p.y - gap - s.height / 2)
            case .downLeft:  return CGPoint(x: p.x - s.width / 2, y: p.y + gap + s.height / 2)
            case .downRight: return CGPoint(x: p.x + s.width / 2, y: p.y + gap + s.height / 2)
            }
        }
    }

    private struct Request {
        let text: String
        let role: Role
        let spots: (CGSize) -> [CGPoint]
    }

    static func place(_ diagram: DiagramGraphic, in size: CGSize, scale: CGFloat = 1) -> [Placed] {
        let plot = plotRect(in: size)
        // Labels may use the space above the plot, but not the axis-label margins.
        let bounds = CGRect(x: plot.minX + 1, y: 0, width: size.width - plot.minX - 1, height: plot.maxY - 1)

        var curves: [Request] = []
        for curve in diagram.curves {
            guard let label = curve.label, let last = curve.points.last(where: { $0.count == 2 }) else { continue }
            let p = point(last, in: plot)
            let order: [Spot] = last[0] > 0.6
                ? [.upLeft, .downLeft, .left, .above, .below, .upRight, .downRight]
                : [.upRight, .downRight, .right, .above, .below, .upLeft, .downLeft]
            curves.append(Request(text: label, role: .curve(curve.tone)) { candidates(p, $0, order) })
        }
        var dots: [Request] = []
        for dot in diagram.dots ?? [] {
            guard let label = dot.label else { continue }
            let p = point([dot.x, dot.y], in: plot)
            let order: [Spot] = [.above, .below, .upRight, .upLeft, .downRight, .downLeft, .right, .left]
            dots.append(Request(text: label, role: .dot) { candidates(p, $0, order) })
        }
        var guides: [Request] = []
        for guide in diagram.guides ?? [] {
            guard let label = guide.label else { continue }
            if guide.axis == .y {
                let y = plot.maxY - CGFloat(guide.at) * plot.height
                let right = CGPoint(x: plot.maxX - 2, y: y)
                let left = CGPoint(x: plot.minX + 2, y: y)
                guides.append(Request(text: label, role: .guide) { s in
                    candidates(right, s, [.upLeft, .downLeft]) + candidates(left, s, [.upRight, .downRight])
                        + candidates(CGPoint(x: plot.midX, y: y), s, [.above, .below])
                        + candidates(CGPoint(x: plot.minX + plot.width * 0.25, y: y), s, [.above, .below])
                        + candidates(CGPoint(x: plot.minX + plot.width * 0.75, y: y), s, [.above, .below])
                })
            } else {
                let x = plot.minX + CGFloat(guide.at) * plot.width
                let top = CGPoint(x: x, y: plot.minY)
                let bottom = CGPoint(x: x, y: plot.maxY - 2)
                guides.append(Request(text: label, role: .guide) { s in
                    candidates(top, s, [.downRight, .downLeft]) + candidates(bottom, s, [.upRight, .upLeft])
                        + candidates(CGPoint(x: x, y: plot.midY), s, [.right, .left])
                })
            }
        }
        var arrows: [Request] = []
        for arrow in diagram.arrows ?? [] {
            guard let label = arrow.label, arrow.from.count == 2, arrow.to.count == 2 else { continue }
            let from = point(arrow.from, in: plot)
            let to = point(arrow.to, in: plot)
            let mid = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
            let order: [Spot]
            if abs(to.x - from.x) >= abs(to.y - from.y) {
                order = [.above, .below, .upRight, .downRight, .upLeft, .downLeft]
            } else if arrow.from[0] > 0.5 {
                order = [.left, .right, .upLeft, .downLeft]
            } else {
                order = [.right, .left, .upRight, .downRight]
            }
            // Then beside either end, so a crowded middle still has somewhere to go.
            let ends: [Spot] = [.above, .below, .left, .right, .upLeft, .upRight, .downLeft, .downRight]
            arrows.append(Request(text: label, role: .arrow) {
                candidates(mid, $0, order) + candidates(from, $0, ends) + candidates(to, $0, ends)
            })
        }

        // Dots are obstacles for every label.
        let dotRects: [CGRect] = (diagram.dots ?? []).map {
            let p = point([$0.x, $0.y], in: plot)
            return CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)
        }

        func run(_ requests: [Request]) -> [Placed] {
            var taken = dotRects
            var placed: [Placed] = []
            for request in requests {
                let size = tagSize(request.text, scale: scale)
                let spots = request.spots(size)
                let rect = { (c: CGPoint) -> CGRect in
                    CGRect(x: c.x - size.width / 2, y: c.y - size.height / 2, width: size.width, height: size.height)
                }
                let free = spots.first { c in
                    bounds.contains(rect(c)) && !taken.contains { $0.insetBy(dx: -1, dy: -1).intersects(rect(c)) }
                }
                let chosen: CGPoint
                if let free {
                    chosen = free
                } else {
                    // Least overlap, then clamped into bounds.
                    let best = spots.min { overlap(rect($0), taken) < overlap(rect($1), taken) } ?? spots[0]
                    chosen = CGPoint(x: min(max(best.x, bounds.minX + size.width / 2), bounds.maxX - size.width / 2),
                                     y: min(max(best.y, bounds.minY + size.height / 2), bounds.maxY - size.height / 2))
                }
                taken.append(rect(chosen))
                placed.append(Placed(id: placed.count, text: request.text, role: request.role, center: chosen,
                                     size: size, isClear: free != nil))
            }
            return placed
        }

        // Try every order of the four groups; keep the fewest label collisions,
        // then the fewest fallbacks. The first order wins ties, so it is stable.
        let groups = [curves, guides, arrows, dots]
        var best: [Placed] = []
        var bestScore = (Int.max, Int.max)
        for order in permutations([0, 1, 2, 3]) {
            let result = run(order.flatMap { groups[$0] })
            var collisions = 0
            for (i, a) in result.enumerated() {
                for b in result[(i + 1)...] where a.rect.intersects(b.rect) { collisions += 1 }
            }
            let score = (collisions, result.filter { !$0.isClear }.count)
            if score < bestScore {
                bestScore = score
                best = result
                if score == (0, 0) { break }
            }
        }
        return best
    }

    private static func permutations(_ items: [Int]) -> [[Int]] {
        guard items.count > 1 else { return [items] }
        return items.indices.flatMap { i -> [[Int]] in
            var rest = items
            let head = rest.remove(at: i)
            return permutations(rest).map { [head] + $0 }
        }
    }

    private static func overlap(_ r: CGRect, _ others: [CGRect]) -> CGFloat {
        others.reduce(0) { total, o in
            let i = r.intersection(o)
            return total + (i.isNull ? 0 : i.width * i.height)
        }
    }
}
