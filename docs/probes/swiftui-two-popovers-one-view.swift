import AppKit
import SwiftUI

// SwiftUI probe: two `.popover`s chained on one macOS view, both presented (ruling `CV-BC`, record 332: Alloy
// code-intel #4, a completion popover and a hover popover on one editor). Which show, and which one Escape dismisses.
//
// HOW TO RUN (compiled form, SA-O):
//
//   xcrun swiftc docs/probes/swiftui-two-popovers-one-view.swift -o /tmp/two-popovers
//   /tmp/two-popovers
//
// THE INSTRUMENT. A window hosting `Button("Anchor").popover(isPresented: $a) { Text("ONE") }.popover(isPresented: $b)
// { Text("TWO") }`; both flags are set true and the run loop spun, then `NSApp.windows` is listed by class
// (`_NSPopoverWindow` is a presented popover) and Escape (a synthesized NSEvent through `NSApp.sendEvent`, sent to
// each popover window and to the host) is sent twice, the flags read back after each. POSITIVE CONTROL: arm T0, the
// same host with only the first flag set (one popover window), and arm T1, the flags read back before any key.
//
// RECORDED OUTPUT (2026-11-16, macOS 27.2.1, Apple Swift 6.4.2, screen LOCKED so the app never became active and no
// window was key; compiled form, run twice, stdout byte-identical, exit 0):
//
//   active=false host key=false screenLocked=true
//   T0 only a: a=true b=false popover windows=1
//   T1 a and b: a=false b=true popover windows=1 frames=["{{405, 512}, {89, 74}}"]
//      window 0 key=false level=0
//   T2 Escape to host: a=false b=true popover windows=1
//   T3.0 Escape to popover window 0: a=false b=true popover windows=1
//   T4 Escape to the key window again: a=false b=true popover windows=1
//   T5.0 both false: popover windows=0
//   T5.1 a then b in one turn: a=true b=true popover windows=1
//   T5.2 b then a in one turn: a=true b=true popover windows=1
//
// READING. (1) Both flags true never gave two popover windows: SwiftUI presents ONE popover per host. (2) With `a` open,
// writing `b = true` made SwiftUI write `a = false` itself (T1): the later presentation dismisses the earlier through
// its binding. (3) Both written in one run-loop turn (T5.1, T5.2, either order) leave both flags true and one window;
// which of the two it shows was not read (the windows' contents are not reachable from here). (4) Escape was NOT
// observable: with the app inactive and no key window, a synthesized Escape to the host and to the popover window
// dismissed nothing, as in `swiftui-menus-popovers.swift` P3/P3b, so which popover Escape dismisses is unrecorded.
// MetalUI keeps ruling `MN-N` (every open popover is a presentation; Escape takes the topmost) and so shows two
// popovers presented together where SwiftUI shows one; recorded in `CV-BC`, not a new divergence row (class M).

struct Probe: View {
    @ObservedObject var m: TwoModel
    var body: some View {
        Button("Anchor") {}
            .popover(isPresented: $m.a) { Text("ONE").padding() }
            .popover(isPresented: $m.b) { Text("TWO").padding() }
            .frame(width: 300, height: 200)
    }
}

final class TwoModel: ObservableObject {
    @Published var a = false
    @Published var b = false
}

@MainActor func spin(_ s: Double = 0.4) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
@MainActor func popoverWindows() -> [NSWindow] { NSApp.windows.filter { $0.isVisible && "\(type(of: $0))".contains("Popover") } }
@MainActor func escape(_ w: NSWindow) -> NSEvent {
    NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                     windowNumber: w.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
                     isARepeat: false, keyCode: 53)!
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
MainActor.assumeIsolated {
    let m = TwoModel()
    let w = NSWindow(contentRect: NSRect(x: 300, y: 400, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
    w.isReleasedWhenClosed = false
    let h = NSHostingView(rootView: Probe(m: m))
    w.contentView = h
    w.orderFrontRegardless(); w.makeKey(); h.layoutSubtreeIfNeeded(); spin()
    print("active=\(app.isActive) host key=\(w.isKeyWindow) screenLocked=\(((CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool) ?? false)")
    m.a = true; spin(0.8)
    print("T0 only a: a=\(m.a) b=\(m.b) popover windows=\(popoverWindows().count)")
    m.b = true; spin(0.8)
    let pws = popoverWindows()
    print("T1 a and b: a=\(m.a) b=\(m.b) popover windows=\(pws.count) frames=\(pws.map { NSStringFromRect($0.frame) })")
    for (i, pw) in pws.enumerated() { print("   window \(i) key=\(pw.isKeyWindow) level=\(pw.level.rawValue)") }
    // Escape to the host, then to each popover window in turn, reading the flags back after each.
    NSApp.sendEvent(escape(w)); spin(0.6)
    print("T2 Escape to host: a=\(m.a) b=\(m.b) popover windows=\(popoverWindows().count)")
    for (i, pw) in popoverWindows().enumerated() {
        pw.makeKey(); spin(0.2)
        NSApp.sendEvent(escape(pw)); spin(0.6)
        print("T3.\(i) Escape to popover window \(i): a=\(m.a) b=\(m.b) popover windows=\(popoverWindows().count)")
    }
    NSApp.sendEvent(escape(NSApp.keyWindow ?? w)); spin(0.6)
    print("T4 Escape to the key window again: a=\(m.a) b=\(m.b) popover windows=\(popoverWindows().count)")
    // T5: both flags written in one transaction (the same run-loop turn), the second written last; then b first.
    m.a = false; m.b = false; spin(0.8)
    print("T5.0 both false: popover windows=\(popoverWindows().count)")
    m.a = true; m.b = true; spin(0.8)
    print("T5.1 a then b in one turn: a=\(m.a) b=\(m.b) popover windows=\(popoverWindows().count)")
    m.a = false; m.b = false; spin(0.8)
    m.b = true; m.a = true; spin(0.8)
    print("T5.2 b then a in one turn: a=\(m.a) b=\(m.b) popover windows=\(popoverWindows().count)")
}
