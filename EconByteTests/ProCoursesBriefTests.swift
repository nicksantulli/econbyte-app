import XCTest
import StoreKit
@testable import EconByte

/// EconByte Pro (1.1.4): the course library, the Daily Brief, the subscription
/// entitlement, and their telemetry. Editorial rules mirror `PackCatalogTests`
/// (and `scripts/validate_content.mjs`); the fail-closed cases prove the runtime
/// validators reject what the tests reject.
final class ProCoursesBriefTests: XCTestCase {

    private static let canonicalDisclaimer =
        "Educational content only. EconByte does not provide financial, investment, or tax advice."

    private static let approvedSourceHosts: Set<String> = [
        "www.federalreserve.gov", "www.federalreservehistory.org",
        "www.newyorkfed.org", "www.philadelphiafed.org", "fred.stlouisfed.org", "www.stlouisfed.org",
        "www.chicagofed.org", "www.clevelandfed.org", "www.atlantafed.org", "www.kansascityfed.org",
        "www.bostonfed.org", "www.richmondfed.org", "www.dallasfed.org", "www.minneapolisfed.org",
        "www.sf.frb.org", "www.frbsf.org",
        "www.bls.gov", "www.bea.gov", "www.census.gov",
        "fiscaldata.treasury.gov", "home.treasury.gov", "www.treasurydirect.gov",
        "www.irs.gov", "www.ssa.gov", "www.fdic.gov", "www.nber.org",
        "www.cbo.gov", "www.imf.org", "www.sec.gov", "www.investor.gov",
        "www.consumerfinance.gov", "www.finra.org", "www.sipc.org",
    ]

    private static let staleTemporalWords = [
        "currently", "today", "nowadays", "recently", "at present",
        "these days", "this year", "last year", "right now", "as of now",
    ]

    private static let prohibitedAdvicePhrases = [
        "you should buy", "you should sell", "you should invest",
        "should buy", "should sell", "invest in", "buy now", "sell now",
        "guaranteed return", "risk-free return", "financial advice",
        "investment advice", "we recommend", "best investment",
        "will outperform", "get rich", "hot stock", "price target",
        "portfolio allocation", "beat the market", "sure thing", "act fast",
    ]

    /// Courses may not name a security, a fund company, a brokerage, a
    /// trademarked index, or a cryptocurrency.
    private static let namedEntities = [
        "s&p", "dow jones", "nasdaq", "russell 2000", "bitcoin", "ethereum", "tesla", "amazon",
        "microsoft", "nvidia", "alphabet", "berkshire", "vanguard", "fidelity", "blackrock", "robinhood",
    ]

    private static let predictionPhrases = [
        "will rise", "will fall", "will go up", "will go down", "we expect", "likely to rise",
        "likely to fall", "poised to", "should rise", "should fall", "we predict", "will rally", "will crash",
    ]

    private func repoRoot(file: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(file)").deletingLastPathComponent().deletingLastPathComponent()
    }

    private func loadCore() throws -> Curriculum { try CurriculumCatalog.loadValidated() }
    private func loadCourses() throws -> CourseCurriculum { try CourseCatalog.loadValidated(core: try loadCore()) }

    private static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // MARK: - Courses: contract

    func testCoursesLoadWithTheExpectedShape() throws {
        let catalog = try loadCourses()
        XCTAssertEqual(catalog.schemaVersion, 1)
        XCTAssertEqual(catalog.disclaimer, Self.canonicalDisclaimer)
        XCTAssertTrue(catalog.educationalNotice.localizedCaseInsensitiveContains("not investment advice"))
        XCTAssertEqual(catalog.courses.map(\.courseID), CourseCatalog.expectedCourses.map(\.courseID))
        XCTAssertEqual(catalog.courses.count, 3)
        for course in catalog.courses {
            XCTAssertGreaterThanOrEqual(course.lessons.count, 5, course.courseID)
            XCTAssertEqual(course.lessons.count, CourseCatalog.expectedLessonsPerCourse, course.courseID)
            XCTAssertEqual(course.estimatedMinutes, course.lessons.map(\.estimatedMinutes).reduce(0, +),
                           "\(course.courseID) duration is the sum of its lessons")
            XCTAssertEqual(course.lessons.filter(\.isPreview).map(\.lessonID), [course.lessons[0].lessonID],
                           "exactly the first lesson of \(course.courseID) is the free preview")
            XCTAssertNotNil(EBCourseFamily(courseID: course.courseID), "\(course.courseID) has a telemetry family")
            for lesson in course.lessons {
                XCTAssertGreaterThanOrEqual(lesson.blocks.count, 5, lesson.lessonID)
                XCTAssertTrue(lesson.hasVisual, "\(lesson.lessonID) needs a chart or diagram")
                XCTAssertEqual(lesson.blocks.filter { if case .quiz = $0 { return true }; return false }.count, 1,
                               "\(lesson.lessonID) has exactly one quiz")
                XCTAssertNotNil(lesson.quiz, lesson.lessonID)
                if case .takeaways = lesson.blocks.last! {} else { XCTFail("\(lesson.lessonID) must end with takeaways") }
                XCTAssertFalse(lesson.sources.isEmpty, lesson.lessonID)
            }
        }
        // Volume targets from the 1.1.4 plan: 3 courses × ≥5 lessons, each with
        // ≥5 blocks, ≥1 chart/diagram and a quiz.
        XCTAssertGreaterThanOrEqual(catalog.allLessons.count, 15)
        XCTAssertEqual(CourseCatalog.expectedLessonsPerCourse, 9, "1.1.4 Phase 13 grows every course to nine lessons")
        XCTAssertEqual(catalog.allLessons.count, 27)
    }

