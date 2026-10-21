import Testing
import MetalUICore
import MetalUILayout
@testable import MetalUI

// Lazy containers, lane 1: the stacks' layout facts (spec section 5, tests 1.1-1.5; rulings `LZ-D`,
// `LZ-B`; probe `docs/probes/swiftui-lazy-containers.swift` arms A1-A9, whose recorded figures are the
// literals here, re-derived below).
//
// **The instrument.** A `ProbeHost` layout that answers a fixed 200 x 200 and asks its one child
// (the lazy stack) for its size at the arm's stated proposal, then places it at the host's origin.
// The root is the host in a 200 x 200 frame, so it sits at (0, 0) and every literal is absolute.
// Children are `Leaf`s of a fixed size that log where they were placed; the stack's own answer is
// read in the host's `placeSubviews`. Red-before: the types did not exist (every test failed to
// compile on `cannot find 'LazyVStack' in scope`; record section 134).
//
// Children are a (30 x 10), b (100 x 20) and c (50 x 10) unless stated, as in the probe.

private func bounds(_ x: Float, _ y: Float, _ width: Float, _ height: Float) -> Bounds<Pixels> {
    Bounds(origin: Point(x: Pixels(x), y: Pixels(y)),
           size: Size(width: Pixels(width), height: Pixels(height)))
}

/// What the host read.
private final class StackAnswer: @unchecked Sendable {
    var size: SizeD?
}

/// A 200 x 200 layout that places its one child at its origin under `proposal`.
private struct ProbeHost: ProposalLayout {
    let proposal: ProposedSize
    let answer: StackAnswer

    func sizeThatFits(proposal: ProposedSize, subviews: MeasurementSubviews) -> LayoutMeasurement {
        LayoutMeasurement(size: SizeD(width: 200, height: 200))
    }

    func placeSubviews(in bounds: LayoutRect, proposal: ProposedSize, subviews: PlacementSubviews) {
        answer.size = subviews[0].sizeThatFits(self.proposal).size
        subviews[0].place(at: Point(x: bounds.x, y: bounds.y), anchor: .topLeading, proposal: self.proposal)
    }
}

/// A leaf of a fixed size that logs its placed bounds under `name`.
private struct Leaf: ProposalElement {
    let width: Double
    let height: Double
    let name: String
    let log: LeafBoundsLog

    func requestProposalLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (ProposalNodeID, Void) {
        let size = SizeD(width: width, height: height)
        return (pass.requestNativeLeaf { _ in LayoutMeasurement(size: size) }, ())
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, pass: inout PrepaintPass) {
        log.byName[name] = bounds
    }

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, prepaint: inout Void,
               pass: inout PaintPass) {}
}

/// Renders `stack` under the host at `proposal` and returns the stack's answer.
@MainActor
private func render<Stack: ProposalElementGroup>(_ proposal: ProposedSize, log: LeafBoundsLog,
                                                 @ProposalContentBuilder _ stack: () -> Stack) -> SizeD? {
    let answer = StackAnswer()
    var root = ProposalLayoutContainer(ProbeHost(proposal: proposal, answer: answer), content: stack)
    Frame(contentSize: Size(width: Pixels(200), height: Pixels(200)), scaleFactor: 1).render(&root)
    return answer.size
}

@MainActor @ProposalContentBuilder
private func abc(_ log: LeafBoundsLog, widths: (Double, Double, Double) = (30, 100, 50))
    -> some ProposalElementGroup {
    Leaf(width: widths.0, height: 10, name: "a", log: log)
    Leaf(width: widths.1, height: 20, name: "b", log: log)
    Leaf(width: widths.2, height: 10, name: "c", log: log)
}

private let at200 = ProposedSize(width: 200, height: 200)

