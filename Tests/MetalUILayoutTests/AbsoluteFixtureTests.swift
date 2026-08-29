import Testing
import Foundation
import MetalUICore
@testable import MetalUILayout

/// Build a tree from a fixture's shape by hand, run layout, and compare every
/// node against the browser's answer for the same fixture.
///
/// **`position: absolute` is directly expressible in CSS** — unlike
/// `Display.stack`, which had to be oracled through a one-cell grid, these
/// fixtures need no translation layer at all. That makes each fixture's
/// geometry a direct assertion about this engine's behavior, not a claim
/// about an intended equivalence a reader has to trust.
///
/// Comparisons here read the **committed** golden rather than driving WebKit.
/// `committedGoldensMatchTheBrowser` in `GeneratorTests` is the one test that
/// re-drives the browser and catches a fixture edited without regenerating.
private func px(_ v: Double) -> MetalUICore.Dimension { .length(.pixels(Pixels(Float(v)))) }

private func sized(_ tree: LayoutTree, _ w: Double, _ h: Double,
                   position: Position = .static) -> LayoutNodeID {
    var s = Style()
    s.size = Size(width: px(w), height: px(h))
    s.position = position
    return tree.newNode(style: s, children: [])
}

private func inset(_ t: Double?, _ r: Double?, _ b: Double?, _ l: Double?) -> Edges<MetalUICore.Dimension> {
    Edges(top: t.map(px) ?? .auto, right: r.map(px) ?? .auto,
          bottom: b.map(px) ?? .auto, left: l.map(px) ?? .auto)
}

/// The absolute box's PARENT is `.static` — a plain flex row it sits inside,
/// alongside a decoy sibling — and the containing block is the GRANDPARENT,
/// two levels up, which is `position: relative` with 5px padding and no
/// border.
///
/// **What this catches:** an implementation that resolves insets against the
/// immediate parent regardless of its `position` (i.e. never walks past the
/// nearest ancestor). That wrong implementation would place `abs` at the
/// static wrapper's own origin — the root's CONTENT box, (5, 5), since the
/// wrapper sits inside the root's 5px padding. The correct implementation
/// walks past the static wrapper to the root and resolves against the root's
/// PADDING box, whose origin is inset only by the root's (zero) BORDER — (0,
/// 0). A fixture where the parent IS the containing block cannot tell these
/// apart, because the two would coincide.
@Test func absContainingBlockSkipsStaticMatchesWebKit() throws {
    let golden = try loadGolden("abs_containing_block_skips_static")
    let tree = LayoutTree(generation: 0)

    var absStyle = Style()
    absStyle.position = .absolute
    absStyle.inset = inset(0, nil, nil, 0)
    absStyle.size = Size(width: px(20), height: px(10))
    let abs = tree.newNode(style: absStyle, children: [])

    let spacer = sized(tree, 60, 10)

    var wrapperStyle = Style()
    wrapperStyle.flexDirection = .row
    let wrapper = tree.newNode(style: wrapperStyle, children: [spacer, abs])

    var rootStyle = Style()
    rootStyle.position = .relative
    rootStyle.size = Size(width: px(200), height: px(100))
    rootStyle.padding = Edges(all: .pixels(Pixels(5)))
    let root = tree.newNode(style: rootStyle, children: [wrapper])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))
    assertMatchesGolden(tree, ids: [root: "root", abs: "abs"], golden: golden, tolerance: 0.1)
}

/// A NON-SQUARE containing block (200 wide, 100 tall) with `top: 10%; left:
/// 10%`.
///
/// **What this catches:** resolving every percentage inset against the same
/// basis — either always width or always height — instead of `left`/`right`
/// against width and `top`/`bottom` against height. On a square containing
/// block those two implementations, and the correct one, would all give the
/// same number; here they diverge: `left` is 20 (10% of 200) and `top` is 10
/// (10% of 100). CLAUDE.md's own percentage-inset constraint (written for
/// `padding`/`border`, which resolve every edge against width) is a trap
/// here — this is the fixture that would redden a naive application of it to
/// `inset`.
@Test func absPercentInsetsNonsquareMatchesWebKit() throws {
    let golden = try loadGolden("abs_percent_insets_nonsquare")
    let tree = LayoutTree(generation: 0)

    var absStyle = Style()
    absStyle.position = .absolute
    absStyle.inset = Edges(top: .length(.percent(0.10)), right: .auto,
                           bottom: .auto, left: .length(.percent(0.10)))
    absStyle.size = Size(width: px(20), height: px(10))
    let abs = tree.newNode(style: absStyle, children: [])

    var rootStyle = Style()
    rootStyle.position = .relative
    rootStyle.size = Size(width: px(200), height: px(100))
    let root = tree.newNode(style: rootStyle, children: [abs])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))
    assertMatchesGolden(tree, ids: [root: "root", abs: "abs"], golden: golden, tolerance: 0.1)
}

