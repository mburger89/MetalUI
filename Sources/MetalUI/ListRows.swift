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
/// **Two arrangements, one per authority** (`LR-BQ`, stage 4 lane 2).
///
/// - **legacy** — the leading spacer node plus the rows, flat, exactly what
///   `Pair(Box(spacerStyle), ArrayGroup(rows))` returned. An ordinary flex
///   column then places built row *i* at `window.lowerBound × rowHeight + i ×
///   rowHeight`, which is its absolute offset.
/// - **proposal** — ONE node: a `WindowedRowsLayout` over the rows, which
///   places row *i* at `(firstIndex + i) × rowHeight` directly. **There is no
///   spacer on this path at all** — the layout states the invariant instead of
///   arranging for a CSS flex column to produce it — and no CSS-defeating
///   device is needed: the kernel has neither an automatic minimum for
///   `minSize.height: 0` to remove nor a freeze loop for `flexShrink: 0` to
///   stop. Both lines stay on `rowStyle` anyway, inert rather than removed, so
///   the file keeps ONE row style instead of two that can drift (`LR-BS`).
///
/// The rows' cross-axis stretch, their minima and maxima and every other flex
/// **item** field come from stage 2's `planLegacyItems` / `registerLegacyItems`,
/// called here with the `List`'s own declared style as the parent — so a row is
/// wrapped exactly as it would be if the `List`'s `Box` had lowered it as a
/// direct child, which is what it did before this lane and what the legacy
/// engine still does.
struct ListRows<Row: Element>: ElementGroup {
    /// Each realized row, already wrapped in the `Box` that pins its height and
    /// already carrying its `.id(String(describing: datum.id))`.
    var rows: [Box<Row>]

    /// The leading spacer's style: `size.height` = `window.lowerBound ×
    /// rowHeight` and `flexShrink = 0`. Built by `List.requestLayout`, which
    /// owns the reasoning for both fields. **Legacy path only** — the proposal
    /// path registers no spacer.
    var spacerStyle: Style

    /// The uniform row height, in points, as `WindowedRowsLayout` wants it.
    var rowHeight: Double

    /// `data.count` — the LOGICAL row count, not the window's size. It is what
    /// the layout answers its height from, so the scroller's clamp and its
    /// thumb see the full extent whatever slice is realized.
    var logicalCount: Int

    /// `window.lowerBound`: the logical index of `rows[0]`.
    var firstIndex: Int

    /// The `List`'s **declared** style — the parent `planLegacyItems` plans the
    /// rows against (`LR-AS`: structure from the declared style, values from
    /// the animated one; nothing on a `List`'s own style is animatable today).
    var listStyle: Style

    /// The spacer's node and each row's own `SingleElementLayout`, threaded to
    /// `prepaintGroup`/`paintGroup` the way every other group threads its
    /// members'. The spacer's node is carried rather than dropped so that a
    /// later phase could read its rect; nothing does today, and that is why it
    /// is a node rather than an element. **`nil` under the proposal
    /// authority**, which registers no spacer.
    struct GroupLayout {
        var spacer: LayoutNodeID?
        var rows: [SingleElementLayout<Box<Row>>]
    }

    typealias GroupPrepaint = [Box<Row>.PrepaintState]

    /// **Under the legacy authority the spacer is registered first**, so the
    /// node order handed to the enclosing `Box` is `[spacer] + rows` —
    /// byte-identical to what `Pair(spacer, ArrayGroup(rows))` returned, and the
    /// order the flex column reads as "skip this much, then the window".
    /// **Under the proposal authority there is no spacer**, and the whole group
    /// is one node.
    ///
    /// Each row goes through **`requestGroupLayout`**, not `requestLayout`:
    /// that entry is where `Element`'s group default lives, and it is what
    /// derives the row's id, binds its `@State` and advances the cursor
    /// (`GlobalElementID.enteringGroupMember`, ruling `MC-H`). Calling
    /// `requestLayout` directly compiles and silently drops all three.
    ///
    /// **The cursor sequence is the same on both authorities** — the spacer
    /// consumes no index on either, because it is a node rather than a member.
    /// Row ids therefore do not depend on the authority, which is half of what
    /// `aLoweredListsRowIdentitiesAreTheLegacyOnes` pins (the other half being
    /// that a group introduces no id LEVEL).
    mutating func requestGroupLayout(under parent: GlobalElementID?,
                                     at cursor: inout Int,
                                     pass: inout LayoutPass) -> ([LayoutNodeID], GroupLayout) {
        var rowNodes: [LayoutNodeID] = []
        rowNodes.reserveCapacity(rows.count)
        var layouts: [SingleElementLayout<Box<Row>>] = []
        layouts.reserveCapacity(rows.count)
        func buildRows() {
            for index in rows.indices {
                let (built, rowLayout) = rows[index].requestGroupLayout(under: parent,
                                                                        at: &cursor, pass: &pass)
                rowNodes.append(contentsOf: built)
                layouts.append(rowLayout)
            }
        }

        guard pass.lowersToProposal else {
            // The identical registrar `Box(style: spacerStyle)` reached.
            // Registering it raw here rather than through `Box` is the whole of
            // the demotion — no `animated` call, so no `$anim` slot.
            let spacer = pass.frame.requestNode(style: spacerStyle, children: [])
            buildRows()
            return ([spacer] + rowNodes, GroupLayout(spacer: spacer, rows: layouts))
        }
        buildRows()
        return ([loweredNode(rowNodes, pass: &pass)], GroupLayout(spacer: nil, rows: layouts))
    }

