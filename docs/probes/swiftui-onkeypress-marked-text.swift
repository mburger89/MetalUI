// SwiftUI probe: `onKeyPress` while the field editor holds marked text (ruling KF-AB, Alloy G14).
//
// HOW TO RUN (SA-O's compiled form, as `swiftui-key-focus.swift`):
//
//   xcrun swiftc docs/probes/swiftui-onkeypress-marked-text.swift -o /tmp/mt-probe && /tmp/mt-probe
//
// THE INSTRUMENT: a `KeyWindow` (always key) hosting a focused `TextField` with `.onKeyPress(keys: [.downArrow,
// .escape])` returning `.handled`; marked text is put into the SwiftUI field editor (an NSTextView) with
// `setMarkedText`, then ↓ and Esc go through `NSApp.sendEvent`.
//
// RECORDED 2026-11-08, macOS 27.2, Apple Swift 6.4.2:
//   no composition: ["kp:63233", "kp:27"]
//   hasMarkedText: true
//   composing: ["kp:63233", "kp:27"] hasMarkedText after: true
//
// READING AND LIMIT. NO REAL INPUT METHOD WAS ATTACHED, so nothing could consume the keys: the probe shows only that
// a key the input context DECLINES is delivered to `onKeyPress` with marked text present (and Esc does not cancel it).
// It does not show what a real IME consumes; AppKit offers the key to the input context first (`NSTextInputContext`),
// and MetalUI's `MetalHostView.keyDown` does the same, so a consumed key never reaches `Window`.

import AppKit
import SwiftUI

final class KeyWindow: NSWindow { override var isKeyWindow: Bool { true }; override var canBecomeKey: Bool { true } }
var log: [String] = []
struct V: View {
    @State var t = ""
    @FocusState var f: Bool
    var body: some View {
        TextField("x", text: $t).focused($f).onAppear { f = true }
            .onKeyPress(keys: [.downArrow, .escape]) { p in log.append("kp:\(p.key.character.unicodeScalars.first!.value)"); return .handled }
            .frame(width: 200, height: 40)
    }
}
func spin(_ s: Double = 0.2) { RunLoop.main.run(until: Date(timeIntervalSinceNow: s)) }
func key(_ c: String, _ code: UInt16, _ w: NSWindow) {
    for type in [NSEvent.EventType.keyDown, .keyUp] {
        let e = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: w.windowNumber, context: nil, characters: c, charactersIgnoringModifiers: c, isARepeat: false, keyCode: code)!
        NSApp.sendEvent(e); spin(0.1)
    }
}
let app = NSApplication.shared; app.setActivationPolicy(.regular)
let w = KeyWindow(contentRect: NSRect(x: 100, y: 100, width: 200, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
w.contentView = NSHostingView(rootView: V()); w.makeKeyAndOrderFront(nil); app.activate(ignoringOtherApps: true); spin(0.6)
print("firstResponder:", String(describing: w.firstResponder))
let down = String(UnicodeScalar(0xF701)!), esc = "\u{1b}"
log = []; key(down, 125, w); key(esc, 53, w); print("no composition:", log)
if let tv = w.firstResponder as? NSTextView {
    tv.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
    print("hasMarkedText:", tv.hasMarkedText())
    log = []; key(down, 125, w); key(esc, 53, w); print("composing:", log, "hasMarkedText after:", tv.hasMarkedText())
}
