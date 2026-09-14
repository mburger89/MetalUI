// SwiftUI probe: which layout inputs SwiftUI accepts, diagnoses, repairs, traps
// or hangs on. Evidence for rulings SA-J (validation policy), SA-K (the
// relaxations and repairs that policy forces) and SA-N (carried kernel
// findings) in docs/superpowers/2026-09-14-swiftui-alignment-decisions.md.
//
// HOW TO RUN. Two ways, and they do not observe the same things (ruling SA-O).
//
// 1. As a script, for the NUMBERS:
//
//      /usr/bin/swift docs/probes/swiftui-layout-input-validation.swift
//
//    `/usr/bin/swift` is Apple's toolchain (Apple Swift 6.4, swiftlang-6.4.0.33.1,
//    Xcode-beta). Re-run 2026-09-14: exit 0, and every size and "placed" line is
//    identical to the compiled run below. It prints NO "diagnostic:" lines even
//    with OS_ACTIVITY_DT_MODE=1 set (0 of the 22 the compiled run shows).
//    The `swift` first on this machine's PATH is swiftly's swift.org 6.3.3,
//    whose JIT fails on every SwiftUI symbol: exit 255, "JIT session error:
//    Symbols not found: [ _$s7SwiftUI…".
//
// 2. Compiled, for the numbers AND SwiftUI's os_log diagnostics:
//
//      swiftc docs/probes/swiftui-layout-input-validation.swift -o /tmp/validation
//      OS_ACTIVITY_DT_MODE=1 /tmp/validation 2>&1 | grep -v 'Connection\]\|ntents'
//
//    OS_ACTIVITY_DT_MODE mirrors os_log to stderr; without it the run looks
//    silent. The recorded output below is this form, with each diagnostic's
//    timestamp/process prefix shortened to "diagnostic:".
//
// `--include-hang` adds P7's NaN priority, which never returns, and `--nan-padding`
// adds P2c's NaN padding, which traps inside SwiftUI (both recorded below).
//
// METHOD. Every figure is a `LayoutSubview.sizeThatFits` answer read by the
// `Probe` layout, or a placed rect read by `Recorder`/`Placed`; nothing is taken
// from documentation. Each group has a positive control ("control") whose answer
// must differ from the arm under test, or the arm proves nothing. P9's controls
// are the finite arms of P1-P8 named in its comment.
//
// RECORDED 2026-09-14 by the kernel-completion design session (second pass),
// macOS 26.6.2 (25G83), swiftc = Apple Swift 6.3.3 (swift-6.3.3-RELEASE), SDK
// Xcode-beta MacOSX.sdk. Exit status 0. One run's stdout+stderr, XPC
// connection/intents noise removed. A diagnostic line belongs to the RUN line
// above it. "placed" lines print twice per P7 arm, once before the probe's size
// line and once after it; why SwiftUI places twice was not investigated, and the
// two passes agree in every arm. Lines P1 through P7b are byte-identical to the
// header an earlier pass of this session recorded; P9, P2b, P2c and P4d were
// first run in this pass. `/usr/bin/swift <file>` was re-run on the final file
// and matched every non-diagnostic line.
//
//   RUN P1 control HStack(spacing: 10) {20;20}
//   P1 control HStack(spacing: 10) {20;20}: 50.0x20.0
//   RUN P1 HStack(spacing: -10) {20;20}
//   P1 HStack(spacing: -10) {20;20}: 30.0x20.0
//   RUN P1 VStack(spacing: -10) {20;20}
//   P1 VStack(spacing: -10) {20;20}: 20.0x30.0
//   RUN P1 HStack(spacing: -100) {20;20} (gaps exceed children)
//   P1 HStack(spacing: -100) {20;20} (gaps exceed children): -60.0x20.0
//   RUN P1 HStack(spacing: -100) {20;20} offered 50x20
//   P1 HStack(spacing: -100) {20;20} offered 50x20: -60.0x20.0
//   RUN P1 HStack(spacing: .nan) {20;20}
//   P1 HStack(spacing: .nan) {20;20}: nanx20.0
//   RUN P1 HStack(spacing: .infinity) {20;20}
//   P1 HStack(spacing: .infinity) {20;20}: infx20.0
//   RUN P2 control padding(5)
//   P2 control padding(5): 30.0x30.0
//   RUN P2 padding(-5)
//   P2 padding(-5): 10.0x10.0
//   RUN P2 padding(-15) (inset larger than half the child)
//   P2 padding(-15) (inset larger than half the child): 0.0x0.0
//   RUN P2 control Color.padding(60) offered 100x100 (child proposal would be -20)
//   P2 control Color.padding(60) offered 100x100 (child proposal would be -20): 120.0x120.0
//   RUN P2 padding(-5) offered 100x100
//   P2 padding(-5) offered 100x100: 100.0x100.0
//   RUN P2 padding(.nan)
//   P2 padding(.nan): 0.0x0.0
//   RUN P2 padding(.infinity)
//   P2 padding(.infinity): infxinf
//   RUN P3 control frame(width: 40)
//   P3 control frame(width: 40): 40.0x20.0
//   RUN P3 frame(width: -10)
//       diagnostic: [SwiftUI] Invalid frame dimension (negative or non-finite).
//   P3 frame(width: -10): 0.0x20.0
//   RUN P3 frame(width: .infinity)
//       diagnostic: [SwiftUI] Invalid frame dimension (negative or non-finite).
//   P3 frame(width: .infinity): 20.0x20.0
//   RUN P3 frame(width: .nan)
//       diagnostic: [SwiftUI] Invalid frame dimension (negative or non-finite).
//   P3 frame(width: .nan): 20.0x20.0
//   RUN P4 control frame(minWidth: 40, maxWidth: 80) offered 100
//   P4 control frame(minWidth: 40, maxWidth: 80) offered 100: 80.0x20.0
//   RUN P4 control frame(minWidth: 40, maxWidth: 80) offered nil
//   P4 control frame(minWidth: 40, maxWidth: 80) offered nil: 40.0x20.0
//   RUN P4 frame(minWidth: 80, maxWidth: 40) offered 100
//       diagnostic: [SwiftUI] Contradictory frame constraints specified.
//       diagnostic: [SwiftUI] Invalid frame dimension (negative or non-finite).
//   P4 frame(minWidth: 80, maxWidth: 40) offered 100: 80.0x20.0
//   RUN P4 frame(minWidth: 80, maxWidth: 40) offered nil
//       diagnostic: [SwiftUI] Contradictory frame constraints specified.
//       diagnostic: [SwiftUI] Invalid frame dimension (negative or non-finite).
//   P4 frame(minWidth: 80, maxWidth: 40) offered nil: 80.0x20.0
//   RUN P4 frame(minWidth: -10) offered nil
//   P4 frame(minWidth: -10) offered nil: 20.0x20.0
//   RUN P4 frame(maxWidth: -10) offered 100
//       diagnostic: [SwiftUI] Invalid frame dimension (negative or non-finite).
//   P4 frame(maxWidth: -10) offered 100: 0.0x20.0
//   RUN P4 frame(minWidth: .nan) offered 100
//       diagnostic: [SwiftUI] Contradictory frame constraints specified.
//       diagnostic: [SwiftUI] Invalid frame dimension (negative or non-finite).
//   P4 frame(minWidth: .nan) offered 100: nanx20.0
//   RUN P4 frame(maxWidth: .nan) offered 100
//       diagnostic: [SwiftUI] Contradictory frame constraints specified.
//       diagnostic: [SwiftUI] Invalid frame dimension (negative or non-finite).
//   P4 frame(maxWidth: .nan) offered 100: nanx20.0
//   RUN P5 control HStack(0){20; Spacer(minLength: 30); 20}
//   P5 control HStack(0){20; Spacer(minLength: 30); 20}: 70.0x20.0
//   RUN P5 HStack(0){20; Spacer(minLength: -30); 20}
//   P5 HStack(0){20; Spacer(minLength: -30); 20}: 10.0x20.0
//   RUN P5 HStack(0){20; Spacer(minLength: .nan); 20}
//   P5 HStack(0){20; Spacer(minLength: .nan); 20}: -infx20.0
//   RUN P5 HStack(0){20; Spacer(minLength: .infinity); 20}
//   P5 HStack(0){20; Spacer(minLength: .infinity); 20}: infx20.0
//   RUN P5 control HStack(0){20; Spacer(); 20} (nil minLength between two views)
//   P5 control HStack(0){20; Spacer(); 20} (nil minLength between two views): 48.0x20.0
//   RUN P4b control frame(idealWidth: 80) offered nil
//   P4b control frame(idealWidth: 80) offered nil: 80.0x20.0
//   RUN P4b frame(idealWidth: -10) offered nil
//       diagnostic: [SwiftUI] Invalid frame dimension (negative or non-finite).
//   P4b frame(idealWidth: -10) offered nil: 0.0x20.0
//   RUN P4b frame(idealWidth: .infinity) offered nil
//   P4b frame(idealWidth: .infinity) offered nil: infx20.0
//   RUN P4b frame(idealWidth: .nan) offered nil
//       diagnostic: [SwiftUI] Contradictory frame constraints specified.
//       diagnostic: [SwiftUI] Invalid frame dimension (negative or non-finite).
//   P4b frame(idealWidth: .nan) offered nil: nanx20.0
//   RUN P4b frame(minWidth: .infinity) offered nil
//       diagnostic: [SwiftUI] Invalid frame dimension (negative or non-finite).
//   P4b frame(minWidth: .infinity) offered nil: infx20.0
//   RUN P6 control Color offered 50x60
//   P6 control Color offered 50x60: 50.0x60.0
//   RUN P6 Color offered .infinity
//   P6 Color offered .infinity: infxinf
//   RUN P6 Rectangle offered .infinity
//   P6 Rectangle offered .infinity: infxinf
//   RUN P6 Color offered .zero
//   P6 Color offered .zero: 0.0x0.0
//   RUN P6 Color offered -10x-20
//   P6 Color offered -10x-20: -10.0x-20.0
//   RUN P6 Color offered NaN x 10
//   P6 Color offered NaN x 10: nanx10.0
//   RUN P6 Rectangle offered NaN x 10
//   P6 Rectangle offered NaN x 10: nanx10.0
//   RUN P7 control0 HStack(0){Flex80; Flex80} offered 100
//       placed first width 50.0
//       placed second width 50.0
//   P7 control0 HStack(0){Flex80; Flex80} offered 100: 100.0x10.0
//       placed second width 50.0
//       placed first width 50.0
//   RUN P7 control HStack(0){Flex80.priority(1); Flex80} offered 100
//       placed first width 80.0
//       placed second width 20.0
//   P7 control HStack(0){Flex80.priority(1); Flex80} offered 100: 100.0x10.0
//       placed second width 20.0
//       placed first width 80.0
//   RUN P7 HStack(0){Flex80.priority(.infinity); Flex80} offered 100
//       placed first width 80.0
//       placed second width 20.0
//   P7 HStack(0){Flex80.priority(.infinity); Flex80} offered 100: 100.0x10.0
//       placed second width 20.0
//       placed first width 80.0
//   RUN P7 HStack(0){Flex80.priority(-1); Flex80} offered 100
//       placed second width 80.0
//       placed first width 20.0
//   P7 HStack(0){Flex80.priority(-1); Flex80} offered 100: 100.0x10.0
//       placed second width 80.0
//       placed first width 20.0
//   RUN P8 control Color.aspectRatio(2, .fit) offered 100x80
//   P8 control Color.aspectRatio(2, .fit) offered 100x80: 100.0x50.0
//   RUN P8 Color.aspectRatio(0, .fit) offered 100 x nil
//   P8 Color.aspectRatio(0, .fit) offered 100 x nil: 0.0xinf
//   RUN P8 Color.aspectRatio(-2, .fit) offered 100 x nil
//   P8 Color.aspectRatio(-2, .fit) offered 100 x nil: 100.0x-50.0
//   RUN P8 control Color.aspectRatio(2, .fit) offered 100 x nil
//   P8 control Color.aspectRatio(2, .fit) offered 100 x nil: 100.0x50.0
//   RUN P8 Color.aspectRatio(0, .fit) offered 100x80
//   P8 Color.aspectRatio(0, .fit) offered 100x80: 0.0x80.0
//   RUN P8 Color.aspectRatio(-2, .fit) offered 100x80
//   P8 Color.aspectRatio(-2, .fit) offered 100x80: 100.0x-50.0
//   RUN P8 Color.aspectRatio(.nan, .fit) offered 100x80
//   P8 Color.aspectRatio(.nan, .fit) offered 100x80: nanxnan
//   RUN P8 Color.aspectRatio(.infinity, .fit) offered 100x80
//   P8 Color.aspectRatio(.infinity, .fit) offered 100x80: nanx0.0
//   RUN P8b control Color.aspectRatio(2, .fill) offered 100x80
//   P8b control Color.aspectRatio(2, .fill) offered 100x80: 160.0x80.0
//   RUN P8b Color.aspectRatio(-2, .fill) offered 100x80
//   P8b Color.aspectRatio(-2, .fill) offered 100x80: -160.0x80.0
//   RUN P8b Color.aspectRatio(-2, .fit) offered nil x 80
//   P8b Color.aspectRatio(-2, .fit) offered nil x 80: -160.0x80.0
//   RUN P8b control Color.aspectRatio(2, .fit) offered nil x nil
//   P8b control Color.aspectRatio(2, .fit) offered nil x nil: 10.0x10.0
//   RUN P8b Color.aspectRatio(-2, .fit) offered nil x nil
//   P8b Color.aspectRatio(-2, .fit) offered nil x nil: 10.0x10.0
//   RUN P4c frame(maxWidth: .infinity) offered 100
//   P4c frame(maxWidth: .infinity) offered 100: 100.0x20.0
//   RUN P4c frame(maxWidth: .infinity) offered nil
//   P4c frame(maxWidth: .infinity) offered nil: 20.0x20.0
//   RUN P4c frame(minWidth: 60, idealWidth: 40) offered nil (min > ideal)
//       diagnostic: [SwiftUI] Contradictory frame constraints specified.
//       diagnostic: [SwiftUI] Invalid frame dimension (negative or non-finite).
//   P4c frame(minWidth: 60, idealWidth: 40) offered nil (min > ideal): 60.0x20.0
//   RUN P4c frame(idealWidth: 100, maxWidth: 80) offered nil (ideal > max)
//       diagnostic: [SwiftUI] Contradictory frame constraints specified.
//       diagnostic: [SwiftUI] Invalid frame dimension (negative or non-finite).
//   P4c frame(idealWidth: 100, maxWidth: 80) offered nil (ideal > max): 100.0x20.0
//   RUN P7b HStack(0){Flex80.priority(-.infinity); Flex80} offered 100
//       placed second width 80.0
//       placed first width 20.0
//   P7b HStack(0){Flex80.priority(-.infinity); Flex80} offered 100: 100.0x10.0
//       placed second width 80.0
//       placed first width 20.0
//   RUN P9 HStack(spacing: -.infinity) {20;20}
//   P9 HStack(spacing: -.infinity) {20;20}: -infx20.0
//   RUN P9 padding(-.infinity)
//   P9 padding(-.infinity): 0.0x0.0
//   RUN P9 frame(width: -.infinity)
//       diagnostic: [SwiftUI] Invalid frame dimension (negative or non-finite).
//   P9 frame(width: -.infinity): 0.0x20.0
//   RUN P9 frame(minWidth: -.infinity) offered nil
//   P9 frame(minWidth: -.infinity) offered nil: 20.0x20.0
//   RUN P9 frame(maxWidth: -.infinity) offered 100
//       diagnostic: [SwiftUI] Invalid frame dimension (negative or non-finite).
//   P9 frame(maxWidth: -.infinity) offered 100: 0.0x20.0
//   RUN P9 HStack(0){20; Spacer(minLength: -.infinity); 20}
//   P9 HStack(0){20; Spacer(minLength: -.infinity); 20}: -infx20.0
//   RUN P9 Color.aspectRatio(-.infinity, .fit) offered 100x80
//   P9 Color.aspectRatio(-.infinity, .fit) offered 100x80: nanx-0.0
//   RUN P2b control padding(5) placement
//   P2b control padding(5) placement: 30.0x30.0
//       placed outer at (200.0, 200.0, 30.0, 30.0)
//       placed inner at (205.0, 205.0, 20.0, 20.0)
//   RUN P2b padding(-5) placement
//   P2b padding(-5) placement: 10.0x10.0
//       placed outer at (200.0, 200.0, 10.0, 10.0)
//       placed inner at (195.0, 195.0, 20.0, 20.0)
//   RUN P2b padding(-15) placement (response clamps)
//   P2b padding(-15) placement (response clamps): 0.0x0.0
//       placed outer at (200.0, 200.0, 0.0, 0.0)
//       placed inner at (185.0, 185.0, 20.0, 20.0)
//   RUN P2b padding(leading: -30, trailing: 5) on 20
//   P2b padding(leading: -30, trailing: 5) on 20: 0.0x20.0
//       placed outer at (200.0, 200.0, 0.0, 20.0)
//       placed inner at (170.0, 200.0, 20.0, 20.0)
//   RUN P2c padding(-.infinity) placement
//   P2c padding(-.infinity) placement: 0.0x0.0
//       placed outer at (200.0, 200.0, 0.0, 0.0)
//       placed inner at (-inf, -inf, 20.0, 20.0)
//   RUN P4d frame(idealWidth: .infinity) offered 100
//   P4d frame(idealWidth: .infinity) offered 100: 20.0x20.0
//
// P2c with --nan-padding, run separately in this pass: exit 133 (SIGTRAP), and
// the last lines are
//   RUN P2c padding(.nan) placement
//   P2c padding(.nan) placement: 0.0x0.0
//       placed outer at (200.0, 200.0, 0.0, 0.0)
//       placed inner at (nan, nan, 20.0, 20.0)
//   SwiftUICore/Layout.swift:1535: Fatal error: view origin is invalid: (nan, nan), UnitPoint(x: 0.0, y: 0.0), (20.0, 20.0)
//
// P7 with --include-hang, re-run in this pass: the last line printed is
// "RUN P7 HStack(0){Flex80.priority(.nan); Flex80} offered 100"; `ps` read
// 99.4% CPU at an elapsed 00:20, and the process was killed with no answer.
// (The earlier pass saw 100.0% at 01:00.)
//
// READING (what the rulings rely on):
// - Diagnosed by SwiftUI ("Invalid frame dimension", "Contradictory frame
//   constraints"): fixed width negative / +inf / -inf / NaN; maxWidth negative,
//   -inf or NaN; minWidth NaN or +inf; idealWidth negative or NaN;
//   minWidth > maxWidth; minWidth > idealWidth; idealWidth > maxWidth.
//   NOT diagnosed: minWidth -10 or -inf, idealWidth +inf, maxWidth +inf, any
//   spacing, padding, Spacer minLength, layoutPriority or aspectRatio value.
// - Accepted silently with a finite answer: negative spacing (30, and -60 when
//   the gaps exceed the children -- the answer goes NEGATIVE, unclamped);
//   negative padding (10; 0 at -15, where the unclamped sum is -10); negative
//   Spacer minLength (10); minWidth -inf (20); layoutPriority +inf and -inf
//   (they order like 1 and -1: P7 and P7b); padding(.nan) and padding(-.inf)
//   (0x0 -- finite only because the response clamps; P2c: the -inf child is
//   then placed at (-inf, -inf), and the NaN child at (nan, nan) TRAPS
//   SwiftUI with "view origin is invalid"); aspectRatio 0 on a 2-D proposal
//   (0x80); aspectRatio -2 on every proposal but nil x nil (100x-50 for .fit
//   at 100x80 and 100 x nil, -160x80 for .fill at 100x80 and for .fit at
//   nil x 80) -- which is `width / ratio <= height` choosing the width branch
//   for .fit and `>=` for .fill, and is NOT `width / height <= ratio` once the
//   ratio is negative; maxWidth +inf (100 at a 100 proposal, the child's 20 at
//   nil); idealWidth +inf under a CONCRETE proposal (P4d: the child's 20).
// - P2b, where negative padding PLACES its child: always at the padding's own
//   origin plus the leading/top inset (195 at -5, 185 at -15, 170 at leading
//   -30), and always at the CHILD's own size (20x20), never at the padding's
//   bounds minus its insets. The response clamp is PER AXIS: leading -30 /
//   trailing 5 on a 20pt child answers 0x20.
// - Accepted with a NON-FINITE answer: spacing NaN / +inf / -inf; padding
//   +inf; minWidth / maxWidth NaN; idealWidth +inf at nil (P4b); minWidth +inf;
//   Spacer minLength NaN (-inf) / +inf / -inf; aspectRatio 0 on (100, nil)
//   (0 x inf), NaN, +inf, -inf (nan x -0); any NaN proposal (Color / Rectangle
//   echo NaN); an +inf proposal to Color / Rectangle (inf x inf -- a legitimate
//   "maximum size" answer, not an error).
// - Hangs: layoutPriority NaN.
// - Frame and spacer semantics the MetalUI kernel does NOT match, out of this
//   design's scope and carried as SA-N: minWidth 40 / maxWidth 80 offered 100
//   answers 80 (the kernel answers 40); Spacer() between two views in
//   HStack(spacing: 0) is 48 wide, i.e. an 8pt default minimum (the kernel's
//   nil minLength is 0); aspectRatio(2 or -2, .fit) on a Color offered
//   nil x nil answers 10x10 for both (the kernel's intrinsic branch answers
//   10x5 for 2 and, by reading, -20x10 for -2); P2b's child-sized placement
//   (the kernel stores a padded child at bounds minus insets).
import AppKit
import SwiftUI

