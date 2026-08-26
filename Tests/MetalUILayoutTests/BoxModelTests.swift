import Testing
import Foundation
import MetalUICore
@testable import MetalUILayout

private func px(_ v: Double) -> MetalUICore.Dimension { .length(.pixels(Pixels(Float(v)))) }
private func pxL(_ v: Double) -> Length { .pixels(Pixels(Float(v))) }
/// A percentage as a `Dimension` (for `size`/`margin`) and as a `Length` (for
/// `padding`/`border`). The argument is a fraction, not a hundredth: `0.10` is
/// CSS's `10%`.
private func pct(_ f: Float) -> MetalUICore.Dimension { .length(.percent(f)) }
private func pctL(_ f: Float) -> Length { .percent(f) }

private func fixedChild(_ tree: LayoutTree, w: Double, h: Double) -> LayoutNodeID {
    var s = Style()
    s.size = Size(width: px(w), height: px(h))
    return tree.newNode(style: s, children: [])
}

/// A container's padding and border inset its children's *origin*.
///
/// Four different edge values, and padding differs from border: with
/// `padding: 20 8 4 16` and `border: 5 3 2 7` the content box starts at
/// (16 + 7, 20 + 5) = (23, 25). Uniform values would let a transposed axis or
/// a dropped edge pass.
///
/// **The name says "origin", not "and shrinks the content box", on purpose.**
/// Both children here have a fixed size, so neither their size nor their
/// packing position depends on whether the container's main-axis budget was
/// actually reduced: mutation-testing this task found that "inset the origin
/// but do NOT shrink the content box" leaves this exact test green. The
/// shrink half is covered elsewhere — `growDistributesTheContentBoxNotTheBorderBox`
/// (main axis) and `stretchFillsTheContentBoxNotTheBorderBox` (cross axis),
/// both below — and this test should be read together with those two, not as
/// a complete guard by itself.
@Test func paddingAndBorderInsetTheOriginOfEachChild() {
    let tree = LayoutTree(generation: 0)
    let a = fixedChild(tree, w: 50, h: 30)
    let b = fixedChild(tree, w: 60, h: 30)
    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.size = Size(width: px(400), height: px(100))
    rootStyle.padding = Edges(top: pxL(20), right: pxL(8), bottom: pxL(4), left: pxL(16))
    rootStyle.border = Edges(top: pxL(5), right: pxL(3), bottom: pxL(2), left: pxL(7))
    let root = tree.newNode(style: rootStyle, children: [a, b])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    // The root's own border box is untouched — border-box sizing.
    #expect(tree.layout(root) == LayoutRect(x: 0, y: 0, width: 400, height: 100))
    // First child at the content-box origin, not (0, 0).
    #expect(tree.layout(a) == LayoutRect(x: 23, y: 25, width: 50, height: 30))
    // Second child packs after the first, still inside the content box.
    #expect(tree.layout(b) == LayoutRect(x: 73, y: 25, width: 60, height: 30))
}

/// The content box is what a stretched item fills, not the border box.
///
/// Cross-axis stretch must use the reduced extent: 100 tall with 20/4 padding
/// and 5/2 border leaves 69, not 100.
@Test func stretchFillsTheContentBoxNotTheBorderBox() {
    let tree = LayoutTree(generation: 0)
    var kidStyle = Style()
    kidStyle.size = Size(width: px(50), height: .auto)   // auto cross -> stretches
    let kid = tree.newNode(style: kidStyle, children: [])

    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.size = Size(width: px(400), height: px(100))
    rootStyle.padding = Edges(top: pxL(20), right: pxL(8), bottom: pxL(4), left: pxL(16))
    rootStyle.border = Edges(top: pxL(5), right: pxL(3), bottom: pxL(2), left: pxL(7))
    let root = tree.newNode(style: rootStyle, children: [kid])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    #expect(tree.layout(kid).height == 69)
    #expect(tree.layout(kid).y == 25)
}

/// A grow item's free space comes from the content box, so padding reduces what
/// it can grow into.
@Test func growDistributesTheContentBoxNotTheBorderBox() {
    let tree = LayoutTree(generation: 0)
    var s = Style()
    s.flexGrow = 1
    s.flexBasis = px(0)
    s.size = Size(width: .auto, height: px(20))
    let kid = tree.newNode(style: s, children: [])

    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.size = Size(width: px(400), height: px(100))
    rootStyle.padding = Edges(top: pxL(0), right: pxL(8), bottom: pxL(0), left: pxL(16))
    rootStyle.border = Edges(top: pxL(0), right: pxL(3), bottom: pxL(0), left: pxL(7))
    let root = tree.newNode(style: rootStyle, children: [kid])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    // 400 - (16 + 7 + 8 + 3) = 366
    #expect(tree.layout(kid).width == 366)
    #expect(tree.layout(kid).x == 23)
}

