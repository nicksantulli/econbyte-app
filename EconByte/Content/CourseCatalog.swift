import Foundation

// MARK: - Courses (1.1.4, EconByte Pro)
//
// `Resources/courses-v1.json` carries the subscription's course library: three
// courses of ordered lessons, each lesson an ordered list of BLOCKS (paragraph,
// callout, key terms, diagram, chart, quiz, takeaways). The first lesson of every
// course is a free preview; the rest are readable only while EconByte Pro is
// active (`PurchaseManager.isProActive`).
//
// Same contract as the card catalogs: decoding and validation fail closed, and
// the structural validator here is the runtime backstop for the editorial checks
// in `EconByteTests` (approved hosts, advice framing, stale wording) and the Node
// mirror in `scripts/validate_content.mjs`. Charts render ONLY from the synthetic
// series bundled in the block — the app has no market-data dependency and every
// chart's `dataNote` says so.

public enum CourseLevel: String, Codable, Hashable {
    case intro
    case intermediate
}

public enum CalloutStyle: String, Codable, Hashable {
    case note
    case caution
    case example
}

public enum ChartKind: String, Codable, Hashable {
    case candlestick
    case line
    case bar
}

/// The diagrams the app can draw (`DiagramView`). A lesson may only reference
/// one of these; an unknown id fails validation rather than rendering blank.
public enum DiagramID: String, Codable, Hashable, CaseIterable {
    case candleAnatomy = "candle-anatomy"
    case riskReturnLadder = "risk-return-ladder"
    case diversificationBasket = "diversification-basket"
    case priceYieldSeesaw = "price-yield-seesaw"
    case yieldCurveShapes = "yield-curve-shapes"
    case allocationPie = "allocation-pie"
    case supportResistance = "support-resistance"
    case feeDrag = "fee-drag"
    case trendChannel = "trend-channel"
}

public struct KeyTerm: Codable, Hashable {
    public let term: String
    public let definition: String
}

public struct ChartPoint: Codable, Hashable {
    public let x: Double
    public let y: Double
}

public struct ChartSeries: Codable, Hashable {
    public let name: String
    public let points: [ChartPoint]
}

public struct Candle: Codable, Hashable {
    public let x: Double
    public let open: Double
    public let high: Double
    public let low: Double
    public let close: Double
    public var isUp: Bool { close >= open }
}

public struct ChartMarker: Codable, Hashable {
    public let x: Double
    public let label: String
}

public struct ChartSpec: Codable, Hashable {
    public let chartID: String
    public let kind: ChartKind
    public let title: String
    public let caption: String
    /// Must begin with "Synthetic": no real market data is ever plotted.
    public let dataNote: String
    public let xLabel: String
    public let yLabel: String
    public let series: [ChartSeries]?
    public let candles: [Candle]?
    public let markers: [ChartMarker]?
}

public struct Quiz: Codable, Hashable {
    public let question: String
    public let choices: [String]
    public let answerIndex: Int
    public let explanation: String
}

/// One block of a lesson. Decoded from `{"type": …, …}`; an unknown type fails
/// decoding, which fails the catalog closed.
public enum LessonBlock: Hashable {
    case paragraph(text: String)
    case callout(style: CalloutStyle, title: String, text: String)
    case keyTerms([KeyTerm])
    case diagram(id: DiagramID, caption: String)
    case chart(ChartSpec)
    case quiz(Quiz)
    case takeaways([String])

    public var typeName: String {
        switch self {
        case .paragraph: return "paragraph"
        case .callout:   return "callout"
        case .keyTerms:  return "keyTerms"
        case .diagram:   return "diagram"
        case .chart:     return "chart"
        case .quiz:      return "quiz"
        case .takeaways: return "takeaways"
        }
    }

