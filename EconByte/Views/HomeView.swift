import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var content: ContentStore
    @EnvironmentObject private var streak: StreakManager
    @State private var showingCardMode = false
    @State private var cardModeCards: [EconCard] = []
    @State private var cardModeTitle = ""
    @State private var showSettings = false
    @State private var showBookmarks = false
    @AppStorage("seenOnboarding") private var seenOnboarding = false

    private let dailyGoal = 3

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
            .sheet(isPresented: $showSettings) { SettingsView().environmentObject(streak) }
            .fullScreenCover(isPresented: $showingCardMode) {
                CardModeView(cards: cardModeCards, title: cardModeTitle)
                    .environmentObject(content)
                    .environmentObject(streak)
                    .environmentObject(AdManager.shared)
            }
            .sheet(isPresented: $showBookmarks) {
                BookmarksView()
                    .environmentObject(content)
                    .environmentObject(streak)
                    .environmentObject(AdManager.shared)
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

    private var todaysSetCard: some View {
        let daily = content.dailySet(count: 8)
        let seen = daily.filter { content.cardStates[$0.id]?.lastSeen != nil }.count
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "newspaper.fill")
                    .foregroundColor(Econ.amber)
                    .font(.title3)
                Text("TODAY'S CARDS")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(Econ.subtext)
                    .tracking(1.5)
                Spacer()
                Text("\(daily.count) cards")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(Econ.subtext)
            }
            ProgressView(value: Double(seen), total: Double(max(daily.count, 1)))
                .tint(Econ.amber)
                .background(Econ.mist.opacity(0.2))
            Button("Start →") {
                cardModeCards = daily
                cardModeTitle = "Today's Set"
                showingCardMode = true
            }
            .buttonStyle(PrimaryButton())
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
                    TopicTile(topic: topic)
                        .onTapGesture {
                            cardModeCards = content.cards(for: topic.id)
                            cardModeTitle = topic.name
                            showingCardMode = true
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: topic.icon)
                .font(.title2)
                .foregroundColor(Econ.sky)
            Text(topic.name)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(Econ.white)
                .lineLimit(2)
            let allTopicCards = content.allCards.filter { $0.topicId == topic.id }
            let total = allTopicCards.count
            let seen = allTopicCards.filter { content.cardStates[$0.id]?.lastSeen != nil }.count
            Text("\(seen)/\(total)")
                .font(.system(size: 12, design: .rounded))
                .foregroundColor(Econ.subtext)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Econ.tide.opacity(0.12))
        .cornerRadius(12)
    }
}