/// **Ruling BM-4** (see CLAUDE.md's "known divergences") — pins a deliberate
/// divergence from CSS, not a bug, and closes the mutation that deletes
/// `contentBox`'s `max(0, …)` guard.
///
/// CSS's real answer when padding + border exceeds the container's specified
/// size on an axis is to **grow the border box itself**, never to let the
/// content box go negative: `box-sizing: border-box` defines the used size as
/// `max(specified, padding + border)`. Measured against live WebKit for
/// `width: 100px; height: 80px; padding: 60px 50px; border-width: 10px` with
/// one auto-sized child: **WebKit renders the root at 120×140**, not 100×80.
/// Horizontal padding+border is 50 + 50 + 10 + 10 = 120, exceeding the
/// specified width of 100; vertical is 60 + 60 + 10 + 10 = 140, exceeding the
/// specified height of 80 — so WebKit grows the border box to fit them
/// exactly: 120 wide, 140 tall.
///
/// This engine does not grow the border box — implementing that belongs in
/// sizing (`resolveNodeSize`/`flexBaseSize`), which moves a node's *stored*
/// size and has reach far beyond `contentBox` (the freeze loop, every
/// ancestor). Out of scope for the box-model task. Instead `contentBox`
/// clamps the *content* box to zero and leaves the border box exactly as
/// specified, so the root here stays 100×80 — this test pins that choice.
///
/// Without `max(0, …)`, the content box's height goes negative (80 - 120 -
/// 20 = -60) and the stretched child inherits it *unclamped* — a negative
/// stored height — which is what actually reddens this test if the guard is
/// removed; the root's own rect does not move under that particular mutation,
/// since the guard lives downstream of it.
@Test func containerDoesNotGrowToFitOverconstrainedPaddingUnlikeWebKit() {
    let tree = LayoutTree(generation: 0)
    let a = tree.newNode(style: Style(), children: [])   // auto/auto: stretches on the cross

    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.size = Size(width: px(100), height: px(80))
    rootStyle.padding = Edges(top: pxL(60), right: pxL(50), bottom: pxL(60), left: pxL(50))
    rootStyle.border = Edges(top: pxL(10), right: pxL(10), bottom: pxL(10), left: pxL(10))
    let root = tree.newNode(style: rootStyle, children: [a])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    // WebKit: 120x140. We keep the specified border box, 100x80 — the pinned
    // divergence.
    #expect(tree.layout(root) == LayoutRect(x: 0, y: 0, width: 100, height: 80))
    // The child matches WebKit exactly (60, 70, 0, 0) even though the root
    // does not: its origin comes only from padding+border offsets, and its
    // clamped-to-zero content box happens to agree with WebKit's own here.
    #expect(tree.layout(a) == LayoutRect(x: 60, y: 70, width: 0, height: 0))
}

/// Margins consume main-axis space and offset the item's own rect.
///
/// Different margins per child, and margins on both ends, so neither "read the
/// wrong child's margin" nor "drop the trailing margin" can pass.
@Test func marginsConsumeMainAxisSpaceAndOffsetTheItem() {
    let tree = LayoutTree(generation: 0)
    var aStyle = Style()
    aStyle.size = Size(width: px(50), height: px(30))
    aStyle.margin = Edges(top: px(0), right: px(12), bottom: px(0), left: px(7))
    let a = tree.newNode(style: aStyle, children: [])

    var bStyle = Style()
    bStyle.size = Size(width: px(60), height: px(30))
    bStyle.margin = Edges(top: px(0), right: px(4), bottom: px(0), left: px(3))
    let b = tree.newNode(style: bStyle, children: [])

    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.size = Size(width: px(400), height: px(100))
    let root = tree.newNode(style: rootStyle, children: [a, b])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    // a starts after its 7 leading margin.
    #expect(tree.layout(a) == LayoutRect(x: 7, y: 0, width: 50, height: 30))
    // b starts after a's outer box (7 + 50 + 12 = 69) plus its own 3 leading.
    #expect(tree.layout(b) == LayoutRect(x: 72, y: 0, width: 60, height: 30))
}

/// A margin reduces what a grow item can grow into — proof the line's content
/// size counts margins rather than only border boxes.
@Test func marginsReduceTheSpaceAvailableToGrow() {
    let tree = LayoutTree(generation: 0)
    var s = Style()
    s.flexGrow = 1
    s.flexBasis = px(0)
    s.size = Size(width: .auto, height: px(20))
    s.margin = Edges(top: px(0), right: px(30), bottom: px(0), left: px(10))
    let kid = tree.newNode(style: s, children: [])

    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.size = Size(width: px(400), height: px(100))
    let root = tree.newNode(style: rootStyle, children: [kid])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    #expect(tree.layout(kid).width == 360)   // 400 - 10 - 30
    #expect(tree.layout(kid).x == 10)
}

/// Cross margins offset placement, and `align-items: flex-end` measures from the
/// content box's far edge minus the trailing margin.
@Test func crossMarginsOffsetAlignment() {
    let tree = LayoutTree(generation: 0)
    var s = Style()
    s.size = Size(width: px(50), height: px(30))
    s.margin = Edges(top: px(6), right: px(0), bottom: px(9), left: px(0))
    let kid = tree.newNode(style: s, children: [])

    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.alignItems = .flexEnd
    rootStyle.size = Size(width: px(400), height: px(100))
    let root = tree.newNode(style: rootStyle, children: [kid])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    // Outer cross box is 6 + 30 + 9 = 45; flex-end puts its far edge at 100, so
    // the outer box starts at 55 and the border box at 55 + 6 = 61.
    #expect(tree.layout(kid).y == 61)
}

