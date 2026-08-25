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
/// after the last. Deleting the `+ gap` term in `layoutChildren` left the whole
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
@Test func computeLayoutRoundsEveryStoredRect() {
    // 3 children of 100/3 in a 100 row. Cumulative rounding must make the
    // widths 33/34/33 and close the row exactly on the parent.
    let tree = LayoutTree()
    func third() -> LayoutNodeID {
        var s = Style()
        s.size = Size(width: MetalUICore.Dimension.length(.pixels(Pixels(Float(100.0 / 3.0)))),
                      height: px(10))
        return tree.newNode(style: s, children: [])
    }
    let a = third(), b = third(), c = third()
    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.size = Size(width: px(100), height: px(10))
    let root = tree.newNode(style: rootStyle, children: [a, b, c])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(400), height: .definite(400)))

    // Every stored value is a whole number — nothing fractional survives.
    for n in [root, a, b, c] {
        let r = tree.layout(n)
        #expect(r.x == r.x.rounded(), "x \(r.x) not rounded")
        #expect(r.width == r.width.rounded(), "width \(r.width) not rounded")
    }
    #expect(tree.layout(a).width + tree.layout(b).width + tree.layout(c).width == 100)
    #expect(tree.layout(c).x + tree.layout(c).width == 100)
}

/// Replaces `autoSizedChildTakesItsContainersExtentForNow`. The Task 7
/// fallback (auto -> container extent) is deleted here; the real content
/// size arrives with flex base size in Task 2. Zero is the honest
/// placeholder: visibly wrong rather than plausibly wrong.
@Test func autoSizedChildIsZeroUntilFlexBaseSizeLands() {
    let tree = LayoutTree()
    let kid = tree.newNode(style: Style(), children: [])   // size defaults to .auto
    var rootStyle = Style()
    rootStyle.size = Size(width: px(300), height: px(100))
    let root = tree.newNode(style: rootStyle, children: [kid])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    #expect(tree.layout(kid).width == 0)
    #expect(tree.layout(kid).height == 0)
}

/// The root fills the space it is offered; a flex item does not.
///
/// `computeLayout`'s `available:` parameter would otherwise be read by nothing
/// once the Task 7 item fallback is deleted — an inert public parameter that no
/// existing test can see, since every other root in this suite has an explicit
/// size. The two expectations here are the two halves of one mutation: making
/// the root ignore `available` reddens the first, and restoring the item
/// fallback reddens the second.
@Test func autoSizedRootTakesTheAvailableSpaceButAnAutoItemDoesNot() {
    let tree = LayoutTree()
    let kid = tree.newNode(style: Style(), children: [])      // size defaults to .auto
    let root = tree.newNode(style: Style(), children: [kid])  // ditto

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    #expect(tree.layout(root) == LayoutRect(x: 0, y: 0, width: 800, height: 600))
    #expect(tree.layout(kid) == LayoutRect(x: 0, y: 0, width: 0, height: 0))
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
