import SwiftUI

struct CardModeView: View {
    let cards: [EconCard]
    let title: String
    /// RECONCILED (1.1.2): which deck this is and how it was entered, so the
    /// session events can be read without ever naming a topic or a card.
    var mode: EBMode = .daily
    var entryPoint: EBEntryPoint = .home
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var content: ContentStore
    @EnvironmentObject private var streak: StreakManager
    @EnvironmentObject private var growth: EconGrowth
    @State private var currentIndex = 0
    @State private var dragOffset: CGFloat = 0
    @State private var sessionDone = false
    @State private var startedAt = Date()
    @State private var cardsAdvanced = 0
    @State private var didEndSession = false

    var body: some View {
        ZStack {
            Econ.ocean.ignoresSafeArea()
            if sessionDone {
                SessionCompleteView(title: title, cardsCount: cards.count) {
                    dismiss()
                }
                .environmentObject(streak)
                .environmentObject(content)
                .environmentObject(growth)
            } else if cards.isEmpty {
                VStack(spacing: 16) {
                    Text("No cards available.")
                        .foregroundColor(Econ.white)
                    Button("Done") { dismiss() }
                        .buttonStyle(SecondaryButton())
                        .padding(.horizontal, 40)
                }
            } else {
                VStack(spacing: 0) {
                    // Nav bar
                    HStack {
                        Button("✕") { dismiss() }
                            .foregroundColor(Econ.subtext)
                            .font(.title2)
                            // A glyph-sized tap target fails the 44×44 minimum
                            // (design section 12); widen the hit area only.
                            .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                            .accessibilityLabel("Close")
                            .accessibilityIdentifier("cardModeCloseButton")
                        Spacer()
                        Text("\(min(currentIndex + 1, cards.count)) / \(cards.count)")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundColor(Econ.subtext)
                            .accessibilityLabel("Card \(min(currentIndex + 1, cards.count)) of \(cards.count)")
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
                        .accessibilityLabel("Set progress")

                    // Card
                    let card = cards[currentIndex]
                    CardView(card: card, position: currentIndex, cardCount: cards.count,
                             mode: mode)
                        .environmentObject(content)
                        .environmentObject(growth)
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
                                        EBEvents.cardAdvanced(mode: mode, direction: .back,
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
            guard !didAppearOnce else { return }
            didAppearOnce = true
            startedAt = Date()
            EBEvents.sessionStarted(mode: mode, entryPoint: entryPoint, deckSize: cards.count)
        }
        .onDisappear {
            endSession(reason: sessionDone ? .completed : .userExit)
        }
    }

    /// One `session_started_v1` per presentation. SwiftUI can call `onAppear`
    /// again when the cover is re-composed.
    @State private var didAppearOnce = false

    /// Exactly one `session_ended_v1` per presentation, whether the deck was
    /// finished or abandoned.
    private func endSession(reason: EBEndReason) {
        guard !didEndSession else { return }
        didEndSession = true
        EBEvents.sessionEnded(mode: mode,
                              reason: reason,
                              cardsViewed: cardsAdvanced,
                              duration: Date().timeIntervalSince(startedAt),
                              hadBookmark: cards.contains { content.isBookmarked($0.id) },
                              adImpressions: AdManager.shared.impressionCount)
        EBEvents.flush()
    }

    private func advance() {
        let card = cards[currentIndex]
        content.markSeen(card.id)
        streak.noteCardSeen()
        // No ad here. Version 1.1's only interstitial placement is the return
        // from a completed set to Home, never inside a card (design section 9.3).
        // RECONCILED (1.1.2): lineage A emitted `card_viewed` with the card id,
        // the topic id and an exact position. All three are PROHIBITED by the
        // shipped schema — two are content identifiers and the third has a
        // defined bucket. `card_advanced_v1` carries direction and a bucketed
        // depth, which answers the same question without naming the card.
        cardsAdvanced += 1
        EBEvents.cardAdvanced(mode: mode, direction: .forward, depth: cardsAdvanced)
        withAnimation(.easeOut(duration: 0.2)) { dragOffset = 0 }
        if currentIndex < cards.count - 1 {
            currentIndex += 1
        } else {
            sessionDone = true
        }
    }
}
