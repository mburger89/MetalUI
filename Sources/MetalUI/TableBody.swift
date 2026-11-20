import Foundation
import MetalUICore
import MetalUILayout

// A `Table`'s body inside its own scroller, and its pinned header (`TBL-E`, `TBL-I`, `TBL-J`, `TBL-K`, record 389).
//
// `TableBody` is what `Table`'s `ProposalScrollView([.horizontal, .vertical])` scrolls. It reads `data.count` once per build and
// `data[i]` once per realised row, resolves the columns (O(C), no element built), solves their widths, plans the two-axis window
// (`TableWindowPlanner`) and builds only the window's rows, cells and header. The header and the frozen cells are placed from the
// table's own CLAMPED offset, never the scroller's raw one (`TBL-E`): a wheel past either end never moves them for a frame.

private let zeroPoint = Point(x: Pixels(0), y: Pixels(0))

/// How a `Table` reads its data (`TBL-D`): the count once per build, an element by position once per realised row. Positions, not
/// indices, so nothing scans: a table over `CountingRows(1_000_000)` reads `count` once and `data[i]` for the window only.
struct TableSource<Value> {
    var count: @MainActor () -> Int
    var element: @MainActor (Int) -> Value

    @MainActor
    init<Data: RandomAccessCollection>(_ data: Data) where Data.Element == Value {
        count = { data.count }
        if Data.Index.self == Int.self, let start = data.startIndex as? Int {
            // `Collection.index(_:offsetBy:)` on a Strideable index range-checks against `endIndex`; reading by arithmetic keeps
            // a position read to the one subscript.
            element = { data[(start + $0) as! Data.Index] }
        } else {
            element = { data[data.index(data.startIndex, offsetBy: $0)] }
        }
    }
}

/// What the user changed about a table's columns (`TBL-L`): widths and order, keyed by column. Written only by the divider and
/// header drag handlers (PR D); read by every build.
struct TableColumnState: Equatable {
    var widths: [TableColumnKey: Double] = [:]
    var order: [TableColumnKey] = []
}

/// A table body's state at its own id (`TBL-L`), written through `withState(…, unchanged: sameEntry)` and never `write`, so a
/// settled table taints nothing and stays eligible inside an ancestor's retained subtree (`RW-I`).
struct TableViewState {
    var lastPlan: TableWindowPlan?
    /// The row a keyboard move starts from and the row a ⇧-move or ⇧-click extends from (row ids), written from input only.
    var lead: AnyHashable?
    var anchor: AnyHashable?
    /// The row id to position cache (`TBL-N`), made at the first click; compared by identity.
    var positions: TableRowPositionCache?
    /// Cell mode's open edit (`TCM-F`, a `TableEditSession`), compared by identity; `editRevision` moves when an edit begins or
    /// ends, so the write that does it draws a frame. `refocus` asks the next prepaint to give the table its focus back.
    var edit: AnyObject?
    var editRevision = 0
    var refocus = false

    static func sameEntry(_ a: TableViewState, _ b: TableViewState) -> Bool {
        a.lastPlan == b.lastPlan && a.lead == b.lead && a.anchor == b.anchor && a.positions === b.positions
            && a.edit === b.edit && a.editRevision == b.editRevision && a.refocus == b.refocus
    }
}

// MARK: - The body

struct TableBody<Value: Identifiable>: Element, ProposalElement {
    var source: TableSource<Value>
    var resolveColumns: @MainActor () -> [AnyTableColumn<Value>]
    var rowHeight: Double
    var frozenCount: Int
    var headerHeight: Double
    var columnState: TableColumnState
    var selection: ListSelection<Value.ID> = .none
    var rowIndex: (@MainActor (Value.ID) -> Int?)?
    var sort: TableSortControl?
    var menu: SelectionContextMenu?
    /// Cell mode (`TCM-A`): on when the table has an active-cell binding.
    var cellMode = TableCellModeSpec<Value.ID>()
    /// The click a cell-mode table's empty space takes while an edit is open (`TCM-F`).
    var emptyClick: (@MainActor () -> Void)?
    /// The body's own handlers (`TBL-N`): focusable with the table's keys, and the accessibility selection.
    var handlers = Handlers()

    struct Layout {
        var node: LayoutNodeID
        var plan: TableWindowPlan
        var index: ColumnExtentIndex
        var rowCount: Int
        var frozen: Int
        var values: EnvironmentValues
        var rows: [TableRowElement]
        var rowLayouts: [SingleElementLayout<TableRowElement>]
        var header: TableHeaderRow?
        var headerLayout: SingleElementLayout<TableHeaderRow>?
        /// Cell mode (`TCM-F`): the editor's element and layout, and the declared index to display position map.
        var editor: LegacyContent<TextField>?
        var editorLayout: LegacyContent<TextField>.GroupLayout?
        var displayOf: [Int] = []
        var editSession: TableEditSession<Value.ID>?
    }

    struct Prepaint {
        var rows: [Void?]
        var header: [TableHeaderCell.Prepaint?]?
        var editor: LegacyContent<TextField>.GroupPrepaint?
    }

