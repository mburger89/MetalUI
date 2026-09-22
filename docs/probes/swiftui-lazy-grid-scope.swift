// SwiftUI probe: are LazyVGrid and LazyHGrid the same layout as Grid, and are
// they lazy? Evidence for ruling GR-L (lazy grids are not part of stage G) in
// docs/superpowers/2026-09-17-grids-decisions.md.
//
// HOW TO RUN (ruling SA-O):
//
//   /usr/bin/swift docs/probes/swiftui-lazy-grid-scope.swift
//
// METHOD. The `Probe` layout of docs/probes/swiftui-grid.swift: the container
// under test is asked for its answer at the stated proposal and placed at (0, 0)
// at that proposal; each cell is an `L` leaf of fixed size recording its placed
// rect. LZ6/LZ7 host a ScrollView 200x200 and count the cells whose `body`
// SwiftUI evaluated during one layout.
//
// CONTROLS. LZ0 (Grid) against LZ1 (LazyVGrid, two flexible columns) over the
// same four leaves; LZ7 (Grid, same 1000 cells) against LZ6.
//
// RECORDED 2026-09-17 by the grids design session, macOS 27.0 (26A428),
// `/usr/bin/swift` = Apple Swift 6.4 (swiftlang-6.4.0.33.1). Exit 0, run twice,
// byte-identical stdout.
//
// THE READING.
// 1. A lazy grid's columns come from its GridItems, not its cells: the 100pt
//    cell c does not widen its column in LZ1 (it overflows a 96pt column, at
//    x -2) where Grid widens column 0 to 100 (LZ0); fixed items are exact
//    (LZ2); adaptive items fit as many 45pt columns as the width allows (LZ3,
//    three at 200). A flexible lazy grid fills the proposed width (LZ1 200,
//    Grid 128) and at nil answers from its cells' ideal sizes (LZ4 58).
//    LazyHGrid is the same on the other axis (LZ5).
// 2. It is lazy: in a 200pt scroll view 16 of 1000 cell bodies were evaluated
//    (LZ6), all 1000 for Grid (LZ7).
// So a lazy grid is a different algorithm (item-driven column sizing) AND needs
// windowing, which is stage 4's mechanism.
//
// WHOLE STDOUT:
//
//   === LZ: LazyVGrid / LazyHGrid, for the scope ruling only
//   LZ0 control Grid{[a 30x10, b 20x10] [c 100x10, d 20x10]} @200x200: size 128x28 | a (35,0 30x10) | b (108,0 20x10) | c (0,18 100x10) | d (108,18 20x10)
//   LZ1 LazyVGrid(.flexible x2){a 30x10, b 20x10, c 100x10, d 20x10} @200x200: size 200x28 | a (33,0 30x10) | b (142,0 20x10) | c (-2,18 100x10) | d (142,18 20x10)
//   LZ2 LazyVGrid(.fixed 50, .fixed 40){a, b, c 100x10, d} @200x200: size 200x28 | a (61,0 30x10) | b (119,0 20x10) | c (26,18 100x10) | d (119,18 20x10)
//   LZ3 LazyVGrid(.adaptive(minimum: 45)){a..f 10x10} @200x200: size 200.00x28 | a (25.67,0 10x10) | b (95.00,0 10x10) | c (164.33,0 10x10) | d (25.67,18 10x10) | e (95.00,18 10x10) | f (164.33,18 10x10)
//   LZ4 LazyVGrid(.flexible x2) at nil @nilxnil: size 58x28 | a (-2.50,0 30x10) | b (35.50,0 20x10) | c (-37.50,18 100x10) | d (35.50,18 20x10)
//   LZ5 LazyHGrid(rows: .fixed 30, .fixed 20){a, b, c 10x100, d} @200x200: size 28x200 | a (0,71 10x30) | b (0,109 10x20) | c (18,36 10x100) | d (18,109 10x20)
//   LZ6 LazyVGrid of 1000 cells in a 200x200 ScrollView: 16 cell bodies evaluated, max index 15
//   LZ7 control: Grid of the same 1000 cells: 1000 cell bodies evaluated
//   DONE
//

import AppKit
import SwiftUI

func d(_ v: CGFloat?) -> String {
    guard let v else { return "nil" }
    if v == .infinity { return "inf" }
    return v == v.rounded() ? String(Int(v)) : String(format: "%.2f", v)
}
func fmt(_ s: CGSize) -> String { "\(d(s.width))x\(d(s.height))" }
func fmt(_ r: CGRect) -> String { "(\(d(r.minX)),\(d(r.minY)) \(d(r.width))x\(d(r.height)))" }

nonisolated(unsafe) var placed: [String: CGRect] = [:]
nonisolated(unsafe) var names: [String] = []
nonisolated(unsafe) var lastSize: CGSize = .zero
nonisolated(unsafe) var built = Set<Int>()

