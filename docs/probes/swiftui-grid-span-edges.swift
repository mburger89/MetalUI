// SwiftUI probe: a grid's TRAILING zero-spacing edge when the cell reaching the
// last column SPANS — the second half of `nativeGridZeroSpacingEdges`' rule in
// `Sources/MetalUILayout/NativeGrid.swift` ("the trailing edge if a cell ending
// at the last column has a zero trailing edge … a non-row cell starts at 0 and
// ends at the last column"). Evidence for ruling GR-R in
// docs/superpowers/2026-09-17-grids-decisions.md (plan task 7, stage G, lane 1).
//
// HOW TO RUN: /usr/bin/swift docs/probes/swiftui-grid-span-edges.swift
//
// `/usr/bin/swift` is Apple's toolchain; a swift.org toolchain's JIT fails on
// SwiftUI symbols.
//
// WHY A COMPANION PROBE. The lane-1 verifier mutated the trailing predicate
// from `$0.column + $0.span == plan.columnCount` to `$0.column ==
// plan.columnCount - 1` — "the cell must START at the last column" instead of
// "END at it" — and the whole 1450-test suite stayed green. Every GE arm the
// rule is named with puts a SINGLE-column cell at the boundary, where the two
// spellings agree:
//
//   GE3  `Grid{[b 20x20, Spacer]}`            — one row, the Spacer at column 1
//                                               of 2, span 1: starts AND ends
//                                               at the last column.
//   GE25 `Grid{[b 20x20] Spacer (non-row)}`   — the non-row Spacer spans every
//                                               column, but the grid has only
//                                               ONE column, so column 0 is also
//                                               `columnCount - 1`.
//   GE26 `Grid{[b, e] [Spacer]}`              — two columns, the Spacer a row
//                                               cell at column 0 span 1: it
//                                               ends at column 0, so NEITHER
//                                               spelling gives a trailing edge.
//
// So no committed arm has a cell of span > 1 reaching the last column, and the
// clause's "a non-row cell … ends at the last column" is untested wherever it
// could bind. These two arms are the missing discriminators.
//
// METHOD. `swiftui-grid.swift`'s GE instrument, unchanged: the grid under test
// is the middle child of an `HStack` between a 30×10 leaf and a 10×10 leaf, at
// nil×nil. The stack's ANSWER carries the two gaps the grid's edges decide, so
// a zero trailing edge shows as 8 fewer points. `Spacer().background(fl("s"))`
// makes the Spacer's own rect visible. An arm line reads
// `name (x,y wxh)` for each leaf, in placement order.
//
// THE TWO ARMS, and what each spelling predicts.
//
//   T1 `HStack{a; Grid{ GridRow{b 20x20, e 20x20}; Spacer (non-row) }; c}` —
//      GE25 with a TWO-cell row, so the non-row Spacer spans columns 0…1.
//      "Ends at the last column" ⇒ a zero trailing edge ⇒ stack 88 wide.
//      "Starts at the last column" ⇒ no trailing edge ⇒ 96, which is exactly
//      C1/GE26's recorded width, so the two readings are not a rounding apart.
//
//   T2 `HStack{a; Grid{ GridRow{b, e}; GridRow{ Spacer.gridCellColumns(2) } };
//      c}` — the same boundary reached by a ROW cell of span 2 rather than a
//      non-row child. Same two predictions, 88 against 96.
//
// CONTROLS. C0 is GE25 and C1 is GE26 from `swiftui-grid.swift`, both recorded
// there and in `docs/probes/swiftui-grid-default-run.txt` (60×28 and 96×28), so
// a run that reproduces them is reading the same grid the GE corpus was read
// from. C1 also fixes the "8pt gap" reading in the same units as T1/T2.
//
// RECORDED 2026-09-21 by the grids track, lane 1's verifier round, macOS 27.0
// (26A428), `/usr/bin/swift` = Apple Swift 6.4 (swiftlang-6.4.0.33.1). Exit 0,
// run twice, byte-identical stdout (`diff` empty).
//
// THE READING. **SwiftUI takes the trailing edge from a cell that ENDS at the
// last column, whatever its span** — T1 and T2 both answer 88, not 96, and in
// both the trailing leaf c is placed flush against the grid (at 78, where the
// grid's own content ends) rather than 8 further on. C1 reproduces 96 with a
// single-column Spacer that does NOT reach the last column, so the instrument
// does see the 8pt gap when the rule says there is one. The kernel's spelling
// is right and the defect was purely that no arm discriminated it.
//
// STDOUT:
//
//   C0 GE25 HStack{a 30x10; Grid{[b 20x20] Spacer (non-row)}; c 10x10} @nilxnil: size 60x28 | a (0,9 30x10) | b (30,0 20x20) | c (50,9 10x10) | s (30,20 20x8)
//   C1 GE26 HStack{a; Grid{[b 20x20, e 20x20] [Spacer]}; c} @nilxnil: size 96x28 | a (0,9 30x10) | b (30,0 20x20) | e (58,0 20x20) | c (86,9 10x10) | s (30,20 20x8)
//   T1 non-row Spacer over TWO columns: HStack{a; Grid{[b, e] Spacer (non-row)}; c} @nilxnil: size 88x28 | a (0,9 30x10) | b (30,0 20x20) | e (58,0 20x20) | c (78,9 10x10) | s (30,20 48x8)
//   T2 a row Spacer with gridCellColumns(2): HStack{a; Grid{[b, e] [Spacer span 2]}; c} @nilxnil: size 88x28 | a (0,9 30x10) | b (30,0 20x20) | e (58,0 20x20) | c (78,9 10x10) | s (30,20 48x8)

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
nonisolated(unsafe) var order: [String] = []
nonisolated(unsafe) var lastSize: CGSize = .zero

