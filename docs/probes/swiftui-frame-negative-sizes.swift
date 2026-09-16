// SwiftUI probe: what `.frame` answers at a NEGATIVE proposal, under a
// NEGATIVE minimum/maximum, and — the finding that turned out to matter — when
// a maximum is given but NO minimum is. Evidence for rulings FR-L and FR-M in
// docs/superpowers/2026-09-15-frame-sizing-decisions.md (plan task 4).
//
// WHY IT EXISTS. Two questions the 54-arm main probe
// (swiftui-frame-semantics.swift) cannot answer, because it has no negative
// size and no arm where a maximum is given and the proposal is BELOW the
// child's own answer:
//
// 1. Task 4's lane 1 proposed replacing `min ?? 0` with `min ?? -.infinity` in
//    `framedSize`, removing the only floor on a frame's answer. `ProposalLayout`
//    is public and `ProposedSize` is publicly constructible, so an outside
//    layout CAN propose a negative width, and ruling SA-J accepts a negative
//    `minWidth`/`minHeight` (it rejects only NaN and +infinity). The arms below
//    withdrew that change: FR-L floors the DECLARED bounds at 0 instead, which
//    is what SwiftUI does.
// 2. The main probe's D group establishes "with a maximum, the frame answers
//    the PROPOSAL". Every D arm with a maximum happens to propose MORE than the
//    child answers, so the rule was never separated from "the frame answers the
//    LARGER of the proposal and the child". H7, H8, H11, H14 and H15 separate
//    them, and they disagree.
//
// HOW TO RUN. Same two ways as the main probe (ruling SA-O), and here they do
// NOT observe the same things — the compiled form prints two SwiftUI runtime
// diagnostics the script form does not:
//
//   /usr/bin/swift docs/probes/swiftui-frame-negative-sizes.swift
//   xcrun swiftc docs/probes/swiftui-frame-negative-sizes.swift -o /tmp/negsz
//   OS_ACTIVITY_DT_MODE=1 /tmp/negsz 2>&1 | grep -v 'Connection\]\|ntents'
//
// `/usr/bin/swift` is Apple's toolchain; the `swift` first on PATH here is
// swiftly's swift.org build, whose JIT fails on every SwiftUI symbol.
//
// METHOD is the main probe's, reduced: `Probe` proposes a stated size to the
// view under test and prints the size it answers; `Reporter` stands in for the
// child, answers a FIXED size whatever it is proposed, and prints the proposal
// it received. A `RUN` line's FIRST "child proposed" is the measure pass — the
// meaningful one; the second is the placement pass at the settled size. Each
// group opens with positive controls whose numbers must DIFFER from the arms
// under test (practices shape 15): H control reads 20 where H control2 reads 80.
//
// RECORDED 2026-09-15 by the frame-and-sizing critic round, macOS 26.6.2
// (25G83), Apple Swift 6.4 (swiftlang-6.4.0.33.1). VERBATIM OUTPUT:
//
//   RUN H control bare child, proposal 100x100
//       child proposed 100.0x100.0
//   H control bare child, proposal 100x100: size 20.0x20.0
//       child at (0.0, 0.0) size 20.0x20.0
//   RUN H control2 frame(maxWidth: 80), proposal 100x100
//       child proposed 80.0x100.0
//   H control2 frame(maxWidth: 80), proposal 100x100: size 80.0x20.0
//       child proposed 80.0x20.0
//       child at (0.0, 0.0) size 20.0x20.0
//       child at (30.0, 0.0) size 20.0x20.0
//   RUN H1 bare child, proposal -30x-30
//       child proposed -30.0x-30.0
//   H1 bare child, proposal -30x-30: size 20.0x20.0
//       child at (0.0, 0.0) size 20.0x20.0
//   RUN H2 frame(maxWidth: 80), proposal -30x-30
//       child proposed -30.0x-30.0
//   H2 frame(maxWidth: 80), proposal -30x-30: size 20.0x20.0
//       child proposed 20.0x20.0
//       child at (0.0, 0.0) size 20.0x20.0
//   RUN H3 frame(minWidth: -50) alone, proposal 100x100
//       child proposed 100.0x100.0
//   H3 frame(minWidth: -50) alone, proposal 100x100: size 20.0x20.0
//       child proposed 20.0x20.0
//       child at (0.0, 0.0) size 20.0x20.0
//   RUN H4 frame(minWidth: -50, maxWidth: 80), proposal -30x-30
//       child proposed 0.0x-30.0
//   H4 frame(minWidth: -50, maxWidth: 80), proposal -30x-30: size 0.0x20.0
//       child proposed 0.0x20.0
//       child at (0.0, 0.0) size 20.0x20.0
//       child at (-10.0, 0.0) size 20.0x20.0
//   RUN H5 frame(width: 60), proposal -30x-30
//       child proposed 60.0x-30.0
//   H5 frame(width: 60), proposal -30x-30: size 60.0x20.0
//       child at (0.0, 0.0) size 20.0x20.0
//       child at (20.0, 0.0) size 20.0x20.0
//   RUN H6 frame(minWidth: -50, maxWidth: -10), proposal 100x100
//       child proposed 0.0x100.0
//   H6 frame(minWidth: -50, maxWidth: -10), proposal 100x100: size 0.0x20.0
//       child proposed 0.0x20.0
//       child at (0.0, 0.0) size 20.0x20.0
//       child at (-10.0, 0.0) size 20.0x20.0
//   RUN H7 frame(maxWidth: 80), proposal 0x0
//       child proposed 0.0x0.0
//   H7 frame(maxWidth: 80), proposal 0x0: size 20.0x20.0
//       child proposed 20.0x20.0
//       child at (0.0, 0.0) size 20.0x20.0
//   RUN H8 frame(maxWidth: 80), proposal 10x10
//       child proposed 10.0x10.0
//   H8 frame(maxWidth: 80), proposal 10x10: size 20.0x20.0
//       child proposed 20.0x20.0
//       child at (0.0, 0.0) size 20.0x20.0
//   RUN H9 frame(minWidth: -50), proposal nil
//       child proposed nilxnil
//   H9 frame(minWidth: -50), proposal nil: size 20.0x20.0
//       child at (0.0, 0.0) size 20.0x20.0
//   RUN H10 frame(width: -60), proposal 100x100
//       child proposed 0.0x100.0
//   H10 frame(width: -60), proposal 100x100: size 0.0x20.0
//       child at (0.0, 0.0) size 20.0x20.0
//       child at (-10.0, 0.0) size 20.0x20.0
//   RUN H11 frame(minWidth: 5, maxWidth: 80), proposal 10x10
//       child proposed 10.0x10.0
//   H11 frame(minWidth: 5, maxWidth: 80), proposal 10x10: size 10.0x20.0
//       child proposed 10.0x20.0
//       child at (0.0, 0.0) size 20.0x20.0
//       child at (-5.0, 0.0) size 20.0x20.0
//   RUN H12 frame(minWidth: 5, maxWidth: 80), proposal 60x60
//       child proposed 60.0x60.0
//   H12 frame(minWidth: 5, maxWidth: 80), proposal 60x60: size 60.0x20.0
//       child proposed 60.0x20.0
//       child at (0.0, 0.0) size 20.0x20.0
//       child at (20.0, 0.0) size 20.0x20.0
//   RUN H13 frame(minWidth: 5, maxWidth: 80) with a 200x160 child, proposal 10x10
//       child proposed 10.0x10.0
//   H13 frame(minWidth: 5, maxWidth: 80) with a 200x160 child, proposal 10x10: size 10.0x160.0
//       child proposed 10.0x160.0
//       child at (0.0, 0.0) size 200.0x160.0
//       child at (-95.0, 0.0) size 200.0x160.0
//   RUN H14 frame(minWidth: 0, maxWidth: 80), proposal 10x10
//       child proposed 10.0x10.0
//   H14 frame(minWidth: 0, maxWidth: 80), proposal 10x10: size 10.0x20.0
//       child proposed 10.0x20.0
//       child at (0.0, 0.0) size 20.0x20.0
//       child at (-5.0, 0.0) size 20.0x20.0
//   RUN H15 frame(maxWidth: 80) with a 200x160 child, proposal 10x10
//       child proposed 10.0x10.0
//   H15 frame(maxWidth: 80) with a 200x160 child, proposal 10x10: size 80.0x160.0
//       child proposed 80.0x160.0
//       child at (0.0, 0.0) size 200.0x160.0
//       child at (-60.0, 0.0) size 200.0x160.0
//   RUN H16 frame(maxWidth: .infinity) with a 200x160 child, proposal 100x100
//       child proposed 100.0x100.0
//   H16 frame(maxWidth: .infinity) with a 200x160 child, proposal 100x100: size 200.0x160.0
//       child proposed 200.0x160.0
//       child at (0.0, 0.0) size 200.0x160.0
//   RUN H17 frame(maxWidth: .infinity, maxHeight: .infinity) with a 200x160 child, proposal 100x100
//       child proposed 100.0x100.0
//   H17 frame(maxWidth: .infinity, maxHeight: .infinity) with a 200x160 child, proposal 100x100: size 200.0x160.0
//       child proposed 200.0x160.0
//       child at (0.0, 0.0) size 200.0x160.0
//   DONE
//
// CROSS-CHECK, 2026-09-15: script form and compiled form diffed on the final
// file — `diff` EMPTY, 101 lines, exit 0 both ways. The compiled form ALSO
// printed exactly two SwiftUI diagnostics, on the two arms that declare a
// negative FRAME dimension:
//
//   RUN H6 frame(minWidth: -50, maxWidth: -10), proposal 100x100
//   [SwiftUI] Invalid frame dimension (negative or non-finite).
//   RUN H10 frame(width: -60), proposal 100x100
//   [SwiftUI] Invalid frame dimension (negative or non-finite).
//
// A negative MINIMUM (H3, H4, H9) is NOT diagnosed, and neither is a negative
// PROPOSAL (H1, H2, H4, H5). SwiftUI diagnoses a negative fixed size and a
// negative maximum; it tolerates the other two.
//
// WHAT THE ARMS SHOW
//
// 1. SwiftUI NEVER answers a negative size, at any input in this file. H2 = 20,
//    H4 = 0, H6 = 0, H10 = 0, H5 = 60. Every declared frame dimension is
//    floored at 0 before use: H10's fixed -60 answers 0; H6's max -10 answers
//    0 and proposes 0 to its child; H4's min -50 turns the -30 proposal into a
//    child proposal of 0.0 where H2, which declares no minimum, forwards
//    -30.0 unchanged. So the floor is applied to the DECLARED min/max, not to
//    the proposal.
// 2. An ABSENT minimum is not the same as `minWidth: 0` — this is the finding
//    that changes the kernel rule. With a maximum and a concrete proposal:
//      - no minimum      → the frame answers max(proposal, child's own answer)
//                          H2 (-30, child 20) = 20; H7 (0) = 20; H8 (10) = 20;
//                          H15 (10, child 200) = 80, i.e. 200 clamped by max;
//                          H16/H17 (100, child 200, max ∞) = 200, unclamped
//      - ANY minimum     → the frame answers the proposal, clamped
//                          H11 (min 5, proposal 10, child 20) = 10
//                          H14 (min 0, proposal 10, child 20) = 10
//                          H13 (min 5, proposal 10, child 200) = 10
//    H14 against H8 is the decisive pair: the SAME numbers, differing only in
//    whether a zero minimum is written, answer 10 and 20.
// 3. The main probe's D arms cannot see this, because each of them proposes
//    MORE than its child answers (D4 100/20, D5 30/20, D10 100/20). D5's 30 is
//    max(30, 20) either way.
// 4. The INFINITE maximum is the same rule, and MetalUI gets it wrong today.
//    H16 — `frame(maxWidth: .infinity)` over a 200x160 child at a 100x100
//    proposal — answers **200x160**, the child, not 100. H17 repeats it with
//    both maximums infinite: 200x160 again. `LayoutTree.framedSize`'s
//    `max == .infinity` branch returns `max(min ?? 0, proposal)` = 100, so the
//    live kernel and the demo's own preview spelling ride on a wrong answer
//    that D10-D12 (all 20pt children) could not see.
// 5. A leaf ignores a negative proposal: H1 answers 20x20, exactly as the
//    H-control does at 100x100. The negative never originates below the frame.
//
// THE COMPLETE RULE, main probe and this one together (71 arms):
//
//   lo = max(0, min)  hi = max(0, this axis's max)   // declared values only
//   childProposal = fixed ?? clamp(parentProposal ?? ideal, min == nil ? -inf : lo, hi)
//                          // nil when parentProposal and ideal are both nil
//   response = fixed ?? clamp(base, lo, hi), where base is
//        ideal                       when the proposal is nil and an ideal is given
//        proposal                    when a maximum is given, the proposal is
//                                    concrete, AND a minimum is given
//        max(proposal, child)        when a maximum is given, the proposal is
//                                    concrete, and NO minimum is given
//        the child's own answer      otherwise
//
// FR-L rules on the floor; FR-M rules on the absent minimum.

