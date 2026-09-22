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
    /// `anchor` is `gridCellAnchor`, `columnAlignment` `gridColumnAlignment`
    /// (its horizontal factor is read) and `unsizedAxes` `gridCellUnsizedAxes`
    /// (GR-G, GR-H). **A call writes only what it is given**, and the kernel
    /// keeps the FIRST `anchor` and `columnAlignment` written on a node, so one
    /// modifier is one call: merging several attributes into one call would
    /// reverse "the inner declaration wins".
    ///
    /// Every parameter is pinned by `GridRegistrarTests.swift` (ruling GR-AD),
    /// which is why the three below arrived in the same change as
    /// `GridCellModifier` rather than a lane earlier.
    public func markNativeGridCell(_ node: ProposalNodeID, columns: Int? = nil,
                                   anchor: ProposalAlignment? = nil,
                                   columnAlignment: ProposalAlignment? = nil,
                                   unsizedAxes: ProposalAxes = []) {
        frame.tree.markNativeGridCell(node.layoutNodeID, columns: columns, anchor: anchor,
                                      columnAlignment: columnAlignment, unsizedAxes: unsizedAxes)
    }
}

// MARK: - The element API (lane 4; rulings GR-J, GR-K, GR-T, GR-G, GR-H)

/// SwiftUI's `Grid`: a container that lays its cells out in rows and columns,
/// where a column is as wide as its widest single-column cell and a row as tall
/// as its tallest (ruling GR-C; probe `docs/probes/swiftui-grid.swift`).
///
/// **Proposal content only.** `Content: ProposalElementGroup`, so `Grid { Box() }`
/// is a compile error rather than the run-time `SA-G` trap a mixed tree would be
/// (guard `aGridRejectsLegacyContent`). There is no legacy spelling and none is
/// planned.
///
/// Its content numbers from 0 under its own id, as `HStack`'s does, and a
/// ``GridRow`` inside it takes one of those indices and numbers its cells under
/// itself — so a cell's id is (grid, row, cell) and removing a cell from one row
/// does not renumber another row's (ruling GR-J). **Inside a row, and between
/// rows, the framework's universal trailing-sibling rule still applies**: a
/// vanishing `if` hands the removed cell's `@State`, focus and `onTap` to the
/// next cell, because `OptionalGroup` advances no cursor. No built-in proposal
/// element has `.id()`, so the documented remedy cannot be spelled here yet
/// (divergence `GR-O` 9, ruling GR-AF; pinned wrong on purpose by
/// `removingACellFromARowHandsItsStateToTheNextCell` and
/// `removingAWholeGridRowHandsItsStateToTheNextRow`).
///
/// **Spacing** (ruling GR-D): `nil`, the default, is the largest platform-default
/// pair spacing meeting at each boundary — not one number for the whole grid; a
/// given value is used verbatim on every gap of that axis, negative included.
/// Two rows of ``ProposalText`` take 8 where SwiftUI's font-derived spacing takes
/// 0 (divergence `GR-O` 5, as `CN-H`'s stacks).
///
/// A grid registers and paints nothing of its own: cells register their own
/// hitboxes and paint themselves, a grid publishes nothing to accessibility, and
/// nothing on the proposal path animates (ruling GR-K).
public struct Grid<Content: ProposalElementGroup>: ProposalElement {
    public var content: Content
    public var alignment: ProposalAlignment
    /// `nil` is the platform default per boundary (GR-D).
    public var horizontalSpacing: Pixels?
    /// `nil` is the platform default per boundary (GR-D).
    public var verticalSpacing: Pixels?

    /// SwiftUI's `Grid(alignment:horizontalSpacing:verticalSpacing:content:)`.
    public init(alignment: ProposalAlignment = .center, horizontalSpacing: Pixels? = nil,
                verticalSpacing: Pixels? = nil, @ElementBuilder content: () -> Content) {
        self.content = content()
        self.alignment = alignment
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
    }

    public struct Layout {
        var node: LayoutNodeID
        var content: Content.GroupLayout
    }

