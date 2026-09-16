import Foundation
import Testing
import MetalUICore
@testable import MetalUILayout

// Lane 1 ("protocol") of `docs/superpowers/specs/2026-09-14-native-kernel-completion-design.md`.
// Rulings SA-A…SA-F in `docs/superpowers/2026-09-14-swiftui-alignment-decisions.md`.
// Every SwiftUI figure quoted below comes from
// `docs/probes/swiftui-layout-protocol-contract.swift`, whose header holds its
// recorded output.

// MARK: - Test layouts

/// A mutable box a `Sendable` layout value may carry into its calls.
private final class LayoutLog: @unchecked Sendable {
    var counts: [Int] = []
    var priorities: [Double] = []
    var spacers: [Bool] = []
    var placeRuns = 0
    var measureCalls = 0
}

private func fixedLeaf(_ tree: LayoutTree, _ width: Double, _ height: Double) -> LayoutNodeID {
    tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: width, height: height)) }
}

/// Answers its proposal, with an unspecified axis read as 0.
private func echoLeaf(_ tree: LayoutTree) -> LayoutNodeID {
    tree.newNativeLeaf { proposal in
        LayoutMeasurement(size: SizeD(width: proposal.width ?? 0, height: proposal.height ?? 0))
    }
}

/// Answers `min(ideal, proposal.width ?? ideal)` × `height`, or, transposed,
/// `height` × `min(ideal, proposal.height ?? ideal)`.
private func flexibleLeaf(_ tree: LayoutTree, ideal: Double, height: Double,
                          transposed: Bool = false) -> LayoutNodeID {
    tree.newNativeLeaf { proposal in
        transposed
            ? LayoutMeasurement(size: SizeD(width: height, height: Swift.min(ideal, proposal.height ?? ideal)))
            : LayoutMeasurement(size: SizeD(width: Swift.min(ideal, proposal.width ?? ideal), height: height))
    }
}

/// A layout driven by two closures, for tests whose layout is the fixture.
private struct ScriptedLayout: ProposalLayout {
    var measure: @Sendable (ProposedSize, MeasurementSubviews) -> LayoutMeasurement
    var place: @Sendable (LayoutRect, ProposedSize, PlacementSubviews) -> Void

    func sizeThatFits(proposal: ProposedSize, subviews: MeasurementSubviews) -> LayoutMeasurement {
        measure(proposal, subviews)
    }

    func placeSubviews(in bounds: LayoutRect, proposal: ProposedSize, subviews: PlacementSubviews) {
        place(bounds, proposal, subviews)
    }
}

// MARK: - Sufficiency: the reference stack

/// The reference tree, built once per stack kind so the two trees register
/// the same nodes in the same order.
///
/// - Root: a vertical stack, spacing 7, `.trailing`.
/// - Child A: a horizontal stack, spacing 3, `.bottom`, that overflows: flexible
///   leaves of ideal 80×9 (priority 1), 60×11 (priority 0) and 50×7 (priority
///   −1), then a fixed 20×13 leaf.
/// - Child B: a horizontal stack, spacing 5, centred: a 30×10 leaf,
///   `Spacer(minLength: 10)`, a 20×18 leaf, a spacer under `layoutPriority(2)`,
///   and an 11×8 leaf.
///
/// `transposed` swaps every axis — stack axes, leaf widths and heights,
/// alignments (`.bottom` ↔ `.trailing`) — so the same distribution runs
/// vertically (record §09's "horizontal only", closed by plan task 6 lane 1).
private struct ReferenceTree {
    var all: [LayoutNodeID] = []
    var root: LayoutNodeID
    var priorityZeroLeafOfA: LayoutNodeID
    var secondSpacerOfB: LayoutNodeID
    var lastLeafOfB: LayoutNodeID

