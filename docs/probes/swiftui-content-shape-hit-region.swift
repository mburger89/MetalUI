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
// RE-RECORDED 2026-09-16 00:03 PDT (lane 3's review round), same machine and
// toolchain, with four additive arms X0–X3: `.allowsHitTesting(false)` with a
// `.padding` layer between it and the gesture, in both orders, and the X1
// chain with a later `.contentShape(Rectangle())`. Every pre-existing arm
// re-read its recorded value byte for byte in the same run. Exit 0. The
// verifier's scratch copy (23:58 PDT) read X0, X1 and X3 identically; X2 is
// new here.
//
// RE-RECORDED AGAIN 2026-09-15 (lane 3), same machine and toolchain, with three
// additive arms H4–H6: a content shape BIGGER than the frame, and whether an
// ancestor `.clipped()` bounds it. Every pre-existing arm re-read its recorded
// value byte for byte in the same run. Exit 0.
//
// RE-RECORDED 2026-09-15 (design review round 2), macOS 26.6.2 (25G83), after
// critic finding 1. One additive arm, N2: `.allowsHitTesting(false)` written
// BEFORE the gesture rather than after it. N1 alone could not say whether the
// order is observable, and the spec's §5.2 mechanism registered the receiver's
// own handlers OUTSIDE the scope it opened. Script form under /usr/bin/swift
// (Apple Swift 6.4, swiftlang-6.4.0.33.1) and compiled form under `xcrun swiftc`
// (the same 6.4): byte-identical stdout, exit 0 both, compiled stderr empty.
//
//   --- H: hit region, clicks at centre (100,100) and edge (20,100)
//     H0 full-window Color + tap (control)   : centre 1 edge 1
//     H1 stack, empty middle, tap, NO shape  : centre 0 edge 0
//     H2 stack + contentShape(Rectangle())   : centre 1 edge 1
//     H3 stack + contentShape(Rect inset 60) : centre 1 edge 0
//     H4 80x80 colour + tap (control)        : centre 1 edge 0
//     H5 the same + contentShape(inset -60)  : centre 1 edge 1
//     H6 H5 inside a 100x100 .clipped()      : centre 1 edge 1
//   --- P: is PADDING hit-testable? (40x40 colour, padding 80 = 200x200)
//     P1 colour.padding(80).onTapGesture     : centre 1 edge 0
//     P2 colour.onTapGesture.padding(80)     : centre 1 edge 0
//     P3 colour.padding(80).contentShape.tap : centre 1 edge 1
//     P4 colour.padding(80).background.tap  : centre 1 edge 1
//     P5 colour.padding(80).tap.background   : centre 1 edge 0
//   --- N: allowsHitTesting on the tappable itself
//     N1 full Color + tap, hit testing off   : centre 0 edge 0
//     N2 full Color, hit testing off, THEN tap: centre 0 edge 0
//   --- X: allowsHitTesting across a padding layer (120x120 colour, padding 40)
//     X0 colour.padding(40).tap (control)      : centre 1 edge 0
//     X1 colour.hitOff.padding(40).tap         : centre 0 edge 0
//     X2 colour.padding(40).hitOff.tap         : centre 0 edge 0
//     X3 X1 + contentShape(Rectangle()) then tap: centre 1 edge 1
//
// WHAT IT SHOWS.
// - H1 vs H2: SwiftUI's DEFAULT hit region is derived from what the view
//   draws — a stack's empty middle is not hittable (0/0) until
//   `.contentShape(Rectangle())` makes it so (1/1).
// - H4 vs H5: a NEGATIVE inset GROWS the region past the view's own frame —
//   a point 40pt outside an 80x80 leaf hits it. MetalUI accepts a negative
//   `contentShape(inset:)` for this reason (ruling OM-J).
// - H5 vs H6: an ancestor `.clipped()` does **not** bound the grown region in
//   SwiftUI — the edge point hits through the clip. MetalUI's does: every
//   registered hitbox is intersected with the active clip in
//   `Frame.insertHitbox`, which is what makes a hitbox for content that is not
//   drawn unreachable. A recorded divergence (ruling OM-AJ), pinned by
//   `aNegativeContentShapeInsetGrowsTheHitRegionAndIsStillClippedByAnAncestor`.
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
// - N1: `.allowsHitTesting(false)` removes the region entirely — INCLUDING the
//   receiver's own gesture, which is written before it. A mechanism that opens
//   the disabled scope only around the CHILDREN reproduces neither N1 nor N2.
// - **N1 == N2: the order is NOT observable.** A gesture attached AFTER
//   `.allowsHitTesting(false)` is dead too (0/0), because the modifier empties
//   the subtree's hit region and the later gesture has nothing to attach to.
//   MetalUI's legacy path stores both on ONE `Handlers` and so cannot tell the
//   two orders apart — which here is AGREEMENT, not a divergence, and removes a
//   row that would otherwise have joined OM-H's not-expressible list.
//   **That agreement holds within ONE `ModifierLayer` only** — see X.
// - X0 vs X1 vs X2: with a `.padding(40)` between the scope and the gesture,
//   SwiftUI reads 0/0 in BOTH orders (X1, X2), against the control's 1/0
//   (X0). In MetalUI the two orders differ: `.allowsHitTesting(false)
//   .padding(40).onClick { }` (X1's spelling) puts the scope on the INNER
//   layer and the click on the OUTER one, and the outer layer's hitbox is
//   live — centre 1, edge 1; the reverse (X2's spelling) puts both on the
//   outer layer and reads 0/0. A recorded divergence (ruling OM-AL), pinned by
//   `anInnerLayersAllowsHitTestingDoesNotReachAClickOnALayerWrittenAfterIt`.
// - X3 is WHY the divergence is OM-I's and not a new mechanism. SwiftUI's
//   `.allowsHitTesting(false)` empties the subtree's hit REGION and does not
//   kill a later layer's gesture: `.contentShape(Rectangle())` written after
//   the padding gives the outer gesture a region again and X3 reads 1/1.
//   MetalUI's default region is always the frame (OM-I, H1 vs H2), so its X1
//   answer IS SwiftUI's X3 — there is no spelling for "no region" to lose. A
//   MetalUI fix that let an inner layer's scope suppress the layers written
//   after it would reproduce X1 and contradict X3 in the same stroke.

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
    // H4–H6, added 2026-09-15 by lane 3: can a content shape be BIGGER than
    // the frame, and does an ancestor still bound it? MetalUI accepts a
    // negative inset (ruling OM-J) and `Frame.insertHitbox` intersects every
    // registered region with the active clip, so both halves are claims about
    // MetalUI that wanted SwiftUI arms rather than a derivation.
    //
    // **The trailing `.frame(200, 200)` on all three is the instrument, not
    // decoration.** Without it the `NSHostingView` sizes itself to the root's
    // 80x80 ideal and AppKit's own `hitTest` throws away every click outside
    // that 80x80 before SwiftUI sees it — measured: an arm with no outer frame
    // read 0/0 whether or not the shape was grown, because the clicks never
    // arrived. The outer frame makes the host 200x200 and centres the subject
    // in it (x 60…140), so the edge point (20, 100) is a real miss rather than
    // an undelivered event.
    arm("H4 80x80 colour + tap (control)        ") {
        Color.blue.frame(width: 80, height: 80).onTapGesture { Count.bump("hit") }
            .frame(width: 200, height: 200)
    }
    arm("H5 the same + contentShape(inset -60)  ") {
        Color.blue.frame(width: 80, height: 80)
            .contentShape(Rectangle().inset(by: -60)).onTapGesture { Count.bump("hit") }
            .frame(width: 200, height: 200)
    }
    arm("H6 H5 inside a 100x100 .clipped()      ") {
        Color.blue.frame(width: 80, height: 80)
            .contentShape(Rectangle().inset(by: -60)).onTapGesture { Count.bump("hit") }
            .frame(width: 100, height: 100).clipped()
            .frame(width: 200, height: 200)
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
    // N2: the REVERSE order. `.allowsHitTesting` is a wrapping modifier in
    // SwiftUI, so a gesture attached OUTSIDE it should survive. MetalUI's
    // legacy path stores both on ONE `Handlers` and cannot tell the two orders
    // apart — added after the first recording, because N1 alone cannot say
    // whether the order is observable at all.
    arm("N2 full Color, hit testing off, THEN tap") {
        Color.blue.allowsHitTesting(false).onTapGesture { Count.bump("hit") }
    }
    // X0–X3, added 2026-09-16 by lane 3's review round (verifier finding 1):
    // the same two orders with a WRAPPING modifier between the scope and the
    // gesture. N1 == N2 says nothing about a chain that crosses a layer, and
    // MetalUI's `.allowsHitTesting(false).padding(40).onClick { }` puts the
    // scope on the INNER layer and the click on the OUTER one. A 120x120 colour
    // padded by 40 fills the 200x200 window, so the edge point (20, 100) lies
    // in the padding and the centre in the colour.
    print("--- X: allowsHitTesting across a padding layer (120x120 colour, padding 40)")
    arm("X0 colour.padding(40).tap (control)      ") {
        Color.blue.frame(width: 120, height: 120).padding(40)
            .onTapGesture { Count.bump("hit") }
    }
    arm("X1 colour.hitOff.padding(40).tap         ") {
        Color.blue.frame(width: 120, height: 120).allowsHitTesting(false).padding(40)
            .onTapGesture { Count.bump("hit") }
    }
    arm("X2 colour.padding(40).hitOff.tap         ") {
        Color.blue.frame(width: 120, height: 120).padding(40).allowsHitTesting(false)
            .onTapGesture { Count.bump("hit") }
    }
    arm("X3 X1 + contentShape(Rectangle()) then tap") {
        Color.blue.frame(width: 120, height: 120).allowsHitTesting(false).padding(40)
            .contentShape(Rectangle()).onTapGesture { Count.bump("hit") }
    }
    // S0–S3, added 2026-09-16 by the tasks 4–5 integration step (lane 3's
    // verifier finding, carried as an open item by the outer-modifier track):
    // `.contentShape` across a padding layer, in both orders. MetalUI's
    // `.contentShape(inset: 20).padding(40).onClick { }` puts the inset on the
    // INNER layer, whose `Handlers` carry no `onClick`, so it registers nothing
    // and the outer layer's frame-shaped hitbox is live. These arms need a
    // third click point, in the colour's own outer 20pt band, so they use
    // `arm3` (centre (100,100), band (50,100), edge (10,100)); the existing
    // arms and their two points are unchanged.
    print("--- S: contentShape across a padding layer (120x120 colour at 40…160, padding 40)")
    arm3("S0 colour.padding(40).tap (control)          ") {
        Color.blue.frame(width: 120, height: 120).padding(40)
            .onTapGesture { Count.bump("hit") }
    }
    arm3("S1 colour.shape(inset 20).padding(40).tap    ") {
        Color.blue.frame(width: 120, height: 120)
            .contentShape(Rectangle().inset(by: 20)).padding(40)
            .onTapGesture { Count.bump("hit") }
    }
    arm3("S2 colour.padding(40).shape(inset 20).tap    ") {
        Color.blue.frame(width: 120, height: 120).padding(40)
            .contentShape(Rectangle().inset(by: 20))
            .onTapGesture { Count.bump("hit") }
    }
    arm3("S3 colour.padding(40).shape(Rectangle()).tap ") {
        Color.blue.frame(width: 120, height: 120).padding(40)
            .contentShape(Rectangle())
            .onTapGesture { Count.bump("hit") }
    }
}

/// `arm` with three points, each in a fresh window: the centre, a point in the
/// subject's outer band, and an edge point in the padding.
@MainActor func arm3<V: View>(_ label: String, _ make: @escaping () -> V) {
    var counts: [Int] = []
    for p in [CGPoint(x: 100, y: 100), CGPoint(x: 50, y: 100), CGPoint(x: 10, y: 100)] {
        _ = Count.take("hit")
        let w = makeWindow(make())
        click(w, at: p)
        counts.append(Count.take("hit"))
        w.orderOut(nil)
    }
    print("  \(label): centre \(counts[0]) band \(counts[1]) edge \(counts[2])")
}

MainActor.assumeIsolated { run() }
