import XCTest
@testable import EconByte

/// EconByte 1.1.3 growth audit (Owner order 2026-09-14; Dudley factory pattern
/// ported from Table Talk 1.1.5):
///
///  1. (1.1.4) the first-open consent card is replaced by Apple's standard ATT
///     and notification prompts at first launch (`FirstLaunchPermissionsTests`);
///  2. the Release instrumentation key gate in the committed project file;
///  3. the version stamp (now 1.1.7 / build 24 — 1.1.6 build 23 is live);
///  4. the ad request gates (entitlement, DUD-224 region, the build-13 ATT
///     ordering) every ad format shares. Written for the anchored banner in
///     1.1.3; the banner itself is gone in 1.1.7 (`AdRetune117Tests`), the
///     gates stay and now cover the interstitial and the rewarded offer.
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

    // MARK: - 1. First-launch permissions replace the consent card (1.1.4)

    /// The 1.1.3 custom consent card is gone: 1.1.4 asks Apple's standard ATT
    /// and notification prompts instead (`FirstLaunchPermissionsTests` covers
    /// the mapping and the upgrade rules). No source may bring the card back.
    func testTheCustomConsentCardIsGoneAndTheAppRunsTheSystemPromptFlow() throws {
        let app = repoRoot.appendingPathComponent("EconByte")
        for removed in ["Views/AnalyticsConsentCard.swift", "Services/FirstOpenConsentPolicy.swift"] {
            XCTAssertFalse(FileManager.default.fileExists(atPath: app.appendingPathComponent(removed).path),
                           "\(removed) was replaced by the system prompts")
        }
        let appSource = InstrumentationPrivacyTests.strippingComments(
            try String(contentsOf: app.appendingPathComponent("EconByteApp.swift"), encoding: .utf8))
        XCTAssertFalse(appSource.contains("AnalyticsConsentCard"))
        XCTAssertTrue(appSource.contains("permissions.runIfNeeded("),
                      "the app runs the first-launch permission flow")
        XCTAssertTrue(appSource.contains("waitForIntro()"),
                      "…only after the studio intro has gone")
        XCTAssertTrue(appSource.contains("isReadyForSystemPrompt"),
                      "…only when iOS would show it (active, nothing presented) — Phase 14")
        XCTAssertTrue(appSource.contains("case .active:") && appSource.contains("runLaunchPermissions()"),
                      "…and again on activation while a prompt is still owed — Phase 14")
        XCTAssertTrue(appSource.contains("isUnitTestRun"),
                      "…and never inside a unit-test host, whose orphaned alert blocks later UI tests — Phase 14")
    }

    /// The 1.1.3 card's stored answer still counts as an analytics answer, so
    /// an install that answered it is never re-mapped by an ATT Allow.
    func testTheLegacyCardAnswerStillCountsAsAnAnalyticsAnswer() {
        XCTAssertEqual(FirstLaunchPermissionPolicy.legacyFirstOpenConsentKey, "ebAnalyticsConsentPromptVersion")
        XCTAssertFalse(FirstLaunchPermissionPolicy.analyticsAlreadyAnswered(defaults: defaults))
        defaults.set(1, forKey: FirstLaunchPermissionPolicy.legacyFirstOpenConsentKey)
        XCTAssertTrue(FirstLaunchPermissionPolicy.analyticsAlreadyAnswered(defaults: defaults))
    }

    /// The UI-test harness arguments stand the prompts down and keep the run
    /// unkeyed.
    func testSkipArgumentsStandTheSystemPromptsDown() {
        XCTAssertTrue(FirstLaunchPermissionPolicy.isSkipped(arguments: ["EconByte", "-EBSkipConsentPrompt"]))
        XCTAssertTrue(FirstLaunchPermissionPolicy.isSkipped(arguments: ["EconByte", "-EBSkipPermissionPrompts"]))
        XCTAssertTrue(FirstLaunchPermissionPolicy.isSkipped(arguments: ["EconByte", "-EBInstrumentationSmoke"]))
        XCTAssertFalse(FirstLaunchPermissionPolicy.isSkipped(arguments: ["EconByte"]))
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

    /// 1.1.4 build 16 is in App Review and builds 17–19 are reserved for 1.1.4
    /// hotfixes, so the 1.1.5 line runs from build 20. Build 20 was the first
    /// 1.1.5 TestFlight, 21 was Phase 24's Pro polish, and 22 (Phase 27) is the
    /// combined release build: Pro polish + the Phase 25 ad-delivery lane + the
    /// AX/IC/EA region fix — live as 1.1.5. 1.1.6 (ads + rating request) is
    /// build 23, live. 1.1.7 (banner removed, full-screen formats only) is
    /// build 24, live. 1.1.8 (analytics drain fix only) is build 25. The stamp
    /// must match in both places the project declares it.
    func testProjectIsStampedOneOneEightBuildTwentyFive() throws {
        let pbx = try String(contentsOf: repoRoot.appendingPathComponent("EconByte.xcodeproj/project.pbxproj"),
                             encoding: .utf8)
        XCTAssertEqual(pbx.components(separatedBy: "MARKETING_VERSION = 1.1.8;").count - 1, 2)
        XCTAssertEqual(pbx.components(separatedBy: "CURRENT_PROJECT_VERSION = 25;").count - 1, 2)
        for used in 13...24 {
            XCTAssertFalse(pbx.contains("CURRENT_PROJECT_VERSION = \(used);"),
                           "build \(used) is live, submitted, in review or reserved for 1.1.4 hotfixes")
        }

        let yml = try String(contentsOf: repoRoot.appendingPathComponent("project.yml"), encoding: .utf8)
        XCTAssertTrue(yml.contains("MARKETING_VERSION: \"1.1.8\""))
        XCTAssertTrue(yml.contains("CURRENT_PROJECT_VERSION: \"25\""))
    }

    // MARK: - 4. Ad request gates (every format; the banner is gone in 1.1.7)

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

    /// A prompt the reader answers (the Phase 14 gate is the answer, not the ask).
    @MainActor
    private final class AnsweringTracking: EconTrackingAuthorizing {
        var status: EconTrackingStatus = .notDetermined
        func requestAuthorization() async -> EconTrackingStatus {
            status = .denied
            return status
        }
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

    /// The interstitial placements are the set exit and (1.1.6) the halfway
    /// break; the telemetry placements add only the rewarded offer (1.1.7
    /// removed the three banner slots — `AdRetune117Tests`).
    func testTheInterstitialPlacementsAreTheSetExitAndTheHalfwayBreak() {
        XCTAssertEqual(EconAdPlacement.allCases, [.dailySetExit, .setMidpoint])
        XCTAssertEqual(EBAdPlacement.dailySetExit.rawValue, "daily_set_exit")
        XCTAssertEqual(EBAdPlacement.setMidpoint.rawValue, "set_midpoint")
        XCTAssertEqual(EBAdPlacement.packTrial.rawValue, "pack_trial")
    }

    /// A Remove Ads owner never has an ad requested on their behalf.
    func testEntitledReadersCannotRequestAnAd() {
        let monetization = makeMonetization()
        monetization.update(entitlements: EconEntitlements(removeAds: true))
        XCTAssertFalse(monetization.canRequestAds)
        monetization.startAdsIfPermitted()
        XCTAssertFalse(monetization.didStartSDK)
    }

    /// DUD-224: no ads in the EEA/UK/CH. Phase 25 (Owner 2026-09-15): an
    /// unknown region is served, non-personalized.
    func testAdRestrictedRegionsCannotRequestAnAd() {
        let restricted = makeMonetization(region: .restricted)
        XCTAssertFalse(restricted.canRequestAds, "EEA/UK/CH must not request an ad")
        restricted.startAdsIfPermitted()
        XCTAssertFalse(restricted.didStartSDK)

        let unknown = makeMonetization(region: .unknown)
        XCTAssertTrue(unknown.canRequestAds, "an unknown region is served")
        unknown.startAdsIfPermitted()
        XCTAssertTrue(unknown.didStartSDK)
        XCTAssertEqual(unknown.currentRequestPolicy.extras, ["npa": "1", "rdp": "1"])
    }

    /// 5.1.2(i): before the tracking decision no ad may be requested. Once the
    /// prompt has been answered (any answer), the SDK starts.
    func testNoAdRequestBeforeTheTrackingDecisionAndRequestsAfterIt() async {
        let adapter = NullAdapter()
        let monetization = EconMonetization(adapter: adapter,
                                            defaults: defaults,
                                            now: { Date(timeIntervalSince1970: 1_789_000_000) },
                                            region: { .allowed },
                                            tracking: AnsweringTracking())
        XCTAssertFalse(monetization.canRequestAds, "an undecided ATT status blocks every ad")
        monetization.startAdsIfPermitted()
        XCTAssertFalse(monetization.didStartSDK)
        XCTAssertEqual(adapter.startCount, 0)

        await monetization.resolveTrackingAuthorizationIfNeeded()
        XCTAssertTrue(monetization.canRequestAds, "an answered prompt unblocks ads")
        XCTAssertTrue(monetization.didStartSDK, "the rewarded offer is gated on the SDK having started")
        XCTAssertEqual(adapter.startCount, 1)
    }

    /// A decided reader in an allowed region with no entitlement: ads may be
    /// requested, and the rewarded request uses the same policy the
    /// interstitial uses — personalized after "Allow" (Owner 2026-09-15),
    /// otherwise not.
    func testAnEligibleReaderGetsTheSharedRequestPolicy() {
        let authorized = makeMonetization(tracking: .authorized)
        authorized.startAdsIfPermitted()
        XCTAssertTrue(authorized.didStartSDK)
        XCTAssertTrue(authorized.canRequestAds)
        XCTAssertTrue(authorized.currentRequestPolicy.usesPersonalizedAds)
        XCTAssertEqual(authorized.currentRequestPolicy.extras, [:])
        XCTAssertEqual(authorized.currentRequestPolicy.trackingStatus, .authorized)

        let denied = makeMonetization(tracking: .denied)
        XCTAssertEqual(denied.currentRequestPolicy.extras, ["npa": "1", "rdp": "1"])

        let unknownRegion = makeMonetization(region: .unknown, tracking: .authorized)
        unknownRegion.startAdsIfPermitted()
        XCTAssertTrue(unknownRegion.canRequestAds, "an unknown region is served")
        XCTAssertEqual(unknownRegion.currentRequestPolicy.extras, ["npa": "1", "rdp": "1"],
                       "…but never personalized")
    }

    /// Every adapter registers the same extras through one builder; asserted on
    /// the source with comments stripped, like `testEveryAdRequestIsNonPersonalized`.
    /// 1.1.7: two loads (interstitial, rewarded) — the two banner loads are gone.
    func testEveryAdapterBuildsItsRequestFromThePolicy() throws {
        let source = InstrumentationPrivacyTests.strippingComments(
            try String(contentsOf: repoRoot.appendingPathComponent("EconByte/Services/AdManager.swift"),
                       encoding: .utf8))
        XCTAssertFalse(source.contains("GoogleBannerView"), "1.1.7: no banner adapter")
        XCTAssertEqual(source.components(separatedBy: "EconAdRequestBuilder.makeRequest(policy: policy)").count - 1, 2,
                       "the interstitial load and the rewarded load (1.1.6) must build their request from the policy")
        XCTAssertEqual(source.components(separatedBy: "request.register(networkExtras)").count - 1, 1,
                       "one builder registers the extras for every format")
    }
}