    /// Every diagram the app can draw is used by some lesson (no dead
    /// drawings) and every chart is declared synthetic.
    func testEveryDiagramIsUsedAndEveryChartIsSynthetic() throws {
        let catalog = try loadCourses()
        var used = Set<DiagramID>()
        var chartIDs = Set<String>()
        var charts = 0
        for block in catalog.allLessons.flatMap(\.blocks) {
            switch block {
            case let .diagram(id, _): used.insert(id)
            case let .chart(spec):
                charts += 1
                XCTAssertTrue(spec.dataNote.lowercased().hasPrefix("synthetic"), spec.chartID)
                XCTAssertTrue(chartIDs.insert(spec.chartID).inserted, "duplicate chart \(spec.chartID)")
                if spec.kind == .candlestick {
                    for candle in spec.candles ?? [] {
                        XCTAssertGreaterThanOrEqual(candle.high, max(candle.open, candle.close), spec.chartID)
                        XCTAssertLessThanOrEqual(candle.low, min(candle.open, candle.close), spec.chartID)
                    }
                } else {
                    XCTAssertFalse((spec.series ?? []).isEmpty, spec.chartID)
                }
            default: break
            }
        }
        XCTAssertEqual(used, Set(DiagramID.allCases), "every drawable diagram should be referenced by a lesson")
        XCTAssertGreaterThanOrEqual(charts, 6, "at least one chart per course pair")
        for id in DiagramID.allCases {
            XCTAssertFalse(DiagramView.accessibilityDescription(for: id).isEmpty, id.rawValue)
        }
    }

    /// The base-rate diagram's dots are fixed counts the rpc lesson caption
    /// quotes; the picture and the caption cannot drift apart.
    func testBaseRateGridDrawsTheCountsItsCaptionStates() throws {
        XCTAssertEqual(BaseRateGrid.caseCount, 100)
        XCTAssertEqual(BaseRateGrid.patternIndices.count, 20)
        XCTAssertEqual(BaseRateGrid.patternRoseIndices.count, 11)
        XCTAssertTrue(BaseRateGrid.patternRoseIndices.isSubset(of: Set(BaseRateGrid.patternIndices)))
        XCTAssertEqual(BaseRateGrid.otherRoseIndices.count, 44)
        XCTAssertTrue(BaseRateGrid.otherRoseIndices.isDisjoint(with: Set(BaseRateGrid.patternIndices)))
        let captions = try loadCourses().allLessons.flatMap(\.blocks).compactMap { block -> String? in
            if case let .diagram(id, caption) = block, id == .baseRateGrid { return caption }
            return nil
        }
        XCTAssertFalse(captions.isEmpty, "a lesson uses the base-rate grid")
        for caption in captions {
            XCTAssertTrue(caption.contains("11") && caption.contains("20") && caption.contains("44") && caption.contains("80"),
                          "the caption quotes the drawn counts: \(caption)")
        }
    }

    // MARK: - Courses: editorial (same bar as the cards)