/// **1.1** (probe A1, A2). Outside a scroller a `LazyVStack(spacing: 0)` answers the PROPOSAL across
/// (200, not the widest child's 100) and its content down (40 = 10 + 20 + 10, not greedy). Children
/// centre: a (200 - 30) / 2 = 85, b (200 - 100) / 2 = 50, c (200 - 50) / 2 = 75; y 0, 10, 30. With
/// `spacing: nil` the default is 8: size 200 x 56 (10 + 8 + 20 + 8 + 10), b at 18, c at 46 (A2).
/// Mutations: the spacing default 8 -> 0; the cross answer = the widest child.
@MainActor
@Test func aLazyVStackOutsideAScrollerPlacesEveryChildAndAnswersTheProposalAcross() {
    let flush = LeafBoundsLog()
    let size = render(at200, log: flush) { LazyVStack(spacing: Pixels(0)) { abc(flush) } }
    #expect(size == SizeD(width: 200, height: 40))
    #expect(flush.byName["a"] == bounds(85, 0, 30, 10))
    #expect(flush.byName["b"] == bounds(50, 10, 100, 20))
    #expect(flush.byName["c"] == bounds(75, 30, 50, 10))

    let spaced = LeafBoundsLog()
    let spacedSize = render(at200, log: spaced) { LazyVStack { abc(spaced) } }
    #expect(spacedSize == SizeD(width: 200, height: 56))
    #expect(spaced.byName["a"] == bounds(85, 0, 30, 10))
    #expect(spaced.byName["b"] == bounds(50, 18, 100, 20))
    #expect(spaced.byName["c"] == bounds(75, 46, 50, 10))
}

/// **1.2** (probe A3, A3b, A3d, A5). At a nil width the stack answers the FIRST child's width: 30 for
/// 30/100/50 (a at 0, b centred at (30 - 100) / 2 = -35, c at -10); 100 when the first is the widest
/// (100/30/50); 50 for 50/100/30 where the first is neither the widest nor the smallest (b at -25).
/// At width 80, narrower than b, the answer is 80 and b overflows centred: 80 x 48 with spacing 4
/// (10 + 4 + 20 + 4 + 10), a at (80 - 30) / 2 = 25, b at -10, c at 15; y 0, 14, 38. Mutations: first ->
/// widest (reddens the 50/100/30 arm); first -> last.
@MainActor
@Test func aLazyVStackAnswersTheFirstChildAtANilCrossProposal() {
    let nilLog = LeafBoundsLog()
    let nilSize = render(ProposedSize(), log: nilLog) { LazyVStack(spacing: Pixels(0)) { abc(nilLog) } }
    #expect(nilSize == SizeD(width: 30, height: 40))
    #expect(nilLog.byName["a"] == bounds(0, 0, 30, 10))
    #expect(nilLog.byName["b"] == bounds(-35, 10, 100, 20))
    #expect(nilLog.byName["c"] == bounds(-10, 30, 50, 10))

    let firstWidest = LeafBoundsLog()
    #expect(render(ProposedSize(), log: firstWidest) {
        LazyVStack(spacing: Pixels(0)) { abc(firstWidest, widths: (100, 30, 50)) }
    } == SizeD(width: 100, height: 40))
    #expect(firstWidest.byName["b"] == bounds(35, 10, 30, 20))

    let middleWidest = LeafBoundsLog()
    #expect(render(ProposedSize(), log: middleWidest) {
        LazyVStack(spacing: Pixels(0)) { abc(middleWidest, widths: (50, 100, 30)) }
    } == SizeD(width: 50, height: 40))
    #expect(middleWidest.byName["b"] == bounds(-25, 10, 100, 20))
    #expect(middleWidest.byName["c"] == bounds(10, 30, 30, 10))

    let narrow = LeafBoundsLog()
    #expect(render(ProposedSize(width: 80), log: narrow) { LazyVStack(spacing: Pixels(4)) { abc(narrow) } }
            == SizeD(width: 80, height: 48))
    #expect(narrow.byName["a"] == bounds(25, 0, 30, 10))
    #expect(narrow.byName["b"] == bounds(-10, 14, 100, 20))
    #expect(narrow.byName["c"] == bounds(15, 38, 50, 10))
}

