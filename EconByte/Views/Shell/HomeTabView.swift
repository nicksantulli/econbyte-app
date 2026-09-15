import SwiftUI

/// Home = today (1.1.4 shell): today's set, the streak, today's brief, the
/// course to continue (or a course teaser), and one featured pack. Everything
/// else moved to Browse (topics, packs, bookmarks), News (the brief) and Pro.
struct HomeTabView: View {
    @EnvironmentObject private var content: ContentStore
    @EnvironmentObject private var streak: StreakManager
    @EnvironmentObject private var store: PurchaseManager
    @EnvironmentObject private var growth: EconGrowth
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var progress: CourseProgressStore
    @EnvironmentObject private var briefs: BriefStore

    private let dailyGoal = 3

    private var ownedPackIDs: Set<String> { AppRouter.ownedPackIDs(content: content, store: store) }

    var body: some View {
        EconTabScaffold(scrollSpace: "home") { _ in
            VStack(alignment: .leading, spacing: 22) {
                todaysSetCard
                streakRow
                briefCard
                courseCard
                featuredPackSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        // Anchored adaptive banner (1.1.3), above the tab bar. Reserves no
        // space until an ad has loaded, and is not constructed at all for a
        // Remove Ads owner or Pro subscriber, an EEA/UK reader, or before the
        // ATT decision (`EconMonetization.canRequestAds`).
        .safeAreaInset(edge: .bottom, spacing: 0) {
            AdBannerSlot(surface: .home, monetization: growth.monetization)
        }
    }

    // MARK: Today's set

    private func startTodaysSet(_ daily: [EconCard], from entryPoint: EBEntryPoint) {
        router.startCards(daily, title: "Today's Set", mode: .daily, entryPoint: entryPoint)
    }

    /// Test-only hook: exposes card `inf-001`'s full example as the grocery
    /// line's accessibility value so a UI test can prove the visible line is a
    /// verbatim slice of the card (never an invented figure). Off in production.
    private var exposeGroceryBinding: Bool {
        ProcessInfo.processInfo.arguments.contains("-exposeGroceryBinding")
    }

    /// One sourced line under TODAY'S CARDS (the 1.1.1 hotfix, carried
    /// forward): a verbatim slice of bundled card `inf-001`. Tapping it starts
    /// today's set, exactly like Start/Review.
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
                        // Two lines is the attribution's budget; the full
                        // source is on the card itself (M-5).
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
        let daily = content.dailySet(count: 8, unlockedAll: store.coreTopicsUnlocked,
                                     ownedPackIDs: ownedPackIDs)
        let seen = daily.filter { content.cardStates[$0.id]?.lastSeen != nil }.count
        let completed = streak.didReachDailyGoalToday
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: completed ? "checkmark.seal.fill" : "rectangle.stack.fill")
                    .foregroundColor(completed ? Econ.sky : Econ.amber)
                    .font(.title3)
                    .accessibilityHidden(true)
                EconSectionLabel(text: "Today's cards")
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
        .accessibilityElement(children: .combine)
    }

    // MARK: Today's brief

