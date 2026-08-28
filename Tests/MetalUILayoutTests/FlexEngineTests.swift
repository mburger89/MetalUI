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
    let tree = LayoutTree(generation: 0)
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
    let tree = LayoutTree(generation: 0)
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
    let tree = LayoutTree(generation: 0)
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
    let tree = LayoutTree(generation: 0)
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
    let tree = LayoutTree(generation: 0)
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
    let tree = LayoutTree(generation: 0)
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
    let tree = LayoutTree(generation: 0)
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
/// (that's `FlexBaseSizeTests.autoBasisWithNoMeasureFunctionOrChildrenIsZero`,
/// renamed by content sizing because the reason changed while the number did
/// not — see its own comment — and which
/// pins the free function directly). A child with no measure function, no
/// definite size and **no children** is zero because that is what measuring it
/// returns — its own padding and border — not because flex base size is
/// unimplemented, and no longer because nothing measures content. This is the
/// one test that would redden if `collectItems` ever reverted to a
/// container-extent main size.
///
/// **Retargeted when §9.4 stretch landed (ruling AL-2).** This test used to
/// assert *both* axes were 0, and the cross half of that is now wrong CSS:
/// `align-items` defaults to `stretch`, so an auto cross size fills the line
/// and WebKit gives this child the container's full 100. The main-axis
/// assertion is the one that guards ruling FS-1, and stretch does not touch the
/// main axis — so it stays exactly as it was, and the old cross assertion is
/// replaced by the stretched value rather than deleted. Deleting it would drop
/// the FS-1 guarantee at the moment it stopped being visible.
///
/// **FS-1 lives in `flexBaseSize`, not `resolveNodeSize`.** To check this test
/// still binds, make `flexBaseSize`'s step 3 `return containerMain ?? 0` ahead
/// of the `measureNode` call; that reddens here. **The mutation used to be
/// spelled against `guard let measure … else { return 0 }`, and that line no
/// longer exists** — content sizing replaced it with the `measureNode` call, so
/// the instruction is respelled rather than dropped. Mutating
/// `resolveNodeSize`'s `resolved ?? 0` does **not** redden this — an item's
/// main size has not come from that function since the flex-sizing milestone,
/// and pointing at it is the natural mistake. (It was mine, during that task's
/// review.)
@Test func autoSizedChildTakesNoMainSizeButStretchesOnTheCross() {
    let tree = LayoutTree(generation: 0)
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
///
/// **Content sizing deliberately left these numbers alone, and that was
/// measured before it was decided.** Making an `auto` root axis shrink-wrap to
/// its content — CSS's answer for a block box's block axis, WebKit **800 x 40**
/// for an 800x600 viewport holding one 100x40 child — was implemented and
/// reverted: it reddened six element-pipeline and frame-loop tests, because a
/// `Row { … }` rendered into a `Frame` declares no height and its root would
/// collapse. Ruling EP-5 takes SwiftUI's answer where the two differ, and
/// SwiftUI's root fills the window. See `resolveRootSize`.
@Test func autoSizedRootTakesTheAvailableSpaceButAnAutoItemDoesNot() {
    let tree = LayoutTree(generation: 0)
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

/// An `auto` root axis with **no offered extent to take** measures its content.
///
/// This is the one thing content sizing changed in `resolveRootSize`, and it is
/// the fourth of the four constant-substituting sites: the branch below was a
/// hardcoded **0**, so a root offered `.maxContent` laid out at 0x0 and every
/// descendant with it. Both axes are exercised and with **different numbers**,
/// so an axis transposition in the measure call cannot pass: the row's content
/// is 100 wide and 40 tall.
///
/// The sibling above is what keeps this honest — it offers definite extents and
/// asserts they still win, so "measure when there is nothing offered" cannot
/// quietly become "measure always".
@Test func anAutoRootWithNoOfferedExtentMeasuresItsContent() {
    let tree = LayoutTree(generation: 0)
    var kidStyle = Style()
    kidStyle.size = Size(width: px(100), height: px(40))
    let kid = tree.newNode(style: kidStyle, children: [])
    let root = tree.newNode(style: Style(), children: [kid])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .maxContent, height: .maxContent))

    #expect(tree.layout(root) == LayoutRect(x: 0, y: 0, width: 100, height: 40))
    #expect(tree.layout(kid) == LayoutRect(x: 0, y: 0, width: 100, height: 40))
}