    mutating func requestProposalLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (ProposalNodeID, Layout) {
        let frame = pass.frame
        // 1. `data.count`, once. 2. The columns: O(C), and no element is built.
        let rowCount = source.count()
        let columns = resolveColumns()
        frame.tableWork.columnsResolved += columns.count
        // 3. The display order: the frozen columns (the first declared), then the user's order, then new columns as declared.
        let frozen = Swift.min(Swift.max(0, frozenCount), columns.count)
        var ordered = Array(columns[0..<frozen])
        var rest = Array(columns[frozen...])
        if !columnState.order.isEmpty {
            var byKey: [TableColumnKey: AnyTableColumn<Value>] = [:]
            for column in rest { byKey[column.key] = column }
            var placed = Set<TableColumnKey>()
            for key in columnState.order {
                if let column = byKey[key], placed.insert(key).inserted { ordered.append(column) }
            }
            rest.removeAll { placed.contains($0.key) }
        }
        ordered.append(contentsOf: rest)
        // Cell mode (`TCM-C`): a cell's column is its DECLARED index, so keep both directions of the map (O(C), cell mode only).
        let cellOn = cellMode.isOn
        var declaredAt: [Int] = [], displayOf: [Int] = []
        if cellOn {
            var declaredIndex: [TableColumnKey: Int] = [:]
            for (i, column) in columns.enumerated() { declaredIndex[column.key] = i }
            declaredAt = ordered.map { declaredIndex[$0.key] ?? 0 }
            displayOf = Array(repeating: 0, count: columns.count)
            for (display, declared) in declaredAt.enumerated() { displayOf[declared] = display }
        }
        // 4. The widths against last frame's viewport; 5. their prefix-sum index.
        let context = pass.scrollContext
        let viewportWidth = context?.along(.horizontal)?.viewportExtent ?? 0
        let widths = TableWidthSolver.resolve(ordered.map(\.width), overrides: ordered.map { columnState.widths[$0.key] },
                                              viewport: viewportWidth)
        let index = ColumnExtentIndex(widths: widths)
        // 6. The two-axis window. 7. The rows and cells are a window over the data (`ID-R`).
        let plan = TableWindowPlanner.plan(rowCount: rowCount, rowHeight: rowHeight, headerHeight: headerHeight, columns: index,
                                           frozenCount: frozen, context: context)
        frame.stateTable.noteWindowedParent(id)
        // 8. One environment push for every cell's `Text`: one line, tail truncation (`TBL-K`).
        let values = frame.scopedValues(applying: .transform { $0.lineLimit = 1; $0.truncationMode = .tail })
        let keyed = !(Value.ID.self is DescriptionInjectiveID.Type)
        // `TBL-N`: the selection is read ONCE and each realised row asks one `==`/`contains` of it; nothing scans the data.
        let reader = selection.reader()
        let accent = frame.environmentTop.tint ?? Color(.accent)
        let selectionContext: TableSelectionContext<Value>? = reader == nil && menu == nil && !cellOn ? nil
            : TableSelectionContext(source: source, rowIndex: rowIndex, selection: selection, body: id, table: frame.stateTable)
        // `TCM-D`: the active cell and the table's focus are read once per build, as the selection is.
        var cellContext: TableCellContext<Value>?
        var activeCell: TableCell<Value.ID>?
        var ring = TableCellRing(color: accent, width: 2)
        if cellOn, let selectionContext {
            cellContext = TableCellContext(spec: cellMode, selection: selectionContext, body: id, table: frame.stateTable,
                                           queue: frame.scrollRequestQueue, declaredAt: declaredAt, displayOf: displayOf,
                                           rowHeight: rowHeight, headerHeight: headerHeight)
            activeCell = cellMode.active?.wrappedValue
            // The table is focused while its editor is (`TCM-D`).
            let focus = frame.focusedElement
            if focus != id && focus != GlobalElementID.child(of: id, at: 0, name: tableEditorName) {
                ring = TableCellRing(color: Color.secondary, width: 1)
            }
        }
        let sortLeading = sort?.leading()
        var realisedIDs: [Value.ID] = []
        var rows: [TableRowElement] = []
        var rowLayouts: [SingleElementLayout<TableRowElement>] = []
        var nodes: [ProposalNodeID] = []
        var header: TableHeaderRow?
        var headerLayout: SingleElementLayout<TableHeaderRow>?
        var editor: LegacyContent<TextField>?
        var editorLayout: LegacyContent<TextField>.GroupLayout?
        var editorPlacement: TableEditorPlacement?
        var editSession: TableEditSession<Value.ID>?
        var cursor = 0
        let sort = self.sort
        func headerCell(_ spec: AnyTableColumn<Value>, paintsBackground: Color?) -> TableHeaderCell {
            var cell = TableHeaderCell(title: spec.title, name: spec.elementID, alignment: spec.alignment,
                                       paintsBackground: paintsBackground)
            if let prototype = spec.sortPrototype, let sort {
                cell.sortOrder = sortLeading?(prototype)
                cell.handlers.onClick = { sort.click(prototype) }
            }
            return cell
        }
        frame.withEnvironment(values) {
            // 9. Each realised row reads `data[i]` once.
            for position in plan.rows {
                let value = source.element(position)
                frame.tableWork.dataReads += 1
                var alternate: Color? = position % 2 == 1 ? Color.surfaceSecondary : nil
                let selected = reader?(value.id) ?? false
                // `TCM-D`: a selected row in cell mode is the unemphasised fill, so a cell tint stays readable on it.
                if selected { alternate = cellOn ? Color.secondary.opacity(0.25) : accent }
                // The row's click and menu, made before its cells so a cell's click can run it (`TCM-D`).
                var rowClick: (@MainActor () -> Void)?
                var rowContextual: ContextualAttachment?
                if let selectionContext {
                    if reader != nil { rowClick = selectionContext.rowClick(row: value.id, position: position) }
                    if let menu {
                        rowClick = menu.clickHandler(wrapping: rowClick, row: value.id)
                        let current = selection
                        rowContextual = menu.rowAttachment(row: value.id) { current.currentSet() }
                    }
                }
                @MainActor func decorate(_ cell: AnyTableCell, column: Int) {
                    guard let cellContext else { return }
                    let tableCell = TableCell(row: value.id, column: declaredAt[column])
                    var handlers = Handlers()
                    handlers.onClick = cellContext.click(cell: tableCell, position: position, rowClick: rowClick)
                    handlers.contextual = rowContextual
                    cell.decor = TableCellDecor(fill: cellMode.fill?(tableCell), ring: activeCell == tableCell ? ring : nil,
                                                handlers: handlers)
                }
                var cells: [AnyTableCell] = []
                var xs: [Double] = [], cellWidths: [Double] = []
                cells.reserveCapacity(plan.columns.count + frozen)
                for column in plan.columns {
                    let spec = ordered[column]
                    let cell = spec.makeCell(value, spec.elementID)
                    decorate(cell, column: column)
                    cells.append(cell)
                    xs.append(index.offset(of: column)); cellWidths.append(index.width(at: column))
                }
                for column in plan.frozen {
                    let spec = ordered[column]
                    let cell = spec.makeCell(value, spec.elementID)
                    decorate(cell, column: column)
                    cell.rowBackground = alternate ?? Color.background   // opaque over the scrolled cells (`TBL-K`)
                    cells.append(cell)
                    xs.append(plan.offsetX + index.offset(of: column)); cellWidths.append(index.width(at: column))
                }
                var row = TableRowElement(name: ElementID.forRow(value.id, keyed: keyed), cells: cells, xs: xs, widths: cellWidths,
                                          height: rowHeight, background: alternate)
                if let selectionContext {
                    realisedIDs.append(value.id)
                    if reader != nil {
                        // The selected row's background and hint, as a `List` row's (`DD-AC` item 1): the hint writes no `$ax`.
                        if selected { row.handlers.axNode.selectionHint = true }
                        row.handlers.onClick = rowClick
                        row.handlers.axNode.isSelectableRow = true
                    }
                    if menu != nil {
                        // `OG-N`: the row's menu and its double-click primary action.
                        row.handlers.onClick = rowClick
                        row.handlers.contextual = rowContextual
                    }
                }
                let (rowNodes, rowLayout) = row.requestProposalGroupLayout(under: id, at: &cursor, pass: &pass)
                rows.append(row)
                rowLayouts.append(rowLayout)
                nodes.append(contentsOf: rowNodes)
                frame.tableWork.cellsRealized += cells.count
            }
            // 9b. Cell mode's editor (`TCM-F`): the body's own child, above the cells and under the header, placed by position.
            if let cellContext, let session = cellContext.openSession {
                editSession = session
                let editorID = GlobalElementID.child(of: id, at: 0, name: tableEditorName)
                session.editorFocused = frame.focusedElement == editorID
                // The row: the session's position verified with one read, then `tableRowIndex`, then one scan (`TCM-F`).
                @MainActor func holds(_ position: Int) -> Bool {
                    guard position >= 0, position < rowCount else { return false }
                    frame.tableWork.dataReads += 1
                    return source.element(position).id == session.cell.row
                }
                var found: Int?
                if let hint = session.position, holds(hint) {
                    found = hint
                } else if let looked = rowIndex?(session.cell.row), holds(looked) {
                    found = looked
                } else {
                    for candidate in 0..<rowCount {
                        frame.tableWork.dataReads += 1
                        if source.element(candidate).id == session.cell.row { found = candidate; break }
                    }
                }
                if let found, !ordered.isEmpty {
                    session.position = found
                    let display = displayOf[Swift.min(Swift.max(0, session.cell.column), displayOf.count - 1)]
                    session.lastFrame = (x: (display < frozen ? plan.offsetX : 0) + index.offset(of: display),
                                         y: headerHeight + Double(found) * rowHeight,
                                         width: Swift.max(index.width(at: display), TableEditorPlacement.minimumWidth))
                }
                if let held = session.lastFrame {
                    editorPlacement = TableEditorPlacement(x: held.x, y: held.y, width: held.width)
                    var field = TextField("", text: session.text, axis: .vertical) { [weak cellContext] new in
                        session.text = new
                        cellContext?.revealEditing(session)
                    }
                    .lineLimit(1...6)
                    field.elementID = tableEditorName
                    field = field.addingKeyPress([.down, .repeat], .any) { [weak cellContext] press in
                        cellContext?.editorKey(press, session: session) ?? .ignored
                    }
                    var content = LegacyContent(field)
                    let (editorNodes, built) = content.requestProposalGroupLayout(under: id, at: &cursor, pass: &pass)
                    editor = content
                    editorLayout = built
                    nodes.append(contentsOf: editorNodes)
                }
            }
            // 10. The header, last: it prepaints and paints over the rows.
            if headerHeight > 0, !ordered.isEmpty {
                var cells: [TableHeaderCell] = []
                var xs: [Double] = [], cellWidths: [Double] = []
                for column in plan.columns {
                    let spec = ordered[column]
                    cells.append(headerCell(spec, paintsBackground: nil))
                    xs.append(index.offset(of: column)); cellWidths.append(index.width(at: column))
                }
                for column in plan.frozen {
                    let spec = ordered[column]
                    cells.append(headerCell(spec, paintsBackground: Color.background))
                    xs.append(plan.offsetX + index.offset(of: column)); cellWidths.append(index.width(at: column))
                }
                var row = TableHeaderRow(cells: cells, xs: xs, widths: cellWidths, height: headerHeight)
                let (headerNodes, built) = row.requestProposalGroupLayout(under: id, at: &cursor, pass: &pass)
                header = row
                headerLayout = built
                nodes.append(contentsOf: headerNodes)
            }
        }
        // 11. The body's handlers (`TBL-N`, `TBL-O`): focusable with the table's keys when it selects or has a menu, and the
        // accessibility selection over the realised rows only.
        var bodyHandlers = Handlers()
        if let selectionContext {
            if !selection.isNone {
                bodyHandlers.actions[ObjectIdentifier(AccessibilityRowSelection.self)] =
                    selectionContext.accessibilityRowSelection(realised: realisedIDs, keyed: keyed)
            }
            bodyHandlers.isFocusable = true
            let rowKeys = selectionContext.keyHandler(menu: menu, queue: frame.scrollRequestQueue, rowHeight: rowHeight,
                                                      headerHeight: headerHeight)
            bodyHandlers.onKey = cellContext?.keyHandler(fallback: rowKeys) ?? rowKeys
        }
        if let cellContext {
            // A click in the empty space commits an open edit (`TCM-D`); only an open edit gives the body a click.
            emptyClick = editSession != nil ? cellContext.emptySpaceClick() : nil
            noteCellLifecycle(id, context: cellContext, session: editSession, frame: frame)
        }
        handlers = bodyHandlers
        // 12. The body's layout; 13. the counters.
        let node = pass.requestNativeLayout(
            TableBodyLayout(rowHeight: rowHeight, headerHeight: headerHeight, rowCount: rowCount, totalWidth: index.totalWidth,
                            viewportWidth: viewportWidth, firstRow: plan.rows.lowerBound, realisedRows: rows.count,
                            hasHeader: header != nil, offsetY: plan.offsetY, editor: editorPlacement),
            children: nodes)
        frame.tableWork.rowsRealized += rows.count
        if plan.mode == .cold { frame.tableWork.coldFrames += 1 }
        return (node, Layout(node: node.layoutNodeID, plan: plan, index: index, rowCount: rowCount, frozen: frozen, values: values,
                             rows: rows, rowLayouts: rowLayouts, header: header, headerLayout: headerLayout,
                             editor: editor, editorLayout: editorLayout, displayOf: displayOf, editSession: editSession))
    }