    func testCourseProseIsEducationalNotAdviceAndFresh() throws {
        let catalog = try loadCourses()
        let verificationYear = Int(catalog.verifiedOn.prefix(4)) ?? 0
        let year = try NSRegularExpression(pattern: "\\b(1[89]\\d{2}|20\\d{2})\\b")
        for course in catalog.courses {
            var texts = [course.title, course.summary]
            for lesson in course.lessons {
                texts += [lesson.title, lesson.summary]
                texts += lesson.blocks.flatMap(\.allText)
            }
            for text in texts {
                let lower = text.lowercased()
                for word in Self.staleTemporalWords {
                    XCTAssertFalse(lower.contains(word), "\(course.courseID) uses \"\(word)\": \(text.prefix(80))")
                }
                for phrase in Self.prohibitedAdvicePhrases {
                    XCTAssertFalse(lower.contains(phrase), "\(course.courseID) advice framing \"\(phrase)\": \(text.prefix(80))")
                }
                for name in Self.namedEntities {
                    XCTAssertFalse(lower.contains(name), "\(course.courseID) names \"\(name)\": \(text.prefix(80))")
                }
                for phrase in Self.predictionPhrases {
                    XCTAssertFalse(lower.contains(phrase), "\(course.courseID) predicts \"\(phrase)\": \(text.prefix(80))")
                }
                let range = NSRange(text.startIndex..., in: text)
                for match in year.matches(in: text, range: range) {
                    guard let r = Range(match.range, in: text), let y = Int(text[r]) else { continue }
                    XCTAssertLessThanOrEqual(y, verificationYear, "\(course.courseID) cites year \(y)")
                }
            }
        }
    }

    func testEveryLessonCitesAnApprovedCanonicalSourceVerifiedInThisPass() throws {
        let catalog = try loadCourses()
        let verifiedOn = try XCTUnwrap(Self.isoFormatter.date(from: catalog.verifiedOn))
        XCTAssertLessThanOrEqual(verifiedOn, Date())
        for lesson in catalog.allLessons {
            for source in lesson.sources {
                guard let url = URL(string: source.url) else {
                    XCTFail("\(lesson.lessonID) unparseable source \(source.url)"); continue
                }
                XCTAssertEqual(url.scheme, "https", lesson.lessonID)
                XCTAssertTrue(Self.approvedSourceHosts.contains(url.host ?? ""),
                              "\(lesson.lessonID) cites \(url.host ?? "?"), not an approved primary source")
                XCTAssertNil(url.query, lesson.lessonID)
                XCTAssertNil(url.fragment, lesson.lessonID)
                // Any recorded pass from the 1.1.4 course audit (2026-09-14) up to
                // the catalog's most recent pass.
                let verified = try XCTUnwrap(Self.isoFormatter.date(from: source.verificationDate), lesson.lessonID)
                XCTAssertTrue(source.verificationDate >= "2026-09-14" && verified <= verifiedOn, lesson.lessonID)
                let published = try XCTUnwrap(Self.isoFormatter.date(from: source.publicationDate), lesson.lessonID)
                XCTAssertLessThanOrEqual(published, verified, lesson.lessonID)
            }
        }
    }

    // MARK: - Courses: fail closed

    private func coursesJSONObject() throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle.curriculumBundle.url(forResource: CourseCatalog.resourceName, withExtension: "json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any])
    }

    private func assertCoursesRejected(_ description: String,
                                       file: StaticString = #filePath, line: UInt = #line,
                                       _ mutate: (inout [String: Any]) -> Void) throws {
        var object = try coursesJSONObject()
        mutate(&object)
        let data = try JSONSerialization.data(withJSONObject: object)
        let core = try loadCore()
        do {
            let broken = try JSONDecoder().decode(CourseCurriculum.self, from: data)
            XCTAssertThrowsError(try CourseCatalog.validate(broken, core: core),
                                 "validator accepted \(description)", file: file, line: line)
        } catch {
            // A decoding failure is also a rejection (the loader fails closed).
        }
    }

    private func mutateFirstLesson(_ object: inout [String: Any], _ change: (inout [String: Any]) -> Void) {
        guard var courses = object["courses"] as? [[String: Any]],
              var lessons = courses[0]["lessons"] as? [[String: Any]] else { return }
        change(&lessons[0])
        courses[0]["lessons"] = lessons
        object["courses"] = courses
    }

    func testValidatorRejectsALessonWithTwoQuizzes() throws {
        try assertCoursesRejected("two quizzes in one lesson") { object in
            mutateFirstLesson(&object) { lesson in
                guard var blocks = lesson["blocks"] as? [[String: Any]],
                      let quiz = blocks.first(where: { $0["type"] as? String == "quiz" }) else { return }
                blocks.insert(quiz, at: 0)
                lesson["blocks"] = blocks
            }
        }
    }

    func testValidatorRejectsAPreviewThatIsNotTheFirstLesson() throws {
        try assertCoursesRejected("a second free preview") { object in
            guard var courses = object["courses"] as? [[String: Any]],
                  var lessons = courses[0]["lessons"] as? [[String: Any]], lessons.count > 1 else { return }
            lessons[1]["isPreview"] = true
            courses[0]["lessons"] = lessons
            object["courses"] = courses
        }
    }