/// **1.3** (probe A6, A7). `LazyHStack` is the same on the other axis. At a nil proposal: width 180
/// (30 + 100 + 50, content), height 10 (the FIRST child's), a at (0, 0), b centred vertically at
/// (10 - 20) / 2 = -5 and x 30, c at (130, 0). At 200 x 200 with `.top`: 180 x 200 (the proposed
/// height across), every child at y 0. Mutation: the cross answer reading the wrong axis.
@MainActor
@Test func aLazyHStackIsTheSameOnTheOtherAxis() {
    let nilLog = LeafBoundsLog()
    let nilSize = render(ProposedSize(), log: nilLog) { LazyHStack(spacing: Pixels(0)) { abc(nilLog) } }
    #expect(nilSize == SizeD(width: 180, height: 10))
    #expect(nilLog.byName["a"] == bounds(0, 0, 30, 10))
    #expect(nilLog.byName["b"] == bounds(30, -5, 100, 20))
    #expect(nilLog.byName["c"] == bounds(130, 0, 50, 10))

    let top = LeafBoundsLog()
    let topSize = render(at200, log: top) { LazyHStack(alignment: .top, spacing: Pixels(0)) { abc(top) } }
    #expect(topSize == SizeD(width: 180, height: 200))
    #expect(top.byName["a"] == bounds(0, 0, 30, 10))
    #expect(top.byName["b"] == bounds(30, 0, 100, 20))
    #expect(top.byName["c"] == bounds(130, 0, 50, 10))
}

/// **1.4** (probe A4, A4t). `.leading` puts every child at x 0 (y 0, 10, 30); `.trailing` at
/// 200 - width: 170, 100, 150. Mutation: alignment ignored (every child centred, a at 85).
@MainActor
@Test func leadingAndTrailingAlignmentPlaceTheChildrenAcross() {
    let leading = LeafBoundsLog()
    _ = render(at200, log: leading) { LazyVStack(alignment: .leading, spacing: Pixels(0)) { abc(leading) } }
    #expect(leading.byName["a"] == bounds(0, 0, 30, 10))
    #expect(leading.byName["b"] == bounds(0, 10, 100, 20))
    #expect(leading.byName["c"] == bounds(0, 30, 50, 10))

    let trailing = LeafBoundsLog()
    _ = render(at200, log: trailing) { LazyVStack(alignment: .trailing, spacing: Pixels(0)) { abc(trailing) } }
    #expect(trailing.byName["a"] == bounds(170, 0, 30, 10))
    #expect(trailing.byName["b"] == bounds(100, 10, 100, 20))
    #expect(trailing.byName["c"] == bounds(150, 30, 50, 10))
}

/// **1.5** (probe A8, A9). A `ForEach` element of two views is two views in sequence: element 0 holds
/// a and b, element 1 holds c; spacing 0: size 200 x 40, a (85, 0), b (50, 10), c (75, 30). An element
/// that registers no view adds no extent and no spacing: a, nothing, c with spacing 6 puts c at
/// 10 + 6 = 16 and the stack 200 x 26 (10 + 6 + 10), not 10 + 6 + 0 + 6 + 10. Mutation: a unit's
/// extent counts a trailing spacing even with no node.
@MainActor
@Test func aForEachElementOfSeveralViewsIsSeveralViewsInSequenceAndOneOfNoneAddsNoSpacing() {
    let two = LeafBoundsLog()
    let twoSize = render(at200, log: two) {
        LazyVStack(spacing: Pixels(0)) {
            ForEach(0..<2) { index in
                if index == 0 {
                    Leaf(width: 30, height: 10, name: "a", log: two)
                    Leaf(width: 100, height: 20, name: "b", log: two)
                } else {
                    Leaf(width: 50, height: 10, name: "c", log: two)
                }
            }
        }
    }
    #expect(twoSize == SizeD(width: 200, height: 40))
    #expect(two.byName["a"] == bounds(85, 0, 30, 10))
    #expect(two.byName["b"] == bounds(50, 10, 100, 20))
    #expect(two.byName["c"] == bounds(75, 30, 50, 10))

    let none = LeafBoundsLog()
    let noneSize = render(at200, log: none) {
        LazyVStack(spacing: Pixels(6)) {
            ForEach(0..<3) { index in
                if index == 0 { Leaf(width: 30, height: 10, name: "a", log: none) }
                if index == 2 { Leaf(width: 50, height: 10, name: "c", log: none) }
            }
        }
    }
    #expect(noneSize == SizeD(width: 200, height: 26))
    #expect(none.byName["a"] == bounds(85, 0, 30, 10))
    #expect(none.byName["c"] == bounds(75, 16, 50, 10))
}
