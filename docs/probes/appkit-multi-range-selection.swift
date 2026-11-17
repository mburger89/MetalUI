// AppKit probe: what `NSTextView.setSelectedRanges(_:affinity:stillSelecting:)` keeps and what it draws when given
// several ranges: three zero-length ranges (three carets), a mix of non-empty and zero-length ranges, and three
// non-empty ranges. Settles that drawing every caret is MetalUI-only (class M, `CV-BG`, record 340): the question
// is whether AppKit keeps zero-length ranges among several and paints a caret for each.
//
// What is printed: `selectedRanges` after the call (what survived), `selectedRange` (the first), and, per case, the
// drawn result: the text view (spaces, so no glyph ink) is rendered with `cacheDisplay(in:to:)` and the first line
// is scanned for runs of the selection colour (non-empty ranges) and of the insertion-point colour (a caret is a
// thin dark bar). A process started from a script cannot become the active application, so the key window is faked
// by a window subclass whose `isKeyWindow` answers a flag; `real key` is printed beside it. If no window can be
// key the drawn lines say so honestly rather than being omitted.
//
// HOW TO RUN (compiled form with Apple's toolchain, ruling SA-O; opens its own window and exits itself):
//
//   xcrun swiftc docs/probes/appkit-multi-range-selection.swift -o /tmp/multi-range && /tmp/multi-range 2>&1 | grep -v 'Connection\]'
//
// RECORDED: see the RECORDED block at the foot of this file (after the code).

import AppKit

final class W: NSWindow {
    nonisolated(unsafe) static var fakeKey = false
    override var isKeyWindow: Bool { W.fakeKey }
    override var canBecomeKey: Bool { true }
}

func spin(_ s: Double = 0.4) { RunLoop.current.run(until: Date(timeIntervalSinceNow: s)) }

func describe(_ ranges: [NSValue]) -> String {
    "[" + ranges.map { "\($0.rangeValue.location)+\($0.rangeValue.length)" }.joined(separator: ", ") + "]"
}

/// The first line's pixels classified: `sel` a non-white, non-dark fill (the selection), `caret` a dark bar, nothing for the background.
func scan(_ v: NSView, y: Int) -> String {
    guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return "no rep" }
    v.cacheDisplay(in: v.bounds, to: rep)
    var out = "", last = ""
    var x = 0
    var runs: [String] = []
    while x < Int(v.bounds.width) {
        guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { break }
        let tinted = c.brightnessComponent < 0.97   // the selection fill: any non-white, non-dark pixel
        let dark = c.brightnessComponent < 0.3
        let kind = dark ? "caret" : (tinted ? "sel" : "")
        if kind != last { if !kind.isEmpty { runs.append("\(kind)@\(x)") }; last = kind }
        x += 1
    }
    out = runs.isEmpty ? "(nothing drawn)" : runs.joined(separator: " ")
    return out
}

final class Delegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ n: Notification) {
        DispatchQueue.main.async { self.run(); exit(0) }
    }
    func run() {
        let win = W(contentRect: NSRect(x: 100, y: 100, width: 300, height: 60), styleMask: [.titled], backing: .buffered, defer: false)
        win.appearance = NSAppearance(named: .aqua)
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 60))
        tv.string = String(repeating: " ", count: 30)
        tv.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        tv.textColor = .clear
        tv.insertionPointColor = .black
        win.contentView = tv
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
        spin(1.0)
        W.fakeKey = true
        win.makeFirstResponder(tv); spin()
        print("setup: real key=\(win.isKeyWindow && NSApp.isActive) fake key=\(W.fakeKey) appActive=\(NSApp.isActive) firstResponder=\(win.firstResponder === tv)")
        let cases: [(String, [NSRange])] = [
            ("three zero-length ranges", [NSRange(location: 2, length: 0), NSRange(location: 8, length: 0), NSRange(location: 14, length: 0)]),
            ("mixed: caret, range, caret", [NSRange(location: 2, length: 0), NSRange(location: 6, length: 4), NSRange(location: 14, length: 0)]),
            ("mixed: range, caret, range", [NSRange(location: 1, length: 3), NSRange(location: 8, length: 0), NSRange(location: 12, length: 3)]),
            ("three non-empty ranges", [NSRange(location: 1, length: 3), NSRange(location: 8, length: 3), NSRange(location: 14, length: 3)]),
            ("one zero-length range", [NSRange(location: 5, length: 0)]),
        ]
        for (name, ranges) in cases {
            tv.setSelectedRanges(ranges.map { NSValue(range: $0) }, affinity: .downstream, stillSelecting: false)
            tv.needsDisplay = true; spin()
            print("\(name): given \(describe(ranges.map { NSValue(range: $0) })) kept \(describe(tv.selectedRanges)) first \(tv.selectedRange())")
            print("  drawn (first line, x runs): \(scan(tv, y: 6))")
        }
        win.close()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = Delegate()
app.delegate = delegate
app.run()

// RECORDED (2026-11-16, macOS 27.2 (Darwin 27.2.0), compiled with the command above; the process could not become the
// active application, so `real key=false` and the key window is faked, as in `appkit-inactive-selection.swift`; the
// text view was the first responder, so a caret is drawn):
//
//   setup: real key=false fake key=true appActive=false firstResponder=true
//   three zero-length ranges: given [2+0, 8+0, 14+0] kept [2+0] first {2, 0}
//     drawn (first line, x runs): (nothing drawn)
//   mixed: caret, range, caret: given [2+0, 6+4, 14+0] kept [2+0, 6+4] first {2, 0}
//     drawn (first line, x runs): (nothing drawn)
//   mixed: range, caret, range: given [1+3, 8+0, 12+3] kept [1+3, 12+3] first {1, 3}
//     drawn (first line, x runs): sel@13 sel@101
//   three non-empty ranges: given [1+3, 8+3, 14+3] kept [1+3, 8+3, 14+3] first {1, 3}
//     drawn (first line, x runs): sel@13 sel@69 sel@117
//   one zero-length range: given [5+0] kept [5+0] first {5, 0}
//     drawn (first line, x runs): caret@44 sel@46
//
// WHAT IT SAYS. AppKit drops zero-length ranges when there are several: three carets keep only the first; a
// caret between two ranges is dropped (the mixed case with a leading caret keeps the leading one and the range, and
// drops the trailing one); non-empty ranges all survive and all draw. A caret is drawn only when the one surviving range
// is a lone zero-length one, and never among several: AppKit has no multi-caret drawing. (The window was not key, so
// the blink phase and the insertion point's drawing were not observed beyond the single caret; the caret@44 case shows
// the bar was drawn there. The "mixed: caret, range, caret" case drew nothing in this scan although it kept a range:
// recorded as seen, not explained.) Xcode and VS Code draw every caret, so `CV-BG` is a MetalUI-only behaviour
// (class M), not a SwiftUI divergence.