    init(_ tree: LayoutTree, transposed: Bool = false,
         stack: (LayoutTree, [LayoutNodeID], ProposalStackAxis, Double, ProposalAlignment) -> LayoutNodeID) {
        var all: [LayoutNodeID] = []
        func keep(_ id: LayoutNodeID) -> LayoutNodeID { all.append(id); return id }
        func fixed(_ width: Double, _ height: Double) -> LayoutNodeID {
            transposed ? fixedLeaf(tree, height, width) : fixedLeaf(tree, width, height)
        }
        let inner: ProposalStackAxis = transposed ? .vertical : .horizontal
        let outer: ProposalStackAxis = transposed ? .horizontal : .vertical

        let a80 = keep(flexibleLeaf(tree, ideal: 80, height: 9, transposed: transposed))
        let a80p = keep(tree.newNativeLayoutPriority(child: a80, priority: 1))
        let a60 = keep(flexibleLeaf(tree, ideal: 60, height: 11, transposed: transposed))
        let a50 = keep(flexibleLeaf(tree, ideal: 50, height: 7, transposed: transposed))
        let a50p = keep(tree.newNativeLayoutPriority(child: a50, priority: -1))
        let a20 = keep(fixed(20, 13))
        let a = keep(stack(tree, [a80p, a60, a50p, a20], inner, 3, transposed ? .trailing : .bottom))

        let b30 = keep(fixed(30, 10))
        let bSpacer = keep(tree.newNativeSpacer(minLength: 10))
        let b20 = keep(fixed(20, 18))
        let bInnerSpacer = keep(tree.newNativeSpacer())
        let bSpacer2 = keep(tree.newNativeLayoutPriority(child: bInnerSpacer, priority: 2))
        let b11 = keep(fixed(11, 8))
        let b = keep(stack(tree, [b30, bSpacer, b20, bSpacer2, b11], inner, 5, .center))

        root = keep(stack(tree, [a, b], outer, 7, transposed ? .bottom : .trailing))
        priorityZeroLeafOfA = a60
        secondSpacerOfB = bSpacer2
        lastLeafOfB = b11
        self.all = all
    }
}

private let referenceProposal = ProposedSize(width: 157, height: 91)
private let referenceBounds = LayoutRect(x: 13, y: 17, width: 157, height: 91)

private func builtInStack(_ tree: LayoutTree, _ children: [LayoutNodeID], _ axis: ProposalStackAxis,
                          _ spacing: Double, _ alignment: ProposalAlignment) -> LayoutNodeID {
    tree.newNativeLinearStack(children: children, axis: axis, spacing: spacing, alignment: alignment)
}

private struct LaidOut {
    var measurement: LayoutMeasurement
    var rects: [LayoutRect]
    var widths: [Double]
    var tree: LayoutTree
    var ids: ReferenceTree
}

private func layOutReference(
    transposed: Bool = false,
    _ stack: (LayoutTree, [LayoutNodeID], ProposalStackAxis, Double, ProposalAlignment) -> LayoutNodeID
) -> LaidOut {
    let tree = LayoutTree(generation: 0)
    let ids = ReferenceTree(tree, transposed: transposed, stack: stack)
    let proposal = transposed ? ProposedSize(width: 91, height: 157) : referenceProposal
    let bounds = transposed ? LayoutRect(x: 17, y: 13, width: 91, height: 157) : referenceBounds
    let measurement = tree.computeNativeLayout(root: ids.root, proposal: proposal, in: bounds)
    return LaidOut(measurement: measurement, rects: ids.all.map(tree.layout),
                   widths: ids.all.map(tree.measuredWidth), tree: tree, ids: ids)
}

