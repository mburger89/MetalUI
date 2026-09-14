// SwiftUI probe: what SwiftUI's custom `Layout` protocol lets a container do
// with a subview proxy, and when SwiftUI re-asks a child for its size.
// Evidence for rulings SA-A (protocol shape), SA-C (measurement cannot place),
// SA-D (the proxy surface: priority and spacer-ness), SA-E (placement
// semantics), SA-H (invalidation contract), SA-J (validation policy) and SA-N
// (carried findings) in
// docs/superpowers/2026-09-14-swiftui-alignment-decisions.md.
//
// HOW TO RUN. Either form (ruling SA-O):
//
//   /usr/bin/swift docs/probes/swiftui-layout-protocol-contract.swift
//
// runs it as a script under Apple's toolchain (Apple Swift 6.4,
// swiftlang-6.4.0.33.1). Re-run 2026-09-14 (third pass): every line below up to
// "--- D" is identical, then arm D's trap prints a JIT stack dump (exit 133). The `swift` first on
// this machine's PATH is swiftly's swift.org 6.3.3, whose JIT fails: exit 255,
// "JIT session error: Symbols not found: [ _$s7SwiftUI…". Compiled:
//
//   swiftc docs/probes/swiftui-layout-protocol-contract.swift -o /tmp/contract
//   OS_ACTIVITY_DT_MODE=1 /tmp/contract 2>&1 | grep -v 'Connection\]\|ntents'
//
// The process is EXPECTED to die at arm D: exit status 133 (SIGTRAP) is the
// observation, not a broken probe. D therefore runs last. `--nan-place` runs
// arm M's NaN placement alone, because it traps too.
//
// `Counted` wraps `Color.clear` because an earlier build of this file wrapped
// `EmptyView()`, and then neither `Counted` nor the parent layout around it
// was ever asked for a size (zero calls in every arm). Why was not
// investigated; the content was changed rather than explained.
//
// RECORDED 2026-09-14 by the kernel-completion design session (third pass, in
// answer to a critic's review), macOS 26.6.2 (25G83), swiftc = Apple Swift
// 6.3.3 (swift-6.3.3-RELEASE), SDK Xcode-beta MacOSX.sdk. Exit status 133. One
// run's stdout+stderr with the XPC connection/intents noise removed; nothing
// else was printed, and no SwiftUI diagnostic preceded the trap. The script form
// (`/usr/bin/swift`) was re-run on this final file too, and every line through
// "--- D" is byte-identical (`diff` empty). Arms A through N reproduce the second
// pass's recorded lines exactly; the third pass ADDED J's run count and its
// J2 control, K2 (two anchors whose factors are asymmetric), L2 (priority under
// fifteen further modifiers) and L3 (priority inside containers):
//
//   --- A/B/C: caching within one pass
//   A same proposal twice inside one sizeThatFits: child calls += 1
//   B control, a different proposal: child calls += 1
//   C placement re-asks the proposal measurement already made: child calls += 0
//       Counted placed at (75.0, 75.0, 30.0, 10.0)
//       proposals seen by child: ["(50.0, 50.0)", "(70.0, 50.0)"]
//   --- F: a second layout pass at the SAME host size, forced
//   F same-size forced relayout: child calls += 0
//   --- G: a second layout pass at a DIFFERENT host size (control for F)
//   A same proposal twice inside one sizeThatFits: child calls += 0
//   B control, a different proposal: child calls += 0
//   C placement re-asks the proposal measurement already made: child calls += 0
//       Counted placed at (105.0, 65.0, 30.0, 10.0)
//   G resized relayout: child calls += 0
//   --- H: control for G, a resize that changes the child's proposal
//       Counted placed at (0.0, 75.0, 30.0, 10.0)
//       Counted placed at (0.0, 65.0, 30.0, 10.0)
//   H resized relayout: child calls += 1 (first pass made 1)
//   --- E: subview proxy surface
//   E subview 0: priority 2.5, zero (0.0, 0.0), unspecified (10.0, 10.0), infinity (inf, inf)
//   E subview 1: priority -inf, zero (12.0, 12.0), unspecified (12.0, 12.0), infinity (inf, inf)
//   E subview 2: priority 0.0, zero (12.0, 0.0), unspecified (12.0, 10.0), infinity (inf, inf)
//   --- E2: inside an HStack, a Spacer beside a Color given priority -infinity
//   E subview 0: priority -inf, zero (12.0, 12.0), unspecified (12.0, 12.0), infinity (inf, inf)
//   E subview 1: priority -inf, zero (0.0, 0.0), unspecified (10.0, 10.0), infinity (inf, inf)
//   --- I: a subview the parent never places
//   I parent bounds (50.0, 50.0, 100.0, 100.0); placing nothing
//       I child placed at (0.0, 0.0, 200.0, 200.0) proposal (200.0, 200.0)
//   --- I2: the same, hosted at 300x240, a fixed 30x30 child, and a parent offset inside a frame
//   I parent bounds (0.0, 0.0, 100.0, 100.0); placing nothing
//       I2 child placed at (0.0, 0.0, 30.0, 30.0) proposal (100.0, 100.0)
//   I parent bounds (120.0, 70.0, 100.0, 100.0); placing nothing
//       I2 child placed at (155.0, 105.0, 30.0, 30.0) proposal (100.0, 100.0)
//   --- J: a subview placed twice
//   J parent bounds (50.0, 50.0, 100.0, 100.0); placing at +10 (20x20) then +50 (40x40)
//       J child placed at (100.0, 100.0, 40.0, 40.0) proposal (40.0, 40.0)
//   J child placeSubviews ran 1 time(s) for two place calls
//   --- J2: control for J's count, a resize that moves the child (the counter can read more than 1)
//   J parent bounds (80.0, 40.0, 100.0, 100.0); placing at +10 (20x20) then +50 (40x40)
//       J child placed at (130.0, 90.0, 40.0, 40.0) proposal (40.0, 40.0)
//   J2 after a resize, J child placeSubviews ran 2 time(s) in total
//   --- K: placed size follows the placement proposal; anchor offsets by it
//   K parent bounds (25.0, 25.0, 150.0, 150.0)
//       K2 leading 30x20 at +100 placed at (125.0, 115.0, 30.0, 20.0) proposal (30.0, 20.0)
//       K2 topTrailing 30x20 at +100 placed at (95.0, 125.0, 30.0, 20.0) proposal (30.0, 20.0)
//       K bottomTrailing 30x20 at +100 placed at (95.0, 105.0, 30.0, 20.0) proposal (30.0, 20.0)
//       K center 30x20 at +100 placed at (110.0, 115.0, 30.0, 20.0) proposal (30.0, 20.0)
//       K topLeading 70x40 placed at (25.0, 25.0, 70.0, 40.0) proposal (70.0, 40.0)
//   --- L: does a layoutPriority survive an outer modifier? (control: E subview 0)
//   E subview 0: priority 0.0, zero (10.0, 0.0), unspecified (10.0, 10.0), infinity (10.0, inf)
//   E subview 1: priority 0.0, zero (6.0, 6.0), unspecified (16.0, 16.0), infinity (inf, inf)
//   E subview 2: priority 2.0, zero (6.0, 6.0), unspecified (16.0, 16.0), infinity (inf, inf)
//   --- L2: priority 2 under each further modifier (controls: L's frame/padding arms read 0, E subview 0 reads 2.5)
//   L2 control .layoutPriority(2) outermost: priority 2.0
//   L2 .overlay {}: priority 2.0
//   L2 .background {}: priority 2.0
//   L2 .opacity(0.5): priority 2.0
//   L2 .onTapGesture {}: priority 2.0
//   L2 .allowsHitTesting(false): priority 2.0
//   L2 .clipShape(Circle()): priority 2.0
//   L2 .border(.black): priority 2.0
//   L2 .aspectRatio(1, .fit): priority 0.0
//   L2 .fixedSize(): priority 0.0
//   L2 .offset(x: 5): priority 2.0
//   L2 .id(1): priority 2.0
//   L2 .frame(maxWidth: .infinity): priority 0.0
//   L2 .overlay {}.overlay {}: priority 2.0
//   L2 ZStack { .layoutPriority(2) }: priority 2.0
//   --- L3: priority 2 inside a CONTAINER (L2's single-child ZStack read 2; controls: L2's control reads 2, L's frame arm reads 0)
//   L3 ZStack { p2; p0 }: priority 0.0
//   L3 ZStack { p0; p2 }: priority 0.0
//   L3 ZStack { p2; p3 }: priority 0.0
//   L3 HStack { p2 }: priority 2.0
//   L3 HStack { p2; p0 }: priority 0.0
//   L3 VStack { p2 }: priority 2.0
//   L3 Where { p2 } (a custom single-child layout): priority 0.0
//   L3 ZStack { p2 }.frame(width: 10): priority 0.0
//       L3 Where placed at (0.0, 0.0, 200.0, 200.0) proposal (200.0, 200.0)
//   --- N: a child layout that answers a non-finite size (control: 30x10)
//   E subview 0: priority 0.0, zero (30.0, 10.0), unspecified (30.0, 10.0), infinity (30.0, 10.0)
//   E subview 1: priority 0.0, zero (inf, 10.0), unspecified (inf, 10.0), infinity (inf, 10.0)
//   E subview 2: priority 0.0, zero (nan, 10.0), unspecified (nan, 10.0), infinity (nan, 10.0)
//       Answer(nanx10.0) placed at (nan, 95.0, nan, 10.0)
//       Answer(infx10.0) placed at (-inf, 95.0, inf, 10.0)
//       Answer(30.0x10.0) placed at (85.0, 95.0, 30.0, 10.0)
//   --- M: placing a subview at a non-finite position (control: +10)
//       M control +10 placed at (60.0, 50.0, 20.0, 20.0) proposal (20.0, 20.0)
//       M x = +inf placed at (inf, 0.0, 20.0, 20.0) proposal (20.0, 20.0)
//   --- D: place during measurement
//
// `--nan-place`, run separately in the second pass and again in the third,
// compiled: exit 133, and the output is
//   --- M (NaN, run alone): placing a subview at x = NaN
//   SwiftUICore/Layout.swift:1535: Fatal error: view origin is invalid: (nan, 0.0), UnitPoint(x: 0.0, y: 0.0), (20.0, 20.0)
//
// READING (what the rulings rely on):
// - A, B, C: within one pass SwiftUI measures a child ONCE per distinct
//   proposal. Asking twice at (50, 50) costs one call; a different proposal
//   (70, 50) costs one more (the positive control); asking again from
//   placeSubviews costs nothing.
// - F, G, H: SwiftUI's memo also survives ACROSS passes. A forced same-size
//   relayout re-runs nothing (F). A resize re-runs the parent but not a child
//   whose proposals did not change (G: += 0). A resize that changes the
//   child's proposal re-measures it (H: += 1, the control for G).
// - D: `LayoutSubview.place` compiles inside `sizeThatFits` -- SwiftUI's
//   `Subviews` is one type for both requirements -- and TRAPS at run time
//   (SIGTRAP, no message). SwiftUI rejects placement during measurement; it
//   does so dynamically, not in the type system.
// - E, E2: a custom layout reads `priority` (2.5 comes back as 2.5). A
//   `Spacer` reads priority -inf, but so does any view given
//   `.layoutPriority(-.infinity)` (E2 subview 1), and outside a stack a Spacer
//   answers its minimum on BOTH axes (12 x 12). So spacer-ness is NOT
//   recoverable from SwiftUI's public proxy by priority: -inf is ambiguous.
//   Size probing is not a reliable test either, BY REASONING, NOT PROBED: the
//   Spacer's 12 x 12 at .zero is what any view framed with minWidth and
//   minHeight 12 would answer. (E subview 2, framed on width only, answers
//   12 x 0, so this particular pair does differ.)
// - L, L2: `priority` survives every modifier that does not lay its content
//   out, and is hidden by every one that does. HIDDEN (reads 0): `.frame`
//   (fixed and flexible), `.padding`, `.aspectRatio`, `.fixedSize`. SURVIVES
//   (reads 2): `.overlay {}` (also twice), `.background {}`, `.opacity`,
//   `.onTapGesture`, `.allowsHitTesting`, `.clipShape`, `.border`, `.offset`,
//   `.id`. The second pass probed only `.frame` and `.padding` and generalised
//   from them to "the outermost modifier's alone"; that was wrong for every
//   SURVIVES row. MetalUI's paint-only proposal modifiers (background, clip,
//   border, opacity, allowsHitTesting, onTap) register no node and so already
//   agree; `.overlay` registers an `overlayAttachment` node and did not.
// - L3: inside a container `priority` is 0 -- with ONE exception: a
//   single-child `ZStack`, `HStack` or `VStack` reads its child's 2 (L2's last
//   arm and L3's HStack/VStack arms), where a two-child stack reads 0 whichever
//   child carries it (even 2 and 3) and a single-child CUSTOM layout (`Where`)
//   reads 0. Why single-child built-in stacks pass it through was not
//   investigated. MetalUI's single-child stacks read 0 (ruling SA-N).
// - I, I2: a subview the parent never places is NOT an error. SwiftUI places
//   it centred in the PARENT's bounds, at its answer to the PARENT's own
//   proposal. I2 is the discriminating arm: parent (120, 70, 100, 100)
//   proposed 100x100, a fixed 30x30 child lands at (155, 105, 30, 30) --
//   centred on (170, 120), and neither the parent's origin (120, 70) nor the
//   root origin. I (parent (50, 50, 100, 100) proposed 200x200, a Color child
//   at (0, 0, 200, 200)) is CONSISTENT with centring but cannot tell it from a
//   placement at the root origin (0, 0), so no ruling cites it alone. I2's
//   first "parent bounds" line, at (0, 0, 100, 100), is a pass SwiftUI ran
//   before the frame placed the parent; its child line is at (0, 0, 30, 30),
//   which is not centred, and why was not investigated.
// - J, J2: a subview placed twice keeps the LAST placement: (100, 100, 40, 40),
//   the +50 position at the 40x40 proposal; the +10 placement is not seen by
//   the child at all -- its own `placeSubviews` ran ONCE for the two `place`
//   calls. J2 is the counter's positive control: a resize that moves the child
//   brings the total to 2, so the 1 is a count and not a counter stuck at 1.
// - K, K2: the placed size is the subview's answer to the PLACEMENT proposal
//   (a Color placed with 70x40 is 70x40), and the anchor offsets the position
//   by that size times the anchor's unit point: at (125, 125) with 30x20,
//   .center lands at (110, 115), .bottomTrailing at (95, 105), .topTrailing at
//   (95, 125) and .leading at (125, 115). K2's two anchors have unequal
//   horizontal and vertical factors, so a transposed factor pair moves them;
//   K's three cannot tell.
// - K ORDER: the children's own `placeSubviews` lines print AFTER the parent's
//   "K parent bounds" line and in REVERSE of the order the parent called
//   `place` (topLeading was placed first and logs last). An eager recursion
//   inside `place` would log in call order. So SwiftUI records each placement
//   and lays out the subtrees only after the parent's `placeSubviews` returns;
//   the reverse order itself is not a contract anything relies on.
// - N: SwiftUI accepts a child's NON-FINITE answer without a diagnostic. An
//   inf-wide answer is placed at (-inf, 95, inf, 10) and a NaN-wide one at
//   (nan, 95, nan, 10), by the probe's centring `Inspect` parent (which places
//   nothing, so these are I's unplaced-subview rule at work).
// - M: SwiftUI accepts an +inf placement position (the child is placed at
//   (inf, 0, 20, 20)) and TRAPS on a NaN one ("view origin is invalid").
import AppKit
import SwiftUI

