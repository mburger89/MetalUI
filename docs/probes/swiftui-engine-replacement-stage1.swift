// SwiftUI probe: what a LOWERED legacy element must answer on the proposal
// path — plan task 7, stage 1 (engine replacement). Evidence for rulings
// LR-… in docs/superpowers/2026-09-17-engine-replacement-decisions.md.
//
// HOW TO RUN (ruling SA-O):
//
//   /usr/bin/swift docs/probes/swiftui-engine-replacement-stage1.swift
//
// `/usr/bin/swift` is Apple's toolchain; a swift.org toolchain's JIT fails on
// SwiftUI symbols.
//
// METHOD. As `swiftui-stack-algorithms.swift`: `size` is
// `LayoutSubview.sizeThatFits` of the whole view at the stated proposal, taken
// by the `Probe` layout, which places it at (0, 0); a `leaf` line comes from
// `Leaf`, a custom `Layout` that answers `clamp(proposal ?? ideal, min, max)`
// per axis and records its last placed rect; a `geometry` line is
// `onGeometryChange` in the probe's own coordinate space. Every group opens
// with a control that must DIFFER from at least one of its arms (practices
// shape 15); where a group's point is that an arm AGREES with a control, a
// second control that disagrees is named.
//
// Groups:
//   T  — Text's answer at nil, narrow, zero, wide and infinite widths, and a
//        Text's own frame inside a narrower fixed frame (the scratch
//        differential's T8 arm).
//   B  — padding INSIDE a fixed frame with an explicit alignment (the lowering
//        of a legacy border-box `Style.padding` under `.width/.height`).
//   H  — `.hidden()` keeps its layout space; a removed `if` does not.
//   S  — cross-axis fill: a zero-width child, a greedy frame, a greedy view
//        (evidence for stage 2, not stage 1).
//   G  — main-axis fill in a fixed-width HStack (evidence for stage 2).
//   W  — two Texts (or a Text and a fixed leaf) in an HStack(spacing: 0) under
//        a narrow width, with and without `layoutPriority` (revision 2,
//        critic round 1 finding 10: evidence for `LR-F`'s withdrawn clamp).
//
// RECORDED 2026-09-16 by the engine-replacement design session (plan task 7,
// stage 1), macOS 27.0 (26A428), `/usr/bin/swift` = Apple Swift 6.4
// (swiftlang-6.4.0.33.1). The whole stdout follows the reading; see the
// OUTPUT block at the end of this header.
//
// Exit 0. Run twice; the two outputs are byte-identical (`diff` empty), 61
// lines.
//
// REVISION 2, RECORDED 2026-09-16 21:10 PDT by the same session's critic round
// 1, same machine and toolchain: group W appended; nothing else changed. Exit
// 0; run twice, byte-identical, 79 lines; the 61 lines of revision 1 are
// reproduced unchanged (the output minus W's lines `diff`s empty against
// revision 1's block).
//
// READING.
// - T: a Text HUGS its widest line. At 60 it answers 45x112 and a 60-wide
//   frame centres it at x 7.5 (T7, T8), or places it at 0 under a leading
//   stack (T9); the legacy CSS leaf is the frame's full 60 (scratch
//   differential T8). Below any word's width it answers the PROPOSAL, not
//   the widest word: 0x592 at 0 (T3), 5x592 at 5 (T4). At nil, 1000 and inf
//   it answers one line, 252x16 (T1, T5, T6). Control T0 (33x16) differs.
// - B: padding inside a fixed frame offsets the child by the inset at
//   `.topLeading` (B1 (12, 12) against control B0's (0, 0)) and is centred
//   inside the frame at `.center` (B2 (25, 17)). B3: the counter chrome's
//   HStack(spacing 12).padding(12) places at 12, 60, 212 — the legacy
//   `Box(style: row)` rects of scratch T1b, relative to its origin.
// - H: `.hidden()` KEEPS its space: c at y 40 (H1), as control H0; a false
//   `if` removes it: c at 20 (H2). The legacy `hidden()` is `display: none`,
//   which removes it (H2's answer).
// - S (stage 2 evidence): a greedy frame in a 196-wide VStack is 196 wide and
//   does not resize its 0-wide child (S1, child still at x 98); a greedy view
//   is 196 wide itself (S2); unframed, the greedy frame takes the stack's own
//   width, 42 (S3). Control S0: the 0-wide child is centred, 0 wide.
// - G (stage 2 evidence): a width-flexible leaf takes the fixed HStack's
//   surplus, 516 = 568 - 40 - 12 (G1); a greedy frame over a 0-wide leaf takes
//   the same 516 while the leaf stays 0 wide and centred at 310 (G2). Control
//   G0: 0 wide, and the fixed pair is centred (a at 258).
// - W (revision 2): at 80 the long label wraps to 46x48 and "Short" keeps 34
//   (W1, the stack-algorithms probe's G18 with geometry); control W0 at 400
//   is one line each (105, 34). Priority on the SHORT text changes nothing
//   (W3 = W1). Priority on the LONG text gives it 59x32 and "Short" 18x32 —
//   SwiftUI hands the lower-priority Text less than its widest word (W2). A
//   fixed 40-wide leaf leaves the label 34 (W4). Below both words' widths at
//   40: 20 and 19 (W5). MetalUI's kernel, measured in the design session's
//   scratch P2 (record §18): W0, W1, W3, W4, W5 agree to the point (45/33
//   against 46/34, font metrics) with or without a below-word clamp; W2
//   disagrees either way — 76/8 (an 84 root) without the clamp, 75/5 with it.
//
// OUTPUT:
//
//   T0 control Text("alpha") @nilxnil: size 33x16
//   T1 Text(long) @nilxnil: size 252x16
//   T2 Text(long) @60xnil: size 45x112
//   T3 Text(long) @0xnil: size 0x592
//   T4 Text(long) @5xnil: size 5x592
//   T5 Text(long) @1000xnil: size 252x16
//   T6 Text(long) @infxnil: size 252x16
//   T7 VStack(spacing:0){Text(long)}.frame(width:60) text frame @nilxnil: size 60x112
//       geometry text: (7.50, 0) 45x112
//   T8 control VStack(spacing:0){a 60x10; Text(long)}.frame(width:60) text frame @nilxnil: size 60x122
//       leaf a: at (0, 0) 60x10
//       geometry text: (7.50, 10) 45x112
//   T9 VStack(alignment:.leading,spacing:0){a 60x10; Text(long)}.frame(width:60) text frame @nilxnil: size 60x122
//       leaf a: at (0, 0) 60x10
//       geometry text: (0, 10) 45x112
//   B0 control c10x26.frame(60x60,.topLeading) @nilxnil: size 60x60
//       leaf c: at (0, 0) 10x26
//   B1 c10x26.padding(12).frame(60x60,.topLeading) @nilxnil: size 60x60
//       leaf c: at (12, 12) 10x26
//   B2 c10x26.padding(12).frame(60x60,.center) @nilxnil: size 60x60
//       leaf c: at (25, 17) 10x26
//   B3 HStack(spacing:12){a36x36; b140x36; c36x36}.padding(12).frame? none (counter chrome) @nilxnil: size 260x60
//       leaf a: at (12, 12) 36x36
//       leaf b: at (60, 12) 140x36
//       leaf c: at (212, 12) 36x36
//   H0 control VStack(spacing:0){a20; b20; c20} @nilxnil: size 20x60
//       leaf a: at (0, 0) 20x20
//       leaf b: at (0, 20) 20x20
//       leaf c: at (0, 40) 20x20
//   H1 VStack(spacing:0){a20; b20.hidden(); c20} @nilxnil: size 20x60
//       leaf a: at (0, 0) 20x20
//       leaf b: at (0, 0) 20x20
//       leaf c: at (0, 40) 20x20
//   H2 VStack(spacing:0){a20; if false {b20}; c20} @nilxnil: size 20x40
//       leaf a: at (0, 0) 20x20
//       leaf c: at (0, 20) 20x20
//   S0 control VStack(spacing:0){a42x16; b0x26}.frame(width:196) @nilxnil: size 196x42
//       leaf a: at (77, 0) 42x16
//       leaf b: at (98, 16) 0x26
//   S1 VStack(spacing:0){a42x16; b0x26.frame(maxWidth:.infinity)}.frame(width:196) @nilxnil: size 196x42
//       leaf a: at (77, 0) 42x16
//       leaf b: at (98, 16) 0x26
//       geometry bframe: (0, 16) 196x26
//   S2 VStack(spacing:0){a42x16; Color.frame(height:26)}.frame(width:196) @nilxnil: size 196x42
//       leaf a: at (77, 0) 42x16
//       geometry color: (0, 16) 196x26
//   S3 VStack(spacing:0){a42x16; b0x26.frame(maxWidth:.infinity)} unframed @nilxnil: size 42x42
//       leaf a: at (0, 0) 42x16
//       leaf b: at (21, 16) 0x26
//       geometry bframe: (0, 16) 42x26
//   G0 control HStack(spacing:12){a40x40; b0x12}.frame(width:568) @nilxnil: size 568x40
//       leaf a: at (258, 0) 40x40
//       leaf b: at (310, 14) 0x12
//   G1 HStack(spacing:12){a40x40; b(0...inf)x12}.frame(width:568) @nilxnil: size 568x40
//       leaf a: at (0, 0) 40x40
//       leaf b: at (52, 14) 516x12
//   G2 HStack(spacing:12){a40x40; b0x12.frame(maxWidth:.infinity)}.frame(width:568) @nilxnil: size 568x40
//       leaf a: at (0, 0) 40x40
//       leaf b: at (310, 14) 0x12
//       geometry bframe: (52, 14) 516x12
//   W0 control HStack(spacing:0){Text(label); Text("Short")} @400xnil: size 139x16
//       geometry long: (0, 0) 105x16
//       geometry short: (105, 0) 34x16
//   W1 HStack(spacing:0){Text(label); Text("Short")} (stack-algorithms G18) @80xnil: size 80x48
//       geometry long: (0, 0) 46x48
//       geometry short: (46, 16) 34x16
//   W2 HStack(spacing:0){Text(label).layoutPriority(1); Text("Short")} @80xnil: size 77x32
//       geometry long: (0, 0) 59x32
//       geometry short: (59, 0) 18x32
//   W3 HStack(spacing:0){Text(label); Text("Short").layoutPriority(1)} @80xnil: size 80x48
//       geometry long: (0, 0) 46x48
//       geometry short: (46, 16) 34x16
//   W4 HStack(spacing:0){Text(label); a 40x10} @80xnil: size 74x64
//       leaf a: at (34, 27) 40x10
//       geometry long: (0, 0) 34x64
//   W5 HStack(spacing:0){Text("alpha bravo"); Text("charlie")} @40xnil: size 39x64
//       geometry first: (0, 0) 20x64
//       geometry second: (20, 8) 19x48
//   DONE

