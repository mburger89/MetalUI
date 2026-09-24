import Testing
import MetalUICore
@testable import MetalUILayout

/// A native 0×0 leaf: the one registration the id, generation, reset and
/// adoption tests below need. **Re-spelled at stage 9** (`LR-FC`): these tests
/// minted ids with the CSS `newNode(style:children:)`, deleted with the legacy
/// engine; each fact is about ids, not about which engine owns the node.
private func leaf(_ tree: LayoutTree) -> LayoutNodeID {
    tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 0, height: 0)) }
}

/// **`treeStoresStyleAndChildren` until stage 9**: its style half read the
/// legacy rows stage 9 deleted (`LR-FC`); the children half is kept, on native
/// nodes.
@Test func treeStoresChildren() {
    let tree = LayoutTree(generation: 0)
    let child = leaf(tree)
    let root = tree.newNativeOverlay(children: [child])

    #expect(tree.nodeCount == 2)
    #expect(tree.children(root) == [child])
    #expect(tree.children(child).isEmpty)
}

@Test func resetClearsNodesForReuse() {
    let tree = LayoutTree(generation: 0)
    _ = leaf(tree)
    _ = leaf(tree)
    #expect(tree.nodeCount == 2)
    tree.reset(generation: 1)
    #expect(tree.nodeCount == 0)
    let fresh = leaf(tree)
    #expect(fresh.index == 0)   // indices restart, so the arena truly reuses storage
}

/// Ruling C-3: an id minted before a `reset` is **detectably** stale afterwards.
///
/// The index alone cannot say so — `stale.index` and `fresh.index` are both 0
/// here, which is the whole hazard: before generations, `tree.layout(stale)`
/// returned `fresh`'s rect with no error. Both halves are asserted, because
/// `isCurrent` returning a constant `false` would satisfy the first alone.
@Test func anIdFromBeforeAResetIsNotCurrentAfterIt() {
    let tree = LayoutTree(generation: 7)
    let stale = leaf(tree)
    tree.setLayout(stale, LayoutRect(x: 1, y: 2, width: 3, height: 4))
    #expect(tree.isCurrent(stale))

    tree.reset(generation: 8)
    let fresh = leaf(tree)

    #expect(stale.index == fresh.index)     // indistinguishable without a generation
    #expect(!tree.isCurrent(stale))
    #expect(tree.isCurrent(fresh))
}

/// Ids do not cross between two trees that were given different generations.
///
/// This is the shape `MetalUI.Frame` relies on: a fresh `LayoutTree` per frame,
/// never `reset`, so cross-frame staleness is a *different-tree* question rather
/// than a reset question. Both directions are asserted so a mutation that makes
/// `isCurrent` compare the wrong operand is visible.
@Test func anIdFromOneTreeIsNotCurrentInAnother() {
    let first = LayoutTree(generation: 1)
    let second = LayoutTree(generation: 2)
    let a = leaf(first)
    let b = leaf(second)

    #expect(a.index == b.index)
    #expect(first.isCurrent(a))
    #expect(!first.isCurrent(b))
    #expect(second.isCurrent(b))
    #expect(!second.isCurrent(a))
}

@Test func layoutResultsAreStoredPerNode() {
    let tree = LayoutTree(generation: 0)
    let n = leaf(tree)
    #expect(tree.layout(n) == LayoutRect(x: 0, y: 0, width: 0, height: 0))
    tree.setLayout(n, LayoutRect(x: 5, y: 6, width: 7, height: 8))
    #expect(tree.layout(n) == LayoutRect(x: 5, y: 6, width: 7, height: 8))
}