    public mutating func requestProposalLayout(_ id: GlobalElementID,
                                               pass: inout LayoutPass) -> (ProposalNodeID, Layout) {
        var cursor = 0
        let (children, contentLayout) = content.requestProposalGroupLayout(under: id, at: &cursor,
                                                                           pass: &pass)
        let node = pass.requestNativeGrid(children: children, alignment: alignment,
                                          horizontalSpacing: horizontalSpacing.map { Double($0.value) },
                                          verticalSpacing: verticalSpacing.map { Double($0.value) })
        return (node, Layout(node: node.layoutNodeID, content: contentLayout))
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout Layout,
                                  pass: inout PrepaintPass) -> Content.GroupPrepaint {
        content.prepaintGroup(layout: &layout.content, pass: &pass)
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout Layout, prepaint: inout Content.GroupPrepaint,
                               pass: inout PaintPass) {
        content.paintGroup(layout: &layout.content, prepaint: &prepaint, pass: &pass)
    }
}

/// What a ``GridRow`` hands to the later phases: its own id and its content's
/// layout. It has no node of its own.
public struct GridRowLayout<ContentLayout> {
    var id: GlobalElementID
    var content: ContentLayout
}

/// SwiftUI's `GridRow`: a run of cells that a ``Grid`` lays out as one row.
///
/// **A group, not an element** (ruling GR-J). It contributes its cells' nodes to
/// whatever contains it — outside a `Grid` those are simply the enclosing
/// container's children, and its row mark is inert there (GG1, GG2) — and marks
/// them as one row on the way out.
///
/// **It consumes one cursor index and numbers its cells from 0 under its own
/// id**, entered through the one shared helper (`MC-H`), as `Component`'s typed
/// default does. That identity level is the whole reason a row is not
/// transparent: without it a vanishing cell in row 0 would shift every later
/// row's `@State`.
///
/// **A row registers AFTER its content**, so a nested `GridRow` marks first and
/// the enclosing one overwrites it, alignment included (ruling GR-T; GG3,
/// GG10–GG12), and a ``GridCellModifier`` written on a row loses to one written
/// on a cell (GG13, GG14).
///
/// `alignment` is a ``VerticalAlignment``: a row aligns its cells on the vertical
/// axis only, so `GridRow(alignment: .leading)` does not compile (guard
/// `aGridRowAlignmentIsAVerticalAlignment`), as `HStack`'s does not.
///
/// **Every proposal modifier on a MULTI-CELL row traps** (divergence `GR-O` 6):
/// `ModifiedContent` and `OnTapModifier` each precondition exactly one native
/// child, where SwiftUI applies the modifier to each cell (GG4, GG7). Only the
/// groups that register nothing — ``GridCellModifier`` and `EnvironmentScope` —
/// pass over several cells. Task 8 owns the gap.
public struct GridRow<Content: ProposalElementGroup>: ProposalElementGroup {
    public var content: Content
    public var alignment: VerticalAlignment?

    public init(alignment: VerticalAlignment? = nil, @ElementBuilder content: () -> Content) {
        self.content = content()
        self.alignment = alignment
    }

    public typealias GroupLayout = GridRowLayout<Content.GroupLayout>

    public mutating func requestProposalGroupLayout(under parent: GlobalElementID?,
                                                    at cursor: inout Int,
                                                    pass: inout LayoutPass)
        -> ([ProposalNodeID], GroupLayout) {
        // One index from the parent, a fresh cursor for the cells, and the
        // row's own id between them (ruling GR-J). The bind is `@State`'s, for
        // the same reason `Component`'s typed default binds: a row is an
        // identity level, and the one shared helper is what keeps the two
        // engines' cursor arithmetic from drifting (`MC-H`).
        let id = GlobalElementID.enteringGroupMember(self, name: nil, under: parent,
                                                     at: &cursor, pass: &pass)
        var inner = 0
        let (nodes, contentLayout) = content.requestProposalGroupLayout(under: id, at: &inner,
                                                                        pass: &pass)
        // AFTER the content, so an inner row's mark is already written and this
        // one overwrites it (ruling GR-T). `cells` may be empty: an empty row is
        // no row at all (GA7).
        pass.markNativeGridRow(nodes, alignment: alignment?.proposalAlignment)
        return (nodes, GridRowLayout(id: id, content: contentLayout))
    }

