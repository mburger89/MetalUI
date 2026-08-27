import Testing
import MetalUICore
@testable import MetalUILayout

@Test func aStyleWrittenDuringLayoutTraps() async {
    await #expect(processExitsWith: .failure) {
        let tree = LayoutTree(generation: 0)
        var style = Style()
        style.size = Size(width: .length(.pixels(Pixels(10))),
                          height: .length(.pixels(Pixels(10))))
        let node = tree.newNode(style: style, children: [])
        tree.beginLayout()
        tree.setStyle(node, style)   // traps: layout is in progress
    }
}

/// The positive control. Without it the test above passes when `setStyle`
/// traps unconditionally.
@Test func aStyleWrittenOutsideLayoutDoesNotTrap() {
    let tree = LayoutTree(generation: 0)
    let node = tree.newNode(style: Style(), children: [])
    var style = Style()
    style.flexGrow = 1
    tree.setStyle(node, style)
    #expect(tree.style(node).flexGrow == 1)
}

/// `endLayout` must clear the flag, or the first layout poisons the tree for
/// every later caller.
@Test func layoutClearsTheGuardWhenItFinishes() {
    let tree = LayoutTree(generation: 0)
    let node = tree.newNode(style: Style(), children: [])
    computeLayout(tree, root: node,
                  available: AvailableSpaceSize(width: .definite(100),
                                                height: .definite(100)))
    #expect(tree.isLayingOut == false)
}

/// The other half of `layoutClearsTheGuardWhenItFinishes`'s claim: once layout
/// has finished, `setStyle` actually works again rather than merely reporting
/// `isLayingOut == false`.
///
/// Carried in a subprocess rather than in-process. If `endLayout` never ran,
/// `setStyle`'s own guard traps for real on the line below — and a trap
/// in-process would take the rest of the suite down with it (taxonomy shape
/// 11: a crash-on-fail destroys the evidence for every *other* test, which is
/// strictly worse than one clean redden). Here that trap is just a subprocess
/// exit code, so the mutation that breaks it reddens cleanly instead.
@Test func setStyleAfterLayoutFinishesDoesNotTrap() async {
    await #expect(processExitsWith: .success) {
        let tree = LayoutTree(generation: 0)
        let node = tree.newNode(style: Style(), children: [])
        computeLayout(tree, root: node,
                      available: AvailableSpaceSize(width: .definite(100),
                                                    height: .definite(100)))
        tree.setStyle(node, Style())   // must not trap
    }
}

@Test func aCycleInTheChildListTrapsRatherThanHanging() async {
    await #expect(processExitsWith: .failure) {
        let ctx = LayoutContext(rootFontSize: 16)
        let fake = LayoutNodeID(generation: 0, index: 0)
        for _ in 0...LayoutContext.maxDepth { ctx.enter(fake) }
    }
}

/// The depth guard fires on a **real layout**, not only when `enter` is called
/// by hand.
///
/// `aCycleInTheChildListTrapsRatherThanHanging` above drives `LayoutContext`
/// directly, so it stays green with `ctx.enter(node)` deleted from `placeNode`
/// — the guard would exist and never be consulted, which is exactly the shape
/// `resolveEdges` was in for a milestone (taxonomy shape 4). This one goes
/// through `computeLayout` and reddens when that call is removed.
///
/// **Depth, not a cycle, because a cycle is not constructible.**
/// `LayoutTree.newNode` takes children that already exist, so every edge points
/// at an earlier node and the child lists are a DAG by construction. Nesting is
/// therefore the only way a real tree reaches the guard: `maxDepth + 1` nodes,
/// one child each, so the innermost `placeNode` is the level past the limit.
@Test func layingOutATreeDeeperThanTheLimitTraps() async {
    await #expect(processExitsWith: .failure) {
        let tree = LayoutTree(generation: 0)
        var node = tree.newNode(style: Style(), children: [])
        for _ in 0..<LayoutContext.maxDepth {
            node = tree.newNode(style: Style(), children: [node])
        }
        computeLayout(tree, root: node,
                      available: AvailableSpaceSize(width: .definite(100),
                                                    height: .definite(100)))
    }
}

@Test func nestingBelowTheDepthLimitDoesNotTrap() {
    let ctx = LayoutContext(rootFontSize: 16)
    let fake = LayoutNodeID(generation: 0, index: 0)
    for _ in 0..<LayoutContext.maxDepth { ctx.enter(fake) }
    for _ in 0..<LayoutContext.maxDepth { ctx.leave() }
    #expect(ctx.depth == 0)
}