/// `#container`'s only in-flow child is 40x20; its absolute sibling is
/// 500x300 — LARGER on both axes. `#container` itself is unsized, so its
/// measured size is the whole assertion.
///
/// **What this catches:** an implementation that excludes the absolute child
/// from `collectItems`'/`layOutStack`'s enumeration but still lets it
/// contribute to the container's measured size some other way (e.g. a
/// max-over-children path that is not also filtered). Because the absolute
/// child is LARGER than the in-flow content on both axes, "removed from
/// flow" (40x20) and "included, but the in-flow content happens to win
/// anyway" are forced to disagree — with a smaller absolute child the two
/// would give the same answer and the fixture would prove nothing.
///
/// `#root` is a fixed-size flex column wrapping `#container`, with
/// `align-items: flex-start` — sidestepping this engine's own divergence 4
/// (an `auto` ROOT axis takes the offered space rather than shrink-wrapping),
/// which is unrelated to absolute positioning and would otherwise swallow the
/// very shrink-to-content behavior this fixture exists to check.
@Test func absRemovedFromFlowMatchesWebKit() throws {
    let golden = try loadGolden("abs_removed_from_flow")
    let tree = LayoutTree(generation: 0)

    let inflow = sized(tree, 40, 20)
    var absStyle = Style()
    absStyle.position = .absolute
    absStyle.size = Size(width: px(500), height: px(300))
    let abs = tree.newNode(style: absStyle, children: [])

    var containerStyle = Style()
    containerStyle.flexDirection = .row
    let container = tree.newNode(style: containerStyle, children: [inflow, abs])

    var rootStyle = Style()
    rootStyle.flexDirection = .column
    rootStyle.alignItems = .flexStart
    rootStyle.size = Size(width: px(400), height: px(300))
    let root = tree.newNode(style: rootStyle, children: [container])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))
    assertMatchesGolden(tree,
                        ids: [root: "root", container: "container", inflow: "inflow"],
                        golden: golden, tolerance: 0.1)
}

/// Both `left` AND `right` given, plus a declared `width` — CSS's
/// over-constrained rule drops `right` (LTR). `top` and `bottom` are also
/// both given with `height: auto`, so the same box exercises the auto-size
/// stretch case on its other axis.
///
/// **What this catches:** dropping `left` instead of `right` (positioning
/// from the trailing edge when a size is declared), or failing to drop
/// either — e.g. clamping the declared width down to fit both insets instead
/// of ignoring one of them.
@Test func absOverConstrainedMatchesWebKit() throws {
    let golden = try loadGolden("abs_over_constrained")
    let tree = LayoutTree(generation: 0)

    var absStyle = Style()
    absStyle.position = .absolute
    absStyle.inset = inset(0, 30, 0, 40)
    absStyle.size = Size(width: px(50), height: .auto)
    let abs = tree.newNode(style: absStyle, children: [])

    var rootStyle = Style()
    rootStyle.position = .relative
    rootStyle.size = Size(width: px(200), height: px(100))
    let root = tree.newNode(style: rootStyle, children: [abs])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))
    assertMatchesGolden(tree, ids: [root: "root", abs: "abs"], golden: golden, tolerance: 0.1)
}

/// **The fifth fixture, beyond the task's original four (controller
/// ruling).** Task 4 flagged "one inset only, with an `auto` size" as a case
/// no oracle had checked: `placeAbsolute` falls back to `measureNode` for the
/// size and positions from the given edge, which is a plausible
/// generalisation of the four documented cases but was never verified
/// against WebKit. Only `left` is given on the horizontal axis (no `right`,
/// no declared `width`); `.content` gives the box something to measure.
///
/// `top` is pinned explicitly (not left `auto` too) so the VERTICAL axis
/// stays outside this fixture's question — leaving it all-`auto` would also
/// exercise the deliberate static-position divergence (spec §7.1, measured
/// and pinned separately), conflating two different unverified things in one
/// fixture.
///
/// **What this catches:** the content-measurement fallback disagreeing with
/// WebKit's shrink-to-fit answer for a single-inset auto-sized box — for
/// example, measuring against the wrong available space (the containing
/// block's full extent rather than an intrinsic/shrink-to-fit query) and
/// getting a size larger than the content actually needs.
@Test func absSingleInsetAutoSizeMatchesWebKit() throws {
    let golden = try loadGolden("abs_single_inset_auto_size")
    let tree = LayoutTree(generation: 0)

    let content = sized(tree, 35, 15)
    var absStyle = Style()
    absStyle.position = .absolute
    absStyle.inset = inset(10, nil, nil, 20)
    let abs = tree.newNode(style: absStyle, children: [content])

    var rootStyle = Style()
    rootStyle.position = .relative
    rootStyle.size = Size(width: px(200), height: px(100))
    let root = tree.newNode(style: rootStyle, children: [abs])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))
    assertMatchesGolden(tree, ids: [root: "root", abs: "abs", content: "content"],
                        golden: golden, tolerance: 0.1)
}