    /// The untyped entry, for a legacy container: the typed one with its ids
    /// unwrapped. Not a copy — there is nothing here to pin separately (`MC-H`).
    public mutating func requestGroupLayout(under parent: GlobalElementID?,
                                            at cursor: inout Int,
                                            pass: inout LayoutPass) -> ([LayoutNodeID], GroupLayout) {
        let (nodes, layout) = requestProposalGroupLayout(under: parent, at: &cursor, pass: &pass)
        return (nodes.map(\.layoutNodeID), layout)
    }

    /// A row has no node and no bounds, so it records none: each cell records its
    /// own through `Element.prepaintGroup` (ruling GR-K, `LR-AA` item 3).
    public mutating func prepaintGroup(layout: inout GroupLayout,
                                       pass: inout PrepaintPass) -> Content.GroupPrepaint {
        content.prepaintGroup(layout: &layout.content, pass: &pass)
    }

    public mutating func paintGroup(layout: inout GroupLayout,
                                    prepaint: inout Content.GroupPrepaint,
                                    pass: inout PaintPass) {
        content.paintGroup(layout: &layout.content, prepaint: &prepaint, pass: &pass)
    }
}

/// One grid-cell attribute, as the four modifiers below spell it.
public enum GridCellAttribute: Sendable, Hashable {
    /// `gridCellColumns`: counts on one chain ADD above 1 (GX15, GX16); 0 and 1
    /// contribute nothing, and 0 lays out as 1 (divergence `GR-O` 3).
    case columns(Int)
    /// `gridCellAnchor`: overrides the column's, the row's and the grid's
    /// alignment on both axes. Nine-point, not a `UnitPoint` (divergence
    /// `GR-O` 4).
    case anchor(ProposalAlignment)
    /// `gridColumnAlignment`: the first declaration in row order decides its
    /// column's horizontal alignment (GL6, GL7).
    case columnAlignment(HorizontalAlignment)
    /// `gridCellUnsizedAxes`: the named axes are proposed the cell's current slot
    /// rather than a share, so the cell does not widen or heighten its column or
    /// row (ruling GR-H).
    case unsizedAxes(ProposalAxes)
}

/// A grid-cell attribute written over every node its content returns.
///
/// **Layout- and identity-transparent** (ruling GR-J), `EnvironmentScope`'s
/// shape: no layout node, no cursor index, no id — `parent` and `cursor` are
/// forwarded unchanged, so a cell keeps its `@State` when the attribute's VALUE
/// changes between frames.
///
/// It marks **after** its content registers, so a modifier written closer to the
/// cell marks first and wins the anchor and the column alignment (the kernel's
/// mark keeps the FIRST value written), while spans add and unsized axes union
/// (GG13–GG16, GL15, GL16; rulings GR-T, GR-I).
///
/// On a ``GridRow`` it applies to **every** cell, as SwiftUI's does (GG5, GG6):
/// a row returns all its cells' nodes, and this marks all of them.
public struct GridCellModifier<Content: ProposalElementGroup>: ProposalElementGroup {
    public var content: Content
    public var attribute: GridCellAttribute

    init(content: Content, attribute: GridCellAttribute) {
        self.content = content
        self.attribute = attribute
    }

    public typealias GroupLayout = Content.GroupLayout

    public mutating func requestProposalGroupLayout(under parent: GlobalElementID?,
                                                    at cursor: inout Int,
                                                    pass: inout LayoutPass)
        -> ([ProposalNodeID], GroupLayout) {
        let (nodes, layout) = content.requestProposalGroupLayout(under: parent, at: &cursor,
                                                                 pass: &pass)
        for node in nodes { mark(node, pass: &pass) }
        return (nodes, layout)
    }

