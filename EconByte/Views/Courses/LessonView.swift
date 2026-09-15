import SwiftUI

/// One course lesson as a story (1.1.5, Owner: "almost like a 'story' you
/// click through rather than an article you read").
///
/// Page 0 is the cover (course, title, summary, minutes); every later page is
/// one beat. A segmented bar at the top shows where the reader is. Tap the right
/// of the page or swipe left to go on; tap the left or swipe right to go back;
/// the Back / Next buttons at the bottom do the same for VoiceOver and Switch
/// Control. On an unanswered check the page itself does not advance on a tap
/// (a near-miss beside a choice must not skip the question) — Next still does.
///
/// The position is saved on every page, so a lesson reopens where it was left;
/// reaching the last beat (the recap) completes it. The sources and the one
/// "educational, not advice" notice sit on the recap. Reduce Motion replaces the
/// slide with a cross-fade. A lesson that is not the free preview is readable
/// only while Pro is active — checked here as well as in `CourseView`, so a deep
/// link can never bypass it.
struct LessonView: View {
    let course: Course
    let lesson: Lesson
    var onProPaywall: (() -> Void)? = nil
    var onNextLesson: ((Lesson) -> Void)? = nil
    var onClose: (() -> Void)? = nil

    @EnvironmentObject private var store: PurchaseManager
    @EnvironmentObject private var progress: CourseProgressStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var page = 0
    @State private var forward = true
    @State private var didRestore = false
    @State private var showSources = false

    private var accessible: Bool { lesson.isPreview || store.isProActive }
    private var lastPage: Int { lesson.pageCount - 1 }
    private var nextLesson: Lesson? {
        guard let index = course.lessons.firstIndex(where: { $0.lessonID == lesson.lessonID }),
              index + 1 < course.lessons.count else { return nil }
        return course.lessons[index + 1]
    }
    private var beat: LessonBeat? { page > 0 ? lesson.beats[page - 1] : nil }
    private var awaitingAnswer: Bool {
        guard let beat, beat.kind == .check, let ordinal = lesson.checkOrdinal(forBeat: page - 1) else { return false }
        return progress.checkResult(lessonID: lesson.lessonID, ordinal: ordinal) == nil
    }

