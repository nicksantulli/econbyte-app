import SwiftUI

/// The Daily Economic Brief (1.1.4).
///
/// Pro readers see the whole document; everyone else sees the headline and the
/// first released item as a teaser, then a lock with the Pro call to action.
/// Every released item carries its figures, a plain-English "what it says" and
/// "why it matters", and a link to the official source with the time it was
/// read. The disclaimer and "How this brief is made" are always visible.
struct BriefView: View {
    var onProPaywall: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: PurchaseManager
    @EnvironmentObject private var briefs: BriefStore
    @State private var showMethodology = false
    @State private var didRecordOpen = false

    private var unlocked: Bool { store.isProActive }

    var body: some View {
        NavigationStack {
            ZStack {
                Econ.ocean.ignoresSafeArea()
                if let brief = briefs.latest {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            header(brief)
                            if unlocked {
                                fullBrief(brief)
                            } else {
                                teaser(brief)
                            }
                            disclaimer(brief)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 40)
                    }
                    .refreshable { await briefs.refreshIfNeeded(force: true) }
                } else {
                    VStack(spacing: 12) {
                        Text("The brief isn't available right now.")
                            .foregroundColor(Econ.white)
                        Button("Try again") { Task { await briefs.refreshIfNeeded(force: true) } }
                            .buttonStyle(SecondaryButton())
                            .padding(.horizontal, 40)
                    }
                }
            }
            .navigationTitle("Daily Brief")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showMethodology = true } label: {
                        Image(systemName: "questionmark.circle").foregroundColor(Econ.sky)
                    }
                    .accessibilityLabel("How this brief is made")
                    .accessibilityIdentifier("briefMethodologyButton")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") { dismiss() }.foregroundColor(Econ.sky)
                        .accessibilityIdentifier("briefCloseButton")
                }
            }
            .sheet(isPresented: $showMethodology) {
                if let brief = briefs.latest {
                    BriefMethodologyView(brief: brief)
                }
            }
        }
        .tint(Econ.sky)
        .task {
            await briefs.refreshIfNeeded()
            if !didRecordOpen {
                didRecordOpen = true
                EBEvents.briefOpened(accessState: unlocked ? .unlocked : .locked, source: briefs.source)
            }
        }
        .accessibilityIdentifier("briefView")
    }

    // MARK: Pieces

    private func header(_ brief: DailyBrief) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(Self.longDate(brief.briefDate).uppercased())
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(Econ.subtext)
                    .tracking(1.5)
                Spacer()
                if brief.isSample == true {
                    Text("SAMPLE")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(Econ.ink)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Econ.amber)
                        .cornerRadius(4)
                        .accessibilityLabel("Sample brief")
                }
                if briefs.isRefreshing { ProgressView().tint(Econ.sky).scaleEffect(0.8) }
            }
            Text(brief.headline)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundColor(Econ.white)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("briefHeadline")
            if let note = briefs.refreshNote {
                Text(note)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(Econ.subtext)
            }
            EducationalNoticeBanner(text: "Informational only — not investment advice. Built from official releases; no news sites.")
        }
    }

    private func fullBrief(_ brief: DailyBrief) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if let released = brief.section(.released) {
                sectionTitle(released.title)
                ForEach(released.items ?? []) { item in
                    ReleasedItemCard(item: item)
                }
            }
            if let scheduled = brief.section(.scheduled) {
                sectionTitle(scheduled.title)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(scheduled.items ?? []) { item in
                        ScheduledRow(item: item)
                    }
                }
                .padding(14)
                .background(Econ.tide.opacity(0.12))
                .cornerRadius(12)
            }
            if let concept = brief.section(.concept) {
                sectionTitle(concept.title)
                ConceptCard(section: concept)
            }
            if !briefs.history.isEmpty {
                sectionTitle("Past briefs")
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(briefs.history) { past in
                        Text("\(Self.longDate(past.briefDate)) — \(past.headline)")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundColor(Econ.white.opacity(0.8))
                            .lineLimit(2)
                    }
                }
                .padding(14)
                .background(Econ.tide.opacity(0.08))
                .cornerRadius(12)
            }
        }
    }

    private func teaser(_ brief: DailyBrief) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if let released = brief.section(.released), let first = brief.teaserItem {
                sectionTitle(released.title)
                ReleasedItemCard(item: first)
                    .accessibilityIdentifier("briefTeaserItem")
            }
            VStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 28))
                    .foregroundColor(Econ.amber)
                    .accessibilityHidden(true)
                Text("The rest of the brief is part of EconByte Pro")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(Econ.white)
                    .multilineTextAlignment(.center)
                Text("Every U.S. business day: what official releases said, what's scheduled this week, and one concept to know — with sources, never news sites.")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(Econ.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                Button("See EconByte Pro") { onProPaywall?() }
                    .buttonStyle(PrimaryButton())
                    .accessibilityIdentifier("briefLockedProButton")
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .background(Econ.tide.opacity(0.15))
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Econ.amber.opacity(0.35), lineWidth: 1))
        }
    }

    private func disclaimer(_ brief: DailyBrief) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(brief.disclaimer)
                .font(.system(size: 11, design: .rounded))
                .foregroundColor(Econ.subtext)
                .fixedSize(horizontal: false, vertical: true)
            Button("How this brief is made") { showMethodology = true }
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(Econ.sky)
        }
        .padding(.top, 4)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundColor(Econ.subtext)
            .tracking(1.5)
    }

    static func longDate(_ iso: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: iso) else { return iso }
        // Same UTC calendar on the way out: the brief date is a calendar day,
        // and formatting it in the device's zone shifted it a day west.
        let output = DateFormatter()
        output.calendar = formatter.calendar
        output.locale = .current
        output.timeZone = formatter.timeZone
        output.setLocalizedDateFormatFromTemplate("EEEEMMMMdyyyy")
        return output.string(from: date)
    }
}

