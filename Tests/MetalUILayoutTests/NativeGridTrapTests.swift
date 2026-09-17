import Testing
import MetalUICore
import MetalUILayout

// Lane 1 of `docs/superpowers/specs/2026-09-17-grids-design.md`: the grid
// registrars' traps (rulings GR-A, GR-D, GR-F, SA-G, SA-J, CN-L in
// `docs/superpowers/2026-09-17-grids-decisions.md` and the decisions docs they
// cite).
//
// **A plain import on purpose**, as `NativeBoundaryTrapTests.swift`: every
// entry point here is public, so these are the traps an outside module meets.
// **Each test asserts its stderr fragment as well as `.failure`**, so a trap
// somewhere else does not pass. Every body registers only and lays nothing out,
// so a mutant that drops a check exits `.success` rather than dying later.

private func stderrText(_ result: ExitTest.Result?) -> String {
    String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
}

private func leaf(_ tree: LayoutTree) -> LayoutNodeID {
    tree.newNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 10, height: 10)) }
}

/// GT1: SwiftUI traps on `gridCellColumns(-1)` (exit 133); the kernel traps
/// with the parameter named (GR-F, SA-J).
///
/// Mutation: drop the precondition (the child exits `.success`).
@Test func aNegativeGridCellColumnsTraps() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        let tree = LayoutTree(generation: 0)
        tree.markNativeGridCell(leaf(tree), columns: -1)
    }
    #expect(stderrText(result).contains("columns must not be negative"),
            "aborted, but not at the negative-columns check:\n\(stderrText(result))")
}

/// SA-G: a legacy child traps at the grid's own check, which names the child,
/// before any other read of it — and so does a row or cell **mark** on a legacy
/// node, at the mark, naming it (second critic round, finding 12; ruling
/// GR-AD). Before the mark checks, arms b and c were accepted silently: the
/// mark was written, and the lie surfaced either inside `newNativeGrid` with a
/// different message or never, if the node reached no grid.
///
/// Mutations: (a) drop the grid's explicit child check (a later read still
/// traps, with the generic "contains a legacy node", and the fragment fails);
/// (b) drop `markNativeGridRow`'s native check (the child exits `.success`);
/// (c) drop `markNativeGridCell`'s (the child exits `.success`).
@Test func aLegacyNodeUnderAGridOrCarryingAGridMarkTraps() async {
    // Arm a: the grid's own child check.
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        let tree = LayoutTree(generation: 0)
        let legacy = tree.newNode(style: Style(), children: [])
        _ = tree.newNativeGrid(children: [leaf(tree), legacy])
    }
    #expect(stderrText(result).contains("grid child 1 is a legacy node (SA-G)"),
            "aborted, but not at the grid's legacy-child check:\n\(stderrText(result))")

    // Arm b: a row mark on a legacy node, which reaches no grid at all.
    let rowResult = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        let tree = LayoutTree(generation: 0)
        tree.markNativeGridRow([tree.newNode(style: Style(), children: [])])
    }
    #expect(stderrText(rowResult).contains("a grid row mark written on a legacy node (SA-G)"),
            "aborted, but not at the row mark's legacy check:\n\(stderrText(rowResult))")

    // Arm c: a cell mark on a legacy node, which reaches no grid at all.
    let cellResult = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        let tree = LayoutTree(generation: 0)
        tree.markNativeGridCell(tree.newNode(style: Style(), children: []), columns: 2)
    }
    #expect(stderrText(cellResult).contains("a grid cell mark written on a legacy node (SA-G)"),
            "aborted, but not at the cell mark's legacy check:\n\(stderrText(cellResult))")
}

/// GS10: SwiftUI answers nan for a nan spacing; the kernel traps at
/// registration with the parameter named (GR-D, SA-J).
///
/// Mutation: drop the finiteness precondition (the child exits `.success`).
@Test func aNaNGridSpacingTraps() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        let tree = LayoutTree(generation: 0)
        _ = tree.newNativeGrid(children: [leaf(tree), leaf(tree)], horizontalSpacing: .nan)
    }
    #expect(stderrText(result).contains("horizontalSpacing must be finite"),
            "aborted, but not at the spacing check:\n\(stderrText(result))")
}

/// GS9: SwiftUI answers inf for an infinite spacing; the kernel traps, naming
/// `verticalSpacing`.
///
/// Mutation: drop the finiteness precondition (the child exits `.success`).
@Test func anInfiniteGridSpacingTraps() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        let tree = LayoutTree(generation: 0)
        _ = tree.newNativeGrid(children: [leaf(tree), leaf(tree)], verticalSpacing: .infinity)
    }
    #expect(stderrText(result).contains("verticalSpacing must be finite"),
            "aborted, but not at the spacing check:\n\(stderrText(result))")
}

/// GR-A: a row mark is written before the grid registers, so a mark on a node
/// that already has a native parent could never be read by that parent.
///
/// Mutation: drop the parent precondition in `markNativeGridRow`.
@Test func aGridRowMarkOnANodeThatAlreadyHasAParentTraps() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        let tree = LayoutTree(generation: 0)
        let cell = leaf(tree)
        _ = tree.newNativeFrame(child: cell, width: 20, height: 20)
        tree.markNativeGridRow([cell])
    }
    #expect(stderrText(result).contains("grid row mark"),
            "aborted, but not at the row mark's parent check:\n\(stderrText(result))")
}

/// GR-A: the same for a cell mark.
///
/// Mutation: drop the parent precondition in `markNativeGridCell`.
@Test func aGridCellMarkOnANodeThatAlreadyHasAParentTraps() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        let tree = LayoutTree(generation: 0)
        let cell = leaf(tree)
        _ = tree.newNativeFrame(child: cell, width: 20, height: 20)
        tree.markNativeGridCell(cell, columns: 2)
    }
    #expect(stderrText(result).contains("grid cell mark"),
            "aborted, but not at the cell mark's parent check:\n\(stderrText(result))")
}

/// CN-L at the grid registrar: a node already under a frame traps when a grid
/// lists it.
///
/// Mutation: skip `recordParent` in `newNativeGrid` (the child exits
/// `.success`).
@Test func aNodeUnderAGridAndASecondParentTraps() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        let tree = LayoutTree(generation: 0)
        let cell = leaf(tree)
        _ = tree.newNativeFrame(child: cell, width: 20, height: 20)
        _ = tree.newNativeGrid(children: [cell])
    }
    #expect(stderrText(result).contains("MC-G hole 4"),
            "aborted, but not at the parent record:\n\(stderrText(result))")
}
