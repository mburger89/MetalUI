// SwiftUI probe: defaultScrollAnchor(_:) and defaultScrollAnchor(_:for:) with
// ScrollAnchorRole (.initialOffset, .sizeChanges, .alignment), for Alloy gap G6
// (stick-to-bottom on a LazyVStack transcript; decisions DSA-A.. in
// docs/superpowers/2026-11-07-default-scroll-anchor-decisions.md).
//
// HOW TO RUN (ruling SA-O):
//
//   /usr/bin/swift docs/probes/swiftui-default-scroll-anchor.swift
//   xcrun swiftc -O docs/probes/swiftui-default-scroll-anchor.swift -o /tmp/dsa && /tmp/dsa
//
// `/usr/bin/swift` is Apple's toolchain; a swift.org toolchain's JIT fails on
// SwiftUI symbols.
//
// METHOD. The view is hosted in a 200x200 borderless NSWindow (ordered front
// regardless, no screen capture; it needs an unlocked session only for the run
// loop to deliver layout, which it did). The first NSScrollView under the hosting
// view is the instrument: `clip.bounds.origin.y` is the offset (the hosted
// document view is flipped, 0 = top) and `documentView.frame.height` the content
// extent; `bottom` prints `maxOffset - offset` (0 = at the bottom). A user scroll
// is `clip.scroll(to:)` + `reflectScrolledClipView`, as in
// swiftui-lazy-containers.swift. Content grows by a model write (rows appended)
// and the run loop is spun. Every arm has a CONTROL: the same scroller without
// the modifier (B0/G0/...), so a reading that does not differ from it is not the
// modifier's.
//
// RECORDED 2026-11-07 by the default-scroll-anchor session (Alloy gap G6), macOS 27.2, Apple Swift
// 6.4.2 (swiftlang-6.4.2.1.9), screen state: the borderless window was ordered front without a screen
// capture and every arm printed (the run loop delivered layout). Compiled form (`xcrun swiftc -O`), run twice:
// the two stdouts differ only in the 1-2 point rubber-band residue of the last wheel gesture in W-arms
// (offset 2201 / 2202, fromBottom -1 / -2); everything else is byte-identical. 64 lines.
//
// A user scroll is a real wheel event: `wheel(_:dy:)` builds a phased, precise-delta CGEvent scroll wheel
// event and hands it to the NSScrollView; `clip.scroll(to:)` (arms `G2`, `G3`, `G5`, `G6`) is NOT a user
// scroll to SwiftUI (G2: a `.bottom` scroller "scrolled up" that way jumps back to the end on the next
// append; G6: a `.sizeChanges` scroller "scrolled to the bottom" that way does not follow) - those arms are
// kept as the recorded reason the W arms exist.
//
// THE READING (each line names the arm).
// 1. API. `defaultScrollAnchor(_:)` and `defaultScrollAnchor(_:for:)` with `ScrollAnchorRole` `.initialOffset`,
//    `.sizeChanges`, `.alignment` all exist on macOS 27 (macOS 15 and later).
// 2. INITIAL. No modifier: offset 0 (I0). `.bottom`: offset = content - viewport (I1 1800 of 2000), `.center` 900
//    (I3), `.top` 0 (I2), UnitPoint(0, 0.25) 450 (I6). An eager VStack is the same as a lazy one (I5). A
//    horizontal anchor on a vertical scroller reads the other component's value for the cross axis: `.leading`
//    (y = 0.5) centres (I4); `.bottom` on a horizontal scroller centres (H2); `.trailing` starts a horizontal
//    scroller at its end (H1) and `.leading` at its start (H3).
// 3. FOLLOW. The plain `.bottom` (all three roles) keeps the end in view when rows are appended while the
//    scroller is at the end (G1: 2000 -> 2400, offset 1800 -> 2200, fromBottom 0), through variable heights
//    (V1: 5230 -> 5910 -> 6550, always fromBottom 0), and when an eager block above grows (T1 at the bottom:
//    1800 -> 1900). `.center` and fractional anchors do NOT follow (I3, I6: the offset stays). The control
//    never moves (I0, G0).
// 4. RELEASE AND RE-ENGAGE (wheel). W1 `.bottom`: wheel up 470 -> an append leaves the offset (1330 -> 1330,
//    fromBottom 470 -> 870); a wheel back to the end (fromBottom -2) -> the next append follows again (2600,
//    fromBottom 0). T1 wheeled up 500 with a block above growing: the offset holds (1300).
// 5. ROLES. R1/W3 `.initialOffset`: starts at the end, follows, released by the wheel, and does NOT re-engage
//    on the return (W3 last append: 2202, fromBottom 398). R2/G4/W2 `.sizeChanges`: starts at the top (0), an
//    append from the top stays (G4), a wheel to the end then an append follows (W2 2600), and a wheel up
//    releases (T2). R3/W4 `.alignment`: starts at the top, never follows overflowing content (W4 398 from the
//    bottom). The plain overload is all three (R4 = I1, W1 = R1 + R2 behaviour).
// 6. ALIGNMENT OF SHORT CONTENT. 5 rows (100 of 200): `.bottom` offset -100 (S1; N1: 3 rows -140), then 20
//    more rows -> 300, fromBottom 0 (it follows once it overflows); `for: .alignment` the same (S2);
//    `for: .sizeChanges` alone does not align (S3: 0) and does not follow (500, offset 0); control 0 (S0).
// 7. PRECEDENCE (O). Per role, the role's own anchor beats the all-roles one whatever the order (O5, O6), among
//    two for one role the INNER (first call) wins (O1 `.bottom` then `.top` -> bottom; O2 -> top), `nil` declares
//    nothing (O3, O4), and the modifier works through an ancestor (O7) and a wrapper (O8).
// 8. EXPLICIT POSITION. `scrollTo(10, .top)` and `scrollPosition(id: 10)` win over the initial bottom (P1, P2:
//    offset 200).
// 9. A lazy block above the viewport is never realised, so growing it changes nothing (the first, lazy form of
//    T read content 2000 -> 2000); T is therefore an EAGER VStack whose row 3 reads the model in its own body (a
//    ForEach does not re-run its closure for an unchanged id).
//
// WHOLE STDOUT:
//
//   === I: initial offset (100 rows x 20 = 2000 in 200)
//   I0 control, no modifier: initial offset 0.0 content 2000.0 viewport 200.0 fromBottom 1800.0 | after +20 rows: offset 0.0 content 2400.0 viewport 200.0 fromBottom 2200.0
//   I1 .defaultScrollAnchor(.bottom): initial offset 1800.0 content 2000.0 viewport 200.0 fromBottom 0.0 | after +20 rows: offset 2200.0 content 2400.0 viewport 200.0 fromBottom 0.0
//   I2 .defaultScrollAnchor(.top): initial offset 0.0 content 2000.0 viewport 200.0 fromBottom 1800.0 | after +20 rows: offset 0.0 content 2400.0 viewport 200.0 fromBottom 2200.0
//   I3 .defaultScrollAnchor(.center): initial offset 900.0 content 2000.0 viewport 200.0 fromBottom 900.0 | after +20 rows: offset 900.0 content 2400.0 viewport 200.0 fromBottom 1300.0
//   I4 .defaultScrollAnchor(.leading) (a horizontal anchor on a vertical scroller): initial offset 900.0 content 2000.0 viewport 200.0 fromBottom 900.0 | after +20 rows: offset 900.0 content 2400.0 viewport 200.0 fromBottom 1300.0
//   I5 .defaultScrollAnchor(.bottom) eager VStack: initial offset 1800.0 content 2000.0 viewport 200.0 fromBottom 0.0 | after +20 rows: offset 2200.0 content 2400.0 viewport 200.0 fromBottom 0.0
//   I6 .defaultScrollAnchor(UnitPoint(x: 0, y: 0.25)): initial offset 450.0 content 2000.0 viewport 200.0 fromBottom 1350.0 | after +20 rows: offset 450.0 content 2400.0 viewport 200.0 fromBottom 1750.0
//   === R: roles
//   R1 .bottom for .initialOffset: initial offset 1800.0 content 2000.0 viewport 200.0 fromBottom 0.0 | after +20 rows: offset 2200.0 content 2400.0 viewport 200.0 fromBottom 0.0
//   R2 .bottom for .sizeChanges: initial offset 0.0 content 2000.0 viewport 200.0 fromBottom 1800.0 | after +20 rows: offset 0.0 content 2400.0 viewport 200.0 fromBottom 2200.0
//   R3 .bottom for .alignment: initial offset 0.0 content 2000.0 viewport 200.0 fromBottom 1800.0 | after +20 rows: offset 0.0 content 2400.0 viewport 200.0 fromBottom 2200.0
//   R4 .bottom + .bottom for .sizeChanges: initial offset 1800.0 content 2000.0 viewport 200.0 fromBottom 0.0 | after +20 rows: offset 2200.0 content 2400.0 viewport 200.0 fromBottom 0.0
//   R5 .bottom for .initialOffset + .top for .sizeChanges: initial offset 1800.0 content 2000.0 viewport 200.0 fromBottom 0.0 | after +20 rows: offset 2200.0 content 2400.0 viewport 200.0 fromBottom 0.0
//   R6 .top + .bottom for .sizeChanges: initial offset 0.0 content 2000.0 viewport 200.0 fromBottom 1800.0 | after +20 rows: offset 0.0 content 2400.0 viewport 200.0 fromBottom 2200.0
//   === O: order of two modifiers on one scroller (the later call is the OUTER view), and an ancestor
//   O1 .bottom then .top (outer .top): initial offset 1800.0 content 2000.0 viewport 200.0 fromBottom 0.0 | after +20 rows: offset 2200.0 content 2400.0 viewport 200.0 fromBottom 0.0
//   O2 .top then .bottom (outer .bottom): initial offset 0.0 content 2000.0 viewport 200.0 fromBottom 1800.0 | after +20 rows: offset 0.0 content 2400.0 viewport 200.0 fromBottom 2200.0
//   O3 .bottom then nil (outer nil): initial offset 1800.0 content 2000.0 viewport 200.0 fromBottom 0.0 | after +20 rows: offset 2200.0 content 2400.0 viewport 200.0 fromBottom 0.0
//   O4 nil then .bottom (outer .bottom): initial offset 1800.0 content 2000.0 viewport 200.0 fromBottom 0.0 | after +20 rows: offset 2200.0 content 2400.0 viewport 200.0 fromBottom 0.0
//   O5 .top, outer .bottom for .initialOffset only: initial offset 1800.0 content 2000.0 viewport 200.0 fromBottom 0.0 | after +20 rows: offset 2200.0 content 2400.0 viewport 200.0 fromBottom 0.0
//   O6 .bottom for .initialOffset, outer .top (all roles): initial offset 1800.0 content 2000.0 viewport 200.0 fromBottom 0.0 | after +20 rows: offset 2200.0 content 2400.0 viewport 200.0 fromBottom 0.0
//   O7 modifier on an ancestor VStack, not on the ScrollView: initial offset 1800.0 content 2000.0 viewport 200.0 fromBottom 0.0 | after +20 rows: offset 2200.0 content 2400.0 viewport 200.0 fromBottom 0.0
//   O8 modifier on a .frame()d scroll view (a wrapper between): initial offset 1800.0 content 2000.0 viewport 200.0 fromBottom 0.0 | after +20 rows: offset 2200.0 content 2400.0 viewport 200.0 fromBottom 0.0
//   === G: growth while at the bottom / after a user scroll up (rows appended)
//   G0 control, user at offset 1800 (bottom), +20: initial offset 0.0 content 2000.0 viewport 200.0 fromBottom 1800.0 | after user scroll to 1800.0: offset 1800.0 content 2000.0 viewport 200.0 fromBottom 0.0 | after +20 rows: offset 1800.0 content 2400.0 viewport 200.0 fromBottom 400.0
//   G1 .bottom, +20, not touched: initial offset 1800.0 content 2000.0 viewport 200.0 fromBottom 0.0 | after +20 rows: offset 2200.0 content 2400.0 viewport 200.0 fromBottom 0.0
//   G2 .bottom, user scrolled UP to 500, +20: initial offset 1800.0 content 2000.0 viewport 200.0 fromBottom 0.0 | after user scroll to 500.0: offset 500.0 content 2000.0 viewport 200.0 fromBottom 1300.0 | after +20 rows: offset 2200.0 content 2400.0 viewport 200.0 fromBottom 0.0
//   G3 .bottom, user scrolled to the bottom 1800 then +20: initial offset 1800.0 content 2000.0 viewport 200.0 fromBottom 0.0 | after user scroll to 1800.0: offset 1800.0 content 2000.0 viewport 200.0 fromBottom 0.0 | after +20 rows: offset 2200.0 content 2400.0 viewport 200.0 fromBottom 0.0
//   G4 .bottom for .sizeChanges, not touched, +20: initial offset 0.0 content 2000.0 viewport 200.0 fromBottom 1800.0 | after +20 rows: offset 0.0 content 2400.0 viewport 200.0 fromBottom 2200.0
//   G5 .bottom for .sizeChanges, user scrolled UP to 500, +20: initial offset 0.0 content 2000.0 viewport 200.0 fromBottom 1800.0 | after user scroll to 500.0: offset 500.0 content 2000.0 viewport 200.0 fromBottom 1300.0 | after +20 rows: offset 500.0 content 2400.0 viewport 200.0 fromBottom 1700.0
//   G6 .bottom for .sizeChanges, user at bottom 1800, +20: initial offset 0.0 content 2000.0 viewport 200.0 fromBottom 1800.0 | after user scroll to 1800.0: offset 1800.0 content 2000.0 viewport 200.0 fromBottom 0.0 | after +20 rows: offset 1800.0 content 2400.0 viewport 200.0 fromBottom 400.0
//   G7 .bottom, eager VStack, user scrolled UP to 500, +20: initial offset 1800.0 content 2000.0 viewport 200.0 fromBottom 0.0 | after user scroll to 500.0: offset 500.0 content 2000.0 viewport 200.0 fromBottom 1300.0 | after +20 rows: offset 2200.0 content 2400.0 viewport 200.0 fromBottom 0.0
//   G8 .bottom, user at 1800 (bottom), -20 rows: initial offset 1800.0 content 2000.0 viewport 200.0 fromBottom 0.0 | after user scroll to 1800.0: offset 1800.0 content 2000.0 viewport 200.0 fromBottom 0.0 | after +-20 rows: offset 1400.0 content 1600.0 viewport 200.0 fromBottom 0.0
//   === W: wheel events (precise, phased) instead of clip.scroll; viewport starts at the bottom
//   W0 control: initial offset 0.0 content 2000.0 viewport 200.0 fromBottom 1800.0 | wheel +400 (down): offset 400.0 content 2000.0 viewport 200.0 fromBottom 1400.0 | wheel -600 (up): offset 0.0 content 2000.0 viewport 200.0 fromBottom 1800.0 | +20 rows: offset 0.0 content 2400.0 viewport 200.0 fromBottom 2200.0 | wheel to the bottom: offset 2202.0 content 2400.0 viewport 200.0 fromBottom -2.0 | +20 rows: offset 2202.0 content 2800.0 viewport 200.0 fromBottom 398.0
//   W1 .bottom: initial offset 1800.0 content 2000.0 viewport 200.0 fromBottom 0.0 | wheel +400 (down): offset 1801.0 content 2000.0 viewport 200.0 fromBottom -1.0 | wheel -600 (up): offset 1330.0 content 2000.0 viewport 200.0 fromBottom 470.0 | +20 rows: offset 1330.0 content 2400.0 viewport 200.0 fromBottom 870.0 | wheel to the bottom: offset 2202.0 content 2400.0 viewport 200.0 fromBottom -2.0 | +20 rows: offset 2600.0 content 2800.0 viewport 200.0 fromBottom 0.0
//   W2 .bottom for .sizeChanges: initial offset 0.0 content 2000.0 viewport 200.0 fromBottom 1800.0 | wheel +400 (down): offset 400.0 content 2000.0 viewport 200.0 fromBottom 1400.0 | wheel -600 (up): offset 0.0 content 2000.0 viewport 200.0 fromBottom 1800.0 | +20 rows: offset 0.0 content 2400.0 viewport 200.0 fromBottom 2200.0 | wheel to the bottom: offset 2202.0 content 2400.0 viewport 200.0 fromBottom -2.0 | +20 rows: offset 2600.0 content 2800.0 viewport 200.0 fromBottom 0.0
//   W3 .bottom for .initialOffset: initial offset 1800.0 content 2000.0 viewport 200.0 fromBottom 0.0 | wheel +400 (down): offset 1801.0 content 2000.0 viewport 200.0 fromBottom -1.0 | wheel -600 (up): offset 1330.0 content 2000.0 viewport 200.0 fromBottom 470.0 | +20 rows: offset 1330.0 content 2400.0 viewport 200.0 fromBottom 870.0 | wheel to the bottom: offset 2202.0 content 2400.0 viewport 200.0 fromBottom -2.0 | +20 rows: offset 2202.0 content 2800.0 viewport 200.0 fromBottom 398.0
//   W4 .bottom for .alignment: initial offset 0.0 content 2000.0 viewport 200.0 fromBottom 1800.0 | wheel +400 (down): offset 400.0 content 2000.0 viewport 200.0 fromBottom 1400.0 | wheel -600 (up): offset 0.0 content 2000.0 viewport 200.0 fromBottom 1800.0 | +20 rows: offset 0.0 content 2400.0 viewport 200.0 fromBottom 2200.0 | wheel to the bottom: offset 2202.0 content 2400.0 viewport 200.0 fromBottom -2.0 | +20 rows: offset 2202.0 content 2800.0 viewport 200.0 fromBottom 398.0
//   W5 .top: initial offset 0.0 content 2000.0 viewport 200.0 fromBottom 1800.0 | wheel +400 (down): offset 400.0 content 2000.0 viewport 200.0 fromBottom 1400.0 | wheel -600 (up): offset 0.0 content 2000.0 viewport 200.0 fromBottom 1800.0 | +20 rows: offset 0.0 content 2400.0 viewport 200.0 fromBottom 2200.0 | wheel to the bottom: offset 2201.0 content 2400.0 viewport 200.0 fromBottom -1.0 | +20 rows: offset 2201.0 content 2800.0 viewport 200.0 fromBottom 399.0
//   === S: content shorter than the viewport (5 rows = 100 in 200), then grows past it
//   S0 control, 5 rows, +20: initial offset 0.0 content 100.0 viewport 200.0 fromBottom -100.0 | after +20 rows: offset 0.0 content 500.0 viewport 200.0 fromBottom 300.0
//   S1 .bottom, 5 rows, +20: initial offset -100.0 content 100.0 viewport 200.0 fromBottom 0.0 | after +20 rows: offset 300.0 content 500.0 viewport 200.0 fromBottom 0.0
//   S2 .bottom for .alignment, 5 rows, +20: initial offset -100.0 content 100.0 viewport 200.0 fromBottom 0.0 | after +20 rows: offset 300.0 content 500.0 viewport 200.0 fromBottom 0.0
//   S3 .bottom for .sizeChanges, 5 rows, +20: initial offset 0.0 content 100.0 viewport 200.0 fromBottom -100.0 | after +20 rows: offset 0.0 content 500.0 viewport 200.0 fromBottom 300.0
//   === T: a block above the viewport grows (row 3 of an EAGER VStack gets 100 taller; a lazy stack never realises it, extent = mean) while at the bottom / scrolled up by wheel
//   T1 .bottom at the bottom: before offset 1800.0 content 2000.0 viewport 200.0 fromBottom 0.0 | after row 3 +100: offset 1900.0 content 2100.0 viewport 200.0 fromBottom 0.0
//   T1 .bottom wheeled up 500: before offset 1300.0 content 2000.0 viewport 200.0 fromBottom 500.0 | after row 3 +100: offset 1300.0 content 2100.0 viewport 200.0 fromBottom 600.0
//   T2 .bottom for .sizeChanges at the bottom: before offset 1802.0 content 2000.0 viewport 200.0 fromBottom -2.0 | after row 3 +100: offset 1900.0 content 2100.0 viewport 200.0 fromBottom 0.0
//   T2 .bottom for .sizeChanges wheeled up 500: before offset 0.0 content 2000.0 viewport 200.0 fromBottom 1800.0 | after row 3 +100: offset 0.0 content 2100.0 viewport 200.0 fromBottom 1900.0
//   T0 control (no modifier), eager: before offset 0.0 content 2000.0 viewport 200.0 fromBottom 1800.0 | after row 3 +100 offset 0.0 content 2100.0 viewport 200.0 fromBottom 1900.0 | tall off, +1 row offset 0.0 content 2020.0 viewport 200.0 fromBottom 1820.0
//   === V: variable heights (rows 20, every 7th 90), 100 rows, +20 rows
//   V1 .bottom initial offset 5230.0 content 5430.0 viewport 200.0 fromBottom 0.0 | +20 offset 5910.0 content 6110.0 viewport 200.0 fromBottom 0.0 | +20 more offset 6550.0 content 6750.0 viewport 200.0 fromBottom 0.0
//   === H: horizontal scroller (100 columns x 20 in 200)
//   H0 control: initial offset 0.0 content 2000.0 viewport 200.0 fromBottom 1800.0 | +20 offset 0.0 content 2400.0 viewport 200.0 fromBottom 2200.0
//   H1 .trailing: initial offset 1800.0 content 2000.0 viewport 200.0 fromBottom 0.0 | +20 offset 2200.0 content 2400.0 viewport 200.0 fromBottom 0.0
//   H2 .bottom (wrong axis): initial offset 900.0 content 2000.0 viewport 200.0 fromBottom 900.0 | +20 offset 900.0 content 2400.0 viewport 200.0 fromBottom 1300.0
//   H3 .leading: initial offset 0.0 content 2000.0 viewport 200.0 fromBottom 1800.0 | +20 offset 0.0 content 2400.0 viewport 200.0 fromBottom 2200.0
//   === P: scrollPosition(id:) / ScrollViewReader with .bottom
//   P1 .bottom + onAppear scrollTo(10, .top): offset 200.0 content 2000.0 viewport 200.0 fromBottom 1600.0 (row 10 top = 200)
//   P2 .bottom + scrollPosition(id: 10) initial: offset 200.0 content 2000.0 viewport 200.0 fromBottom 1600.0 (row 10 top = 200)
//   N1 3 rows (60) .bottom, content top y of first row: offset -140.0 content 60.0 viewport 200.0 fromBottom 0.0
//   DONE

