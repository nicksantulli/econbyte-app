import SwiftUI
import UIKit

// MARK: - App shell (1.1.4 redesign, Owner order 2026-09-14)
//
// "split up some of the content into tabs — like a home tab, pro, browse sorta
// thing … If we're doing any sort of news then a tab for news."
//
// Four tabs — Home · Browse · News · Pro — under one custom top bar: the
// EconByte wordmark fixed at the top left, the Settings gear at the top right.
// The bar sits OUTSIDE each tab's scroll view, so the wordmark keeps the same
// size and position while the content scrolls (no large → inline title
// collapse, which the Owner asked to remove). A hairline divider fades in once
// the content has scrolled under the bar.
//
// Every modal lives here, on the tab container, driven by `AppRouter`, so any
// tab can start a card session, open a course, or present a paywall, and the
// "dismiss the sheet first, then present the cover" rule (nested presentation
// breaks StoreKit on iPad) is enforced in one place.

enum EconTab: String, Hashable, CaseIterable {
    case home, browse, news, pro

    var title: String {
        switch self {
        case .home: return "Home"
        case .browse: return "Browse"
        case .news: return "News"
        case .pro: return "Pro"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house.fill"
        case .browse: return "square.grid.2x2.fill"
        case .news: return "newspaper.fill"
        case .pro: return "graduationcap.fill"
        }
    }
}

// MARK: Presentation payloads

/// Atomic payload for the card-mode cover — the deck, title, mode and entry
/// point travel together so the cover can never present before its data
/// exists (DUD-251), and `session_started_v1` reports the right entry point.
struct CardModeSession: Identifiable {
    let id = UUID()
    let cards: [EconCard]
    let title: String
    let mode: EBMode
    let entryPoint: EBEntryPoint
}

/// Same atomic-payload pattern for the Unlock All paywall.
struct PaywallSession: Identifiable {
    let id = UUID()
    let entryPoint: EconEntryPoint
}

struct ProPaywallSession: Identifiable {
    let id = UUID()
    let entryPoint: EconEntryPoint
}

struct CourseSession: Identifiable {
    let id = UUID()
    let course: Course
    var initialLesson: Lesson? = nil
}

// MARK: Router

@MainActor
final class AppRouter: ObservableObject {
    @Published var selectedTab: EconTab
    @Published var cardModeSession: CardModeSession?
    @Published var paywallSession: PaywallSession?
    @Published var proPaywallSession: ProPaywallSession?
    @Published var courseSession: CourseSession?
    @Published var showSettings = false
    @Published var showBookmarks = false

    /// Set by a sheet that wants a paywall; presented once that sheet is gone.
    var pendingPaywallAfterSettings = false
    var pendingProPaywall: EconEntryPoint?

    /// DEBUG-only: `-econInitialTab browse|news|pro` opens on that tab (UI
    /// tests and screenshot runs). Release always opens on Home.
    init() {
        var tab = EconTab.home
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-econInitialTab"), i + 1 < args.count,
           let requested = EconTab(rawValue: args[i + 1]) {
            tab = requested
        }
        #endif
        selectedTab = tab
    }

    func presentPaywall(_ entryPoint: EconEntryPoint) {
        paywallSession = PaywallSession(entryPoint: entryPoint)
    }

    func presentProPaywall(_ entryPoint: EconEntryPoint) {
        proPaywallSession = ProPaywallSession(entryPoint: entryPoint)
    }

    func openCourse(_ course: Course, at lesson: Lesson? = nil) {
        courseSession = CourseSession(course: course, initialLesson: lesson)
    }

    func presentPendingProPaywall() {
        guard let entryPoint = pendingProPaywall else { return }
        pendingProPaywall = nil
        proPaywallSession = ProPaywallSession(entryPoint: entryPoint)
    }

    func startCards(_ cards: [EconCard], title: String, mode: EBMode, entryPoint: EBEntryPoint) {
        cardModeSession = CardModeSession(cards: cards, title: title, mode: mode, entryPoint: entryPoint)
    }

    /// Content ids of the packs this reader may read: owned outright or
    /// included by an active Pro subscription (D19). Unlock All is not
    /// consulted (D18).
    static func ownedPackIDs(content: ContentStore, store: PurchaseManager) -> Set<String> {
        Set(content.packs.filter { store.hasAccess(packProductID: $0.productID) }.map(\.id))
    }