/// CSS Sizing §4.5's automatic minimum, for a **container** item — the largest
/// behavioural consequence of wiring `measureNode` into `collectItems`.
///
/// `min-width: auto` is CSS's default on every flex item and was **floorless**
/// for a container until content sizing: the content suggestion came from
/// `tree.measure(kid)`, which is `nil` for anything without a `MeasureFunction`,
/// so a container shrank straight through its own children.
///
/// **Both halves are measured in WebKit, on the same tree**, because the
/// unconstrained answer is what makes the floor visible:
///
/// ```html
/// #root { display: flex; width: 160px; height: 60px; }
/// .a { display: flex; flex: 0 1 200px; }   /* holds a 120px child */
/// .b { width: 120px; height: 20px; }
/// ```
///
///     min-width on .a   WebKit          why
///     auto (default)    a=120, b=40     a's content floors it at 120
///     0                 a=100, b=60     bases 200:120 shrink 160 as 100:60
///
/// The differential is the point: with the floor absent the engine lands on
/// 100/60, which is a *plausible* answer, not an obviously broken one. Only the
/// pair distinguishes them.
///
/// **`.b` is deliberately an empty div with a definite `width`**, and it must
/// NOT be floored at 120: §4.5's automatic minimum is
/// `min(specified suggestion, content suggestion)` and an empty div's content
/// suggestion is 0. WebKit shrinks it to 40. That is what keeps ruling FS-3's
/// missing half honest here — implementing the specified suggestion alone, or
/// passing the item's own size down as `known`, would freeze `b` at 120 and
/// redden this.
@Test func aContainerItemIsFlooredByItsChildrensWidth() {
    func build(minWidth: MetalUICore.Dimension) -> (LayoutTree, LayoutNodeID, LayoutNodeID, LayoutNodeID) {
        let tree = LayoutTree(generation: 0)
        let g = fixedChild(tree, w: 120, h: 20)
        var aStyle = Style()
        aStyle.flexDirection = .row
        aStyle.flexBasis = px(200)
        aStyle.flexGrow = 0
        aStyle.flexShrink = 1
        aStyle.minSize = Size(width: minWidth, height: autoDim)
        let a = tree.newNode(style: aStyle, children: [g])
        let b = fixedChild(tree, w: 120, h: 20)
        var rootStyle = Style()
        rootStyle.flexDirection = .row
        rootStyle.size = Size(width: px(160), height: px(60))
        let root = tree.newNode(style: rootStyle, children: [a, b])
        computeLayout(tree, root: root,
                      available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))
        return (tree, a, b, g)
    }

    // `min-width: auto` — the CSS default, and the floor is now live.
    let (floored, a1, b1, g1) = build(minWidth: autoDim)
    #expect(floored.layout(a1).width == 120)
    #expect(floored.layout(b1).width == 40)
    #expect(floored.layout(b1).x == 120)
    #expect(floored.layout(g1).width == 120)

    // `min-width: 0` — an explicit minimum REPLACES the automatic one, so the
    // same tree shrinks freely. This is the differential, not a second example.
    let (free, a2, b2, _) = build(minWidth: px(0))
    #expect(free.layout(a2).width == 100)
    #expect(free.layout(b2).width == 60)
}

