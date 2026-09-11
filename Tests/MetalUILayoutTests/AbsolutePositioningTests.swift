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

private func inset(_ t: Double?, _ r: Double?, _ b: Double?, _ l: Double?) -> Edges<MetalUICore.Dimension> {
    Edges(top: t.map(px) ?? .auto, right: r.map(px) ?? .auto,
          bottom: b.map(px) ?? .auto, left: l.map(px) ?? .auto)
}

/// A single inset positions from that edge.
@Test func aSingleInsetPositionsFromThatEdge() {
    let tree = LayoutTree(generation: 0)
    var s = Style()
    s.size = Size(width: px(20), height: px(10))
    s.position = .absolute
    s.inset = inset(15, nil, nil, 25)
    let abs = tree.newNode(style: s, children: [])
    var cb = Style()
    cb.position = .relative
    let node = tree.newNode(style: cb, children: [abs])

    computeLayout(tree, root: node,
                  available: AvailableSpaceSize(width: .definite(200),
                                                height: .definite(100)))
    #expect(tree.layout(abs).x == 25)
    #expect(tree.layout(abs).y == 15)
    #expect(tree.layout(abs).width == 20)
}

/// Opposite insets with an `auto` size stretch the box between them.
@Test func oppositeInsetsWithAnAutoSizeStretchTheBox() {
    let tree = LayoutTree(generation: 0)
    var s = Style()
    s.position = .absolute
    s.inset = inset(10, 30, 20, 40)     // size stays .auto
    let abs = tree.newNode(style: s, children: [])
    var cb = Style()
    cb.position = .relative
    let node = tree.newNode(style: cb, children: [abs])

    computeLayout(tree, root: node,
                  available: AvailableSpaceSize(width: .definite(200),
                                                height: .definite(100)))
    #expect(tree.layout(abs).x == 40)
    #expect(tree.layout(abs).width == 130, "200 - 40 left - 30 right")
    #expect(tree.layout(abs).y == 10)
    #expect(tree.layout(abs).height == 70, "100 - 10 top - 20 bottom")
}

/// Over-constrained: both insets AND a size. CSS drops `right`.
@Test func anOverConstrainedBoxIgnoresItsRightInset() {
    let tree = LayoutTree(generation: 0)
    var s = Style()
    s.size = Size(width: px(50), height: .auto)
    s.position = .absolute
    s.inset = inset(0, 30, 0, 40)
    let abs = tree.newNode(style: s, children: [])
    var cb = Style()
    cb.position = .relative
    let node = tree.newNode(style: cb, children: [abs])

    computeLayout(tree, root: node,
                  available: AvailableSpaceSize(width: .definite(200),
                                                height: .definite(100)))
    #expect(tree.layout(abs).x == 40, "left wins")
    #expect(tree.layout(abs).width == 50, "the declared width wins; right is dropped")
}

/// **Percentage insets resolve per axis, and this is the test that catches
/// following CLAUDE.md's padding constraint by mistake.**
///
/// The containing block is deliberately NON-SQUARE — 200 wide, 100 tall. On a
/// square containing block `top: 10%` and `left: 10%` give the same number and
/// a width-only implementation passes. Here they differ: 10 vs 20.
@Test func percentageInsetsResolveAgainstWidthForXAndHeightForY() {
    let tree = LayoutTree(generation: 0)
    var s = Style()
    s.size = Size(width: px(20), height: px(10))
    s.position = .absolute
    s.inset = Edges(top: .length(.percent(0.10)), right: .auto,
                    bottom: .auto, left: .length(.percent(0.10)))
    let abs = tree.newNode(style: s, children: [])
    var cb = Style()
    cb.position = .relative
    let node = tree.newNode(style: cb, children: [abs])

    computeLayout(tree, root: node,
                  available: AvailableSpaceSize(width: .definite(200),
                                                height: .definite(100)))
    #expect(tree.layout(abs).x == 20, "10% of the 200 WIDTH")
    #expect(tree.layout(abs).y == 10, "10% of the 100 HEIGHT — not the width")
}

