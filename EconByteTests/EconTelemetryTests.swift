import XCTest
@testable import EconByte

/// EconByte 1.1.2 — the analytics/diagnostics behaviour tests.
///
/// `InstrumentationPrivacyTests` covers what can never be sent. This file covers
/// what happens: the default-on posture and its opt-out, the bounded queue, the
/// fail-soft path, and the two guards that stop the schema from describing
/// measurement the app does not actually perform.
@MainActor
final class EconTelemetryTests: XCTestCase {

    // MARK: - Harness

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "eb.telemetry.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    /// Records every transport-facing call so a test can prove the analytics SDK
    /// was never started and no batch was ever sent.
    private final class SpyTelemetryTransport: TelemetryTransporting {
        var startCount = 0
        var stopCount = 0
        var startedIdentity: String?
        var lastConfiguration: TelemetryConfiguration?
        var sentBatches: [[TelemetryEvent]] = []
        /// Set false to simulate an offline flush.
        var sendSucceeds = true

        private(set) var isStarted = false

        func start(apiKey: String, configuration: TelemetryConfiguration, distinctID: String) {
            startCount += 1
            isStarted = true
            startedIdentity = distinctID
            lastConfiguration = configuration
        }

        func send(_ events: [TelemetryEvent]) async -> Bool {
            sentBatches.append(events)
            return sendSucceeds
        }

        func stopAndClearLocalState() {
            stopCount += 1
            isStarted = false
        }

        var sentEvents: [TelemetryEvent] { sentBatches.flatMap { $0 } }
    }

    private final class SpyDiagnosticsTransport: DiagnosticsTransporting {
        var startCount = 0
        var closeCount = 0
        var clearCount = 0
        var cacheRemovalGuaranteed = true
        private(set) var isStarted = false

        var guaranteesLocalCacheRemoval: Bool { cacheRemovalGuaranteed }
        func start(dsn: String, configuration: DiagnosticsConfiguration) {
            startCount += 1
            isStarted = true
        }
        func close() { closeCount += 1; isStarted = false }
        @discardableResult func clearLocalEnvelopeCache() -> Bool { clearCount += 1; return true }
    }

    private func makeTelemetry(transport: SpyTelemetryTransport,
                               apiKey: String? = "phc_test_key_not_a_real_project",
                               now: @escaping () -> Date = Date.init,
                               identities: [String] = []) -> EconTelemetry {
        var remaining = identities
        return EconTelemetry(
            transport: transport,
            apiKey: apiKey,
            defaults: defaults,
            now: now,
            identityFactory: { remaining.isEmpty ? UUID().uuidString : remaining.removeFirst() }
        )
    }

    // MARK: - Default-on, opt-out, and identity

    /// A fresh install with a configured project sends from the first launch;
    /// the Settings switch is the way out, not the way in.
    func testAnalyticsIsOnByDefaultOnAFreshInstall() async {
        let spy = SpyTelemetryTransport()
        let telemetry = makeTelemetry(transport: spy, identities: ["identity-one"])

        XCTAssertTrue(telemetry.isAnalyticsEnabled,
                      "analytics ship on; the user opts out rather than in")
        XCTAssertEqual(telemetry.analyticsIdentity, "identity-one")
        XCTAssertEqual(spy.startCount, 1, "the transport starts once, at construction")
        XCTAssertEqual(spy.startedIdentity, "identity-one",
                       "the distinct id is the app-scoped random UUID, never a device id")

        telemetry.capture(TelemetryEvent("app_opened_v1", ["app_version": .string("1.1.2 (9)")]))
        await telemetry.flush()

        XCTAssertEqual(spy.sentEvents.map(\.name), ["app_opened_v1"])
    }

