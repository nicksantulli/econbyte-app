import XCTest
import SwiftUI
import UIKit
@testable import EconByte

/// 1.1.5 card graphics gate (`docs/content/CARD-GRAPHICS-1.1.5.md`).
///
/// Every card in both catalogs decodes, every card carries a graphic, and every
/// graphic satisfies the structural contract, uses real SF Symbols, states only
/// numbers its basis allows, reads aloud, and renders in light, dark and at a
/// large text size. The content checker (`scripts/card_graphics.mjs`) goes
/// further — it re-resolves real data and recomputes formulas — and must pass
/// before content lands; this is the build-time backstop.
final class CardGraphicsTests: XCTestCase {

    private func catalogs() throws -> (core: Curriculum, packs: PackCurriculum) {
        let core = try CurriculumCatalog.loadValidated()
        return (core, try PackCatalog.loadValidated(core: core))
    }

    private func allCards() throws -> [CurriculumCard] {
        let (core, packs) = try catalogs()
        return core.allCards + packs.allCards
    }

    // MARK: - Decoding and coverage

    func testEveryCardInBothCatalogsDecodes() throws {
        let (core, packs) = try catalogs()
        XCTAssertEqual(core.allCards.count, 180)
        XCTAssertEqual(packs.allCards.count, 288)
    }

    func testEveryCardCarriesAGraphic() throws {
        let missing = try allCards().filter { $0.graphic == nil }.map(\.cardID)
        XCTAssertEqual(missing, [], "cards without a graphic")
    }

    @MainActor
    func testTheRuntimeStorePassesEveryGraphicThrough() throws {
        let store = ContentStore.shared
        XCTAssertNil(store.loadError)
        XCTAssertNil(store.packLoadError)
        let byID = Dictionary(uniqueKeysWithValues: try allCards().map { ($0.cardID, $0.graphic) })
        XCTAssertEqual(store.everyCard.count, 468)
        for card in store.everyCard {
            XCTAssertEqual(card.graphic, byID[card.id] ?? nil, card.id)
        }
    }

    // MARK: - Contract

    func testEveryGraphicSatisfiesTheContract() throws {
        var failures: [String] = []
        for card in try allCards() {
            guard let graphic = card.graphic else { continue }
            let problems = graphic.validationProblems()
            if !problems.isEmpty { failures.append("\(card.cardID): \(problems.joined(separator: "; "))") }
        }
        XCTAssertEqual(failures, [], failures.joined(separator: "\n"))
    }

    func testEveryIconIsARealSFSymbol() throws {
        var failures: [String] = []
        for card in try allCards() {
            for item in card.graphic?.icons?.items ?? [] where UIImage(systemName: item.symbol) == nil {
                failures.append("\(card.cardID): \(item.symbol)")
            }
        }
        XCTAssertEqual(failures, [])
    }

    /// The accuracy core, mirrored from the content checker: a `fromCard`,
    /// `computed` or `sourced` graphic may display a number only if the card's
    /// prose states it, a `derived` entry computes it, or the plotted data
    /// contains it. A `conceptual` graphic displays none (`validationProblems`).
    func testDisplayedNumbersAreBackedByTheCardOrTheData() throws {
        var failures: [String] = []
        for card in try allCards() {
            guard let graphic = card.graphic,
                  [.fromCard, .computed, .sourced].contains(graphic.basis) else { continue }
            var allowed = Self.numbers(in: "\(card.title) \(card.definition) \(card.example)", prose: true)
            allowed += (graphic.derived ?? []).map(\.value)
            allowed += (graphic.line?.series ?? []).flatMap { $0.points.flatMap { $0 } }
            allowed += (graphic.bars?.items ?? []).map(\.value)
            allowed += (graphic.proportion.map { [$0.total] + $0.segments.map(\.value) } ?? [])
            allowed += (graphic.line?.references ?? []).map(\.y)
            if graphic.basis == .fromCard {
                // Bar and proportion values themselves must come from the prose.
                let prose = Self.numbers(in: "\(card.title) \(card.definition) \(card.example)", prose: true)
                    + (graphic.derived ?? []).map(\.value)
                for value in (graphic.bars?.items ?? []).map(\.value) + (graphic.proportion?.segments ?? []).map(\.value)
                where !Self.contains(prose, value) {
                    failures.append("\(card.cardID): value \(value) is not in the card")
                }
            }
            for text in graphic.displayStrings {
                let cleaned = text.replacingOccurrences(of: "12-month", with: "twelve-month")
                for number in Self.numbers(in: cleaned, prose: false) where !Self.contains(allowed, number) {
                    failures.append("\(card.cardID): \"\(text)\" shows \(number)")
                }
            }
        }
        XCTAssertEqual(failures, [], failures.joined(separator: "\n"))
    }

