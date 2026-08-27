import Testing
import MetalUICore
@testable import MetalUILayout

private func px(_ v: Double) -> Dimension { .length(.pixels(Pixels(Float(v)))) }

/// A container reports the size its own children imply, with no layout written.
@Test func measuringARowContainerReturnsItsContentSize() {
    let tree = LayoutTree(generation: 0)
    var kid = Style()
    kid.size = Size(width: px(60), height: px(20))
    let a = tree.newNode(style: kid, children: [])
    let b = tree.newNode(style: kid, children: [])

    var row = Style()
    row.flexDirection = .row
    let container = tree.newNode(style: row, children: [a, b])

    let ctx = LayoutContext(rootFontSize: 16)
    let size = measureNode(ctx, tree, container,
                           known: .unspecified,
                           available: AvailableSpaceSize(width: .maxContent,
                                                         height: .maxContent),
                           containingBlockWidth: nil)
    #expect(size.width == 120)
    #expect(size.height == 20)
}

/// **The purity guard.** A `measureNode` that called `setLayout` would return
/// the correct size and pass every golden in the corpus; this is the only thing
/// that can see it. Asserts on the stored rects of *every* node, not just the
/// container's, because the recursion writes children first.
@Test func measuringWritesNoLayout() {
    let tree = LayoutTree(generation: 0)
    var kid = Style()
    kid.size = Size(width: px(60), height: px(20))
    let a = tree.newNode(style: kid, children: [])
    var row = Style()
    row.flexDirection = .row
    let container = tree.newNode(style: row, children: [a])

    let sentinel = LayoutRect(x: -1, y: -2, width: -3, height: -4)
    tree.setLayout(a, sentinel)
    tree.setLayout(container, sentinel)

    let ctx = LayoutContext(rootFontSize: 16)
    _ = measureNode(ctx, tree, container, known: .unspecified,
                    available: AvailableSpaceSize(width: .maxContent, height: .maxContent),
                    containingBlockWidth: nil)

    #expect(tree.layout(a) == sentinel)
    #expect(tree.layout(container) == sentinel)
}

/// A known size wins over the measured one — the `known` half of §5.5's contract.
@Test func aKnownSizeOverridesTheMeasuredOne() {
    let tree = LayoutTree(generation: 0)
    var kid = Style()
    kid.size = Size(width: px(60), height: px(20))
    let a = tree.newNode(style: kid, children: [])
    var row = Style()
    row.flexDirection = .row
    let container = tree.newNode(style: row, children: [a])

    let ctx = LayoutContext(rootFontSize: 16)
    let size = measureNode(ctx, tree, container,
                           known: OptionalSizeD(width: 200, height: nil),
                           available: AvailableSpaceSize(width: .definite(200),
                                                         height: .maxContent),
                           containingBlockWidth: nil)
    #expect(size.width == 200)
    #expect(size.height == 20)
}

/// A leaf with a measure function answers from it, so callers cannot tell a
/// leaf from a container. `newLeaf` has no production caller — this builds one.
@Test func measuringALeafUsesItsMeasureFunction() {
    let tree = LayoutTree(generation: 0)
    let leaf = tree.newLeaf(style: Style()) { _, available in
        if case .minContent = available.width { return SizeD(width: 30, height: 40) }
        return SizeD(width: 90, height: 20)
    }
    let ctx = LayoutContext(rootFontSize: 16)
    let wide = measureNode(ctx, tree, leaf, known: .unspecified,
                           available: AvailableSpaceSize(width: .maxContent, height: .maxContent),
                           containingBlockWidth: nil)
    let narrow = measureNode(ctx, tree, leaf, known: .unspecified,
                             available: AvailableSpaceSize(width: .minContent, height: .maxContent),
                             containingBlockWidth: nil)
    #expect(wide == SizeD(width: 90, height: 20))
    #expect(narrow == SizeD(width: 30, height: 40))
}

/// A container with no children measures 0, not a trap. `layOutChildren`'s
/// `guard !items.isEmpty` becomes a returned size here.
@Test func measuringAnEmptyContainerIsZeroNotATrap() {
    let tree = LayoutTree(generation: 0)
    let container = tree.newNode(style: Style(), children: [])
    let ctx = LayoutContext(rootFontSize: 16)
    let size = measureNode(ctx, tree, container, known: .unspecified,
                           available: AvailableSpaceSize(width: .maxContent, height: .maxContent),
                           containingBlockWidth: nil)
    #expect(size == SizeD.zero)
}

/// What `measureNode` reports is the **border** box, so padding and border sit
/// outside the extent the children imply.
///
/// Every other test in this file has zero padding and zero border, so dropping
/// the edge term reddens nothing there — and the omission would be silent
/// rather than wrong-looking, because the `known` branch above *does* answer in
/// border-box units (`known` is handed straight to `layOutChildren` as the
/// container's border box). Mixing the two units in one return value is the
/// defect this pins.
///
/// Four distinct padding edges plus a border, so a transposed edge or a
/// horizontal/vertical swap cannot cancel out (taxonomy shape 1).
@Test func measuringAContainerReportsItsBorderBoxNotItsContentBox() {
    let tree = LayoutTree(generation: 0)
    var kid = Style()
    kid.size = Size(width: px(60), height: px(20))
    let a = tree.newNode(style: kid, children: [])

    var row = Style()
    row.flexDirection = .row
    row.padding = Edges(top: .pixels(Pixels(5)), right: .pixels(Pixels(7)),
                        bottom: .pixels(Pixels(9)), left: .pixels(Pixels(11)))
    row.border = Edges(all: .pixels(Pixels(2)))
    let container = tree.newNode(style: row, children: [a])

    let ctx = LayoutContext(rootFontSize: 16)
    let size = measureNode(ctx, tree, container, known: .unspecified,
                           available: AvailableSpaceSize(width: .maxContent,
                                                         height: .maxContent),
                           containingBlockWidth: nil)
    // 60 + (11 + 7) padding + (2 + 2) border = 82.
    // 20 + (5 + 9) padding + (2 + 2) border = 38.
    #expect(size.width == 82)
    #expect(size.height == 38)
}
