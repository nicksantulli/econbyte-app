import XCTest

/// 1.1.5 card graphics, in the running app: every card in the two free topics
/// (Inflation, Interest Rates — together they carry all eight graphic kinds),
/// plus a second line chart (lm-002) and a second proportion (sd-010), read as
/// a Pro subscriber with no banner; the Inflation deck as a free reader with the
/// banner slot; and a large Dynamic Type pass. Attachments are the evidence
/// screenshots. The assertion is that each card announces its graphic to
/// VoiceOver, which the CardView hook adds to the card's label.
final class CardGraphicsEvidenceTests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launch(pro: Bool, ads: Bool, contentSize: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-skipStudioIntro", "-EBSkipConsentPrompt", "-EBSkipPermissionPrompts",
                                "-econResetGrowthState", "-econBriefOffline"]
        if pro { app.launchArguments.append("-econDebugPro") }
        if !ads { app.launchArguments.append("-econDisableAds") }
        if let contentSize { app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize] }
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

    @discardableResult
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication, attempts: Int = 20) -> Bool {
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

    /// Opens a core topic's deck from Browse.
    private func openTopic(_ id: String, in app: XCUIApplication) {
        app.tabBars.buttons["Browse"].tap()
        let tile = app.descendants(matching: .any)["topic-\(id)"]
        XCTAssertTrue(tile.waitForExistence(timeout: 15), "topic-\(id) tile")
        XCTAssertTrue(scrollTo(tile, in: app), "topic-\(id) reachable")
        tile.tap()
        XCTAssertTrue(app.buttons["cardModeCloseButton"].waitForExistence(timeout: 15), "\(id) deck opens")
    }

    /// The card is one combined accessibility element; the hook puts the
    /// graphic's summary into its label.
    private func assertCardAnnouncesAGraphic(_ app: XCUIApplication, _ context: String) {
        let card = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'Concept.' AND label CONTAINS 'Graphic: '")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10), "\(context): the card announces its graphic")
    }

    /// Captures `count` cards of the open deck, advancing with Next.
    private func captureDeck(_ app: XCUIApplication, prefix: String, count: Int, only: Set<Int>? = nil) {
        for index in 1...count {
            if only == nil || only!.contains(index) {
                assertCardAnnouncesAGraphic(app, "\(prefix) card \(index)")
                capture(String(format: "%@-%02d", prefix, index))
            }
            if index < count {
                let next = app.buttons["Next →"]
                XCTAssertTrue(next.waitForExistence(timeout: 10))
                next.tap()
            }
        }
    }

    func testFreeTopicDecksShowEveryGraphicKind() {
        let app = launch(pro: true, ads: false)
        openTopic("inflation", in: app)
        captureDeck(app, prefix: "p20-pro-inflation", count: 12)
        app.buttons["cardModeCloseButton"].tap()

        openTopic("interest-rates", in: app)
        captureDeck(app, prefix: "p20-pro-interest-rates", count: 12)
        app.buttons["cardModeCloseButton"].tap()

        // A second line chart (lm-002, card 2) and a second proportion (sd-010, card 10).
        openTopic("labor-markets", in: app)
        captureDeck(app, prefix: "p20-pro-labor-markets", count: 2, only: [2])
        app.buttons["cardModeCloseButton"].tap()
        openTopic("supply-demand", in: app)
        captureDeck(app, prefix: "p20-pro-supply-demand", count: 10, only: [1, 6, 10])
    }

    func testFreeReaderWithBannerSlot() {
        let app = launch(pro: false, ads: true)
        openTopic("inflation", in: app)
        captureDeck(app, prefix: "p20-free-banner-inflation", count: 12)
    }

    func testLargeDynamicType() {
        let app = launch(pro: true, ads: false, contentSize: "UICTContentSizeCategoryAccessibilityL")
        openTopic("inflation", in: app)
        captureDeck(app, prefix: "p20-ax-inflation", count: 11, only: [1, 3, 5, 9, 11])
        app.buttons["cardModeCloseButton"].tap()
        openTopic("interest-rates", in: app)
        captureDeck(app, prefix: "p20-ax-interest-rates", count: 12, only: [3, 6, 12])
    }
}
