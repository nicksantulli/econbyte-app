import XCTest
import UIKit
@testable import EconByte

/// 1.1.5 story lessons (Phase 19): every lesson decodes as beats within the
/// story rules, every beat kind and visual decodes and round-trips, the
/// validator fails closed on the new rules, and course progress resumes,
/// records checks and migrates 1.1.4 records without losing anything.
final class StoryLessonsTests: XCTestCase {

    private func loadCourses() throws -> CourseCurriculum {
        try CourseCatalog.loadValidated(core: try CurriculumCatalog.loadValidated())
    }

    // MARK: - The bundled catalog

    func testAllTwentySevenLessonsAreStoriesWithinTheRules() throws {
        let catalog = try loadCourses()
        XCTAssertEqual(catalog.schemaVersion, 2)
        XCTAssertEqual(catalog.allLessons.count, 27)
        var beats = 0, checks = 0, visuals = 0
        for lesson in catalog.allLessons {
            XCTAssertTrue(StoryRules.beatRange.contains(lesson.beats.count), "\(lesson.lessonID) beat count \(lesson.beats.count)")
            XCTAssertLessThanOrEqual(StoryRules.words(in: lesson.summary), StoryRules.maxWordsPerBeat, "\(lesson.lessonID) cover summary")
            XCTAssertEqual(lesson.pageCount, lesson.beats.count + 1)
            XCTAssertTrue(lesson.beats.first?.kind == .idea || lesson.beats.first?.kind == .term, lesson.lessonID)
            XCTAssertEqual(lesson.beats.last?.kind, .recap, "\(lesson.lessonID) ends with its recap")
            XCTAssertEqual(lesson.beats.filter { $0.kind == .recap }.count, 1, lesson.lessonID)
            XCTAssertTrue(StoryRules.checkRange.contains(lesson.checks.count), "\(lesson.lessonID) has \(lesson.checks.count) checks")
            XCTAssertNotNil(lesson.quiz, lesson.lessonID)
            let withVisual = lesson.beats.filter { $0.visual != nil }.count
            XCTAssertGreaterThan(withVisual * 2, lesson.beats.count, "\(lesson.lessonID): a visual on most beats")
            for (index, beat) in lesson.beats.enumerated() {
                XCTAssertLessThanOrEqual(beat.wordCount, StoryRules.maxWordsPerBeat,
                                         "\(lesson.lessonID) beat \(index + 1): \(beat.screenText.joined(separator: " ").prefix(80))")
                if let check = beat.check {
                    XCTAssertLessThanOrEqual(StoryRules.words(in: check.explanation), StoryRules.maxWordsPerBeat)
                    XCTAssertNotEqual(index, 0)
                    XCTAssertNotEqual(index, lesson.beats.count - 1)
                }
            }
            let shown = Set(lesson.beats.compactMap { beat -> String? in
                if case let .chart(id)? = beat.visual { return id }
                return nil
            })
            XCTAssertEqual(shown, Set(lesson.charts.map(\.chartID)), "\(lesson.lessonID): every chart is shown, and only its own")
            beats += lesson.beats.count
            checks += lesson.checks.count
            visuals += withVisual
        }
        // Printed for the phase report.
        print("STORY-STATS lessons=\(catalog.allLessons.count) beats=\(beats) checks=\(checks) visualBeats=\(visuals)")
    }

    func testCourseMinutesAreTheSumOfTheirLessons() throws {
        for course in try loadCourses().courses {
            XCTAssertEqual(course.estimatedMinutes, course.lessons.map(\.estimatedMinutes).reduce(0, +), course.courseID)
            XCTAssertTrue(course.lessons.allSatisfy { $0.estimatedMinutes >= 2 }, course.courseID)
        }
    }