/// **Sufficiency of the protocol (ruling SA-B, SA-D, CN-B):** a
/// `ProposalLayout` written with a plain import (`ReferenceLinearStack.swift`)
/// reproduces the built-in linear stack's every stored rect and measured width
/// on a tree that reaches priority groups, reserved minimums, flexibility
/// order, spacers and cross-axis alignment — horizontally AND, transposed,
/// vertically.
///
/// The literal rects were re-derived by hand for ruling CN-B before the run
/// (plan task 6, lane 1; the unnamed spacer has minimum 0 until lane 2's CN-C):
/// - Root (V) at 157×91: A and B are one priority group, probed at
///   (157, ∞) and (157, 0). A is 13 tall at both (flexibility 0); B's spacers
///   claim the cross proposal (lane 2 zeroes it), so B answers ∞ and 18
///   (flexibility ∞). A is served first at (91 − 7) / 2 = 42 → 13; B at 71 →
///   71. **The root measures 157×91.** A at (13, 17, 157, 13), B at
///   (13, 37, 157, 71).
/// - A (H, 157 − 9 = 148): priority 1 is offered 148 minus the lower
///   minimums (a60 0, a50 0, a20 20) = 128 and a80 answers 80; 68 remain.
///   Priority 0 reserves a50's 0 and serves a20 (flexibility 0) at 34 → 20,
///   then a60 at 48 → 48. Priority −1 gets 0. Cursor 13 + 80 + 3 = 96, so
///   **A's priority-0 leaf is (96, 17 + 13 − 11, 48, 11) = (96, 19, 48, 11)**.
/// - B (H, 157 − 20 = 137, cross 71): priority 2 is offered 137 minus the
///   others' minimums (30 + 10 + 20 + 11 = 71) = 66, and its spacer answers 66;
///   71 remain. Priority 0 reserves the min-10 spacer's 10 and serves b30,
///   b20, b11 (all flexibility 0) at 20.3 → 30, 15.5 → 20, 11 → 11. The
///   min-10 spacer gets the last 10. Cursor 13 → 48 → 63 → 88, so **B's second
///   spacer is (88, 37, 66, 71)**; cursor 88 + 66 + 5 = 159, so **B's last leaf
///   is (159, 37 + (71 − 8) / 2, 11, 8) = (159, 68.5, 11, 8), stored rounded
///   as (159, 69, 11, 8)** (`roundLayout` rounds each edge half away from zero:
///   68.5 → 69, 76.5 → 77).
///
/// Shape 15: a priority-blind and an order-blind (no flexibility sort)
/// reference must each DISAGREE with the built-in on both trees.
@Test func aCustomLayoutReimplementingTheLinearStackMatchesTheBuiltInRects() throws {
    let builtIn = layOutReference(builtInStack)
    #expect(builtIn.measurement == LayoutMeasurement(size: SizeD(width: 157, height: 91)))
    #expect(builtIn.tree.layout(builtIn.ids.priorityZeroLeafOfA) == LayoutRect(x: 96, y: 19, width: 48, height: 11))
    #expect(builtIn.tree.layout(builtIn.ids.secondSpacerOfB) == LayoutRect(x: 88, y: 37, width: 66, height: 71))
    #expect(builtIn.tree.layout(builtIn.ids.lastLeafOfB) == LayoutRect(x: 159, y: 69, width: 11, height: 8))

    for transposed in [false, true] {
        let builtIn = layOutReference(transposed: transposed, builtInStack)
        let custom = layOutReference(transposed: transposed) { tree, children, axis, spacing, alignment in
            tree.newNativeLayout(ReferenceLinearStack(axis: axis, spacing: spacing, alignment: alignment),
                                 children: children)
        }
        try #require(builtIn.rects.count == custom.rects.count)
        #expect(custom.measurement == builtIn.measurement, "transposed \(transposed)")
        for index in builtIn.rects.indices {
            #expect(custom.rects[index] == builtIn.rects[index], "node \(index), transposed \(transposed)")
            #expect(custom.widths[index] == builtIn.widths[index],
                    "measured width of node \(index), transposed \(transposed)")
        }

        let priorityBlind = layOutReference(transposed: transposed) { tree, children, axis, spacing, alignment in
            tree.newNativeLayout(PriorityBlindLinearStack(axis: axis, spacing: spacing, alignment: alignment),
                                 children: children)
        }
        let orderBlind = layOutReference(transposed: transposed) { tree, children, axis, spacing, alignment in
            tree.newNativeLayout(OrderBlindLinearStack(axis: axis, spacing: spacing, alignment: alignment),
                                 children: children)
        }
        try #require(priorityBlind.rects != builtIn.rects,
                     "a priority-blind stack must change the reference tree's rects (transposed \(transposed))")
        try #require(orderBlind.rects != builtIn.rects,
                     "an order-blind stack must change the reference tree's rects (transposed \(transposed))")
    }
}

// MARK: - Measurement through the run's cache

