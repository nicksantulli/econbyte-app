// Renders the app's real in-app wordmark (EconByte/Theme/EconWordmark.swift)
// to a transparent PNG for the app icon generator. Compiled together with that
// file by scripts/icon/build_icon.sh — nothing here re-draws the letters or the
// swoosh; it only picks the icon's options and rasterises.
//
// usage: render_wordmark <out.png> <fontSizePx> <navy|navyDeep> <swooshBoost>
// prints one JSON line: {"width":…, "height":…} (the layout box in px).

import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

@main
struct RenderWordmark {
    @MainActor
    static func main() {
        let args = CommandLine.arguments
        guard args.count == 5, let size = Double(args[2]), let boost = Double(args[4]) else {
            FileHandle.standardError.write("usage: render_wordmark <out.png> <fontSizePx> <navy|navyDeep> <swooshBoost>\n".data(using: .utf8)!)
            exit(2)
        }
        let econ: Color = args[3] == "navyDeep" ? EconBrand.navyDeep : EconBrand.navy
        let view = EconWordmark(fontSize: CGFloat(size), econColor: econ, swooshBoost: CGFloat(boost))
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        renderer.isOpaque = false
        guard let cg = renderer.cgImage else {
            FileHandle.standardError.write("render failed\n".data(using: .utf8)!)
            exit(1)
        }
        let url = URL(fileURLWithPath: args[1]) as CFURL
        guard let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil) else { exit(1) }
        CGImageDestinationAddImage(dest, cg, nil)
        guard CGImageDestinationFinalize(dest) else { exit(1) }
        print("{\"width\":\(cg.width),\"height\":\(cg.height)}")
    }
}
