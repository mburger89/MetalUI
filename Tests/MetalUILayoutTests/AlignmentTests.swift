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