/// **Ruling FS-3** (see CLAUDE.md's "known divergences", the fifth) — pins a
/// deliberate divergence from CSS and from WebKit, not a bug.
///
/// CSS Sizing §4.5's automatic minimum is
/// `min(specified size suggestion, content size suggestion)`. This engine
/// implements the **content** half only — content sizing made it live for
/// containers, and that is what turned FS-3 from a dormant gap into a
/// measurable disagreement: an item is floored by its children even when its
/// own definite `width` says it may be smaller.
///
/// **Measured against live WebKit**, on the tree this test builds:
///
/// ```html
/// #root { display: flex; width: 150px; height: 60px; }
/// .a { display: flex; width: 100px; }   /* holds a 200px child */
/// .b { width: 100px; height: 20px; }
/// ```
///
///     .a's style          WebKit        this engine    why
///     width: 100px        a=100, b=50   a=200, b=0     min(100, 200) vs 200
///     width: 130px        a=130, b=20   a=200, b=0     the floor ignores it
///     width: 100px+min:0  a=75,  b=75   a=75,  b=75    no automatic minimum
///
/// The middle row is the sharpest form: WebKit's floor **tracks the specified
/// width** and this engine's does not move at all, because it is the child's
/// 200 in both cases. The third row is the differential that identifies the
/// cause — an explicit `min-width: 0` replaces the automatic minimum, both
/// engines shrink 100/100 into 150 as 75/75, and they agree exactly.
///
/// **Not implemented here, and the reason is reach, not effort** — the same
/// one that kept ruling BM-4 out of the box-model milestone. The specified size
/// suggestion changes an item's *floor*, which the freeze loop consumes and
/// every ancestor then sees as a different stored size. It belongs in a sizing
/// plan with the corpus regenerated behind it.
///
/// **Deliberately no fixture and no golden**, on the same footing as WebKit's
/// flex sub-one clause: a golden would encode this engine's answer as correct,
/// and a future fix should move nothing in the corpus. This test is the only
/// pin, so implementing FS-3 must redden exactly it — verified by mutation.
/// Seven `flex: 1 1 0` children splitting 100px, against WebKit —
/// **`flex_row_seven_equal`'s first engine-vs-golden comparison.**
///
/// It was the one fixture of 61 with a golden and no comparison test: read only
/// by `committedGoldensMatchTheBrowser`, which measures the browser and checks
/// it against a file the browser produced. That is taxonomy shape 3 — a
/// committed artifact constrained by nothing that consumes it — and
/// `ContentSizingFixtureTests`' own header names the shape while the corpus held
/// a live instance of it.
///
/// **It is the second non-integral fixture an engine comparison reads, and that
/// is the point of adding it here rather than anywhere else.** 100 split seven
/// ways is 14.28125 per child in WebKit and 14.2857… in the engine, so every
/// number in this test exists only after `roundLayout` has run on both sides:
/// the raw values do not agree and the rounded ones do. `flex_row_shrink` was
/// the sole fixture holding that distinction up (see `Rounding.swift`, which
/// says so and is corrected by this test), and a single fixture holding a
/// distinction is how a blind spot comes back — give `flex_row_shrink` bases
/// that divide evenly and nothing would have noticed.
///
/// Killed by the rounding mutation `(r.x + r.width).rounded()` →
/// `.rounded(.down)` in `roundLayout`: measured `--no-parallel`, that reddens
/// this test alongside `committedGoldensMatchTheBrowser`, moving `c1` 15→14,
/// `c2` 14→13, `c5` 15→14 and `c6` 14→13 — the same four boxes on both sides,
/// which is the evidence that engine and browser are being compared in the same
/// space rather than each in its own.
@Test func sevenEqualChildrenMatchWebKit() throws {
    let golden = try loadGolden("flex_row_seven_equal")
    let tree = LayoutTree(generation: 0)

    var kidStyle = Style()
    kidStyle.flexGrow = 1
    kidStyle.flexShrink = 1
    kidStyle.flexBasis = px(0)
    let kids = (0..<7).map { _ in tree.newNode(style: kidStyle, children: []) }

    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.size = Size(width: px(100), height: px(20))
    let root = tree.newNode(style: rootStyle, children: kids)

    // The fixture's own viewport (`allFixtures` in GeneratorTests), not the
    // 800x600 most of the corpus uses.
    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(400), height: .definite(200)))

    var ids: [LayoutNodeID: String] = [root: "root"]
    for (i, kid) in kids.enumerated() { ids[kid] = "c\(i)" }
    // Tolerance 0.1, not 1: the whole subject here is which whole pixel each
    // edge lands on, and a tolerance of 1 would accept the mutation above.
    assertMatchesGolden(tree, ids: ids, golden: golden, tolerance: 0.1)
}