/// `margin: auto` resolves to 0 — deliberately, and only until it is implemented.
///
/// CSS gives auto margins priority over `justify-content`: they absorb free
/// space first. This engine does not, and a silently-zero auto margin looks like
/// a working layout that is merely mis-centred. Recorded in CLAUDE.md's
/// inert-API table; delete that row when this changes.
///
/// **Three edges `.auto`, one a real `15px` — not all four `.auto`.** All-`.auto`
/// was fix-round-1's taxonomy-shape-8 hole: `(x: 0, y: 0)` is exactly what a
/// mutation that stops reading `Style.margin` *at all* would also produce, so
/// the test could not tell ".auto resolves to 0" apart from "margin is never
/// read." Mixing in `top: 15px` forces the distinction: `y` must be 15, proving
/// the real Dimension is read and threaded through, while `x` stays 0 only
/// because `.auto` — not because nothing is being read.
@Test func autoMarginsResolveToZeroForNow() {
    let tree = LayoutTree(generation: 0)
    var s = Style()
    s.size = Size(width: px(50), height: px(30))
    s.margin = Edges(top: px(15), right: .auto, bottom: .auto, left: .auto)
    let kid = tree.newNode(style: s, children: [])

    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.size = Size(width: px(400), height: px(100))
    let root = tree.newNode(style: rootStyle, children: [kid])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    // CSS would centre it at x = 175 (margin-left: auto and margin-right: auto
    // split the free space evenly). We put it at 0 and say so — `left: .auto`
    // resolves to 0, not to CSS's answer.
    #expect(tree.layout(kid).x == 0)
    // top: 15px is a REAL margin, not auto, and must be read: proof the zero
    // above is `.auto`-specific, not "margin is dead."
    #expect(tree.layout(kid).y == 15)
}

/// Margins against WebKit: three children, different asymmetric margins on
/// both axes, `justify-content: space-between`. `flex_row_margins` is the
/// fixture — see its HTML for why `space-between` matters: a content size
/// that drops margins moves every gap, not just the outer edges.
@Test func rowMarginsMatchWebKit() throws {
    let golden = try loadGolden("flex_row_margins")
    let tree = LayoutTree(generation: 0)

    func marginChild(w: Double, h: Double, top: Double, right: Double,
                     bottom: Double, left: Double) -> LayoutNodeID {
        var s = Style()
        s.size = Size(width: px(w), height: px(h))
        s.margin = Edges(top: px(top), right: px(right), bottom: px(bottom), left: px(left))
        return tree.newNode(style: s, children: [])
    }
    let a = marginChild(w: 40, h: 30, top: 5, right: 10, bottom: 15, left: 20)
    let b = marginChild(w: 50, h: 40, top: 2, right: 25, bottom: 8, left: 3)
    let c = marginChild(w: 60, h: 20, top: 12, right: 4, bottom: 1, left: 18)

    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.justifyContent = .spaceBetween
    rootStyle.size = Size(width: px(400), height: px(100))
    let root = tree.newNode(style: rootStyle, children: [a, b, c])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    assertMatchesGolden(tree,
                        ids: [root: "root", a: "a", b: "b", c: "c"],
                        golden: golden, tolerance: 0.1)
}

/// A `flex: 1 1 0` child with margins beside a fixed child with its own
/// (different) margins, against WebKit. `flex_row_margin_with_grow` is the
/// fixture; this is the browser-checked proof that the freeze loop's budget
/// is shrunk by BOTH children's total margin, not only the growing one's.
@Test func rowMarginWithGrowMatchesWebKit() throws {
    let golden = try loadGolden("flex_row_margin_with_grow")
    let tree = LayoutTree(generation: 0)

    var aStyle = Style()
    aStyle.flexGrow = 1
    aStyle.flexShrink = 1
    aStyle.flexBasis = px(0)
    aStyle.size = Size(width: .auto, height: px(40))
    aStyle.margin = Edges(top: px(4), right: px(15), bottom: px(6), left: px(9))
    let a = tree.newNode(style: aStyle, children: [])

    var bStyle = Style()
    bStyle.size = Size(width: px(80), height: px(40))
    bStyle.margin = Edges(top: px(10), right: px(2), bottom: px(3), left: px(20))
    let b = tree.newNode(style: bStyle, children: [])

    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.size = Size(width: px(400), height: px(60))
    let root = tree.newNode(style: rootStyle, children: [a, b])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    assertMatchesGolden(tree,
                        ids: [root: "root", a: "a", b: "b"],
                        golden: golden, tolerance: 0.1)
}

// MARK: - Fix round 1

/// **Fix-round-1 bug 1.** `row-reverse` applied a margin to the item's
/// physical RIGHT when it should have gone on the physical LEFT (and the
/// mirror error for `flex-end`-side margins), because the engine added the
/// physical `marginMain.leading` to the still flex-relative `cursor` before
/// converting to a physical coordinate — mixing a physical and a
/// flex-relative quantity.
///
/// These are the exact numbers measured against live WebKit for `row-reverse`,
/// `a{w:50, margin-left:10, margin-right:30}`, `b{w:60, margin-left:20,
/// margin-right:4}` in a 400px line: **WebKit gives `a.x = 320`,
/// `b.x = 246`.** The buggy code (`cursor + marginMain.leading` computed
/// BEFORE the reversal subtraction) gave `340` and `230` — each 20 off,
/// which is `a`'s `margin-left` landing on the wrong side.
@Test func reverseContainersApplyMarginsToThePhysicalEdge() {
    let tree = LayoutTree(generation: 0)
    var aStyle = Style()
    aStyle.size = Size(width: px(50), height: px(20))
    aStyle.margin = Edges(top: px(0), right: px(30), bottom: px(0), left: px(10))
    let a = tree.newNode(style: aStyle, children: [])

    var bStyle = Style()
    bStyle.size = Size(width: px(60), height: px(20))
    bStyle.margin = Edges(top: px(0), right: px(4), bottom: px(0), left: px(20))
    let b = tree.newNode(style: bStyle, children: [])

    var rootStyle = Style()
    rootStyle.flexDirection = .rowReverse
    rootStyle.size = Size(width: px(400), height: px(100))
    let root = tree.newNode(style: rootStyle, children: [a, b])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    #expect(tree.layout(a).x == 320)
    #expect(tree.layout(b).x == 246)
}

