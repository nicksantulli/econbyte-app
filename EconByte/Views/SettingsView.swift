import SwiftUI
import StoreKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("notificationsEnabled") private var notificationsEnabled = false
    @EnvironmentObject private var streak: StreakManager
    @EnvironmentObject private var store: PurchaseManager
    @State private var working = false

    private var removeAdsProduct: Product? { store.product(for: .removeAds) }

    var body: some View {
        NavigationStack {
            ZStack {
                Econ.ocean.ignoresSafeArea()
                List {
                    Section {
                        Toggle("Daily Streak Reminder", isOn: $notificationsEnabled)
                            .onChange(of: notificationsEnabled) { val in
                                if val { streak.requestNotificationPermission() }
                            }
                            .tint(Econ.amber)
                    } header: {
                        Text("Notifications")
                    }
                    Section {
                        if store.isRemoveAdsPurchased {
                            HStack {
                                Text("Remove Ads")
                                Spacer()
                                Text("Purchased ✓").foregroundColor(Econ.sky)
                            }
                        } else {
                            Button {
                                working = true
                                Task {
                                    _ = await store.purchase(.removeAds)
                                    working = false
                                }
                            } label: {
                                HStack {
                                    Text("Remove Ads")
                                    Spacer()
                                    if working {
                                        ProgressView()
                                    } else {
                                        Text(removeAdsProduct?.displayPrice ?? "$0.99")
                                            .foregroundColor(Econ.amber)
                                    }
                                }
                            }
                            .disabled(working)
                        }
                        if !store.isUnlockAllPurchased {
                            HStack {
                                Text("Unlock All Topics")
                                Spacer()
                                Text(store.product(for: .unlockAll)?.displayPrice ?? "$0.99")
                                    .foregroundColor(Econ.subtext)
                            }
                            .foregroundColor(Econ.subtext)
                        }
                        Button("Restore Purchases") {
                            working = true
                            Task {
                                await store.restorePurchases()
                                working = false
                            }
                        }
                        .disabled(working)
                    } header: {
                        Text("EconByte Pro")
                    } footer: {
                        Text("One-time purchases. Restore re-syncs anything you've bought with your Apple ID across devices.")
                    }
                    #if DEBUG
                    Section {
                        Toggle("🧪 Unlock All Topics", isOn: Binding(
                            get: { store.isUnlockAllPurchased },
                            set: { store.debugSetUnlockAll($0) }))
                            .tint(Econ.amber)
                        Toggle("🧪 Remove Ads", isOn: Binding(
                            get: { store.isRemoveAdsPurchased },
                            set: { store.debugSetRemoveAds($0) }))
                            .tint(Econ.amber)
                    } header: {
                        Text("Debug — test only")
                    } footer: {
                        Text("DEBUG builds only. Flips entitlements without a real purchase so you can test locked vs unlocked in the Simulator. Stripped from release builds.")
                    }
                    #endif
                    Section {
                        Link("Rate EconByte", destination: URL(string: "https://dudleyapps.com")!)
                        Link("Privacy Policy", destination: URL(string: "https://dudleyapps.com/privacy")!)
                        DudleyAboutRow()
                    } header: {
                        Text("About")
                    }
                }
                .scrollContentBackground(.hidden)
                .foregroundColor(Econ.white)
            }
            .task { await store.loadProducts() }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(Econ.sky)
                }
            }
        }
        .tint(Econ.sky)
    }
}
