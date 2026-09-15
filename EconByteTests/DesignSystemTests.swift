import XCTest
import SwiftUI
import UIKit
@testable import EconByte

/// 1.1.5 design-system gate (Phase 19): views use the tokens in `Theme.swift`,
/// text tokens meet WCAG AA on every ground they are used on, and every
/// purchase button carries the action and its price.
final class DesignSystemTests: XCTestCase {

    private func repoRoot(file: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(file)").deletingLastPathComponent().deletingLastPathComponent()
    }

    /// Every Swift file under `EconByte/Views`.
    private func viewSources() throws -> [(name: String, text: String)] {
        let views = repoRoot().appendingPathComponent("EconByte/Views")
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: views, includingPropertiesForKeys: nil))
        return try enumerator.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
            .map { ($0.path.replacingOccurrences(of: views.path + "/", with: ""), try String(contentsOf: $0)) }
    }

    func testViewsUseTokensNotAdHocTypeRadiiOrLowContrastColour() throws {
        let rules: [(pattern: String, why: String)] = [
            (#"\.system\(size:"#, "a fixed point size does not scale with Dynamic Type — use EconType"),
            (#"cornerRadius\(\s*[0-9]"#, "a numeric corner radius — use EconRadius"),
            (#"cornerRadius:\s*[0-9]"#, "a numeric corner radius — use EconRadius"),
            (#"Econ\.subtext"#, "Econ.subtext is 2.5:1 on navy (fails AA) — use EconColor.textTertiary"),
        ]
        let sources = try viewSources()
        XCTAssertGreaterThan(sources.count, 15, "the scan found the view sources")
        var violations: [String] = []
        for (name, text) in sources {
            for (lineNumber, line) in text.components(separatedBy: .newlines).enumerated() {
                for rule in rules where line.range(of: rule.pattern, options: .regularExpression) != nil {
                    violations.append("\(name):\(lineNumber + 1) \(rule.why): \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }
        XCTAssertTrue(violations.isEmpty, violations.joined(separator: "\n"))
    }

    // MARK: Contrast

    private func rgba(_ color: Color) -> (r: Double, g: Double, b: Double, a: Double) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark)).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b), Double(a))
    }

    /// `color` composited over an opaque `ground`.
    private func over(_ color: Color, _ ground: (r: Double, g: Double, b: Double, a: Double)) -> (r: Double, g: Double, b: Double) {
        let c = rgba(color)
        return (c.r * c.a + ground.r * (1 - c.a), c.g * c.a + ground.g * (1 - c.a), c.b * c.a + ground.b * (1 - c.a))
    }

    private func luminance(_ c: (r: Double, g: Double, b: Double)) -> Double {
        func channel(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b)
    }

    private func contrast(_ a: (r: Double, g: Double, b: Double), _ b: (r: Double, g: Double, b: Double)) -> Double {
        let (l1, l2) = (luminance(a), luminance(b))
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    func testEveryTextTokenMeetsWCAGAAOnEveryGround() {
        let navy = rgba(EconColor.background)
        let navyRGB = (r: navy.r, g: navy.g, b: navy.b)
        let raised = over(EconColor.surfaceRaised, navy)
        let raisedGround = (r: raised.r, g: raised.g, b: raised.b, a: 1.0)
        let texts: [(String, Color)] = [
            ("textPrimary", EconColor.textPrimary), ("textSecondary", EconColor.textSecondary),
            ("textTertiary", EconColor.textTertiary), ("interactive", EconColor.interactive),
            ("accentText", EconColor.accentText),
        ]
        for (name, token) in texts {
            XCTAssertGreaterThanOrEqual(contrast(over(token, navy), navyRGB), 4.5, "\(name) on the navy ground")
            XCTAssertGreaterThanOrEqual(contrast(over(token, raisedGround), raised), 4.5, "\(name) on the raised surface")
        }
        let face = rgba(EconColor.cardFace)
        let faceRGB = (r: face.r, g: face.g, b: face.b)
        XCTAssertGreaterThanOrEqual(contrast(over(EconColor.onCardPrimary, face), faceRGB), 4.5)
        XCTAssertGreaterThanOrEqual(contrast(over(EconColor.onCardSecondary, face), faceRGB), 4.5)
        let accent = rgba(EconColor.accent)
        XCTAssertGreaterThanOrEqual(contrast(over(EconColor.onAccent, accent), (accent.r, accent.g, accent.b)), 4.5,
                                    "button text on the amber fill")
        // The retired 1.1.4 colour really did fail — the reason for the change.
        XCTAssertLessThan(contrast(over(Econ.subtext, navy), navyRGB), 4.5)
    }

    // MARK: Purchase button

    func testEveryPricedPurchaseButtonShowsTheActionOverItsPrice() {
        let pack = PurchaseButtonModel.make(action: "Unlock", price: .ready("$1.99"))
        XCTAssertEqual(pack.title, "Unlock")
        XCTAssertEqual(pack.detail, "$1.99")
        XCTAssertEqual(pack.label, "Unlock · $1.99", "VoiceOver and tests read the joined label")

        let trial = PurchaseButtonModel.make(action: "Start 7-day free trial", price: .ready("$39.99"),
                                             priceText: "then $39.99 per year")
        XCTAssertEqual(trial.detail, "then $39.99 per year", "the Pro CTA keeps its billed price")
        XCTAssertEqual(trial.label, "Start 7-day free trial · then $39.99 per year")

        for state in [PurchaseButtonModel.make(action: "Unlock", price: .loading),
                      PurchaseButtonModel.make(action: "Unlock", price: .unavailable),
                      PurchaseButtonModel.make(action: "Unlock", price: .ready("$1.99"), ownedLabel: "Owned"),
                      PurchaseButtonModel.make(action: "Unlock", price: .ready("$1.99"), pending: true)] {
            XCTAssertNil(state.detail, "no price line without a live price: \(state.title)")
            XCTAssertEqual(state.label, state.title)
            XCTAssertFalse(state.isEnabled)
        }
    }

    func testAllButtonsShareOneHeightToken() throws {
        // PurchaseButton, PrimaryButton and SecondaryButton all size from
        // EconSize.buttonHeight (scaled), so they are the same size everywhere.
        let theme = try String(contentsOf: repoRoot().appendingPathComponent("EconByte/Theme/Theme.swift"))
        let controls = try String(contentsOf: repoRoot().appendingPathComponent("EconByte/Views/Purchase/PurchaseControls.swift"))
        XCTAssertEqual(theme.components(separatedBy: "minHeight: CGFloat = EconSize.buttonHeight").count - 1, 2)
        XCTAssertTrue(controls.contains("minHeight: CGFloat = EconSize.buttonHeight"))
        XCTAssertGreaterThanOrEqual(EconSize.buttonHeight, EconSize.tapTarget)
    }
}
