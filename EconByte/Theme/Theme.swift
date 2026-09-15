import SwiftUI

// MARK: - EconByte design system (1.1.5, Phase 19 audit)
//
// Every view takes its type, spacing, radii, colours and elevation from the
// tokens below — never a point size, padding, radius or ad-hoc opacity of its
// own. `DesignSystemTests` scans `Views/` and fails on a raw `.system(size:)`,
// a numeric corner radius or the retired low-contrast `Econ.subtext`.
//
// Appearance: EconByte is a brand-locked dark app (`.preferredColorScheme(.dark)`
// at the root — the navy ground carries the Owner-approved white-and-gold
// wordmark). The palette is therefore one set of dark-ground tokens; the
// system Light setting renders identically, which the audit screenshots prove.
// Contrast (WCAG 2.1, measured on the navy ground and on the raised surface):
// textPrimary 11.6 / 9.8, textSecondary 7.2 / 6.1, textTertiary 6.0 / 5.1,
// interactive 5.8 / 4.9, accentText 9.9 / 8.3; onCard text on the light card
// face 15.0 and 5.4. Every text token passes AA (4.5:1) on every ground.

/// Raw brand colours. Views use `EconColor`; these exist for the tokens,
/// the wordmark and the drawings.
enum Econ {
    static let ocean    = Color(hex: "0F3D52")
    static let tide     = Color(hex: "1A7EA6")
    static let sky      = Color(hex: "5BC4E0")
    static let amber    = Color(hex: "E8A020")
    static let amberLight = Color(hex: "F5C842")
    static let page     = Color(hex: "F7F9FC")
    static let ink      = Color(hex: "0D2533")
    static let mist     = Color(hex: "D8E8EF")
    /// 1.1.4's secondary text colour. 2.5:1 on the navy ground — fails WCAG AA.
    /// Retired from views in 1.1.5; use `EconColor.textTertiary`.
    static let subtext  = Color(hex: "5A7A8A")
    static let white    = Color.white
}

/// Semantic colours.
enum EconColor {
    // Grounds
    static let background = Econ.ocean
    /// Cards, rows, tiles.
    static let surface = Econ.tide.opacity(0.12)
    /// Grouped rows, fields and the one emphasised card on a screen.
    static let surfaceRaised = Econ.tide.opacity(0.18)
    /// Content set into a card (previews, plan tiles, chart and diagram grounds).
    static let surfaceInset = Econ.ocean.opacity(0.6)
    /// The flip card's light face.
    static let cardFace = Econ.page

    // Text on the navy grounds
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.75)
    /// Metadata, captions, section labels, placeholders.
    static let textTertiary = Color(hex: "A3BFCC")
    /// Amber as text (small sizes on a surface need the lighter tone for AA).
    static let accentText = Econ.amberLight

    // Text on the light card face
    static let onCardPrimary = Econ.ink
    static let onCardSecondary = Color(hex: "4E6B79")

    // Interaction
    /// Primary fills: the purchase and primary buttons, selection, badges.
    static let accent = Econ.amber
    /// Text and icons on an `accent` fill (7.1:1).
    static let onAccent = Econ.ink
    /// Links, secondary actions, progress, "done" states.
    static let interactive = Econ.sky
    static let interactiveFill = Econ.tide.opacity(0.15)

    // Lines
    static let divider = Econ.mist.opacity(0.22)
    static let outline = Econ.mist.opacity(0.2)
    static let accentOutline = Econ.amber.opacity(0.35)
}