/// Within one layout call a subview's measurement body runs once per distinct
/// proposal, whether asked from `sizeThatFits` or `placeSubviews` (ruling SA-H
/// clause 2; probe arms A/B/C).
///
/// The root is offered 100×80, so an unplaced child would be measured at a
/// third proposal; the layout places child 0 at 50×50, as probe A/B/C's
/// parent does, so the kernel's post-`placeSubviews` measurement is a hit.
@Test func aSubviewMeasuresOncePerDistinctProposalWithinOneRun() {
    let tree = LayoutTree(generation: 0)
    let calls = LayoutLog()
    let log = LayoutLog()
    let child = tree.newNativeLeaf { proposal in
        calls.measureCalls += 1
        return LayoutMeasurement(size: SizeD(width: proposal.width ?? 0, height: proposal.height ?? 0))
    }
    let layout = ScriptedLayout(
        measure: { _, subviews in
            _ = subviews[0].sizeThatFits(ProposedSize(width: 50, height: 50))
            log.counts.append(calls.measureCalls)
            _ = subviews[0].sizeThatFits(ProposedSize(width: 50, height: 50))
            log.counts.append(calls.measureCalls)
            _ = subviews[0].sizeThatFits(ProposedSize(width: 70, height: 50))
            log.counts.append(calls.measureCalls)
            return LayoutMeasurement(size: SizeD(width: 100, height: 80))
        },
        place: { bounds, _, subviews in
            _ = subviews[0].sizeThatFits(ProposedSize(width: 50, height: 50))
            log.counts.append(calls.measureCalls)
            subviews[0].place(at: Point(x: bounds.x, y: bounds.y),
                              proposal: ProposedSize(width: 50, height: 50))
        })
    let root = tree.newNativeLayout(layout, children: [child])

    _ = tree.computeNativeLayout(root: root, proposal: ProposedSize(width: 100, height: 80),
                                 in: LayoutRect(x: 0, y: 0, width: 100, height: 80))

    #expect(log.counts == [1, 1, 2, 2])
    #expect(calls.measureCalls == 2)
}

// MARK: - Placement

/// `place(at:anchor:proposal:)` stores the subview at its answer to the
/// placement's proposal, offset from the position by the anchor's factors
/// times that size (ruling SA-E; probes K and K2).
///
/// Parent bounds (25, 25, 150, 150); every child answers its proposal.
/// - child 0 at (25, 25), topLeading, 70×40 → (25, 25, 70, 40);
/// - children 1…4 at (125, 125), 30×20: center → (125 − 15, 125 − 10) =
///   (110, 115); bottomTrailing → (95, 105); **topTrailing** → (95, 125);
///   **leading** → (125, 115).
/// Only the last two have unequal factors per axis, so only they can see a
/// transposed factor pair.
@Test func placingASubviewUsesItsAnswerToThePlacementProposalAndTheAnchor() {
    let tree = LayoutTree(generation: 0)
    let children = (0..<5).map { _ in echoLeaf(tree) }
    let layout = ScriptedLayout(
        measure: { proposal, _ in
            LayoutMeasurement(size: SizeD(width: proposal.width ?? 0, height: proposal.height ?? 0))
        },
        place: { bounds, _, subviews in
            let corner = Point(x: bounds.x + 100, y: bounds.y + 100)
            let small = ProposedSize(width: 30, height: 20)
            subviews[0].place(at: Point(x: bounds.x, y: bounds.y), anchor: .topLeading,
                              proposal: ProposedSize(width: 70, height: 40))
            subviews[1].place(at: corner, anchor: .center, proposal: small)
            subviews[2].place(at: corner, anchor: .bottomTrailing, proposal: small)
            subviews[3].place(at: corner, anchor: .topTrailing, proposal: small)
            subviews[4].place(at: corner, anchor: .leading, proposal: small)
        })
    let root = tree.newNativeLayout(layout, children: children)

    _ = tree.computeNativeLayout(root: root, proposal: ProposedSize(width: 150, height: 150),
                                 in: LayoutRect(x: 25, y: 25, width: 150, height: 150))

    #expect(tree.layout(children[0]) == LayoutRect(x: 25, y: 25, width: 70, height: 40))
    #expect(tree.layout(children[1]) == LayoutRect(x: 110, y: 115, width: 30, height: 20))
    #expect(tree.layout(children[2]) == LayoutRect(x: 95, y: 105, width: 30, height: 20))
    #expect(tree.layout(children[3]) == LayoutRect(x: 95, y: 125, width: 30, height: 20))
    #expect(tree.layout(children[4]) == LayoutRect(x: 125, y: 115, width: 30, height: 20))
}

