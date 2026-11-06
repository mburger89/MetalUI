import Testing
import MetalUICore
@testable import MetalUILayout

// `ViewThatFits` at the kernel (`VF-A`, `VF-B`, `VF-H`; record 217; probe `docs/probes/swiftui-view-that-fits.swift`,
// whose arm ids are quoted). Every expected value is a probe reading; the arms are portable (they also run on Linux and
// Windows). Counts and rects only, never time.

private final class Asked: @unchecked Sendable {
    var proposals: [ProposedSize] = []
}

/// A candidate leaf of a fixed size that logs every proposal it is asked.
private func candidate(_ tree: LayoutTree, _ width: Double, _ height: Double, log: Asked = Asked()) -> LayoutNodeID {
    tree.newNativeLeaf { proposal in
        log.proposals.append(proposal)
        return LayoutMeasurement(size: SizeD(width: width, height: height))
    }
}

private func fits(_ tree: LayoutTree, _ children: [LayoutNodeID], horizontal: Bool = true,
                  vertical: Bool = false) -> LayoutNodeID {
    tree.newNativeFirstFitting(children: children, horizontal: horizontal, vertical: vertical)
}

@discardableResult
private func lay(_ tree: LayoutTree, _ root: LayoutNodeID, _ proposal: ProposedSize) -> LayoutMeasurement {
    tree.computeNativeLayout(root: root, proposal: proposal,
                             in: LayoutRect(x: 0, y: 0, width: proposal.width ?? 0, height: proposal.height ?? 0))
}