/// Row-reverse's counterpart pinned earlier: a fix verified only on the row
/// axis could still transpose top/bottom on the column axis (physical-start
/// there is `top`, not `left`) and nothing above would catch it. Same
/// numbers, transposed to height/margin-top/margin-bottom in a
/// `column-reverse` container.
@Test func columnReverseContainersApplyMarginsToThePhysicalEdge() {
    let tree = LayoutTree(generation: 0)
    var aStyle = Style()
    aStyle.size = Size(width: px(20), height: px(50))
    aStyle.margin = Edges(top: px(10), right: px(0), bottom: px(30), left: px(0))
    let a = tree.newNode(style: aStyle, children: [])

    var bStyle = Style()
    bStyle.size = Size(width: px(20), height: px(60))
    bStyle.margin = Edges(top: px(20), right: px(0), bottom: px(4), left: px(0))
    let b = tree.newNode(style: bStyle, children: [])

    var rootStyle = Style()
    rootStyle.flexDirection = .columnReverse
    rootStyle.size = Size(width: px(100), height: px(400))
    let root = tree.newNode(style: rootStyle, children: [a, b])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    #expect(tree.layout(a).y == 320)
    #expect(tree.layout(b).y == 246)
}

/// **Fix-round-1 bug 2.** A stretched item's cross size ignored its own
/// cross margins and filled the whole line, overflowing the container.
/// CSS stretches the margin box: the available border-box cross size is
/// `containerCross - marginCross.leading - marginCross.trailing`.
///
/// Matches the reviewer's WebKit probe exactly: row, `height: 100`, child
/// `height: auto; margin: 10px 0 25px` (no explicit cross size, so it
/// stretches). **WebKit gives `50x65`** (100 - 10 - 25); the buggy code
/// (`cross = clamp(containerCross, …)`, margins never subtracted) gave
/// `50x100` and overflowed the container by 35px.
@Test func stretchSubtractsCrossMarginsBeforeClamping() {
    let tree = LayoutTree(generation: 0)
    var s = Style()
    s.size = Size(width: px(50), height: .auto)
    s.margin = Edges(top: px(10), right: px(0), bottom: px(25), left: px(0))
    let kid = tree.newNode(style: s, children: [])

    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.size = Size(width: px(400), height: px(100))
    let root = tree.newNode(style: rootStyle, children: [kid])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    #expect(tree.layout(kid).height == 65)
    #expect(tree.layout(kid).y == 10)
}

/// The clamp-ordering half of bug 2: `min`/`max-height` describe the BORDER
/// box, so margins must be subtracted first and the min/max clamp applied to
/// what is left — never the other way around. Available border-box height is
/// `100 - 15 - 5 = 80`; `max-height: 50` then caps it to `50`. Clamping the
/// full `containerCross` (100) against `max-height` FIRST and subtracting
/// margins after would instead produce `50 - 15 - 5 = 30`, an entirely
/// different (and wrong) number — this test distinguishes the two orderings,
/// not just the presence of a clamp.
@Test func stretchWithMaxHeightClampsTheBorderBoxNotTheMarginBox() {
    let tree = LayoutTree(generation: 0)
    var s = Style()
    s.size = Size(width: px(70), height: .auto)
    s.maxSize = Size(width: .auto, height: px(50))
    s.margin = Edges(top: px(15), right: px(0), bottom: px(5), left: px(0))
    let kid = tree.newNode(style: s, children: [])

    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.size = Size(width: px(400), height: px(100))
    let root = tree.newNode(style: rootStyle, children: [kid])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    #expect(tree.layout(kid).height == 50)
    #expect(tree.layout(kid).y == 15)
}

/// `row-reverse`, against WebKit, three children with different widths and
/// asymmetric margins on both axes. `flex_row_reverse_margins` is the
/// fixture; see its HTML for the mutation this guards (bug 1).
@Test func rowReverseMarginsMatchWebKit() throws {
    let golden = try loadGolden("flex_row_reverse_margins")
    let tree = LayoutTree(generation: 0)

    func marginChild(w: Double, h: Double, top: Double, right: Double,
                     bottom: Double, left: Double) -> LayoutNodeID {
        var s = Style()
        s.size = Size(width: px(w), height: px(h))
        s.margin = Edges(top: px(top), right: px(right), bottom: px(bottom), left: px(left))
        return tree.newNode(style: s, children: [])
    }
    let a = marginChild(w: 50, h: 30, top: 5, right: 30, bottom: 15, left: 10)
    let b = marginChild(w: 60, h: 40, top: 2, right: 4, bottom: 8, left: 20)
    let c = marginChild(w: 40, h: 20, top: 12, right: 18, bottom: 1, left: 6)

    var rootStyle = Style()
    rootStyle.flexDirection = .rowReverse
    rootStyle.size = Size(width: px(400), height: px(100))
    let root = tree.newNode(style: rootStyle, children: [a, b, c])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    assertMatchesGolden(tree,
                        ids: [root: "root", a: "a", b: "b", c: "c"],
                        golden: golden, tolerance: 0.1)
}

