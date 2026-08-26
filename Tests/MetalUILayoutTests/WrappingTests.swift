import Testing
import Foundation
import MetalUICore
@testable import MetalUILayout

private func px(_ v: Double) -> MetalUICore.Dimension { .length(.pixels(Pixels(Float(v)))) }
private func pxL(_ v: Double) -> Length { .pixels(Pixels(Float(v))) }

private func item(_ tree: LayoutTree, main: Double, cross: Double) -> LayoutNodeID {
    var s = Style()
    s.size = Size(width: px(main), height: px(cross))
    return tree.newNode(style: s, children: [])
}

private func line(_ mains: [Double]) -> [FlexItem] {
    mains.map {
        FlexItem(node: LayoutNodeID(0), baseSize: $0, hypotheticalMainSize: $0,
                 minMain: nil, maxMain: nil, targetMainSize: $0, crossSize: 10,
                 stretchEligible: false, minCross: nil, maxCross: nil,
                 frozen: false, marginMain: (0, 0), marginCross: (0, 0))
    }
}

/// Items break onto a new line when their outer main sizes plus gaps would
/// exceed the container.
///
/// Deliberately uneven — 60/90/40/70 in 200 — so the break indices are not a
/// round number and "break when full" cannot be confused with "break every two".
@Test func linesBreakWhenTheNextItemWouldOverflow() {
    let items = line([60, 90, 40, 70])
    let lines = collectLines(items, wrap: .wrap, containerMain: 200, gap: 0)

    // 60 + 90 = 150 fits; + 40 = 190 fits; + 70 = 260 does not.
    #expect(lines.map(\.count) == [3, 1])
    #expect(lines[0].map(\.targetMainSize) == [60, 90, 40])
    #expect(lines[1].map(\.targetMainSize) == [70])
}

/// Gaps count toward the break decision.
///
/// The same items with `gap: 20` fit only two per line: 60 + 20 + 90 = 170,
/// and adding 40 would make 230.
@Test func gapsCountTowardTheBreakDecision() {
    let items = line([60, 90, 40, 70])
    let lines = collectLines(items, wrap: .wrap, containerMain: 200, gap: 20)
    #expect(lines.map(\.count) == [2, 2])
}

/// `nowrap` puts everything on one line however much it overflows — the
/// behaviour every one of the 40 committed fixtures depends on.
@Test func nowrapNeverBreaks() {
    let items = line([60, 90, 40, 70])
    let lines = collectLines(items, wrap: .noWrap, containerMain: 200, gap: 0)
    #expect(lines.map(\.count) == [4])
}

/// An item too large for the container occupies a line alone rather than
/// producing an empty line before it.
@Test func anOversizedItemGetsItsOwnLineRatherThanAnEmptyOne() {
    let items = line([300, 50])
    let lines = collectLines(items, wrap: .wrap, containerMain: 200, gap: 0)
    #expect(lines.map(\.count) == [1, 1])
    // Optional-chained on purpose: removing the never-empty-line guard makes
    // this `[0, 1, 1]`, and a subscript would then TRAP — aborting the runner
    // and hiding the other 183 results behind a crash. A mutation should fail
    // loudly in one place, not take the suite with it.
    #expect(lines.first?.first?.targetMainSize == 300)
}

/// A line's cross size is the largest outer cross size among its items —
/// border box plus that item's cross margins.
@Test func aLinesCrossSizeIsTheLargestOuterCrossSizeOnIt() {
    var items = line([10, 10, 10])
    items[0].crossSize = 20
    items[1].crossSize = 30
    items[1].marginCross = (5, 7)      // outer 42 — the largest, via margins
    items[2].crossSize = 35
    #expect(lineCrossSize(items) == 42)
}

