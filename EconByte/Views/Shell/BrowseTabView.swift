import SwiftUI

/// Browse (1.1.4 shell): search over topic names and card titles, Bookmarks,
/// the 15 core topics and the 6 topic packs.
struct BrowseTabView: View {
    @EnvironmentObject private var content: ContentStore
    @EnvironmentObject private var store: PurchaseManager
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var growth: EconGrowth

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var resultIconWidth: CGFloat = EconSpace.xl

    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        EconTabScaffold(scrollSpace: "browse") { proxy in
            VStack(alignment: .leading, spacing: EconSpace.section) {
                searchField
                if trimmedQuery.isEmpty {
                    bookmarksRow
                    coreTopicsSection
                    packsSection
                } else {
                    searchResults(proxy)
                }
            }
            .padding(.horizontal, EconSpace.gutter)
            .padding(.top, EconSpace.s)
            .padding(.bottom, EconSpace.xxl)
        }
        // Phase 11: the anchored banner on Browse at rest, above the tab bar.
        // Searching is a sensitive surface (portfolio `search_result`,
        // `financial_or_policy_search`) and the keyboard would lift the strip
        // over the results, so the slot is removed while the field is focused
        // or holds a query.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            AdBannerSlot(surface: (searchFocused || !trimmedQuery.isEmpty) ? .search : .browse,
                         monetization: growth.monetization)
        }
    }

    // MARK: Search

    private var searchField: some View {
        HStack(spacing: EconSpace.xs) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(EconColor.textTertiary)
                .accessibilityHidden(true)
            TextField("", text: $query,
                      prompt: Text("Search topics and cards").foregroundColor(EconColor.textTertiary))
                .font(EconType.body)
                .foregroundColor(EconColor.textPrimary)
                .focused($searchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier("browseSearchField")
            if !query.isEmpty {
                EconIconButton(systemImage: "xmark.circle.fill", label: "Clear search",
                               tint: EconColor.textTertiary) {
                    query = ""
                }
                .accessibilityIdentifier("browseSearchClearButton")
            }
        }
        .padding(.leading, EconSpace.s)
        .padding(.trailing, query.isEmpty ? EconSpace.s : 0)
        .padding(.vertical, query.isEmpty ? EconSpace.xs : 0)
        .frame(minHeight: EconSize.tapTarget)
        .background(EconColor.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: EconRadius.control, style: .continuous))
    }

    private struct TopicHit: Identifiable {
        let topic: EconTopic
        let pack: EconPack?
        var id: String { topic.id }
    }

    private var topicHits: [TopicHit] {
        let q = trimmedQuery
        let core = content.topics.filter { $0.name.localizedStandardContains(q) }
            .map { TopicHit(topic: $0, pack: nil) }
        let packed = content.packs.flatMap { pack in
            pack.topics.filter { $0.name.localizedStandardContains(q) }
                .map { TopicHit(topic: $0, pack: pack) }
        }
        return core + packed
    }

    private var cardHits: [EconCard] {
        let q = trimmedQuery
        return Array(content.everyCard.filter { $0.concept.localizedStandardContains(q) }.prefix(40))
    }

    @ViewBuilder
    private func searchResults(_ proxy: ScrollViewProxy) -> some View {
        let topics = topicHits
        let cards = cardHits
        if topics.isEmpty && cards.isEmpty {
            Text("No topics or cards match “\(trimmedQuery)”.")
                .font(EconType.subheadline)
                .foregroundColor(EconColor.textSecondary)
                .padding(.top, EconSpace.s)
                .accessibilityIdentifier("browseNoResults")
        }
        if !topics.isEmpty {
            VStack(alignment: .leading, spacing: EconSpace.xs) {
                EconSectionLabel(text: "Topics")
                ForEach(topics) { hit in
                    resultRow(title: hit.topic.name,
                              subtitle: hit.pack?.name ?? "Core topic",
                              icon: hit.topic.icon,
                              locked: isLocked(topicID: hit.topic.id, pack: hit.pack)) {
                        open(topicID: hit.topic.id, leadingCard: nil, proxy: proxy)
                    }
                    .accessibilityIdentifier("browseTopicResult-\(hit.topic.id)")
                }
            }
        }
        if !cards.isEmpty {
            VStack(alignment: .leading, spacing: EconSpace.xs) {
                EconSectionLabel(text: "Cards")
                ForEach(cards) { card in
                    let pack = content.pack(forTopic: card.topicId)
                    resultRow(title: card.concept,
                              subtitle: content.topicName(for: card.topicId),
                              icon: "rectangle.on.rectangle",
                              locked: isLocked(topicID: card.topicId, pack: pack)) {
                        open(topicID: card.topicId, leadingCard: card, proxy: proxy)
                    }
                    .accessibilityIdentifier("browseCardResult-\(card.id)")
                }
            }
        }
    }

    private func resultRow(title: String, subtitle: String, icon: String, locked: Bool,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: EconSpace.s) {
                Image(systemName: icon)
                    .font(EconType.body)
                    .foregroundColor(locked ? EconColor.textTertiary : EconColor.interactive)
                    .frame(width: resultIconWidth)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(EconType.subheadlineEmphasis)
                        .foregroundColor(EconColor.textPrimary)
                        .multilineTextAlignment(.leading)
                    Text(subtitle)
                        .font(EconType.caption)
                        .foregroundColor(EconColor.textTertiary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: EconSpace.xs)
                Image(systemName: locked ? "lock.fill" : "chevron.right")
                    .font(EconType.footnote.weight(.semibold))
                    .foregroundColor(locked ? EconColor.accent : EconColor.textTertiary)
                    .accessibilityHidden(true)
            }
            .econRow()
        }
        .buttonStyle(.plain)
        .accessibilityValue(Text(locked ? "locked" : ""))
    }

    private func isLocked(topicID: String, pack: EconPack?) -> Bool {
        if let pack { return !store.hasAccess(packProductID: pack.productID) }
        return !content.isTopicFree(topicID) && !store.coreTopicsUnlocked
    }

    /// A readable topic opens its deck (a searched card first). A locked core
    /// topic opens the Unlock All paywall; a locked pack topic scrolls to that
    /// pack's offer, where it can be previewed and bought.
    private func open(topicID: String, leadingCard: EconCard?, proxy: ScrollViewProxy) {
        searchFocused = false
        if let pack = content.pack(forTopic: topicID) {
            guard store.hasAccess(packProductID: pack.productID),
                  let topic = pack.topics.first(where: { $0.id == topicID }) else {
                query = ""
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation { proxy.scrollTo("browsePack-\(pack.id)", anchor: .top) }
                }
                return
            }
            router.openPackTopic(topic, content: content, store: store, entryPoint: .topicGrid,
                                 leadingCard: leadingCard)
        } else if let topic = content.topics.first(where: { $0.id == topicID }) {
            router.openCoreTopic(topic, content: content, store: store, leadingCard: leadingCard)
        }
    }

    // MARK: Sections

    private var bookmarksRow: some View {
        Button {
            router.showBookmarks = true
        } label: {
            HStack(spacing: EconSpace.xs) {
                Image(systemName: "bookmark.fill")
                    .foregroundColor(EconColor.accent)
                    .accessibilityHidden(true)
                Text("Bookmarks (\(content.bookmarkedCards.count))")
                    .font(EconType.body.weight(.medium))
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
        .accessibilityIdentifier("browseBookmarksRow")
    }

    /// Two tile columns, one at the accessibility text sizes.
    private var topicColumns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible()), GridItem(.flexible())]
    }

    private var coreTopicsSection: some View {
        VStack(alignment: .leading, spacing: EconSpace.s) {
            HStack {
                EconSectionLabel(text: "Core topics")
                Spacer()
                Text("\(content.topics.count)")
                    .font(EconType.footnote.weight(.medium))
                    .foregroundColor(EconColor.textTertiary)
            }
            LazyVGrid(columns: topicColumns, spacing: EconSpace.s) {
                ForEach(content.topics) { topic in
                    let locked = !content.isTopicFree(topic.id) && !store.coreTopicsUnlocked
                    Button {
                        router.openCoreTopic(topic, content: content, store: store)
                    } label: {
                        TopicTile(topic: topic, locked: locked)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("topic-\(topic.id)")
                }
            }
        }
    }

    /// Every pack is discoverable here whether or not it is owned: a locked
    /// pack shows a three-card preview and its buy row; a readable pack shows
    /// its four topics as tiles.
    @ViewBuilder
    private var packsSection: some View {
        if !content.packs.isEmpty {
            VStack(alignment: .leading, spacing: EconSpace.s) {
                HStack {
                    EconSectionLabel(text: "Packs")
                    Spacer()
                    Text("\(content.packs.count)")
                        .font(EconType.footnote.weight(.medium))
                        .foregroundColor(EconColor.textTertiary)
                }
                if PackBundleOfferView.isOffered(bundleOwned: store.isPackBundlePurchased,
                                                 allPacksReadable: store.allPacksReadable) {
                    PackBundleOfferView(entryPoint: .topicGrid)
                        .id("browsePackBundle")
                }
                ForEach(content.packs) { pack in
                    PackOfferView(pack: pack, entryPoint: .topicGrid) { topic in
                        router.openPackTopic(topic, content: content, store: store, entryPoint: .topicGrid)
                    }
                    .id("browsePack-\(pack.id)")
                }
            }
        }
    }
}