/// Type scale. Every style is a Dynamic Type text style, so all text scales up
/// to the accessibility sizes; layouts wrap instead of clipping.
enum EconType {
    /// Story cover titles.
    static let display = Font.system(.largeTitle, design: .rounded).weight(.heavy)
    /// Screen and document titles (a brief headline, a course title).
    static let title = Font.system(.title2, design: .rounded).weight(.heavy)
    /// Card titles, story beat headings, flip-card concepts.
    static let title3 = Font.system(.title3, design: .rounded).weight(.bold)
    /// Story beat text: large, comfortable reading.
    static let story = Font.system(.title3, design: .rounded).weight(.medium)
    /// Row titles and buttons.
    static let headline = Font.system(.headline, design: .rounded)
    static let body = Font.system(.body, design: .rounded)
    static let bodyEmphasis = Font.system(.body, design: .rounded).weight(.semibold)
    static let subheadline = Font.system(.subheadline, design: .rounded)
    static let subheadlineEmphasis = Font.system(.subheadline, design: .rounded).weight(.semibold)
    static let footnote = Font.system(.footnote, design: .rounded)
    /// Metadata ("6 min", dates, counts).
    static let caption = Font.system(.caption, design: .rounded).weight(.medium)
    /// Section labels (uppercased, tracked — see `EconSectionLabel`).
    static let overline = Font.system(.caption, design: .rounded).weight(.bold)
    /// Badges and chart annotations.
    static let micro = Font.system(.caption2, design: .rounded).weight(.bold)
    /// Big figures (brief values, story stats).
    static let figure = Font.system(.title2, design: .rounded).weight(.heavy)
    static let overlineTracking: CGFloat = 1.2
}

/// Spacing scale (points). Page gutter `l`, card padding `m`, row padding `s`.
enum EconSpace {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let s: CGFloat = 12
    static let m: CGFloat = 16
    static let l: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    /// Horizontal page margin on every screen.
    static let gutter: CGFloat = l
    /// Vertical gap between sections of a tab.
    static let section: CGFloat = xl
}

/// Corner radii.
enum EconRadius {
    /// Badges and chips.
    static let badge: CGFloat = 6
    /// Rows, tiles, fields, buttons, choices, plan tiles, insets.
    static let control: CGFloat = 12
    /// Cards and sheets of content.
    static let card: CGFloat = 16
    /// Marks inside a drawing (bars, swatches, marker tags).
    static let mark: CGFloat = 3
}

/// Minimum sizes.
enum EconSize {
    /// Apple's minimum hit target.
    static let tapTarget: CGFloat = 44
    /// Every full-width button (purchase and primary), before Dynamic Type
    /// scaling: tall enough for an action line over a price line.
    static let buttonHeight: CGFloat = 60
}

/// Elevation: EconByte is flat on its navy ground — depth comes from surface
/// tone, an outline for emphasis, and one shadow for the physical flip card.
enum EconElevation {
    case flat, outlined, floating
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Surfaces

private struct EconCardModifier: ViewModifier {
    var padding: CGFloat
    var fill: Color
    var elevation: EconElevation
    var outline: Color

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: EconRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: EconRadius.card, style: .continuous)
                    .stroke(outline, lineWidth: elevation == .outlined ? 1 : 0)
            )
            .shadow(color: .black.opacity(elevation == .floating ? 0.25 : 0),
                    radius: elevation == .floating ? 16 : 0, x: 0, y: elevation == .floating ? 8 : 0)
    }
}

private struct EconRowModifier: ViewModifier {
    var fill: Color
    func body(content: Content) -> some View {
        content
            .padding(EconSpace.s)
            .frame(maxWidth: .infinity, minHeight: EconSize.tapTarget, alignment: .leading)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: EconRadius.control, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: EconRadius.control, style: .continuous))
    }
}

extension View {
    /// A card: `m` padding, `card` radius, `surface` fill.
    func econCard(padding: CGFloat = EconSpace.m,
                  fill: Color = EconColor.surface,
                  elevation: EconElevation = .flat,
                  outline: Color = EconColor.accentOutline) -> some View {
        modifier(EconCardModifier(padding: padding, fill: fill, elevation: elevation, outline: outline))
    }