    var body: some View {
        ZStack {
            EconColor.background.ignoresSafeArea()
            if accessible {
                story
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        closeButton
                    }
                    .padding(.horizontal, EconSpace.xs)
                    Spacer()
                    LockedLessonView(lesson: lesson) { onProPaywall?() }
                    Spacer()
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("lesson-\(lesson.lessonID)")
        .sheet(isPresented: $showSources) { LessonSourcesView(lesson: lesson) }
        .onAppear {
            guard !didRestore else { return }
            didRestore = true
            page = progress.resumePage(for: lesson)
        }
    }

    // MARK: Story

    private var story: some View {
        VStack(spacing: 0) {
            VStack(spacing: EconSpace.xs) {
                StoryProgressBar(pages: lesson.pageCount, current: page)
                    .padding(.trailing, EconSpace.gutter - EconSpace.xxs)
                HStack(spacing: EconSpace.xs) {
                    Text(course.title.uppercased())
                        .font(EconType.overline)
                        .tracking(EconType.overlineTracking)
                        .foregroundColor(EconColor.textTertiary)
                        .lineLimit(2)
                    Spacer(minLength: EconSpace.xs)
                    closeButton
                }
            }
            .padding(.leading, EconSpace.gutter)
            .padding(.trailing, EconSpace.xxs)
            .padding(.top, EconSpace.xs)
            // Story chrome (progress, course name, close) caps at accessibility2
            // so the beat itself keeps most of the screen at the largest sizes.
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)

            GeometryReader { geo in
                ScrollViewReader { proxy in
                ScrollView {
                    pageContent(proxy)
                        .padding(.horizontal, EconSpace.gutter)
                        .padding(.vertical, EconSpace.m)
                        .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .top)
                        .contentShape(Rectangle())
                        .gesture(SpatialTapGesture().onEnded { value in
                            if value.location.x < geo.size.width / 3 {
                                go(to: page - 1)
                            } else if !awaitingAnswer && page < lastPage {
                                go(to: page + 1)
                            }
                        })
                }
                // The page id sits on the scroll view, its own accessibility
                // node: on a container it would overwrite the id of a page's
                // only child (a check beat without a picture lost "quiz").
                .accessibilityIdentifier("storyPage-\(page)")
                .id(page)
                .transition(pageTransition)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 30).onEnded { value in
                        let dx = value.translation.width, dy = value.translation.height
                        guard abs(dx) > abs(dy) * 1.5, abs(dx) > 50 else { return }
                        go(to: dx < 0 ? min(page + 1, lastPage) : page - 1)
                    }
                )
                }
            }
            .clipped()

            controls
        }
        .accessibilityAction(named: Text("Next page")) { go(to: min(page + 1, lastPage)) }
        .accessibilityAction(named: Text("Previous page")) { go(to: page - 1) }
    }

    private var closeButton: some View {
        EconIconButton(systemImage: "xmark", label: "Close lesson", tint: EconColor.textSecondary) {
            onClose?()
        }
        .accessibilityIdentifier("storyCloseButton")
    }

    private var pageTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                           removal: .opacity)
    }

    private func go(to target: Int) {
        guard (0...lastPage).contains(target), target != page else { return }
        forward = target > page
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) { page = target }
        if target == lastPage {
            progress.markCompleted(lessonID: lesson.lessonID, courseID: course.courseID)
        } else {
            progress.recordPage(target, lessonID: lesson.lessonID)
        }
        UIAccessibility.post(notification: .screenChanged, argument: nil)
    }

    // MARK: Pages

    @ViewBuilder
    private func pageContent(_ proxy: ScrollViewProxy) -> some View {
        if let beat {
            StoryBeatView(beat: beat, lesson: lesson, beatIndex: page - 1,
                          onSources: { showSources = true },
                          onReveal: {
                              withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
                                  proxy.scrollTo(StoryCheckView.feedbackAnchor, anchor: .bottom)
                              }
                          })
        } else {
            cover
        }
    }

    private var cover: some View {
        VStack(alignment: .leading, spacing: EconSpace.m) {
            Spacer(minLength: EconSpace.xl)
            Image(systemName: course.icon)
                .font(.system(.largeTitle))
                .foregroundColor(EconColor.accent)
                .frame(width: 72, height: 72)
                .background(EconColor.surfaceRaised)
                .clipShape(Circle())
                .accessibilityHidden(true)
            Text(lesson.title)
                .font(EconType.display)
                .foregroundColor(EconColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(lesson.summary)
                .font(EconType.story)
                .foregroundColor(EconColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: EconSpace.xs) {
                Label("\(lesson.estimatedMinutes) min", systemImage: "clock")
                if progress.isCompleted(lesson.lessonID) {
                    Label("Completed", systemImage: "checkmark.circle.fill")
                        .foregroundColor(EconColor.interactive)
                }
            }
            .font(EconType.caption)
            .foregroundColor(EconColor.textTertiary)
            Spacer(minLength: EconSpace.xl)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: EconSpace.s) {
            Button { go(to: page - 1) } label: {
                Image(systemName: "chevron.left")
                    .font(EconType.headline)
                    .foregroundColor(page > 0 ? EconColor.interactive : EconColor.textTertiary)
                    .frame(width: 60, height: 60)
                    .background(EconColor.interactiveFill)
                    .clipShape(RoundedRectangle(cornerRadius: EconRadius.control, style: .continuous))
            }
            .disabled(page == 0)
            .accessibilityLabel("Previous page")
            .accessibilityIdentifier("storyBackButton")

            if page == lastPage {
                if let next = nextLesson {
                    Button("Next lesson") { onNextLesson?(next) }
                        .buttonStyle(PrimaryButton())
                        .accessibilityIdentifier("lessonCompleteButton")
                } else {
                    Button("Done") { onClose?() }
                        .buttonStyle(PrimaryButton())
                        .accessibilityIdentifier("lessonCompleteButton")
                }
            } else {
                // A lesson in progress reopens on the page the reader left
                // (`onAppear`), so the cover only ever offers "Start".
                Button(page == 0 ? "Start" : "Next") { go(to: page + 1) }
                .buttonStyle(PrimaryButton())
                .accessibilityIdentifier("storyNextButton")
            }
        }
        .padding(.horizontal, EconSpace.gutter)
        .padding(.top, EconSpace.xs)
        .padding(.bottom, EconSpace.s)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .accessibilityValue(Text("Page \(page + 1) of \(lesson.pageCount)"))
    }
}

/// Instagram-style segmented progress: one segment per page, filled up to and
/// including the current one.
struct StoryProgressBar: View {
    let pages: Int
    let current: Int