/// `column-reverse` counterpart, against WebKit. `flex_column_reverse_margins`
/// is the fixture — it is what would catch a fix that only generalised
/// correctly for rows and silently transposed top/bottom for columns.
@Test func columnReverseMarginsMatchWebKit() throws {
    let golden = try loadGolden("flex_column_reverse_margins")
    let tree = LayoutTree(generation: 0)

    func marginChild(w: Double, h: Double, top: Double, right: Double,
                     bottom: Double, left: Double) -> LayoutNodeID {
        var s = Style()
        s.size = Size(width: px(w), height: px(h))
        s.margin = Edges(top: px(top), right: px(right), bottom: px(bottom), left: px(left))
        return tree.newNode(style: s, children: [])
    }
    let a = marginChild(w: 30, h: 50, top: 10, right: 15, bottom: 30, left: 5)
    let b = marginChild(w: 40, h: 60, top: 20, right: 8, bottom: 4, left: 2)
    let c = marginChild(w: 20, h: 40, top: 6, right: 1, bottom: 18, left: 12)

    var rootStyle = Style()
    rootStyle.flexDirection = .columnReverse
    rootStyle.size = Size(width: px(100), height: px(400))
    let root = tree.newNode(style: rootStyle, children: [a, b, c])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    assertMatchesGolden(tree,
                        ids: [root: "root", a: "a", b: "b", c: "c"],
                        golden: golden, tolerance: 0.1)
}

/// Stretch + cross margins + `max-height`, against WebKit.
/// `flex_row_stretch_with_margins` is the fixture; see its HTML for why `.b`
/// needs `max-height` (bug 2's clamp-ordering half).
@Test func rowStretchWithMarginsMatchesWebKit() throws {
    let golden = try loadGolden("flex_row_stretch_with_margins")
    let tree = LayoutTree(generation: 0)

    var aStyle = Style()
    aStyle.size = Size(width: px(50), height: .auto)
    aStyle.margin = Edges(top: px(10), right: px(0), bottom: px(25), left: px(0))
    let a = tree.newNode(style: aStyle, children: [])

    var bStyle = Style()
    bStyle.size = Size(width: px(70), height: .auto)
    bStyle.maxSize = Size(width: .auto, height: px(50))
    bStyle.margin = Edges(top: px(15), right: px(0), bottom: px(5), left: px(0))
    let b = tree.newNode(style: bStyle, children: [])

    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.size = Size(width: px(400), height: px(100))
    let root = tree.newNode(style: rootStyle, children: [a, b])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    assertMatchesGolden(tree,
                        ids: [root: "root", a: "a", b: "b"],
                        golden: golden, tolerance: 0.1)
}

/// The composition the Task 2 brief did not enumerate: `flex-grow`,
/// `justify-content: space-between`, and margins on every child, together —
/// against WebKit. `flex_row_grow_space_between_margins` is the fixture; see
/// its HTML for why `.a` needs `max-width` (otherwise growth alone consumes
/// all free space and `space-between` becomes a no-op, testing nothing new).
/// This is the browser-checked version of the double-count argument in the
/// Task 2 report: the grow budget `layoutContainer` shrinks by total margin,
/// and the outer-size content total `positionItems` feeds to
/// `justify-content`, must agree with each other.
@Test func rowGrowSpaceBetweenWithMarginsMatchesWebKit() throws {
    let golden = try loadGolden("flex_row_grow_space_between_margins")
    let tree = LayoutTree(generation: 0)

    var aStyle = Style()
    aStyle.flexGrow = 1
    aStyle.flexShrink = 1
    aStyle.flexBasis = px(0)
    aStyle.maxSize = Size(width: px(150), height: .auto)
    aStyle.size = Size(width: .auto, height: px(40))
    aStyle.margin = Edges(top: px(4), right: px(15), bottom: px(6), left: px(9))
    let a = tree.newNode(style: aStyle, children: [])

    var bStyle = Style()
    bStyle.size = Size(width: px(60), height: px(40))
    bStyle.margin = Edges(top: px(2), right: px(25), bottom: px(8), left: px(3))
    let b = tree.newNode(style: bStyle, children: [])

    var cStyle = Style()
    cStyle.size = Size(width: px(50), height: px(40))
    cStyle.margin = Edges(top: px(12), right: px(4), bottom: px(1), left: px(18))
    let c = tree.newNode(style: cStyle, children: [])

    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.justifyContent = .spaceBetween
    rootStyle.size = Size(width: px(400), height: px(100))
    let root = tree.newNode(style: rootStyle, children: [a, b, c])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    assertMatchesGolden(tree,
                        ids: [root: "root", a: "a", b: "b", c: "c"],
                        golden: golden, tolerance: 0.1)
}

// MARK: - Task 3: percentages and nesting

/// Percentage padding resolves against the containing block's **width** on
/// EVERY edge, including top and bottom.
///
/// The root is deliberately 400x100 inside an 800x600 offered space, so three
/// candidate bases all disagree and each one has its own visible answer:
///
/// | basis | left | top | bottom |
/// |---|---|---|---|
/// | containing block width, 800 — correct | 32 | 40 | 24 |
/// | the root's own width, 400 — the Task 3 bug | 16 | 20 | 12 |
/// | containing block height, 600 — the plan's mutation 1 | 32 | 30 | 18 |
///
/// On a square container the first and third collapse, which is exactly why
/// `resolveEdges` has documented the width rule since M1a with nothing able to
/// check it. Every edge is a different percentage, so a dropped or transposed
/// edge cannot pass either.
///
/// **The plan's Step 1 code block asserted `padding: 10%` on a 400-wide root
/// gives 40, and that is wrong** — it reads "the containing block's width" as
/// "this box's own width". The two coincide only when a box fills its parent's
/// content box. Measured in WebKit, `padding: 15%` on a 400-wide root inside an
/// 800-wide body gives **120**, not 60. The engine agreed with the plan rather
/// than with CSS until this test; see `flex_nested_percent_padding` for the
/// same rule one level down, where the containing block is not the viewport.
@Test func percentagePaddingResolvesAgainstTheContainingBlockWidthOnEveryEdge() {
    let tree = LayoutTree(generation: 0)
    let a = fixedChild(tree, w: 50, h: 20)
    // Auto cross size: `b` stretches to the CONTENT box's height, so the
    // vertical basis is visible in a size and not only in an origin.
    var bStyle = Style()
    bStyle.size = Size(width: px(60), height: .auto)
    let b = tree.newNode(style: bStyle, children: [])

    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.size = Size(width: px(400), height: px(100))
    rootStyle.padding = Edges(top: pctL(0.05), right: pctL(0.02),
                              bottom: pctL(0.03), left: pctL(0.04))
    let root = tree.newNode(style: rootStyle, children: [a, b])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    // 4% and 5% of 800 — the containing block's width, on the vertical edge too.
    #expect(tree.layout(a) == LayoutRect(x: 32, y: 40, width: 50, height: 20))
    // Content height is 100 - (5% + 3%) of 800 = 100 - 64 = 36.
    #expect(tree.layout(b) == LayoutRect(x: 82, y: 40, width: 60, height: 36))
}

