import XCTest

/// 1.1.4 Phase 13 (content growth) evidence, launched as a Pro subscriber
/// (`-econDebugPro`, DEBUG only) so every topic, pack and lesson is readable:
/// a core topic and a pack topic that each open a 12-card deck, every diagram
/// added in Phase 13 rendering inside its lesson, a new lesson's chart and quiz
/// per course, and the News archive listing the five bundled sample briefs.
/// The attachments are the evidence screenshots; the assertions are the contract.
final class Phase13ContentEvidenceTests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launchPro() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-skipStudioIntro", "-EBSkipConsentPrompt", "-EBSkipPermissionPrompts",
                                "-econResetGrowthState", "-econDisableAds", "-econDebugPro"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["econWordmark"].waitForExistence(timeout: 20),
                      "Home renders")
        return app
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Scrolls down until the element is hittable; if it was passed on the way
    /// (a block that sits above the one just captured), scrolls back up for it.
    @discardableResult
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication, attempts: Int = 16) -> Bool {
        for _ in 0..<attempts {
            if element.exists && element.isHittable { return true }
            app.swipeUp()
        }
        for _ in 0..<(attempts * 2) {
            if element.exists && element.isHittable { return true }
            app.swipeDown()
        }
        return element.exists && element.isHittable
    }

    // MARK: - Topics with 12 cards

    func testCoreTopicAndPackTopicEachOpenATwelveCardDeck() {
        let app = launchPro()
        let any = app.descendants(matching: .any)
        app.tabBars.buttons["Browse"].tap()

        let gdp = any["topic-gdp"]
        XCTAssertTrue(gdp.waitForExistence(timeout: 15))
        XCTAssertTrue(scrollTo(gdp, in: app))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier == 'topic-gdp' AND label CONTAINS '/12'")).firstMatch.exists,
                      "the GDP tile counts 12 cards")
        capture("p13-browse-core-topics")
        gdp.tap()
        XCTAssertTrue(any["Card 1 of 12"].waitForExistence(timeout: 15), "the GDP deck has 12 cards")
        capture("p13-core-topic-gdp-12-cards")
        app.buttons["cardModeCloseButton"].tap()

        let packTopic = any["topic-stocks-bonds"]
        XCTAssertTrue(scrollTo(packTopic, in: app, attempts: 24), "a Pro reader sees the Markets pack's topics")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier == 'topic-stocks-bonds' AND label CONTAINS '/12'")).firstMatch.exists,
                      "the Stocks & Bonds tile counts 12 cards")
        capture("p13-pack-markets-topics")
        packTopic.tap()
        XCTAssertTrue(any["Card 1 of 12"].waitForExistence(timeout: 15), "the pack topic deck has 12 cards")
        capture("p13-pack-topic-stocks-bonds-12-cards")
    }

    // MARK: - New lessons: diagrams, charts, quizzes

    private func openLesson(_ lessonID: String, course courseID: String, in app: XCUIApplication) {
        let any = app.descendants(matching: .any)
        app.tabBars.buttons["Pro"].tap()
        let courseRow = any["proCourseRow-\(courseID)"]
        XCTAssertTrue(courseRow.waitForExistence(timeout: 15))
        XCTAssertTrue(scrollTo(courseRow, in: app))
        courseRow.tap()
        XCTAssertTrue(any["course-\(courseID)"].waitForExistence(timeout: 15), "\(courseID) opens")
        let row = any["lessonRow-\(lessonID)"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue(scrollTo(row, in: app), "\(lessonID) is listed")
        XCTAssertFalse((row.value as? String ?? "").contains("locked"), "\(lessonID) is readable with Pro")
        row.tap()
        XCTAssertTrue(any["lesson-\(lessonID)"].waitForExistence(timeout: 15), "\(lessonID) opens")
    }

    func testEveryPhase13DiagramRendersInItsLessonWithChartAndQuiz() {
        let lessons: [(course: String, lesson: String, diagram: String, labelPrefix: String, hasChart: Bool)] = [
            ("investing-approaches", "ia-08", "rebalance-bands", "Diagram of one category's share of a mix", true),
            ("reading-price-charts", "rpc-08", "trendline-anchors", "Diagram of a rising price path with three marked lows", true),
            ("reading-price-charts", "rpc-09", "base-rate-grid", "Diagram of 100 illustrative past cases", false),
            ("bonds-rates-yield-curve", "bry-07", "credit-spread-stack", "Diagram of three yield bars", true),
            ("bonds-rates-yield-curve", "bry-08", "breakeven-split", "Diagram of two yield bars for the same maturity", true),
        ]
        for entry in lessons {
            let app = launchPro()
            let any = app.descendants(matching: .any)
            openLesson(entry.lesson, course: entry.course, in: app)
            // DiagramView is one image element whose label describes the drawing
            // (`DiagramView.accessibilityDescription`); the wrapper identifier is not exposed.
            let diagram = app.images.matching(NSPredicate(format: "label BEGINSWITH %@", entry.labelPrefix)).firstMatch
            XCTAssertTrue(scrollTo(diagram, in: app), "\(entry.lesson) renders \(entry.diagram)")
            // Bring the whole drawing (and its caption) on screen before capturing.
            let window = app.windows.firstMatch.frame
            for _ in 0..<4 where diagram.frame.maxY > window.maxY * 0.72 {
                app.swipeUp(velocity: .slow)
            }
            XCTAssertTrue(diagram.isHittable, "\(entry.diagram) stays on screen")
            capture("p13-diagram-\(entry.diagram)-\(entry.lesson)")
            if entry.hasChart {
                let chart = any.matching(NSPredicate(format: "identifier BEGINSWITH 'chart-\(entry.lesson)' AND NOT identifier ENDSWITH '-note'")).firstMatch
                XCTAssertTrue(scrollTo(chart, in: app, attempts: 20), "\(entry.lesson) renders its chart")
                capture("p13-lesson-chart-\(entry.lesson)")
            }
            do {
                let quiz = any["quiz"]
                XCTAssertTrue(scrollTo(quiz, in: app, attempts: 20), "\(entry.lesson) has its quiz")
                app.buttons["quizChoice-0"].tap()
                XCTAssertTrue(any["quizExplanation"].waitForExistence(timeout: 10), "answering reveals the explanation")
                _ = scrollTo(any["quizExplanation"], in: app, attempts: 3)
                capture("p13-lesson-quiz-\(entry.lesson)")
            }
            app.terminate()
        }
    }

    // MARK: - News archive

    func testNewsArchiveListsTheFiveBundledBriefs() {
        let app = launchPro()
        let any = app.descendants(matching: .any)
        app.tabBars.buttons["News"].tap()
        XCTAssertTrue(any["briefHeadline"].waitForExistence(timeout: 15))
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'briefArchiveRow-'"))
        let first = rows.firstMatch
        XCTAssertTrue(scrollTo(first, in: app, attempts: 30), "the archive is on News")
        XCTAssertEqual(rows.count, 5, "the archive lists all five bundled briefs")
        capture("p13-news-archive-top")
        let last = rows.element(boundBy: rows.count - 1)
        _ = scrollTo(last, in: app, attempts: 6)
        app.swipeUp()
        capture("p13-news-archive-all-five")
        last.tap()
        XCTAssertTrue(app.buttons["briefCloseButton"].waitForExistence(timeout: 10), "an archived brief opens")
        capture("p13-news-archive-oldest-brief")
    }
}
