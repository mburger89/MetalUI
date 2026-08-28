import Testing
import Foundation
import MetalUICore
@testable import MetalUILayout

/// **Browser evidence for ruling TX-H** — a column's `auto` cross size is
/// shrink-to-fit, not max-content.
///
/// These five fixtures exist because of a caveat, and the caveat is the point of
/// the file. The change that produced them moved **no** existing golden, and
/// that is *weak* evidence rather than strong — for exactly the reason
/// divergence 6 survived four milestones. Every box in the 61 fixtures that
/// preceded these is an empty div with a declared size, so its min-content and
/// max-content widths are the **same number**; fit-content and max-content
/// cannot be distinguished in any of them, in either direction. The old corpus
/// could neither regress under this change nor validate it.
///
/// What separates the two rules is content whose two intrinsic widths differ. In
/// this framework that is text — which has no browser oracle, because WebKit
/// shapes with its own font stack — or a **wrapping flex container**, which has
/// no text in it at all. Every `.a`/`.s`/`.c`/`.e` below is the second kind: four
/// (or two) 50-wide items that wrap, min-content 50, max-content 200 (or 100).
///
/// The engine's numbers are its own; the goldens' are WebKit's. `assertMatchesGolden`
/// is the only place the two meet.
private func px(_ v: Double) -> MetalUICore.Dimension { .length(.pixels(Pixels(Float(v)))) }
private func lpx(_ v: Double) -> Length { .pixels(Pixels(Float(v))) }

private func leaf(_ tree: LayoutTree, _ w: Double, _ h: Double) -> LayoutNodeID {
    var s = Style()
    s.size = Size(width: px(w), height: px(h))
    return tree.newNode(style: s, children: [])
}

/// A wrapping flex container holding `count` 50x20 items: min-content 50,
/// max-content `50 * count`, and a height that depends on which it is laid out
/// at. The one shape in this repo that can tell shrink-to-fit from max-content
/// without a font.
private func wrapper(_ tree: LayoutTree, count: Int,
                     configure: (inout Style) -> Void = { _ in })
    -> (LayoutNodeID, [LayoutNodeID]) {
    let kids = (0..<count).map { _ in leaf(tree, 50, 20) }
    var s = Style()
    s.flexWrap = .wrap
    configure(&s)
    return (tree.newNode(style: s, children: kids), kids)
}

/// The headline: `.a` shrinks to the 120 it is offered instead of taking its
/// 200pt max-content width and hanging 40 off each side.
///
/// `.pct` is the control for the branch's **guard** rather than its arithmetic:
/// a percentage cross size is not `auto`, so `ownCross` returns it without
/// measuring anything. 50% of 120 is 60, one item per line, 80 tall — a height
/// no fit-content answer produces, so widening the `auto` branch to cover
/// declared sizes moves `.pct` and leaves `.a` alone.
@Test func columnFitContentMatchesWebKit() throws {
    let golden = try loadGolden("flex_column_fit_content")
    let tree = LayoutTree(generation: 0)

    let (a, k) = wrapper(tree, count: 4)
    let (pct, p) = wrapper(tree, count: 4) { $0.size = Size(width: .length(.percent(0.5)),
                                                           height: .auto) }
    let tail = leaf(tree, 80, 20)

    var rootStyle = Style()
    rootStyle.flexDirection = .column
    rootStyle.alignItems = .center
    rootStyle.size = Size(width: px(120), height: px(300))
    let root = tree.newNode(style: rootStyle, children: [a, pct, tail])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    assertMatchesGolden(tree,
                        ids: [root: "root", a: "a",
                              k[0]: "k1", k[1]: "k2", k[2]: "k3", k[3]: "k4",
                              pct: "pct",
                              p[0]: "p1", p[1]: "p2", p[2]: "p3", p[3]: "p4",
                              tail: "tail"],
                        golden: golden, tolerance: 0.1)
}

/// fit-content's `max(min-content, available)` floor — **the only fixture in the
/// corpus that can tell fit-content from stretch.**
///
/// Where `min-content <= available <= max-content` shrink-to-fit answers exactly
/// `available`, which is also stretch's answer; the number is right either way
/// and names no rule. Here the container is 30 wide and one item is 50, so the
/// floor binds and WebKit overflows: 50 wide, at 0 / -10 / -20 for
/// `flex-start` / `center` / `flex-end`. A stretch implementation gives 30 at 0
/// for all three.
///
/// The three alignments are the `align-self` half: fit-content is the same 50 for
/// each and only the offset differs, so the file also pins that `align-self`
/// routes into the same branch `align-items` does. `.stretch` is the fourth item
/// and takes the container's 30 — where its own 50-wide children then shrink,
/// which is the second thing distinguishing it.
@Test func columnFitContentFloorMatchesWebKit() throws {
    let golden = try loadGolden("flex_column_fit_content_floor")
    let tree = LayoutTree(generation: 0)

    let (s, sk) = wrapper(tree, count: 2) { $0.alignSelf = .flexStart }
    let (c, ck) = wrapper(tree, count: 2) { $0.alignSelf = .center }
    let (e, ek) = wrapper(tree, count: 2) { $0.alignSelf = .flexEnd }
    let (stretch, tk) = wrapper(tree, count: 2)

    var rootStyle = Style()
    rootStyle.flexDirection = .column
    rootStyle.size = Size(width: px(30), height: px(400))
    let root = tree.newNode(style: rootStyle, children: [s, c, e, stretch])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    assertMatchesGolden(tree,
                        ids: [root: "root",
                              s: "s", sk[0]: "s1", sk[1]: "s2",
                              c: "c", ck[0]: "c1", ck[1]: "c2",
                              e: "e", ek[0]: "e1", ek[1]: "e2",
                              stretch: "stretch", tk[0]: "t1", tk[1]: "t2"],
                        golden: golden, tolerance: 0.1)
}