/// **Divergence — spec §7, deliberate.** CSS uses the box's STATIC position
/// (where it would have sat in flow) when every inset is `auto`. This engine
/// places it at the containing block's padding-box origin instead.
///
/// Measured directly against WebKit with a throwaway probe (deleted after
/// this pin was written): `.before`, a 40x20 in-flow sibling, followed by an
/// absolute box with no insets at all, inside a 200x100 `position: relative`
/// root. **WebKit places the absolute box at (0, 20)** — below `.before`, its
/// static position. **This engine places it at (0, 0)**, ignoring `.before`
/// entirely.
///
/// Implementing static position means laying the box out in flow, recording
/// its position, then removing it — a second pass the motivating features
/// (modals, popovers, tooltips) do not need, since they always set insets
/// (spec §3.5). **No fixture or golden encodes this**, on the same footing as
/// this project's other named divergences (BM-4, FS-3, TX-H): a golden would
/// record this engine's answer as correct, and a future fix should move
/// nothing in the corpus.
@Test func allAutoInsetsPlaceAtTheContainingBlockOriginNotTheStaticPosition() {
    let tree = LayoutTree(generation: 0)
    let before = sized(tree, 40, 20)
    let abs = sized(tree, 20, 10, position: .absolute)
    var cb = Style()
    cb.position = .relative
    cb.size = Size(width: px(200), height: px(100))
    let root = tree.newNode(style: cb, children: [before, abs])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))
    #expect(tree.layout(abs).x == 0)
    #expect(tree.layout(abs).y == 0, "not 20 — WebKit's static position puts it below `.before`")
}

/// **The 0×0 sizing bug, pinned directly.** Task 3's `placeAbsolute` sized
/// every absolute child by calling `measureNode(known: .unspecified, …)`
/// unconditionally, which for a childless node with no `MeasureFunction`
/// fell into the container branch and returned `contentSize + edges` — zero
/// for an empty container, never consulting `Style.size`. (`measureNode` now
/// answers such a node in closed form, with the same edges.) All insets stay
/// `.auto` here, so this isolates the sizing bug from the (already-tested)
/// inset arithmetic: with no insets to stretch or position from, the ONLY
/// source the resolved size can come from is the declared `Style.size`.
@Test func anAbsoluteChildWithNoChildrenResolvesToItsDeclaredSize() {
    let tree = LayoutTree(generation: 0)
    var s = Style()
    s.size = Size(width: px(20), height: px(10))
    s.position = .absolute
    let abs = tree.newNode(style: s, children: [])
    var cb = Style()
    cb.position = .relative
    let node = tree.newNode(style: cb, children: [abs])

    computeLayout(tree, root: node,
                  available: AvailableSpaceSize(width: .definite(200),
                                                height: .definite(100)))
    #expect(tree.layout(abs).width == 20, "not 0 — the declared size, not the empty content size")
    #expect(tree.layout(abs).height == 10)
}

/// A declared size on an absolute box is clamped by that box's own
/// `minSize`/`maxSize`, the same way `resolveNodeSize` clamps a flex item's
/// cross axis and `layOutStack`'s `resolvedAxis` clamps a stack child's.
///
/// **Both terms, on separate axes, because each is separately removable.**
/// `maxWidth: 40` binds a declared `width: 100` downward and `minHeight: 60`
/// binds a declared `height: 10` upward; a clamp that dropped only its `max`
/// argument would still pass an assertion that tested only the min, and the
/// reverse. Without the clamp entirely the box measures its raw declared
/// 100x10 — the mutation this pins, and the wrong answer is silent: the box
/// paints at the right place at the wrong size, and `.minWidth(_:)` on an
/// absolutely-positioned box would be one more member of CLAUDE.md's
/// declared-but-inert table.
@Test func anAbsoluteBoxesDeclaredSizeIsClampedByItsOwnMinAndMax() {
    let tree = LayoutTree(generation: 0)
    var s = Style()
    s.size = Size(width: px(100), height: px(10))
    s.maxSize = Size(width: px(40), height: .auto)
    s.minSize = Size(width: .auto, height: px(60))
    s.position = .absolute
    let abs = tree.newNode(style: s, children: [])
    var cb = Style()
    cb.position = .relative
    let root = tree.newNode(style: cb, children: [abs])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(200),
                                                height: .definite(100)))
    #expect(tree.layout(abs).width == 40, "maxWidth binds the declared 100 downward")
    #expect(tree.layout(abs).height == 60, "minHeight binds the declared 10 upward")
}