    var body: some View {
        HStack(spacing: pages > 20 ? 2 : EconSpace.xxs) {
            ForEach(0..<pages, id: \.self) { index in
                Capsule()
                    .fill(index <= current ? EconColor.interactive : EconColor.outline)
                    .frame(height: 4)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Lesson progress")
        .accessibilityValue("Page \(current + 1) of \(pages)")
        .accessibilityIdentifier("storyProgressBar")
    }
}

// MARK: - One beat

struct StoryBeatView: View {
    let beat: LessonBeat
    let lesson: Lesson
    let beatIndex: Int
    var onSources: () -> Void
    var onReveal: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: EconSpace.l) {
            // A check puts its question first and its picture after the
            // feedback, so the answer's explanation lands on screen.
            if beat.kind != .check, let visual = beat.visual {
                StoryVisualView(visual: visual, lesson: lesson)
            }
            switch beat.kind {
            case .idea: idea
            case .term: terms
            case .check:
                if let check = beat.check, let ordinal = lesson.checkOrdinal(forBeat: beatIndex) {
                    StoryCheckView(quiz: check, lessonID: lesson.lessonID, ordinal: ordinal, onReveal: onReveal)
                }
            case .recap: recap
            }
            if beat.kind == .check, let visual = beat.visual {
                StoryVisualView(visual: visual, lesson: lesson)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var toneIcon: (name: String, color: Color, label: String)? {
        switch beat.tone {
        case .caution?: return ("exclamationmark.triangle.fill", EconColor.accent, "Caution")
        case .example?: return ("function", EconColor.interactive, "Example")
        case .note?: return ("lightbulb.fill", EconColor.interactive, "Note")
        case nil: return nil
        }
    }

    private var idea: some View {
        VStack(alignment: .leading, spacing: EconSpace.s) {
            if let heading = beat.heading {
                HStack(alignment: .firstTextBaseline, spacing: EconSpace.xs) {
                    if let tone = toneIcon {
                        Image(systemName: tone.name)
                            .foregroundColor(tone.color)
                            .accessibilityLabel(tone.label)
                    }
                    Text(heading)
                        .font(EconType.title3)
                        .foregroundColor(EconColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }
            } else if let tone = toneIcon {
                Image(systemName: tone.name)
                    .font(EconType.title3)
                    .foregroundColor(tone.color)
                    .accessibilityLabel(tone.label)
            }
            Text(beat.text ?? "")
                .font(EconType.story)
                .foregroundColor(EconColor.textPrimary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, beat.tone == nil ? 0 : EconSpace.s)
        .overlay(alignment: .leading) {
            if let tone = toneIcon {
                Capsule().fill(tone.color).frame(width: 3).accessibilityHidden(true)
            }
        }
    }

    private var terms: some View {
        VStack(alignment: .leading, spacing: EconSpace.m) {
            if let heading = beat.heading {
                Text(heading)
                    .font(EconType.title3)
                    .foregroundColor(EconColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
            }
            ForEach(Array((beat.terms ?? []).enumerated()), id: \.offset) { _, term in
                VStack(alignment: .leading, spacing: EconSpace.xxs) {
                    Text(term.term)
                        .font(EconType.title3)
                        .foregroundColor(EconColor.accentText)
                    Text(term.definition)
                        .font(EconType.story)
                        .foregroundColor(EconColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
            if let text = beat.text {
                Text(text)
                    .font(EconType.body)
                    .foregroundColor(EconColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var recap: some View {
        VStack(alignment: .leading, spacing: EconSpace.m) {
            Text(beat.heading ?? "Recap")
                .font(EconType.title)
                .foregroundColor(EconColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: EconSpace.s) {
                ForEach(Array((beat.items ?? []).enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: EconSpace.s) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(EconColor.interactive)
                            .accessibilityHidden(true)
                        Text(item)
                            .font(EconType.body)
                            .foregroundColor(EconColor.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .econCard()
            .accessibilityIdentifier("takeaways")
            Button {
                onSources()
            } label: {
                Label("Sources (\(lesson.sources.count))", systemImage: "doc.text")
            }
            .buttonStyle(EconLinkButton())
            .accessibilityIdentifier("lessonSourcesButton")
            // The one "not advice" line in a lesson, at its end.
            EducationalNoticeBanner(text: PlanCopy.notAdvice)
        }
    }
}

// MARK: - Quick check

/// Single-answer multiple choice with immediate feedback. The first answer is
/// recorded; the reader can tap other choices afterwards to see why they are
/// wrong, without changing it.
struct StoryCheckView: View {
    let quiz: Quiz
    let lessonID: String
    let ordinal: Int
    var onReveal: () -> Void = {}
    static let feedbackAnchor = "storyCheckFeedback"
    @EnvironmentObject private var progress: CourseProgressStore
    @State private var chosen: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var revealed: Bool { chosen != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: EconSpace.s) {
            EconSectionLabel(text: "Quick check")
            Text(quiz.question)
                .font(EconType.title3)
                .foregroundColor(EconColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array(quiz.choices.enumerated()), id: \.offset) { index, choice in
                Button {
                    let first = chosen == nil
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) { chosen = index }
                    if first {
                        progress.recordCheck(lessonID: lessonID, ordinal: ordinal, correct: index == quiz.answerIndex)
                        UINotificationFeedbackGenerator().notificationOccurred(index == quiz.answerIndex ? .success : .warning)
                    }
                    DispatchQueue.main.async { onReveal() }
                } label: {
                    HStack(spacing: EconSpace.s) {
                        Image(systemName: symbol(for: index))
                            .font(EconType.headline)
                            .foregroundColor(color(for: index))
                            .accessibilityHidden(true)
                        Text(choice)
                            .font(EconType.body)
                            .foregroundColor(EconColor.textPrimary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .econRow(fill: EconColor.surfaceRaised)
                    .overlay(RoundedRectangle(cornerRadius: EconRadius.control, style: .continuous)
                        .stroke(color(for: index).opacity(revealed && (index == quiz.answerIndex || index == chosen) ? 0.9 : 0),
                                lineWidth: 2))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("quizChoice-\(index)")
                .accessibilityValue(Text(accessibilityValue(for: index)))
            }
            if revealed {
                VStack(alignment: .leading, spacing: EconSpace.xxs) {
                    Text(chosen == quiz.answerIndex ? "Correct" : "Not quite")
                        .font(EconType.headline)
                        .foregroundColor(chosen == quiz.answerIndex ? EconColor.interactive : EconColor.accentText)
                    Text(quiz.explanation)
                        .font(EconType.body)
                        .foregroundColor(EconColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("quizExplanation")
                .id(Self.feedbackAnchor)
                .transition(.opacity)
            }
        }
        // `.contain`: a plain container's identifier would override the
        // choices' own ids (SwiftUI propagation); contained children keep theirs.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("quiz")
        .onAppear {
            // A re-opened lesson shows the recorded first answer's verdict.
            if chosen == nil, let recorded = progress.checkResult(lessonID: lessonID, ordinal: ordinal) {
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
        guard revealed else { return EconColor.textTertiary }
        if index == quiz.answerIndex { return EconColor.interactive }
        if index == chosen { return EconColor.accentText }
        return EconColor.textTertiary
    }

    private func accessibilityValue(for index: Int) -> String {
        guard revealed else { return "" }
        if index == quiz.answerIndex { return "correct answer" }
        if index == chosen { return "your answer, incorrect" }
        return ""
    }
}

// MARK: - Supporting views

/// The "educational, not advice" line at the end of every lesson.
struct EducationalNoticeBanner: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: EconSpace.xs) {
            Image(systemName: "info.circle")
                .foregroundColor(EconColor.accent)
                .accessibilityHidden(true)
            Text(text)
                .font(EconType.footnote)
                .foregroundColor(EconColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .econInset()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("educationalNotice")
    }
}

/// A lesson's primary sources, from the recap.
struct LessonSourcesView: View {
    let lesson: Lesson
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                EconColor.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: EconSpace.s) {
                        ForEach(Array(lesson.sources.enumerated()), id: \.offset) { _, source in
                            if let url = URL(string: source.url) {
                                Link(destination: url) {
                                    VStack(alignment: .leading, spacing: EconSpace.xxs) {
                                        Text(source.documentTitle)
                                            .font(EconType.subheadlineEmphasis)
                                            .foregroundColor(EconColor.interactive)
                                            .multilineTextAlignment(.leading)
                                        Text("\(source.organization) · verified \(source.verificationDate)")
                                            .font(EconType.caption)
                                            .foregroundColor(EconColor.textTertiary)
                                    }
                                    .econRow()
                                }
                            }
                        }
                    }
                    .padding(EconSpace.gutter)
                }
            }
            .navigationTitle("Sources")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }.foregroundColor(EconColor.interactive)
                }
            }
        }
        .tint(EconColor.interactive)
        .accessibilityIdentifier("lessonSourcesView")
    }
}

/// Shown in place of a Pro lesson when Pro is not active.
struct LockedLessonView: View {
    let lesson: Lesson
    let onProPaywall: () -> Void

    var body: some View {
        VStack(spacing: EconSpace.m) {
            Image(systemName: "lock.fill")
                .font(.system(.largeTitle))
                .foregroundColor(EconColor.accent)
                .accessibilityHidden(true)
            Text(lesson.title)
                .font(EconType.title)
                .foregroundColor(EconColor.textPrimary)
                .multilineTextAlignment(.center)
            Text(lesson.summary)
                .font(EconType.body)
                .foregroundColor(EconColor.textSecondary)
                .multilineTextAlignment(.center)
            Button("See EconByte Pro") { onProPaywall() }
                .buttonStyle(PrimaryButton())
                .accessibilityIdentifier("lessonLockedProButton")
        }
        .padding(EconSpace.xl)
    }
}