@Test func aContainerIsNotFlooredByItsSpecifiedSizeUnlikeWebKit() {
    /// The same tree three ways: `.a` is a container 200 wide on the inside and
    /// `aWidth` wide by declaration, `.b` is a leaf, and the root is too small
    /// for both.
    func build(aWidth: Double, aMin: MetalUICore.Dimension)
        -> (LayoutTree, LayoutNodeID, LayoutNodeID) {
        let tree = LayoutTree(generation: 0)
        let g = fixedChild(tree, w: 200, h: 20)
        var aStyle = Style()
        aStyle.flexDirection = .row
        aStyle.size = Size(width: px(aWidth), height: autoDim)
        aStyle.minSize = Size(width: aMin, height: autoDim)
        let a = tree.newNode(style: aStyle, children: [g])
        let b = fixedChild(tree, w: 100, h: 20)
        var rootStyle = Style()
        rootStyle.flexDirection = .row
        rootStyle.size = Size(width: px(150), height: px(60))
        let root = tree.newNode(style: rootStyle, children: [a, b])
        computeLayout(tree, root: root,
                      available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))
        return (tree, a, b)
    }

    // WebKit: a=100, b=50. Here the floor is the child's 200, so `.a` cannot
    // shrink at all and `.b` is squeezed out of the root entirely.
    let (t1, a1, b1) = build(aWidth: 100, aMin: autoDim)
    #expect(t1.layout(a1).width == 200)
    #expect(t1.layout(b1).width == 0)
    #expect(t1.layout(b1).x == 200)

    // WebKit: a=130, b=20 — its floor moved with the specified width. Ours did
    // not move at all, which is the divergence stated as a differential.
    let (t2, a2, b2) = build(aWidth: 130, aMin: autoDim)
    #expect(t2.layout(a2).width == 200)
    #expect(t2.layout(b2).width == 0)

    // `min-width: 0` replaces the automatic minimum, so no suggestion of either
    // kind applies and the two engines agree: 100 and 100 shrink into 150.
    let (t3, a3, b3) = build(aWidth: 100, aMin: px(0))
    #expect(t3.layout(a3).width == 75)
    #expect(t3.layout(b3).width == 75)
}

