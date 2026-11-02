import Testing
import MetalUICore
@testable import MetalUILayout

// R3-10 item 4 (`LD-A`, `LD-B`): a node registered while `registersRightToLeft` is set reflects each child's
// rect about the middle of its own bounds at placement. Every figure is SwiftUI's, read by
// `docs/probes/swiftui-layout-direction.swift` (header holds the recorded output): arm A1 `HStack` 0/10 -> 90/70,
// B frame alignments, C1 `ZStack`, D1 overlay, E padding, H1 `VStack`, I1 custom layout, J1 `Grid`, K1 a left-to-right
// container nested in a right-to-left one, L1 a horizontal scroller. Each test runs the left-to-right tree first
// (the separating arm: nothing moves) and the right-to-left one second. Each names the mutation that must redden it;
// the mutation table is in record 191.

@MainActor private func leaf(_ tree: LayoutTree, _ width: Double, _ height: Double = 10) -> LayoutNodeID {
    tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: width, height: height)) }
}

/// The x of each probe after laying `build`'s root out at 100 x 40, with the tree registering right-to-left or not.
@MainActor private func xs(rtl: Bool, _ build: (LayoutTree) -> (root: LayoutNodeID, probes: [LayoutNodeID])) -> [Double] {
    let tree = LayoutTree(generation: 1)
    tree.registersRightToLeft = rtl
    let (root, probes) = build(tree)
    tree.computeNativeLayout(root: root, proposal: ProposedSize(width: 100, height: 40),
                             in: LayoutRect(x: 0, y: 0, width: 100, height: 40))
    return probes.map { tree.layout($0).x }
}

/// A frame of width 100 whose child sits at its leading edge: the probe's `.frame(width: 100, alignment: .leading)`.
@MainActor private func leadingFrame(_ tree: LayoutTree, _ child: LayoutNodeID) -> LayoutNodeID {
    tree.newNativeFrame(child: child, width: 100, alignment: .leading)
}

/// A1: `HStack(spacing: 0) { 10; 20 }` is 0/10 and mirrors to 90/70; A2: spacing 5 is 0/15 and 90/65.
/// **Mutation:** `place(child, childBounds, solution.proposals[index])` in the `.linearStack` arm of `placeNative`
/// written `placeNative(child, in: childBounds, ...)` (the flip skipped for stacks).
@Test @MainActor func aRightToLeftHStackReversesItsChildren() {
    for (spacing, ltr, rtl) in [(0.0, [0.0, 10], [90.0, 70]), (5.0, [0.0, 15], [90.0, 65])] {
        func build(_ tree: LayoutTree) -> (root: LayoutNodeID, probes: [LayoutNodeID]) {
            let a = leaf(tree, 10), b = leaf(tree, 20)
            let stack = tree.newNativeLinearStack(children: [a, b], axis: .horizontal, spacing: spacing)
            return (leadingFrame(tree, stack), [a, b])
        }
        #expect(xs(rtl: false, build) == ltr, "left-to-right, spacing \(spacing)")
        #expect(xs(rtl: true, build) == rtl, "right-to-left, spacing \(spacing)")
    }
}

/// The reflection is about the middle of the parent's own bounds, not the origin: the same `HStack` placed at x = 40
/// (the stack 30 wide at 70...100 inside a frame at 40...140 and 100 wide) is at 130/110, 40 more than at the origin.
/// **Mutation:** `mirroredChildRect` without its `2 * bounds.x` term.
@Test @MainActor func aMirroredChildIsReflectedAboutItsParentsBoundsAndNotTheOrigin() {
    func positions(rtl: Bool, originX: Double) -> [Double] {
        let tree = LayoutTree(generation: 1)
        tree.registersRightToLeft = rtl
        let a = leaf(tree, 10), b = leaf(tree, 20)
        let stack = tree.newNativeLinearStack(children: [a, b], axis: .horizontal, spacing: 0)
        let root = leadingFrame(tree, stack)
        tree.computeNativeLayout(root: root, proposal: ProposedSize(width: 100, height: 40),
                                 in: LayoutRect(x: originX, y: 0, width: 100, height: 40))
        return [tree.layout(a).x, tree.layout(b).x]
    }
    #expect(positions(rtl: true, originX: 0) == [90, 70])
    #expect(positions(rtl: true, originX: 40) == [130, 110])
    #expect(positions(rtl: false, originX: 40) == [40, 50])
}

