// SwiftUI probe: which `GridRow`'s ALIGNMENT a nested row gives its cells when
// the nesting crosses a wrapper — the half of `GR-I`'s "the row token WITH ITS
// ALIGNMENT comes from the outermost mark" that the lane-3 discriminator probe
// does not reach (its R0-R3 arms all write a nil alignment, so they read the
// membership and not the alignment). Evidence for rulings `GR-I` (the
// modifier-chain walk) and `GR-T` (an enclosing `GridRow` wins) in
// docs/superpowers/2026-09-17-grids-decisions.md (plan task 7, stage G, lane 3
// verifier round, `GR-AN`).
//
// HOW TO RUN: /usr/bin/swift docs/probes/swiftui-grid-row-alignment-inheritance.swift
//
// `/usr/bin/swift` is Apple's toolchain; a swift.org toolchain's JIT fails on
// SwiftUI symbols.
//
// WHY IT EXISTS. `LayoutTree.gridChildMarks` takes the row token from the
// OUTERMOST mark on a child's modifier chain and takes that mark's alignment
// with it. Splitting the two — token from the outermost, alignment from the
// innermost — left the whole 1463-test suite GREEN in the verifier round
// (mutation V12), and the mutant is not equivalent: on the kernel's own
// `GridRow(.bottom){a}.padding(1)` inside `GridRow(.top)` it moves `a` from
// y = 1 to y = 29. Nothing measured SwiftUI's answer, so the clause was both
// unpinned and unprobed.
//
// METHOD. The grid probe's instrument, unchanged: an `NSHostingView` whose root
// `Probe` layout asks the view under test for its answer at the stated proposal
// and places it at (0, 0) at that proposal. `fx(w, h)` is a fixed-size `L` leaf.
// An arm line reads `name (x,y wxh) <- the proposal it was PLACED with`, then
// every measurement in the order SwiftUI asked. `a` is 30x10 and `b` 20x40, so
// the row is 40 tall and `a`'s y READS the alignment: 0 for `.top`, 30 for
// `.bottom` (1 and 29 inside a `padding(1)`).
//
// PREDICTED BEFORE THE RUN, from the kernel's rule and from the discriminator
// probe's R2 (a nested `GridRow` inside a `padding` flattens into its enclosing
// row):
//
//   A0 GridRow(.top){a; b}                                a (0,0)   size 58x40
//   A1 GridRow(.bottom){a; b}                             a (0,30)  size 58x40
//   A2 GridRow(.top){ GridRow(.bottom){a}; b }            a (0,0)   — the OUTER wins
//   A3 GridRow(.top){ GridRow(.bottom){a}.padding(1); b } a (1,1)   size 60x40
//   A4 GridRow(.bottom){ GridRow(.top){a}.padding(1); b } a (1,29)  size 60x40
//
// and under the mutation A3 would read a (1,29) and A4 a (1,1).
//
// CONTROLS (practices shape 15). A0 and A1 must DISAGREE (0 against 30), or the
// instrument cannot see a row alignment at all; A3 and A4 must disagree with
// each other, or the arms read the padding and not the alignment; and A3 must
// agree with A0's edge and A4 with A1's, which is the claim.
//
// RECORDED 2026-09-21 by the grids track, lane 3's verifier round, macOS 27.0
// (26A428), `/usr/bin/swift` = Apple Swift 6.4 (swiftlang-6.4.0.33.1). Exit 0,
// run twice, byte-identical stdout (`diff` empty).
//
// THE READING. **All five arms came out exactly as predicted.** SwiftUI gives a
// flattened nested row's cells the ENCLOSING row's alignment, across a wrapper
// (A3, A4) and without one (A2), so the kernel's rule is right and it was the
// coverage that was missing. Pinned by arm R4 of test 3.10
// (`cellAttributesAndRowTokensAreReadThroughModifierNodesAndNotContainers`) in
// `Tests/MetalUILayoutTests/NativeGridTests.swift`.
//
// STDOUT:
//   A0 control, one row, alignment .top: Grid{ GridRow(.top){a 30x10; b 20x40} } @nilxnil: size 58x40 | a (0,0 30x10) <- 30x40 | b (38,0 20x40) <- nilxnil
//       measured, in order: a nilxnil->30x10; b nilxnil->20x40; a 30x40->30x10
//   A1 control, one row, alignment .bottom @nilxnil: size 58x40 | a (0,30 30x10) <- 30x40 | b (38,0 20x40) <- nilxnil
//       measured, in order: a nilxnil->30x10; b nilxnil->20x40; a 30x40->30x10
//   A2 a nested GridRow(.bottom) inside GridRow(.top), NO wrapper @nilxnil: size 58x40 | a (0,0 30x10) <- 30x40 | b (38,0 20x40) <- nilxnil
//       measured, in order: a nilxnil->30x10; b nilxnil->20x40; a 30x40->30x10
//   A3 a nested GridRow(.bottom).padding(1) inside GridRow(.top) @nilxnil: size 60x40 | a (1,1 30x10) <- 30x38 | b (40,0 20x40) <- nilxnil
//       measured, in order: a nilxnil->30x10; b nilxnil->20x40; a 30x38->30x10
//   A4 the reverse: a nested GridRow(.top).padding(1) inside GridRow(.bottom) @nilxnil: size 60x40 | a (1,29 30x10) <- 30x38 | b (40,0 20x40) <- nilxnil
//       measured, in order: a nilxnil->30x10; b nilxnil->20x40; a 30x38->30x10
//
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
func fx(_ n: String, _ w: CGFloat, _ h: CGFloat) -> some View { leaf(n) { _ in CGSize(width: w, height: h) } }
/// `dbl`: twice the proposed width (20 at nil) by a fixed height.
func dbl(_ n: String, _ h: CGFloat = 10) -> some View { leaf(n) { p in CGSize(width: (p.width ?? 10) * 2, height: h) } }

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
MainActor.assumeIsolated {
    arm("A0 control, one row, alignment .top: Grid{ GridRow(.top){a 30x10; b 20x40} }", p(nil, nil)) {
        Grid { GridRow(alignment: .top) { fx("a", 30, 10); fx("b", 20, 40) } }
    }
    arm("A1 control, one row, alignment .bottom", p(nil, nil)) {
        Grid { GridRow(alignment: .bottom) { fx("a", 30, 10); fx("b", 20, 40) } }
    }
    arm("A2 a nested GridRow(.bottom) inside GridRow(.top), NO wrapper", p(nil, nil)) {
        Grid { GridRow(alignment: .top) { GridRow(alignment: .bottom) { fx("a", 30, 10) }; fx("b", 20, 40) } }
    }
    arm("A3 a nested GridRow(.bottom).padding(1) inside GridRow(.top)", p(nil, nil)) {
        Grid { GridRow(alignment: .top) { GridRow(alignment: .bottom) { fx("a", 30, 10) }.padding(1); fx("b", 20, 40) } }
    }
    arm("A4 the reverse: a nested GridRow(.top).padding(1) inside GridRow(.bottom)", p(nil, nil)) {
        Grid { GridRow(alignment: .bottom) { GridRow(alignment: .top) { fx("a", 30, 10) }.padding(1); fx("b", 20, 40) } }
    }
}

exit(0)
