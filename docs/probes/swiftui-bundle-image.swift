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
// POSITIVE CONTROL / SEPARATING ARM: B0 (`plain` resolves: 8×6 pt) against B1
// (`missing`: what a failed lookup sizes to).
//
// RECORDED: see the block below (filled in by the run that commits it).

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
    try? FileManager.default.removeItem(at: root)
    exit(0)
}