/// B1-B3: a leading frame puts the child at 0 (right edge under RTL: 90), trailing 90 -> 0, centre 45 both.
/// **Mutation:** the `.frame` arm's `place(child, ...)` written `placeNative(child, in: ...)`.
@Test @MainActor func aRightToLeftFrameMirrorsLeadingAndTrailingAndLeavesCentre() {
    let cases: [(ProposalAlignment, Double, Double)] = [(.leading, 0, 90), (.trailing, 90, 0), (.center, 45, 45)]
    for (alignment, ltr, rtl) in cases {
        func build(_ tree: LayoutTree) -> (root: LayoutNodeID, probes: [LayoutNodeID]) {
            let a = leaf(tree, 10)
            return (tree.newNativeFrame(child: a, maxWidth: .infinity, alignment: alignment), [a])
        }
        #expect(xs(rtl: false, build) == [ltr], "left-to-right \(alignment)")
        #expect(xs(rtl: true, build) == [rtl], "right-to-left \(alignment)")
    }
}

/// C1: `ZStack(alignment: .leading)` of a 30 and a 10 leaf: both at 0, then both against the right edge (70, 90).
/// **Mutation:** the `.overlay` arm's `place(child, ...)` written `placeNative(child, in: ...)`.
@Test @MainActor func aRightToLeftZStackAlignsItsLeadingEdgeToTheRight() {
    func build(_ tree: LayoutTree) -> (root: LayoutNodeID, probes: [LayoutNodeID]) {
        let a = leaf(tree, 30), b = leaf(tree, 10)
        return (leadingFrame(tree, tree.newNativeOverlay(children: [a, b], alignment: .leading)), [a, b])
    }
    #expect(xs(rtl: false, build) == [0, 0])
    #expect(xs(rtl: true, build) == [70, 90])
}

/// D1/D2: an overlay or background attached at `.leading` moves to the right (90) and the base it is attached to
/// does not move (0). A separate test from the `ZStack` above: it is a separate placement site (`OM-AI`).
/// **Mutation:** the `.overlayAttachment` arm's overlay placement written `placeNative(overlay, in: ...)` reddens the
/// overlay figure; its primary placement written the same way reddens nothing here (a primary placed in its own
/// bounds reflects onto itself) and is recorded as such in record 191.
@Test @MainActor func aRightToLeftOverlayAttachmentMovesTheOverlayAndNotTheBase() {
    func build(_ tree: LayoutTree) -> (root: LayoutNodeID, probes: [LayoutNodeID]) {
        let base = leaf(tree, 100, 40), badge = leaf(tree, 10)
        return (tree.newNativeOverlayAttachment(child: base, overlay: badge, alignment: .leading), [base, badge])
    }
    #expect(xs(rtl: false, build) == [0, 0])
    #expect(xs(rtl: true, build) == [0, 90])
}

/// E1/E2: `padding(.leading, 10)` around a 10 leaf puts the child at 10 (80 under RTL: the pad is on the right);
/// `padding(.trailing, 10)` puts it at 0 (90). **Mutation:** the `.padding` arm's `place(child, ...)` written
/// `placeNative(child, in: ...)`.
@Test @MainActor func aRightToLeftPaddingPutsTheLeadingInsetOnTheRight() {
    let leading: Edges<Double> = Edges(top: 0, right: 0, bottom: 0, left: 10)
    let trailing: Edges<Double> = Edges(top: 0, right: 10, bottom: 0, left: 0)
    for (insets, ltr, rtl) in [(leading, 10.0, 80.0), (trailing, 0.0, 90.0)] {
        func build(_ tree: LayoutTree) -> (root: LayoutNodeID, probes: [LayoutNodeID]) {
            let a = leaf(tree, 10)
            let padded = tree.newNativePadding(child: a, insets: insets)
            return (tree.newNativeFrame(child: padded, maxWidth: .infinity, alignment: .leading), [a])
        }
        #expect(xs(rtl: false, build) == [ltr])
        #expect(xs(rtl: true, build) == [rtl])
    }
}

/// H1: `VStack(alignment: .leading)` of a 10 and a 30 leaf: 0/0, then 90/70 (the stack is 30 wide at 70..100 and
/// each child is leading-aligned inside it). **Mutation:** as for the horizontal stack (the shared `place`).
@Test @MainActor func aRightToLeftVStackAlignsItsCrossAxisToTheRight() {
    func build(_ tree: LayoutTree) -> (root: LayoutNodeID, probes: [LayoutNodeID]) {
        let a = leaf(tree, 10), b = leaf(tree, 30)
        let stack = tree.newNativeLinearStack(children: [a, b], axis: .vertical, spacing: 0, alignment: .leading)
        return (tree.newNativeFrame(child: stack, maxWidth: .infinity, alignment: .leading), [a, b])
    }
    #expect(xs(rtl: false, build) == [0, 0])
    #expect(xs(rtl: true, build) == [90, 70])
}

