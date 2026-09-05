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
        let transport = PostHogTelemetryTransport(host: TelemetryCredentials.defaultHost)
        let telemetry = EconTelemetry(transport: transport, apiKey: nil, defaults: defaults)

        telemetry.setAnalyticsConsent(true)
        telemetry.capture(TelemetryEvent("app_opened_v1", ["app_version": .string("1.1.2")]))
        await telemetry.flush()

        XCTAssertFalse(transport.isStarted, "no key → the PostHog SDK is never started")
        XCTAssertFalse(telemetry.isAnalyticsEnabled)
        XCTAssertNil(telemetry.analyticsIdentity)
    }

    func testSentryAdapterIsFailSoftWithoutADSN() {
        let transport = SentryDiagnosticsTransport()
        let diagnostics = EconDiagnostics(transport: transport, dsn: nil, defaults: defaults)

        diagnostics.setDiagnosticsConsent(true)

        XCTAssertFalse(transport.isStarted, "no DSN → the Sentry SDK is never started")
        XCTAssertFalse(diagnostics.isDiagnosticsEnabled)
        XCTAssertEqual(diagnostics.lastRefusal, .noDSNConfigured)
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
        XCTAssertTrue(diagnostics.scrubServerSideIP,
                      "the one that is ON: Sentry must never store the client IP")
        XCTAssertFalse(diagnostics.sendDefaultPii,
                       "scrubServerSideIP is carried by sendDefaultPii=false, which serialises infer_ip=never")
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

        // UNCHANGED from 1.1.1, and deliberately so: EconByte serves AdMob
        // interstitials and prompts for ATT, so the app as a whole DOES track.
        // The analytics added in 1.1.2 are not what makes this true.
        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, true,
                       "the AdMob declaration from 1.1.1 must survive this release")
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

        // The ad SDK's device identifier, untouched by 1.1.2 and still the one
        // entry that IS tracking. Asserted so this release cannot silently widen
        // or narrow a published answer.
        guard let deviceID = byType["NSPrivacyCollectedDataTypeDeviceID"] else {
            return XCTFail("the AdMob Device ID declaration from 1.1.1 is missing")
        }
        XCTAssertEqual(deviceID["NSPrivacyCollectedDataTypeTracking"] as? Bool, true)
        XCTAssertEqual(deviceID["NSPrivacyCollectedDataTypePurposes"] as? [String],
                       ["NSPrivacyCollectedDataTypePurposeThirdPartyAdvertising"])
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

    // MARK: - Source helpers

    private func fieldNames<T>(of value: T) -> [String] {
        Mirror(reflecting: value).children.compactMap(\.label)
    }

    private func repoRoot(file: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(file)").deletingLastPathComponent().deletingLastPathComponent()
    }

    private func adapterSource(_ name: String, file: StaticString = #filePath) throws -> String {
        let url = repoRoot(file: file)
            .appendingPathComponent("EconByte/Services").appendingPathComponent(name)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func privacyManifest(file: StaticString = #filePath) throws -> [String: Any] {
        let url = repoRoot(file: file)
            .appendingPathComponent("EconByte/Resources/PrivacyInfo.xcprivacy")
        let data = try Data(contentsOf: url)
        let parsed = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try XCTUnwrap(parsed as? [String: Any], "PrivacyInfo.xcprivacy is not a plist dictionary")
    }
}
