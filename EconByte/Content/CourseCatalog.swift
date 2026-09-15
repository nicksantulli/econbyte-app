import Foundation

// MARK: - Courses (1.1.4, EconByte Pro; 1.1.5 story lessons)
//
// `Resources/courses-v1.json` carries the subscription's course library: three
// courses of ordered lessons. 1.1.5 (schemaVersion 2, Owner: "almost like a
// 'story' you click through rather than an article") turned each lesson into
// ordered BEATS — one idea per screen, at most `StoryRules.maxWordsPerBeat`
// words, most with a visual, one or two quick checks and a recap last — plus
// the synthetic charts its beats show. `docs/content/STORY-SCHEMA-1.1.5.md`.
// The first lesson of every course is a free preview; the rest are readable
// only while EconByte Pro is active (`PurchaseManager.isProActive`).
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
    // Phase 13 (content growth):
    case rebalanceBands = "rebalance-bands"
    case trendlineAnchors = "trendline-anchors"
    case baseRateGrid = "base-rate-grid"
    case creditSpreadStack = "credit-spread-stack"
    case breakevenSplit = "breakeven-split"
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

// MARK: Story beats (schemaVersion 2)

public enum BeatKind: String, Codable, Hashable {
    /// One idea: heading, text, an optional tone and visual.
    case idea
    /// One or two key terms.
    case term
    /// A quick-check question with immediate feedback.
    case check
    /// The closing recap (always the last beat).
    case recap
}

public struct StoryCompareSide: Codable, Hashable {
    public let label: String
    public let detail: String
}

/// The picture on a beat. Decoded from `{"type": …}`; an unknown type fails
/// decoding, which fails the catalog closed.
public enum StoryVisual: Hashable {
    case diagram(DiagramID)
    case chart(chartID: String)
    case stat(value: String, label: String)
    case flow(steps: [String])
    case compare(left: StoryCompareSide, right: StoryCompareSide)
    case symbol(name: String)

    /// Decorative SF Symbols a beat may use (all present on iOS 16). Mirrors
    /// `ALLOWED_SYMBOLS` in `scripts/validate_content.mjs`.
    public static let allowedSymbols: Set<String> = [
        "chart.line.uptrend.xyaxis", "chart.line.downtrend.xyaxis", "chart.bar.fill", "chart.pie.fill",
        "percent", "dollarsign.circle.fill", "banknote.fill", "building.columns.fill", "clock.fill",
        "calendar", "scalemass.fill", "arrow.up.arrow.down", "arrow.triangle.2.circlepath",
        "exclamationmark.triangle.fill", "lightbulb.fill", "magnifyingglass", "person.2.fill",
        "brain.head.profile", "hourglass", "shield.fill", "doc.text.fill", "eye.fill",
        "questionmark.circle.fill", "checkmark.seal.fill", "hand.raised.fill", "arrow.up.right",
        "arrow.down.right", "flag.fill", "tray.full.fill", "square.stack.3d.up.fill", "cart.fill",
        "house.fill", "target", "ruler.fill", "speedometer", "list.number",
    ]

    public var typeName: String {
        switch self {
        case .diagram: return "diagram"
        case .chart: return "chart"
        case .stat: return "stat"
        case .flow: return "flow"
        case .compare: return "compare"
        case .symbol: return "symbol"
        }
    }

    /// Words the visual adds to its screen (drawings and charts add none).
    public var readingText: [String] {
        switch self {
        case .diagram, .chart, .symbol: return []
        case let .stat(value, label): return [value, label]
        case let .flow(steps): return steps
        case let .compare(left, right): return [left.label, left.detail, right.label, right.detail]
        }
    }
}

extension StoryVisual: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, diagramID, chartID, value, label, steps, left, right, name
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "diagram": self = .diagram(try c.decode(DiagramID.self, forKey: .diagramID))
        case "chart": self = .chart(chartID: try c.decode(String.self, forKey: .chartID))
        case "stat": self = .stat(value: try c.decode(String.self, forKey: .value),
                                  label: try c.decode(String.self, forKey: .label))
        case "flow": self = .flow(steps: try c.decode([String].self, forKey: .steps))
        case "compare": self = .compare(left: try c.decode(StoryCompareSide.self, forKey: .left),
                                        right: try c.decode(StoryCompareSide.self, forKey: .right))
        case "symbol": self = .symbol(name: try c.decode(String.self, forKey: .name))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c,
                                                   debugDescription: "unknown story visual type \(type)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(typeName, forKey: .type)
        switch self {
        case let .diagram(id): try c.encode(id, forKey: .diagramID)
        case let .chart(chartID): try c.encode(chartID, forKey: .chartID)
        case let .stat(value, label): try c.encode(value, forKey: .value); try c.encode(label, forKey: .label)
        case let .flow(steps): try c.encode(steps, forKey: .steps)
        case let .compare(left, right): try c.encode(left, forKey: .left); try c.encode(right, forKey: .right)
        case let .symbol(name): try c.encode(name, forKey: .name)
        }
    }
}

