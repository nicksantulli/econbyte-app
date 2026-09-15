import XCTest

/// EconByte 1.1.4 shell redesign (Phase 10) — rendered proof and evidence:
/// the four tabs, the fixed wordmark header (same frame while content scrolls
/// and on every tab), Settings, and — on a fresh install only — Apple's ATT
/// prompt then the notifications prompt, with Allow mapped onto analytics and
/// the daily reminder.
final class ShellRedesignTests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-skipStudioIntro", "-EBSkipPermissionPrompts",
                                "-econResetGrowthState", "-econDisableAds"] + extra
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["econWordmark"].waitForExistence(timeout: 20),
                      "the wordmark bar renders on launch")
        return app
    }

    private func waitForValue(_ element: XCUIElement, _ value: String, timeout: TimeInterval = 10) -> Bool {
        let predicate = NSPredicate(format: "value == %@", value)
        return XCTWaiter().wait(for: [expectation(for: predicate, evaluatedWith: element)], timeout: timeout) == .completed
    }

    // MARK: - Tabs, header, Settings

    func testTabsFixedHeaderAndSettings() {
        let app = launch()
        let any = app.descendants(matching: .any)
        let wordmark = any["econWordmark"]
        XCTAssertEqual(wordmark.label, "EconByte", "the wordmark reads as the app name")
        XCTAssertFalse(app.navigationBars["EconByte"].exists, "no large/inline navigation title any more")
        for tab in ["Home", "Browse", "News", "Pro"] {
            XCTAssertTrue(app.tabBars.buttons[tab].exists, "\(tab) tab")
        }

        // Home, at rest and scrolled: the wordmark's frame never changes.
        XCTAssertTrue(app.buttons["homeGroceryLine"].waitForExistence(timeout: 10))
        let atRest = wordmark.frame
        XCTAssertLessThan(atRest.minX, 40, "the wordmark sits at the top left")
        capture("p10-01-home")
        app.swipeUp()
        sleep(1)
        XCTAssertEqual(wordmark.frame, atRest, "same size and position while the content scrolls")
        capture("p10-02-home-scrolled")
        app.swipeUp()
        sleep(1)
        XCTAssertEqual(wordmark.frame, atRest)
        XCTAssertTrue(any["homeCourseCard"].exists, "Home shows the course card")
        capture("p10-03-home-bottom")

        // Browse.
        app.tabBars.buttons["Browse"].tap()
        XCTAssertTrue(app.buttons["topic-gdp"].waitForExistence(timeout: 10), "core topics are on Browse")
        XCTAssertEqual(wordmark.frame, atRest, "same position on every tab")
        capture("p10-04-browse")
        app.swipeUp()
        app.swipeUp()
        sleep(1)
        XCTAssertEqual(wordmark.frame, atRest)
        capture("p10-05-browse-packs")
        for _ in 0..<3 { app.swipeDown() }
        let search = app.textFields["browseSearchField"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("inflation")
        XCTAssertTrue(any.matching(NSPredicate(format: "identifier BEGINSWITH 'browseCardResult-'"))
                        .firstMatch.waitForExistence(timeout: 10), "search finds cards by title")
        capture("p10-06-browse-search")
        app.buttons["browseSearchClearButton"].tap()
        // Dismiss the keyboard (it covers the tab bar) by scrolling the page.
        app.swipeDown()
        XCTAssertTrue(app.tabBars.buttons["News"].waitForExistence(timeout: 5)
                        && app.tabBars.buttons["News"].isHittable, "the tab bar is reachable again")

        // News.
        app.tabBars.buttons["News"].tap()
        XCTAssertTrue(any["briefHeadline"].waitForExistence(timeout: 10), "the brief is on News")
        XCTAssertEqual(wordmark.frame, atRest)
        capture("p10-07-news")
        app.swipeUp()
        sleep(1)
        XCTAssertEqual(wordmark.frame, atRest)
        capture("p10-08-news-scrolled")

        // Pro (not subscribed): the paywall inline, then the courses.
        app.tabBars.buttons["Pro"].tap()
        XCTAssertTrue(app.buttons["proPaywallSubscribeButton"].waitForExistence(timeout: 15))
        XCTAssertEqual(wordmark.frame, atRest)
        capture("p10-09-pro")
        let course = any["proCourseRow-investing-approaches"]
        for _ in 0..<6 where !(course.exists && course.isHittable) { app.swipeUp() }
        XCTAssertTrue(course.exists, "courses with a free first lesson are on the Pro tab")
        capture("p10-10-pro-courses")
        let terms = any["proPaywallTermsLink"]
        for _ in 0..<6 where !(terms.exists && terms.isHittable) { app.swipeUp() }
        XCTAssertTrue(terms.exists && any["proPaywallPrivacyLink"].exists, "3.1.2 links on the inline paywall")
        capture("p10-11-pro-terms")

        // Settings, from the gear in the shared bar.
        app.buttons["settingsGearButton"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        sleep(1)
        capture("p10-12-settings-1")
        app.swipeUp()
        sleep(1)
        capture("p10-13-settings-2")
        app.swipeUp()
        sleep(1)
        capture("p10-14-settings-3")
        for id in ["settingsEducationalNotice", "settingsSupportLink", "settingsRateButton", "settingsVersionRow"] {
            XCTAssertTrue(any[id].exists, "About keeps \(id)")
        }
        let sources = app.buttons["settingsSourcesButton"]
        for _ in 0..<4 where !(sources.exists && sources.isHittable) { app.swipeUp() }
        sources.tap()
        XCTAssertTrue(app.navigationBars["Sources & editorial policy"].waitForExistence(timeout: 10))
        sleep(1)
        capture("p10-15-sources-policy")
    }

    func testSubscriberShell() {
        let app = launch(["-econDebugPro"])
        let any = app.descendants(matching: .any)
        XCTAssertTrue(any["homeCourseCard"].waitForExistence(timeout: 10))
        capture("p10-20-pro-home")
        app.tabBars.buttons["Pro"].tap()
        XCTAssertTrue(any["proActiveBadge"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["proPaywallSubscribeButton"].exists)
        capture("p10-21-pro-tab-subscriber")
        app.tabBars.buttons["News"].tap()
        XCTAssertTrue(any["briefHeadline"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["briefLockedProButton"].exists)
        capture("p10-22-news-subscriber")
        app.buttons["settingsGearButton"].tap()
        XCTAssertTrue(any["settingsProStatusRow"].waitForExistence(timeout: 10))
        sleep(1)
        capture("p10-23-settings-subscriber")
    }

    // MARK: - First launch: the two system prompts

    /// Runs only when the harness sets `TEST_RUNNER_EB_FIRST_LAUNCH=allow|deny`
    /// after uninstalling the app and `xcrun simctl privacy <udid> reset all
    /// com.nsantulli.econbyte` — iOS shows each prompt once per install, so this
    /// cannot be part of an ordinary run.
    func testFirstLaunchAsksTrackingThenNotificationsAndMapsTheAnswers() throws {
        guard let mode = ProcessInfo.processInfo.environment["EB_FIRST_LAUNCH"],
              mode == "allow" || mode == "deny" else {
            throw XCTSkip("fresh-install prompt proof; run with TEST_RUNNER_EB_FIRST_LAUNCH=allow|deny")
        }
        let allow = mode == "allow"
        let app = XCUIApplication()
        // No -skipStudioIntro (the prompts must follow the intro), no
        // -econDisableAds (an ad-restricted region is never shown ATT).
        app.launchArguments += ["-econResetGrowthState"]
        app.launch()
        sleep(1)
        capture("p10-first-00-intro-\(mode)")

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let att = springboard.alerts.containing(NSPredicate(format: "label CONTAINS[c] 'track'")).firstMatch
        XCTAssertTrue(att.waitForExistence(timeout: 40), "Apple's ATT prompt appears after the intro")
        XCTAssertFalse(springboard.alerts.containing(NSPredicate(format: "label CONTAINS[c] 'notifications'")).firstMatch.exists,
                       "ATT comes first")
        sleep(1)   // let the system alert finish animating in
        capture("p10-first-01-att-\(mode)")
        att.buttons[allow ? "Allow" : "Ask App Not to Track"].tap()

        let notifications = springboard.alerts.containing(NSPredicate(format: "label CONTAINS[c] 'notifications'")).firstMatch
        XCTAssertTrue(notifications.waitForExistence(timeout: 20), "Apple's notifications prompt follows")
        sleep(1)
        capture("p10-first-02-notifications-\(mode)")
        let buttons = notifications.buttons
        let target = allow ? buttons["Allow"] : buttons.matching(NSPredicate(format: "label BEGINSWITH 'Don'")).firstMatch
        target.tap()

        let any = app.descendants(matching: .any)
        XCTAssertTrue(any["econWordmark"].waitForExistence(timeout: 15))
        sleep(2)
        XCTAssertFalse(springboard.alerts.firstMatch.exists, "no further prompt")
        capture("p10-first-03-home-\(mode)")

        app.buttons["settingsGearButton"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        let expected = allow ? "1" : "0"
        let reminders = app.switches["settingsRemindersToggle"]
        for _ in 0..<6 where !(reminders.exists && reminders.isHittable) { app.swipeUp() }
        XCTAssertTrue(waitForValue(reminders, expected), "notifications \(mode) ⇒ reminder \(expected)")
        let analytics = app.switches["settingsAnalyticsToggle"]
        for _ in 0..<6 where !(analytics.exists && analytics.isHittable) { app.swipeUp() }
        XCTAssertTrue(waitForValue(analytics, expected), "ATT \(mode) ⇒ analytics \(expected)")
        XCTAssertTrue(waitForValue(app.switches["settingsDiagnosticsToggle"], expected),
                      "ATT \(mode) ⇒ crash reports \(expected)")
        capture("p10-first-04-settings-\(mode)")
    }
}