    /// The opt-out has to be immediate *and* durable: no further event may be
    /// queued after the switch, and the next launch must not quietly re-enable.
    func testOptingOutStopsSendingImmediatelyAndSurvivesRelaunch() async {
        let firstRun = SpyTelemetryTransport()
        let telemetry = makeTelemetry(transport: firstRun)
        XCTAssertTrue(telemetry.isAnalyticsEnabled)

        telemetry.setAnalyticsConsent(false)

        telemetry.capture(TelemetryEvent("app_opened_v1", ["app_version": .string("1.1.2 (9)")]))
        await telemetry.flush()
        XCTAssertEqual(telemetry.queuedEventCount, 0, "capture stops before the call returns")
        XCTAssertEqual(firstRun.sentBatches.count, 0, "nothing is sent after the opt-out")
        XCTAssertEqual(firstRun.stopCount, 1, "the vendor SDK is torn down, not just muted")

        // Relaunch: a new facade over the same stored defaults.
        let secondRun = SpyTelemetryTransport()
        let relaunched = makeTelemetry(transport: secondRun)

        XCTAssertFalse(relaunched.isAnalyticsEnabled, "the opt-out persists across launches")
        XCTAssertEqual(secondRun.startCount, 0, "an opted-out launch never starts the SDK")
        XCTAssertNil(relaunched.analyticsIdentity)

        relaunched.capture(TelemetryEvent("app_opened_v1", ["app_version": .string("1.1.2 (9)")]))
        await relaunched.flush()
        XCTAssertEqual(secondRun.sentBatches.count, 0)
    }

    /// And back on again — with a new identity, so the two sides of an opt-out
    /// cannot be stitched together.
    func testOptingBackInResumesSendingWithAFreshIdentity() async {
        let telemetry = makeTelemetry(transport: SpyTelemetryTransport(),
                                      identities: ["identity-one", "identity-two"])
        telemetry.setAnalyticsConsent(false)
        telemetry.setAnalyticsConsent(true)
        XCTAssertEqual(telemetry.analyticsIdentity, "identity-two",
                       "re-enabling mints a new id rather than resurrecting the old one")

        let secondRun = SpyTelemetryTransport()
        let relaunched = makeTelemetry(transport: secondRun)
        XCTAssertTrue(relaunched.isAnalyticsEnabled)
        XCTAssertEqual(secondRun.startCount, 1)

        relaunched.capture(TelemetryEvent("app_opened_v1", ["app_version": .string("1.1.2 (9)")]))
        await relaunched.flush()
        XCTAssertEqual(secondRun.sentEvents.map(\.name), ["app_opened_v1"])
    }

    /// A build with no key stays inert whatever the default says — the fail-soft
    /// path is what makes a secrets-less checkout safe to run.
    func testDefaultOnStillSendsNothingWithoutAKey() async {
        let spy = SpyTelemetryTransport()
        let telemetry = makeTelemetry(transport: spy, apiKey: nil)

        XCTAssertFalse(telemetry.isAnalyticsEnabled)
        XCTAssertNil(telemetry.analyticsIdentity)
        XCTAssertFalse(telemetry.isConfigured)

        telemetry.capture(TelemetryEvent("app_opened_v1", ["app_version": .string("1.1.2 (9)")]))
        await telemetry.flush()

        XCTAssertEqual(spy.startCount, 0)
        XCTAssertEqual(spy.sentBatches.count, 0)
    }

    /// Constructing twice over the same defaults must not mint a second id.
    func testTheIdentityIsStableAcrossLaunches() {
        let first = makeTelemetry(transport: SpyTelemetryTransport(),
                                  identities: ["identity-one", "identity-two"])
        let stored = first.analyticsIdentity
        let second = makeTelemetry(transport: SpyTelemetryTransport(),
                                   identities: ["identity-three"])
        XCTAssertEqual(second.analyticsIdentity, stored)
    }

    // MARK: - The queue is bounded, expiring, and single-flight

