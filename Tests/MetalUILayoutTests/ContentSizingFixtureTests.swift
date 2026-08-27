import Testing
import Foundation
import MetalUICore
@testable import MetalUILayout

/// The content-sizing milestone's **browser evidence**.
///
/// A golden is a pure function of (fixture HTML, viewport, WebKit version) —
/// `generateGolden` drives a `WKWebView` and imports nothing from the engine, so
/// no engine change can move one. The engine meets a golden only here, in
/// `assertMatchesGolden`. A fixture with a golden and no comparison test is read
/// by `committedGoldensMatchTheBrowser` alone, which checks the browser against
/// itself: taxonomy shape 3, an artifact that is written and never read *by the
/// thing it exists to constrain*. These four tests are what make the four new
/// fixtures load-bearing.
///
/// They exist because the 57 fixtures that preceded them are **structurally
/// blind to this whole milestone**. Every one of their children is an empty
/// `div` whose content size is 0 — and 0 is exactly the constant all four wired
/// sites used to substitute, so all four sites are reached and return the same
/// number. 53 of the 57 are two levels deep, and the four with a real nested
/// container declare both of its axes. Reverting `measureNode` to "a container
/// is 0" reddened 15 tests before these landed and **not one was a fixture**.
/// The four below are the complement of that list, one site each.

private func px(_ v: Double) -> MetalUICore.Dimension { .length(.pixels(Pixels(Float(v)))) }

private func leaf(_ tree: LayoutTree, _ w: Double, _ h: Double) -> LayoutNodeID {
    var s = Style()
    s.size = Size(width: px(w), height: px(h))
    return tree.newNode(style: s, children: [])
}

/// Site 3 — `collectItems`' `auto` cross size, the divergence this milestone is
/// named for, as a browser fixture rather than a hand-written expectation.
///
/// `flex_nested_auto_cross`. `.mid` is a `width: 120px` flex container with no
/// height; its cross size is the max over its own line (50, from `.a`, not 24
/// from `.b`), and §9.4.8 measures the *line* from that unstretched value
/// before stretch runs. WebKit: `mid 120x50`, `after` at y = 50, `tail` at
/// y = 80. With `ownCross` back at `resolveNodeSize`'s 0 the line collapses and
/// the two later lines stack at 0 and 30.
///
/// `autoCrossNestedContainerMeasuresItsLineLikeWebKit` in `WrappingTests` makes
/// the same claim by hand and was, until now, the only thing that made it.
@Test func nestedAutoCrossMatchesWebKit() throws {
    let golden = try loadGolden("flex_nested_auto_cross")
    let tree = LayoutTree(generation: 0)

    let a = leaf(tree, 40, 50)
    let b = leaf(tree, 30, 24)
    var midStyle = Style()
    midStyle.flexDirection = .row
    midStyle.size = Size(width: px(120), height: .auto)
    let mid = tree.newNode(style: midStyle, children: [a, b])

    let after = leaf(tree, 120, 30)
    let tail = leaf(tree, 120, 20)

    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.flexWrap = .wrap
    rootStyle.alignContent = .flexStart
    rootStyle.size = Size(width: px(200), height: px(200))
    let root = tree.newNode(style: rootStyle, children: [mid, after, tail])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    assertMatchesGolden(tree,
                        ids: [root: "root", mid: "mid", a: "a", b: "b",
                              after: "after", tail: "tail"],
                        golden: golden, tolerance: 0.1)
}

/// Site 1 — `flexBaseSize`'s §9.2 content branch, through two levels of `auto`
/// main size, which no fixture and no committed test reached through
/// `computeLayout` before this one.
///
/// `flex_auto_height_two_levels`. `.inner` measures 48 from its two 24-tall
/// children; `.outer` measures 48 *because `.inner` answered*; `.after` at
/// y = 48 is the only place outside `.outer` where that shows.
///
/// **The root declares both axes on purpose.** An `auto` root axis is ruling
/// CS-I's deliberate divergence — WebKit shrink-wraps (measured: `300x48` for
/// the draft of this fixture), this engine keeps the offered extent. Putting
/// the auto axis one level down tests the propagation with none of the
/// divergence in it.
///
/// **`min-height: 0` on both containers is what makes this test site 1 at all,
/// and it was added after a measurement, not before one.** Without it, the
/// fixture is green under a site-1 revert *and* green under a site-2 revert,
/// and red only under both — a real masking pair, and the first one measured on
/// this branch. In a column, §4.5's automatic minimum probes the item's
/// min-content HEIGHT, which for fixed-height children is the same 48 the
/// content branch computes, so either site alone rescues the other. Switching
/// the automatic minimum off leaves the content branch as the only source of
/// the number. WebKit's answer is **byte-identical** either way — nothing here
/// shrinks — so the golden did not move when the declaration was added, which
/// is the evidence that it changes what the fixture *pins* and not what it
/// *is*.
@Test func autoHeightAtTwoLevelsMatchesWebKit() throws {
    let golden = try loadGolden("flex_auto_height_two_levels")
    let tree = LayoutTree(generation: 0)

    let g1 = leaf(tree, 60, 24)
    let g2 = leaf(tree, 60, 24)
    var innerStyle = Style()
    innerStyle.flexDirection = .column
    innerStyle.size = Size(width: px(180), height: .auto)
    innerStyle.minSize = Size(width: .auto, height: px(0))
    let inner = tree.newNode(style: innerStyle, children: [g1, g2])

    var outerStyle = Style()
    outerStyle.flexDirection = .column
    outerStyle.size = Size(width: px(240), height: .auto)
    outerStyle.minSize = Size(width: .auto, height: px(0))
    let outer = tree.newNode(style: outerStyle, children: [inner])

    let after = leaf(tree, 100, 30)

    var rootStyle = Style()
    rootStyle.flexDirection = .column
    rootStyle.size = Size(width: px(300), height: px(220))
    let root = tree.newNode(style: rootStyle, children: [outer, after])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    assertMatchesGolden(tree,
                        ids: [root: "root", outer: "outer", inner: "inner",
                              g1: "g1", g2: "g2", after: "after"],
                        golden: golden, tolerance: 0.1)
}