/// `swiftui-grid.swift`'s `L`, verbatim.
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
func leaf(_ n: String, _ f: @escaping @Sendable (ProposedViewSize) -> CGSize) -> some View { L(name: n, f: f) { SwiftUI.Color.clear } }
/// fixed w x h
func fx(_ n: String, _ w: CGFloat, _ h: CGFloat) -> some View { leaf(n) { _ in CGSize(width: w, height: h) } }
/// proposal ?? 10 on both axes — the GE arms' Spacer background
func fl(_ n: String) -> some View { leaf(n) { p in CGSize(width: p.width ?? 10, height: p.height ?? 10) } }
func p(_ w: CGFloat?, _ h: CGFloat?) -> ProposedViewSize { ProposedViewSize(width: w, height: h) }

@MainActor func arm<V: View>(_ label: String, _ proposal: ProposedViewSize, @ViewBuilder _ view: () -> V) {
    order = []; placed = [:]
    let host = NSHostingView(rootView: Probe(proposal: proposal) { view() })
    host.frame = CGRect(x: 0, y: 0, width: 1000, height: 1000)
    host.layoutSubtreeIfNeeded()
    var line = "\(label) @\(fmt(proposal)): size \(fmt(lastSize))"
    for n in order { line += " | \(n) " + (placed[n].map { fmt($0) } ?? "not placed") }
    print(line)
    fflush(stdout)
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
MainActor.assumeIsolated {
    arm("C0 GE25 HStack{a 30x10; Grid{[b 20x20] Spacer (non-row)}; c 10x10}", p(nil, nil)) {
        HStack {
            fx("a", 30, 10)
            Grid {
                GridRow { fx("b", 20, 20) }
                Spacer().background(fl("s"))
            }
            fx("c", 10, 10)
        }
    }
    arm("C1 GE26 HStack{a; Grid{[b 20x20, e 20x20] [Spacer]}; c}", p(nil, nil)) {
        HStack {
            fx("a", 30, 10)
            Grid {
                GridRow { fx("b", 20, 20); fx("e", 20, 20) }
                GridRow { Spacer().background(fl("s")) }
            }
            fx("c", 10, 10)
        }
    }
    arm("T1 non-row Spacer over TWO columns: HStack{a; Grid{[b, e] Spacer (non-row)}; c}", p(nil, nil)) {
        HStack {
            fx("a", 30, 10)
            Grid {
                GridRow { fx("b", 20, 20); fx("e", 20, 20) }
                Spacer().background(fl("s"))
            }
            fx("c", 10, 10)
        }
    }
    arm("T2 a row Spacer with gridCellColumns(2): HStack{a; Grid{[b, e] [Spacer span 2]}; c}", p(nil, nil)) {
        HStack {
            fx("a", 30, 10)
            Grid {
                GridRow { fx("b", 20, 20); fx("e", 20, 20) }
                GridRow { Spacer().background(fl("s")).gridCellColumns(2) }
            }
            fx("c", 10, 10)
        }
    }
}
exit(0)
