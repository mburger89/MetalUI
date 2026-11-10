// SwiftUI/AppKit probe: the selected segment's EDGE (stroke and shadow) of a segmented
// control, in light and dark (SG-A..., docs/superpowers/2026-11-01-segmented-dark-decisions.md, SD-C).
//
// HOW TO RUN (SA-O's compiled form):
//
//   xcrun swiftc docs/probes/swiftui-segmented-thumb.swift -o /tmp/st-probe && /tmp/st-probe 2>&1 | grep -v 'Connection\]'
//
// INSTRUMENTS tried, in order, per appearance, for a SwiftUI `Picker(.segmented)` in an
// `NSHostingView` and a bare `NSSegmentedControl` (260x40, appearance forced):
//   I1 `bitmapImageRepForCachingDisplay` + `cacheDisplay(in:to:)`;
//   (`CGWindowListCreateImage` is unavailable on macOS 27 - ScreenCaptureKit only; `screencapture -l` was
//   tried by swiftui-segmented-dark.swift and refuses without a capture permission.)
// A capture counts as READ only if it has a non-uniform pixel row; otherwise it prints BLANK.
// When a capture reads, a horizontal pixel row across the left edge of the selected segment is
// printed (stroke width/colour, shadow extent) plus a vertical column under it.
// Always printed: the semantic colours AppKit paints with, resolved per appearance.
//
// RECORDED OUTPUT: see record 260 (macOS 27, 2026-11-09, agent session). Every instrument printed
// BLANK (uniform or fully transparent); the semantic colours are the recorded evidence.
import AppKit
import SwiftUI

struct P: View {
    @State var v = 0
    var body: some View {
        Picker("", selection: $v) { Text("A").tag(0); Text("B").tag(1); Text("C").tag(2) }
            .pickerStyle(.segmented).labelsHidden().frame(width: 240).padding(10)
    }
}
func hex(_ c: NSColor) -> String {
    guard let s = c.usingColorSpace(.sRGB) else { return "?" }
    return String(format: "#%02X%02X%02X a=%.3f", Int((s.redComponent * 255).rounded()),
                  Int((s.greenComponent * 255).rounded()), Int((s.blueComponent * 255).rounded()), s.alphaComponent)
}
func px(_ r: NSBitmapImageRep, _ x: Int, _ y: Int) -> String {
    guard let c = r.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return "?" }
    return String(format: "%02X%02X%02X/%.2f", Int((c.redComponent * 255).rounded()),
                  Int((c.greenComponent * 255).rounded()), Int((c.blueComponent * 255).rounded()), c.alphaComponent)
}
func report(_ tag: String, _ r: NSBitmapImageRep?) {
    guard let r else { print("  \(tag): no image"); return }
    var seen = Set<String>()
    for x in stride(from: 0, to: r.pixelsWide, by: 1) { seen.insert(px(r, x, r.pixelsHigh / 2)) }
    if seen.count < 3 { print("  \(tag): BLANK (\(seen.count) distinct values on the middle row: \(seen))"); return }
    let y = r.pixelsHigh / 2
    print("  \(tag): size \(r.pixelsWide)x\(r.pixelsHigh); row y=\(y), x=4..30: " + (4..<30).map { "\($0):" + px(r, $0, y) }.joined(separator: " "))
    print("  \(tag): column x=25 (inside segment 1, left of its label), y=0..\(r.pixelsHigh - 1): " + (0..<r.pixelsHigh).map { "\($0):" + px(r, 25, $0) }.joined(separator: " "))
    print("  \(tag): column x=125 (segment 2, unselected): " + (0..<r.pixelsHigh).map { "\($0):" + px(r, 125, $0) }.joined(separator: " "))
}
func run(_ view: NSView, _ name: NSAppearance.Name, _ label: String) {
    let ap = NSAppearance(named: name)!
    view.appearance = ap
    view.frame = NSRect(x: 0, y: 0, width: 260, height: 40)
    let win = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    win.appearance = ap; win.contentView = view; win.setFrameOrigin(NSPoint(x: 200, y: 400))
    win.orderFrontRegardless(); view.layoutSubtreeIfNeeded()
    for _ in 0..<5 { RunLoop.current.run(until: Date().addingTimeInterval(0.2)); view.displayIfNeeded() }
    print("\(label) \(name.rawValue)")
    if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
        view.cacheDisplay(in: view.bounds, to: rep); report("I1 cacheDisplay", rep)
    }
    win.orderOut(nil)
}
NSApplication.shared.setActivationPolicy(.accessory); NSApplication.shared.finishLaunching()
for (an, name) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
    NSAppearance.current = NSAppearance(named: name)
    print("semantic \(an):")
    for (n, c) in [("separatorColor", NSColor.separatorColor), ("controlColor", .controlColor),
                   ("selectedControlColor", .selectedControlColor), ("controlBackgroundColor", .controlBackgroundColor),
                   ("windowBackgroundColor", .windowBackgroundColor), ("quaternaryLabelColor", .quaternaryLabelColor),
                   ("tertiaryLabelColor", .tertiaryLabelColor), ("gridColor", .gridColor),
                   ("shadowColor", .shadowColor), ("labelColor", .labelColor)] as [(String, NSColor)] {
        print("  \(n) \(hex(c))")
    }
}
for (an, name) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
    _ = an
    run(NSHostingView(rootView: P()), name, "SwiftUI")
    let s = NSSegmentedControl(labels: ["A", "B", "C"], trackingMode: .selectOne, target: nil, action: nil)
    s.selectedSegment = 0
    run(s, name, "NSSegmentedControl")
}
