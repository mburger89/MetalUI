// SwiftUI probe: the flexibility key's "a nil proposal axis counts for
// neither" clause on the WIDTH axis — a grid measured at nil x finite, whose
// two cells change their key ORDER if the nil width axis is counted. Evidence
// for ruling GR-E (step 2) in docs/superpowers/2026-09-17-grids-decisions.md
// (plan task 7, stage G, lane 2 re-verification).
//
// HOW TO RUN: /usr/bin/swift docs/probes/swiftui-grid-nil-width-key.swift
//
// `/usr/bin/swift` is Apple's toolchain; a swift.org toolchain's JIT fails on
// SwiftUI symbols.
//
// WHY. `docs/probes/swiftui-grid.swift`'s GF12/GF13 pair already reads the
// clause on the HEIGHT axis (150 x nil against 150x100). No corpus arm reads it
// on the WIDTH axis, and `NativeGridSolver.provide`'s two guards are separate
// copies of one clause: dropping `if proposal.width != nil` left the whole
// 1450-test suite green (lane-2 verifier round, record §20), while dropping
// `if proposal.height != nil` reddened two tests. These arms are the missing
// width-axis discriminator.
//
// METHOD. The grid probe's instrument, unchanged: an `NSHostingView` whose root
// `Probe` layout asks the view under test for its answer at the stated proposal
// and places it at (0, 0) at that proposal. A cell is an `L` leaf, a custom
// `Layout` answering a pure function of its proposal — `fw(h)` is width
// `proposal ?? 10` by fixed height `h`, `cb(lo, hi)` is `clamp(proposal ?? 10,
// lo, hi)` on both axes, both copied from `swiftui-grid.swift`. An arm line
// reads `name (x,y wxh) <- the proposal it was PLACED with`, then every
// measurement in the order SwiftUI asked.
//
// THE GRID. Two rows of one cell: `a` = fw(20), `b` = cb(10, 80). Their keys at
// nil x 100, counting only the finite (height) axis: a's inf-answer height is
// its fixed 20 and its 0x0 height is 20, so a's flexibility is 0 and it has no
// infinite axis; b's is 80 - 10 = 70. a is the less flexible cell, so a is
// served FIRST and takes half of H' = 100 - 8 = 92, answering its fixed 20;
// b then takes all of 92 - 20 = 72. Counting the nil width axis as well would
// make a's inf-answer width infinite — one infinite axis against b's none — and
// the key's first term puts the cell with FEWER infinite axes first, so b would
// be served first, take 46, and a's 20 would leave the grid 74 tall.
//
// CONTROL. N0 is the same grid at 100x100, where the width axis is finite and
// so does count: b is served first there, and the grid is 74 tall. N0 and N1
// must disagree, or the instrument reads nothing about the nil axis.
//
// PREDICTED BEFORE THE RUN, from the reference model in
// `docs/probes/swiftui-grid.swift` (hand-derived, record §20):
//
//   N0 @100x100: size 100x74 | a (0,0 100x20) | b (10,28 80x46)
//   N1 @nilx100: size 10x100 | a (0,0 10x20)  | b (0,28 10x72)
//
// and, under the mutation (the nil width axis counted), N1 would read
// size 10x74 with b 10x46 and b measured before a.
//
// RECORDED 2026-09-21 by the grids track, lane 2 implementer, macOS 27.0
// (26A428), `/usr/bin/swift` = Apple Swift 6.4 (swiftlang-6.4.0.33.1). Exit 0,
// run twice, byte-identical stdout (`diff` empty).
//
// THE READING. Both arms came out exactly as predicted, so SwiftUI counts the
// nil width axis for neither term of the key.
// 1. N1 (nil x 100) answers 10x100 and its measurement log serves `a` first
//    (`a nilx46` before `b nilx72`): a, whose inf answer is infinitely WIDE,
//    is still the less flexible cell, so the nil width axis added neither an
//    infinite-axis count nor any flexibility.
// 2. N0 (the control, 100x100) answers 100x74 and serves `b` first
//    (`b 100x46` before `a 100x46`) — the order the mutation would produce at
//    N1 — so the instrument does respond to the width axis when it is finite,
//    and N1's reading is about the axis being nil, not about the two leaves.
// 3. The kernel's own answers at these two grids are asserted by
//    `theFlexibilityKeyCountsInfiniteAxesFirstAndIgnoresANilAxis`' GF19/GF20
//    arms (`Tests/MetalUILayoutTests/NativeGridTests.swift`, test 2.2).
//
// STDOUT:
//
//   N0 control: Grid{[a fw h20] [b clamp 10...80]} at 100x100 (a finite width axis, which DOES count) @100x100: size 100x74 | a (0,0 100x20) <- 100x46 | b (10,28 80x46) <- 100x46
//       measured, in order: a 0x0->0x20; a infxinf->infx20; b 0x0->10x10; b infxinf->80x80; b 100x46->80x46; a 100x46->100x20
//   N1 the same grid at nil x 100 (the nil width axis must count for neither) @nilx100: size 10x100 | a (0,0 10x20) <- nilx46 | b (0,28 10x72) <- nilx72
//       measured, in order: a 0x0->0x20; a infxinf->infx20; b 0x0->10x10; b infxinf->80x80; a nilx46->10x20; b nilx72->10x72
import SwiftUI
import AppKit

