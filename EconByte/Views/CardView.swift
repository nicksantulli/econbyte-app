import SwiftUI

struct CardView: View {
    let card: EconCard
    /// Position of this card within the current set, for the `position` property
    /// on card telemetry and for the VoiceOver announcement.
    var position: Int = 0
    /// Number of cards in the current set, announced with `position`.
    var cardCount: Int = 0
    /// Which deck this card is being read in, for `card_flipped_v1`.
    var mode: EBMode = .daily
    @EnvironmentObject private var content: ContentStore
    @EnvironmentObject private var growth: EconGrowth
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isFlipped = false
    @State private var rotation: Double = 0

    /// With Reduce Motion the faces cross-fade, so the swap follows `isFlipped`
    /// directly rather than the halfway point of a rotation that never runs.
    private var showsBackFace: Bool { reduceMotion ? isFlipped : rotation >= 90 }

    var body: some View {
        ZStack {
            if showsBackFace {
                backFace
                    .rotation3DEffect(.degrees(reduceMotion ? 0 : 180), axis: (x: 0, y: 1, z: 0))
                    .transition(reduceMotion ? .opacity : .identity)
            } else {
                frontFace
                    .transition(reduceMotion ? .opacity : .identity)
            }
        }
        .rotation3DEffect(.degrees(reduceMotion ? 0 : rotation), axis: (x: 0, y: 1, z: 0))
        .onTapGesture { flip() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityValue(showsBackFace
                            ? "Showing the real-world example"
                            : "Showing the concept")
        .accessibilityHint("Double tap to flip the card.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { flip() }
        .accessibilityAction(named: Text("Flip card")) { flip() }
    }

    /// Announces topic, position, face, the readable content, and — on the back
    /// — whether a source is attached (design section 12).
    private var accessibilityLabelText: Text {
        let topic = content.topicName(for: card.topicId)
        let place = cardCount > 0
            ? "card \(position + 1) of \(cardCount)"
            : "card \(position + 1)"
        if showsBackFace {
            let source = card.source.isEmpty ? "No source listed." : "Source: \(card.source)."
            return Text("\(topic), \(place). Real-world example. \(card.exampleBody) \(source)")
        }
        return Text("\(topic), \(place). Concept. \(card.concept). \(card.graphic.map { "\($0.accessibilitySummary) " } ?? "")\(card.conceptBody)")
    }

    private func flip() {
        if reduceMotion {
            // Reduce Motion: cross-fade instead of a 3D rotation, and keep
            // `rotation` in step so the two paths cannot disagree.
            withAnimation(.easeInOut(duration: 0.25)) { isFlipped.toggle() }
            rotation = isFlipped ? 180 : 0
            if isFlipped { noteFlipped() }
            return
        }
        withAnimation(.easeInOut(duration: 0.4)) {
            rotation = isFlipped ? 0 : 180
        }
        isFlipped.toggle()
        if isFlipped { noteFlipped() }
    }

    private func noteFlipped() {
        content.markFlipped(card.id)
        // RECONCILED (1.1.2): the card id, the topic id and the exact position
        // are all prohibited by the shipped schema. The difficulty tier is the
        // one property that says something about the card without identifying
        // it, and it comes from the bundled catalog rather than a literal.
        EBEvents.cardFlipped(mode: mode, difficulty: card.difficulty)
    }

    private var frontFace: some View {
        VStack(spacing: 0) {
            // Topic chip
            HStack {
                Text(content.topicName(for: card.topicId))
                    .modifier(TopicChip())
                Spacer()
                bookmarkButton
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)

            Spacer()
            VStack(spacing: 16) {
                Text(card.concept)
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundColor(Econ.ink)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                if let graphic = card.graphic {
                    CardGraphicView(spec: graphic)
                        .padding(.horizontal, 20)
                }

                Text(card.conceptBody)
                    .font(.system(size: 17, design: .rounded))
                    .foregroundColor(Econ.ink.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }
            Spacer()

            VStack(spacing: 8) {
                if !isFlipped {
                    Text("Tap to see example →")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(Econ.subtext)
                }
            }
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Econ.page)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 6)
    }

    private var backFace: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Real World", systemImage: "globe.americas.fill")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(Econ.tide)
                Spacer()
                bookmarkButton
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)

            Spacer()
            VStack(spacing: 16) {
                Text(card.exampleBody)
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundColor(Econ.ink)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                HStack {
                    Image(systemName: "link")
                        .font(.caption)
                    Text(card.source)
                        .font(.system(size: 12, design: .rounded))
                }
                .foregroundColor(Econ.subtext)
            }
            Spacer()
                .frame(minHeight: 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Econ.page)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 6)
    }

    private var bookmarkButton: some View {
        Button {
            content.toggleBookmark(card.id)
            EBEvents.bookmarkChanged(
                action: content.isBookmarked(card.id) ? .added : .removed,
                bookmarkCount: content.bookmarkedCards.count)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Image(systemName: content.isBookmarked(card.id) ? "bookmark.fill" : "bookmark")
                .foregroundColor(Econ.amber)
                .font(.title3)
                // 44×44 minimum tap target (design section 12).
                .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(content.isBookmarked(card.id) ? "Remove bookmark" : "Bookmark card")
        .accessibilityIdentifier("cardBookmarkButton")
    }
}
