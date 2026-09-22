// SwiftUI probe: which child a stack serves first when two children both
// answer infinity at an infinite main proposal but differ at 0 (a Grid, a
// nested stack, a leaf with a minimum). Evidence for ruling GR-X in
// docs/superpowers/2026-09-17-grids-decisions.md (plan task 7, stage G, lane 2).
//
// HOW TO RUN: /usr/bin/swift docs/probes/swiftui-grid-stack-ties.swift
//
// METHOD. The grid probe's instrument (`docs/probes/swiftui-grid.swift`): an
// NSHostingView whose root `Probe` layout asks the view under test for its
// answer at the stated proposal and places it at (0, 0) at that proposal. A
// leaf is a custom `Layout` answering a pure function of its proposal, logging
// every measurement in order; an arm line reads `name (x,y wxh) <- placement
// proposal`, then the measurements in order.
//
// CONTROLS. T0 (a leaf clamped 0...40 beside a flexible leaf) shows the stack
// serving the less flexible child first, so an arm CAN disagree with
// declaration order; T5 (two flexible leaves) is the equal-flexibility baseline.
//
// RECORDED 2026-09-17 by the grids track, lane 2, macOS 27.0 (26A428),
// `/usr/bin/swift` = Apple Swift 6.4 (swiftlang-6.4.0.33.1). Exit 0, run twice,
// byte-identical stdout (`diff` empty).
//
// THE READING.
// 1. T0 (control): a child clamped 0...40 is served before a flexible one
//    declared earlier: b 40, a 52. An arm here can contradict declaration order.
// 2. T7, NO GRID: `VStack{z flexible; b height >= 58, no maximum}` at 200x100
//    serves b first (b is offered 46 and answers 58; z gets 34), although both
//    answer inf at an infinite main proposal and z is declared first. So when
//    both flexibilities are infinite SwiftUI does not fall back to declaration
//    order; the child with the larger answer at 0 went first here. T6 (GE19,
//    the same with a Grid of height 58 at 0) reads the same z 34.
// 3. T1 (GE10) reads a 36: the grid (18 wide at 0, inf at inf) is served before
//    the flexible a declared earlier. T2, T3, T4, T5 and T8 cannot tell the
//    orders apart (the second child answers exactly what it is offered).
// So the grid arms GE10 and GE19 turn on the stack's order for two infinite
// flexibilities, which MetalUI's linear stack (ruling CN-B: "ties in
// declaration order") breaks the other way; the grid is not involved (T7).
//
// STDOUT:
//
//   T0 control: HStack{a flexible; b width 0...40} at 100x100 @100x100: size 100x100 | a (0,0 52x100) <- 52x100 | b (60,45 40x10) <- 46x100
//       measured, in order: a infx100->infx100; b infx100->40x10; b 46x100->40x10; a 52x100->52x100
//   T1 GE10: HStack{a flexible; Grid{[c flexible priority 1, d 10x10]}} at 100x100 @100x100: size 100x100 | a (0,0 36x100) <- 36x100 | c (44,0 38x100) <- 38x100 | d (90,45 10x10) <- 10x100
//       measured, in order: a infx100->infx100; c 0x0->0x0; c infxinf->infxinf; d 0x0->10x10; d infxinf->10x10; c infx100->infx100; d infx100->10x10; d 10x100->10x10; d 0x0->10x10; d infxinf->10x10; c 0x100->0x100; d 0x100->10x10; d 10x100->10x10; a 0x100->0x100; c 0x0->0x0; c infxinf->infxinf; d 0x0->10x10; d infxinf->10x10; c 38x100->38x100; d 0x100->10x10; d 10x100->10x10; a 36x100->36x100
//   T2 HStack{a flexible; HStack{c flexible; d 10x10}} at 100x100 (no grid) @100x100: size 100x100 | a (0,0 46x100) <- 46x100 | c (54,0 28x100) <- 28x100 | d (90,45 10x10) <- 19x100
//       measured, in order: a infx100->infx100; c infx100->infx100; d infx100->10x10; c 0x100->0x100; d 0x100->10x10; a 0x100->0x100; d 19x100->10x10; c 28x100->28x100; a 46x100->46x100
//   T3 HStack{a flexible; b width >= 18, no maximum} at 100x100 @100x100: size 100x100 | a (0,0 46x100) <- 46x100 | b (54,0 46x100) <- 46x100
//       measured, in order: a infx100->infx100; b infx100->infx100; b 0x100->18x100; a 0x100->0x100; b 46x100->46x100; a 46x100->46x100
//   T4 T3 reversed: HStack{b width >= 18; a flexible} at 100x100 @100x100: size 100x100 | b (0,0 46x100) <- 46x100 | a (54,0 46x100) <- 46x100
//       measured, in order: b infx100->infx100; a infx100->infx100; a 0x100->0x100; b 0x100->18x100; b 46x100->46x100; a 46x100->46x100
//   T5 baseline: HStack{a flexible; b flexible} at 100x100 @100x100: size 100x100 | a (0,0 46x100) <- 46x100 | b (54,0 46x100) <- 46x100
//       measured, in order: a infx100->infx100; b infx100->infx100; b 0x100->0x100; a 0x100->0x100; a 46x100->46x100; b 46x100->46x100
//   T6 GE19: VStack{z flexible; Grid{[a flexible, b 20x20] [c 10x30, d 40x10]}} at 200x100 @200x100: size 200x100 | z (0,0 200x34) <- 200x34 | a (0,42 152x20) <- 152x20 | b (170,42 20x20) <- 40x20 | c (71,70 10x30) <- 152x30 | d (160,80 40x10) <- 40x30
//       measured, in order: z 200xinf->200xinf; a 0x0->0x0; a infxinf->infxinf; b 0x0->20x20; b infxinf->20x20; c 0x0->10x30; c infxinf->10x30; d 0x0->40x10; d infxinf->40x10; b 96xinf->20x20; c 96xinf->10x30; d 96xinf->40x10; a 152xinf->152xinf; b 40xinf->20x20; c 152x30->10x30; d 40x30->40x10; b 0x0->20x20; b infxinf->20x20; c 0x0->10x30; c infxinf->10x30; d 0x0->40x10; d infxinf->40x10; b 96x0->20x20; c 96x0->10x30; d 96x30->40x10; a 152x20->152x20; b 40x20->20x20; c 152x30->10x30; d 40x30->40x10; z 200x0->200x0; a 0x0->0x0; a infxinf->infxinf; b 0x0->20x20; b infxinf->20x20; c 0x0->10x30; c infxinf->10x30; d 0x0->40x10; d infxinf->40x10; b 96x19->20x20; c 96x19->10x30; d 96x30->40x10; b 40x20->20x20; c 152x30->10x30; d 40x30->40x10; z 200x34->200x34
//   T7 VStack{z flexible; b height >= 58, no maximum} at 200x100 (no grid) @200x100: size 200x100 | z (0,0 200x34) <- 200x34 | b (0,42 200x58) <- 200x46
//       measured, in order: z 200xinf->200xinf; b 200xinf->200xinf; b 200x0->200x58; z 200x0->200x0; b 200x46->200x58; z 200x34->200x34
//   T8 HStack{a flexible; b width >= 18 but at most 100000} at 100x100 @100x100: size 100x100 | a (0,0 46x100) <- 46x100 | b (54,45 46x10) <- 46x100
//       measured, in order: a infx100->infx100; b infx100->100000x10; b 46x100->46x10; a 46x100->46x100
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
func fx(_ n: String, _ w: CGFloat, _ h: CGFloat) -> some View { leaf(n) { _ in CGSize(width: w, height: h) } }
func fl(_ n: String) -> some View { leaf(n) { p in CGSize(width: p.width ?? 10, height: p.height ?? 10) } }
func cw(_ n: String, _ lo: CGFloat, _ hi: CGFloat) -> some View { leaf(n) { p in CGSize(width: min(max(p.width ?? 10, lo), hi), height: 10) } }
/// width max(proposal ?? 10, lo), no maximum; height proposal ?? 10
func minW(_ n: String, _ lo: CGFloat) -> some View { leaf(n) { p in CGSize(width: max(p.width ?? 10, lo), height: p.height ?? 10) } }
/// height max(proposal ?? 10, lo), no maximum; width proposal ?? 10
func minH(_ n: String, _ lo: CGFloat) -> some View { leaf(n) { p in CGSize(width: p.width ?? 10, height: max(p.height ?? 10, lo)) } }
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
    arm("T0 control: HStack{a flexible; b width 0...40} at 100x100", p(100, 100)) { HStack { fl("a"); cw("b", 0, 40) } }
    arm("T1 GE10: HStack{a flexible; Grid{[c flexible priority 1, d 10x10]}} at 100x100", p(100, 100)) { HStack { fl("a"); Grid { GridRow { fl("c").layoutPriority(1); fx("d", 10, 10) } } } }
    arm("T2 HStack{a flexible; HStack{c flexible; d 10x10}} at 100x100 (no grid)", p(100, 100)) { HStack { fl("a"); HStack { fl("c"); fx("d", 10, 10) } } }
    arm("T3 HStack{a flexible; b width >= 18, no maximum} at 100x100", p(100, 100)) { HStack { fl("a"); minW("b", 18) } }
    arm("T4 T3 reversed: HStack{b width >= 18; a flexible} at 100x100", p(100, 100)) { HStack { minW("b", 18); fl("a") } }
    arm("T5 baseline: HStack{a flexible; b flexible} at 100x100", p(100, 100)) { HStack { fl("a"); fl("b") } }
    arm("T6 GE19: VStack{z flexible; Grid{[a flexible, b 20x20] [c 10x30, d 40x10]}} at 200x100", p(200, 100)) { VStack { fl("z"); Grid { GridRow { fl("a"); fx("b", 20, 20) }; GridRow { fx("c", 10, 30); fx("d", 40, 10) } } } }
    arm("T7 VStack{z flexible; b height >= 58, no maximum} at 200x100 (no grid)", p(200, 100)) { VStack { fl("z"); minH("b", 58) } }
    arm("T8 HStack{a flexible; b width >= 18 but at most 100000} at 100x100", p(100, 100)) { HStack { fl("a"); cw("b", 18, 100000) } }
}
exit(0)
