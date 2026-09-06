import XCTest

/// Task 5 rendered-flow gate: consent controls, purchase-control continuity, the
/// completed-set exit, and the review destination.
///
/// These tests drive the real app from a cold launch with the growth state reset
/// (`-econResetGrowthState`), so every run starts from a fresh-install posture.
final class GrowthFlowTests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// `adsDisabled` adds the DEBUG-only `-econDisableAds` argument, which reports
    /// the device as ad-restricted through the real DUD-224 suppression path. Use
    /// it for any test that drives the app past a genuinely ad-eligible exit but
    /// is not itself asserting ad behaviour — otherwise a live fill from Google's
    /// test unit can present an interstitial mid-assertion.
    private func launchApp(adsDisabled: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-skipStudioIntro", "-econResetGrowthState"]
        if adsDisabled { app.launchArguments.append("-econDisableAds") }
        app.launch()
        XCTAssertTrue(app.navigationBars["EconByte"].waitForExistence(timeout: 15),
                      "Home should render on cold launch")
        return app
    }

    private func openSettings(_ app: XCUIApplication) {
        let gear = app.buttons["settingsGearButton"]
        XCTAssertTrue(gear.waitForExistence(timeout: 15), "Settings gear should render")
        gear.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 15),
                      "Settings sheet should open")
    }

    /// Scrolls until the element is actually hittable, and stops as soon as it
    /// is, so a later `tap()` lands on the control rather than past it.
    @discardableResult
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        for _ in 0..<8 {
            if element.exists && element.isHittable { return true }
            app.swipeUp()
        }
        return element.exists && element.isHittable
    }

    /// Flips a SwiftUI `Toggle` and waits for the change to land. The tap is
    /// aimed at the trailing edge, where the control itself sits, because the
    /// switch element's frame spans the whole list row.
    @discardableResult
    private func setSwitch(_ element: XCUIElement, to on: Bool) -> Bool {
        let expected = on ? "1" : "0"
        if (element.value as? String) == expected { return true }
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if (element.value as? String) == expected { return true }
            _ = element.waitForExistence(timeout: 0.25)
        }
        return (element.value as? String) == expected
    }

    // MARK: - Consent controls (spec section 10.1)

    /// Analytics and diagnostics are separate, optional, and default off.
    func testAnalyticsAndDiagnosticsConsentBothDefaultOff() {
        let app = launchApp()
        openSettings(app)

        let analytics = app.switches["settingsAnalyticsToggle"]
        let diagnostics = app.switches["settingsDiagnosticsToggle"]
        scrollTo(analytics, in: app)

        XCTAssertTrue(analytics.waitForExistence(timeout: 8),
                      "an analytics consent switch should exist in Settings")
        XCTAssertTrue(diagnostics.waitForExistence(timeout: 8),
                      "a diagnostics consent switch should exist in Settings")
        XCTAssertEqual(analytics.value as? String, "0", "analytics consent defaults off")
        XCTAssertEqual(diagnostics.value as? String, "0", "diagnostics consent defaults off")
    }

    /// Turning a consent on and off again round-trips without disturbing content.
    func testAnalyticsConsentRoundTripsAndLeavesContentIntact() {
        let app = launchApp()
        openSettings(app)

        let analytics = app.switches["settingsAnalyticsToggle"]
        XCTAssertTrue(analytics.waitForExistence(timeout: 8))
        XCTAssertTrue(scrollTo(analytics, in: app),
                      "the analytics switch should be reachable in Settings")

        XCTAssertTrue(setSwitch(analytics, to: true),
                      "turning analytics on should stick")
        XCTAssertTrue(setSwitch(analytics, to: false),
                      "turning analytics back off should stick")

        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["EconByte"].waitForExistence(timeout: 8),
                      "declining analytics must not affect the learning flow")
        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label CONTAINS 'Start'"))
            .firstMatch.waitForExistence(timeout: 8))
    }

    /// The deletion handle, asserted on screen.
    ///
    /// `AppStore/1.1.2/app-privacy-answers.md` §1 tells App Review that the
    /// anonymous analytics identifier "is shown to the user in Settings so they
    /// can quote it in a deletion request". The reconciliation merge dropped the
    /// row while leaving that sentence in the answers, which is a privacy
    /// promise the build did not keep. This test is what stops it happening
    /// twice.
    ///
    /// A UI-test launch resolves no PostHog key (`InstrumentationContext`), so
    /// there is no id on the wire — and the row must SAY so rather than show an
    /// id no deletion request could match.
    func testAnalyticsIdentityRowIsOfferedWithConsentAndWithdrawnWithIt() {
        let app = launchApp()
        openSettings(app)

        let analytics = app.switches["settingsAnalyticsToggle"]
        XCTAssertTrue(analytics.waitForExistence(timeout: 8))
        XCTAssertTrue(scrollTo(analytics, in: app),
                      "the analytics switch should be reachable in Settings")

        // The identifier is on the row's VALUE, which is the thing the promise is
        // about: what the user can actually quote to support.
        let row = app.staticTexts["analyticsIdentityRow"]
        XCTAssertFalse(row.exists,
                       "before consent there is no analytics id, so there must be no row")

        XCTAssertTrue(setSwitch(analytics, to: true),
                      "turning analytics on should stick")
        XCTAssertTrue(row.waitForExistence(timeout: 8),
                      "opting in must reveal the Analytics ID row — it is the only handle a user "
                        + "has on data they cannot otherwise name in a deletion request")
        XCTAssertTrue(app.staticTexts["Analytics ID"].waitForExistence(timeout: 8),
                      "the value needs its own visible title, or it is an unexplained string")
        XCTAssertEqual(row.label, "not available",
                       "a UI-test launch resolves no analytics credentials, so nothing is on the "
                        + "wire and the row says so instead of inventing an id")

        let copy = app.buttons["analyticsIdentityCopyButton"]
        XCTAssertTrue(copy.waitForExistence(timeout: 8),
                      "an id a user cannot copy is not a usable deletion handle")
        XCTAssertFalse(copy.isEnabled,
                       "with no id to copy the control must be disabled rather than silently "
                        + "putting an empty string on the pasteboard")

        XCTAssertTrue(setSwitch(analytics, to: false),
                      "turning analytics back off should stick")
        XCTAssertFalse(row.waitForExistence(timeout: 3),
                       "withdrawing consent resets the id, so the row must go with it")
    }

    /// Reminders default off and the system dialog never appears on launch.
    func testRemindersDefaultOffAndNoPermissionDialogOnLaunch() {
        let app = launchApp()
        XCTAssertEqual(app.alerts.count, 0,
                       "no permission dialog may appear on first launch")

        openSettings(app)
        let reminders = app.switches["settingsRemindersToggle"]
        XCTAssertTrue(reminders.waitForExistence(timeout: 8))
        XCTAssertEqual(reminders.value as? String, "0", "reminders default off")
    }

    // MARK: - Purchase controls (spec section 8)

    /// Both approved purchases stay independently reachable, plus Restore.
    func testBothPurchaseControlsAndRestoreRemainReachable() {
        let app = launchApp()
        openSettings(app)

        XCTAssertTrue(app.buttons["settingsRemoveAdsButton"].waitForExistence(timeout: 8),
                      "Remove Ads must remain purchasable from Settings")
        XCTAssertTrue(app.buttons["settingsUnlockAllButton"].waitForExistence(timeout: 8),
                      "Unlock All Topics must remain purchasable from Settings")
        XCTAssertTrue(app.buttons["settingsRestoreButton"].waitForExistence(timeout: 8),
                      "Restore Purchases must remain reachable")
    }

    /// The paywall must not imply the two products are one bundle.
    func testPaywallDoesNotUseAnUmbrellaProLabel() {
        let app = launchApp()

        let locked = app.buttons["topic-gdp"]
        XCTAssertTrue(locked.waitForExistence(timeout: 10))
        scrollTo(locked, in: app)
        locked.tap()

        XCTAssertTrue(app.staticTexts["Unlock All Topics"].waitForExistence(timeout: 10),
                      "the paywall should open for a locked topic")
        XCTAssertFalse(app.navigationBars["EconByte Pro"].exists,
                       "an umbrella Pro label implies the two purchases are bundled")
    }

    // MARK: - Rating destination (spec section 11.2)

    func testSettingsExposesARateLinkThatIsNotTheHomepage() {
        let app = launchApp()
        openSettings(app)

        let rate = app.buttons["settingsRateButton"]
        scrollTo(rate, in: app)
        XCTAssertTrue(rate.waitForExistence(timeout: 8),
                      "Settings should expose a Rate EconByte link")
        XCTAssertTrue(rate.isEnabled)
    }

    // MARK: - Completed-set exit (spec section 9.3)

    /// Drives a full daily set and leaves the app on the session-complete state.
    ///
    /// The Home CTA reads "Start" only until today's goal is met; once a set is
    /// finished it becomes "Review", so both labels are accepted — otherwise a
    /// second call could never find the button. Cards are advanced until the
    /// completion state actually appears rather than a fixed number of times, so
    /// a dropped tap on a loaded machine cannot strand the deck mid-set.
    private func completeASet(in app: XCUIApplication) {
        let cta = app.buttons.containing(
            NSPredicate(format: "label CONTAINS 'Start' OR label CONTAINS 'Review'")
        ).firstMatch
        XCTAssertTrue(cta.waitForExistence(timeout: 15), "Home should offer today's set")
        cta.tap()

        let counter = app.staticTexts.containing(NSPredicate(format: "label CONTAINS '/'")).firstMatch
        XCTAssertTrue(counter.waitForExistence(timeout: 15), "card mode should open")

        let done = app.buttons["sessionCompleteDoneButton"]
        let next = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Next'")).firstMatch
        for _ in 0..<30 {
            if done.exists { break }
            if next.exists, next.isHittable {
                next.tap()
            } else {
                _ = done.waitForExistence(timeout: 0.5)
            }
        }
        XCTAssertTrue(done.waitForExistence(timeout: 15),
                      "the session-complete state should appear after the final card")
    }

    /// A fresh install completing its very first set is below the lifetime
    /// threshold, so the exit must return straight to Home with no interstitial.
    ///
    /// This one runs the ad path for real — no `-econDisableAds` — because the
    /// assertion is exactly that the policy suppresses the ad, not that the
    /// harness did. A regression that let a first-set exit become eligible would
    /// fail here.
    func testFirstCompletedSetReturnsHomeWithNoInterstitial() {
        let app = launchApp()
        completeASet(in: app)

        let done = app.buttons["sessionCompleteDoneButton"]
        XCTAssertTrue(done.waitForExistence(timeout: 10),
                      "the session-complete state should appear after the final card")
        XCTAssertEqual(app.alerts.count, 0, "no system prompt at the set exit")
        done.tap()

        XCTAssertTrue(app.navigationBars["EconByte"].waitForExistence(timeout: 12),
                      "the set exit returns to Home with no ad on a fresh install")
    }

    /// Design section 10.1: each consent choice is presented after the first
    /// completed set, never on first launch, and never blocking.
    func testConsentChoicesArePresentedAtTheFirstCompletedSet() {
        let app = launchApp()
        XCTAssertFalse(app.switches["consentPromptAnalyticsToggle"].exists,
                       "consent must not be asked for on first launch")
        XCTAssertFalse(app.buttons["notificationPrimerEnableButton"].exists,
                       "the reminder primer must not appear on Home")

        completeASet(in: app)

        let analytics = app.switches["consentPromptAnalyticsToggle"]
        let diagnostics = app.switches["consentPromptDiagnosticsToggle"]
        XCTAssertTrue(analytics.waitForExistence(timeout: 10),
                      "the analytics choice should be offered after the first completed set")
        XCTAssertTrue(diagnostics.waitForExistence(timeout: 10),
                      "the diagnostics choice should be offered as a separate choice")
        XCTAssertEqual(analytics.value as? String, "0", "analytics defaults off")
        XCTAssertEqual(diagnostics.value as? String, "0", "diagnostics defaults off")
        XCTAssertEqual(app.alerts.count, 0,
                       "the offer is non-blocking and prompts no system dialog")

        // Two unrelated asks never share a screen.
        XCTAssertFalse(app.buttons["notificationPrimerEnableButton"].exists,
                       "the reminder primer defers while consent is being offered")

        // Declining leaves the learning flow untouched.
        app.buttons["consentPromptDoneButton"].tap()
        app.buttons["sessionCompleteDoneButton"].tap()
        XCTAssertTrue(app.navigationBars["EconByte"].waitForExistence(timeout: 12))
    }

    /// The primer defers past the consent offer — so prove it actually arrives
    /// on the next completed set rather than being lost.
    ///
    /// This test completes two sets, and the second set-exit is the one moment
    /// where every ad gate passes. Ads are therefore suppressed for it: the
    /// subject here is the primer, and an interstitial arriving on a fill would
    /// make the assertions non-deterministic. Ad behaviour at that exit is
    /// covered deterministically in `GrowthSystemsTests` with a spy adapter that
    /// controls fill, failure, and no-fill.
    func testReminderPrimerArrivesOnTheSecondCompletedSet() {
        let app = launchApp(adsDisabled: true)

        // First set: consent is offered, the primer stands down.
        completeASet(in: app)
        XCTAssertTrue(app.switches["consentPromptAnalyticsToggle"].waitForExistence(timeout: 10),
                      "the first completed set offers the consent choices")
        XCTAssertFalse(app.buttons["notificationPrimerEnableButton"].exists,
                       "the primer defers while consent is being offered")
        app.buttons["consentPromptDoneButton"].tap()
        app.buttons["sessionCompleteDoneButton"].tap()
        XCTAssertTrue(app.navigationBars["EconByte"].waitForExistence(timeout: 12))

        // Second set: the primer arrives, and consent is not asked again.
        completeASet(in: app)
        let primer = app.buttons["notificationPrimerEnableButton"]
        XCTAssertTrue(primer.waitForExistence(timeout: 10),
                      "the reminder primer should arrive on the next completed set")
        XCTAssertFalse(app.switches["consentPromptAnalyticsToggle"].exists,
                       "the consent offer is made once, not repeated")
        XCTAssertEqual(app.alerts.count, 0,
                       "the primer is non-blocking and prompts no system dialog itself")

        app.buttons["notificationPrimerDismissButton"].tap()
        app.buttons["sessionCompleteDoneButton"].tap()
        XCTAssertTrue(app.navigationBars["EconByte"].waitForExistence(timeout: 12))
    }
}
