import SwiftUI

struct CardModeView: View {
    let cards: [EconCard]
    let title: String
    /// Which deck this is, and where it was opened from. Both are closed
    /// vocabularies (see EconTelemetryWiring.swift); the deck's *contents* —
    /// card ids, topic ids, titles — are never sent.
    var mode: EBMode = .daily
    var entryPoint: EBEntryPoint = .home

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var content: ContentStore
    @EnvironmentObject private var streak: StreakManager
    @EnvironmentObject private var ads: AdManager
    @State private var currentIndex = 0
    @State private var dragOffset: CGFloat = 0
    @State private var sessionDone = false

    // Session measurement. All three collapse to buckets before they leave:
    // a start instant becomes a duration bucket, a count becomes a card bucket,
    // and the bookmark set becomes one boolean.
    @State private var startedAt = Date()
    @State private var cardsAdvanced = 0
    @State private var adImpressionsAtStart = 0
    @State private var bookmarkedAtStart: Set<String> = []
    @State private var didReportEnd = false

    var body: some View {
        ZStack {
            Econ.ocean.ignoresSafeArea()
            if sessionDone {
                SessionCompleteView(title: title, cardsCount: cards.count) {
                    reportSessionEnded(reason: .completed)
                    dismiss()
                }
                .environmentObject(streak)
                .environmentObject(content)
            } else if cards.isEmpty {
                VStack(spacing: 16) {
                    Text("No cards available.")
                        .foregroundColor(Econ.white)
                    Button("Done") {
                        reportSessionEnded(reason: .userExit)
                        dismiss()
                    }
                        .buttonStyle(SecondaryButton())
                        .padding(.horizontal, 40)
                }
            } else {
                VStack(spacing: 0) {
                    // Nav bar
                    HStack {
                        Button("✕") {
                            reportSessionEnded(reason: .userExit)
                            dismiss()
                        }
                            .foregroundColor(Econ.subtext)
                            .font(.title2)
                            .accessibilityIdentifier("cardModeCloseButton")
                        Spacer()
                        Text("\(min(currentIndex + 1, cards.count)) / \(cards.count)")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundColor(Econ.subtext)
                        Spacer()
                        Text(title)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(Econ.white)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)

                    // Progress
                    ProgressView(value: Double(currentIndex + 1), total: Double(cards.count))
                        .tint(Econ.sky)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)

                    // Card
                    let card = cards[currentIndex]
                    CardView(card: card, mode: mode)
                        .environmentObject(content)
                        .padding(.horizontal, 20)
                        .offset(x: dragOffset)
                        .gesture(
                            DragGesture()
                                .onChanged { dragOffset = $0.translation.width }
                                .onEnded { value in
                                    if value.translation.width < -60 {
                                        advance()
                                    } else if value.translation.width > 60 && currentIndex > 0 {
                                        withAnimation(.easeOut(duration: 0.2)) { dragOffset = 0 }
                                        currentIndex -= 1
                                        EconGrowth.cardAdvanced(mode: mode, direction: .back,
                                                                depth: currentIndex)
                                    } else {
                                        withAnimation(.spring()) { dragOffset = 0 }
                                    }
                                }
                        )
                        .id(currentIndex)

                    Spacer()

                    // Next button
                    Button("Next →") { advance() }
                        .buttonStyle(PrimaryButton())
                        .padding(.horizontal, 20)
                        .padding(.bottom, 32)
                }
            }
        }
        .onAppear {
            startedAt = Date()
            adImpressionsAtStart = ads.impressionCount
            bookmarkedAtStart = Set(content.bookmarkedCards.map(\.id))
            EconGrowth.sessionStarted(mode: mode, entryPoint: entryPoint, deckSize: cards.count)
        }
        .onDisappear {
            // Backstop for a swipe-down / system dismissal that never reaches a
            // button. `reportSessionEnded` is idempotent, so the ordinary paths
            // still report their own, more accurate, reason.
            reportSessionEnded(reason: .userExit)
            EconGrowth.flush()
        }
    }

    private func advance() {
        let card = cards[currentIndex]
        content.markSeen(card.id)
        streak.noteCardSeen()
        cardsAdvanced += 1
        EconGrowth.cardAdvanced(mode: mode, direction: .forward, depth: cardsAdvanced)
        Task { await ads.noteCardSwipe() }
        withAnimation(.easeOut(duration: 0.2)) { dragOffset = 0 }
        if currentIndex < cards.count - 1 {
            currentIndex += 1
        } else {
            sessionDone = true
        }
    }

    /// Emits `session_ended_v1` exactly once per presentation.
    private func reportSessionEnded(reason: EBEndReason) {
        guard !didReportEnd else { return }
        didReportEnd = true
        let addedABookmark = content.bookmarkedCards.contains { !bookmarkedAtStart.contains($0.id) }
        EconGrowth.sessionEnded(mode: mode,
                                reason: reason,
                                cardsViewed: cardsAdvanced,
                                duration: Date().timeIntervalSince(startedAt),
                                hadBookmark: addedABookmark,
                                adImpressions: ads.impressionCount - adImpressionsAtStart)
    }
}