/// A custom layout packing from the left (probe I1): 0/10 and 90/70. **Mutation:** `placeCustom`'s recorded-child
/// branch written without the `flip` (`placeNative(child, in: rect, ...)`).
private struct LeftPacked: ProposalLayout, Hashable {
    func sizeThatFits(proposal: ProposedSize, subviews: MeasurementSubviews) -> LayoutMeasurement {
        let widths = (0..<subviews.count).map { subviews[$0].sizeThatFits(.unspecified).size.width }
        return LayoutMeasurement(size: SizeD(width: widths.reduce(0, +), height: 10))
    }
    func placeSubviews(in bounds: LayoutRect, proposal: ProposedSize, subviews: PlacementSubviews) {
        var x = bounds.x
        for index in 0..<subviews.count {
            subviews[index].place(at: Point(x: x, y: bounds.y), anchor: .topLeading, proposal: .unspecified)
            x += subviews[index].sizeThatFits(.unspecified).size.width
        }
    }
}

@Test @MainActor func aRightToLeftCustomLayoutMirrorsWhatItPlacedFromTheLeft() {
    func build(_ tree: LayoutTree) -> (root: LayoutNodeID, probes: [LayoutNodeID]) {
        let a = leaf(tree, 10), b = leaf(tree, 20)
        let custom = tree.newNativeLayout(LeftPacked(), children: [a, b])
        return (tree.newNativeFrame(child: custom, maxWidth: .infinity, alignment: .leading), [a, b])
    }
    #expect(xs(rtl: false, build) == [0, 10])
    #expect(xs(rtl: true, build) == [90, 70])
}

/// A custom layout that records nothing for a child: the unrecorded child is centred and mirrors onto itself, and
/// stays where it was. Pins the second `flip` site of `placeCustom` as a no-op that must not move a centred child.
private struct PlacesNothing: ProposalLayout, Hashable {
    func sizeThatFits(proposal: ProposedSize, subviews: MeasurementSubviews) -> LayoutMeasurement {
        LayoutMeasurement(size: SizeD(width: 40, height: 10))
    }
    func placeSubviews(in bounds: LayoutRect, proposal: ProposedSize, subviews: PlacementSubviews) {}
}

@Test @MainActor func anUnrecordedChildOfARightToLeftCustomLayoutStaysCentred() {
    func build(_ tree: LayoutTree) -> (root: LayoutNodeID, probes: [LayoutNodeID]) {
        let a = leaf(tree, 10)
        let custom = tree.newNativeLayout(PlacesNothing(), children: [a])
        return (tree.newNativeFrame(child: custom, maxWidth: .infinity, alignment: .leading), [a])
    }
    #expect(xs(rtl: false, build) == [15])
    #expect(xs(rtl: true, build) == [75], "the 40 wide layout is at 60..100 and its centred child at 75")
}

/// J1: `Grid { GridRow { 10; 20 } }`: 0/10 and 90/70. **Mutation:** `placeGrid`'s `flip ? ... : placement.rect`
/// written `placement.rect`.
@Test @MainActor func aRightToLeftGridReversesItsColumns() {
    func build(_ tree: LayoutTree) -> (root: LayoutNodeID, probes: [LayoutNodeID]) {
        let a = leaf(tree, 10), b = leaf(tree, 20)
        tree.markNativeGridRow([a, b])
        let grid = tree.newNativeGrid(children: [a, b], horizontalSpacing: 0)
        return (tree.newNativeFrame(child: grid, maxWidth: .infinity, alignment: .leading), [a, b])
    }
    #expect(xs(rtl: false, build) == [0, 10])
    #expect(xs(rtl: true, build) == [90, 70])
}