import AppKit
import SwiftUI

func d(_ v: CGFloat?) -> String {
    guard let v else { return "nil" }
    if v == .infinity { return "inf" }
    return v == v.rounded() ? String(Int(v)) : String(format: "%.2f", v)
}
func fmt(_ s: CGSize) -> String { "\(d(s.width))x\(d(s.height))" }
func fmt(_ p: ProposedViewSize) -> String { "\(d(p.width))x\(d(p.height))" }

nonisolated(unsafe) var placed: [String: CGRect] = [:]
nonisolated(unsafe) var order: [String] = []
nonisolated(unsafe) var lastSize: CGSize = .zero
nonisolated(unsafe) var geometry: [String: CGRect] = [:]

struct Probe: Layout {
    let proposal: ProposedViewSize
    func sizeThatFits(proposal _: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let size = subviews[0].sizeThatFits(proposal)
        lastSize = size
        return size
    }
    func placeSubviews(in _: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        lastSize = subviews[0].sizeThatFits(proposal)
        subviews[0].place(at: .zero, anchor: .topLeading, proposal: proposal)
    }
}

struct Leaf: Layout {
    let name: String
    var minW: CGFloat = 0, idealW: CGFloat, maxW: CGFloat
    var minH: CGFloat = 0, idealH: CGFloat, maxH: CGFloat
    func sizeThatFits(proposal p: ProposedViewSize, subviews _: Subviews, cache: inout ()) -> CGSize {
        if placed[name] == nil, !order.contains(name) { order.append(name) }
        return CGSize(width: min(max(p.width ?? idealW, minW), maxW),
                      height: min(max(p.height ?? idealH, minH), maxH))
    }
    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        if !order.contains(name) { order.append(name) }
        placed[name] = bounds
        subviews[0].place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
    }
}

