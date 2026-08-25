import Testing
import Foundation
import MetalUICore
@testable import MetalUILayout

private func px(_ v: Double) -> MetalUICore.Dimension { .length(.pixels(Pixels(Float(v)))) }

private func flexChild(_ tree: LayoutTree, grow: Float, shrink: Float,
                       basis: MetalUICore.Dimension, cross: Double = 40) -> LayoutNodeID {
    var s = Style()
    s.flexGrow = grow
    s.flexShrink = shrink
    s.flexBasis = basis
    s.size = Size(width: .auto, height: px(cross))
    return tree.newNode(style: s, children: [])
}

/// A child that mirrors a fixture's `.a { flex: <g> <s> <b>; }` **exactly** —
/// no height, because the fixtures declare none. Our engine therefore gives it
/// a cross size of 0 while WebKit stretches it to the container's height; see
/// `assertMainAxisMatchesGolden` for why that is expected and not a defect.
private func fixtureFlexChild(_ tree: LayoutTree, grow: Float, shrink: Float,
                              basis: MetalUICore.Dimension) -> LayoutNodeID {
    var s = Style()
    s.flexGrow = grow
    s.flexShrink = shrink
    s.flexBasis = basis
    return tree.newNode(style: s, children: [])
}

private func row(_ tree: LayoutTree, width: Double, _ kids: [LayoutNodeID]) -> LayoutNodeID {
    var s = Style()
    s.flexDirection = .row
    s.size = Size(width: px(width), height: px(40))
    return tree.newNode(style: s, children: kids)
}

/// Compare **only the main axis** (`x` and `width`) of every named node against
/// the browser's rounded box.
///
/// **The cross axis is deliberately not compared, and this is not
/// cherry-picking the axes that happen to agree.** The fixtures behind these
/// comparisons give their children no explicit height. WebKit lays those out at
/// the container's full height because `align-items` defaults to `stretch`;
/// this engine does not implement alignment at all — `collectItems` takes an
/// item's cross size from the item's own style, so ours is 0. The two sides
/// therefore disagree on `y`/`height` for a reason that has nothing to do with
/// §9.7, which is what these tests exist to pin.
///
/// **When the alignment task lands, widen this to all four fields** (or delete
/// it in favour of `assertMatchesGolden` in `FlexEngineTests`, which already
/// compares all four) — an axis excluded on purpose is only honest while the
/// reason still holds. Do **not** close the gap by giving the fixtures explicit
/// heights: that hides a real missing feature behind a doctored fixture.
private func assertMainAxisMatchesGolden(
    _ tree: LayoutTree,
    ids: [(LayoutNodeID, String)],
    golden: GoldenFile,
    tolerance: Double = 0.1,
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    let byID = Dictionary(uniqueKeysWithValues: golden.rounded.map { ($0.id, $0) })
    for (node, id) in ids {
        let ours = tree.layout(node)
        let theirs = try #require(byID[id], "golden '\(golden.fixture)' has no node '\(id)'",
                                  sourceLocation: sourceLocation)
        #expect(abs(ours.x - theirs.x) <= tolerance,
                "\(id).x ours \(ours.x) vs \(theirs.x)", sourceLocation: sourceLocation)
        #expect(abs(ours.width - theirs.width) <= tolerance,
                "\(id).w ours \(ours.width) vs \(theirs.width)", sourceLocation: sourceLocation)
    }
}

@Test func growDistributesFreeSpaceInProportionToFlexGrow() {
    let tree = LayoutTree()
    let a = flexChild(tree, grow: 1, shrink: 1, basis: px(0))
    let b = flexChild(tree, grow: 2, shrink: 1, basis: px(0))
    let c = flexChild(tree, grow: 0, shrink: 0, basis: px(100))
    let root = row(tree, width: 700, [a, b, c])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    // 700 - 100 = 600 free, split 1:2.
    #expect(tree.layout(a).width == 200)
    #expect(tree.layout(b).width == 400)
    #expect(tree.layout(c).width == 100)
    #expect(tree.layout(a).x == 0)
    #expect(tree.layout(b).x == 200)
    #expect(tree.layout(c).x == 600)
}