    /// Every piece of reader-facing text in the block, for the editorial tests.
    public var allText: [String] {
        switch self {
        case let .paragraph(text): return [text]
        case let .callout(_, title, text): return [title, text]
        case let .keyTerms(terms): return terms.flatMap { [$0.term, $0.definition] }
        case let .diagram(_, caption): return [caption]
        case let .chart(spec): return [spec.title, spec.caption, spec.dataNote, spec.xLabel, spec.yLabel]
                + (spec.series?.map(\.name) ?? []) + (spec.markers?.map(\.label) ?? [])
        case let .quiz(quiz): return [quiz.question, quiz.explanation] + quiz.choices
        case let .takeaways(items): return items
        }
    }
}

extension LessonBlock: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, text, style, title, terms, diagramID, caption, items
        case chartID, kind, dataNote, xLabel, yLabel, series, candles, markers
        case question, choices, answerIndex, explanation
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "paragraph":
            self = .paragraph(text: try c.decode(String.self, forKey: .text))
        case "callout":
            self = .callout(style: try c.decode(CalloutStyle.self, forKey: .style),
                            title: try c.decode(String.self, forKey: .title),
                            text: try c.decode(String.self, forKey: .text))
        case "keyTerms":
            self = .keyTerms(try c.decode([KeyTerm].self, forKey: .terms))
        case "diagram":
            self = .diagram(id: try c.decode(DiagramID.self, forKey: .diagramID),
                            caption: try c.decode(String.self, forKey: .caption))
        case "chart":
            self = .chart(try ChartSpec(from: decoder))
        case "quiz":
            self = .quiz(try Quiz(from: decoder))
        case "takeaways":
            self = .takeaways(try c.decode([String].self, forKey: .items))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c,
                                                   debugDescription: "unknown lesson block type \(type)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(typeName, forKey: .type)
        switch self {
        case let .paragraph(text):
            try c.encode(text, forKey: .text)
        case let .callout(style, title, text):
            try c.encode(style, forKey: .style); try c.encode(title, forKey: .title); try c.encode(text, forKey: .text)
        case let .keyTerms(terms):
            try c.encode(terms, forKey: .terms)
        case let .diagram(id, caption):
            try c.encode(id, forKey: .diagramID); try c.encode(caption, forKey: .caption)
        case let .chart(spec):
            try spec.encode(to: encoder)
        case let .quiz(quiz):
            try quiz.encode(to: encoder)
        case let .takeaways(items):
            try c.encode(items, forKey: .items)
        }
    }
}

public struct Lesson: Codable, Hashable, Identifiable {
    public let lessonID: String
    public let title: String
    public let summary: String
    public let estimatedMinutes: Int
    /// Exactly the first lesson of each course; readable without Pro.
    public let isPreview: Bool
    public let blocks: [LessonBlock]
    public let sources: [CurriculumSource]

    public var id: String { lessonID }
    public var quiz: Quiz? {
        for block in blocks { if case let .quiz(quiz) = block { return quiz } }
        return nil
    }
    public var hasVisual: Bool {
        blocks.contains { block in
            switch block { case .chart, .diagram: return true; default: return false }
        }
    }
}

public struct Course: Codable, Hashable, Identifiable {
    public let courseID: String
    public let title: String
    /// SF Symbol name.
    public let icon: String
    public let summary: String
    public let level: CourseLevel
    public let estimatedMinutes: Int
    public let lessons: [Lesson]

    public var id: String { courseID }
    public var previewLesson: Lesson? { lessons.first { $0.isPreview } }
}

public struct CourseCurriculum: Codable, Hashable {
    public let schemaVersion: Int
    public let catalogVersion: String
    public let verifiedOn: String
    public let disclaimer: String
    /// The "educational, not advice" line shown on every lesson.
    public let educationalNotice: String
    public let editorialPolicy: String
    public let courses: [Course]

    public var allLessons: [Lesson] { courses.flatMap(\.lessons) }

    public func course(withID id: String) -> Course? { courses.first { $0.courseID == id } }
    public func lesson(withID id: String) -> Lesson? { allLessons.first { $0.lessonID == id } }
    public func course(containingLesson lessonID: String) -> Course? {
        courses.first { $0.lessons.contains { $0.lessonID == lessonID } }
    }
}

public enum CourseCatalog {