nonisolated(unsafe) var measureCalls = 0
nonisolated(unsafe) var measuredProposals: [String] = []
func fmt(_ p: ProposedViewSize) -> String {
    "(\(p.width.map { "\($0)" } ?? "nil"), \(p.height.map { "\($0)" } ?? "nil"))"
}
func log(_ s: String) { print(s); fflush(stdout) }

/// A leaf-like layout that counts how many times SwiftUI asks it for a size.
struct Counted: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        measureCalls += 1
        measuredProposals.append(fmt(proposal))
        return CGSize(width: 30, height: 10)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        log("    Counted placed at \(bounds)")
    }
}

/// Parent whose measurement asks its child twice at one proposal (A), then at
/// a second proposal (B, the positive control), and whose placement asks again
/// at the first proposal (C).
struct AskTwice: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let before = measureCalls
        _ = subviews[0].sizeThatFits(ProposedViewSize(width: 50, height: 50))
        _ = subviews[0].sizeThatFits(ProposedViewSize(width: 50, height: 50))
        log("A same proposal twice inside one sizeThatFits: child calls += \(measureCalls - before)")
        let beforeB = measureCalls
        _ = subviews[0].sizeThatFits(ProposedViewSize(width: 70, height: 50))
        log("B control, a different proposal: child calls += \(measureCalls - beforeB)")
        return CGSize(width: 50, height: 50)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let before = measureCalls
        _ = subviews[0].sizeThatFits(ProposedViewSize(width: 50, height: 50))
        log("C placement re-asks the proposal measurement already made: child calls += \(measureCalls - before)")
        subviews[0].place(at: bounds.origin, proposal: ProposedViewSize(width: 50, height: 50))
    }
}