/// Stretch fills the ITEM'S LINE, not the container.
///
/// Two lines in a 300-tall container: the first holds a 40-tall item, the second
/// a 90-tall one. An auto-cross item on the first line stretches to 40, not to
/// 300 and not to 90. Nothing before wrapping could tell those apart, because
/// there was only ever one line and its cross size WAS the container's.
///
/// **`align-content: flex-start` is declared so this measures a line's NATURAL
/// cross size.** Under CSS's initial `stretch` the same tree gives 125 — see
/// `aStretchedLineChangesWhatItsStretchedItemsFill`, which is this exact tree
/// with the default restored. The pair is the differential: one property, two
/// answers, nothing else changed.
@Test func stretchFillsTheItemsOwnLineNotTheContainer() {
    let tree = LayoutTree()
    let tall = item(tree, main: 120, cross: 40)
    var autoStyle = Style()
    autoStyle.size = Size(width: px(120), height: .auto)
    let stretched = tree.newNode(style: autoStyle, children: [])
    let second = item(tree, main: 120, cross: 90)

    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.flexWrap = .wrap
    rootStyle.alignContent = .flexStart
    rootStyle.size = Size(width: px(260), height: px(300))
    let root = tree.newNode(style: rootStyle, children: [tall, stretched, second])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    // `tall` and `stretched` share line 0 (120 + 120 = 240 <= 260).
    #expect(tree.layout(stretched).height == 40)
    #expect(tree.layout(stretched).y == 0)
    // `second` starts line 1, below line 0's 40.
    #expect(tree.layout(second).y == 40)
}

// MARK: - Ruling WR-1: the cross-axis gap is the space between lines

/// A row's `row-gap` separates its LINES, and its `column-gap` its items.
///
/// Both `gap` call sites in the engine read `isRow ? .horizontal : .vertical` —
/// always the MAIN axis — so before this task a row silently ignored its
/// `row-gap` entirely and a column its `column-gap`. Neither component was
/// dead (each is read in one direction), so it never earned a row in
/// CLAUDE.md's inert table, and `gapUsesTheMainAxisOfTheContainer` reads as
/// full coverage while saying nothing about the dropped half.
///
/// The two axes are deliberately different numbers: with `gap: 8px 14px` a
/// container that used the main-axis component for both would put 14 between
/// the lines, and a container that used the cross component for both would
/// break at different indices.
@Test func rowGapSeparatesLinesAndColumnGapSeparatesItems() {
    let tree = LayoutTree()
    let a = item(tree, main: 60, cross: 20)
    let b = item(tree, main: 90, cross: 35)
    let c = item(tree, main: 70, cross: 15)

    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.flexWrap = .wrap
    rootStyle.gap = Axes(horizontal: pxL(14), vertical: pxL(8))
    // Declared so this measures the GAP alone. Under CSS's initial
    // `align-content: stretch` the two lines grow to 106 and 86 and `c` lands
    // at 114 — still 8 below line 0, but with the 8 buried inside a number that
    // moves for a second reason. That the leftover-cross computation SUBTRACTS
    // the cross gaps before distributing them is a real rule, and it is pinned
    // against the browser by `flex_wrap_align_content_stretch` (12px row-gap,
    // three lines) rather than here.
    rootStyle.alignContent = .flexStart
    rootStyle.size = Size(width: px(218), height: px(200))
    let root = tree.newNode(style: rootStyle, children: [a, b, c])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    // column-gap 14 sits between `a` and `b` on line 0…
    #expect(tree.layout(b).x == 74)
    // …and 60 + 14 + 90 + 14 + 70 = 248 > 218, so `c` starts line 1.
    #expect(tree.layout(c).x == 0)
    // row-gap 8 — NOT the main axis's 14 — sits between the lines, below
    // line 0's cross size of 35.
    #expect(tree.layout(c).y == 43)
}

// MARK: - CSS Flexbox §8.3: wrap-reverse flips the CROSS AXIS

