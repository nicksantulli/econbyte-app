import XCTest

/// End-to-end UI smoke coverage for EconByte, so core-loop regressions are
/// catchable headlessly via `xcodebuild test`.
///
/// No launch-arg harness is wired for EconByte (all content is bundle-resident
/// and loads synchronously), so these tests drive the real app flow from cold
/// launch. All tests set `continueAfterFailure = false`.
final class EconByteUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    // MARK: - Home screen

    /// Smoke: the app launches and renders the home screen with the Today's Cards
    /// section and Browse Topics grid.
    func testHomeScreenSmoke() {
        let app = XCUIApplication()
        app.launch()

        // Navigation title.
        XCTAssertTrue(app.navigationBars["EconByte"].waitForExistence(timeout: 5),
                      "EconByte navigation title should render on the home screen")

        // Today's Cards section and Start button.
        let start = app.buttons.containing(
            NSPredicate(format: "label CONTAINS 'Start'")
        ).firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 5),
                      "Start button for Today's Cards should render on the home screen")
    }

    /// Browse Topics grid shows at least one topic tile after launch.
    func testBrowseTopicsGridRenders() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.navigationBars["EconByte"].waitForExistence(timeout: 5))

        // 10 topic tiles render in the grid. We assert at least one
        // to stay resilient to content shuffles.
        let buttons = app.buttons.allElementsBoundByIndex
        XCTAssertGreaterThan(buttons.count, 2,
                             "At least one topic tile (plus Start + gear) should render on Home")
    }

    // MARK: - Card mode

    /// Tapping "Start →" opens card mode with a progress counter visible.
    func testTodaysCardsCardModeOpens() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.navigationBars["EconByte"].waitForExistence(timeout: 5))

        let start = app.buttons.containing(
            NSPredicate(format: "label CONTAINS 'Start'")
        ).firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()

        // Progress counter: "1 / 8" rendered by CardModeView nav bar.
        let counter = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS '/'")
        ).firstMatch
        XCTAssertTrue(counter.waitForExistence(timeout: 5),
                      "Progress counter (N / 8) should render in card mode")
    }

    /// Card mode close button (✕) dismisses and returns to Home.
    func testCardModeCloseReturnsHome() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.navigationBars["EconByte"].waitForExistence(timeout: 5))
        app.buttons.containing(NSPredicate(format: "label CONTAINS 'Start'")).firstMatch.tap()

        // Wait for card mode.
        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS '/'"))
                .firstMatch.waitForExistence(timeout: 5)
        )

        // Close button.
        let close = app.buttons["✕"]
        XCTAssertTrue(close.waitForExistence(timeout: 3), "Close (✕) button should render in card mode")
        close.tap()

        // Back on Home.
        XCTAssertTrue(app.navigationBars["EconByte"].waitForExistence(timeout: 5),
                      "EconByte home should reappear after dismissing card mode")
    }

    /// Financial disclaimer renders on the front face of a card in card mode.
    func testCardDisclaimerRenders() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.navigationBars["EconByte"].waitForExistence(timeout: 5))
        app.buttons.containing(NSPredicate(format: "label CONTAINS 'Start'")).firstMatch.tap()

        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS '/'"))
                .firstMatch.waitForExistence(timeout: 5)
        )

        // Disclaimer text on card front face.
        let disclaimer = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS 'not financial'")
        ).firstMatch
        XCTAssertTrue(disclaimer.waitForExistence(timeout: 5),
                      "Financial disclaimer should render on the front face of every card")
    }

    // MARK: - Settings

    /// Settings sheet opens from the gear button and shows the Privacy Policy link.
    func testSettingsSheetOpensWithPrivacyLink() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.navigationBars["EconByte"].waitForExistence(timeout: 5))

        // Gear button in navigation bar.
        let gear = app.buttons.containing(
            NSPredicate(format: "label CONTAINS 'gearshape' OR label CONTAINS 'Settings'")
        ).firstMatch
        XCTAssertTrue(gear.waitForExistence(timeout: 5), "Settings gear should render in the nav bar")
        gear.tap()

        // Privacy Policy link (§5.1).
        let privacy = app.buttons.containing(
            NSPredicate(format: "label CONTAINS 'Privacy'")
        ).firstMatch
        XCTAssertTrue(privacy.waitForExistence(timeout: 4),
                      "Privacy Policy link should appear in Settings")
        XCTAssertTrue(privacy.isEnabled,
                      "Privacy Policy link should be enabled (tappable)")
    }

    // MARK: - Bookmarks

    /// Bookmarks row renders on Home screen.
    func testBookmarksRowRenders() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.navigationBars["EconByte"].waitForExistence(timeout: 5))

        let bookmarks = app.buttons.containing(
            NSPredicate(format: "label CONTAINS 'Bookmarks'")
        ).firstMatch
        XCTAssertTrue(bookmarks.waitForExistence(timeout: 5),
                      "Bookmarks row should render on the home screen")
    }
}