    /// Cell mode's after-frame notes (`TCM-F`, `TCM-H`): the `editing` binding's changes (a caller's `nil` cancels, a cell begins
    /// an edit), focus leaving the editor and the table leaving the hierarchy (each commits). They run after the frame, where
    /// writes are inputs, never in a phase. The last two are noted only while an edit is open.
    private func noteCellLifecycle(_ id: GlobalElementID, context: TableCellContext<Value>,
                                   session: TableEditSession<Value.ID>?, frame: Frame) {
        func note(_ write: LifecycleWrite) {
            let order = frame.reserveLifecycleOrder()
            let node = frame.tree.nodeCount
            frame.noteLifecycle(write, order: order, owner: id, span: (node, node))
        }
        if let editing = cellMode.editing {
            let token = TableEditingToken<Value.ID>(cell: editing.wrappedValue)
            note(.change(value: token, isEqual: { ($0 as? TableEditingToken<Value.ID>) == token },
                         action: { _, new in context.editingChanged(to: (new as? TableEditingToken<Value.ID>)?.cell) },
                         initial: false))
        }
        guard let session else { return }
        let focused = session.editorFocused
        note(.change(value: focused, isEqual: { ($0 as? Bool) == focused },
                     action: { old, new in if (old as? Bool) == true, (new as? Bool) == false { context.focusLeft() } },
                     initial: false))
        note(.disappear { context.disappeared() })
    }

    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout,
                           pass: inout PrepaintPass) -> Prepaint {
        let frame = pass.frame
        return frame.insideListRows {
            // `TBL-L`: the state is written through `withState(unchanged:)`, never `write`, so a settled table taints nothing.
            let plan = layout.plan
            pass.withState(id, initial: TableViewState(), unchanged: TableViewState.sameEntry) { $0.lastPlan = plan }
            // `TBL-I`: the plan this frame's resolved offsets and viewport give; not contained in the built one means one more
            // frame. A settled table asks for nothing.
            let fresh = TableWindowPlanner.fresh(rowCount: layout.rowCount, rowHeight: rowHeight, headerHeight: headerHeight,
                                                 columns: layout.index, frozenCount: layout.frozen,
                                                 scroller: frame.activeScrollerFrame)
            if !TableWindowPlanner.contains(plan, fresh) { frame.requestAnotherFrame() }
            if cellMode.isOn { seatCellModeFocus(id, layout: layout, frame: frame, pass: &pass) }
            // `TBL-N`: the body's own region (focus, keys, the accessibility selection) registers before its rows, so a row's
            // hitbox is above it.
            if handlers.isFocusable { pass.registerHandlers(handlers, at: bounds, id: id) }
            registerEmptySpace(id, bounds: bounds, fresh: fresh, pass: &pass)
            resolveScrollRequests(id, bounds: bounds, layout: layout, frame: frame)
            @MainActor func run() -> Prepaint {
                frame.withEnvironment(layout.values) {
                    var result = Prepaint(rows: [], header: nil)
                    result.rows.reserveCapacity(layout.rows.count)
                    for i in layout.rows.indices {
                        result.rows.append(layout.rows[i].prepaintGroup(layout: &layout.rowLayouts[i], pass: &pass))
                    }
                    if var editor = layout.editor, var editorLayout = layout.editorLayout {
                        result.editor = editor.prepaintGroup(layout: &editorLayout, pass: &pass)
                        layout.editor = editor
                        layout.editorLayout = editorLayout
                    }
                    if var header = layout.header, var headerLayout = layout.headerLayout {
                        result.header = header.prepaintGroup(layout: &headerLayout, pass: &pass)
                        layout.header = header
                        layout.headerLayout = headerLayout
                    }
                    return result
                }
            }
            // `AB-X` rule 1: a cold frame publishes the table and no rows, and asks for a retry.
            if plan.mode == .cold, pass.collectsAccessibility {
                frame.requestAccessibilityRetry()
                return frame.withAccessibilitySuppressed(except: id) { run() }
            }
            return run()
        }
    }

    /// While an edit is open, a click anywhere in the viewport that no row or cell takes commits it (`TCM-F`): the body is only as
    /// tall as its rows, so the empty space below them is a region of its own, registered before the rows so they sit above it.
    private func registerEmptySpace(_ id: GlobalElementID, bounds: Bounds<Pixels>, fresh: TableWindowPlan, pass: inout PrepaintPass) {
        guard let onClick = emptyClick else { return }
        var region = Handlers()
        region.onClick = onClick
        let origin = Point(x: bounds.origin.x + Pixels(Float(fresh.offsetX)), y: bounds.origin.y + Pixels(Float(fresh.offsetY)))
        let area = Bounds(origin: origin, size: Size(width: Pixels(Float(fresh.viewportWidth)), height: Pixels(Float(fresh.viewportHeight))))
        pass.registerHandlers(region, at: area, id: GlobalElementID.child(of: id, at: 0, name: ElementID("$tableEmptySpace")))
    }

    /// Cell mode's focus, from inside the frame (`TCM-F`): a new edit's editor takes it with its caret at the end of its text, and a
    /// table whose edit ended while the editor held it takes it back.
    private func seatCellModeFocus(_ id: GlobalElementID, layout: Layout, frame: Frame, pass: inout PrepaintPass) {
        if pass.readState(id, initial: TableViewState()).refocus {
            frame.seatFocus(on: id)
            pass.withState(id, initial: TableViewState()) { $0.refocus = false }
        }
        guard let session = layout.editSession, session.isOpen, layout.editor != nil else { return }
        let editorID = GlobalElementID.child(of: id, at: 0, name: tableEditorName)
        if session.needsSeed {
            session.needsSeed = false
            let end = session.text.count
            pass.withState(editorID, initial: TextEditState()) { $0.anchor = end; $0.head = end }
        }
        if session.needsFocus {
            session.needsFocus = false
            frame.seatFocus(on: editorID)
        }
    }

    /// A pending `scrollTo` or key reveal for a row, resolved by POSITION (`TBL-O`, spec 5.2): this table's own `TableLeadReveal`
    /// carries its position; a caller's `scrollTo(rowID)` goes through `tableRowIndex`, and without it scans the data (documented).
    /// The target is the row plus the pinned header above it, over the current horizontal band, so the horizontal position never
    /// jumps and the row lands below the header. Before the rows prepaint, so this answer is the first match.
    private func resolveScrollRequests(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: Layout, frame: Frame) {
        let pending = frame.unresolvedScrollRequests(enclosing: id)
        guard !pending.isEmpty else { return }
        let count = layout.rowCount
        for request in pending where !frame.isScrollRequestResolved(request.index) {
            var position: Int?
            // Cell mode (`TCM-J`): the column to reveal as a DISPLAY position, `nil` for the horizontal band as it is.
            var column: Int?
            if let reveal = request.key.base as? TableLeadReveal {
                if reveal.body == id { position = reveal.position }
            } else if let reveal = request.key.base as? TableCellReveal {
                if reveal.body == id { position = reveal.position; column = reveal.column }
            } else if let cell = request.key.base as? TableCell<Value.ID> {
                // A caller's `scrollTo(TableCell)`: the row as for a row id, the column as a declared index.
                if let found = rowIndex?(cell.row) {
                    position = found
                } else {
                    for candidate in 0..<count {
                        frame.tableWork.dataReads += 1
                        if source.element(candidate).id == cell.row { position = candidate; break }
                    }
                }
                if !layout.displayOf.isEmpty { column = layout.displayOf[Swift.min(Swift.max(0, cell.column), layout.displayOf.count - 1)] }
            } else if let row = request.key.base as? Value.ID {
                if let found = rowIndex?(row) {
                    position = found
                } else {
                    for candidate in 0..<count {
                        frame.tableWork.dataReads += 1
                        if source.element(candidate).id == row { position = candidate; break }
                    }
                }
            }
            guard let position, position >= 0, position < count else { continue }
            // The horizontal band: the viewport's as it is, or (cell mode) the column's own, widened by the frozen columns it must
            // clear, so a scrolled cell never ends up under them (`TCM-E`). A frozen column never moves the scroll sideways.
            var left = layout.plan.offsetX, width = layout.plan.viewportWidth
            if let column, column >= layout.frozen, column < layout.index.count {
                let frozenWidth = layout.index.offset(of: layout.frozen)
                left = layout.index.offset(of: column) - frozenWidth
                width = layout.index.width(at: column) + frozenWidth
            }
            let target = Bounds(origin: Point(x: Pixels(Float(Double(bounds.origin.x.value) + left)),
                                              y: Pixels(Float(Double(bounds.origin.y.value) + Double(position) * rowHeight))),
                                size: Size(width: Pixels(Float(width)),
                                           height: Pixels(Float(rowHeight + headerHeight))))
            frame.resolveScrollRequest(request.index, target: target)
        }
    }

    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout, prepaint: inout Prepaint,
                        pass: inout PaintPass) {
        let frame = pass.frame
        frame.withEnvironment(layout.values) {
            for i in layout.rows.indices {
                layout.rows[i].paintGroup(layout: &layout.rowLayouts[i], prepaint: &prepaint.rows[i], pass: &pass)
            }
            if var editor = layout.editor, var editorLayout = layout.editorLayout, var held = prepaint.editor {
                editor.paintGroup(layout: &editorLayout, prepaint: &held, pass: &pass)
                layout.editor = editor
                layout.editorLayout = editorLayout
                prepaint.editor = held
            }
            if var header = layout.header, var headerLayout = layout.headerLayout {
                header.paintGroup(layout: &headerLayout, prepaint: &prepaint.header, pass: &pass)
                layout.header = header
                layout.headerLayout = headerLayout
            }
        }
    }
}