/// `minSize` and `maxSize` are live `Style` properties, and the engine must
/// honour them when resolving a node's size.
///
/// `clamp` is unit-tested as a pure function in ResolveTests, but nothing
/// checked that `resolveNodeSize` actually *calls* it: deleting the `clamp` call
/// left the entire suite green before this test. The third child also pins
/// CSS §10.4's tie-break — when min and max conflict, **min wins**.
@Test func minAndMaxSizeClampAChildAndMinWinsOnConflict() {
    let tree = LayoutTree(generation: 0)

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
    let tree = LayoutTree(generation: 0)
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
    let tree = LayoutTree(generation: 0)
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
    let tree = LayoutTree(generation: 0)
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
    let tree = LayoutTree(generation: 0)
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
    let tree = LayoutTree(generation: 0)
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
    let tree = LayoutTree(generation: 0)

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

/// `row-reverse` against WebKit: three unequal children, no `justify-content`
/// override, so this pins the *default* `flex-start` reading against the
/// reversed axis rather than something an explicit justify value might mask.
///
/// Same 40/70/50-in-400 shape as `rowReversePacksFromTheEndAndFlipsJustifyContent`
/// in AlignmentTests.swift, but this one is browser-verified rather than
/// hand-computed.
@Test func rowReverseMatchesWebKit() throws {
    let golden = try loadGolden("flex_row_reverse")
    let tree = LayoutTree(generation: 0)
    let a = fixedChild(tree, w: 40, h: 40)
    let b = fixedChild(tree, w: 70, h: 40)
    let c = fixedChild(tree, w: 50, h: 40)
    var rootStyle = Style()
    rootStyle.flexDirection = .rowReverse
    rootStyle.size = Size(width: px(400), height: px(40))
    let root = tree.newNode(style: rootStyle, children: [a, b, c])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    assertMatchesGolden(tree,
                        ids: [root: "root", a: "a", b: "b", c: "c"],
                        golden: golden, tolerance: 0.1)
}

/// `column-reverse` composed with `justify-content: flex-end` against WebKit —
/// the fixture where a sign error in either flip shows, because a bug in only
/// one of the two would still place the packed run at a plausible-looking
/// edge.
///
/// Also the AL-7 fixture: `.a` has an explicit `height` (a definite **main**
/// size in a column, which no other fixture in the corpus provides) and an
/// `auto` width, so it stretches to the container's cross extent. `.b` and
/// `.c` have explicit widths and do not.
@Test func columnReverseJustifyEndMatchesWebKit() throws {
    let golden = try loadGolden("flex_column_reverse_justify_end")
    let tree = LayoutTree(generation: 0)

    var aStyle = Style()                      // definite main size, auto cross: stretches
    aStyle.size = Size(width: .auto, height: px(40))
    let a = tree.newNode(style: aStyle, children: [])

    let b = fixedChild(tree, w: 60, h: 70)
    let c = fixedChild(tree, w: 80, h: 50)

    var rootStyle = Style()
    rootStyle.flexDirection = .columnReverse
    rootStyle.justifyContent = .flexEnd
    rootStyle.size = Size(width: px(100), height: px(400))
    let root = tree.newNode(style: rootStyle, children: [a, b, c])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    assertMatchesGolden(tree,
                        ids: [root: "root", a: "a", b: "b", c: "c"],
                        golden: golden, tolerance: 0.1)
}

/// Padding and border inset the content box against WebKit: a row with four
/// distinct padding edges and four distinct (and different-from-padding)
/// border edges, two fixed children and a third that grows into whatever the
/// content box leaves over. `flex_row_padding_border` is the fixture; see its
/// HTML for why every edge and both boxes differ.
@Test func rowPaddingAndBorderMatchesWebKit() throws {
    let golden = try loadGolden("flex_row_padding_border")
    let tree = LayoutTree(generation: 0)
    let a = fixedChild(tree, w: 50, h: 30)
    let b = fixedChild(tree, w: 60, h: 30)

    var cStyle = Style()
    cStyle.flexGrow = 1
    cStyle.flexShrink = 1
    cStyle.flexBasis = px(0)
    cStyle.size = Size(width: .auto, height: px(30))
    let c = tree.newNode(style: cStyle, children: [])

    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.size = Size(width: px(400), height: px(100))
    rootStyle.padding = Edges(top: .pixels(Pixels(20)), right: .pixels(Pixels(8)),
                              bottom: .pixels(Pixels(4)), left: .pixels(Pixels(16)))
    rootStyle.border = Edges(top: .pixels(Pixels(5)), right: .pixels(Pixels(3)),
                             bottom: .pixels(Pixels(2)), left: .pixels(Pixels(7)))
    let root = tree.newNode(style: rootStyle, children: [a, b, c])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    assertMatchesGolden(tree,
                        ids: [root: "root", a: "a", b: "b", c: "c"],
                        golden: golden, tolerance: 0.1)
}

/// The column counterpart: `flex_column_padding_asymmetric` uses fixed-pixel
/// padding and border only — **it does not exercise percentage padding**, and
/// nothing in the corpus does yet (Task 3 adds that fixture). Its shape
/// (120x400, strongly non-square) is chosen so that fixture, when it lands,
/// can tell a percentage resolved against width from one resolved against
/// height; on its own, today, the non-square shape buys nothing. What this
/// fixture *does* pin now: every child has an `auto` width, so stretch
/// filling the reduced *content* width — not the border-box width — is the
/// strongest single check that the content box reached the cross axis.
@Test func columnPaddingAsymmetricMatchesWebKit() throws {
    let golden = try loadGolden("flex_column_padding_asymmetric")
    let tree = LayoutTree(generation: 0)

    func autoWidthChild(h: Double) -> LayoutNodeID {
        var s = Style()
        s.size = Size(width: .auto, height: px(h))
        return tree.newNode(style: s, children: [])
    }
    let a = autoWidthChild(h: 40)
    let b = autoWidthChild(h: 90)
    let c = autoWidthChild(h: 60)

    var rootStyle = Style()
    rootStyle.flexDirection = .column
    rootStyle.size = Size(width: px(120), height: px(400))
    rootStyle.padding = Edges(top: .pixels(Pixels(12)), right: .pixels(Pixels(30)),
                              bottom: .pixels(Pixels(6)), left: .pixels(Pixels(18)))
    rootStyle.border = Edges(top: .pixels(Pixels(4)), right: .pixels(Pixels(2)),
                             bottom: .pixels(Pixels(8)), left: .pixels(Pixels(6)))
    let root = tree.newNode(style: rootStyle, children: [a, b, c])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    assertMatchesGolden(tree,
                        ids: [root: "root", a: "a", b: "b", c: "c"],
                        golden: golden, tolerance: 0.1)
}

// MARK: - Two `auto` cross-size rules, both found by M2's text leaf

/// The tree both tests below use, and the reason they can be written without
/// text at all: `.a` is a **wrapping** container, so — like a run of text and
/// unlike every empty div in the corpus — its min-content width (50, one item)
/// and its max-content width (200, four items) are different numbers, and its
/// height depends on which of them it is laid out at.
///
/// `width` was hardcoded to 120 while both tests below recorded divergences.
/// It is a parameter now because fixing divergence 6 made 120 unable to
/// distinguish the rule it pins: where `min-content <= available <= max-content`
/// shrink-to-fit answers exactly `available`, which is also **stretch's**
/// answer. Only a container narrower than the item's min-content separates them.
private func wrappingChildInANarrowContainer(
    width: Double = 120, direction: FlexDirection, align: AlignItems?
) -> (LayoutTree, LayoutNodeID) {
    let tree = LayoutTree(generation: 0)
    let kids = (0..<4).map { _ in fixedChild(tree, w: 50, h: 20) }
    var innerStyle = Style()
    innerStyle.flexWrap = .wrap
    let a = tree.newNode(style: innerStyle, children: kids)

    var rootStyle = Style()
    rootStyle.flexDirection = direction
    rootStyle.alignItems = align
    rootStyle.size = Size(width: px(width), height: px(600))
    let root = tree.newNode(style: rootStyle, children: [a])
    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(width), height: .definite(600)))
    return (tree, a)
}