/// `wrap-reverse` stacks lines from the container's cross-END, and pins each
/// item to its line's *flipped* cross-start — the line's bottom edge in a row.
///
/// **Reversing the line ORDER alone is not what CSS does**, and this tree shows
/// why: `a` and `b` share line 0 and still land on different `y` values (260 and
/// 270), because each sits at its own line's bottom edge inside a 40-tall line.
/// No forward-wrapping fixture can exhibit that — a forward line pins both to
/// the same top edge — which is why this composition needs its own coverage
/// rather than inheriting it from the `wrap` tests.
///
/// The numbers are WebKit's, measured on this exact tree and recorded in
/// `docs/superpowers/2026-08-25-wrapping-decisions.md`:
///
///     align-content: flex-start (declared below)   c 170, a 260, b 270
///
/// `170` is `300 - 40 - 90`: line 1 sits one line-height plus line 0's height
/// up from the bottom. Before the reversal landed this engine gave c 40, a 0,
/// b 0 — i.e. it laid out as plain `wrap`.
///
/// `align-content: flex-start` is declared so this measures the REVERSAL alone;
/// `wrapReverseUnderAlignContentStretch` is this same tree with CSS's initial
/// value restored, and is the differential.
@Test func wrapReverseStacksLinesFromTheCrossEnd() {
    let tree = LayoutTree()
    let a = item(tree, main: 120, cross: 40)
    let b = item(tree, main: 120, cross: 30)
    let c = item(tree, main: 120, cross: 90)

    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.flexWrap = .wrapReverse
    rootStyle.alignContent = .flexStart
    rootStyle.size = Size(width: px(260), height: px(300))
    let root = tree.newNode(style: rootStyle, children: [a, b, c])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    // Line 1 (`c` alone) sits ABOVE line 0 — the whole cross axis is flipped,
    // so `flex-start` packs the stack against the container's bottom.
    #expect(tree.layout(c).y == 170)
    // Line 0 is at the very bottom, and its two items are pinned to their own
    // bottom edges: 260 = 300 - 40, 270 = 300 - 30.
    #expect(tree.layout(a).y == 260)
    #expect(tree.layout(b).y == 270)
    // The MAIN axis is untouched — `wrap-reverse` reverses nothing about it.
    #expect(tree.layout(a).x == 0)
    #expect(tree.layout(b).x == 120)
    #expect(tree.layout(c).x == 0)
}

/// The same tree under CSS's initial `align-content: stretch`.
///
/// Both lines grow by 85 (170 leftover, two lines), so line 0 becomes 125 tall
/// and line 1 175. Reversed, line 1 sits at the top (y 0) and `c` is pinned to
/// ITS bottom edge at 175 - 90 = 85; line 0 starts at 175 and its items still
/// land at 260 and 270 because the container's bottom has not moved.
///
/// WebKit, on this exact tree: `c 85, a 260, b 270`.
///
/// The pair with `wrapReverseStacksLinesFromTheCrossEnd` is the differential:
/// one property changes, `c` moves 170 -> 85, and `a`/`b` stay put — which is
/// the signature of growth being distributed to LINES while the flipped
/// cross-start of the last line remains the container's edge.
@Test func wrapReverseUnderAlignContentStretch() {
    let tree = LayoutTree()
    let a = item(tree, main: 120, cross: 40)
    let b = item(tree, main: 120, cross: 30)
    let c = item(tree, main: 120, cross: 90)

    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.flexWrap = .wrapReverse
    // `alignContent` deliberately NOT set — CSS's initial `stretch` is the
    // second half of the differential.
    rootStyle.size = Size(width: px(260), height: px(300))
    let root = tree.newNode(style: rootStyle, children: [a, b, c])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    #expect(tree.layout(c).y == 85)
    #expect(tree.layout(a).y == 260)
    #expect(tree.layout(b).y == 270)
}

/// `align-items` is expressed in FLEX-relative terms, so `wrap-reverse` flips
/// what `flex-start` and `flex-end` mean: `flex-start` is the line's bottom
/// edge and `flex-end` its top.
///
/// Three items on one 60-tall line inside a 60-tall container (so
/// `align-content` cannot move anything and this measures §9.6 alone):
/// a 20 tall at `flex-start`, b 20 tall at `flex-end`, c 20 tall centred.
@Test func wrapReverseFlipsWhatAlignItemsFlexStartMeans() {
    let tree = LayoutTree()

    func child(_ align: AlignSelf) -> LayoutNodeID {
        var s = Style()
        s.size = Size(width: px(60), height: px(20))
        s.alignSelf = align
        return tree.newNode(style: s, children: [])
    }
    let a = child(.flexStart)
    let b = child(.flexEnd)
    let c = child(.center)

    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.flexWrap = .wrapReverse
    rootStyle.size = Size(width: px(200), height: px(60))
    let root = tree.newNode(style: rootStyle, children: [a, b, c])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    // One line, 20 tall naturally, grown to the container's 60 by the initial
    // `align-content: stretch` — so the line IS the container here.
    // `flex-start` -> the line's flipped cross-start, i.e. its BOTTOM.
    #expect(tree.layout(a).y == 40)
    // `flex-end` -> the line's flipped cross-END, i.e. its TOP.
    #expect(tree.layout(b).y == 0)
    // `center` is symmetric and does not move — which is exactly why a
    // centre-aligned fixture cannot pin this flip.
    #expect(tree.layout(c).y == 20)
}

