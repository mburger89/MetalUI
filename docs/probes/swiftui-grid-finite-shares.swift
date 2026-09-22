// SwiftUI probe: three sub-clauses of the FINITE solve's proposal arithmetic
// (§4.2 of docs/superpowers/specs/2026-09-17-grids-design.md) that no arm of
// `docs/probes/swiftui-grid.swift` discriminates — the spanning cell's
// proposal FLOOR, the "share if open, width if not" term for a column OUTSIDE
// a span, and the running sum of committed column widths. Evidence for rulings
// GR-E/GR-F/GR-U in docs/superpowers/2026-09-17-grids-decisions.md (plan task 7,
// stage G, lanes 2 and 3).
//
// HOW TO RUN: /usr/bin/swift docs/probes/swiftui-grid-finite-shares.swift
//
// `/usr/bin/swift` is Apple's toolchain; a swift.org toolchain's JIT fails on
// SwiftUI symbols.
//
// PROVENANCE, AND A WARNING. An earlier draft of this file was left uncommitted
// in the worktree by an interrupted round, with a header whose "STDOUT" block
// did not come from any run of it: on all five arms it recorded the KERNEL's
// answers as SwiftUI's, and its C0/C1 control lines contradicted
// `docs/probes/swiftui-grid-default-run.txt`. The arms below are that draft's,
// unchanged; the stdout, the reading and the O1 conclusion are this file's own
// run, taken by the lane-1 verifier (record §22). Two of the three clauses come
// out as that draft claimed; the third does not.
//
// WHY A COMPANION PROBE. Three mutations of `NativeGridSolver` leave the whole
// 1450-test suite green, each a normative clause of §4.2:
//
//   F  `NativeGrid.swift`'s `serve`, a spanning cell's width
//      `Swift.max(wPrime - outside + innerGaps(plan, cell), spanWidth(cell))`
//      — dropping the second argument, the floor at the span's own columns.
//   O  the same line's `outside += levelInColumn[column] > 0 ? shareW
//      : widths[column]` — making it always `widths[column]`.
//   R  `widen`'s `if committedColumn[column] { committedWidth += value - old }`
//      — letting the running sum of committed widths go stale when a later
//      group widens a column an earlier group committed.
//
// The corpus arms reach each line but never at a shape where the two spellings
// differ: GX8 serves its span FIRST (every column still 0, so the floor is just
// the inner gap and loses to the outside term), every span in the corpus sits
// in a grid whose outside columns are all closed by the time it is served, and
// no corpus arm has a later group widening an earlier group's committed column.
// These three arms are the missing discriminators.
//
// METHOD. The grid probe's instrument, unchanged: an `NSHostingView` whose root
// `Probe` layout asks the view under test for its answer at the stated proposal
// and places it at (0, 0) at that proposal. A cell is an `L` leaf, a custom
// `Layout` answering a pure function of its proposal (`fx` fixed, `fh` fixed
// width and flexible height, `cw` width clamped, `cb` clamped on both axes,
// `fw` flexible width and fixed height — all copied from `swiftui-grid.swift`).
// An arm line reads `name (x,y wxh) <- the proposal it was PLACED with`, and
// every arm also prints its measurement sequence, `name proposal->answer` in
// the order SwiftUI asked, which is where each clause is read directly.
//
// THE THREE ARMS, with the kernel's answer beside SwiftUI's. (The kernel's
// figures were read by running the same five grids through `LayoutTree`'s
// `.grid` node in a scratch test, unmutated and under each mutation; they are
// in record §22, lane 1's verifier round.)
//
//   F1 `Grid { GridRow { a 200x10, b 10x10 }; GridRow { x span 2 } }` at
//      100×100, where x is 60 wide and 40 tall when proposed at least 200 wide,
//      20 tall otherwise. a and b have flexibility 0 and x has +20, so x is a
//      group of its own and is served after both columns are filled and
//      committed. W′ = 92 and the span's columns already sum 218: with the
//      floor x is proposed 218 (answer 40 tall, grid 218×58); without it,
//      92 + 8 = 100 (answer 20 tall, grid 218×38).
//      **SwiftUI 218×58; kernel 218×58; mutant F 218×38. The clause is right.**
//
//   O1 `Grid { GridRow { a 20x10, b 30x10, c width 40 height-flexible };
//      GridRow { x clamp 0…250 span 2, d 40x10 } }` at 300×100. c answers an
//      infinite height at an infinite proposal, so it sorts after x and column 2
//      is still OPEN when x is served. The kernel charges column 2 its group's
//      share — by then (284 − 50 committed) ÷ 1 open = 234 — and proposes x
//      284 − 234 + 8 = 58, so nothing widens (grid 106×100). "Always the width"
//      charges 40, proposes x 252, x answers its 250 cap and the shortfall
//      widens both spanned columns (grid 298×100).
//      **SwiftUI 245.33×100 — NEITHER.** Its sequence shows `x 197.33x46->…`:
//      284 − 94.67 + 8, where 94.67 is W′ ÷ 3, the share with NOTHING committed
//      and all three columns counted open. So SwiftUI does not charge the
//      outside column the share the kernel computes at that moment, and the
//      kernel diverges here by 139.33pt. See record §22; no ruling owns it yet.
//
//   R1 `Grid { GridRow { a 50x10 priority 2, b 10x10 priority 2 };
//      GridRow { c clamp 0…200 priority 1, e clamp 0…300 priority 0 } }` at
//      300×100. The priority-2 group commits both columns at 50 and 10; the
//      priority-1 group then widens column 0 from 50 to 200. With the running
//      sum kept, e's group sees 210 committed and is offered 292 − 210 = 82
//      (grid 290×28); with it stale it sees 60 and is offered 232, which e
//      answers in full (grid 440×28).
//      **SwiftUI 290×28; kernel 290×28; mutant R 440×28. The clause is right.**
//
// CONTROLS. C0 is GX8 from `swiftui-grid.swift` (100×38 at 300×100, x proposed
// 300×46 — the finite span branch, where the floor loses) and C1 is GX12
// (300×114 at 300×200 — the non-row child that the outside term's clause is
// named with in §4.2). Both reproduce `swiftui-grid-default-run.txt` line for
// line, measurement sequences included, so a run that reproduces them is
// reading the same grid the rest of the corpus was read from.
//
// RECORDED 2026-09-21 by the grids track, lane 1's verifier round, macOS 27.0
// (26A428), `/usr/bin/swift` = Apple Swift 6.4 (swiftlang-6.4.0.33.1).
// Exit 0, run twice, byte-identical stdout (`diff` empty).
//
// STDOUT:
//
//   C0 GX8 Grid{[x 100x10 span 2] [a 30x10, b 20x20]} @300x100: size 100x38 | x (0,0 100x10) <- 300x46 | a (10.50,23 30x10) <- 51x20 | b (69.50,18 20x20) <- 41x20
//       measured, in order: x 0x0->100x10; x infxinf->100x10; a 0x0->30x10; a infxinf->30x10; b 0x0->20x20; b infxinf->20x20; x 300x46->100x10; a 146x46->30x10; b 146x46->20x20; a 51x20->30x10; b 41x20->20x20
//   C1 GX12 [a clamp 20...120, b width 0...60 h30] FULL x width-flexible h10 @300x200: size 300x114 | a (28,0 120x96) <- 176x96 | b (212,33 60x30) <- 116x96 | x (0,104 300x10) <- 300x96
//       measured, in order: a 0x0->20x20; a infxinf->120x120; b 0x0->0x30; b infxinf->60x30; x 0x0->0x10; x infxinf->infx10; b 146x96->60x30; a 232x96->120x96; x 300x96->300x10; a 176x96->120x96; b 116x96->60x30
//   F1 [a 200x10, b 10x10] [x 60 wide, 40 tall when proposed >= 200 wide, span 2] @100x100: size 218x58 | a (0,0 200x10) <- 46x46 | b (208,0 10x10) <- 46x46 | x (79,18 60x40) <- 218x40
//       measured, in order: a 0x0->200x10; a infxinf->200x10; b 0x0->10x10; b infxinf->10x10; x 0x0->60x20; x infxinf->60x40; a 46x46->200x10; b 46x46->10x10; x 218x82->60x40; x 218x40->60x40
//   O1 [a 20x10, b 30x10, c w40 height-flexible] [x clamp 0...250 span 2, d 40x10] @300x100: size 245.33x100 | a (34.83,36 20x10) <- 89.67x82 | b (132.50,36 30x10) <- 99.67x82 | c (205.33,0 40x82) <- 62.33x82 | x (0,90 197.33x10) <- 197.33x46 | d (205.33,90 40x10) <- 94.67x46
//       measured, in order: a 0x0->20x10; a infxinf->20x10; b 0x0->30x10; b infxinf->30x10; c 0x0->40x0; c infxinf->40xinf; x 0x0->0x10; x infxinf->250x10; d 0x0->40x10; d infxinf->40x10; a 94.67x46->20x10; b 94.67x46->30x10; d 94.67x46->40x10; x 197.33x46->197.33x10; c 62.33x82->40x82; a 89.67x82->20x10; b 99.67x82->30x10
//   R1 [a 50x10 prio 2, b 10x10 prio 2] [c clamp 0...200 prio 1, e clamp 0...300 prio 0] @300x100: size 290x28 | a (75,0 50x10) <- 200x10 | b (244,0 10x10) <- 82x10 | c (0,18 200x10) <- 232x82 | e (208,18 82x10) <- 82x72
//       measured, in order: a 0x0->50x10; a infxinf->50x10; b 0x0->10x10; b infxinf->10x10; c 0x0->0x10; c infxinf->200x10; e 0x0->0x10; e infxinf->300x10; a 146x92->50x10; b 146x92->10x10; c 232x82->200x10; e 82x72->82x10; a 200x10->50x10; b 82x10->10x10

