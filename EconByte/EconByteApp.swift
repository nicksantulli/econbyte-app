import SwiftUI

@main
struct EconByteApp: App {
    @StateObject private var content = ContentStore.shared
    @StateObject private var streak = StreakManager.shared
    @StateObject private var ads = AdManager.shared
    @StateObject private var store = PurchaseManager.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            StudioIntroGate {
                HomeView()
                    .environmentObject(content)
                    .environmentObject(streak)
                    .environmentObject(ads)
                    .environmentObject(store)
            }
            .preferredColorScheme(.dark)
            .task {
                // Construct the diagnostics facade first so Sentry's crash
                // handler installs as early as possible. Crash reporting is on
                // whenever a DSN is configured; with no DSN this is inert (NoOp
                // transport) and never starts.
                _ = EconDiagnostics.shared
                Self.applyInstrumentationSmokeIfRequested()
                Self.crashOnPurposeIfRequested()
                EconGrowth.recordLaunch()
                ads.start()
                ads.setAdsDisabled(store.isRemoveAdsPurchased)
                ReviewPrompt.registerLaunch()
            }
            // Keep the ad gate in sync the moment Remove Ads is purchased/restored.
            .onChange(of: store.isRemoveAdsPurchased) { disabled in
                ads.setAdsDisabled(disabled)
            }
        }
        // Hand whatever is queued to the transport when the app leaves the
        // foreground, so a day of bucketed counts is not lost to a cold kill.
        .onChange(of: scenePhase) { phase in
            if phase != .active { EconGrowth.flush() }
        }
    }

    /// DEBUG-ONLY instrumentation smoke hook. When the app is launched with
    /// `-EBInstrumentationSmoke YES`, force analytics on (undoing a stored
    /// opt-out for this run) and log the resolved state, so an ingestion smoke
    /// run reports what it actually exercised rather than what it hoped for.
    /// Analytics and crash reporting are already on by default in 1.1.2; this
    /// exists for the case where the smoke device previously opted out.
    /// Compiled out of Release entirely. With no key/DSN configured it is still
    /// fail-soft: the facades no-op and nothing initializes.
    ///
    /// From 1.1.2 a Debug process reaches the LIVE projects only when
    /// `-AllowAnalyticsInDebug` is also passed (see InstrumentationContext) — so
    /// the ingestion proof is launched with BOTH arguments, and this hook alone
    /// stays inert. The log line below reports which of the two happened.
    private static func applyInstrumentationSmokeIfRequested() {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-EBInstrumentationSmoke")
                || UserDefaults.standard.bool(forKey: "EBInstrumentationSmoke") else { return }
        let context = InstrumentationContext.current
        NSLog("[EB][smoke] instrumentation smoke: forcing analytics on for this run")
        NSLog("[EB][smoke] context: allowFlag=\(context.isExplicitlyAllowed) unitTest=\(context.isUnitTestRun) automation=\(context.isAutomationRun) debugBuild=\(context.isDebugBuild) suppressed=\(context.suppressesLiveTransports)")
        EconTelemetry.shared.setAnalyticsConsent(true)
        EconDiagnostics.shared.setDiagnosticsConsent(true)
        NSLog("[EB][smoke] analytics configured=\(EconTelemetry.shared.isConfigured) enabled=\(EconTelemetry.shared.isAnalyticsEnabled) distinctId=\(EconTelemetry.shared.analyticsIdentity ?? "none"); diagnostics configured=\(EconDiagnostics.shared.isConfigured) enabled=\(EconDiagnostics.shared.isDiagnosticsEnabled)")
        #endif
    }

    /// DEBUG-ONLY deliberate crash, for proving the crash pipeline end to end.
    /// Launch with `-EBInstrumentationCrash YES`: the app finishes launching,
    /// gives Sentry's handler a moment to install and the analytics flush a
    /// moment to leave, then traps. The next launch uploads the report.
    ///
    /// This is compiled out of Release, so no shipped build contains a code path
    /// that can crash on purpose. It stays DEBUG-only permanently — if a future
    /// lane needs to re-verify ingestion, it re-runs this, it does not ship a
    /// switch.
    private static func crashOnPurposeIfRequested() {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-EBInstrumentationCrash")
                || UserDefaults.standard.bool(forKey: "EBInstrumentationCrash") else { return }
        NSLog("[EB][smoke] deliberate test crash in 3s (DEBUG only)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            NSLog("[EB][smoke] crashing now")
            fatalError("EBInstrumentationCrash: deliberate crash to verify Sentry ingestion")
        }
        #endif
    }
}
