import Testing
import MetalUICore
@testable import MetalUILayout

// C14b (`SB-F`): the descendant-rect hash of a retained subtree's replay key (`LayoutTree.subtreeSignature`).
// Window-level pins are `MetalUITestingTests/RetainedSubtreeSemanticsTests.swift`. Counts, never time.

private func column(_ tree: LayoutTree, innerWidth: Double) -> LayoutNodeID {
    let a = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: innerWidth, height: 10)) }
    let b = tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 20, height: 10)) }
    let stack = tree.newNativeLinearStack(children: [a, b], axis: .vertical)
    // A fixed outer frame: the top node's rect is the same whatever the inner width is.
    return tree.newNativeFrame(child: stack, width: 100, height: 40)
}

/// 1.3 (interior) — two subtrees whose top node has the same rect and whose descendants differ hash
/// differently, and the node count is the subtree's (the key's `interior` and `nodeCount`). Mutation: a
/// descendant's rect left out of the hash (`for child in childLists[index]` dropped) — equal hashes.
@Test @MainActor func theSignatureSeesADescendantTheTopRectDoesNot() {
    func run(_ innerWidth: Double) -> (hash: Int, count: Int, top: LayoutRect) {
        let tree = LayoutTree(generation: 1)
        let root = column(tree, innerWidth: innerWidth)
        tree.computeNativeLayout(root: root, proposal: ProposedSize(width: 200, height: 200),
                                 in: LayoutRect(x: 0, y: 0, width: 200, height: 200))
        let (hash, count) = tree.subtreeSignature(of: [root])
        return (hash, count, tree.layout(root))
    }
    let narrow = run(30), wide = run(60), again = run(30)
    #expect(narrow.top == wide.top, "the frame fixes the top rect")
    #expect(narrow.count == 4 && wide.count == 4, "frame, stack and two leaves")
    #expect(narrow.hash != wide.hash, "a descendant's rect is in the hash")
    #expect(narrow.hash == again.hash, "and the hash is a function of the layout")
}