/// A subview `placeSubviews` never places is measured at the parent's proposal
/// and centred in the parent's bounds (ruling SA-E; probe arm I2).
///
/// Bounds (120, 70, 100, 100), proposal 100×100: a fixed 30×30 child lands at
/// (120 + 35, 70 + 35) = (155, 105); a proposal-echoing child answers 100×100
/// and lands on the bounds. Arm I is not used: its (0, 0, 200, 200) cannot tell
/// centring from a placement at the root origin.
@Test func anUnplacedSubviewIsCentredInItsParentAtTheParentsProposal() {
    let tree = LayoutTree(generation: 0)
    let fixed = fixedLeaf(tree, 30, 30)
    let echo = echoLeaf(tree)
    let layout = ScriptedLayout(
        measure: { _, _ in LayoutMeasurement(size: SizeD(width: 100, height: 100)) },
        place: { _, _, _ in })
    let root = tree.newNativeLayout(layout, children: [fixed, echo])

    _ = tree.computeNativeLayout(root: root, proposal: ProposedSize(width: 100, height: 100),
                                 in: LayoutRect(x: 120, y: 70, width: 100, height: 100))

    #expect(tree.layout(fixed) == LayoutRect(x: 155, y: 105, width: 30, height: 30))
    #expect(tree.layout(echo) == LayoutRect(x: 120, y: 70, width: 100, height: 100))
}

/// Placed twice, a subview keeps its LAST placement: position and proposal
/// (ruling SA-E; probe arm J, which lands at (100, 100, 40, 40)).
@Test func aSubviewPlacedTwiceKeepsItsLastPlacement() {
    let tree = LayoutTree(generation: 0)
    let child = echoLeaf(tree)
    let layout = ScriptedLayout(
        measure: { _, _ in LayoutMeasurement(size: SizeD(width: 100, height: 100)) },
        place: { _, _, subviews in
            subviews[0].place(at: Point(x: 60, y: 60), proposal: ProposedSize(width: 20, height: 20))
            subviews[0].place(at: Point(x: 100, y: 100), proposal: ProposedSize(width: 40, height: 40))
        })
    let root = tree.newNativeLayout(layout, children: [child])

    _ = tree.computeNativeLayout(root: root, proposal: ProposedSize(width: 100, height: 100),
                                 in: LayoutRect(x: 50, y: 50, width: 100, height: 100))

    #expect(tree.layout(child) == LayoutRect(x: 100, y: 100, width: 40, height: 40))
}

/// Placed twice, a subview's own subtree is placed ONCE, after the parent's
/// `placeSubviews` returns (ruling SA-E; probe J counts the child's
/// `placeSubviews` runs as 1 for two `place` calls, and J2 is that counter's
/// control). An eager `place` would run the child's `placeSubviews` twice.
@Test func aSubviewPlacedTwicePlacesItsSubtreeOnce() {
    let tree = LayoutTree(generation: 0)
    let log = LayoutLog()
    let grandchild = fixedLeaf(tree, 10, 10)
    let counting = ScriptedLayout(
        measure: { _, _ in LayoutMeasurement(size: SizeD(width: 40, height: 40)) },
        place: { _, _, _ in log.placeRuns += 1 })
    let child = tree.newNativeLayout(counting, children: [grandchild])
    let parent = ScriptedLayout(
        measure: { _, _ in LayoutMeasurement(size: SizeD(width: 100, height: 100)) },
        place: { _, _, subviews in
            subviews[0].place(at: Point(x: 60, y: 60), proposal: ProposedSize(width: 20, height: 20))
            subviews[0].place(at: Point(x: 100, y: 100), proposal: ProposedSize(width: 40, height: 40))
        })
    let root = tree.newNativeLayout(parent, children: [child])

    _ = tree.computeNativeLayout(root: root, proposal: ProposedSize(width: 100, height: 100),
                                 in: LayoutRect(x: 50, y: 50, width: 100, height: 100))

    #expect(log.placeRuns == 1)
}

// MARK: - The proxy surface