    @ViewBuilder
    private var briefCard: some View {
        if let brief = briefs.latest {
            Button { router.selectedTab = .news } label: {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "newspaper.fill")
                            .foregroundColor(Econ.amber)
                            .accessibilityHidden(true)
                        EconSectionLabel(text: "Today's brief")
                        Spacer()
                        if briefs.showsSampleBadge(brief) { BriefSampleBadge() }
                    }
                    Text(BriefDates.long(brief.briefDate))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Econ.subtext)
                    Text(brief.headline)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(Econ.white)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                    if let item = brief.teaserItem, let figure = item.figures?.first {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(figure.value)
                                .font(.system(size: 20, weight: .heavy, design: .rounded))
                                .foregroundColor(Econ.amberLight)
                            Text(figure.label)
                                .font(.system(size: 12, design: .rounded))
                                .foregroundColor(Econ.subtext)
                                .lineLimit(2)
                        }
                    }
                    HStack(spacing: 4) {
                        Text("Read the brief")
                        Image(systemName: "arrow.right").accessibilityHidden(true)
                    }
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(Econ.sky)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Econ.tide.opacity(0.13))
                .cornerRadius(16)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("homeBriefCard")
        }
    }

    // MARK: Courses

    /// The course to surface: one in progress, else the first not finished,
    /// else the first.
    private func featuredCourse(_ courses: [Course]) -> (course: Course, next: Lesson?, done: Int) {
        let inProgress = courses.first {
            let done = progress.completedCount(of: $0)
            return done > 0 && done < $0.lessons.count
        }
        let unfinished = courses.first { progress.completedCount(of: $0) < $0.lessons.count }
        let course = inProgress ?? unfinished ?? courses[0]
        return (course, progress.nextLesson(in: course), progress.completedCount(of: course))
    }

    @ViewBuilder
    private var courseCard: some View {
        if let courses = content.courses?.courses, !courses.isEmpty {
            let pick = featuredCourse(courses)
            let isPro = store.isProActive
            let total = pick.course.lessons.count
            Button {
                router.openCourse(pick.course, at: isPro ? pick.next : nil)
            } label: {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "graduationcap.fill")
                            .foregroundColor(Econ.amber)
                            .accessibilityHidden(true)
                        EconSectionLabel(text: isPro
                                         ? (pick.done > 0 ? "Continue your course" : "Start a course")
                                         : "Courses")
                        Spacer()
                        if !isPro {
                            Text("First lesson free")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(Econ.ink)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Econ.amber)
                                .cornerRadius(5)
                        }
                    }
                    HStack(spacing: 14) {
                        CourseProgressRing(done: pick.done, total: total, icon: pick.course.icon)
                            .frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(pick.course.title)
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundColor(Econ.white)
                                .multilineTextAlignment(.leading)
                            Text(isPro
                                 ? (pick.next.map { "Next: \($0.title)" } ?? "Course complete ✓")
                                 : "\(total) lessons with charts and quizzes")
                                .font(.system(size: 13, design: .rounded))
                                .foregroundColor(Econ.subtext)
                                .multilineTextAlignment(.leading)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .foregroundColor(Econ.subtext)
                            .accessibilityHidden(true)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Econ.tide.opacity(0.13))
                .cornerRadius(16)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("homeCourseCard")
        }
    }

    // MARK: Featured pack

    /// One pack a day, from the packs this reader cannot read yet — preferring
    /// those the App Store has priced, so Home never features a disabled offer
    /// while a buyable one exists (every pack, once all are readable).
    private var featuredPack: EconPack? {
        let locked = content.packs.filter { !store.hasAccess(packProductID: $0.productID) }
        let priced = locked.filter { pack in
            PurchaseManager.ProductID(rawValue: pack.productID).flatMap { store.offer(for: $0) } != nil
        }
        let pool = !priced.isEmpty ? priced : (locked.isEmpty ? content.packs : locked)
        guard !pool.isEmpty else { return nil }
        let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
        return pool[day % pool.count]
    }

    @ViewBuilder
    private var featuredPackSection: some View {
        if let pack = featuredPack {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    EconSectionLabel(text: "Featured pack")
                    Spacer()
                    Button("All packs") { router.selectedTab = .browse }
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(Econ.sky)
                        .accessibilityIdentifier("homeAllPacksButton")
                }
                PackOfferView(pack: pack, entryPoint: .home) { topic in
                    router.openPackTopic(topic, content: content, store: store, entryPoint: .home)
                }
            }
        }
    }
}

/// Progress ring with the course icon in the middle.
struct CourseProgressRing: View {
    let done: Int
    let total: Int
    let icon: String

    var body: some View {
        ZStack {
            Circle().stroke(Econ.tide.opacity(0.4), lineWidth: 3)
            Circle()
                .trim(from: 0, to: total == 0 ? 0 : CGFloat(done) / CGFloat(total))
                .stroke(Econ.sky, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Econ.amber)
        }
        .accessibilityHidden(true)
    }
}