/// Proposes `proposal` to its single subview and records the size it answers.
/// Every probe runs through this, so every figure below is a SwiftUI
/// `LayoutSubview.sizeThatFits` answer, not a guess from documentation.
struct Probe: Layout {
    let label: String
    let proposal: ProposedViewSize
    func sizeThatFits(proposal _: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let size = subviews[0].sizeThatFits(proposal)
        results.append("\(label): \(fmt(size))"); print("\(label): \(fmt(size))"); fflush(stdout)
        return .zero
    }
    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews[0].place(at: bounds.origin, proposal: proposal)
    }
}

nonisolated(unsafe) var results: [String] = []
func fmt(_ s: CGSize) -> String { "\(s.width)x\(s.height)" }

@MainActor func run<V: View>(_ label: String, _ proposal: ProposedViewSize, @ViewBuilder _ view: () -> V) {
    print("RUN \(label)"); fflush(stdout)
    let host = NSHostingView(rootView: Probe(label: label, proposal: proposal) { view() })
    host.frame = CGRect(x: 0, y: 0, width: 400, height: 400)
    host.layoutSubtreeIfNeeded()
}

/// Records the width it is placed at, so a stack's per-child allocation is
/// visible rather than only the stack's total.
struct Recorder: Layout {
    let label: String
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        subviews[0].sizeThatFits(proposal)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        print("    placed \(label) width \(bounds.width)"); fflush(stdout)
        subviews[0].place(at: bounds.origin, proposal: proposal)
    }
}
/// Logs the full rect it is placed at, and places its subview at that rect's
/// origin with the same proposal.
struct Placed: Layout {
    let label: String
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        subviews[0].sizeThatFits(proposal)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        print("    placed \(label) at \(bounds)"); fflush(stdout)
        subviews[0].place(at: bounds.origin, proposal: proposal)
    }
}
struct Flex80: View {
    let label: String
    var body: some View { Recorder(label: label) { SwiftUI.Color.red.frame(idealWidth: 80, maxWidth: 80).frame(height: 10) } }
}

