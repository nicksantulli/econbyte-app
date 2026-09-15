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

    // MARK: Faces (1.1.5 design system)
    //
    // Both faces share `face(header:body:footer:)`: a fixed header row (topic
    // chip + bookmark), a body that ALWAYS scrolls vertically — centred when it
    // is shorter than the card, scrolling when a long definition, an
    // accessibility text size or a card graphic makes it taller — and a fixed
    // footer. Nothing inside the body is ever squeezed to fit: the scroll view
    // proposes unlimited height, so a graphic keeps its natural size. A tap
    // anywhere still flips the card; a vertical drag scrolls; card mode's swipe
    // only reacts to mostly horizontal drags.

    private var frontFace: some View {
        face {
            Text(content.topicName(for: card.topicId))
                .modifier(CardFaceChip())
        } body: {
            // PHASE 20 GRAPHIC SLOT (front face, first in this scrolling stack,
            // above the concept title). The face scrolls, so the graphic always
            // renders at its full natural size; its summary is spoken through
            // `accessibilityLabelText`.
            if let graphic = card.graphic {
                CardGraphicView(spec: graphic)
            }
            Text(card.concept)
                .font(EconType.title)
                .foregroundColor(EconColor.onCardPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(card.conceptBody)
                .font(EconType.body)
                .foregroundColor(EconColor.onCardPrimary.opacity(0.85))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        } footer: {
            if !isFlipped {
                Text("Tap to flip")
                    .font(EconType.footnote)
                    .foregroundColor(EconColor.onCardSecondary)
            }
        }
    }

    private var backFace: some View {
        face {
            Label("Real World", systemImage: "globe.americas.fill")
                .font(EconType.caption.weight(.semibold))
                .foregroundColor(Econ.ocean)
        } body: {
            Text(card.exampleBody)
                .font(EconType.body.weight(.medium))
                .foregroundColor(EconColor.onCardPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline, spacing: EconSpace.xxs) {
                Image(systemName: "link")
                    .font(EconType.caption)
                    .accessibilityHidden(true)
                Text(card.source)
                    .font(EconType.caption)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundColor(EconColor.onCardSecondary)
        } footer: {
            EmptyView()
        }
    }

    private func face<Header: View, FaceBody: View, Footer: View>(
        @ViewBuilder header: () -> Header,
        @ViewBuilder body: () -> FaceBody,
        @ViewBuilder footer: () -> Footer) -> some View {
        let stack = VStack(spacing: EconSpace.m) { body() }
            .padding(.horizontal, EconSpace.xl)
            .padding(.vertical, EconSpace.m)
            .frame(maxWidth: .infinity)
        return VStack(spacing: 0) {
            HStack {
                header()
                Spacer()
                bookmarkButton
            }
            .padding(.leading, EconSpace.xl)
            .padding(.trailing, EconSpace.s)
            .padding(.top, EconSpace.s)

            GeometryReader { geo in
                ScrollView(.vertical, showsIndicators: true) {
                    stack
                        .frame(minHeight: geo.size.height, alignment: .center)
                }
                .accessibilityIdentifier("cardFaceScroll")
            }

            footer()
                .padding(.bottom, EconSpace.l)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(EconColor.cardFace)
        .clipShape(RoundedRectangle(cornerRadius: EconRadius.card, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 16, x: 0, y: 8)
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
                .font(EconType.title3)
                // 44×44 minimum tap target (design section 12).
                .frame(minWidth: EconSize.tapTarget, minHeight: EconSize.tapTarget)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(content.isBookmarked(card.id) ? "Remove bookmark" : "Bookmark card")
        .accessibilityIdentifier("cardBookmarkButton")
    }
}