struct TopicTile: View {
    @EnvironmentObject private var content: ContentStore
    let topic: EconTopic
    var locked: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: EconSpace.xs) {
            HStack {
                Image(systemName: topic.icon)
                    .font(.title2)
                    .foregroundColor(locked ? EconColor.textTertiary : EconColor.interactive)
                Spacer()
                if locked {
                    Image(systemName: "lock.fill")
                        .font(EconType.footnote.weight(.semibold))
                        .foregroundColor(EconColor.accent)
                }
            }
            Text(topic.name)
                .font(EconType.subheadlineEmphasis)
                .foregroundColor(locked ? EconColor.textSecondary : EconColor.textPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            let allTopicCards = content.everyCard.filter { $0.topicId == topic.id }
            let total = allTopicCards.count
            let seen = allTopicCards.filter { content.cardStates[$0.id]?.lastSeen != nil }.count
            // A locked tile shows nothing on this line (the lock says it); the
            // line keeps its height so tiles in a row stay aligned.
            Text("\(seen)/\(total)")
                .font(EconType.caption)
                .foregroundColor(EconColor.textTertiary)
                .opacity(locked ? 0 : 1)
                .accessibilityHidden(locked)
        }
        .padding(EconSpace.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(EconColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: EconRadius.control, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: EconRadius.control, style: .continuous)
                .stroke(locked ? EconColor.accentOutline : Color.clear, lineWidth: 1)
        )
    }
}