/// A proxy reads `priority` and `isSpacer` by the built-in stack's own rules
/// (rulings SA-D, CN-C, CN-D; probes L, L2, L3 and contract probe E).
///
/// | child | priority | isSpacer | why |
/// |---|---|---|---|
/// | `layoutPriority(2.5)` | 2.5 | false | probe E / L control |
/// | `frame` over `layoutPriority(2)` | 0 | false | probe L: a laying-out wrapper hides it |
/// | one overlay attachment over `layoutPriority(2)` | 2 | false | probe L2 |
/// | two overlay attachments over `layoutPriority(2)` | 2 | false | probe L2 |
/// | a one-child linear stack over `layoutPriority(2)` | 2 | false | probe L3 (CN-D; was pinned 0 until plan task 6) |
/// | `layoutPriority(1)` over `layoutPriority(3)` over a spacer | 1 | true | the outer value; spacer under any depth of priority |
/// | `frame` over a spacer | 0 | false | a frame hides the spacer's −∞ (K2d) and its spacer-ness |
/// | overlay attachment over a spacer | −∞ | false | the attachment passes the primary's priority (X8); `isNativeSpacer` does not look through it |
/// | a plain leaf | 0 | false | |
/// | a bare spacer | −∞ | true | contract probe E |
@Test func aCustomLayoutReadsPriorityAndSpacernessWithTheBuiltInStacksRules() {
    let tree = LayoutTree(generation: 0)
    let log = LayoutLog()
    let children = [
        tree.newNativeLayoutPriority(child: fixedLeaf(tree, 1, 1), priority: 2.5),
        tree.newNativeFrame(child: tree.newNativeLayoutPriority(child: fixedLeaf(tree, 1, 1), priority: 2),
                            width: 5),
        tree.newNativeOverlayAttachment(
            child: tree.newNativeLayoutPriority(child: fixedLeaf(tree, 1, 1), priority: 2),
            overlay: fixedLeaf(tree, 1, 1)),
        tree.newNativeOverlayAttachment(
            child: tree.newNativeOverlayAttachment(
                child: tree.newNativeLayoutPriority(child: fixedLeaf(tree, 1, 1), priority: 2),
                overlay: fixedLeaf(tree, 1, 1)),
            overlay: fixedLeaf(tree, 1, 1)),
        tree.newNativeLinearStack(
            children: [tree.newNativeLayoutPriority(child: fixedLeaf(tree, 1, 1), priority: 2)],
            axis: .horizontal),
        tree.newNativeLayoutPriority(
            child: tree.newNativeLayoutPriority(child: tree.newNativeSpacer(), priority: 3),
            priority: 1),
        tree.newNativeFrame(child: tree.newNativeSpacer(), width: 5),
        tree.newNativeOverlayAttachment(child: tree.newNativeSpacer(), overlay: fixedLeaf(tree, 1, 1)),
        fixedLeaf(tree, 1, 1),
        tree.newNativeSpacer(),
    ]
    let layout = ScriptedLayout(
        measure: { _, subviews in
            log.priorities = subviews.map(\.priority)
            log.spacers = subviews.map(\.isSpacer)
            return LayoutMeasurement(size: .zero)
        },
        place: { _, _, _ in })
    let root = tree.newNativeLayout(layout, children: children)

    _ = tree.computeNativeLayout(root: root, proposal: ProposedSize(width: 100, height: 100),
                                 in: LayoutRect(x: 0, y: 0, width: 100, height: 100))

    #expect(log.priorities == [2.5, 0, 2, 2, 2, 1, 0, -.infinity, 0, -.infinity])
    #expect(log.spacers == [false, false, false, false, false, true, false, false, false, true])
}

// MARK: - The dynamic backstops (exit tests)
//
// Each asserts its message fragment on stderr as well as the failure, because a
// trap elsewhere must not pass (`ElementGroupTrapTests.swift`'s note). Exit-test
// bodies cannot capture, so the stashes are file-scope.

private final class Stash: @unchecked Sendable {
    var placement: PlacementSubviews?
    var measurement: MeasurementSubviews?
}

private let stash = Stash()

private struct StashingPlacementLayout: ProposalLayout {
    func sizeThatFits(proposal: ProposedSize, subviews: MeasurementSubviews) -> LayoutMeasurement {
        LayoutMeasurement(size: SizeD(width: 10, height: 10))
    }
    func placeSubviews(in bounds: LayoutRect, proposal: ProposedSize, subviews: PlacementSubviews) {
        stash.placement = subviews
    }
}

private struct PlacingFromTheStashLayout: ProposalLayout {
    func sizeThatFits(proposal: ProposedSize, subviews: MeasurementSubviews) -> LayoutMeasurement {
        LayoutMeasurement(size: SizeD(width: 10, height: 10))
    }
    func placeSubviews(in bounds: LayoutRect, proposal: ProposedSize, subviews: PlacementSubviews) {
        stash.placement?[0].place(at: Point(x: 0, y: 0), proposal: .unspecified)
    }
}

