import SwiftUI

/// One course lesson, rendered block by block (1.1.4).
///
/// The "educational, not advice" notice sits at the top of every lesson; the
/// sources at the bottom. Completing a lesson means reaching the takeaways and
/// tapping "Mark as complete" (or "Next lesson"), which records progress locally
/// and emits the bucketed completion event once. A lesson that is not the free
/// preview is readable only while Pro is active — the check is here as well as
/// in `CourseView`, so a deep link can never bypass it.
struct LessonView: View {
    let course: Course
    let lesson: Lesson
    var onProPaywall: (() -> Void)? = nil
    var onNextLesson: ((Lesson) -> Void)? = nil

    @EnvironmentObject private var store: PurchaseManager
    @EnvironmentObject private var progress: CourseProgressStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var accessible: Bool { lesson.isPreview || store.isProActive }
    private var nextLesson: Lesson? {
        guard let index = course.lessons.firstIndex(where: { $0.lessonID == lesson.lessonID }),
              index + 1 < course.lessons.count else { return nil }
        return course.lessons[index + 1]
    }

    var body: some View {
        ZStack {
            Econ.ocean.ignoresSafeArea()
            if accessible {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        ForEach(Array(lesson.blocks.enumerated()), id: \.offset) { index, block in
                            LessonBlockView(block: block, lessonID: lesson.lessonID, ordinal: index)
                                .environmentObject(progress)
                        }
                        completion
                        sources
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
            } else {
                LockedLessonView(lesson: lesson) { onProPaywall?() }
            }
        }
        .navigationTitle(lesson.title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("lesson-\(lesson.lessonID)")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(course.title.uppercased())
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(Econ.subtext)
                .tracking(1.5)
            Text(lesson.title)
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundColor(Econ.white)
                .fixedSize(horizontal: false, vertical: true)
            Text(lesson.summary)
                .font(.system(size: 15, design: .rounded))
                .foregroundColor(Econ.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Label("\(lesson.estimatedMinutes) min", systemImage: "clock")
                if progress.isCompleted(lesson.lessonID) {
                    Label("Completed", systemImage: "checkmark.circle.fill").foregroundColor(Econ.sky)
                }
            }
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundColor(Econ.subtext)
            EducationalNoticeBanner(text: ContentStore.shared.courses?.educationalNotice
                                    ?? "Educational content only — not investment advice.")
        }
    }

    private var completion: some View {
        VStack(spacing: 10) {
            if let next = nextLesson {
                Button(progress.isCompleted(lesson.lessonID) ? "Next lesson →" : "Mark complete, next lesson →") {
                    progress.markCompleted(lessonID: lesson.lessonID, courseID: course.courseID)
                    onNextLesson?(next)
                }
                .buttonStyle(PrimaryButton())
                .accessibilityIdentifier("lessonCompleteButton")
            } else {
                Button(progress.isCompleted(lesson.lessonID) ? "Completed ✓" : "Mark course complete") {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                        progress.markCompleted(lessonID: lesson.lessonID, courseID: course.courseID)
                    }
                }
                .buttonStyle(PrimaryButton())
                .disabled(progress.isCompleted(lesson.lessonID))
                .accessibilityIdentifier("lessonCompleteButton")
            }
        }
        .padding(.top, 6)
    }

    private var sources: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SOURCES")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(Econ.subtext)
                .tracking(1.5)
            ForEach(Array(lesson.sources.enumerated()), id: \.offset) { _, source in
                if let url = URL(string: source.url) {
                    Link(destination: url) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(source.documentTitle)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundColor(Econ.sky)
                            Text("\(source.organization) · verified \(source.verificationDate)")
                                .font(.system(size: 11, design: .rounded))
                                .foregroundColor(Econ.subtext)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            Text("For educational purposes only — not financial or investment advice.")
                .font(.system(size: 11, design: .rounded))
                .foregroundColor(Econ.subtext)
                .padding(.top, 4)
        }
        .padding(14)
        .background(Econ.tide.opacity(0.10))
        .cornerRadius(12)
    }
}

/// The line every lesson and brief opens with.
struct EducationalNoticeBanner: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundColor(Econ.amber)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(Econ.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Econ.amber.opacity(0.10))
        .cornerRadius(10)
        .accessibilityIdentifier("educationalNotice")
    }
}

/// Shown in place of a Pro lesson's body when Pro is not active.
struct LockedLessonView: View {
    let lesson: Lesson
    let onProPaywall: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.system(size: 40))
                .foregroundColor(Econ.amber)
                .accessibilityHidden(true)
            Text(lesson.title)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundColor(Econ.white)
                .multilineTextAlignment(.center)
            Text(lesson.summary)
                .font(.system(size: 15, design: .rounded))
                .foregroundColor(Econ.white.opacity(0.75))
                .multilineTextAlignment(.center)
            Text("This lesson is part of EconByte Pro. The first lesson of every course is free.")
                .font(.system(size: 13, design: .rounded))
                .foregroundColor(Econ.subtext)
                .multilineTextAlignment(.center)
            Button("See EconByte Pro") { onProPaywall() }
                .buttonStyle(PrimaryButton())
                .accessibilityIdentifier("lessonLockedProButton")
        }
        .padding(28)
    }
}

// MARK: - Blocks

struct LessonBlockView: View {
    let block: LessonBlock
    let lessonID: String
    let ordinal: Int
    @EnvironmentObject private var progress: CourseProgressStore