/// H: forwards its own proposal's width, so a host resize changes the child's
/// proposal. The control for G, whose child proposals do not depend on size.
struct ForwardWidth: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let size = subviews[0].sizeThatFits(ProposedViewSize(width: proposal.width, height: 50))
        return CGSize(width: proposal.width ?? size.width, height: 50)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews[0].place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: 50))
    }
}

/// D: `LayoutSubview.place` is callable from `sizeThatFits` (it compiles, and
/// SwiftUI's `Subviews` is the same type in both requirements). Does it take?
struct PlaceDuringMeasure: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        subviews[0].place(at: CGPoint(x: 77, y: 77), proposal: .unspecified)
        log("D place(at: 77,77) called inside sizeThatFits returned normally")
        return CGSize(width: 50, height: 50)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        log("D placeSubviews bounds \(bounds); placing child at origin + (5, 0)")
        subviews[0].place(at: CGPoint(x: bounds.minX + 5, y: bounds.minY), proposal: .unspecified)
    }
}

/// E: what a custom layout can read off a subview: priority, and whether a
/// Spacer is distinguishable from a flexible Color without private API.
struct Inspect: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        for (i, s) in subviews.enumerated() {
            log("E subview \(i): priority \(s.priority), zero \(s.sizeThatFits(.zero)), unspecified \(s.sizeThatFits(.unspecified)), infinity \(s.sizeThatFits(.infinity))")
        }
        return .zero
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {}
}

