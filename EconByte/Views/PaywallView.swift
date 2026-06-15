import SwiftUI
import StoreKit

/// Paywall shown when a free user taps a locked topic. Sells the
/// `com.nsantulli.econbyte.unlockall` non-consumable ($0.99). Price is read
/// from StoreKit (`product.displayPrice`) — never hardcoded — per DUD-186.
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: PurchaseManager
    @State private var working = false

    private var product: Product? { store.product(for: .unlockAll) }

    private var lockedTopicCount: Int {
        let topics = ContentStore.shared.topics
        return topics.filter { !ContentStore.shared.isTopicFree($0.id) }.count
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Econ.ocean.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 24) {
                        Image(systemName: "lock.open.fill")
                            .font(.system(size: 52))
                            .foregroundColor(Econ.amber)
                            .padding(.top, 24)

                        Text("Unlock All Topics")
                            .font(.system(size: 26, weight: .heavy, design: .rounded))
                            .foregroundColor(Econ.white)

                        Text("Inflation and Interest Rates are free. Unlock the remaining \(lockedTopicCount) topics — GDP, Labor Markets, Trade & Tariffs, Recessions and more — with a one-time purchase.")
                            .font(.system(size: 15, design: .rounded))
                            .foregroundColor(Econ.white.opacity(0.75))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)

                        VStack(spacing: 12) {
                            featureRow("checkmark.circle.fill", "Every topic, unlocked forever")
                            featureRow("infinity", "All current and future card packs")
                            featureRow("icloud.and.arrow.down.fill", "Restores across your devices")
                        }
                        .padding(.horizontal, 28)

                        if store.isUnlockAllPurchased {
                            Text("Already unlocked ✓")
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                .foregroundColor(Econ.sky)
                                .padding(.top, 8)
                        } else {
                            Button {
                                buy()
                            } label: {
                                if working {
                                    ProgressView().tint(Econ.ink)
                                } else {
                                    Text("Unlock All — \(product?.displayPrice ?? "$0.99")")
                                }
                            }
                            .buttonStyle(PrimaryButton())
                            .disabled(working)
                            .padding(.horizontal, 28)
                            .padding(.top, 8)

                            Button("Restore Purchases") { restore() }
                                .buttonStyle(SecondaryButton())
                                .disabled(working)
                                .padding(.horizontal, 28)
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("EconByte Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") { dismiss() }.foregroundColor(Econ.sky)
                }
            }
            .onChange(of: store.isUnlockAllPurchased) { unlocked in
                if unlocked { dismiss() }
            }
        }
        .tint(Econ.sky)
        .task { await store.loadProducts() }
    }

    private func featureRow(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(Econ.amber)
                .frame(width: 24)
            Text(text)
                .font(.system(size: 15, design: .rounded))
                .foregroundColor(Econ.white.opacity(0.9))
            Spacer()
        }
    }

    private func buy() {
        working = true
        Task {
            _ = await store.purchase(.unlockAll)
            working = false
        }
    }

    private func restore() {
        working = true
        Task {
            await store.restorePurchases()
            working = false
        }
    }
}
