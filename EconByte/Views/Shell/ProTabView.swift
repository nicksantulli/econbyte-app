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
            ProPaywallContent(entryPoint: .proTab) {
                coursesSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
    }

    @ViewBuilder
    private var coursesSection: some View {
        if let courses = content.courses?.courses, !courses.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    EconSectionLabel(text: store.isProActive ? "Your courses" : "Courses")
                    Spacer()
                    if !store.isProActive {
                        Text("First lesson free")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(Econ.amber)
                    }
                }
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

    var body: some View {
        let done = progress.completedCount(of: course)
        let total = course.lessons.count
        return Button(action: action) {
            HStack(spacing: 12) {
                CourseProgressRing(done: done, total: total, icon: course.icon)
                    .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(course.title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(Econ.white)
                        .multilineTextAlignment(.leading)
                    Text(store.isProActive || done > 0
                         ? "\(done)/\(total) lessons · \(course.estimatedMinutes) min"
                         : "\(total) lessons · first lesson free")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(Econ.subtext)
                }
                Spacer()
                Image(systemName: store.isProActive ? "chevron.right" : "lock.open")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(store.isProActive ? Econ.subtext : Econ.amber)
                    .accessibilityHidden(true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Econ.tide.opacity(0.12))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("proCourseRow-\(course.courseID)")
        .accessibilityValue(Text("\(done) of \(total) lessons complete"))
    }
}
