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
    let tree = LayoutTree()
    let items = (0..<3).map { _ in
        FlexItem(node: fixedChild(tree, w: 50, h: 10), baseSize: 50,
                 hypotheticalMainSize: 50, minMain: nil, maxMain: nil,
                 targetMainSize: 50, crossSize: 10, frozen: true)
    }
    #expect(lineContentSize(items, gap: 12) == 174)
    #expect(lineContentSize(items, gap: 0) == 150)
    // One item has no gaps at all.
    #expect(lineContentSize([items[0]], gap: 12) == 50)
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
