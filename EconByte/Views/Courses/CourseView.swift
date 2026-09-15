import SwiftUI

/// A course's lesson list with progress (1.1.4). Presented in its own
/// `NavigationStack` from Home; lessons push `LessonView`.
struct CourseView: View {
    let course: Course
    var initialLesson: Lesson? = nil
    var onProPaywall: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: PurchaseManager
    @EnvironmentObject private var progress: CourseProgressStore
    @State private var path: [Lesson] = []

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Econ.ocean.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        lessonList
                        EducationalNoticeBanner(text: ContentStore.shared.courses?.educationalNotice
                                                ?? "Educational content only — not investment advice.")
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle(course.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") { dismiss() }.foregroundColor(Econ.sky)
                        .accessibilityIdentifier("courseCloseButton")
                }
            }
            .navigationDestination(for: Lesson.self) { lesson in
                LessonView(course: course, lesson: lesson,
                           onProPaywall: onProPaywall,
                           onNextLesson: { next in path = [next] })
                    .environmentObject(store)
                    .environmentObject(progress)
            }
        }
        .tint(Econ.sky)
        .onAppear {
            if let initialLesson, path.isEmpty { path = [initialLesson] }
        }
        .accessibilityIdentifier("course-\(course.courseID)")
    }

    private var header: some View {
        let done = progress.completedCount(of: course)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: course.icon)
                    .font(.title)
                    .foregroundColor(Econ.amber)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(course.title)
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundColor(Econ.white)
                    Text("\(course.lessons.count) lessons · about \(course.estimatedMinutes) min · \(course.level == .intro ? "Intro" : "Intermediate")")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Econ.subtext)
                }
            }
            Text(course.summary)
                .font(.system(size: 15, design: .rounded))
                .foregroundColor(Econ.white.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
            ProgressView(value: Double(done), total: Double(max(course.lessons.count, 1)))
                .tint(Econ.sky)
                .background(Econ.mist.opacity(0.2))
                .accessibilityLabel("Course progress")
                .accessibilityValue("\(done) of \(course.lessons.count) lessons")
            Text(done == course.lessons.count ? "Course complete ✓" : "\(done) of \(course.lessons.count) lessons complete")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(done == course.lessons.count ? Econ.sky : Econ.subtext)
        }
        .padding(18)
        .background(Econ.tide.opacity(0.15))
        .cornerRadius(16)
    }

    private var lessonList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("LESSONS")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(Econ.subtext)
                .tracking(1.5)
            ForEach(Array(course.lessons.enumerated()), id: \.element.lessonID) { index, lesson in
                let accessible = lesson.isPreview || store.isProActive
                Button {
                    if accessible { path = [lesson] } else { onProPaywall?() }
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(progress.isCompleted(lesson.lessonID) ? Econ.sky : Econ.tide.opacity(0.35))
                                .frame(width: 30, height: 30)
                            if progress.isCompleted(lesson.lessonID) {
                                Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundColor(Econ.ink)
                            } else {
                                Text("\(index + 1)").font(.system(size: 13, weight: .bold, design: .rounded)).foregroundColor(Econ.white)
                            }
                        }
                        .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(lesson.title)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundColor(accessible ? Econ.white : Econ.white.opacity(0.6))
                                .multilineTextAlignment(.leading)
                            HStack(spacing: 6) {
                                Text("\(lesson.estimatedMinutes) min")
                                if lesson.isPreview { Text("· Free preview") }
                                if lesson.hasVisual { Image(systemName: "chart.xyaxis.line").accessibilityLabel("includes a chart or diagram") }
                            }
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(Econ.subtext)
                        }
                        Spacer()
                        Image(systemName: accessible ? "chevron.right" : "lock.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(accessible ? Econ.subtext : Econ.amber)
                            .accessibilityHidden(true)
                    }
                    .padding(14)
                    .background(Econ.tide.opacity(accessible ? 0.12 : 0.06))
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("lessonRow-\(lesson.lessonID)")
                .accessibilityValue(Text(accessible ? (progress.isCompleted(lesson.lessonID) ? "completed" : "") : "locked, requires EconByte Pro"))
            }
        }
    }
}
