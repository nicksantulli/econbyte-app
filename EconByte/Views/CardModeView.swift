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
            EconColor.background.ignoresSafeArea()
            if sessionDone {
                SessionCompleteView(title: title, cardsCount: cards.count) {
                    dismiss()
                }
                .environmentObject(streak)
                .environmentObject(content)
                .environmentObject(growth)
            } else if cards.isEmpty {
                VStack(spacing: EconSpace.m) {
                    Text("No cards available.")
                        .font(EconType.body)
                        .foregroundColor(EconColor.textPrimary)
                    Button("Done") { dismiss() }
                        .buttonStyle(SecondaryButton())
                        .padding(.horizontal, EconSpace.xxl)
                }
            } else {
                VStack(spacing: 0) {
                    // Nav bar
                    HStack {
                        // 44 × 44 hit area and the "Close" VoiceOver label come
                        // from `EconIconButton` (design section 12).
                        EconIconButton(systemImage: "xmark", label: "Close",
                                       tint: EconColor.textSecondary) { dismiss() }
                            .accessibilityIdentifier("cardModeCloseButton")
                        Spacer()
                        Text("\(min(currentIndex + 1, cards.count)) / \(cards.count)")
                            .font(EconType.subheadline)
                            .foregroundColor(EconColor.textTertiary)
                            .accessibilityLabel("Card \(min(currentIndex + 1, cards.count)) of \(cards.count)")
                        Spacer()
                        Text(title)
                            .font(EconType.subheadlineEmphasis)
                            .foregroundColor(EconColor.textPrimary)
                            .multilineTextAlignment(.trailing)
                    }
                    .padding(.horizontal, EconSpace.gutter)
                    .padding(.vertical, EconSpace.s)

                    // Progress
                    ProgressView(value: Double(currentIndex + 1), total: Double(cards.count))
                        .tint(EconColor.interactive)
                        .padding(.horizontal, EconSpace.gutter)
                        .padding(.bottom, EconSpace.s)
                        .accessibilityLabel("Set progress")

                    // Card
                    let card = cards[currentIndex]
                    CardView(card: card, position: currentIndex, cardCount: cards.count,
                             mode: mode)
                        .environmentObject(content)
                        .environmentObject(growth)
                        .padding(.horizontal, EconSpace.gutter)
                        .offset(x: dragOffset)
                        // 1.1.5: the card face scrolls vertically, so the deck
                        // swipe only follows mostly horizontal drags; a vertical
                        // drag belongs to the card's scroll view.
                        .gesture(
                            DragGesture(minimumDistance: 20)
                                .onChanged { value in
                                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                                    dragOffset = value.translation.width
                                }
                                .onEnded { value in
                                    guard abs(value.translation.width) > abs(value.translation.height) else {
                                        withAnimation(.spring()) { dragOffset = 0 }
                                        return
                                    }
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
                    Button("Next") { advance() }
                        .buttonStyle(PrimaryButton())
                        .padding(.horizontal, EconSpace.gutter)
                        .padding(.bottom, EconSpace.xxl)
                }
                // Anchored adaptive banner (1.1.3): under the card, never over
                // it — reading, flipping and advancing are never interrupted.
                // Same gating as Home (`EconMonetization.canRequestAds`).
                // Phase 11: a bookmarks review is saved reading — no banner.
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    AdBannerSlot(surface: mode == .bookmarks ? .bookmarksReview : .cardMode,
                                 monetization: growth.monetization)
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