struct L: Layout {
    let name: String; let w: CGFloat; let h: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews _: Subviews, cache: inout ()) -> CGSize {
        if !names.contains(name) { names.append(name) }
        return CGSize(width: w, height: h)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        if !names.contains(name) { names.append(name) }
        placed[name] = bounds
        subviews[0].place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
    }
}
func fx(_ n: String, _ w: CGFloat, _ h: CGFloat) -> some View { L(name: n, w: w, h: h) { SwiftUI.Color.clear } }

struct Probe: Layout {
    let proposal: ProposedViewSize
    func sizeThatFits(proposal _: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let s = subviews[0].sizeThatFits(proposal); lastSize = s; return s
    }
    func placeSubviews(in _: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        lastSize = subviews[0].sizeThatFits(proposal)
        subviews[0].place(at: .zero, anchor: .topLeading, proposal: proposal)
    }
}
@MainActor func arm<V: View>(_ label: String, _ proposal: ProposedViewSize, @ViewBuilder _ view: () -> V) {
    placed = [:]; names = []; lastSize = CGSize(width: -1, height: -1)
    let host = NSHostingView(rootView: Probe(proposal: proposal) { view() })
    host.frame = CGRect(x: 0, y: 0, width: 1000, height: 1000)
    host.layoutSubtreeIfNeeded()
    print("\(label) @\(d(proposal.width))x\(d(proposal.height)): size \(fmt(lastSize))" + names.map { " | \($0) " + (placed[$0].map(fmt) ?? "not placed") }.joined())
    fflush(stdout)
}

/// A cell that records its index when SwiftUI evaluates its body.
struct Counted: View {
    let i: Int
    var body: some View {
        built.insert(i)
        return SwiftUI.Color.clear.frame(height: 20)
    }
}

@MainActor func probes() {
    let p200 = ProposedViewSize(width: 200, height: 200)
    let none = ProposedViewSize(width: nil, height: nil)
    print("=== LZ: LazyVGrid / LazyHGrid, for the scope ruling only")
    // Control: Grid sizes a column from its widest cell.
    arm("LZ0 control Grid{[a 30x10, b 20x10] [c 100x10, d 20x10]}", p200) { Grid { GridRow { fx("a",30,10); fx("b",20,10) }; GridRow { fx("c",100,10); fx("d",20,10) } } }
    arm("LZ1 LazyVGrid(.flexible x2){a 30x10, b 20x10, c 100x10, d 20x10}", p200) { LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())]) { fx("a",30,10); fx("b",20,10); fx("c",100,10); fx("d",20,10) } }
    arm("LZ2 LazyVGrid(.fixed 50, .fixed 40){a, b, c 100x10, d}", p200) { LazyVGrid(columns: [GridItem(.fixed(50)), GridItem(.fixed(40))]) { fx("a",30,10); fx("b",20,10); fx("c",100,10); fx("d",20,10) } }
    arm("LZ3 LazyVGrid(.adaptive(minimum: 45)){a..f 10x10}", p200) { LazyVGrid(columns: [GridItem(.adaptive(minimum: 45))]) { fx("a",10,10); fx("b",10,10); fx("c",10,10); fx("d",10,10); fx("e",10,10); fx("f",10,10) } }
    arm("LZ4 LazyVGrid(.flexible x2) at nil", none) { LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())]) { fx("a",30,10); fx("b",20,10); fx("c",100,10); fx("d",20,10) } }
    arm("LZ5 LazyHGrid(rows: .fixed 30, .fixed 20){a, b, c 10x100, d}", p200) { LazyHGrid(rows: [GridItem(.fixed(30)), GridItem(.fixed(20))]) { fx("a",10,30); fx("b",10,20); fx("c",10,100); fx("d",10,20) } }

    // Laziness: 1000 cells in a 200pt-tall ScrollView; count bodies evaluated.
    built = []
    let host = NSHostingView(rootView: ScrollView { LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())]) { ForEach(0..<1000, id: \.self) { Counted(i: $0) } } })
    host.frame = CGRect(x: 0, y: 0, width: 200, height: 200)
    host.layoutSubtreeIfNeeded()
    print("LZ6 LazyVGrid of 1000 cells in a 200x200 ScrollView: \(built.count) cell bodies evaluated, max index \(built.max() ?? -1)")
    built = []
    let host2 = NSHostingView(rootView: ScrollView { Grid { ForEach(0..<500, id: \.self) { r in GridRow { Counted(i: 2 * r); Counted(i: 2 * r + 1) } } } })
    host2.frame = CGRect(x: 0, y: 0, width: 200, height: 200)
    host2.layoutSubtreeIfNeeded()
    print("LZ7 control: Grid of the same 1000 cells: \(built.count) cell bodies evaluated")
    fflush(stdout)
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
MainActor.assumeIsolated { probes() }
print("DONE")
