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

/// `placeNode` **consults** the depth guard — the call, not the guard.
///
/// `aCycleInTheChildListTrapsRatherThanHanging` above drives `LayoutContext`
/// directly, so it stays green with `ctx.enter(node)` deleted from `placeNode`:
/// the guard would exist and never be reached, which is the shape `resolveEdges`
/// sat in for a milestone (taxonomy shape 4). This one reddens when that call
/// is removed — measured, both ways.
///
/// **Driven to the limit by hand rather than by a deep tree, because a deep
/// tree cannot get there.** The obvious version of this test lays out
/// `maxDepth + 1` nested nodes; it passes with `ctx.enter` deleted, because 257
/// frames of `placeNode` -> `positionItems` **overflow the stack first**. That
/// was measured, not assumed: on a Swift Testing exit-test task, 150 nested
/// nodes lay out fine and 200 die with SIGBUS, so a real recursion reaches the
/// guard's own message on no path this suite can run. (`computeLayout` on the
/// main thread has an 8 MB stack and would; a task gets far less.) Entering
/// the context by hand and then calling `placeNode` **once** reaches the
/// guard's call site with three stack frames.
///
/// A cycle is not the way in either: `LayoutTree.newNode` takes children that
/// already exist, so every edge points at an earlier node and the child lists
/// are a DAG by construction.
@Test func placeNodeConsultsTheDepthGuard() async {
    let result = await #expect(processExitsWith: .failure,
                               observing: [\.standardErrorContent]) {
        let tree = LayoutTree(generation: 0)
        let node = tree.newNode(style: Style(), children: [])
        let ctx = LayoutContext(rootFontSize: 16)
        for _ in 0..<LayoutContext.maxDepth { ctx.enter(node) }   // exactly at the limit
        placeNode(ctx, tree, node, origin: (0, 0),
                  size: SizeD(width: 10, height: 10), containingBlockWidth: nil)
    }
    let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(stderr.contains("layout recursion exceeded"),
            "aborted, but not at the depth guard this test is about:\n\(stderr)")
}

/// The same for `measureNode`, and it needs its own test rather than trusting
/// the one above: measurement does not recurse into children **yet** — nothing
/// below `measureNode` calls `measureNode` until the four constant-substituting
/// sites are wired — so its `ctx.enter` is the one call in this engine that no
/// nesting can reach, and only a hand-entered context can pin it at all.
@Test func measureNodeConsultsTheDepthGuard() async {
    let result = await #expect(processExitsWith: .failure,
                               observing: [\.standardErrorContent]) {
        let tree = LayoutTree(generation: 0)
        let node = tree.newNode(style: Style(), children: [])
        let ctx = LayoutContext(rootFontSize: 16)
        for _ in 0..<LayoutContext.maxDepth { ctx.enter(node) }   // exactly at the limit
        _ = measureNode(ctx, tree, node, known: .unspecified,
                        available: AvailableSpaceSize(width: .maxContent,
                                                      height: .maxContent),
                        containingBlockWidth: nil)
    }
    let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(stderr.contains("layout recursion exceeded"),
            "aborted, but not at the depth guard this test is about:\n\(stderr)")
}

@Test func nestingBelowTheDepthLimitDoesNotTrap() {
    let ctx = LayoutContext(rootFontSize: 16)
    let fake = LayoutNodeID(generation: 0, index: 0)
    for _ in 0..<LayoutContext.maxDepth { ctx.enter(fake) }
    for _ in 0..<LayoutContext.maxDepth { ctx.leave() }
    #expect(ctx.depth == 0)
}