    func testTheQueueDropsTheOldestEventsPastCapacity() {
        let queue = TelemetryQueue(capacity: 3, batchSize: 2, expiry: 60)
        let now = Date()
        for index in 0..<5 {
            queue.enqueue(TelemetryEvent("app_opened_v1", ["ordinal": .int(index)]), at: now)
        }
        XCTAssertEqual(queue.count, 3)
        XCTAssertEqual(queue.pending.first?.event.properties["ordinal"], .int(2),
                       "the oldest events are the ones dropped")
    }

    func testAnExpiredEventIsNeverSent() {
        let queue = TelemetryQueue(capacity: 10, batchSize: 5, expiry: 60)
        let start = Date()
        queue.enqueue(TelemetryEvent("app_opened_v1"), at: start)
        XCTAssertTrue(queue.checkoutBatch(now: start.addingTimeInterval(61)).isEmpty,
                      "an event older than the expiry window is discarded, not sent late")
    }

    func testABatchInFlightCannotBeCheckedOutTwice() {
        let queue = TelemetryQueue(capacity: 10, batchSize: 2, expiry: 60)
        let now = Date()
        queue.enqueue(TelemetryEvent("app_opened_v1"), at: now)
        queue.enqueue(TelemetryEvent("app_opened_v1"), at: now)
        queue.enqueue(TelemetryEvent("app_opened_v1"), at: now)

        XCTAssertEqual(queue.checkoutBatch(now: now).count, 2)
        XCTAssertTrue(queue.checkoutBatch(now: now).isEmpty, "duplicate flush guard")
        queue.commitBatch()
        XCTAssertEqual(queue.checkoutBatch(now: now).count, 1)
    }

    func testAFailedSendReturnsTheBatchRatherThanDroppingIt() async {
        let spy = SpyTelemetryTransport()
        spy.sendSucceeds = false
        let telemetry = makeTelemetry(transport: spy)

        telemetry.capture(TelemetryEvent("app_opened_v1", ["app_version": .string("1.1.2 (9)")]))
        await telemetry.flush()

        XCTAssertEqual(telemetry.queuedEventCount, 1, "an offline flush keeps the event")

        spy.sendSucceeds = true
        await telemetry.flush()
        XCTAssertEqual(telemetry.queuedEventCount, 0)
        XCTAssertEqual(spy.sentEvents.count, 2, "the same event was retried, not lost")
    }

    // MARK: - Validation

    func testUndeclaredEventIsRejected() {
        XCTAssertEqual(TelemetryValidator.validate(TelemetryEvent("app_backgrounded_v1")),
                       .rejected(.unknownEvent("app_backgrounded_v1")))
    }

    func testUndeclaredPropertyIsRejected() {
        let result = TelemetryValidator.validate(
            TelemetryEvent("ad_load_finished_v1", ["outcome": .string("filled"),
                                                   "latency_ms": .int(412)])
        )
        XCTAssertEqual(result, .rejected(.undeclaredProperty(event: "ad_load_finished_v1",
                                                             property: "latency_ms")))
    }

    /// The prohibited list, named field by field, so a future schema addition
    /// cannot quietly admit one of them.
    func testProhibitedContentFieldsAreRejectedByName() {
        let prohibited = [
            "card_id", "card_text", "concept", "concept_body", "example_body",
            "topic_id", "topic_name", "set_id", "source", "source_url",
            "bookmark_ids", "bookmark_list", "card_history",
            "session_started_at", "duration_seconds", "cards_viewed", "install_date",
            "price", "display_price", "revenue", "product_id",
            "transaction_id", "original_transaction_id", "receipt",
            "advertising_id", "idfa", "idfv", "ad_unit_id", "att_status",
            "ip", "latitude", "longitude", "region", "user_agent",
            "device_id", "contacts", "clipboard", "user_text", "email",
            "sdk_error_description", "stack_trace",
        ]
        for field in prohibited {
            let event = TelemetryEvent("session_ended_v1", [field: .string("x")])
            XCTAssertEqual(TelemetryValidator.validate(event),
                           .rejected(.prohibitedProperty(event: "session_ended_v1", property: field)),
                           "\(field) must be rejected by name, not merely as undeclared")
        }
    }