// MARK: - Cards

struct ReleasedItemCard: View {
    let item: BriefItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.title ?? "")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(Econ.white)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                if let date = item.releaseDate {
                    Text(date)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(Econ.subtext)
                }
            }
            if let figures = item.figures, !figures.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                    ForEach(Array(figures.enumerated()), id: \.offset) { _, figure in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(figure.value)
                                .font(.system(size: 18, weight: .heavy, design: .rounded))
                                .foregroundColor(Econ.amberLight)
                                .minimumScaleFactor(0.7)
                                .lineLimit(1)
                            Text(figure.label)
                                .font(.system(size: 11, design: .rounded))
                                .foregroundColor(Econ.subtext)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            if let summary = item.summary {
                Text(summary)
                    .font(.system(size: 14, design: .rounded))
                    .foregroundColor(Econ.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let meaning = item.meaning {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lightbulb").foregroundColor(Econ.sky).accessibilityHidden(true)
                    Text(meaning)
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(Econ.white.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let source = item.source, let url = URL(string: source.url) {
                Link(destination: url) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(source.organization) — \(source.documentTitle)")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(Econ.sky)
                            .multilineTextAlignment(.leading)
                        Text("Read \(Self.shortTimestamp(source.retrievedAt))")
                            .font(.system(size: 10, design: .rounded))
                            .foregroundColor(Econ.subtext)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(16)
        .background(Econ.tide.opacity(0.12))
        .cornerRadius(14)
    }

    static func shortTimestamp(_ iso: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: iso) else { return iso }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

struct ScheduledRow: View {
    let item: BriefItem
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(item.date ?? "")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(Econ.amberLight)
                .frame(width: 84, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                if let url = item.url.flatMap(URL.init(string:)) {
                    Link(item.title ?? "", destination: url)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(Econ.white)
                } else {
                    Text(item.title ?? "")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(Econ.white)
                }
                Text(item.organization ?? "")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(Econ.subtext)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct ConceptCard: View {
    let section: BriefSection
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section.conceptTitle ?? "")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(Econ.white)
            Text(section.text ?? "")
                .font(.system(size: 14, design: .rounded))
                .foregroundColor(Econ.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
            if let cardID = section.linkedCardID,
               let card = ContentStore.shared.everyCard.first(where: { $0.id == cardID }) {
                Label("In your cards: \(card.concept) (\(ContentStore.shared.topicName(for: card.topicId)))",
                      systemImage: "rectangle.on.rectangle")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Econ.sky)
            } else if let lessonID = section.linkedLessonID,
                      let lesson = ContentStore.shared.courses?.lesson(withID: lessonID) {
                Label("In the courses: \(lesson.title)", systemImage: "book")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Econ.sky)
            }
        }
        .padding(16)
        .background(Econ.sky.opacity(0.08))
        .cornerRadius(14)
    }
}

struct BriefMethodologyView: View {
    let brief: DailyBrief
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ZStack {
                Econ.ocean.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(brief.methodology)
                            .font(.system(size: 15, design: .rounded))
                            .foregroundColor(Econ.white.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                        Text("SOURCES THE BRIEF MAY USE")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(Econ.subtext)
                            .tracking(1.5)
                        Text(DailyBrief.allowedHosts.sorted().joined(separator: "\n"))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(Econ.white.opacity(0.75))
                        Text(brief.disclaimer)
                            .font(.system(size: 12, design: .rounded))
                            .foregroundColor(Econ.subtext)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("How this brief is made")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }.foregroundColor(Econ.sky)
                }
            }
        }
        .tint(Econ.sky)
    }
}