import SwiftUI
import AppKit

func spin(_ s: TimeInterval) { RunLoop.current.run(until: Date(timeIntervalSinceNow: s)) }

@MainActor final class Model: ObservableObject {
    @Published var n: Int
    @Published var tall: Bool = false
    init(_ n: Int) { self.n = n }
}
struct Row: View {
    let i: Int; var h: CGFloat = 20; var tall: Bool = false
    var body: some View { Color.blue.frame(height: h + (tall ? 100 : 0)).overlay(Text("\(i)").font(.system(size: 8))) }
}
/// Row whose height reads the model in ITS OWN body (a ForEach does not re-run its
/// closure for an unchanged id, so a tall flag read in the closure never lands).
struct ModelRow: View {
    let i: Int; @ObservedObject var m: Model
    var body: some View { Row(i: i, tall: i == 3 && m.tall) }
}
@MainActor func scrollViews(in view: NSView) -> [NSScrollView] {
    var found: [NSScrollView] = []
    if let s = view as? NSScrollView { found.append(s) }
    for sub in view.subviews { found += scrollViews(in: sub) }
    return found
}
@MainActor func host<V: View>(_ v: V, width: CGFloat = 200, height: CGFloat = 200) -> (NSWindow, NSHostingView<V>) {
    let h = NSHostingView(rootView: v)
    let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.borderless], backing: .buffered, defer: false)
    win.isReleasedWhenClosed = false
    win.contentView = h
    win.orderFrontRegardless()
    spin(0.4)
    return (win, h)
}
@MainActor func reading(_ h: NSView, horizontal: Bool = false) -> String {
    guard let s = scrollViews(in: h).first, let d = s.documentView else { return "(no NSScrollView)" }
    let o = horizontal ? s.contentView.bounds.origin.x : s.contentView.bounds.origin.y
    let ext = horizontal ? d.frame.width : d.frame.height
    let vis = horizontal ? s.contentView.bounds.width : s.contentView.bounds.height
    return "offset \(o) content \(ext) viewport \(vis) fromBottom \(ext - vis - o)"
}
@MainActor func userScroll(_ h: NSView, to y: CGFloat, horizontal: Bool = false) {
    guard let s = scrollViews(in: h).first else { return }
    s.contentView.scroll(to: horizontal ? NSPoint(x: y, y: 0) : NSPoint(x: 0, y: y))
    s.reflectScrolledClipView(s.contentView)
    spin(0.3)
}
/// A real wheel gesture delivered to the NSScrollView (a precise-delta event with
/// began/changed/ended phases); `dy` > 0 scrolls the content DOWN (offset grows)
/// is negative delta in AppKit's convention, so the sign is flipped here.
@MainActor func wheel(_ h: NSView, dy: Int32, steps: Int = 4) {
    guard let s = scrollViews(in: h).first else { return }
    s.window?.makeFirstResponder(s)
    let phases: [Int64] = [1, 2, 2, 2, 4] // began, changed..., ended (NSEvent.Phase raw)
    for i in 0..<(steps + 1) {
        let last = i == steps
        guard let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: last ? 0 : -dy / Int32(steps), wheel2: 0, wheel3: 0) else { continue }
        cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: i == 0 ? 1 : (last ? 4 : 2))
        cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        _ = phases
        if let ev = NSEvent(cgEvent: cg) { s.scrollWheel(with: ev) }
        spin(0.05)
    }
    spin(0.3)
}
@MainActor func finish(_ w: NSWindow) { w.orderOut(nil); w.contentView = nil; spin(0.05) }