@MainActor func probes() {
    let fixed20 = ProposedViewSize(width: nil, height: nil)
    let square = { SwiftUI.Rectangle().frame(width: 20, height: 20) }

    // P1 negative stack spacing. Control: +10 -> 50 wide.
    run("P1 control HStack(spacing: 10) {20;20}", fixed20) { HStack(spacing: 10) { square(); square() } }
    run("P1 HStack(spacing: -10) {20;20}", fixed20) { HStack(spacing: -10) { square(); square() } }
    run("P1 VStack(spacing: -10) {20;20}", fixed20) { VStack(spacing: -10) { square(); square() } }
    run("P1 HStack(spacing: -100) {20;20} (gaps exceed children)", fixed20) { HStack(spacing: -100) { square(); square() } }
    run("P1 HStack(spacing: -100) {20;20} offered 50x20", ProposedViewSize(width: 50, height: 20)) { HStack(spacing: -100) { square(); square() } }
    run("P1 HStack(spacing: .nan) {20;20}", fixed20) { HStack(spacing: .nan) { square(); square() } }
    run("P1 HStack(spacing: .infinity) {20;20}", fixed20) { HStack(spacing: .infinity) { square(); square() } }
    // P2 negative padding. Control: +5 -> 30.
    run("P2 control padding(5)", fixed20) { square().padding(5) }
    run("P2 padding(-5)", fixed20) { square().padding(-5) }
    run("P2 padding(-15) (inset larger than half the child)", fixed20) { square().padding(-15) }
    run("P2 control Color.padding(60) offered 100x100 (child proposal would be -20)", ProposedViewSize(width: 100, height: 100)) { SwiftUI.Color.red.padding(60) }
    run("P2 padding(-5) offered 100x100", ProposedViewSize(width: 100, height: 100)) { SwiftUI.Color.red.padding(-5) }
    run("P2 padding(.nan)", fixed20) { square().padding(.nan) }
    run("P2 padding(.infinity)", fixed20) { square().padding(.infinity) }
    // P3 invalid fixed frame dimensions. Control: width 40.
    run("P3 control frame(width: 40)", fixed20) { square().frame(width: 40) }
    run("P3 frame(width: -10)", fixed20) { square().frame(width: -10) }
    run("P3 frame(width: .infinity)", fixed20) { square().frame(width: .infinity) }
    run("P3 frame(width: .nan)", fixed20) { square().frame(width: .nan) }
    // P4 flexible frame constraints. Control: min 40 max 80 on a 20pt child at 100 -> ?
    run("P4 control frame(minWidth: 40, maxWidth: 80) offered 100", ProposedViewSize(width: 100, height: 100)) { square().frame(minWidth: 40, maxWidth: 80) }
    run("P4 control frame(minWidth: 40, maxWidth: 80) offered nil", fixed20) { square().frame(minWidth: 40, maxWidth: 80) }
    run("P4 frame(minWidth: 80, maxWidth: 40) offered 100", ProposedViewSize(width: 100, height: 100)) { square().frame(minWidth: 80, maxWidth: 40) }
    run("P4 frame(minWidth: 80, maxWidth: 40) offered nil", fixed20) { square().frame(minWidth: 80, maxWidth: 40) }
    run("P4 frame(minWidth: -10) offered nil", fixed20) { square().frame(minWidth: -10) }
    run("P4 frame(maxWidth: -10) offered 100", ProposedViewSize(width: 100, height: 100)) { square().frame(maxWidth: -10) }
    run("P4 frame(minWidth: .nan) offered 100", ProposedViewSize(width: 100, height: 100)) { square().frame(minWidth: .nan) }
    run("P4 frame(maxWidth: .nan) offered 100", ProposedViewSize(width: 100, height: 100)) { square().frame(maxWidth: .nan) }
    // P5 Spacer minimum. Control: minLength 30 in an unconstrained HStack -> 70.
    run("P5 control HStack(0){20; Spacer(minLength: 30); 20}", fixed20) { HStack(spacing: 0) { square(); Spacer(minLength: 30); square() } }
    run("P5 HStack(0){20; Spacer(minLength: -30); 20}", fixed20) { HStack(spacing: 0) { square(); Spacer(minLength: -30); square() } }
    run("P5 HStack(0){20; Spacer(minLength: .nan); 20}", fixed20) { HStack(spacing: 0) { square(); Spacer(minLength: .nan); square() } }
    run("P5 HStack(0){20; Spacer(minLength: .infinity); 20}", fixed20) { HStack(spacing: 0) { square(); Spacer(minLength: .infinity); square() } }
    run("P5 control HStack(0){20; Spacer(); 20} (nil minLength between two views)", fixed20) { HStack(spacing: 0) { square(); Spacer(); square() } }
    // P4b ideal dimensions. Control: idealWidth 80 offered nil -> 80.
    run("P4b control frame(idealWidth: 80) offered nil", fixed20) { square().frame(idealWidth: 80) }
    run("P4b frame(idealWidth: -10) offered nil", fixed20) { square().frame(idealWidth: -10) }
    run("P4b frame(idealWidth: .infinity) offered nil", fixed20) { square().frame(idealWidth: .infinity) }
    run("P4b frame(idealWidth: .nan) offered nil", fixed20) { square().frame(idealWidth: .nan) }
    run("P4b frame(minWidth: .infinity) offered nil", fixed20) { square().frame(minWidth: .infinity) }
    // P6 proposal edge cases on shapes. Control: 50x60 -> 50x60.
    run("P6 control Color offered 50x60", ProposedViewSize(width: 50, height: 60)) { SwiftUI.Color.red }
    run("P6 Color offered .infinity", .infinity) { SwiftUI.Color.red }
    run("P6 Rectangle offered .infinity", .infinity) { SwiftUI.Rectangle() }
    run("P6 Color offered .zero", .zero) { SwiftUI.Color.red }
    run("P6 Color offered -10x-20", ProposedViewSize(width: -10, height: -20)) { SwiftUI.Color.red }
    run("P6 Color offered NaN x 10", ProposedViewSize(width: .nan, height: 10)) { SwiftUI.Color.red }
    run("P6 Rectangle offered NaN x 10", ProposedViewSize(width: .nan, height: 10)) { SwiftUI.Rectangle() }
    // P7 layout priority. Control: priority 1 on the first of two 80pt-ideal flexible children in 100 -> 180? (measured via stack width only)
    run("P7 control0 HStack(0){Flex80; Flex80} offered 100", ProposedViewSize(width: 100, height: 10)) { HStack(spacing: 0) { Flex80(label: "first"); Flex80(label: "second") } }
    run("P7 control HStack(0){Flex80.priority(1); Flex80} offered 100", ProposedViewSize(width: 100, height: 10)) { HStack(spacing: 0) { Flex80(label: "first").layoutPriority(1); Flex80(label: "second") } }
    run("P7 HStack(0){Flex80.priority(.infinity); Flex80} offered 100", ProposedViewSize(width: 100, height: 10)) { HStack(spacing: 0) { Flex80(label: "first").layoutPriority(.infinity); Flex80(label: "second") } }
    // P8 aspect ratio. Control: 2 fit offered 100x80 -> 100x50.
    run("P7 HStack(0){Flex80.priority(-1); Flex80} offered 100", ProposedViewSize(width: 100, height: 10)) { HStack(spacing: 0) { Flex80(label: "first").layoutPriority(-1); Flex80(label: "second") } }
    // P7 NaN: SwiftUI does not return. Opt in with `--include-hang`; the run
    // then spins at ~99% CPU inside NSHostingView layout and never prints.
    if CommandLine.arguments.contains("--include-hang") {
        run("P7 HStack(0){Flex80.priority(.nan); Flex80} offered 100", ProposedViewSize(width: 100, height: 10)) { HStack(spacing: 0) { Flex80(label: "first").layoutPriority(.nan); Flex80(label: "second") } }
    }
    run("P8 control Color.aspectRatio(2, .fit) offered 100x80", ProposedViewSize(width: 100, height: 80)) { SwiftUI.Color.red.aspectRatio(2, contentMode: .fit) }
    run("P8 Color.aspectRatio(0, .fit) offered 100 x nil", ProposedViewSize(width: 100, height: nil)) { SwiftUI.Color.red.aspectRatio(0, contentMode: .fit) }
    run("P8 Color.aspectRatio(-2, .fit) offered 100 x nil", ProposedViewSize(width: 100, height: nil)) { SwiftUI.Color.red.aspectRatio(-2, contentMode: .fit) }
    run("P8 control Color.aspectRatio(2, .fit) offered 100 x nil", ProposedViewSize(width: 100, height: nil)) { SwiftUI.Color.red.aspectRatio(2, contentMode: .fit) }
    run("P8 Color.aspectRatio(0, .fit) offered 100x80", ProposedViewSize(width: 100, height: 80)) { SwiftUI.Color.red.aspectRatio(0, contentMode: .fit) }
    run("P8 Color.aspectRatio(-2, .fit) offered 100x80", ProposedViewSize(width: 100, height: 80)) { SwiftUI.Color.red.aspectRatio(-2, contentMode: .fit) }
    run("P8 Color.aspectRatio(.nan, .fit) offered 100x80", ProposedViewSize(width: 100, height: 80)) { SwiftUI.Color.red.aspectRatio(.nan, contentMode: .fit) }
    run("P8 Color.aspectRatio(.infinity, .fit) offered 100x80", ProposedViewSize(width: 100, height: 80)) { SwiftUI.Color.red.aspectRatio(.infinity, contentMode: .fit) }
    // P8b negative ratio on the remaining branches. Control: 2 fill offered 100x80 -> 160x80.
    run("P8b control Color.aspectRatio(2, .fill) offered 100x80", ProposedViewSize(width: 100, height: 80)) { SwiftUI.Color.red.aspectRatio(2, contentMode: .fill) }
    run("P8b Color.aspectRatio(-2, .fill) offered 100x80", ProposedViewSize(width: 100, height: 80)) { SwiftUI.Color.red.aspectRatio(-2, contentMode: .fill) }
    run("P8b Color.aspectRatio(-2, .fit) offered nil x 80", ProposedViewSize(width: nil, height: 80)) { SwiftUI.Color.red.aspectRatio(-2, contentMode: .fit) }
    run("P8b control Color.aspectRatio(2, .fit) offered nil x nil", fixed20) { SwiftUI.Color.red.aspectRatio(2, contentMode: .fit) }
    run("P8b Color.aspectRatio(-2, .fit) offered nil x nil", fixed20) { SwiftUI.Color.red.aspectRatio(-2, contentMode: .fit) }
    // P4c the frame idioms and orderings P4 left out. Control: P4's min 40 / max 80.
    run("P4c frame(maxWidth: .infinity) offered 100", ProposedViewSize(width: 100, height: 100)) { square().frame(maxWidth: .infinity) }
    run("P4c frame(maxWidth: .infinity) offered nil", fixed20) { square().frame(maxWidth: .infinity) }
    run("P4c frame(minWidth: 60, idealWidth: 40) offered nil (min > ideal)", fixed20) { square().frame(minWidth: 60, idealWidth: 40) }
    run("P4c frame(idealWidth: 100, maxWidth: 80) offered nil (ideal > max)", fixed20) { square().frame(idealWidth: 100, maxWidth: 80) }
    // P7b the other infinite priority.
    run("P7b HStack(0){Flex80.priority(-.infinity); Flex80} offered 100", ProposedViewSize(width: 100, height: 10)) { HStack(spacing: 0) { Flex80(label: "first").layoutPriority(-.infinity); Flex80(label: "second") } }
    // P9 negative infinity, which P1-P8 left out. Controls: the finite arms above
    // (P1 spacing -10 -> 30, P2 padding -5 -> 10, P3 width 40, P4 minWidth -10
    // -> 20, P5 minLength -30 -> 10, P8 ratio -2).
    run("P9 HStack(spacing: -.infinity) {20;20}", fixed20) { HStack(spacing: -.infinity) { square(); square() } }
    run("P9 padding(-.infinity)", fixed20) { square().padding(-.infinity) }
    run("P9 frame(width: -.infinity)", fixed20) { square().frame(width: -.infinity) }
    run("P9 frame(minWidth: -.infinity) offered nil", fixed20) { square().frame(minWidth: -.infinity) }
    run("P9 frame(maxWidth: -.infinity) offered 100", ProposedViewSize(width: 100, height: 100)) { square().frame(maxWidth: -.infinity) }
    run("P9 HStack(0){20; Spacer(minLength: -.infinity); 20}", fixed20) { HStack(spacing: 0) { square(); Spacer(minLength: -.infinity); square() } }
    run("P9 Color.aspectRatio(-.infinity, .fit) offered 100x80", ProposedViewSize(width: 100, height: 80)) { SwiftUI.Color.red.aspectRatio(-.infinity, contentMode: .fit) }
    // P2b where negative padding PLACES its child, and whether the response
    // clamp is per axis. `Placed` logs the bounds each layer receives, so the
    // outer (padding's own) and inner (child's) rects print one above the other.
    // Control: padding(5).
    run("P2b control padding(5) placement", fixed20) { Placed(label: "outer") { Placed(label: "inner") { square() }.padding(5) } }
    run("P2b padding(-5) placement", fixed20) { Placed(label: "outer") { Placed(label: "inner") { square() }.padding(-5) } }
    run("P2b padding(-15) placement (response clamps)", fixed20) { Placed(label: "outer") { Placed(label: "inner") { square() }.padding(-15) } }
    run("P2b padding(leading: -30, trailing: 5) on 20", fixed20) { Placed(label: "outer") { Placed(label: "inner") { square() }.padding(EdgeInsets(top: 0, leading: -30, bottom: 0, trailing: 5)) } }
    // P2c where the two finite-answering non-finite paddings place their child.
    // Control: P2b's padding(-15) placement (185).
    // The NaN arm TRAPS inside SwiftUI (recorded below), so it runs only on
    // request, with `--nan-padding`, and ends the process.
    run("P2c padding(-.infinity) placement", fixed20) { Placed(label: "outer") { Placed(label: "inner") { square() }.padding(-.infinity) } }
    if CommandLine.arguments.contains("--nan-padding") {
        run("P2c padding(.nan) placement", fixed20) { Placed(label: "outer") { Placed(label: "inner") { square() }.padding(.nan) } }
    }
    // P4d an infinite ideal under a CONCRETE proposal. Control: P4b's nil arm (inf).
    run("P4d frame(idealWidth: .infinity) offered 100", ProposedViewSize(width: 100, height: 100)) { square().frame(idealWidth: .infinity) }

}

MainActor.assumeIsolated { probes() }