/// One screen of a story lesson.
public struct LessonBeat: Codable, Hashable {
    public let kind: BeatKind
    public let heading: String?
    public let text: String?
    public let tone: CalloutStyle?
    public let terms: [KeyTerm]?
    public let check: Quiz?
    public let items: [String]?
    public let visual: StoryVisual?

    public init(kind: BeatKind, heading: String? = nil, text: String? = nil, tone: CalloutStyle? = nil,
                terms: [KeyTerm]? = nil, check: Quiz? = nil, items: [String]? = nil, visual: StoryVisual? = nil) {
        self.kind = kind
        self.heading = heading
        self.text = text
        self.tone = tone
        self.terms = terms
        self.check = check
        self.items = items
        self.visual = visual
    }

    /// Everything the reader reads on this beat's screen (a check's explanation
    /// is revealed after answering and counted on its own).
    public var screenText: [String] {
        var parts: [String] = []
        if let heading { parts.append(heading) }
        if let text { parts.append(text) }
        for term in terms ?? [] { parts += [term.term, term.definition] }
        parts += items ?? []
        if kind == .check, let check { parts.append(check.question); parts += check.choices }
        parts += visual?.readingText ?? []
        return parts
    }

    public var wordCount: Int { screenText.reduce(0) { $0 + StoryRules.words(in: $1) } }

    /// Every reader-facing string, for the editorial tests.
    public var allText: [String] {
        screenText + (check.map { [$0.explanation] } ?? [])
    }
}

public enum StoryRules {
    public static let maxWordsPerBeat = 35
    public static let maxHeadingWords = 8
    public static let beatRange = 10...30
    public static let checkRange = 1...2

    public static func words(in text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }
}

public struct Lesson: Codable, Hashable, Identifiable {
    public let lessonID: String
    public let title: String
    public let summary: String
    public let estimatedMinutes: Int
    /// Exactly the first lesson of each course; readable without Pro.
    public let isPreview: Bool
    /// The synthetic charts this lesson's beats show.
    public let charts: [ChartSpec]
    public let beats: [LessonBeat]
    public let sources: [CurriculumSource]

    public var id: String { lessonID }

    public func chart(withID id: String) -> ChartSpec? { charts.first { $0.chartID == id } }

    /// The lesson's check beats, in order.
    public var checks: [Quiz] { beats.compactMap { $0.kind == .check ? $0.check : nil } }
    /// The first quick check (1.1.4's single quiz).
    public var quiz: Quiz? { checks.first }
    public var hasVisual: Bool { beats.contains { $0.visual != nil } }

    /// Story pages: the cover (page 0) and one page per beat.
    public var pageCount: Int { beats.count + 1 }

    /// The ordinal of the check on `beatIndex` among the lesson's checks.
    public func checkOrdinal(forBeat beatIndex: Int) -> Int? {
        guard beats.indices.contains(beatIndex), beats[beatIndex].kind == .check else { return nil }
        return beats[..<beatIndex].filter { $0.kind == .check }.count
    }