/// `H1`: the eight widths. The test is `<=` (W = 100 and W = 60 fit), each candidate is asked `(nil, H)` first and the
/// chosen one then the whole proposal, and a candidate after the chosen one is never asked.
/// Mutation: `<=` to `<` in `firstFittingCandidate` reddens W = 100 and W = 60.
@Test @MainActor func aViewThatFitsPicksTheFirstChildWhoseIdealFitsWithLessOrEqual() throws {
    let cases: [(width: Double, choice: Int, answer: Double)] = [
        (101, 0, 100), (100, 0, 100), (99.5, 1, 60), (60.5, 1, 60), (60, 1, 60), (59.99, 2, 30), (30, 2, 30), (29, 2, 30),
    ]
    for (width, choice, answer) in cases {
        let tree = LayoutTree(generation: 1)
        let logs = [Asked(), Asked(), Asked()]
        let root = fits(tree, [candidate(tree, 100, 20, log: logs[0]), candidate(tree, 60, 20, log: logs[1]),
                               candidate(tree, 30, 20, log: logs[2])])
        let measurement = lay(tree, root, ProposedSize(width: width, height: 50))
        #expect(tree.firstFittingChoice(root) == choice, "W = \(width)")
        #expect(measurement.size == SizeD(width: answer, height: 20), "W = \(width)")
        for index in 0...choice {
            #expect(logs[index].proposals.first == ProposedSize(width: nil, height: 50), "candidate \(index) at W = \(width) is asked its ideal first")
        }
        // The chosen candidate is asked the whole proposal; the ones after it are never asked.
        #expect(logs[choice].proposals.contains(ProposedSize(width: width, height: 50)), "W = \(width)")
        for index in (choice + 1)..<3 { #expect(logs[index].proposals.isEmpty, "candidate \(index) at W = \(width)") }
    }
}

/// `V1` and `B1`: a vertical view tests heights (each candidate asked `(W, nil)`), a two-axis one both (each asked
/// `(nil, nil)`); the last candidate is the fallback. Mutation: ignoring `vertical` in `firstFittingCandidate` reddens `V1`
/// at 99.5 and 30 and `B1` at 120 x 15.
@Test @MainActor func aVerticalAndATwoAxisViewThatFitsReadTheirAxes() throws {
    for (height, choice) in [(100.0, 0), (99.5, 1), (30.0, 2)] {
        let tree = LayoutTree(generation: 1)
        let logs = [Asked(), Asked(), Asked()]
        let root = fits(tree, [candidate(tree, 20, 100, log: logs[0]), candidate(tree, 20, 60, log: logs[1]),
                               candidate(tree, 20, 30, log: logs[2])], horizontal: false, vertical: true)
        lay(tree, root, ProposedSize(width: 50, height: height))
        #expect(tree.firstFittingChoice(root) == choice, "V1 H = \(height)")
        #expect(logs[0].proposals.first == ProposedSize(width: 50, height: nil))
    }
    let both: [(Double, Double, Int, SizeD)] = [(120, 50, 0, SizeD(width: 100, height: 40)), (120, 15, 1, SizeD(width: 60, height: 10)),
                                               (50, 50, 2, SizeD(width: 30, height: 30)), (20, 10, 2, SizeD(width: 30, height: 30))]
    for (width, height, choice, answer) in both {
        let tree = LayoutTree(generation: 1)
        let log = Asked()
        let root = fits(tree, [candidate(tree, 100, 40, log: log), candidate(tree, 60, 10), candidate(tree, 30, 30)],
                        horizontal: true, vertical: true)
        let measurement = lay(tree, root, ProposedSize(width: width, height: height))
        #expect(tree.firstFittingChoice(root) == choice, "B1 \(width) x \(height)")
        #expect(measurement.size == answer, "B1 \(width) x \(height)")
        #expect(log.proposals.first == ProposedSize(width: nil, height: nil))
    }
    // Neither axis named: nothing is tested and the first child is always chosen (unmeasured in SwiftUI).
    let tree = LayoutTree(generation: 1)
    let none = fits(tree, [candidate(tree, 100, 20), candidate(tree, 10, 20)], horizontal: false, vertical: false)
    lay(tree, none, ProposedSize(width: 5, height: 5))
    #expect(tree.firstFittingChoice(none) == 0)
}

/// `W1` and `W2`: the fit test is the ideal alone. A candidate whose ideal is 50 and which answers 150 at the proposal is
/// chosen (and the view answers 150, past the proposal); one whose ideal is 150 and which would answer 50 is rejected.
/// Mutation: testing the answer at the proposal instead of the ideal turns both around.
@Test @MainActor func theFitTestIsTheIdealAlone() throws {
    let tree = LayoutTree(generation: 1)
    let wide = tree.newNativeLeaf { proposal in
        LayoutMeasurement(size: SizeD(width: proposal.width == nil ? 50 : 150, height: 20))
    }
    let root = fits(tree, [wide, candidate(tree, 20, 20)])
    let measurement = lay(tree, root, ProposedSize(width: 100, height: 50))
    #expect(tree.firstFittingChoice(root) == 0, "W1: ideal 50, answer 150 at 100")
    #expect(measurement.size == SizeD(width: 150, height: 20))

    let other = LayoutTree(generation: 1)
    let narrow = other.newNativeLeaf { proposal in
        LayoutMeasurement(size: SizeD(width: proposal.width == nil ? 150 : 50, height: 20))
    }
    let rejecting = fits(other, [narrow, candidate(other, 20, 20)])
    lay(other, rejecting, ProposedSize(width: 100, height: 50))
    #expect(other.firstFittingChoice(rejecting) == 1, "W2: ideal 150, answer 50 at 100")

    // `Z1`: an ideal of 0 at W = 0 fits.
    let zero = LayoutTree(generation: 1)
    let z = fits(zero, [candidate(zero, 0, 20), candidate(zero, 20, 20)])
    lay(zero, z, ProposedSize(width: 0, height: 50))
    #expect(zero.firstFittingChoice(z) == 0)
}

/// `I1`..`I4`: what the view reports to its parent. `I1` (horizontal, {100, 60, 30} x 20): `(nil,nil)` 100, `(0,0)` 30
/// (the fallback), `(inf,inf)` 100, `(50,nil)` 30, `(nil,10)` 100, `(80,50)` 60. `I2` (both axes, `(nil, 10)`): 60 x 10.
/// `I3` (vertical): `(0,0)` 70 x 60, `(50,nil)` 20 x 100. `I4`: an `HStack(spacing: 0) { view; 50 }` offers the view 150 / 70
/// / 20 at W = 200 / 120 / 70 and it shows 100 / 60 / 30.
@Test @MainActor func aViewThatFitsAnswersItsParent() throws {
    func horizontal() -> (LayoutTree, LayoutNodeID) {
        let tree = LayoutTree(generation: 1)
        let root = fits(tree, [candidate(tree, 100, 20), candidate(tree, 60, 20), candidate(tree, 30, 20)])
        return (tree, root)
    }
    let i1: [(ProposedSize, SizeD)] = [
        (ProposedSize(width: nil, height: nil), SizeD(width: 100, height: 20)), (ProposedSize(width: 0, height: 0), SizeD(width: 30, height: 20)),
        (ProposedSize(width: .infinity, height: .infinity), SizeD(width: 100, height: 20)), (ProposedSize(width: 50, height: nil), SizeD(width: 30, height: 20)),
        (ProposedSize(width: nil, height: 10), SizeD(width: 100, height: 20)), (ProposedSize(width: 80, height: 50), SizeD(width: 60, height: 20)),
    ]
    for (proposal, expected) in i1 {
        let (tree, root) = horizontal()
        #expect(tree.measureNativeLayout(root: root, proposal: proposal).size == expected, "I1 \(proposal)")
    }
    let both = LayoutTree(generation: 1)
    let two = fits(both, [candidate(both, 100, 40), candidate(both, 60, 10), candidate(both, 30, 30)], horizontal: true, vertical: true)
    #expect(both.measureNativeLayout(root: two, proposal: ProposedSize(width: nil, height: 10)).size == SizeD(width: 60, height: 10), "I2")
    func vertical() -> (LayoutTree, LayoutNodeID) {
        let tree = LayoutTree(generation: 1)
        let root = fits(tree, [candidate(tree, 20, 100), candidate(tree, 40, 80), candidate(tree, 70, 60)], horizontal: false, vertical: true)
        return (tree, root)
    }
    let (t3a, r3a) = vertical()
    #expect(t3a.measureNativeLayout(root: r3a, proposal: ProposedSize(width: 0, height: 0)).size == SizeD(width: 70, height: 60), "I3 (0,0)")
    let (t3b, r3b) = vertical()
    #expect(t3b.measureNativeLayout(root: r3b, proposal: ProposedSize(width: 50, height: nil)).size == SizeD(width: 20, height: 100), "I3 (50,nil)")
    for (width, offered, shown) in [(200.0, 150.0, 100.0), (120, 70, 60), (70, 20, 30)] {
        let tree = LayoutTree(generation: 1)
        let logs = [Asked(), Asked(), Asked()]
        let view = fits(tree, [candidate(tree, 100, 20, log: logs[0]), candidate(tree, 60, 20, log: logs[1]), candidate(tree, 30, 20, log: logs[2])])
        let row = tree.newNativeLinearStack(children: [view, candidate(tree, 50, 20)], axis: .horizontal, spacing: 0)
        lay(tree, row, ProposedSize(width: width, height: 50))
        let choice = try #require(tree.firstFittingChoice(view))
        #expect(logs[choice].proposals.last == ProposedSize(width: offered, height: 50), "I4 W = \(width) offers \(offered)")
        #expect(tree.layout(view).width == shown, "I4 W = \(width) shows \(shown)")
    }
}

/// `F1`..`F4` (the app's need 3): a flexible candidate is measured at its ideal, which is not the proposal: an
/// `HStack(spacing: 0) { 50; Spacer() }` is 58, with `Spacer(minLength: 0)` 50, a bare greedy leaf 10 (a `Color`'s), the
/// drag handle shape `{50; greedy}` 60, a `frame(minWidth: 80, maxWidth: .infinity)` 80; each is chosen over a 10 x 20
/// fallback at the widths the probe read.
@Test @MainActor func flexibleCandidatesMeasureAtTheirIdeal() throws {
    func greedy(_ tree: LayoutTree) -> LayoutNodeID {
        tree.newNativeLeaf { proposal in LayoutMeasurement(size: SizeD(width: proposal.width ?? 10, height: proposal.height ?? 10)) }
    }
    let shapes: [(name: String, ideal: Double, chosen: [Double: Bool], build: (LayoutTree) -> LayoutNodeID)] = [
        ("F1", 58, [40: false, 70: true, 200: true], { t in
            t.newNativeLinearStack(children: [candidate(t, 50, 20), t.newNativeSpacer()], axis: .horizontal, spacing: 0) }),
        ("F1m", 50, [40: false, 70: true, 200: true], { t in
            t.newNativeLinearStack(children: [candidate(t, 50, 20), t.newNativeSpacer(minLength: 0)], axis: .horizontal, spacing: 0) }),
        ("F2", 10, [40: true, 70: true, 200: true], { t in greedy(t) }),
        ("F2b", 60, [40: false, 70: true, 200: true], { t in
            t.newNativeLinearStack(children: [candidate(t, 50, 20), greedy(t)], axis: .horizontal, spacing: 0) }),
        ("F4", 80, [40: false, 70: false, 200: true], { t in
            t.newNativeFrame(child: candidate(t, 10, 20), minWidth: 80, maxWidth: .infinity) }),
    ]
    for shape in shapes {
        let alone = LayoutTree(generation: 1)
        let flexible = shape.build(alone)
        let ideal = alone.measureNativeLayout(root: flexible, proposal: ProposedSize(width: nil, height: 50)).size.width
        #expect(ideal == shape.ideal, "\(shape.name) ideal")
        for (width, expected) in shape.chosen {
            let tree = LayoutTree(generation: 1)
            let root = fits(tree, [shape.build(tree), candidate(tree, 10, 20)])
            lay(tree, root, ProposedSize(width: width, height: 50))
            #expect((tree.firstFittingChoice(root) == 0) == expected, "\(shape.name) at W = \(width)")
        }
    }
}

/// `N1`: a nested view's ideal is its first child's, so nesting does not cascade: `{ {150, 90}, 40 }` picks the inner one
/// at W = 160 and the 40 at 100 and 60.
@Test @MainActor func aNestedViewThatFitsIdealIsItsFirstChilds() throws {
    for (width, outer) in [(160.0, 0), (100, 1), (60, 1)] {
        let tree = LayoutTree(generation: 1)
        let inner = fits(tree, [candidate(tree, 150, 20), candidate(tree, 90, 20)])
        let root = fits(tree, [inner, candidate(tree, 40, 20)])
        lay(tree, root, ProposedSize(width: width, height: 50))
        #expect(tree.firstFittingChoice(root) == outer, "N1 W = \(width)")
    }
}

/// Only the chosen candidate is placed: an unchosen candidate's whole subtree keeps zero rects (and is never measured past
/// the ideal asks), the choice reads back, and the view's own rect is the proposal's. W = 70 chooses the 60-wide second
/// candidate: the first (a stack of two leaves) is asked its ideal only, the third not at all.
@Test @MainActor func onlyTheChosenCandidateIsPlaced() throws {
    let tree = LayoutTree(generation: 1)
    let logs = [Asked(), Asked(), Asked(), Asked()]
    let firstA = candidate(tree, 60, 20, log: logs[0]), firstB = candidate(tree, 40, 20, log: logs[1])
    let first = tree.newNativeLinearStack(children: [firstA, firstB], axis: .horizontal, spacing: 0)
    let second = candidate(tree, 60, 20, log: logs[2])
    let third = candidate(tree, 30, 20, log: logs[3])
    let root = fits(tree, [first, second, third])
    // Placed at its own answer, centred in the container, as a parent places a child (`CN-J`).
    tree.computeNativeLayout(root: root, proposal: ProposedSize(width: 70, height: 50),
                             centredIn: LayoutRect(x: 0, y: 0, width: 70, height: 50))
    #expect(tree.firstFittingChoice(root) == 1)
    #expect(tree.layout(root) == LayoutRect(x: 5, y: 15, width: 60, height: 20))
    #expect(tree.layout(second) == LayoutRect(x: 5, y: 15, width: 60, height: 20), "the chosen candidate takes the view's bounds")
    let zero = LayoutRect(x: 0, y: 0, width: 0, height: 0)
    #expect(tree.layout(first) == zero)
    #expect(tree.layout(firstA) == zero)
    #expect(tree.layout(firstB) == zero)
    #expect(tree.layout(third) == zero)
    #expect(logs[3].proposals.isEmpty, "nothing past the first fit is asked")
    // Leaf closures: the first candidate's two leaves once each (ideal), the chosen leaf twice ((nil,50), (70,50)).
    #expect(tree.lastNativeLayoutWork.measureCalls == 4)
    // A node that is not a view-that-fits has no choice, and neither has one never placed.
    #expect(tree.firstFittingChoice(first) == nil)
    let unplaced = LayoutTree(generation: 2)
    #expect(unplaced.firstFittingChoice(fits(unplaced, [candidate(unplaced, 1, 1)])) == nil)
}

/// `PR1`/`PR2` (the plan's reading; the probe file's priority arms do not separate and are not re-taken there): a
/// `layoutPriority` on the view is the view's, one on its only child is not passed through. Two greedy leaves split 100/100;
/// a view whose child carries priority 1 splits the same, and a priority on the view itself takes the whole offer first.
@Test @MainActor func aViewThatFitsPassesNoChildPriority() throws {
    func greedy(_ tree: LayoutTree) -> LayoutNodeID {
        tree.newNativeLeaf { proposal in LayoutMeasurement(size: SizeD(width: proposal.width ?? 10, height: 20)) }
    }
    func widths(childPriority: Bool, viewPriority: Bool) -> (Double, Double) {
        let tree = LayoutTree(generation: 1)
        var child = greedy(tree)
        if childPriority { child = tree.newNativeLayoutPriority(child: child, priority: 1) }
        var view = fits(tree, [child])
        if viewPriority { view = tree.newNativeLayoutPriority(child: view, priority: 1) }
        let other = greedy(tree)
        let row = tree.newNativeLinearStack(children: [view, other], axis: .horizontal, spacing: 0)
        lay(tree, row, ProposedSize(width: 200, height: 50))
        return (tree.layout(other).width, tree.layout(child).width)
    }
    let control = widths(childPriority: false, viewPriority: false)
    #expect(control.0 == 100 && control.1 == 100)
    let throughChild = widths(childPriority: true, viewPriority: false)
    #expect(throughChild.0 == 100 && throughChild.1 == 100, "PR2: not passed through")
    let onView = widths(childPriority: false, viewPriority: true)
    #expect(onView.1 > 100 && onView.0 < 100, "PR1: a priority on the view works")
}

// MARK: - The memo carries the choice (`VF-H`)

private func keyedFixed(_ tree: LayoutTree, _ key: String, _ width: Double) -> LayoutNodeID {
    tree.newNativeLeaf(key: key) { proposal in
        LayoutMeasurement(size: SizeD(width: width, height: 20))
    }
}

private func memoTree(_ memo: LayoutMemo, generation: UInt64) -> (LayoutTree, view: LayoutNodeID, chosen: LayoutNodeID, root: LayoutNodeID) {
    let tree = LayoutTree(generation: generation)
    tree.memo = memo
    let first = keyedFixed(tree, "a", 100), second = keyedFixed(tree, "b", 60), third = keyedFixed(tree, "c", 30)
    let view = fits(tree, [first, second, third])
    let root = tree.newNativeLinearStack(children: [view], axis: .horizontal, spacing: 0)
    return (tree, view, second, root)
}

/// The choice survives a restored root placement: a second identical frame hits the memo's root placement and still reads
/// the choice and the chosen rect; under `verifies` the restore is recomputed fresh and compared, including the choices.
/// Mutation: dropping `choices` from `Placed` (store `[]`) makes the second frame read `nil`.
@Test @MainActor func aRestoredPlacementRestoresTheChoice() throws {
    for verifies in [false, true] {
        let memo = LayoutMemo(verifies: verifies)
        let (first, firstView, _, firstRoot) = memoTree(memo, generation: 1)
        lay(first, firstRoot, ProposedSize(width: 70, height: 50))
        #expect(first.firstFittingChoice(firstView) == 1)
        memo.endFrame()
        let (second, view, chosen, root) = memoTree(memo, generation: 2)
        lay(second, root, ProposedSize(width: 70, height: 50))
        #expect(second.lastNativeLayoutWork.memoRootHits == 1, "the second frame restores the whole placement (verifies: \(verifies))")
        #expect(second.firstFittingChoice(view) == 1, "the choice is restored (verifies: \(verifies))")
        #expect(second.layout(chosen).width == 60)
    }
}

/// And through a restored **subtree** placement (`SB-AD`, a marked root) translated to another origin (`RG-E`): `[A, B]`
/// trailing-aligned, A the marked stack holding the view, B a leaf of 20 then 140, so A's x moves by 20 and A is restored
/// translated, its choice (the 120-wide second candidate at W = 150) with it, and the rects equal a memo-free tree's.
@Test @MainActor func aRestoredSubtreePlacementRestoresTheChoice() throws {
    func build(_ generation: UInt64, bWidth: Double, memo: LayoutMemo?, mark: Bool = true)
        -> (tree: LayoutTree, view: LayoutNodeID, marked: LayoutNodeID, root: LayoutNodeID) {
        let tree = LayoutTree(generation: generation)
        tree.memo = memo
        let view = fits(tree, [keyedFixed(tree, "a", 200), keyedFixed(tree, "b", 120), keyedFixed(tree, "c", 50)])
        let marked = tree.newNativeLinearStack(children: [view], axis: .horizontal, spacing: 0)
        if mark { tree.markPlacementRoot(marked) }
        let b = tree.newNativeLeaf(key: "b\(bWidth)") { proposal in
            LayoutMeasurement(size: SizeD(width: Swift.min(bWidth, proposal.width ?? bWidth), height: 10))
        }
        let root = tree.newNativeLinearStack(children: [marked, b], axis: .vertical, alignment: .trailing)
        return (tree, view, marked, root)
    }
    let proposal = ProposedSize(width: 150, height: 200)
    let container = LayoutRect(x: 0, y: 0, width: 150, height: 200)
    for verifies in [false, true] {
        let memo = LayoutMemo(verifies: verifies)
        let first = build(1, bWidth: 20, memo: memo)
        first.tree.computeNativeLayout(root: first.root, proposal: proposal, centredIn: container)
        #expect(first.tree.firstFittingChoice(first.view) == 1)
        memo.endFrame()
        let second = build(2, bWidth: 140, memo: memo)
        second.tree.computeNativeLayout(root: second.root, proposal: proposal, centredIn: container)
        #expect(second.tree.lastNativeLayoutWork.memoSubtreeHits == 1, "the marked subtree is restored (verifies: \(verifies))")
        #expect(second.tree.firstFittingChoice(second.view) == 1, "the choice is restored (verifies: \(verifies))")
        #expect(second.tree.layout(second.marked).x != first.tree.layout(first.marked).x, "the fixture moved the subtree")
        let fresh = build(3, bWidth: 140, memo: nil, mark: false)
        fresh.tree.computeNativeLayout(root: fresh.root, proposal: proposal, centredIn: container)
        #expect(second.tree.layout(second.view) == fresh.tree.layout(fresh.view), "bit for bit")
        #expect(fresh.tree.firstFittingChoice(fresh.view) == 1)
    }
}

/// A switch is a different subtree even when every rect is equal (`VF-H`): candidate `a` is 50 wide at its ideal and
/// answers 0 x 0 to a proposal, `b` answers 0 x 0 always, so at W = 60 `a` is chosen and at W = 30 `b` is, and every
/// stored rect and measured width is zero in both. Only `subtreeSignatures` (the retained key's hash) can tell the
/// placements apart. Mutation: dropping the choice from `subtreeSignatures` (both variants) leaves the two equal.
@Test @MainActor func aSwitchChangesTheSubtreeSignatureEvenWithEqualRects() throws {
    func signatures(width: Double) -> (relative: Int, absolute: Int, plain: Int, choice: Int?) {
        let tree = LayoutTree(generation: 1)
        let a = tree.newNativeLeaf { proposal in
            LayoutMeasurement(size: proposal.width == nil ? SizeD(width: 50, height: 0) : SizeD(width: 0, height: 0))
        }
        let b = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 0, height: 0)) }
        let view = fits(tree, [a, b])
        tree.computeNativeLayout(root: view, proposal: ProposedSize(width: width, height: 0),
                                 in: LayoutRect(x: 0, y: 0, width: 0, height: 0))
        let both = tree.subtreeSignatures(of: [view], relativeTo: (0, 0))
        return (both.relative, both.absolute, tree.subtreeSignature(of: [view]).hash, tree.firstFittingChoice(view))
    }
    let wide = signatures(width: 60), narrow = signatures(width: 30)
    #expect(wide.choice == 0 && narrow.choice == 1)
    #expect(wide.relative != narrow.relative, "relative")
    #expect(wide.absolute != narrow.absolute, "absolute")
    #expect(wide.plain != narrow.plain, "subtreeSignature(of:)")
}

