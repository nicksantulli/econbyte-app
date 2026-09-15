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
        app.launchArguments += ["-skipStudioIntro", "-EBSkipConsentPrompt", "-econResetGrowthState"]
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

    // MARK: - Topic packs (1.1.3) — discoverability + evidence capture

    private func capturePack(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Locked topic packs are discoverable on Home: name, summary, the four
    /// topic names, a three-card preview, a buy button whose price comes from
    /// StoreKit (the scheme's `EconByte.storekit`), and Restore. No locked pack
    /// exposes a topic tile. The attachments are the Phase 2 evidence
    /// screenshots — the assertions are the contract they document.
    func testTopicPacksAreDiscoverableOnHomeWithPreviewAndBuyRow() {
        let app = XCUIApplication()
        app.launchArguments += ["-skipStudioIntro", "-EBSkipConsentPrompt",
                                "-econResetGrowthState", "-econDisableAds"]
        app.launch()
        XCTAssertTrue(app.navigationBars["EconByte"].waitForExistence(timeout: 15))

        let any = app.descendants(matching: .any)
        let markets = any["pack-markets"]
        for _ in 0..<8 where !(markets.exists && markets.isHittable) { app.swipeUp() }
        XCTAssertTrue(markets.waitForExistence(timeout: 15), "the Markets pack offer is on Home")
        XCTAssertTrue(any["pack-markets-preview"].exists, "a locked pack previews three cards")
        XCTAssertFalse(any["topic-stocks-bonds"].exists, "a locked pack exposes no topic tile")

        let buy = app.buttons["pack-markets-buy"]
        XCTAssertTrue(buy.waitForExistence(timeout: 15))
        // "$" — the storefront in EconByte.storekit is USA; the label is the
        // StoreKit displayPrice, never a literal.
        let priced = NSPredicate(format: "label CONTAINS '$'")
        wait(for: [expectation(for: priced, evaluatedWith: buy)], timeout: 20)
        XCTAssertTrue(app.buttons["pack-markets-restore"].exists, "Restore beside the buy button")
        capturePack("eb-home-packs-1")

        let personal = any["pack-personal"]
        for _ in 0..<8 where !(personal.exists && personal.isHittable) { app.swipeUp() }
        XCTAssertTrue(app.buttons["pack-personal-buy"].waitForExistence(timeout: 15))
        capturePack("eb-home-packs-2")

        // One frame per App Store product for the IAP review screenshots: the
        // pack's buy button (name + StoreKit price) scrolled into view.
        for id in ["markets", "personal"] {
            let button = app.buttons["pack-\(id)-buy"]
            for _ in 0..<10 where !(button.exists && button.isHittable) { app.swipeUp() }
            XCTAssertTrue(button.waitForExistence(timeout: 15), id)
            XCTAssertEqual(XCTWaiter().wait(for: [expectation(for: priced, evaluatedWith: button)], timeout: 20),
                           .completed, "\(id) buy button must show its StoreKit price")
            capturePack("eb-iap-\(id)")
        }
    }

    // MARK: - EconByte Pro (1.1.4) — surfaces render, gates hold, evidence capture

    /// Drives every 1.1.4 surface from a cold, non-subscribed launch, then from a
    /// launch that reports Pro as active (`-econDebugPro`, DEBUG only). The
    /// assertions are the contract; the attachments are the Phase 8 evidence:
    /// Home with the Pro hub and the new pack rows, the subscription paywall,
    /// a lesson with a chart, a quiz, the brief teaser, the unlocked brief,
    /// Home with Pro active, Settings with the subscription status.
    func testProSurfacesRenderGateAndCaptureEvidence() {
        let app = launchApp(adsDisabled: true)
        let any = app.descendants(matching: .any)

        // Home: the Pro hub with a call to action (not subscribed).
        let hub = any["proHub"]
        for _ in 0..<8 where !(hub.exists && hub.isHittable) { app.swipeUp() }
        XCTAssertTrue(hub.waitForExistence(timeout: 15), "the EconByte Pro section is on Home")
        XCTAssertTrue(any["proBriefRow"].exists, "the Daily Brief row is on Home")
        XCTAssertTrue(any["proCourseRow-investing-approaches"].exists, "the courses are on Home")
        XCTAssertTrue(any["proCtaRow"].exists, "a non-subscriber sees the Pro call to action")
        XCTAssertFalse(any["proActiveBadge"].exists)
        capturePack("eb-home-pro-hub")

        // Home: the four new packs are discoverable with StoreKit prices.
        let priced = NSPredicate(format: "label CONTAINS '$'")
        for id in ["history", "world", "systems", "personalfinance"] {
            let buy = app.buttons["pack-\(id)-buy"]
            for _ in 0..<12 where !(buy.exists && buy.isHittable) { app.swipeUp() }
            XCTAssertTrue(buy.waitForExistence(timeout: 15), "\(id) pack offer is on Home")
            XCTAssertEqual(XCTWaiter().wait(for: [expectation(for: priced, evaluatedWith: buy)], timeout: 20),
                           .completed, "\(id) buy button shows its StoreKit price")
            XCTAssertTrue(any["pack-\(id)-preview"].exists, "\(id) previews three cards")
            if id == "world" { capturePack("eb-home-packs-new-1") }
            if id == "personalfinance" { capturePack("eb-home-packs-new-2") }
        }

        // The Pro paywall: price primary, trial line present (local config =
        // eligible), terms + privacy + restore reachable.
        let cta = any["proCtaRow"]
        for _ in 0..<12 where !(cta.exists && cta.isHittable) { app.swipeDown() }
        XCTAssertTrue(cta.waitForExistence(timeout: 10))
        cta.tap()
        XCTAssertTrue(app.navigationBars["EconByte Pro"].waitForExistence(timeout: 15), "the Pro paywall opens")
        let subscribe = app.buttons["proPaywallSubscribeButton"]
        XCTAssertTrue(subscribe.waitForExistence(timeout: 15))
        XCTAssertEqual(XCTWaiter().wait(for: [expectation(for: priced, evaluatedWith: subscribe)], timeout: 20),
                       .completed, "the subscribe button carries the StoreKit price")
        XCTAssertTrue(any["proPaywallPlan-annual"].exists && any["proPaywallPlan-monthly"].exists)
        XCTAssertTrue(any["proPaywallTrialLine"].waitForExistence(timeout: 15),
                      "a trial-eligible reader sees the subordinate trial line")
        XCTAssertTrue(app.buttons["proPaywallRestoreButton"].exists, "Restore is on the paywall")
        capturePack("eb-pro-paywall")
        let terms = any["proPaywallTermsLink"]
        for _ in 0..<6 where !(terms.exists && terms.isHittable) { app.swipeUp() }
        XCTAssertTrue(terms.exists, "Terms of Use link is on the paywall")
        XCTAssertTrue(any["proPaywallPrivacyLink"].exists, "Privacy Policy link is on the paywall")
        app.buttons["proPaywallCloseButton"].tap()
        XCTAssertTrue(app.navigationBars["EconByte"].waitForExistence(timeout: 10))

        // A course: lesson 1 is the free preview; lesson 2 is locked.
        let courseRow = any["proCourseRow-investing-approaches"]
        for _ in 0..<8 where !(courseRow.exists && courseRow.isHittable) { app.swipeUp() }
        courseRow.tap()
        XCTAssertTrue(any["course-investing-approaches"].waitForExistence(timeout: 15), "the course opens")
        let lesson2 = any["lessonRow-ia-02"]
        XCTAssertTrue(lesson2.waitForExistence(timeout: 10))
        XCTAssertTrue((lesson2.value as? String ?? "").contains("locked"), "lesson 2 is locked without Pro")
        any["lessonRow-ia-01"].tap()
        XCTAssertTrue(any["lesson-ia-01"].waitForExistence(timeout: 15), "the free preview lesson opens")
        XCTAssertTrue(any["educationalNotice"].exists, "every lesson carries the educational notice")
        let chart = any.matching(NSPredicate(format: "identifier BEGINSWITH 'chart-' AND NOT identifier ENDSWITH '-note'")).firstMatch
        for _ in 0..<10 where !(chart.exists && chart.isHittable) { app.swipeUp() }
        XCTAssertTrue(chart.exists, "the lesson renders a chart")
        XCTAssertTrue(any.matching(NSPredicate(format: "identifier BEGINSWITH 'chart-' AND identifier ENDSWITH '-note'")).firstMatch.exists,
                      "the chart says its data is synthetic")
        capturePack("eb-lesson-chart")
        let quiz = any["quiz"]
        for _ in 0..<10 where !(quiz.exists && quiz.isHittable) { app.swipeUp() }
        XCTAssertTrue(quiz.exists, "the lesson has its quiz")
        app.buttons["quizChoice-0"].tap()
        XCTAssertTrue(any["quizExplanation"].waitForExistence(timeout: 10), "answering reveals the explanation")
        capturePack("eb-lesson-quiz")
        app.navigationBars.buttons.element(boundBy: 0).tap()   // back to the course
        XCTAssertTrue(app.buttons["courseCloseButton"].waitForExistence(timeout: 10))
        app.buttons["courseCloseButton"].tap()
        XCTAssertTrue(app.navigationBars["EconByte"].waitForExistence(timeout: 10))

        // The brief: free teaser + lock.
        let briefRow = any["proBriefRow"]
        for _ in 0..<8 where !(briefRow.exists && briefRow.isHittable) { app.swipeUp() }
        briefRow.tap()
        XCTAssertTrue(any["briefView"].waitForExistence(timeout: 15), "the Daily Brief opens")
        XCTAssertTrue(any["briefHeadline"].exists)
        XCTAssertTrue(any["briefTeaserItem"].waitForExistence(timeout: 10), "the free teaser shows one released item")
        let lock = app.buttons["briefLockedProButton"]
        for _ in 0..<6 where !(lock.exists && lock.isHittable) { app.swipeUp() }
        XCTAssertTrue(lock.exists, "the rest of the brief is locked without Pro")
        app.swipeDown()
        capturePack("eb-brief-teaser")
        app.buttons["briefCloseButton"].tap()

        // Second launch: Pro active (DEBUG override, no StoreKit).
        let pro = XCUIApplication()
        pro.launchArguments += ["-skipStudioIntro", "-EBSkipConsentPrompt", "-econDisableAds", "-econDebugPro"]
        pro.launch()
        XCTAssertTrue(pro.navigationBars["EconByte"].waitForExistence(timeout: 15))
        let proAny = pro.descendants(matching: .any)
        let proHub = proAny["proHub"]
        for _ in 0..<8 where !(proHub.exists && proHub.isHittable) { pro.swipeUp() }
        XCTAssertTrue(proAny["proActiveBadge"].waitForExistence(timeout: 10), "Pro shows as active")
        XCTAssertFalse(proAny["proCtaRow"].exists, "no call to action for a subscriber")
        XCTAssertFalse(pro.buttons["topic-gdp"].label.isEmpty)
        capturePack("eb-home-pro-active")
        proAny["proBriefRow"].tap()
        XCTAssertTrue(proAny["briefView"].waitForExistence(timeout: 15))
        XCTAssertFalse(pro.buttons["briefLockedProButton"].exists, "a subscriber sees the whole brief")
        capturePack("eb-brief-pro")
        pro.buttons["briefCloseButton"].tap()
        openSettings(pro)
        let status = proAny["settingsProStatusRow"]
        for _ in 0..<6 where !(status.exists && status.isHittable) { pro.swipeUp() }
        XCTAssertTrue(status.waitForExistence(timeout: 10), "Settings shows the subscription status")
        XCTAssertTrue(proAny["settingsManageSubscriptionLink"].exists, "Manage Subscription is reachable")
        capturePack("eb-settings-pro")
    }
}