/// I/J/K: logs every placement it receives (bounds and proposal), so what a
/// parent's `placeSubviews` did to it is visible from the child's side.
nonisolated(unsafe) var placeRuns: [String: Int] = [:]
struct Where: Layout {
    let label: String
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        subviews[0].sizeThatFits(proposal)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        placeRuns[label, default: 0] += 1
        log("    \(label) placed at \(bounds) proposal \(fmt(proposal))")
        subviews[0].place(at: bounds.origin, proposal: proposal)
    }
}

/// I: a parent that never places its subview.
struct PlaceNone: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: 100, height: 100)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        log("I parent bounds \(bounds); placing nothing")
    }
}

/// J: a parent that places its subview twice, at two positions and proposals.
struct PlaceTwice: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: 100, height: 100)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        log("J parent bounds \(bounds); placing at +10 (20x20) then +50 (40x40)")
        subviews[0].place(at: CGPoint(x: bounds.minX + 10, y: bounds.minY + 10),
                          proposal: ProposedViewSize(width: 20, height: 20))
        subviews[0].place(at: CGPoint(x: bounds.minX + 50, y: bounds.minY + 50),
                          proposal: ProposedViewSize(width: 40, height: 40))
    }
}

/// K: the placed size is the subview's answer to the placement proposal, and
/// the anchor offsets the position by that size. Both children are
/// proposal-responsive `Color`s, so a placement that ignored the proposal
/// would show the parent's size instead.
struct PlaceWithProposal: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: 150, height: 150)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        log("K parent bounds \(bounds)")
        subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.minY), anchor: .topLeading,
                          proposal: ProposedViewSize(width: 70, height: 40))
        subviews[1].place(at: CGPoint(x: bounds.minX + 100, y: bounds.minY + 100), anchor: .center,
                          proposal: ProposedViewSize(width: 30, height: 20))
        subviews[2].place(at: CGPoint(x: bounds.minX + 100, y: bounds.minY + 100), anchor: .bottomTrailing,
                          proposal: ProposedViewSize(width: 30, height: 20))
        // K2: anchors whose horizontal and vertical factors DIFFER, so a
        // transposed h<->v factor pair moves the rect (the three above cannot).
        if subviews.count > 3 {
            subviews[3].place(at: CGPoint(x: bounds.minX + 100, y: bounds.minY + 100), anchor: .topTrailing,
                              proposal: ProposedViewSize(width: 30, height: 20))
            subviews[4].place(at: CGPoint(x: bounds.minX + 100, y: bounds.minY + 100), anchor: .leading,
                              proposal: ProposedViewSize(width: 30, height: 20))
        }
    }
}

