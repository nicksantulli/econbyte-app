import XCTest
@testable import EconByte

/// EconByte 1.1.2 instrumentation lane — the privacy guard for the PostHog +
/// Sentry SDK adoption.
///
/// The point of linking the vendor SDKs is measurement, and the point of THIS
/// file is that measurement can never carry a card, a definition, a bookmark, a
/// transaction, or anything a user typed. Two things are asserted:
///
///  1. The schema is *closed*: every property the app is allowed to send is
///     constrained to a bounded shape (an enum, a short version token, a small
///     integer, or a flag). There is no property anywhere in the allowlist that
///     accepts an open string — so there is nowhere for free text to ride.
///  2. A free-text / PII field is rejected on every event, by name and by value.
///
/// Plus: the real adapters are wired fail-soft — with no key/DSN they never
/// start the SDK and never crash.
@MainActor
final class InstrumentationPrivacyTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "eb.instrumentation.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - The schema has no open-string hole

    /// Every declared property, on every event, must map to a bounded kind.
    /// A declared property with no kind (or a hypothetical open-string kind)
    /// would be a free-text channel; there must be none.
    func testEveryAllowedPropertyIsBoundedToANonFreeTextKind() {
        for (event, properties) in TelemetrySchema.allowedProperties {
            for property in properties {
                guard let kind = TelemetrySchema.propertyKinds[property] else {
                    return XCTFail("\(event).\(property) has no declared kind — an undeclared kind is an open string")
                }
                switch kind {
                case .enumerated, .token, .smallCount, .flag:
                    continue // all four are bounded
                }
            }
        }
    }

    /// No allowed property is *named* like a free-text or PII field. A future
    /// schema addition that slips one in fails here before it can ship.
    func testNoAllowedPropertyIsNamedLikeFreeTextOrPII() {
        let freeTextish = ["text", "note", "notes", "comment", "message", "body",
                           "description", "content", "answer", "concept", "query",
                           "email", "name", "phone", "reason_text", "feedback",
                           "card_id", "topic_id", "source", "price"]
        let allowed = Set(TelemetrySchema.allowedProperties.values.flatMap { $0 })
        for name in freeTextish {
            XCTAssertFalse(allowed.contains(name),
                           "\"\(name)\" reads as a free-text/PII field and must never be an allowed property")
        }
    }

    // MARK: - A free-text / PII field is rejected on every event

    /// Adding an obvious free-text field to any event is rejected — either as a
    /// named prohibited field or as an undeclared property. Nothing free-form
    /// reaches the queue.
    func testAFreeTextFieldIsRejectedOnEveryEvent() {
        let intruders = ["card_text", "user_text", "note", "free_text", "email",
                         "topic_id", "product_id"]
        for event in TelemetrySchema.allowedEventNames.sorted() {
            for intruder in intruders {
                let candidate = TelemetryEvent(event, [intruder: .string("anything the user typed here")])
                let result = TelemetryValidator.validate(candidate)
                switch result {
                case .rejected(.prohibitedProperty), .rejected(.undeclaredProperty):
                    continue // correctly refused
                default:
                    XCTFail("\(event) accepted free-text field \"\(intruder)\" — got \(result)")
                }
            }
        }
    }

    /// A card's own prose smuggled as the *value* of a real, bounded property is
    /// rejected too: the enum vocabulary and the token charset both exclude it.
    func testCardProseSmuggledAsAValueIsRejected() {
        let prose = "Inflation is the rate at which prices rise — what's a real example?"

        // Through an enum property.
        let asEnum = TelemetryEvent("session_started_v1", [
            "mode": .string("daily"), "entry_point": .string(prose),
            "deck_size_bucket": .string("5_9"),
        ])
        XCTAssertEqual(TelemetryValidator.validate(asEnum),
                       .rejected(.disallowedValue(event: "session_started_v1",
                                                  property: "entry_point", value: prose)))

        // Through a token property — the "?" and "'" are outside the token charset.
        let asToken = TelemetryEvent("review_request_attempted_v1", [
            "app_version": .string(prose),
            "launch_count_bucket": .string("4_10"),
        ])
        XCTAssertEqual(TelemetryValidator.validate(asToken),
                       .rejected(.disallowedValue(event: "review_request_attempted_v1",
                                                  property: "app_version", value: prose)))
    }

    // MARK: - The PostHog value mapping cannot carry anything but primitives

    /// The adapter maps a validated event to PostHog's `[String: Any]` using only
    /// the three primitive TelemetryValue shapes. There is no code path from a
    /// TelemetryEvent to a nested object or free-form blob.
    func testPostHogPropertyMappingEmitsOnlyPrimitives() {
        let event = TelemetryEvent("session_ended_v1", [
            "mode": .string("daily"),
            "ad_impressions_count": .int(2),
            "had_bookmark": .bool(true),
        ])
        let mapped = PostHogTelemetryTransport.properties(from: event)
        XCTAssertEqual(mapped["mode"] as? String, "daily")
        XCTAssertEqual(mapped["ad_impressions_count"] as? Int, 2)
        XCTAssertEqual(mapped["had_bookmark"] as? Bool, true)
        for (_, value) in mapped {
            let ok = value is String || value is Int || value is Bool
            XCTAssertTrue(ok, "a non-primitive value reached the PostHog payload: \(type(of: value))")
        }
    }

    // MARK: - Fail-soft: the real adapters never start without a credential

    func testPostHogAdapterIsFailSoftWithoutAKey() async {
        let transport = PostHogTelemetryTransport(apiKey: "phc_unused_by_this_test",
                                                  host: TelemetryCredentials.defaultHost)
        let telemetry = EconTelemetry(transport: transport, apiKey: nil, defaults: defaults)

        telemetry.setAnalyticsConsent(true)
        telemetry.capture(TelemetryEvent("app_opened_v1", ["app_version": .string("1.1.2")]))
        await telemetry.flush()

        XCTAssertFalse(transport.isStarted, "no key → the PostHog SDK is never started")
        XCTAssertNil(transport.distinctID, "an unstarted adapter reports no id, rather than a stale one")
        XCTAssertFalse(telemetry.isAnalyticsEnabled)
        XCTAssertNil(telemetry.analyticsIdentity)

        // Fail-soft has a second half the facade cannot cover: the adapter must
        // also refuse on its own. Without this, `send`'s `isStarted` guard is
        // dead code as far as the suite is concerned — deleting it leaves every
        // test green while an unstarted SDK is handed events.
        let sent = await transport.send([TelemetryEvent("app_opened_v1",
                                                        ["app_version": .string("1.1.2 (9)")])])
        XCTAssertFalse(sent, "an unstarted transport must refuse the batch, not claim delivery")
        XCTAssertFalse(transport.isStarted, "sending must not start the SDK as a side effect")
    }

    func testSentryAdapterIsFailSoftWithoutADSN() {
        let transport = SentryDiagnosticsTransport()
        let diagnostics = EconDiagnostics(transport: transport, dsn: nil, defaults: defaults)

        diagnostics.setDiagnosticsConsent(true)

        XCTAssertFalse(transport.isStarted, "no DSN → the Sentry SDK is never started")
        XCTAssertFalse(diagnostics.isDiagnosticsEnabled)
        XCTAssertEqual(diagnostics.lastRefusal, .noDSNConfigured)
    }

    // MARK: - The opt-out deletes the queue that reset()/close() leave behind
    //
    // posthog-ios 3.71.4's `PostHogStorage.reset()` deliberately skips the event
    // queue ("each queue manages its own disk state"), and `close()` only stops
    // the queue object. So an opt-out that calls reset+close leaves finished,
    // unsent events on disk, and the SDK ships them the moment analytics is
    // switched back on — after the user was told the queue had been cleared.
    //
    // This exercises the real adapter against a real directory: the SDK calls
    // inside `stopAndClearLocalState` all early-return when the SDK was never set
    // up, so what is left running is exactly the purge that ships.

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("eb-posthog-purge-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    /// Writes the files the SDK would leave behind and proves the opt-out
    /// removes them.
    func testOptingOutDeletesThePostHogStateThatResetAndCloseLeaveBehind() throws {
        let base = try makeTemporaryDirectory()
        let token = "phc_test_project_token"
        let bundleID = "com.nsantulli.econbyte.tests"
        let transport = PostHogTelemetryTransport(apiKey: token,
                                                  host: TelemetryCredentials.defaultHost,
                                                  storageBase: base,
                                                  bundleIdentifier: bundleID)

        let projectDirectory = transport.localStateDirectory
        XCTAssertEqual(projectDirectory,
                       base.appendingPathComponent(bundleID, isDirectory: true)
                           .appendingPathComponent(token, isDirectory: true),
                       "the purge must target the directory posthog-ios actually writes to")

        // A queued, unsent event plus the anonymous id — the two things that
        // survive reset()/close() and would resurface on re-enable.
        try FileManager.default.createDirectory(
            at: projectDirectory.appendingPathComponent("posthog.queueFolder.uuid",
                                                        isDirectory: true),
            withIntermediateDirectories: true)
        let queuedEvent = projectDirectory
            .appendingPathComponent("posthog.queueFolder.uuid", isDirectory: true)
            .appendingPathComponent(UUID().uuidString)
        try Data("{}".utf8).write(to: queuedEvent)
        let anonymousID = projectDirectory.appendingPathComponent("posthog.anonymousId")
        try Data("01a06e5a".utf8).write(to: anonymousID)

        XCTAssertTrue(FileManager.default.fileExists(atPath: queuedEvent.path))

        transport.stopAndClearLocalState()

        XCTAssertTrue(transport.didPurgeLocalState,
                      "the adapter must report that the purge actually happened")
        XCTAssertFalse(FileManager.default.fileExists(atPath: queuedEvent.path),
                       "an event queued before the opt-out must not survive it")
        XCTAssertFalse(FileManager.default.fileExists(atPath: anonymousID.path),
                       "the SDK's anonymous id must go too, or re-enabling reuses the old identity")
        XCTAssertFalse(FileManager.default.fileExists(atPath: projectDirectory.path))
    }

    /// Every key the SDK's own reset leaves on disk is inside the directory the
    /// purge removes — so the list cannot grow past what the purge covers.
    func testEveryKeyThatSurvivesTheSDKResetLivesUnderThePurgedDirectory() throws {
        let base = try makeTemporaryDirectory()
        let transport = PostHogTelemetryTransport(apiKey: "phc_token",
                                                  host: TelemetryCredentials.defaultHost,
                                                  storageBase: base,
                                                  bundleIdentifier: "com.example.tests")
        let directory = transport.localStateDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        XCTAssertFalse(PostHogLocalStore.survivesResetAndClose.isEmpty)
        for key in PostHogLocalStore.survivesResetAndClose {
            let file = directory.appendingPathComponent(key)
            try Data("x".utf8).write(to: file)
        }

        XCTAssertTrue(PostHogLocalStore.purge(directory: directory))
        for key in PostHogLocalStore.survivesResetAndClose {
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: directory.appendingPathComponent(key).path),
                "\(key) survived the opt-out purge")
        }
    }

    func testPurgingAnAbsentDirectoryIsASuccess() throws {
        let base = try makeTemporaryDirectory()
        XCTAssertTrue(PostHogLocalStore.purge(directory: base.appendingPathComponent("nothing-here")),
                      "nothing left to leak is the outcome either way")
    }

    /// The Sentry adapter can honestly promise local-cache removal (it owns the
    /// cache directory), which is the precondition for Release diagnostics.
    func testSentryAdapterGuaranteesCacheRemovalAndClearIsSafeWhenAbsent() {
        let transport = SentryDiagnosticsTransport()
        XCTAssertTrue(transport.guaranteesLocalCacheRemoval)
        XCTAssertTrue(transport.clearLocalEnvelopeCache(),
                      "clearing an absent cache is a success, not a failure")
    }

    // MARK: - Credential resolution (key + host), still fail-soft on blanks

    func testHostResolutionFallsBackToUSCloudOnBlankOrMissing() {
        XCTAssertEqual(TelemetryCredentials.host(from: nil), TelemetryCredentials.defaultHost)
        XCTAssertEqual(TelemetryCredentials.host(from: [:]), TelemetryCredentials.defaultHost)
        XCTAssertEqual(TelemetryCredentials.host(from: [TelemetryCredentials.hostInfoPlistKey: "   "]),
                       TelemetryCredentials.defaultHost)
        XCTAssertEqual(TelemetryCredentials.host(from: [TelemetryCredentials.hostInfoPlistKey: "https://eu.i.posthog.com"]),
                       "https://eu.i.posthog.com")
    }

    func testABlankKeyIsNotACredential() {
        XCTAssertNil(TelemetryCredentials.apiKey(from: [TelemetryCredentials.infoPlistKey: ""]))
        XCTAssertNil(TelemetryCredentials.apiKey(from: [TelemetryCredentials.infoPlistKey: "   "]))
        XCTAssertNil(TelemetryCredentials.embeddedAPIKey, "a key must never be embedded in source")
        XCTAssertNil(DiagnosticsCredentials.embeddedDSN, "a DSN must never be embedded in source")
    }

    func testABlankDSNIsNotACredential() {
        XCTAssertNil(DiagnosticsCredentials.dsn(from: nil))
        XCTAssertNil(DiagnosticsCredentials.dsn(from: [:]))
        XCTAssertNil(DiagnosticsCredentials.dsn(from: [DiagnosticsCredentials.infoPlistKey: ""]))
        XCTAssertNil(DiagnosticsCredentials.dsn(from: [DiagnosticsCredentials.infoPlistKey: "  "]))
    }

    // MARK: - A test or automation run may not reach the live projects
    //
    // Seen 2026-09-05: UI-test suites launch the REAL app with the REAL key, so
    // every `xcodebuild test` relaunch wrote `app_opened_v1` into production
    // analytics and a deliberate test crash could have written into production
    // Sentry. Ingested test traffic is indistinguishable from user traffic and
    // PostHog has no delete-by-property, so the fix has to be "never send it".

    private func context(arguments: [String] = [],
                         environment: [String: String] = [:],
                         debug: Bool) -> InstrumentationContext {
        InstrumentationContext(arguments: ["EconByte"] + arguments,
                               environment: environment,
                               isDebugBuild: debug)
    }

    /// This very process. If the suppression ever regresses, this assertion is
    /// made by a run that would itself have been polluting the project.
    func testThisTestProcessIsRecognisedAsATestRun() {
        let live = InstrumentationContext.current
        XCTAssertTrue(live.isUnitTestRun,
                      "XCTestConfigurationFilePath must identify the unit-test host")
        XCTAssertTrue(live.suppressesLiveTransports,
                      "a unit-test run must never be allowed to configure a live transport")
    }

    func testAUnitTestRunResolvesNoCredentialsEvenWithRealOnesPresent() {
        let testRun = context(environment: [InstrumentationContext.xcTestEnvironmentKey: "/tmp/x.xctestconfiguration"],
                              debug: false)
        XCTAssertNil(TelemetryCredentials.resolved("phc_real_key", in: testRun))
        XCTAssertNil(DiagnosticsCredentials.resolved("https://k@o0.ingest.sentry.io/1", in: testRun))
    }

    func testAUITestLaunchResolvesNoCredentials() {
        for argument in InstrumentationContext.automationArguments.sorted() {
            let automation = context(arguments: [argument], debug: false)
            XCTAssertTrue(automation.isAutomationRun, "\(argument) must mark the run as automation")
            XCTAssertNil(TelemetryCredentials.resolved("phc_real_key", in: automation),
                         "\(argument) must not reach the live analytics project")
            XCTAssertNil(DiagnosticsCredentials.resolved("https://k@o0.ingest.sentry.io/1", in: automation),
                         "\(argument) must not reach the live Sentry project")
        }
    }

    func testAPlainDebugRunResolvesNoCredentials() {
        let debugRun = context(debug: true)
        XCTAssertTrue(debugRun.suppressesLiveTransports,
                      "a developer's Simulator run is not a user and must not be counted as one")
        XCTAssertNil(TelemetryCredentials.resolved("phc_real_key", in: debugRun))
    }

    /// The one deliberate way in — the ingestion proof, and nothing else.
    func testTheExplicitAllowFlagLiftsSuppressionInEveryContext() {
        let allowed = context(arguments: [InstrumentationContext.allowFlag, "-skipStudioIntro"],
                              environment: [InstrumentationContext.xcTestEnvironmentKey: "/tmp/x"],
                              debug: true)
        XCTAssertFalse(allowed.suppressesLiveTransports)
        XCTAssertEqual(TelemetryCredentials.resolved("phc_real_key", in: allowed), "phc_real_key")
        XCTAssertEqual(DiagnosticsCredentials.resolved("dsn", in: allowed), "dsn")
    }

    /// The shipped path is untouched: no XCTest variable, no automation
    /// argument, not a Debug build → the credentials resolve exactly as before.
    func testAReleaseRunIsUnaffectedBySuppression() {
        let release = context(debug: false)
        XCTAssertFalse(release.isUnitTestRun)
        XCTAssertFalse(release.isAutomationRun)
        XCTAssertFalse(release.suppressesLiveTransports)
        XCTAssertEqual(TelemetryCredentials.resolved("phc_real_key", in: release), "phc_real_key")
        XCTAssertEqual(DiagnosticsCredentials.resolved("dsn", in: release), "dsn")
        XCTAssertNil(TelemetryCredentials.resolved(nil, in: release),
                     "suppression must not invent a credential where there is none")
    }

    // MARK: - Nor may a test run trigger the App Store review sheet
    //
    // Found the hard way on 2026-09-05: `testCardModeCloseReturnsHome` failed
    // intermittently with "Start button should be tappable on Home". It was not
    // a scroll bug — `SKStoreReviewController` puts a system sheet over Home two
    // seconds after the 5th/20th/50th launch, a UI suite relaunches the app once
    // per test, and so exactly one test lands on a milestone and fails. WHICH
    // test depends on how many times that simulator has ever opened the app,
    // which is why the suite passed on a freshly erased device and failed after
    // the ingestion proof had launched the app a few more times.

    // RECONCILED (1.1.2): these four were written against v1.0's `ReviewPrompt`,
    // which asked on the 5th/20th/50th LAUNCH. Version 1.1 deleted that type and
    // replaced launch milestones with `ReviewRequestPolicy` — ask only after a
    // genuinely good session, at most once per app version, never after a
    // negative-session event. The guard the instrumentation lineage added is
    // still needed and still lives at the same seam, so it moved with it: it is
    // now a property of the PROCESS (`mayShowSystemReviewSheet`) rather than a
    // clause inside the launch-count decision, which is also why the eligibility
    // policy stays a pure function that can run inside XCTest.

    func testARealUserIsStillAskedWhenThePolicySaysSo() {
        XCTAssertTrue(ReviewRequestPolicy.mayShowSystemReviewSheet(in: context(debug: false)),
                      "a real user on a real device is asked when the policy says eligible")
    }

    func testAUITestLaunchIsNeverAskedToRateTheApp() {
        for argument in InstrumentationContext.automationArguments.sorted() {
            let automation = context(arguments: [argument], debug: false)
            XCTAssertFalse(
                ReviewRequestPolicy.mayShowSystemReviewSheet(in: automation),
                "\(argument): a review sheet over Home makes the suite depend on how many "
                    + "times this simulator has ever launched the app")
        }
    }

    func testAUnitTestRunIsNeverAskedToRateTheApp() {
        let testRun = context(environment: [InstrumentationContext.xcTestEnvironmentKey: "/tmp/x"],
                              debug: false)
        XCTAssertFalse(ReviewRequestPolicy.mayShowSystemReviewSheet(in: testRun))
    }

    /// A developer's Simulator run is not automation, and seeing the sheet is
    /// the only way to check it. Debug alone must not suppress it.
    func testAPlainDebugRunStillSeesTheSheet() {
        XCTAssertTrue(ReviewRequestPolicy.mayShowSystemReviewSheet(in: context(debug: true)))
    }

    /// The eligibility policy itself must remain reachable from a unit test —
    /// the suppression is about presenting Apple's sheet, not about deciding.
    func testTheEligibilityPolicyStillDecidesInsideATestRun() {
        var state = ReviewRequestState()
        state.launchCount = 2
        state.completedSetCount = 1
        state.currentSessionCompletedSet = true
        state.currentSessionCards = 8
        XCTAssertEqual(ReviewRequestPolicy.decide(state: state,
                                                  currentVersion: "1.1.3",
                                                  now: Date(timeIntervalSince1970: 60 * 60 * 24 * 30)),
                       .eligible)
    }

    // MARK: - Every reviewed switch is actually applied to the vendor object
    //
    // The real hole in this design: a configuration struct can assert a posture
    // that no adapter ever hands to the SDK, and every test still passes because
    // the tests assert the struct. Both SDKs ship switches that default to ON
    // (PostHog's `enableSwizzling`, `captureApplicationLifecycleEvents`,
    // `captureScreenViews`), so an unapplied field is not a stylistic gap — it is
    // the SDK doing the thing we documented it would not do.
    //
    // These two scan the adapter sources for a use of each declared field. A
    // source scan is the right shape here because the alternative is starting the
    // real vendor SDK inside a unit test and reading its options back, which
    // means initialising it against a live DSN to learn something a scan settles
    // for free.

    /// Fields that no adapter applies, each with the reason it cannot.
    /// Anything not listed here must appear in its adapter.
    private static let telemetryFieldsAppliedElsewhere: [String: String] = [
        "eventExpiry": "applied by EconTelemetry's own queue, not by PostHog",
        "rawEventRetentionDays": "a PostHog project setting; recorded here so the privacy answers and the project agree",
        "aggregateRetentionMonths": "same — server-side retention, nothing to apply on device",
    ]

    private static let diagnosticsFieldsAppliedElsewhere: [String: String] = [
        "rawRetentionDays": "a Sentry project setting; recorded here so the privacy answers and the project agree",
    ]

    func testEveryTelemetryConfigurationFieldIsAppliedByThePostHogAdapter() throws {
        let adapter = try adapterSource("PostHogTelemetryTransport.swift")
        for field in fieldNames(of: TelemetryConfiguration()) {
            if let reason = Self.telemetryFieldsAppliedElsewhere[field] {
                XCTAssertFalse(reason.isEmpty)
                continue
            }
            XCTAssertTrue(adapter.contains("configuration.\(field)"),
                          "TelemetryConfiguration.\(field) is declared but never applied to PostHogConfig — "
                            + "the SDK keeps its own default, which for several of these is ON")
        }
        XCTAssertEqual(TelemetryConfiguration().personProfiles, .never)
    }

    /// The comment stripper above is only sound because neither adapter hides a
    /// `//` or `/*` inside a string literal, where stripping would eat real code.
    /// Both files are URL-free by design (the host and DSN arrive as parameters),
    /// so this holds today; if a literal URL ever lands in one, this fails and
    /// the stripper has to grow a lexer before the scan can be trusted again.
    func testAdaptersContainNoCommentMarkersInsideStringLiterals() throws {
        for name in ["PostHogTelemetryTransport.swift", "SentryDiagnosticsTransport.swift"] {
            let stripped = try adapterSource(name)
            for line in stripped.split(separator: "\n") where line.contains("\"") {
                XCTAssertFalse(line.contains("//") || line.contains("/*"),
                               "\(name) has a comment marker inside code/string text: \(line)")
            }
        }
    }

    /// Proves the scan reads code, not prose: a commented-out application must
    /// NOT satisfy it. Without this, `strippingComments` could regress to a raw
    /// read and every field test would still pass.
    func testACommentedOutApplicationDoesNotSatisfyTheScan() {
        let source = """
        // config.enableSwizzling = configuration.swizzling
        /* config.sessionReplay = configuration.sessionReplay */
        config.maxBatchSize = configuration.maxBatchSize
        """
        let stripped = Self.strippingComments(source)
        XCTAssertFalse(stripped.contains("configuration.swizzling"),
                       "a line comment must not count as applying the field")
        XCTAssertFalse(stripped.contains("configuration.sessionReplay"),
                       "a block comment must not count as applying the field")
        XCTAssertTrue(stripped.contains("configuration.maxBatchSize"),
                      "real code must survive the strip")
    }

    /// The identity half of the same problem. Under `personProfiles = .never`,
    /// posthog-ios 3.71.4 IGNORES `identify` outright (PostHogSDK.identify bails
    /// at `requirePersonProcessing`), so an adapter that calls it has not chosen
    /// the id — it has only made the app believe it did, while events are keyed
    /// by the SDK's anonymous id and Settings shows something else entirely.
    func testTheAdapterReadsTheIdBackInsteadOfCallingIdentify() throws {
        let adapter = try adapterSource("PostHogTelemetryTransport.swift")
        XCTAssertFalse(adapter.contains("PostHogSDK.shared.identify"),
                       "identify is a no-op under personProfiles = .never — calling it only hides "
                        + "which id is really on the wire")
        XCTAssertTrue(adapter.contains("PostHogSDK.shared.getDistinctId()"),
                      "the displayed id must be read back from the SDK, not assumed")
        XCTAssertTrue(adapter.contains("PostHogSDK.shared.optOut()"),
                      "the opt-out must reach the SDK, not just this app's queue")
        XCTAssertTrue(adapter.contains("PostHogLocalStore.purge"),
                      "reset() and close() leave the queue on disk — the opt-out must delete it")
    }

    func testEveryDiagnosticsConfigurationFieldIsAppliedBySentryAdapter() throws {
        let adapter = try adapterSource("SentryDiagnosticsTransport.swift")
        for field in fieldNames(of: DiagnosticsConfiguration()) {
            if let reason = Self.diagnosticsFieldsAppliedElsewhere[field] {
                XCTAssertFalse(reason.isEmpty)
                continue
            }
            XCTAssertTrue(adapter.contains("configuration.\(field)"),
                          "DiagnosticsConfiguration.\(field) is declared but never applied to SentryOptions")
        }
    }

    /// The four PostHog flags and four Sentry flags held at their reviewed
    /// values. The scan above proves they are *applied*; this proves the value
    /// being applied is still the one that was reviewed.
    func testTheReviewedOffSwitchesAreStillOff() {
        let telemetry = TelemetryConfiguration()
        XCTAssertFalse(telemetry.errorTracking, "Sentry is the app's only crash owner")
        XCTAssertFalse(telemetry.captureLogs)
        XCTAssertFalse(telemetry.sendTracingHeaders,
                       "tracing headers would stamp our anonymous id onto third-party requests — "
                        + "in this app that includes the ad stack")
        XCTAssertFalse(telemetry.swizzling)
        XCTAssertFalse(telemetry.captureApplicationLifecycleEvents)
        XCTAssertFalse(telemetry.captureScreenViews)
        XCTAssertFalse(telemetry.captureElementInteractions)
        XCTAssertFalse(telemetry.sessionReplay)

        let diagnostics = DiagnosticsConfiguration()
        XCTAssertFalse(diagnostics.enableSessionReplay)
        XCTAssertFalse(diagnostics.enableAppLaunchProfiling)
        XCTAssertFalse(diagnostics.captureLogs)
        XCTAssertEqual(diagnostics.maxBreadcrumbs, 0)
        // The three the SDK defaults to ON. A session envelope is a per-launch
        // usage record, not a crash, and Settings + the App Store answers both
        // say EconByte sends crash reports — so "crash-only" rests on this line.
        XCTAssertFalse(diagnostics.enableAutoSessionTracking,
                       "sentry-cocoa defaults sessions ON; a session is usage data, not a crash")
        XCTAssertFalse(diagnostics.enableAppHangTracking)
        XCTAssertFalse(diagnostics.enableWatchdogTerminationTracking)
        XCTAssertEqual(diagnostics.tracesSampleRate, 0)
        XCTAssertEqual(diagnostics.profilesSampleRate, 0)
        XCTAssertFalse(diagnostics.attachScreenshot)
        XCTAssertFalse(diagnostics.attachViewHierarchy)
        XCTAssertTrue(diagnostics.scrubServerSideIP,
                      "the one that is ON: Sentry must never store the client IP")
        XCTAssertFalse(diagnostics.sendDefaultPii,
                       "scrubServerSideIP is carried by sendDefaultPii=false, which serialises infer_ip=never")
    }

    // MARK: - The LIVE Sentry beforeSend, not a copy of it
    //
    // Until 1.1.2 `DiagnosticsFilter` was a detached model: the suite ran it over
    // hand-built values while the real `beforeSend` did its own two-line strip,
    // so the model could stay green while the shipped path did something else.
    // `SentryDiagnosticsTransport.screen` IS the closure the SDK calls; these
    // tests run it, substituting only the vendor envelope object.

    /// Stands in for `SentryEvent`. `stripClearsUser` exists so a strip that
    /// silently fails can be simulated — that is the case the post-condition in
    /// `screen` is there to catch.
    private final class FakeEnvelope: DiagnosticsEnvelope {
        var scrubbableTags: [String: String]?
        var carriesUserObject: Bool
        var carriesBreadcrumbs: Bool
        var carriesExtra: Bool
        var stripCount = 0
        var stripClearsUser = true
        var stripClearsExtra = true

        init(tags: [String: String]? = nil,
             user: Bool = true,
             breadcrumbs: Bool = false,
             extra: Bool = false) {
            scrubbableTags = tags
            carriesUserObject = user
            carriesBreadcrumbs = breadcrumbs
            carriesExtra = extra
        }

        func stripIdentifyingFields() {
            stripCount += 1
            if stripClearsUser { carriesUserObject = false }
            if stripClearsExtra { carriesExtra = false }
            carriesBreadcrumbs = false
        }
    }

    /// The normal path. sentry-cocoa 8.58.4 stamps its own installation id as
    /// `event.user` BEFORE beforeSend runs (SentryClient.processEvent calls
    /// setUserIdIfNoUserSet, then the callback), so an envelope arriving here
    /// with a user object is the rule, not the exception — and it must be
    /// stripped and SENT, not dropped. Dropping it would silently delete 100% of
    /// EconByte's crash reports.
    func testTheLiveScreenStripsTheSDKUserBreadcrumbsAndExtrasAndStillSends() {
        let envelope = FakeEnvelope(tags: ["release": "1.1.2", "os_major": "18"],
                                    user: true, breadcrumbs: true, extra: true)

        let screened = SentryDiagnosticsTransport.screen(envelope)

        XCTAssertNotNil(screened, "a crash carrying only the SDK's own user object must still be sent")
        XCTAssertEqual(envelope.stripCount, 1)
        XCTAssertFalse(envelope.carriesUserObject, "the SDK installation id never leaves")
        XCTAssertFalse(envelope.carriesBreadcrumbs, "app breadcrumbs never leave")
        XCTAssertFalse(envelope.carriesExtra, "free-form extras never leave")
        XCTAssertEqual(envelope.scrubbableTags, ["release": "1.1.2", "os_major": "18"],
                       "the six declared tags are the one thing the filter keeps")
    }

    /// The post-condition. If the strip ever stops working — a future SDK that
    /// repopulates the user after the callback edits it — the envelope is
    /// dropped rather than sent with an identity on it.
    func testTheLiveScreenDropsAnEnvelopeWhoseUserSurvivesTheStrip() {
        let envelope = FakeEnvelope(user: true)
        envelope.stripClearsUser = false

        XCTAssertNil(SentryDiagnosticsTransport.screen(envelope),
                     "a user object that survives the strip means the strip is broken — drop it")
    }

    func testTheLiveScreenDropsAnEnvelopeWhoseExtrasSurviveTheStrip() {
        let envelope = FakeEnvelope(user: true, extra: true)
        envelope.stripClearsExtra = false

        XCTAssertNil(SentryDiagnosticsTransport.screen(envelope),
                     "an extras payload that survives the strip is an unfiltered free-text channel")
    }

    /// The live branch of the tag rule: a tag outside `DiagnosticsTag` drops the
    /// whole envelope rather than shipping it.
    func testTheLiveScreenDropsAnUndeclaredTag() {
        let envelope = FakeEnvelope(tags: ["card_id": "inf-001", "release": "1.1.2"])

        XCTAssertNil(SentryDiagnosticsTransport.screen(envelope),
                     "a tag naming card content must never be sent, even attached to a crash")
    }

    func testTheLiveScreenLeavesNoEmptyTagDictionaryBehind() {
        let envelope = FakeEnvelope(tags: [:])
        XCTAssertNotNil(SentryDiagnosticsTransport.screen(envelope))
        XCTAssertNil(envelope.scrubbableTags, "an empty tag map is cleared rather than sent as {}")
    }

    // MARK: - The Sentry beforeSend model drops what it says it drops

    func testDiagnosticsFilterDropsAUserObjectAnAttachmentAndAnUndeclaredTag() {
        XCTAssertEqual(DiagnosticsFilter.beforeSend(DiagnosticEvent(userID: "someone")),
                       .drop(.userIdentity))
        XCTAssertEqual(DiagnosticsFilter.beforeSend(DiagnosticEvent(attachments: ["screen.png"])),
                       .drop(.attachment("screen.png")))
        XCTAssertEqual(DiagnosticsFilter.beforeSend(DiagnosticEvent(tags: ["card_id": "inf-001"])),
                       .drop(.disallowedTag("card_id")))
    }

    func testDiagnosticsFilterStripsBreadcrumbsAndTheServerIP() {
        let event = DiagnosticEvent(tags: ["release": "1.1.2", "os_major": "18"],
                                    breadcrumbs: ["viewed a card"],
                                    serverIP: "203.0.113.7")
        guard case let .send(scrubbed) = DiagnosticsFilter.beforeSend(event) else {
            return XCTFail("an event carrying only declared tags must be sent")
        }
        XCTAssertTrue(scrubbed.breadcrumbs.isEmpty, "app breadcrumbs never leave")
        XCTAssertNil(scrubbed.serverIP, "the client IP is never stored")
        XCTAssertEqual(scrubbed.tags, event.tags)
    }

    // MARK: - The privacy manifest matches what the app now collects

    /// `PrivacyInfo.xcprivacy` is the machine-readable half of the App Store
    /// privacy answers, and 1.1.2 is the release that starts collecting the
    /// app's *own* analytics. A manifest that still describes 1.1.1 is a false
    /// statement shipped in the binary, so it is asserted here rather than
    /// eyeballed at submission.
    func testPrivacyManifestDeclaresCrashDataProductInteractionAndTheAnalyticsIdentifier() throws {
        let manifest = try privacyManifest()

        // 1.1.2 build 13: the app tracks, and says so. Builds 10-12 answered
        // `false` here on the reasoning that non-personalized ads need no IDFA;
        // App Review rejected build 12 under 5.1.2(i) because the app-level
        // App Privacy label says Device ID is used to track, and the label
        // cannot be moved (ASC refuses while an ATT-carrying binary is live).
        // Asserted in full by `testThePrivacyManifestDeclaresTheAppTracks`;
        // repeated here so this test cannot pass against the old shape either.
        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, true)
        XCTAssertEqual(manifest["NSPrivacyTrackingDomains"] as? [String],
                       ["googleads.g.doubleclick.net"])

        let declared = manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]] ?? []
        let byType = Dictionary(uniqueKeysWithValues: declared.compactMap { entry -> (String, [String: Any])? in
            guard let type = entry["NSPrivacyCollectedDataType"] as? String else { return nil }
            return (type, entry)
        })

        // The three types 1.1.2 adds. All three are NOT linked and NOT tracking:
        // whatever the ad SDK does, nothing this app collects itself is joined to
        // an identity or used to track.
        for type in ["NSPrivacyCollectedDataTypeCrashData",
                     "NSPrivacyCollectedDataTypeProductInteraction",
                     "NSPrivacyCollectedDataTypeUserID"] {
            guard let entry = byType[type] else {
                return XCTFail("\(type) is collected but not declared in PrivacyInfo.xcprivacy")
            }
            XCTAssertEqual(entry["NSPrivacyCollectedDataTypeLinked"] as? Bool, false,
                           "\(type) is not linked to an identity — the app has no accounts")
            XCTAssertEqual(entry["NSPrivacyCollectedDataTypeTracking"] as? Bool, false,
                           "\(type) is never used for tracking")
            let purposes = entry["NSPrivacyCollectedDataTypePurposes"] as? [String] ?? []
            XCTAssertFalse(purposes.isEmpty, "\(type) must state why it is collected")
        }

        let crashPurposes = byType["NSPrivacyCollectedDataTypeCrashData"]?[
            "NSPrivacyCollectedDataTypePurposes"] as? [String] ?? []
        XCTAssertTrue(crashPurposes.contains("NSPrivacyCollectedDataTypePurposeAppFunctionality"))

        let interactionPurposes = byType["NSPrivacyCollectedDataTypeProductInteraction"]?[
            "NSPrivacyCollectedDataTypePurposes"] as? [String] ?? []
        XCTAssertEqual(interactionPurposes, ["NSPrivacyCollectedDataTypePurposeAnalytics"])

        // The per-install analytics UUID. Apple's Device ID is "the device ID,
        // advertising ID, or other device-level ID"; this one is minted by the
        // app, resets when the user opts out, and does not survive a reinstall —
        // an *assigned* id, which is Apple's User ID. Declared rather than argued
        // away: it rides on every event we send.
        let userIDPurposes = byType["NSPrivacyCollectedDataTypeUserID"]?[
            "NSPrivacyCollectedDataTypePurposes"] as? [String] ?? []
        XCTAssertEqual(userIDPurposes, ["NSPrivacyCollectedDataTypePurposeAnalytics"])

        // The two ad-side rows. Both are declared as used for tracking, which is
        // what the published label says and what GoogleMobileAds 12.14.0's own
        // manifest says of the device identifier it reads. Neither is linked to
        // an identity: the app has no accounts, and the published label answers
        // "device IDs are not linked to the user's identity".
        for type in ["NSPrivacyCollectedDataTypeDeviceID",
                     "NSPrivacyCollectedDataTypeAdvertisingData"] {
            guard let entry = byType[type] else {
                return XCTFail("\(type) is an ad-side row the label declares — it must be in the manifest")
            }
            XCTAssertEqual(entry["NSPrivacyCollectedDataTypeTracking"] as? Bool, true,
                           "\(type) is declared 'used to track' on the App Store label")
            XCTAssertEqual(entry["NSPrivacyCollectedDataTypeLinked"] as? Bool, false,
                           "\(type) is not linked to an identity")
            XCTAssertEqual(entry["NSPrivacyCollectedDataTypePurposes"] as? [String],
                           ["NSPrivacyCollectedDataTypePurposeThirdPartyAdvertising"])
        }
    }

    /// The Info.plist keys the credentials read. If a key is renamed on one side
    /// only, the app silently stops finding its own configuration and every build
    /// ships inert — which looks exactly like "working, but nobody used it".
    func testTheInfoPlistCarriesTheThreeInstrumentationKeys() throws {
        let info = try XCTUnwrap(Bundle.main.infoDictionary)
        for key in [TelemetryCredentials.infoPlistKey,
                    TelemetryCredentials.hostInfoPlistKey,
                    DiagnosticsCredentials.infoPlistKey] {
            XCTAssertNotNil(info[key],
                            "\(key) is missing from the built Info.plist — the xcconfig injection is broken")
        }
    }

    // MARK: - The binary is built from the SDKs that were reviewed
    //
    // Every privacy claim in this file is a claim about three specific vendor
    // builds: posthog-ios 3.71.4, sentry-cocoa 8.58.4, GoogleMobileAds 12.14.0.
    // A version range means the archive can contain a build nobody looked at —
    // and GoogleMobileAds is the SDK carrying the app's only tracking
    // declaration, so it is the worst one to leave floating.

    func testEveryVendorSDKIsPinnedToAnExactVersion() throws {
        let project = try String(
            contentsOf: repoRoot().appendingPathComponent("EconByte.xcodeproj/project.pbxproj"),
            encoding: .utf8)
        for looseKind in ["upToNextMajorVersion", "upToNextMinorVersion", "branch", "revision"] {
            XCTAssertFalse(project.contains(looseKind),
                           "a \(looseKind) package requirement lets an unreviewed SDK build into "
                            + "the archive — pin every dependency exactly")
        }
        XCTAssertEqual(project.components(separatedBy: "kind = exactVersion;").count - 1, 3,
                       "all three vendor packages must be pinned exactly")
    }

    /// The resolved graph is committed, so a fresh clone and the machine that
    /// archived the build resolve the same bytes.
    func testPackageResolvedIsCommittedAndHoldsTheReviewedVersions() throws {
        let url = repoRoot().appendingPathComponent(
            "EconByte.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved")
        let parsed = try JSONSerialization.jsonObject(with: try Data(contentsOf: url))
        let pins = try XCTUnwrap((parsed as? [String: Any])?["pins"] as? [[String: Any]])

        var versions: [String: String] = [:]
        for pin in pins {
            guard let identity = pin["identity"] as? String,
                  let version = (pin["state"] as? [String: Any])?["version"] as? String else { continue }
            versions[identity] = version
        }

        XCTAssertEqual(versions["posthog-ios"], "3.71.4")
        XCTAssertEqual(versions["sentry-cocoa"], "8.58.4")
        XCTAssertEqual(versions["swift-package-manager-google-mobile-ads"], "12.14.0")
    }

    // MARK: - The app tracks, and every artefact says so
    //
    // THIS SECTION WAS INVERTED IN 1.1.2 BUILD 13. Until build 12 it asserted
    // the opposite, and the reasoning was good: non-personalized ads do not need
    // the advertising identifier, so an ATT prompt bought nothing and a declared
    // tracking domain costs ad fill for every reader who declines. What that
    // reasoning missed is that the App Privacy label is an APP-LEVEL record and
    // is not ours alone to set:
    //
    //   * App Review rejected build 12 on 2026-09-07 under Guideline 5.1.2(i) —
    //     the label answers "Identifiers > Device ID: used to track you" and the
    //     binary never asks through ATT.
    //   * App Store Connect REFUSES to publish the label as not-tracking while a
    //     relevant binary carries `NSUserTrackingUsageDescription`, and the LIVE
    //     1.1.1 (build 8) does. The refusal was reproduced, and the edit was
    //     cancelled rather than falsified:
    //     ~/dudley-evidence-retention/econbyte/1.1.2-resubmission-2026-09-07/
    //   * GoogleMobileAds 12.14.0's own `PrivacyInfo.xcprivacy` declares
    //     `NSPrivacyCollectedDataTypeDeviceID` with `Tracking = true`. The
    //     aggregated privacy report Apple reads therefore says the app tracks
    //     regardless of what this app's own manifest claims — which is why
    //     build 12's `NSPrivacyTracking = false` was itself the incoherent half.
    //
    // So build 13 moves the binary to the label, which is Apple's own remedy #3.
    // These tests are the same contract as before, pointed the other way: one
    // per artefact (source manifest, built manifest, app source, source
    // Info.plist, built Info.plist, Mach-O load commands), so no single edit can
    // drop the prompt again while the label still says the app tracks.

    /// The manifest baked into the archive: the app tracks, and names the domain
    /// Apple's binary validation requires it to name.
    ///
    /// The domain is not a guess and not a preference. `NSPrivacyTracking = true`
    /// with an EMPTY `NSPrivacyTrackingDomains` is rejected at upload as an
    /// Invalid Binary — this app already learned that on 1.1.1 (lineage-B commit
    /// 58479fa, "declare AdMob tracking domain (fix Invalid Binary)"). The Google
    /// Mobile Ads SDK declares no tracking domains of its own (asserted in
    /// `testTheTrackingDomainIsTheOneTheAdSDKActuallyUses` against the built
    /// app's aggregated manifests), so the app must name the SDK's ad-serving
    /// domain itself, exactly as live build 8 does.
    func testThePrivacyManifestDeclaresTheAppTracks() throws {
        let manifest = try privacyManifest()

        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, true,
                       "the published App Privacy label answers 'Device ID: used to track you'; "
                        + "a manifest saying otherwise is the 5.1.2(i) rejection")
        XCTAssertEqual(manifest["NSPrivacyTrackingDomains"] as? [String],
                       ["googleads.g.doubleclick.net"],
                       "NSPrivacyTracking = true with no domain is an Invalid Binary at upload")

        // Only the two ad-side rows track. Everything the app itself collects —
        // its own analytics id, its own events, its own crash reports — is
        // still not tracking, and adding a third tracking row would silently
        // widen the label.
        let declared = manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]] ?? []
        let tracked = declared
            .filter { $0["NSPrivacyCollectedDataTypeTracking"] as? Bool == true }
            .compactMap { $0["NSPrivacyCollectedDataType"] as? String }
        XCTAssertEqual(Set(tracked), ["NSPrivacyCollectedDataTypeDeviceID",
                                      "NSPrivacyCollectedDataTypeAdvertisingData"],
                       "exactly the two ad-side rows may be declared as used for tracking")
    }

    /// The manifest that actually ships, read out of the built app rather than
    /// out of the source tree, together with every third-party manifest bundled
    /// beside it. This is the aggregate Apple's privacy report is built from,
    /// and it is the only place the SDK's own claims can be observed rather than
    /// assumed.
    func testTheTrackingDomainIsTheOneTheAdSDKActuallyUses() throws {
        let manifests = try builtPrivacyManifests()
        XCTAssertGreaterThanOrEqual(manifests.count, 2,
                                    "the app manifest plus at least one vendor manifest")

        let app = try XCTUnwrap(manifests["EconByte.app"], "the app's own manifest must ship")
        XCTAssertEqual(app["NSPrivacyTracking"] as? Bool, true)
        XCTAssertEqual(app["NSPrivacyTrackingDomains"] as? [String],
                       ["googleads.g.doubleclick.net"])

        // Every vendor manifest, examined rather than trusted: none of them
        // declares a tracking domain, which is exactly why the app must declare
        // one. If a future SDK version starts declaring its own, this fails and
        // the app's list is re-derived from it instead of being carried over.
        for (owner, manifest) in manifests where owner != "EconByte.app" {
            let domains = manifest["NSPrivacyTrackingDomains"] as? [String] ?? []
            XCTAssertTrue(domains.isEmpty,
                          "\(owner) now declares tracking domains \(domains) — the app's "
                           + "NSPrivacyTrackingDomains must be re-derived from the aggregate")
        }

        // The reason the app-level answer must be `true` at all: the ad SDK
        // declares the device identifier as used for tracking, so the aggregate
        // says the app tracks whatever the app's own manifest says.
        let vendorTracked = manifests
            .filter { $0.key != "EconByte.app" }
            .flatMap { (_, manifest) -> [String] in
                (manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]] ?? [])
                    .filter { $0["NSPrivacyCollectedDataTypeTracking"] as? Bool == true }
                    .compactMap { $0["NSPrivacyCollectedDataType"] as? String }
            }
        XCTAssertTrue(vendorTracked.contains("NSPrivacyCollectedDataTypeDeviceID"),
                      "GoogleMobileAds declares the device id as tracking; if that ever stops "
                       + "being true, the whole 5.1.2(i) argument should be re-opened")
    }

    /// Exactly one file may reach the framework. The prompt is an ordering rule
    /// enforced by `EconMonetization`, and an ATT call anywhere else — in the
    /// adapter, in a view, in a mock — is a second, ungated call site, which is
    /// the shape live build 8 shipped (it asked from `presentInterstitial()`,
    /// after the first ad request had already gone out).
    func testOnlyTheTrackingAuthorizationAdapterReachesTheFramework() throws {
        var referencing: [String] = []
        for url in try appSourceFiles() {
            let code = Self.strippingComments(try String(contentsOf: url, encoding: .utf8))
            if code.contains("AppTrackingTransparency") || code.contains("ATTrackingManager") {
                referencing.append(url.lastPathComponent)
            }
        }
        XCTAssertEqual(referencing, ["EconTrackingAuthorization.swift"],
                       "only the ATT adapter may name the framework; found \(referencing)")
    }

    /// The usage description is what the reader reads in the system dialog, and
    /// the one artefact a reviewer can check without running anything. Both
    /// copies are asserted: the source plist is what the next edit starts from,
    /// the built plist is what ships.
    ///
    /// The string is asserted for its CLAIM, not just its presence. Every ad
    /// request carries `npa=1` (`testEveryAdRequestIsNonPersonalized`), so a
    /// string promising personalized ads would be a promise the binary does not
    /// keep — which is the same class of defect as the label mismatch that
    /// caused the rejection in the first place.
    func testBothInfoPlistsCarryAnHonestTrackingUsageDescription() throws {
        let source = try sourceInfoPlist()["NSUserTrackingUsageDescription"] as? String
        let built = Bundle.main.infoDictionary?["NSUserTrackingUsageDescription"] as? String

        let purpose = try XCTUnwrap(source, "EconByte/Info.plist must declare why it prompts")
        XCTAssertEqual(built, purpose,
                       "the built Info.plist must carry the same string the source declares")
        XCTAssertFalse(purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertTrue(purpose.contains("measured"),
                      "the string must say what authorization is actually used for")
        XCTAssertTrue(purpose.lowercased().contains("does not personalize"),
                      "every request is npa=1, so the string must not imply personalization")
        // 1.1.3 build 16 maps an ATT Allow onto the analytics switch, so the
        // prompt itself must say that Allow turns on anonymous usage stats.
        XCTAssertTrue(purpose.lowercased().contains("anonymous usage"),
                      "the purpose string must disclose that Allow turns on anonymous usage stats")
    }

    /// The strongest form of the claim: the app target's own compiled image
    /// links the framework, so the prompt is genuinely reachable from shipped
    /// code rather than only from a source file that happens to mention it.
    ///
    /// Both of the app's own Mach-O images are scanned. A Debug build puts
    /// essentially all of the app's code in `EconByte.debug.dylib` and leaves a
    /// ~58 KB launcher as `Bundle.main.executableURL`, so scanning only the main
    /// executable would pass — or, here, fail — for the wrong reason. It is
    /// enough for ONE of the app's own images to carry the load command;
    /// `Frameworks/` is deliberately not scanned, because GoogleMobileAds
    /// weak-links AppTrackingTransparency itself and vendor linkage is not this
    /// app's claim to make.
    func testTheAppBinaryLinksAppTrackingTransparency() throws {
        let bundle = Bundle.main.bundleURL
        let executable = try XCTUnwrap(Bundle.main.executableURL,
                                       "the test host has no executable to inspect")
        let images = [executable, bundle.appendingPathComponent("EconByte.debug.dylib")]
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        XCTAssertFalse(images.isEmpty, "no app image to inspect")

        let load = "AppTrackingTransparency.framework/AppTrackingTransparency"
        let linked = try images.contains { url in
            try Data(contentsOf: url).range(of: Data(load.utf8)) != nil
        }
        XCTAssertTrue(linked,
                      "no app image links AppTrackingTransparency — with no framework linked "
                       + "the prompt is unreachable and 5.1.2(i) is unfixed")
    }

    /// Restoring ATT does NOT relax this, and that is the point of the test in
    /// build 13. `config/app-factory/monetization-policy.json` sets
    /// `adsPolicy.personalizedAdsMode = "disabled"` portfolio-wide; this asserts
    /// that policy is expressed in the app both ways Google offers it — the
    /// SDK-level switch and the per-request extra — so dropping one cannot
    /// silently re-enable personalization. Scanned with comments stripped, for
    /// the same reason `adapterSource` is: a commented-out line must not count.
    func testEveryAdRequestIsNonPersonalized() throws {
        let source = Self.strippingComments(
            try String(contentsOf: repoRoot().appendingPathComponent("EconByte/Services/AdManager.swift"),
                       encoding: .utf8))
        XCTAssertTrue(source.contains("publisherPrivacyPersonalizationState = .disabled"),
                      "the SDK-level personalization switch must be set before the SDK starts")
        XCTAssertTrue(source.contains("request.register(extras)"),
                      "the non-personalized extras must actually be registered on the request")

        // RECONCILED (1.1.2): the extras themselves live in lineage A's policy
        // layer, not in the adapter — `AdManager` is a provider adapter and
        // every eligibility and request rule sits in `EconMonetization`, which
        // is what makes the ad policy testable without the SDK. So the literal
        // is asserted where it is written, and the adapter is asserted to
        // register whatever the policy hands it. Both halves are required: a
        // policy nobody registers is as useless as a registration with no policy.
        let policy = Self.strippingComments(
            try String(contentsOf: repoRoot().appendingPathComponent("EconByte/Services/EconMonetization.swift"),
                       encoding: .utf8))
        XCTAssertTrue(policy.contains("\"npa\": \"1\""),
                      "every ad request must carry the npa=1 extra")
        XCTAssertTrue(policy.contains("\"rdp\": \"1\""),
                      "and the restricted-data-processing extra 1.1 shipped with")
    }

    // MARK: - Source helpers

    private func fieldNames<T>(of value: T) -> [String] {
        Mirror(reflecting: value).children.compactMap(\.label)
    }

    private func repoRoot(file: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(file)").deletingLastPathComponent().deletingLastPathComponent()
    }

    /// The adapter's source with every comment removed.
    ///
    /// Stripping comments is the whole point: these adapters are heavily
    /// commented, and each comment names the very field the line below it
    /// applies. A raw-text scan therefore passes on a field whose application
    /// has been commented OUT — the mutation `// config.enableSwizzling =
    /// configuration.swizzling` left the string in place, the scan found it, and
    /// the guard reported an applied field that the SDK never receives. That is
    /// exactly the failure this test exists to catch, so the scan must see code
    /// only.
    private func adapterSource(_ name: String, file: StaticString = #filePath) throws -> String {
        let url = repoRoot(file: file)
            .appendingPathComponent("EconByte/Services").appendingPathComponent(name)
        return Self.strippingComments(try String(contentsOf: url, encoding: .utf8))
    }

    /// Removes `//` line comments and `/* … */` block comments. Deliberately
    /// simple: neither adapter contains a string literal holding `//` or `/*`
    /// (`testAdaptersContainNoCommentMarkersInsideStringLiterals` keeps that
    /// true), so a full Swift lexer would buy nothing here.
    static func strippingComments(_ source: String) -> String {
        var out = ""
        var inBlockComment = false

        for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
            var kept = ""
            let characters = Array(line)
            var i = 0
            while i < characters.count {
                let pair = i + 1 < characters.count ? String([characters[i], characters[i + 1]]) : ""
                if inBlockComment {
                    if pair == "*/" { inBlockComment = false; i += 2 } else { i += 1 }
                    continue
                }
                if pair == "/*" { inBlockComment = true; i += 2; continue }
                if pair == "//" { break }          // rest of the line is a comment
                kept.append(characters[i])
                i += 1
            }
            out += kept + "\n"
        }
        return out
    }

    /// Every Swift file in the app target's source tree.
    private func appSourceFiles(file: StaticString = #filePath) throws -> [URL] {
        let root = repoRoot(file: file).appendingPathComponent("EconByte")
        let walker = try XCTUnwrap(FileManager.default.enumerator(at: root,
                                                                  includingPropertiesForKeys: nil))
        let files = walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty, "no Swift sources found under \(root.path)")
        return files
    }

    /// The Info.plist as committed, before the build substitutes its variables.
    /// Asserted alongside `Bundle.main` because the built copy is the one the
    /// reviewer sees and the source copy is the one the next edit starts from.
    private func sourceInfoPlist(file: StaticString = #filePath) throws -> [String: Any] {
        let url = repoRoot(file: file).appendingPathComponent("EconByte/Info.plist")
        let parsed = try PropertyListSerialization.propertyList(from: try Data(contentsOf: url),
                                                               format: nil)
        return try XCTUnwrap(parsed as? [String: Any], "Info.plist is not a plist dictionary")
    }

    /// Every `PrivacyInfo.xcprivacy` inside the BUILT app bundle, keyed by the
    /// bundle that owns it — the app's own manifest under `EconByte.app`, and
    /// one entry per embedded framework. This is the set Xcode aggregates into
    /// the archive's privacy report, so a claim about "the SDK's own manifest"
    /// can be checked against the SDK rather than against a memory of its docs.
    private func builtPrivacyManifests() throws -> [String: [String: Any]] {
        let bundle = Bundle.main.bundleURL
        var found: [String: [String: Any]] = [:]

        func load(_ url: URL, owner: String) throws {
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            let parsed = try PropertyListSerialization.propertyList(
                from: try Data(contentsOf: url), format: nil)
            found[owner] = try XCTUnwrap(parsed as? [String: Any],
                                         "\(owner) has a PrivacyInfo.xcprivacy that is not a dictionary")
        }

        try load(bundle.appendingPathComponent("PrivacyInfo.xcprivacy"), owner: "EconByte.app")

        let frameworks = bundle.appendingPathComponent("Frameworks")
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: frameworks, includingPropertiesForKeys: nil)) ?? []
        for framework in contents where framework.pathExtension == "framework" {
            try load(framework.appendingPathComponent("PrivacyInfo.xcprivacy"),
                     owner: framework.lastPathComponent)
        }
        return found
    }

    private func privacyManifest(file: StaticString = #filePath) throws -> [String: Any] {
        let url = repoRoot(file: file)
            .appendingPathComponent("EconByte/Resources/PrivacyInfo.xcprivacy")
        let data = try Data(contentsOf: url)
        let parsed = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try XCTUnwrap(parsed as? [String: Any], "PrivacyInfo.xcprivacy is not a plist dictionary")
    }
}
