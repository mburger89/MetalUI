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
    /// (`LayoutTree.markNativeGridCell`; GR-F). Counts on one node **add above
    /// 1**; a negative count traps, and so does one above `Int32.max` (GR-S).
    ///
    /// **This forwards `columns` only.** The kernel's mark also takes `anchor:`,
    /// `columnAlignment:` and `unsizedAxes:` (lane 3; GR-G, GR-H), which nothing
    /// in this module writes yet: lane 4 adds them here together with
    /// `GridCellModifier`, and `GR-AD` asks for a `GridRegistrarTests` arm per
    /// argument in the same change rather than an exported parameter with no
    /// caller.
    public func markNativeGridCell(_ node: ProposalNodeID, columns: Int? = nil) {
        frame.tree.markNativeGridCell(node.layoutNodeID, columns: columns)
    }
}