    public static let resourceName = "courses-v1"
    public static let expectedCourseCount = 3
    public static let minimumLessonsPerCourse = 5
    public static let minimumBlocksPerLesson = 5

    /// Ordered course contract: content id → lesson-id prefix.
    public static let expectedCourses: [(courseID: String, lessonPrefix: String)] = [
        ("investing-approaches", "ia"),
        ("reading-price-charts", "rpc"),
        ("bonds-rates-yield-curve", "bry"),
    ]

    /// Loads the bundled course library and fails closed on any structural
    /// defect. Editorial validation lives in `EconByteTests` (and the Node
    /// mirror) exactly as it does for the card catalogs.
    public static func loadValidated(in bundle: Bundle = .curriculumBundle,
                                     core: Curriculum) throws -> CourseCurriculum {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json") else {
            throw CurriculumError.resourceMissing("\(resourceName).json")
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw CurriculumError.resourceMissing("\(resourceName).json (\(error))")
        }
        let catalog: CourseCurriculum
        do {
            catalog = try JSONDecoder().decode(CourseCurriculum.self, from: data)
        } catch {
            throw CurriculumError.decodingFailed(String(describing: error))
        }
        try validate(catalog, core: core)
        return catalog
    }

    static func validate(_ catalog: CourseCurriculum, core: Curriculum) throws {
        func fail(_ reason: String) throws -> Never {
            throw CurriculumError.validationFailed(reason)
        }

        guard catalog.schemaVersion == 1 else {
            try fail("unsupported courses schemaVersion \(catalog.schemaVersion)")
        }
        guard catalog.disclaimer == core.disclaimer else {
            try fail("courses disclaimer differs from the core catalog")
        }
        guard catalog.educationalNotice.localizedCaseInsensitiveContains("not investment advice")
                || catalog.educationalNotice.localizedCaseInsensitiveContains("not financial advice") else {
            try fail("courses educationalNotice must say the content is not investment advice")
        }
        guard !catalog.editorialPolicy.isEmpty, !catalog.verifiedOn.isEmpty else {
            try fail("courses catalog is missing its editorial policy or verification date")
        }
        guard catalog.courses.count == expectedCourseCount else {
            try fail("expected \(expectedCourseCount) courses, found \(catalog.courses.count)")
        }

        var seenLessonIDs = Set<String>()
        var seenChartIDs = Set<String>()

        for (course, expected) in zip(catalog.courses, expectedCourses) {
            guard course.courseID == expected.courseID else {
                try fail("unexpected course \(course.courseID), expected \(expected.courseID)")
            }
            guard !course.title.isEmpty, !course.icon.isEmpty, !course.summary.isEmpty else {
                try fail("course \(course.courseID) is missing a title, icon, or summary")
            }
            guard course.estimatedMinutes > 0 else {
                try fail("course \(course.courseID) declares no duration")
            }
            guard course.lessons.count >= minimumLessonsPerCourse else {
                try fail("course \(course.courseID) has \(course.lessons.count) lessons, needs \(minimumLessonsPerCourse)")
            }
            for (index, lesson) in course.lessons.enumerated() {
                let expectedID = String(format: "%@-%02d", expected.lessonPrefix, index + 1)
                guard lesson.lessonID == expectedID else {
                    try fail("lesson \(lesson.lessonID) at position \(index + 1) of \(course.courseID) should be \(expectedID)")
                }
                guard seenLessonIDs.insert(lesson.lessonID).inserted else {
                    try fail("duplicate lesson identifier \(lesson.lessonID)")
                }
                guard !lesson.title.isEmpty, !lesson.summary.isEmpty, lesson.estimatedMinutes > 0 else {
                    try fail("lesson \(lesson.lessonID) is missing a title, summary, or duration")
                }
                guard lesson.isPreview == (index == 0) else {
                    try fail("lesson \(lesson.lessonID): exactly the first lesson of a course is the free preview")
                }
                guard lesson.blocks.count >= minimumBlocksPerLesson else {
                    try fail("lesson \(lesson.lessonID) has \(lesson.blocks.count) blocks, needs \(minimumBlocksPerLesson)")
                }
                guard !lesson.sources.isEmpty else {
                    try fail("lesson \(lesson.lessonID) cites no primary source")
                }
                for source in lesson.sources {
                    guard !source.url.isEmpty, !source.organization.isEmpty, !source.documentTitle.isEmpty else {
                        try fail("lesson \(lesson.lessonID) has an incomplete source")
                    }
                }

                var quizzes = 0, visuals = 0, paragraphs = 0, takeaways = 0
                for block in lesson.blocks {
                    switch block {
                    case let .paragraph(text):
                        paragraphs += 1
                        guard !text.isEmpty else { try fail("lesson \(lesson.lessonID) has an empty paragraph") }
                    case let .callout(_, title, text):
                        guard !title.isEmpty, !text.isEmpty else { try fail("lesson \(lesson.lessonID) has an empty callout") }
                    case let .keyTerms(terms):
                        guard (2...6).contains(terms.count) else {
                            try fail("lesson \(lesson.lessonID) key terms must number 2–6")
                        }
                    case let .diagram(_, caption):
                        visuals += 1
                        guard !caption.isEmpty else { try fail("lesson \(lesson.lessonID) diagram has no caption") }
                    case let .chart(spec):
                        visuals += 1
                        guard seenChartIDs.insert(spec.chartID).inserted else {
                            try fail("duplicate chart identifier \(spec.chartID)")
                        }
                        guard spec.dataNote.lowercased().hasPrefix("synthetic") else {
                            try fail("chart \(spec.chartID) must declare synthetic data")
                        }
                        guard !spec.title.isEmpty, !spec.caption.isEmpty, !spec.xLabel.isEmpty, !spec.yLabel.isEmpty else {
                            try fail("chart \(spec.chartID) is missing a title, caption, or axis label")
                        }
                        switch spec.kind {
                        case .candlestick:
                            guard let candles = spec.candles, (8...60).contains(candles.count) else {
                                try fail("chart \(spec.chartID) needs 8–60 candles")
                            }
                            var lastX = -Double.infinity
                            for candle in candles {
                                guard candle.high >= max(candle.open, candle.close),
                                      candle.low <= min(candle.open, candle.close) else {
                                    try fail("chart \(spec.chartID) has an inconsistent candle at x=\(candle.x)")
                                }
                                guard candle.x > lastX else { try fail("chart \(spec.chartID) candles must have increasing x") }
                                lastX = candle.x
                            }
                        case .line, .bar:
                            guard let series = spec.series, (1...4).contains(series.count) else {
                                try fail("chart \(spec.chartID) needs 1–4 series")
                            }
                            for s in series {
                                guard !s.name.isEmpty, (2...60).contains(s.points.count) else {
                                    try fail("chart \(spec.chartID) series \(s.name) needs 2–60 points")
                                }
                            }
                        }
                    case let .quiz(quiz):
                        quizzes += 1
                        guard (3...4).contains(quiz.choices.count),
                              quiz.choices.indices.contains(quiz.answerIndex),
                              !quiz.question.isEmpty, !quiz.explanation.isEmpty else {
                            try fail("lesson \(lesson.lessonID) quiz is malformed")
                        }
                    case let .takeaways(items):
                        takeaways += 1
                        guard (2...5).contains(items.count) else {
                            try fail("lesson \(lesson.lessonID) takeaways must number 2–5")
                        }
                    }
                }
                guard quizzes == 1 else { try fail("lesson \(lesson.lessonID) needs exactly one quiz, has \(quizzes)") }
                guard visuals >= 1 else { try fail("lesson \(lesson.lessonID) needs a chart or a diagram") }
                guard paragraphs >= 1 else { try fail("lesson \(lesson.lessonID) needs a paragraph") }
                guard takeaways >= 1 else { try fail("lesson \(lesson.lessonID) needs a takeaways block") }
                if case .takeaways = lesson.blocks.last! {} else {
                    try fail("lesson \(lesson.lessonID) must end with takeaways")
                }
            }
        }
    }
}