    func testAValueOutsideAnEnumeratedVocabularyIsRejected() {
        let event = TelemetryEvent("session_started_v1", [
            "mode": .string("wyr"),           // Table Talk's vocabulary, not ours
            "entry_point": .string("home"),
            "deck_size_bucket": .string("5_9"),
        ])
        XCTAssertEqual(TelemetryValidator.validate(event),
                       .rejected(.disallowedValue(event: "session_started_v1",
                                                  property: "mode", value: "wyr")))
    }

    func testAnOutOfRangeSmallCountIsRejected() {
        XCTAssertEqual(TelemetryValidator.validate(TelemetryEvent("ad_impression_v1", ["ordinal": .int(42)])),
                       .rejected(.disallowedValue(event: "ad_impression_v1",
                                                  property: "ordinal", value: "42")))
    }

    func testAWellFormedEventOfEveryKindIsAccepted() {
        XCTAssertEqual(TelemetryValidator.validate(TelemetryEvent("session_ended_v1", [
            "mode": .string("bookmarks"),
            "reason": .string("completed"),
            "cards_viewed_bucket": .string("5_9"),
            "duration_bucket": .string("2m_5m"),
            "had_bookmark": .bool(true),
            "ad_impressions_count": .int(1),
        ])), .accepted)
    }

    // MARK: - Buckets collapse exact counts and durations

    func testBucketsCollapseExactCountsAndDurations() {
        XCTAssertEqual(TelemetryBucket.installAge(days: 0), "d0")
        XCTAssertEqual(TelemetryBucket.installAge(days: 45), "d30_89")
        XCTAssertEqual(TelemetryBucket.installAge(days: 900), "d90_plus")
        XCTAssertEqual(TelemetryBucket.launchCount(1), "1")
        XCTAssertEqual(TelemetryBucket.launchCount(60), "51_plus")
        XCTAssertEqual(TelemetryBucket.cards(0), "0")
        XCTAssertEqual(TelemetryBucket.cards(8), "5_9")
        XCTAssertEqual(TelemetryBucket.cards(400), "30_plus")
        XCTAssertEqual(TelemetryBucket.duration(seconds: 5), "lt_30s")
        XCTAssertEqual(TelemetryBucket.duration(seconds: 3600), "15m_plus")
        XCTAssertEqual(TelemetryBucket.bookmarkCount(0), "0")
        XCTAssertEqual(TelemetryBucket.bookmarkCount(99), "25_plus")
        XCTAssertEqual(TelemetryBucket.streak(1), "1")
        XCTAssertEqual(TelemetryBucket.streak(365), "30_plus")
    }

    /// Every bucket function may only ever return a value its declared
    /// vocabulary contains — otherwise the validator would silently drop real
    /// events in production.
    func testEveryBucketFunctionStaysInsideItsDeclaredVocabulary() {
        for days in [0, 1, 2, 3, 6, 7, 29, 30, 89, 90, 1000] {
            XCTAssertTrue(TelemetrySchema.Bucket.installAge.contains(TelemetryBucket.installAge(days: days)))
        }
        for launches in [0, 1, 2, 3, 4, 10, 11, 50, 51, 5000] {
            XCTAssertTrue(TelemetrySchema.Bucket.launchCount.contains(TelemetryBucket.launchCount(launches)))
        }
        for count in [0, 1, 4, 5, 9, 10, 14, 15, 29, 30, 999] {
            XCTAssertTrue(TelemetrySchema.Bucket.depth.contains(TelemetryBucket.cards(count)))
            XCTAssertTrue(TelemetrySchema.Bucket.deckSize.contains(TelemetryBucket.cards(count)))
        }
        for seconds in [0.0, 29, 30, 119, 120, 299, 300, 899, 900, 100_000] {
            XCTAssertTrue(TelemetrySchema.Bucket.duration.contains(TelemetryBucket.duration(seconds: seconds)))
        }
        for count in [0, 1, 4, 5, 9, 10, 24, 25, 900] {
            XCTAssertTrue(TelemetrySchema.Bucket.bookmarkCount.contains(TelemetryBucket.bookmarkCount(count)))
        }
        for days in [0, 1, 2, 3, 4, 6, 7, 29, 30, 900] {
            XCTAssertTrue(TelemetrySchema.Bucket.streak.contains(TelemetryBucket.streak(days)))
        }
    }