    /// A tappable row: `s` padding, `control` radius, 44 pt minimum height.
    func econRow(fill: Color = EconColor.surface) -> some View {
        modifier(EconRowModifier(fill: fill))
    }

    /// Content set into a card: `s` padding, `control` radius, inset fill.
    func econInset(padding: CGFloat = EconSpace.s) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(EconColor.surfaceInset)
            .clipShape(RoundedRectangle(cornerRadius: EconRadius.control, style: .continuous))
    }
}

// MARK: - Buttons

/// The full-width primary action (not a purchase — purchases use
/// `PurchaseButton`, which shares this size and shape).
struct PrimaryButton: ButtonStyle {
    @ScaledMetric(relativeTo: .headline) private var minHeight: CGFloat = EconSize.buttonHeight

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(EconType.headline)
            .foregroundColor(EconColor.onAccent)
            .multilineTextAlignment(.center)
            .padding(.horizontal, EconSpace.m)
            .padding(.vertical, EconSpace.xs)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .background(EconColor.accent)
            .clipShape(RoundedRectangle(cornerRadius: EconRadius.control, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: EconRadius.control, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

/// The full-width secondary action.
struct SecondaryButton: ButtonStyle {
    @ScaledMetric(relativeTo: .headline) private var minHeight: CGFloat = EconSize.buttonHeight

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(EconType.headline)
            .foregroundColor(EconColor.interactive)
            .multilineTextAlignment(.center)
            .padding(.horizontal, EconSpace.m)
            .padding(.vertical, EconSpace.xs)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .background(EconColor.interactiveFill)
            .clipShape(RoundedRectangle(cornerRadius: EconRadius.control, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: EconRadius.control, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

/// A text link-style action with a 44 pt hit area ("All packs", "Restore Purchases").
struct EconLinkButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(EconType.subheadlineEmphasis)
            .foregroundColor(EconColor.interactive)
            .frame(minHeight: EconSize.tapTarget)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// An icon-only button: 44 × 44 hit area and a required VoiceOver label.
struct EconIconButton: View {
    let systemImage: String
    let label: String
    var tint: Color = EconColor.interactive
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(EconType.headline)
                .foregroundColor(tint)
                .frame(width: EconSize.tapTarget, height: EconSize.tapTarget)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(Text(label))
    }
}

// MARK: - Small components

/// A small pill ("Free", "SAMPLE", "Save 66%", "Current plan").
struct EconBadge: View {
    enum Style { case accent, interactive, quiet }
    let text: String
    var style: Style = .accent

    var body: some View {
        Text(text)
            .font(EconType.micro)
            .foregroundColor(style == .quiet ? EconColor.textSecondary : EconColor.onAccent)
            .padding(.horizontal, EconSpace.xs)
            .padding(.vertical, 2)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: EconRadius.badge, style: .continuous))
            .fixedSize()
    }

    private var background: Color {
        switch style {
        case .accent: return EconColor.accent
        case .interactive: return EconColor.interactive
        case .quiet: return EconColor.surfaceRaised
        }
    }
}

/// Section label used across the app ("TODAY'S CARDS", "CORE TOPICS", …).
struct EconSectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(EconType.overline)
            .foregroundColor(EconColor.textTertiary)
            .tracking(EconType.overlineTracking)
            .accessibilityAddTraits(.isHeader)
    }
}

struct TopicChip: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(EconType.micro)
            .foregroundColor(EconColor.interactive)
            .padding(.horizontal, EconSpace.xs)
            .padding(.vertical, EconSpace.xxs)
            .background(Econ.tide.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: EconRadius.badge, style: .continuous))
    }
}

/// A light-face variant of `TopicChip` for the flip card.
struct CardFaceChip: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(EconType.micro)
            .foregroundColor(Econ.ocean)
            .padding(.horizontal, EconSpace.xs)
            .padding(.vertical, EconSpace.xxs)
            .background(Econ.tide.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: EconRadius.badge, style: .continuous))
    }
}