    func testDerivedArithmeticHolds() throws {
        for card in try allCards() {
            for derived in card.graphic?.derived ?? [] {
                let value = try XCTUnwrap(Self.evaluate(derived.expr), "\(card.cardID): \(derived.expr)")
                XCTAssertEqual(derived.value, value, accuracy: max(abs(value) * 0.005, 0.05), "\(card.cardID): \(derived.expr)")
            }
        }
    }

    func testGraphicTextFollowsTheHouseRules() throws {
        let stale = ["currently", "today", "nowadays", "recently", "at present", "these days",
                     "this year", "last year", "right now", "as of now"]
        let advice = ["should buy", "should sell", "invest in", "buy now", "sell now", "guaranteed return",
                      "we recommend", "best investment", "beat the market", "portfolio allocation", "price target"]
        var failures: [String] = []
        for card in try allCards() {
            for text in card.graphic?.displayStrings ?? [] {
                let lower = text.lowercased()
                for word in stale where lower.range(of: "\\b\(word)\\b", options: .regularExpression) != nil {
                    failures.append("\(card.cardID): stale \"\(word)\" in \"\(text)\"")
                }
                for phrase in advice where lower.contains(phrase) {
                    failures.append("\(card.cardID): advice \"\(phrase)\" in \"\(text)\"")
                }
                for match in Self.matches(of: #"\b(\d{4})\b"#, in: text) {
                    if let year = Int(match), year > 2026, year < 2200 { failures.append("\(card.cardID): year \(year)") }
                }
            }
        }
        XCTAssertEqual(failures, [], failures.joined(separator: "\n"))
    }

    func testEveryGraphicHasASpokenSummaryAndABasisFootnote() throws {
        for card in try allCards() {
            guard let graphic = card.graphic else { continue }
            let summary = graphic.accessibilitySummary
            XCTAssertTrue(summary.hasPrefix("Graphic: \(graphic.title)."), card.cardID)
            XCTAssertGreaterThan(summary.count, graphic.title.count + 20, "\(card.cardID) summary is too thin")
            switch graphic.basis {
            case .conceptual:   XCTAssertEqual(graphic.footnote, graphic.note, card.cardID)
            case .fromCard:     XCTAssertTrue(graphic.footnote?.hasPrefix("Figures from this card's source") == true, card.cardID)
            case .fromLesson:   XCTFail("\(card.cardID): a card graphic never uses the lesson basis")
            case .computed:     XCTAssertTrue(graphic.footnote?.hasPrefix("Computed from this card's figures") == true, card.cardID)
            case .sourced:      XCTAssertTrue(graphic.footnote?.hasPrefix("Source: ") == true, card.cardID)
            case .illustrative: XCTAssertTrue(graphic.footnote?.hasPrefix("Illustrative, not real data") == true, card.cardID)
            }
        }
    }