import AppKit
import SwiftUI

func fmt(_ s: CGSize) -> String { "\(s.width)x\(s.height)" }
func fmt(_ p: ProposedViewSize) -> String {
    func d(_ v: CGFloat?) -> String { v.map { "\($0)" } ?? "nil" }
    return "\(d(p.width))x\(d(p.height))"
}

/// Proposes `proposal` to the view under test and prints the size it answers.
struct Probe: Layout {
    let label: String
    let proposal: ProposedViewSize
    func sizeThatFits(proposal _: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let size = subviews[0].sizeThatFits(proposal)
        print("\(label): size \(fmt(size))"); fflush(stdout)
        return size
    }
    func placeSubviews(in _: CGRect, proposal _: ProposedViewSize, subviews: Subviews,
                       cache: inout ()) {
        // Placed at `.zero`, never at `bounds.origin`: the main probe recorded
        // that centring a finite child inside an infinite frame at
        // `bounds.origin` crashes SwiftUI on a NaN origin, and a negative
        // frame is the same hazard.
        subviews[0].place(at: .zero, anchor: .topLeading, proposal: proposal)
    }
}

/// Stands in for the view under test's child: answers a FIXED size whatever it
/// is proposed, and prints the proposal it received.
struct Reporter: Layout {
    let answer: CGSize
    func sizeThatFits(proposal: ProposedViewSize, subviews _: Subviews, cache: inout ()) -> CGSize {
        print("    child proposed \(fmt(proposal))"); fflush(stdout)
        return answer
    }
    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews,
                       cache: inout ()) {
        print("    child at (\(bounds.origin.x), \(bounds.origin.y)) size \(fmt(bounds.size))")
        fflush(stdout)
        subviews[0].place(at: bounds.origin, anchor: .topLeading,
                          proposal: ProposedViewSize(answer))
    }
}

