import SwiftUI

/// The Daily Economic Brief document (1.1.4), shown inline in the News tab
/// and, for past briefs, in `BriefArchiveView`.
///
/// Pro readers see the whole document; everyone else sees the headline and the
/// first released item as a teaser, then a lock with the Pro call to action.
/// Every released item carries its figures, a plain-English "what it says" and
/// "why it matters", and a link to the official source with the time it was
/// read. The disclaimer is always visible; "How this brief is made" is one tap
/// away from the News tab and the archive.
struct BriefDocumentView: View {
    let brief: DailyBrief
    let unlocked: Bool
    /// The News tab shows the store's refresh spinner and offline note.
    var showsRefreshState = false
    var onProPaywall: (() -> Void)? = nil

    @EnvironmentObject private var briefs: BriefStore

    var body: some View {
        VStack(alignment: .leading, spacing: EconSpace.m) {
            header
            if unlocked {
                fullBrief
            } else {
                teaser
            }
            Text(brief.disclaimer)
                .font(EconType.caption)
                .foregroundColor(EconColor.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: EconSpace.xs) {
            HStack {
                Text(BriefDates.long(brief.briefDate).uppercased())
                    .font(EconType.overline)
                    .foregroundColor(EconColor.textTertiary)
                    .tracking(EconType.overlineTracking)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                if briefs.showsSampleBadge(brief) { BriefSampleBadge() }
                if showsRefreshState, briefs.isRefreshing {
                    ProgressView().tint(EconColor.interactive).controlSize(.small)
                }
            }
            Text(brief.headline)
                .font(EconType.title)
                .foregroundColor(EconColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("briefHeadline")
                .accessibilityAddTraits(.isHeader)
            if showsRefreshState, let note = briefs.refreshNote {
                Text(note)
                    .font(EconType.caption)
                    .foregroundColor(EconColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var fullBrief: some View {
        VStack(alignment: .leading, spacing: EconSpace.m) {
            if let released = brief.section(.released) {
                EconSectionLabel(text: released.title)
                ForEach(released.items ?? []) { item in
                    ReleasedItemCard(item: item)
                }
            }
            if let scheduled = brief.section(.scheduled) {
                EconSectionLabel(text: scheduled.title)
                VStack(alignment: .leading, spacing: EconSpace.xs) {
                    ForEach(scheduled.items ?? []) { item in
                        ScheduledRow(item: item)
                    }
                }
                .econCard()
                .accessibilityIdentifier("briefScheduledSection")
            }
            if let concept = brief.section(.concept) {
                EconSectionLabel(text: concept.title)
                ConceptCard(section: concept)
            }
        }
    }

    private var teaser: some View {
        VStack(alignment: .leading, spacing: EconSpace.m) {
            if let released = brief.section(.released), let first = brief.teaserItem {
                EconSectionLabel(text: released.title)
                ReleasedItemCard(item: first)
                    .accessibilityIdentifier("briefTeaserItem")
            }
            VStack(spacing: EconSpace.s) {
                Image(systemName: "lock.fill")
                    .font(.title)
                    .foregroundColor(EconColor.accent)
                    .accessibilityHidden(true)
                Text("The full brief is part of Pro")
                    .font(EconType.title3)
                    .foregroundColor(EconColor.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button("See EconByte Pro") { onProPaywall?() }
                    .buttonStyle(PrimaryButton())
                    .accessibilityIdentifier("briefLockedProButton")
            }
            .frame(maxWidth: .infinity)
            .econCard(elevation: .outlined)
        }
    }
}

struct BriefSampleBadge: View {
    var body: some View {
        EconBadge(text: "SAMPLE")
            .accessibilityLabel("Sample brief")
    }
}

enum BriefDates {
    /// "Monday, September 14, 2026" for an ISO calendar day. Parsed and
    /// formatted in UTC: the brief date is a calendar day, and formatting it in
    /// the device's zone shifted it a day west.
    static func long(_ iso: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: iso) else { return iso }
        let output = DateFormatter()
        output.calendar = formatter.calendar
        output.locale = .current
        output.timeZone = formatter.timeZone
        output.setLocalizedDateFormatFromTemplate("EEEEMMMMdyyyy")
        return output.string(from: date)
    }
}

/// A past brief from the archive (Pro), in its own sheet.
struct BriefArchiveView: View {
    let brief: DailyBrief

    @Environment(\.dismiss) private var dismiss
    @State private var showMethodology = false

    var body: some View {
        NavigationStack {
            ZStack {
                EconColor.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: EconSpace.m) {
                        BriefDocumentView(brief: brief, unlocked: true)
                        Button("How this brief is made") { showMethodology = true }
                            .buttonStyle(EconLinkButton())
                    }
                    .padding(.horizontal, EconSpace.gutter)
                    .padding(.top, EconSpace.xs)
                    .padding(.bottom, EconSpace.xxl)
                }
            }
            .navigationTitle(BriefDates.long(brief.briefDate))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") { dismiss() }.foregroundColor(EconColor.interactive)
                        .accessibilityIdentifier("briefCloseButton")
                }
            }
            .sheet(isPresented: $showMethodology) { BriefMethodologyView(brief: brief) }
        }
        .tint(EconColor.interactive)
    }
}

// MARK: - Cards

struct ReleasedItemCard: View {
    let item: BriefItem

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var isAccessibilitySize: Bool { dynamicTypeSize.isAccessibilitySize }

    /// Two figure columns, one at the accessibility text sizes.
    private var figureColumns: [GridItem] {
        isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.flexible()), GridItem(.flexible())]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: EconSpace.xs) {
            let titleLayout = isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: EconSpace.xxs))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: EconSpace.xs))
            titleLayout {
                Text(item.title ?? "")
                    .font(EconType.headline)
                    .foregroundColor(EconColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if !isAccessibilitySize { Spacer() }
                if let date = item.releaseDate {
                    Text(date)
                        .font(EconType.caption)
                        .foregroundColor(EconColor.textTertiary)
                }
            }
            if let figures = item.figures, !figures.isEmpty {
                LazyVGrid(columns: figureColumns, alignment: .leading, spacing: EconSpace.xs) {
                    ForEach(Array(figures.enumerated()), id: \.offset) { _, figure in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(figure.value)
                                .font(EconType.figure)
                                .foregroundColor(EconColor.accentText)
                                .minimumScaleFactor(0.7)
                                .lineLimit(isAccessibilitySize ? nil : 1)
                            Text(figure.label)
                                .font(EconType.caption)
                                .foregroundColor(EconColor.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            if let summary = item.summary {
                Text(summary)
                    .font(EconType.subheadline)
                    .foregroundColor(EconColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let meaning = item.meaning {
                HStack(alignment: .top, spacing: EconSpace.xs) {
                    Image(systemName: "lightbulb").foregroundColor(EconColor.interactive).accessibilityHidden(true)
                    Text(meaning)
                        .font(EconType.footnote)
                        .foregroundColor(EconColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let source = item.source, let url = URL(string: source.url) {
                Link(destination: url) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(source.organization) — \(source.documentTitle)")
                            .font(EconType.caption.weight(.semibold))
                            .foregroundColor(EconColor.interactive)
                            .multilineTextAlignment(.leading)
                        Text("Read \(Self.shortTimestamp(source.retrievedAt))")
                            .font(EconType.caption)
                            .foregroundColor(EconColor.textTertiary)
                    }
                    .frame(maxWidth: .infinity, minHeight: EconSize.tapTarget, alignment: .leading)
                    .contentShape(Rectangle())
                }
            }
        }
        .econCard()
    }

    static func shortTimestamp(_ iso: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: iso) else { return iso }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

struct ScheduledRow: View {
    let item: BriefItem

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The date column beside the release (stacked above it at accessibility sizes).
    @ScaledMetric(relativeTo: .caption) private var dateColumnWidth: CGFloat = 84

    var body: some View {
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .top, spacing: EconSpace.xs))
        layout {
            Text(item.date ?? "")
                .font(EconType.caption.weight(.bold))
                .foregroundColor(EconColor.accentText)
                .frame(width: stacked ? nil : dateColumnWidth, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                if let url = item.url.flatMap(URL.init(string:)) {
                    Link(item.title ?? "", destination: url)
                        .font(EconType.footnote.weight(.semibold))
                        .foregroundColor(EconColor.textPrimary)
                        .multilineTextAlignment(.leading)
                } else {
                    Text(item.title ?? "")
                        .font(EconType.footnote.weight(.semibold))
                        .foregroundColor(EconColor.textPrimary)
                }
                Text(item.organization ?? "")
                    .font(EconType.caption)
                    .foregroundColor(EconColor.textTertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct ConceptCard: View {
    let section: BriefSection
    var body: some View {
        VStack(alignment: .leading, spacing: EconSpace.xs) {
            Text(section.conceptTitle ?? "")
                .font(EconType.headline)
                .foregroundColor(EconColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(section.text ?? "")
                .font(EconType.subheadline)
                .foregroundColor(EconColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let cardID = section.linkedCardID,
               let card = ContentStore.shared.everyCard.first(where: { $0.id == cardID }) {
                Label("In your cards: \(card.concept) (\(ContentStore.shared.topicName(for: card.topicId)))",
                      systemImage: "rectangle.on.rectangle")
                    .font(EconType.caption)
                    .foregroundColor(EconColor.interactive)
            } else if let lessonID = section.linkedLessonID,
                      let lesson = ContentStore.shared.courses?.lesson(withID: lessonID) {
                Label("In the courses: \(lesson.title)", systemImage: "book")
                    .font(EconType.caption)
                    .foregroundColor(EconColor.interactive)
            }
        }
        .econCard(fill: EconColor.interactiveFill)
    }
}

struct BriefMethodologyView: View {
    let brief: DailyBrief
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ZStack {
                EconColor.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: EconSpace.s) {
                        EconSectionLabel(text: "How it's published")
                        ForEach(DailyBrief.publishingProcess, id: \.self) { step in
                            HStack(alignment: .top, spacing: EconSpace.xs) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(EconColor.accent)
                                    .accessibilityHidden(true)
                                Text(step)
                                    .font(EconType.subheadline)
                                    .foregroundColor(EconColor.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .accessibilityIdentifier("briefPublishingProcess")
                        EconSectionLabel(text: "This edition")
                            .padding(.top, EconSpace.xxs)
                        Text(brief.methodology)
                            .font(EconType.subheadline)
                            .foregroundColor(EconColor.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        EconSectionLabel(text: "Sources the brief may use")
                        Text(DailyBrief.allowedHosts.sorted().joined(separator: "\n"))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(EconColor.textSecondary)
                        Text(brief.disclaimer)
                            .font(EconType.caption)
                            .foregroundColor(EconColor.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(EconSpace.gutter)
                }
            }
            .navigationTitle("How this brief is made")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }.foregroundColor(EconColor.interactive)
                }
            }
        }
        .tint(EconColor.interactive)
    }
}
