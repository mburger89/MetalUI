import Testing
import Foundation
import MetalUICore
@testable import MetalUILayout

/// Build a tree from a fixture's shape by hand, run layout, and compare every
/// node against the browser's answer for the same fixture.
///
/// Comparisons here read the **committed** golden rather than driving WebKit.
/// That is what makes `Golden/*.json` load-bearing: a rotted or hand-edited
/// golden reddens these tests. `committedGoldensMatchTheBrowser` in
/// GeneratorTests is the one place that re-drives the browser, and it is what
/// catches a fixture edited without its golden being regenerated.

/// Qualified: this file imports Foundation, whose Measurement API also exports a
/// `Dimension` type, so the bare name is ambiguous here.
private func px(_ v: Double) -> MetalUICore.Dimension { .length(.pixels(Pixels(Float(v)))) }
private let autoDim: MetalUICore.Dimension = .auto

private func fixedChild(_ tree: LayoutTree, w: Double, h: Double) -> LayoutNodeID {
    var s = Style()
    s.size = Size(width: px(w), height: px(h))
    return tree.newNode(style: s, children: [])
}

/// The three-child shape shared by `flex_row_three_fixed`,
/// `flex_column_three_fixed` and `flex_row_gap`.
private func threeFixedChildren(
    direction: FlexDirection,
    width: Double,
    height: Double,
    gap: Double = 0
) -> (LayoutTree, root: LayoutNodeID, x: LayoutNodeID, y: LayoutNodeID, z: LayoutNodeID) {
    let tree = LayoutTree()
    let x = fixedChild(tree, w: 60, h: 20)
    let y = fixedChild(tree, w: 90, h: 30)
    let z = fixedChild(tree, w: 40, h: 50)
    var rootStyle = Style()
    rootStyle.flexDirection = direction
    rootStyle.size = Size(width: px(width), height: px(height))
    rootStyle.gap = Axes(both: .pixels(Pixels(Float(gap))))
    let root = tree.newNode(style: rootStyle, children: [x, y, z])
    return (tree, root, x, y, z)
}

/// Compare every named node's computed rect against the browser's rounded box.
///
/// `sourceLocation` defaults to the call site so a disagreement is reported at
/// the test that failed, not inside this helper.
func assertMatchesGolden(
    _ tree: LayoutTree,
    ids: [LayoutNodeID: String],
    golden: GoldenFile,
    tolerance: Double,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    let byID = Dictionary(uniqueKeysWithValues: golden.rounded.map { ($0.id, $0) })
    for (node, id) in ids {
        let ours = tree.layout(node)
        guard let theirs = byID[id] else {
            Issue.record("golden '\(golden.fixture)' has no node '\(id)'",
                         sourceLocation: sourceLocation)
            continue
        }
        #expect(abs(ours.x - theirs.x) <= tolerance,
                "\(id).x: ours \(ours.x) vs WebKit \(theirs.x)", sourceLocation: sourceLocation)
        #expect(abs(ours.y - theirs.y) <= tolerance,
                "\(id).y: ours \(ours.y) vs WebKit \(theirs.y)", sourceLocation: sourceLocation)
        #expect(abs(ours.width - theirs.width) <= tolerance,
                "\(id).w: ours \(ours.width) vs WebKit \(theirs.width)", sourceLocation: sourceLocation)
        #expect(abs(ours.height - theirs.height) <= tolerance,
                "\(id).h: ours \(ours.height) vs WebKit \(theirs.height)", sourceLocation: sourceLocation)
    }
}

@Test func rowPacksFixedChildrenLeftToRight() {
    let tree = LayoutTree()
    let x = fixedChild(tree, w: 60, h: 20)
    let y = fixedChild(tree, w: 90, h: 30)
    let z = fixedChild(tree, w: 40, h: 50)
    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.size = Size(width: px(300), height: px(50))
    let root = tree.newNode(style: rootStyle, children: [x, y, z])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    #expect(tree.layout(root) == LayoutRect(x: 0, y: 0, width: 300, height: 50))
    #expect(tree.layout(x) == LayoutRect(x: 0,   y: 0, width: 60, height: 20))
    #expect(tree.layout(y) == LayoutRect(x: 60,  y: 0, width: 90, height: 30))
    #expect(tree.layout(z) == LayoutRect(x: 150, y: 0, width: 40, height: 50))
}

