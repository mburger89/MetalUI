import MetalUICore
import MetalUILayout

/// `List`'s row arrangement: the leading window spacer and the realized rows,
/// as an `ElementGroup` rather than as `Pair(Box(spacerStyle),
/// ArrayGroup(rows))` (ruling `LR-BS`, plan task 7 stage 4, lane 1).
///
/// **Why a group and not an element.** Something has to arrange the realized
/// rows, and under the proposal authority (lane 2) that something is a
/// `ProposalLayout` registered over them. Whatever holds it must introduce **no
/// identity level**: `TombstoneTests.rowID` and `FocusTests.rowID` hand-compute
/// `scrollerID → listID → child(of: listID, name: datum.id) → child(at: 0)`,
/// with a `$state0`/`$focus` slot below, and an element between the `List` and
/// its rows would add a level, silently re-point both chains and reset every
/// row's `@State`, focus, `$anim` and accessibility node once. A group consumes
/// cursor indices and introduces no level, so it is the only shape available.
///
/// **The spacer is a bare NODE here, where it used to be a `Box` element, and
/// that is this lane's one moving legacy number.** An element costs a
/// `StateTable` entry it never reads: `Box.requestLayout` calls
/// `animated(_:_:for:pass:)`, which mints a `$anim` slot on first sight of
/// every registering element, unconditionally. Under the proposal authority
/// there will be no spacer at all — the windowed layout places row *i* at
/// `(firstIndex + i) × rowHeight` directly — so an element here would make the
/// two authorities' `StateTable` id sets differ for **every** `List`, which
/// stage 1's §5.1 item 4 forbids and which `LayoutDifferential`'s
/// `stateSlotsEqual` reports. Keeping a dead element on the proposal path
/// purely to hold a number equal was rejected.
///
/// **Nothing else about the spacer changes.** It carries the identical `Style`
/// and registers through the identical registrar, and an element that declares
/// neither a `Decoration` nor a `Handlers` emits no rect and registers no
/// hitbox, no focus entry and no accessibility record (`Frame.registerHandlers`
/// appends only when `hasSomethingToSay`). What it stops doing is minting that
/// `$anim` entry and recording a `Frame.elementBounds` row of its own. Pinned
/// by `theListsSpacerIsANodeNotAnElement` and
/// `aListsSceneAndHitboxesAreUnchangedByTheGroup` (`ListTests.swift`), and by
/// `theResidentEntrySetStaysBoundedWhileScrolling10kRows`'s `2n + 5`.
///
/// **The rows number from cursor 0, where `Pair` started them at 1**, because
/// the spacer no longer consumes an index. No row id moves: every row carries
/// `.id(String(describing: datum.id))`, so its component is `.named` and a name
/// replaces a position rather than joining it — the `at:` argument is never
/// consulted once a `name:` is supplied. Mutation **M1c** (advancing the cursor
/// past the spacer as `Pair` did) is the measurement of that claim.
///
/// **This lane registers the legacy arrangement only.** `List.requestLayout`'s
/// own site check still fires under the proposal authority, so a diagnostics
/// frame reports `list.noLowering` and builds zero rows, and the spacer still
/// lowers through `lowerLegacyNode` exactly as the `Box` it replaced did. Lane
/// 2 deletes that check and gives this group its `WindowedRowsLayout` branch.
struct ListRows<Row: Element>: ElementGroup {
    /// Each realized row, already wrapped in the `Box` that pins its height and
    /// already carrying its `.id(String(describing: datum.id))`.
    var rows: [Box<Row>]

    /// The leading spacer's style: `size.height` = `window.lowerBound ×
    /// rowHeight` and `flexShrink = 0`. Built by `List.requestLayout`, which
    /// owns the reasoning for both fields.
    var spacerStyle: Style

    /// The spacer's node and each row's own `SingleElementLayout`, threaded to
    /// `prepaintGroup`/`paintGroup` the way every other group threads its
    /// members'. The spacer's node is carried rather than dropped so that a
    /// later phase could read its rect; nothing does today, and that is why it
    /// is a node rather than an element.
    struct GroupLayout {
        var spacer: LayoutNodeID
        var rows: [SingleElementLayout<Box<Row>>]
    }

    typealias GroupPrepaint = [Box<Row>.PrepaintState]

    /// **The spacer is registered first**, so the node order handed to the
    /// enclosing `Box` is `[spacer] + rows` — byte-identical to what
    /// `Pair(spacer, ArrayGroup(rows))` returned, and the order the flex column
    /// reads as "skip this much, then the window".
    ///
    /// Each row goes through **`requestGroupLayout`**, not `requestLayout`:
    /// that entry is where `Element`'s group default lives, and it is what
    /// derives the row's id, binds its `@State` and advances the cursor
    /// (`GlobalElementID.enteringGroupMember`, ruling `MC-H`). Calling
    /// `requestLayout` directly compiles and silently drops all three.
    mutating func requestGroupLayout(under parent: GlobalElementID?,
                                     at cursor: inout Int,
                                     pass: inout LayoutPass) -> ([LayoutNodeID], GroupLayout) {
        // The identical registrar `Box(style: spacerStyle)` reached: the
        // childless legacy node, or its lowering under the proposal authority.
        // Registering it raw here rather than through `Box` is the whole of the
        // demotion — no `animated` call, so no `$anim` slot.
        let spacer = pass.lowersToProposal
            ? pass.lowerLegacyNode(spacerStyle, declared: spacerStyle, children: [], site: .box)
            : pass.frame.requestNode(style: spacerStyle, children: [])

        var nodes: [LayoutNodeID] = [spacer]
        nodes.reserveCapacity(rows.count + 1)
        var layouts: [SingleElementLayout<Box<Row>>] = []
        layouts.reserveCapacity(rows.count)
        for index in rows.indices {
            let (rowNodes, rowLayout) = rows[index].requestGroupLayout(under: parent,
                                                                       at: &cursor, pass: &pass)
            nodes.append(contentsOf: rowNodes)
            layouts.append(rowLayout)
        }
        return (nodes, GroupLayout(spacer: spacer, rows: layouts))
    }

    mutating func prepaintGroup(layout: inout GroupLayout,
                                pass: inout PrepaintPass) -> GroupPrepaint {
        precondition(layout.rows.count == rows.count, Self.countMismatch("prepaint"))
        var prepaints: [Box<Row>.PrepaintState] = []
        prepaints.reserveCapacity(rows.count)
        for index in rows.indices {
            prepaints.append(rows[index].prepaintGroup(layout: &layout.rows[index], pass: &pass))
        }
        return prepaints
    }

    mutating func paintGroup(layout: inout GroupLayout,
                             prepaint: inout GroupPrepaint,
                             pass: inout PaintPass) {
        precondition(layout.rows.count == rows.count && prepaint.count == rows.count,
                     Self.countMismatch("paint"))
        for index in rows.indices {
            rows[index].paintGroup(layout: &layout.rows[index],
                                   prepaint: &prepaint[index], pass: &pass)
        }
    }

    /// `ArrayGroup.countMismatch`'s rule, for the same reason: the arrays come
    /// from this value's own `requestGroupLayout` and are threaded back
    /// unmodified, so a differing count means the window was rebuilt between
    /// phases — `List` stores what `requestLayout` built precisely so this
    /// cannot happen from ordinary use.
    private static func countMismatch(_ phase: StaticString) -> String {
        """
        ListRows \(phase): the phase state has a different row count than the group running \
        this phase — the List's window was rebuilt mid-frame
        """
    }
}
