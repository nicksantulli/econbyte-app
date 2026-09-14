import Foundation

// MARK: - May this process talk to the live projects at all?
//
// Seen 2026-09-05 across the studio's PostHog projects: a UI-test suite launches
// the REAL app with the REAL key, so every `xcodebuild test` relaunch wrote
// `app_opened_v1` into production analytics, and a deliberate test crash would
// have written into production Sentry. Test traffic is not user traffic, it is
// indistinguishable from user traffic once ingested, and PostHog has no
// delete-by-property — so the only workable fix is to never send it.
//
// The rule below is therefore deliberately blunt: a unit-test host, an
// automation launch, or ANY Debug build is inert. The single way out is the
// explicit `-AllowAnalyticsInDebug` argument, which the ingestion-proof smoke
// passes on purpose and nothing else does.
//
// A shipped Release build is untouched: `isDebugBuild` is false, XCTest's
// environment variable does not exist, and none of the automation arguments are
// present, so `suppressesLiveTransports` is false and the credentials resolve
// exactly as they did before this file existed.

/// The launch context, expressed as plain data so the decision is unit-testable
/// without a test runner inside a test runner.
struct InstrumentationContext: Equatable {

    /// The one explicit override. Passing it says "I know this is a Debug or
    /// test process and I want the live projects anyway" — the ingestion proof.
    static let allowFlag = "-AllowAnalyticsInDebug"

    /// XCTest sets this in the environment of the process that hosts the tests.
    static let xcTestEnvironmentKey = "XCTestConfigurationFilePath"

    /// Launch arguments that only ever come from automation. `-skipStudioIntro`
    /// and `-exposeGroceryBinding` are EconByteUITests' existing hooks;
    /// `-uitestResult` is StudioIntroView's; `-UITesting` is reserved so a
    /// future suite has a marker that means nothing else.
    ///
    /// RECONCILED (1.1.2): `-econResetGrowthState` and `-econDisableAds` are the
    /// 1.1 UI suite's harness arguments (`GrowthFlowTests`,
    /// `AccessibilityTests`, `ScreenshotTests`). They were invisible to lineage
    /// C because that lineage did not have the 1.1 growth stack — and without
    /// them here, the restored suite would relaunch the real app on the real
    /// key and write test traffic into the live projects, which is the exact
    /// defect this file exists to prevent.
    ///
    /// 1.1.3: `-EBSkipConsentPrompt` suppresses the first-open analytics consent
    /// card for UI tests and screenshot runs (`FirstOpenConsentPolicy`). It is
    /// an automation marker for the same reason the others are.
    static let automationArguments: Set<String> = [
        "-UITesting", "-skipStudioIntro", "-exposeGroceryBinding", "-uitestResult",
        "-econResetGrowthState", "-econDisableAds", "-EBSkipConsentPrompt",
    ]

    let arguments: [String]
    let environment: [String: String]
    let isDebugBuild: Bool

    static var current: InstrumentationContext {
        #if DEBUG
        let debug = true
        #else
        let debug = false
        #endif
        return InstrumentationContext(arguments: ProcessInfo.processInfo.arguments,
                                      environment: ProcessInfo.processInfo.environment,
                                      isDebugBuild: debug)
    }

    var isExplicitlyAllowed: Bool { arguments.contains(Self.allowFlag) }

    var isUnitTestRun: Bool { environment[Self.xcTestEnvironmentKey] != nil }

    var isAutomationRun: Bool {
        arguments.contains { Self.automationArguments.contains($0) }
    }

    /// True when neither vendor SDK may be configured for this run.
    var suppressesLiveTransports: Bool {
        if isExplicitlyAllowed { return false }
        return isUnitTestRun || isAutomationRun || isDebugBuild
    }
}
