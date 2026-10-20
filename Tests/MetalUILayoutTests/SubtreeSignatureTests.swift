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

/// 2.11 (`FS-D`, lane 2) — the signature taken relative to the first top node's origin is a function of the subtree's
/// **shape**: the same subtree laid out at two origins hashes equal relative and different absolute, a descendant that
/// differs still differs, and an origin that is not the top node's moves it. Mutation: the origin subtracted from x only
/// (the vertical shift's relative hashes differ).
@Test @MainActor func aRelativeSubtreeSignatureIsTranslationInvariant() {
    func run(innerWidth: Double, x: Double, y: Double) -> (absolute: Int, relative: Int, count: Int) {
        let tree = LayoutTree(generation: 1)
        let root = column(tree, innerWidth: innerWidth)
        tree.computeNativeLayout(root: root, proposal: ProposedSize(width: 200, height: 200),
                                 in: LayoutRect(x: x, y: y, width: 200, height: 200))
        let top = tree.layout(root)
        let relative = tree.subtreeSignature(of: [root], relativeTo: (x: top.x, y: top.y))
        return (tree.subtreeSignature(of: [root]).hash, relative.hash, relative.count)
    }
    let here = run(innerWidth: 30, x: 0, y: 0), shifted = run(innerWidth: 30, x: 24, y: 0)
    let lower = run(innerWidth: 30, x: 0, y: 17), both = run(innerWidth: 30, x: 24, y: 17)
    let wide = run(innerWidth: 60, x: 24, y: 17)
    #expect(here.absolute != shifted.absolute && here.absolute != lower.absolute, "the absolute hash sees the move")
    #expect(here.relative == shifted.relative, "a horizontal move leaves the relative hash")
    #expect(here.relative == lower.relative, "a vertical move leaves the relative hash")
    #expect(here.relative == both.relative && here.count == 4, "so does a move on both axes")
    #expect(both.relative != wide.relative, "a descendant that differs still differs")
}
