import XCTest
@testable import EconByte

/// EconByte 1.1.3 growth audit (Owner order 2026-09-14; Dudley factory pattern
/// ported from Table Talk 1.1.5):
///
///  1. the first-open analytics consent card — asked once, only when keyed,
///     both answers persisted, never on top of the 1.1 primer's answer;
///  2. the Release instrumentation key gate in the committed project file;
///  3. the version stamp (1.1.3 / build 14 — the live max is build 13);
///  4. the anchored banner — production unit, Google's test unit in Debug, and
///     the same three gates the interstitial has (entitlement, DUD-224 region,
///     the build-13 ATT ordering) before a banner is ever constructed.
///
/// The interstitial pacing audit and the review-rules-v2 policy are asserted
/// in `GrowthSystemsTests` beside the rules they replace.
@MainActor
final class GrowthAuditTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "eb.growth-audit.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    // MARK: - 1. First-open consent card

    /// An unkeyed build has nothing to consent to and must never ask. Every
    /// Debug, unit-test and UI-test process is unkeyed by `InstrumentationContext`,
    /// which is why a plain Simulator run never sees the card.
    func testUnkeyedBuildNeverAsks() {
        XCTAssertFalse(FirstOpenConsentPolicy.shouldPresent(isConfigured: false,
                                                            legacyPrimerAnswered: false,
                                                            defaults: defaults, arguments: []))
    }

    func testKeyedBuildAsksExactlyOnceAndBothAnswersPersist() {
        XCTAssertTrue(FirstOpenConsentPolicy.shouldPresent(isConfigured: true,
                                                           legacyPrimerAnswered: false,
                                                           defaults: defaults, arguments: []))
        FirstOpenConsentPolicy.recordAnswered(defaults: defaults)
        XCTAssertEqual(defaults.integer(forKey: FirstOpenConsentPolicy.answeredVersionKey),
                       FirstOpenConsentPolicy.promptVersion)
        XCTAssertFalse(FirstOpenConsentPolicy.shouldPresent(isConfigured: true,
                                                            legacyPrimerAnswered: false,
                                                            defaults: defaults, arguments: []),
                       "\"Not now\" is a real, persisted answer — the card does not nag")
        FirstOpenConsentPolicy.reset(defaults: defaults)
        XCTAssertTrue(FirstOpenConsentPolicy.shouldPresent(isConfigured: true,
                                                           legacyPrimerAnswered: false,
                                                           defaults: defaults, arguments: []))
    }

    /// One question, one answer: an install the 1.1 / 1.1.2 session-complete
    /// primer already asked is never asked again by the new card.
    func testAnInstallAlreadyAskedByTheLegacyPrimerIsNotAskedAgain() {
        XCTAssertFalse(FirstOpenConsentPolicy.shouldPresent(isConfigured: true,
                                                            legacyPrimerAnswered: true,
                                                            defaults: defaults, arguments: []))
    }

    /// The harness arguments stand the card down in every configuration, and
    /// the skip argument is an automation marker so the run stays unkeyed too.
    func testSkipAndSmokeArgumentsSuppressTheCard() {
        XCTAssertFalse(FirstOpenConsentPolicy.shouldPresent(
            isConfigured: true, legacyPrimerAnswered: false, defaults: defaults,
            arguments: ["EconByte", FirstOpenConsentPolicy.skipArgument]))
        XCTAssertFalse(FirstOpenConsentPolicy.shouldPresent(
            isConfigured: true, legacyPrimerAnswered: false, defaults: defaults,
            arguments: ["EconByte", "-EBInstrumentationSmoke"]))
        XCTAssertEqual(FirstOpenConsentPolicy.skipArgument, "-EBSkipConsentPrompt")
        XCTAssertTrue(InstrumentationContext.automationArguments.contains(FirstOpenConsentPolicy.skipArgument),
                      "a launch that skips the card must also be recognised as automation")
    }

    /// The card states the same facts Settings → Privacy & Data states, and
    /// never reads as an ad-tracking prompt — ATT is a separate, later dialog.
    func testConsentCopyStatesTheFactsAndIsNotATrackingPrompt() {
        let blob = FirstOpenConsentCopy.allSlots.joined(separator: " ").lowercased()
        for required in ["anonymous", "90 days", "settings", "resets", "never a card"] {
            XCTAssertTrue(blob.contains(required), "consent copy must state: \(required)")
        }
        for banned in ["track you", "tracking permission", "personalized ads", "idfa", "advertising id "] {
            XCTAssertFalse(blob.contains(banned),
                           "consent copy must not read as an ad-tracking prompt: \(banned)")
        }
        XCTAssertFalse(FirstOpenConsentCopy.accept.isEmpty)
        XCTAssertFalse(FirstOpenConsentCopy.decline.isEmpty)
        XCTAssertNotEqual(FirstOpenConsentCopy.accept, FirstOpenConsentCopy.decline)
    }

    /// The decision itself is never measured — `consent_state` stays prohibited.
    func testTheConsentDecisionIsNotATelemetryProperty() {
        XCTAssertTrue(TelemetrySchema.prohibitedProperties.contains("consent_state"))
        XCTAssertTrue(TelemetrySchema.prohibitedProperties.contains("consent_string"))
        let allowed = Set(TelemetrySchema.allowedProperties.values.flatMap { $0 })
        XCTAssertFalse(allowed.contains("consent_state"))
    }

    /// Answering "yes" on a keyed build starts analytics through the same facade
    /// path Settings uses; "no" leaves it off, persisted, and clears the identity.
    func testTheAnswerFlowsThroughTheTelemetryFacade() {
        let telemetry = EconTelemetry(transport: NoOpTelemetryTransport(),
                                      apiKey: "phc_test_only_not_a_project",
                                      defaults: defaults)
        XCTAssertTrue(telemetry.isConfigured)
        XCTAssertFalse(telemetry.isAnalyticsEnabled)

        telemetry.setAnalyticsConsent(true)
        XCTAssertTrue(telemetry.isAnalyticsEnabled)
        XCTAssertTrue(EconTelemetry.isOptedIn(defaults))

        telemetry.setAnalyticsConsent(false)
        XCTAssertFalse(telemetry.isAnalyticsEnabled)
        XCTAssertNil(telemetry.analyticsIdentity)
        XCTAssertFalse(EconTelemetry.isOptedIn(defaults), "\"Not now\" is persisted as an answer")
        XCTAssertNotNil(defaults.object(forKey: EconTelemetry.Key.consent),
                        "the stored answer exists — it is not merely absent")
    }

    // MARK: - 2. Release instrumentation key gate (project file)

    /// A Release device build must refuse to ship with an empty PostHog key
    /// unless explicitly overridden — Table Talk 1.1.4's root cause, closed at
    /// the project level rather than by remembering.
    func testProjectCarriesTheInstrumentationKeyGate() throws {
        let pbx = try String(contentsOf: repoRoot.appendingPathComponent("EconByte.xcodeproj/project.pbxproj"),
                             encoding: .utf8)
        XCTAssertTrue(pbx.contains("name = \"Instrumentation key gate\";"))
        XCTAssertTrue(pbx.contains("KG0000000000000000000001 /* Instrumentation key gate */,"),
                      "gate must be in the EconByte target's build phases")
        XCTAssertTrue(pbx.contains("POSTHOG_API_KEY"))
        XCTAssertTrue(pbx.contains("EB_ALLOW_UNKEYED_RELEASE"))
        XCTAssertTrue(pbx.contains("PLATFORM_NAME"), "gate must only bite device (archive) builds")
        XCTAssertTrue(pbx.contains("exit 1"), "an unkeyed Release device build must FAIL, not warn")
    }

    /// The committed base config still has empty defaults and still includes
    /// the gitignored secrets file — the paste path the Owner uses.
    func testSecretsPathIsUnchanged() throws {
        let base = try String(contentsOf: repoRoot.appendingPathComponent("Config/Instrumentation.xcconfig"),
                              encoding: .utf8)
        XCTAssertTrue(base.contains("#include? \"Secrets.xcconfig\""))
        XCTAssertTrue(base.contains("POSTHOG_API_KEY ="))
        XCTAssertTrue(base.contains("SENTRY_DSN ="))
        let ignore = try String(contentsOf: repoRoot.appendingPathComponent(".gitignore"), encoding: .utf8)
        XCTAssertTrue(ignore.contains("Config/Secrets.xcconfig"))
        let example = try String(contentsOf: repoRoot.appendingPathComponent("Config/Secrets.xcconfig.example"),
                                 encoding: .utf8)
        let keyLine = example.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("POSTHOG_API_KEY") }
        XCTAssertEqual(keyLine, "POSTHOG_API_KEY =", "never a real key in the committed template")
    }

    // MARK: - 3. Version stamp

    /// The live App Store maximum is 1.1.2 build 13; 1.1.3 build 15 (topic
    /// packs) is submitted; this tree is 1.1.4 build 16 (EconByte Pro) in both
    /// places the project declares it, and the documentation mirror agrees.
    func testProjectIsStampedOneOneFourBuildSixteen() throws {
        let pbx = try String(contentsOf: repoRoot.appendingPathComponent("EconByte.xcodeproj/project.pbxproj"),
                             encoding: .utf8)
        XCTAssertEqual(pbx.components(separatedBy: "MARKETING_VERSION = 1.1.4;").count - 1, 2)
        XCTAssertEqual(pbx.components(separatedBy: "CURRENT_PROJECT_VERSION = 16;").count - 1, 2)
        XCTAssertFalse(pbx.contains("CURRENT_PROJECT_VERSION = 15;"), "build 15 is on ASC; 16 is next")
        XCTAssertFalse(pbx.contains("CURRENT_PROJECT_VERSION = 14;"), "build 14 is on ASC")
        XCTAssertFalse(pbx.contains("CURRENT_PROJECT_VERSION = 13;"), "build 13 is live")

        let yml = try String(contentsOf: repoRoot.appendingPathComponent("project.yml"), encoding: .utf8)
        XCTAssertTrue(yml.contains("MARKETING_VERSION: \"1.1.4\""))
        XCTAssertTrue(yml.contains("CURRENT_PROJECT_VERSION: \"16\""))
    }

    // MARK: - 4. Anchored banner

    @MainActor
    private final class NullAdapter: EconInterstitialAdapting {
        var isAdLoaded = false
        var onAdDismissed: ((Bool) -> Void)?
        private(set) var startCount = 0
        func startSDK(policy: EconAdRequestPolicy) { startCount += 1 }
        func preload(policy: EconAdRequestPolicy) {}
        func discardLoadedAd() {}
        func present() async -> Bool { false }
    }

    @MainActor
    private final class FixedTracking: EconTrackingAuthorizing {
        var status: EconTrackingStatus
        init(_ status: EconTrackingStatus) { self.status = status }
        func requestAuthorization() async -> EconTrackingStatus { status }
    }

    /// The adapter is built inside rather than as a default argument: the
    /// double is main-actor-isolated and a default argument is evaluated
    /// nonisolated (the same reason `ReviewRequestCoordinator` takes a closure).
    private func makeMonetization(region: EconAdRegionState = .allowed,
                                  tracking: EconTrackingStatus = .denied,
                                  adapter: NullAdapter? = nil) -> EconMonetization {
        EconMonetization(adapter: adapter ?? NullAdapter(),
                         defaults: defaults,
                         now: { Date(timeIntervalSince1970: 1_789_000_000) },
                         region: { region },
                         tracking: FixedTracking(tracking))
    }

    /// The Owner's production banner unit (AdMob console, 2026-09-14) in Release;
    /// only Google's public test banner unit can ever be selected in Debug.
    func testBannerUnitIdentifiersMatchTheOwnersConsoleAndGooglesTestUnit() {
        XCTAssertEqual(EconAdUnit.releaseBanner, "ca-app-pub-9950526548980224/4084037009")
        XCTAssertEqual(EconAdUnit.debugBanner, "ca-app-pub-3940256099942544/2435281174")
        XCTAssertNotEqual(EconAdUnit.releaseBanner, EconAdUnit.release,
                          "the banner is its own unit, not the interstitial's")
        #if DEBUG
        XCTAssertEqual(EconAdUnit.banner, EconAdUnit.debugBanner)
        #else
        XCTAssertEqual(EconAdUnit.banner, EconAdUnit.releaseBanner)
        #endif
    }

    /// The interstitial's placement vocabulary is untouched — the banner is a
    /// separate surface, measured under its own event.
    func testTheInterstitialPlacementIsStillOnlyTheSetExit() {
        XCTAssertEqual(EconAdPlacement.allCases, [.dailySetExit])
        XCTAssertEqual(EBAdPlacement.bannerHome.rawValue, "home")
        XCTAssertEqual(EBAdPlacement.bannerCard.rawValue, "card")
        XCTAssertEqual(EBAdPlacement.dailySetExit.rawValue, "daily_set_exit")
    }

    func testBannerImpressionIsDeclaredWithAClosedPlacementVocabulary() {
        XCTAssertEqual(TelemetrySchema.allowedProperties["banner_impression_v1"], ["placement"])
        XCTAssertEqual(TelemetrySchema.allowedValues["placement"], ["daily_set_exit", "home", "card"])
        XCTAssertEqual(TelemetryValidator.validate(TelemetryEvent("banner_impression_v1",
                                                                  ["placement": .string("home")])),
                       .accepted)
        XCTAssertEqual(TelemetryValidator.validate(TelemetryEvent("banner_impression_v1",
                                                                  ["placement": .string("settings")])),
                       .rejected(.disallowedValue(event: "banner_impression_v1",
                                                  property: "placement", value: "settings")))
        // No unit id, no size, no revenue can ride on it.
        for intruder in ["ad_unit_id", "revenue", "height"] {
            if case .accepted = TelemetryValidator.validate(TelemetryEvent("banner_impression_v1",
                                                                            [intruder: .string("x")])) {
                XCTFail("banner_impression_v1 accepted \(intruder)")
            }
        }
    }

    /// A Remove Ads owner never has a banner requested on their behalf.
    func testEntitledReadersCannotRequestABanner() {
        let monetization = makeMonetization()
        monetization.update(entitlements: EconEntitlements(removeAds: true))
        XCTAssertFalse(monetization.canRequestAds)
        monetization.startAdsIfPermitted()
        XCTAssertFalse(monetization.didStartSDK)
    }

    /// DUD-224: no banner in the EEA/UK, and none when the region is unknown.
    func testAdRestrictedRegionsCannotRequestABanner() {
        for region in [EconAdRegionState.restricted, .unknown] {
            let monetization = makeMonetization(region: region)
            XCTAssertFalse(monetization.canRequestAds, "\(region) must not request a banner")
            monetization.startAdsIfPermitted()
            XCTAssertFalse(monetization.didStartSDK)
        }
    }

    /// 5.1.2(i): before the tracking decision no ad may be requested — the
    /// banner included. Once the prompt has been answered (any answer), the SDK
    /// starts and the banner may be constructed.
    func testNoBannerBeforeTheTrackingDecisionAndABannerAfterIt() async {
        let adapter = NullAdapter()
        let monetization = EconMonetization(adapter: adapter,
                                            defaults: defaults,
                                            now: { Date(timeIntervalSince1970: 1_789_000_000) },
                                            region: { .allowed },
                                            tracking: FixedTracking(.notDetermined))
        XCTAssertFalse(monetization.canRequestAds, "an undecided ATT status blocks the banner")
        monetization.startAdsIfPermitted()
        XCTAssertFalse(monetization.didStartSDK)
        XCTAssertEqual(adapter.startCount, 0)

        await monetization.resolveTrackingAuthorizationIfNeeded()
        XCTAssertTrue(monetization.canRequestAds, "an answered prompt unblocks the banner")
        XCTAssertTrue(monetization.didStartSDK, "the slot is gated on the SDK having started")
        XCTAssertEqual(adapter.startCount, 1)
    }

    /// A decided reader in an allowed region with no entitlement: the banner is
    /// constructible, and its request policy is the same non-personalized one
    /// the interstitial uses.
    func testAnEligibleReaderGetsANonPersonalizedBannerRequestPolicy() {
        let monetization = makeMonetization(tracking: .authorized)
        monetization.startAdsIfPermitted()
        XCTAssertTrue(monetization.didStartSDK)
        XCTAssertTrue(monetization.canRequestAds)
        XCTAssertEqual(monetization.currentRequestPolicy.extras["npa"], "1",
                       "the banner is non-personalized even for an ATT-authorized reader")
        XCTAssertEqual(monetization.currentRequestPolicy.extras["rdp"], "1")
        XCTAssertEqual(monetization.currentRequestPolicy.trackingStatus, .authorized)
    }

    /// The banner adapter registers the same extras as the interstitial adapter;
    /// asserted on the source with comments stripped, like `testEveryAdRequestIsNonPersonalized`.
    func testTheBannerAdapterRegistersTheNonPersonalizedExtras() throws {
        let source = InstrumentationPrivacyTests.strippingComments(
            try String(contentsOf: repoRoot.appendingPathComponent("EconByte/Services/AdManager.swift"),
                       encoding: .utf8))
        XCTAssertTrue(source.contains("struct GoogleBannerView"))
        XCTAssertTrue(source.contains("currentOrientationAnchoredAdaptiveBanner"),
                      "the banner must be Google's anchored adaptive size, not a fixed 320x50")
        XCTAssertEqual(source.components(separatedBy: "request.register(extras)").count - 1, 2,
                       "both the interstitial and the banner request must register the extras")
    }
}
