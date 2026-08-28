import Testing
import Foundation
import MetalUICore
@testable import MetalUILayout

/// **The oracle is CSS grid's one-cell layout**, not a stack — because CSS has
/// no stack. `display: grid` with every child at `grid-area: 1 / 1` sizes the
/// container to the largest item and overlaps them all, which is exactly what
/// `Display.stack` must do.
///
/// **Nothing checks that the HTML and the Swift tree describe the same layout.**
/// That is true of all 67 fixtures here, but flex-HTML against flex-`Style` is a
/// small conceptual gap and grid-HTML against stack-`Style` is a larger one: a
/// reader has to know the two are *intended* to be equivalent. They are, and the
/// mapping is: `display: grid` + `grid-area: 1/1` on every child ⇒
/// `display: .stack`; `justify-items` ⇒ `justifyItems`; `align-items` ⇒
/// `alignItems`.
///
/// **Every fixture states `justify-items` and `align-items` explicitly**, because
/// grid defaults both to `stretch` while `Stack` centres (spec §2). A fixture
/// relying on grid's defaults measures the wrong thing and reads as an engine bug.
///
/// **`stack_stretch` needed one more correction beyond the mapping above, and
/// it found a real engine bug rather than only a fixture wrinkle.** CSS Box
/// Alignment's `stretch` only fills the cell when the item's own width/height
/// is `auto` — a box with an explicit size falls back to `start` and keeps its
/// declared size. Verified directly against this repo's own `LayoutOracle`
/// before committing the fixture: a 20x10 child under `justify-items: stretch;
/// align-items: stretch` measures 20x10 at (0,0), not 300x200.
/// `positionStackItems` (`FlexEngine.swift`) used to carry no such carve-out —
/// it overrode a stretched item's size unconditionally. `stack_stretch.html`'s
/// child is unsized so it exercises the auto branch cleanly, but that alone
/// was a workaround, not a fix: `Stack` becomes `StyledElement`-reachable in
/// Task 5, so `Stack { Box().width(20).height(10) }.alignItems(.stretch)`
/// would have compiled and silently disagreed with WebKit. **Fix round 1
/// closed it**: `positionStackItems` now stretches an axis only when
/// `tree.style(item.node)`'s size on that axis is `.auto`, and
/// `stack_stretch_declared_size.html`/`stackStretchDeclaredSizeMatchesWebKit`
/// below pin the declared-size branch `stack_stretch` cannot reach.
///
/// **`stack_sizes_to_largest` needed a structural correction too** (controller
/// ruling PF-2), and it is why this fixture's tree has two levels where the
/// other four have one. The stack itself declares no size and is a child of a
/// fixed-size flex root instead of being the document root: a declared size on
/// the stack would assert nothing about max-over-children (every candidate
/// implementation gives the declared size back), and an `auto`-sized document
/// root would hit this engine's own divergence 4 — an `auto` root axis takes
/// the space it is offered rather than shrink-wrapping — for a reason
/// unconnected to stacking at all.
private func px(_ v: Double) -> MetalUICore.Dimension { .length(.pixels(Pixels(Float(v)))) }

private func sized(_ tree: LayoutTree, _ w: Double, _ h: Double) -> LayoutNodeID {
    var s = Style()
    s.size = Size(width: px(w), height: px(h))
    return tree.newNode(style: s, children: [])
}

private func stackNode(_ tree: LayoutTree, _ children: [LayoutNodeID],
                       align: AlignItems, justify: JustifyItems,
                       size: Size<MetalUICore.Dimension>? = nil) -> LayoutNodeID {
    var s = Style()
    s.display = .stack
    s.alignItems = align
    s.justifyItems = justify
    if let size { s.size = size }
    return tree.newNode(style: s, children: children)
}

/// The three alignment fixtures' shared geometry: a 300x200 stack holding one
/// 20x10 child. Sharing this builder is what keeps the three a differential —
/// same root, same child, only the alignment changes.
private func alignmentTree(align: AlignItems, justify: JustifyItems)
    -> (LayoutTree, root: LayoutNodeID, child: LayoutNodeID) {
    let tree = LayoutTree(generation: 0)
    let child = sized(tree, 20, 10)
    let root = stackNode(tree, [child], align: align, justify: justify,
                         size: Size(width: px(300), height: px(200)))
    return (tree, root, child)
}

