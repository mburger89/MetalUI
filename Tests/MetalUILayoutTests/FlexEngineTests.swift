import Testing
import Foundation
import MetalUICore
@testable import MetalUILayout

/// Build a tree by hand, run the CSS engine, and compare every node against the
/// numbers it must produce.
///
/// Until plan task 7's stage 7a this file also compared sixteen trees against
/// committed WebKit goldens. Those goldens, their comparisons and the oracle
/// that generated them were retired by that stage: record §42's §4 names, for
/// each golden, the native test arm that replaces it or the CSS-only concept it
/// was deleted with. The tests left here are the CSS engine's own, and retire
/// with it (stage 7b).

/// Qualified: this file imports Foundation, whose Measurement API also exports a
/// `Dimension` type, so the bare name is ambiguous here.
private func px(_ v: Double) -> MetalUICore.Dimension { .length(.pixels(Pixels(Float(v)))) }
private let autoDim: MetalUICore.Dimension = .auto

private func fixedChild(_ tree: LayoutTree, w: Double, h: Double) -> LayoutNodeID {
    var s = Style()
    s.size = Size(width: px(w), height: px(h))
    return tree.newNode(style: s, children: [])
}

/// The three-child shape of the retired goldens `flex_row_three_fixed`,
/// `flex_column_three_fixed` and `flex_row_gap` (stage 7a, record §42).
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

