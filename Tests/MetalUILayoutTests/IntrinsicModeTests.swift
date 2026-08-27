import Testing
import MetalUICore
@testable import MetalUILayout

/// A container asked for min-content must ask its children for min-content.
/// Before this task the leaf received `.maxContent` under both queries.
@Test func aContainersIntrinsicQueryReachesItsChildren() {
    let tree = LayoutTree(generation: 0)
    let leaf = tree.newLeaf(style: Style()) { _, available in
        if case .minContent = available.width { return SizeD(width: 30, height: 40) }
        return SizeD(width: 90, height: 20)
    }
    var row = Style()
    row.flexDirection = .row
    let container = tree.newNode(style: row, children: [leaf])

    let ctx = LayoutContext(rootFontSize: 16)
    let narrow = measureNode(ctx, tree, container, known: .unspecified,
                             available: AvailableSpaceSize(width: .minContent, height: .maxContent),
                             containingBlockWidth: nil)
    let wide = measureNode(LayoutContext(rootFontSize: 16), tree, container, known: .unspecified,
                           available: AvailableSpaceSize(width: .maxContent, height: .maxContent),
                           containingBlockWidth: nil)
    #expect(narrow.width == 30)
    #expect(wide.width == 90)
}

/// §9.9.1.1: under min-content the line budget is zero, so each item lines
/// alone. This is a WRAPPING fact, not a base-size fact — no amount of
/// `flexBaseSize` work reaches it, which is why `collectLines` is in scope here.
@Test func aWrapContainerUnderMinContentPutsEachItemOnItsOwnLine() {
    let tree = LayoutTree(generation: 0)
    var kid = Style()
    kid.size = Size(width: .length(.pixels(Pixels(40))),
                    height: .length(.pixels(Pixels(20))))
    let kids = (0..<3).map { _ in tree.newNode(style: kid, children: []) }
    var wrap = Style()
    wrap.flexDirection = .row
    wrap.flexWrap = .wrap
    let container = tree.newNode(style: wrap, children: kids)

    let narrow = measureNode(LayoutContext(rootFontSize: 16), tree, container,
                             known: .unspecified,
                             available: AvailableSpaceSize(width: .minContent, height: .maxContent),
                             containingBlockWidth: nil)
    let wide = measureNode(LayoutContext(rootFontSize: 16), tree, container,
                           known: .unspecified,
                           available: AvailableSpaceSize(width: .maxContent, height: .maxContent),
                           containingBlockWidth: nil)
    #expect(narrow == SizeD(width: 40, height: 60))
    #expect(wide == SizeD(width: 120, height: 20))
}