@Test func columnPacksFixedChildrenTopToBottom() {
    let tree = LayoutTree()
    let x = fixedChild(tree, w: 60, h: 20)
    let y = fixedChild(tree, w: 90, h: 30)
    let z = fixedChild(tree, w: 40, h: 50)
    var rootStyle = Style()
    rootStyle.flexDirection = .column
    rootStyle.size = Size(width: px(120), height: px(400))
    let root = tree.newNode(style: rootStyle, children: [x, y, z])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    #expect(tree.layout(x) == LayoutRect(x: 0, y: 0,  width: 60, height: 20))
    #expect(tree.layout(y) == LayoutRect(x: 0, y: 20, width: 90, height: 30))
    #expect(tree.layout(z) == LayoutRect(x: 0, y: 50, width: 40, height: 50))
}

/// `gap` adds a fixed run between adjacent items, and never before the first or
/// after the last. Deleting the `+ gap` term in `positionItems` left the whole
/// suite green before this test and `flex_row_gap` existed.
@Test func gapSeparatesAdjacentItemsButNotTheEnds() {
    let (tree, root, x, y, z) = threeFixedChildren(direction: .row, width: 300, height: 50, gap: 12)
    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    // No leading gap; one 12 between x and y; another between y and z.
    #expect(tree.layout(x) == LayoutRect(x: 0,   y: 0, width: 60, height: 20))
    #expect(tree.layout(y) == LayoutRect(x: 72,  y: 0, width: 90, height: 30))
    #expect(tree.layout(z) == LayoutRect(x: 174, y: 0, width: 40, height: 50))
    // And no trailing gap: the content ends at 214, inside the 300 container.
    #expect(tree.layout(z).x + tree.layout(z).width == 214)
}

/// A column container takes its gap from the vertical axis, not the horizontal.
@Test func gapUsesTheMainAxisOfTheContainer() {
    let tree = LayoutTree()
    let a = fixedChild(tree, w: 20, h: 10)
    let b = fixedChild(tree, w: 20, h: 10)
    var rootStyle = Style()
    rootStyle.flexDirection = .column
    rootStyle.size = Size(width: px(100), height: px(100))
    // Deliberately asymmetric: a main-axis pick of `horizontal` would give 30.
    rootStyle.gap = Axes(horizontal: .pixels(Pixels(20)), vertical: .pixels(Pixels(5)))
    let root = tree.newNode(style: rootStyle, children: [a, b])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    #expect(tree.layout(b) == LayoutRect(x: 0, y: 15, width: 20, height: 10))
}

/// `display: none` removes an item from the flow entirely: it occupies no main
/// axis space, so its successors close up over it.
///
/// Deleting the `where tree.style(kid).display != .none` filter left the whole
/// suite green before this test existed.
@Test func displayNoneChildrenAreSkippedAndConsumeNoSpace() {
    let tree = LayoutTree()
    let a = fixedChild(tree, w: 60, h: 20)

    var hiddenStyle = Style()
    hiddenStyle.display = .none
    hiddenStyle.size = Size(width: px(90), height: px(30))
    let hidden = tree.newNode(style: hiddenStyle, children: [])

    let c = fixedChild(tree, w: 40, h: 50)
    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.size = Size(width: px(300), height: px(50))
    let root = tree.newNode(style: rootStyle, children: [a, hidden, c])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    #expect(tree.layout(a) == LayoutRect(x: 0, y: 0, width: 60, height: 20))
    // c sits where it would with only two children — NOT at 150.
    #expect(tree.layout(c) == LayoutRect(x: 60, y: 0, width: 40, height: 50))
    // The hidden item is never positioned or sized at all.
    #expect(tree.layout(hidden) == LayoutRect(x: 0, y: 0, width: 0, height: 0))
}

