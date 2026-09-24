import Testing
import Foundation
import MetalUICore
@testable import MetalUILayout

private func px(_ v: Double) -> MetalUICore.Dimension { .length(.pixels(Pixels(Float(v)))) }

private func fixedChild(_ tree: LayoutTree, w: Double, h: Double) -> LayoutNodeID {
    var s = Style()
    s.size = Size(width: px(w), height: px(h))
    return tree.newNode(style: s, children: [])
}

/// A line's content size counts gaps **between** items only.
///
/// Three 50px items with `gap: 12` occupy 174, not 186. Nothing has read this
/// value since M1a — `cursor` died with the loop — so an implementation that
/// added a trailing gap passed the entire suite. `justify-content` reads it as
/// the divisor for free space, which is what finally makes it observable.
@Test func lineContentSizeCountsGapsBetweenItemsOnly() {
    let tree = LayoutTree(generation: 0)
    let items = (0..<3).map { _ in
        FlexItem(node: fixedChild(tree, w: 50, h: 10), baseSize: 50, mainEdges: 0,
                 hypotheticalMainSize: 50, minMain: nil, maxMain: nil,
                 targetMainSize: 50, crossSize: 10,
                 stretchEligible: false, minCross: nil, maxCross: nil, frozen: true,
                 marginMain: (0, 0), marginCross: (0, 0))
    }
    #expect(lineContentSize(items.map(\.targetMainSize), gap: 12) == 174)
    #expect(lineContentSize(items.map(\.targetMainSize), gap: 0) == 150)
    // One item has no gaps at all.
    #expect(lineContentSize([items[0].targetMainSize], gap: 12) == 50)
    // Zero items is a degenerate case the caller guards, but must not underflow
    // to a negative content size.
    #expect(lineContentSize([], gap: 12) == 0)
}

/// `space-around` and `space-evenly` differ only at the container's edges.
///
/// With 2 items and 90 free: `around` gives each item 45 of margin, so the
/// leading edge is 22.5 and the space between two items is 45. `evenly` splits
/// into 3 equal runs of 30. A test with one item cannot tell them apart — both
/// centre it — which is why this uses two.
@Test func spaceAroundAndSpaceEvenlyDifferAtTheEdges() {
    let around = distributeMainAxis(.spaceAround, freeSpace: 90, itemCount: 2)
    #expect(around.leading == 22.5)
    #expect(around.between == 45)

    let evenly = distributeMainAxis(.spaceEvenly, freeSpace: 90, itemCount: 2)
    #expect(evenly.leading == 30)
    #expect(evenly.between == 30)

    let between = distributeMainAxis(.spaceBetween, freeSpace: 90, itemCount: 2)
    #expect(between.leading == 0)
    #expect(between.between == 90)
}

@Test func flexStartEndAndCentrePlaceTheWholeLine() {
    #expect(distributeMainAxis(.flexStart, freeSpace: 90, itemCount: 3).leading == 0)
    #expect(distributeMainAxis(.flexEnd, freeSpace: 90, itemCount: 3).leading == 90)
    #expect(distributeMainAxis(.center, freeSpace: 90, itemCount: 3).leading == 45)
    for j in [JustifyContent.flexStart, .flexEnd, .center] {
        #expect(distributeMainAxis(j, freeSpace: 90, itemCount: 3).between == 0,
                "\(j) must not add space between items")
    }
}

/// A single item collapses `space-between` onto `flex-start`, and both
/// `space-around` and `space-evenly` onto `center`. CSS says so explicitly, and
/// it is the degenerate case every one-item fixture would hide.
@Test func distributionWithOneItemCollapsesToTheCssDegenerateCases() {
    #expect(distributeMainAxis(.spaceBetween, freeSpace: 90, itemCount: 1).leading == 0)
    #expect(distributeMainAxis(.spaceAround, freeSpace: 90, itemCount: 1).leading == 45)
    #expect(distributeMainAxis(.spaceEvenly, freeSpace: 90, itemCount: 1).leading == 45)
}

