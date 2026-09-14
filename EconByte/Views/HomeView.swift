import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var content: ContentStore
    @EnvironmentObject private var streak: StreakManager
    @EnvironmentObject private var store: PurchaseManager
    @EnvironmentObject private var growth: EconGrowth
    // Card mode is driven by an identifiable payload (not isPresented + separate
    // @State). Passing the deck through separate @State raced the cover's
    // presentation — the cover could build with an empty `cardModeCards` before
    // the assignment propagated, showing "No cards available." on first tap.
    // `.fullScreenCover(item:)` hands the deck to the cover atomically, so it's
    // always populated. (DUD-251)
    @State private var cardModeSession: CardModeSession?
    @State private var showSettings = false
    @State private var showBookmarks = false
    @State private var paywallSession: PaywallSession?
    @State private var pendingPaywallAfterSettings = false

    private let dailyGoal = 3

    /// Atomic payload for the card-mode cover — carries the deck + title together
    /// so the cover can never present before its data exists.
    private struct CardModeSession: Identifiable {
        let id = UUID()
        let cards: [EconCard]
        let title: String
        /// RECONCILED (1.1.2): the deck and the way it was entered travel with
        /// the session payload for the same DUD-251 reason the cards do — a
        /// separate `@State` races the cover's presentation, and then
        /// `session_started_v1` reports the wrong entry point.
        let mode: EBMode
        let entryPoint: EBEntryPoint
    }

    /// Same atomic-payload pattern as `CardModeSession`, for the same DUD-251
    /// reason: carrying the entry point in a separate `@State` raced the cover's
    /// presentation, so the paywall could render before the entry point landed
    /// and report the wrong one.
    private struct PaywallSession: Identifiable {
        let id = UUID()
        let entryPoint: EconEntryPoint
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Econ.ocean.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        todaysSetCard
                        streakRow
                        Divider().overlay(Econ.mist.opacity(0.3))
                        browseSection
                        bookmarksRow
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("EconByte")
            .navigationBarTitleDisplayMode(.large)
            // Anchored adaptive banner (1.1.3). Reserves no space until an ad
            // has loaded, and is not constructed at all for a Remove Ads owner,
            // an EEA/UK reader, or before the ATT decision
            // (`EconMonetization.canRequestAds`).
            .safeAreaInset(edge: .bottom, spacing: 0) {
                AdBannerSlot(placement: .bannerHome, monetization: growth.monetization)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                            .foregroundColor(Econ.sky)
                    }
                    .accessibilityLabel("Settings")
                    .accessibilityIdentifier("settingsGearButton")
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(onRequestPaywall: { pendingPaywallAfterSettings = true })
                    .environmentObject(streak)
                    .environmentObject(store)
                    .environmentObject(growth)
            }
            .onChange(of: showSettings) { showing in
                guard !showing, pendingPaywallAfterSettings else { return }
                pendingPaywallAfterSettings = false
                paywallSession = PaywallSession(entryPoint: .settings)
            }
            .fullScreenCover(item: $cardModeSession) { session in
                CardModeView(cards: session.cards, title: session.title,
                             mode: session.mode, entryPoint: session.entryPoint)
                    .environmentObject(content)
                    .environmentObject(streak)
                    .environmentObject(store)
                    .environmentObject(growth)
            }
            .sheet(isPresented: $showBookmarks) {
                BookmarksView()
                    .environmentObject(content)
                    .environmentObject(streak)
                    .environmentObject(growth)
            }
            .fullScreenCover(item: $paywallSession) { session in
                PaywallView(entryPoint: session.entryPoint)
                    .environmentObject(store)
                    .environmentObject(growth)
            }
        }
        .tint(Econ.sky)
        // Version 1.0 requested notification authorization automatically one
        // second after Home first appeared. Version 1.1 prompts only from an
        // explicit opt-in (design section 11.1, CONTENT-DECISIONS.md D8).
    }

    /// RECONCILED (1.1.2): lineage A emitted `daily_set_started` carrying a
    /// `set_id` and an exact `eligible_card_count`. The shipped 1.1.2 schema
    /// prohibits both — a set id is a content identifier and an exact count has
    /// a defined bucket — so this is `session_started_v1` with a bucketed deck
    /// size. `CardModeView` emits it, once, when the deck actually appears.
    private func startTodaysSet(_ daily: [EconCard], from entryPoint: EBEntryPoint) {
        cardModeSession = CardModeSession(cards: daily, title: "Today's Set",
                                          mode: .daily, entryPoint: entryPoint)
    }

    /// Test-only hook: exposes card `inf-001`'s full example as the grocery
    /// line's accessibility value so a UI test can prove the visible line is a
    /// verbatim slice of the card (never an invented figure). Off in production.
    private var exposeGroceryBinding: Bool {
        ProcessInfo.processInfo.arguments.contains("-exposeGroceryBinding")
    }

    /// One sourced line of copy under TODAY'S CARDS — the 1.1.1 hotfix, carried
    /// forward. The text is a verbatim slice of bundled card `inf-001`, not
    /// free-typed. Tapping it starts today's set through the same
    /// `startTodaysSet` the Start/Review button calls — no new screen. Inert
    /// when there is no daily set to start.
    ///
    /// RECONCILED (1.1.2): the source attribution shown here changes with the
    /// catalog. On v1.0/1.1.1 content `inf-001` cited the Bureau of Labor
    /// Statistics as free text; on the restored 1.1 catalog it cites
    /// FRED/CPIAUCSL as a structured source, and `ContentStore` renders that as
    /// "organization — document title". The line and the label are always the
    /// card's own.
    @ViewBuilder
    private func groceryLine(_ daily: [EconCard]) -> some View {
        if let g = content.groceryHighlight {
            Button {
                guard !daily.isEmpty else { return }
                startTodaysSet(daily, from: .homeHighlight)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(g.line)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(Econ.white.opacity(0.85))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(g.source)
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundColor(Econ.subtext)
                        // M-5: the restored catalog's structured source renders
                        // as "organization — document title", which for
                        // FRED/CPIAUCSL is long enough to run to three or four
                        // lines at large text sizes and push the highlight's own
                        // line off the card. Two lines is the attribution's
                        // budget; the full source is on the card itself.
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .disabled(daily.isEmpty)
            .accessibilityIdentifier("homeGroceryLine")
            .accessibilityLabel(Text(g.line))
            .accessibilityValue(Text(exposeGroceryBinding ? g.exampleBody : g.source))
            .accessibilityHint(Text("Starts today's set"))
        }
    }

    private var todaysSetCard: some View {
        let daily = content.dailySet(count: 8, unlockedAll: store.isUnlockAllPurchased)
        let seen = daily.filter { content.cardStates[$0.id]?.lastSeen != nil }.count
        // Completed = the user has met today's goal (same signal as the streak
        // row's "Today's goal reached ✓"). Reflect it in the CTA.
        let completed = streak.didReachDailyGoalToday
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: completed ? "checkmark.seal.fill" : "newspaper.fill")
                    .foregroundColor(completed ? Econ.sky : Econ.amber)
                    .font(.title3)
                    // Decorative: the adjacent text carries the meaning, and an
                    // audit otherwise reads the raw SF Symbol name aloud.
                    .accessibilityHidden(true)
                Text("TODAY'S CARDS")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(Econ.subtext)
                    .tracking(1.5)
                Spacer()
                Text(completed ? "Done ✓" : "\(daily.count) cards")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(completed ? Econ.sky : Econ.subtext)
            }
            ProgressView(value: completed ? 1 : Double(seen),
                         total: completed ? 1 : Double(max(daily.count, 1)))
                .tint(completed ? Econ.sky : Econ.amber)
                .background(Econ.mist.opacity(0.2))
            groceryLine(daily)
            Group {
                if completed {
                    Button("Review →") { startTodaysSet(daily, from: .home) }
                        .buttonStyle(SecondaryButton())
                } else {
                    Button("Start →") { startTodaysSet(daily, from: .home) }
                        .buttonStyle(PrimaryButton())
                }
            }
        }
        .padding(20)
        .background(Econ.tide.opacity(0.15))
        .cornerRadius(16)
    }

    private var streakRow: some View {
        HStack(spacing: 12) {
            Text("🔥")
                .font(.title2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Streak: \(streak.currentStreak) day\(streak.currentStreak == 1 ? "" : "s")")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundColor(Econ.amber)
                Text(streak.cardsTodayCount >= dailyGoal
                     ? "Today's goal reached ✓"
                     : "\(dailyGoal - streak.cardsTodayCount) more card\(dailyGoal - streak.cardsTodayCount == 1 ? "" : "s") to keep your streak.")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(Econ.white.opacity(0.6))
            }
            Spacer()
        }
    }

    private var browseSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("BROWSE TOPICS")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(Econ.subtext)
                .tracking(1.5)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(content.topics) { topic in
                    let locked = !content.isTopicFree(topic.id) && !store.isUnlockAllPurchased
                    Button {
                        if locked {
                            // RECONCILED (1.1.2): `topic_id` was allowed by
                            // lineage A's schema and is PROHIBITED by the
                            // shipped one — a topic id is a content identifier.
                            // The entry point and the access state carry the
                            // funnel; the topic does not travel.
                            EBEvents.lockedTopicTapped(entryPoint: .topicGrid)
                            paywallSession = PaywallSession(entryPoint: .topicGrid)
                        } else {
                            EBEvents.topicOpened(
                                entryPoint: .topicGrid,
                                accessState: content.accessState(
                                    for: topic.id,
                                    unlockedAll: store.isUnlockAllPurchased))
                            cardModeSession = CardModeSession(
                                cards: content.cards(for: topic.id, unlockedAll: store.isUnlockAllPurchased),
                                title: topic.name,
                                mode: .topic,
                                entryPoint: .topicGrid)
                        }
                    } label: {
                        TopicTile(topic: topic, locked: locked)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("topic-\(topic.id)")
                }
            }
        }
    }

    private var bookmarksRow: some View {
        Button {
            showBookmarks = true
        } label: {
            HStack {
                Image(systemName: "bookmark.fill")
                    .foregroundColor(Econ.amber)
                Text("Bookmarks (\(content.bookmarkedCards.count))")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundColor(Econ.white)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(Econ.subtext)
            }
            .padding(16)
            .background(Econ.tide.opacity(0.12))
            .cornerRadius(12)
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
            let allTopicCards = content.allCards.filter { $0.topicId == topic.id }
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
