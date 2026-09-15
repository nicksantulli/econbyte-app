import SwiftUI

/// Pro (1.1.4 shell). A subscriber sees their status and the course library.
/// Everyone else sees the subscription paywall inline — the same 3.1.2
/// content as the full-screen paywall — with the courses in the middle, each
/// with its first lesson free.
struct ProTabView: View {
    @EnvironmentObject private var store: PurchaseManager
    @EnvironmentObject private var content: ContentStore
    @EnvironmentObject private var progress: CourseProgressStore
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        EconTabScaffold(scrollSpace: "pro") { _ in
            VStack(alignment: .leading, spacing: 24) {
                if store.isProActive {
                    statusCard
                    coursesSection
                    includedSection
                } else {
                    ProPaywallContent(entryPoint: .proTab) {
                        coursesSection
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title2)
                    .foregroundColor(Econ.amber)
                    .accessibilityHidden(true)
                Text("EconByte Pro")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundColor(Econ.white)
                Spacer()
                Text("Active ✓")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(Econ.sky)
                    .accessibilityIdentifier("proActiveBadge")
            }
            if let plan = store.proProductID {
                detailRow("Plan", plan == PurchaseManager.ProductID.proAnnual.rawValue ? "Yearly" : "Monthly")
            }
            if let expiration = store.proExpiration {
                detailRow("Current period ends", expiration.formatted(date: .abbreviated, time: .omitted))
            }
            Link("Manage Subscription", destination: PurchaseManager.manageSubscriptionsURL)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(Econ.sky)
                .accessibilityIdentifier("proManageSubscriptionLink")
        }
        .padding(18)
        .background(Econ.tide.opacity(0.16))
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Econ.amber.opacity(0.35), lineWidth: 1))
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundColor(Econ.white.opacity(0.8))
            Spacer()
            Text(value).foregroundColor(Econ.subtext)
        }
        .font(.system(size: 14, design: .rounded))
        .accessibilityElement(children: .combine)
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

    private var includedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            EconSectionLabel(text: "Included")
            includedRow("newspaper.fill", "The Daily Brief", "In News") { router.selectedTab = .news }
            includedRow("square.stack.3d.up.fill", "Every topic pack and core topic", "In Browse") { router.selectedTab = .browse }
            HStack(spacing: 12) {
                Image(systemName: "rectangle.slash").foregroundColor(Econ.amber).frame(width: 24)
                    .accessibilityHidden(true)
                Text("No ads")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(Econ.white)
                Spacer()
            }
            .padding(14)
            .background(Econ.tide.opacity(0.10))
            .cornerRadius(12)
        }
    }

    private func includedRow(_ icon: String, _ title: String, _ hint: String,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).foregroundColor(Econ.amber).frame(width: 24)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(Econ.white)
                Spacer()
                Text(hint)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(Econ.subtext)
                Image(systemName: "chevron.right").foregroundColor(Econ.subtext)
                    .accessibilityHidden(true)
            }
            .padding(14)
            .background(Econ.tide.opacity(0.10))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
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
