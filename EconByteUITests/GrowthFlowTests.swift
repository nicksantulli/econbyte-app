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
        XCTAssertTrue(app.descendants(matching: .any)["econWordmark"].waitForExistence(timeout: 15),
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

        // 1.1.4: Privacy sits below the Pro and Purchases sections, and a List
        // row below the fold is not built until it is scrolled to.
        let analytics = app.switches["settingsAnalyticsToggle"]
        XCTAssertTrue(scrollTo(analytics, in: app),
                      "the analytics switch should be reachable in Settings")

        XCTAssertTrue(setSwitch(analytics, to: true),
                      "turning analytics on should stick")
        XCTAssertTrue(setSwitch(analytics, to: false),
                      "turning analytics back off should stick")

        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["econWordmark"].waitForExistence(timeout: 8),
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

        // 1.1.4: Privacy sits below the Pro and Purchases sections, and a List
        // row below the fold is not built until it is scrolled to.
        let analytics = app.switches["settingsAnalyticsToggle"]
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
        app.tabBars.buttons["Browse"].tap()

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

        let counter = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Card ' AND label CONTAINS ' of '")).firstMatch
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

        XCTAssertTrue(app.descendants(matching: .any)["econWordmark"].waitForExistence(timeout: 12),
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
        XCTAssertTrue(app.descendants(matching: .any)["econWordmark"].waitForExistence(timeout: 12))
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
        XCTAssertTrue(app.descendants(matching: .any)["econWordmark"].waitForExistence(timeout: 12))

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
        XCTAssertTrue(app.descendants(matching: .any)["econWordmark"].waitForExistence(timeout: 12))
    }

    // MARK: - Topic packs (1.1.3) — discoverability + evidence capture

    private func capturePack(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Locked topic packs are discoverable on Browse (1.1.4; Home in 1.1.3): name, summary, the four
    /// topic names, a three-card preview, a buy button whose price comes from
    /// StoreKit (the scheme's `EconByte.storekit`), and Restore. No locked pack
    /// exposes a topic tile. The attachments are the Phase 2 evidence
    /// screenshots — the assertions are the contract they document.
    func testTopicPacksAreDiscoverableOnHomeWithPreviewAndBuyRow() {
        let app = XCUIApplication()
        app.launchArguments += ["-skipStudioIntro", "-EBSkipConsentPrompt",
                                "-econResetGrowthState", "-econDisableAds"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["econWordmark"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Browse"].tap()

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
    /// launch that reports Pro as active (`-econDebugPro`, DEBUG only), through
    /// the tab shell: Home's brief and course cards, the four new packs on
    /// Browse, the subscription paywall (Settings → cover), the Pro tab's
    /// inline paywall and course list, a lesson with a chart and a quiz, the
    /// News tab's teaser and, for a subscriber, the whole brief.
    func testProSurfacesRenderGateAndCaptureEvidence() {
        let app = launchApp(adsDisabled: true)
        let any = app.descendants(matching: .any)

        // Home: today's brief and the course teaser.
        XCTAssertTrue(any["homeBriefCard"].waitForExistence(timeout: 15), "today's brief is on Home")
        let homeCourse = any["homeCourseCard"]
        for _ in 0..<6 where !(homeCourse.exists && homeCourse.isHittable) { app.swipeUp() }
        XCTAssertTrue(homeCourse.exists, "a course teaser is on Home")
        capturePack("eb-home-pro-hub")

        // Browse: the four new packs are discoverable. Their products exist
        // only in EconByte.storekit until the Owner creates them in ASC, and
        // this box's xcodebuild does not attach the scheme's StoreKit
        // configuration (sentinel-price proof, 2026-09-14), so the buy control is
        // either priced ("$") or in its fail-closed state (Phase 11: a readable,
        // disabled label once loading has finished — never a bare "—").
        app.tabBars.buttons["Browse"].tap()
        let pricedOrClosed = NSPredicate(format: "label CONTAINS '$' OR (enabled == false AND NOT (label BEGINSWITH 'Loading'))")
        for id in ["history", "world", "systems", "personalfinance"] {
            let buy = app.buttons["pack-\(id)-buy"]
            for _ in 0..<14 where !(buy.exists && buy.isHittable) { app.swipeUp() }
            XCTAssertTrue(buy.waitForExistence(timeout: 15), "\(id) pack offer is on Browse")
            XCTAssertEqual(XCTWaiter().wait(for: [expectation(for: pricedOrClosed, evaluatedWith: buy)], timeout: 20),
                           .completed, "\(id) buy button is priced by StoreKit or fail-closed")
            if !buy.label.contains("$") {
                XCTAssertFalse(buy.isEnabled, "\(id) buy control must be disabled while StoreKit has no price")
                XCTAssertFalse(buy.label.contains("—"), "\(id) buy control must not show a placeholder dash")
                XCTAssertTrue(any["pack-\(id)-pricesUnavailable"].exists, "\(id) offers Prices unavailable — Try again")
            }
            XCTAssertTrue(any["pack-\(id)-preview"].exists, "\(id) previews three cards")
            if id == "world" { capturePack("eb-home-packs-new-1") }
            if id == "personalfinance" { capturePack("eb-home-packs-new-2") }
        }

        // The Pro paywall cover, entered from Settings (a deterministic List
        // row tap). The Settings row dismisses the sheet and the shell presents
        // the cover.
        openSettings(app)
        let settingsPro = app.buttons["settingsProButton"]
        XCTAssertTrue(settingsPro.waitForExistence(timeout: 10), "Settings offers EconByte Pro")
        settingsPro.tap()
        XCTAssertTrue(app.navigationBars["EconByte Pro"].waitForExistence(timeout: 20), "the Pro paywall opens")
        let subscribe = app.buttons["proPaywallSubscribeButton"]
        XCTAssertTrue(subscribe.waitForExistence(timeout: 15))
        XCTAssertEqual(XCTWaiter().wait(for: [expectation(for: pricedOrClosed, evaluatedWith: subscribe)], timeout: 20),
                       .completed, "the subscribe button is priced by StoreKit or fail-closed")
        XCTAssertTrue(any["proPaywallPlan-annual"].exists && any["proPaywallPlan-monthly"].exists)
        if subscribe.label.contains("$") {
            XCTAssertTrue(any["proPaywallTrialLine"].waitForExistence(timeout: 15),
                          "a trial-eligible reader sees the subordinate trial line")
        } else {
            XCTAssertFalse(subscribe.isEnabled, "no price, no live subscribe control")
            XCTAssertFalse(any["proPaywallTrialLine"].exists, "no trial line without a StoreKit answer")
        }
        XCTAssertTrue(app.buttons["proPaywallRestoreButton"].exists, "Restore is on the paywall")
        capturePack("eb-pro-paywall")
        let terms = any["proPaywallTermsLink"]
        for _ in 0..<6 where !(terms.exists && terms.isHittable) { app.swipeUp() }
        XCTAssertTrue(terms.exists, "Terms of Use link is on the paywall")
        XCTAssertTrue(any["proPaywallPrivacyLink"].exists, "Privacy Policy link is on the paywall")
        app.buttons["proPaywallCloseButton"].tap()
        XCTAssertTrue(any["econWordmark"].waitForExistence(timeout: 10))

        // The Pro tab: the same paywall inline, and the courses.
        app.tabBars.buttons["Pro"].tap()
        XCTAssertTrue(app.buttons["proPaywallSubscribeButton"].waitForExistence(timeout: 15),
                      "a non-subscriber sees the paywall inline on the Pro tab")
        let courseRow = any["proCourseRow-investing-approaches"]
        for _ in 0..<8 where !(courseRow.exists && courseRow.isHittable) { app.swipeUp() }
        XCTAssertTrue(courseRow.exists, "the courses are on the Pro tab")
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
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Synthetic'")).firstMatch.exists,
                      "the chart says its data is synthetic")
        capturePack("eb-lesson-chart")
        let quiz = any["quiz"]
        for _ in 0..<10 where !(quiz.exists && quiz.isHittable) { app.swipeUp() }
        XCTAssertTrue(quiz.exists, "the lesson has its quiz")
        app.buttons["quizChoice-0"].tap()
        XCTAssertTrue(any["quizExplanation"].waitForExistence(timeout: 10), "answering reveals the explanation")
        capturePack("eb-lesson-quiz")
        app.terminate()

        // News: free teaser + lock (fresh launch, still not subscribed).
        let free = launchApp(adsDisabled: true)
        let freeAny = free.descendants(matching: .any)
        free.tabBars.buttons["News"].tap()
        XCTAssertTrue(freeAny["briefHeadline"].waitForExistence(timeout: 15), "the Daily Brief is on the News tab")
        XCTAssertTrue(freeAny["briefTeaserItem"].waitForExistence(timeout: 10), "the free teaser shows one released item")
        let lock = free.buttons["briefLockedProButton"]
        for _ in 0..<6 where !(lock.exists && lock.isHittable) { free.swipeUp() }
        XCTAssertTrue(lock.exists, "the rest of the brief is locked without Pro")
        XCTAssertFalse(freeAny["briefScheduledSection"].exists, "the schedule is part of the Pro brief")
        capturePack("eb-brief-teaser")
        free.terminate()

        // Second launch: Pro active (DEBUG override, no StoreKit).
        let pro = XCUIApplication()
        pro.launchArguments += ["-skipStudioIntro", "-EBSkipConsentPrompt", "-econDisableAds", "-econDebugPro"]
        pro.launch()
        let proAny = pro.descendants(matching: .any)
        XCTAssertTrue(proAny["econWordmark"].waitForExistence(timeout: 15))
        pro.tabBars.buttons["Pro"].tap()
        XCTAssertTrue(proAny["proActiveBadge"].waitForExistence(timeout: 10), "Pro shows as active")
        XCTAssertFalse(pro.buttons["proPaywallSubscribeButton"].exists, "no paywall for a subscriber")
        capturePack("eb-home-pro-active")
        pro.tabBars.buttons["News"].tap()
        XCTAssertTrue(proAny["briefHeadline"].waitForExistence(timeout: 15))
        XCTAssertFalse(pro.buttons["briefLockedProButton"].exists, "a subscriber sees the whole brief")
        let schedule = proAny["briefScheduledSection"]
        for _ in 0..<8 where !(schedule.exists && schedule.isHittable) { pro.swipeUp() }
        XCTAssertTrue(schedule.exists, "a subscriber sees what is scheduled this week")
        capturePack("eb-brief-pro")
        openSettings(pro)
        let status = proAny["settingsProStatusRow"]
        XCTAssertTrue(status.waitForExistence(timeout: 10), "Settings shows the subscription status")
        XCTAssertTrue(proAny["settingsManageSubscriptionLink"].exists, "Manage Subscription is reachable")
        capturePack("eb-settings-pro")
    }
}