func d(_ v: CGFloat?) -> String {
    guard let v else { return "nil" }
    if v == .infinity { return "inf" }
    if v.isNaN { return "nan" }
    return v == v.rounded() ? String(Int(v)) : String(format: "%.2f", v)
}
func fmt(_ s: CGSize) -> String { "\(d(s.width))x\(d(s.height))" }
func fmt(_ p: ProposedViewSize) -> String { "\(d(p.width))x\(d(p.height))" }
func fmt(_ r: CGRect) -> String { "(\(d(r.minX)),\(d(r.minY)) \(d(r.width))x\(d(r.height)))" }

nonisolated(unsafe) var placed: [String: CGRect] = [:]
nonisolated(unsafe) var placedProposal: [String: ProposedViewSize] = [:]
nonisolated(unsafe) var seqLog: [String] = []
nonisolated(unsafe) var order: [String] = []
nonisolated(unsafe) var lastSize: CGSize = .zero

struct L: Layout {
    let name: String
    let f: @Sendable (ProposedViewSize) -> CGSize
    func sizeThatFits(proposal: ProposedViewSize, subviews _: Subviews, cache: inout ()) -> CGSize {
        if !order.contains(name) { order.append(name) }
        let s = f(proposal); seqLog.append("\(name) \(fmt(proposal))->\(fmt(s))"); return s
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        if !order.contains(name) { order.append(name) }
        placed[name] = bounds; placedProposal[name] = proposal
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
/// `fw`: width proposal ?? 10, fixed height.
func fw(_ n: String, _ h: CGFloat = 20) -> some View { leaf(n) { p in CGSize(width: p.width ?? 10, height: h) } }
/// `cb`: clamp(proposal ?? 10, lo, hi) on both axes.
func cb(_ n: String, _ lo: CGFloat, _ hi: CGFloat) -> some View { leaf(n) { p in CGSize(width: min(max(p.width ?? 10, lo), hi), height: min(max(p.height ?? 10, lo), hi)) } }
func p(_ w: CGFloat?, _ h: CGFloat?) -> ProposedViewSize { ProposedViewSize(width: w, height: h) }

@MainActor func arm<V: View>(_ label: String, _ proposal: ProposedViewSize, @ViewBuilder _ view: () -> V) {
    seqLog = []; order = []; placedProposal = [:]; placed = [:]
    let host = NSHostingView(rootView: Probe(proposal: proposal) { view() })
    host.frame = CGRect(x: 0, y: 0, width: 1000, height: 1000)
    host.layoutSubtreeIfNeeded()
    var line = "\(label) @\(fmt(proposal)): size \(fmt(lastSize))"
    for n in order { line += " | \(n) " + (placed[n].map { fmt($0) } ?? "not placed") + (placedProposal[n].map { " <- \(fmt($0))" } ?? "") }
    print(line)
    print("    measured, in order: " + seqLog.joined(separator: "; "))
    fflush(stdout)
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
MainActor.assumeIsolated {
    arm("N0 control: Grid{[a fw h20] [b clamp 10...80]} at 100x100 (a finite width axis, which DOES count)", p(100, 100)) {
        Grid { GridRow { fw("a", 20) }; GridRow { cb("b", 10, 80) } }
    }
    arm("N1 the same grid at nil x 100 (the nil width axis must count for neither)", p(nil, 100)) {
        Grid { GridRow { fw("a", 20) }; GridRow { cb("b", 10, 80) } }
    }
}
exit(0)