struct Host<Content: View>: View {
    @ObservedObject var m: Model
    let content: (Model) -> Content
    var body: some View { content(m) }
}
typealias Mod = (AnyView) -> AnyView

@MainActor func arm(_ name: String, count: Int = 100, lazy: Bool = true, grow: Int = 20,
                    scrolledTo: CGFloat? = nil, mod: @escaping Mod) {
    let m = Model(count)
    let (w, h) = host(Host(m: m) { m in
        mod(AnyView(ScrollView {
            if lazy { LazyVStack(spacing: 0) { ForEach(0..<m.n, id: \.self) { Row(i: $0) } } }
            else { VStack(spacing: 0) { ForEach(0..<m.n, id: \.self) { Row(i: $0) } } }
        }))
    })
    var line = "\(name): initial \(reading(h))"
    if let y = scrolledTo { userScroll(h, to: y); line += " | after user scroll to \(y): \(reading(h))" }
    m.n += grow; spin(0.4)
    line += " | after +\(grow) rows: \(reading(h))"
    print(line)
    finish(w)
}

@MainActor func probes() {
    print("=== I: initial offset (100 rows x 20 = 2000 in 200)")
    arm("I0 control, no modifier") { $0 }
    arm("I1 .defaultScrollAnchor(.bottom)") { AnyView($0.defaultScrollAnchor(.bottom)) }
    arm("I2 .defaultScrollAnchor(.top)") { AnyView($0.defaultScrollAnchor(.top)) }
    arm("I3 .defaultScrollAnchor(.center)") { AnyView($0.defaultScrollAnchor(.center)) }
    arm("I4 .defaultScrollAnchor(.leading) (a horizontal anchor on a vertical scroller)") { AnyView($0.defaultScrollAnchor(.leading)) }
    arm("I5 .defaultScrollAnchor(.bottom) eager VStack", lazy: false) { AnyView($0.defaultScrollAnchor(.bottom)) }
    arm("I6 .defaultScrollAnchor(UnitPoint(x: 0, y: 0.25))") { AnyView($0.defaultScrollAnchor(UnitPoint(x: 0, y: 0.25))) }

    print("=== R: roles")
    arm("R1 .bottom for .initialOffset") { AnyView($0.defaultScrollAnchor(.bottom, for: .initialOffset)) }
    arm("R2 .bottom for .sizeChanges") { AnyView($0.defaultScrollAnchor(.bottom, for: .sizeChanges)) }
    arm("R3 .bottom for .alignment") { AnyView($0.defaultScrollAnchor(.bottom, for: .alignment)) }
    arm("R4 .bottom + .bottom for .sizeChanges") { AnyView($0.defaultScrollAnchor(.bottom).defaultScrollAnchor(.bottom, for: .sizeChanges)) }
    arm("R5 .bottom for .initialOffset + .top for .sizeChanges") { AnyView($0.defaultScrollAnchor(.bottom, for: .initialOffset).defaultScrollAnchor(.top, for: .sizeChanges)) }
    arm("R6 .top + .bottom for .sizeChanges") { AnyView($0.defaultScrollAnchor(.top).defaultScrollAnchor(.bottom, for: .sizeChanges)) }

    print("=== O: order of two modifiers on one scroller (the later call is the OUTER view), and an ancestor")
    arm("O1 .bottom then .top (outer .top)") { AnyView($0.defaultScrollAnchor(.bottom).defaultScrollAnchor(.top)) }
    arm("O2 .top then .bottom (outer .bottom)") { AnyView($0.defaultScrollAnchor(.top).defaultScrollAnchor(.bottom)) }
    arm("O3 .bottom then nil (outer nil)") { AnyView($0.defaultScrollAnchor(.bottom).defaultScrollAnchor(nil)) }
    arm("O4 nil then .bottom (outer .bottom)") { AnyView($0.defaultScrollAnchor(nil).defaultScrollAnchor(.bottom)) }
    arm("O5 .top, outer .bottom for .initialOffset only") { AnyView($0.defaultScrollAnchor(.top).defaultScrollAnchor(.bottom, for: .initialOffset)) }
    arm("O6 .bottom for .initialOffset, outer .top (all roles)") { AnyView($0.defaultScrollAnchor(.bottom, for: .initialOffset).defaultScrollAnchor(.top)) }
    arm("O7 modifier on an ancestor VStack, not on the ScrollView") { v in AnyView(VStack { v }.defaultScrollAnchor(.bottom)) }
    arm("O8 modifier on a .frame()d scroll view (a wrapper between)") { AnyView($0.frame(width: 200, height: 200).defaultScrollAnchor(.bottom)) }

    print("=== G: growth while at the bottom / after a user scroll up (rows appended)")
    arm("G0 control, user at offset 1800 (bottom), +20", scrolledTo: 1800) { $0 }
    arm("G1 .bottom, +20, not touched") { AnyView($0.defaultScrollAnchor(.bottom)) }
    arm("G2 .bottom, user scrolled UP to 500, +20", scrolledTo: 500) { AnyView($0.defaultScrollAnchor(.bottom)) }
    arm("G3 .bottom, user scrolled to the bottom 1800 then +20", scrolledTo: 1800) { AnyView($0.defaultScrollAnchor(.bottom)) }
    arm("G4 .bottom for .sizeChanges, not touched, +20") { AnyView($0.defaultScrollAnchor(.bottom, for: .sizeChanges)) }
    arm("G5 .bottom for .sizeChanges, user scrolled UP to 500, +20", scrolledTo: 500) { AnyView($0.defaultScrollAnchor(.bottom, for: .sizeChanges)) }
    arm("G6 .bottom for .sizeChanges, user at bottom 1800, +20", scrolledTo: 1800) { AnyView($0.defaultScrollAnchor(.bottom, for: .sizeChanges)) }
    arm("G7 .bottom, eager VStack, user scrolled UP to 500, +20", lazy: false, scrolledTo: 500) { AnyView($0.defaultScrollAnchor(.bottom)) }
    arm("G8 .bottom, user at 1800 (bottom), -20 rows", grow: -20, scrolledTo: 1800) { AnyView($0.defaultScrollAnchor(.bottom)) }

    print("=== W: wheel events (precise, phased) instead of clip.scroll; viewport starts at the bottom")
    for (name, mod) in [("W0 control", { (v: AnyView) in v }), ("W1 .bottom", { AnyView($0.defaultScrollAnchor(.bottom)) }), ("W2 .bottom for .sizeChanges", { AnyView($0.defaultScrollAnchor(.bottom, for: .sizeChanges)) }), ("W3 .bottom for .initialOffset", { AnyView($0.defaultScrollAnchor(.bottom, for: .initialOffset)) }), ("W4 .bottom for .alignment", { AnyView($0.defaultScrollAnchor(.bottom, for: .alignment)) }), ("W5 .top", { AnyView($0.defaultScrollAnchor(.top)) })] as [(String, Mod)] {
        let m = Model(100)
        let (w, h) = host(Host(m: m) { m in
            mod(AnyView(ScrollView { LazyVStack(spacing: 0) { ForEach(0..<m.n, id: \.self) { Row(i: $0) } } }))
        })
        var line = "\(name): initial \(reading(h))"
        wheel(h, dy: 400); line += " | wheel +400 (down): \(reading(h))"
        wheel(h, dy: -600); line += " | wheel -600 (up): \(reading(h))"
        m.n += 20; spin(0.4); line += " | +20 rows: \(reading(h))"
        wheel(h, dy: 100000); line += " | wheel to the bottom: \(reading(h))"
        m.n += 20; spin(0.4); line += " | +20 rows: \(reading(h))"
        print(line); finish(w)
    }

    print("=== S: content shorter than the viewport (5 rows = 100 in 200), then grows past it")
    arm("S0 control, 5 rows, +20", count: 5) { $0 }
    arm("S1 .bottom, 5 rows, +20", count: 5) { AnyView($0.defaultScrollAnchor(.bottom)) }
    arm("S2 .bottom for .alignment, 5 rows, +20", count: 5) { AnyView($0.defaultScrollAnchor(.bottom, for: .alignment)) }
    arm("S3 .bottom for .sizeChanges, 5 rows, +20", count: 5) { AnyView($0.defaultScrollAnchor(.bottom, for: .sizeChanges)) }

    print("=== T: a block above the viewport grows (row 3 of an EAGER VStack gets 100 taller; a lazy stack never realises it, extent = mean) while at the bottom / scrolled up by wheel")
    for (name, role) in [("T1 .bottom", nil), ("T2 .bottom for .sizeChanges", ScrollAnchorRole.sizeChanges)] as [(String, ScrollAnchorRole?)] {
        for up in [false, true] {
            let m = Model(100)
            let (w, h) = host(Host(m: m) { m in
                let sv = ScrollView { VStack(spacing: 0) { ForEach(0..<m.n, id: \.self) { ModelRow(i: $0, m: m) } } }
                return role.map { AnyView(sv.defaultScrollAnchor(.bottom, for: $0)) } ?? AnyView(sv.defaultScrollAnchor(.bottom))
            })
            var line = "\(name) \(up ? "wheeled up 500" : "at the bottom")"
            if up { wheel(h, dy: -500) } else if role != nil { wheel(h, dy: 100000) }
            line += ": before \(reading(h))"
            m.tall = true; spin(0.4)
            line += " | after row 3 +100: \(reading(h))"
            print(line)
            finish(w)
        }
    }

    do {
        let m = Model(100)
        let (w, h) = host(Host(m: m) { m in ScrollView { VStack(spacing: 0) { ForEach(0..<m.n, id: \.self) { ModelRow(i: $0, m: m) } } } })
        var line = "T0 control (no modifier), eager: before \(reading(h))"
        m.tall = true; spin(0.4); line += " | after row 3 +100 \(reading(h))"
        m.tall = false; m.n += 1; spin(0.4); line += " | tall off, +1 row \(reading(h))"
        print(line); finish(w)
    }
    print("=== V: variable heights (rows 20, every 7th 90), 100 rows, +20 rows")
    do {
        let m = Model(100)
        let (w, h) = host(Host(m: m) { m in
            ScrollView { LazyVStack(spacing: 0) { ForEach(0..<m.n, id: \.self) { Row(i: $0, h: $0 % 7 == 0 ? 90 : 20) } } }.defaultScrollAnchor(.bottom)
        })
        var line = "V1 .bottom initial \(reading(h))"
        m.n += 20; spin(0.4); line += " | +20 \(reading(h))"
        m.n += 20; spin(0.4); line += " | +20 more \(reading(h))"
        print(line); finish(w)
    }

    print("=== H: horizontal scroller (100 columns x 20 in 200)")
    for (name, a) in [("H0 control", nil), ("H1 .trailing", UnitPoint.trailing), ("H2 .bottom (wrong axis)", UnitPoint.bottom), ("H3 .leading", UnitPoint.leading)] as [(String, UnitPoint?)] {
        let m = Model(100)
        let (w, h) = host(Host(m: m) { m in
            let sv = ScrollView(.horizontal) { LazyHStack(spacing: 0) { ForEach(0..<m.n, id: \.self) { Row(i: $0).frame(width: 20, height: 20) } } }
            return a.map { AnyView(sv.defaultScrollAnchor($0)) } ?? AnyView(sv)
        })
        var line = "\(name): initial \(reading(h, horizontal: true))"
        m.n += 20; spin(0.4); line += " | +20 \(reading(h, horizontal: true))"
        print(line); finish(w)
    }

    print("=== P: scrollPosition(id:) / ScrollViewReader with .bottom")
    do {
        let m = Model(100)
        let (w, h) = host(Host(m: m) { m in
            ScrollViewReader { proxy in
                ScrollView { LazyVStack(spacing: 0) { ForEach(0..<m.n, id: \.self) { Row(i: $0).id($0) } } }
                    .defaultScrollAnchor(.bottom)
                    .onAppear { proxy.scrollTo(10, anchor: .top) }
            }
        })
        print("P1 .bottom + onAppear scrollTo(10, .top): \(reading(h)) (row 10 top = 200)")
        finish(w)
    }
    do {
        let m = Model(100)
        struct PV: View {
            @ObservedObject var m: Model
            @State var pos: Int? = 10
            var body: some View {
                ScrollView { LazyVStack(spacing: 0) { ForEach(0..<m.n, id: \.self) { Row(i: $0).id($0) } }.scrollTargetLayout() }
                    .scrollPosition(id: $pos).defaultScrollAnchor(.bottom)
            }
        }
        let (w, h) = host(PV(m: m))
        print("P2 .bottom + scrollPosition(id: 10) initial: \(reading(h)) (row 10 top = 200)")
        finish(w)
    }
    do {
        let m = Model(3)
        let (w, h) = host(Host(m: m) { m in
            ScrollView { VStack(spacing: 0) { ForEach(0..<m.n, id: \.self) { Row(i: $0) } } }.defaultScrollAnchor(.bottom)
        })
        print("N1 3 rows (60) .bottom, content top y of first row: \(reading(h))")
        finish(w)
    }
    fflush(stdout)
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
MainActor.assumeIsolated { probes() }
print("DONE")
