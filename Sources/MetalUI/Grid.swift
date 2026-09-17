import MetalUICore
import MetalUILayout

// Grids (plan task 7, stage G): `docs/superpowers/specs/2026-09-17-grids-design.md`,
// rulings GR-A… in `docs/superpowers/2026-09-17-grids-decisions.md`.
//
// Lane 1 holds only the typed `LayoutPass` registrars. They live here, not in
// `Passes.swift`, so the grid track edits no shared file (ruling GR-A); they
// call `frame.tree` directly, which is internal to this module. Lane 4 adds
// `Grid`, `GridRow` and the cell modifiers.

extension LayoutPass {
    /// Registers a grid over native children (`LayoutTree.newNativeGrid`; spec
    /// §4). A nil spacing is the platform default per boundary (GR-D); a given
    /// spacing must be finite (SA-J).
    public func requestNativeGrid(children: [ProposalNodeID], alignment: ProposalAlignment = .center,
                                  horizontalSpacing: Double? = nil,
                                  verticalSpacing: Double? = nil) -> ProposalNodeID {
        ProposalNodeID(frame.tree.newNativeGrid(children: children.map(\.layoutNodeID), alignment: alignment,
                                                horizontalSpacing: horizontalSpacing,
                                                verticalSpacing: verticalSpacing))
    }

    /// Marks `cells` as one grid row, overwriting an earlier row mark and its
    /// alignment (`LayoutTree.markNativeGridRow`; GR-A, GR-T). Reads
    /// `alignment`'s vertical factor only. Traps on a node that already has a
    /// parent.
    public func markNativeGridRow(_ cells: [ProposalNodeID], alignment: ProposalAlignment? = nil) {
        frame.tree.markNativeGridRow(cells.map(\.layoutNodeID), alignment: alignment)
    }

    /// Marks `node` as a grid cell spanning `columns` columns
    /// (`LayoutTree.markNativeGridCell`; GR-F). A negative count traps.
    public func markNativeGridCell(_ node: ProposalNodeID, columns: Int? = nil) {
        frame.tree.markNativeGridCell(node.layoutNodeID, columns: columns)
    }
}