    /// A core topic: the Unlock All paywall when locked, else its deck.
    /// `leadingCard` (from search) is moved to the front of the deck.
    func openCoreTopic(_ topic: EconTopic, content: ContentStore, store: PurchaseManager,
                       leadingCard: EconCard? = nil) {
        let locked = !content.isTopicFree(topic.id) && !store.coreTopicsUnlocked
        if locked {
            // `topic_id` is a prohibited telemetry property; the entry point
            // and the access state carry the funnel.
            EBEvents.lockedTopicTapped(entryPoint: .topicGrid)
            presentPaywall(.topicGrid)
            return
        }
        EBEvents.topicOpened(entryPoint: .topicGrid,
                             accessState: content.accessState(for: topic.id,
                                                              unlockedAll: store.coreTopicsUnlocked))
        startCards(Self.deck(content.cards(for: topic.id, unlockedAll: store.coreTopicsUnlocked),
                             leading: leadingCard),
                   title: topic.name, mode: .topic, entryPoint: .topicGrid)
    }

    /// A readable pack topic (callers check access; a locked pack is bought
    /// from its offer card, never opened).
    func openPackTopic(_ topic: EconTopic, content: ContentStore, store: PurchaseManager,
                       entryPoint: EBEntryPoint, leadingCard: EconCard? = nil) {
        let owned = Self.ownedPackIDs(content: content, store: store)
        EBEvents.topicOpened(entryPoint: entryPoint,
                             accessState: content.accessState(for: topic.id,
                                                              unlockedAll: store.coreTopicsUnlocked,
                                                              ownedPackIDs: owned))
        startCards(Self.deck(content.cards(for: topic.id, unlockedAll: store.coreTopicsUnlocked,
                                           ownedPackIDs: owned),
                             leading: leadingCard),
                   title: topic.name, mode: .topic, entryPoint: entryPoint)
    }

    private static func deck(_ cards: [EconCard], leading: EconCard?) -> [EconCard] {
        guard let leading, let index = cards.firstIndex(of: leading) else { return cards }
        var deck = cards
        deck.remove(at: index)
        deck.insert(leading, at: 0)
        return deck
    }
}

// MARK: Top bar

/// The shared top bar: wordmark fixed top-left, gear top-right.
struct EconHeaderBar: View {
    /// Shows the hairline once content has scrolled under the bar.
    var showsDivider: Bool
    let onSettings: () -> Void

    static let wordmarkSize: CGFloat = 28

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            EconWordmark(fontSize: Self.wordmarkSize)
                .accessibilityIdentifier("econWordmark")
            Spacer(minLength: EconSpace.s)
            EconIconButton(systemImage: "gearshape", label: "Settings", action: onSettings)
                .accessibilityIdentifier("settingsGearButton")
        }
        .padding(.leading, EconSpace.gutter)
        .padding(.trailing, EconSpace.xs)
        .padding(.top, EconSpace.xxs)
        .padding(.bottom, 2)
        .background(EconColor.background)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(EconColor.divider)
                .frame(height: 1 / UIScreen.main.scale)
                .opacity(showsDivider ? 1 : 0)
                .accessibilityHidden(true)
        }
    }
}

private struct EconScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// A tab's page: the fixed top bar above a vertical scroll view. The bar is
/// not part of the scrolling content, so it cannot move or resize.
struct EconTabScaffold<Content: View>: View {
    let scrollSpace: String
    var onRefresh: (() async -> Void)? = nil
    @ViewBuilder let content: (ScrollViewProxy) -> Content

    @EnvironmentObject private var router: AppRouter
    @State private var scrolled = false

    var body: some View {
        VStack(spacing: 0) {
            EconHeaderBar(showsDivider: scrolled, onSettings: { router.showSettings = true })
                .zIndex(1)
            ScrollViewReader { proxy in
                scrollView(proxy)
            }
        }
        .background(EconColor.background.ignoresSafeArea())
    }