/// `row-reverse` + `wrap-reverse` flips BOTH axes: the container fills from the
/// bottom-right.
///
/// The main axis's flip already existed (`positionItems`' cursor conversion);
/// this asserts the two conversions compose rather than cancelling or
/// double-applying. Same 260x300 tree as
/// `wrapReverseStacksLinesFromTheCrossEnd`, so the cross numbers are
/// identical and only `x` moves.
@Test func rowReverseComposesWithWrapReverseToFillFromTheBottomRight() {
    let tree = LayoutTree()
    let a = item(tree, main: 120, cross: 40)
    let b = item(tree, main: 120, cross: 30)
    let c = item(tree, main: 120, cross: 90)

    var rootStyle = Style()
    rootStyle.flexDirection = .rowReverse
    rootStyle.flexWrap = .wrapReverse
    rootStyle.alignContent = .flexStart
    rootStyle.size = Size(width: px(260), height: px(300))
    let root = tree.newNode(style: rootStyle, children: [a, b, c])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    // Main: the first item takes the container's RIGHT edge (260 - 120), the
    // second sits to its left.
    #expect(tree.layout(a).x == 140)
    #expect(tree.layout(b).x == 20)
    #expect(tree.layout(c).x == 140)
    // Cross: unchanged from the forward-main case — the two flips are
    // independent.
    #expect(tree.layout(a).y == 260)
    #expect(tree.layout(b).y == 270)
    #expect(tree.layout(c).y == 170)
}

/// `wrap-reverse` breaks lines in DOCUMENT order, exactly as `wrap` does — only
/// their placement is reversed.
///
/// Asserted on `collectLines` directly because the engine's positions cannot
/// distinguish "broke differently" from "placed differently": a container that
/// collected [a,b,c] / [d] and stacked it forwards is trivially different from
/// one that collected [d] / [a,b,c], but both put `d` on top. This pins the
/// break side.
@Test func wrapReverseBreaksLinesInDocumentOrder() {
    let items = line([60, 90, 40, 70])
    let forward = collectLines(items, wrap: .wrap, containerMain: 200, gap: 0)
    let reversed = collectLines(items, wrap: .wrapReverse, containerMain: 200, gap: 0)
    #expect(forward.map(\.count) == reversed.map(\.count))
    #expect(reversed.map { $0.map(\.targetMainSize) } == [[60, 90, 40], [70]])
}

// MARK: - Browser comparisons (shape 9: each fixture is a PAIR)

/// Wrapping x line cross sizing, against WebKit. `flex_wrap_uneven` is the
/// fixture; its HTML lists the four uniformity traps its numbers avoid,
/// including why the container is 218px and not 220.
@Test func wrapUnevenMatchesWebKit() throws {
    let golden = try loadGolden("flex_wrap_uneven")
    let tree = LayoutTree()
    let a = item(tree, main: 60,  cross: 20)
    let b = item(tree, main: 90,  cross: 35)
    let c = item(tree, main: 40,  cross: 25)
    let d = item(tree, main: 25,  cross: 15)
    let e = item(tree, main: 50,  cross: 45)
    let f = item(tree, main: 120, cross: 30)

    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.flexWrap = .wrap
    // Load-bearing since `align-content` landed, and load-bearing in the
    // FIXTURE too: `flex-start` is not the initial value, so dropping this
    // line from either side moves every box (the lines would grow to fill the
    // 200px content box under CSS's default `stretch`). It was written as a
    // workaround for an unimplemented property; it is now a genuine pin of
    // `flex-start`, which is the one align-content value the three dedicated
    // fixtures do not cover.
    rootStyle.alignContent = .flexStart
    rootStyle.gap = Axes(horizontal: pxL(14), vertical: pxL(8))
    rootStyle.size = Size(width: px(218), height: px(200))
    let root = tree.newNode(style: rootStyle, children: [a, b, c, d, e, f])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    assertMatchesGolden(tree,
                        ids: [root: "root", a: "a", b: "b", c: "c", d: "d", e: "e", f: "f"],
                        golden: golden, tolerance: 0.1)
}