import SwiftUI
import AppKit

func d(_ v: CGFloat?) -> String {
    guard let v else { return "nil" }
    if v == .infinity { return "inf" }
    if v.isNaN { return "nan" }
    return v == v.rounded() ? String(Int(v)) : String(format: "%.2f", v)
}
func fmt(_ s: CGSize) -> String { "\(d(s.width))x\(d(s.height))" }
func fmt(_ s: ProposedViewSize) -> String { "\(d(s.width))x\(d(s.height))" }
func fmt(_ r: CGRect) -> String { "(\(d(r.minX)),\(d(r.minY)) \(d(r.width))x\(d(r.height)))" }

nonisolated(unsafe) var placed: [String: CGRect] = [:]
nonisolated(unsafe) var placedProposal: [String: ProposedViewSize] = [:]
nonisolated(unsafe) var seqLog: [String] = []
nonisolated(unsafe) var order: [String] = []
nonisolated(unsafe) var lastSize: CGSize = .zero

/// `swiftui-grid.swift`'s `L`, verbatim: answers `f(proposal)`, logs every
/// measurement in order, and records its placed rect and placement proposal.
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
func leaf(_ n: String, _ f: @escaping @Sendable (ProposedViewSize) -> CGSize) -> some View { L(name: n, f: f) { SwiftUI.Color.clear } }
/// fixed w x h
func fx(_ n: String, _ w: CGFloat, _ h: CGFloat) -> some View { leaf(n) { _ in CGSize(width: w, height: h) } }
/// fixed width w, height proposal ?? 10
func fh(_ n: String, _ w: CGFloat = 20) -> some View { leaf(n) { p in CGSize(width: w, height: p.height ?? 10) } }
/// width proposal ?? 10, fixed height h
func fw(_ n: String, _ h: CGFloat = 20) -> some View { leaf(n) { p in CGSize(width: p.width ?? 10, height: h) } }
/// clamp(proposal ?? 10, lo, hi) on both axes
func cb(_ n: String, _ lo: CGFloat, _ hi: CGFloat) -> some View { leaf(n) { p in CGSize(width: min(max(p.width ?? 10, lo), hi), height: min(max(p.height ?? 10, lo), hi)) } }
/// width clamp(proposal ?? 10, lo, hi), fixed height h
func cw(_ n: String, _ lo: CGFloat, _ hi: CGFloat, _ h: CGFloat = 10) -> some View { leaf(n) { p in CGSize(width: min(max(p.width ?? 10, lo), hi), height: h) } }
/// F1's leaf: fixed width w, `hi` tall when proposed at least `threshold` wide,
/// `lo` tall otherwise — so its height reads back the width it was PROPOSED.
func wk(_ n: String, _ w: CGFloat, _ threshold: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> some View {
    leaf(n) { p in CGSize(width: w, height: (p.width ?? 0) >= threshold ? hi : lo) }
}
func p(_ w: CGFloat?, _ h: CGFloat?) -> ProposedViewSize { ProposedViewSize(width: w, height: h) }

@MainActor func arm<V: View>(_ label: String, _ proposal: ProposedViewSize, @ViewBuilder _ view: () -> V) {
    seqLog = []; order = []; placed = [:]; placedProposal = [:]
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
    arm("C0 GX8 Grid{[x 100x10 span 2] [a 30x10, b 20x20]}", p(300, 100)) {
        Grid {
            GridRow { fx("x", 100, 10).gridCellColumns(2) }
            GridRow { fx("a", 30, 10); fx("b", 20, 20) }
        }
    }
    arm("C1 GX12 [a clamp 20...120, b width 0...60 h30] FULL x width-flexible h10", p(300, 200)) {
        Grid {
            GridRow { cb("a", 20, 120); cw("b", 0, 60, 30) }
            fw("x", 10)
        }
    }
    arm("F1 [a 200x10, b 10x10] [x 60 wide, 40 tall when proposed >= 200 wide, span 2]", p(100, 100)) {
        Grid {
            GridRow { fx("a", 200, 10); fx("b", 10, 10) }
            GridRow { wk("x", 60, 200, 20, 40).gridCellColumns(2) }
        }
    }
    arm("O1 [a 20x10, b 30x10, c w40 height-flexible] [x clamp 0...250 span 2, d 40x10]", p(300, 100)) {
        Grid {
            GridRow { fx("a", 20, 10); fx("b", 30, 10); fh("c", 40) }
            GridRow { cw("x", 0, 250, 10).gridCellColumns(2); fx("d", 40, 10) }
        }
    }
    arm("R1 [a 50x10 prio 2, b 10x10 prio 2] [c clamp 0...200 prio 1, e clamp 0...300 prio 0]", p(300, 100)) {
        Grid {
            GridRow { fx("a", 50, 10).layoutPriority(2); fx("b", 10, 10).layoutPriority(2) }
            GridRow { cw("c", 0, 200).layoutPriority(1); cw("e", 0, 300) }
        }
    }
}
exit(0)
