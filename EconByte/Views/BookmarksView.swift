import SwiftUI

struct BookmarksView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var content: ContentStore
    @EnvironmentObject private var streak: StreakManager
    @EnvironmentObject private var ads: AdManager
    @State private var showReview = false

    var body: some View {
        NavigationStack {
            ZStack {
                Econ.ocean.ignoresSafeArea()
                Group {
                    if content.bookmarkedCards.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "bookmark.slash")
                                .font(.system(size: 48))
                                .foregroundColor(Econ.subtext)
                            Text("No bookmarks yet.")
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .foregroundColor(Econ.white)
                            Text("Tap the bookmark icon on any card to save it.")
                                .font(.system(size: 14, design: .rounded))
                                .foregroundColor(Econ.subtext)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                    } else {
                        VStack(spacing: 0) {
                            Button("Review Saved (\(content.bookmarkedCards.count))") {
                                showReview = true
                            }
                            .buttonStyle(PrimaryButton())
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)

                            List(content.bookmarkedCards) { card in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(content.topicName(for: card.topicId))
                                        .modifier(TopicChip())
                                    Text(card.concept)
                                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                                        .foregroundColor(Econ.white)
                                    Text(card.conceptBody)
                                        .font(.system(size: 13, design: .rounded))
                                        .foregroundColor(Econ.subtext)
                                        .lineLimit(2)
                                }
                                .listRowBackground(Econ.tide.opacity(0.12))
                            }
                            .listStyle(.plain)
                            .scrollContentBackground(.hidden)
                        }
                    }
                }
            }
            .navigationTitle("Bookmarks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(Econ.sky)
                }
            }
            .fullScreenCover(isPresented: $showReview) {
                CardModeView(cards: content.bookmarkedCards, title: "Saved Cards")
                    .environmentObject(content)
                    .environmentObject(streak)
                    .environmentObject(ads)
            }
        }
        .tint(Econ.sky)
    }
}
