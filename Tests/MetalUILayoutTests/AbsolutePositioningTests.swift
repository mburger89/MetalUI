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