/// A **nested** container's percentage padding resolves against its parent's
/// CONTENT box, not against its own width and not against its parent's border
/// box.
///
/// This is the half of the rule the viewport cannot check: for the root, the
/// containing block is whatever `computeLayout` was offered, so a root-only
/// test cannot tell "the containing block" from "the offered space". Here
/// `.mid` is 200 wide inside a root whose content box is 270 wide and whose
/// border box is 400, and the three bases give 20, 27 and 40.
///
/// **WebKit says 27.** `contentBox` passed `borderBox.width` — the box's own
/// size — until Task 3, and gave 20.
@Test func nestedPercentagePaddingResolvesAgainstTheParentsContentBox() {
    let tree = LayoutTree(generation: 0)
    let g1 = fixedChild(tree, w: 20, h: 10)

    var g2Style = Style()
    g2Style.flexGrow = 1
    g2Style.flexShrink = 1
    g2Style.flexBasis = px(0)
    g2Style.size = Size(width: .auto, height: px(10))
    let g2 = tree.newNode(style: g2Style, children: [])

    var midStyle = Style()
    midStyle.flexDirection = .row
    midStyle.size = Size(width: px(200), height: px(100))
    midStyle.padding = Edges(all: pctL(0.10))
    let mid = tree.newNode(style: midStyle, children: [g1, g2])

    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.size = Size(width: px(400), height: px(200))
    rootStyle.padding = Edges(top: pxL(15), right: pxL(40), bottom: pxL(25), left: pxL(60))
    rootStyle.border = Edges(top: pxL(5), right: pxL(10), bottom: pxL(8), left: pxL(20))
    let root = tree.newNode(style: rootStyle, children: [mid])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    // Root content box: 400 - 60 - 40 - 20 - 10 = 270 wide, origin x = 80.
    #expect(tree.layout(mid) == LayoutRect(x: 80, y: 20, width: 200, height: 100))
    // 10% of 270 = 27, on the vertical edge too (10% of the content HEIGHT,
    // 147, would be 14.7).
    #expect(tree.layout(g1) == LayoutRect(x: 107, y: 47, width: 20, height: 10))
    // And the inner content box's SIZE carries the same basis: 200 - 27 - 27
    // - 20 = 126, where the own-width basis would leave 140.
    #expect(tree.layout(g2) == LayoutRect(x: 127, y: 47, width: 126, height: 10))
}

/// Insets compose down the tree without double-counting.
///
/// Outer padding 10 + border 5; inner padding 20 + border 3. The grandchild sits
/// at 10 + 5 + 20 + 3 = 38 from the root on both axes. Applying the outer inset
/// to the grandchild as well would give 53; skipping the inner would give 15.
@Test func nestedContainersComposeTheirInsetsExactlyOnce() {
    let tree = LayoutTree(generation: 0)
    let grandchild = fixedChild(tree, w: 20, h: 10)

    var midStyle = Style()
    midStyle.flexDirection = .row
    midStyle.size = Size(width: px(200), height: px(80))
    midStyle.padding = Edges(all: pxL(20))
    midStyle.border = Edges(all: pxL(3))
    let mid = tree.newNode(style: midStyle, children: [grandchild])

    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.size = Size(width: px(400), height: px(200))
    rootStyle.padding = Edges(all: pxL(10))
    rootStyle.border = Edges(all: pxL(5))
    let root = tree.newNode(style: rootStyle, children: [mid])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    #expect(tree.layout(mid) == LayoutRect(x: 15, y: 15, width: 200, height: 80))
    #expect(tree.layout(grandchild) == LayoutRect(x: 38, y: 38, width: 20, height: 10))
}

