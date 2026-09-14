import XCTest

/// Captures the App Store screenshots from the release candidate itself, so the
/// storefront set is reproducible and provably fresh (design section 13.2
/// forbids synthetic or historical images).
///
/// Run with the Release configuration against a 6.9" iPhone simulator; the
/// attachments come out at the device's native 1320x2868 and are exported from
/// the result bundle into `AppStore/1.1/screenshots/`.
final class ScreenshotTests: XCTestCase {

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

    func testCaptureAppStoreScreenshots() {
        let app = XCUIApplication()
        app.launchArguments += ["-skipStudioIntro", "-EBSkipConsentPrompt"]
        app.launch()

        XCTAssertTrue(app.navigationBars["EconByte"].waitForExistence(timeout: 30),
                      "Home should render before capture")
        sleep(1)
        capture("01-home")

        // Topic grid: scroll far enough to show free and locked topics together.
        app.swipeUp()
        sleep(1)
        capture("02-topics")
        app.swipeDown()
        sleep(1)

        let start = app.buttons.containing(
            NSPredicate(format: "label CONTAINS 'Start' OR label CONTAINS 'Review'")
        ).firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        for _ in 0..<4 where !start.isHittable { app.swipeDown() }
        start.tap()

        let card = app.buttons.containing(
            NSPredicate(format: "label CONTAINS 'card 1 of'")
        ).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15), "Card mode should open")
        sleep(1)
        capture("03-card-front")

        // The bookmark control lives inside the combined card element, so it is
        // reachable here only by position (VoiceOver reaches it as a named
        // custom action).
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.873, dy: 0.20)).tap()
        sleep(1)

        card.tap() // flip to the sourced real-world example
        sleep(2)
        capture("04-card-back")

        // Complete the set.
        let next = app.buttons.containing(
            NSPredicate(format: "label CONTAINS 'Next'")
        ).firstMatch
        for _ in 0..<12 {
            guard next.exists, next.isHittable else { break }
            next.tap()
            usleep(400_000)
        }

        let done = app.buttons["sessionCompleteDoneButton"]
        XCTAssertTrue(done.waitForExistence(timeout: 15), "Session complete should render")
        sleep(1)
        capture("05-session-complete")

        done.tap()
        XCTAssertTrue(app.navigationBars["EconByte"].waitForExistence(timeout: 20))
        sleep(1)
        capture("06-home-streak")

        let bookmarks = app.buttons.containing(
            NSPredicate(format: "label CONTAINS 'Bookmarks'")
        ).firstMatch
        XCTAssertTrue(bookmarks.waitForExistence(timeout: 15))
        for _ in 0..<4 where !bookmarks.isHittable { app.swipeUp() }
        bookmarks.tap()
        XCTAssertTrue(app.navigationBars["Bookmarks"].waitForExistence(timeout: 15))
        sleep(1)
        capture("07-bookmarks")
    }
}
