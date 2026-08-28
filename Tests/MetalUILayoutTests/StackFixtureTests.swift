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
/// **`stack_stretch` needed one more correction beyond the mapping above.** CSS
/// Box Alignment's `stretch` only fills the cell when the item's own
/// width/height is `auto` — a box with an explicit size falls back to `start`
/// and keeps its declared size. Verified directly against this repo's own
/// `LayoutOracle` before committing the fixture: a 20x10 child under
/// `justify-items: stretch; align-items: stretch` measures 20x10 at (0,0), not
/// 300x200. `positionStackItems` (`FlexEngine.swift`) carries no such carve-out
/// — it overrides a stretched item's size unconditionally, which is CSS's own
/// answer for an *auto*-sized box. So `stack_stretch.html`'s child is
/// deliberately unsized, unlike the other three alignment fixtures' 20x10 —
/// sizing it explicitly would make the fixture disagree with the engine for a
/// reason that is CSS's fine print on `stretch`, not a stack bug.
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
