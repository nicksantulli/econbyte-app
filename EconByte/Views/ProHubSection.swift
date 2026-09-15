import SwiftUI

/// The EconByte Pro section on Home (1.1.4): the Daily Brief row, the three
/// courses with progress, and — while Pro is not active — one call-to-action
/// row. Kept to one header and five rows so Home's praised density holds
/// (Owner-relayed feedback, 2026-09-14); the detail lives behind each row.
struct ProHubSection: View {
    let onOpenBrief: () -> Void
    let onOpenCourse: (Course) -> Void
    let onProPaywall: () -> Void

    @EnvironmentObject private var content: ContentStore
    @EnvironmentObject private var store: PurchaseManager
    @EnvironmentObject private var progress: CourseProgressStore
    @EnvironmentObject private var briefs: BriefStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("ECONBYTE PRO")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(Econ.subtext)
                    .tracking(1.5)
                Spacer()
                if store.isProActive {
                    Text("Active ✓")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(Econ.sky)
                        .accessibilityIdentifier("proActiveBadge")
                }
            }
            briefRow
            if let courses = content.courses {
                ForEach(courses.courses) { course in
                    courseRow(course)
                }
            }
            if !store.isProActive {
                ctaRow
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("proHub")
    }

    private var briefRow: some View {
        Button(action: onOpenBrief) {
            HStack(spacing: 12) {
                Image(systemName: "newspaper.fill")
                    .font(.title3)
                    .foregroundColor(Econ.amber)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Daily Brief")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(Econ.white)
                        if !store.isProActive {
                            Text("Preview")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(Econ.ink)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Econ.amber)
                                .cornerRadius(3)
                        }
                    }
                    Text(briefs.latest?.headline ?? "Official releases, in plain English")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(Econ.subtext)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundColor(Econ.subtext).accessibilityHidden(true)
            }
            .padding(14)
            .background(Econ.tide.opacity(0.12))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("proBriefRow")
    }

    private func courseRow(_ course: Course) -> some View {
        let done = progress.completedCount(of: course)
        let total = course.lessons.count
        return Button { onOpenCourse(course) } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().stroke(Econ.tide.opacity(0.4), lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: total == 0 ? 0 : CGFloat(done) / CGFloat(total))
                        .stroke(Econ.sky, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: course.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Econ.amber)
                }
                .frame(width: 30, height: 30)
                .accessibilityHidden(true)
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
            .background(Econ.tide.opacity(0.10))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("proCourseRow-\(course.courseID)")
        .accessibilityValue(Text("\(done) of \(total) lessons complete"))
    }

    private var ctaRow: some View {
        Button(action: onProPaywall) {
            HStack(spacing: 12) {
                Image(systemName: "graduationcap.fill")
                    .foregroundColor(Econ.ink)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(store.isEligibleForTrial == true ? "Try EconByte Pro free for 7 days" : "Get EconByte Pro")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(Econ.ink)
                    Text("Courses, the Daily Brief, every pack, no ads")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(Econ.ink.opacity(0.75))
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundColor(Econ.ink.opacity(0.7)).accessibilityHidden(true)
            }
            .padding(14)
            .background(Econ.amber)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("proCtaRow")
    }
}