    func testValidatorRejectsAChartNotDeclaredSynthetic() throws {
        try assertCoursesRejected("a chart claiming real data") { object in
            guard var courses = object["courses"] as? [[String: Any]] else { return }
            outer: for ci in courses.indices {
                guard var lessons = courses[ci]["lessons"] as? [[String: Any]] else { continue }
                for li in lessons.indices {
                    guard var blocks = lessons[li]["blocks"] as? [[String: Any]] else { continue }
                    for bi in blocks.indices where blocks[bi]["type"] as? String == "chart" {
                        blocks[bi]["dataNote"] = "Daily closing prices from an exchange feed."
                        lessons[li]["blocks"] = blocks
                        courses[ci]["lessons"] = lessons
                        break outer
                    }
                }
            }
            object["courses"] = courses
        }
    }

    func testValidatorRejectsAnUnknownDiagramAndAnUnknownBlockType() throws {
        try assertCoursesRejected("an undrawable diagram id") { object in
            mutateFirstLesson(&object) { lesson in
                guard var blocks = lesson["blocks"] as? [[String: Any]] else { return }
                blocks.insert(["type": "diagram", "diagramID": "money-printer", "caption": "x"], at: 0)
                lesson["blocks"] = blocks
            }
        }
        try assertCoursesRejected("an unknown block type") { object in
            mutateFirstLesson(&object) { lesson in
                guard var blocks = lesson["blocks"] as? [[String: Any]] else { return }
                blocks.insert(["type": "video", "url": "https://example.invalid"], at: 0)
                lesson["blocks"] = blocks
            }
        }
    }

    func testValidatorRejectsALessonWithNoSources() throws {
        try assertCoursesRejected("a lesson with no sources") { object in
            mutateFirstLesson(&object) { $0["sources"] = [] }
        }
    }

    func testCourseLoaderThrowsWhenTheResourceIsMissing() throws {
        let core = try loadCore()
        XCTAssertThrowsError(try CourseCatalog.loadValidated(in: Bundle(for: ProCoursesBriefTests.self), core: core)) { error in
            guard case CurriculumError.resourceMissing = error else { return XCTFail("expected resourceMissing, got \(error)") }
        }
    }

    // MARK: - Course progress

    @MainActor
    func testCourseProgressCompletesOnceRecordsFirstQuizAnswerAndComputesCompletion() throws {
        let suite = "ProCoursesBriefTests.progress.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let course = try XCTUnwrap(loadCourses().courses.first)
        let progress = CourseProgressStore(defaults: defaults)
        let first = course.lessons[0], second = course.lessons[1]

        XCTAssertEqual(progress.completion(of: course), 0)
        XCTAssertEqual(progress.nextLesson(in: course)?.lessonID, first.lessonID)

        progress.recordQuiz(lessonID: first.lessonID, correct: false)
        progress.recordQuiz(lessonID: first.lessonID, correct: true)
        XCTAssertEqual(progress.quizResult(first.lessonID), false, "the first answer is the record")

        progress.markCompleted(lessonID: first.lessonID, courseID: course.courseID)
        progress.markCompleted(lessonID: first.lessonID, courseID: course.courseID)
        XCTAssertTrue(progress.isCompleted(first.lessonID))
        XCTAssertEqual(progress.completedCount(of: course), 1)
        XCTAssertEqual(progress.completion(of: course), 1.0 / Double(course.lessons.count), accuracy: 0.0001)
        XCTAssertEqual(progress.nextLesson(in: course)?.lessonID, second.lessonID)

        // Persisted: a fresh store over the same defaults sees the same state.
        let reloaded = CourseProgressStore(defaults: defaults)
        XCTAssertTrue(reloaded.isCompleted(first.lessonID))
        XCTAssertEqual(reloaded.quizResult(first.lessonID), false)
    }

    // MARK: - Daily Brief: sample + validation

