import XCTest

/// 1.1.5 story lessons, end to end on the simulator (Phase 19): open a lesson,
/// move through beats with the Next button, a right-side tap, a left-side tap
/// and a swipe, answer a quick check, leave and come back to the same page,
/// finish on the recap (sources + not-advice notice), and go straight on to
/// the next lesson. Launched as a Pro reader so every lesson is readable.
final class StoryLessonUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launchPro() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-skipStudioIntro", "-EBSkipConsentPrompt", "-EBSkipPermissionPrompts",
                                "-econResetGrowthState", "-econDisableAds", "-econDebugPro", "-econBriefOffline"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["econWordmark"].waitForExistence(timeout: 20), "Home renders")
        return app
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func openCourse(_ courseID: String, in app: XCUIApplication) {
        let any = app.descendants(matching: .any)
        app.tabBars.buttons["Pro"].tap()
        let row = any["proCourseRow-\(courseID)"]
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        for _ in 0..<10 where !row.isHittable { app.swipeUp() }
        row.tap()
        XCTAssertTrue(any["course-\(courseID)"].waitForExistence(timeout: 15), "\(courseID) opens")
    }

    /// The story page on screen, from the `storyPage-N` container.
    private func currentPage(_ app: XCUIApplication) -> Int? {
        let page = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'storyPage-'")).firstMatch
        guard page.waitForExistence(timeout: 5) else { return nil }
        return Int(page.identifier.replacingOccurrences(of: "storyPage-", with: ""))
    }

    func testOpenAdvanceAnswerACheckLeaveResumeAndComplete() {
        let app = launchPro()
        let any = app.descendants(matching: .any)
        openCourse("investing-approaches", in: app)

        let row = any["lessonRow-ia-02"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(any["lesson-ia-02"].waitForExistence(timeout: 15), "the story opens full screen")
        XCTAssertEqual(currentPage(app), 0, "a new lesson opens on its cover")
        let bar = any["storyProgressBar"]
        XCTAssertTrue(bar.exists, "the segmented progress bar is on top")
        let total = Int((bar.value as? String ?? "").components(separatedBy: " of ").last ?? "") ?? 0
        XCTAssertGreaterThanOrEqual(total, 11, "cover + at least 10 beats")
        capture("story-01-cover")

        // Next button, right-side tap, left-side tap, swipe.
        let next = app.buttons["storyNextButton"]
        XCTAssertEqual(next.label, "Start")
        next.tap()
        XCTAssertEqual(currentPage(app), 1)
        capture("story-02-first-beat")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.45)).tap()
        XCTAssertEqual(currentPage(app), 2, "a tap on the right advances")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.45)).tap()
        XCTAssertEqual(currentPage(app), 1, "a tap on the left goes back")
        app.swipeLeft()
        XCTAssertEqual(currentPage(app), 2, "a swipe left advances")
        app.swipeRight()
        XCTAssertEqual(currentPage(app), 1, "a swipe right goes back")

        // On to the first quick check; answer it.
        let quiz = any["quiz"]
        for _ in 0..<total where !quiz.exists { next.tap() }
        XCTAssertTrue(quiz.waitForExistence(timeout: 5), "the story has a quick check")
        let checkPage = currentPage(app) ?? 0
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.2)).tap()
        XCTAssertEqual(currentPage(app), checkPage, "a stray tap does not skip an unanswered check")
        capture("story-03-check")
        app.buttons["quizChoice-0"].tap()
        XCTAssertTrue(any["quizExplanation"].waitForExistence(timeout: 5), "answering gives immediate feedback")
        capture("story-04-check-answered")
        next.tap()
        let resumeAt = currentPage(app) ?? 0
        XCTAssertEqual(resumeAt, checkPage + 1)

        // Leave and come back: the lesson reopens on the page the reader left.
        app.buttons["storyCloseButton"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue((row.value as? String ?? "").contains("in progress"), "the course list shows the lesson in progress")
        row.tap()
        XCTAssertTrue(any["lesson-ia-02"].waitForExistence(timeout: 15))
        XCTAssertEqual(currentPage(app), resumeAt, "a reopened lesson resumes on the page the reader left")
        capture("story-03b-resumed")

        // Finish: the recap completes the lesson and carries sources + notice.
        let complete = app.buttons["lessonCompleteButton"]
        for _ in 0..<total where !complete.exists { next.tap() }
        XCTAssertTrue(complete.waitForExistence(timeout: 5), "the last beat offers the next lesson")
        XCTAssertTrue(any["takeaways"].exists, "the last beat is the recap")
        XCTAssertTrue(any["educationalNotice"].exists, "the recap carries the not-advice notice")
        XCTAssertTrue(app.buttons["lessonSourcesButton"].exists, "the recap links the sources")
        capture("story-05-recap")
        app.buttons["lessonSourcesButton"].tap()
        XCTAssertTrue(any["lessonSourcesView"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["Done"].tap()

        XCTAssertEqual(complete.label, "Next lesson")
        complete.tap()
        XCTAssertTrue(any["lesson-ia-03"].waitForExistence(timeout: 10), "Next lesson opens the next story in place")
        XCTAssertEqual(currentPage(app), 0)
        app.buttons["storyCloseButton"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertEqual(row.value as? String, "completed", "reaching the recap completed the lesson")
    }
}
