import SwiftUI

// MARK: - The one purchase button and offer card (1.1.4 release scope)
//
// Every purchase surface in EconByte — each topic pack, the All Packs Bundle,
// Unlock All, Remove Ads and EconByte Pro — is an `OfferCard` holding one
// `PurchaseButton`. Same size rules everywhere (full width, a Dynamic-Type
// scaled minimum height, one font), the label always carries the StoreKit
// price ("Unlock · $1.99"), an owned product reads "Owned", and the Phase 11
// loading / failed states come from `PurchaseButtonModel`, so no surface can
// drift from the others.

struct PurchaseButton: View {
    let model: PurchaseButtonModel
    let identifier: String
    /// Identifier of the "Prices unavailable — Try again" notice.
    var unavailableIdentifier: String? = nil
    var onRetry: (() -> Void)? = nil
    let action: () -> Void

    @ScaledMetric(relativeTo: .headline) private var minHeight: CGFloat = 52

    var body: some View {
        VStack(spacing: 8) {
            Button(action: action) {
                HStack(spacing: 8) {
                    if model.showsSpinner {
                        ProgressView()
                            .tint(model.style == .primary ? Econ.ink : Econ.sky)
                            .accessibilityHidden(true)
                    }
                    Text(model.label)
                        .lineLimit(3)
                        .minimumScaleFactor(0.85)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(.headline, design: .rounded))
                .foregroundColor(model.style == .primary ? Econ.ink : Econ.sky)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: minHeight)
                .background(model.style == .primary ? Econ.amber : Econ.tide.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Econ.sky.opacity(model.style == .owned ? 0.45 : 0), lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(PurchaseButtonPressStyle())
            .disabled(!model.isEnabled)
            .opacity(model.isEnabled || model.style == .owned ? 1 : 0.55)
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
/// preview, the Pro plan tiles), the purchase button and Restore.
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(Econ.amber)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(.headline, design: .rounded).weight(.heavy))
                    .foregroundColor(Econ.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 4)
                if let status {
                    Text(status)
                        .font(.system(.footnote, design: .rounded).weight(.semibold))
                        .foregroundColor(Econ.sky)
                        .accessibilityIdentifier(statusIdentifier ?? "\(identifier)-status")
                }
            }
            if let subtitle {
                Text(subtitle)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(Econ.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
            content()
            if let button { button }
            if let onRestore {
                Button("Restore Purchases", action: onRestore)
                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                    .foregroundColor(Econ.sky)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .buttonStyle(.borderless)
                    .disabled(restoreDisabled)
                    .accessibilityIdentifier(restoreIdentifier ?? "\(identifier)-restore")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Econ.tide.opacity(0.12))
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Econ.amber.opacity(highlighted ? 0.35 : 0), lineWidth: 1))
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
