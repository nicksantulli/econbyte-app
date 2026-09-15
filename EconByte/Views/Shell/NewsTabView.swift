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
            VStack(alignment: .leading, spacing: EconSpace.section) {
                if let brief = briefs.latest {
                    BriefDocumentView(brief: brief, unlocked: unlocked, showsRefreshState: true,
                                      onProPaywall: { router.presentProPaywall(.brief) })
                    if unlocked { archiveSection }
                    methodologyRow
                } else {
                    unavailable
                }
            }
            .padding(.horizontal, EconSpace.gutter)
            .padding(.top, EconSpace.s)
            .padding(.bottom, EconSpace.xxl)
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
        VStack(alignment: .leading, spacing: EconSpace.xs) {
            EconSectionLabel(text: "Archive")
            ForEach(archiveBriefs) { past in
                    Button { archived = past } label: {
                        HStack(spacing: EconSpace.s) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: EconSpace.xxs) {
                                    Text(BriefDates.long(past.briefDate))
                                        .font(EconType.caption.weight(.semibold))
                                        .foregroundColor(EconColor.textTertiary)
                                    if past.briefDate == briefs.latest?.briefDate {
                                        EconBadge(text: "Latest", style: .interactive)
                                            .accessibilityLabel("latest")
                                    }
                                }
                                Text(past.headline)
                                    .font(EconType.subheadline.weight(.medium))
                                    .foregroundColor(EconColor.textPrimary)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: EconSpace.xs)
                            Image(systemName: "chevron.right")
                                .font(EconType.footnote.weight(.semibold))
                                .foregroundColor(EconColor.textTertiary)
                                .accessibilityHidden(true)
                        }
                        .econRow()
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("briefArchiveRow-\(past.briefDate)")
            }
        }
    }

    private var methodologyRow: some View {
        Button { showMethodology = true } label: {
            HStack(spacing: EconSpace.s) {
                Image(systemName: "questionmark.circle.fill")
                    .foregroundColor(EconColor.interactive)
                    .accessibilityHidden(true)
                Text("How this brief is made")
                    .font(EconType.subheadline.weight(.medium))
                    .foregroundColor(EconColor.textPrimary)
                    .multilineTextAlignment(.leading)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(EconType.footnote.weight(.semibold))
                    .foregroundColor(EconColor.textTertiary)
                    .accessibilityHidden(true)
            }
            .econRow()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("briefMethodologyButton")
    }

    private var unavailable: some View {
        VStack(spacing: EconSpace.s) {
            Text("The brief isn't available right now.")
                .font(EconType.headline)
                .foregroundColor(EconColor.textPrimary)
                .multilineTextAlignment(.center)
            Button("Try again") { Task { await briefs.refreshIfNeeded(force: true) } }
                .buttonStyle(SecondaryButton())
                .padding(.horizontal, EconSpace.xxl)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, EconSpace.xxl * 2)
    }
}