    @ViewBuilder
    private func scrollView(_ proxy: ScrollViewProxy) -> some View {
        let scroll = ScrollView {
            VStack(spacing: 0) {
                GeometryReader { geo in
                    Color.clear.preference(key: EconScrollOffsetKey.self,
                                           value: geo.frame(in: .named(scrollSpace)).minY)
                }
                .frame(height: 0)
                content(proxy)
            }
        }
        .coordinateSpace(name: scrollSpace)
        // Browse's search keyboard must never strand the tab bar behind it.
        .scrollDismissesKeyboard(.immediately)
        .onPreferenceChange(EconScrollOffsetKey.self) { minY in
            let isScrolled = minY < -1
            if isScrolled != scrolled {
                withAnimation(.easeOut(duration: 0.15)) { scrolled = isScrolled }
            }
        }
        if let onRefresh {
            scroll.refreshable { await onRefresh() }
        } else {
            scroll
        }
    }
}

// MARK: Root

struct RootTabView: View {
    @EnvironmentObject private var content: ContentStore
    @EnvironmentObject private var streak: StreakManager
    @EnvironmentObject private var store: PurchaseManager
    @EnvironmentObject private var growth: EconGrowth

    @StateObject private var router = AppRouter()
    @StateObject private var courseProgress = CourseProgressStore.shared
    @StateObject private var briefs = BriefStore.shared

    init() {
        Self.configureTabBarAppearance()
    }

    var body: some View {
        TabView(selection: $router.selectedTab) {
            HomeTabView()
                .tabItem { Label(EconTab.home.title, systemImage: EconTab.home.systemImage) }
                .tag(EconTab.home)
            BrowseTabView()
                .tabItem { Label(EconTab.browse.title, systemImage: EconTab.browse.systemImage) }
                .tag(EconTab.browse)
            NewsTabView()
                .tabItem { Label(EconTab.news.title, systemImage: EconTab.news.systemImage) }
                .tag(EconTab.news)
            ProTabView()
                .tabItem { Label(EconTab.pro.title, systemImage: EconTab.pro.systemImage) }
                .tag(EconTab.pro)
        }
        .environmentObject(router)
        .environmentObject(courseProgress)
        .environmentObject(briefs)
        .tint(EconColor.accent)
        .sheet(isPresented: $router.showSettings) {
            SettingsView(onRequestPaywall: { router.pendingPaywallAfterSettings = true },
                         onRequestProPaywall: { router.pendingProPaywall = .settings })
                .environmentObject(streak)
                .environmentObject(store)
                .environmentObject(growth)
                .environmentObject(content)
        }
        .onChange(of: router.showSettings) { showing in
            guard !showing else { return }
            if router.pendingPaywallAfterSettings {
                router.pendingPaywallAfterSettings = false
                router.presentPaywall(.settings)
            }
            router.presentPendingProPaywall()
        }
        .sheet(item: $router.courseSession) { session in
            CourseView(course: session.course,
                       initialLesson: session.initialLesson,
                       onProPaywall: {
                           router.pendingProPaywall = .course
                           router.courseSession = nil
                       })
                .environmentObject(store)
                .environmentObject(courseProgress)
        }
        .onChange(of: router.courseSession?.id) { id in
            if id == nil { router.presentPendingProPaywall() }
        }
        .sheet(isPresented: $router.showBookmarks) {
            BookmarksView()
                .environmentObject(content)
                .environmentObject(streak)
                .environmentObject(growth)
        }
        .fullScreenCover(item: $router.proPaywallSession) { session in
            ProPaywallView(entryPoint: session.entryPoint)
                .environmentObject(store)
                .environmentObject(growth)
        }
        .fullScreenCover(item: $router.cardModeSession) { session in
            CardModeView(cards: session.cards, title: session.title,
                         mode: session.mode, entryPoint: session.entryPoint)
                .environmentObject(content)
                .environmentObject(streak)
                .environmentObject(store)
                .environmentObject(growth)
        }
        .fullScreenCover(item: $router.paywallSession) { session in
            PaywallView(entryPoint: session.entryPoint)
                .environmentObject(store)
                .environmentObject(growth)
        }
    }

    private static func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(EconColor.background)
        appearance.shadowColor = UIColor(EconColor.divider)
        let normal = UIColor(EconColor.textTertiary)
        let selected = UIColor(EconColor.accent)
        for item in [appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance,
                     appearance.compactInlineLayoutAppearance] {
            item.normal.iconColor = normal
            item.normal.titleTextAttributes = [.foregroundColor: normal]
            item.selected.iconColor = selected
            item.selected.titleTextAttributes = [.foregroundColor: selected]
        }
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}
