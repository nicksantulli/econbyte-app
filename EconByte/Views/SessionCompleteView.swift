import SwiftUI

struct SessionCompleteView: View {
    let title: String
    let cardsCount: Int
    let onDone: () -> Void
    @EnvironmentObject private var streak: StreakManager
    @EnvironmentObject private var content: ContentStore

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Text("🔥")
                .font(.system(size: 60))
            Text("Streak: \(streak.currentStreak) day\(streak.currentStreak == 1 ? "" : "s")")
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundColor(Econ.amber)
            Text("You finished \"\(title)\" — \(cardsCount) cards done.")
                .font(.system(size: 17, design: .rounded))
                .foregroundColor(Econ.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            VStack(spacing: 12) {
                Button("Browse More Topics") {
                    onDone()
                }
                .buttonStyle(SecondaryButton())
                Button("Done") { onDone() }
                    .buttonStyle(PrimaryButton())
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }
}