    func testCheckOrdinalsCountChecksInOrder() throws {
        let lessons = try loadCourses().allLessons
        let twoChecks = lessons.first(where: { $0.checks.count == 2 })
        let lesson = try XCTUnwrap(twoChecks ?? lessons.first)
        XCTAssertNotNil(twoChecks, "at least one story has two quick checks")
        let checkIndices = lesson.beats.indices.filter { lesson.beats[$0].kind == .check }
        for (ordinal, index) in checkIndices.enumerated() {
            XCTAssertEqual(lesson.checkOrdinal(forBeat: index), ordinal)
        }
        XCTAssertNil(lesson.checkOrdinal(forBeat: 0), "the first beat is never a check")
        XCTAssertNil(lesson.checkOrdinal(forBeat: 999))
    }

    func testEverySymbolInTheAllowlistExistsOnThisOS() {
        for name in StoryVisual.allowedSymbols {
            XCTAssertNotNil(UIImage(systemName: name), "SF Symbol \(name) is missing")
        }
    }

    // MARK: - Decoding

    private static let everyKindJSON = """
    [
      {"kind": "idea", "heading": "Two parts", "text": "Income plus price change.", "tone": "example",
       "visual": {"type": "flow", "steps": ["Income", "Price change", "Total return"]}},
      {"kind": "idea", "text": "A stat.", "visual": {"type": "stat", "value": "7%", "label": "illustrative"}},
      {"kind": "idea", "text": "A comparison.", "visual": {"type": "compare",
        "left": {"label": "Steady", "detail": "small swings"}, "right": {"label": "Volatile", "detail": "wide swings"}}},
      {"kind": "idea", "text": "A symbol.", "visual": {"type": "symbol", "name": "scalemass.fill"}},
      {"kind": "idea", "text": "A drawing.", "visual": {"type": "diagram", "diagramID": "risk-return-ladder"}},
      {"kind": "term", "terms": [{"term": "Return", "definition": "Income plus price change."}],
       "visual": {"type": "chart", "chartID": "x-1"}},
      {"kind": "check", "check": {"question": "Which?", "choices": ["A", "B", "C"], "answerIndex": 1, "explanation": "B."}},
      {"kind": "recap", "items": ["One", "Two"]}
    ]
    """

    func testEveryBeatKindAndVisualDecodesAndRoundTrips() throws {
        let beats = try JSONDecoder().decode([LessonBeat].self, from: Data(Self.everyKindJSON.utf8))
        XCTAssertEqual(beats.map(\.kind), [.idea, .idea, .idea, .idea, .idea, .term, .check, .recap])
        XCTAssertEqual(beats[0].tone, .example)
        XCTAssertEqual(beats[0].visual, .flow(steps: ["Income", "Price change", "Total return"]))
        XCTAssertEqual(beats[1].visual, .stat(value: "7%", label: "illustrative"))
        XCTAssertEqual(beats[2].visual, .compare(left: StoryCompareSide(label: "Steady", detail: "small swings"),
                                                 right: StoryCompareSide(label: "Volatile", detail: "wide swings")))
        XCTAssertEqual(beats[3].visual, .symbol(name: "scalemass.fill"))
        XCTAssertEqual(beats[4].visual, .diagram(.riskReturnLadder))
        XCTAssertEqual(beats[5].visual, .chart(chartID: "x-1"))
        XCTAssertEqual(beats[6].check?.answerIndex, 1)
        XCTAssertEqual(beats[7].items, ["One", "Two"])

        // Words on screen: heading + text + flow steps; a check counts question + choices.
        XCTAssertEqual(beats[0].wordCount, 2 + 4 + 5)
        XCTAssertEqual(beats[6].wordCount, 1 + 3)
        XCTAssertEqual(beats[1].wordCount, 2 + 1 + 1)

        let reencoded = try JSONDecoder().decode([LessonBeat].self, from: try JSONEncoder().encode(beats))
        XCTAssertEqual(reencoded, beats)
    }

