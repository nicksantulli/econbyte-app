import XCTest

/// Phase 24 evidence walk (not a behavior gate): screenshots of every lesson's
/// centerpiece picture and full walks of three sample lessons (every beat, the
/// answered check and the recap), plus the course and Pro screens. Run it once
/// at the default text size and once with the simulator's own text size set to
/// the largest accessibility size (`simctl ui … content_size`; iOS 26 ignores
/// the launch argument). Attachments are exported from the result bundle.
final class ProPolishEvidenceTests: XCTestCase {

    private static let courses: [(id: String, lessons: [String])] = [
        ("investing-approaches", (1...9).map { String(format: "ia-%02d", $0) }),
        ("reading-price-charts", (1...9).map { String(format: "rpc-%02d", $0) }),
        ("bonds-rates-yield-curve", (1...9).map { String(format: "bry-%02d", $0) }),
    ]

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    private func launchPro() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-skipStudioIntro", "-EBSkipConsentPrompt", "-EBSkipPermissionPrompts",
                                "-econResetGrowthState", "-econDisableAds", "-econDebugPro", "-econBriefOffline"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["econWordmark"].waitForExistence(timeout: 20))
        return app
    }

    private var sizeTag: String {
        ProcessInfo.processInfo.environment["P24_SIZE_TAG"] ?? "default"
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "p24-\(sizeTag)-\(name)"
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
        XCTAssertTrue(any["course-\(courseID)"].waitForExistence(timeout: 15))
    }

    private func openLesson(_ lessonID: String, in app: XCUIApplication) -> Bool {
        let any = app.descendants(matching: .any)
        let row = any["lessonRow-\(lessonID)"]
        guard row.waitForExistence(timeout: 10) else { return false }
        for _ in 0..<12 where !row.isHittable { app.swipeUp() }
        row.tap()
        return any["lesson-\(lessonID)"].waitForExistence(timeout: 15)
    }

    private func page(_ app: XCUIApplication) -> Int {
        let node = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'storyPage-'")).firstMatch
        _ = node.waitForExistence(timeout: 5)
        return Int(node.identifier.replacingOccurrences(of: "storyPage-", with: "")) ?? -1
    }

    private func pageCount(_ app: XCUIApplication) -> Int {
        let bar = app.descendants(matching: .any)["storyProgressBar"]
        _ = bar.waitForExistence(timeout: 5)
        return Int((bar.value as? String ?? "").components(separatedBy: " of ").last ?? "") ?? 0
    }

    private func goToCover(_ app: XCUIApplication) {
        let back = app.buttons["storyBackButton"]
        for _ in 0..<40 where back.exists { back.tap() }
    }

    func testCenterpieceOfEveryLesson() {
        let app = launchPro()
        let any = app.descendants(matching: .any)
        for course in Self.courses {
            openCourse(course.id, in: app)
            for lessonID in course.lessons {
                guard openLesson(lessonID, in: app) else { XCTFail("\(lessonID) did not open"); continue }
                goToCover(app)
                let total = pageCount(app)
                let centerpiece = any["storyCenterpiece"]
                let next = app.buttons["storyNextButton"]
                for _ in 0..<total where !centerpiece.exists && next.exists { next.tap() }
                if centerpiece.waitForExistence(timeout: 3) {
                    capture("\(lessonID)-centerpiece-p\(page(app))")
                } else {
                    XCTFail("\(lessonID): no centerpiece found")
                }
                app.buttons["storyCloseButton"].tap()
            }
            app.buttons["courseCloseButton"].tap()
        }
    }

    func testSampleLessonWalksAndCourseScreens() {
        let app = launchPro()
        let any = app.descendants(matching: .any)
        app.tabBars.buttons["Pro"].tap()
        _ = any["proCourseRow-investing-approaches"].waitForExistence(timeout: 15)
        capture("pro-tab-top")
        for (courseID, lessonID) in [("investing-approaches", "ia-06"), ("reading-price-charts", "rpc-04"), ("bonds-rates-yield-curve", "bry-07")] {
            openCourse(courseID, in: app)
            capture("\(courseID)-detail")
            guard openLesson(lessonID, in: app) else { XCTFail("\(lessonID) did not open"); continue }
            goToCover(app)
            let total = pageCount(app)
            for index in 0..<total {
                let current = page(app)
                capture("\(lessonID)-page\(String(format: "%02d", current))")
                let quiz = any["quiz"]
                if quiz.exists, app.buttons["quizChoice-0"].exists, !any["quizExplanation"].exists {
                    app.buttons["quizChoice-1"].tap()
                    _ = any["quizExplanation"].waitForExistence(timeout: 5)
                    sleep(1)
                    capture("\(lessonID)-page\(String(format: "%02d", current))-answered")
                }
                guard index < total - 1, app.buttons["storyNextButton"].exists else { break }
                app.buttons["storyNextButton"].tap()
            }
            app.buttons["storyCloseButton"].tap()
            capture("\(courseID)-detail-after")
            app.buttons["courseCloseButton"].tap()
        }
    }
}