/// The body's layout (`TBL-E`, `TBL-I`): it answers `(max(Σ widths, viewport width), header + count x rowHeight)` at any
/// proposal, places row `i` at `(0, header + i x rowHeight)` and the header at `(0, offset.y)`, the table's clamped offset.
///
/// **Not `Hashable`**, so it taints exactly its ancestors for the layout memo, as `LazyStackLayout` does (`LZ-F`): the realised
/// window is not a key.
struct TableBodyLayout: ProposalLayout {
    var rowHeight: Double
    var headerHeight: Double
    var rowCount: Int
    var totalWidth: Double
    var viewportWidth: Double
    /// The first realised row's position, and how many were realised.
    var firstRow: Int
    var realisedRows: Int
    var hasHeader: Bool
    /// The table's clamped vertical offset: the header's place in the content.
    var offsetY: Double
    /// Cell mode's editor, placed after the rows and before the header (`TCM-F`); `nil` without an open edit.
    var editor: TableEditorPlacement?

    func sizeThatFits(proposal: ProposedSize, subviews: MeasurementSubviews) -> LayoutMeasurement {
        LayoutMeasurement(size: SizeD(width: Swift.max(totalWidth, viewportWidth),
                                      height: headerHeight + rowHeight * Double(rowCount)))
    }

