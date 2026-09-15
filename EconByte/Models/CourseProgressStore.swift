import Foundation

/// Per-lesson progress for the Pro courses (1.1.4), persisted locally.
///
/// A lesson is complete when the reader reaches its takeaways; its one quiz
/// records whether the first answer was right. Both live in UserDefaults keyed
/// on `lessonID`, so — exactly like card bookmarks — a lesson id must never be
/// reused for different content. Nothing here leaves the device: the only
/// emission is the bucketed `course_lesson_completed_v1`, once per lesson.
@MainActor
final class CourseProgressStore: ObservableObject {

    static let shared = CourseProgressStore()

    struct LessonProgress: Codable, Equatable {
        var completedAt: Date?
        /// `nil` until the quiz has been answered once.
        var quizCorrect: Bool?
    }

    static let defaultsKey = "econ.courses.progress"

    @Published private(set) var progress: [String: LessonProgress] = [:]

    private let defaults: UserDefaults
    private let now: () -> Date

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
        if let data = defaults.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode([String: LessonProgress].self, from: data) {
            progress = decoded
        }
    }

    func isCompleted(_ lessonID: String) -> Bool {
        progress[lessonID]?.completedAt != nil
    }

    func quizResult(_ lessonID: String) -> Bool? {
        progress[lessonID]?.quizCorrect
    }

    /// Records the first answer to a lesson's quiz. A later retry does not
    /// overwrite it — the reader can re-take the quiz, the record is of the
    /// first attempt.
    func recordQuiz(lessonID: String, correct: Bool) {
        var entry = progress[lessonID] ?? LessonProgress()
        guard entry.quizCorrect == nil else { return }
        entry.quizCorrect = correct
        progress[lessonID] = entry
        save()
    }

    /// Marks a lesson complete. Emits `course_lesson_completed_v1` only on the
    /// first completion, with the quiz result as answered so far (false if the
    /// reader skipped it).
    func markCompleted(lessonID: String, courseID: String) {
        var entry = progress[lessonID] ?? LessonProgress()
        guard entry.completedAt == nil else { return }
        entry.completedAt = now()
        progress[lessonID] = entry
        save()
        if let family = EBCourseFamily(courseID: courseID) {
            EBEvents.courseLessonCompleted(family: family, quizCorrect: entry.quizCorrect ?? false)
        }
    }

    /// Fraction of a course's lessons completed, 0…1.
    func completion(of course: Course) -> Double {
        guard !course.lessons.isEmpty else { return 0 }
        let done = course.lessons.filter { isCompleted($0.lessonID) }.count
        return Double(done) / Double(course.lessons.count)
    }

    func completedCount(of course: Course) -> Int {
        course.lessons.filter { isCompleted($0.lessonID) }.count
    }

    /// The first lesson not yet completed, or the last lesson when all are.
    func nextLesson(in course: Course) -> Lesson? {
        course.lessons.first { !isCompleted($0.lessonID) } ?? course.lessons.last
    }

    private func save() {
        if let data = try? JSONEncoder().encode(progress) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }

    #if DEBUG
    static func resetPersistedState(in defaults: UserDefaults) {
        defaults.removeObject(forKey: defaultsKey)
    }
    #endif
}
