import SwiftUI

/// Pro (1.1.4 shell): the Pro offer inline — the same 3.1.2 content as the
/// full-screen paywall, with a subscriber's current plan marked — and the
/// course library in the middle (first lesson of each course free).
struct ProTabView: View {
    @EnvironmentObject private var store: PurchaseManager
    @EnvironmentObject private var content: ContentStore
    @EnvironmentObject private var progress: CourseProgressStore
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        EconTabScaffold(scrollSpace: "pro") { _ in
            // Subscribers and everyone else see the same offer: a subscriber's
            // tile says "Current plan" (checklist A10) with Manage Subscription.
            // Phase 24: a subscriber came for the courses, so they come first and
            // the (unchanged) plan card follows; a non-subscriber sees the offer
            // first with the courses as its interlude, exactly as before.
            Group {
                if store.isProActive {
                    VStack(spacing: EconSpace.l) {
                        coursesSection
                        ProPaywallContent(entryPoint: .proTab) { EmptyView() }
                    }
                } else {
                    ProPaywallContent(entryPoint: .proTab) {
                        coursesSection
                    }
                }
            }
            .padding(.horizontal, EconSpace.gutter)
            .padding(.top, EconSpace.s)
            .padding(.bottom, EconSpace.xxl)
        }
    }

    @ViewBuilder
    private var coursesSection: some View {
        if let courses = content.courses?.courses, !courses.isEmpty {
            VStack(alignment: .leading, spacing: EconSpace.s) {
                // Each row says "first lesson free", so the header does not.
                EconSectionLabel(text: store.isProActive ? "Your courses" : "Courses")
                ForEach(courses) { course in
                    ProCourseRow(course: course) { router.openCourse(course) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// One course with its progress ring (Pro tab).
struct ProCourseRow: View {
    let course: Course
    let action: () -> Void

    @EnvironmentObject private var store: PurchaseManager
    @EnvironmentObject private var progress: CourseProgressStore

    @ScaledMetric(relativeTo: .subheadline) private var ringSize: CGFloat = EconSize.tapTarget

    var body: some View {
        let done = progress.completedCount(of: course)
        let total = course.lessons.count
        return Button(action: action) {
            EconAdaptiveRow(spacing: EconSpace.s) {
                CourseProgressRing(done: done, total: total, icon: course.icon)
                    .frame(width: ringSize, height: ringSize)
                VStack(alignment: .leading, spacing: 2) {
                    Text(course.title)
                        .font(EconType.subheadlineEmphasis)
                        .foregroundColor(EconColor.textPrimary)
                        .multilineTextAlignment(.leading)
                    Text(subtitle(done: done, total: total))
                        .font(EconType.caption)
                        .foregroundColor(EconColor.textTertiary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: store.isProActive ? "chevron.right" : "lock.open")
                    .font(EconType.footnote.weight(.semibold))
                    .foregroundColor(store.isProActive ? EconColor.textTertiary : EconColor.accent)
                    .accessibilityHidden(true)
            }
            .econRow()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("proCourseRow-\(course.courseID)")
        .accessibilityValue(Text("\(done) of \(total) lessons complete"))
    }

    /// A subscriber mid-course sees what is next; everyone else the size of the
    /// course and the free first lesson.
    private func subtitle(done: Int, total: Int) -> String {
        guard store.isProActive || done > 0 else { return "\(total) lessons · first lesson free" }
        if done > 0, done < total, let next = progress.nextLesson(in: course) {
            return "\(done)/\(total) · Next: \(next.title)"
        }
        return "\(done)/\(total) lessons · \(course.estimatedMinutes) min"
    }
}