    /// No two diagram labels overlap at the size the card draws them (the
    /// plate's plot at iPhone 17 width on the scrolling card face), for every
    /// diagram in both catalogs.
    func testDiagramLabelsNeverOverlap() throws {
        var failures: [String] = []
        for card in try allCards() {
            guard let diagram = card.graphic?.diagram else { continue }
            for size in [CGSize(width: 290, height: 132)] {
                let placed = DiagramLabelLayout.place(diagram, in: size)
                for (i, a) in placed.enumerated() {
                    for b in placed[(i + 1)...] where a.rect.intersects(b.rect) {
                        failures.append("\(card.cardID) @\(Int(size.height)): \"\(a.text)\" overlaps \"\(b.text)\"")
                    }
                }
            }
        }
        XCTAssertEqual(failures, [], failures.joined(separator: "\n"))
    }

    // MARK: - The validator rejects defects

    private func spec(_ json: String) throws -> CardGraphicSpec {
        try JSONDecoder().decode(CardGraphicSpec.self, from: Data(json.utf8))
    }

    func testAnUnknownKindFailsDecoding() {
        XCTAssertThrowsError(try spec(#"{"kind":"pie","title":"T","basis":"conceptual"}"#))
    }

    func testAnUnknownBasisFailsDecoding() {
        XCTAssertThrowsError(try spec(#"{"kind":"flow","title":"T","basis":"vibes","flow":{"layout":"chain","steps":[{"title":"A"},{"title":"B"}]}}"#))
    }

    func testValidatorRejectsDigitsInAConceptualGraphic() throws {
        let s = try spec(#"{"kind":"flow","title":"Two steps","basis":"conceptual","flow":{"layout":"chain","steps":[{"title":"Rates rise 2%"},{"title":"Spending slows"}]}}"#)
        XCTAssertTrue(s.validationProblems().contains { $0.contains("conceptual graphic shows no numbers") })
    }

    func testValidatorRejectsAnOutOfOrderTimeline() throws {
        let s = try spec(#"{"kind":"timeline","title":"Order","basis":"fromCard","timeline":{"events":[{"when":"Mar 15, 1933","label":"B"},{"when":"Mar 6, 1933","label":"A"}]}}"#)
        XCTAssertTrue(s.validationProblems().contains { $0.contains("out of order") })
        XCTAssertLessThan(CardGraphicSpec.dateKey("Mar 6, 1933")!, CardGraphicSpec.dateKey("Mar 15, 1933")!)
        XCTAssertLessThan(CardGraphicSpec.dateKey("1933")!, CardGraphicSpec.dateKey("Jan 1933")!)
    }

    func testValidatorRejectsASourcedGraphicWithoutAnApprovedSource() throws {
        let noSource = try spec(#"{"kind":"line","title":"Rate","basis":"sourced","line":{"xLabel":"Year","yLabel":"Percent","xFormat":"year","series":[{"name":"A","points":[[2019,1],[2020,2]]}]}}"#)
        XCTAssertTrue(noSource.validationProblems().contains { $0.contains("needs a source") })
        let badHost = try spec(#"{"kind":"line","title":"Rate","basis":"sourced","source":{"organization":"X","title":"Y","url":"https://example.com/series","period":"2019–2020","retrieved":"2026-09-15"},"line":{"xLabel":"Year","yLabel":"Percent","xFormat":"year","series":[{"name":"A","points":[[2019,1],[2020,2]]}]}}"#)
        XCTAssertTrue(badHost.validationProblems().contains { $0.contains("host is not approved") })
    }

    func testValidatorRejectsAnOverfullProportionAndABadWaffle() throws {
        let over = try spec(#"{"kind":"proportion","title":"Share","basis":"fromCard","proportion":{"style":"bar","total":100,"segments":[{"label":"A","value":70},{"label":"B","value":40}]}}"#)
        XCTAssertTrue(over.validationProblems().contains { $0.contains("sum above total") })
        let waffle = try spec(#"{"kind":"proportion","title":"Share","basis":"fromCard","proportion":{"style":"waffle","total":30,"segments":[{"label":"A","value":10.5}],"remainderLabel":"Rest"}}"#)
        let problems = waffle.validationProblems()
        XCTAssertTrue(problems.contains { $0.contains("waffle total") })
        XCTAssertTrue(problems.contains { $0.contains("waffle values are integers") })
    }

    func testValidatorRejectsAMismatchedPayloadAndNonIncreasingX() throws {
        let mismatched = try spec(#"{"kind":"bars","title":"T","basis":"fromCard","flow":{"layout":"chain","steps":[{"title":"A"},{"title":"B"}]}}"#)
        let problems = mismatched.validationProblems()
        XCTAssertTrue(problems.contains { $0.contains("bars payload is missing") })
        XCTAssertTrue(problems.contains { $0.contains("flow payload present") })
        XCTAssertFalse(mismatched.isRenderable)
        let backwards = try spec(#"{"kind":"line","title":"T","basis":"illustrative","line":{"xLabel":"Year","yLabel":"Y","xFormat":"year","series":[{"name":"A","points":[[2020,1],[2019,2]]}]}}"#)
        XCTAssertTrue(backwards.validationProblems().contains { $0.contains("strictly increase") })
    }

    // MARK: - Rendering

    /// Renders one real graphic of every kind in light, dark and at an
    /// accessibility text size; a kind with no catalog example falls back to a
    /// fixture so the renderer is always exercised. Set
    /// `CARD_GRAPHICS_SNAPSHOT_DIR` (via `TEST_RUNNER_…`) to also write PNGs of
    /// two examples per kind for visual review.
    @MainActor
    func testEveryKindRendersInLightDarkAndLargeText() throws {
        let cards = try allCards()
        let snapshotDir = ProcessInfo.processInfo.environment["CARD_GRAPHICS_SNAPSHOT_DIR"]
        if let snapshotDir { try FileManager.default.createDirectory(atPath: snapshotDir, withIntermediateDirectories: true) }
        let fixtures = try Self.fixtures()
        for kind in CardGraphicKind.allCases {
            var examples = cards.filter { $0.graphic?.kind == kind }.map { ($0.cardID, $0.graphic!) }
            if examples.isEmpty, let fixture = fixtures[kind] { examples = [("fixture-\(kind.rawValue)", fixture)] }
            XCTAssertFalse(examples.isEmpty, "no example for \(kind)")
            let picks = snapshotDir == nil ? Array(examples.prefix(1)) : Self.spread(examples, count: 2)
            for (id, spec) in picks {
                let variants: [(String, ColorScheme, DynamicTypeSize)] = [
                    ("light", .light, .large), ("dark", .dark, .large), ("ax", .dark, .accessibility3),
                ]
                for (name, scheme, typeSize) in variants {
                    let view = GraphicPlate(spec: spec)
                        .frame(width: 314)
                        .padding(10)
                        .background(scheme == .dark ? Econ.ocean.opacity(0.35) : Econ.page)
                        .environment(\.colorScheme, scheme)
                        .environment(\.dynamicTypeSize, typeSize)
                    let renderer = ImageRenderer(content: view)
                    renderer.scale = 2
                    let image = try XCTUnwrap(renderer.uiImage, "\(id) \(name) did not render")
                    XCTAssertGreaterThan(image.size.height, 60, "\(id) \(name) rendered empty")
                    XCTAssertEqual(image.size.width, 334, accuracy: 1, "\(id) \(name)")
                    if let snapshotDir, let png = image.pngData() {
                        try png.write(to: URL(fileURLWithPath: snapshotDir).appendingPathComponent("\(kind.rawValue)-\(id)-\(name).png"))
                    }
                }
                // The plate caps its text and chart metrics at `largestTypeSize`,
                // so the largest accessibility size draws exactly like that cap.
                let capped = try Self.renderedHeight(spec, typeSize: GraphicPlate.largestTypeSize)
                let largest = try Self.renderedHeight(spec, typeSize: .accessibility5)
                XCTAssertEqual(largest, capped, accuracy: 0.5, "\(id) grows past the xxxLarge cap")
            }
        }
    }

    /// 1.1.5 integration: the concept face scrolls, so the graphic always shows
    /// in full (no smaller plate, no "show graphic" button, no sheet) and sits
    /// in the face's graphic slot above the concept title.
    func testGraphicShowsInFullInTheCardFaceSlot() throws {
        let root = URL(fileURLWithPath: "\(#filePath)").deletingLastPathComponent().deletingLastPathComponent()
        let graphic = try String(contentsOf: root.appendingPathComponent("EconByte/Views/Graphics/CardGraphicView.swift"))
        for banned in ["ViewThatFits", "layoutPriority", ".sheet(", "GraphicSize", "cardGraphicCollapsed"] {
            XCTAssertFalse(graphic.contains(banned), "the graphic no longer shrinks or collapses: found \(banned)")
        }
        let card = try String(contentsOf: root.appendingPathComponent("EconByte/Views/CardView.swift"))
        let slot = try XCTUnwrap(card.range(of: "PHASE 20 GRAPHIC SLOT"))
        let hook = try XCTUnwrap(card.range(of: "CardGraphicView(spec: graphic)"))
        let title = try XCTUnwrap(card.range(of: "Text(card.concept)"))
        XCTAssertLessThan(slot.lowerBound, hook.lowerBound, "the hook is in the graphic slot")
        XCTAssertLessThan(hook.lowerBound, title.lowerBound, "the graphic sits above the concept title")
        XCTAssertTrue(card.contains("$0.accessibilitySummary"), "VoiceOver reads the graphic through the card label")
    }

    // MARK: - Helpers

    @MainActor
    private static func renderedHeight(_ spec: CardGraphicSpec, typeSize: DynamicTypeSize) throws -> CGFloat {
        let view = CardGraphicView(spec: spec)
            .frame(width: 314)
            .environment(\.colorScheme, .dark)
            .environment(\.dynamicTypeSize, typeSize)
        return try XCTUnwrap(ImageRenderer(content: view).uiImage, "\(spec.title) at \(typeSize)").size.height
    }

    private static func spread<T>(_ items: [T], count: Int) -> [T] {
        guard items.count > count else { return items }
        return (0..<count).map { items[$0 * (items.count - 1) / max(1, count - 1)] }
    }

    private static func fixtures() throws -> [CardGraphicKind: CardGraphicSpec] {
        let json = #"""
        {
          "bars": {"kind":"bars","title":"Fixture","basis":"illustrative","bars":{"items":[{"label":"A","value":1},{"label":"B","value":2}]}},
          "line": {"kind":"line","title":"Fixture","basis":"illustrative","line":{"xLabel":"Year","yLabel":"Y","xFormat":"year","series":[{"name":"A","points":[[2019,1],[2020,2],[2021,1.5]]}]}},
          "diagram": {"kind":"diagram","title":"Fixture","basis":"conceptual","diagram":{"xLabel":"Quantity","yLabel":"Price","curves":[{"label":"Demand","points":[[0.1,0.9],[0.9,0.1]]}]}},
          "flow": {"kind":"flow","title":"Fixture","basis":"conceptual","flow":{"layout":"cycle","steps":[{"title":"A"},{"title":"B"},{"title":"C"}]}},
          "compare": {"kind":"compare","title":"Fixture","basis":"conceptual","compare":{"columns":["A","B"],"rows":[{"label":"X","values":["a","b"]},{"label":"Y","values":["c","d"]}]}},
          "timeline": {"kind":"timeline","title":"Fixture","basis":"illustrative","timeline":{"events":[{"when":"1999","label":"A"},{"when":"2001","label":"B"}]}},
          "formula": {"kind":"formula","title":"Fixture","basis":"conceptual","formula":{"expression":"A = B × C","terms":[{"symbol":"A","meaning":"Thing"}]}},
          "proportion": {"kind":"proportion","title":"Fixture","basis":"illustrative","proportion":{"style":"waffle","total":100,"segments":[{"label":"A","value":40}],"remainderLabel":"Rest"}},
          "icons": {"kind":"icons","title":"Fixture","basis":"conceptual","icons":{"connector":"plus","items":[{"symbol":"house","label":"Home"},{"symbol":"banknote","label":"Loan"}]}},
          "candles": {"kind":"candles","title":"Fixture","basis":"illustrative","candles":{"xLabel":"Day","yLabel":"Price","candles":[{"open":104,"high":104.3,"low":102.7,"close":103},{"open":103,"high":103.3,"low":101.7,"close":102},{"open":102,"high":102.3,"low":100.7,"close":101},{"open":100.8,"high":101.25,"low":98.6,"close":101.2}],"highlight":{"from":4,"to":4,"pattern":"hammer","label":"Hammer"},"annotate":"ohlc","references":[{"y":104,"label":"Resistance"}]}}
        }
        """#
        let raw = try JSONDecoder().decode([String: CardGraphicSpec].self, from: Data(json.utf8))
        return Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in CardGraphicKind(rawValue: key).map { ($0, value) } })
    }

    private static func matches(of pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            let r = match.numberOfRanges > 1 ? match.range(at: 1) : match.range
            return Range(r, in: text).map { String(text[$0]) }
        }
    }

    private static let wordNumbers: [String: Double] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
        "ten": 10, "eleven": 11, "twelve": 12, "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
        "hundred": 100, "thousand": 1000, "million": 1e6, "billion": 1e9, "trillion": 1e12, "half": 0.5,
        "double": 2, "doubled": 2, "doubles": 2, "twice": 2, "triple": 3, "tripled": 3, "quadrupled": 4,
        "first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5, "dozen": 12, "decade": 10, "decades": 10,
        "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18,
        "nineteen": 19, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90, "century": 100,
        "sixth": 6, "seventh": 7, "eighth": 8, "ninth": 9, "tenth": 10, "zero": 0, "doubling": 2,
        "triples": 3, "quadruple": 4,
    ]

    /// Numbers stated in text: grouped digits ("1,000"), decimals, scale words
    /// ("1.2 million" → 1.2 and 1,200,000) and, for prose, number words.
    static func numbers(in text: String, prose: Bool) -> [Double] {
        var out: [Double] = []
        let normalized = text.replacingOccurrences(of: "\u{2212}", with: "-")
        guard let regex = try? NSRegularExpression(pattern: #"(\d[\d,]*(?:\.\d+)?)(\s*(thousand|million|billion|trillion))?"#,
                                                   options: [.caseInsensitive]) else { return out }
        let ns = normalized as NSString
        for match in regex.matches(in: normalized, range: NSRange(location: 0, length: ns.length)) {
            var raw = ns.substring(with: match.range(at: 1))
            // "2025, trillion yuan": a trailing comma ends the number, so no scale word applies.
            let hadTrailingComma = raw.hasSuffix(",")
            while raw.hasSuffix(",") { raw.removeLast() }
            let grouped = raw.range(of: #"^\d{1,3}(,\d{3})+(\.\d+)?$"#, options: .regularExpression) != nil
            if !grouped && raw.contains(",") {
                out += raw.split(separator: ",").compactMap { Double($0) }
                continue
            }
            guard let value = Double(raw.replacingOccurrences(of: ",", with: "")) else { continue }
            out.append(value)
            if match.range(at: 3).location != NSNotFound, !hadTrailingComma {
                let word = ns.substring(with: match.range(at: 3)).lowercased()
                out.append(value * (wordNumbers[word] ?? 1))
            }
        }
        if prose {
            for word in normalized.lowercased().split(whereSeparator: { !$0.isLetter }) {
                if let value = wordNumbers[String(word)] { out.append(value) }
            }
        }
        return out
    }

    /// Same tolerance as the content checker: exact, or the same figure at one
    /// decimal of display rounding.
    static func contains(_ allowed: [Double], _ value: Double) -> Bool {
        allowed.contains { a in
            abs(a - value) <= max(1e-9, abs(value) * 1e-9)
                || (abs(a) >= 0.01 && abs(a - value) <= 0.051 && abs(value) < 1000 && value != value.rounded())
        }
    }

    /// Numbers, + − × ÷ ^ and parentheses.
    static func evaluate(_ expression: String) -> Double? {
        let s = Array(expression.replacingOccurrences(of: "\u{2212}", with: "-")
            .replacingOccurrences(of: "×", with: "*").replacingOccurrences(of: "÷", with: "/")
            .filter { !$0.isWhitespace })
        var i = 0
        func number() -> Double? {
            var j = i
            while j < s.count, s[j].isNumber || s[j] == "." { j += 1 }
            guard j > i, let v = Double(String(s[i..<j])) else { return nil }
            i = j
            return v
        }
        func atom() -> Double? {
            guard i < s.count else { return nil }
            if s[i] == "(" { i += 1; let v = add(); guard i < s.count, s[i] == ")" else { return nil }; i += 1; return v }
            if s[i] == "-" { i += 1; return atom().map { -$0 } }
            return number()
        }
        func power() -> Double? {
            guard var v = atom() else { return nil }
            if i < s.count, s[i] == "^" { i += 1; guard let e = power() else { return nil }; v = pow(v, e) }
            return v
        }
        func mul() -> Double? {
            guard var v = power() else { return nil }
            while i < s.count, s[i] == "*" || s[i] == "/" {
                let op = s[i]; i += 1
                guard let r = power() else { return nil }
                v = op == "*" ? v * r : v / r
            }
            return v
        }
        func add() -> Double? {
            guard var v = mul() else { return nil }
            while i < s.count, s[i] == "+" || s[i] == "-" {
                let op = s[i]; i += 1
                guard let r = mul() else { return nil }
                v = op == "+" ? v + r : v - r
            }
            return v
        }
        let value = add()
        return i == s.count ? value : nil
    }

    // MARK: - Phase 24: candlestick patterns and the donut

    private static func candles(_ list: [[Double]], highlight: String? = nil) throws -> CandlesGraphic {
        let items = list.map { "{\"open\":\($0[0]),\"high\":\($0[1]),\"low\":\($0[2]),\"close\":\($0[3])}" }.joined(separator: ",")
        let json = "{\"xLabel\":\"Day\",\"yLabel\":\"Price\",\"candles\":[\(items)]\(highlight.map { ",\"highlight\":\($0)" } ?? "")}"
        return try JSONDecoder().decode(CandlesGraphic.self, from: Data(json.utf8))
    }

    private static let decline: [[Double]] = [[104, 104.3, 102.7, 103], [103, 103.3, 101.7, 102], [102, 102.3, 100.7, 101]]
    private static let rise: [[Double]] = [[100, 101.3, 99.7, 101], [101, 102.3, 100.7, 102], [102, 103.3, 101.7, 103]]

    func testCandlePatternsAcceptTextbookShapes() throws {
        let hammer = try Self.candles(Self.decline + [[100.8, 101.25, 98.6, 101.2]], highlight: #"{"from":4,"to":4,"pattern":"hammer","label":"Hammer"}"#)
        XCTAssertEqual(hammer.patternProblems(), [])
        let star = try Self.candles(Self.rise + [[103.2, 105.4, 102.95, 103.0]], highlight: #"{"from":4,"to":4,"pattern":"shootingStar","label":"Shooting star"}"#)
        XCTAssertEqual(star.patternProblems(), [])
        let doji = try Self.candles([[100, 101.5, 98.5, 100.1]], highlight: #"{"from":1,"to":1,"pattern":"doji","label":"Doji"}"#)
        XCTAssertEqual(doji.patternProblems(), [])
        let bullish = try Self.candles(Self.decline + [[101, 101.2, 99.8, 100], [99.8, 101.6, 99.6, 101.4]],
                                       highlight: #"{"from":4,"to":5,"pattern":"bullishEngulfing","label":"Bullish engulfing"}"#)
        XCTAssertEqual(bullish.patternProblems(), [])
        let bearish = try Self.candles(Self.rise + [[103, 104.2, 102.8, 104], [104.2, 104.4, 102.5, 102.7]],
                                       highlight: #"{"from":4,"to":5,"pattern":"bearishEngulfing","label":"Bearish engulfing"}"#)
        XCTAssertEqual(bearish.patternProblems(), [])
    }

    func testCandlePatternsRejectWrongShapesAndLabels() throws {
        func rejects(_ g: CandlesGraphic, _ fragment: String, file: StaticString = #filePath, line: UInt = #line) {
            XCTAssertTrue(g.patternProblems().contains { $0.contains(fragment) }, "\(fragment): \(g.patternProblems())", file: file, line: line)
        }
        rejects(try Self.candles([[100, 99, 98, 99.5]]), "high is below the body")
        rejects(try Self.candles([[100, 101, 100.2, 99.5]]), "low is above the body")
        rejects(try Self.candles(Self.decline + [[101, 102.5, 99, 101.5]], highlight: #"{"from":4,"to":4,"pattern":"hammer","label":"Hammer"}"#),
                "short wick exceeds 10%")
        rejects(try Self.candles(Self.rise + [[100.8, 101.25, 98.6, 101.2]], highlight: #"{"from":4,"to":4,"pattern":"hammer","label":"Hammer"}"#),
                "wrong prior move")
        rejects(try Self.candles([[100, 101.5, 98.5, 101]], highlight: #"{"from":1,"to":1,"pattern":"doji","label":"Doji"}"#),
                "body exceeds 10%")
        rejects(try Self.candles(Self.decline + [[101, 101.2, 99.8, 100], [100.2, 101.6, 99.6, 100.8]],
                                 highlight: #"{"from":4,"to":5,"pattern":"bullishEngulfing","label":"Bullish engulfing"}"#),
                "must cover the first")
        rejects(try Self.candles(Self.decline + [[101, 101.2, 99.8, 100], [99.8, 101.6, 99.6, 101.4]],
                                 highlight: #"{"from":4,"to":5,"pattern":"bullishEngulfing","label":"Bearish engulfing"}"#),
                "bullish")
        rejects(try Self.candles(Self.decline + [[100.8, 101.25, 98.6, 101.2]], highlight: #"{"from":4,"to":4,"pattern":"hammer","label":"Big candle"}"#),
                "must name the pattern")
        rejects(try Self.candles(Self.decline, highlight: #"{"from":3,"to":5,"pattern":"none","label":"Span"}"#), "from/to")
    }

    /// The anatomy labels (Open/High/Low/Close) never overlap, even on a candle
    /// whose open and close sit at its high.
    func testCandleAnnotationLabelsNeverOverlap() throws {
        let tight = try Self.candles([[100.95, 101, 99, 101]])
        let rows = CandlesGraphicView.annotationRows(for: tight.candles[0], y: { CGFloat(200 - ($0 - 99) * 60) }, minGap: 14)
        XCTAssertEqual(rows.map(\.text), ["High", "Close", "Open", "Low"])
        for pair in zip(rows, rows.dropFirst()) {
            XCTAssertGreaterThanOrEqual(pair.1.label - pair.0.label, 14 - 1e-9, "\(pair.0.text) and \(pair.1.text) overlap")
        }
    }

    @MainActor
    func testDonutRendersAndReadsItsShares() throws {
        let spec = try spec(#"{"kind":"proportion","title":"An illustrative mix","basis":"illustrative","proportion":{"style":"donut","total":100,"segments":[{"label":"Stocks","value":60},{"label":"Bonds","value":30}],"remainderLabel":"Cash"}}"#)
        XCTAssertEqual(spec.validationProblems(), [])
        XCTAssertTrue(spec.accessibilitySummary(in: .lesson).contains("Cash, 10"))
        for host in [GraphicHost.card, .lesson] {
            let view = GraphicPlate(spec: spec, host: host).frame(width: 340).environment(\.colorScheme, .dark)
            let image = try XCTUnwrap(ImageRenderer(content: view).uiImage)
            XCTAssertGreaterThan(image.size.height, 100)
        }
    }
}
