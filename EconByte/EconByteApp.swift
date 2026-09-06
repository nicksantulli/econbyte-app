import SwiftUI

@main
struct EconByteApp: App {
    // Declared first on purpose: EconGrowth's initializer honours the DEBUG-only
    // `-econResetGrowthState` UI-test harness, which must run before the content
    // and streak singletons read their persisted state.
    @StateObject private var growth = EconGrowth.shared
    @StateObject private var content = ContentStore.shared
    @StateObject private var streak = StreakManager.shared
    @StateObject private var store = PurchaseManager.shared

    @Environment(\.scenePhase) private var scenePhase
    @State private var wasBackgrounded = false

    var body: some Scene {
        WindowGroup {
            StudioIntroGate {
                HomeView()
                    .environmentObject(content)
                    .environmentObject(streak)
                    .environmentObject(store)
                    .environmentObject(growth)
            }
            .preferredColorScheme(.dark)
            .task {
                // Construct the diagnostics facade first so, when the user has
                // opted in and a DSN is configured, Sentry's crash handler
                // installs as early as possible. With no DSN, or no consent,
                // this is inert (NoOp transport) and never starts.
                _ = EconDiagnostics.shared
                Self.applyInstrumentationSmokeIfRequested()
                Self.crashOnPurposeIfRequested()
                // Reconcile verified entitlements BEFORE anything can start the
                // ad SDK: a stale-false Remove Ads cache must never initialize
                // the provider for an entitled reader. Mirrors the foreground path.
                await store.updatePurchasedProducts()
                growth.syncEntitlements(from: store)
                growth.applicationDidBecomeActive()
                growth.reportContentLoadFailureIfNeeded(content)
            }
            // Purchase, restore, refund, and revocation must all reach ad
            // behaviour and content access on the same turn.
            .onChange(of: store.isRemoveAdsPurchased) { _ in
                growth.syncEntitlements(from: store)
            }
            .onChange(of: store.isUnlockAllPurchased) { _ in
                growth.syncEntitlements(from: store)
            }
            .onChange(of: scenePhase) { phase in
                // Hand whatever is queued to the transport when the app leaves
                // the foreground, so a day of bucketed counts is not lost to a
                // cold kill.
                if phase != .active { EBEvents.flush() }
                switch phase {
                case .background:
                    wasBackgrounded = true
                case .active:
                    guard wasBackgrounded else { return }
                    wasBackgrounded = false
                    Task {
                        await store.updatePurchasedProducts()
                        growth.syncEntitlements(from: store)
                        growth.applicationDidBecomeActive()
                    }
                default:
                    break
                }
            }
        }
    }

    /// DEBUG-ONLY instrumentation smoke hook. Launched with
    /// `-EBInstrumentationSmoke YES`, it forces analytics and crash diagnostics
    /// on for this run and logs the resolved state, so an ingestion smoke run
    /// reports what it actually exercised rather than what it hoped for.
    /// Compiled out of Release entirely; with no key/DSN configured it is still
    /// fail-soft — the facades no-op and nothing initializes.
    ///
    /// A Debug process reaches the LIVE projects only when
    /// `-AllowAnalyticsInDebug` is also passed (see `InstrumentationContext`),
    /// so the ingestion proof is launched with BOTH arguments and this hook
    /// alone stays inert. The log line below reports which of the two happened.
    ///
    /// RECONCILED (1.1.2): it now has to force consent ON rather than merely
    /// undo a stored opt-out, because the reconciled build is opt-in.
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
    /// Compiled out of Release, so no shipped build contains a code path that
    /// can crash on purpose.
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