    // MARK: - The schema describes measurement that actually happens
    //
    // Two guards, both source scans, both for the same reason: a schema entry
    // with no call site is not measurement, it is a promise on paper, and it
    // reads as coverage in review. A runtime check cannot replace them —
    // several of these events fire only on a real ad fill or a real StoreKit
    // sheet, which no unit test can reach, and "unreachable in a test" must not
    // become an excuse for "absent from the source".

    func testEveryDeclaredEventHasAnEmissionCallSite() throws {
        let sources = try appSourceFiles()
        XCTAssertFalse(sources.isEmpty, "source scan found no files — check the app root")

        let corpus = try producerCorpus()
        for event in TelemetrySchema.allowedEventNames.sorted() {
            XCTAssertTrue(corpus.contains("TelemetryEvent(\"\(event)\""),
                          "\(event) is declared in TelemetrySchema but no app code emits it")
        }
    }

    /// Every enumerated value must be reachable too.
    ///
    /// # Why this excludes the schema file
    ///
    /// The schema declares every value as a quoted literal. Scanning it would
    /// match each assertion against the declaration it is supposed to be
    /// checking, and the test would pass while nothing in the app produced the
    /// value. The declaring file is therefore excluded: a value has to be
    /// produced somewhere that is not the declaration.
    ///
    /// Two property families cannot be proved by a literal scan, and each is
    /// checked against its real producer instead of being waved through:
    ///
    ///  - bucket values come from `TelemetryBucket`, which
    ///    `testEveryBucketFunctionStaysInsideItsDeclaredVocabulary` covers.
    ///  - `difficulty` comes from the bundled catalog at runtime, never from a
    ///    Swift literal — checked against the loaded catalog below.
    func testEveryEnumeratedValueIsProducibleBySomeCallSite() throws {
        let corpus = try producerCorpus()
        XCTAssertFalse(corpus.contains("static let propertyKinds"),
                       "the schema declaration must not be part of its own producer corpus")

        let bucketProperties: Set<String> = [
            "install_age_bucket", "launch_count_bucket", "depth_bucket",
            "cards_viewed_bucket", "deck_size_bucket", "duration_bucket",
            "bookmark_count_bucket", "streak_bucket",
        ]
        let catalogDifficulties = Set(ContentStore.shared.allCards.map(\.difficulty))

        for (property, values) in TelemetrySchema.allowedValues
        where !bucketProperties.contains(property) {
            for value in values.sorted() {
                let producedAsLiteral = corpus.contains("\"\(value)\"")
                let producedByCatalog = property == "difficulty" && catalogDifficulties.contains(value)
                XCTAssertTrue(producedAsLiteral || producedByCatalog,
                              "\(property) declares \"\(value)\" but nothing in the app produces it")
            }
        }
    }

    /// The declared difficulty vocabulary and the bundled catalog must be the
    /// same set — in both directions. A tier in the catalog that the schema does
    /// not declare would have its `card_flipped_v1` events silently dropped in
    /// production; a tier the schema declares that no card carries is coverage
    /// that does not exist.
    func testDeclaredDifficultiesMatchTheBundledCatalog() throws {
        let catalog = Set(ContentStore.shared.allCards.map(\.difficulty))
        XCTAssertFalse(catalog.isEmpty, "the bundled catalog failed to load")
        XCTAssertEqual(TelemetrySchema.allowedValues["difficulty"], catalog,
                       "cards.json and TelemetrySchema disagree about the difficulty tiers")
    }