func fixed(_ n: String, _ w: CGFloat, _ h: CGFloat) -> some View {
    Leaf(name: n, minW: w, idealW: w, maxW: w, minH: h, idealH: h, maxH: h) { SwiftUI.Color.clear }
}
func flexW(_ n: String, _ minW: CGFloat, _ ideal: CGFloat, _ maxW: CGFloat, _ h: CGFloat) -> some View {
    Leaf(name: n, minW: minW, idealW: ideal, maxW: maxW, minH: h, idealH: h, maxH: h) { SwiftUI.Color.clear }
}

extension View {
    func geo(_ n: String) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: .named("probe")) } action: { geometry[n] = $0 }
    }
}

@MainActor func run<V: View>(_ label: String, _ proposal: ProposedViewSize, @ViewBuilder _ view: () -> V) {
    placed = [:]; order = []; geometry = [:]
    lastSize = CGSize(width: -1, height: -1)
    let host = NSHostingView(rootView: Probe(proposal: proposal) { view().coordinateSpace(.named("probe")) })
    host.frame = CGRect(x: 0, y: 0, width: 1000, height: 1000)
    host.layoutSubtreeIfNeeded()
    // onGeometryChange delivers after layout; one more pass flushes it.
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    host.layoutSubtreeIfNeeded()
    print("\(label) @\(fmt(proposal)): size \(fmt(lastSize))")
    for n in order {
        let at = placed[n].map { "at (\(d($0.minX)), \(d($0.minY))) \(d($0.width))x\(d($0.height))" } ?? "not placed"
        print("    leaf \(n): \(at)")
    }
    for (n, r) in geometry.sorted(by: { $0.key < $1.key }) {
        print("    geometry \(n): (\(d(r.minX)), \(d(r.minY))) \(d(r.width))x\(d(r.height))")
    }
    fflush(stdout)
}

