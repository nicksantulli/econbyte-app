import Foundation

// MARK: - App Tracking Transparency (1.1.2 build 13)
//
// WHY THIS FILE EXISTS AGAIN.
//
// Version 1.1 removed the ATT pathway and 1.1.2's builds 10-12 kept it removed,
// on the reasoning that non-personalized ads do not need the advertising
// identifier. App Review rejected build 12 under **Guideline 5.1.2(i)** on
// 2026-09-07: the app-level App Privacy label answers "Device ID - used to track
// you: Yes", and an app whose label says it tracks must ask through ATT first.
//
// The label cannot simply be flipped to No. App Store Connect refuses to publish
// that answer while a relevant binary carries `NSUserTrackingUsageDescription` —
// and the LIVE 1.1.1 (build 8) does. The refusal was reproduced and recorded in
// `~/dudley-evidence-retention/econbyte/1.1.2-resubmission-2026-09-07/`. On top
// of that, GoogleMobileAds 12.14.0's own privacy manifest declares
// `NSPrivacyCollectedDataTypeDeviceID` with `Tracking = true`, so the aggregated
// privacy report Apple reads says the app tracks no matter what this app's own
// manifest claims. The label was right; the binary was the half to move.
//
// So build 13 restores the prompt — and restores it *correctly*, which build 8
// never did:
//
//   * It is asked ONCE per install, after a completed card session, from the
//     session-complete screen's exit path. Never at launch, never over the
//     app's own privacy/consent card, never twice.
//   * NO ad request — not even the SDK start or a preload — may precede the
//     decision. Build 8 preloaded at launch and asked later, which is the
//     ordering 5.1.2(i) is about.
//   * Every outcome unblocks ads: authorized, denied, restricted, and a prompt
//     iOS declined to present all move the app forward. There is no state in
//     which the reader is left with a permanently silent ad slot.
//
// The framework is deliberately behind a protocol: ATT cannot be exercised in a
// unit test (there is no prompt, and the status is process-global), so every
// ordering rule above is asserted against `EconTrackingAuthorizing` instead.

/// The four ATT outcomes as a pure value.
///
/// A dismissed prompt is not a fifth case: iOS resolves a dismissal to
/// `.denied`, and a prompt it declined to present leaves `.notDetermined`.
public enum EconTrackingStatus: String, Equatable, CaseIterable, Sendable {
    case notDetermined
    case restricted
    case denied
    case authorized

    /// The reader has answered, or the system answered for them. Everything
    /// except `.notDetermined` unblocks the ad request.
    public var isDecided: Bool { self != .notDetermined }

    /// Whether the *provider* would be allowed to personalize on this status.
    ///
    /// EconByte still answers `npa=1` on every request whatever this says: the
    /// portfolio invariant `adsPolicy.personalizedAdsMode: "disabled"` in
    /// `config/app-factory/monetization-policy.json` is enforced for every app
    /// by `scripts/release_evidence_gate.mjs` (POLICY_PERSONALIZATION) and by
    /// DudleyCore's `MonetizationPolicyRegistry`, which throws on
    /// `personalizedAdsEnabled` for any app. Turning personalization on for
    /// authorized readers is the follow-up that actually collects the eCPM this
    /// prompt makes available, and it is a portfolio policy revision, not an
    /// EconByte edit. This property is the seam that revision will use; nothing
    /// reads it today, and `EconAdRequestPolicy.extras` pins that.
    public var providerWouldPermitPersonalizedAds: Bool { self == .authorized }
}

/// The seam between the ad policy and the framework.
@MainActor
public protocol EconTrackingAuthorizing: AnyObject {
    var status: EconTrackingStatus { get }

    /// Presents the system prompt and returns the resolved status. Must be a
    /// no-op returning the current status when the status is already decided —
    /// iOS allows exactly one prompt per install, and asking again is how an app
    /// ends up with an "answer" it never showed a dialog for.
    func requestAuthorization() async -> EconTrackingStatus
}

#if canImport(AppTrackingTransparency)
import AppTrackingTransparency

/// The live adapter. This is the ONLY file in the app that imports
/// AppTrackingTransparency or names `ATTrackingManager`, which
/// `InstrumentationPrivacyTests` asserts by scanning every app source.
@MainActor
public final class EconTrackingAuthorization: EconTrackingAuthorizing {

    public static let shared = EconTrackingAuthorization()

    public init() {}

    public var status: EconTrackingStatus {
        Self.mapped(ATTrackingManager.trackingAuthorizationStatus)
    }

    public func requestAuthorization() async -> EconTrackingStatus {
        guard status == .notDetermined else { return status }
        return Self.mapped(await ATTrackingManager.requestTrackingAuthorization())
    }

    static func mapped(_ raw: ATTrackingManager.AuthorizationStatus) -> EconTrackingStatus {
        switch raw {
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .denied      // fail closed: unknown is not consent
        }
    }
}

#else

/// Build environments without the framework (there are none on iOS 16.6, but a
/// missing framework must never mean "assume consent"). Fails closed to
/// `.denied`, which is a decided status: ads still serve, non-personalized.
@MainActor
public final class EconTrackingAuthorization: EconTrackingAuthorizing {
    public static let shared = EconTrackingAuthorization()
    public init() {}
    public var status: EconTrackingStatus { .denied }
    public func requestAuthorization() async -> EconTrackingStatus { .denied }
}

#endif