/// L2: logs only each subview's `priority`, labelled, so a long list of
/// modifiers reads one line each.
struct Priorities: Layout {
    var prefix = "L2"
    let labels: [String]
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        for (i, s) in subviews.enumerated() { log("\(prefix) \(labels[i]): priority \(s.priority)") }
        return .zero
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {}
}

/// N: answers a fixed size, finite or not, whatever it is proposed.
struct Answer: Layout {
    let size: CGSize
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize { size }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        log("    Answer(\(size.width)x\(size.height)) placed at \(bounds)")
    }
}

/// M: places its one subview at a computed position, proposal 20x20.
struct PlaceAt: Layout {
    let point: @Sendable (CGRect) -> CGPoint
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: 100, height: 100)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews[0].place(at: point(bounds), proposal: ProposedViewSize(width: 20, height: 20))
    }
}

@MainActor func host<V: View>(_ view: V, size: CGSize = CGSize(width: 200, height: 200)) -> NSHostingView<V> {
    let h = NSHostingView(rootView: view)
    h.frame = CGRect(origin: .zero, size: size)
    h.layoutSubtreeIfNeeded()
    return h
}

@MainActor func probes() {
    // M's NaN arm traps ("view origin is invalid"), so it runs alone, on request.
    if CommandLine.arguments.contains("--nan-place") {
        log("--- M (NaN, run alone): placing a subview at x = NaN")
        _ = host(PlaceAt(point: { _ in CGPoint(x: CGFloat.nan, y: 0) }) { Where(label: "M x = NaN") { SwiftUI.Color.red } })
        log("M NaN host returned")
        return
    }
    log("--- A/B/C: caching within one pass")
    measureCalls = 0
    let h = host(AskTwice { Counted() { SwiftUI.Color.clear } })
    log("    proposals seen by child: \(measuredProposals)")

    log("--- F: a second layout pass at the SAME host size, forced")
    let beforeF = measureCalls
    h.needsLayout = true
    h.layoutSubtreeIfNeeded()
    log("F same-size forced relayout: child calls += \(measureCalls - beforeF)")

    log("--- G: a second layout pass at a DIFFERENT host size (control for F)")
    let beforeG = measureCalls
    h.frame = CGRect(x: 0, y: 0, width: 260, height: 180)
    h.layoutSubtreeIfNeeded()
    log("G resized relayout: child calls += \(measureCalls - beforeG)")

    log("--- H: control for G, a resize that changes the child's proposal")
    measureCalls = 0
    let hh = host(ForwardWidth { Counted() { SwiftUI.Color.clear } })
    let beforeH = measureCalls
    hh.frame = CGRect(x: 0, y: 0, width: 260, height: 180)
    hh.layoutSubtreeIfNeeded()
    log("H resized relayout: child calls += \(measureCalls - beforeH) (first pass made \(beforeH))")

    log("--- E: subview proxy surface")
    _ = host(Inspect {
        SwiftUI.Color.red.layoutPriority(2.5)
        Spacer(minLength: 12)
        SwiftUI.Color.blue.frame(minWidth: 12)
    })
    log("--- E2: inside an HStack, a Spacer beside a Color given priority -infinity")
    _ = host(HStack { Inspect { Spacer(minLength: 12); SwiftUI.Color.red.layoutPriority(-.infinity) } })

    log("--- I: a subview the parent never places")
    _ = host(PlaceNone { Where(label: "I child") { SwiftUI.Color.red } })
    log("--- I2: the same, hosted at 300x240, a fixed 30x30 child, and a parent offset inside a frame")
    _ = host(PlaceNone { Where(label: "I2 child") { SwiftUI.Color.red.frame(width: 30, height: 30) } }
                 .frame(width: 100, height: 100).padding(.leading, 40),
             size: CGSize(width: 300, height: 240))
    log("--- J: a subview placed twice")
    placeRuns = [:]
    let hj = host(PlaceTwice { Where(label: "J child") { SwiftUI.Color.red } })
    log("J child placeSubviews ran \(placeRuns["J child", default: 0]) time(s) for two place calls")
    log("--- J2: control for J's count, a resize that moves the child (the counter can read more than 1)")
    hj.frame = CGRect(x: 0, y: 0, width: 260, height: 180)
    hj.layoutSubtreeIfNeeded()
    log("J2 after a resize, J child placeSubviews ran \(placeRuns["J child", default: 0]) time(s) in total")
    log("--- K: placed size follows the placement proposal; anchor offsets by it")
    _ = host(PlaceWithProposal {
        Where(label: "K topLeading 70x40") { SwiftUI.Color.red }
        Where(label: "K center 30x20 at +100") { SwiftUI.Color.green }
        Where(label: "K bottomTrailing 30x20 at +100") { SwiftUI.Color.blue }
        Where(label: "K2 topTrailing 30x20 at +100") { SwiftUI.Color.yellow }
        Where(label: "K2 leading 30x20 at +100") { SwiftUI.Color.orange }
    })

    log("--- L: does a layoutPriority survive an outer modifier? (control: E subview 0)")
    _ = host(Inspect {
        SwiftUI.Color.red.layoutPriority(2).frame(width: 10)
        SwiftUI.Color.red.layoutPriority(2).padding(3)
        SwiftUI.Color.red.padding(3).layoutPriority(2)
    })

    log("--- L2: priority 2 under each further modifier (controls: L's frame/padding arms read 0, E subview 0 reads 2.5)")
    _ = host(Priorities(labels: ["control .layoutPriority(2) outermost", ".overlay {}", ".background {}", ".opacity(0.5)",
                                 ".onTapGesture {}", ".allowsHitTesting(false)", ".clipShape(Circle())",
                                 ".border(.black)", ".aspectRatio(1, .fit)", ".fixedSize()", ".offset(x: 5)",
                                 ".id(1)", ".frame(maxWidth: .infinity)", ".overlay {}.overlay {}",
                                 "ZStack { .layoutPriority(2) }"]) {
        SwiftUI.Color.red.layoutPriority(2)
        SwiftUI.Color.red.layoutPriority(2).overlay { SwiftUI.Color.blue }
        SwiftUI.Color.red.layoutPriority(2).background { SwiftUI.Color.blue }
        SwiftUI.Color.red.layoutPriority(2).opacity(0.5)
        SwiftUI.Color.red.layoutPriority(2).onTapGesture {}
        SwiftUI.Color.red.layoutPriority(2).allowsHitTesting(false)
        SwiftUI.Color.red.layoutPriority(2).clipShape(Circle())
        SwiftUI.Color.red.layoutPriority(2).border(.black)
        SwiftUI.Color.red.layoutPriority(2).aspectRatio(1, contentMode: .fit)
        SwiftUI.Color.red.layoutPriority(2).fixedSize()
        SwiftUI.Color.red.layoutPriority(2).offset(x: 5)
        SwiftUI.Color.red.layoutPriority(2).id(1)
        SwiftUI.Color.red.layoutPriority(2).frame(maxWidth: .infinity)
        SwiftUI.Color.red.layoutPriority(2).overlay { SwiftUI.Color.blue }.overlay { SwiftUI.Color.green }
        ZStack { SwiftUI.Color.red.layoutPriority(2) }
    })

    log("--- L3: priority 2 inside a CONTAINER (L2's single-child ZStack read 2; controls: L2's control reads 2, L's frame arm reads 0)")
    _ = host(Priorities(prefix: "L3", labels: ["ZStack { p2; p0 }", "ZStack { p0; p2 }", "ZStack { p2; p3 }", "HStack { p2 }",
                                 "HStack { p2; p0 }", "VStack { p2 }", "Where { p2 } (a custom single-child layout)",
                                 "ZStack { p2 }.frame(width: 10)"]) {
        ZStack { SwiftUI.Color.red.layoutPriority(2); SwiftUI.Color.blue }
        ZStack { SwiftUI.Color.blue; SwiftUI.Color.red.layoutPriority(2) }
        ZStack { SwiftUI.Color.red.layoutPriority(2); SwiftUI.Color.blue.layoutPriority(3) }
        HStack { SwiftUI.Color.red.layoutPriority(2) }
        HStack { SwiftUI.Color.red.layoutPriority(2); SwiftUI.Color.blue }
        VStack { SwiftUI.Color.red.layoutPriority(2) }
        Where(label: "L3 Where") { SwiftUI.Color.red.layoutPriority(2) }
        ZStack { SwiftUI.Color.red.layoutPriority(2) }.frame(width: 10)
    })

    log("--- N: a child layout that answers a non-finite size (control: 30x10)")
    _ = host(Inspect {
        Answer(size: CGSize(width: 30, height: 10)) { SwiftUI.Color.clear }
        Answer(size: CGSize(width: CGFloat.infinity, height: 10)) { SwiftUI.Color.clear }
        Answer(size: CGSize(width: CGFloat.nan, height: 10)) { SwiftUI.Color.clear }
    })

    log("--- M: placing a subview at a non-finite position (control: +10)")
    _ = host(PlaceAt(point: { b in CGPoint(x: b.minX + 10, y: b.minY) }) { Where(label: "M control +10") { SwiftUI.Color.red } })
    _ = host(PlaceAt(point: { _ in CGPoint(x: CGFloat.infinity, y: 0) }) { Where(label: "M x = +inf") { SwiftUI.Color.red } })

    // D runs last because it does not return (see the recorded output).
    // Its positive control is every arm above that places from
    // `placeSubviews` (I, J, K, M) and returns.
    log("--- D: place during measurement")
    _ = host(PlaceDuringMeasure { Counted() { SwiftUI.Color.clear } })
    log("D host returned")
}

MainActor.assumeIsolated { probes() }