/// Overflow must not push the line backwards under the space-* values.
///
/// CSS clamps the *distributed* portion at zero: an overflowing line under
/// `space-between` still starts at the container's start edge. Negative free
/// space distributed as though positive would put later items at smaller
/// coordinates than earlier ones.
@Test func negativeFreeSpaceNeverDistributesBackwards() {
    for j in [JustifyContent.spaceBetween, .spaceAround, .spaceEvenly] {
        let o = distributeMainAxis(j, freeSpace: -120, itemCount: 3)
        #expect(o.between == 0, "\(j) distributed negative space between items")
        #expect(o.leading == 0, "\(j) pushed an overflowing line off the start edge")
    }
    // flex-end and center DO honour negative free space — an overflowing
    // centred line overhangs both edges equally. That is CSS, not a bug.
    #expect(distributeMainAxis(.center, freeSpace: -120, itemCount: 3).leading == -60)
}

/// Cross-axis placement, with a line 100 tall and items that are not.
///
/// Every item here has a *different* cross size, and none equals the line's —
/// with uniform cross sizes all four values produce identical output and the
/// test pins nothing.
@Test func crossAxisOffsetPlacesAnItemWithinTheLine() {
    #expect(crossAxisOffset(.flexStart, itemCross: 30, lineCross: 100) == 0)
    #expect(crossAxisOffset(.flexEnd,   itemCross: 30, lineCross: 100) == 70)
    #expect(crossAxisOffset(.center,    itemCross: 30, lineCross: 100) == 35)
    // A different item size must move the answer — a constant would pass above.
    #expect(crossAxisOffset(.center,    itemCross: 60, lineCross: 100) == 20)
    #expect(crossAxisOffset(.flexEnd,   itemCross: 60, lineCross: 100) == 40)
}

/// An item taller than its line overhangs; it is never pushed to a negative
/// offset by `flex-start`, nor clamped by `flex-end`.
@Test func anItemLargerThanItsLineOverhangsRatherThanClamping() {
    #expect(crossAxisOffset(.flexStart, itemCross: 140, lineCross: 100) == 0)
    #expect(crossAxisOffset(.flexEnd,   itemCross: 140, lineCross: 100) == -40)
    #expect(crossAxisOffset(.center,    itemCross: 140, lineCross: 100) == -20)
}

/// `align-self` overrides the container's `align-items`; nil defers to it; and
/// the container's own nil default is `stretch`, not `flex-start`.
@Test func alignSelfOverridesAlignItemsAndTheDefaultIsStretch() {
    var container = Style()
    container.alignItems = .center

    var item = Style()
    #expect(resolvedAlignment(item, container: container) == .center)

    item.alignSelf = .flexEnd
    #expect(resolvedAlignment(item, container: container) == .flexEnd)

    // CSS's initial `align-items` is `normal`, which behaves as `stretch` on a
    // flex item. Defaulting to `flex-start` here would make Task 3's stretch
    // work unreachable for every unstyled container in the corpus.
    #expect(resolvedAlignment(Style(), container: Style()) == .stretch)

    // Every `AlignSelf` case must map to its identically-named `AlignItems`
    // case. The assertions above only ever set `alignSelf` to `.flexEnd`, so
    // three of the five switch arms in `resolvedAlignment` were completely
    // unexercised: a combined mutation remapping `.stretch -> .flexStart`,
    // `.flexStart -> .center` and `.baseline -> .center` all at once passed
    // the whole suite. A `.stretch` typo there would silently disable Task
    // 3's stretch for every explicit `align-self: stretch`, surfacing three
    // tasks later as "stretch doesn't work sometimes".
    let pairs: [(AlignSelf, AlignItems)] = [
        (.flexStart, .flexStart),
        (.flexEnd,   .flexEnd),
        (.center,    .center),
        (.baseline,  .baseline),
        (.stretch,   .stretch),
    ]
    for (selfValue, expected) in pairs {
        var probe = Style()
        probe.alignSelf = selfValue
        #expect(resolvedAlignment(probe, container: container) == expected,
                "align-self: \(selfValue) should resolve to \(expected)")
    }
}

// MARK: - CSS Flexbox §9.4, cross-axis stretch.

