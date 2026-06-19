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

    /// Cold-launch helper — skips the ~4s Dudley studio intro so tests can
    /// interact with Home immediately (see StudioIntroView `-skipStudioIntro`).
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("-skipStudioIntro")
        app.launch()
        return app
    }

    private func tapStart(in app: XCUIApplication) {
        let start = app.buttons.containing(
            NSPredicate(format: "label CONTAINS 'Start'")
        ).firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 8))
        for _ in 0..<4 where !start.isHittable {
            app.swipeDown()
        }
        if !start.isHittable { app.swipeUp() }
        XCTAssertTrue(start.isHittable, "Start button should be tappable on Home")
        start.tap()
    }

    // MARK: - Home screen

    /// Smoke: the app launches and renders the home screen with the Today's Cards
    /// section and Browse Topics grid.
    func testHomeScreenSmoke() {
        let app = launchApp()

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
        let app = launchApp()

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
        let app = launchApp()

        XCTAssertTrue(app.navigationBars["EconByte"].waitForExistence(timeout: 5))

        tapStart(in: app)

        // Progress counter: "1 / 8" rendered by CardModeView nav bar.
        let counter = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS '/'")
        ).firstMatch
        XCTAssertTrue(counter.waitForExistence(timeout: 5),
                      "Progress counter (N / 8) should render in card mode")
    }

    /// Card mode close button (✕) dismisses and returns to Home.
    func testCardModeCloseReturnsHome() {
        let app = launchApp()

        XCTAssertTrue(app.navigationBars["EconByte"].waitForExistence(timeout: 5))
        tapStart(in: app)

        // Wait for card mode.
        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS '/'"))
                .firstMatch.waitForExistence(timeout: 5)
        )

        // Close button.
        let close = app.buttons["cardModeCloseButton"]
        XCTAssertTrue(close.waitForExistence(timeout: 8), "Close button should render in card mode")
        close.tap()

        // Back on Home.
        XCTAssertTrue(app.navigationBars["EconByte"].waitForExistence(timeout: 8),
                      "EconByte home should reappear after dismissing card mode")
    }

    /// Financial disclaimer renders on the front face of a card in card mode.
    func testCardDisclaimerRenders() {
        let app = launchApp()

        XCTAssertTrue(app.navigationBars["EconByte"].waitForExistence(timeout: 5))
        tapStart(in: app)

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
        let app = launchApp()

        XCTAssertTrue(app.navigationBars["EconByte"].waitForExistence(timeout: 5))

        // Gear button in navigation bar.
        let gear = app.buttons["settingsGearButton"]
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
        let app = launchApp()

        XCTAssertTrue(app.navigationBars["EconByte"].waitForExistence(timeout: 5))

        let bookmarks = app.buttons.containing(
            NSPredicate(format: "label CONTAINS 'Bookmarks'")
        ).firstMatch
        XCTAssertTrue(bookmarks.waitForExistence(timeout: 5),
                      "Bookmarks row should render on the home screen")
    }

    // MARK: - IAP / Paywall

    /// Tapping a locked topic opens the paywall with an Unlock All purchase button.
    func testLockedTopicOpensPaywall() {
        let app = launchApp()

        XCTAssertTrue(app.navigationBars["EconByte"].waitForExistence(timeout: 5))

        let lockedTopic = app.buttons["topic-gdp"]
        XCTAssertTrue(lockedTopic.waitForExistence(timeout: 8),
                      "Locked GDP topic tile should render on Home")
        for _ in 0..<3 where !lockedTopic.isHittable {
            app.swipeUp()
        }
        lockedTopic.tap()

        XCTAssertTrue(app.staticTexts["Unlock All Topics"].waitForExistence(timeout: 8),
                      "Paywall should open when a locked topic is tapped")

        let unlock = app.buttons["paywallUnlockButton"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 8),
                      "Unlock All purchase button should render on the paywall")
    }

    /// Settings → Unlock All Topics opens the same paywall sheet.
    func testSettingsUnlockAllOpensPaywall() {
        let app = launchApp()

        XCTAssertTrue(app.navigationBars["EconByte"].waitForExistence(timeout: 5))

        let gear = app.buttons["settingsGearButton"]
        XCTAssertTrue(gear.waitForExistence(timeout: 5))
        gear.tap()

        let unlockAll = app.buttons["settingsUnlockAllButton"]
        XCTAssertTrue(unlockAll.waitForExistence(timeout: 5),
                      "Unlock All Topics row should be tappable in Settings")
        unlockAll.tap()

        XCTAssertTrue(app.staticTexts["Unlock All Topics"].waitForExistence(timeout: 10),
                      "Settings Unlock All should present the paywall after Settings dismisses")
    }

    /// Settings shows a tappable Remove Ads purchase row.
    func testSettingsRemoveAdsButtonExists() {
        let app = launchApp()

        XCTAssertTrue(app.navigationBars["EconByte"].waitForExistence(timeout: 5))

        let gear = app.buttons["settingsGearButton"]
        XCTAssertTrue(gear.waitForExistence(timeout: 5))
        gear.tap()

        let removeAds = app.buttons["settingsRemoveAdsButton"]
        XCTAssertTrue(removeAds.waitForExistence(timeout: 5),
                      "Remove Ads purchase row should render in Settings")
    }
}