/// A `PlacementSubview` smuggled out of its `placeSubviews` call cannot record
/// a placement from a sibling's call (ruling SA-C's token check). Sibling A is
/// placed first (index order), stashes its subviews; sibling B uses them.
@Test func aPlacementSubviewUsedOutsideItsPlaceSubviewsCallTraps() async {
    let result = await #expect(processExitsWith: .failure,
                               observing: [\.standardErrorContent]) {
        let tree = LayoutTree(generation: 0)
        let a = tree.newNativeLayout(StashingPlacementLayout(), children: [
            tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 5, height: 5)) },
        ])
        let b = tree.newNativeLayout(PlacingFromTheStashLayout(), children: [])
        let root = tree.newNativeLinearStack(children: [a, b], axis: .horizontal)
        tree.computeNativeLayout(root: root, proposal: ProposedSize(width: 100, height: 100),
                                 in: LayoutRect(x: 0, y: 0, width: 100, height: 100))
    }
    let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(stderr.contains("used outside its placeSubviews call"),
            "aborted, but not at the token check this test is about:\n\(stderr)")
}

private struct AskingDuringPlacementLayout: ProposalLayout {
    func sizeThatFits(proposal: ProposedSize, subviews: MeasurementSubviews) -> LayoutMeasurement {
        LayoutMeasurement(size: SizeD(width: 50, height: 50))
    }
    func placeSubviews(in bounds: LayoutRect, proposal: ProposedSize, subviews: PlacementSubviews) {
        stash.placement = subviews
        let fresh = ProposedSize(width: 33, height: 33)
        _ = subviews[1].sizeThatFits(fresh)
        subviews[0].place(at: Point(x: 0, y: 0), proposal: fresh)
        subviews[1].place(at: Point(x: 0, y: 0), proposal: fresh)
    }
}

private struct PlacingWhileMeasuredLayout: ProposalLayout {
    func sizeThatFits(proposal: ProposedSize, subviews: MeasurementSubviews) -> LayoutMeasurement {
        stash.placement?[0].place(at: Point(x: 1, y: 1), proposal: .unspecified)
        return LayoutMeasurement(size: SizeD(width: 10, height: 10))
    }
    func placeSubviews(in bounds: LayoutRect, proposal: ProposedSize, subviews: PlacementSubviews) {}
}

/// A `PlacementSubview` used from inside a measurement body traps, even while
/// its own `placeSubviews` call is still active and so its token is current
/// (ruling SA-C's `measureDepth` check; probe D's rule, enforced dynamically).
/// The parent asks child 1 at a proposal not yet measured, so child 1's
/// `sizeThatFits` runs inside the parent's `placeSubviews` and uses the stash.
@Test func aPlacementSubviewUsedDuringMeasurementTraps() async {
    let result = await #expect(processExitsWith: .failure,
                               observing: [\.standardErrorContent]) {
        let tree = LayoutTree(generation: 0)
        let leaf = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 5, height: 5)) }
        let measured = tree.newNativeLayout(PlacingWhileMeasuredLayout(), children: [])
        let root = tree.newNativeLayout(AskingDuringPlacementLayout(), children: [leaf, measured])
        tree.computeNativeLayout(root: root, proposal: ProposedSize(width: 100, height: 100),
                                 in: LayoutRect(x: 0, y: 0, width: 100, height: 100))
    }
    let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(stderr.contains("used during measurement"),
            "aborted, but not at the measurement check this test is about:\n\(stderr)")
}

private struct StashingMeasurementLayout: ProposalLayout {
    func sizeThatFits(proposal: ProposedSize, subviews: MeasurementSubviews) -> LayoutMeasurement {
        stash.measurement = subviews
        return LayoutMeasurement(size: SizeD(width: 10, height: 10))
    }
    func placeSubviews(in bounds: LayoutRect, proposal: ProposedSize, subviews: PlacementSubviews) {}
}

/// A subview proxy used after its layout call returned traps with a message,
/// rather than measuring against a finished run (ruling SA-C).
@Test func aSubviewUsedAfterItsLayoutRunTraps() async {
    let result = await #expect(processExitsWith: .failure,
                               observing: [\.standardErrorContent]) {
        let tree = LayoutTree(generation: 0)
        let leaf = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 5, height: 5)) }
        let root = tree.newNativeLayout(StashingMeasurementLayout(), children: [leaf])
        tree.computeNativeLayout(root: root, proposal: ProposedSize(width: 100, height: 100),
                                 in: LayoutRect(x: 0, y: 0, width: 100, height: 100))
        _ = stash.measurement?[0].sizeThatFits(ProposedSize(width: 1, height: 1))
    }
    let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(stderr.contains("outlived its layout run"),
            "aborted, but not at the run-lifetime check this test is about:\n\(stderr)")
}