    var body: some View {
        switch block {
        case let .paragraph(text):
            Text(text)
                .font(.system(size: 16, design: .rounded))
                .foregroundColor(Econ.white.opacity(0.92))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        case let .callout(style, title, text):
            CalloutView(style: style, title: title, text: text)
        case let .keyTerms(terms):
            KeyTermsView(terms: terms)
        case let .diagram(id, caption):
            VStack(alignment: .leading, spacing: 8) {
                DiagramView(id: id)
                Text(caption)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(Econ.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityIdentifier("diagram-\(id.rawValue)")
        case let .chart(spec):
            ChartBlockView(spec: spec)
        case let .quiz(quiz):
            QuizBlockView(quiz: quiz, lessonID: lessonID)
                .environmentObject(progress)
        case let .takeaways(items):
            TakeawaysView(items: items)
        }
    }
}

struct CalloutView: View {
    let style: CalloutStyle
    let title: String
    let text: String

    private var icon: String {
        switch style {
        case .note:    return "lightbulb.fill"
        case .caution: return "exclamationmark.triangle.fill"
        case .example: return "function"
        }
    }
    private var tint: Color {
        switch style {
        case .note:    return Econ.sky
        case .caution: return Econ.amber
        case .example: return Econ.mist
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: icon).foregroundColor(tint).accessibilityHidden(true)
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(tint)
            }
            Text(text)
                .font(.system(size: 14, design: .rounded))
                .foregroundColor(Econ.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.10))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(tint.opacity(0.35), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

struct KeyTermsView: View {
    let terms: [KeyTerm]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("KEY TERMS")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(Econ.subtext)
                .tracking(1.5)
            ForEach(Array(terms.enumerated()), id: \.offset) { _, term in
                VStack(alignment: .leading, spacing: 2) {
                    Text(term.term)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(Econ.amberLight)
                    Text(term.definition)
                        .font(.system(size: 14, design: .rounded))
                        .foregroundColor(Econ.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Econ.tide.opacity(0.12))
        .cornerRadius(12)
    }
}

struct TakeawaysView: View {
    let items: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TAKEAWAYS")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(Econ.subtext)
                .tracking(1.5)
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Econ.sky)
                        .accessibilityHidden(true)
                    Text(item)
                        .font(.system(size: 14, design: .rounded))
                        .foregroundColor(Econ.white.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Econ.sky.opacity(0.08))
        .cornerRadius(12)
        .accessibilityIdentifier("takeaways")
    }
}

/// Single-answer multiple choice. The first answer is recorded; the reader can
/// tap other choices afterwards to see why they are wrong, without changing it.
struct QuizBlockView: View {
    let quiz: Quiz
    let lessonID: String
    @EnvironmentObject private var progress: CourseProgressStore
    @State private var chosen: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var revealed: Bool { chosen != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("QUICK CHECK")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(Econ.subtext)
                .tracking(1.5)
            Text(quiz.question)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(Econ.white)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array(quiz.choices.enumerated()), id: \.offset) { index, choice in
                Button {
                    guard chosen == nil else { chosen = index; return }
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) { chosen = index }
                    progress.recordQuiz(lessonID: lessonID, correct: index == quiz.answerIndex)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: symbol(for: index))
                            .foregroundColor(color(for: index))
                            .accessibilityHidden(true)
                        Text(choice)
                            .font(.system(size: 14, design: .rounded))
                            .foregroundColor(Econ.white.opacity(0.9))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Econ.ocean.opacity(0.7))
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .stroke(color(for: index).opacity(revealed && (index == quiz.answerIndex || index == chosen) ? 0.8 : 0.2), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("quizChoice-\(index)")
                .accessibilityValue(Text(accessibilityValue(for: index)))
            }
            if revealed {
                VStack(alignment: .leading, spacing: 4) {
                    Text(chosen == quiz.answerIndex ? "Correct" : "Not quite")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(chosen == quiz.answerIndex ? Econ.sky : Econ.amber)
                    Text(quiz.explanation)
                        .font(.system(size: 14, design: .rounded))
                        .foregroundColor(Econ.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityIdentifier("quizExplanation")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Econ.tide.opacity(0.14))
        .cornerRadius(12)
        // `.contain`: a plain container's identifier would override the
        // choices' own ids (SwiftUI propagation); contained children keep theirs.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("quiz")
        .onAppear {
            // A re-opened lesson shows the recorded first answer's verdict.
            if chosen == nil, let recorded = progress.quizResult(lessonID) {
                chosen = recorded ? quiz.answerIndex : quiz.choices.indices.first { $0 != quiz.answerIndex }
            }
        }
    }

    private func symbol(for index: Int) -> String {
        guard revealed else { return "circle" }
        if index == quiz.answerIndex { return "checkmark.circle.fill" }
        if index == chosen { return "xmark.circle.fill" }
        return "circle"
    }

    private func color(for index: Int) -> Color {
        guard revealed else { return Econ.subtext }
        if index == quiz.answerIndex { return Econ.sky }
        if index == chosen { return Econ.amber }
        return Econ.subtext
    }

    private func accessibilityValue(for index: Int) -> String {
        guard revealed else { return "" }
        if index == quiz.answerIndex { return "correct answer" }
        if index == chosen { return "your answer, incorrect" }
        return ""
    }
}