/// A container whose **own reported size** differs between `.minContent` and
/// `.maxContent` — the one row of the re-baseline's mode-swap table that
/// reddened **0 goldens**.
///
/// `flex_wrap_min_vs_max_content`. `.mid` has no `width`, so `flexBaseSize`
/// step 3 measures it under the container's question, which for a
/// definite-width row root is `.maxContent`: 120 for three 40px children on one
/// line, clamped by `max-width: 100px` to 100, which then breaks them 2 + 1.
/// Under `.minContent` the line budget is zero, each child lines alone, and
/// `.mid` reports 40 — the cap goes inert and `g2`/`g3` move.
///
/// The §4.5 half of that mutation already reddens two Group B goldens; this is
/// the `flexBaseSize` half.
@Test func wrapMinVersusMaxContentMatchesWebKit() throws {
    let golden = try loadGolden("flex_wrap_min_vs_max_content")
    let tree = LayoutTree(generation: 0)

    let kids = (0..<3).map { _ in leaf(tree, 40, 20) }
    var midStyle = Style()
    midStyle.flexDirection = .row
    midStyle.flexWrap = .wrap
    midStyle.maxSize = Size(width: px(100), height: .auto)
    let mid = tree.newNode(style: midStyle, children: kids)

    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.size = Size(width: px(260), height: px(160))
    let root = tree.newNode(style: rootStyle, children: [mid])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    assertMatchesGolden(tree,
                        ids: [root: "root", mid: "mid",
                              kids[0]: "g1", kids[1]: "g2", kids[2]: "g3"],
                        golden: golden, tolerance: 0.1)
}

/// Site 2 — CSS Sizing §4.5's automatic minimum for a container item, the
/// change with the widest blast radius, since `min-width: auto` is CSS's
/// default on every flex item.
///
/// `flex_item_floored_by_content`. Both items are `flex: 1 1 0`, so the
/// unfloored answer is 50 / 50 and is entirely plausible; WebKit says 80 / 20
/// because `.squeezed`'s 80px child floors it. `.other` is an empty div whose
/// content suggestion is 0, so it is **not** floored — that asymmetry is what
/// distinguishes "the automatic minimum works" from "every item is frozen at
/// its hypothetical main size".
///
/// `aContainerItemIsFlooredByItsChildrensWidth` carries the `min-width: 0`
/// differential, which a golden cannot: a golden is one layout.
@Test func itemFlooredByItsContentMatchesWebKit() throws {
    let golden = try loadGolden("flex_item_floored_by_content")
    let tree = LayoutTree(generation: 0)

    let g1 = leaf(tree, 80, 20)
    var squeezedStyle = Style()
    squeezedStyle.flexDirection = .row
    squeezedStyle.flexGrow = 1
    squeezedStyle.flexShrink = 1
    squeezedStyle.flexBasis = px(0)
    let squeezed = tree.newNode(style: squeezedStyle, children: [g1])

    var otherStyle = Style()
    otherStyle.flexGrow = 1
    otherStyle.flexShrink = 1
    otherStyle.flexBasis = px(0)
    let other = tree.newNode(style: otherStyle, children: [])

    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.size = Size(width: px(100), height: px(60))
    let root = tree.newNode(style: rootStyle, children: [squeezed, other])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    assertMatchesGolden(tree,
                        ids: [root: "root", squeezed: "squeezed",
                              g1: "g1", other: "other"],
                        golden: golden, tolerance: 0.1)
}