/// With no positioned ancestor at all, the containing block is the **root's own
/// padding box** — the root's border box backed in by its border and no
/// further.
///
/// **The root is `.static`, which is what makes this a different code path from
/// every other test and fixture here.** A positioned ancestor's padding box is
/// computed by `placeNode`'s `childCB`; the root's is computed once by
/// `computeLayout`'s seed, which has to back the padding back out of the
/// content box `contentBox` hands it. Every `abs_*` fixture puts its padding on
/// a `.relative` node and therefore exercises `childCB` instead, so the seed's
/// arithmetic was reachable and unreached.
///
/// **Padding and border differ (10 and 4) on purpose.** The three candidate
/// boxes then give three different answers on every edge: border box (0, 0)
/// 200x100, padding box (4, 4) 192x92, content box (14, 14) 172x72. With
/// padding alone, or border alone, two of the three coincide and a wrong seed
/// reads as correct. The absolute child's four insets are all 0, so it
/// stretches to the containing block's full extent and the assertion sees the
/// box's *size* as well as its origin.
@Test func withNoPositionedAncestorTheContainingBlockIsTheRootsPaddingBox() {
    let tree = LayoutTree(generation: 0)
    var s = Style()
    s.position = .absolute
    s.inset = Edges(top: px(0), right: px(0), bottom: px(0), left: px(0))
    let abs = tree.newNode(style: s, children: [])
    var r = Style()
    r.padding = Edges(all: .pixels(Pixels(10)))
    r.border = Edges(all: .pixels(Pixels(4)))
    let root = tree.newNode(style: r, children: [abs])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(200),
                                                height: .definite(100)))
    let laid = tree.layout(abs)
    #expect(laid.x == 4 && laid.y == 4,
            "the padding box's origin is inside the border only — not (0, 0) and not the content box's (14, 14)")
    #expect(laid.width == 192 && laid.height == 92,
            "and its extent excludes the border only — not 200x100 and not the content box's 172x72")
}

/// A `display: .none` box stays unplaced even when it is also `.absolute`.
///
/// The absolute pass is a third enumeration of a container's children, beside
/// `collectItems` and `layOutStack`'s loop, and it carries its own copy of the
/// `display != .none` filter. Dropping that conjunct places and sizes a box the
/// two in-flow sites both refuse to touch — so `display: .none` would mean "out
/// of flow" for an absolute box rather than "not there", and the box would
/// paint.
///
/// **The declared size and both insets are non-zero**, so an unfiltered
/// implementation writes a rect that differs from the untouched default on all
/// four fields rather than only on the two a zero inset would move.
@Test func aDisplayNoneAbsoluteChildIsNotPlaced() {
    let tree = LayoutTree(generation: 0)
    var s = Style()
    s.size = Size(width: px(50), height: px(40))
    s.position = .absolute
    s.display = .none
    s.inset = Edges(top: px(30), right: .auto, bottom: .auto, left: px(20))
    let abs = tree.newNode(style: s, children: [])
    var cb = Style()
    cb.position = .relative
    let root = tree.newNode(style: cb, children: [abs])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(200),
                                                height: .definite(100)))
    let laid = tree.layout(abs)
    #expect(laid.x == 0 && laid.y == 0,
            "never placed — an unfiltered absolute pass puts it at its insets, (20, 30)")
    #expect(laid.width == 0 && laid.height == 0,
            "and never sized — an unfiltered pass gives it its declared 50x40")
}