/// `justify-items: center; align-items: center` — both axes' slack split
/// evenly. Catches an implementation that centres on only one axis, or that
/// swaps `alignItems`/`justifyItems`'s axes (20x10 is not square, so a swap
/// would still move the child, just to the wrong one of the nine positions).
@Test func stackAlignmentCenterMatchesWebKit() throws {
    let golden = try loadGolden("stack_alignment_center")
    let (tree, root, child) = alignmentTree(align: .center, justify: .center)
    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))
    assertMatchesGolden(tree, ids: [root: "root", child: "child"], golden: golden, tolerance: 0.1)
}

/// `justify-items: start; align-items: start` — the child at the container's
/// leading edge on both axes. Catches an implementation that always centres
/// regardless of `alignItems`/`justifyItems`, or that reads `flexStart` as some
/// other axis's start.
@Test func stackAlignmentTopLeadingMatchesWebKit() throws {
    let golden = try loadGolden("stack_alignment_topleading")
    let (tree, root, child) = alignmentTree(align: .flexStart, justify: .start)
    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))
    assertMatchesGolden(tree, ids: [root: "root", child: "child"], golden: golden, tolerance: 0.1)
}

/// `justify-items: end; align-items: end` — the child at the container's
/// trailing edge on both axes. Together with the two fixtures above, the three
/// alignments produce three distinct positions from identical geometry — the
/// differential this milestone's spec requires, and the shape that catches an
/// implementation that only ever returns one fixed corner.
@Test func stackAlignmentBottomTrailingMatchesWebKit() throws {
    let golden = try loadGolden("stack_alignment_bottomtrailing")
    let (tree, root, child) = alignmentTree(align: .flexEnd, justify: .end)
    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))
    assertMatchesGolden(tree, ids: [root: "root", child: "child"], golden: golden, tolerance: 0.1)
}

/// `justify-items: stretch; align-items: stretch` fills the container on both
/// axes — 300x200, not the child's own 20x10-shaped nothing. This is the
/// "stretch differential" spec §6 requires: it is the one place CSS's real
/// default (stretch) and this framework's real default (centre, `nil` reads as
/// stretch only when written literally) disagree, so an implementation that
/// silently took CSS's default instead of SwiftUI's would pass every other
/// fixture in this file and only fail here. See the file header for why this
/// child, alone among the four alignment fixtures, is unsized.
@Test func stackStretchMatchesWebKit() throws {
    let golden = try loadGolden("stack_stretch")
    let tree = LayoutTree(generation: 0)
    // Deliberately unsized — see the file header.
    let child = tree.newNode(style: Style(), children: [])
    let root = stackNode(tree, [child], align: .stretch, justify: .stretch,
                         size: Size(width: px(300), height: px(200)))
    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))
    assertMatchesGolden(tree, ids: [root: "root", child: "child"], golden: golden, tolerance: 0.1)
}

/// `justify-items: stretch; align-items: stretch` again, but with a
/// **declared** 20x10 child rather than the unsized one above — the other
/// half of the stretch rule, added in this milestone's fix round 1 after the
/// task's own oracle probe found `positionStackItems` stretching a declared
/// size unconditionally. CSS Box Alignment's `stretch` fills an axis only
/// when the item's own size on it is `auto`; a declared size falls back to
/// `start` and keeps its own value. `stackStretchMatchesWebKit` above cannot
/// see this branch at all — its child has no declared size to keep — and this
/// one cannot see that branch, so the two are each other's negative control:
/// mutating the `widthIsAuto`/`heightIsAuto` guard back to unconditional in
/// `positionStackItems` reddens this test alone and leaves
/// `stackStretchMatchesWebKit` green, which is the pairing the fix-round
/// verification recorded.
@Test func stackStretchDeclaredSizeMatchesWebKit() throws {
    let golden = try loadGolden("stack_stretch_declared_size")
    let tree = LayoutTree(generation: 0)
    let child = sized(tree, 20, 10)
    let root = stackNode(tree, [child], align: .stretch, justify: .stretch,
                         size: Size(width: px(300), height: px(200)))
    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))
    assertMatchesGolden(tree, ids: [root: "root", child: "child"], golden: golden, tolerance: 0.1)
}

