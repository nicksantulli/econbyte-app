import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("notificationsEnabled") private var notificationsEnabled = false
    @EnvironmentObject private var streak: StreakManager

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
                        Link("Rate EconByte", destination: URL(string: "https://apps.apple.com/app/id000000000")!)
                        Link("Privacy Policy", destination: URL(string: "https://dudleyapps.com/privacy")!)
                        DudleyAboutRow()
                    } header: {
                        Text("About")
                    }
                }
                .scrollContentBackground(.hidden)
                .foregroundColor(Econ.white)
            }
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
