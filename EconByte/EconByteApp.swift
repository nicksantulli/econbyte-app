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
            StudioIntroGate(onFinished: { LaunchSequence.shared.markIntroFinished() }) {
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

                // First-launch permissions (1.1.3 build 16, App Review 2.1):
                // Apple's ATT prompt, then Apple's notifications prompt, once the
                // studio intro has gone and iOS would actually show them. Anything
                // already answered is skipped, so later launches are a no-op;
                // UI-test arguments stand it down.
                await LaunchSequence.shared.waitForIntro()
                await runLaunchPermissions()
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
                    // Retry any prompt still owed on every activation once the
                    // intro has gone: iOS shows nothing to an inactive app or over
                    // a presentation, and an answered prompt is a no-op.
                    if LaunchSequence.shared.introFinished {
                        Task { await runLaunchPermissions() }
                    }
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

    // MARK: First-launch permissions (1.1.3 build 16)

    /// Waits (bounded) until iOS would actually present a system prompt — the
    /// app active, nothing presented over the root — then runs Apple's ATT
    /// prompt followed by the notifications prompt. Called after the studio
    /// intro and again on every activation: anything already answered is a
    /// no-op, and a run iOS could not present simply runs again next time.
    @MainActor
    private func runLaunchPermissions() async {
        let arguments = ProcessInfo.processInfo.arguments
        if !FirstLaunchPermissionPolicy.isSkipped(arguments: arguments) {
            let environment = LivePromptPresentationEnvironment.shared
            let deadline = Date().addingTimeInterval(20)
            while !environment.isReadyForSystemPrompt {
                // Not ready in time (backgrounded, a sheet left open): the next
                // `.active` tries again, and ads stay held until then.
                if Task.isCancelled || Date() > deadline { return }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            // Let the intro's fade and the first Home layout settle.
            try? await Task.sleep(nanoseconds: 450_000_000)
        }
        await EconGrowth.shared.permissions.runIfNeeded(arguments: arguments)
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
    /// undo a stored opt-out, because the reconciled build is opt-in. The
    /// first-launch permission flow stands down for a smoke run
    /// (`FirstLaunchPermissionPolicy.isSkipped`) so there is one answer, not two.
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

/// Lets the launch task wait for the studio intro to finish (1.1.3 build 16),
/// so the first system prompt never lands on the brand beat.
@MainActor
final class LaunchSequence {
    static let shared = LaunchSequence()
    private(set) var introFinished = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func markIntroFinished() {
        guard !introFinished else { return }
        introFinished = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }

    func waitForIntro() async {
        guard !introFinished else { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}
