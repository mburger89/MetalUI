import Testing
import MetalUICore
@testable import MetalUILayout

private func px(_ v: Double) -> MetalUICore.Dimension { .length(.pixels(Pixels(Float(v)))) }

private func sized(_ tree: LayoutTree, _ w: Double, _ h: Double,
                   position: Position = .static) -> LayoutNodeID {
    var s = Style()
    s.size = Size(width: px(w), height: px(h))
    s.position = position
    return tree.newNode(style: s, children: [])
}

/// An absolute child contributes nothing to its container's measured size.
///
/// **The absolute child is deliberately LARGER than the in-flow one on both
/// axes.** With a smaller absolute child, "removed from flow" and "included but
/// not the maximum" give identical answers and the test could not tell them
/// apart — the uniformity hazard that hid divergence 6 for four milestones.
@Test func anAbsoluteChildDoesNotContributeToItsContainersSize() {
    let tree = LayoutTree(generation: 0)
    let inFlow = sized(tree, 40, 20)
    let abs = sized(tree, 500, 300, position: .absolute)
    var row = Style()
    row.flexDirection = .row
    let node = tree.newNode(style: row, children: [inFlow, abs])

    let ctx = LayoutContext(rootFontSize: 16)
    let measured = measureNode(ctx, tree, node, known: .unspecified,
                               available: AvailableSpaceSize(width: .maxContent,
                                                             height: .maxContent),
                               containingBlockWidth: nil)
    #expect(measured.width == 40, "the 500-wide absolute child must not count")
    #expect(measured.height == 20, "nor its 300 height")
}

/// The same, for a stack — `layOutStack` is a separate enumeration site and a
/// fix applied to only one of the two is the shape this test exists to catch.
@Test func anAbsoluteChildDoesNotContributeToAStacksSize() {
    let tree = LayoutTree(generation: 0)
    let inFlow = sized(tree, 40, 20)
    let abs = sized(tree, 500, 300, position: .absolute)
    var s = Style()
    s.display = .stack
    s.alignItems = .center
    s.justifyItems = .center
    let node = tree.newNode(style: s, children: [inFlow, abs])

    let ctx = LayoutContext(rootFontSize: 16)
    let measured = measureNode(ctx, tree, node, known: .unspecified,
                               available: AvailableSpaceSize(width: .maxContent,
                                                             height: .maxContent),
                               containingBlockWidth: nil)
    #expect(measured.width == 40)
    #expect(measured.height == 20)
}

/// An absolute child does not shift its in-flow siblings either — it is not
/// merely excluded from the size, it occupies no space on the main axis.
@Test func anAbsoluteChildDoesNotShiftItsInFlowSiblings() {
    let tree = LayoutTree(generation: 0)
    let first = sized(tree, 40, 20)
    let abs = sized(tree, 500, 300, position: .absolute)
    let third = sized(tree, 30, 20)
    var row = Style()
    row.flexDirection = .row
    let node = tree.newNode(style: row, children: [first, abs, third])

    computeLayout(tree, root: node,
                  available: AvailableSpaceSize(width: .definite(400),
                                                height: .definite(100)))
    #expect(tree.layout(first).x == 0)
    #expect(tree.layout(third).x == 40, "not 540 — the absolute child takes no room")
}

/// An absolute child is placed against the nearest NON-STATIC ancestor, not its
/// parent.
///
/// **The parent is deliberately `.static` and offset from the containing
/// block.** A fixture where the parent *is* the containing block cannot
/// distinguish "walked the chain" from "used the parent" — and using the parent
/// is exactly the wrong implementation this test exists to catch.
@Test func anAbsoluteChildIsPlacedAgainstTheNearestNonStaticAncestor() {
    let tree = LayoutTree(generation: 0)
    let abs = sized(tree, 20, 10, position: .absolute)

    // A static wrapper, pushed away from the origin by a sibling.
    var staticWrapper = Style()
    staticWrapper.flexDirection = .row
    let wrapper = tree.newNode(style: staticWrapper, children: [abs])

    let spacer = sized(tree, 60, 10)

    // The containing block: relative, so it qualifies. `border`, not
    // `padding` — the padding box (spec §3.3) excludes the border but is
    // NOT pushed inward by the container's own padding (that is exactly what
    // `theContainingBlockIsThePaddingBoxNotTheBorderBox` below proves: with
    // border 7 / padding 3 the child lands at x==7, border alone). A first
    // draft of this fixture used `padding` here, which shifts the in-flow
    // content origin identically to `border` (so the wrapper/spacer sanity
    // check below is unchanged either way) but leaves the PADDING box's own
    // origin untouched at (0, 0) — silently testing the wrong box. `border`
    // is what actually moves the containing block off the origin.
    var cb = Style()
    cb.flexDirection = .row
    cb.position = .relative
    cb.border = Edges(all: .pixels(Pixels(5)))
    let containingBlock = tree.newNode(style: cb, children: [spacer, wrapper])

    // An outer `.static` wrapper, so `containingBlock` is NOT the tree's own
    // root. Without this, `computeLayout`'s root-seeding path coincidentally
    // computes the same box `containingBlock` would compute for itself —
    // masking a mutation that skips the non-static recomputation entirely
    // and always reuses the threaded-in value (mutation 1 in the task's
    // required-mutations list). Measured: with `containingBlock` AS the
    // root, that mutation reddened nothing in the whole 544-test suite.
    var outer = Style()
    outer.flexDirection = .row
    let root = tree.newNode(style: outer, children: [containingBlock])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(200),
                                                height: .definite(100)))

    // The wrapper sits at x = 65 (5 border + 60 spacer). The absolute child
    // must ignore that and land on the containing block's PADDING box: (5, 5).
    #expect(tree.layout(wrapper).x == 65, "sanity: the static wrapper is offset")
    #expect(tree.layout(abs).x == 5, "not 65 — placed against the containing block")
    #expect(tree.layout(abs).y == 5)
}

/// With no non-static ancestor, the root is the containing block.
@Test func withNoPositionedAncestorTheRootIsTheContainingBlock() {
    let tree = LayoutTree(generation: 0)
    let abs = sized(tree, 20, 10, position: .absolute)
    let spacer = sized(tree, 60, 10)
    var row = Style()
    row.flexDirection = .row
    let inner = tree.newNode(style: row, children: [spacer, abs])
    var outer = Style()
    outer.flexDirection = .row
    let node = tree.newNode(style: outer, children: [inner])

    computeLayout(tree, root: node,
                  available: AvailableSpaceSize(width: .definite(200),
                                                height: .definite(100)))
    #expect(tree.layout(abs).x == 0)
    #expect(tree.layout(abs).y == 0)
}

/// The containing block is the ancestor's PADDING box, not its border box.
/// Getting this wrong shifts every absolute child by the border width — a
/// small uniform error that reads as a rounding problem rather than a bug.
@Test func theContainingBlockIsThePaddingBoxNotTheBorderBox() {
    let tree = LayoutTree(generation: 0)
    let abs = sized(tree, 20, 10, position: .absolute)
    var cb = Style()
    cb.position = .relative
    cb.border = Edges(all: .pixels(Pixels(7)))
    cb.padding = Edges(all: .pixels(Pixels(3)))
    let node = tree.newNode(style: cb, children: [abs])

    computeLayout(tree, root: node,
                  available: AvailableSpaceSize(width: .definite(200),
                                                height: .definite(100)))
    // Padding box starts inside the border: 7, not 0 and not 10.
    #expect(tree.layout(abs).x == 7)
    #expect(tree.layout(abs).y == 7)
}
