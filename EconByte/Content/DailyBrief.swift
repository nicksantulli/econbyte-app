import Foundation

// MARK: - Daily Economic Brief (1.1.4, EconByte Pro)
//
// A brief is a small JSON document produced once per U.S. business day by a
// server job (`docs/daily-brief/SERVER.md`) that reads ONLY official releases
// and open-licence statistical data — never a commercial news site — and writes
// its own plain-English sentences about public facts. The app never fetches,
// parses, or summarizes anything itself: it downloads the finished document from
// the EconByte brief service (`BriefStore.latestURL`), validates it, caches the
// last 30, and falls back to the bundled sample when nothing else is available.
//
// The model is deliberately strict. A brief that cites a host outside
// `DailyBrief.allowedHosts`, lacks its disclaimer, or is missing one of the three
// sections is rejected before it can be shown — so a defect on the server side
// degrades to yesterday's brief (or the sample), never to unsourced text.

public enum BriefSectionType: String, Codable, Hashable {
    /// "What was released": numbers from official releases, with sources.
    case released
    /// "Scheduled this week": the official release calendar.
    case scheduled
    /// "One concept to know": a link into a card or a lesson.
    case concept
}

public struct BriefFigure: Codable, Hashable {
    public let label: String
    public let value: String
}

public struct BriefSource: Codable, Hashable {
    public let organization: String
    public let documentTitle: String
    public let url: String
    /// ISO-8601 timestamp of when the server read the page.
    public let retrievedAt: String
}

/// One entry of a `released` or `scheduled` section. The two shapes share a
/// type because the JSON puts both under `items`; `DailyBrief.validate` checks
/// the fields each section type requires.
public struct BriefItem: Codable, Hashable, Identifiable {
    // released
    public let title: String?
    public let releaseDate: String?
    public let summary: String?
    public let meaning: String?
    public let figures: [BriefFigure]?
    public let source: BriefSource?
    // scheduled
    public let date: String?
    public let organization: String?
    public let url: String?

    public var id: String { "\(title ?? "")|\(releaseDate ?? date ?? "")|\(url ?? source?.url ?? "")" }
}

public struct BriefSection: Codable, Hashable, Identifiable {
    public let type: BriefSectionType
    public let title: String
    public let items: [BriefItem]?
    // concept
    public let conceptTitle: String?
    public let text: String?
    public let linkedCardID: String?
    public let linkedLessonID: String?

    public var id: String { type.rawValue }
}

public struct DailyBrief: Codable, Hashable, Identifiable {
    public let schemaVersion: Int
    /// The business day the brief covers, `YYYY-MM-DD`.
    public let briefDate: String
    public let publishedAt: String
    /// True on the bundled sample so the UI can say so.
    public let isSample: Bool?
    public let headline: String
    public let sections: [BriefSection]
    public let disclaimer: String
    public let methodology: String

    public var id: String { briefDate }

    public func section(_ type: BriefSectionType) -> BriefSection? {
        sections.first { $0.type == type }
    }

    /// How a brief gets published, as the "How this brief is made" screen states
    /// it. Must match the brief service (`docs/daily-brief/SERVER.md`).
    public static let publishingProcess: [String] = [
        "Sources: official statistical releases and central-bank publications only — never news articles or headlines.",
        "Drafting: an AI model writes the plain-English text from the releases' own words and tables, and nothing else.",
        "Checks before publishing: the document format, every source link, every number against the release text, and a second, independent fact-check. A brief that fails is not published; the previous one stays.",
        "Schedule: each U.S. federal business day, at 11:30 a.m. and 5:30 p.m. New York time (the later run only when new releases are out). No briefs on weekends or federal holidays.",
        "Delivered from the EconByte brief service; the app keeps the latest 30 briefs for offline reading.",
    ]

    /// The free teaser: the headline plus the first released item. Everything
    /// else is Pro.
    public var teaserItem: BriefItem? { section(.released)?.items?.first }

    /// Hosts a brief may cite: official statistical releases and central-bank
    /// publications with public-domain or open reuse terms. Mirrors
    /// `BRIEF_HOSTS` in `scripts/validate_content.mjs` and the allow-list in
    /// `docs/daily-brief/SERVER.md`. No news publisher is ever on this list.
    public static let allowedHosts: Set<String> = [
        "www.bls.gov", "www.bea.gov", "www.census.gov", "home.treasury.gov",
        "fiscaldata.treasury.gov", "www.treasurydirect.gov", "www.federalreserve.gov",
        "fred.stlouisfed.org", "www.cbo.gov", "www.eia.gov",
        "www.ecb.europa.eu", "www.bankofengland.co.uk", "ec.europa.eu", "www.ons.gov.uk",
        "www150.statcan.gc.ca", "www.statcan.gc.ca", "www.imf.org", "www.worldbank.org",
        "www.oecd.org", "www.bis.org",
    ]

    /// Bundled samples are every `brief-sample-YYYY-MM-DD.json` in the app
    /// bundle (Phase 13: the five most recent U.S. business days with official
    /// releases). They are discovered by prefix, so adding or retiring a sample
    /// is a resource change only.
    public static let sampleResourcePrefix = "brief-sample-"