/// Stored rects are absolute to the root, never relative to the parent.
///
/// `roundLayout` carries no cross-rect state: its whole no-drift guarantee rests
/// on callers handing it absolute coordinates. A flex engine naturally computes
/// parent-relative positions, so switching to them would look harmless here and
/// silently reintroduce the accumulation `roundLayout` exists to prevent. The
/// grandchildren below sit at a non-zero offset in BOTH axes, so this test fails
/// the moment anyone stores a parent-relative rect.
@Test func nestedContainersStoreAbsoluteNotRelativeCoordinates() {
    let tree = LayoutTree()
    let spacer = fixedChild(tree, w: 30, h: 40)

    let g1 = fixedChild(tree, w: 20, h: 25)
    let g2 = fixedChild(tree, w: 20, h: 35)
    var midStyle = Style()
    midStyle.flexDirection = .column
    midStyle.size = Size(width: px(100), height: px(150))
    let mid = tree.newNode(style: midStyle, children: [g1, g2])

    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.size = Size(width: px(300), height: px(200))
    let root = tree.newNode(style: rootStyle, children: [spacer, mid])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    #expect(tree.layout(mid) == LayoutRect(x: 30, y: 0, width: 100, height: 150))
    // Relative coordinates would put g1 at x = 0 and g2 at (0, 25).
    #expect(tree.layout(g1) == LayoutRect(x: 30, y: 0,  width: 20, height: 25))
    #expect(tree.layout(g2) == LayoutRect(x: 30, y: 25, width: 20, height: 35))
}

/// `computeLayout` must apply a rounding pass to every stored rect, not just the
/// leaves: three children of 100/3 in a 100-wide row must close exactly on the
/// parent (33 + 34 + 33 = 100), which only holds if rounding walks the whole
/// cumulative main axis rather than rounding each width independently.
/// 3 children of 100/3 in a 100 row, and a fractional-width **grandchild**
/// nested inside the middle one.
///
/// The grandchild is not decoration: `roundStoredRects` claims to round
/// "every node's stored rect, depth-first" (`FlexEngine.swift`), but the only
/// other nested fixture in this suite —
/// `nestedContainersStoreAbsoluteNotRelativeCoordinates` — is entirely
/// integral, so it cannot tell a depth-first rounding pass from one that
/// rounds only the root's direct children. Deleting `roundStoredRects`'s
/// `for kid in tree.children(node)` recursion left this whole file green
/// before `grandchild` was added to the loop below; it reddens now because
/// `grandchild`'s absolute position inherits `b`'s fractional raw origin.
@Test func computeLayoutRoundsEveryStoredRect() {
    let tree = LayoutTree()
    // A fractional-width leaf, nested one level inside `b` below.
    let grandchild = fixedChild(tree, w: 100.0 / 7.0, h: 5)
    func third(children: [LayoutNodeID] = []) -> LayoutNodeID {
        var s = Style()
        s.size = Size(width: MetalUICore.Dimension.length(.pixels(Pixels(Float(100.0 / 3.0)))),
                      height: px(10))
        return tree.newNode(style: s, children: children)
    }
    let a = third(), b = third(children: [grandchild]), c = third()
    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.size = Size(width: px(100), height: px(10))
    let root = tree.newNode(style: rootStyle, children: [a, b, c])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(400), height: .definite(400)))

    // Every stored value is a whole number — nothing fractional survives,
    // at the root's direct children (a, b, c) or two levels down (grandchild).
    for n in [root, a, b, c, grandchild] {
        let r = tree.layout(n)
        #expect(r.x == r.x.rounded(), "x \(r.x) not rounded")
        #expect(r.width == r.width.rounded(), "width \(r.width) not rounded")
    }
    #expect(tree.layout(a).width + tree.layout(b).width + tree.layout(c).width == 100)
    #expect(tree.layout(c).x + tree.layout(c).width == 100)
}