    /// Every reader-facing string, for the editorial tests.
    public var allText: [String] {
        var text: [String] = [title, summary]
        for beat in beats { text += beat.allText }
        for chart in charts {
            text += [chart.title, chart.caption, chart.dataNote, chart.xLabel, chart.yLabel]
            text += chart.series?.map(\.name) ?? []
            text += chart.markers?.map(\.label) ?? []
        }
        return text
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
    /// 1.1.4 shipped six lessons per course; Phase 13 (content growth) nine.
    public static let expectedLessonsPerCourse = 9
    /// 1.1.5: story lessons.
    public static let schemaVersion = 2

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

    static func validateChart(_ spec: ChartSpec, seen: inout Set<String>,
                              fail: (String) throws -> Never) throws {
        guard seen.insert(spec.chartID).inserted else {
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
    }

    static func validate(_ catalog: CourseCurriculum, core: Curriculum) throws {
        func fail(_ reason: String) throws -> Never {
            throw CurriculumError.validationFailed(reason)
        }

        guard catalog.schemaVersion == schemaVersion else {
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
            guard course.lessons.count == expectedLessonsPerCourse else {
                try fail("course \(course.courseID) has \(course.lessons.count) lessons, expected \(expectedLessonsPerCourse)")
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
                guard StoryRules.beatRange.contains(lesson.beats.count) else {
                    try fail("lesson \(lesson.lessonID) has \(lesson.beats.count) beats, needs \(StoryRules.beatRange)")
                }
                guard StoryRules.words(in: lesson.summary) <= StoryRules.maxWordsPerBeat else {
                    try fail("lesson \(lesson.lessonID) summary is longer than the cover allows")
                }
                guard !lesson.sources.isEmpty else {
                    try fail("lesson \(lesson.lessonID) cites no primary source")
                }
                for source in lesson.sources {
                    guard !source.url.isEmpty, !source.organization.isEmpty, !source.documentTitle.isEmpty else {
                        try fail("lesson \(lesson.lessonID) has an incomplete source")
                    }
                }

                var lessonChartIDs = Set<String>()
                for spec in lesson.charts {
                    try validateChart(spec, seen: &seenChartIDs, fail: fail)
                    lessonChartIDs.insert(spec.chartID)
                }

                var checks = 0, recaps = 0, visuals = 0, symbols = 0
                var shownCharts = Set<String>()
                for (index, beat) in lesson.beats.enumerated() {
                    let place = "lesson \(lesson.lessonID) beat \(index + 1)"
                    guard beat.wordCount <= StoryRules.maxWordsPerBeat else {
                        try fail("\(place) has \(beat.wordCount) words (max \(StoryRules.maxWordsPerBeat))")
                    }
                    if let heading = beat.heading {
                        guard !heading.isEmpty, StoryRules.words(in: heading) <= StoryRules.maxHeadingWords else {
                            try fail("\(place) heading must be 1–\(StoryRules.maxHeadingWords) words")
                        }
                    }
                    if beat.tone != nil, beat.kind != .idea { try fail("\(place) tone belongs on idea beats") }
                    switch beat.kind {
                    case .idea:
                        guard let text = beat.text, !text.isEmpty, beat.terms == nil, beat.check == nil, beat.items == nil else {
                            try fail("\(place) idea beat needs text and nothing but heading, tone and visual")
                        }
                    case .term:
                        guard let terms = beat.terms, (1...2).contains(terms.count),
                              terms.allSatisfy({ !$0.term.isEmpty && !$0.definition.isEmpty }),
                              beat.check == nil, beat.items == nil else {
                            try fail("\(place) term beat needs 1–2 complete terms")
                        }
                    case .check:
                        checks += 1
                        guard let quiz = beat.check, (3...4).contains(quiz.choices.count),
                              Set(quiz.choices).count == quiz.choices.count,
                              quiz.choices.indices.contains(quiz.answerIndex),
                              !quiz.question.isEmpty, !quiz.explanation.isEmpty,
                              beat.text == nil, beat.terms == nil, beat.items == nil else {
                            try fail("\(place) check is malformed")
                        }
                        guard StoryRules.words(in: quiz.explanation) <= StoryRules.maxWordsPerBeat else {
                            try fail("\(place) explanation is longer than \(StoryRules.maxWordsPerBeat) words")
                        }
                        guard index != 0, index != lesson.beats.count - 1 else {
                            try fail("\(place) a check is never the first or last beat")
                        }
                    case .recap:
                        recaps += 1
                        guard let items = beat.items, (2...5).contains(items.count), items.allSatisfy({ !$0.isEmpty }),
                              beat.visual == nil, beat.text == nil, beat.terms == nil, beat.check == nil else {
                            try fail("\(place) recap needs 2–5 items and nothing else")
                        }
                        guard index == lesson.beats.count - 1 else { try fail("\(place) the recap is the last beat") }
                    }
                    if let visual = beat.visual {
                        visuals += 1
                        switch visual {
                        case .diagram:
                            break
                        case let .chart(chartID):
                            guard lessonChartIDs.contains(chartID) else {
                                try fail("\(place) shows chart \(chartID), which is not in the lesson")
                            }
                            shownCharts.insert(chartID)
                        case let .stat(value, label):
                            guard !value.isEmpty, value.count <= 16, !label.isEmpty, StoryRules.words(in: label) <= 6 else {
                                try fail("\(place) stat needs a value (≤16 characters) and a label (≤6 words)")
                            }
                        case let .flow(steps):
                            guard (2...4).contains(steps.count),
                                  steps.allSatisfy({ !$0.isEmpty && StoryRules.words(in: $0) <= 4 }) else {
                                try fail("\(place) flow needs 2–4 steps of ≤4 words")
                            }
                        case let .compare(left, right):
                            guard [left, right].allSatisfy({ !$0.label.isEmpty && StoryRules.words(in: $0.label) <= 4
                                && !$0.detail.isEmpty && StoryRules.words(in: $0.detail) <= 8 }) else {
                                try fail("\(place) compare sides need a label (≤4 words) and a detail (≤8 words)")
                            }
                        case let .symbol(name):
                            symbols += 1
                            guard StoryVisual.allowedSymbols.contains(name) else {
                                try fail("\(place) symbol \(name) is not in the allowlist")
                            }
                        }
                    }
                }
                guard let first = lesson.beats.first, first.kind == .idea || first.kind == .term else {
                    try fail("lesson \(lesson.lessonID) must open with an idea or a term")
                }
                guard recaps == 1 else { try fail("lesson \(lesson.lessonID) needs exactly one recap, has \(recaps)") }
                guard StoryRules.checkRange.contains(checks) else {
                    try fail("lesson \(lesson.lessonID) needs 1–2 checks, has \(checks)")
                }
                guard visuals * 2 > lesson.beats.count else {
                    try fail("lesson \(lesson.lessonID): only \(visuals) of \(lesson.beats.count) beats carry a visual")
                }
                guard symbols <= visuals / 3 else {
                    try fail("lesson \(lesson.lessonID): too many decorative symbol visuals")
                }
                guard shownCharts == lessonChartIDs else {
                    try fail("lesson \(lesson.lessonID) carries a chart no beat shows")
                }
            }
        }
    }
}
