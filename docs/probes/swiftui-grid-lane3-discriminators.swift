// SwiftUI probe: the three grid clauses lane 3's mutation round found the suite
// could not hold — two `gridCellColumns` on ONE MODIFIER CHAIN, a row mark on
// both ends of one chain, and the proposal an unsized SPAN is given. Evidence
// for rulings GR-F (the column sum), GR-H (`gridCellUnsizedAxes`), GR-I (the
// modifier-chain walk) and GR-T (row membership) in
// docs/superpowers/2026-09-17-grids-decisions.md (plan task 7, stage G, lane 3).
//
// HOW TO RUN: /usr/bin/swift docs/probes/swiftui-grid-lane3-discriminators.swift
//
// `/usr/bin/swift` is Apple's toolchain; a swift.org toolchain's JIT fails on
// SwiftUI symbols.
//
// WHY EACH GROUP EXISTS. Each was written after a mutation of the kernel left
// the whole 1463-test suite GREEN (record §20, lane 3's mutation table):
//
//   W  `LayoutTree.gridChildMarks`' `columns += …` replaced by a `max`
//      (mutation M3.5b). The suite's chain arms are the main probe's GWI1 and
//      GWI2, which write 2 and 1 — and 1 is not above 1, so "sum the marks above
//      1" and "take the largest mark" both answer 2. No arm anywhere writes two
//      marks above 1 on one chain.
//   R  the walk's `if rowToken == nil` replaced by "take the innermost" (M3.RT).
//      Every row-mark arm in the suite writes ONE token per chain.
//   U  `NativeGridSolver.serve`'s unsized-horizontal branch reading
//      `widths[cell.column]` instead of `spanWidth(cell)` (M3.UW). The main
//      probe's only unsized SPAN is GU3, whose leaf follows its proposal, so
//      the wrong proposal is re-measured away at placement and no rect moves.
//
// METHOD. The grid probe's instrument, unchanged: an `NSHostingView` whose root
// `Probe` layout asks the view under test for its answer at the stated proposal
// and places it at (0, 0) at that proposal. A cell is an `L` leaf, a custom
// `Layout` answering a pure function of its proposal: `fx(w, h)` is fixed and
// `dbl(h)` answers twice its proposed width (10 at nil) by a fixed height. An
// arm line reads `name (x,y wxh) <- the proposal it was PLACED with`, then every
// measurement in the order SwiftUI asked — and for U it is that MEASUREMENT log,
// not the rects alone, that reads the span's proposal.
//
// PREDICTED BEFORE THE RUN, hand-derived from the reference model in
// `docs/probes/swiftui-grid.swift`, which is what the kernel implements:
//
//   W0 (`c.columns(2).padding(1)`)                      115x40 | a (11,5 30x10)
//   W1 (`c.padding(1).columns(2)`)                      the same as W0
//   W2 (`c.columns(2).padding(1).columns(2)`, span 4)   115x40 | a (0,5 30x10)
//   W3 (W2 with a four-cell top row)                    115x40; a span of 2 would answer 130x40
//   R0 (one row of two cells)                           58x20  | a (0,5 30x10) | b (38,0 20x20)
//   R1 (a nested GridRow, no wrapper)                   the same as R0
//   R2 (the nested GridRow inside a padding(1))         60x20  | a (1,5 30x10) | b (40,0 20x20)
//   R3 (two separate rows, for scale)                   30x38
//   U0 (a span of 2, NOT unsized, at 200x200)           400x38 | c proposed 200x172
//   U1 (the same span, unsized horizontally)            116x38 | c proposed  58x172
//
// and under each mutation: W2 would read W0's rects and W3 would answer 130x40;
// R2 would put a and b in rows of their own (the kernel's 32x40); U1's c would
// be proposed 30x172 and the grid would answer 60x38.
//
// CONTROLS (practices shape 15). W0 and W1 must AGREE and both DISAGREE with W2;
// R0, R1 and R2 must all be ONE row and R3 (30x38) shows what two rows look
// like; U0 and U1 must disagree, or the unsized mark reads nothing. W3's and
// U1's numbers are what make them value arms rather than "something changed"
// arms.
//
// RECORDED 2026-09-21 by the grids track, lane 3, macOS 27.0 (26A428),
// `/usr/bin/swift` = Apple Swift 6.4 (swiftlang-6.4.0.33.1). Exit 0, run twice,
// byte-identical stdout (`diff` empty).
//
// THE READING. **All ten arms came out exactly as predicted**, so none of the
// three clauses is a kernel invention:
// 1. W2 and W3 show SwiftUI ADDING two `gridCellColumns` written on opposite
//    sides of a `.padding()`, exactly as it adds two written on one view
//    (the main probe's GX15), and W0/W1 show one mark reading the same wherever
//    it sits.
// 2. R2 flattens a nested `GridRow` through a `.padding()` into its enclosing
//    row — the OUTERMOST row mark wins — which is `GR-T`'s nested-row rule
//    surviving a wrapper, and R3 is what the other answer would look like.
// 3. U1's measurement log reads `c 58x172`: an unsized span is proposed its
//    SPANNED COLUMNS' widths plus their inner gap (30 + 8 + 20), not its first
//    column's 30.
// Pinned by tests 3.5 (W), 3.10 (R2) and 3.7 (U0/U1) in
// `Tests/MetalUILayoutTests/NativeGridTests.swift`.
//
// STDOUT:
//   W0 control, ONE mark inside the padding: [a 30x10, b 20x20] [c 100x10 .columns(2).padding(1), d 5x5] @nilxnil: size 115x40 | a (11,5 30x10) <- 52x20 | b (71,0 20x20) <- 42x20 | c (1,29 100x10) <- nilxnil | d (110,31.50 5x5) <- 5x12
//       measured, in order: a nilxnil->30x10; b nilxnil->20x20; c nilxnil->100x10; d nilxnil->5x5; a 52x20->30x10; b 42x20->20x20; d 5x12->5x5
//   W1 control, ONE mark outside the padding: [a, b] [c .padding(1).columns(2), d] @nilxnil: size 115x40 | a (11,5 30x10) <- 52x20 | b (71,0 20x20) <- 42x20 | c (1,29 100x10) <- nilxnil | d (110,31.50 5x5) <- 5x12
//       measured, in order: a nilxnil->30x10; b nilxnil->20x20; c nilxnil->100x10; d nilxnil->5x5; a 52x20->30x10; b 42x20->20x20; d 5x12->5x5
//   W2 TWO marks, one each side of the padding: [a, b] [c .columns(2).padding(1).columns(2), d] @nilxnil: size 115x40 | a (0,5 30x10) <- 30x20 | b (38,0 20x20) <- nilxnil | c (1,29 100x10) <- nilxnil | d (110,31.50 5x5) <- 5x12
//       measured, in order: a nilxnil->30x10; b nilxnil->20x20; c nilxnil->100x10; d nilxnil->5x5; a 30x20->30x10; d 5x12->5x5
//   W3 W2 with a four-cell top row, where four columns and five differ in WIDTH @nilxnil: size 115x40 | a (2,5 30x10) <- 34x20 | b (44,0 20x20) <- 24x20 | e (76,7.50 5x5) <- 9x20 | f (93,6.50 7x7) <- 11x20 | c (1,29 100x10) <- nilxnil | d (110,31.50 5x5) <- 5x12
//       measured, in order: a nilxnil->30x10; b nilxnil->20x20; e nilxnil->5x5; f nilxnil->7x7; c nilxnil->100x10; d nilxnil->5x5; a 34x20->30x10; b 24x20->20x20; e 9x20->5x5; f 11x20->7x7; d 5x12->5x5
//   R0 control, one row of two cells: Grid{ GridRow{a 30x10; b 20x20} } @nilxnil: size 58x20 | a (0,5 30x10) <- 30x20 | b (38,0 20x20) <- nilxnil
//       measured, in order: a nilxnil->30x10; b nilxnil->20x20; a 30x20->30x10
//   R1 control, a nested GridRow with NO wrapper: Grid{ GridRow{ GridRow{a}; b } } @nilxnil: size 58x20 | a (0,5 30x10) <- 30x20 | b (38,0 20x20) <- nilxnil
//       measured, in order: a nilxnil->30x10; b nilxnil->20x20; a 30x20->30x10
//   R2 a nested GridRow inside a padding: Grid{ GridRow{ GridRow{a}.padding(1); b } } @nilxnil: size 60x20 | a (1,5 30x10) <- 30x18 | b (40,0 20x20) <- nilxnil
//       measured, in order: a nilxnil->30x10; b nilxnil->20x20; a 30x18->30x10
//   R3 two separate rows, for comparison: Grid{ GridRow{a}; GridRow{b} } @nilxnil: size 30x38 | a (0,0 30x10) <- nilxnil | b (5,18 20x20) <- 30x20
//       measured, in order: a nilxnil->30x10; b nilxnil->20x20; b 30x20->20x20
//   U0 control, a SPAN of 2 that is not unsized: [a 30x10, b 20x20] [c span2 = twice its proposal] at 200x200 @200x200: size 400x38 | a (85.50,5 30x10) <- 201x20 | b (294.50,0 20x20) <- 191x20 | c (0,28 400x10) <- 200x172
//       measured, in order: a 0x0->30x10; a infxinf->30x10; b 0x0->20x20; b infxinf->20x20; c 0x0->0x10; c infxinf->infx10; a 96x96->30x10; b 96x96->20x20; c 200x172->400x10; a 201x20->30x10; b 191x20->20x20
//   U1 the same SPAN marked gridCellUnsizedAxes(.horizontal) @200x200: size 116x38 | a (14.50,5 30x10) <- 59x20 | b (81.50,0 20x20) <- 49x20 | c (0,28 116x10) <- 58x172
//       measured, in order: a 0x0->30x10; a infxinf->30x10; b 0x0->20x20; b infxinf->20x20; c 0x0->0x10; c infxinf->infx10; a 96x96->30x10; b 96x96->20x20; c 58x172->116x10; a 59x20->30x10; b 49x20->20x20
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
    // W: two gridCellColumns on one chain.
    arm("W0 control, ONE mark inside the padding: [a 30x10, b 20x20] [c 100x10 .columns(2).padding(1), d 5x5]", p(nil, nil)) {
        Grid {
            GridRow { fx("a", 30, 10); fx("b", 20, 20) }
            GridRow { fx("c", 100, 10).gridCellColumns(2).padding(1); fx("d", 5, 5) }
        }
    }
    arm("W1 control, ONE mark outside the padding: [a, b] [c .padding(1).columns(2), d]", p(nil, nil)) {
        Grid {
            GridRow { fx("a", 30, 10); fx("b", 20, 20) }
            GridRow { fx("c", 100, 10).padding(1).gridCellColumns(2); fx("d", 5, 5) }
        }
    }
    arm("W2 TWO marks, one each side of the padding: [a, b] [c .columns(2).padding(1).columns(2), d]", p(nil, nil)) {
        Grid {
            GridRow { fx("a", 30, 10); fx("b", 20, 20) }
            GridRow { fx("c", 100, 10).gridCellColumns(2).padding(1).gridCellColumns(2); fx("d", 5, 5) }
        }
    }
    arm("W3 W2 with a four-cell top row, where four columns and five differ in WIDTH", p(nil, nil)) {
        Grid {
            GridRow { fx("a", 30, 10); fx("b", 20, 20); fx("e", 5, 5); fx("f", 7, 7) }
            GridRow { fx("c", 100, 10).gridCellColumns(2).padding(1).gridCellColumns(2); fx("d", 5, 5) }
        }
    }
    // R: a row mark on both ends of one chain.
    arm("R0 control, one row of two cells: Grid{ GridRow{a 30x10; b 20x20} }", p(nil, nil)) {
        Grid { GridRow { fx("a", 30, 10); fx("b", 20, 20) } }
    }
    arm("R1 control, a nested GridRow with NO wrapper: Grid{ GridRow{ GridRow{a}; b } }", p(nil, nil)) {
        Grid { GridRow { GridRow { fx("a", 30, 10) }; fx("b", 20, 20) } }
    }
    arm("R2 a nested GridRow inside a padding: Grid{ GridRow{ GridRow{a}.padding(1); b } }", p(nil, nil)) {
        Grid { GridRow { GridRow { fx("a", 30, 10) }.padding(1); fx("b", 20, 20) } }
    }
    arm("R3 two separate rows, for comparison: Grid{ GridRow{a}; GridRow{b} }", p(nil, nil)) {
        Grid { GridRow { fx("a", 30, 10) }; GridRow { fx("b", 20, 20) } }
    }
    // U: the proposal an unsized SPAN is given.
    arm("U0 control, a SPAN of 2 that is not unsized: [a 30x10, b 20x20] [c span2 = twice its proposal] at 200x200", p(200, 200)) {
        Grid {
            GridRow { fx("a", 30, 10); fx("b", 20, 20) }
            GridRow { dbl("c").gridCellColumns(2) }
        }
    }
    arm("U1 the same SPAN marked gridCellUnsizedAxes(.horizontal)", p(200, 200)) {
        Grid {
            GridRow { fx("a", 30, 10); fx("b", 20, 20) }
            GridRow { dbl("c").gridCellColumns(2).gridCellUnsizedAxes(.horizontal) }
        }
    }
}
exit(0)