@Test func shrinkIsWeightedByBaseSize() {
    // §9.7: shrink is scaled by base size, so equal shrink factors do NOT
    // remove equal amounts. a=200 b=200 c=100 in a 300 row: 200 overflow.
    // Scaled factors: a 1*200=200, b 2*200=400, c frozen. Total 600.
    // a loses 200*(200/600)=66.67 -> 133.33; b loses 200*(400/600)=133.33 -> 66.67.
    //
    // **This test cannot detect the weighting being dropped.** a and b have the
    // same base size, so the common 200 cancels: unweighted factors 1 and 2 out
    // of 3 give exactly the same 133.33 / 66.67 as weighted 200 and 400 out of
    // 600. Deleting `* item.baseSize` leaves this test green — verified by
    // mutation, not by reading. It pins the arithmetic against WebKit's answer
    // for `flex_row_shrink` (which is blind for the same reason); the test that
    // actually pins the weighting is
    // `shrinkWeightingDistinguishesItemsWithDifferentBaseSizes` below, which
    // exists precisely because this one is a §1-shape uniform-value test.
    let tree = LayoutTree()
    let a = flexChild(tree, grow: 0, shrink: 1, basis: px(200))
    let b = flexChild(tree, grow: 0, shrink: 2, basis: px(200))
    let c = flexChild(tree, grow: 0, shrink: 0, basis: px(100))
    let root = row(tree, width: 300, [a, b, c])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    #expect(tree.layout(a).width == 133)   // 133.33 rounded
    #expect(tree.layout(b).width == 67)    // 66.67 rounded
    #expect(tree.layout(c).width == 100)
    #expect(tree.layout(c).x + tree.layout(c).width == 300)
}

/// The weighting, on items whose base sizes actually differ.
///
/// `shrinkIsWeightedByBaseSize` above uses two 200px items, where weighting by
/// base size and not weighting give the *same* answer — the common factor 200
/// cancels out of `200/600` vs `1/3`. It pins the arithmetic but cannot detect
/// the weighting being dropped. This one can: equal shrink factors on a 300px
/// and a 100px item must remove three times as much from the larger.
///
/// 300 + 100 = 400 in a 200 row: 200 overflow. Weighted factors 1*300 and
/// 1*100, total 400. The 300 loses 200*(300/400) = 150 -> 150; the 100 loses
/// 200*(100/400) = 50 -> 50. Unweighted, both lose 100: 200 and 0.
@Test func shrinkWeightingDistinguishesItemsWithDifferentBaseSizes() {
    let tree = LayoutTree()
    let big = flexChild(tree, grow: 0, shrink: 1, basis: px(300))
    let small = flexChild(tree, grow: 0, shrink: 1, basis: px(100))
    let root = row(tree, width: 200, [big, small])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    #expect(tree.layout(big).width == 150)
    #expect(tree.layout(small).width == 50)
    #expect(tree.layout(small).x == 150)
}

@Test func gapIsRemovedFromFreeSpaceBeforeDistribution() {
    let tree = LayoutTree()
    let a = flexChild(tree, grow: 1, shrink: 1, basis: px(0))
    let b = flexChild(tree, grow: 1, shrink: 1, basis: px(0))
    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.size = Size(width: px(220), height: px(40))
    rootStyle.gap = Axes(both: .pixels(Pixels(20)))
    let root = tree.newNode(style: rootStyle, children: [a, b])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    // 220 - 20 gap = 200 free, split evenly.
    #expect(tree.layout(a).width == 100)
    #expect(tree.layout(b).width == 100)
    #expect(tree.layout(b).x == 120)
}