    /// Phase 13: five bundled samples, one per recent U.S. business day, newest
    /// first, every one a validated sample with its own headline and concept.
    func testFiveBundledSampleBriefsCoverDistinctBusinessDaysNewestFirst() throws {
        let urls = DailyBrief.bundledSampleURLs()
        XCTAssertEqual(urls.count, 5, "five bundled sample briefs")
        for url in urls {
            XCTAssertNoThrow(try DailyBrief.decodeValidated(try Data(contentsOf: url)), url.lastPathComponent)
            XCTAssertEqual(url.deletingPathExtension().lastPathComponent,
                           DailyBrief.sampleResourcePrefix + (try DailyBrief.decodeValidated(try Data(contentsOf: url))).briefDate,
                           "the file name is the brief date")
        }
        let samples = DailyBrief.loadBundledSamples()
        XCTAssertEqual(samples.count, 5, "every bundled sample validates")
        XCTAssertEqual(samples.map(\.briefDate), samples.map(\.briefDate).sorted(by: >), "newest first")
        XCTAssertEqual(Set(samples.map(\.briefDate)).count, 5)
        XCTAssertEqual(Set(samples.map(\.headline)).count, 5, "each day has its own headline")
        XCTAssertEqual(Set(samples.compactMap { $0.section(.concept)?.conceptTitle }).count, 5, "each day teaches its own concept")
        let calendar = Calendar(identifier: .iso8601)
        for brief in samples {
            XCTAssertEqual(brief.isSample, true, brief.briefDate)
            let day = try XCTUnwrap(Self.isoFormatter.date(from: brief.briefDate))
            var utc = calendar; utc.timeZone = TimeZone(secondsFromGMT: 0)!
            XCTAssertFalse(utc.isDateInWeekend(day), "\(brief.briefDate) is a business day")
            let text = ([brief.headline, brief.methodology] + (brief.section(.released)?.items ?? []).flatMap {
                [$0.title ?? "", $0.summary ?? "", $0.meaning ?? ""]
            }).joined(separator: " ").lowercased()
            XCTAssertFalse(text.contains("every business day") || text.contains("every u.s. business day"),
                           "no publishing-cadence claim until the server job exists (\(brief.briefDate))")
            let released = try XCTUnwrap(brief.section(.released)?.items)
            XCTAssertTrue(released.allSatisfy { ($0.releaseDate ?? "") <= brief.briefDate },
                          "\(brief.briefDate) reports only releases already published")
        }
    }

    func testBundledSampleBriefLoadsAndCitesOnlyAllowedSources() throws {
        for brief in DailyBrief.loadBundledSamples() {
        XCTAssertEqual(brief.isSample, true, "the bundled brief must say it is a sample")
        XCTAssertNotNil(brief.section(.released))
        XCTAssertNotNil(brief.section(.scheduled))
        XCTAssertNotNil(brief.section(.concept))
        XCTAssertNotNil(brief.teaserItem)
        XCTAssertTrue(brief.disclaimer.localizedCaseInsensitiveContains("not investment advice"))
        XCTAssertTrue(brief.methodology.localizedCaseInsensitiveContains("primary sources"))
        for item in brief.section(.released)?.items ?? [] {
            let host = try XCTUnwrap(URL(string: try XCTUnwrap(item.source?.url))?.host)
            XCTAssertTrue(DailyBrief.allowedHosts.contains(host), host)
            XCTAssertFalse((item.figures ?? []).isEmpty, item.title ?? "")
        }
        for item in brief.section(.scheduled)?.items ?? [] {
            let host = try XCTUnwrap(URL(string: try XCTUnwrap(item.url))?.host)
            XCTAssertTrue(DailyBrief.allowedHosts.contains(host), host)
        }
        // The concept links a real card.
        let concept = try XCTUnwrap(brief.section(.concept))
        if let cardID = concept.linkedCardID {
            XCTAssertTrue(try loadCore().allCards.contains { $0.cardID == cardID }, cardID)
        }
        }
        XCTAssertFalse(DailyBrief.loadBundledSamples().isEmpty)
    }

    /// No news publisher can ever be an allowed brief source.
    func testBriefAllowedHostsAreOfficialOnly() {
        for host in DailyBrief.allowedHosts {
            XCTAssertTrue(host.hasSuffix(".gov") || host.hasSuffix(".org") || host.hasSuffix(".eu")
                          || host.hasSuffix(".uk") || host.hasSuffix(".ca") || host.hasSuffix(".int"), host)
            for banned in ["news", "times", "journal", "post", "reuters", "bloomberg", "cnbc", "yahoo"] {
                XCTAssertFalse(host.contains(banned), host)
            }
        }
    }

