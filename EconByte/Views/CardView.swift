import SwiftUI

struct CardView: View {
    let card: EconCard
    @EnvironmentObject private var content: ContentStore
    @State private var isFlipped = false
    @State private var rotation: Double = 0

    var body: some View {
        ZStack {
            if rotation < 90 {
                frontFace
            } else {
                backFace
                    .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
            }
        }
        .rotation3DEffect(.degrees(rotation), axis: (x: 0, y: 1, z: 0))
        .onTapGesture { flip() }
    }

    private func flip() {
        withAnimation(.easeInOut(duration: 0.4)) {
            rotation = isFlipped ? 0 : 180
        }
        isFlipped.toggle()
        if isFlipped { content.markFlipped(card.id) }
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

                Text(card.conceptBody)
                    .font(.system(size: 17, design: .rounded))
                    .foregroundColor(Econ.ink.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }
            Spacer()

            VStack(spacing: 8) {
                Text("For educational purposes only — not financial or investment advice.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(Econ.subtext)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
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

            Text("For educational purposes only — not financial or investment advice.")
                .font(.system(size: 11, design: .rounded))
                .foregroundColor(Econ.subtext)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Econ.page)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 6)
    }

    private var bookmarkButton: some View {
        Button {
            content.toggleBookmark(card.id)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Image(systemName: content.isBookmarked(card.id) ? "bookmark.fill" : "bookmark")
                .foregroundColor(Econ.amber)
                .font(.title3)
        }
    }
}
