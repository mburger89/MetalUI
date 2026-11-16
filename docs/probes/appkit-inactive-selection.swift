// AppKit probe: the colour NSTextView paints its selection in when it is the first responder of the key window,
// when it is not the first responder, and when its window is not key; and the two system colours behind it,
// `NSColor.selectedTextBackgroundColor` and `NSColor.unemphasizedSelectedTextBackgroundColor`, in light and dark
// appearance. Settles `CodeTheme.inactiveSelection`'s default (`CV-BB`, record 331).
//
// The selection colour is measured as a pixel: the text view (20 spaces, all selected, so no glyph ink) is rendered
// with `cacheDisplay(in:to:)` and pixels inside the first line's selection rectangle are read in sRGB. A process
// started from a script cannot become the active application, so the key window is faked by a window subclass whose
// `isKeyWindow` answers a flag (the text view asks its window); `real key` is printed beside it.
//
// HOW TO RUN (compiled form with Apple's toolchain, ruling SA-O; opens its own windows and exits itself):
//
//   xcrun swiftc docs/probes/appkit-inactive-selection.swift -o /tmp/inactive-sel && /tmp/inactive-sel 2>&1 | grep -v 'Connection\]'
//
// RECORDED: see the RECORDED block at the foot of this file (after the code).

import AppKit

final class W: NSWindow {
    nonisolated(unsafe) static var fakeKey = false
    override var isKeyWindow: Bool { W.fakeKey }
    override var canBecomeKey: Bool { true }
}

func spin(_ s: Double = 0.5) { RunLoop.current.run(until: Date(timeIntervalSinceNow: s)) }

func hex(_ c: NSColor) -> String {
    guard let s = c.usingColorSpace(.sRGB) else { return "?" }
    func b(_ v: CGFloat) -> Int { Int((v * 255).rounded()) }
    return String(format: "#%02X%02X%02X a=%.2f", b(s.redComponent), b(s.greenComponent), b(s.blueComponent), s.alphaComponent)
}

func resolved(_ c: NSColor, _ appearance: NSAppearance) -> String {
    var out = ""
    appearance.performAsCurrentDrawingAppearance { out = hex(c) }
    return out
}

func pixel(_ v: NSView, x: Int, y: Int) -> String {
    guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return "no rep" }
    v.cacheDisplay(in: v.bounds, to: rep)
    guard let c = rep.colorAt(x: x, y: y) else { return "no pixel" }
    return hex(c)
}

final class Delegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ n: Notification) {
        DispatchQueue.main.async { self.run(); exit(0) }
    }
    func run() {
        for (name, appearance) in [("light", NSAppearance(named: .aqua)!), ("dark", NSAppearance(named: .darkAqua)!)] {
            print("\(name): selectedTextBackgroundColor = \(resolved(.selectedTextBackgroundColor, appearance))"
                  + "  unemphasizedSelectedTextBackgroundColor = \(resolved(.unemphasizedSelectedTextBackgroundColor, appearance))"
                  + "  textBackgroundColor = \(resolved(.textBackgroundColor, appearance))")
            let win = W(contentRect: NSRect(x: 100, y: 100, width: 300, height: 60), styleMask: [.titled], backing: .buffered, defer: false)
            win.appearance = appearance
            let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 60))
            tv.string = String(repeating: " ", count: 20)
            tv.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
            tv.textColor = .clear   // the glyphs do not hide the fill
            win.contentView = tv
            let other = NSTextField(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
            tv.addSubview(other)
            NSApp.activate(ignoringOtherApps: true)
            win.makeKeyAndOrderFront(nil)
            spin(1.0)
            print("  setup: key=\(win.isKeyWindow) appActive=\(NSApp.isActive)")
            tv.setSelectedRange(NSRange(location: 0, length: 20))
            func sample() -> String { [(40, 6), (40, 10)].map { pixel(tv, x: $0.0, y: $0.1) }.joined(separator: " | ") }
            W.fakeKey = true
            win.makeFirstResponder(tv); spin()
            print("  \(name) first responder, key window: \(sample())")
            win.makeFirstResponder(nil); spin()
            print("  \(name) not first responder, key window: \(sample())")
            win.makeFirstResponder(tv); W.fakeKey = false; tv.needsDisplay = true; spin()
            print("  \(name) first responder, window not key: \(sample())")
            win.close()
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = Delegate()
app.delegate = delegate
app.run()

// RECORDED (macOS, 2026-11-16, compiled form):
//
// light: selectedTextBackgroundColor = #B3D7FF a=1.00  unemphasizedSelectedTextBackgroundColor = #DCDCDC a=1.00  textBackgroundColor = #FFFFFF a=1.00
//   setup: key=false appActive=false
//   light first responder, key window: #E3E3E3 a=1.00 | #E3E3E3 a=1.00
//   light not first responder, key window: #E3E3E3 a=1.00 | #E3E3E3 a=1.00
//   light first responder, window not key: #E3E3E3 a=1.00 | #E3E3E3 a=1.00
// dark: selectedTextBackgroundColor = #3F638B a=1.00  unemphasizedSelectedTextBackgroundColor = #464646 a=1.00  textBackgroundColor = #1E1E1E a=1.00
//   setup: key=false appActive=false
//   dark first responder, key window: #585858 a=1.00 | #585858 a=1.00
//   dark not first responder, key window: #585858 a=1.00 | #585858 a=1.00
//   dark first responder, window not key: #585858 a=1.00 | #585858 a=1.00
//
// READING: the system colours are exact: `unemphasizedSelectedTextBackgroundColor` is #DCDCDC (light) and #464646 (dark),
// which are `CodeTheme.defaultInactiveSelection`. The pixel rows are NOT a measurement of the active selection: the
// probe process never became the active application (`appActive=false`, `key=false`), so NSTextView painted its
// unemphasized fill in all three states (the pixels differ from the colour by NSTextView's own blending, not by state).
// The focused default, `selectedTextBackgroundColor` (#B3D7FF / #3F638B), is unchanged by this ruling.