/// An `auto`-sized absolute box is measured against its **containing block's**
/// extent, not at max-content.
///
/// `placeAbsolute` reaches `measureNode` only for an axis that is genuinely
/// `auto` and not bounded by two insets, and the `available:` it passes is the
/// containing block on both axes. Passing `.maxContent` instead is the
/// difference between "as wide as it may be" and "as wide as it wants", and it
/// is invisible on content that cannot reflow.
///
/// **The content therefore wraps.** Four 50x20 items in a `flexWrap: .wrap` row
/// inside a 120-wide containing block fit two per line: 100x40. At max-content
/// the same four items form one 200x20 line, which also overflows the
/// containing block. A non-wrapping child would measure the same either way and
/// this test could not tell the two apart — the uniformity hazard AP-D and
/// divergence 6 were both produced by.
@Test func anAutoSizedAbsoluteBoxIsMeasuredAgainstItsContainingBlockNotMaxContent() {
    let tree = LayoutTree(generation: 0)
    var kid = Style()
    kid.size = Size(width: px(50), height: px(20))
    let kids = (0..<4).map { _ in tree.newNode(style: kid, children: []) }
    var s = Style()
    s.position = .absolute
    s.flexDirection = .row
    s.flexWrap = .wrap
    let abs = tree.newNode(style: s, children: kids)
    var cb = Style()
    cb.position = .relative
    cb.size = Size(width: px(120), height: px(300))
    let root = tree.newNode(style: cb, children: [abs])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(400),
                                                height: .definite(400)))
    #expect(tree.layout(abs).width == 100,
            "two 50-wide items per 120-wide line — not the 200 one max-content line would give")
    #expect(tree.layout(abs).height == 40, "two lines of 20, not one")
}

/// A percentage `padding` or `border` on an absolute box resolves against its
/// **containing block's width**, which `placeAbsolute` has to hand to the
/// recursive `placeNode` explicitly.
///
/// Every other `placeNode` call inherits a containing-block width from a parent
/// that already had one; this one is the entry point into a subtree whose
/// position came from somewhere else in the tree, so the width has to be
/// re-stated. Passing `nil` instead makes every percentage edge inside an
/// absolutely-positioned subtree resolve to 0 — silently, and only for
/// percentages, so a subtree using pixel padding looks fine.
///
/// The containing block is deliberately **non-square** (200x60) and the padding
/// is uniform, so resolving the vertical edges against the height would give 6
/// rather than 20 and the child's y would separate from its x. The child's
/// origin is what is asserted, since padding is not visible in the absolute
/// box's own rect: it moves where in-flow content starts.
@Test func percentagePaddingInsideAnAbsoluteBoxResolvesAgainstItsContainingBlocksWidth() {
    let tree = LayoutTree(generation: 0)
    var kidStyle = Style()
    kidStyle.size = Size(width: px(10), height: px(10))
    let kid = tree.newNode(style: kidStyle, children: [])
    var s = Style()
    s.position = .absolute
    s.size = Size(width: px(100), height: px(100))
    s.padding = Edges(all: .percent(0.10))
    let abs = tree.newNode(style: s, children: [kid])
    var cb = Style()
    cb.position = .relative
    cb.size = Size(width: px(200), height: px(60))
    let root = tree.newNode(style: cb, children: [abs])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(400),
                                                height: .definite(400)))
    #expect(tree.layout(kid).x == 20,
            "10% of the containing block's 200 width — 0 if the width is not threaded through")
    #expect(tree.layout(kid).y == 20,
            "the vertical edge takes the same WIDTH basis: 20, not 6 and not 0")
}
