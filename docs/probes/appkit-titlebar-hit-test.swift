// AppKit probe: what a click in the title-bar band hits when the content view
// runs under a transparent title bar (`.fullSizeContentView` +
// `titlebarAppearsTransparent` + `titleVisibility = .hidden`, the flags
// SwiftUI's `.hiddenTitleBar` sets — swiftui-app-shell.swift H0), and where
// the window buttons sit. Evidence for ruling AS-… (the title-bar inset) in
// docs/superpowers/2026-10-08-app-shell-decisions.md.
//
// HOW TO RUN (compiled form, SA-O):
//
//   xcrun swiftc docs/probes/appkit-titlebar-hit-test.swift -o /tmp/titlebar-hit && /tmp/titlebar-hit
//
// INSTRUMENT. `NSWindow.contentView!.superview!` (the frame view) is asked
// `hitTest(_:)` at points in its own coordinates — the call AppKit's event
// dispatch makes to find a mouse-down's view. A flipped content view whose
// `mouseDownCanMoveWindow` is false (as MetalUI's host view inherits) fills
// the window. ARMS: S0 the standard title bar (control: the band is outside
// the content view); F0 full-size content under the transparent hidden bar;
// F1 F0 plus a toolbar.
// For each: the hit view's class at the band's centre, at its left end beside
// the buttons, and 10 pt below the band; the band's height
// (frame − contentLayoutRect); the zoom button's maxX in window coordinates.
//
// RECORDED 2026-10-09 by the app-shell design session, macOS 27.0.1, Apple
// Swift 6.4, screen locked. Run twice: stdout byte-identical (md5
// e0f13ac4449e94cbcea3f473621f2107), exit 0.
//
// OUTPUT, verbatim:
//
//   === S0 standard title bar (control)
//     contentView=(600.0, 400.0) contentLayoutRect=(0.0, 0.0, 600.0, 400.0) band=32.0 zoomMaxX=69.0
//     hit band centre (300, 16.0) -> NSTitlebarView
//     hit band left beside buttons (79.0, 16.0) -> NSTitlebarView
//     hit on close button (14, 16.0) -> _NSThemeCloseWidget
//     hit 10 below band (300, 42.0) -> Content
//   === F0 full-size content, transparent hidden title bar
//     contentView=(600.0, 400.0) contentLayoutRect=(0.0, 0.0, 600.0, 368.0) band=32.0 zoomMaxX=69.0
//     hit band centre (300, 16.0) -> Content
//     hit band left beside buttons (79.0, 16.0) -> Content
//     hit on close button (14, 16.0) -> _NSThemeCloseWidget
//     hit 10 below band (300, 42.0) -> Content
//   === F1 F0 + toolbar
//     contentView=(600.0, 400.0) contentLayoutRect=(0.0, 0.0, 600.0, 334.0) band=66.0 zoomMaxX=79.0
//     hit band centre (300, 33.0) -> Content
//     hit band left beside buttons (89.0, 33.0) -> Content
//     hit on close button (14, 33.0) -> Content
//     hit 10 below band (300, 76.0) -> Content
//
// READING. S0 (control): the 32-pt band is the title bar's own view and the
// content starts below it. F0: under the transparent hidden bar a press
// anywhere in the band but on a window button reaches the CONTENT view — so
// AppKit drags the window from the band only if the content view lets it
// (`mouseDownCanMoveWindow`), and MetalUI's host view must decide (ruling
// AS-F). The band is 32 pt and the buttons end at x = 69. F1: a toolbar makes
// the band 66 pt and moves the buttons (maxX 79; at y 33 the close widget is
// not under the point: the buttons are re-centred in the taller band).

import AppKit

final class Content: NSView {
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
}

@MainActor func run(_ tag: String, fullSize: Bool, toolbar: Bool) {
    var mask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
    if fullSize { mask.insert(.fullSizeContentView) }
    let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: mask,
                     backing: .buffered, defer: false)
    w.isReleasedWhenClosed = false
    w.contentView = Content()
    if fullSize {
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
    }
    if toolbar { w.toolbar = NSToolbar(identifier: "probe") }
    w.layoutIfNeeded()
    let frameView = w.contentView!.superview!
    let band = w.frame.height - w.contentLayoutRect.height
    let zoomMaxX = w.standardWindowButton(.zoomButton).map { $0.convert($0.bounds, to: nil).maxX } ?? -1
    // Points in window coordinates (origin bottom-left), converted to the frame view's.
    // The frame view is the window's root (no superview), so `hitTest(_:)`
    // takes a point in window coordinates (origin bottom-left).
    func hit(_ x: CGFloat, _ yFromTop: CGFloat) -> String {
        precondition(frameView.superview == nil)
        let view = frameView.hitTest(NSPoint(x: x, y: w.frame.height - yFromTop))
        return view.map { String(describing: type(of: $0)) } ?? "nil"
    }
    print("=== \(tag)")
    print("  contentView=\(w.contentView!.frame.size) contentLayoutRect=\(w.contentLayoutRect) band=\(band) zoomMaxX=\(zoomMaxX)")
    print("  hit band centre (300, \(band / 2)) -> \(hit(300, band / 2))")
    print("  hit band left beside buttons (\(zoomMaxX + 10), \(band / 2)) -> \(hit(zoomMaxX + 10, band / 2))")
    print("  hit on close button (\(14), \(band / 2)) -> \(hit(14, band / 2))")
    print("  hit 10 below band (300, \(band + 10)) -> \(hit(300, band + 10))")
    w.close()
}

setvbuf(stdout, nil, _IOLBF, 0)
_ = NSApplication.shared
MainActor.assumeIsolated {
    run("S0 standard title bar (control)", fullSize: false, toolbar: false)
    run("F0 full-size content, transparent hidden title bar", fullSize: true, toolbar: false)
    run("F1 F0 + toolbar", fullSize: true, toolbar: true)
}