/// An auto-sized item's **main** size is zero — it does not inherit the
/// container's extent.
///
/// Replaces `autoSizedChildTakesItsContainersExtentForNow`. The Task 7
/// fallback (auto -> container extent) is deleted here and never comes back:
/// this pins `collectItems`' wiring through `computeLayout`, not §9.2 itself
/// (that's `FlexBaseSizeTests.autoBasisWithNoMeasureFunctionIsZero`, which
/// pins the free function directly). A child with no measure function and no
/// definite size is zero because nothing measures content yet — not because
/// flex base size is unimplemented, which it now is. This is the one test
/// that would redden if `collectItems` ever reverted to a container-extent
/// main size.
///
/// **Retargeted when §9.4 stretch landed (ruling AL-2).** This test used to
/// assert *both* axes were 0, and the cross half of that is now wrong CSS:
/// `align-items` defaults to `stretch`, so an auto cross size fills the line
/// and WebKit gives this child the container's full 100. The main-axis
/// assertion is the one that guards ruling FS-1, and stretch does not touch the
/// main axis — so it stays exactly as it was, and the old cross assertion is
/// replaced by the stretched value rather than deleted. Deleting it would drop
/// the FS-1 guarantee at the moment it stopped being visible.
@Test func autoSizedChildTakesNoMainSizeButStretchesOnTheCross() {
    let tree = LayoutTree()
    let kid = tree.newNode(style: Style(), children: [])   // size defaults to .auto
    var rootStyle = Style()
    rootStyle.size = Size(width: px(300), height: px(100))
    let root = tree.newNode(style: rootStyle, children: [kid])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    // Main axis (this root is a row): no content, no basis, no fallback.
    #expect(tree.layout(kid).width == 0)
    // Cross axis: §9.4 stretch fills the line, and 100 is the container's, not
    // the 600 of the offered available space — an item never reads `available`.
    #expect(tree.layout(kid).height == 100)
}

/// The root fills the space it is offered; a flex item does not.
///
/// `computeLayout`'s `available:` parameter would otherwise be read by nothing
/// once the Task 7 item fallback is deleted — an inert public parameter that no
/// existing test can see, since every other root in this suite has an explicit
/// size. The two expectations here are the two halves of one mutation: making
/// the root ignore `available` reddens the first, and restoring the item
/// fallback reddens the second.
///
/// **Retargeted when §9.4 stretch landed (ruling AL-2).** The item half used to
/// assert a 0x0 rect. The cross axis is now 600 — the root's height, which the
/// root itself took from `available` — so the item assertion is split: `width`
/// still pins ruling FS-1 (an auto **main** size is 0, never the container's
/// extent), and the height pins stretch. The FS-1 half survives because stretch
/// leaves the main axis alone; asserting the whole rect again would conflate the
/// two rules, and asserting only the width would drop stretch's coverage here.
@Test func autoSizedRootTakesTheAvailableSpaceButAnAutoItemDoesNot() {
    let tree = LayoutTree()
    let kid = tree.newNode(style: Style(), children: [])      // size defaults to .auto
    let root = tree.newNode(style: Style(), children: [kid])  // ditto

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    #expect(tree.layout(root) == LayoutRect(x: 0, y: 0, width: 800, height: 600))
    #expect(tree.layout(kid).x == 0)
    #expect(tree.layout(kid).y == 0)
    // FS-1: the item does NOT take the offered 800 on its main axis.
    #expect(tree.layout(kid).width == 0)
    // §9.4: it does stretch to the line's cross extent, which is the root's 600.
    #expect(tree.layout(kid).height == 600)
}

/// `minSize` and `maxSize` are live `Style` properties, and the engine must
/// honour them when resolving a node's size.
///
/// `clamp` is unit-tested as a pure function in ResolveTests, but nothing
/// checked that `resolveNodeSize` actually *calls* it: deleting the `clamp` call
/// left the entire suite green before this test. The third child also pins
/// CSS §10.4's tie-break — when min and max conflict, **min wins**.
@Test func minAndMaxSizeClampAChildAndMinWinsOnConflict() {
    let tree = LayoutTree()

    // Asked for 200 wide, capped at 80. Asked for 10 tall, floored at 30.
    var cappedStyle = Style()
    cappedStyle.size = Size(width: px(200), height: px(10))
    cappedStyle.maxSize = Size(width: px(80), height: autoDim)
    cappedStyle.minSize = Size(width: autoDim, height: px(30))
    let capped = tree.newNode(style: cappedStyle, children: [])

    // min 120 > max 50: CSS §10.4 says the minimum wins, so 120 — not 50, and
    // not the requested 10.
    var conflictedStyle = Style()
    conflictedStyle.size = Size(width: px(10), height: px(20))
    conflictedStyle.minSize = Size(width: px(120), height: autoDim)
    conflictedStyle.maxSize = Size(width: px(50), height: autoDim)
    let conflicted = tree.newNode(style: conflictedStyle, children: [])

    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.size = Size(width: px(400), height: px(200))
    let root = tree.newNode(style: rootStyle, children: [capped, conflicted])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    #expect(tree.layout(capped) == LayoutRect(x: 0, y: 0, width: 80, height: 30))
    // Positioned after the *clamped* 80, not after the requested 200.
    #expect(tree.layout(conflicted) == LayoutRect(x: 80, y: 0, width: 120, height: 20))
}