    func placeSubviews(in bounds: LayoutRect, proposal: ProposedSize, subviews: PlacementSubviews) {
        for slot in 0..<Swift.min(realisedRows, subviews.count) {
            subviews[slot].place(at: Point(x: bounds.x, y: bounds.y + headerHeight + Double(firstRow + slot) * rowHeight),
                                 anchor: .topLeading, proposal: ProposedSize(width: bounds.width, height: rowHeight))
        }
        var next = realisedRows
        if let editor, subviews.count > next {
            // The editor is as tall as its lines need (`nil`), so it grows down over the rows under it.
            subviews[next].place(at: Point(x: bounds.x + editor.x, y: bounds.y + editor.y), anchor: .topLeading,
                                 proposal: ProposedSize(width: editor.width, height: nil))
            next += 1
        }
        if hasHeader, subviews.count > next {
            subviews[next].place(at: Point(x: bounds.x, y: bounds.y + offsetY), anchor: .topLeading,
                                         proposal: ProposedSize(width: bounds.width, height: headerHeight))
        }
    }
}

/// Where cell mode's editor sits in content space (`TCM-F`): its cell's x and top, and the larger of the column's width and 120.
struct TableEditorPlacement {
    static let minimumWidth = 120.0
    var x: Double
    var y: Double
    var width: Double
}