let long = "alpha bravo charlie delta echo foxtrot golf"
let none = ProposedViewSize(width: nil, height: nil)
func w(_ x: CGFloat?) -> ProposedViewSize { ProposedViewSize(width: x, height: nil) }

@MainActor func probes() {
    // T — Text. Control T0: a one-word string differs from T1 at nil.
    run("T0 control Text(\"alpha\")", none) { Text("alpha") }
    run("T1 Text(long)", none) { Text(long) }
    run("T2 Text(long)", w(60)) { Text(long) }
    run("T3 Text(long)", w(0)) { Text(long) }
    run("T4 Text(long)", w(5)) { Text(long) }
    run("T5 Text(long)", w(1000)) { Text(long) }
    run("T6 Text(long)", w(.infinity)) { Text(long) }
    run("T7 VStack(spacing:0){Text(long)}.frame(width:60) text frame", none) {
        VStack(spacing: 0) { Text(long).geo("text") }.frame(width: 60)
    }
    run("T8 control VStack(spacing:0){a 60x10; Text(long)}.frame(width:60) text frame", none) {
        VStack(spacing: 0) { fixed("a", 60, 10); Text(long).geo("text") }.frame(width: 60)
    }
    run("T9 VStack(alignment:.leading,spacing:0){a 60x10; Text(long)}.frame(width:60) text frame", none) {
        VStack(alignment: .leading, spacing: 0) { fixed("a", 60, 10); Text(long).geo("text") }.frame(width: 60)
    }

    // B — padding inside a fixed frame. Control B0 (no padding) differs from B1.
    run("B0 control c10x26.frame(60x60,.topLeading)", none) {
        fixed("c", 10, 26).frame(width: 60, height: 60, alignment: .topLeading)
    }
    run("B1 c10x26.padding(12).frame(60x60,.topLeading)", none) {
        fixed("c", 10, 26).padding(12).frame(width: 60, height: 60, alignment: .topLeading)
    }
    run("B2 c10x26.padding(12).frame(60x60,.center)", none) {
        fixed("c", 10, 26).padding(12).frame(width: 60, height: 60)
    }
    run("B3 HStack(spacing:12){a36x36; b140x36; c36x36}.padding(12).frame? none (counter chrome)", none) {
        HStack(spacing: 12) { fixed("a", 36, 36); fixed("b", 140, 36); fixed("c", 36, 36) }.padding(12)
    }

    // H — hidden. Control H0 (all shown) agrees with H1 on c; H2 disagrees.
    run("H0 control VStack(spacing:0){a20; b20; c20}", none) {
        VStack(spacing: 0) { fixed("a", 20, 20); fixed("b", 20, 20); fixed("c", 20, 20) }
    }
    run("H1 VStack(spacing:0){a20; b20.hidden(); c20}", none) {
        VStack(spacing: 0) { fixed("a", 20, 20); fixed("b", 20, 20).hidden(); fixed("c", 20, 20) }
    }
    let show = false
    run("H2 VStack(spacing:0){a20; if false {b20}; c20}", none) {
        VStack(spacing: 0) { fixed("a", 20, 20); if show { fixed("b", 20, 20) }; fixed("c", 20, 20) }
    }

    // S — cross-axis fill inside a 196-wide column. Control S0: a fixed 42x16.
    run("S0 control VStack(spacing:0){a42x16; b0x26}.frame(width:196)", none) {
        VStack(spacing: 0) { fixed("a", 42, 16); fixed("b", 0, 26) }.frame(width: 196)
    }
    run("S1 VStack(spacing:0){a42x16; b0x26.frame(maxWidth:.infinity)}.frame(width:196)", none) {
        VStack(spacing: 0) { fixed("a", 42, 16); fixed("b", 0, 26).frame(maxWidth: .infinity).geo("bframe") }.frame(width: 196)
    }
    run("S2 VStack(spacing:0){a42x16; Color.frame(height:26)}.frame(width:196)", none) {
        VStack(spacing: 0) { fixed("a", 42, 16); SwiftUI.Color.red.frame(height: 26).geo("color") }.frame(width: 196)
    }
    run("S3 VStack(spacing:0){a42x16; b0x26.frame(maxWidth:.infinity)} unframed", none) {
        VStack(spacing: 0) { fixed("a", 42, 16); fixed("b", 0, 26).frame(maxWidth: .infinity).geo("bframe") }
    }

    // G — main-axis fill in a 568-wide HStack. Control G0: a fixed 0x12.
    run("G0 control HStack(spacing:12){a40x40; b0x12}.frame(width:568)", none) {
        HStack(spacing: 12) { fixed("a", 40, 40); fixed("b", 0, 12) }.frame(width: 568)
    }
    run("G1 HStack(spacing:12){a40x40; b(0...inf)x12}.frame(width:568)", none) {
        HStack(spacing: 12) { fixed("a", 40, 40); flexW("b", 0, 0, .infinity, 12) }.frame(width: 568)
    }
    run("G2 HStack(spacing:12){a40x40; b0x12.frame(maxWidth:.infinity)}.frame(width:568)", none) {
        HStack(spacing: 12) { fixed("a", 40, 40); fixed("b", 0, 12).frame(maxWidth: .infinity).geo("bframe") }.frame(width: 568)
    }

    // W — text inside a horizontal stack under a narrow width (revision 2,
    // critic finding 10: does a Text's answer below a word change stack
    // allocation?). Control W0: at 400 both texts are one line.
    let label = "A fairly long label"
    run("W0 control HStack(spacing:0){Text(label); Text(\"Short\")}", w(400)) {
        HStack(spacing: 0) { Text(label).geo("long"); Text("Short").geo("short") }
    }
    run("W1 HStack(spacing:0){Text(label); Text(\"Short\")} (stack-algorithms G18)", w(80)) {
        HStack(spacing: 0) { Text(label).geo("long"); Text("Short").geo("short") }
    }
    run("W2 HStack(spacing:0){Text(label).layoutPriority(1); Text(\"Short\")}", w(80)) {
        HStack(spacing: 0) { Text(label).layoutPriority(1).geo("long"); Text("Short").geo("short") }
    }
    run("W3 HStack(spacing:0){Text(label); Text(\"Short\").layoutPriority(1)}", w(80)) {
        HStack(spacing: 0) { Text(label).geo("long"); Text("Short").layoutPriority(1).geo("short") }
    }
    run("W4 HStack(spacing:0){Text(label); a 40x10}", w(80)) {
        HStack(spacing: 0) { Text(label).geo("long"); fixed("a", 40, 10) }
    }
    run("W5 HStack(spacing:0){Text(\"alpha bravo\"); Text(\"charlie\")}", w(40)) {
        HStack(spacing: 0) { Text("alpha bravo").geo("first"); Text("charlie").geo("second") }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
MainActor.assumeIsolated { probes() }
print("DONE")
