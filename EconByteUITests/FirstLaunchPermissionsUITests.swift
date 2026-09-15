import XCTest

/// EconByte 1.1.3 build 16 — App Review Guideline 2.1 fix (2026-09-15).
///
/// App Review could not find build 15's ATT prompt (it was asked at a completed
/// set's exit, and only in some states). On a FRESH install build 16 must show
/// Apple's ATT prompt right after the studio intro — before any card, any set,
/// any ad — then Apple's notifications prompt, and map the answers.
///
/// Runs only when the harness sets `TEST_RUNNER_EB_FIRST_LAUNCH=allow|deny`
/// after `xcrun simctl uninstall <udid> com.nsantulli.econbyte` and
/// `xcrun simctl privacy <udid> reset all com.nsantulli.econbyte` on a booted
/// simulator — iOS shows each prompt once per install, so this cannot be part
/// of an ordinary run. `TEST_RUNNER_EB_DEVICE_TAG` names the screenshots.
///
/// The reminder switch proves the notifications mapping on screen. The
/// analytics and crash-report switches are captured but not asserted: a UI-test
/// process is unkeyed by `InstrumentationContext`, and 1.1.3's Settings shows
/// the live (unconfigured ⇒ off) facade state rather than the stored answer.
/// The ATT ⇒ analytics mapping is asserted in `FirstLaunchPermissionsTests`.
final class FirstLaunchPermissionsUITests: XCTestCase {

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

    private func waitForValue(_ element: XCUIElement, _ value: String, timeout: TimeInterval = 10) -> Bool {
        let predicate = NSPredicate(format: "value == %@", value)
        return XCTWaiter().wait(for: [expectation(for: predicate, evaluatedWith: element)],
                                timeout: timeout) == .completed
    }

    func testFreshLaunchShowsTrackingThenNotificationsBeforeAnythingElse() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let mode = environment["EB_FIRST_LAUNCH"], mode == "allow" || mode == "deny" else {
            throw XCTSkip("fresh-install prompt proof; run with TEST_RUNNER_EB_FIRST_LAUNCH=allow|deny")
        }
        let allow = mode == "allow"
        let tag = "\(environment["EB_DEVICE_TAG"] ?? "sim")-\(mode)"

        let app = XCUIApplication()
        // No -skipStudioIntro (the prompts must follow the intro), no skip
        // arguments, no -econDisableAds.
        app.launchArguments += ["-econResetGrowthState"]
        app.launch()
        sleep(1)
        capture("att-fix-00-intro-\(tag)")

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let att = springboard.alerts.containing(NSPredicate(format: "label CONTAINS[c] 'track'")).firstMatch
        XCTAssertTrue(att.waitForExistence(timeout: 40),
                      "Apple's ATT prompt appears after the intro, with no card opened and no set completed")
        XCTAssertFalse(springboard.alerts.containing(NSPredicate(format: "label CONTAINS[c] 'notifications'")).firstMatch.exists,
                       "ATT comes first")
        XCTAssertFalse(app.buttons["sessionCompleteDoneButton"].exists, "no session was needed")
        sleep(1)   // let the system alert finish animating in
        capture("att-fix-01-att-\(tag)")
        att.buttons[allow ? "Allow" : "Ask App Not to Track"].tap()

        let notifications = springboard.alerts.containing(NSPredicate(format: "label CONTAINS[c] 'notifications'")).firstMatch
        XCTAssertTrue(notifications.waitForExistence(timeout: 20), "Apple's notifications prompt follows")
        sleep(1)
        capture("att-fix-02-notifications-\(tag)")
        let target = allow
            ? notifications.buttons["Allow"]
            : notifications.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Don'")).firstMatch
        target.tap()

        XCTAssertTrue(app.navigationBars["EconByte"].waitForExistence(timeout: 15), "Home is usable")
        sleep(2)
        XCTAssertFalse(springboard.alerts.firstMatch.exists, "no further prompt")
        capture("att-fix-03-home-\(tag)")

        app.buttons["settingsGearButton"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        let reminders = app.switches["settingsRemindersToggle"]
        for _ in 0..<6 where !(reminders.exists && reminders.isHittable) { app.swipeUp() }
        XCTAssertTrue(waitForValue(reminders, allow ? "1" : "0"),
                      "notifications \(mode) ⇒ daily reminder \(allow ? "on" : "off")")
        capture("att-fix-04-settings-reminder-\(tag)")
        let analytics = app.switches["settingsAnalyticsToggle"]
        for _ in 0..<8 where !(analytics.exists && analytics.isHittable) { app.swipeUp() }
        capture("att-fix-05-settings-privacy-\(tag)")
    }
}