/// A table's own frame (`TBL-E`): a table is greedy and self-scrolling, so it answers its proposal on each axis and 0 where it
/// has none (arm `G3`: a table in a vertical `ScrollView` is the proposed width by 0, and never realises every row).
struct TableFrameLayout: ProposalLayout {
    func sizeThatFits(proposal: ProposedSize, subviews: MeasurementSubviews) -> LayoutMeasurement {
        LayoutMeasurement(size: SizeD(width: proposal.width ?? 0, height: proposal.height ?? 0))
    }

    func placeSubviews(in bounds: LayoutRect, proposal: ProposedSize, subviews: PlacementSubviews) {
        for index in subviews.indices {
            subviews[index].place(at: Point(x: bounds.x, y: bounds.y), anchor: .topLeading,
                                  proposal: ProposedSize(width: bounds.width, height: bounds.height))
        }
    }
}

// MARK: - The header

/// The pinned header row (`TBL-E`, `TBL-K`): an opaque band, its cells (scrolling first, frozen after), and a 1-point separator
/// under it. It registers an opaque background hitbox so a click never reaches a row under it.
struct TableHeaderRow: Element, ProposalElement {
    var cells: [TableHeaderCell]
    var xs: [Double]
    var widths: [Double]
    var height: Double

    var elementID: ElementID? { ElementID("$tableHeader") }