/// fit-content x **cross margins** — the composition that existed in the engine
/// and in no fixture, and the one the first prototype of this fix got wrong.
///
/// The available space is the container's cross extent minus the item's own cross
/// margins: `120 - 10 - 6 = 104`, and WebKit says 104. Ignoring the margins gives
/// 120 and overflows the column by exactly 16. The margins are asymmetric so that
/// a transposition, or subtracting one edge twice, is visible.
@Test func columnFitContentSubtractsCrossMarginsLikeWebKit() throws {
    let golden = try loadGolden("flex_column_fit_content_margins")
    let tree = LayoutTree(generation: 0)

    let (a, k) = wrapper(tree, count: 4) {
        $0.margin = Edges(top: px(0), right: px(6), bottom: px(0), left: px(10))
    }
    let tail = leaf(tree, 40, 24)

    var rootStyle = Style()
    rootStyle.flexDirection = .column
    rootStyle.alignItems = .center
    rootStyle.size = Size(width: px(120), height: px(200))
    let root = tree.newNode(style: rootStyle, children: [a, tail])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    assertMatchesGolden(tree,
                        ids: [root: "root", a: "a",
                              k[0]: "k1", k[1]: "k2", k[2]: "k3", k[3]: "k4",
                              tail: "tail"],
                        golden: golden, tolerance: 0.1)
}

/// The same rule one level down, against a **content box** rather than a
/// declared width.
///
/// `.outer` is 144 wide with 10 + 14 of horizontal padding, so `.a` shrinks to
/// its 120pt content box and sits at x = 10. The root's 300, `.outer`'s 144 and
/// `.outer`'s content 120 are three different numbers, so the fixture
/// distinguishes all three candidate bases — the trick
/// `flex_percent_padding_nonsquare` uses for percentage insets, applied here.
@Test func nestedColumnFitContentMatchesWebKit() throws {
    let golden = try loadGolden("flex_column_fit_content_nested")
    let tree = LayoutTree(generation: 0)

    let (a, k) = wrapper(tree, count: 4)

    var outerStyle = Style()
    outerStyle.flexDirection = .column
    outerStyle.alignItems = .center
    outerStyle.size = Size(width: px(144), height: px(200))
    outerStyle.padding = Edges(top: lpx(0), right: lpx(14), bottom: lpx(0), left: lpx(10))
    let outer = tree.newNode(style: outerStyle, children: [a])

    let after = leaf(tree, 80, 30)

    var rootStyle = Style()
    rootStyle.flexDirection = .column
    rootStyle.size = Size(width: px(300), height: px(400))
    let root = tree.newNode(style: rootStyle, children: [outer, after])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    assertMatchesGolden(tree,
                        ids: [root: "root", outer: "outer", a: "a",
                              k[0]: "k1", k[1]: "k2", k[2]: "k3", k[3]: "k4",
                              after: "after"],
                        golden: golden, tolerance: 0.1)
}

/// An **indefinite** cross extent — the case the branch reaches by propagating
/// the container's own intrinsic question rather than a number.
///
/// `.col` declares no width, so when the root measures it there is no extent to
/// shrink-to-fit against and the answer must come from the question. With the
/// cross axis hardcoded to max-content — which is what it was before this fix,
/// and what it still is in a **row** — `.col` reports 200 as both of its
/// intrinsic widths and the root's own fit-content collapses to `max(200, 120)`.
/// WebKit puts `.col` at 120.
///
/// `.mark` is the second observable: `.col` centres it, so its x reads `.col`'s
/// width off directly (25 at 120, 65 at 200), and its 70pt width makes `.col`'s
/// min-content 70 rather than `.a`'s 50 — so "a column's min-content is the max
/// over its items" is pinned and not assumed.
@Test func nestedAutoWidthColumnFitContentMatchesWebKit() throws {
    let golden = try loadGolden("flex_column_fit_content_nested_auto")
    let tree = LayoutTree(generation: 0)

    let (a, k) = wrapper(tree, count: 4)
    let mark = leaf(tree, 70, 16)

    var colStyle = Style()
    colStyle.flexDirection = .column
    colStyle.alignItems = .center
    let col = tree.newNode(style: colStyle, children: [a, mark])

    var rootStyle = Style()
    rootStyle.flexDirection = .column
    rootStyle.alignItems = .center
    rootStyle.size = Size(width: px(120), height: px(400))
    let root = tree.newNode(style: rootStyle, children: [col])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    assertMatchesGolden(tree,
                        ids: [root: "root", col: "col", a: "a",
                              k[0]: "k1", k[1]: "k2", k[2]: "k3", k[3]: "k4",
                              mark: "mark"],
                        golden: golden, tolerance: 0.1)
}
