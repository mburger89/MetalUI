import Testing
import MetalUICore
@testable import MetalUILayout

@Test func treeStoresStyleAndChildren() {
    let tree = LayoutTree()
    var childStyle = Style()
    childStyle.flexGrow = 1
    let child = tree.newNode(style: childStyle, children: [])
    var rootStyle = Style()
    rootStyle.flexDirection = .column
    let root = tree.newNode(style: rootStyle, children: [child])

    #expect(tree.nodeCount == 2)
    #expect(tree.children(root) == [child])
    #expect(tree.children(child).isEmpty)
    #expect(tree.style(child).flexGrow == 1)
    #expect(tree.style(root).flexDirection == .column)
}

@Test func leavesCarryAMeasureFunctionAndBranchesDoNot() throws {
    let tree = LayoutTree()
    let leaf = tree.newLeaf(style: Style()) { known, available in
        SizeD(width: known.width ?? 42, height: 7)
    }
    let branch = tree.newNode(style: Style(), children: [leaf])
    #expect(tree.measure(leaf) != nil)
    #expect(tree.measure(branch) == nil)

    let m = try #require(tree.measure(leaf))
    // Known width wins over available space.
    let sized = m(OptionalSizeD(width: 99, height: nil),
                  AvailableSpaceSize(width: .definite(500), height: .maxContent))
    #expect(sized.width == 99)
    #expect(sized.height == 7)
    // With no known width, the leaf returns its own natural size.
    let natural = m(OptionalSizeD(width: nil, height: nil),
                    AvailableSpaceSize(width: .maxContent, height: .maxContent))
    #expect(natural.width == 42)
}

@Test func resetClearsNodesForReuse() {
    let tree = LayoutTree()
    _ = tree.newNode(style: Style(), children: [])
    _ = tree.newNode(style: Style(), children: [])
    #expect(tree.nodeCount == 2)
    tree.reset()
    #expect(tree.nodeCount == 0)
    let fresh = tree.newNode(style: Style(), children: [])
    #expect(fresh.index == 0)   // indices restart, so the arena truly reuses storage
}

@Test func layoutResultsAreStoredPerNode() {
    let tree = LayoutTree()
    let n = tree.newNode(style: Style(), children: [])
    #expect(tree.layout(n) == LayoutRect(x: 0, y: 0, width: 0, height: 0))
    tree.setLayout(n, LayoutRect(x: 5, y: 6, width: 7, height: 8))
    #expect(tree.layout(n) == LayoutRect(x: 5, y: 6, width: 7, height: 8))
}