/// K1: a left-to-right `HStack` nested in a right-to-left one keeps its own order inside its mirrored box; the
/// PARENT's direction decides where the box goes (`na 90`, inner box 60..90 holding 60/70, `nb 50`).
/// **Mutation:** `registersRightToLeft` left set while the inner stack registers (the inner `Frame` environment
/// scope not restoring the flag) reddens it: the inner pair would read 80/60.
@Test @MainActor func aLeftToRightStackInsideARightToLeftOneKeepsItsOwnOrder() {
    func build(_ tree: LayoutTree, rtl: Bool) -> (root: LayoutNodeID, probes: [LayoutNodeID]) {
        let outerFlag = tree.registersRightToLeft
        tree.registersRightToLeft = false
        let ia = leaf(tree, 10), ib = leaf(tree, 20)
        let inner = tree.newNativeLinearStack(children: [ia, ib], axis: .horizontal, spacing: 0)
        tree.registersRightToLeft = outerFlag
        let na = leaf(tree, 10), nb = leaf(tree, 10)
        let outer = tree.newNativeLinearStack(children: [na, inner, nb], axis: .horizontal, spacing: 0)
        return (leadingFrame(tree, outer), [na, ia, ib, nb])
    }
    #expect(xs(rtl: false, { build($0, rtl: false) }) == [0, 10, 20, 40])
    #expect(xs(rtl: true, { build($0, rtl: true) }) == [90, 60, 70, 50])
}

/// L1: a horizontal scroll viewport over a 300 wide content in 100: the content opens at the leading (right) edge,
/// its minX -200 (the viewport mirrors the content's rect about its own middle), and its first child at 90.
/// **Mutation:** the `.scrollViewport` arm's `place(child, ...)` written `placeNative(child, in: ...)`.
@Test @MainActor func aRightToLeftHorizontalScrollViewportOpensAtItsTrailingEnd() {
    func build(_ tree: LayoutTree) -> (root: LayoutNodeID, probes: [LayoutNodeID]) {
        let first = leaf(tree, 10), rest = leaf(tree, 290)
        let content = tree.newNativeLinearStack(children: [first, rest], axis: .horizontal, spacing: 0)
        return (tree.newNativeScrollViewport(child: content, axis: .horizontal), [content, first])
    }
    #expect(xs(rtl: false, build) == [0, 0])
    #expect(xs(rtl: true, build) == [-200, 90])
}

/// The wrappers that place a child at their own origin (`fixedSize`, `aspectRatio`, `layoutPriority`) mirror it too.
/// **Mutation:** any of the three arms' `place(child, ...)` written `placeNative(child, in: ...)` reddens its row.
@Test @MainActor func aRightToLeftFixedSizeAspectRatioAndPriorityWrappersMirrorTheirChild() {
    let wrappers: [(String, (LayoutTree, LayoutNodeID) -> LayoutNodeID)] = [
        ("fixedSize", { $0.newNativeFixedSize(child: $1, horizontal: true, vertical: true) }),
        ("aspectRatio", { $0.newNativeAspectRatio(child: $1, ratio: 2, contentMode: .fit) }),
        ("layoutPriority", { $0.newNativeLayoutPriority(child: $1, priority: 1) }),
    ]
    for (name, wrap) in wrappers {
        func build(_ tree: LayoutTree) -> (root: LayoutNodeID, probes: [LayoutNodeID]) {
            let a = leaf(tree, 20, 10)
            let wrapped = wrap(tree, a)
            return (tree.newNativeFrame(child: wrapped, maxWidth: .infinity, alignment: .trailing), [a])
        }
        // A trailing frame puts the 20 wide child at 80; the wrapper is the same size, so mirroring about its own
        // bounds leaves it on itself: the probe is that the wrapper does not DISPLACE it (80 -> 0 under RTL).
        #expect(xs(rtl: false, build) == [80], "\(name) left-to-right")
        #expect(xs(rtl: true, build) == [0], "\(name) right-to-left")
    }
}

/// Mirroring is placement only: the same tree measures and places the same amount of work either way, and answers
/// the same size. A branching tree (a stack of a frame, a padded leaf and a nested stack), so a mirror that
/// re-measured would show. **Red before:** none needed, it must arrive green; **mutation:** `mirroredChildRect`
/// calling `measureNative` on the child reddens it.
@Test @MainActor func mirroringDoesTheSameMeasurementWorkAsLeftToRight() {
    func work(rtl: Bool) -> (NativeLayoutWork, SizeD) {
        let tree = LayoutTree(generation: 1)
        tree.registersRightToLeft = rtl
        let a = leaf(tree, 10), b = leaf(tree, 20), c = leaf(tree, 15), d = leaf(tree, 5)
        let padded = tree.newNativePadding(child: b, insets: Edges(top: 1, right: 2, bottom: 1, left: 3))
        let nested = tree.newNativeLinearStack(children: [c, d], axis: .horizontal, spacing: 2)
        let framed = tree.newNativeFrame(child: a, width: 30, alignment: .leading)
        let root = tree.newNativeLinearStack(children: [framed, padded, nested], axis: .horizontal, spacing: 4)
        let measurement = tree.computeNativeLayout(root: root, proposal: ProposedSize(width: 200, height: 40),
                                                   in: LayoutRect(x: 0, y: 0, width: 200, height: 40))
        return (tree.lastNativeLayoutWork, measurement.size)
    }
    let (ltr, ltrSize) = work(rtl: false)
    let (rtl, rtlSize) = work(rtl: true)
    #expect(ltr.measureCalls > 0 && ltr.cacheMisses > 0, "the arm does work")
    #expect(ltr == rtl)
    #expect(ltrSize == rtlSize)
}