/// Wrapping x stretch, against WebKit — the composition that distinguishes
/// "stretch fills the line" from "stretch fills the container".
///
/// `flex_wrap_stretch_auto_cross` is the fixture. Its three lines are 40, 90
/// and 25 tall inside a 300-tall container, so each auto-cross child lands on a
/// different number under the two models; `.d` adds a `max-height` clamped
/// against the line, and `.f` adds cross margins, so the margin-subtraction and
/// clamp orderings are measured against a LINE rather than the container.
@Test func wrapStretchAutoCrossMatchesWebKit() throws {
    let golden = try loadGolden("flex_wrap_stretch_auto_cross")
    let tree = LayoutTree()

    let a = item(tree, main: 120, cross: 40)

    var bStyle = Style()
    bStyle.size = Size(width: px(120), height: .auto)
    let b = tree.newNode(style: bStyle, children: [])

    let c = item(tree, main: 130, cross: 90)

    var dStyle = Style()
    dStyle.size = Size(width: px(100), height: .auto)
    dStyle.maxSize = Size(width: .auto, height: px(60))
    let d = tree.newNode(style: dStyle, children: [])

    let e = item(tree, main: 200, cross: 25)

    var fStyle = Style()
    fStyle.size = Size(width: px(40), height: .auto)
    fStyle.margin = Edges(top: px(6), right: px(0), bottom: px(8), left: px(0))
    let f = tree.newNode(style: fStyle, children: [])

    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.flexWrap = .wrap
    rootStyle.alignContent = .flexStart
    rootStyle.size = Size(width: px(260), height: px(300))
    let root = tree.newNode(style: rootStyle, children: [a, b, c, d, e, f])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    assertMatchesGolden(tree,
                        ids: [root: "root", a: "a", b: "b", c: "c", d: "d", e: "e", f: "f"],
                        golden: golden, tolerance: 0.1)
}

/// Wrapping x the box model, against WebKit. `flex_wrap_with_margins_and_padding`
/// is the fixture; its HTML shows why dropping margins from the break decision
/// changes the line SHAPE ([a,b]/[c,d] becomes [a,b,c]/[d]) rather than nudging
/// an offset, and why a border-box line cross size puts every item on line 1
/// twelve pixels too high.
@Test func wrapWithMarginsAndPaddingMatchesWebKit() throws {
    let golden = try loadGolden("flex_wrap_with_margins_and_padding")
    let tree = LayoutTree()

    func child(w: Double, h: Double, m: (Double, Double, Double, Double)) -> LayoutNodeID {
        var s = Style()
        s.size = Size(width: px(w), height: px(h))
        s.margin = Edges(top: px(m.0), right: px(m.1), bottom: px(m.2), left: px(m.3))
        return tree.newNode(style: s, children: [])
    }
    let a = child(w: 80,  h: 30, m: (4, 6, 8, 2))
    let b = child(w: 100, h: 20, m: (10, 3, 5, 7))
    let c = child(w: 60,  h: 45, m: (2, 9, 6, 5))
    let d = child(w: 90,  h: 25, m: (12, 4, 3, 8))

    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.flexWrap = .wrap
    rootStyle.alignContent = .flexStart
    rootStyle.gap = Axes(horizontal: pxL(6), vertical: pxL(9))
    rootStyle.size = Size(width: px(300), height: px(220))
    rootStyle.padding = Edges(top: pxL(7), right: pxL(11), bottom: pxL(13), left: pxL(9))
    rootStyle.border = Edges(top: pxL(3), right: pxL(5), bottom: pxL(2), left: pxL(4))
    let root = tree.newNode(style: rootStyle, children: [a, b, c, d])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    assertMatchesGolden(tree,
                        ids: [root: "root", a: "a", b: "b", c: "c", d: "d"],
                        golden: golden, tolerance: 0.1)
}

