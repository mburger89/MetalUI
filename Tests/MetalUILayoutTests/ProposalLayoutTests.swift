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

/// Answers `min(ideal, proposal.width ?? ideal)` × `height`.
private func flexibleLeaf(_ tree: LayoutTree, ideal: Double, height: Double) -> LayoutNodeID {
    tree.newNativeLeaf { proposal in
        LayoutMeasurement(size: SizeD(width: Swift.min(ideal, proposal.width ?? ideal), height: height))
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
/// - Child A: a horizontal stack, spacing 3, `.bottom`, that overflows with no
///   spacer: flexible leaves of ideal 80×9 (priority 1), 60×11 (priority 0) and
///   50×7 (priority −1), then a fixed 20×13 leaf.
/// - Child B: a horizontal stack, spacing 5, centred: a 30×10 leaf,
///   `Spacer(minLength: 10)`, a 20×18 leaf, a spacer under `layoutPriority(2)`,
///   and an 11×8 leaf.
///
/// **Adjusted from the design's 20×17 and 11×9** so no B edge falls on x.5:
/// B is 18 tall (its tallest child), and centring a 17-tall leaf or a 9-tall
/// one in it, or the min-0 spacer's 0-tall answer in a 17-tall B, put a y on a
/// half point.
private struct ReferenceTree {
    var all: [LayoutNodeID] = []
    var root: LayoutNodeID
    var priorityZeroLeafOfA: LayoutNodeID
    var secondSpacerOfB: LayoutNodeID
    var lastLeafOfB: LayoutNodeID

    init(_ tree: LayoutTree,
         stack: (LayoutTree, [LayoutNodeID], ProposalStackAxis, Double, ProposalAlignment) -> LayoutNodeID) {
        var all: [LayoutNodeID] = []
        func keep(_ id: LayoutNodeID) -> LayoutNodeID { all.append(id); return id }

        let a80 = keep(flexibleLeaf(tree, ideal: 80, height: 9))
        let a80p = keep(tree.newNativeLayoutPriority(child: a80, priority: 1))
        let a60 = keep(flexibleLeaf(tree, ideal: 60, height: 11))
        let a50 = keep(flexibleLeaf(tree, ideal: 50, height: 7))
        let a50p = keep(tree.newNativeLayoutPriority(child: a50, priority: -1))
        let a20 = keep(fixedLeaf(tree, 20, 13))
        let a = keep(stack(tree, [a80p, a60, a50p, a20], .horizontal, 3, .bottom))

        let b30 = keep(fixedLeaf(tree, 30, 10))
        let bSpacer = keep(tree.newNativeSpacer(minLength: 10))
        let b20 = keep(fixedLeaf(tree, 20, 18))
        let bInnerSpacer = keep(tree.newNativeSpacer())
        let bSpacer2 = keep(tree.newNativeLayoutPriority(child: bInnerSpacer, priority: 2))
        let b11 = keep(fixedLeaf(tree, 11, 8))
        let b = keep(stack(tree, [b30, bSpacer, b20, bSpacer2, b11], .horizontal, 5, .center))

        root = keep(stack(tree, [a, b], .vertical, 7, .trailing))
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
    _ stack: (LayoutTree, [LayoutNodeID], ProposalStackAxis, Double, ProposalAlignment) -> LayoutNodeID
) -> LaidOut {
    let tree = LayoutTree(generation: 0)
    let ids = ReferenceTree(tree, stack: stack)
    let measurement = tree.computeNativeLayout(root: ids.root, proposal: referenceProposal,
                                               in: referenceBounds)
    return LaidOut(measurement: measurement, rects: ids.all.map(tree.layout),
                   widths: ids.all.map(tree.measuredWidth), tree: tree, ids: ids)
}

/// **Sufficiency of the protocol (ruling SA-B, SA-D):** a `ProposalLayout`
/// written with a plain import (`ReferenceLinearStack.swift`) reproduces the
/// built-in linear stack's every stored rect and measured width on a tree that
/// reaches priority allocation, spacer surplus and cross-axis alignment.
///
/// The three literal rects were derived by hand before the run:
/// - Root measured at 157×91. A (proposal 157×nil, child proposal nil×nil):
///   natural 80 + 60 + 50 + 20 + 3·3 = 219 > 157, so 157×13. B: natural
///   30 + 10 + 20 + 0 + 11 + 4·5 = 91, with a spacer, so max(91, 157) = 157×18.
///   Root: 13 + 18 + 7 = 38, so 157×38.
/// - Root placement at (13, 17, 157, 91): A at (13, 17, 157, 13), B at
///   (13, 37, 157, 18).
/// - A allocates: remaining 157 − 9 = 148; priority 1 takes its ideal 80,
///   leaving 68; priority 0 holds the 60 leaf and the fixed 20 leaf, ideal 80 >
///   68, so each is proposed 34; priority −1 gets 0. Cursor 13 + 80 + 3 = 96,
///   so **A's priority-0 leaf is (96, 17 + 13 − 11, 34, 11) = (96, 19, 34, 11)**.
/// - B's spacer surplus (157 − 91) / 2 = 33 each. Cursor: 13 → 48 (30 + 5) →
///   96 (spacer 10 + 33 + 5) → 121 (20 + 5). **B's second spacer is proposed
///   0 + 33 wide and answers its minimum 0 tall: (121, 37 + 18/2, 33, 0) =
///   (121, 46, 33, 0).** Cursor 121 + 33 + 5 = 159, so **B's last leaf is
///   (159, 37 + (18 − 8)/2, 11, 8) = (159, 42, 11, 8)**.
@Test func aCustomLayoutReimplementingTheLinearStackMatchesTheBuiltInRects() throws {
    let builtIn = layOutReference(builtInStack)
    let custom = layOutReference { tree, children, axis, spacing, alignment in
        tree.newNativeLayout(ReferenceLinearStack(axis: axis, spacing: spacing, alignment: alignment),
                             children: children)
    }

    #expect(builtIn.measurement == LayoutMeasurement(size: SizeD(width: 157, height: 38)))
    #expect(builtIn.tree.layout(builtIn.ids.priorityZeroLeafOfA) == LayoutRect(x: 96, y: 19, width: 34, height: 11))
    #expect(builtIn.tree.layout(builtIn.ids.secondSpacerOfB) == LayoutRect(x: 121, y: 46, width: 33, height: 0))
    #expect(builtIn.tree.layout(builtIn.ids.lastLeafOfB) == LayoutRect(x: 159, y: 42, width: 11, height: 8))

    try #require(builtIn.rects.count == custom.rects.count)
    #expect(custom.measurement == builtIn.measurement)
    for index in builtIn.rects.indices {
        #expect(custom.rects[index] == builtIn.rects[index], "node \(index)")
        #expect(custom.widths[index] == builtIn.widths[index], "measured width of node \(index)")
    }

    // Shape 15: the two controls must DISAGREE with the built-in, or the
    // equality above could not see a proxy that drops priority or spacer-ness.
    let priorityBlind = layOutReference { tree, children, axis, spacing, alignment in
        tree.newNativeLayout(PriorityBlindLinearStack(axis: axis, spacing: spacing, alignment: alignment),
                             children: children)
    }
    let spacerBlind = layOutReference { tree, children, axis, spacing, alignment in
        tree.newNativeLayout(SpacerBlindLinearStack(axis: axis, spacing: spacing, alignment: alignment),
                             children: children)
    }
    try #require(priorityBlind.rects != builtIn.rects,
                 "a priority-blind stack must change the reference tree's rects")
    try #require(spacerBlind.rects != builtIn.rects,
                 "a spacer-blind stack must change the reference tree's rects")
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
/// (ruling SA-D; probes L, L2, L3).
///
/// | child | priority | isSpacer | why |
/// |---|---|---|---|
/// | `layoutPriority(2.5)` | 2.5 | false | probe E / L control |
/// | `frame` over `layoutPriority(2)` | 0 | false | probe L: a laying-out wrapper hides it |
/// | one overlay attachment over `layoutPriority(2)` | 2 | false | probe L2 |
/// | two overlay attachments over `layoutPriority(2)` | 2 | false | probe L2 |
/// | a one-child linear stack over `layoutPriority(2)` | **0, pinned wrong on purpose** | false | SwiftUI reads 2 (probe L3); SA-N item 8, plan task 6 |
/// | `layoutPriority(1)` over `layoutPriority(3)` over a spacer | 1 | true | spacer under any depth of priority |
/// | `frame` over a spacer | 0 | false | never through another wrapper |
/// | overlay attachment over a spacer | 0 | false | `isNativeSpacer` does not look through attachments |
/// | a plain leaf | 0 | false | |
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

    #expect(log.priorities == [2.5, 0, 2, 2, 0, 1, 0, 0, 0])
    #expect(log.spacers == [false, false, false, false, false, true, false, false, false])
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
