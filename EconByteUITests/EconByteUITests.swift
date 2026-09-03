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

    // MARK: - Grocery highlight (v1.1.1)

    /// Success criterion: the sourced grocery line renders on Home immediately
    /// after launch — the reviewer can see it WITHOUT opening a card.
    func testGroceryLineRendersOnHomeWithoutOpeningCard() {
        let app = launchApp()

        XCTAssertTrue(app.navigationBars["EconByte"].waitForExistence(timeout: 5))

        let grocery = app.buttons["homeGroceryLine"]
        XCTAssertTrue(grocery.waitForExistence(timeout: 5),
                      "Grocery line should render on Home without opening any card")

        // No card mode has been entered: CardModeView's close button (which only
        // exists once a card set is open) must be absent, proving the grocery
        // line is seen on Home itself, not after opening a card.
        XCTAssertFalse(app.buttons["cardModeCloseButton"].exists,
                       "Grocery line must be visible on Home before any card is opened")

        // The visible line carries the card's real BLS grocery figure.
        XCTAssertTrue(grocery.label.contains("grocery") && grocery.label.contains("$117"),
                      "Grocery line should show the card's real figure. Saw: \(grocery.label)")
    }

    /// Binding proof (scope 1): the displayed grocery line is a verbatim slice of
    /// card inf-001's `exampleBody`, never an invented number. Under
    /// `-exposeGroceryBinding` the app exposes the card's full example as the
    /// element's accessibility value; the visible label must be contained in it.
    func testGroceryLineIsBoundToInf001CardContent() {
        let app = XCUIApplication()
        app.launchArguments += ["-skipStudioIntro", "-exposeGroceryBinding"]
        app.launch()

        XCTAssertTrue(app.navigationBars["EconByte"].waitForExistence(timeout: 5))
        let grocery = app.buttons["homeGroceryLine"]
        XCTAssertTrue(grocery.waitForExistence(timeout: 5))

        let displayed = grocery.label
        let cardExample = (grocery.value as? String) ?? ""
        XCTAssertFalse(cardExample.isEmpty,
                       "inf-001 exampleBody should be exposed under -exposeGroceryBinding")
        XCTAssertTrue(cardExample.contains(displayed),
                      "Displayed grocery line must be verbatim inf-001 content. "
                      + "displayed=[\(displayed)] example=[\(cardExample)]")
    }

    /// Behaviour (scope 2): tapping the grocery line starts today's set — the
    /// same flow as Start/Review, no new screen.
    func testGroceryLineTapStartsTodaysSet() {
        let app = launchApp()

        XCTAssertTrue(app.navigationBars["EconByte"].waitForExistence(timeout: 5))
        let grocery = app.buttons["homeGroceryLine"]
        XCTAssertTrue(grocery.waitForExistence(timeout: 5))
        for _ in 0..<3 where !grocery.isHittable { app.swipeUp() }
        XCTAssertTrue(grocery.isHittable, "Grocery line should be tappable on Home")
        grocery.tap()

        // Same destination as Start/Review: CardModeView, identified by its close
        // button (which does not exist on Home). Using the close button — not the
        // "N / 8" counter — avoids a false pass, since Home's topic tiles already
        // show "seen/total" text containing "/".
        let close = app.buttons["cardModeCloseButton"]
        XCTAssertTrue(close.waitForExistence(timeout: 5),
                      "Tapping the grocery line should open today's set (CardModeView)")
    }
}