    private func sampleBriefJSON() throws -> [String: Any] {
        let url = try XCTUnwrap(DailyBrief.bundledSampleURLs().first)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any])
    }

    private func assertBriefRejected(_ description: String, file: StaticString = #filePath, line: UInt = #line,
                                     _ mutate: (inout [String: Any]) -> Void) throws {
        var object = try sampleBriefJSON()
        mutate(&object)
        let data = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try DailyBrief.decodeValidated(data), "accepted \(description)", file: file, line: line)
    }

    func testBriefValidatorRejectsANewsSourceAMissingDisclaimerAndAMissingSection() throws {
        try assertBriefRejected("a commercial news source") { object in
            guard var sections = object["sections"] as? [[String: Any]],
                  var items = sections[0]["items"] as? [[String: Any]],
                  var source = items[0]["source"] as? [String: Any] else { return }
            source["url"] = "https://www.example-news.com/markets/story"
            items[0]["source"] = source
            sections[0]["items"] = items
            object["sections"] = sections
        }
        try assertBriefRejected("a brief with no advice disclaimer") { $0["disclaimer"] = "Have a nice day." }
        try assertBriefRejected("a brief missing the scheduled section") { object in
            guard let sections = object["sections"] as? [[String: Any]] else { return }
            object["sections"] = sections.filter { $0["type"] as? String != "scheduled" }
        }
        try assertBriefRejected("a released item without figures") { object in
            guard var sections = object["sections"] as? [[String: Any]],
                  var items = sections[0]["items"] as? [[String: Any]] else { return }
            items[0]["figures"] = []
            sections[0]["items"] = items
            object["sections"] = sections
        }
    }

    // MARK: - Daily Brief: store (fail-soft fetch, cache)

    private final class StubURLProtocol: URLProtocol {
        nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            let (status, data) = Self.handler?(request) ?? (500, Data())
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    private func stubbedSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func temporaryCacheDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("brief-tests-\(UUID().uuidString)", isDirectory: true)
    }

    @MainActor
    func testBriefStoreFallsBackToTheBundledSampleWhenLatestIs404() async throws {
        StubURLProtocol.handler = { _ in (404, Data()) }
        let cache = temporaryCacheDirectory()
        defer { try? FileManager.default.removeItem(at: cache) }
        let store = BriefStore(session: stubbedSession(), cacheDirectory: cache)
        XCTAssertEqual(store.source, .bundled)
        XCTAssertEqual(store.latest?.isSample, true)
        XCTAssertEqual(store.history.count, 4, "the older bundled samples fill the archive")
        XCTAssertEqual(store.history.map(\.briefDate), store.history.map(\.briefDate).sorted(by: >))
        XCTAssertTrue(store.history.allSatisfy { $0.briefDate < (store.latest?.briefDate ?? "") })
        await store.refresh()
        XCTAssertEqual(store.source, .bundled, "a 404 keeps the sample on screen")
        XCTAssertEqual(store.latest?.isSample, true)
        XCTAssertNotNil(store.refreshNote)
        XCTAssertEqual(store.cachedDates, [], "nothing is cached from a 404")
    }

    @MainActor
    func testBriefStorePublishesAndCachesAValidatedNetworkBriefAndRejectsAnInvalidOne() async throws {
        var object = try sampleBriefJSON()
        object["briefDate"] = "2026-09-15"
        object["isSample"] = false
        object["headline"] = "A network brief"
        let good = try JSONSerialization.data(withJSONObject: object)
        StubURLProtocol.handler = { _ in (200, good) }
        let cache = temporaryCacheDirectory()
        defer { try? FileManager.default.removeItem(at: cache) }

        let store = BriefStore(session: stubbedSession(), cacheDirectory: cache)
        await store.refresh()
        XCTAssertEqual(store.source, .network)
        XCTAssertEqual(store.latest?.headline, "A network brief")
        XCTAssertNil(store.refreshNote)
        XCTAssertEqual(store.cachedDates, ["2026-09-15"])

        // A later document that fails validation never replaces the good one.
        var bad = object
        bad["disclaimer"] = "none"
        let badData = try JSONSerialization.data(withJSONObject: bad)
        StubURLProtocol.handler = { _ in (200, badData) }
        await store.refresh()
        XCTAssertEqual(store.latest?.headline, "A network brief")
        XCTAssertNotNil(store.refreshNote)

        // A fresh store over the same cache starts from the cached brief.
        let relaunched = BriefStore(session: stubbedSession(), cacheDirectory: cache)
        XCTAssertEqual(relaunched.source, .cache)
        XCTAssertEqual(relaunched.latest?.headline, "A network brief")
    }

    @MainActor
    func testBriefStoreKeepsOnlyTheNewestThirtyBriefs() async throws {
        let cache = temporaryCacheDirectory()
        defer { try? FileManager.default.removeItem(at: cache) }
        let base = try sampleBriefJSON()
        for day in 1...35 {
            var object = base
            object["briefDate"] = String(format: "2026-10-%02d", day)
            object["isSample"] = false
            let data = try JSONSerialization.data(withJSONObject: object)
            StubURLProtocol.handler = { _ in (200, data) }
            let store = BriefStore(session: stubbedSession(), cacheDirectory: cache)
            await store.refresh()
        }
        let store = BriefStore(session: stubbedSession(), cacheDirectory: cache)
        XCTAssertEqual(store.cachedDates.count, BriefStore.cacheLimit)
        XCTAssertEqual(store.cachedDates.first, "2026-10-35".replacingOccurrences(of: "35", with: "35"))
        XCTAssertEqual(store.cachedDates.last, "2026-10-06")
        XCTAssertEqual(store.latest?.briefDate, "2026-10-35".replacingOccurrences(of: "35", with: "35"))
        XCTAssertEqual(store.history.count, BriefStore.cacheLimit - 1)
    }

    // MARK: - Entitlement: Pro suppresses ads and opens core topics (D19)

    func testProEntitlementSuppressesAdsAndUnlocksCoreTopicsWithoutTouchingTheOneTimeFlags() {
        let pro = EconEntitlements(unlockAll: false, removeAds: false, pro: true)
        XCTAssertTrue(pro.adsSuppressed)
        XCTAssertTrue(pro.paidTopicsUnlocked)
        XCTAssertFalse(pro.unlockAll)
        XCTAssertFalse(pro.removeAds)

        let lapsed = EconEntitlements(unlockAll: false, removeAds: false, pro: false)
        XCTAssertFalse(lapsed.adsSuppressed)
        XCTAssertFalse(lapsed.paidTopicsUnlocked)

        // Verified truth wins, so a lapse takes effect at once.
        XCTAssertEqual(EconEntitlements.reconciled(cached: pro, verified: lapsed), lapsed)

        let decision = EconAdPolicy().decide(placement: .dailySetExit, state: EconAdState(),
                                             entitlements: pro, region: .allowed,
                                             setCompletedNormally: true, blockers: [],
                                             now: Date(), dayKey: "2026-09-14")
        XCTAssertEqual(decision, .suppressedEntitled, "a Pro subscriber is never shown an interstitial")
    }

    @MainActor
    func testProSubscriberNeverGetsTheAdSDKStartedOrTheTrackingPrompt() {
        let defaults = UserDefaults(suiteName: "ProCoursesBriefTests.ads.\(UUID().uuidString)")!
        let adapter = SpyAdapter()
        let monetization = EconMonetization(adapter: adapter, defaults: defaults, region: { .allowed },
                                            tracking: StubTracking())
        monetization.update(entitlements: EconEntitlements(pro: true))
        XCTAssertFalse(monetization.shouldRequestTrackingAuthorization)
        monetization.startAdsIfPermitted()
        XCTAssertFalse(monetization.didStartSDK)
        XCTAssertEqual(adapter.startCount, 0)
        XCTAssertFalse(monetization.canRequestAds)
    }

    @MainActor
    private final class SpyAdapter: EconInterstitialAdapting {
        var isAdLoaded = false
        var onAdDismissed: ((Bool) -> Void)?
        private(set) var startCount = 0
        func startSDK(policy: EconAdRequestPolicy) { startCount += 1 }
        func preload(policy: EconAdRequestPolicy) {}
        func discardLoadedAd() {}
        func present() async -> Bool { false }
    }

    private final class StubTracking: EconTrackingAuthorizing {
        var status: EconTrackingStatus = .notDetermined
        func requestAuthorization() async -> EconTrackingStatus { status }
    }

    // MARK: - Store contract: the subscription products exist in the local
    // StoreKit configuration exactly as the code names them (ASC is created later
    // from the same ids — no code change).

    func testStoreKitConfigurationCarriesTheProGroupWithFreeTrialsAndAllSixPacks() throws {
        let data = try Data(contentsOf: repoRoot().appendingPathComponent("EconByte.storekit"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let groups = try XCTUnwrap(object["subscriptionGroups"] as? [[String: Any]])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0]["name"] as? String, "EconByte Pro")
        let subscriptions = try XCTUnwrap(groups[0]["subscriptions"] as? [[String: Any]])
        XCTAssertEqual(Set(subscriptions.compactMap { $0["productID"] as? String }),
                       Set(PurchaseManager.ProductID.subscriptions.map(\.rawValue)))
        for sub in subscriptions {
            let offer = try XCTUnwrap(sub["introductoryOffer"] as? [String: Any], "\(sub["productID"] ?? "") has a trial")
            XCTAssertEqual(offer["paymentMode"] as? String, "free")
            XCTAssertEqual(offer["subscriptionPeriod"] as? String, "P1W", "one-week free trial")
            XCTAssertEqual(sub["type"] as? String, "RecurringSubscription")
        }
        let monthly = try XCTUnwrap(subscriptions.first { $0["productID"] as? String == PurchaseManager.ProductID.proMonthly.rawValue })
        XCTAssertEqual(monthly["recurringSubscriptionPeriod"] as? String, "P1M")
        XCTAssertEqual(monthly["displayPrice"] as? String, "4.99")
        let annual = try XCTUnwrap(subscriptions.first { $0["productID"] as? String == PurchaseManager.ProductID.proAnnual.rawValue })
        XCTAssertEqual(annual["recurringSubscriptionPeriod"] as? String, "P1Y")
        XCTAssertEqual(annual["displayPrice"] as? String, "29.99")

        let products = try XCTUnwrap(object["products"] as? [[String: Any]])
        let ids = Set(products.compactMap { $0["productID"] as? String })
        for pack in PurchaseManager.ProductID.packs {
            XCTAssertTrue(ids.contains(pack.rawValue), pack.rawValue)
        }
        // No "synced" keys: with them present the simulator ignores local products.
        let settings = try XCTUnwrap(object["settings"] as? [String: Any])
        XCTAssertNil(settings["_applicationInternalID"])
        XCTAssertNil(settings["_developerTeamID"])
    }

    func testPaywallLinksAreAppleStandardEULAAndDudleyPrivacy() {
        XCTAssertEqual(PurchaseManager.termsOfUseURL.absoluteString,
                       "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")
        XCTAssertEqual(PurchaseManager.privacyPolicyURL.absoluteString, "https://dudleyapps.com/privacy")
        XCTAssertEqual(PurchaseManager.manageSubscriptionsURL.absoluteString, "https://apps.apple.com/account/subscriptions")
    }

    // MARK: - Telemetry (plan §3.5)

    func testProEventsAreDeclaredBucketedAndRejectIdentifiers() {
        XCTAssertEqual(TelemetrySchema.allowedProperties["pro_paywall_shown_v1"], ["entry_point", "products_ready", "trial_eligible"])
        XCTAssertEqual(TelemetrySchema.allowedProperties["pro_trial_started_v1"], ["product_family"])
        XCTAssertEqual(TelemetrySchema.allowedProperties["pro_subscribed_v1"], ["product_family"])
        XCTAssertEqual(TelemetrySchema.allowedProperties["course_lesson_completed_v1"], ["course_family", "quiz_correct"])
        XCTAssertEqual(TelemetrySchema.allowedProperties["brief_opened_v1"], ["access_state", "brief_source"])

        XCTAssertEqual(TelemetryValidator.validate(TelemetryEvent("pro_paywall_shown_v1", [
            "entry_point": .string("course"), "products_ready": .bool(true), "trial_eligible": .bool(true),
        ])), .accepted)
        XCTAssertEqual(TelemetryValidator.validate(TelemetryEvent("pro_trial_started_v1", [
            "product_family": .string("pro_annual"),
        ])), .accepted)
        XCTAssertEqual(TelemetryValidator.validate(TelemetryEvent("course_lesson_completed_v1", [
            "course_family": .string("charts"), "quiz_correct": .bool(false),
        ])), .accepted)
        XCTAssertEqual(TelemetryValidator.validate(TelemetryEvent("brief_opened_v1", [
            "access_state": .string("locked"), "brief_source": .string("bundled"),
        ])), .accepted)

        for (event, property) in [("pro_subscribed_v1", "expiration_date"), ("pro_subscribed_v1", "price"),
                                  ("course_lesson_completed_v1", "lesson_id"), ("course_lesson_completed_v1", "quiz_answer"),
                                  ("brief_opened_v1", "headline"), ("brief_opened_v1", "brief_date")] {
            XCTAssertNotEqual(TelemetryValidator.validate(TelemetryEvent(event, [property: .string("x")])), .accepted,
                              "\(event) must reject \(property)")
        }
        XCTAssertNotEqual(TelemetryValidator.validate(TelemetryEvent("course_lesson_completed_v1", [
            "course_family": .string("investing-approaches"), "quiz_correct": .bool(true),
        ])), .accepted, "a raw course id is not a family")
    }

    func testCourseFamiliesCoverExactlyTheThreeCourses() throws {
        let ids = try loadCourses().courses.map(\.courseID)
        let families = ids.compactMap(EBCourseFamily.init(courseID:))
        XCTAssertEqual(families.count, 3)
        XCTAssertEqual(Set(families.map(\.rawValue)), TelemetrySchema.allowedValues["course_family"])
        XCTAssertNil(EBCourseFamily(courseID: "unknown-course"))
    }

    func testEveryProductFamilyHasAProduct() {
        let declared = TelemetrySchema.allowedValues["product_family"] ?? []
        let produced = Set(PurchaseManager.ProductID.allCases.map { $0.family.rawValue })
        XCTAssertEqual(declared, produced, "each declared product family maps to exactly one SKU family")
    }
}