    func testAnUnknownBeatKindOrVisualTypeFailsDecoding() {
        XCTAssertThrowsError(try JSONDecoder().decode(LessonBeat.self, from: Data(#"{"kind": "video", "text": "x"}"#.utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(LessonBeat.self,
            from: Data(#"{"kind": "idea", "text": "x", "visual": {"type": "hologram"}}"#.utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(LessonBeat.self,
            from: Data(#"{"kind": "idea", "text": "x", "visual": {"type": "diagram", "diagramID": "money-printer"}}"#.utf8)))
    }

    // MARK: - Validator fails closed on the story rules

    private func coursesObject() throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle.curriculumBundle.url(forResource: CourseCatalog.resourceName, withExtension: "json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any])
    }

    private func assertRejected(_ description: String, file: StaticString = #filePath, line: UInt = #line,
                                _ change: (inout [String: Any]) -> Void) throws {
        var object = try coursesObject()
        guard var courses = object["courses"] as? [[String: Any]],
              var lessons = courses[0]["lessons"] as? [[String: Any]] else { return XCTFail("shape", file: file, line: line) }
        change(&lessons[0])
        courses[0]["lessons"] = lessons
        object["courses"] = courses
        let data = try JSONSerialization.data(withJSONObject: object)
        let core = try CurriculumCatalog.loadValidated()
        do {
            let broken = try JSONDecoder().decode(CourseCurriculum.self, from: data)
            XCTAssertThrowsError(try CourseCatalog.validate(broken, core: core), "validator accepted \(description)",
                                 file: file, line: line)
        } catch {
            // A decoding failure is also a rejection.
        }
    }

    private func beats(_ lesson: [String: Any]) -> [[String: Any]] { lesson["beats"] as? [[String: Any]] ?? [] }

    func testTheUnchangedCatalogPassesTheValidator() throws {
        XCTAssertNoThrow(try loadCourses())
    }

    func testValidatorRejectsABeatOverTheWordLimit() throws {
        try assertRejected("a 36-word beat") { lesson in
            var list = beats(lesson)
            list[0] = ["kind": "idea", "text": Array(repeating: "word", count: 36).joined(separator: " ")]
            lesson["beats"] = list
        }
    }

    func testValidatorRejectsARecapThatIsNotLast() throws {
        try assertRejected("a recap before the end") { lesson in
            var list = beats(lesson)
            let recap = list.removeLast()
            list.insert(recap, at: 1)
            lesson["beats"] = list
        }
    }

    func testValidatorRejectsThreeChecksAndACheckFirst() throws {
        try assertRejected("three checks") { lesson in
            var list = beats(lesson)
            guard let check = list.first(where: { $0["kind"] as? String == "check" }) else { return }
            list.insert(check, at: 2); list.insert(check, at: 3)
            lesson["beats"] = list
        }
        try assertRejected("a check as the first beat") { lesson in
            var list = beats(lesson)
            guard let check = list.first(where: { $0["kind"] as? String == "check" }) else { return }
            list.insert(check, at: 0)
            lesson["beats"] = list
        }
    }

    func testValidatorRejectsALessonWithTooFewVisuals() throws {
        try assertRejected("visuals on half the beats or fewer") { lesson in
            lesson["beats"] = beats(lesson).map { beat in
                var b = beat
                if case "chart"? = (b["visual"] as? [String: Any])?["type"] as? String { return b }
                b.removeValue(forKey: "visual")
                return b
            }
        }
    }

    func testValidatorRejectsAChartNoBeatShowsAndAnUnlistedChart() throws {
        try assertRejected("a chart no beat shows") { lesson in
            lesson["beats"] = beats(lesson).map { beat in
                var b = beat
                if case "chart"? = (b["visual"] as? [String: Any])?["type"] as? String {
                    b["visual"] = ["type": "symbol", "name": "percent"]
                }
                return b
            }
        }
        try assertRejected("a beat showing a chart that is not in the lesson") { lesson in
            var list = beats(lesson)
            list[0]["visual"] = ["type": "chart", "chartID": "no-such-chart"]
            lesson["beats"] = list
        }
    }

    func testValidatorRejectsASymbolOutsideTheAllowlist() throws {
        try assertRejected("an unknown symbol") { lesson in
            var list = beats(lesson)
            list[0]["visual"] = ["type": "symbol", "name": "flame.fill"]
            lesson["beats"] = list
        }
    }

    // MARK: - Progress: resume, checks, migration

    private func freshDefaults() throws -> (UserDefaults, String) {
        let suite = "StoryLessonsTests.\(UUID().uuidString)"
        return (try XCTUnwrap(UserDefaults(suiteName: suite)), suite)
    }

    @MainActor
    func testResumeReturnsTheLastPageAndCompletionClearsIt() throws {
        let (defaults, suite) = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let course = try XCTUnwrap(try loadCourses().courses.first)
        let lesson = course.lessons[1]
        let store = CourseProgressStore(defaults: defaults)

        XCTAssertEqual(store.resumePage(for: lesson), 0, "a new lesson opens at its cover")
        store.recordPage(4, lessonID: lesson.lessonID)
        XCTAssertEqual(store.resumePage(for: lesson), 4)
        XCTAssertEqual(CourseProgressStore(defaults: defaults).resumePage(for: lesson), 4, "the position persists")

        store.markCompleted(lessonID: lesson.lessonID, courseID: course.courseID)
        XCTAssertTrue(store.isCompleted(lesson.lessonID))
        XCTAssertEqual(store.resumePage(for: lesson), 0, "a completed lesson re-reads from the cover")
        store.recordPage(3, lessonID: lesson.lessonID)
        XCTAssertNil(store.progress[lesson.lessonID]?.lastBeat, "a completed lesson keeps no position")
    }

    @MainActor
    func testChecksRecordTheFirstAnswerEachAndCheckZeroIsTheQuiz() throws {
        let (defaults, suite) = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CourseProgressStore(defaults: defaults)

        store.recordCheck(lessonID: "ia-03", ordinal: 1, correct: true)
        XCTAssertNil(store.quizResult("ia-03"), "check 1 is not the quiz")
        store.recordCheck(lessonID: "ia-03", ordinal: 0, correct: false)
        store.recordCheck(lessonID: "ia-03", ordinal: 0, correct: true)
        store.recordCheck(lessonID: "ia-03", ordinal: 1, correct: false)
        XCTAssertEqual(store.checkResult(lessonID: "ia-03", ordinal: 0), false, "first answer wins")
        XCTAssertEqual(store.checkResult(lessonID: "ia-03", ordinal: 1), true, "first answer wins")
        XCTAssertEqual(store.quizResult("ia-03"), false, "quizCorrect mirrors check 0")

        store.recordQuiz(lessonID: "ia-04", correct: true)
        XCTAssertEqual(store.checkResult(lessonID: "ia-04", ordinal: 0), true, "the 1.1.4 API still records check 0")
    }

    /// A 1.1.4 install's exact stored bytes: `completedAt` as a reference-date
    /// number, `quizCorrect`, no version key. Nothing may be lost.
    @MainActor
    func testMigrationKeepsEvery114RecordAndClampsImpossiblePositions() throws {
        let (defaults, suite) = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let stored114 = """
        {"ia-01": {"completedAt": 779600000, "quizCorrect": true},
         "ia-02": {"quizCorrect": false},
         "rpc-01": {"completedAt": 779700000}}
        """
        defaults.set(Data(stored114.utf8), forKey: CourseProgressStore.defaultsKey)
        XCTAssertEqual(defaults.integer(forKey: CourseProgressStore.versionKey), 0)

        let catalog = try loadCourses()
        let counts = CourseProgressStore.pageCounts(in: catalog)
        let store = CourseProgressStore(defaults: defaults, pageCounts: counts)

        XCTAssertTrue(store.isCompleted("ia-01"))
        XCTAssertTrue(store.isCompleted("rpc-01"))
        XCTAssertFalse(store.isCompleted("ia-02"))
        XCTAssertEqual(store.progress["ia-01"]?.completedAt, Date(timeIntervalSinceReferenceDate: 779_600_000))
        XCTAssertEqual(store.quizResult("ia-01"), true)
        XCTAssertEqual(store.checkResult(lessonID: "ia-01", ordinal: 0), true, "the 1.1.4 quiz is check 0")
        XCTAssertEqual(store.checkResult(lessonID: "ia-02", ordinal: 0), false)
        XCTAssertNil(store.checkResult(lessonID: "ia-02", ordinal: 1))
        let course = try XCTUnwrap(catalog.courses.first)
        XCTAssertEqual(store.completedCount(of: course), 1, "course completion carries over")
        XCTAssertEqual(defaults.integer(forKey: CourseProgressStore.versionKey), CourseProgressStore.currentVersion)

        // A position beyond the lesson's pages (e.g. saved against a longer
        // draft) is dropped; a valid one is kept.
        let ia02 = try XCTUnwrap(catalog.lesson(withID: "ia-02"))
        let migrated = CourseProgressStore.migrated(
            ["ia-02": .init(lastBeat: ia02.pageCount + 5), "ia-03": .init(lastBeat: 2),
             "ia-01": .init(completedAt: Date(), lastBeat: 3)],
            pageCounts: counts)
        XCTAssertNil(migrated["ia-02"]?.lastBeat)
        XCTAssertEqual(migrated["ia-03"]?.lastBeat, 2)
        XCTAssertNil(migrated["ia-01"]?.lastBeat, "a completed lesson keeps no position")

        // Idempotent: a second launch changes nothing.
        let before = store.progress
        let again = CourseProgressStore(defaults: defaults, pageCounts: counts)
        XCTAssertEqual(again.progress, before)
    }

    // MARK: - Phase 24: pictures, centerpieces and lesson graphics

    func testPictureCoverageAndOneCenterpiecePerLesson() throws {
        let catalog = try loadCourses()
        var covered = 0, teaching = 0, graphics = 0
        var byKind: [String: Int] = [:]
        for lesson in catalog.allLessons {
            let coverage = lesson.pictureCoverage
            XCTAssertGreaterThanOrEqual(Double(coverage.covered), Double(coverage.teaching) * StoryRules.lessonPictureCoverage,
                                        "\(lesson.lessonID): \(coverage.covered) of \(coverage.teaching) teaching beats have a picture")
            covered += coverage.covered
            teaching += coverage.teaching
            let centerpieces = lesson.beats.filter(\.isCenterpiece)
            XCTAssertEqual(centerpieces.count, 1, "\(lesson.lessonID) has exactly one centerpiece")
            for beat in centerpieces {
                XCTAssertTrue(beat.isTeaching, lesson.lessonID)
                XCTAssertTrue(StoryRules.canBeCenterpiece(beat.visual), "\(lesson.lessonID): the centerpiece is a strong picture")
            }
            for beat in lesson.beats {
                if case let .graphic(spec)? = beat.visual {
                    graphics += 1
                    byKind[spec.kind.rawValue, default: 0] += 1
                }
            }
        }
        XCTAssertGreaterThanOrEqual(Double(covered), Double(teaching) * StoryRules.catalogPictureCoverage,
                                    "\(covered) of \(teaching) teaching beats have a picture")
        print("PICTURE-STATS covered=\(covered) teaching=\(teaching) graphics=\(graphics) kinds=\(byKind.sorted { $0.key < $1.key })")
    }

    /// Every lesson graphic satisfies the card-graphics contract, uses a lesson
    /// basis, and prints only numbers the lesson states, its `derived` entries
    /// compute, or its plotted data contains (the content checker goes further:
    /// it re-resolves recipes and recomputes formulas).
    func testEveryLessonGraphicSatisfiesTheContractAndItsNumbersAreBacked() throws {
        var failures: [String] = []
        for lesson in try loadCourses().allLessons {
            let prose = Self.numbers(in: Self.lessonProse(lesson))
            for (index, beat) in lesson.beats.enumerated() {
                guard case let .graphic(spec)? = beat.visual else { continue }
                let place = "\(lesson.lessonID) beat \(index + 1)"
                let problems = spec.validationProblems()
                if !problems.isEmpty { failures.append("\(place): \(problems.joined(separator: "; "))") }
                if spec.basis == .fromCard { failures.append("\(place): a lesson graphic uses fromLesson") }
                if spec.kind == .icons { failures.append("\(place): icons are not used in lessons") }
                if beat.kind == .recap { failures.append("\(place): a recap carries no picture") }
                XCTAssertTrue(spec.isRenderable, place)
                guard [.fromLesson, .computed, .sourced].contains(spec.basis) else { continue }
                var allowed = prose + (spec.derived ?? []).map(\.value)
                allowed += (spec.line?.series ?? []).flatMap { $0.points.flatMap { $0 } }
                allowed += (spec.line?.references ?? []).map(\.y)
                if spec.basis == .fromLesson {
                    let stated = prose + (spec.derived ?? []).map(\.value)
                    let values = (spec.bars?.items ?? []).map(\.value) + (spec.proportion?.segments ?? []).map(\.value)
                        + (spec.candles?.candles ?? []).flatMap { [$0.open, $0.high, $0.low, $0.close] }
                    for value in values where !Self.contains(stated, value) {
                        failures.append("\(place): value \(value) is not in the lesson")
                    }
                    allowed += values
                }
                allowed += (spec.proportion.map { [$0.total] } ?? [])
                for text in spec.displayStrings {
                    let cleaned = text.replacingOccurrences(of: "12-month", with: "twelve-month")
                    for number in Self.numbers(in: cleaned) where !Self.contains(allowed, number) {
                        failures.append("\(place): \"\(text)\" shows \(number)")
                    }
                }
            }
        }
        XCTAssertEqual(failures, [], failures.joined(separator: "\n"))
    }

    func testEveryLessonGraphicHasALessonFootnoteAndASpokenSummary() throws {
        for lesson in try loadCourses().allLessons {
            for (index, beat) in lesson.beats.enumerated() {
                guard case let .graphic(spec)? = beat.visual else { continue }
                let place = "\(lesson.lessonID) beat \(index + 1)"
                let summary = spec.accessibilitySummary(in: .lesson)
                XCTAssertTrue(summary.hasPrefix("Graphic: \(spec.title)."), place)
                XCTAssertGreaterThan(summary.count, spec.title.count + 20, "\(place): the spoken summary is too thin")
                let footnote = spec.footnote(in: .lesson)
                switch spec.basis {
                case .conceptual:   XCTAssertEqual(footnote, spec.note, place)
                case .fromLesson:   XCTAssertTrue(footnote?.hasPrefix("Figures from this lesson") == true, place)
                case .computed:     XCTAssertTrue(footnote?.hasPrefix("Computed from this lesson's figures") == true, place)
                case .sourced:      XCTAssertTrue(footnote?.hasPrefix("Source: ") == true, place)
                case .illustrative: XCTAssertTrue(footnote?.hasPrefix("Illustrative, not real data") == true, place)
                case .fromCard:     XCTFail("\(place): fromCard in a lesson")
                }
                XCTAssertFalse(summary.contains("this card"), "\(place): a lesson graphic never mentions a card")
            }
        }
    }

    /// Every lesson graphic draws on the lesson plate at iPhone 17 width; the
    /// centerpiece plate is taller; text stops growing at the plate's cap, so the
    /// largest accessibility size draws exactly like xxxLarge.
    @MainActor
    func testEveryLessonGraphicRendersOnTheLessonPlate() throws {
        var checkedCap = Set<CardGraphicKind>()
        for lesson in try loadCourses().allLessons {
            for (index, beat) in lesson.beats.enumerated() {
                guard case let .graphic(spec)? = beat.visual else { continue }
                let place = "\(lesson.lessonID) beat \(index + 1)"
                let regular = try Self.lessonPlateHeight(spec, prominent: false, typeSize: .large)
                XCTAssertGreaterThan(regular, 80, "\(place) rendered empty")
                if spec.kind == .line || spec.kind == .candles {
                    XCTAssertGreaterThan(try Self.lessonPlateHeight(spec, prominent: true, typeSize: .large), regular,
                                         "\(place): the centerpiece plate is taller")
                }
                if checkedCap.insert(spec.kind).inserted {
                    let capped = try Self.lessonPlateHeight(spec, prominent: beat.isCenterpiece, typeSize: GraphicPlate.largestTypeSize)
                    let largest = try Self.lessonPlateHeight(spec, prominent: beat.isCenterpiece, typeSize: .accessibility5)
                    XCTAssertEqual(largest, capped, accuracy: 0.5, "\(place) grows past the plate's text cap")
                }
            }
        }
    }

    func testGraphicVisualAndCenterpieceDecodeAndRoundTrip() throws {
        let json = #"""
        {"kind": "idea", "text": "Day 4 is a hammer.", "centerpiece": true,
         "visual": {"type": "graphic", "graphic": {"kind": "candles", "title": "A hammer after a decline", "basis": "illustrative",
           "candles": {"xLabel": "Day", "yLabel": "Price",
             "candles": [{"open": 104, "high": 104.3, "low": 102.7, "close": 103}, {"open": 103, "high": 103.3, "low": 101.7, "close": 102},
                         {"open": 102, "high": 102.3, "low": 100.7, "close": 101}, {"open": 100.8, "high": 101.25, "low": 98.6, "close": 101.2}],
             "highlight": {"from": 4, "to": 4, "pattern": "hammer", "label": "Hammer"}}}}}
        """#
        let beat = try JSONDecoder().decode(LessonBeat.self, from: Data(json.utf8))
        XCTAssertTrue(beat.isCenterpiece)
        guard case let .graphic(spec)? = beat.visual else { return XCTFail("a graphic visual") }
        XCTAssertEqual(spec.kind, .candles)
        XCTAssertEqual(spec.candles?.highlight?.pattern, .hammer)
        XCTAssertEqual(spec.validationProblems(), [])
        XCTAssertTrue(StoryRules.canBeCenterpiece(beat.visual))
        XCTAssertEqual(beat.wordCount, 5, "a graphic's labels are artwork, not beat words")
        XCTAssertTrue(beat.allText.contains("Hammer"), "the editorial scans still read the graphic's labels")
        XCTAssertEqual(try JSONDecoder().decode(LessonBeat.self, from: try JSONEncoder().encode(beat)), beat)
        XCTAssertFalse(StoryRules.canBeCenterpiece(.symbol(name: "percent")))
        XCTAssertFalse(StoryRules.canBeCenterpiece(.stat(value: "7%", label: "x")))
    }

    func testValidatorRejectsTwoCenterpiecesAndABadLessonGraphic() throws {
        try assertRejected("two centerpieces") { lesson in
            var list = beats(lesson)
            let chartBeats = list.indices.filter { ["chart", "diagram"].contains((list[$0]["visual"] as? [String: Any])?["type"] as? String) }
            guard chartBeats.count >= 2 else { return }
            list[chartBeats[0]]["centerpiece"] = true
            list[chartBeats[1]]["centerpiece"] = true
            lesson["beats"] = list
        }
        try assertRejected("a centerpiece on a symbol") { lesson in
            var list = beats(lesson)
            list = list.map { var b = $0; b.removeValue(forKey: "centerpiece"); return b }
            list[0]["visual"] = ["type": "symbol", "name": "percent"]
            list[0]["centerpiece"] = true
            lesson["beats"] = list
        }
        try assertRejected("a lesson graphic with the card basis") { lesson in
            var list = beats(lesson)
            list[0]["visual"] = ["type": "graphic", "graphic": [
                "kind": "bars", "title": "Two fees", "basis": "fromCard",
                "bars": ["items": [["label": "A", "value": 1], ["label": "B", "value": 2]]]]]
            lesson["beats"] = list
        }
        try assertRejected("a hammer whose upper wick is long") { lesson in
            var list = beats(lesson)
            let candles: [[String: Any]] = [
                ["open": 104, "high": 104.2, "low": 102.8, "close": 103], ["open": 103, "high": 103.2, "low": 101.8, "close": 102],
                ["open": 102, "high": 102.2, "low": 100.8, "close": 101], ["open": 101, "high": 102.5, "low": 99, "close": 101.5]]
            list[0]["visual"] = ["type": "graphic", "graphic": [
                "kind": "candles", "title": "Not a hammer", "basis": "illustrative",
                "candles": ["xLabel": "Day", "yLabel": "Price", "candles": candles,
                            "highlight": ["from": 4, "to": 4, "pattern": "hammer", "label": "Hammer"]]]]
            lesson["beats"] = list
        }
    }

    // MARK: Phase 24 helpers

    @MainActor
    private static func lessonPlateHeight(_ spec: CardGraphicSpec, prominent: Bool, typeSize: DynamicTypeSize) throws -> CGFloat {
        let view = GraphicPlate(spec: spec, host: .lesson, prominent: prominent)
            .frame(width: 362)
            .environment(\.colorScheme, .dark)
            .environment(\.dynamicTypeSize, typeSize)
        return try XCTUnwrap(ImageRenderer(content: view).uiImage, spec.title).size.height
    }

    /// The prose a `fromLesson` graphic may restate (graphic labels excluded).
    private static func lessonProse(_ lesson: Lesson) -> String {
        var parts = [lesson.title, lesson.summary]
        for beat in lesson.beats {
            parts += beat.screenText
            if let explanation = beat.check?.explanation { parts.append(explanation) }
        }
        for chart in lesson.charts { parts += [chart.title, chart.caption] }
        return parts.joined(separator: " \n ")
    }

    private static let wordNumbers: [String: Double] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "twenty": 20, "thirty": 30,
        "forty": 40, "fifty": 50, "sixty": 60, "hundred": 100, "thousand": 1000, "million": 1e6, "billion": 1e9,
        "half": 0.5, "twice": 2, "double": 2, "first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5, "decade": 10, "decades": 10,
    ]

    /// Numbers in text: grouped digits ("1,000"), decimals, scale words
    /// ("1.5 million" → 1.5 and 1,500,000) and number words.
    static func numbers(in text: String) -> [Double] {
        var out: [Double] = []
        let normalized = text.replacingOccurrences(of: "−", with: "-")
        let pattern = #"(\d{1,3}(?:,\d{3})+(?:\.\d+)?|\d+(?:\.\d+)?)(\s*(?:thousand|million|billion|trillion))?"#
        let regex = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        for match in regex.matches(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)) {
            guard let r = Range(match.range(at: 1), in: normalized),
                  let value = Double(normalized[r].replacingOccurrences(of: ",", with: "")) else { continue }
            out.append(value)
            if let s = Range(match.range(at: 2), in: normalized) {
                let word = normalized[s].trimmingCharacters(in: .whitespaces).lowercased()
                out.append(value * ["thousand": 1e3, "million": 1e6, "billion": 1e9, "trillion": 1e12][word, default: 1])
            }
        }
        for word in normalized.lowercased().split(whereSeparator: { !$0.isLetter }) {
            if let value = wordNumbers[String(word)] { out.append(value) }
        }
        return out
    }

    /// Same figure, allowing display rounding of a non-integer (9.06 shown as "9.1").
    static func contains(_ allowed: [Double], _ value: Double) -> Bool {
        allowed.contains { a in
            abs(a - value) <= max(1e-9, abs(value) * 1e-9)
                || (abs(a) >= 0.01 && abs(a - value) <= 0.051 && abs(value) < 1000 && value != value.rounded())
        }
    }
}
