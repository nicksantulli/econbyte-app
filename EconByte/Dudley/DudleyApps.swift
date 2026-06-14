import SwiftUI

// MARK: - Dudley Studio Kit — portfolio / cross-promo data
//
// The single per-app touch point of the kit. Each app sets `DudleyApps.current`
// to its own id; the "More by Dudley" list filters that one out automatically.
// Add a new row here when a Dudley app ships and every app's About sheet picks
// it up.

/// One app in the Dudley portfolio, for the cross-promo list.
struct DudleyApp: Identifiable {
    let id: String              // stable key, also used as `current`
    let name: String
    let tileColor: Color        // simple letter-tile so we need no bundled icon
    let appStoreID: String?     // nil until the app is live on the App Store

    /// Direct App Store open (skips Safari) when the app is live.
    var storeURL: URL? {
        guard let appStoreID else { return nil }
        return URL(string: "itms-apps://apps.apple.com/app/id\(appStoreID)")
    }
}

enum DudleyApps {
    /// Identifies the app this build belongs to. Set per app.
    static let current = "econbyte"

    /// The full portfolio. Append new apps here as they ship.
    static let all: [DudleyApp] = [
        DudleyApp(id: "powellprowl", name: "Powell Prowl: Rate Chase",
                  tileColor: Color(red: 0.04, green: 0.09, blue: 0.20),
                  appStoreID: "6775539250"),
        DudleyApp(id: "viberater", name: "Vibe Rater",
                  tileColor: Color(red: 0.48, green: 0.18, blue: 0.97),
                  appStoreID: nil),
        DudleyApp(id: "tabletalk", name: "Table Talk",
                  tileColor: Color(red: 0.165, green: 0.608, blue: 0.529),
                  appStoreID: nil),
        DudleyApp(id: "econbyte", name: "EconByte: Daily Economics",
                  tileColor: Color(red: 0.059, green: 0.239, blue: 0.322),
                  appStoreID: nil),
    ]

    /// Apps to cross-promote: everything except the one currently running, and
    /// only those actually live on the App Store.
    static var crossPromo: [DudleyApp] {
        all.filter { $0.id != current && $0.appStoreID != nil }
    }
}

// MARK: - Bundle version helpers

extension Bundle {
    var shortVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    var buildNumber: String {
        infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}