// MARK: - CSS Flexbox §9.6.15 / §8.4: align-content

/// `align-content` distributes leftover cross space among LINES.
///
/// Three lines of cross sizes 40/60/30 in a 300-tall container: 170 used,
/// 130 leftover. Three lines, not two — `space-between` and `space-around` are
/// hard to distinguish with two, and `space-evenly` collapses toward them.
@Test func alignContentDistributesLeftoverCrossSpaceAmongLines() {
    #expect(distributeLines(.flexStart, freeSpace: 130, lineCount: 3).leading == 0)
    #expect(distributeLines(.flexEnd, freeSpace: 130, lineCount: 3).leading == 130)
    #expect(distributeLines(.center, freeSpace: 130, lineCount: 3).leading == 65)

    let between = distributeLines(.spaceBetween, freeSpace: 130, lineCount: 3)
    #expect(between.leading == 0)
    #expect(between.between == 65)

    let around = distributeLines(.spaceAround, freeSpace: 130, lineCount: 3)
    #expect(abs(around.leading - 130.0 / 6.0) < 1e-9)
    #expect(abs(around.between - 130.0 / 3.0) < 1e-9)

    let evenly = distributeLines(.spaceEvenly, freeSpace: 130, lineCount: 3)
    #expect(abs(evenly.leading - 32.5) < 1e-9)
    #expect(abs(evenly.between - 32.5) < 1e-9)
}

/// `stretch` — the CSS default — grows every line by an equal share instead of
/// leaving space between them.
@Test func alignContentStretchGrowsEveryLineEqually() {
    let o = distributeLines(.stretch, freeSpace: 130, lineCount: 3)
    #expect(o.leading == 0)
    #expect(o.between == 0)
    // The growth is reported separately; lines are not moved apart.
    #expect(lineStretchAmount(.stretch, freeSpace: 130, lineCount: 3) == 130.0 / 3.0)
    #expect(lineStretchAmount(.center, freeSpace: 130, lineCount: 3) == 0)
}

/// §9.6.15 says to *increase* each line's cross size, so negative free space —
/// lines that already overflow their container — never shrinks a line.
///
/// Without the guard, three lines overflowing a container by 90 would each be
/// pulled 30 shorter and the whole stack would collapse inward, which is the
/// opposite of what an overflowing container does. `flexEnd` is asserted
/// alongside to show the guard is on `stretch`'s growth ALONE: the six
/// delegated values do honour negative free space (ruling AL-4 governs which of
/// them clamp), so a blanket "no negative free space" rule here would be wrong.
@Test func lineStretchNeverShrinksAnOverflowingContainer() {
    #expect(lineStretchAmount(.stretch, freeSpace: -90, lineCount: 3) == 0)
    #expect(lineStretchAmount(.stretch, freeSpace: 0, lineCount: 3) == 0)
    #expect(distributeLines(.flexEnd, freeSpace: -90, lineCount: 3).leading == -90)
}

/// A stretched LINE changes what a stretch-eligible ITEM inside it fills.
///
/// **Order is the whole subtlety: distribute to lines first, resolve item
/// stretch second.** Reversed, `stretched` fills line 0's NATURAL 40 and then
/// sits in a 125-tall line with 85px of slack beneath it — the item is wrong,
/// not just the line.
///
/// This is `stretchFillsTheItemsOwnLineNotTheContainer`'s exact tree with
/// `align-content` left at CSS's default, so it also pins that the default is
/// `stretch` and not `flex-start`. The numbers are WebKit's, measured on this
/// tree during the previous task and recorded in
/// `docs/superpowers/2026-08-25-wrapping-decisions.md` as the divergence this
/// task closes: 300 - 40 - 90 = 170 leftover, 85 to each of the two lines, so
/// line 0 is 125 and line 1 starts at 125.
///
/// 125 is distinguishable from all three wrong answers: 40 (item stretch before
/// line growth, or `align-content: flex-start`), 300 (stretch fills the
/// container) and 175 (line 1's stretched size).
@Test func aStretchedLineChangesWhatItsStretchedItemsFill() {
    let tree = LayoutTree()
    let tall = item(tree, main: 120, cross: 40)
    var autoStyle = Style()
    autoStyle.size = Size(width: px(120), height: .auto)
    let stretched = tree.newNode(style: autoStyle, children: [])
    let second = item(tree, main: 120, cross: 90)

    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.flexWrap = .wrap
    // `alignContent` deliberately NOT set — the default is what is under test.
    rootStyle.size = Size(width: px(260), height: px(300))
    let root = tree.newNode(style: rootStyle, children: [tall, stretched, second])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    #expect(tree.layout(stretched).height == 125)
    #expect(tree.layout(stretched).y == 0)
    // The explicit-height item on the same line does NOT grow — only the line
    // does, and only `auto`-cross items follow it.
    #expect(tree.layout(tall).height == 40)
    #expect(tree.layout(second).y == 125)
    #expect(tree.layout(second).height == 90)
}

