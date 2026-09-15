import SwiftUI

struct BookmarksView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var content: ContentStore
    @EnvironmentObject private var streak: StreakManager
    @EnvironmentObject private var growth: EconGrowth
    @State private var showReview = false

    var body: some View {
        NavigationStack {
            ZStack {
                EconColor.background.ignoresSafeArea()
                Group {
                    if content.bookmarkedCards.isEmpty {
                        VStack(spacing: EconSpace.m) {
                            Image(systemName: "bookmark.slash")
                                .font(.system(.largeTitle))
                                .foregroundColor(EconColor.textTertiary)
                                .accessibilityHidden(true)
                            Text("No bookmarks yet.")
                                .font(EconType.title3)
                                .foregroundColor(EconColor.textPrimary)
                                .multilineTextAlignment(.center)
                            Text("Tap the bookmark icon on any card to save it.")
                                .font(EconType.subheadline)
                                .foregroundColor(EconColor.textTertiary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, EconSpace.xxl)
                        }
                    } else {
                        VStack(spacing: 0) {
                            Button("Review Saved (\(content.bookmarkedCards.count))") {
                                showReview = true
                            }
                            .buttonStyle(PrimaryButton())
                            .padding(.horizontal, EconSpace.gutter)
                            .padding(.vertical, EconSpace.s)

                            List(content.bookmarkedCards) { card in
                                VStack(alignment: .leading, spacing: EconSpace.xxs) {
                                    Text(content.topicName(for: card.topicId))
                                        .modifier(TopicChip())
                                    Text(card.concept)
                                        .font(EconType.subheadlineEmphasis)
                                        .foregroundColor(EconColor.textPrimary)
                                    Text(card.conceptBody)
                                        .font(EconType.footnote)
                                        .foregroundColor(EconColor.textTertiary)
                                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                                }
                                .listRowBackground(EconColor.surface)
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
                        .foregroundColor(EconColor.interactive)
                }
            }
            .fullScreenCover(isPresented: $showReview) {
                CardModeView(cards: content.bookmarkedCards, title: "Saved Cards",
                             mode: .bookmarks, entryPoint: .bookmarks)
                    .environmentObject(content)
                    .environmentObject(streak)
                    .environmentObject(growth)
            }
        }
        .tint(EconColor.interactive)
    }
}