/// Ruling FS-3 — an item's automatic minimum is the SMALLER of its specified
/// and content size suggestions, and both halves are live.
///
/// **This test was `aContainerIsNotFlooredByItsSpecifiedSizeUnlikeWebKit` and
/// asserted the divergence rather than the agreement.** It was CLAUDE.md
/// divergence 5's only pin, written so that implementing FS-3 would produce a
/// red test rather than a surprise; the sizing milestone's Task 6 implemented
/// it, this test reddened on exactly the five expectations below, and every
/// one of the five now holds WebKit's number instead of the engine's old one.
/// Divergence 5 is closed.
///
/// **All three cases are kept and the third has changed job.** It used to be
/// the differential that named the cause — an explicit `min-width: 0` making
/// the two engines agree where the automatic minimum made them disagree. With
/// the rule implemented there is nothing left to differentiate, so it is now
/// the **control**: it shows that an explicit `min-width` still *replaces* the
/// automatic minimum outright rather than combining with it, which is the one
/// thing a "floor at min(specified, content, explicit)" misreading would break
/// while leaving cases 1 and 2 green.
///
/// The three cases were not redundant with `specifiedSizeSuggestionMatchesWebKit`
/// (the browser fixture, retired with its golden by stage 7a, record §42): that
/// one pinned the 130 case end to end against a golden, and this one pins all
/// three side by side with the `min-width: 0` control the fixture could not
/// carry — a fixture holds one tree.
@Test func anItemsAutomaticMinimumIsTheSmallerOfItsSpecifiedAndContentSizes() {
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

    // `.a` floors at `min(100, 200)` — its own specified width — and `.b`
    // takes the 50 that is left. WebKit: a=100, b=50, and `.b` starts at 100.
    // Flooring at the content 200 instead squeezes `.b` out of the root
    // entirely (b=0 at x=200), which is what this engine did before FS-3.
    let (t1, a1, b1) = build(aWidth: 100, aMin: autoDim)
    #expect(t1.layout(a1).width == 100)
    #expect(t1.layout(b1).width == 50)
    #expect(t1.layout(b1).x == 100)

    // The floor MOVES WITH the specified width: 130 in, 130 out, and `.b` gets
    // the remaining 20. This is the discriminating case — a floor stuck at the
    // content 200 does not move between it and the case above, and a rule that
    // ignored the content suggestion would let `.a` shrink to 75 in both.
    let (t2, a2, b2) = build(aWidth: 130, aMin: autoDim)
    #expect(t2.layout(a2).width == 130)
    #expect(t2.layout(b2).width == 20)

    // The CONTROL. An explicit `min-width: 0` REPLACES the automatic minimum
    // rather than combining with it, so neither suggestion applies and both
    // items shrink freely: 100 and 100 into 150 gives 75 and 75. Unchanged by
    // FS-3, and it is what a "combine the explicit minimum with the automatic
    // one" misreading would break while leaving both cases above green.
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
/// The browser evidence was `FitContentFixtureTests` and its six fixtures,
/// retired with the goldens by stage 7a (record §42); this test was the
/// hand-written companion that carried the differential a single golden could
/// not.
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

/// **An item's cross size is measured from its USED main size, after §9.7 has
/// flexed it — ruling TX-H, fixed.** Measured against WebKit on the same
/// tree, and now agreeing on both:
///
/// | container | WebKit | this engine |
/// |---|---|---|
/// | `row; align-items: flex-start` | `120x40` | agree |
/// | `row` (stretch) | `120x600` | agree |
///
/// CSS Flexbox orders this explicitly: §9.7 resolves the flexible lengths
/// (step 6) and *then* §9.4 step 7 determines each item's hypothetical cross
/// size "by performing layout with the **used** main size". `collectItems`
/// still measures `ownCross` from the item's HYPOTHETICAL main size — a line's
/// own cross extent has to be measured from something before §9.7 can even
/// run — but `layOutChildren` now re-measures every non-stretched auto-cross
/// item a second time, per line, once `resolveFlexibleLengths` has resolved
/// its USED main size (`itemFitContentCrossSize`, shared by both call sites).
/// `.a` here shrinks from 200 (max-content, one row of four) to the root's
/// 120 by ordinary main-axis flexing, which wraps it to two rows, so the
/// second measurement gives 40 where the first gave 20.
///
/// Invisible before M2 for the reason the helper above states — an item whose
/// content does not reflow has the same cross size at every main size — and it
/// is what used to make `Row { Text(longLabel) }` one line tall while being
/// narrower than one line.
///
/// **Renamed from `anItemsCrossSizeIsMeasuredBeforeFlexingUnlikeWebKit`,
/// which asserted the wrong answer on purpose and said so in its own
/// message** — this is the same differential inverted, not a new test:
/// `ownCross` is what named the site before the fix (the `stretch` half was
/// always an agreement, which is what pointed at this function rather than at
/// the line calling it), so the new name keeps naming it now that the
/// hypothetical-vs-used distinction it names is resolved rather than open.
@Test func anItemsCrossSizeIsMeasuredFromItsUsedMainSizeMatchingWebKit() {
    let (flexStart, a) = wrappingChildInANarrowContainer(direction: .row, align: .flexStart)
    #expect(flexStart.layout(a).width == 120)
    #expect(flexStart.layout(a).height == 40)

    // Stretch takes its cross size from the line rather than from the item, so
    // it is unaffected — the differential that names `ownCross` as the site,
    // kept unchanged from before the fix.
    let (stretched, b) = wrappingChildInANarrowContainer(direction: .row, align: nil)
    #expect(stretched.layout(b).width == 120)
    #expect(stretched.layout(b).height == 600)
}

// MARK: - Ruling SZ-O — TX-H's re-measure must reach the LINE and the CONTAINER

/// **An `auto`-cross container reports the height its flexed child actually
/// occupies.** Ruling SZ-O, and the first of two pins on the same defect.
///
/// The test above establishes that the *item* is 40 tall. This one asks what
/// its **parent** says, and the two answers disagreed for the whole of the
/// milestone that introduced TX-H: the re-measure wrote `item.crossSize` and
/// nothing recomputed `contentCross`, which had already been summed from the
/// pre-flex item cross sizes. So an `auto`-height row containing a 40-tall
/// child measured **20** — a child painting 20pt outside a parent that is not
/// clipping it, and a number no assertion in the 752-test suite could see,
/// because every existing cross-size pin reads the ITEM.
///
/// Measured against live WebKit through the oracle on this exact tree
/// (`#outer { display: flex; width: 120px; align-items: flex-start }` wrapping
/// `.a { display: flex; flex-wrap: wrap }` of four 50x20, `html, body
/// { height: 100% }`, viewport 800x600):
///
/// | | before SZ-O | after SZ-O | WebKit |
/// |---|---|---|---|
/// | `outer` | **120x20** | 120x40 | **120x40** |
/// | `.a` | 120x40 | 120x40 | 120x40 |
///
/// **`align-items: flex-start` is load-bearing and so is the `auto` height.**
/// Under `stretch` the item takes the line's extent and never enters
/// `itemFitContentCrossSize` at all (this milestone's Task 8 measured a whole
/// performance benchmark against that dead configuration — practices doc shape
/// 15), and with a declared height on `outer` the container reports the
/// declaration rather than `contentCross` and the defect is invisible.
///
/// No fixture holds this: it is expressible in HTML, but the corpus's job is
/// the browser comparison and `crossSizeAfterFlexPropagatesToTheLine` below
/// carries the wrapping half. This pair is the hand-written companion, on
/// `anItemsCrossSizeIsMeasuredFromItsUsedMainSizeMatchingWebKit`'s footing.
@Test func crossSizeAfterFlexPropagatesToAnAutoContainer() {
    let tree = LayoutTree(generation: 0)
    let kids = (0..<4).map { _ in fixedChild(tree, w: 50, h: 20) }
    var innerStyle = Style()
    innerStyle.flexWrap = .wrap
    let a = tree.newNode(style: innerStyle, children: kids)

    var outerStyle = Style()
    outerStyle.flexDirection = .row
    outerStyle.alignItems = .flexStart
    outerStyle.size = Size(width: px(120), height: .auto)
    let outer = tree.newNode(style: outerStyle, children: [a])

    computeLayout(tree, root: outer,
                  available: AvailableSpaceSize(width: .definite(800), height: .maxContent))

    // The item, which TX-H alone already got right.
    #expect(tree.layout(a).height == 40)
    // The container, which it did not. 20 here is the pre-flex extent.
    #expect(tree.layout(outer).height == 40)
    #expect(tree.layout(outer).width == 120)
}

/// **A wrapping container's second line starts below a first line that grew
/// after flexing, rather than overlapping it.** Ruling SZ-O, second pin, and
/// the sharper of the two: this one is a visible rendering defect rather than
/// a wrong number, because the two siblings are drawn on top of one another.
///
/// A wrapping row 120 wide. `.a` is declared 200, so it exceeds the line budget
/// and lines alone; §9.7 then shrinks it to 120, which wraps its own four
/// 50x20 children onto two rows and makes it 40 tall. `.b` is 120 wide and
/// takes the second line, whose `y` is line one's cross extent. `FlexLine`'s
/// `crossSize` was fixed before §9.7 ran, so line one measured **20** and `.b`
/// was drawn 20pt up, inside `.a`.
///
/// Measured against live WebKit through the oracle on this exact tree
/// (`#root { display: flex; flex-wrap: wrap; width: 120px; height: 600px;
/// align-items: flex-start; align-content: flex-start }`, viewport 800x600):
///
/// | | before SZ-O | after SZ-O | WebKit |
/// |---|---|---|---|
/// | `.a` | (0,0) 120x40 | (0,0) 120x40 | (0,0) 120x40 |
/// | `.b` | (0,**20**) 120x30 | (0,40) 120x30 | (0,**40**) 120x30 |
///
/// **`align-content: flex-start` is load-bearing, and NOT in the way the first
/// draft of this comment claimed — the claim was measured and was wrong.** It
/// said that removing the declaration leaves the test green under the pre-SZ-O
/// engine. Measured, with the reorder reverted: `.b` lands at **295**, not at
/// 20 and not at 40, so the test still reddens. Under the default `stretch`
/// the two lines absorb the container's leftover cross space between them
/// (pre-fix `(600 - (20 + 30)) / 2 = 275`, so line one is `20 + 275 = 295`;
/// post-fix `(600 - (40 + 30)) / 2 = 265`, so line one is `40 + 265 = 305`),
/// which means the two engines still differ — by the same 10pt the line grew,
/// halved. What `flex-start` buys is that `.b`'s `y` **is** line one's cross
/// extent, so the assertion reads `40` against `20` rather than `305` against
/// `295`: the numbers name the defect instead of encoding a distribution on
/// top of it. That is a legibility property, not a discrimination one, and
/// saying so is the difference between a comment a reader can rely on and one
/// that sounds finished.
@Test func crossSizeAfterFlexPropagatesToTheLine() {
    let tree = LayoutTree(generation: 0)
    let kids = (0..<4).map { _ in fixedChild(tree, w: 50, h: 20) }
    var aStyle = Style()
    aStyle.flexWrap = .wrap
    aStyle.size = Size(width: px(200), height: .auto)
    let a = tree.newNode(style: aStyle, children: kids)

    let b = fixedChild(tree, w: 120, h: 30)

    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.flexWrap = .wrap
    rootStyle.alignItems = .flexStart
    rootStyle.alignContent = .flexStart
    rootStyle.size = Size(width: px(120), height: px(600))
    let root = tree.newNode(style: rootStyle, children: [a, b])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    #expect(tree.layout(a).y == 0)
    #expect(tree.layout(a).height == 40)
    // 20 here is the overlap: `.b` drawn on top of the bottom half of `.a`.
    #expect(tree.layout(b).y == 40)
    #expect(tree.layout(b).height == 30)
}

/// The widths a measure closure was offered by §4.5's content-suggestion probe
/// alone. That probe is the only caller that asks a leaf `.minContent` on the
/// HEIGHT axis in these layouts. `flexBaseSize` asks `.maxContent` and the
/// cross-size measures pass a definite height, so filtering on it isolates the
/// probe. `MeasureFunction` is `@Sendable`, and layout runs synchronously on
/// the caller's thread, hence the unchecked box.
private final class ProbeWidths: @unchecked Sendable {
    var offered: [AvailableSpace] = []
}

/// A column's §4.5 probe offers the item's used width: clamped by its cross
/// `min-width`, and `.maxContent` when the container has no cross extent.
///
/// `sizing_column_content_suggestion` pins the margin, declared-width and
/// `max-width` parts against WebKit. The `min-width` clamp cannot have a golden
/// yet: WebKit's `min-width: 200px` shape (`.a` 20, `.b` 40) is also wrong in
/// §9.2's flex base size, which this change does not touch, so the layout
/// stays wrong whatever the probe offers. So the oracle here is the closure,
/// not WebKit: it reports the width it was asked at.
///
/// Red against the engine whose probe offered `.maxContent` in a column:
/// case A recorded `.maxContent`, not `.definite(200)`. Case B is the other
/// direction and passed there too: an indefinite container must keep the old
/// max-content fallback.
@Test func aColumnsContentSuggestionProbeOffersTheClampedWidthOrMaxContent() throws {
    func column(width: Double?) -> (LayoutTree, LayoutNodeID, ProbeWidths) {
        let tree = LayoutTree(generation: 0)
        let widths = ProbeWidths()
        var leafStyle = Style()
        leafStyle.minSize = Size(width: px(200), height: .auto)
        let leaf = tree.newLeaf(style: leafStyle) { _, available in
            if case .minContent = available.height { widths.offered.append(available.width) }
            return SizeD(width: 10, height: 10)
        }
        var s = Style()
        s.display = .flex
        s.flexDirection = .column
        if let width { s.size = Size(width: px(width), height: px(60)) }
        return (tree, tree.newNode(style: s, children: [leaf]), widths)
    }

    // A — a definite 120: stretch's arithmetic, clamped up to the 200 minimum.
    let (definiteTree, definiteRoot, definite) = column(width: 120)
    computeLayout(definiteTree, root: definiteRoot,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))
    try #require(!definite.offered.isEmpty)
    #expect(Set(definite.offered) == [.definite(200)])

    // B — no cross extent: the fallback stays max-content.
    let (autoTree, autoRoot, indefinite) = column(width: nil)
    _ = measureNode(LayoutContext(rootFontSize: 16), autoTree, autoRoot,
                    known: .unspecified,
                    available: AvailableSpaceSize(width: .maxContent, height: .maxContent),
                    containingBlockWidth: nil)
    try #require(!indefinite.offered.isEmpty)
    #expect(Set(indefinite.offered) == [.maxContent])
}
