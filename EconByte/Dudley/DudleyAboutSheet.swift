import SwiftUI

// MARK: - Dudley Studio Kit — "Made by Dudley Development" About sheet
//
// Presented from the Settings "About" row. Stays in-app (a sheet, not a Safari
// hand-off) and adapts to the host app's color scheme via system colors. The
// single external touch point is the labelled "Visit dudleyapps.com" button.
// Design: DUD-146.

/// A tappable Settings row that opens the Dudley About sheet.
struct DudleyAboutRow: View {
    @State private var showSheet = false

    var body: some View {
        Button { showSheet = true } label: {
            HStack(spacing: 12) {
                DudleyMonogram(size: 28, cornerRadius: 6)
                Text("Made by Dudley Development")
                    .font(.system(size: 16))
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens info about the studio")
        .sheet(isPresented: $showSheet) { DudleyAboutSheet() }
    }
}

/// The studio About sheet: monogram, wordmark, tagline, the one external link,
/// and a "More by Dudley" cross-promo list.
struct DudleyAboutSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                DudleyMonogram(size: 56)
                    .padding(.top, 28)

                VStack(spacing: 4) {
                    Text("Dudley")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.primary)
                    Text("DEVELOPMENT")
                        .font(.system(size: 10, weight: .light))
                        .foregroundColor(.secondary)
                        .tracking(4)
                }

                Text(DudleyBrand.tagline)
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Link(destination: DudleyBrand.siteURL) {
                    Text("Visit dudleyapps.com ↗")
                        .font(.system(size: 16, weight: .medium))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                        .background(Color.accentColor.opacity(0.12))
                        .foregroundColor(.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .padding(.top, 4)

                if !DudleyApps.crossPromo.isEmpty {
                    moreByDudley
                        .padding(.top, 8)
                }

                Text("Version \(Bundle.main.shortVersion) (\(Bundle.main.buildNumber))")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
            }
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .presentationDragIndicator(.visible)
    }

    private var moreByDudley: some View {
        VStack(spacing: 0) {
            HStack {
                dividerLine
                Text("MORE BY DUDLEY")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .tracking(1)
                    .fixedSize()
                dividerLine
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)

            ForEach(DudleyApps.crossPromo) { app in
                crossPromoRow(app)
            }
        }
    }

    private func crossPromoRow(_ app: DudleyApp) -> some View {
        Link(destination: app.storeURL ?? DudleyBrand.siteURL) {
            HStack(spacing: 12) {
                letterTile(for: app)
                Text(app.name)
                    .font(.system(size: 16))
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
    }

    /// Simple letter tile so cross-promo needs no bundled icon from other apps.
    private func letterTile(for app: DudleyApp) -> some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(app.tileColor)
            .frame(width: 32, height: 32)
            .overlay(
                Text(String(app.name.prefix(1)))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            )
    }

    private var dividerLine: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.25))
            .frame(height: 1)
    }
}

#Preview("About sheet") { DudleyAboutSheet() }
#Preview("About row") {
    List { Section("About") { DudleyAboutRow() } }
}
