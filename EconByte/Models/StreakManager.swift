import Foundation

@MainActor
final class StreakManager: ObservableObject {
    static let shared = StreakManager()

    @Published private(set) var currentStreak: Int = 0
    @Published private(set) var cardsTodayCount: Int = 0
    private let streakKey = "currentStreak"
    private let lastDateKey = "lastStreakDate"
    private let todayCountKey = "cardsTodayCount"
    private let todayDateKey = "cardsTodayDate"
    let dailyGoal = 3

    /// True once the user has met today's card goal — the same signal that
    /// drives the "Today's goal reached ✓" copy. The home "TODAY'S CARDS" CTA
    /// reads this so it reflects completion instead of always saying "Start".
    var didReachDailyGoalToday: Bool { cardsTodayCount >= dailyGoal }

    private init() { load() }

    private func load() {
        currentStreak = UserDefaults.standard.integer(forKey: streakKey)
        let todayDate = calendar.startOfDay(for: Date())
        let savedDate = UserDefaults.standard.object(forKey: todayDateKey) as? Date
        if let saved = savedDate, calendar.isDate(saved, inSameDayAs: todayDate) {
            cardsTodayCount = UserDefaults.standard.integer(forKey: todayCountKey)
        } else {
            cardsTodayCount = 0
            checkStreakReset()
        }
    }

    private var calendar: Calendar { Calendar.current }

    private func checkStreakReset() {
        guard let lastStr = UserDefaults.standard.string(forKey: lastDateKey),
              let lastDate = ISO8601DateFormatter().date(from: lastStr) else { return }
        let daysSince = calendar.dateComponents([.day], from: calendar.startOfDay(for: lastDate),
                                                to: calendar.startOfDay(for: Date())).day ?? 0
        if daysSince >= 2 {
            currentStreak = 0
            UserDefaults.standard.set(0, forKey: streakKey)
        }
    }

    func noteCardSeen() {
        let today = calendar.startOfDay(for: Date())
        let savedDate = UserDefaults.standard.object(forKey: todayDateKey) as? Date
        if savedDate == nil || !calendar.isDate(savedDate!, inSameDayAs: today) {
            cardsTodayCount = 0
            UserDefaults.standard.set(today, forKey: todayDateKey)
        }
        cardsTodayCount += 1
        UserDefaults.standard.set(cardsTodayCount, forKey: todayCountKey)
        if cardsTodayCount == dailyGoal {
            creditStreakDay()
        }
    }

    private func creditStreakDay() {
        currentStreak += 1
        UserDefaults.standard.set(currentStreak, forKey: streakKey)
        let iso = ISO8601DateFormatter().string(from: Date())
        UserDefaults.standard.set(iso, forKey: lastDateKey)
        // Bucketed streak length only — never the exact day count, never a date.
        EBEvents.streakDayCredited(streak: currentStreak)
    }

    // Notification authorization and scheduling moved to `NotificationPolicy` /
    // `NotificationCoordinator` in version 1.1. The 1.0 reminder here read
    // "Your streak is at risk" and prompted for authorization without an opt-in;
    // both are prohibited by design section 11.1 (CONTENT-DECISIONS.md D8).
}
