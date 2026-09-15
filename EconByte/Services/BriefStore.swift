import Foundation

/// Owns the Daily Brief on the device (1.1.4).
///
/// Order of preference: the newest validated brief in the on-device cache, then
/// the bundled sample. `refresh()` fetches `latest.json` from the static
/// endpoint, validates it fail-closed, stores it in the cache (which keeps the
/// most recent 30 briefs by date), and publishes it. Every failure — offline,
/// 404 while the server job does not exist yet, a document that fails
/// validation — is silent to the reader beyond a small caption: the screen keeps
/// showing what it already had. No user data is sent; the request is a plain
/// GET of a public file through an ephemeral session with no cookies.
@MainActor
final class BriefStore: ObservableObject {

    static let shared = BriefStore()

    /// The published location of the latest brief. May 404 until the server job
    /// (a follow-up lane) exists; the app is built to treat that as "no news".
    static let latestURL = URL(string: "https://dudleyapps.com/econbyte/brief/latest.json")!
    static let cacheLimit = 30
    /// A refresh is attempted at most this often, so opening the screen
    /// repeatedly is not a request each time.
    static let minimumRefreshInterval: TimeInterval = 60 * 60

    @Published private(set) var latest: DailyBrief?
    @Published private(set) var source: EBBriefSource = .bundled
    @Published private(set) var isRefreshing = false
    /// A short, non-technical reason the latest fetch did not replace the brief
    /// on screen (shown as a caption). `nil` after a successful refresh.
    @Published private(set) var refreshNote: String?
    /// Older cached briefs, newest first, excluding `latest`.
    @Published private(set) var history: [DailyBrief] = []

    private let endpoint: URL
    private let session: URLSession
    private let cacheDirectory: URL
    private let now: () -> Date
    private var lastAttempt: Date?

    init(endpoint: URL = BriefStore.latestURL,
         session: URLSession = BriefStore.makeSession(),
         cacheDirectory: URL? = nil,
         bundle: Bundle = .curriculumBundle,
         now: @escaping () -> Date = Date.init) {
        self.endpoint = endpoint
        self.session = session
        self.now = now
        self.cacheDirectory = cacheDirectory ?? BriefStore.defaultCacheDirectory()
        reloadFromDisk(bundle: bundle)
    }

    nonisolated static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }

    nonisolated static func defaultCacheDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("briefs", isDirectory: true)
    }

    // MARK: Loading

    private func reloadFromDisk(bundle: Bundle) {
        let cached = loadCache()
        if let newest = cached.first {
            latest = newest
            history = Array(cached.dropFirst())
            source = .cache
        } else {
            latest = try? DailyBrief.loadBundledSample(in: bundle)
            history = []
            source = .bundled
        }
    }

    /// Every validated brief on disk, newest first. A file that fails to
    /// decode or validate is skipped (and left in place for a later version to
    /// interpret), never shown.
    private func loadCache() -> [DailyBrief] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: cacheDirectory,
                                                                        includingPropertiesForKeys: nil) else { return [] }
        let briefs = files.filter { $0.pathExtension == "json" }.compactMap { url -> DailyBrief? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? DailyBrief.decodeValidated(data)
        }
        return briefs.sorted { $0.briefDate > $1.briefDate }
    }

    // MARK: Refresh

    /// Fetches the latest brief if enough time has passed since the last try.
    /// `force` ignores the interval (pull to refresh).
    func refreshIfNeeded(force: Bool = false) async {
        if !force, let last = lastAttempt, now().timeIntervalSince(last) < Self.minimumRefreshInterval { return }
        await refresh()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        lastAttempt = now()
        defer { isRefreshing = false }
        do {
            var request = URLRequest(url: endpoint)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            guard http.statusCode == 200 else {
                refreshNote = http.statusCode == 404
                    ? "No published brief yet — showing the bundled sample."
                    : "The latest brief could not be downloaded."
                return
            }
            let brief = try DailyBrief.decodeValidated(data)
            store(brief)
            if let current = latest, current.briefDate > brief.briefDate, current.isSample != true {
                // Never replace a newer cached brief with an older one.
                refreshNote = nil
                return
            }
            latest = brief
            source = .network
            history = loadCache().filter { $0.briefDate != brief.briefDate }
            refreshNote = nil
        } catch is CurriculumError {
            refreshNote = "The downloaded brief did not pass validation; showing the last good one."
            NSLog("[BriefStore] brief failed validation")
        } catch {
            refreshNote = "You're offline — showing the most recent brief."
            NSLog("[BriefStore] refresh failed: \(error.localizedDescription)")
        }
    }

    // MARK: Cache

    private func store(_ brief: DailyBrief) {
        do {
            try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            let url = cacheDirectory.appendingPathComponent("\(brief.briefDate).json")
            let data = try JSONEncoder().encode(brief)
            try data.write(to: url, options: .atomic)
            prune()
        } catch {
            NSLog("[BriefStore] cache write failed: \(error.localizedDescription)")
        }
    }

    /// Keeps the newest `cacheLimit` briefs by date; the filename is the date.
    private func prune() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: cacheDirectory,
                                                                        includingPropertiesForKeys: nil) else { return }
        let sorted = files.filter { $0.pathExtension == "json" }
            .sorted { $0.deletingPathExtension().lastPathComponent > $1.deletingPathExtension().lastPathComponent }
        for stale in sorted.dropFirst(Self.cacheLimit) {
            try? FileManager.default.removeItem(at: stale)
        }
    }

    /// Cached brief dates, newest first — exposed for tests.
    var cachedDates: [String] {
        loadCache().map(\.briefDate)
    }

    #if DEBUG
    func debugClearCache() {
        try? FileManager.default.removeItem(at: cacheDirectory)
        reloadFromDisk(bundle: .curriculumBundle)
    }
    #endif
}