    struct Layout {
        var node: LayoutNodeID
        var cells: [SingleElementLayout<TableHeaderCell>]
    }

    mutating func requestProposalLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (ProposalNodeID, Layout) {
        pass.frame.stateTable.noteWindowedParent(id)   // `ID-R`: the cells are a window over the columns
        var cursor = 0
        var nodes: [ProposalNodeID] = []
        var layouts: [SingleElementLayout<TableHeaderCell>] = []
        for i in cells.indices {
            let (cellNodes, cellLayout) = cells[i].requestProposalGroupLayout(under: id, at: &cursor, pass: &pass)
            nodes.append(contentsOf: cellNodes)
            layouts.append(cellLayout)
        }
        let node = pass.requestNativeLayout(TableRowLayout(xs: xs, widths: widths, height: height), children: nodes)
        return (node, Layout(node: node.layoutNodeID, cells: layouts))
    }

    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout,
                           pass: inout PrepaintPass) -> [TableHeaderCell.Prepaint?] {
        pass.insertHitbox(bounds, id: id, opaque: true)
        var states: [TableHeaderCell.Prepaint?] = []
        for i in cells.indices { states.append(cells[i].prepaintGroup(layout: &layout.cells[i], pass: &pass)) }
        return states
    }

    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout, prepaint: inout [TableHeaderCell.Prepaint?],
                        pass: inout PaintPass) {
        pass.fill(bounds, color: pass.resolve(Color.background), cornerRadii: Corners(all: Pixels(0)))
        for i in cells.indices { cells[i].paintGroup(layout: &layout.cells[i], prepaint: &prepaint[i], pass: &pass) }
        let line = Bounds(origin: Point(x: bounds.origin.x, y: bounds.origin.y + bounds.size.height - Pixels(1)),
                          size: Size(width: bounds.size.width, height: Pixels(1)))
        pass.fill(line, color: pass.resolve(Color.separator), cornerRadii: Corners(all: Pixels(0)))
    }
}

/// One header cell: the title, the divider at its trailing edge (`TBL-K`, `TBL-R`) and, on the column the table sorts by, the sort
/// indicator (`TBL-Q`). Three element requests: the cell, the label and the divider, plus the indicator's on the sorted column.
/// A sortable column's header is a click target: the click writes the table's `sortOrder` once.
struct TableHeaderCell: Element, ProposalElement {
    var title: Text
    var name: ElementID
    var alignment: TableColumnAlignment
    /// A frozen header cell paints this under itself, so it is opaque over the scrolled cells it covers.
    var paintsBackground: Color?
    /// The order the table sorts by when this column leads it, else `nil`.
    var sortOrder: SortOrder?
    var handlers = Handlers()
    var label: LegacyContent<Text>?
    var divider = TableColumnDivider()
    var indicator: LegacyContent<ModifiedContent<Image, LayoutModifier>>?

    var elementID: ElementID? { name }

    struct Layout {
        var node: LayoutNodeID
        var label: LegacyContent<Text>.GroupLayout
        var divider: SingleElementLayout<TableColumnDivider>
        var indicator: LegacyContent<ModifiedContent<Image, LayoutModifier>>.GroupLayout?
    }

    struct Prepaint {
        var label: LegacyContent<Text>.GroupPrepaint?
        var divider: Void?
        var indicator: LegacyContent<ModifiedContent<Image, LayoutModifier>>.GroupPrepaint?
    }