/// Using an id against the wrong tree **traps** rather than answering.
///
/// `isCurrent` only reports; this is the half that acts, and no in-process
/// assertion can observe it — so it runs in a subprocess and the exit status is
/// the assertion. The index is deliberately **in range** in the second tree (0
/// of 3), which is what makes the failure attributable: an out-of-range index
/// would abort for a reason that has nothing to do with generations, and ruling
/// C-3's whole point is that the in-range case is the silent one.
@Test func usingAnIdAgainstAnotherTreeTraps() async {
    let result = await #expect(processExitsWith: .failure,
                               observing: [\.standardErrorContent]) {
        let issuer = LayoutTree(generation: 1)
        let other = LayoutTree(generation: 2)
        let id = leaf(issuer)
        for _ in 0..<3 { _ = leaf(other) }
        _ = other.layout(id)
    }
    // The exit status alone would be satisfied by any abort in that body — an
    // out-of-range index, a fatal error somewhere else. The message is what
    // attributes it to the generation check.
    let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(stderr.contains("outlived the tree that issued it"),
            "aborted, but not at the guard this test is about:\n\(stderr)")
}

/// The positive control for `usingAnIdAgainstAnotherTreeTraps`.
///
/// Byte-for-byte the same body but reading the id in the tree that issued it.
/// Without this, "the subprocess died" would be satisfied by a build that traps
/// on every `layout` call, or on nothing to do with generations at all.
@Test func usingAnIdAgainstItsOwnTreeDoesNotTrap() async {
    await #expect(processExitsWith: .success) {
        let issuer = LayoutTree(generation: 1)
        let other = LayoutTree(generation: 2)
        let id = leaf(issuer)
        for _ in 0..<3 { _ = leaf(other) }
        _ = issuer.layout(id)
    }
}

/// A `reset` that does not advance the generation **traps**.
///
/// This is ruling C-3's literal trigger and it had no test: `reset(generation:)`
/// requiring a strictly greater value is the entire reason ids minted before a
/// reset are detectably stale, and reusing 5 leaves every one of them
/// `isCurrent` against a tree whose storage has been refilled with unrelated
/// nodes. `anIdFromBeforeAResetIsNotCurrentAfterIt` cannot see this — it passes
/// a greater generation, as any well-behaved caller does.
@Test func resettingToAGenerationThatDoesNotAdvanceTraps() async {
    let result = await #expect(processExitsWith: .failure,
                               observing: [\.standardErrorContent]) {
        let tree = LayoutTree(generation: 5)
        _ = leaf(tree)
        tree.reset(generation: 5)
    }
    let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(stderr.contains("does not advance past"),
            "aborted, but not at the guard this test is about:\n\(stderr)")
}

/// The positive control for `resettingToAGenerationThatDoesNotAdvanceTraps`.
///
/// The same body with 6 instead of 5, so "the subprocess died" cannot be
/// satisfied by a `reset` that traps unconditionally, or by anything else in
/// the body.
@Test func resettingToAGreaterGenerationDoesNotTrap() async {
    await #expect(processExitsWith: .success) {
        let tree = LayoutTree(generation: 5)
        _ = leaf(tree)
        tree.reset(generation: 6)
    }
}

/// A node cannot adopt a child issued by another tree.
///
/// The check at registration is the one place a foreign id would otherwise be
/// *stored* rather than merely read: it would sit in `childLists` and be handed
/// to the engine on the next layout, where the trap would fire far from the
/// call that caused it. Catching it at the point of adoption is what makes the
/// abort attributable. (Through `newNode`'s check until stage 9; a native
/// registrar reaches the same `slot(_:)` check through `nativeNode(_:)`.)
@Test func adoptingAChildFromAnotherTreeTraps() async {
    let result = await #expect(processExitsWith: .failure,
                               observing: [\.standardErrorContent]) {
        let issuer = LayoutTree(generation: 1)
        let other = LayoutTree(generation: 2)
        let foreign = leaf(issuer)
        _ = other.newNativeOverlay(children: [foreign])
    }
    let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(stderr.contains("outlived the tree that issued it"),
            "aborted, but not at the guard this test is about:\n\(stderr)")
}

/// The positive control for `adoptingAChildFromAnotherTreeTraps`: the same two
/// trees, the child adopted by the tree that issued it.
@Test func adoptingAChildFromTheSameTreeDoesNotTrap() async {
    await #expect(processExitsWith: .success) {
        let issuer = LayoutTree(generation: 1)
        let other = LayoutTree(generation: 2)
        let own = leaf(issuer)
        _ = leaf(other)
        _ = issuer.newNativeOverlay(children: [own])
    }
}