/// `stretch` fills the line's cross extent — but only for an item whose cross
/// size is `auto`, and never past its cross-axis max.
///
/// Three children with three different outcomes, because a rule that stretched
/// everything and a rule that stretched the right things are indistinguishable
/// from any set where every item is auto-sized: `stretched` is auto and fills
/// the 100 line, `definite` keeps its own 30, and `capped` is auto but stops at
/// its `max-height: 60`.
@Test func stretchFillsTheCrossAxisOnlyForAutoSizedItems() {
    let tree = LayoutTree(generation: 0)

    var autoStyle = Style()                       // height stays .auto
    autoStyle.size = Size(width: px(50), height: .auto)
    let stretched = tree.newNode(style: autoStyle, children: [])

    var definiteStyle = Style()                   // definite height wins
    definiteStyle.size = Size(width: px(50), height: px(30))
    let definite = tree.newNode(style: definiteStyle, children: [])

    var cappedStyle = Style()                     // auto, but capped at 60
    cappedStyle.size = Size(width: px(50), height: .auto)
    cappedStyle.maxSize = Size(width: .auto, height: px(60))
    let capped = tree.newNode(style: cappedStyle, children: [])

    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.size = Size(width: px(300), height: px(100))
    let root = tree.newNode(style: rootStyle, children: [stretched, definite, capped])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    #expect(tree.layout(stretched).height == 100)
    #expect(tree.layout(definite).height == 30)
    #expect(tree.layout(capped).height == 60)
}

/// The same rule on the other axis: in a **column**, stretch fills the width.
///
/// The row form above cannot distinguish `crossDim` being selected correctly
/// from it being hardwired to `size.height`. This one can: a column's cross
/// axis is width, so a hardwired height lookup finds `.auto` on a child whose
/// height is definite and stretches it anyway — 200 wide instead of 40, and a
/// height of 200 instead of its own 25.
@Test func stretchFillsTheWidthInAColumn() {
    let tree = LayoutTree(generation: 0)

    var autoStyle = Style()                       // width stays .auto
    autoStyle.size = Size(width: .auto, height: px(25))
    let stretched = tree.newNode(style: autoStyle, children: [])

    var definiteStyle = Style()                   // definite width wins
    definiteStyle.size = Size(width: px(40), height: px(25))
    let definite = tree.newNode(style: definiteStyle, children: [])

    var cappedStyle = Style()                     // auto width, capped at 70
    cappedStyle.size = Size(width: .auto, height: px(25))
    cappedStyle.maxSize = Size(width: px(70), height: .auto)
    let capped = tree.newNode(style: cappedStyle, children: [])

    var rootStyle = Style()
    rootStyle.flexDirection = .column
    rootStyle.size = Size(width: px(200), height: px(300))
    let root = tree.newNode(style: rootStyle, children: [stretched, definite, capped])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    #expect(tree.layout(stretched).width == 200)
    #expect(tree.layout(definite).width == 40)
    #expect(tree.layout(capped).width == 70)
    // The main axis is untouched by stretch — every child keeps its own 25.
    #expect(tree.layout(stretched).height == 25)
    #expect(tree.layout(definite).height == 25)
    #expect(tree.layout(capped).height == 25)
}

/// A stretched size is floored by the item's cross-axis **min**, not only
/// capped by its max — and a min above the line makes the item overhang.
///
/// Without the floor the item takes the line's 100 and the assertion below
/// reads 100 instead of 140. The clamp's two halves need separate items
/// because one item cannot violate both bounds at once.
@Test func aStretchedSizeIsFlooredByTheCrossMinAsWellAsCappedByTheMax() {
    let tree = LayoutTree(generation: 0)

    var flooredStyle = Style()
    flooredStyle.size = Size(width: px(50), height: .auto)
    flooredStyle.minSize = Size(width: .auto, height: px(140))
    let floored = tree.newNode(style: flooredStyle, children: [])

    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.size = Size(width: px(300), height: px(100))
    let root = tree.newNode(style: rootStyle, children: [floored])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    #expect(tree.layout(floored).height == 140)
}

/// An explicit non-stretch alignment leaves an auto-sized item at its own size.
@Test func aNonStretchAlignmentLeavesAnAutoSizedItemUnstretched() {
    let tree = LayoutTree(generation: 0)
    var s = Style()
    s.size = Size(width: px(50), height: .auto)
    s.alignSelf = .center
    let item = tree.newNode(style: s, children: [])

    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.size = Size(width: px(300), height: px(100))
    let root = tree.newNode(style: rootStyle, children: [item])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    // Auto cross size with no content and no stretch is still 0 — and being 0,
    // `center` puts it at the line's midpoint.
    #expect(tree.layout(item).height == 0)
    #expect(tree.layout(item).y == 50)
}

