// SwiftUI probe: the segmented Picker's track, selected and unselected segment
// colours in light and dark (SD-A, docs/superpowers/2026-11-01-segmented-dark-decisions.md).
//
// HOW TO RUN (SA-O's compiled form):
//
//   xcrun swiftc docs/probes/swiftui-segmented-dark.swift -o /tmp/sd-probe && /tmp/sd-probe 2>&1 | grep -v 'Connection\]'
//
// INSTRUMENT. A SwiftUI `Picker(...).pickerStyle(.segmented)` in an
// `NSHostingView` (260x40, appearance forced with `NSAppearance`), drawn with
// `cacheDisplay(in:to:)` into an `NSBitmapImageRep` (no window server capture,
// so a locked screen does not matter). Arm N repeats it with a bare
// `NSSegmentedControl`. Pixels are read in sRGB at scale 1: the track at
// x=4 (left of segment 1, inside the track inset), the selected segment at
// the centre of segment 1 away from its label, the unselected at the centre
// of segment 3. The row is sampled at y = height/2 - 9 to stay off the label.
//
// RECORDED OUTPUT (macOS 27, 2026-11-01, agent session without screen-capture permission).
// NO NATIVE PIXELS WERE OBTAINED: `cacheDisplay`, `NSSegmentedCell.draw(withFrame:in:)` into a bitmap
// and `CALayer.render(in:)` all drew nothing for either control (the picture is blank), and
// `screencapture -x` / `-l` answered "could not create image from display/window". This file is the
// capture-based instrument for a session that has the permission (it prints the three samples per
// appearance). The proxy measured instead, `NSColor` resolved under each appearance and composited
// over `windowBackgroundColor` (`controlColor`, the colour AppKit paints a segmented pill with):
//   light: window #FFFFFF; controlColor #FFFFFF (white pill); quaternarySystemFill track #F8F8F8
//   dark:  window #1E1E1E; controlColor = white at 0.25 alpha, composited #565656 (pill);
//          quaternarySystemFill #242424, secondarySystemFill #303030 (track candidates)
// so the pill composites LIGHTER than the track in both appearances (SD-A). Unverified by pixel.
import AppKit
import SwiftUI

struct P: View {
    @State var v = 0
    var body: some View {
        Picker("", selection: $v) { Text("A").tag(0); Text("B").tag(1); Text("C").tag(2) }
            .pickerStyle(.segmented).labelsHidden().frame(width: 240).padding(10)
    }
}

func render(_ view: NSView, _ name: NSAppearance.Name) -> NSBitmapImageRep {
    view.appearance = NSAppearance(named: name)
    view.frame = NSRect(x: 0, y: 0, width: 260, height: 40)
    let win = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    win.appearance = NSAppearance(named: name)
    win.contentView = view
    win.backgroundColor = .clear
    win.orderFrontRegardless()
    view.layoutSubtreeIfNeeded()
    for _ in 0..<5 { RunLoop.current.run(until: Date().addingTimeInterval(0.2)); view.displayIfNeeded() }
    win.setFrameOrigin(NSPoint(x: 200, y: 400)); win.makeKeyAndOrderFront(nil)
    for _ in 0..<5 { RunLoop.current.run(until: Date().addingTimeInterval(0.2)) }
    let out = NSTemporaryDirectory() + "sd-\(UUID().uuidString).png"
    let t = Process(); t.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    t.arguments = ["-x", "-o", "-l", String(win.windowNumber), out]; try! t.run(); t.waitUntilExit()
    let rep = NSBitmapImageRep(data: try! Data(contentsOf: URL(fileURLWithPath: out)))!
    if let dir = ProcessInfo.processInfo.environment["SD_PNG_DIR"] {
        try? FileManager.default.copyItem(atPath: out, toPath: "\(dir)/\(view.className.suffix(12))-\(name.rawValue).png")
    }
    win.orderOut(nil)
    return rep
}
func px(_ r: NSBitmapImageRep, _ x: Int, _ y: Int) -> String {
    let c = r.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
    if c.alphaComponent < 0.01 { return "clear" }
    return String(format: "#%02X%02X%02X", Int((c.redComponent * 255).rounded()),
                  Int((c.greenComponent * 255).rounded()), Int((c.blueComponent * 255).rounded()))
}
NSApplication.shared.setActivationPolicy(.accessory); NSApplication.shared.finishLaunching()
for (label, make) in [("SwiftUI", { () -> NSView in NSHostingView(rootView: P()) }),
                      ("NSSegmentedControl", { () -> NSView in
                          let s = NSSegmentedControl(labels: ["A", "B", "C"], trackingMode: .selectOne, target: nil, action: nil)
                          s.selectedSegment = 0; return s })] as [(String, () -> NSView)] {
    for (an, name) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
        let r = render(make(), name)
        let y = 12
        print("\(label) \(an): track(x=14) \(px(r, 14, y))  selected(seg1 right of label) \(px(r, 70, y))  unselected(seg3) \(px(r, 200, y))")
    }
}
