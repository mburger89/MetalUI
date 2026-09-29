// SwiftUI probe: where a vertical stack's gaps and a grid's row, gap and
// anchor offsets put the baselines it reports (plan task 11 part 1, lane 2's
// fix round; rulings TE-K item 2 and TE-X item 2 in
// docs/superpowers/2026-09-28-text-semantics-decisions.md). A companion to
// `swiftui-text-semantics.swift`, whose `Measure` instrument it copies: B1g
// and X3i there measure only spacing 0 and a one-cell grid, where every
// offset is 0.
//
// HOW TO RUN, from the repository root:
//
//   xcrun swiftc docs/probes/swiftui-baseline-offsets.swift -o /tmp/baseline-offsets && /tmp/baseline-offsets
//
// Headless (an NSHostingView's fittingSize drives the pass, displayScale 2),
// so a locked screen measures the same. `Text("Hg")` at the default 13 pt is
// 17.5 x 16 with both baselines 13; at 26 pt 33.5 x 30 at 25.
//
// Separating arms: O1 (spacing 8) against its control O1c (spacing 0, B1g's
// 13/41) — the last baseline moves by exactly the gap; O2 (centred rows)
// against O3 (`.top`) — the first baseline moves by the centring offset; O4
// (a bottom anchor) against O3's first row.
//
// RECORDED OUTPUT (2026-09-28, macOS 27.0, Xcode's Swift 6.4):
//
//     O1c VStack(spacing: 0){Text 13; Text 26}: size=33.5x46 first=13 last=41
//     O1 VStack(spacing: 8){Text 13; Text 26}: size=33.5x54 first=13 last=49
//     O2 Grid(vSpacing: 8){GridRow{Text 13; Color 40}; GridRow{Text 26}}: size=81.5x78 first=25 last=73
//     O3 Grid(alignment: .top, vSpacing: 8){same}: size=81.5x78 first=13 last=73
//     O4 Grid(alignment: .top){GridRow{Text 13 .gridCellAnchor(.bottom); Color 40}}: size=65.5x40 first=37 last=37
//     O5 Grid(alignment: .top){GridRow(alignment: .bottom){Text 13; Color 40}}: size=65.5x40 first=37 last=37
//
// READING. A vertical stack's last baseline is its last child's at its placed
// offset, gaps included (O1: 16 + 8 + 25 = 49; O1c: 16 + 25 = 41). A grid's
// baselines are its cells' at their placed offsets: the row cursor and the
// vertical gap (O2/O3 last: 40 + 8 + 25 = 73), the grid's own vertical factor
// (O2 first: (40 − 16) × ½ + 13 = 25; O3 at `.top`: 13) and a cell anchor
// (O4: (40 − 16) × 1 + 13 = 37). O5 separates a ROW's own alignment from a
// per-cell anchor (O4) and from the grid's own (O2/O3): a `GridRow(alignment:
// .bottom)` with no cell anchor reads the same 37 as O4's cell anchor — a
// row's own factor, not only an anchor's or the grid's, must reach the
// offset (`TE-AB`).

import AppKit
import SwiftUI

nonisolated(unsafe) var log: [String: String] = [:]

struct Measure: Layout {
    let key: String
    func sizeThatFits(proposal _: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let s = subviews[0].sizeThatFits(.unspecified)
        let d = subviews[0].dimensions(in: .unspecified)
        log[key] = "size=\(fmt(s.width))x\(fmt(s.height)) first=\(fmt(d[.firstTextBaseline])) last=\(fmt(d[.lastTextBaseline]))"
        return s
    }
    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews[0].place(at: bounds.origin, proposal: .unspecified)
    }
}

func fmt(_ v: CGFloat) -> String {
    let r = (v * 1000).rounded() / 1000
    return r == r.rounded() ? String(Int(r)) : String(Double(r))
}

@MainActor
func measure(_ key: String, _ view: some View) -> String {
    log[key] = nil
    let host = NSHostingView(rootView: Measure(key: key) { view }.environment(\.displayScale, 2))
    _ = host.fittingSize
    return log[key] ?? "not measured"
}

@MainActor
func run() {
    let big = Font.system(size: 26)
    print("  O1c VStack(spacing: 0){Text 13; Text 26}: \(measure("O1c", VStack(spacing: 0) { Text("Hg"); Text("Hg").font(big) }))")
    print("  O1 VStack(spacing: 8){Text 13; Text 26}: \(measure("O1", VStack(spacing: 8) { Text("Hg"); Text("Hg").font(big) }))")
    print("  O2 Grid(vSpacing: 8){GridRow{Text 13; Color 40}; GridRow{Text 26}}: \(measure("O2", Grid(verticalSpacing: 8) { GridRow { Text("Hg"); Color.red.frame(width: 40, height: 40) }; GridRow { Text("Hg").font(big) } }))")
    print("  O3 Grid(alignment: .top, vSpacing: 8){same}: \(measure("O3", Grid(alignment: .top, verticalSpacing: 8) { GridRow { Text("Hg"); Color.red.frame(width: 40, height: 40) }; GridRow { Text("Hg").font(big) } }))")
    print("  O4 Grid(alignment: .top){GridRow{Text 13 .gridCellAnchor(.bottom); Color 40}}: \(measure("O4", Grid(alignment: .top) { GridRow { Text("Hg").gridCellAnchor(.bottom); Color.red.frame(width: 40, height: 40) } }))")
    print("  O5 Grid(alignment: .top){GridRow(alignment: .bottom){Text 13; Color 40}}: \(measure("O5", Grid(alignment: .top) { GridRow(alignment: .bottom) { Text("Hg"); Color.red.frame(width: 40, height: 40) } }))")
}

MainActor.assumeIsolated { run() }
