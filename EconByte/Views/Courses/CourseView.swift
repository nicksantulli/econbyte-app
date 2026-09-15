import SwiftUI

/// A course's lesson list with progress. Presented in its own
/// `NavigationStack` from Home and the Pro tab; a lesson opens full screen as a
/// story (1.1.5) and "Next lesson" swaps the next story in place.
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

    private var header: some View {
        let done = progress.completedCount(of: course)
        return VStack(alignment: .leading, spacing: EconSpace.s) {
            HStack(spacing: EconSpace.s) {
                Image(systemName: course.icon)
                    .font(EconType.title)
                    .foregroundColor(EconColor.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: EconSpace.xxs) {
                    Text(course.title)
                        .font(EconType.title)
                        .foregroundColor(EconColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(course.lessons.count) lessons · \(course.estimatedMinutes) min · \(course.level == .intro ? "Intro" : "Intermediate")")
                        .font(EconType.caption)
                        .foregroundColor(EconColor.textTertiary)
                }
            }
            HStack(spacing: EconSpace.s) {
                ProgressView(value: Double(done), total: Double(max(course.lessons.count, 1)))
                    .tint(EconColor.interactive)
                    .accessibilityLabel("Course progress")
                    .accessibilityValue("\(done) of \(course.lessons.count) lessons")
                Text("\(done)/\(course.lessons.count)")
                    .font(EconType.caption)
                    .monospacedDigit()
                    .foregroundColor(done == course.lessons.count ? EconColor.interactive : EconColor.textTertiary)
                    .accessibilityHidden(true)
            }
        }
        .econCard()
    }

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
