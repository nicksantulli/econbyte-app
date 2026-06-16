import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var content: ContentStore
    @EnvironmentObject private var streak: StreakManager
    @EnvironmentObject private var store: PurchaseManager
    // Card mode is driven by an identifiable payload (not isPresented + separate
    // @State). Passing the deck through separate @State raced the cover's
    // presentation — the cover could build with an empty `cardModeCards` before
    // the assignment propagated, showing "No cards available." on first tap.
    // `.fullScreenCover(item:)` hands the deck to the cover atomically, so it's
    // always populated. (DUD-251)
    @State private var cardModeSession: CardModeSession?
    @State private var showSettings = false
    @State private var showBookmarks = false
    @State private var showPaywall = false
    @AppStorage("seenOnboarding") private var seenOnboarding = false

    private let dailyGoal = 3

    /// Atomic payload for the card-mode cover — carries the deck + title together
    /// so the cover can never present before its data exists.
    private struct CardModeSession: Identifiable {
        let id = UUID()
        let cards: [EconCard]
        let title: String
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
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                            .foregroundColor(Econ.sky)
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .environmentObject(streak)
                    .environmentObject(store)
            }
            .fullScreenCover(item: $cardModeSession) { session in
                CardModeView(cards: session.cards, title: session.title)
                    .environmentObject(content)
                    .environmentObject(streak)
                    .environmentObject(store)
                    .environmentObject(AdManager.shared)
            }
            .sheet(isPresented: $showBookmarks) {
                BookmarksView()
                    .environmentObject(content)
                    .environmentObject(streak)
                    .environmentObject(AdManager.shared)
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView().environmentObject(store)
            }
        }
        .tint(Econ.sky)
        .onAppear {
            if !seenOnboarding {
                seenOnboarding = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    streak.requestNotificationPermission()
                }
            }
        }
    }

    private func startTodaysSet(_ daily: [EconCard]) {
        cardModeSession = CardModeSession(cards: daily, title: "Today's Set")
    }

    private var todaysSetCard: some View {
        let daily = content.dailySet(count: 8)
        let seen = daily.filter { content.cardStates[$0.id]?.lastSeen != nil }.count
        // Completed = the user has met today's goal (same signal as the streak
        // row's "Today's goal reached ✓"). Reflect it in the CTA.
        let completed = streak.didReachDailyGoalToday
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: completed ? "checkmark.seal.fill" : "newspaper.fill")
                    .foregroundColor(completed ? Econ.sky : Econ.amber)
                    .font(.title3)
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
            Group {
                if completed {
                    Button("Review →") { startTodaysSet(daily) }
                        .buttonStyle(SecondaryButton())
                } else {
                    Button("Start →") { startTodaysSet(daily) }
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
                    TopicTile(topic: topic, locked: locked)
                        .onTapGesture {
                            if locked {
                                showPaywall = true
                            } else {
                                cardModeSession = CardModeSession(
                                    cards: content.cards(for: topic.id), title: topic.name)
                            }
                        }
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