/// **A column's `auto` cross size is shrink-to-fit, and agrees with WebKit.**
/// Ruling TX-H. Measured against WebKit through the oracle, on the tree above:
///
/// | container | WebKit | this engine |
/// |---|---|---|
/// | `120 wide; column; align-items: center` | `120x40` at `x = 0` | agree |
/// | `120 wide; column` (stretch) | `120x40` | agree |
/// | `30 wide; column; align-items: center` | `50x80` at `x = -10` | agree |
/// | `30 wide; column` (stretch) | `30x80` at `x = 0` | agree |
///
/// **This test asserted the opposite until divergence 6 was fixed**, and it was
/// named `anAutoCrossSizeIsMaxContentRatherThanFitContentUnlikeWebKit`: it
/// expected `200x40` at `x = -40` for the first row, because `collectItems`'
/// `ownCross` measured max-content on whichever axis was the cross one. That is
/// right in a **row**, whose cross axis is the block axis, and wrong in a
/// **column**, whose cross axis is the inline axis — CSS sizes an `auto` inline
/// axis by shrink-to-fit, `min(max(min-content, available), max-content)`. The
/// numbers here are WebKit's now rather than a recorded disagreement with it.
///
/// **The 30-wide rows are not decoration and were added with the fix.** Where
/// `min-content <= available <= max-content`, fit-content answers exactly
/// `available` — which is what a stretched item gets too, so the 120-wide rows
/// alone would pass against an implementation that stretched everything and
/// never measured. At 30 the min-content floor binds, `.a` overflows to 50, and
/// centre / stretch give different widths *and* different x.
///
/// The browser evidence is `FitContentFixtureTests` and its six fixtures; this
/// test is the hand-written companion that carries the differential a single
/// golden cannot.
@Test func anAutoCrossSizeInAColumnIsFitContentLikeWebKit() {
    let (centred, a) = wrappingChildInANarrowContainer(direction: .column, align: .center)
    #expect(centred.layout(a).width == 120)
    #expect(centred.layout(a).height == 40)
    #expect(centred.layout(a).x == 0)

    let (stretched, b) = wrappingChildInANarrowContainer(direction: .column, align: nil)
    #expect(stretched.layout(b).width == 120)
    #expect(stretched.layout(b).height == 40)

    // Narrower than one 50pt item, so `max(min-content, available)` binds and
    // the two alignments separate. A stretch-everything implementation gives
    // `30x80` at `x = 0` for both.
    let (floored, c) = wrappingChildInANarrowContainer(width: 30, direction: .column,
                                                       align: .center)
    #expect(floored.layout(c).width == 50)
    #expect(floored.layout(c).height == 80)
    #expect(floored.layout(c).x == -10)

    let (flooredStretch, d) = wrappingChildInANarrowContainer(width: 30, direction: .column,
                                                              align: nil)
    #expect(flooredStretch.layout(d).width == 30)
    #expect(flooredStretch.layout(d).height == 80)
    #expect(flooredStretch.layout(d).x == 0)
}

