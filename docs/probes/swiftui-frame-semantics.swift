// SwiftUI probe: what `.frame` actually does — the proposal it makes to its
// child, the size it answers, where it places a child that differs from it, and
// how two chained frames compose. Evidence for rulings FR-A…FR-? in
// docs/superpowers/2026-09-15-frame-sizing-decisions.md (plan task 4).
//
// It also re-measures the one finding record §09 left open and `SA-N` item 1
// carried to this task: whether a FINITE `maxWidth` frame grows toward a larger
// proposal. It does (arm D).
//
// HOW TO RUN. Two ways, and they do not observe the same things (ruling SA-O).
//
// 1. As a script, for the NUMBERS:
//
//      /usr/bin/swift docs/probes/swiftui-frame-semantics.swift
//
//    `/usr/bin/swift` is Apple's toolchain. The `swift` first on this machine's
//    PATH is swiftly's swift.org build, whose JIT fails on every SwiftUI symbol.
//
// 2. Compiled, for the numbers AND SwiftUI's os_log diagnostics:
//
//      swiftc docs/probes/swiftui-frame-semantics.swift -o /tmp/framesem
//      OS_ACTIVITY_DT_MODE=1 /tmp/framesem 2>&1 | grep -v 'Connection\]\|ntents'
//
// METHOD. Every figure is read from SwiftUI, never from documentation:
//
// - a `size` line is a `LayoutSubview.sizeThatFits` answer for the whole view
//   under test, taken by the `Probe` layout at a stated proposal;
// - a `child proposed` line is the `ProposedViewSize` SwiftUI handed to the
//   view under test's own child, printed by a `Reporter` layout standing in for
//   that child. `Reporter` answers a FIXED size whatever it is proposed, so a
//   frame that merely forwards its child's answer is distinguishable from one
//   that imposes its own;
// - a `child at` line is that child's placed rect **relative to the view under
//   test's own placed origin**, so an alignment offset is read directly.
//
// Every group opens with a positive control whose answer must DIFFER from the
// arm under test (practices shape 15). The controls are named "control" and the
// disagreement each one must show is stated in the source comment above it.
//
// RECORDED 2026-09-15 by the frame-and-sizing design session (plan task 4),
// macOS 26.6.2 (25G83). Toolchains as reported on this machine:
// `/usr/bin/swift` and `xcrun swiftc` = Apple Swift 6.4 (swiftlang-6.4.0.33.1);
// PATH `swiftc` (swiftly) = Apple Swift 6.3.3 (swift-6.3.3-RELEASE), used only
// for the cross-check noted below. One run's stdout, XPC noise removed.
//
//   RUN A control bare child, proposal nil
//       child proposed nilxnil
//   A control bare child, proposal nil: size 20.0x20.0
//       child at (0.0, 0.0) size 20.0x20.0
//   RUN A1 frame(width: 60), proposal nil
//       child proposed 60.0xnil
//   A1 frame(width: 60), proposal nil: size 60.0x20.0
//       child at (0.0, 0.0) size 20.0x20.0
//       child at (20.0, 0.0) size 20.0x20.0
//   RUN A2 frame(width: 60, height: 40), proposal 300x200
//   A2 frame(width: 60, height: 40), proposal 300x200: size 60.0x40.0
//       child proposed 60.0x40.0
//       child at (0.0, 0.0) size 20.0x20.0
//       child at (20.0, 10.0) size 20.0x20.0
//   RUN A3 frame(width: 60) only, proposal 300x200
//       child proposed 60.0x200.0
//   A3 frame(width: 60) only, proposal 300x200: size 60.0x20.0
//       child at (0.0, 0.0) size 20.0x20.0
//       child at (20.0, 0.0) size 20.0x20.0
//   RUN A4 frame(height: 40) only, proposal 300x200
//       child proposed 300.0x40.0
//   A4 frame(height: 40) only, proposal 300x200: size 20.0x40.0
//       child at (0.0, 0.0) size 20.0x20.0
//       child at (0.0, 10.0) size 20.0x20.0
//   RUN A5 frame(width: 60, height: 40) with a 200x160 child, proposal 300x200
//   A5 frame(width: 60, height: 40) with a 200x160 child, proposal 300x200: size 60.0x40.0
//       child proposed 60.0x40.0
//       child at (0.0, 0.0) size 200.0x160.0
//       child at (-70.0, -60.0) size 200.0x160.0
//   RUN A6 frame(width: 0, height: 0), proposal 300x200
//   A6 frame(width: 0, height: 0), proposal 300x200: size 0.0x0.0
//       child proposed 0.0x0.0
//       child at (0.0, 0.0) size 20.0x20.0
//       child at (-10.0, -10.0) size 20.0x20.0
//   RUN B control frame(60x40, .center)
//   B control frame(60x40, .center): size 60.0x40.0
//       child proposed 60.0x40.0
//       child at (0.0, 0.0) size 20.0x20.0
//       child at (20.0, 10.0) size 20.0x20.0
//   RUN B1 frame(60x40, .topLeading)
//   B1 frame(60x40, .topLeading): size 60.0x40.0
//       child proposed 60.0x40.0
//       child at (0.0, 0.0) size 20.0x20.0
//   RUN B2 frame(60x40, .top)
//   B2 frame(60x40, .top): size 60.0x40.0
//       child proposed 60.0x40.0
//       child at (0.0, 0.0) size 20.0x20.0
//       child at (20.0, 0.0) size 20.0x20.0
//   RUN B3 frame(60x40, .topTrailing)
//   B3 frame(60x40, .topTrailing): size 60.0x40.0
//       child proposed 60.0x40.0
//       child at (0.0, 0.0) size 20.0x20.0
//       child at (40.0, 0.0) size 20.0x20.0
//   RUN B4 frame(60x40, .leading)
//   B4 frame(60x40, .leading): size 60.0x40.0
//       child proposed 60.0x40.0
//       child at (0.0, 0.0) size 20.0x20.0
//       child at (0.0, 10.0) size 20.0x20.0
//   RUN B5 frame(60x40, .trailing)
//   B5 frame(60x40, .trailing): size 60.0x40.0
//       child proposed 60.0x40.0
//       child at (0.0, 0.0) size 20.0x20.0
//       child at (40.0, 10.0) size 20.0x20.0
//   RUN B6 frame(60x40, .bottomLeading)
//   B6 frame(60x40, .bottomLeading): size 60.0x40.0
//       child proposed 60.0x40.0
//       child at (0.0, 0.0) size 20.0x20.0
//       child at (0.0, 20.0) size 20.0x20.0
//   RUN B7 frame(60x40, .bottom)
//   B7 frame(60x40, .bottom): size 60.0x40.0
//       child proposed 60.0x40.0
//       child at (0.0, 0.0) size 20.0x20.0
//       child at (20.0, 20.0) size 20.0x20.0
//   RUN B8 frame(60x40, .bottomTrailing)
//   B8 frame(60x40, .bottomTrailing): size 60.0x40.0
//       child proposed 60.0x40.0
//       child at (0.0, 0.0) size 20.0x20.0
//       child at (40.0, 20.0) size 20.0x20.0
//   RUN B9 frame(60x40, .topLeading) with a 200x160 child
//   B9 frame(60x40, .topLeading) with a 200x160 child: size 60.0x40.0
//       child proposed 60.0x40.0
//       child at (0.0, 0.0) size 200.0x160.0
//   RUN C control frame(idealWidth: 80), proposal 300x200
//       child proposed 300.0x200.0
//   C control frame(idealWidth: 80), proposal 300x200: size 20.0x20.0
//       child proposed 20.0x20.0
//       child at (0.0, 0.0) size 20.0x20.0
//   RUN C1 frame(idealWidth: 80), proposal nil
//       child proposed 80.0xnil
//   C1 frame(idealWidth: 80), proposal nil: size 80.0x20.0
//       child at (0.0, 0.0) size 20.0x20.0
//       child at (30.0, 0.0) size 20.0x20.0
//   RUN C2 frame(idealWidth: 80, idealHeight: 50), proposal nil
//   C2 frame(idealWidth: 80, idealHeight: 50), proposal nil: size 80.0x50.0
//       child proposed 80.0x50.0
//       child at (0.0, 0.0) size 20.0x20.0
//       child at (30.0, 15.0) size 20.0x20.0
//   RUN C3 frame(idealWidth: 80) with a 200x160 child, proposal nil
//       child proposed 80.0xnil
//   C3 frame(idealWidth: 80) with a 200x160 child, proposal nil: size 80.0x160.0
//       child at (0.0, 0.0) size 200.0x160.0
//       child at (-60.0, 0.0) size 200.0x160.0
//   RUN C4 frame(minWidth: 40, idealWidth: 80, maxWidth: 120), proposal nil
//       child proposed 80.0xnil
//   C4 frame(minWidth: 40, idealWidth: 80, maxWidth: 120), proposal nil: size 80.0x20.0
//       child at (0.0, 0.0) size 20.0x20.0
//       child at (30.0, 0.0) size 20.0x20.0
//   RUN C5 frame(minWidth: 40, idealWidth: 80, maxWidth: 120), proposal 300x200
//       child proposed 120.0x200.0
//   C5 frame(minWidth: 40, idealWidth: 80, maxWidth: 120), proposal 300x200: size 120.0x20.0
//       child proposed 120.0x20.0
//       child at (0.0, 0.0) size 20.0x20.0
//       child at (50.0, 0.0) size 20.0x20.0
//   RUN D control frame(minWidth: 40, maxWidth: 80), proposal 100x100
//       child proposed 80.0x100.0
//   D control frame(minWidth: 40, maxWidth: 80), proposal 100x100: size 80.0x20.0
//       child proposed 80.0x20.0
//       child at (0.0, 0.0) size 20.0x20.0
//       child at (30.0, 0.0) size 20.0x20.0
//   RUN D1 frame(minWidth: 40, maxWidth: 80), proposal 60x60
//       child proposed 60.0x60.0
//   D1 frame(minWidth: 40, maxWidth: 80), proposal 60x60: size 60.0x20.0
//       child proposed 60.0x20.0
//       child at (0.0, 0.0) size 20.0x20.0
//       child at (20.0, 0.0) size 20.0x20.0
//   RUN D2 frame(minWidth: 40, maxWidth: 80), proposal 30x30
//       child proposed 40.0x30.0
//   D2 frame(minWidth: 40, maxWidth: 80), proposal 30x30: size 40.0x20.0
//       child proposed 40.0x20.0
//       child at (0.0, 0.0) size 20.0x20.0
//       child at (10.0, 0.0) size 20.0x20.0
//   RUN D3 frame(minWidth: 40, maxWidth: 80), proposal nil
//       child proposed nilxnil
//   D3 frame(minWidth: 40, maxWidth: 80), proposal nil: size 40.0x20.0
//       child proposed 40.0xnil
//       child at (0.0, 0.0) size 20.0x20.0
//       child at (10.0, 0.0) size 20.0x20.0
//   RUN D4 frame(maxWidth: 80) alone, proposal 100x100
//       child proposed 80.0x100.0
//   D4 frame(maxWidth: 80) alone, proposal 100x100: size 80.0x20.0
//       child proposed 80.0x20.0
//       child at (0.0, 0.0) size 20.0x20.0
//       child at (30.0, 0.0) size 20.0x20.0
//   RUN D5 frame(maxWidth: 80) alone, proposal 30x30
//       child proposed 30.0x30.0
//   D5 frame(maxWidth: 80) alone, proposal 30x30: size 30.0x20.0
//       child proposed 30.0x20.0
//       child at (0.0, 0.0) size 20.0x20.0
//       child at (5.0, 0.0) size 20.0x20.0
//   RUN D6 frame(maxWidth: 80) alone, proposal nil
//       child proposed nilxnil
//   D6 frame(maxWidth: 80) alone, proposal nil: size 20.0x20.0
//       child at (0.0, 0.0) size 20.0x20.0
//   RUN D7 frame(minWidth: 40) alone, proposal 100x100
//       child proposed 100.0x100.0
//   D7 frame(minWidth: 40) alone, proposal 100x100: size 40.0x20.0
//       child proposed 40.0x20.0
//       child at (0.0, 0.0) size 20.0x20.0
//       child at (10.0, 0.0) size 20.0x20.0
//   RUN D8 frame(minWidth: 40) alone, proposal 30x30
//       child proposed 40.0x30.0
//   D8 frame(minWidth: 40) alone, proposal 30x30: size 40.0x20.0
//       child proposed 40.0x20.0
//       child at (0.0, 0.0) size 20.0x20.0
//       child at (10.0, 0.0) size 20.0x20.0
//   RUN D9 frame(minWidth: 40) alone, proposal nil
//       child proposed nilxnil
//   D9 frame(minWidth: 40) alone, proposal nil: size 40.0x20.0
//       child proposed 40.0xnil
//       child at (0.0, 0.0) size 20.0x20.0
//       child at (10.0, 0.0) size 20.0x20.0
//   RUN D10 frame(maxWidth: .infinity), proposal 100x100
//       child proposed 100.0x100.0
//   D10 frame(maxWidth: .infinity), proposal 100x100: size 100.0x20.0
//       child proposed 100.0x20.0
//       child at (0.0, 0.0) size 20.0x20.0
//       child at (40.0, 0.0) size 20.0x20.0
//   RUN D11 frame(maxWidth: .infinity), proposal nil
//       child proposed nilxnil
//   D11 frame(maxWidth: .infinity), proposal nil: size 20.0x20.0
//       child at (0.0, 0.0) size 20.0x20.0
//   RUN D12 frame(maxWidth: .infinity), proposal infxinf
//       child proposed infxinf
//   D12 frame(maxWidth: .infinity), proposal infxinf: size infx20.0
//       child proposed infx20.0
//       child at (0.0, 0.0) size 20.0x20.0
//       child at (inf, 0.0) size 20.0x20.0
//   RUN D13 frame(minWidth: 40, maxWidth: 80) with a 200x160 child, proposal 100x100
//       child proposed 80.0x100.0
//   D13 frame(minWidth: 40, maxWidth: 80) with a 200x160 child, proposal 100x100: size 80.0x160.0
//       child proposed 80.0x160.0
//       child at (0.0, 0.0) size 200.0x160.0
//       child at (-60.0, 0.0) size 200.0x160.0
//   RUN D14 frame(maxWidth: 80) with a 200x160 child, proposal nil
//       child proposed nilxnil
//   D14 frame(maxWidth: 80) with a 200x160 child, proposal nil: size 80.0x160.0
//       child proposed 80.0xnil
//       child at (0.0, 0.0) size 200.0x160.0
//       child at (-60.0, 0.0) size 200.0x160.0
//   RUN D15 frame(minWidth: 400) alone, proposal 100x100
//       child proposed 400.0x100.0
//   D15 frame(minWidth: 400) alone, proposal 100x100: size 400.0x20.0
//       child proposed 400.0x20.0
//       child at (0.0, 0.0) size 20.0x20.0
//       child at (190.0, 0.0) size 20.0x20.0
//   RUN D16 frame(minHeight: 40, maxHeight: 80), proposal 100x100
//       child proposed 100.0x80.0
//   D16 frame(minHeight: 40, maxHeight: 80), proposal 100x100: size 20.0x80.0
//       child proposed 20.0x80.0
//       child at (0.0, 0.0) size 20.0x20.0
//       child at (0.0, 30.0) size 20.0x20.0
//   RUN D17 frame(minWidth: 40, maxWidth: 80, alignment: .topLeading), proposal 100x100
//       child proposed 80.0x100.0
//   D17 frame(minWidth: 40, maxWidth: 80, alignment: .topLeading), proposal 100x100: size 80.0x20.0
//       child proposed 80.0x20.0
//       child at (0.0, 0.0) size 20.0x20.0
//   RUN E control frame(width: 100), proposal 300x200
//       child proposed 100.0x200.0
//   E control frame(width: 100), proposal 300x200: size 100.0x20.0
//       child at (0.0, 0.0) size 20.0x20.0
//       child at (40.0, 0.0) size 20.0x20.0
//   RUN E1 frame(width: 100).frame(width: 50), proposal 300x200
//       child proposed 100.0x200.0
//   E1 frame(width: 100).frame(width: 50), proposal 300x200: size 50.0x20.0
//       child at (0.0, 0.0) size 20.0x20.0
//       child at (15.0, 0.0) size 20.0x20.0
//   RUN E2 frame(width: 50).frame(width: 100), proposal 300x200
//       child proposed 50.0x200.0
//   E2 frame(width: 50).frame(width: 100), proposal 300x200: size 100.0x20.0
//       child at (0.0, 0.0) size 20.0x20.0
//       child at (40.0, 0.0) size 20.0x20.0
//   RUN E3 frame(maxWidth: .infinity).frame(width: 50), proposal 300x200
//       child proposed 50.0x200.0
//   E3 frame(maxWidth: .infinity).frame(width: 50), proposal 300x200: size 50.0x20.0
//       child proposed 50.0x20.0
//       child at (0.0, 0.0) size 20.0x20.0
//       child at (15.0, 0.0) size 20.0x20.0
//   RUN E4 frame(width: 50).frame(maxWidth: .infinity), proposal 300x200
//       child proposed 50.0x200.0
//   E4 frame(width: 50).frame(maxWidth: .infinity), proposal 300x200: size 300.0x20.0
//       child proposed 50.0x20.0
//       child at (0.0, 0.0) size 20.0x20.0
//       child at (140.0, 0.0) size 20.0x20.0
//   RUN E5 frame(minWidth: 40).frame(minWidth: 80), proposal 300x200
//       child proposed 300.0x200.0
//   E5 frame(minWidth: 40).frame(minWidth: 80), proposal 300x200: size 80.0x20.0
//       child proposed 80.0x20.0
//       child proposed 40.0x20.0
//       child at (0.0, 0.0) size 20.0x20.0
//       child at (30.0, 0.0) size 20.0x20.0
//   RUN E6 frame(width: 60, height: 40).frame(width: 120, height: 100, alignment: .topLeading), proposal nil
//   E6 frame(width: 60, height: 40).frame(width: 120, height: 100, alignment: .topLeading), proposal nil: size 120.0x100.0
//       child proposed 60.0x40.0
//       child at (0.0, 0.0) size 20.0x20.0
//       child at (20.0, 10.0) size 20.0x20.0
//   RUN F control Text, proposal nil
//   F control Text, proposal nil: size 139.0x15.0
//   RUN F1 Text.frame(width: 60), proposal nil
//   F1 Text.frame(width: 60), proposal nil: size 60.0x60.0
//   RUN F2 Text.frame(maxWidth: 60), proposal nil
//   F2 Text.frame(maxWidth: 60), proposal nil: size 60.0x15.0
//   RUN F3 Text.frame(width: 60), proposal 300x200
//   F3 Text.frame(width: 60), proposal 300x200: size 60.0x60.0
//   RUN G control HStack of two 20pt children, proposal nil
//       child proposed nilxnil
//       child at (0.0, 0.0) size 20.0x20.0
//       child proposed nilxnil
//       child at (0.0, 0.0) size 20.0x20.0
//   G control HStack of two 20pt children, proposal nil: size 40.0x20.0
//       child proposed nilx20.0
//       child at (0.0, 0.0) size 20.0x20.0
//       child proposed nilx20.0
//       child at (0.0, 0.0) size 20.0x20.0
//       child at (20.0, 0.0) size 20.0x20.0
//   RUN G1 HStack.frame(width: 100), proposal nil
//       child proposed 0.0xnil
//       child proposed infxnil
//       child proposed 0.0xnil
//       child proposed infxnil
//       child proposed 50.0xnil
//       child at (0.0, 0.0) size 20.0x20.0
//       child proposed 80.0xnil
//       child at (0.0, 0.0) size 20.0x20.0
//   G1 HStack.frame(width: 100), proposal nil: size 100.0x20.0
//       child proposed 0.0x20.0
//       child proposed infx20.0
//       child proposed 0.0x20.0
//       child proposed infx20.0
//       child proposed 50.0x20.0
//       child at (0.0, 0.0) size 20.0x20.0
//       child proposed 80.0x20.0
//       child at (0.0, 0.0) size 20.0x20.0
//       child at (50.0, 0.0) size 20.0x20.0
//       child at (30.0, 0.0) size 20.0x20.0
//   DONE
//
// CROSS-CHECK, 2026-09-15: the script form (`/usr/bin/swift <file>`) and the
// compiled form (`xcrun swiftc <file>`, run with OS_ACTIVITY_DT_MODE=1) were
// diffed on the final file. `diff` is EMPTY — 295 lines, 54 arms, identical,
// both exiting 0 — and neither form printed a single SwiftUI diagnostic, which
// is expected: every input here is one SwiftUI accepts.
//
// WHAT THE ARMS SHOW, in one place (each claim's arms are named):
//
// - A fixed axis is PROPOSED to the child and becomes the frame's answer,
//   whatever the child answers (A1-A3, A5). An unspecified axis forwards the
//   parent's own proposal and adopts the child's answer (A3, A4).
// - A child bigger than the frame keeps its size and OVERFLOWS (A5, B9).
// - Alignment places the child inside the frame at the nine standard points
//   (B1-B8: offsets 0/20/40 horizontally, 0/10/20 vertically).
// - An ideal is used ONLY when that axis's proposal is nil (C control vs C1),
//   and it then beats the child's own answer (C3).
// - A flexible frame's ANSWER is: clamp(base, min, max), where base is the
//   PROPOSAL when a maximum is given (D control 80, D1 60, D2 40, D4 80,
//   D5 30, D10 100, D13 80), the IDEAL when the proposal is nil (C1, C4),
//   and otherwise the CHILD's answer (D6 20, D7 40, D8 40, D9 40, D14 80,
//   D15 400). Its CHILD PROPOSAL is clamp(proposal ?? ideal, min, max), or nil
//   when both are nil (D3, D6, D9).
// - Chained frames: the outer one's size wins and the inner one keeps its own,
//   overflowing (E1 reports 50 with the leaf at 15; E2 reports 100 with the
//   leaf at 40). A fixed frame inside a flexible one is proposed the fixed
//   value (E3), and a flexible frame outside a fixed one grows past it (E4).
// - A measured leaf re-wraps at a fixed frame's proposal (F1/F3 60x60 against
//   the control's 139x15) but NOT at a flexible maximum, which clamps the
//   reported width and leaves the text one line tall (F2 60x15).