/// **Ruling BM-3** — a child's percentage *size* resolves against its parent's
/// CONTENT box, on both axes.
///
/// `collectItems` already receives the content box as `containerSize` and
/// builds its `parent` binding from it, so this was correct by construction
/// from Task 1 — and reached by nothing. Mutating that binding back to the
/// border box reddened no test in the repo, which is the same "untested-correct"
/// state Task 2's two real bugs were in before someone probed them.
///
/// Content box: 400 - 30 - 50 - 10 - 10 = 300 wide, 200 - 20 - 30 - 5 - 5 = 140
/// tall, at (40, 25). `a` is a percentage on both axes (150 x 70, where the
/// border box would give 200 x 100), so a fix that threads the content box into
/// the main axis alone still reddens; `b` mixes a pixel width with a percentage
/// height, so the axes cannot be confused, and its origin moves with `a`'s width.
@Test func percentageChildSizesResolveAgainstTheParentsContentBox() {
    let tree = LayoutTree(generation: 0)
    var aStyle = Style()
    aStyle.size = Size(width: pct(0.50), height: pct(0.50))
    let a = tree.newNode(style: aStyle, children: [])

    var bStyle = Style()
    bStyle.size = Size(width: px(60), height: pct(0.25))
    let b = tree.newNode(style: bStyle, children: [])

    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.size = Size(width: px(400), height: px(200))
    rootStyle.padding = Edges(top: pxL(20), right: pxL(50), bottom: pxL(30), left: pxL(30))
    rootStyle.border = Edges(top: pxL(5), right: pxL(10), bottom: pxL(5), left: pxL(10))
    let root = tree.newNode(style: rootStyle, children: [a, b])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    #expect(tree.layout(a) == LayoutRect(x: 40, y: 25, width: 150, height: 70))
    #expect(tree.layout(b) == LayoutRect(x: 190, y: 25, width: 60, height: 35))
}

/// Percentage padding against WebKit. `flex_percent_padding_nonsquare` is the
/// fixture; see its HTML for the three bases it separates and for why the
/// percentages are small (larger ones drag in ruling BM-4's over-constrained
/// box, which this fixture is not about).
@Test func percentPaddingNonSquareMatchesWebKit() throws {
    let golden = try loadGolden("flex_percent_padding_nonsquare")
    let tree = LayoutTree(generation: 0)
    let a = fixedChild(tree, w: 50, h: 20)

    var bStyle = Style()
    bStyle.size = Size(width: px(60), height: .auto)
    let b = tree.newNode(style: bStyle, children: [])

    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.size = Size(width: px(400), height: px(100))
    rootStyle.padding = Edges(top: pctL(0.05), right: pctL(0.02),
                              bottom: pctL(0.03), left: pctL(0.04))
    let root = tree.newNode(style: rootStyle, children: [a, b])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    assertMatchesGolden(tree,
                        ids: [root: "root", a: "a", b: "b"],
                        golden: golden, tolerance: 0.1)
}

/// Nested percentage padding against WebKit — the browser's word on which box
/// is the containing block. `flex_nested_percent_padding` is the fixture; it is
/// the probe that found the basis bug.
@Test func nestedPercentPaddingMatchesWebKit() throws {
    let golden = try loadGolden("flex_nested_percent_padding")
    let tree = LayoutTree(generation: 0)
    let g1 = fixedChild(tree, w: 20, h: 10)

    var g2Style = Style()
    g2Style.flexGrow = 1
    g2Style.flexShrink = 1
    g2Style.flexBasis = px(0)
    g2Style.size = Size(width: .auto, height: px(10))
    let g2 = tree.newNode(style: g2Style, children: [])

    var midStyle = Style()
    midStyle.flexDirection = .row
    midStyle.size = Size(width: px(200), height: px(100))
    midStyle.padding = Edges(all: pctL(0.10))
    let mid = tree.newNode(style: midStyle, children: [g1, g2])

    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.size = Size(width: px(400), height: px(200))
    rootStyle.padding = Edges(top: pxL(15), right: pxL(40), bottom: pxL(25), left: pxL(60))
    rootStyle.border = Edges(top: pxL(5), right: pxL(10), bottom: pxL(8), left: pxL(20))
    let root = tree.newNode(style: rootStyle, children: [mid])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    assertMatchesGolden(tree,
                        ids: [root: "root", mid: "mid", g1: "g1", g2: "g2"],
                        golden: golden, tolerance: 0.1)
}

/// Nesting against WebKit: a padded, bordered container inside a padded,
/// bordered container, with two children at both levels and a growing
/// grandchild. `flex_nested_padding` is the fixture — see its HTML for why the
/// two generations' insets differ and why the inner container needs two
/// children.
@Test func nestedPaddingMatchesWebKit() throws {
    let golden = try loadGolden("flex_nested_padding")
    let tree = LayoutTree(generation: 0)
    let g1 = fixedChild(tree, w: 20, h: 10)

    var g2Style = Style()
    g2Style.flexGrow = 1
    g2Style.flexShrink = 1
    g2Style.flexBasis = px(0)
    g2Style.size = Size(width: .auto, height: px(10))
    let g2 = tree.newNode(style: g2Style, children: [])

    var midStyle = Style()
    midStyle.flexDirection = .row
    midStyle.size = Size(width: px(200), height: px(80))
    midStyle.padding = Edges(all: pxL(20))
    midStyle.border = Edges(all: pxL(3))
    let mid = tree.newNode(style: midStyle, children: [g1, g2])

    let sib = fixedChild(tree, w: 40, h: 60)

    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.size = Size(width: px(400), height: px(200))
    rootStyle.padding = Edges(all: pxL(10))
    rootStyle.border = Edges(all: pxL(5))
    let root = tree.newNode(style: rootStyle, children: [mid, sib])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    assertMatchesGolden(tree,
                        ids: [root: "root", mid: "mid", g1: "g1", g2: "g2", sib: "sib"],
                        golden: golden, tolerance: 0.1)
}

