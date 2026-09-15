import SwiftUI

/// A course's lesson list with progress. Presented in its own
/// `NavigationStack` from Home and the Pro tab; a lesson opens full screen as a
/// story (1.1.5) and "Next lesson" swaps the next story in place.
///
/// Phase 24: the navigation bar carries the course title, so the header card no
/// longer repeats it; the card holds the course facts, progress and one primary
/// action that resumes (or starts) the right lesson.
struct CourseView: View {
    let course: Course
    var initialLesson: Lesson? = nil
    var onProPaywall: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: PurchaseManager
    @EnvironmentObject private var progress: CourseProgressStore
    @State private var story: StorySession?
    @State private var didOpenInitial = false

    private struct StorySession: Identifiable {
        let id = UUID()
        let lesson: Lesson
    }

    var body: some View {
        NavigationStack {
            ZStack {
                EconColor.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: EconSpace.section) {
                        header
                        lessonList
                    }
                    .padding(.horizontal, EconSpace.gutter)
                    .padding(.top, EconSpace.xs)
                    .padding(.bottom, EconSpace.xxl)
                }
            }
            .navigationTitle(course.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") { dismiss() }
                        .foregroundColor(EconColor.interactive)
                        .accessibilityIdentifier("courseCloseButton")
                }
            }
        }
        .tint(EconColor.interactive)
        .fullScreenCover(item: $story) { session in
            StoryLessonHost(course: course, startLesson: session.lesson,
                            onProPaywall: {
                                story = nil
                                onProPaywall?()
                            },
                            onClose: { story = nil })
                .environmentObject(store)
                .environmentObject(progress)
        }
        .onAppear {
            guard !didOpenInitial else { return }
            didOpenInitial = true
            if let initialLesson { story = StorySession(lesson: initialLesson) }
        }
        .accessibilityIdentifier("course-\(course.courseID)")
    }

    // MARK: Header

    private enum PrimaryAction {
        case open(Lesson, title: String)
        case pro
    }

    /// The one thing to do next: resume a lesson in progress, else start the
    /// first unfinished lesson the reader can open, else offer Pro.
    private var primaryAction: PrimaryAction {
        let readable = course.lessons.filter { $0.isPreview || store.isProActive }
        if let inProgress = readable.first(where: { progress.resumePage(for: $0) > 0 }) {
            return .open(inProgress, title: "Continue")
        }
        if let next = readable.first(where: { !progress.isCompleted($0.lessonID) }) {
            let started = course.lessons.contains { progress.isCompleted($0.lessonID) }
            return .open(next, title: next.isPreview && !store.isProActive ? "Start free lesson" : (started ? "Next lesson" : "Start"))
        }
        if !store.isProActive { return .pro }
        return .open(course.lessons[0], title: "Read again")
    }

    private var header: some View {
        let done = progress.completedCount(of: course)
        let total = course.lessons.count
        return VStack(alignment: .leading, spacing: EconSpace.m) {
            EconAdaptiveRow(spacing: EconSpace.s) {
                CourseProgressRing(done: done, total: total, icon: course.icon)
                    .frame(width: EconSize.tapTarget + EconSpace.xs, height: EconSize.tapTarget + EconSpace.xs)
                VStack(alignment: .leading, spacing: EconSpace.xxs) {
                    Text("\(done) of \(total) lessons")
                        .font(EconType.headline)
                        .foregroundColor(done == total ? EconColor.interactive : EconColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(course.estimatedMinutes) min · \(course.level == .intro ? "Intro" : "Intermediate")")
                        .font(EconType.caption)
                        .foregroundColor(EconColor.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("courseProgress")

            switch primaryAction {
            case let .open(lesson, title):
                Button {
                    story = StorySession(lesson: lesson)
                } label: {
                    VStack(spacing: 2) {
                        Text(title)
                        Text(lesson.title)
                            .font(EconType.caption)
                            .lineLimit(2)
                    }
                }
                .buttonStyle(PrimaryButton())
                .accessibilityLabel(Text("\(title): \(lesson.title)"))
                .accessibilityIdentifier("courseContinueButton")
            case .pro:
                Button("See EconByte Pro") { onProPaywall?() }
                    .buttonStyle(PrimaryButton())
                    .accessibilityIdentifier("courseContinueButton")
            }
        }
        .econCard()
    }

    // MARK: Lessons

    private var lessonList: some View {
        VStack(alignment: .leading, spacing: EconSpace.xs) {
            EconSectionLabel(text: "Lessons")
            ForEach(Array(course.lessons.enumerated()), id: \.element.lessonID) { index, lesson in
                let accessible = lesson.isPreview || store.isProActive
                let completed = progress.isCompleted(lesson.lessonID)
                let resume = progress.resumePage(for: lesson)
                Button {
                    if accessible { story = StorySession(lesson: lesson) } else { onProPaywall?() }
                } label: {
                    HStack(spacing: EconSpace.s) {
                        ZStack {
                            Circle()
                                .fill(completed ? EconColor.interactive : EconColor.surfaceRaised)
                            if completed {
                                Image(systemName: "checkmark")
                                    .font(EconType.footnote.weight(.bold))
                                    .foregroundColor(EconColor.onAccent)
                            } else {
                                Text("\(index + 1)")
                                    .font(EconType.footnote.weight(.bold))
                                    .foregroundColor(EconColor.textPrimary)
                            }
                            if resume > 0 {
                                Circle()
                                    .trim(from: 0, to: CGFloat(resume) / CGFloat(max(lesson.pageCount - 1, 1)))
                                    .stroke(EconColor.interactive, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                            }
                        }
                        .frame(width: 32, height: 32)
                        .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: EconSpace.xxs) {
                            Text(lesson.title)
                                .font(EconType.subheadlineEmphasis)
                                .foregroundColor(accessible ? EconColor.textPrimary : EconColor.textSecondary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: EconSpace.xs) {
                                Text("\(lesson.estimatedMinutes) min")
                                    .font(EconType.caption)
                                    .foregroundColor(EconColor.textTertiary)
                                if resume > 0 {
                                    Text("In progress")
                                        .font(EconType.caption)
                                        .foregroundColor(EconColor.interactive)
                                }
                                if lesson.isPreview && !store.isProActive {
                                    EconBadge(text: "Free")
                                }
                            }
                        }
                        Spacer(minLength: EconSpace.xs)
                        Image(systemName: accessible ? "chevron.right" : "lock.fill")
                            .font(EconType.footnote.weight(.semibold))
                            .foregroundColor(accessible ? EconColor.textTertiary : EconColor.accent)
                            .accessibilityHidden(true)
                    }
                    .econRow(fill: accessible ? EconColor.surface : EconColor.surface.opacity(0.5))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("lessonRow-\(lesson.lessonID)")
                .accessibilityValue(Text(rowValue(accessible: accessible, completed: completed, resume: resume, lesson: lesson)))
            }
        }
    }

    private func rowValue(accessible: Bool, completed: Bool, resume: Int, lesson: Lesson) -> String {
        guard accessible else { return "locked, requires EconByte Pro" }
        if completed { return "completed" }
        if resume > 0 { return "in progress, page \(resume + 1) of \(lesson.pageCount)" }
        return lesson.isPreview && !store.isProActive ? "free" : ""
    }
}

/// Holds the lesson on screen so "Next lesson" replaces the story in place
/// instead of dismissing and re-presenting the cover.
struct StoryLessonHost: View {
    let course: Course
    let startLesson: Lesson
    var onProPaywall: (() -> Void)?
    var onClose: () -> Void

    @State private var lesson: Lesson?

    var body: some View {
        let current = lesson ?? startLesson
        LessonView(course: course, lesson: current,
                   onProPaywall: onProPaywall,
                   onNextLesson: { next in lesson = next },
                   onClose: onClose)
            .id(current.lessonID)
    }
}