@Test func rowOfFixedChildrenMatchesWebKit() throws {
    let golden = try loadGolden("flex_row_three_fixed")
    let (tree, root, x, y, z) = threeFixedChildren(direction: .row, width: 300, height: 50)
    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    assertMatchesGolden(tree,
                        ids: [root: "root", x: "x", y: "y", z: "z"],
                        golden: golden, tolerance: 0.1)
}

@Test func columnOfFixedChildrenMatchesWebKit() throws {
    let golden = try loadGolden("flex_column_three_fixed")
    let (tree, root, x, y, z) = threeFixedChildren(direction: .column, width: 120, height: 400)
    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    assertMatchesGolden(tree,
                        ids: [root: "root", x: "x", y: "y", z: "z"],
                        golden: golden, tolerance: 0.1)
}

@Test func rowWithGapMatchesWebKit() throws {
    let golden = try loadGolden("flex_row_gap")
    let (tree, root, x, y, z) = threeFixedChildren(direction: .row, width: 300, height: 50, gap: 12)
    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    assertMatchesGolden(tree,
                        ids: [root: "root", x: "x", y: "y", z: "z"],
                        golden: golden, tolerance: 0.1)
}

/// Three items of differing main sizes, an explicit cross size on every one,
/// and strictly positive free space — the shape shared by all four
/// `justify-content` fixtures. `justify` is applied to the root; the row
/// fixtures share sizes (40/70/50 wide, 40 tall in a 400-wide container), the
/// column fixture inverts the axes (40/70/50 tall, 60 wide in a 400-tall
/// container).
private func threeJustifiedChildren(
    direction: FlexDirection,
    justify: JustifyContent,
    width: Double,
    height: Double
) -> (LayoutTree, root: LayoutNodeID, a: LayoutNodeID, b: LayoutNodeID, c: LayoutNodeID) {
    let tree = LayoutTree()
    let isRow = direction.isRow
    let a = isRow ? fixedChild(tree, w: 40, h: 40) : fixedChild(tree, w: 60, h: 40)
    let b = isRow ? fixedChild(tree, w: 70, h: 40) : fixedChild(tree, w: 60, h: 70)
    let c = isRow ? fixedChild(tree, w: 50, h: 40) : fixedChild(tree, w: 60, h: 50)
    var rootStyle = Style()
    rootStyle.flexDirection = direction
    rootStyle.justifyContent = justify
    rootStyle.size = Size(width: px(width), height: px(height))
    let root = tree.newNode(style: rootStyle, children: [a, b, c])
    return (tree, root, a, b, c)
}

@Test func rowJustifySpaceBetweenMatchesWebKit() throws {
    let golden = try loadGolden("flex_row_justify_between")
    let (tree, root, a, b, c) = threeJustifiedChildren(direction: .row, justify: .spaceBetween,
                                                        width: 400, height: 40)
    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    assertMatchesGolden(tree,
                        ids: [root: "root", a: "a", b: "b", c: "c"],
                        golden: golden, tolerance: 0.1)
}

@Test func rowJustifySpaceAroundMatchesWebKit() throws {
    let golden = try loadGolden("flex_row_justify_around")
    let (tree, root, a, b, c) = threeJustifiedChildren(direction: .row, justify: .spaceAround,
                                                        width: 400, height: 40)
    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    assertMatchesGolden(tree,
                        ids: [root: "root", a: "a", b: "b", c: "c"],
                        golden: golden, tolerance: 0.1)
}

@Test func rowJustifySpaceEvenlyMatchesWebKit() throws {
    let golden = try loadGolden("flex_row_justify_evenly")
    let (tree, root, a, b, c) = threeJustifiedChildren(direction: .row, justify: .spaceEvenly,
                                                        width: 400, height: 40)
    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    assertMatchesGolden(tree,
                        ids: [root: "root", a: "a", b: "b", c: "c"],
                        golden: golden, tolerance: 0.1)
}