    /// `requestGroupLayout`'s proposal-authority arm (`LR-BQ`, `LR-BR`): the
    /// realized rows' item wrappers, then one `WindowedRowsLayout` over them.
    ///
    /// **Every row's record is consumed here** (`LR-AQ`: a record no lowered
    /// container consumes reports each non-default item field as
    /// `<site>.<field>.unconsumed` once the root's registration returns).
    /// `rowStyle` declares `flexShrink: 0` and `minSize.height: 0`, both
    /// non-default, so a row left unconsumed would report both by name — which
    /// is what makes `theListSiteReportsNothingAndItsRowsItemFieldsAreLowered`'s
    /// empty report a statement about the consumption and not only about the
    /// site.
    ///
    /// **`parentSite: .list` is what keeps `LoweringSite.list` reachable** after
    /// the site check goes (`LR-BV`): `planLegacyItems` raises exactly one entry
    /// at the parent's site, `flexGrow.weights`, and every other entry it
    /// appends is raised at the child's own. No row can raise the weights entry
    /// today — `rowStyle` sets no `flexGrow` and a caller's closure builds the
    /// row's CONTENT, one level below the row `Box` — so the site sits in the
    /// position `component` has held since `LR-BO`.
    ///
    /// **The parent the rows are planned against is the `List`'s own declared
    /// style, with one deliberate correction** (`LR-CD`): `planLegacyItems`
    /// elides a single child's stretch when the parent declares no size on that
    /// axis (`LR-AC`, stage 1's `LR-E` principle 3), because a fit-content
    /// parent stretching its only child is the identity. `WindowedRowsLayout` is
    /// **not** fit-content on the cross axis — it answers the proposal whenever
    /// it is offered one — so the elision's premise fails here and a ONE-row
    /// list would leave its single row unstretched where the legacy engine
    /// stretches it to the list's width. The planning parent therefore declares
    /// a cross size when the `List` itself does not; nothing else in
    /// `planLegacyItems` reads `parent.size.width` for a column parent.
    private func loweredNode(_ rowNodes: [LayoutNodeID],
                             pass: inout LayoutPass) -> LayoutNodeID {
        // **No `droppingPresentations` here** (plan task 7, stage 5, ruling
        // `LR-CK`): this is a lowering collection site, but it cannot receive a
        // presentation placeholder — `rowNodes` are the `List`'s own row `Box`es,
        // built in `List.requestLayout`, never a `Deferred`. A `Deferred` a
        // caller's row closure builds registers one level down, inside the row
        // `Box`, whose own `lowerLegacyNode` drops it.
        let received = rowNodes.map { pass.frame.lowering.consume($0) }
        var planningParent = listStyle
        if planningParent.size.width == .auto {
            planningParent.size.width = .length(.pixels(Pixels(0)))
        }
        var fields: [UnlowerableField] = []
        let plans = pass.planLegacyItems(received, parent: planningParent,
                                         parentKind: .flex(isRow: false),
                                         parentSite: .list, fields: &fields)
        let node: LayoutNodeID
        if fields.isEmpty {
            node = pass.frame.requestNativeLayout(
                WindowedRowsLayout(rowHeight: rowHeight, logicalCount: logicalCount,
                                   firstIndex: firstIndex),
                children: pass.registerLegacyItems(rowNodes, plans))
        } else {
            // `report`'s shape (`LegacyLowering.swift`), which is `private`
            // there: note every entry and stand a 0×0 native leaf in for the
            // arrangement, so a diagnostics frame completes and a production
            // one traps on the first entry.
            for field in fields.dropLast() { pass.frame.noteUnlowerable(field) }
            node = pass.frame.unlowerable(fields[fields.count - 1])
        }
        // Recorded so the enclosing `Box` consumes it and can stretch or grow
        // the whole arrangement, exactly as it would a child element's node.
        // `declared: Style()` for the reason `ScrollView`'s viewport uses it —
        // this node has no modifier surface of its own; the `List`'s modifiers
        // are on the `Box` above it.
        return pass.recordLoweredItem(node, animated: Style(), declared: Style(), site: .list,
                                      contentAlignment: .topLeading, kind: .leaf)
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

/// `List`'s windowed arrangement as a `ProposalLayout` (plan task 7, stage 4,
/// ruling `LR-BR`): it answers the list's **full** content extent on the
/// stacking axis and places realized row *i* at `(firstIndex + i) × rowHeight`.
///
/// **It states the windowing invariant once, where the legacy path arranges for
/// a CSS flex column to produce it** — a leading spacer sized
/// `firstIndex × rowHeight`, `minSize.height: 0` on each row to remove CSS's
/// automatic minimum, `flexShrink: 0` on each row and on the spacer to keep the
/// freeze loop out, and a declared `size.height` on the container so the
/// scrollbar sees the whole list. Only the last of those five survives here,
/// and it survives as this type's own `sizeThatFits`.
///
/// **What it answers, and where that is deliberately NOT SwiftUI's answer**
/// (probe K6, re-run 2026-09-23, `docs/probes/swiftui-stack-algorithms.swift`):
/// SwiftUI's `List` is greedy and content-blind — `K6a` 100×100 at a 100×100
/// proposal, `K6b` 0×0 at nil×nil, `K6c` 100×0, `K6d` 0×100 — because SwiftUI's
/// `List` **is** the viewport and owns its own scrolling.
///
/// - **Height** is `rowHeight × logicalCount`, always, whatever the proposal.
///   MetalUI's `List` is its scroller's CONTENT (one of the four load-bearing
///   requirements in `List`'s own doc is an enclosing `ScrollView`), so a
///   greedy answer would report a 400pt extent for a 14 000pt list and the
///   offset clamp, the thumb and `aWindowedListStillReportsItsFullContentHeight`
///   would all read the viewport instead. The greedy answer belongs to the
///   kernel's scroll viewport, which stage 3 lowered `ScrollView` onto (`CN-M`).
/// - **Width** is the proposal's when there is one — that half **is** K6's —
///   and otherwise the widest realized row's answer at `(nil, rowHeight)`,
///   where K6b/K6d answer 0. A vertical `List` inside a horizontal `ScrollView`
///   is measured at a nil width (`visibleRange` already declines to window that
///   composition), and answering 0 there would render it blank — a second
///   blank-render mode beside divergence 14's. So the nil axis answers the
///   content, as the legacy engine does.
/// - **No baselines**: `LayoutMeasurement.firstBaseline`/`lastBaseline` have no
///   producer and no consumer (CLAUDE.md's declared-but-inert table).
///
/// **What it costs** (`LR-CA`). `LayoutTree.placeCustom` measures every child
/// again after `placeSubviews` returns, to turn a placement record into a rect,
/// so placement alone is **one `measureNative` lookup per realized row on both
/// paths** — `sizeThatFits` measuring nothing is not the same as the layout
/// measuring nothing. On the concrete-width path that is the whole cost and it
/// is `O(window)`. On the nil-width path `sizeThatFits` measures each row at
/// `(nil, rowHeight)` and placement re-measures it at `(bounds.width,
/// rowHeight)`, a different key and so a second miss — **2 lookups per row** —
/// and on that path `visibleRange` declines to window at all, so every LOGICAL
/// row is realized and the path is `O(logicalCount)`. Measured by
/// `aNilWidthListMeasuresEveryLogicalRowTwice`; mitigating it would change
/// `visibleRange`, which `LR-BT` pins shut, and is stage 6b's.
///
/// **It rejects nothing** (`SA-J`). `rowHeight <= 0` is legal, quiet input
/// `List` has always accepted (`visibleRange` declines to window against it,
/// `aZeroRowHeightDoesNotTrapOnceAScrollContextIsPresent`); a negative one gives
/// a negative height, which no checkpoint forbids. `logicalCount` and
/// `firstIndex` come from `data.count` and `visibleRange`, already clamped into
/// `0..<count`. A `precondition` here would reject input SwiftUI accepts, and
/// relaxing a trap into a clamp later is the additive direction anyway.
struct WindowedRowsLayout: ProposalLayout {
    var rowHeight: Double
    /// `data.count`, NOT the window's size.
    var logicalCount: Int
    /// The logical index of subview 0.
    var firstIndex: Int

    func sizeThatFits(proposal: ProposedSize, subviews: MeasurementSubviews) -> LayoutMeasurement {
        let width: Double
        if let proposed = proposal.width {
            width = proposed
        } else {
            var widest = 0.0
            for index in subviews.indices {
                let answer = subviews[index].sizeThatFits(ProposedSize(width: nil, height: rowHeight))
                widest = Swift.max(widest, answer.size.width)
            }
            width = widest
        }
        return LayoutMeasurement(size: SizeD(width: width, height: rowHeight * Double(logicalCount)))
    }

    /// Every subview is placed exactly once, in index order, at its absolute
    /// offset — so `SA-E`'s "an unplaced subview is centred" never fires here
    /// and its "the last record wins" rule is never exercised.
    func placeSubviews(in bounds: LayoutRect, proposal: ProposedSize,
                       subviews: PlacementSubviews) {
        let rowProposal = ProposedSize(width: bounds.width, height: rowHeight)
        for index in subviews.indices {
            subviews[index].place(
                at: Point(x: bounds.x, y: bounds.y + Double(firstIndex + index) * rowHeight),
                anchor: .topLeading, proposal: rowProposal)
        }
    }
}