import AppKit
import SwiftUI

nonisolated(unsafe) var outerOrigin = CGPoint.zero

func fmt(_ s: CGSize) -> String { "\(s.width)x\(s.height)" }
func fmt(_ p: ProposedViewSize) -> String {
    func d(_ v: CGFloat?) -> String { v.map { "\($0)" } ?? "nil" }
    return "\(d(p.width))x\(d(p.height))"
}
func fmt(_ p: CGPoint) -> String { "(\(p.x), \(p.y))" }

/// Proposes `proposal` to the view under test and prints the size it answers.
/// Records where it placed it, so `Reporter` can print a RELATIVE offset.
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
        // Placed at the origin, not at `bounds.origin`, so that every "child at"
        // line below is already relative to the view under test. SwiftUI runs
        // placement twice per host layout (the other probe's P7 notes the same);
        // with a fixed origin both passes print the same numbers.
        subviews[0].place(at: .zero, anchor: .topLeading, proposal: proposal)
    }
}

/// Stands in for the view under test's child. Answers `answer` whatever it is
/// proposed — so the frame's own contribution is separable from the child's —
/// and prints both the proposal it received and its placed rect, the latter
/// relative to the frame's placed origin.
struct Reporter: Layout {
    let answer: CGSize
    func sizeThatFits(proposal: ProposedViewSize, subviews _: Subviews, cache: inout ()) -> CGSize {
        print("    child proposed \(fmt(proposal))"); fflush(stdout)
        return answer
    }
    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews,
                       cache: inout ()) {
        let rel = CGPoint(x: bounds.origin.x - outerOrigin.x, y: bounds.origin.y - outerOrigin.y)
        print("    child at \(fmt(rel)) size \(fmt(bounds.size))"); fflush(stdout)
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
/// A child that answers 200x160 to every proposal — bigger than every frame below.
@MainActor func childBig() -> some View { Reporter(answer: CGSize(width: 200, height: 160)) { SwiftUI.Color.blue } }

let none = ProposedViewSize(width: nil, height: nil)
let p300 = ProposedViewSize(width: 300, height: 200)
let p100 = ProposedViewSize(width: 100, height: 100)
let p60 = ProposedViewSize(width: 60, height: 60)
let p30 = ProposedViewSize(width: 30, height: 30)
let pInf = ProposedViewSize(width: .infinity, height: .infinity)

@MainActor func probes() {
    // ---- A. A FIXED frame: what it proposes, what it answers, where it puts a
    // child of a different size. Control: the bare child, which must answer
    // 20x20 at a nil proposal and be proposed nil x nil — if the arms below
    // showed the same lines, the frame would be doing nothing.
    run("A control bare child, proposal nil", none) { child20() }
    run("A1 frame(width: 60), proposal nil", none) { child20().frame(width: 60) }
    run("A2 frame(width: 60, height: 40), proposal 300x200", p300) {
        child20().frame(width: 60, height: 40)
    }
    run("A3 frame(width: 60) only, proposal 300x200", p300) { child20().frame(width: 60) }
    run("A4 frame(height: 40) only, proposal 300x200", p300) { child20().frame(height: 40) }
    run("A5 frame(width: 60, height: 40) with a 200x160 child, proposal 300x200", p300) {
        childBig().frame(width: 60, height: 40)
    }
    run("A6 frame(width: 0, height: 0), proposal 300x200", p300) {
        child20().frame(width: 0, height: 0)
    }

    // ---- B. Alignment of a child SMALLER than the frame. Control: .center,
    // whose offset must differ from every edge arm's.
    run("B control frame(60x40, .center)", none) { child20().frame(width: 60, height: 40, alignment: .center) }
    run("B1 frame(60x40, .topLeading)", none) { child20().frame(width: 60, height: 40, alignment: .topLeading) }
    run("B2 frame(60x40, .top)", none) { child20().frame(width: 60, height: 40, alignment: .top) }
    run("B3 frame(60x40, .topTrailing)", none) { child20().frame(width: 60, height: 40, alignment: .topTrailing) }
    run("B4 frame(60x40, .leading)", none) { child20().frame(width: 60, height: 40, alignment: .leading) }
    run("B5 frame(60x40, .trailing)", none) { child20().frame(width: 60, height: 40, alignment: .trailing) }
    run("B6 frame(60x40, .bottomLeading)", none) { child20().frame(width: 60, height: 40, alignment: .bottomLeading) }
    run("B7 frame(60x40, .bottom)", none) { child20().frame(width: 60, height: 40, alignment: .bottom) }
    run("B8 frame(60x40, .bottomTrailing)", none) { child20().frame(width: 60, height: 40, alignment: .bottomTrailing) }
    run("B9 frame(60x40, .topLeading) with a 200x160 child", none) {
        childBig().frame(width: 60, height: 40, alignment: .topLeading)
    }

    // ---- C. IDEAL. Control: the same frame at a CONCRETE proposal, which must
    // NOT answer the ideal if the ideal is only for unspecified axes.
    run("C control frame(idealWidth: 80), proposal 300x200", p300) { child20().frame(idealWidth: 80) }
    run("C1 frame(idealWidth: 80), proposal nil", none) { child20().frame(idealWidth: 80) }
    run("C2 frame(idealWidth: 80, idealHeight: 50), proposal nil", none) {
        child20().frame(idealWidth: 80, idealHeight: 50)
    }
    run("C3 frame(idealWidth: 80) with a 200x160 child, proposal nil", none) {
        childBig().frame(idealWidth: 80)
    }
    run("C4 frame(minWidth: 40, idealWidth: 80, maxWidth: 120), proposal nil", none) {
        child20().frame(minWidth: 40, idealWidth: 80, maxWidth: 120)
    }
    run("C5 frame(minWidth: 40, idealWidth: 80, maxWidth: 120), proposal 300x200", p300) {
        child20().frame(minWidth: 40, idealWidth: 80, maxWidth: 120)
    }

    // ---- D. FLEXIBLE: finite versus infinite maximum, and minimum alone.
    // Control: min 40 / max 80 at proposal 100 on a 20pt child. SA-N item 1
    // recorded 80 here where MetalUI's kernel answers 40; every arm below is
    // read against it.
    run("D control frame(minWidth: 40, maxWidth: 80), proposal 100x100", p100) {
        child20().frame(minWidth: 40, maxWidth: 80)
    }
    run("D1 frame(minWidth: 40, maxWidth: 80), proposal 60x60", p60) {
        child20().frame(minWidth: 40, maxWidth: 80)
    }
    run("D2 frame(minWidth: 40, maxWidth: 80), proposal 30x30", p30) {
        child20().frame(minWidth: 40, maxWidth: 80)
    }
    run("D3 frame(minWidth: 40, maxWidth: 80), proposal nil", none) {
        child20().frame(minWidth: 40, maxWidth: 80)
    }
    run("D4 frame(maxWidth: 80) alone, proposal 100x100", p100) { child20().frame(maxWidth: 80) }
    run("D5 frame(maxWidth: 80) alone, proposal 30x30", p30) { child20().frame(maxWidth: 80) }
    run("D6 frame(maxWidth: 80) alone, proposal nil", none) { child20().frame(maxWidth: 80) }
    run("D7 frame(minWidth: 40) alone, proposal 100x100", p100) { child20().frame(minWidth: 40) }
    run("D8 frame(minWidth: 40) alone, proposal 30x30", p30) { child20().frame(minWidth: 40) }
    run("D9 frame(minWidth: 40) alone, proposal nil", none) { child20().frame(minWidth: 40) }
    run("D10 frame(maxWidth: .infinity), proposal 100x100", p100) { child20().frame(maxWidth: .infinity) }
    run("D11 frame(maxWidth: .infinity), proposal nil", none) { child20().frame(maxWidth: .infinity) }
    // D12's infinite proposal is answered with inf and the child is placed at
    // x = inf. An earlier pass of this harness placed the view under test at
    // `bounds.origin` instead of `.zero`; that form CRASHED SwiftUI here —
    // "SwiftUICore/Layout.swift:1535: Fatal error: view origin is invalid:
    // (nan, 190.0), UnitPoint(x: 0.0, y: 0.0), (20.0, 20.0)" — because centring
    // a 20pt child inside an infinite frame gives a NaN origin. Recorded
    // because MetalUI's kernel deliberately does NOT answer inf here.
    run("D12 frame(maxWidth: .infinity), proposal infxinf", pInf) { child20().frame(maxWidth: .infinity) }
    run("D13 frame(minWidth: 40, maxWidth: 80) with a 200x160 child, proposal 100x100", p100) {
        childBig().frame(minWidth: 40, maxWidth: 80)
    }
    run("D14 frame(maxWidth: 80) with a 200x160 child, proposal nil", none) {
        childBig().frame(maxWidth: 80)
    }
    run("D15 frame(minWidth: 400) alone, proposal 100x100", p100) { child20().frame(minWidth: 400) }
    run("D16 frame(minHeight: 40, maxHeight: 80), proposal 100x100", p100) {
        child20().frame(minHeight: 40, maxHeight: 80)
    }
    run("D17 frame(minWidth: 40, maxWidth: 80, alignment: .topLeading), proposal 100x100", p100) {
        child20().frame(minWidth: 40, maxWidth: 80, alignment: .topLeading)
    }

    // ---- E. CHAINED frames. Control: one frame alone, whose child proposal
    // must differ from the two-frame arms'.
    run("E control frame(width: 100), proposal 300x200", p300) { child20().frame(width: 100) }
    run("E1 frame(width: 100).frame(width: 50), proposal 300x200", p300) {
        child20().frame(width: 100).frame(width: 50)
    }
    run("E2 frame(width: 50).frame(width: 100), proposal 300x200", p300) {
        child20().frame(width: 50).frame(width: 100)
    }
    run("E3 frame(maxWidth: .infinity).frame(width: 50), proposal 300x200", p300) {
        child20().frame(maxWidth: .infinity).frame(width: 50)
    }
    run("E4 frame(width: 50).frame(maxWidth: .infinity), proposal 300x200", p300) {
        child20().frame(width: 50).frame(maxWidth: .infinity)
    }
    run("E5 frame(minWidth: 40).frame(minWidth: 80), proposal 300x200", p300) {
        child20().frame(minWidth: 40).frame(minWidth: 80)
    }
    run("E6 frame(width: 60, height: 40).frame(width: 120, height: 100, alignment: .topLeading), proposal nil", none) {
        child20().frame(width: 60, height: 40).frame(width: 120, height: 100, alignment: .topLeading)
    }

    // ---- F. A MEASURED leaf inside a fixed frame: does the frame's proposal
    // reach a leaf that re-measures? Control: the same text with no frame,
    // whose height must be one line where the framed arm's is more.
    run("F control Text, proposal nil", none) { Text("alpha bravo charlie delta").font(.system(size: 12)) }
    run("F1 Text.frame(width: 60), proposal nil", none) {
        Text("alpha bravo charlie delta").font(.system(size: 12)).frame(width: 60)
    }
    run("F2 Text.frame(maxWidth: 60), proposal nil", none) {
        Text("alpha bravo charlie delta").font(.system(size: 12)).frame(maxWidth: 60)
    }
    run("F3 Text.frame(width: 60), proposal 300x200", p300) {
        Text("alpha bravo charlie delta").font(.system(size: 12)).frame(width: 60)
    }

    // ---- G. A frame around a CONTAINER, to check the frame proposes to the
    // container the same way it proposes to a leaf. Control: the HStack alone.
    run("G control HStack of two 20pt children, proposal nil", none) {
        HStack(spacing: 0) { child20(); child20() }
    }
    run("G1 HStack.frame(width: 100), proposal nil", none) {
        HStack(spacing: 0) { child20(); child20() }.frame(width: 100)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
MainActor.assumeIsolated { probes() }
print("DONE")