/// A node registered after the flag is cleared carries no mark, whatever registered before it (`LD-B`): its
/// signature equals the one it has in a tree that never set the flag, and differs from a marked one.
/// **Mutation:** `appendNode` inserting unconditionally (`rightToLeftNodes.insert(...)` outside the `if`).
@Test @MainActor func aNodeRegisteredLeftToRightAfterARightToLeftOneIsNotMarked() {
    func signature(afterRightToLeft: Bool, marked: Bool) -> LayoutSignature? {
        let tree = LayoutTree(generation: 1)
        if afterRightToLeft { tree.registersRightToLeft = true; _ = tree.newNativeSpacer(); tree.registersRightToLeft = false }
        tree.registersRightToLeft = marked
        let node = tree.newNativeSpacer()
        return tree.structuralSignature(of: node)
    }
    #expect(signature(afterRightToLeft: true, marked: false) == signature(afterRightToLeft: false, marked: false))
    #expect(signature(afterRightToLeft: false, marked: true) != signature(afterRightToLeft: false, marked: false))
}

/// `reset(generation:)` clears the marks: a reused tree's first node registers unmarked once the flag is cleared.
/// **Mutation:** `rightToLeftNodes.removeAll` dropped from `reset(generation:)`.
@Test @MainActor func resettingATreeClearsItsRightToLeftMarks() {
    let tree = LayoutTree(generation: 1)
    tree.registersRightToLeft = true
    let marked = tree.newNativeSpacer()
    let markedSignature = tree.structuralSignature(of: marked)
    tree.reset(generation: 2)
    tree.registersRightToLeft = false
    let fresh = tree.newNativeSpacer()
    #expect(fresh.index == marked.index, "the same index is reused")
    #expect(tree.structuralSignature(of: fresh) != markedSignature)
}

// MARK: - The memo and the graft

private let big = ProposedSize(width: 200, height: 200)
private let bounds200 = LayoutRect(x: 0, y: 0, width: 200, height: 200)

private func keyed(_ tree: LayoutTree, _ key: String, width: Double = 20, height: Double = 10) -> LayoutNodeID {
    tree.newNativeLeaf(key: key) { proposal in
        LayoutMeasurement(size: SizeD(width: Swift.min(width, proposal.width ?? width), height: height))
    }
}

/// `[A, B]`: A (a horizontal stack of two keyed leaves, a placement root) over B, leading-aligned.
@MainActor private func tower(generation: UInt64, rtl: Bool, bWidth: Double, memo: LayoutMemo?)
    -> (tree: LayoutTree, root: LayoutNodeID, a: LayoutNodeID, leaves: [LayoutNodeID]) {
    let tree = LayoutTree(generation: generation)
    tree.memo = memo
    tree.registersRightToLeft = rtl
    let a1 = keyed(tree, "a1", width: 30), a2 = keyed(tree, "a2", width: 40)
    let a = tree.newNativeLinearStack(children: [a1, a2], axis: .horizontal)
    tree.markPlacementRoot(a)
    let b = keyed(tree, "b\(bWidth)", width: bWidth)
    let root = tree.newNativeLinearStack(children: [a, b], axis: .vertical, alignment: .topLeading)
    return (tree, root, a, [a1, a2])
}

