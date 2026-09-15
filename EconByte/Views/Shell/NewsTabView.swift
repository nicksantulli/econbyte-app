import SwiftUI

/// News (1.1.4 shell): the Daily Economic Brief — the latest brief inline, the
/// archive of past briefs, what is scheduled this week, and how the brief is
/// made. Readers without Pro see the free teaser and the way in.
struct NewsTabView: View {
    @EnvironmentObject private var store: PurchaseManager
    @EnvironmentObject private var briefs: BriefStore
    @EnvironmentObject private var router: AppRouter

    @State private var showMethodology = false
    @State private var archived: DailyBrief?

    private var unlocked: Bool { store.isProActive }

    var body: some View {
        EconTabScaffold(scrollSpace: "news",
                        onRefresh: { await briefs.refreshIfNeeded(force: true) }) { _ in
            VStack(alignment: .leading, spacing: 24) {
                if let brief = briefs.latest {
                    BriefDocumentView(brief: brief, unlocked: unlocked, showsRefreshState: true,
                                      onProPaywall: { router.presentProPaywall(.brief) })
                    if unlocked { archiveSection }
                    methodologyRow
                } else {
                    unavailable
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .sheet(isPresented: $showMethodology) {
            if let brief = briefs.latest { BriefMethodologyView(brief: brief) }
        }
        .sheet(item: $archived) { brief in
            BriefArchiveView(brief: brief)
                .environmentObject(briefs)
        }
        .task { await briefs.refreshIfNeeded() }
        .onAppear {
            guard briefs.latest != nil else { return }
            EBEvents.briefOpened(accessState: unlocked ? .unlocked : .locked, source: briefs.source)
        }
    }

    /// Every brief on the device, newest first: the one shown above, then the
    /// older ones. With no published brief yet these are the bundled samples.
    private var archiveBriefs: [DailyBrief] {
        (briefs.latest.map { [$0] } ?? []) + briefs.history
    }

    private var archiveSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            EconSectionLabel(text: "Archive")
            ForEach(archiveBriefs) { past in
                    Button { archived = past } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(BriefDates.long(past.briefDate))
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundColor(Econ.subtext)
                                    if past.briefDate == briefs.latest?.briefDate {
                                        Text("LATEST")
                                            .font(.system(size: 9, weight: .bold, design: .rounded))
                                            .foregroundColor(Econ.sky)
                                            .accessibilityLabel("latest")
                                    }
                                }
                                Text(past.headline)
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .foregroundColor(Econ.white)
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .foregroundColor(Econ.subtext)
                                .accessibilityHidden(true)
                        }
                        .padding(12)
                        .background(Econ.tide.opacity(0.10))
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("briefArchiveRow-\(past.briefDate)")
            }
            if briefs.history.isEmpty {
                Text("Earlier briefs appear here as they're published.")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(Econ.subtext)
            }
        }
    }

    private var methodologyRow: some View {
        Button { showMethodology = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "questionmark.circle.fill")
                    .foregroundColor(Econ.sky)
                    .accessibilityHidden(true)
                Text("How this brief is made")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(Econ.white)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(Econ.subtext)
                    .accessibilityHidden(true)
            }
            .padding(14)
            .background(Econ.tide.opacity(0.12))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("briefMethodologyButton")
    }

    private var unavailable: some View {
        VStack(spacing: 12) {
            Text("The brief isn't available right now.")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(Econ.white)
            Button("Try again") { Task { await briefs.refreshIfNeeded(force: true) } }
                .buttonStyle(SecondaryButton())
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}