/// **An item's cross size is measured from its HYPOTHETICAL main size, before
/// §9.7 flexes it; CSS measures it from the USED main size, after.** Measured
/// against WebKit on the same tree:
///
/// | container | WebKit | this engine |
/// |---|---|---|
/// | `row; align-items: flex-start` | `120x40` | **`120x20`** |
/// | `row` (stretch) | `120x600` | `120x600` — agree |
///
/// CSS Flexbox orders this explicitly: §9.7 resolves the flexible lengths
/// (step 6) and *then* §9.4 step 7 determines each item's hypothetical cross
/// size "by performing layout with the **used** main size". `collectItems`
/// computes `ownCross` in the same pass that computes the hypothetical main
/// size, so an item that is about to shrink keeps the cross size it had at its
/// unshrunk width: `.a` here is laid out 120 wide and 20 tall, one row of four
/// 50pt items in a space that only fits two.
///
/// Invisible before M2 for the reason the helper above states — an item whose
/// content does not reflow has the same cross size at every main size — and it
/// is what makes `Row { Text(longLabel) }` one line tall while being narrower
/// than one line.
///
/// **Still not fixed, and untouched by divergence 6's fix**, which is confined
/// to `!isRow`: this tree is a ROW, so its cross axis is the block axis and
/// max-content is the right rule there. What is wrong here is *when* the
/// measurement happens, not what it measures. Fixing it is a reordering of the
/// main algorithm and every golden in the corpus is downstream of it. No
/// fixture and no golden encodes it, deliberately: a golden would record this
/// engine's answer as correct and a future fix should move nothing in the
/// corpus.
@Test func anItemsCrossSizeIsMeasuredBeforeFlexingUnlikeWebKit() {
    let (flexStart, a) = wrappingChildInANarrowContainer(direction: .row, align: .flexStart)
    #expect(flexStart.layout(a).width == 120)
    #expect(flexStart.layout(a).height == 20)

    // Stretch takes its cross size from the line rather than from the item, so
    // it is unaffected — the differential that names `ownCross` as the site.
    let (stretched, b) = wrappingChildInANarrowContainer(direction: .row, align: nil)
    #expect(stretched.layout(b).width == 120)
    #expect(stretched.layout(b).height == 600)
}