/// §9.7.4.a — flex factors summing to **less than one** distribute only that
/// fraction of the *initial* free space, and the rest stays unfilled.
///
/// Without the clause the loop distributes all 400 and the three items come out
/// 133/133/134, closing the row. `flex_row_fractional_grow` is the browser's
/// word on it; this pins the same arithmetic without WebKit in the loop.
@Test func flexFactorsSummingBelowOneLeaveFreeSpaceUnfilled() {
    let tree = LayoutTree()
    let kids = (0..<3).map { _ in flexChild(tree, grow: 0.25, shrink: 1, basis: px(0)) }
    let root = row(tree, width: 400, kids)

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    // 0.25 * 3 = 0.75 of 400 = 300 distributed, 100 each. 100px goes unused.
    for kid in kids { #expect(tree.layout(kid).width == 100) }
    #expect(tree.layout(kids[2]).x + tree.layout(kids[2]).width == 300)
}

/// A lone sub-one factor is the case the clause exists for: without it a single
/// `flex-grow: 0.5` item silently swallows *all* the free space, because
/// `factor / factorTotal` is 1 whenever there is only one unfrozen item.
@Test func aLoneSubOneGrowFactorTakesOnlyItsFraction() {
    let tree = LayoutTree()
    let a = flexChild(tree, grow: 0.5, shrink: 1, basis: px(0))
    let root = row(tree, width: 400, [a])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    #expect(tree.layout(a).width == 200)
}

@MainActor
@Test func growMatchesWebKitOnTheUnusedGolden() throws {
    // flex_row_fixed_and_grow.json has been committed since M1a Task 4 and
    // nothing has ever compared against it. This is what makes it load-bearing.
    //
    // Main axis only — see `assertMainAxisMatchesGolden`. (This fixture's `a`
    // and `b` declare no height either; the hand-built tree below gives them
    // 100 to match the container, but the comparison still excludes the cross
    // axis so it stays honest alongside the other three.)
    let golden = try loadGolden("flex_row_fixed_and_grow")

    let tree = LayoutTree()
    let a = flexChild(tree, grow: 1, shrink: 1, basis: px(0), cross: 100)
    let b = flexChild(tree, grow: 2, shrink: 1, basis: px(0), cross: 100)
    var cs = Style()
    cs.size = Size(width: px(100), height: px(100))
    let c = tree.newNode(style: cs, children: [])
    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.size = Size(width: px(700), height: px(100))
    let root = tree.newNode(style: rootStyle, children: [a, b, c])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    try assertMainAxisMatchesGolden(
        tree, ids: [(root, "root"), (a, "a"), (b, "b"), (c, "c")], golden: golden)
}

/// `flex_row_grow_uneven`: 640 row, `1 1 0` / `3 1 0` / `0 0 140px`.
/// 500 free after the fixed 140, split 1:3 -> 125 and 375.
///
/// Main axis only — see `assertMainAxisMatchesGolden`. All three children lack
/// a height, so WebKit stretches them to 40 and ours are 0 until alignment
/// lands; widen this comparison then.
@MainActor
@Test func unevenGrowMatchesWebKit() throws {
    let golden = try loadGolden("flex_row_grow_uneven")

    let tree = LayoutTree()
    let a = fixtureFlexChild(tree, grow: 1, shrink: 1, basis: px(0))
    let b = fixtureFlexChild(tree, grow: 3, shrink: 1, basis: px(0))
    let c = fixtureFlexChild(tree, grow: 0, shrink: 0, basis: px(140))
    let root = row(tree, width: 640, [a, b, c])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    try assertMainAxisMatchesGolden(
        tree, ids: [(root, "root"), (a, "a"), (b, "b"), (c, "c")], golden: golden)
}

/// `flex_row_shrink`: 300 row holding 200 + 200 + 100. The browser's answer is
/// the base-size-weighted one, which is the whole point of the fixture.
///
/// Main axis only — see `assertMainAxisMatchesGolden`. All three children lack
/// a height, so WebKit stretches them to 40 and ours are 0 until alignment
/// lands; widen this comparison then.
@MainActor
@Test func shrinkMatchesWebKit() throws {
    let golden = try loadGolden("flex_row_shrink")

    let tree = LayoutTree()
    let a = fixtureFlexChild(tree, grow: 0, shrink: 1, basis: px(200))
    let b = fixtureFlexChild(tree, grow: 0, shrink: 2, basis: px(200))
    let c = fixtureFlexChild(tree, grow: 0, shrink: 0, basis: px(100))
    let root = row(tree, width: 300, [a, b, c])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    try assertMainAxisMatchesGolden(
        tree, ids: [(root, "root"), (a, "a"), (b, "b"), (c, "c")], golden: golden)
}

/// `flex_row_fractional_grow`: three `flex: 0.25 1 0` items in a 400 row.
/// WebKit gives 100/100/100 and leaves 100px of the container empty — the
/// browser's confirmation of §9.7.4.a's sub-one clause.
///
/// Main axis only — see `assertMainAxisMatchesGolden`. All three children lack
/// a height, so WebKit stretches them to 40 and ours are 0 until alignment
/// lands; widen this comparison then.
@MainActor
@Test func fractionalGrowMatchesWebKit() throws {
    let golden = try loadGolden("flex_row_fractional_grow")

    let tree = LayoutTree()
    let kids = (0..<3).map { _ in fixtureFlexChild(tree, grow: 0.25, shrink: 1, basis: px(0)) }
    let root = row(tree, width: 400, kids)

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    try assertMainAxisMatchesGolden(
        tree,
        ids: [(root, "root"), (kids[0], "a"), (kids[1], "b"), (kids[2], "c")],
        golden: golden)
}
