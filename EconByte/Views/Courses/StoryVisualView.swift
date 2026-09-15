import SwiftUI

/// The picture on a story beat (1.1.5): one of the lesson drawings, one of the
/// lesson's synthetic charts, a typed graphic (Phase 24, the card-graphics spec
/// drawn on the lesson ground), or a simple data-driven figure — a big stat, a
/// flow of steps, a two-sided comparison, or a decorative symbol. Figures use
/// only words and numbers from the lesson (validated), wrap at accessibility
/// text sizes, and read to VoiceOver as one element. Every picture sits on the
/// same lesson surface tone and corner radius.
struct StoryVisualView: View {
    enum Size {
        /// Above a quick check's question: short, so the answer's feedback fits.
        case compact
        case regular
        /// The lesson's key-concept picture.
        case centerpiece

        var plotHeight: CGFloat {
            switch self {
            case .compact: return 150
            case .regular: return 220
            case .centerpiece: return 270
            }
        }
    }

    let visual: StoryVisual
    let lesson: Lesson
    var size: Size = .regular

    var body: some View {
        switch visual {
        case let .graphic(spec):
            if spec.isRenderable {
                GraphicPlate(spec: spec, host: .lesson, prominent: size == .centerpiece)
            }
        case let .diagram(id):
            DiagramView(id: id, height: size.plotHeight)
                .accessibilityIdentifier("diagram-\(id.rawValue)")
        case let .chart(chartID):
            if let spec = lesson.chart(withID: chartID) {
                ChartBlockView(spec: spec, showsCaption: false, plotHeight: size.plotHeight)
            }
        case let .stat(value, label):
            VStack(spacing: EconSpace.xxs) {
                Text(value)
                    .font(EconType.display)
                    .foregroundColor(EconColor.accentText)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(label)
                    .font(EconType.subheadline)
                    .foregroundColor(EconColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, EconSpace.m)
            .lessonSurface()
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("storyStat")
        case let .flow(steps):
            ViewThatFits(in: .horizontal) {
                HStack(spacing: EconSpace.xxs) { flowSteps(steps, arrow: "arrow.right") }
                VStack(spacing: EconSpace.xxs) { flowSteps(steps, arrow: "arrow.down") }
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(steps.joined(separator: ", then ")))
            .accessibilityIdentifier("storyFlow")
        case let .compare(left, right):
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: EconSpace.s) { compareSide(left); compareSide(right) }
                VStack(spacing: EconSpace.s) { compareSide(left); compareSide(right) }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("storyCompare")
        case let .symbol(name):
            Image(systemName: name)
                .font(.system(.largeTitle))
                .imageScale(.large)
                .foregroundColor(EconColor.accent)
                .frame(width: 96, height: 96)
                .background(EconColor.surfaceRaised)
                .clipShape(Circle())
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func flowSteps(_ steps: [String], arrow: String) -> some View {
        ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
            if index > 0 {
                Image(systemName: arrow)
                    .font(EconType.footnote.weight(.bold))
                    .foregroundColor(EconColor.accent)
            }
            Text(step)
                .font(EconType.subheadlineEmphasis)
                .foregroundColor(EconColor.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, EconSpace.s)
                .padding(.vertical, EconSpace.s)
                .frame(minHeight: EconSize.tapTarget)
                .background(EconColor.surfaceRaised)
                .clipShape(RoundedRectangle(cornerRadius: EconRadius.control, style: .continuous))
        }
    }

    private func compareSide(_ side: StoryCompareSide) -> some View {
        VStack(alignment: .leading, spacing: EconSpace.xxs) {
            Text(side.label)
                .font(EconType.headline)
                .foregroundColor(EconColor.accentText)
                .fixedSize(horizontal: false, vertical: true)
            Text(side.detail)
                .font(EconType.subheadline)
                .foregroundColor(EconColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(EconSpace.s)
        .lessonSurface()
    }
}

extension View {
    /// The ground every lesson picture sits on: the lesson surface tone, the
    /// control radius (the same as a lesson graphic plate).
    func lessonSurface() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .background(EconColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: EconRadius.control, style: .continuous))
    }
}