@Test func columnJustifyCenterMatchesWebKit() throws {
    let golden = try loadGolden("flex_column_justify_center")
    let (tree, root, a, b, c) = threeJustifiedChildren(direction: .column, justify: .center,
                                                        width: 60, height: 400)
    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    assertMatchesGolden(tree,
                        ids: [root: "root", a: "a", b: "b", c: "c"],
                        golden: golden, tolerance: 0.1)
}

/// Three children of distinct heights (20/60/40), none equal to the 100px
/// line — a uniform-height fixture would give `align-items: center` the same
/// answer as every other alignment and pin nothing. Full-rect comparison so
/// `x`/`width` (main axis, from Task 1) and `y`/`height` (cross axis, this
/// task) are both checked in the one assertion.
@Test func rowAlignCenterMatchesWebKit() throws {
    let golden = try loadGolden("flex_row_align_center")
    let tree = LayoutTree()
    let a = fixedChild(tree, w: 40, h: 20)
    let b = fixedChild(tree, w: 70, h: 60)
    let c = fixedChild(tree, w: 50, h: 40)
    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.alignItems = .center
    rootStyle.size = Size(width: px(400), height: px(100))
    let root = tree.newNode(style: rootStyle, children: [a, b, c])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    assertMatchesGolden(tree,
                        ids: [root: "root", a: "a", b: "b", c: "c"],
                        golden: golden, tolerance: 0.1)
}

/// `align-items: flex-end` on the container, with `align-self: center`
/// overriding it on the middle child — pins both the container default and
/// the per-item override against WebKit in one fixture. Same distinct
/// heights (20/60/40) as `flex_row_align_center`.
@Test func rowAlignEndWithSelfOverrideMatchesWebKit() throws {
    let golden = try loadGolden("flex_row_align_end_with_self")
    let tree = LayoutTree()
    let a = fixedChild(tree, w: 40, h: 20)
    var bStyle = Style()
    bStyle.size = Size(width: px(70), height: px(60))
    bStyle.alignSelf = .center
    let bNode = tree.newNode(style: bStyle, children: [])
    let c = fixedChild(tree, w: 50, h: 40)
    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.alignItems = .flexEnd
    rootStyle.size = Size(width: px(400), height: px(100))
    let root = tree.newNode(style: rootStyle, children: [a, bNode, c])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    assertMatchesGolden(tree,
                        ids: [root: "root", a: "a", bNode: "b", c: "c"],
                        golden: golden, tolerance: 0.1)
}

/// A column container's cross axis is horizontal, not vertical — and the two
/// tests above cannot exercise that: both are rows, so `isRow` is `true` in
/// every assertion this file made before this test existed. That leaves two
/// mutations completely unguarded: forcing `containerCross` (in both
/// `collectItems` and `positionItems`) to always read `.height` instead of
/// picking by axis, and dropping the column branch of the cross-offset
/// computation to a bare `0` (`x = containerOrigin.0 + (isRow ? cursor : 0)`).
/// Both pass the whole 130-test suite without this. Three children of
/// distinct widths (40/90/60), none equal to the 200px cross extent, so
/// `align-items: flex-end` gives each of them a different `x` — a uniform
/// width would make every alignment produce the same answer here too.
@Test func columnAlignFlexEndOffsetsEachChildByItsOwnWidth() {
    let tree = LayoutTree()
    let a = fixedChild(tree, w: 40, h: 30)
    let b = fixedChild(tree, w: 90, h: 40)
    let c = fixedChild(tree, w: 60, h: 50)
    var rootStyle = Style()
    rootStyle.flexDirection = .column
    rootStyle.alignItems = .flexEnd
    rootStyle.size = Size(width: px(200), height: px(300))
    let root = tree.newNode(style: rootStyle, children: [a, b, c])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    // x = containerCross (200) - itemCross, a different number per child.
    #expect(tree.layout(a) == LayoutRect(x: 160, y: 0,  width: 40, height: 30))
    #expect(tree.layout(b) == LayoutRect(x: 110, y: 30, width: 90, height: 40))
    #expect(tree.layout(c) == LayoutRect(x: 140, y: 70, width: 60, height: 50))
}