/// A `Spacer` below a view-that-fits is not marked by the stack around it (`markSpacers` stops, like `.custom`): a spacer
/// candidate keeps its own axis-less answer (the concrete cross proposal, 50), where one directly in the stack answers 0 across.
/// MetalUI's reading of a case SwiftUI's probe did not measure (`VF-J`). Mutation: `markSpacers` walking into a
/// first-fitting node marks the candidate across the stack and its height reads 0.
@Test @MainActor func aSpacerBelowAViewThatFitsIsNotMarkedByTheStackAround() throws {
    let tree = LayoutTree(generation: 1)
    let spacer = tree.newNativeSpacer()
    let view = fits(tree, [spacer])
    let row = tree.newNativeLinearStack(children: [view, candidate(tree, 10, 20)], axis: .horizontal, spacing: 0)
    lay(tree, row, ProposedSize(width: 100, height: 50))
    #expect(tree.layout(spacer).height == 50, "the unmarked spacer takes the concrete cross proposal: \(tree.layout(spacer))")
    let direct = LayoutTree(generation: 1)
    let marked = direct.newNativeSpacer()
    let stack = direct.newNativeLinearStack(children: [marked, candidate(direct, 10, 20)], axis: .horizontal, spacing: 0)
    lay(direct, stack, ProposedSize(width: 100, height: 50))
    #expect(direct.layout(marked).height == 0, "the control: a spacer in the stack itself answers 0 across")
}
