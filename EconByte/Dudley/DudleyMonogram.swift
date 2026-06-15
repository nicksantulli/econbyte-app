import SwiftUI

// MARK: - Dudley Studio Kit
//
// Shared, drop-in studio-branding component used across every Dudley app
// (Vibe Rater, Powell Prowl, Table Talk, EconByte, Last Human, and the default
// for all future apps).
//
// This file has ZERO app-specific dependencies — copy the whole `Dudley/`
// folder into any Dudley app and it compiles as-is. The canonical source of
// truth lives in the Dudley vault under `vault/engineering/dudley-studio-kit/`.
//
// DUD-193 rebrand: the studio mark is now the operator-provided longhorn-D
// PNG (`dudley-mark.png`, shipped in Assets.xcassets as the `DudleyMark`
// imageset) on the brand cream tile. We render the supplied art rather than
// re-drawing it in code — per the design handoff, the PNG is the source of
// truth and the old hand-drawn navy/cyan "D" monogram is retired.

/// The Dudley Development monogram: the longhorn-D mark (`DudleyMark` asset)
/// centered on the brand cream tile. Renders at any `size` (square).
struct DudleyMonogram: View {
    /// Edge length in points. The tile is always square.
    var size: CGFloat
    /// Continuous corner radius. Defaults to the brand ratio (16pt @ 72pt).
    var cornerRadius: CGFloat? = nil

    private var corner: CGFloat { cornerRadius ?? size * (16.0 / 72.0) }

    var body: some View {
        ZStack {
            DudleyBrand.cream
            Image("DudleyMark")
                .resizable()
                .renderingMode(.original)
                .aspectRatio(contentMode: .fit)
                // The mark reads best with a little breathing room inside the tile.
                .padding(size * 0.16)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .accessibilityHidden(true)
    }
}

// MARK: - Brand tokens
//
// Warm-Americana palette (DUD-193 brand-story): warm browns, cream, rust.
// The cream value `#F0E6CE` is the exact background the longhorn-D mark was
// designed against — always pair the mark with this cream, never pure white.

enum DudleyBrand {
    /// Brand cream — the canonical mark background (#F0E6CE).
    static let cream = Color(red: 0.941, green: 0.902, blue: 0.808)
    /// Scorched / dark-brown mark ink (#3D1C08) — used for wordmark + accents.
    static let darkBrown = Color(red: 0.239, green: 0.110, blue: 0.031)
    /// Studio intro background — the warm cream the mark materialises onto.
    static let intro = cream
    /// Intro wordmark primary — "Dudley" (#3D1C08, dark brown on cream).
    static let wordmarkPrimary = darkBrown
    /// Intro wordmark secondary — "DEVELOPMENT" (#7A4A22, dusty brown).
    static let wordmarkSecondary = Color(red: 0.478, green: 0.290, blue: 0.133)
    /// Hot branding-iron amber, used for the reveal glow (#D47C1A).
    static let amber = Color(red: 0.831, green: 0.486, blue: 0.102)
    /// Rust accent (#B5471F) — branding-iron tip / honky-tonk hit.
    static let rust = Color(red: 0.710, green: 0.278, blue: 0.122)

    static let siteURL = URL(string: "https://dudleyapps.com")!
    static let tagline = "Small apps with real character."
}

#Preview("Monogram sizes") {
    VStack(spacing: 24) {
        DudleyMonogram(size: 96)
        DudleyMonogram(size: 72)
        DudleyMonogram(size: 28, cornerRadius: 6)
    }
    .padding()
    .background(Color.black)
}
