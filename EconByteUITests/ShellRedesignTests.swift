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
        for id in ["settingsSourcesButton", "settingsSupportLink", "settingsRateButton", "settingsVersionRow"] {
            XCTAssertTrue(any[id].exists, "About keeps \(id)")
        }
        let sources = app.buttons["settingsSourcesButton"]
        for _ in 0..<4 where !(sources.exists && sources.isHittable) { app.swipeUp() }
        sources.tap()
        XCTAssertTrue(app.navigationBars["Sources & editorial policy"].waitForExistence(timeout: 10))
        sleep(1)
        capture("p10-15-sources-policy")
    }

    // MARK: - 1.1.4 release scope: paywall states and the one purchase button
    //
    // `-econDebugStore <scenario>` (DEBUG only) serves the EconByte.storekit US
    // prices without StoreKit, because xcodebuild on this Mac does not attach
    // the StoreKit configuration (Phase 8/11 proof). The layout, copy and state
    // logic under test are the shipping code; only the price source is fixed.

    private func launchStore(_ scenario: String, tab: String, _ extra: [String] = []) -> XCUIApplication {
        launch(["-econDebugStore", scenario, "-econInitialTab", tab] + extra)
    }

    private func waitForLabel(_ element: XCUIElement, _ label: String, timeout: TimeInterval = 10) -> Bool {
        let predicate = NSPredicate(format: "label == %@", label)
        return XCTWaiter().wait(for: [expectation(for: predicate, evaluatedWith: element)], timeout: timeout) == .completed
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication, swipes: Int = 12) {
        for _ in 0..<swipes where !(element.exists && element.isHittable) { app.swipeUp() }
    }

    func testPaywallEligibleForTrial() {
        let app = launchStore("eligible", tab: "pro")
        let any = app.descendants(matching: .any)
        let annual = any["proPaywallPlan-annual"]
        let monthly = any["proPaywallPlan-monthly"]
        XCTAssertTrue(annual.waitForExistence(timeout: 15))
        XCTAssertTrue(annual.isSelected, "annual is preselected")
        XCTAssertEqual(annual.label, "Annual plan, $39.99 per year, $3.33 per month, Save 66%")
        XCTAssertEqual(monthly.label, "Monthly plan, $9.99 per month")
        XCTAssertEqual(any["proPaywallTrialLine"].label,
                       "Free for 7 days, then $39.99 per year. Cancel anytime in Settings at least 24 hours before the trial ends.")
        let cta = app.buttons["proPaywallSubscribeButton"]
        XCTAssertEqual(cta.label, "Start 7-day free trial · then $39.99 per year")
        XCTAssertTrue(cta.isEnabled)
        XCTAssertEqual(app.switches.count, 0, "no toggle paywall")
        sleep(1)
        capture("a2-paywall-eligible")
        capture("review-com.nsantulli.econbyte.pro.annual")

        monthly.tap()
        XCTAssertTrue(waitForLabel(cta, "Subscribe · $9.99 per month"), "the CTA follows the selected plan")
        XCTAssertFalse(any["proPaywallTrialLine"].exists, "monthly has no trial")
        XCTAssertTrue(monthly.isSelected)
        sleep(1)
        capture("a2-paywall-eligible-monthly-selected")
        capture("review-com.nsantulli.econbyte.pro.monthly")

        annual.tap()
        XCTAssertTrue(waitForLabel(cta, "Start 7-day free trial · then $39.99 per year"))
        for id in ["proPaywallRestoreButton", "proPaywallBenefits", "proPaywallAutoRenewDisclosure",
                   "proPaywallNotAdvice", "proPaywallTermsLink", "proPaywallPrivacyLink"] {
            let element = any[id]
            reveal(element, in: app)
            XCTAssertTrue(element.exists, id)
        }
        let benefits = any["proPaywallBenefits"]
        XCTAssertTrue(benefits.staticTexts["3 courses, 27 lessons with charts and quizzes"].exists)
        XCTAssertTrue(benefits.staticTexts["All 6 topic packs (288 cards) and all 15 core topics"].exists)
        sleep(1)
        capture("a2-paywall-eligible-terms")
    }

    func testPaywallNotEligibleForTrial() {
        let app = launchStore("ineligible", tab: "pro")
        let any = app.descendants(matching: .any)
        let annual = any["proPaywallPlan-annual"]
        XCTAssertTrue(annual.waitForExistence(timeout: 15))
        XCTAssertTrue(annual.isSelected)
        XCTAssertEqual(annual.label, "Annual plan, $39.99 per year, $3.33 per month, Save 66%")
        XCTAssertFalse(any["proPaywallTrialLine"].exists, "no trial wording for a reader who cannot take it")
        XCTAssertEqual(app.buttons["proPaywallSubscribeButton"].label, "Subscribe · $39.99 per year")
        let trialWords = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'free trial' OR label CONTAINS[c] 'Free for'"))
        XCTAssertEqual(trialWords.count, 0, "no trial text anywhere")
        sleep(1)
        capture("a2-paywall-not-eligible")
    }

    func testPaywallSubscribedShowsCurrentPlan() {
        let app = launchStore("subscribed", tab: "pro")
        let any = app.descendants(matching: .any)
        XCTAssertTrue(any["proActiveBadge"].waitForExistence(timeout: 15))
        let annual = any["proPaywallPlan-annual"]
        XCTAssertEqual(annual.label, "Annual plan, $39.99 per year, $3.33 per month, Current plan")
        let cta = app.buttons["proPaywallSubscribeButton"]
        XCTAssertEqual(cta.label, "Current plan")
        XCTAssertFalse(cta.isEnabled)
        XCTAssertTrue(app.buttons["proManageSubscriptionLink"].exists, "Manage Subscription for a subscriber")
        XCTAssertFalse(any["proPaywallTrialLine"].exists)
        sleep(1)
        capture("a2-paywall-subscribed")
        any["proPaywallPlan-monthly"].tap()
        XCTAssertTrue(waitForLabel(cta, "Switch to Monthly · $9.99 per month"), "a plan change goes through StoreKit")
        XCTAssertTrue(cta.isEnabled)
        sleep(1)
        capture("a2-paywall-subscribed-switch")
    }

    func testPaywallProductsFailed() {
        let app = launchStore("failed", tab: "pro")
        let any = app.descendants(matching: .any)
        let annual = any["proPaywallPlan-annual"]
        XCTAssertTrue(annual.waitForExistence(timeout: 15))
        XCTAssertEqual(annual.label, "Annual plan, Price unavailable")
        XCTAssertEqual(any["proPaywallPlan-monthly"].label, "Monthly plan, Price unavailable")
        let cta = app.buttons["proPaywallSubscribeButton"]
        XCTAssertEqual(cta.label, "Subscribe")
        XCTAssertFalse(cta.isEnabled, "no price, no live subscribe control")
        XCTAssertTrue(any["proPaywallPricesUnavailable"].exists)
        XCTAssertTrue(app.buttons["proPaywallPricesUnavailableRetryButton"].exists)
        XCTAssertFalse(any["proPaywallTrialLine"].exists)
        XCTAssertTrue(app.buttons["proPaywallRestoreButton"].exists, "Restore still works without prices")
        sleep(1)
        capture("a2-paywall-products-failed")
    }

    /// The cover (from Settings) has a visible Close, and every one-time offer
    /// uses the same button: packs, the bundle, Unlock All, Remove Ads.
    func testEveryOfferUsesTheOnePurchaseButton() {
        let app = launchStore("eligible", tab: "browse")
        let any = app.descendants(matching: .any)

        let bundle = app.buttons["packBundle-buy"]
        reveal(bundle, in: app)
        XCTAssertTrue(bundle.waitForExistence(timeout: 15), "the All Packs Bundle is offered on Browse")
        XCTAssertEqual(bundle.label, "Unlock · $5.99")
        XCTAssertTrue(app.staticTexts["All Packs Bundle"].exists, "named exactly as in App Store Connect")
        XCTAssertTrue(app.buttons["packBundle-restore"].exists)
        sleep(1)
        capture("a2-browse-bundle")
        capture("review-com.nsantulli.econbyte.pack.bundle")
        let bundleHeight = bundle.frame.height

        for id in ["markets", "personal", "history", "world", "systems", "personalfinance"] {
            let buy = app.buttons["pack-\(id)-buy"]
            reveal(buy, in: app, swipes: 16)
            XCTAssertTrue(buy.exists, id)
            XCTAssertEqual(buy.label, "Unlock · $1.99", id)
            XCTAssertEqual(buy.frame.height, bundleHeight, accuracy: 1, "\(id): identical button size")
            XCTAssertTrue(any["pack-\(id)-preview"].exists, id)
            if ["history", "world", "systems", "personalfinance"].contains(id) {
                // Scroll the card's header into view for the review frame.
                app.swipeUp(velocity: .slow)
                let header = any["pack-\(id)"]
                if !(header.exists && header.isHittable) { app.swipeDown(velocity: .slow) }
                sleep(1)
                capture("review-com.nsantulli.econbyte.pack.\(id)")
            }
            if id == "markets" { capture("a2-pack-offer-card") }
        }

        let gdp = app.buttons["topic-gdp"]
        for _ in 0..<20 where !(gdp.exists && gdp.isHittable) { app.swipeDown() }
        gdp.tap()
        let unlock = app.buttons["paywallUnlockButton"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 10))
        XCTAssertEqual(unlock.label, "Unlock · $2.99")
        XCTAssertEqual(unlock.frame.height, bundleHeight, accuracy: 1)
        XCTAssertTrue(app.buttons["paywallRestoreButton"].exists)
        sleep(1)
        capture("a2-unlock-all-offer")
        app.buttons["paywallCloseButton"].tap()

        app.buttons["settingsGearButton"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        let expected = ["settingsRemoveAdsButton": "Remove ads · $1.99",
                        "settingsUnlockAllButton": "Unlock · $2.99",
                        "settingsPackBundleButton": "Unlock · $5.99"]
        for (id, label) in expected.sorted(by: { $0.key < $1.key }) {
            let button = app.buttons[id]
            reveal(button, in: app, swipes: 6)
            XCTAssertEqual(button.label, label, id)
        }
        sleep(1)
        capture("a2-settings-purchases")

        let proRow = app.buttons["settingsProButton"]
        for _ in 0..<6 where !(proRow.exists && proRow.isHittable) { app.swipeDown() }
        proRow.tap()
        XCTAssertTrue(app.buttons["proPaywallCloseButton"].waitForExistence(timeout: 15), "visible Close on the cover")
        sleep(1)
        capture("a2-paywall-cover")
        app.buttons["proPaywallCloseButton"].tap()
        XCTAssertTrue(any["econWordmark"].waitForExistence(timeout: 10))
    }

    func testOwnedProductsReadOwned() {
        let app = launchStore("ineligible", tab: "browse", ["-econDebugOwnAll"])
        let bundle = app.buttons["packBundle-buy"]
        reveal(bundle, in: app)
        XCTAssertTrue(bundle.waitForExistence(timeout: 15))
        XCTAssertEqual(bundle.label, "Owned")
        XCTAssertFalse(bundle.isEnabled)
        let markets = app.buttons["pack-markets-buy"]
        reveal(markets, in: app, swipes: 16)
        XCTAssertEqual(markets.label, "Owned", "a pack owned through the bundle reads Owned")
        XCTAssertTrue(app.buttons["topic-stocks-bonds"].exists, "an owned pack opens its topics")
        sleep(1)
        capture("a2-owned-pack")
        app.buttons["settingsGearButton"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        for id in ["settingsRemoveAdsButton", "settingsUnlockAllButton", "settingsPackBundleButton"] {
            let button = app.buttons[id]
            reveal(button, in: app, swipes: 6)
            XCTAssertEqual(button.label, "Owned", id)
        }
        sleep(1)
        capture("a2-owned-settings")
    }

    // MARK: - Phase 11: purchase controls and banner layout

    /// Orchestrator finding (Phase 10 screenshots): with no StoreKit price the
    /// Pro tiles showed "—", the button "Subscribe for —", the pack CTA
    /// "Unlock Personal Finance — —", Settings rows "—". On this Mac's
    /// xcodebuild the local StoreKit configuration is not attached, so the Pro
    /// products are genuinely unpriced here — exactly the state to prove.
    func testPurchaseControlsNeverShowARawPlaceholder() {
        let app = launch()
        let any = app.descendants(matching: .any)
        let settled = NSPredicate(format: "NOT (label BEGINSWITH 'Loading')")
        func assertReadable(_ element: XCUIElement, _ name: String) {
            let label = element.label
            XCTAssertFalse(label.contains("— —"), "\(name): doubled dash in '\(label)'")
            XCTAssertFalse(label.hasSuffix("—"), "\(name): dangling dash in '\(label)'")
            XCTAssertFalse(label.contains("for —"), "\(name): placeholder price in '\(label)'")
            XCTAssertNotEqual(label.trimmingCharacters(in: .whitespaces), "—", "\(name): bare placeholder")
        }

        app.tabBars.buttons["Pro"].tap()
        let subscribe = app.buttons["proPaywallSubscribeButton"]
        XCTAssertTrue(subscribe.waitForExistence(timeout: 15))
        _ = XCTWaiter().wait(for: [expectation(for: settled, evaluatedWith: subscribe)], timeout: 40)
        assertReadable(subscribe, "subscribe")
        for id in ["proPaywallPlan-annual", "proPaywallPlan-monthly"] {
            XCTAssertTrue(any[id].exists, id)
            assertReadable(any[id], id)
        }
        if !subscribe.label.contains("$") {
            XCTAssertFalse(subscribe.isEnabled, "no price, no live subscribe control")
            XCTAssertEqual(subscribe.label, "Subscribe", "disabled but readable")
            XCTAssertTrue(any["proPaywallPricesUnavailable"].exists, "Prices unavailable — Try again")
            XCTAssertTrue(app.buttons["proPaywallPricesUnavailableRetryButton"].exists)
        }
        capture("p11-01-pro-prices")

        app.tabBars.buttons["Browse"].tap()
        let buy = app.buttons["pack-personalfinance-buy"]
        for _ in 0..<14 where !(buy.exists && buy.isHittable) { app.swipeUp() }
        XCTAssertTrue(buy.waitForExistence(timeout: 15))
        _ = XCTWaiter().wait(for: [expectation(for: settled, evaluatedWith: buy)], timeout: 40)
        assertReadable(buy, "pack CTA")
        if !buy.label.contains("$") {
            XCTAssertEqual(buy.label, "Unlock")
            XCTAssertFalse(buy.isEnabled)
        }
        capture("p11-02-pack-cta")

        app.buttons["settingsGearButton"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        let proRow = app.buttons["settingsProButton"]
        XCTAssertTrue(proRow.waitForExistence(timeout: 10))
        _ = XCTWaiter().wait(for: [expectation(for: settled, evaluatedWith: proRow)], timeout: 20)
        assertReadable(proRow, "Settings Pro row")
        for id in ["settingsRemoveAdsButton", "settingsUnlockAllButton", "settingsPack-markets-buy"] {
            let row = app.buttons[id]
            for _ in 0..<6 where !(row.exists && row.isHittable) { app.swipeUp() }
            if row.exists { assertReadable(row, id) }
        }
        let dashes = app.staticTexts.matching(NSPredicate(format: "label == '—'"))
        XCTAssertEqual(dashes.count, 0, "no bare placeholder text anywhere in Settings")
        capture("p11-03-settings-prices")
    }

    /// Banner layout: above the tab bar on Home and Browse, gone while
    /// searching, and above the home indicator (under the Next button) in a
    /// card session. Uses Google's public test banner unit (DEBUG); if it does
    /// not fill on this simulator the layout cannot be asserted and the test
    /// says so instead of passing.
    func testBannersSitAboveTheTabBarAndHomeIndicatorAndLeaveSearch() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-skipStudioIntro", "-EBSkipPermissionPrompts",
                                "-econResetGrowthState", "-econTrackingAnswered"]
        app.launch()
        let any = app.descendants(matching: .any)
        XCTAssertTrue(any["econWordmark"].waitForExistence(timeout: 20))

        func waitForBanner(_ id: String, timeout: Int = 30) -> XCUIElement? {
            let banner = any[id]
            for _ in 0..<timeout {
                if banner.exists, banner.frame.height > 10 { return banner }
                sleep(1)
            }
            return nil
        }

        guard let home = waitForBanner("ad.banner.home", timeout: 45) else {
            capture("p11-10-banner-home-nofill")
            throw XCTSkip("Google's test banner did not fill on this simulator; banner layout not asserted")
        }
        /// The visible strip: the element's top plus the loaded ad height the
        /// slot reports (DEBUG accessibility value). The element's own frame
        /// runs on through the bottom safe area, so its maxY is not the ad.
        func visibleMaxY(_ banner: XCUIElement) -> CGFloat {
            let height = Double(banner.value as? String ?? "").map { CGFloat($0) } ?? banner.frame.height
            return banner.frame.minY + height
        }
        let tabBar = app.tabBars.firstMatch
        capture("p11-10-banner-home")
        NSLog("[p11] home banner frame \(home.frame) value \(String(describing: home.value)) tab bar \(tabBar.frame)")
        XCTAssertGreaterThanOrEqual(visibleMaxY(home) - home.frame.minY, 50, "an adaptive banner is at least 50 pt tall")
        XCTAssertLessThanOrEqual(visibleMaxY(home), tabBar.frame.minY + 1, "Home banner sits above the tab bar")

        app.tabBars.buttons["Browse"].tap()
        if let browse = waitForBanner("ad.banner.browse") {
            capture("p11-11-banner-browse")
            XCTAssertLessThanOrEqual(visibleMaxY(browse), tabBar.frame.minY + 1, "Browse banner sits above the tab bar")
        } else {
            XCTFail("the Browse banner did not fill although Home's did")
        }
        app.textFields["browseSearchField"].tap()
        app.typeText("infl")
        XCTAssertTrue(any["ad.banner.browse"].waitForNonExistence(timeout: 5),
                      "no banner while searching (sensitive surface; keyboard would lift it over results)")
        capture("p11-12-browse-search-no-banner")
        app.buttons["browseSearchClearButton"].tap()
        if app.keyboards.count > 0 { app.swipeDown() }

        let homeTab = app.tabBars.buttons["Home"]
        XCTAssertTrue(homeTab.waitForExistence(timeout: 10))
        homeTab.tap()
        let grocery = app.buttons["homeGroceryLine"]
        for _ in 0..<4 where !(grocery.exists && grocery.isHittable) { app.swipeDown() }
        XCTAssertTrue(grocery.waitForExistence(timeout: 10), "Home's grocery line starts today's set")
        grocery.tap()
        XCTAssertTrue(app.buttons["cardModeCloseButton"].waitForExistence(timeout: 10))
        if let card = waitForBanner("ad.banner.card") {
            let window = app.windows.firstMatch.frame
            capture("p11-13-banner-card")
            XCTAssertLessThanOrEqual(visibleMaxY(card), window.maxY - 20, "card banner clears the home indicator")
            let next = app.buttons["Next →"]
            if next.exists {
                XCTAssertLessThanOrEqual(next.frame.maxY, card.frame.minY + 1, "the banner never covers Next")
            }
        } else {
            XCTFail("the card-session banner did not fill although Home's did")
        }
    }

    func testSubscriberShell() {
        let app = launch(["-econDebugPro"])
        let any = app.descendants(matching: .any)
        XCTAssertTrue(any["homeCourseCard"].waitForExistence(timeout: 10))
        capture("p10-20-pro-home")
        app.tabBars.buttons["Pro"].tap()
        XCTAssertTrue(any["proActiveBadge"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["proPaywallSubscribeButton"].label, "Current plan")
        XCTAssertFalse(app.buttons["proPaywallSubscribeButton"].isEnabled)
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
        let diagnostics = app.switches["settingsDiagnosticsToggle"]
        for _ in 0..<6 where !(diagnostics.exists && diagnostics.isHittable) { app.swipeUp() }
        XCTAssertTrue(waitForValue(diagnostics, expected),
                      "ATT \(mode) ⇒ crash reports \(expected)")
        capture("p10-first-04-settings-\(mode)")
    }

    /// Phase 14 hardening proof: iOS shows nothing to an app that is not active,
    /// and build 15 spent its one ask in exactly that kind of state. The DEBUG
    /// `-econPermissionPromptDelay` hook holds the flow back so the app can be
    /// genuinely backgrounded first; the flow then runs while no prompt can be
    /// shown, and Apple's ATT prompt must appear once the app is active again.
    /// Runs only with `TEST_RUNNER_EB_FIRST_LAUNCH=background` after uninstall +
    /// `simctl privacy reset all`, with no other system alert on screen.
    func testTrackingPromptWaitsUntilTheAppIsActiveAgain() throws {
        guard ProcessInfo.processInfo.environment["EB_FIRST_LAUNCH"] == "background" else {
            throw XCTSkip("fresh-install retry proof; run with TEST_RUNNER_EB_FIRST_LAUNCH=background")
        }
        let tag = ProcessInfo.processInfo.environment["EB_DEVICE_TAG"] ?? "sim"
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let att = springboard.alerts.containing(NSPredicate(format: "label CONTAINS[c] 'track'")).firstMatch
        let app = XCUIApplication()
        app.launchArguments += ["-econResetGrowthState", "-econPermissionPromptDelay", "6"]
        app.launch()
        XCTAssertFalse(springboard.alerts.firstMatch.exists,
                       "no system alert may be up before backgrounding (Home would dismiss it instead)")
        XCUIDevice.shared.press(.home)
        let backgrounded = app.wait(for: .runningBackgroundSuspended, timeout: 10) || app.state == .runningBackground
        guard backgrounded else {
            // iPadOS 26 (seen on iPad Air 11-inch (M3), iPhone-compatibility mode)
            // can leave the app foreground after a Home press, so the "no prompt
            // while backgrounded" half cannot be staged there. Skip, never pass.
            throw XCTSkip("Home did not background the app on this device (state \(app.state.rawValue))")
        }
        sleep(12)   // past the delay: the flow runs while the app cannot show a prompt
        XCTAssertFalse(att.exists, "no ATT prompt while the app is in the background")
        capture("p14-bg-00-home-screen-\(tag)")

        app.activate()
        XCTAssertTrue(att.waitForExistence(timeout: 40), "ATT appears once the app is active again")
        sleep(1)
        capture("p14-bg-01-att-after-return-\(tag)")
        att.buttons["Allow"].tap()
        let notifications = springboard.alerts.containing(NSPredicate(format: "label CONTAINS[c] 'notifications'")).firstMatch
        XCTAssertTrue(notifications.waitForExistence(timeout: 20), "notifications follow ATT")
        sleep(1)
        capture("p14-bg-02-notifications-\(tag)")
        notifications.buttons["Allow"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["econWordmark"].waitForExistence(timeout: 15))
        sleep(2)
        XCTAssertFalse(springboard.alerts.firstMatch.exists, "no further prompt")
        capture("p14-bg-03-home-\(tag)")
    }
}
