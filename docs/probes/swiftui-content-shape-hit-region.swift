// SwiftUI probe: WHERE is a view hit-testable, and what does `.contentShape`
// change? Measured by synthesizing real clicks into real NSWindows hosting
// SwiftUI, the harness the environment track's
// `swiftui-disabled-interaction.swift` established (its history section
// explains why the down/spin/up order and `FirstMouseHost` are needed).
//
// Evidence for rulings OM-I (MetalUI's default hit region is the element's
// frame, which is SwiftUI's `.contentShape(Rectangle())` and NOT SwiftUI's
// default), OM-J (`.contentShape(inset:)` is the deliverable subset) and OM-K
// (padding is hit-testable in MetalUI and not in SwiftUI) in
// docs/superpowers/2026-09-15-outer-modifiers-decisions.md.
//
// HOW TO RUN (both forms were run):
//
//   /usr/bin/swift docs/probes/swiftui-content-shape-hit-region.swift
//   xcrun swiftc docs/probes/swiftui-content-shape-hit-region.swift -o /tmp/om-hit
//   OS_ACTIVITY_DT_MODE=1 /tmp/om-hit
//
// It opens and orders out one small window per arm. Exit status 0.
//
// THE INSTRUMENT. Every arm is a 200x200 window. Each arm is clicked twice: at
// the CENTRE (100, 100) and at an EDGE point (20, 100), and both counts are
// printed. Window coordinates have their origin at the bottom left; every arm
// here is symmetric about both axes, so no flip matters.
//
// POSITIVE CONTROLS. H0: a full-window tappable Color reads centre 1, edge 1 —
// the harness delivers clicks at both points. H1 is the discriminating control
// for the contentShape arms: the SAME stack without `.contentShape` reads 0 at
// a point in its empty space, so a 1 in H2/H3 is the modifier and not the
// harness.
//
// RECORDED 2026-09-15, macOS 26.6.2 (25G83). Script form under /usr/bin/swift
// (Apple Swift 6.4, swiftlang-6.4.0.33.1) and compiled form under `xcrun swiftc`
// (the same 6.4): byte-identical stdout, exit 0 both, compiled stderr empty.
//
//   --- H: hit region, clicks at centre (100,100) and edge (20,100)
//     H0 full-window Color + tap (control)   : centre 1 edge 1
//     H1 stack, empty middle, tap, NO shape  : centre 0 edge 0
//     H2 stack + contentShape(Rectangle())   : centre 1 edge 1
//     H3 stack + contentShape(Rect inset 60) : centre 1 edge 0
//   --- P: is PADDING hit-testable? (40x40 colour, padding 80 = 200x200)
//     P1 colour.padding(80).onTapGesture     : centre 1 edge 0
//     P2 colour.onTapGesture.padding(80)     : centre 1 edge 0
//     P3 colour.padding(80).contentShape.tap : centre 1 edge 1
//     P4 colour.padding(80).background.tap  : centre 1 edge 1
//     P5 colour.padding(80).tap.background   : centre 1 edge 0
//   --- N: allowsHitTesting on the tappable itself
//     N1 full Color + tap, hit testing off   : centre 0 edge 0
//
// WHAT IT SHOWS.
// - H1 vs H2: SwiftUI's DEFAULT hit region is derived from what the view
//   draws — a stack's empty middle is not hittable (0/0) until
//   `.contentShape(Rectangle())` makes it so (1/1).
// - H3: `.contentShape(Rectangle().inset(by: 60))` SHRINKS the hit region:
//   the centre still hits, a point 20pt from the edge no longer does. A
//   content shape can therefore be smaller than the frame, which is the one
//   thing MetalUI's frame-shaped hitbox cannot express.
// - P1/P2: PADDING IS NOT HIT-TESTABLE in SwiftUI, in either order. MetalUI's
//   `.padding(80).onClick { }` registers at the padded bounds and reads edge 1
//   (measured the same session by a deleted scratch test,
//   `zzScratchPaddingHitRegion`: centre 1 edge 1).
// - P3/P4: `.contentShape(Rectangle())` and a `.background` declared BEFORE
//   the gesture each make the padding hittable (edge 1). P5 shows the
//   background must come before the gesture to do it. So MetalUI's behaviour
//   equals SwiftUI's for the filled case (P4) and diverges only for a padded,
//   background-less click target (P1).
// - N1: `.allowsHitTesting(false)` removes the region entirely.

import SwiftUI
import AppKit

