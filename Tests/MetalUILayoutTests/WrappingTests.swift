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
/// 300 and not to 90. Nothing before this task could tell those apart, because
/// there was only ever one line and its cross size WAS the container's.
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

// MARK: - Scoped divergences this task knowingly ships

/// Wrapped lines pack from cross-start; CSS's initial `align-content` is
/// `stretch`.
///
/// **Delete this test in Task 2**, which implements `align-content`. It exists
/// so the divergence is a decision rather than a surprise, and it names
/// WebKit's real numbers, measured on the exact tree below with a probe
/// fixture that was deliberately not committed (the same treatment as the
/// WebKit sub-one-flex divergence: a future fix must move nothing in the
/// corpus):
///
/// ```
///            engine (flex-start)   WebKit (stretch)
///   b        120x40 at (120, 0)    120x125 at (120, 0)
///   c        120x90 at (0, 40)     120x90  at (0, 125)
/// ```
///
/// WebKit's 125 is line 0's own 40 plus its share of the 170 left over
/// (300 - 40 - 90), split evenly between the two lines. Every wrapped fixture
/// in the corpus declares `align-content: flex-start` explicitly so that no
/// GOLDEN encodes this — only this test does.
@Test func wrappedLinesPackFromCrossStartRatherThanStretching() {
    let tree = LayoutTree()
    let a = item(tree, main: 120, cross: 40)
    var autoStyle = Style()
    autoStyle.size = Size(width: px(120), height: .auto)
    let b = tree.newNode(style: autoStyle, children: [])
    let c = item(tree, main: 120, cross: 90)

    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.flexWrap = .wrap
    rootStyle.size = Size(width: px(260), height: px(300))
    let root = tree.newNode(style: rootStyle, children: [a, b, c])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    #expect(tree.layout(b).height == 40)     // WebKit: 125
    #expect(tree.layout(c).y == 40)          // WebKit: 125
}

/// `wrap-reverse` wraps but does not reverse.
///
/// `collectLines` treats it as `.wrap`, and nothing stacks the lines from the
/// cross-END. Task 3 owns the reversal; until then a `wrap-reverse` container
/// lays out identically to a `wrap` one — which is a *better* answer than the
/// `nowrap` it produced before this task, and still not CSS's. CLAUDE.md's
/// inert-API table carries the row. **Delete both when Task 3 lands.**
///
/// CSS's answer for the tree below: line 0 at the container's cross-END, so
/// `c` (line 1) would sit above `a` and `b`, not below them.
@Test func wrapReverseCollectsLinesButDoesNotReverseThemYet() {
    let tree = LayoutTree()
    let a = item(tree, main: 120, cross: 40)
    let b = item(tree, main: 120, cross: 30)
    let c = item(tree, main: 120, cross: 90)

    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.flexWrap = .wrapReverse
    rootStyle.size = Size(width: px(260), height: px(300))
    let root = tree.newNode(style: rootStyle, children: [a, b, c])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    // Wrapped — `nowrap` would put all three on one line at y = 0.
    #expect(tree.layout(c).y == 40)
    // Not reversed — CSS puts line 1 ABOVE line 0 here, i.e. `c` at y = 0
    // and `a`/`b` at y = 210.
    #expect(tree.layout(a).y == 0)
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
    // Inert today — the engine packs lines from cross-start regardless — but
    // declared because the FIXTURE declares it, and Task 2 makes it load-bearing.
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