/// A `nowrap` container's leftover cross space is zero by construction, so
/// `align-content` cannot move anything on it — whatever value it declares.
///
/// This is the guarantee that keeps all 40 pre-wrapping goldens byte-identical,
/// and it is a property of §9.4.8's single-line clause (the line's cross size
/// IS the container's content-box cross extent), not of a `flexWrap` check in
/// the align-content code. **Four values are asserted, not one** — the loop
/// covers `spaceBetween`, `flexEnd`, `center` and `stretch` against a container
/// far taller than its items, which are the four that move a line in four
/// different ways if any leftover leaks in. The remaining three
/// (`flexStart`, `spaceAround`, `spaceEvenly`) are covered transitively: a
/// leftover of exactly 0 makes `flexStart` a no-op by definition, and the two
/// `space-*` values collapse onto `center`'s answer at `lineCount == 1`.
@Test func alignContentIsANoOpForNowrap() {
    for value in [AlignContent.spaceBetween, .flexEnd, .center, .stretch] {
        let tree = LayoutTree()
        let a = item(tree, main: 60, cross: 20)
        let b = item(tree, main: 90, cross: 35)

        var rootStyle = Style()
        rootStyle.flexDirection = .row
        rootStyle.flexWrap = .noWrap
        rootStyle.alignContent = value
        rootStyle.size = Size(width: px(300), height: px(240))
        let root = tree.newNode(style: rootStyle, children: [a, b])

        computeLayout(tree, root: root,
                      available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

        #expect(tree.layout(a).y == 0, "align-content \(value) moved a nowrap line")
        #expect(tree.layout(b).y == 0, "align-content \(value) moved a nowrap line")
    }
}

/// `align-content: space-between` x the box model, against WebKit.
///
/// `flex_wrap_align_content_between` is the fixture; its HTML lists why it has
/// three lines rather than two, why each line's cross size differs, and why the
/// 68px of leftover space is the thing that makes the seven values
/// distinguishable at all. The container's asymmetric padding and border are
/// what make it a composition rather than a second unit test: the lines are
/// distributed inside the CONTENT box, and the row-gap between them is space
/// already spent that `align-content` must not spend again.
@Test func wrapAlignContentBetweenMatchesWebKit() throws {
    let golden = try loadGolden("flex_wrap_align_content_between")
    let tree = LayoutTree()
    let a = item(tree, main: 80,  cross: 28)
    let b = item(tree, main: 100, cross: 40)
    let c = item(tree, main: 70,  cross: 18)
    let d = item(tree, main: 130, cross: 52)
    let e = item(tree, main: 110, cross: 24)
    let f = item(tree, main: 90,  cross: 36)

    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.flexWrap = .wrap
    rootStyle.alignContent = .spaceBetween
    rootStyle.gap = Axes(horizontal: pxL(7), vertical: pxL(9))
    rootStyle.size = Size(width: px(300), height: px(240))
    rootStyle.padding = Edges(top: pxL(8), right: pxL(10), bottom: pxL(12), left: pxL(14))
    rootStyle.border = Edges(top: pxL(2), right: pxL(3), bottom: pxL(4), left: pxL(5))
    let root = tree.newNode(style: rootStyle, children: [a, b, c, d, e, f])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    assertMatchesGolden(tree,
                        ids: [root: "root", a: "a", b: "b", c: "c", d: "d", e: "e", f: "f"],
                        golden: golden, tolerance: 0.1)
}

/// `align-content: center` on a COLUMN, against WebKit.
///
/// `flex_wrap_align_content_center` is the fixture. A column's cross axis is
/// horizontal, so its lines stack left-to-right and `align-content` distributes
/// leftover WIDTH — every other wrapped fixture in the corpus is a row, and an
/// implementation that assumed a vertical cross axis would pass all of them.
/// It also mirrors ruling WR-1: here the MAIN gap is `row-gap` (8) and the gap
/// between LINES is `column-gap` (11).
@Test func wrapAlignContentCenterOnAColumnMatchesWebKit() throws {
    let golden = try loadGolden("flex_wrap_align_content_center")
    let tree = LayoutTree()
    // A column's main axis is vertical, so `main:` is the height here.
    func child(w: Double, h: Double) -> LayoutNodeID {
        var s = Style()
        s.size = Size(width: px(w), height: px(h))
        return tree.newNode(style: s, children: [])
    }
    let a = child(w: 45, h: 50)
    let b = child(w: 60, h: 70)
    let c = child(w: 80, h: 40)
    let d = child(w: 55, h: 90)
    let e = child(w: 40, h: 60)
    let f = child(w: 70, h: 30)

    var rootStyle = Style()
    rootStyle.flexDirection = .column
    rootStyle.flexWrap = .wrap
    rootStyle.alignContent = .center
    rootStyle.gap = Axes(horizontal: pxL(11), vertical: pxL(8))
    rootStyle.size = Size(width: px(320), height: px(150))
    let root = tree.newNode(style: rootStyle, children: [a, b, c, d, e, f])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    assertMatchesGolden(tree,
                        ids: [root: "root", a: "a", b: "b", c: "c", d: "d", e: "e", f: "f"],
                        golden: golden, tolerance: 0.1)
}

/// `align-content: stretch` — the DEFAULT — x item stretch, against WebKit.
///
/// `flex_wrap_align_content_stretch` is the fixture, and it declares no
/// `align-content` at all: it pins CSS's initial value, which is what the
/// previous task diverged from. Neither does this tree — `rootStyle.alignContent`
/// is deliberately left `nil` below.
///
/// It is the one fixture where line growth is observable in the ITEMS rather
/// than only in their positions, because every line carries an `auto`-cross
/// child. `.d` adds a `max-height` and `.f` cross margins, so the clamp and
/// margin-subtraction orderings are re-measured against a GROWN line rather
/// than a natural one.
@Test func wrapAlignContentStretchMatchesWebKit() throws {
    let golden = try loadGolden("flex_wrap_align_content_stretch")
    let tree = LayoutTree()

    let a = item(tree, main: 90, cross: 30)

    var bStyle = Style()
    bStyle.size = Size(width: px(100), height: .auto)
    let b = tree.newNode(style: bStyle, children: [])

    let c = item(tree, main: 120, cross: 50)

    var dStyle = Style()
    dStyle.size = Size(width: px(80), height: .auto)
    dStyle.maxSize = Size(width: .auto, height: px(60))
    let d = tree.newNode(style: dStyle, children: [])

    let e = item(tree, main: 70, cross: 22)

    var fStyle = Style()
    fStyle.size = Size(width: px(60), height: .auto)
    fStyle.margin = Edges(top: px(5), right: px(0), bottom: px(9), left: px(0))
    let f = tree.newNode(style: fStyle, children: [])

    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.flexWrap = .wrap
    // `alignContent` deliberately NOT set — the fixture does not set it either.
    rootStyle.gap = Axes(horizontal: pxL(10), vertical: pxL(12))
    rootStyle.size = Size(width: px(250), height: px(300))
    let root = tree.newNode(style: rootStyle, children: [a, b, c, d, e, f])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    assertMatchesGolden(tree,
                        ids: [root: "root", a: "a", b: "b", c: "c", d: "d", e: "e", f: "f"],
                        golden: golden, tolerance: 0.1)
}
