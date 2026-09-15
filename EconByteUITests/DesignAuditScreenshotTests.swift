import XCTest

/// 1.1.5 design-system audit evidence (Phase 19): walks every top-level
/// surface and the main sheets, capturing one screenshot per state as a kept
/// attachment. The same walk runs against the 1.1.4 code ("before") and the
/// 1.1.5 code ("after"), in system light and dark and at an accessibility text
/// size, so the audit compares like with like.
///
/// Environment (passed as `TEST_RUNNER_…` to xcodebuild):
///   AUDIT_TAG           prefix for every attachment name (e.g. "after-dark")
///   AUDIT_CONTENT_SIZE  a UIContentSizeCategory name to launch with (optional)
///
/// The walk asserts only that each surface opened; layout contracts live in the
/// other suites.
final class DesignAuditScreenshotTests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    private var tag: String { ProcessInfo.processInfo.environment["AUDIT_TAG"] ?? "audit" }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-skipStudioIntro", "-EBSkipConsentPrompt", "-EBSkipPermissionPrompts",
                                "-econResetGrowthState", "-econDisableAds", "-econBriefOffline",
                                "-econTrackingAnswered"] + extra
        if let size = ProcessInfo.processInfo.environment["AUDIT_CONTENT_SIZE"], !size.isEmpty {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", size]
        }
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["econWordmark"].waitForExistence(timeout: 30), "Home renders")
        return app
    }

    private func capture(_ name: String) {
        usleep(600_000)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "\(tag)-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @discardableResult
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication, attempts: Int = 14) -> Bool {
        for _ in 0..<attempts {
            if element.exists && element.isHittable { return true }
            app.swipeUp()
        }
        return element.exists && element.isHittable
    }

    private func closeSheet(_ app: XCUIApplication) {
        for id in ["Done", "Close"] where app.navigationBars.buttons[id].exists {
            app.navigationBars.buttons[id].firstMatch.tap()
            return
        }
        app.swipeDown(velocity: .fast)
    }

    /// Free reader, trial-eligible prices: every tab, the paywalls, Settings,
    /// a card session and the free preview lesson.
    func testWalkFreeReader() {
        let app = launch(["-econDebugStore", "eligible"])
        let any = app.descendants(matching: .any)

        capture("01-home-top")
        app.swipeUp(); capture("02-home-scrolled")
        app.swipeUp(); app.swipeUp(); capture("03-home-bottom")

        app.tabBars.buttons["Browse"].tap()
        capture("04-browse-top")
        let bundle = any["packBundle"]
        _ = scrollTo(bundle, in: app, attempts: 10)
        capture("05-browse-packs")
        app.swipeUp(); capture("06-browse-pack-card")

        app.tabBars.buttons["News"].tap()
        capture("07-news-top")
        app.swipeUp(); app.swipeUp(); capture("08-news-lock")

        app.tabBars.buttons["Pro"].tap()
        capture("09-pro-top")
        app.swipeUp(); capture("10-pro-courses")
        app.swipeUp(); app.swipeUp(); capture("11-pro-legal")

        // Settings sheet.
        app.tabBars.buttons["Home"].tap()
        app.buttons["settingsGearButton"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        capture("12-settings-top")
        app.swipeUp(); capture("13-settings-middle")
        app.swipeUp(); app.swipeUp(); capture("14-settings-bottom")

        // Pro paywall cover from Settings.
        app.swipeDown(); app.swipeDown(); app.swipeDown()
        let settingsPro = app.buttons["settingsProButton"]
        if settingsPro.waitForExistence(timeout: 5) {
            settingsPro.tap()
            if app.buttons["proPaywallCloseButton"].waitForExistence(timeout: 15) {
                capture("15-paywall-cover")
                app.swipeUp(); app.swipeUp(); capture("16-paywall-cover-legal")
                app.buttons["proPaywallCloseButton"].tap()
            }
        } else {
            closeSheet(app)
        }

        // Unlock All paywall from a locked core topic.
        app.tabBars.buttons["Browse"].tap()
        app.swipeDown(); app.swipeDown()
        let gdp = any["topic-gdp"]
        if scrollTo(gdp, in: app, attempts: 6) {
            gdp.tap()
            if app.buttons["paywallCloseButton"].waitForExistence(timeout: 10) {
                capture("17-unlock-all-paywall")
                app.buttons["paywallCloseButton"].tap()
            }
        }

        // Bookmarks (empty state).
        app.swipeDown(); app.swipeDown(); app.swipeDown()
        let bookmarks = app.buttons["browseBookmarksRow"]
        if bookmarks.waitForExistence(timeout: 5) {
            bookmarks.tap()
            if app.navigationBars["Bookmarks"].waitForExistence(timeout: 10) {
                capture("18-bookmarks-empty")
                closeSheet(app)
            }
        }

        // A card session: front, back.
        app.tabBars.buttons["Home"].tap()
        app.swipeDown(); app.swipeDown()
        let start = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Start' OR label CONTAINS 'Review'")).firstMatch
        if start.waitForExistence(timeout: 10) {
            start.tap()
            let card = app.buttons.containing(NSPredicate(format: "label CONTAINS 'card 1 of'")).firstMatch
            if card.waitForExistence(timeout: 15) {
                capture("19-card-front")
                card.tap()
                sleep(1)
                capture("20-card-back")
            }
            if app.buttons["cardModeCloseButton"].exists { app.buttons["cardModeCloseButton"].tap() }
        }

        // The free preview lesson, from the Pro tab's course list.
        app.tabBars.buttons["Pro"].tap()
        let courseRow = any["proCourseRow-investing-approaches"]
        if scrollTo(courseRow, in: app, attempts: 10) {
            courseRow.tap()
            if any["course-investing-approaches"].waitForExistence(timeout: 15) {
                capture("21-course")
                any["lessonRow-ia-01"].tap()
                if any["lesson-ia-01"].waitForExistence(timeout: 15) {
                    capture("22-lesson-1")
                    walkLesson(app, prefix: "23-lesson", steps: 5)
                }
            }
        }
    }

    /// Pro reader: the subscriber paywall state and the unlocked brief.
    func testWalkProReader() {
        let app = launch(["-econDebugStore", "subscribed", "-econDebugPro"])
        app.tabBars.buttons["Pro"].tap()
        capture("30-pro-subscriber")
        app.tabBars.buttons["News"].tap()
        capture("31-news-pro")
        app.swipeUp(); app.swipeUp(); capture("32-news-pro-scrolled")
    }

    /// Advances through a lesson. A story lesson (1.1.5) advances with its Next
    /// control; an article lesson (1.1.4) scrolls.
    private func walkLesson(_ app: XCUIApplication, prefix: String, steps: Int) {
        let next = app.buttons["storyNextButton"]
        for step in 1...steps {
            if next.exists {
                next.tap()
            } else {
                app.swipeUp()
            }
            capture("\(prefix)-\(step)")
        }
    }
}