/// The only end-to-end guard on the trailing gap. Ruling AL-5.
///
/// Identical to `rowJustifySpaceBetweenMatchesWebKit`, but with `gap: 12`
/// added on both the Swift tree and the fixture — and its golden's numbers
/// are **byte-identical** to the no-gap fixture's (0 / 160 / 350 either way).
/// That is not a mistake and this test is not a duplicate: `gap` cancels
/// *precisely* under a correct `space-between`, because the stride is
/// `(containerMain - content) / (n - 1)` and `content` has already subtracted
/// the gaps out of `containerMain` before that division runs. Two fixtures,
/// same numbers, on purpose — see the comment inside
/// `flex_row_justify_between_gap.html` for the full explanation.
///
/// `lineContentSizeCountsGapsBetweenItemsOnly` (in AlignmentTests.swift) tests
/// `lineContentSize` in isolation and never calls `positionItems` or
/// `computeLayout`, so it cannot catch a trailing-gap regression that lives in
/// the wiring between them. This test can: reintroducing the trailing gap
/// (`gap * count` instead of `count - 1` in `lineContentSize`) shifts every
/// non-root node here by `gap / (n - 1)` = 6px, far above the 0.1pt
/// comparison tolerance, while `rowJustifySpaceBetweenMatchesWebKit` (no gap)
/// stays green throughout. Do not delete this as a copy of that test.
@Test func rowJustifySpaceBetweenWithGapMatchesWebKit() throws {
    let golden = try loadGolden("flex_row_justify_between_gap")
    let tree = LayoutTree()
    let a = fixedChild(tree, w: 40, h: 40)
    let b = fixedChild(tree, w: 70, h: 40)
    let c = fixedChild(tree, w: 50, h: 40)
    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.justifyContent = .spaceBetween
    rootStyle.gap = Axes(both: .pixels(Pixels(12)))
    rootStyle.size = Size(width: px(400), height: px(40))
    let root = tree.newNode(style: rootStyle, children: [a, b, c])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    assertMatchesGolden(tree,
                        ids: [root: "root", a: "a", b: "b", c: "c"],
                        golden: golden, tolerance: 0.1)
}

/// WebKit's word on §9.4 stretch — and the only comparison in the corpus that
/// can tell "stretch everything" apart from "stretch the right things".
///
/// Every other fixture is uniform on the cross axis: either all its children
/// declare a height or none does, so a rule ignoring `align-self` and a rule
/// ignoring the `auto` check both reproduce every committed golden. This one
/// gives four children four different cross outcomes in one 100px line, and
/// WebKit confirms all four: `a` (auto) stretches to 100, `b` keeps its
/// definite 30, `c` opts out via `align-self: flex-start` and stays at its
/// content's 0, and `d` stretches into its `max-height: 60`.
///
/// `d` is the only browser-verified evidence that a stretched size is clamped
/// by the item's cross max; without it that clause rests on hand-written
/// arithmetic alone. Deleting `.c`'s `align-self` line and regenerating moves
/// `c.height` from 0 to 100 — verified, so the opt-out is genuinely load-bearing
/// here rather than merely present.
@Test func rowStretchMixedMatchesWebKit() throws {
    let golden = try loadGolden("flex_row_stretch_mixed")
    let tree = LayoutTree()

    var aStyle = Style()                                  // auto height: stretches
    aStyle.size = Size(width: px(60), height: .auto)
    let a = tree.newNode(style: aStyle, children: [])

    let b = fixedChild(tree, w: 70, h: 30)                // definite height wins

    var cStyle = Style()                                  // opts out of stretch
    cStyle.size = Size(width: px(50), height: .auto)
    cStyle.alignSelf = .flexStart
    let c = tree.newNode(style: cStyle, children: [])

    var dStyle = Style()                                  // stretches, then clamps
    dStyle.size = Size(width: px(80), height: .auto)
    dStyle.maxSize = Size(width: .auto, height: px(60))
    let d = tree.newNode(style: dStyle, children: [])

    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.size = Size(width: px(400), height: px(100))
    let root = tree.newNode(style: rootStyle, children: [a, b, c, d])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    assertMatchesGolden(tree,
                        ids: [root: "root", a: "a", b: "b", c: "c", d: "d"],
                        golden: golden, tolerance: 0.1)
}