@MainActor func run<V: View>(_ label: String, _ proposal: ProposedViewSize,
                             @ViewBuilder _ view: () -> V) {
    print("RUN \(label)"); fflush(stdout)
    let host = NSHostingView(rootView: Probe(label: label, proposal: proposal) { view() })
    host.frame = CGRect(x: 0, y: 0, width: 400, height: 400)
    host.layoutSubtreeIfNeeded()
}

/// A child that answers 20x20 to every proposal.
@MainActor func child20() -> some View { Reporter(answer: CGSize(width: 20, height: 20)) { SwiftUI.Color.red } }
/// A child that answers 200x160 to every proposal — bigger than every frame here.
@MainActor func childBig() -> some View { Reporter(answer: CGSize(width: 200, height: 160)) { SwiftUI.Color.blue } }

let p100 = ProposedViewSize(width: 100, height: 100)
let pNeg = ProposedViewSize(width: -30, height: -30)
let p0 = ProposedViewSize(width: 0, height: 0)
let p10 = ProposedViewSize(width: 10, height: 10)
let none = ProposedViewSize(width: nil, height: nil)
let p60 = ProposedViewSize(width: 60, height: 60)

@MainActor func probes() {
    // ---- H. Negative proposals and negative minimums. Two controls: the bare
    // child at a positive proposal, and the maximum arm at a positive proposal,
    // whose 80 must differ from every negative arm's answer below.
    run("H control bare child, proposal 100x100", p100) { child20() }
    run("H control2 frame(maxWidth: 80), proposal 100x100", p100) { child20().frame(maxWidth: 80) }

    run("H1 bare child, proposal -30x-30", pNeg) { child20() }
    run("H2 frame(maxWidth: 80), proposal -30x-30", pNeg) { child20().frame(maxWidth: 80) }
    run("H3 frame(minWidth: -50) alone, proposal 100x100", p100) { child20().frame(minWidth: -50) }
    run("H4 frame(minWidth: -50, maxWidth: 80), proposal -30x-30", pNeg) {
        child20().frame(minWidth: -50, maxWidth: 80)
    }
    run("H5 frame(width: 60), proposal -30x-30", pNeg) { child20().frame(width: 60) }
    run("H6 frame(minWidth: -50, maxWidth: -10), proposal 100x100", p100) {
        child20().frame(minWidth: -50, maxWidth: -10)
    }
    // H7/H8 separate "negative is special-cased" from "small is taken
    // greedily": H8's 10 is below the child's own 20, so a greedy frame must
    // answer 10 there. If H7 answers 0 and H2 answered the child's 20, the
    // negative is being discarded rather than floored.
    run("H7 frame(maxWidth: 80), proposal 0x0", p0) { child20().frame(maxWidth: 80) }
    run("H8 frame(maxWidth: 80), proposal 10x10", p10) { child20().frame(maxWidth: 80) }
    run("H9 frame(minWidth: -50), proposal nil", none) { child20().frame(minWidth: -50) }
    run("H10 frame(width: -60), proposal 100x100", p100) { child20().frame(width: -60) }
    // H11-H13 are ALL-POSITIVE and decide the ordinary rule, not the negative
    // edge: does a frame with a maximum answer the PROPOSAL when the proposal
    // is below the child's own answer, or the CHILD? H8 says the child with no
    // minimum; H11 asks the same with a minimum BELOW the child, where
    // "clamp(proposal, min, max)" and "clamp(max(proposal, child), min, max)"
    // disagree (10 against 20). H12 is H11 with a child the proposal exceeds,
    // the control that must read the proposal.
    run("H11 frame(minWidth: 5, maxWidth: 80), proposal 10x10", p10) {
        child20().frame(minWidth: 5, maxWidth: 80)
    }
    run("H12 frame(minWidth: 5, maxWidth: 80), proposal 60x60", p60) {
        child20().frame(minWidth: 5, maxWidth: 80)
    }
    run("H13 frame(minWidth: 5, maxWidth: 80) with a 200x160 child, proposal 10x10", p10) {
        childBig().frame(minWidth: 5, maxWidth: 80)
    }
    // H14 asks whether the H8-vs-H11 difference is the ABSENCE of a minimum or
    // its value: minWidth 0 is the weakest minimum that can be written, so if
    // it reads 10 like H11 rather than 20 like H8, the distinction is absence.
    run("H14 frame(minWidth: 0, maxWidth: 80), proposal 10x10", p10) {
        child20().frame(minWidth: 0, maxWidth: 80)
    }
    // H15: no minimum, proposal below a LARGE child. If the absent minimum is
    // the child's own answer, this clamps 200 to the 80 maximum.
    run("H15 frame(maxWidth: 80) with a 200x160 child, proposal 10x10", p10) {
        childBig().frame(maxWidth: 80)
    }
    // H16/H17 are the demo's own spelling — an INFINITE maximum, no minimum —
    // over a child BIGGER than the proposal. Under "base = proposal" the frame
    // answers 100; under "base = max(proposal, child)" it answers 200. The main
    // probe's D10/D11/D12 all use a 20pt child and cannot separate them, and
    // MetalUI's demo preview and `aNativeFrameWithInfiniteMaximumExpands...`
    // both ride on the answer.
    run("H16 frame(maxWidth: .infinity) with a 200x160 child, proposal 100x100", p100) {
        childBig().frame(maxWidth: .infinity)
    }
    run("H17 frame(maxWidth: .infinity, maxHeight: .infinity) with a 200x160 child, proposal 100x100", p100) {
        childBig().frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
MainActor.assumeIsolated { probes() }
print("DONE")