/// A placement root is not restored across a direction flip (`LD-B`): the second frame's tree has the same shape,
/// the same leaf keys, the same proposal and bounds, and the other direction. The separating arm is the same
/// direction twice, which restores (one subtree hit). **Mutation:** the `nodeSignature` tag line removed.
@Test @MainActor func aPlacementRootIsNotRestoredAcrossADirectionFlip() throws {
    func secondFrame(firstRTL: Bool, secondRTL: Bool) -> (hits: Int, xs: [Double]) {
        let memo = LayoutMemo()
        let first = tower(generation: 1, rtl: firstRTL, bWidth: 30, memo: memo)
        first.tree.computeNativeLayout(root: first.root, proposal: big, in: bounds200)
        memo.endFrame()
        // B's width changes so the root's own memo cannot answer: only the placement root can.
        let second = tower(generation: 2, rtl: secondRTL, bWidth: 45, memo: memo)
        second.tree.computeNativeLayout(root: second.root, proposal: big, in: bounds200)
        return (second.tree.lastNativeLayoutWork.memoSubtreeHits, second.leaves.map { second.tree.layout($0).x })
    }
    let same = secondFrame(firstRTL: true, secondRTL: true)
    #expect(same.hits == 1, "the separating arm: the same direction restores")
    let flipped = secondFrame(firstRTL: false, secondRTL: true)
    #expect(flipped.hits == 0)
    #expect(flipped.xs == same.xs, "and the placed rects are the right-to-left ones")
    #expect(flipped.xs == [170, 130], "the 70 wide A at the 200 wide root's right edge, its leaves reversed inside it")
    let back = secondFrame(firstRTL: true, secondRTL: false)
    #expect(back.hits == 0)
    #expect(back.xs == [0, 30])
}

/// `captureSegment` carries the marks and `graft` copies them, never the current flag (`LD-B`): a segment captured
/// under right-to-left and grafted into a tree whose flag is clear still mirrors, and a left-to-right segment
/// grafted while the flag is set does not. The grafted tree equals a fresh build in its digest (`rtl` included).
/// **Mutation:** `graft`'s `rightToLeft` loop removed (the first arm reddens), or replaced by
/// `if registersRightToLeft { insert }` (the second arm reddens).
@Test @MainActor func aGraftCarriesTheDirectionItWasCapturedUnder() throws {
    func content(_ tree: LayoutTree) -> LayoutNodeID {
        let a = keyed(tree, "ga", width: 10), b = keyed(tree, "gb", width: 20)
        return tree.newNativeLinearStack(children: [a, b], axis: .horizontal, spacing: 0)
    }
    func segment(rtl: Bool) throws -> LayoutSegment {
        let source = LayoutTree(generation: 1)
        source.registersRightToLeft = rtl
        let top = content(source)
        return try #require(source.captureSegment(from: 0, tops: [top]).segment)
    }
    func grafted(_ segment: LayoutSegment, flag: Bool) -> (xs: [Double], digest: [String]) {
        let target = LayoutTree(generation: 2)
        target.registersRightToLeft = flag
        let tops = target.graft(segment)
        let frame = target.newNativeFrame(child: tops[0], width: 100, alignment: .leading)
        target.computeNativeLayout(root: frame, proposal: ProposedSize(width: 100, height: 40),
                                   in: LayoutRect(x: 0, y: 0, width: 100, height: 40))
        return (target.children(tops[0]).map { target.layout($0).x }, target.structureDigest())
    }
    let rightToLeft = try segment(rtl: true), leftToRight = try segment(rtl: false)
    // The wrapping frame is registered by the target after the graft, under the target's own flag.
    let mirroredGraft = grafted(rightToLeft, flag: false)
    #expect(mirroredGraft.xs == [20, 0], "the 30 wide stack at 0..30 holds 20, 0: mirrored inside its own box")
    #expect(grafted(leftToRight, flag: true).xs == [70, 80], "a left-to-right segment is not mirrored by the flag at graft time")
    #expect(grafted(leftToRight, flag: false).xs == [0, 10])
    // The grafted tree equals a fresh build of the same content, `rtl` marks included.
    let fresh = LayoutTree(generation: 2)
    fresh.registersRightToLeft = true
    let freshTop = content(fresh)
    fresh.registersRightToLeft = false
    let freshFrame = fresh.newNativeFrame(child: freshTop, width: 100, alignment: .leading)
    fresh.computeNativeLayout(root: freshFrame, proposal: ProposedSize(width: 100, height: 40),
                              in: LayoutRect(x: 0, y: 0, width: 100, height: 40))
    #expect(mirroredGraft.digest == fresh.structureDigest())
    #expect(mirroredGraft.digest.contains { $0.contains("|rtl") })
    #expect(!grafted(leftToRight, flag: true).digest.dropLast().contains { $0.contains("|rtl") })
}
