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

/// The depth guard fires on a **real layout**: `maxDepth + 1` nested nodes,
/// laid out through `computeLayout`, trapping with the guard's own message.
///
/// **Three separate things can only be seen from here.**
///
/// 1. **That `placeNode` consults the guard at all.**
///    `aCycleInTheChildListTrapsRatherThanHanging` above drives `LayoutContext`
///    directly, so it stays green with `ctx.enter(node)` deleted from
///    `placeNode` — the guard would exist and never be reached, taxonomy shape
///    4. Measured: with that call removed this test exits 0 and reddens.
/// 2. **That `maxDepth` is below the stack's own ceiling.** This is the one the
///    hand-entered tests cannot see by construction, and it is why the constant
///    was wrong for a whole milestone. At `maxDepth = 256` this test is RED:
///    the recursion SIGBUSes at 199 levels on a test task's stack, so the
///    process dies before the guard can name anything and stderr is empty. At
///    64 it is green. Re-run it if the constant ever moves.
/// 3. **That the guard's message is what came out**, rather than any other
///    fatal error — which is what the `stderr.contains` is for. `.failure`
///    alone is satisfied by a stack overflow, and that is precisely the failure
///    mode being ruled out.
///
/// A cycle is not the way in: `LayoutTree.newNode` takes children that already
/// exist, so every edge points at an earlier node and the child lists are a DAG
/// by construction. Depth is the only reachable route.
@Test func layingOutATreeDeeperThanTheLimitTraps() async {
    let result = await #expect(processExitsWith: .failure,
                               observing: [\.standardErrorContent]) {
        let tree = LayoutTree(generation: 0)
        var node = tree.newNode(style: Style(), children: [])
        for _ in 0..<LayoutContext.maxDepth {
            node = tree.newNode(style: Style(), children: [node])
        }
        computeLayout(tree, root: node,
                      available: AvailableSpaceSize(width: .definite(100),
                                                    height: .definite(100)))
    }
    let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(stderr.contains("layout recursion exceeded"),
            "aborted, but not at the depth guard this test is about:\n\(stderr)")
}

/// The same for `measureNode`, and it cannot be written the way the test above
/// is: measurement does not recurse into children **yet** — nothing below
/// `measureNode` calls `measureNode` until the four constant-substituting sites
/// are wired — so no tree, however deep, reaches its `ctx.enter` more than once.
/// Entering the context by hand is the only thing that pins this call site at
/// all, and it stops being the only thing the moment Task 4 wires the four
/// sites, at which point this deserves the nested-tree treatment too.
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

/// The positive control for the guard's threshold: `maxDepth` levels are fine
/// and only the one past it traps.
///
/// **In a subprocess, per ruling CS-C.** In-process — how this shipped in Task
/// 1 — mutating the guard to `depth < maxDepth` does not redden it, it *traps
/// inside it*, and a trap in the test process is signal 5 with no summary line
/// and every other test's result destroyed (taxonomy shape 11). The assertion
/// is unchanged; only where it runs is. A wrong `depth` records an issue in the
/// child, which exits non-zero, which reddens this cleanly.
@Test func nestingBelowTheDepthLimitDoesNotTrap() async {
    await #expect(processExitsWith: .success) {
        let ctx = LayoutContext(rootFontSize: 16)
        let fake = LayoutNodeID(generation: 0, index: 0)
        for _ in 0..<LayoutContext.maxDepth { ctx.enter(fake) }
        for _ in 0..<LayoutContext.maxDepth { ctx.leave() }
        #expect(ctx.depth == 0)
    }
}
