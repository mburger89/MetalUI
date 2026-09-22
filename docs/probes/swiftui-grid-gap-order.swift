// SwiftUI probe: when two rows (or two columns) disagree about the spacing at
// one gap, does the grid take the LARGEST pair value meeting there, or the last
// one it sees? Evidence for ruling GR-D in
// docs/superpowers/2026-09-17-grids-decisions.md (plan task 7, stage G, lane 1).
//
// HOW TO RUN: /usr/bin/swift docs/probes/swiftui-grid-gap-order.swift
//
// WHY A COMPANION PROBE. `docs/probes/swiftui-grid.swift` (revision 5) has no
// arm that can tell the two rules apart: GS1's larger pair is in the LATER row,
// and GS4/GS5 have one pair per boundary. The lane-1 verifier showed that
// mutating `NativeGrid.swift`'s two `Swift.max` reductions into "the last pair
// wins" left the whole 1449-test suite green. These four arms are the missing
// discriminators, and they are what `eachGapIsTheLargestPairSpacingMeetingThere`
// now asserts.
//
// METHOD. The grid probe's instrument: an NSHostingView whose root `Probe`
// layout asks the view under test for its answer at the stated proposal and
// places it at (0, 0) at that proposal. A leaf is a custom `Layout` answering a
// pure function of its proposal. An arm line reads `name (x,y wxh)`.
//
// A `Spacer()` cell carries SwiftUI's "no spacing on this edge" mark, so a pair
// that touches one is 0 and a pair of two ordinary leaves is the 8pt platform
// default. Putting the Spacer in the FIRST row (arm H1) or the LAST column
// (arm V1) puts the 0 where a "last wins" reduction would read it.
//
// CONTROLS. C0 is GA1 from `swiftui-grid.swift` (78x58, no Spacer anywhere) and
// C1 is GQ6 (the Spacer row FIRST, where both rules agree at 58x58): each is
// already recorded there, so a run that reproduces them is reading the same
// grid the rest of the corpus was read from.
//
// RECORDED 2026-09-17 by the grids track, lane 1, macOS 27.0 (26A428),
// `/usr/bin/swift` = Apple Swift 6.4 (swiftlang-6.4.0.33.1). Exit 0, run twice,
// byte-identical stdout (`diff` empty).
//
// THE READING. H1 answers 58 wide, not 50: the gap before column 1 is the 8 of
// the SECOND row's (c, d) pair, although the FIRST row's (Spacer, b) pair says
// 0 there. V1 answers 58 tall, not 50: the gap before row 1 is the 8 of the
// FIRST column's (b, d) pair, although the LAST column's (Spacer, c) pair says
// 0. So SwiftUI takes the largest pair meeting at a gap, on both axes, and
// neither "first wins" nor "last wins" reproduces it.
//
// STDOUT:
//
//   C0 GA1: Grid{[a 30x10, b 20x20] [c 10x30, d 40x10]} at nil: size 78x58 | a (0,5 30x10) | c (10,28 10x30) | b (48,0 20x20) | d (38,38 40x10)
//   C1 GQ6: Grid{[Spacer, b 20x20] [c 10x30, d 40x10]} at nil: size 58x58 | c (0,28 10x30) | b (28,0 20x20) | d (18,38 40x10)
//   H1 the Spacer row FIRST: Grid{[c 10x30, d 40x10] [Spacer, b 20x20]} at nil: size 58x58 | c (0,0 10x30) | d (18,10 40x10) | b (28,38 20x20)
//   V1 the Spacer column LAST: Grid{[b 20x20, Spacer] [d 40x10, c 10x30]} at nil: size 58x58 | b (10,0 20x20) | d (0,38 40x10) | c (48,28 10x30)
//
// (the names in a line are in the order the grid PLACED them, which is why C0
// and C1 read a, c, b, d rather than declaration order; the rects are what the
// kernel's arms assert, converted by `roundLayout`.)
import SwiftUI
import AppKit

func d(_ v: CGFloat?) -> String {
    guard let v else { return "nil" }
    if v == .infinity { return "inf" }
    if v.isNaN { return "nan" }
    return v == v.rounded() ? String(Int(v)) : String(format: "%.2f", v)
}
func fmt(_ s: CGSize) -> String { "\(d(s.width))x\(d(s.height))" }
func fmt(_ r: CGRect) -> String { "(\(d(r.minX)),\(d(r.minY)) \(d(r.width))x\(d(r.height)))" }

nonisolated(unsafe) var placed: [String: CGRect] = [:]
nonisolated(unsafe) var order: [String] = []
nonisolated(unsafe) var lastSize: CGSize = .zero

struct L: Layout {
    let name: String
    let f: @Sendable (ProposedViewSize) -> CGSize
    func sizeThatFits(proposal: ProposedViewSize, subviews _: Subviews, cache: inout ()) -> CGSize {
        f(proposal)
    }
    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        if !order.contains(name) { order.append(name) }
        placed[name] = bounds
        subviews[0].place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
    }
}
struct Probe: Layout {
    let proposal: ProposedViewSize
    func sizeThatFits(proposal _: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let size = subviews[0].sizeThatFits(proposal); lastSize = size; return size
    }
    func placeSubviews(in _: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        lastSize = subviews[0].sizeThatFits(proposal)
        subviews[0].place(at: .zero, anchor: .topLeading, proposal: proposal)
    }
}
func leaf(_ n: String, _ f: @escaping @Sendable (ProposedViewSize) -> CGSize) -> some View { L(name: n, f: f) { Color.clear } }
func fx(_ n: String, _ w: CGFloat, _ h: CGFloat) -> some View { leaf(n) { _ in CGSize(width: w, height: h) } }
func p(_ w: CGFloat?, _ h: CGFloat?) -> ProposedViewSize { ProposedViewSize(width: w, height: h) }

@MainActor func arm<V: View>(_ label: String, _ proposal: ProposedViewSize, @ViewBuilder _ view: () -> V) {
    order = []; placed = [:]
    let host = NSHostingView(rootView: Probe(proposal: proposal) { view() })
    host.frame = CGRect(x: 0, y: 0, width: 1000, height: 1000)
    host.layoutSubtreeIfNeeded()
    var line = "\(label): size \(fmt(lastSize))"
    for n in order { line += " | \(n) " + (placed[n].map { fmt($0) } ?? "not placed") }
    print(line)
    fflush(stdout)
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
MainActor.assumeIsolated {
    arm("C0 GA1: Grid{[a 30x10, b 20x20] [c 10x30, d 40x10]} at nil", p(nil, nil)) {
        Grid { GridRow { fx("a", 30, 10); fx("b", 20, 20) }; GridRow { fx("c", 10, 30); fx("d", 40, 10) } }
    }
    arm("C1 GQ6: Grid{[Spacer, b 20x20] [c 10x30, d 40x10]} at nil", p(nil, nil)) {
        Grid { GridRow { Spacer(); fx("b", 20, 20) }; GridRow { fx("c", 10, 30); fx("d", 40, 10) } }
    }
    arm("H1 the Spacer row FIRST: Grid{[c 10x30, d 40x10] [Spacer, b 20x20]} at nil", p(nil, nil)) {
        Grid { GridRow { fx("c", 10, 30); fx("d", 40, 10) }; GridRow { Spacer(); fx("b", 20, 20) } }
    }
    arm("V1 the Spacer column LAST: Grid{[b 20x20, Spacer] [d 40x10, c 10x30]} at nil", p(nil, nil)) {
        Grid { GridRow { fx("b", 20, 20); Spacer() }; GridRow { fx("d", 40, 10); fx("c", 10, 30) } }
    }
}
exit(0)