/// A **percentage** cross min/max resolves against the container's **cross**
/// extent, not its main one.
///
/// This closes a green hole: mutating the stretch clamp's two `against:`
/// arguments from `containerCross` to `containerMain` reddened **nothing**.
/// It is the identical slip `percentageFlexBasisResolvesAgainstTheMainAxis`
/// (retired with its golden by stage 7a, record §48) existed to catch one axis
/// over — the flex basis had a guard, the cross
/// min/max had none, because every cross bound in the corpus is in pixels and a
/// pixel bound resolves the same against either extent.
///
/// The row is 700 x 100 so the two readings are arithmetically loud and cannot
/// be confused:
///
/// - `capped`: `max-height: 50%`. Against the cross 100 that is 50, and the
///   item stretches into its cap. Against the main 700 it is 350, no cap binds
///   at all, and the item takes the line's full 100.
/// - `floored`: `min-height: 150%`. Against the cross 100 that is 150, so the
///   item overhangs the line by 50. Against the main 700 it is 1050.
///
/// Both bounds are exercised because the mutation could land on either
/// `resolveDimension` call, and one item cannot violate a floor and a ceiling
/// at once.
@Test func aPercentageCrossBoundResolvesAgainstTheCrossExtentNotTheMain() {
    let tree = LayoutTree(generation: 0)

    var cappedStyle = Style()
    cappedStyle.size = Size(width: px(50), height: .auto)
    cappedStyle.maxSize = Size(width: .auto, height: .length(.percent(0.5)))
    let capped = tree.newNode(style: cappedStyle, children: [])

    var flooredStyle = Style()
    flooredStyle.size = Size(width: px(50), height: .auto)
    flooredStyle.minSize = Size(width: .auto, height: .length(.percent(1.5)))
    let floored = tree.newNode(style: flooredStyle, children: [])

    var rootStyle = Style()
    rootStyle.flexDirection = .row
    rootStyle.size = Size(width: px(700), height: px(100))
    let root = tree.newNode(style: rootStyle, children: [capped, floored])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    // 50% of the cross 100, not 50% of the main 700 (which would leave it at 100).
    #expect(tree.layout(capped).height == 50)
    // 150% of the cross 100, not 150% of the main 700 (which would give 1050).
    #expect(tree.layout(floored).height == 150)
}

// MARK: - Reverse flex directions.

/// `.rowReverse` packs from the main-end edge, and `justify-content: flex-start`
/// follows the reversed axis rather than the visual left.
///
/// Items of 40/70/50 in a 400 row: forward gives 0/40/110; reversed gives
/// 360/290/240. Equal-sized items in a full container would make the two
/// indistinguishable, which is why these differ.
@Test func rowReversePacksFromTheEndAndFlipsJustifyContent() {
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

    #expect(tree.layout(a) == LayoutRect(x: 360, y: 0, width: 40, height: 40))
    #expect(tree.layout(b) == LayoutRect(x: 290, y: 0, width: 70, height: 40))
    #expect(tree.layout(c) == LayoutRect(x: 240, y: 0, width: 50, height: 40))
}

/// Reverse flips the main axis only. The cross axis is untouched, so
/// `align-items: flex-end` still means the bottom of a reversed row.
@Test func reverseDoesNotFlipTheCrossAxis() {
    let tree = LayoutTree(generation: 0)
    var s = Style()
    s.size = Size(width: px(50), height: px(20))
    let item = tree.newNode(style: s, children: [])
    var rootStyle = Style()
    rootStyle.flexDirection = .rowReverse
    rootStyle.alignItems = .flexEnd
    rootStyle.size = Size(width: px(200), height: px(100))
    let root = tree.newNode(style: rootStyle, children: [item])

    computeLayout(tree, root: root,
                  available: AvailableSpaceSize(width: .definite(800), height: .definite(600)))

    #expect(tree.layout(item).y == 80)      // cross-end, not flipped to 0
    #expect(tree.layout(item).x == 150)     // main-end, flipped
}
