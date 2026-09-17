// SwiftUI probe: at a FINITE proposal, where does a spanning cell's width
// shortfall go when none of its spanned columns still holds an unprocessed
// single-column cell — over the spanned columns that hold NO single-column
// cell at all, or over all of them? Evidence for ruling GR-F (the span rule) in
// docs/superpowers/2026-09-17-grids-decisions.md (plan task 7, stage G, lane 2).
//
// HOW TO RUN: /usr/bin/swift docs/probes/swiftui-grid-span-targets.swift
//
// WHY A COMPANION PROBE. `docs/probes/swiftui-grid.swift` (revision 6) reads the
// three-step target rule at two of its three steps at a finite proposal — GX9
// (a spanned column still holding an unprocessed single) and GX8 (every spanned
// column holds one, so the shortfall is spread over all of them) — and the
// middle step, "the spanned columns holding no single-column cell anywhere",
// ONLY at nil×nil (GX11). The kernel has two solves, one per branch, and the
// lane-2 re-verification showed that DELETING the middle step from the finite
// one — `NativeGrid.swift`'s `NativeGridSolver.finishGroup`, the line
// `if targets.isEmpty { targets = columns.filter { plan.columnSingleCells[$0].isEmpty } }`
// — left the whole 1450-test suite green. These two arms are the missing
// discriminators, and they are what the S1/S2 arms of
// `aSpanAtAFiniteProposalIsOfferedTheWidthOutsideItAndWidensItsOpenColumnsFirst`
// now assert.
//
// METHOD. The grid probe's instrument: an NSHostingView whose root `Probe`
// layout asks the view under test for its answer at the stated proposal and
// places it at (0, 0) at that proposal. A leaf is a custom `Layout` answering a
// pure function of its proposal. An arm line reads `name (x,y wxh)`.
//
// THE TWO ARMS. Each has a spanned column reachable ONLY by the span, so that
// column holds no single-column cell, while the other spanned column's singles
// are all processed by the time the span's group finishes (every cell is a
// fixed-size leaf, so every cell has flexibility 0 and they form ONE group):
//
//   S1 `Grid { GridRow { a 20x20 }; GridRow { x 60x20 .gridCellColumns(2) } }`
//      — column 1 is spanned only. "No single-column cell" puts the whole 40pt
//      shortfall in column 1 and leaves a at x = 0; "all spanned columns" splits
//      it 20/20 and centres a in a 40-wide column 0, at x = 10.
//   S2 `Grid { GridRow { a 20x20, b 30x20 }; GridRow { d 10x20, x 90x20
//      .gridCellColumns(2) } }` — the span covers columns 1 and 2, and column 2
//      is spanned only. "No single-column cell" gives column 2 the whole 60pt
//      shortfall and leaves b at x = 28; "all spanned columns" splits it 30/30
//      and centres b in a 60-wide column 1, at x = 43.
//
// Each is also run at nil×nil, where the kernel takes its OTHER branch, to show
// the two agree.
//
// CONTROLS. C0 is GX8 from `swiftui-grid.swift` (100x38 at 300×100: the finite
// branch's third step, every spanned column holding a single) and C1 is GX11
// (156x58 at nil×nil: the middle step at nil, the rule under test one branch
// over). Each is already recorded there, so a run that reproduces them is
// reading the same grid the rest of the corpus was read from.
//
// RECORDED 2026-09-17 by the grids track, lane 2 re-verification, macOS 27.0
// (26A428), `/usr/bin/swift` = Apple Swift 6.4 (swiftlang-6.4.0.33.1). Exit 0,
// run twice, byte-identical stdout (`diff` empty).
//
// THE READING. S1 reads a at (0,0) and S2 reads b at (28,0), at the finite
// proposal and at nil alike: SwiftUI puts the whole shortfall in the spanned
// column that holds no single-column cell, and the kernel's middle step is
// right on both branches. The arm that would have been needed to see it was
// simply missing. (S1's 60x48 and S2's 118x48 also confirm the pairless column
// boundary — no row has a cell pair meeting at it — contributes 0, not the 8pt
// default: with 8 they would read 68 and 126 wide.)
//
// STDOUT:
//
//   C0 GX8: Grid{[x 100x10 span 2] [a 30x10, b 20x20]} at 300x100: size 100x38 | a (10.50,23 30x10) | b (69.50,18 20x20) | x (0,0 100x10)
//   C1 GX11 the middle step at nil: size 156x58 | a (0,0 10x40) | e (108,48 10x10) | f (126,48 30x10) | b (18,0 100x40) | c (126,0 30x40) | d (45,48 10x10)
//   S1 [a 20x20] [x 60x20 span 2] at 200x200: size 60x48 | a (0,0 20x20) | x (0,28 60x20)
//   S1 [a 20x20] [x 60x20 span 2] at nil: size 60x48 | a (0,0 20x20) | x (0,28 60x20)
//   S2 [a 20x20, b 30x20] [d 10x20, x 90x20 span 2] at 300x200: size 118x48 | a (0,0 20x20) | d (5,28 10x20) | b (28,0 30x20) | x (28,28 90x20)
//   S2 [a 20x20, b 30x20] [d 10x20, x 90x20 span 2] at nil: size 118x48 | a (0,0 20x20) | d (5,28 10x20) | b (28,0 30x20) | x (28,28 90x20)
//
// (the names in a line are in the order the grid PLACED them, which is why C0
// reads a, b, x and C1 reads a, e, f, b, c, d rather than declaration order; the
// rects are what the kernel's arms assert, converted by `roundLayout`. C0 and C1
// reproduce `swiftui-grid.swift`'s recorded rects for those two arms exactly.)
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
/// GX11's own spellings, copied verbatim from `swiftui-grid.swift` (`cb`, `fh`,
/// `cw`) so C1 is that arm and not a paraphrase of it.
func cb(_ n: String, _ lo: CGFloat, _ hi: CGFloat) -> some View { leaf(n) { p in CGSize(width: min(max(p.width ?? 10, lo), hi), height: min(max(p.height ?? 10, lo), hi)) } }
func fh(_ n: String, _ w: CGFloat = 20) -> some View { leaf(n) { p in CGSize(width: w, height: p.height ?? 10) } }
func cw(_ n: String, _ lo: CGFloat, _ hi: CGFloat, _ h: CGFloat = 10) -> some View { leaf(n) { p in CGSize(width: min(max(p.width ?? 10, lo), hi), height: h) } }
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
    arm("C0 GX8: Grid{[x 100x10 span 2] [a 30x10, b 20x20]} at 300x100", p(300, 100)) {
        Grid {
            GridRow { fx("x", 100, 10).gridCellColumns(2) }
            GridRow { fx("a", 30, 10); fx("b", 20, 20) }
        }
    }
    arm("C1 GX11 the middle step at nil", p(nil, nil)) {
        Grid {
            GridRow { cb("a", 0, 100); fx("b", 100, 40).gridCellColumns(2); cw("c", 30, 40, 40).gridCellColumns(2) }
            GridRow { fh("d", 10).gridCellColumns(2); fh("e", 10); cw("f", 30, 180, 10) }
        }
    }
    for (label, proposal) in [("200x200", p(200, 200)), ("nil", p(nil, nil))] {
        arm("S1 [a 20x20] [x 60x20 span 2] at \(label)", proposal) {
            Grid {
                GridRow { fx("a", 20, 20) }
                GridRow { fx("x", 60, 20).gridCellColumns(2) }
            }
        }
    }
    for (label, proposal) in [("300x200", p(300, 200)), ("nil", p(nil, nil))] {
        arm("S2 [a 20x20, b 30x20] [d 10x20, x 90x20 span 2] at \(label)", proposal) {
            Grid {
                GridRow { fx("a", 20, 20); fx("b", 30, 20) }
                GridRow { fx("d", 10, 20); fx("x", 90, 20).gridCellColumns(2) }
            }
        }
    }
}
exit(0)