/// The one that proves max-over-children, with a different winner per axis —
/// `wide` (90x10) wins width, `tall` (20x70) wins height, and `mid` (50x40)
/// wins neither, so a "return the first/last child" or "return the width
/// winner's height too" bug cannot pass by coincidence. Same three sizes
/// `StackLayoutTests.aStackSizesToItsLargestChildOnEachAxisIndependently` uses,
/// for the same reason.
///
/// The stack (`data-id="stack"`) is a MEASURED child of a fixed-size flex root,
/// not a declared-size document root — see the file header for why. The flex
/// root's `alignItems = .flexStart` is what keeps the stack from being
/// stretched to the root's full 300pt height on the cross axis; its own main
/// axis (width) already shrinks to content, since a flex item with no
/// `flexGrow` does not grow past its flex basis.
@Test func stackSizesToLargestChildMatchesWebKit() throws {
    let golden = try loadGolden("stack_sizes_to_largest")
    let tree = LayoutTree(generation: 0)
    let wide = sized(tree, 90, 10)
    let tall = sized(tree, 20, 70)
    let mid  = sized(tree, 50, 40)
    let stack = stackNode(tree, [wide, tall, mid], align: .center, justify: .center)

    var rootStyle = Style()
    rootStyle.alignItems = .flexStart
    rootStyle.size = Size(width: px(400), height: px(300))
    let root = tree.newNode(style: rootStyle, children: [stack])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))
    assertMatchesGolden(tree,
                        ids: [root: "root", stack: "stack",
                              wide: "wide", tall: "tall", mid: "mid"],
                        golden: golden, tolerance: 0.1)
}

/// A stack as one item of a flex ROW, with siblings on both sides —
/// `layOutChildren` is shared by both paths and branches on `display`, and a
/// dispatch bug hides exactly here: a stack whose parent is a flex container
/// must contribute its own MEASURED size (max over its children, per axis) to
/// the row's line. A dispatch bug that instead summed the stack's children
/// like a flex row would report `90 + 20 = 110` wide instead of `max(90, 20)
/// = 90`, and the `.after` sibling would land at `40 + 110 = 150` instead of
/// `40 + 90 = 130`. `.before`/`.after` are what make that visible as a
/// POSITION shift on a sibling, not only as the stack's own (untested-against)
/// width.
///
/// `align-items: flex-start` on the row keeps the stack from being stretched
/// to the row's full 150pt height, which would hide the 70pt the stack itself
/// measures from its `.tall` child.
@Test func stackInFlexMatchesWebKit() throws {
    let golden = try loadGolden("stack_in_flex")
    let tree = LayoutTree(generation: 0)
    let before = sized(tree, 40, 30)
    let wide = sized(tree, 90, 10)
    let tall = sized(tree, 20, 70)
    let stack = stackNode(tree, [wide, tall], align: .center, justify: .center)
    let after = sized(tree, 60, 20)

    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.alignItems = .flexStart
    rootStyle.size = Size(width: px(400), height: px(150))
    let root = tree.newNode(style: rootStyle, children: [before, stack, after])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))
    assertMatchesGolden(tree,
                        ids: [root: "root", before: "before", stack: "stack",
                              wide: "wide", tall: "tall", after: "after"],
                        golden: golden, tolerance: 0.1)
}

/// A flex ROW as one child of a stack, alongside a larger sibling — the other
/// direction of the same seam. A dispatch bug here would lay the nested row
/// out at the stack's own width (or at the backdrop's 200) instead of its own
/// 90, since `.backdrop` is deliberately the largest child on both axes: if
/// the row instead won either axis, "the stack measured the row correctly"
/// and "the stack ignored the row and used the backdrop" would produce
/// identical numbers, and this fixture could not distinguish them.
@Test func flexInStackMatchesWebKit() throws {
    let golden = try loadGolden("flex_in_stack")
    let tree = LayoutTree(generation: 0)
    let backdrop = sized(tree, 200, 120)

    let item0 = sized(tree, 30, 25)
    let item1 = sized(tree, 30, 25)
    let item2 = sized(tree, 30, 25)
    var rowStyle = Style()
    rowStyle.flexDirection = .row
    let row = tree.newNode(style: rowStyle, children: [item0, item1, item2])

    let root = stackNode(tree, [backdrop, row], align: .center, justify: .center,
                         size: Size(width: px(300), height: px(200)))

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))
    assertMatchesGolden(tree,
                        ids: [root: "root", backdrop: "backdrop", row: "row",
                              item0: "item0", item1: "item1", item2: "item2"],
                        golden: golden, tolerance: 0.1)
}