    public mutating func requestGroupLayout(under parent: GlobalElementID?,
                                            at cursor: inout Int,
                                            pass: inout LayoutPass) -> ([LayoutNodeID], GroupLayout) {
        let (nodes, layout) = requestProposalGroupLayout(under: parent, at: &cursor, pass: &pass)
        return (nodes.map(\.layoutNodeID), layout)
    }

    /// **One call per modifier, writing only the attribute it names.** A merged
    /// call that passed all four would reverse the "the first mark on a node
    /// stands" rule silently, because `markNativeGridCell` keeps the first
    /// `anchor` and `columnAlignment` it is given (lane 3's note to lane 4).
    private func mark(_ node: ProposalNodeID, pass: inout LayoutPass) {
        switch attribute {
        case let .columns(count):
            pass.markNativeGridCell(node, columns: count)
        case let .anchor(anchor):
            pass.markNativeGridCell(node, anchor: anchor)
        case let .columnAlignment(alignment):
            pass.markNativeGridCell(node, columnAlignment: alignment.proposalAlignment)
        case let .unsizedAxes(axes):
            pass.markNativeGridCell(node, unsizedAxes: axes)
        }
    }

    public mutating func prepaintGroup(layout: inout GroupLayout,
                                       pass: inout PrepaintPass) -> Content.GroupPrepaint {
        content.prepaintGroup(layout: &layout, pass: &pass)
    }

    public mutating func paintGroup(layout: inout GroupLayout,
                                    prepaint: inout Content.GroupPrepaint,
                                    pass: inout PaintPass) {
        content.paintGroup(layout: &layout, prepaint: &prepaint, pass: &pass)
    }
}

extension ProposalElementGroup {
    /// SwiftUI's `gridCellColumns(_:)`: how many columns this cell spans.
    ///
    /// Counts on one modifier chain ADD above 1 (GX15: 3 then 2 spans 5), a
    /// count of 0 or 1 contributes nothing, and 0 lays out as 1 (`GR-O` 3). A
    /// negative count traps, and so does a count — or a chain's or a row's sum —
    /// above `Int32.max` (`GR-S`).
    public func gridCellColumns(_ count: Int) -> GridCellModifier<Self> {
        GridCellModifier(content: self, attribute: .columns(count))
    }

    /// SwiftUI's `gridCellAnchor(_:)`: where this cell sits in its slot,
    /// overriding the column's, the row's and the grid's alignment on both axes
    /// (GL10, GL11, GL13) — a non-row child included.
    ///
    /// Nine-point only: SwiftUI takes a `UnitPoint` and GL14 reads a fractional
    /// one, which MetalUI has no spelling for (divergence `GR-O` 4, guard
    /// `aGridCellAnchorIsNinePoint`; task 11 owns the gap).
    public func gridCellAnchor(_ anchor: ProposalAlignment) -> GridCellModifier<Self> {
        GridCellModifier(content: self, attribute: .anchor(anchor))
    }

    /// SwiftUI's `gridColumnAlignment(_:)`: the horizontal alignment of this
    /// cell's column. The FIRST declaration in row-then-cell order wins (GL6,
    /// GL7); a spanning cell declares for its first column without being aligned
    /// by it (GL8); a non-row child declares nothing (GX13).
    public func gridColumnAlignment(_ alignment: HorizontalAlignment) -> GridCellModifier<Self> {
        GridCellModifier(content: self, attribute: .columnAlignment(alignment))
    }

    /// SwiftUI's `gridCellUnsizedAxes(_:)`: the named axes are proposed this
    /// cell's current slot rather than a share of the grid, so a flexible cell
    /// does not widen its column or heighten its row (ruling GR-H; GU9's divider).
    /// Declarations on one chain form a union (GU12, GU13).
    public func gridCellUnsizedAxes(_ axes: ProposalAxes) -> GridCellModifier<Self> {
        GridCellModifier(content: self, attribute: .unsizedAxes(axes))
    }
}
