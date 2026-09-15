import SwiftUI

/// Browse (1.1.4 shell): search over topic names and card titles, Bookmarks,
/// the 15 core topics and the 6 topic packs.
struct BrowseTabView: View {
    @EnvironmentObject private var content: ContentStore
    @EnvironmentObject private var store: PurchaseManager
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var growth: EconGrowth

    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        EconTabScaffold(scrollSpace: "browse") { proxy in
            VStack(alignment: .leading, spacing: 22) {
                searchField
                if trimmedQuery.isEmpty {
                    bookmarksRow
                    coreTopicsSection
                    packsSection
                } else {
                    searchResults(proxy)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 32)
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
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(Econ.subtext)
                .accessibilityHidden(true)
            TextField("", text: $query,
                      prompt: Text("Search topics and cards").foregroundColor(Econ.subtext))
                .font(.system(size: 16, design: .rounded))
                .foregroundColor(Econ.white)
                .focused($searchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier("browseSearchField")
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(Econ.subtext)
                }
                .accessibilityLabel("Clear search")
                .accessibilityIdentifier("browseSearchClearButton")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Econ.tide.opacity(0.18))
        .cornerRadius(12)
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
                .font(.system(size: 15, design: .rounded))
                .foregroundColor(Econ.white.opacity(0.7))
                .padding(.top, 12)
                .accessibilityIdentifier("browseNoResults")
        }
        if !topics.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
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
            VStack(alignment: .leading, spacing: 10) {
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
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 17))
                    .foregroundColor(locked ? Econ.subtext : Econ.sky)
                    .frame(width: 26)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(Econ.white)
                        .multilineTextAlignment(.leading)
                    Text(subtitle)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(Econ.subtext)
                }
                Spacer(minLength: 8)
                Image(systemName: locked ? "lock.fill" : "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(locked ? Econ.amber : Econ.subtext)
                    .accessibilityHidden(true)
            }
            .padding(12)
            .background(Econ.tide.opacity(0.12))
            .cornerRadius(12)
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
            HStack {
                Image(systemName: "bookmark.fill")
                    .foregroundColor(Econ.amber)
                    .accessibilityHidden(true)
                Text("Bookmarks (\(content.bookmarkedCards.count))")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundColor(Econ.white)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(Econ.subtext)
                    .accessibilityHidden(true)
            }
            .padding(16)
            .background(Econ.tide.opacity(0.12))
            .cornerRadius(12)
        }
        .accessibilityIdentifier("browseBookmarksRow")
    }

    private var coreTopicsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                EconSectionLabel(text: "Core topics")
                Spacer()
                Text("\(content.topics.count)")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(Econ.subtext)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
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
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    EconSectionLabel(text: "Packs")
                    Spacer()
                    Text("\(content.packs.count)")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(Econ.subtext)
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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: topic.icon)
                    .font(.title2)
                    .foregroundColor(locked ? Econ.subtext : Econ.sky)
                Spacer()
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Econ.amber)
                }
            }
            Text(topic.name)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(locked ? Econ.white.opacity(0.55) : Econ.white)
                .lineLimit(2)
            let allTopicCards = content.everyCard.filter { $0.topicId == topic.id }
            let total = allTopicCards.count
            let seen = allTopicCards.filter { content.cardStates[$0.id]?.lastSeen != nil }.count
            Text(locked ? "Unlock to view" : "\(seen)/\(total)")
                .font(.system(size: 12, design: .rounded))
                .foregroundColor(Econ.subtext)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Econ.tide.opacity(locked ? 0.06 : 0.12))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Econ.amber.opacity(locked ? 0.25 : 0), lineWidth: 1)
        )
    }
}