    /// Decodes and validates a brief document. Fails closed.
    public static func decodeValidated(_ data: Data) throws -> DailyBrief {
        let brief: DailyBrief
        do {
            brief = try JSONDecoder().decode(DailyBrief.self, from: data)
        } catch {
            throw CurriculumError.decodingFailed(String(describing: error))
        }
        try validate(brief)
        return brief
    }

    /// URLs of the bundled sample briefs, newest file name (= date) first.
    public static func bundledSampleURLs(in bundle: Bundle = .curriculumBundle) -> [URL] {
        (bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])
            .filter { $0.deletingPathExtension().lastPathComponent.hasPrefix(sampleResourcePrefix) }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// Every bundled sample that decodes and validates, newest `briefDate`
    /// first. Written for the 1.1.4 lane from official releases (see each
    /// file's own sources), present in every build so the News tab and its
    /// archive are never empty, and labelled as samples. A sample that fails
    /// validation is skipped, never shown (the content tests fail first).
    public static func loadBundledSamples(in bundle: Bundle = .curriculumBundle) -> [DailyBrief] {
        bundledSampleURLs(in: bundle)
            .compactMap { url in (try? Data(contentsOf: url)).flatMap { try? decodeValidated($0) } }
            .sorted { $0.briefDate > $1.briefDate }
    }

    /// The newest bundled sample.
    public static func loadBundledSample(in bundle: Bundle = .curriculumBundle) throws -> DailyBrief {
        guard let url = bundledSampleURLs(in: bundle).first else {
            throw CurriculumError.resourceMissing("\(sampleResourcePrefix)*.json")
        }
        return try decodeValidated(try Data(contentsOf: url))
    }

    static func validate(_ brief: DailyBrief) throws {
        func fail(_ reason: String) throws -> Never {
            throw CurriculumError.validationFailed(reason)
        }
        func isISODate(_ s: String) -> Bool {
            s.count == 10 && s[s.index(s.startIndex, offsetBy: 4)] == "-" && s[s.index(s.startIndex, offsetBy: 7)] == "-"
                && s.filter(\.isNumber).count == 8
        }
        func checkHost(_ raw: String, _ site: String) throws {
            guard let url = URL(string: raw), url.scheme == "https", let host = url.host else {
                try fail("\(site) cites a non-https or unparseable URL")
            }
            guard allowedHosts.contains(host) else {
                try fail("\(site) cites \(host), which is not an allowed brief source")
            }
        }

        guard brief.schemaVersion == 1 else { try fail("unsupported brief schemaVersion \(brief.schemaVersion)") }
        guard isISODate(brief.briefDate) else { try fail("briefDate must be YYYY-MM-DD") }
        guard !brief.headline.isEmpty else { try fail("brief has no headline") }
        guard brief.disclaimer.localizedCaseInsensitiveContains("advice") else {
            try fail("brief disclaimer must state it is not investment advice")
        }
        guard brief.methodology.localizedCaseInsensitiveContains("primary") else {
            try fail("brief methodology must describe the primary-source method")
        }
        let types = Set(brief.sections.map(\.type))
        guard types.isSuperset(of: [.released, .scheduled, .concept]) else {
            try fail("brief is missing a required section")
        }
        for section in brief.sections {
            guard !section.title.isEmpty else { try fail("a brief section has no title") }
            switch section.type {
            case .released:
                guard let items = section.items, !items.isEmpty else { try fail("released section has no items") }
                for item in items {
                    guard let title = item.title, !title.isEmpty, let summary = item.summary, !summary.isEmpty,
                          let date = item.releaseDate, isISODate(date) else {
                        try fail("a released item is missing its title, summary, or release date")
                    }
                    guard let figures = item.figures, !figures.isEmpty,
                          figures.allSatisfy({ !$0.label.isEmpty && !$0.value.isEmpty }) else {
                        try fail("released item \(title) has no figures")
                    }
                    guard let source = item.source, !source.organization.isEmpty,
                          !source.documentTitle.isEmpty, !source.retrievedAt.isEmpty else {
                        try fail("released item \(title) has no complete source")
                    }
                    try checkHost(source.url, "released item \(title)")
                }
            case .scheduled:
                guard let items = section.items, !items.isEmpty else { try fail("scheduled section has no items") }
                for item in items {
                    guard let title = item.title, !title.isEmpty, let date = item.date, isISODate(date),
                          let organization = item.organization, !organization.isEmpty, let url = item.url else {
                        try fail("a scheduled item is missing its title, date, organization, or URL")
                    }
                    try checkHost(url, "scheduled item \(title)")
                }
            case .concept:
                guard let title = section.conceptTitle, !title.isEmpty, let text = section.text, !text.isEmpty else {
                    try fail("concept section is missing its title or text")
                }
                guard (section.linkedCardID ?? "").isEmpty == false || (section.linkedLessonID ?? "").isEmpty == false else {
                    try fail("concept section links neither a card nor a lesson")
                }
            }
        }
    }
}