    mutating func requestProposalLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (ProposalNodeID, Layout) {
        var cursor = 0
        var content = LegacyContent(title)
        let (labelNodes, labelLayout) = content.requestProposalGroupLayout(under: id, at: &cursor, pass: &pass)
        label = content
        let (dividerNodes, dividerLayout) = divider.requestProposalGroupLayout(under: id, at: &cursor, pass: &pass)
        var nodes = labelNodes + dividerNodes
        var indicatorLayout: LegacyContent<ModifiedContent<Image, LayoutModifier>>.GroupLayout?
        indicator = nil
        if let sortOrder {
            // `chevron.down` is the one chevron every platform has (`SYM-I`): ascending turns it over.
            var chevron = LegacyContent(Image(systemName: "chevron.down").rotationEffect(.degrees(sortOrder == .forward ? 180 : 0)))
            let (indicatorNodes, built) = chevron.requestProposalGroupLayout(under: id, at: &cursor, pass: &pass)
            nodes += indicatorNodes
            indicatorLayout = built
            indicator = chevron
        }
        let node = pass.requestNativeLayout(TableHeaderCellLayout(alignment: alignment, inset: TableMetrics.cellInset,
                                                                   dividerWidth: TableMetrics.dividerHitWidth,
                                                                   hasIndicator: sortOrder != nil),
                                            children: nodes)
        return (node, Layout(node: node.layoutNodeID, label: labelLayout, divider: dividerLayout, indicator: indicatorLayout))
    }

    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout,
                           pass: inout PrepaintPass) -> Prepaint {
        if handlers.onClick != nil { pass.registerHandlers(handlers, at: bounds, id: id) }
        var prepaint = Prepaint(label: nil, divider: nil, indicator: nil)
        if var content = label {
            prepaint.label = content.prepaintGroup(layout: &layout.label, pass: &pass)
            label = content
        }
        prepaint.divider = divider.prepaintGroup(layout: &layout.divider, pass: &pass)
        if var chevron = indicator, var built = layout.indicator {
            prepaint.indicator = chevron.prepaintGroup(layout: &built, pass: &pass)
            indicator = chevron
            layout.indicator = built
        }
        return prepaint
    }

    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout, prepaint: inout Prepaint,
                        pass: inout PaintPass) {
        if let paintsBackground {
            pass.fill(bounds, color: pass.resolve(paintsBackground), cornerRadii: Corners(all: Pixels(0)))
        }
        if var content = label, var held = prepaint.label {
            content.paintGroup(layout: &layout.label, prepaint: &held, pass: &pass)
            label = content
            prepaint.label = held
        }
        divider.paintGroup(layout: &layout.divider, prepaint: &prepaint.divider, pass: &pass)
        if var chevron = indicator, var built = layout.indicator, var held = prepaint.indicator {
            chevron.paintGroup(layout: &built, prepaint: &held, pass: &pass)
            indicator = chevron
            layout.indicator = built
            prepaint.indicator = held
        }
    }
}

/// Places a header cell's label (aligned like the cells below it), its divider (centred on the trailing edge) and, when the column
/// leads the sort, the indicator at the trailing inset with the label giving way to it.
struct TableHeaderCellLayout: ProposalLayout {
    var alignment: TableColumnAlignment
    var inset: Double
    var dividerWidth: Double
    var hasIndicator = false

    func sizeThatFits(proposal: ProposedSize, subviews: MeasurementSubviews) -> LayoutMeasurement {
        LayoutMeasurement(size: SizeD(width: proposal.width ?? 0, height: proposal.height ?? 0))
    }

    func placeSubviews(in bounds: LayoutRect, proposal: ProposedSize, subviews: PlacementSubviews) {
        guard subviews.count == (hasIndicator ? 3 : 2) else { return }
        var reserved = 0.0
        if hasIndicator {
            let size = subviews[2].sizeThatFits(ProposedSize(width: nil, height: bounds.height)).size
            reserved = size.width + 4
            subviews[2].place(at: Point(x: bounds.x + bounds.width - inset - size.width,
                                        y: bounds.y + (bounds.height - size.height) / 2),
                              anchor: .topLeading, proposal: ProposedSize(width: size.width, height: size.height))
        }
        let inner = ProposedSize(width: Swift.max(0, bounds.width - 2 * inset - reserved), height: bounds.height)
        let size = subviews[0].sizeThatFits(inner).size
        let x: Double
        if alignment.isTrailing {
            x = bounds.x + bounds.width - inset - reserved - size.width
        } else if alignment.isCentered {
            x = bounds.x + (bounds.width - reserved - size.width) / 2
        } else {
            x = bounds.x + inset
        }
        subviews[0].place(at: Point(x: x, y: bounds.y + (bounds.height - size.height) / 2), anchor: .topLeading, proposal: inner)
        subviews[1].place(at: Point(x: bounds.x + bounds.width - dividerWidth / 2, y: bounds.y), anchor: .topLeading,
                          proposal: ProposedSize(width: dividerWidth, height: bounds.height))
    }
}

/// The column divider (`TBL-R`): a 6-point hit area centred on the column's trailing edge, drawing a 1-point separator. PR B draws
/// it; PR D gives it the drag and the pointer.
struct TableColumnDivider: Element, ProposalElement {
    struct Layout { var node: LayoutNodeID }
    private struct LeafKey: Hashable {}

    mutating func requestProposalLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (ProposalNodeID, Layout) {
        let node = pass.requestNativeLeaf(key: LeafKey()) { proposal in
            LayoutMeasurement(size: SizeD(width: proposal.width ?? 6, height: proposal.height ?? 0))
        }
        return (node, Layout(node: node.layoutNodeID))
    }

    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout, pass: inout PrepaintPass) {}

    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout, prepaint: inout Void,
                        pass: inout PaintPass) {
        let line = Bounds(origin: Point(x: bounds.origin.x + (bounds.size.width - Pixels(1)) / 2, y: bounds.origin.y),
                          size: Size(width: Pixels(1), height: bounds.size.height))
        pass.fill(line, color: pass.resolve(Color.separator), cornerRadii: Corners(all: Pixels(0)))
    }
}
