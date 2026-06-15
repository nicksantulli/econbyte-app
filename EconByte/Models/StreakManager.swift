import Foundation
import UserNotifications

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
    }

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            if granted {
                Task { @MainActor in StreakManager.shared.scheduleStreakReminder() }
            }
        }
    }

    func scheduleStreakReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["streak-reminder"])
        var components = DateComponents()
        components.hour = 19
        components.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let content = UNMutableNotificationContent()
        content.title = "EconByte"
        content.body = "Your streak is at risk 🔥 · 3 cards = 90 seconds."
        content.sound = .default
        let request = UNNotificationRequest(identifier: "streak-reminder", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}