    // MARK: - Diagnostics: on by construction, with nowhere to send being a refusal

    func testDiagnosticsStartsAutomaticallyWhenADSNIsConfigured() {
        let spy = SpyDiagnosticsTransport()
        let diagnostics = EconDiagnostics(transport: spy,
                                          dsn: "https://key@example.invalid/1",
                                          defaults: defaults)
        XCTAssertTrue(diagnostics.isDiagnosticsEnabled)
        XCTAssertTrue(spy.isStarted)
        XCTAssertEqual(spy.startCount, 1)
        XCTAssertNil(diagnostics.lastRefusal)
    }

    func testAskingDiagnosticsToStartTwiceStartsItOnce() {
        let spy = SpyDiagnosticsTransport()
        let diagnostics = EconDiagnostics(transport: spy,
                                          dsn: "https://key@example.invalid/1",
                                          defaults: defaults)
        diagnostics.setDiagnosticsConsent(true)
        diagnostics.setDiagnosticsConsent(true)
        XCTAssertEqual(spy.startCount, 1)
    }

    func testWithoutADSNNothingStartsHoweverOftenItIsAskedTo() {
        let spy = SpyDiagnosticsTransport()
        let diagnostics = EconDiagnostics(transport: spy, dsn: nil, defaults: defaults)
        diagnostics.setDiagnosticsConsent(true)
        diagnostics.setDiagnosticsConsent(true)

        XCTAssertEqual(spy.startCount, 0)
        XCTAssertFalse(diagnostics.isDiagnosticsEnabled)
        XCTAssertEqual(diagnostics.lastRefusal, .noDSNConfigured)
    }

    /// A Release build refuses to collect when the SDK cannot promise to delete
    /// its own envelope cache.
    func testReleaseRefusesWhenTheSDKCannotPromiseCacheRemoval() {
        let spy = SpyDiagnosticsTransport()
        spy.cacheRemovalGuaranteed = false
        let diagnostics = EconDiagnostics(transport: spy,
                                          dsn: "https://key@example.invalid/1",
                                          defaults: defaults,
                                          isReleaseBuild: true)
        XCTAssertEqual(spy.startCount, 0)
        XCTAssertFalse(diagnostics.isDiagnosticsEnabled)
        XCTAssertEqual(diagnostics.lastRefusal, .cacheRemovalNotGuaranteed)
    }

    func testDisablingDiagnosticsClosesTheSDKAndRemovesTheEnvelopeCache() {
        let spy = SpyDiagnosticsTransport()
        let diagnostics = EconDiagnostics(transport: spy,
                                          dsn: "https://key@example.invalid/1",
                                          defaults: defaults)
        diagnostics.setDiagnosticsConsent(false)

        XCTAssertFalse(diagnostics.isDiagnosticsEnabled)
        XCTAssertEqual(spy.clearCount, 1, "the local envelope cache is deleted before teardown")
        XCTAssertEqual(spy.closeCount, 1)
    }

    // MARK: - Source helpers

    private func repoRoot(file: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(file)").deletingLastPathComponent().deletingLastPathComponent()
    }

    private func appSourceFiles(file: StaticString = #filePath) throws -> [URL] {
        let appRoot = repoRoot(file: file).appendingPathComponent("EconByte")
        guard let walker = FileManager.default.enumerator(at: appRoot,
                                                          includingPropertiesForKeys: nil) else {
            return []
        }
        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    /// Every app source EXCEPT the schema's own declaration, concatenated. The
    /// exclusion is the whole point — see the two guards above.
    private func producerCorpus(file: StaticString = #filePath) throws -> String {
        try appSourceFiles(file: file)
            .filter { $0.lastPathComponent != "EconTelemetry.swift" }
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
    }
}
