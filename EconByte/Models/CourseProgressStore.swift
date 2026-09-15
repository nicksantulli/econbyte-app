import Foundation

/// Per-lesson progress for the Pro courses, persisted locally.
///
/// 1.1.4 stored, per `lessonID`, when the lesson was completed and whether the
/// first answer to its one quiz was right. 1.1.5 story lessons add where the
/// reader is (`lastBeat`, the story page to resume at) and the first answer to
/// each quick check (`checks`, keyed by the check's order in the lesson). The
/// new fields are optional, so a 1.1.4 record decodes unchanged: completion and
/// the quiz answer carry over, and the quiz answer IS the first check's answer
/// (`quizCorrect` is kept in step with check 0 in both directions).
///
/// The one-time migration (`econ.courses.progress.version` 1 → 2) keeps every
/// record and only drops a resume position the lesson can no longer reach.
/// Nothing here leaves the device: the only emission is the bucketed
/// `course_lesson_completed_v1`, once per lesson.
@MainActor
final class CourseProgressStore: ObservableObject {

    static let shared = CourseProgressStore(
        pageCounts: ContentStore.shared.courses.map(CourseProgressStore.pageCounts(in:)))

    struct LessonProgress: Codable, Equatable {
        var completedAt: Date?
        /// `nil` until the first check has been answered once (1.1.4: the quiz).
        var quizCorrect: Bool?
        /// The story page to resume at (0 = the cover); `nil` once complete.
        var lastBeat: Int?
        /// First answers to the lesson's checks, by check ordinal ("0", "1").
        var checks: [String: Bool]?
    }

    static let defaultsKey = "econ.courses.progress"
    static let versionKey = "econ.courses.progress.version"
    static let currentVersion = 2

    @Published private(set) var progress: [String: LessonProgress] = [:]

    private let defaults: UserDefaults
    private let now: () -> Date

    /// `pageCounts` (lessonID → story pages, cover included) lets the
    /// migration clamp stored positions; `nil` skips clamping.
    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init,
         pageCounts: [String: Int]? = nil) {
        self.defaults = defaults
        self.now = now
        if let data = defaults.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode([String: LessonProgress].self, from: data) {
            progress = decoded
        }
        migrateIfNeeded(pageCounts: pageCounts)
    }

    static func pageCounts(in catalog: CourseCurriculum) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: catalog.allLessons.map { ($0.lessonID, $0.pageCount) })
    }

    // MARK: Migration

    /// Pure: what a stored progress map becomes under the story schema.
    static func migrated(_ stored: [String: LessonProgress], pageCounts: [String: Int]?) -> [String: LessonProgress] {
        var result = stored
        for (lessonID, var entry) in stored {
            if entry.completedAt != nil { entry.lastBeat = nil }
            if let beat = entry.lastBeat {
                let limit = pageCounts?[lessonID] ?? Int.max
                if beat < 0 || beat >= limit { entry.lastBeat = nil }
            }
            if let first = entry.quizCorrect, entry.checks?["0"] == nil {
                entry.checks = (entry.checks ?? [:]).merging(["0": first]) { current, _ in current }
            }
            result[lessonID] = entry
        }
        return result
    }

    private func migrateIfNeeded(pageCounts: [String: Int]?) {
        let version = defaults.integer(forKey: Self.versionKey)
        let next = Self.migrated(progress, pageCounts: pageCounts)
        if next != progress {
            progress = next
            save()
        }
        if version < Self.currentVersion {
            defaults.set(Self.currentVersion, forKey: Self.versionKey)
        }
    }

    // MARK: Completion

    func isCompleted(_ lessonID: String) -> Bool {
        progress[lessonID]?.completedAt != nil
    }

    /// Marks a lesson complete. Emits `course_lesson_completed_v1` only on the
    /// first completion, with the first check's result so far (false if the
    /// reader skipped it).
    func markCompleted(lessonID: String, courseID: String) {
        var entry = progress[lessonID] ?? LessonProgress()
        guard entry.completedAt == nil else { return }
        entry.completedAt = now()
        entry.lastBeat = nil
        progress[lessonID] = entry
        save()
        if let family = EBCourseFamily(courseID: courseID) {
            EBEvents.courseLessonCompleted(family: family, quizCorrect: entry.quizCorrect ?? false)
        }
    }

    /// Fraction of a course's lessons completed, 0…1.
    func completion(of course: Course) -> Double {
        guard !course.lessons.isEmpty else { return 0 }
        return Double(completedCount(of: course)) / Double(course.lessons.count)
    }

    func completedCount(of course: Course) -> Int {
        course.lessons.filter { isCompleted($0.lessonID) }.count
    }

    /// The first lesson not yet completed, or the last lesson when all are.
    func nextLesson(in course: Course) -> Lesson? {
        course.lessons.first { !isCompleted($0.lessonID) } ?? course.lessons.last
    }

    // MARK: Resume

    /// The page a lesson opens at: where the reader left off, or the cover for
    /// a new or completed lesson.
    func resumePage(for lesson: Lesson) -> Int {
        guard !isCompleted(lesson.lessonID), let beat = progress[lesson.lessonID]?.lastBeat,
              (0..<lesson.pageCount).contains(beat) else { return 0 }
        return beat
    }

    /// Records the page on screen. A completed lesson keeps no position (it is
    /// re-read from the cover).
    func recordPage(_ page: Int, lessonID: String) {
        guard !isCompleted(lessonID), page >= 0 else { return }
        var entry = progress[lessonID] ?? LessonProgress()
        guard entry.lastBeat != page else { return }
        entry.lastBeat = page
        progress[lessonID] = entry
        save()
    }

    // MARK: Checks

    /// The first answer to check `ordinal`, or `nil` if unanswered. A 1.1.4
    /// quiz answer is check 0's answer.
    func checkResult(lessonID: String, ordinal: Int) -> Bool? {
        guard let entry = progress[lessonID] else { return nil }
        return entry.checks?[String(ordinal)] ?? (ordinal == 0 ? entry.quizCorrect : nil)
    }

    /// Records the first answer to a check. A retry does not overwrite it — the
    /// reader can try other choices, the record is of the first attempt.
    func recordCheck(lessonID: String, ordinal: Int, correct: Bool) {
        guard checkResult(lessonID: lessonID, ordinal: ordinal) == nil else { return }
        var entry = progress[lessonID] ?? LessonProgress()
        entry.checks = (entry.checks ?? [:]).merging([String(ordinal): correct]) { current, _ in current }
        if ordinal == 0 { entry.quizCorrect = correct }
        progress[lessonID] = entry
        save()
    }

    /// 1.1.4 API: the lesson's (first) quiz.
    func quizResult(_ lessonID: String) -> Bool? {
        checkResult(lessonID: lessonID, ordinal: 0)
    }

    func recordQuiz(lessonID: String, correct: Bool) {
        recordCheck(lessonID: lessonID, ordinal: 0, correct: correct)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(progress) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }

    #if DEBUG
    static func resetPersistedState(in defaults: UserDefaults) {
        defaults.removeObject(forKey: defaultsKey)
        defaults.removeObject(forKey: versionKey)
    }
    #endif
}
