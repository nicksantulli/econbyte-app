import Foundation

/// Owns the Daily Brief on the device (1.1.4).
///
/// Order of preference: the newest validated brief in the on-device cache, then
/// the bundled samples (newest first; the older samples fill the archive).
/// `refresh()` fetches `latest.json` from the brief service (`baseURL`),
/// validates it fail-closed, stores it in the cache (which keeps the most recent
/// 30 briefs by date), publishes it, and then reads `index.json` to fill the
/// archive with published briefs the device does not have yet. Fetched briefs
/// never carry the SAMPLE badge; the bundled samples do, and they are never
/// mixed into an archive of published briefs. Every failure — offline,
/// 404 while the server job does not exist yet, a document that fails
/// validation — is silent to the reader beyond a small caption: the screen keeps
/// showing what it already had. No user data is sent; the request is a plain
/// GET of a public file through an ephemeral session with no cookies.
@MainActor
final class BriefStore: ObservableObject {

    static let shared: BriefStore = {
        #if DEBUG
        // `-econBriefOffline`: UI tests that assert the bundled samples never
        // reach the live service.
        if ProcessInfo.processInfo.arguments.contains("-econBriefOffline") {
            return BriefStore(endpoint: URL(string: "https://offline.invalid/latest.json")!)
        }
        #endif
        return BriefStore()
    }()

    /// The EconByte brief service's public base URL — the ONE place it is set
    /// (Lane B, live 2026-09-15). Serves `latest.json`, `index.json` and
    /// `archive/<YYYY-MM-DD>.json`.
    nonisolated static let baseURL = URL(string: "https://econbyte-brief-production.up.railway.app/")!
    nonisolated static var latestURL: URL { baseURL.appendingPathComponent("latest.json") }
    nonisolated static var indexURL: URL { baseURL.appendingPathComponent("index.json") }
    /// Published briefs pulled into the archive per refresh, newest first.
    static let archiveFetchLimit = 14
    static let cacheLimit = 30
    /// How often a new brief is published, as the paywall states it (A5, A14).
    /// Must match the brief service's real schedule.
    static let cadenceDescription = "each U.S. federal business day"
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
    private let indexEndpoint: URL
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
        self.indexEndpoint = endpoint.deletingLastPathComponent().appendingPathComponent("index.json")
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
            let samples = DailyBrief.loadBundledSamples(in: bundle)
            latest = samples.first
            history = Array(samples.dropFirst())
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
                    ? "No brief published yet."
                    : "Couldn't download the latest brief."
                return
            }
            let brief = try DailyBrief.decodeValidated(data)
            guard brief.isSample != true else {
                // A sample is never published over, or next to, real briefs.
                refreshNote = nil
                return
            }
            store(brief)
            if let current = latest, current.briefDate > brief.briefDate, source != .bundled {
                // Never replace a newer cached brief with an older one.
                refreshNote = nil
            } else {
                latest = brief
                source = .network
                refreshNote = nil
            }
            await refreshArchive()
            if let shown = latest {
                history = loadCache().filter { $0.briefDate != shown.briefDate }
            }
        } catch is CurriculumError {
            refreshNote = "Showing the last good brief."
            NSLog("[BriefStore] brief failed validation")
        } catch {
            refreshNote = "Offline — showing the last saved brief."
            NSLog("[BriefStore] refresh failed: \(error.localizedDescription)")
        }
    }

    /// Reads `index.json` and caches published briefs this device is missing.
    /// Best effort: any failure leaves the archive as it was.
    private func refreshArchive() async {
        guard let result = try? await session.data(for: Self.request(indexEndpoint)),
              (result.1 as? HTTPURLResponse)?.statusCode == 200 else { return }
        let have = Set(cachedDates)
        let missing = BriefIndex.entries(from: result.0, base: indexEndpoint.deletingLastPathComponent())
            .filter { !$0.isSample && !have.contains($0.briefDate) }
            .prefix(Self.archiveFetchLimit)
        for entry in missing {
            guard let fetched = try? await session.data(for: Self.request(entry.url)),
                  (fetched.1 as? HTTPURLResponse)?.statusCode == 200,
                  let brief = try? DailyBrief.decodeValidated(fetched.0),
                  brief.briefDate == entry.briefDate, brief.isSample != true else { continue }
            store(brief)
        }
    }

    private static func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    /// The SAMPLE badge belongs to the bundled samples only — never to a brief
    /// fetched from the service (even one that sets `isSample`).
    func showsSampleBadge(_ brief: DailyBrief) -> Bool {
        source == .bundled && brief.isSample == true
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

/// One entry of the brief service's `index.json`.
struct BriefIndexEntry: Equatable {
    let briefDate: String
    let url: URL
    /// The service lists the app's samples too; the archive skips them.
    var isSample = false
}

/// Reads `index.json` tolerantly — `{"briefs": [{"briefDate", "url": "/archive/<date>.json",
/// "isSample"}]}` (the live service), `{"dates": [...]}` or a bare array of dates
/// (resolved to `archive/<date>.json`) — and keeps only well-formed dates whose
/// file lives on the service's own host over HTTPS.
enum BriefIndex {
    static func entries(from data: Data, base: URL) -> [BriefIndexEntry] {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return [] }
        var raw: [Any] = []
        if let array = json as? [Any] {
            raw = array
        } else if let object = json as? [String: Any] {
            // `briefs` (with isSample) wins over the bare `dates` list.
            raw = (object["briefs"] as? [Any]) ?? (object["items"] as? [Any])
                ?? (object["archive"] as? [Any]) ?? (object["dates"] as? [Any]) ?? []
        }
        var seen = Set<String>()
        let entries = raw.compactMap { item -> BriefIndexEntry? in
            var date: String?
            var path: String?
            var sample = false
            if let string = item as? String {
                date = string
            } else if let object = item as? [String: Any] {
                date = (object["briefDate"] as? String) ?? (object["date"] as? String)
                path = (object["url"] as? String) ?? (object["path"] as? String) ?? (object["file"] as? String)
                sample = (object["isSample"] as? Bool) ?? false
            }
            guard let date, isISODate(date), !seen.contains(date) else { return nil }
            let resolved = path.flatMap { URL(string: $0, relativeTo: base)?.absoluteURL }
                ?? base.appendingPathComponent("archive").appendingPathComponent("\(date).json")
            guard resolved.scheme == "https", resolved.host == base.host else { return nil }
            seen.insert(date)
            return BriefIndexEntry(briefDate: date, url: resolved, isSample: sample)
        }
        return entries.sorted { $0.briefDate > $1.briefDate }
    }

    static func isISODate(_ s: String) -> Bool {
        let parts = s.split(separator: "-")
        return s.count == 10 && parts.count == 3 && parts[0].count == 4 && parts[1].count == 2 && parts[2].count == 2
            && s.filter(\.isNumber).count == 8
    }
}