/// A percentage-sized child inside a padded parent, against WebKit — ruling
/// BM-3's fixture. `flex_percent_child_in_padded` is the corpus's only reach
/// into `collectItems`' `parent` binding.
@Test func percentChildInPaddedParentMatchesWebKit() throws {
    let golden = try loadGolden("flex_percent_child_in_padded")
    let tree = LayoutTree(generation: 0)

    var aStyle = Style()
    aStyle.size = Size(width: pct(0.50), height: pct(0.50))
    let a = tree.newNode(style: aStyle, children: [])

    var bStyle = Style()
    bStyle.size = Size(width: px(60), height: pct(0.25))
    let b = tree.newNode(style: bStyle, children: [])

    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.size = Size(width: px(400), height: px(200))
    rootStyle.padding = Edges(top: pxL(20), right: pxL(50), bottom: pxL(30), left: pxL(30))
    rootStyle.border = Edges(top: pxL(5), right: pxL(10), bottom: pxL(5), left: pxL(10))
    let root = tree.newNode(style: rootStyle, children: [a, b])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    assertMatchesGolden(tree,
                        ids: [root: "root", a: "a", b: "b"],
                        golden: golden, tolerance: 0.1)
}

// MARK: - Ruling BM-5: compositions Task 2 left untested-correct

/// **Ruling BM-5, composition 1.** Stretch + `min-height` + cross margins, a
/// composition the engine handles and no fixture reached. Task 2's two real
/// bugs both lived in exactly this shape, so "believed correct" is not the same
/// state as "measured".
///
/// **WebKit agrees with the engine**, which is the finding: `.a` gets 50x70 at
/// y = 20 (available 100 - 20 - 30 = 50, floored by `min-height: 70`, and the
/// item then deliberately overflows the container: 20 + 70 + 30 = 120), and
/// `.b` gets 60x75 at y = 10 (available 75, floor 40 does not bind).
/// `flex_row_stretch_with_margins` pins the same ordering against `max-height`.
@Test func rowStretchWithMinHeightAndMarginsMatchesWebKit() throws {
    let golden = try loadGolden("flex_row_stretch_min_height_margins")
    let tree = LayoutTree(generation: 0)

    var aStyle = Style()
    aStyle.size = Size(width: px(50), height: .auto)
    aStyle.minSize = Size(width: .auto, height: px(70))
    aStyle.margin = Edges(top: px(20), right: px(0), bottom: px(30), left: px(0))
    let a = tree.newNode(style: aStyle, children: [])

    var bStyle = Style()
    bStyle.size = Size(width: px(60), height: .auto)
    bStyle.minSize = Size(width: .auto, height: px(40))
    bStyle.margin = Edges(top: px(10), right: px(0), bottom: px(15), left: px(0))
    let b = tree.newNode(style: bStyle, children: [])

    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.size = Size(width: px(400), height: px(100))
    let root = tree.newNode(style: rootStyle, children: [a, b])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    assertMatchesGolden(tree,
                        ids: [root: "root", a: "a", b: "b"],
                        golden: golden, tolerance: 0.1)
}

/// **Ruling BM-5, composition 2.** `row-reverse` and cross-axis stretch
/// composed — the corpus had each alone and neither together.
///
/// **WebKit agrees with the engine.** Reversal is a main-axis conversion and
/// stretch is a cross-axis size, so the composition is expected to be trivially
/// correct; the point is that nothing had checked, which is the state Task 2's
/// bugs were found in. `.b`'s `align-self: flex-end` is the part that would
/// notice reversal leaking into the cross axis, since flex-end is the one
/// alignment whose leading and trailing space differ; `.c`'s `max-height` is
/// what would notice a stretch that ignored the clamp.
@Test func rowReverseStretchMatchesWebKit() throws {
    let golden = try loadGolden("flex_row_reverse_stretch")
    let tree = LayoutTree(generation: 0)

    var aStyle = Style()
    aStyle.size = Size(width: px(50), height: .auto)
    let a = tree.newNode(style: aStyle, children: [])

    var bStyle = Style()
    bStyle.size = Size(width: px(60), height: px(30))
    bStyle.alignSelf = .flexEnd
    let b = tree.newNode(style: bStyle, children: [])

    var cStyle = Style()
    cStyle.size = Size(width: px(70), height: .auto)
    cStyle.maxSize = Size(width: .auto, height: px(40))
    let c = tree.newNode(style: cStyle, children: [])

    var rootStyle = Style()
    rootStyle.flexDirection = .rowReverse
    rootStyle.size = Size(width: px(400), height: px(100))
    let root = tree.newNode(style: rootStyle, children: [a, b, c])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    assertMatchesGolden(tree,
                        ids: [root: "root", a: "a", b: "b", c: "c"],
                        golden: golden, tolerance: 0.1)
}

/// Percentage margins resolve against the containing block's **width** on every
/// edge, including top and bottom — the same CSS rule padding and border follow.
///
/// This closed the last green mutation on the box-model branch. Mutating
/// `resolveMargin`'s basis to the container's *height* left all 171 tests green:
/// the rule was asserted in two doc comments, verified against WebKit five ways
/// by a reviewer, and pinned by nothing. That is taxonomy shape 9 in
/// `docs/practices/verifying-tests-can-fail.md` — correct-by-construction is the
/// state every bug on this branch was in the day before it was found.
///
/// The container is 400x100 on purpose. On a square, the two bases agree and this
/// test cannot fail.
@Test func percentageMarginsResolveAgainstTheContainingBlockWidth() {
    let tree = LayoutTree(generation: 0)
    var s = Style()
    s.size = Size(width: px(50), height: px(20))
    // 10% of the 400 content width = 40 on the leading edges. Against the 100
    // height it would be 10 — a difference no rounding can explain.
    s.margin = Edges(top: pct(0.10), right: pct(0.05), bottom: pct(0.10), left: pct(0.10))
    let kid = tree.newNode(style: s, children: [])

    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.size = Size(width: px(400), height: px(100))
    let root = tree.newNode(style: rootStyle, children: [kid])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    #expect(tree.layout(kid).x == 40)
    #expect(tree.layout(kid).y == 40)
}