/// The script is not a bundled app, so `NSApp.isActive` stays false and an
/// inactive window eats its first click unless the view accepts first mouse.
final class FirstMouseHost<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

enum Count {
    nonisolated(unsafe) static var hits: [String: Int] = [:]
    static func bump(_ k: String) { hits[k, default: 0] += 1 }
    static func take(_ k: String) -> Int { let v = hits[k, default: 0]; hits[k] = 0; return v }
}

@MainActor func spin(_ s: Double = 0.15) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

@MainActor func makeWindow<V: View>(_ view: V) -> NSWindow {
    let w = NSWindow(contentRect: CGRect(x: 200, y: 200, width: 200, height: 200),
                     styleMask: [.titled], backing: .buffered, defer: false)
    w.isReleasedWhenClosed = false
    w.contentView = FirstMouseHost(rootView: view)
    w.makeKeyAndOrderFront(nil)
    spin()
    return w
}

@MainActor func click(_ w: NSWindow, at p: CGPoint) {
    func ev(_ t: NSEvent.EventType) -> NSEvent {
        NSEvent.mouseEvent(with: t, location: p, modifierFlags: [],
                           timestamp: ProcessInfo.processInfo.systemUptime,
                           windowNumber: w.windowNumber, context: nil, eventNumber: 0,
                           clickCount: 1, pressure: t == .leftMouseDown ? 1 : 0)!
    }
    w.sendEvent(ev(.leftMouseDown))
    spin(0.05)
    w.sendEvent(ev(.leftMouseUp))
    spin()
}

let centre = CGPoint(x: 100, y: 100)
let edge = CGPoint(x: 20, y: 100)

/// Clicks the same arm twice in two fresh windows, so one click cannot mask the
/// other, and prints both counts.
@MainActor func arm<V: View>(_ label: String, _ make: @escaping () -> V) {
    _ = Count.take("hit")
    let w1 = makeWindow(make())
    click(w1, at: centre)
    let c = Count.take("hit")
    w1.orderOut(nil)
    let w2 = makeWindow(make())
    click(w2, at: edge)
    let e = Count.take("hit")
    w2.orderOut(nil)
    print("  \(label): centre \(c) edge \(e)")
}

/// A 200x200 stack whose middle is EMPTY: two short texts pinned to the ends.
@MainActor func gappyStack() -> some View {
    VStack {
        Text("top")
        Spacer()
        Text("bottom")
    }
    .frame(width: 200, height: 200)
}

@MainActor func run() {
    print("--- H: hit region, clicks at centre (100,100) and edge (20,100)")
    arm("H0 full-window Color + tap (control)   ") {
        Color.blue.onTapGesture { Count.bump("hit") }
    }
    arm("H1 stack, empty middle, tap, NO shape  ") {
        gappyStack().onTapGesture { Count.bump("hit") }
    }
    arm("H2 stack + contentShape(Rectangle())   ") {
        gappyStack().contentShape(Rectangle()).onTapGesture { Count.bump("hit") }
    }
    arm("H3 stack + contentShape(Rect inset 60) ") {
        gappyStack().contentShape(Rectangle().inset(by: 60)).onTapGesture { Count.bump("hit") }
    }
    print("--- P: is PADDING hit-testable? (40x40 colour, padding 80 = 200x200)")
    arm("P1 colour.padding(80).onTapGesture     ") {
        Color.blue.frame(width: 40, height: 40).padding(80)
            .onTapGesture { Count.bump("hit") }
    }
    arm("P2 colour.onTapGesture.padding(80)     ") {
        Color.blue.frame(width: 40, height: 40)
            .onTapGesture { Count.bump("hit") }.padding(80)
    }
    arm("P3 colour.padding(80).contentShape.tap ") {
        Color.blue.frame(width: 40, height: 40).padding(80)
            .contentShape(Rectangle()).onTapGesture { Count.bump("hit") }
    }
    arm("P4 colour.padding(80).background.tap  ") {
        Color.blue.frame(width: 40, height: 40).padding(80)
            .background(Color.green).onTapGesture { Count.bump("hit") }
    }
    arm("P5 colour.padding(80).tap.background   ") {
        Color.blue.frame(width: 40, height: 40).padding(80)
            .onTapGesture { Count.bump("hit") }.background(Color.green)
    }
    print("--- N: allowsHitTesting on the tappable itself")
    arm("N1 full Color + tap, hit testing off   ") {
        Color.blue.onTapGesture { Count.bump("hit") }.allowsHitTesting(false)
    }
}

MainActor.assumeIsolated { run() }
