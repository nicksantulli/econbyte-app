import SwiftUI

struct CardModeView: View {
    let cards: [EconCard]
    let title: String
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var content: ContentStore
    @EnvironmentObject private var streak: StreakManager
    @EnvironmentObject private var ads: AdManager
    @State private var currentIndex = 0
    @State private var dragOffset: CGFloat = 0
    @State private var sessionDone = false

    var body: some View {
        ZStack {
            Econ.ocean.ignoresSafeArea()
            if sessionDone {
                SessionCompleteView(title: title, cardsCount: cards.count) {
                    dismiss()
                }
                .environmentObject(streak)
                .environmentObject(content)
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
                    CardView(card: card)
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
    }

    private func advance() {
        let card = cards[currentIndex]
        content.markSeen(card.id)
        streak.noteCardSeen()
        Task { await ads.noteCardSwipe() }
        withAnimation(.easeOut(duration: 0.2)) { dragOffset = 0 }
        if currentIndex < cards.count - 1 {
            currentIndex += 1
        } else {
            sessionDone = true
        }
    }
}
