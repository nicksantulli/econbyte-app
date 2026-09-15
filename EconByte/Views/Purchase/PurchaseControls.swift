import SwiftUI

// MARK: - The one purchase button and offer card (1.1.4 release scope; 1.1.5 design system)
//
// Every purchase surface in EconByte — each topic pack, the All Packs Bundle,
// Unlock All, Remove Ads and EconByte Pro — is an `OfferCard` holding one
// `PurchaseButton`, always at the bottom of the card with Restore under it.
//
// 1.1.5 (Owner: "all the buttons are the same size and clearly labelled with
// how much they cost"): the button stacks the action over its price —
// "Unlock" / "$1.99", "Start 7-day free trial" / "then $39.99 per year" — so
// the price is always its own line and every button has the same height
// (`EconSize.buttonHeight`, scaled with Dynamic Type) whatever its words.
// VoiceOver reads the joined label ("Unlock · $1.99"). The loading / failed /
// pending / owned states come from `PurchaseButtonModel`, so no surface can
// drift from the others.

struct PurchaseButton: View {
    let model: PurchaseButtonModel
    let identifier: String
    /// Identifier of the "Prices unavailable — Try again" notice.
    var unavailableIdentifier: String? = nil
    var onRetry: (() -> Void)? = nil
    let action: () -> Void

    @ScaledMetric(relativeTo: .headline) private var minHeight: CGFloat = EconSize.buttonHeight

    private var foreground: Color { model.style == .primary ? EconColor.onAccent : EconColor.interactive }
    private var fill: Color { model.style == .primary ? EconColor.accent : EconColor.interactiveFill }

    var body: some View {
        VStack(spacing: EconSpace.xs) {
            Button(action: action) {
                HStack(spacing: EconSpace.xs) {
                    if model.showsSpinner {
                        ProgressView()
                            .tint(foreground)
                            .accessibilityHidden(true)
                    }
                    VStack(spacing: 1) {
                        Text(model.title)
                            .font(EconType.headline)
                        if let detail = model.detail {
                            Text(detail)
                                .font(EconType.subheadlineEmphasis)
                                .monospacedDigit()
                        }
                    }
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundColor(foreground)
                .padding(.horizontal, EconSpace.m)
                .padding(.vertical, EconSpace.xs)
                .frame(maxWidth: .infinity, minHeight: minHeight)
                .background(fill)
                .clipShape(RoundedRectangle(cornerRadius: EconRadius.control, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: EconRadius.control, style: .continuous)
                        .stroke(EconColor.interactive.opacity(model.style == .owned ? 0.45 : 0), lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: EconRadius.control, style: .continuous))
            }
            .buttonStyle(PurchaseButtonPressStyle())
            .disabled(!model.isEnabled)
            .opacity(model.isEnabled || model.style == .owned ? 1 : 0.55)
            // The Button stays its own accessibility element (so "not enabled"
            // is announced and testable); the label joins action and price.
            .accessibilityLabel(Text(model.label))
            .accessibilityIdentifier(identifier)

            if model.showsPricesUnavailable, let onRetry {
                PricesUnavailableNotice(identifier: unavailableIdentifier ?? "\(identifier)-pricesUnavailable",
                                        onRetry: onRetry)
            }
        }
    }
}

private struct PurchaseButtonPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

/// A product offer: icon, name, one short line, optional content (a pack's
/// preview, the Pro plan tiles), then — always last, in this order — the
/// purchase button and Restore.
struct OfferCard<Content: View>: View {
    let icon: String
    let title: String
    var subtitle: String?
    /// A short state on the right of the title ("Active ✓").
    var status: String?
    var statusIdentifier: String?
    /// Amber outline while the offer is still for sale.
    var highlighted: Bool
    let identifier: String
    let button: PurchaseButton?
    var restoreIdentifier: String?
    var onRestore: (() -> Void)?
    var restoreDisabled: Bool
    let content: () -> Content

