// SwiftUI probe: `Image(_ name:bundle:)` over LOOSE PNG files in a bundle (the
// shape a SwiftPM `.copy`/`.process` resource bundle has on macOS — no asset
// catalog), for MetalUI's bundle image initialiser (portable-app branch,
// rulings PX-… in docs/superpowers/2026-10-07-portable-app-decisions.md; the
// configurator's gap MG-10).
//
// HOW TO RUN (compiled form, SA-O):
//
//   xcrun swiftc docs/probes/swiftui-bundle-image.swift -o /tmp/bundle-image-probe
//   /tmp/bundle-image-probe
//
// The probe writes a bundle directory under NSTemporaryDirectory():
// `Probe.bundle/Contents/Resources/` holding `plain.png` (8×6), `scaled.png`
// (8×6) beside `scaled@2x.png` (16×12) and `scaled@3x.png` (24×18), and
// `Icons/dark/key.png` (10×10) in a subdirectory, each a solid colour so the
// variant chosen is told apart by its pixel size. `Bundle(path:)` opens it.
// Each arm hosts an Image in an NSHostingView, reads its `fittingSize` (points)
// and the accessibility label of the hosting view's first image element.
//
// POSITIVE CONTROL / SEPARATING ARM: B9 (`cat`, an 8×6 image set compiled by
// `xcrun actool` into an `Assets.car` in the SAME Resources directory: the
// named lookup itself works, 8×6 pt) against B0 (`plain`, a loose 8×6 PNG
// beside it) and B1 (`missing`: what a failed lookup sizes to). B0 vs B1
// alone separate nothing (both 0×0) — B9 was added by the portable-app
// critic pass (PX-O) for exactly that reason.
//
// RECORDED 2026-10-07 by the portable-app design session, macOS 27.0.1
// (26A434), Apple Swift 6.4, screen LOCKED. Compiled form, run three times
// (the final file, with the Info.plist): byte-identical, exit 0, stderr
// empty. An earlier run without the Info.plist read the same for B0–B8.
// Re-recorded the same day by the critic pass with B9 (actool from
// Xcode-beta): three runs byte-identical, exit 0, stderr empty; I0–B8
// unchanged.
//
//   actool status=0 Assets.car=true
//   bundle=true url(plain)=true
//   screen backingScaleFactor=2.0
//   === I0 instrument control: Image(nsImage: NSImage(contentsOf: plain.png))
//     fittingSize=8.0x6.0 ax=[]
//   I1 AppKit's own loose-file lookup: bundle.image(forResource: "scaled") size=8.0x6.0 reps=["24x18", "16x12", "8x6"]
//   I2 bundle.image(forResource: "Icons/dark/key")=nil url(key, subdirectory: Icons/dark)=true
//   === B0 control: Image("plain", bundle:) — an 8×6 px loose PNG
//     fittingSize=0.0x0.0 ax=[]
//   === B1 separating: Image("missing", bundle:)
//     fittingSize=0.0x0.0 ax=[]
//   === B2 Image("scaled", bundle:) beside @2x/@3x variants
//     fittingSize=0.0x0.0 ax=[]
//   === B3 Image("only", bundle:) with ONLY only@2x.png (16×12 px)
//     fittingSize=0.0x0.0 ax=[]
//   === B4 Image("plain.png", bundle:) — the name with its extension
//     fittingSize=0.0x0.0 ax=[]
//   === B5 Image("Icons/dark/key", bundle:) — a subdirectory path
//     fittingSize=0.0x0.0 ax=[]
//   === B6 Image("key", bundle:) — the subdirectory file by basename
//     fittingSize=0.0x0.0 ax=[]
//   === B7 Image(decorative: "plain", bundle:)
//     fittingSize=0.0x0.0 ax=[]
//   === B8 Image("plain", bundle:).resizable().frame(width: 40, height: 30)
//     fittingSize=40.0x30.0 ax=[]
//   === B9 positive control: Image("cat", bundle:) — an 8×6 image set in a compiled Assets.car
//     fittingSize=8.0x6.0 ax=[]
//
// READING NOTES.
// - B9: the instrument sees a named bundle image: an asset-catalog entry in
//   the same bundle sizes 8×6 pt. So B0–B7's 0×0 is the lookup refusing loose
//   files, not the harness failing to see any named image.
// - I0: the instrument works — `Image(nsImage:)` of the file sizes 8×6 pt.
// - I1/I2: AppKit's own lookup finds loose files (`bundle.image(forResource:)`
//   returns all three reps of `scaled`), but not a subdirectory path; the
//   Foundation lookup `url(forResource:withExtension:subdirectory:)` does.
// - B0–B7: SwiftUI's `Image(_:bundle:)` and `Image(decorative:bundle:)` find
//   NONE of the loose PNGs — every arm sizes 0×0, exactly like B1 (`missing`).
//   SwiftUI's named images are asset-catalog entries. B8: a resizable framed
//   missing image takes its frame (40×30) and draws nothing.
// - `ax=[]` everywhere: no accessibility client activated the window, so the
//   AX column is not evidence of anything (a broken instrument, kept visible).

import AppKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers

@MainActor func writePNG(_ url: URL, width: Int, height: Int, rgb: (UInt8, UInt8, UInt8)) {
    var px = [UInt8](repeating: 255, count: width * height * 4)
    for i in stride(from: 0, to: px.count, by: 4) { px[i] = rgb.0; px[i + 1] = rgb.1; px[i + 2] = rgb.2 }
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: &px, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let image = ctx.makeImage()!
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

@MainActor func axLabels(_ element: Any) -> [String] {
    var out: [String] = []
    guard let e = element as? NSAccessibilityProtocol else { return out }
    if let l = e.accessibilityLabel(), !l.isEmpty { out.append("label=\(l)") }
    if let o = element as? NSObject, o.responds(to: #selector(NSAccessibilityProtocol.accessibilityChildren)),
       let children = o.perform(#selector(NSAccessibilityProtocol.accessibilityChildren))?.takeUnretainedValue() as? [Any] {
        for c in children { out += axLabels(c) }
    }
    return out
}

@MainActor func measure<V: View>(_ name: String, _ view: V) {
    let host = NSHostingView(rootView: view)
    let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
                       styleMask: [.titled], backing: .buffered, defer: false)
    win.isReleasedWhenClosed = false
    win.contentView = host
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    print("=== \(name)")
    print("  fittingSize=\(host.fittingSize.width)x\(host.fittingSize.height) ax=\(axLabels(host))")
    win.contentView = nil
}

MainActor.assumeIsolated {
    NSApplication.shared.setActivationPolicy(.accessory)
    let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Probe-\(getpid()).bundle")
    let res = root.appendingPathComponent("Contents/Resources")
    writePNG(res.appendingPathComponent("plain.png"), width: 8, height: 6, rgb: (255, 0, 0))
    writePNG(res.appendingPathComponent("scaled.png"), width: 8, height: 6, rgb: (0, 255, 0))
    writePNG(res.appendingPathComponent("scaled@2x.png"), width: 16, height: 12, rgb: (0, 0, 255))
    writePNG(res.appendingPathComponent("scaled@3x.png"), width: 24, height: 18, rgb: (255, 255, 0))
    writePNG(res.appendingPathComponent("Icons/dark/key.png"), width: 10, height: 10, rgb: (0, 255, 255))
    writePNG(res.appendingPathComponent("only@2x.png"), width: 16, height: 12, rgb: (255, 0, 255))
    // An Info.plist, so the directory is a well-formed bundle (an arm without
    // one read the same; kept so the reading cannot rest on its absence).
    let plist = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\"><dict>"
        + "<key>CFBundleIdentifier</key><string>probe.bundle.image</string>"
        + "<key>CFBundlePackageType</key><string>BNDL</string></dict></plist>"
    try? plist.write(to: root.appendingPathComponent("Contents/Info.plist"), atomically: true, encoding: .utf8)
    // B9's asset catalog: one 8×6 image set compiled by actool into the same
    // Resources directory (the positive control for the named lookup itself).
    let catalog = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Probe-\(getpid()).xcassets")
    let set = catalog.appendingPathComponent("cat.imageset")
    writePNG(set.appendingPathComponent("cat.png"), width: 8, height: 6, rgb: (128, 0, 255))
    try? "{\"info\":{\"author\":\"xcode\",\"version\":1}}".write(
        to: catalog.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
    try? "{\"images\":[{\"filename\":\"cat.png\",\"idiom\":\"universal\",\"scale\":\"1x\"}],\"info\":{\"author\":\"xcode\",\"version\":1}}".write(
        to: set.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
    let actool = Process()
    actool.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    actool.arguments = ["actool", "--compile", res.path, "--platform", "macosx",
                        "--minimum-deployment-target", "14.0", catalog.path]
    actool.standardOutput = FileHandle.nullDevice
    actool.standardError = FileHandle.nullDevice
    try? actool.run(); actool.waitUntilExit()
    print("actool status=\(actool.terminationStatus) Assets.car=\(FileManager.default.fileExists(atPath: res.appendingPathComponent("Assets.car").path))")
    let bundle = Bundle(path: root.path)!
    print("bundle=\(bundle.bundlePath.hasSuffix(".bundle")) url(plain)=\(bundle.url(forResource: "plain", withExtension: "png") != nil)")
    print("screen backingScaleFactor=\(NSScreen.main?.backingScaleFactor ?? -1)")

    measure("I0 instrument control: Image(nsImage: NSImage(contentsOf: plain.png))",
            Image(nsImage: NSImage(contentsOf: res.appendingPathComponent("plain.png"))!))
    let appKitScaled = bundle.image(forResource: "scaled")
    print("I1 AppKit's own loose-file lookup: bundle.image(forResource: \"scaled\") size=\(appKitScaled.map { "\($0.size.width)x\($0.size.height) reps=\($0.representations.map { "\($0.pixelsWide)x\($0.pixelsHigh)" })" } ?? "nil")")
    print("I2 bundle.image(forResource: \"Icons/dark/key\")=\(bundle.image(forResource: "Icons/dark/key").map { "\($0.size)" } ?? "nil") url(key, subdirectory: Icons/dark)=\(bundle.url(forResource: "key", withExtension: "png", subdirectory: "Icons/dark") != nil)")
    measure("B0 control: Image(\"plain\", bundle:) — an 8×6 px loose PNG", Image("plain", bundle: bundle))
    measure("B1 separating: Image(\"missing\", bundle:)", Image("missing", bundle: bundle))
    measure("B2 Image(\"scaled\", bundle:) beside @2x/@3x variants", Image("scaled", bundle: bundle))
    measure("B3 Image(\"only\", bundle:) with ONLY only@2x.png (16×12 px)", Image("only", bundle: bundle))
    measure("B4 Image(\"plain.png\", bundle:) — the name with its extension", Image("plain.png", bundle: bundle))
    measure("B5 Image(\"Icons/dark/key\", bundle:) — a subdirectory path", Image("Icons/dark/key", bundle: bundle))
    measure("B6 Image(\"key\", bundle:) — the subdirectory file by basename", Image("key", bundle: bundle))
    measure("B7 Image(decorative: \"plain\", bundle:)", Image(decorative: "plain", bundle: bundle))
    measure("B8 Image(\"plain\", bundle:).resizable().frame(width: 40, height: 30)",
            Image("plain", bundle: bundle).resizable().frame(width: 40, height: 30))
    measure("B9 positive control: Image(\"cat\", bundle:) — an 8×6 image set in a compiled Assets.car",
            Image("cat", bundle: bundle))
    try? FileManager.default.removeItem(at: root)
    try? FileManager.default.removeItem(at: catalog)
    exit(0)
}
