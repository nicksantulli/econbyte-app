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
}