    init(icon: String, title: String, subtitle: String? = nil,
         status: String? = nil, statusIdentifier: String? = nil,
         highlighted: Bool = true, identifier: String,
         button: PurchaseButton?,
         restoreIdentifier: String? = nil, onRestore: (() -> Void)? = nil, restoreDisabled: Bool = false,
         @ViewBuilder content: @escaping () -> Content) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.status = status
        self.statusIdentifier = statusIdentifier
        self.highlighted = highlighted
        self.identifier = identifier
        self.button = button
        self.restoreIdentifier = restoreIdentifier
        self.onRestore = onRestore
        self.restoreDisabled = restoreDisabled
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: EconSpace.s) {
            EconAdaptiveRow {
                HStack(alignment: .firstTextBaseline, spacing: EconSpace.xs) {
                    Image(systemName: icon)
                        .font(EconType.title3)
                        .foregroundColor(EconColor.accent)
                        .accessibilityHidden(true)
                    Text(title)
                        .font(EconType.title3)
                        .foregroundColor(EconColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }
                Spacer(minLength: EconSpace.xxs)
                if let status {
                    Text(status)
                        .font(EconType.footnote.weight(.semibold))
                        .foregroundColor(EconColor.interactive)
                        .accessibilityIdentifier(statusIdentifier ?? "\(identifier)-status")
                }
            }
            if let subtitle {
                Text(subtitle)
                    .font(EconType.subheadline)
                    .foregroundColor(EconColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content()
            if let button { button }
            if let onRestore {
                Button("Restore Purchases", action: onRestore)
                    .buttonStyle(EconLinkButton())
                    .frame(maxWidth: .infinity)
                    .disabled(restoreDisabled)
                    .accessibilityIdentifier(restoreIdentifier ?? "\(identifier)-restore")
            }
        }
        .econCard(elevation: highlighted ? .outlined : .flat)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}

extension OfferCard where Content == EmptyView {
    init(icon: String, title: String, subtitle: String? = nil, highlighted: Bool = true,
         identifier: String, button: PurchaseButton?,
         restoreIdentifier: String? = nil, onRestore: (() -> Void)? = nil, restoreDisabled: Bool = false) {
        self.init(icon: icon, title: title, subtitle: subtitle, highlighted: highlighted, identifier: identifier,
                  button: button, restoreIdentifier: restoreIdentifier, onRestore: onRestore,
                  restoreDisabled: restoreDisabled) { EmptyView() }
    }
}

// MARK: - Purchase / restore plumbing shared by every offer

/// The side effects around a purchase or restore that every surface must do
/// the same way: the ad blocker while StoreKit's sheet is up, the review-prompt
/// negative-session notes, entitlement sync, the diagnostic for a failed
/// restore, and the one alert copy (`PurchaseAlertCopy`).
@MainActor
enum PurchaseFlow {

    static func buy(_ id: PurchaseManager.ProductID, from entryPoint: EBEntryPoint,
                    store: PurchaseManager, growth: EconGrowth,
                    accessGranted: () -> Bool) async -> PurchaseAlertCopy.Alert? {
        growth.monetization.setBlocker(.purchase, active: true)
        growth.review.noteNegativeSessionEvent(.purchase)
        let result = await store.purchase(id, from: entryPoint)
        growth.monetization.setBlocker(.purchase, active: false)
        growth.syncEntitlements(from: store)
        if case .success = result {} else {
            growth.review.noteNegativeSessionEvent(.purchaseFailure)
        }
        return alert(for: result, kind: .purchase, store: store, growth: growth, accessGranted: accessGranted())
    }

    static func restore(from entryPoint: EBEntryPoint, store: PurchaseManager,
                        growth: EconGrowth) async -> PurchaseAlertCopy.Alert? {
        growth.monetization.setBlocker(.restore, active: true)
        growth.review.noteNegativeSessionEvent(.restore)
        let result = await store.restorePurchases(from: entryPoint)
        growth.monetization.setBlocker(.restore, active: false)
        growth.syncEntitlements(from: store)
        if case .failed = result {
            growth.review.noteNegativeSessionEvent(.restoreFailure)
            growth.diagnosticLog.capture(.restoreFailed)
        }
        return alert(for: result, kind: .restore, store: store, growth: growth, accessGranted: true)
    }

    private static func alert(for result: PurchaseManager.PurchaseResult, kind: PurchaseAlertCopy.Kind,
                              store: PurchaseManager, growth: EconGrowth,
                              accessGranted: Bool) -> PurchaseAlertCopy.Alert? {
        if result == .productUnavailable {
            growth.diagnosticLog.capture(.storeProductsUnavailable)
            Task { await store.loadProducts() }
        }
        guard let next = PurchaseAlertCopy.alert(for: result, kind: kind, accessGranted: accessGranted) else { return nil }
        // A user-facing error is a bad moment to ask for a rating (rules-v2).
        growth.review.noteNegativeSessionEvent(.errorShown)
        return next
    }
}
