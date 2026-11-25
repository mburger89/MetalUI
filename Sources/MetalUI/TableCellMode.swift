import MetalUICore
import MetalUILayout
import MetalUIPlatform

// `Table` cell mode (`TCM-A`..`TCM-K`, record 394): an active cell, cell keys, an inline editor and a per-cell fill. MetalUI-only
// (class M): SwiftUI's `Table` has no cell cursor, so a table without `tableActiveCell` is PRs B to E exactly. The modifiers, the
// build-time spec and the input-time context live here; `TableBody` builds the cells, the ring and the editor from them.

/// A cell of a table: a row id and a column's declared index (MetalUI-only, `TCM-B`, `TCM-C`).
///
/// `column` is the column's position in the flattened declaration, counting static columns and `TableColumnForEach` elements alike.
/// It is not the display position, so it is stable when the user reorders columns. For a `TableColumnForEach(0..<n)` table it equals
/// the element's id. A caller that inserts or removes columns remaps its stored cells itself; an index past the last column is
/// clamped.
public struct TableCell<RowID: Hashable>: Hashable {
    /// The row's id.
    public var row: RowID
    /// The column's declared index.
    public var column: Int

    /// The cell at `column` of the row `row`.
    public init(row: RowID, column: Int) {
        self.row = row
        self.column = column
    }
}

// MARK: - The modifiers

/// What a table's cell-mode modifiers recorded (`TCM-B`): cell mode is on exactly when `active` is set.
struct TableCellModeSpec<ID: Hashable> {
    var active: Binding<TableCell<ID>?>?
    var editing: Binding<TableCell<ID>?>?
    var text: (@MainActor (TableCell<ID>) -> String)?
    var isEditable: @MainActor (TableCell<ID>) -> Bool = { _ in true }
    var onCommit: (@MainActor (TableCell<ID>, String) -> Void)?
    var fill: (@MainActor (TableCell<ID>) -> Color?)?

    var isOn: Bool { active != nil }
    var canEdit: Bool { editing != nil && text != nil && onCommit != nil }
}

extension Table {
    /// Turns on cell mode and binds its active cell (MetalUI-only, `TCM-B`; SwiftUI's `Table` has no cell cursor).
    ///
    /// A click on a cell makes it the active cell, focuses the table and selects the cell's row as a row click does, so a row
    /// selection binding still works. The arrow keys, Tab, Home, End and the page keys move the active cell (`TCM-E`); the table
    /// reveals it on both axes. The binding is written once per move and not at all for a move to the same cell. A focused table
    /// draws a 2-point accent ring inside the active cell, an unfocused one a 1-point secondary ring. The active cell is never
    /// pruned when the data changes: a cell whose row no longer resolves draws no ring, and the next key move starts from the
    /// first row. A table without this modifier is exactly the row table, and `tableCellEditing(_:text:isEditable:onCommit:)`
    /// and `tableCellBackground(_:)` have no effect on it.
    public func tableActiveCell(_ cell: Binding<TableCell<Value.ID>?>) -> Self {
        var copy = self
        copy.cellMode.active = cell
        return copy
    }

    /// Makes the cells of a cell-mode table editable (MetalUI-only, `TCM-F`, `TCM-H`).
    ///
    /// Return, F2 or a printable key on the active cell opens an editor over it; a printable key replaces the text with that
    /// character. `text` supplies the editor's initial text, the raw value and never the displayed content. `isEditable` defaults
    /// to every cell. `editing` is the cell being edited: MetalUI writes it when an edit begins and `nil` when it ends; setting it
    /// to `nil` from outside cancels the edit (no `onCommit`, the typed text is discarded) and setting it to a cell begins one
    /// there, reveals the cell and makes it the active cell. `onCommit` receives the edited text, exactly once per edit, even when
    /// the text is unchanged; the caller writes it. An edit commits on Return, Tab, a click elsewhere, focus leaving the editor,
    /// the table leaving the hierarchy or its window closing, and cancels on Escape or a caller's `nil`. It stays open while its
    /// cell scrolls out of the window, and while its row cannot be found (the caller cancels it).
    public func tableCellEditing(
        _ editing: Binding<TableCell<Value.ID>?>,
        text: @escaping @MainActor (TableCell<Value.ID>) -> String,
        isEditable: @escaping @MainActor (TableCell<Value.ID>) -> Bool = { _ in true },
        onCommit: @escaping @MainActor (TableCell<Value.ID>, String) -> Void) -> Self {
        var copy = self
        copy.cellMode.editing = editing
        copy.cellMode.text = text
        copy.cellMode.isEditable = isEditable
        copy.cellMode.onCommit = onCommit
        return copy
    }

    /// A fill for the whole cell box of a cell-mode table, not the content inset; `nil` means no fill (MetalUI-only, `TCM-I`).
    ///
    /// `fill` runs while a realised cell's box is built, in the same invalidation as the cell's content, never in paint and never
    /// for an idle table. It paints above the row's stripe or selection and under the cell's content and the active ring.
    public func tableCellBackground(_ fill: @escaping @MainActor (TableCell<Value.ID>) -> Color?) -> Self {
        var copy = self
        copy.cellMode.fill = fill
        return copy
    }
}

// MARK: - What a cell paints

/// The ring an active cell draws inside its box (`TCM-D`).
struct TableCellRing {
    var color: Color
    var width: Double
}

/// What cell mode adds to one realised cell: a fill under the content, a ring over it and the cell's own click. `nil` for every
/// cell of a row table, so a row table's cells paint and register exactly as before.
struct TableCellDecor {
    var fill: Color?
    var ring: TableCellRing?
    var handlers: Handlers?
}

// MARK: - Keys the body hands to the context

/// The key a cell move or a cell-mode `scrollTo` enqueues (`TCM-E`, `TCM-J`): this table's own, matched only by the body it names.
/// `column` is the DISPLAY position, so the reveal needs no column lookup.
struct TableCellReveal: Hashable {
    let body: GlobalElementID
    let position: Int
    let column: Int
}

// MARK: - The edit

/// One edit (`TCM-F`, `TCM-G`): a class, so typing mutates it without a state write. The body holds it in `TableViewState.edit`.
/// It ends exactly once: `isOpen` flips before any callback, and every path (key, click, focus, disappearance, the caller) checks it.
@MainActor
final class TableEditSession<ID: Hashable> {
    let cell: TableCell<ID>
    var text: String
    var isOpen = true
    /// The cell's row position, as last resolved: verified with one read per build.
    var position: Int?
    /// The editor's last placement in content space (x, y, width), held while the row cannot be found (`TCM-F`).
    var lastFrame: (x: Double, y: Double, width: Double)?
    /// The editor takes focus, and its caret goes to the end of the text, the frame it first appears.
    var needsFocus = true
    var needsSeed = true
    /// Whether the editor held focus as of the last build.
    var editorFocused = false
    /// What the fields were when an attempt began (`AttemptRestorable`, below).
    struct SavedFields {
        var text: String, isOpen: Bool, position: Int?, lastFrame: (x: Double, y: Double, width: Double)?
        var needsFocus: Bool, needsSeed: Bool, editorFocused: Bool
    }
    var attemptSaved: SavedFields?

    init(cell: TableCell<ID>, text: String, position: Int?) {
        self.cell = cell
        self.text = text
        self.position = position
    }
}

/// A build writes the session's placement and its one-shot flags (`position`, `lastFrame`, `editorFocused`, `needsSeed`, `needsFocus`): a redo's second attempt
/// would find the focus request already consumed. The body registers the session before its first write of an attempt, and a rollback puts the fields back
/// (`RK-AJ`; found by verify mode's census, record 422).
extension TableEditSession: @MainActor AttemptRestorable {
    func beginAttempt() { attemptSaved = SavedFields(text: text, isOpen: isOpen, position: position, lastFrame: lastFrame, needsFocus: needsFocus,
                                                    needsSeed: needsSeed, editorFocused: editorFocused) }

    func rollbackAttempt() {
        guard let saved = attemptSaved else { return }
        text = saved.text; isOpen = saved.isOpen; position = saved.position; lastFrame = saved.lastFrame
        needsFocus = saved.needsFocus; needsSeed = saved.needsSeed; editorFocused = saved.editorFocused
        attemptSaved = nil
    }

    func endAttempt() { attemptSaved = nil }

    var attemptContents: String { "\(text)|\(isOpen)|\(String(describing: position))|\(String(describing: lastFrame))|\(needsFocus)|\(needsSeed)|\(editorFocused)" }
}

/// The value the `editing` binding contributes to the after-frame comparison (`TCM-H`).
struct TableEditingToken<ID: Hashable>: Hashable {
    var cell: TableCell<ID>?
}

/// F2, the function key that begins an edit (`TCM-E`): NSF2FunctionKey.
let tableCellF2 = "\u{f705}"

/// The editor's name under its table body: its identity is the body's, so cell recycling never reaches it (`TCM-F`).
let tableEditorName = ElementID("$tableEditor")

// MARK: - The context

/// What cell mode needs of one table build at input time (`TCM-D`, `TCM-E`): one per build, shared by every realised cell's closures
/// and by the body's keys. It reads the bindings when it runs, never at build.
@MainActor
final class TableCellContext<Value: Identifiable> {
    typealias Cell = TableCell<Value.ID>
    typealias Session = TableEditSession<Value.ID>

    let spec: TableCellModeSpec<Value.ID>
    let selection: TableSelectionContext<Value>
    let body: GlobalElementID
    weak var table: StateTable?
    let queue: ScrollRequestQueue
    /// Display position to declared column index, and back.
    let declaredAt: [Int]
    let displayOf: [Int]
    let rowHeight: Double
    let headerHeight: Double

    init(spec: TableCellModeSpec<Value.ID>, selection: TableSelectionContext<Value>, body: GlobalElementID, table: StateTable,
         queue: ScrollRequestQueue, declaredAt: [Int], displayOf: [Int], rowHeight: Double, headerHeight: Double) {
        self.spec = spec
        self.selection = selection
        self.body = body
        self.table = table
        self.queue = queue
        self.declaredAt = declaredAt
        self.displayOf = displayOf
        self.rowHeight = rowHeight
        self.headerHeight = headerHeight
    }

    var source: TableSource<Value> { selection.source }
    var columnCount: Int { declaredAt.count }

    /// The open edit, if any.
    var openSession: Session? {
        guard let session = table?.peek(body, as: TableViewState.self)?.edit as? Session, session.isOpen else { return nil }
        return session
    }

    // MARK: Where a cell is

    private func clampedDeclared(_ column: Int) -> Int { Swift.min(Swift.max(0, column), Swift.max(0, columnCount - 1)) }

    /// The active cell's row position (the position cache verified with one read, then `tableRowIndex`, then one scan) and its
    /// DISPLAY column; `nil` when there is none or its row no longer resolves.
    private func active() -> (cell: Cell, position: Int, display: Int)? {
        guard columnCount > 0, let cell = spec.active?.wrappedValue, let position = selection.space().index(cell.row) else { return nil }
        return (cell, position, displayOf[clampedDeclared(cell.column)])
    }

    private func cell(at position: Int, display: Int) -> Cell {
        Cell(row: source.element(position).id, column: declaredAt[display])
    }

    // MARK: Moving

    /// Makes `cell` (at `position`) the active cell: one binding write when it changed, then the reveal on both axes.
    func activate(_ cell: Cell, position: Int, reveals: Bool = true) {
        selection.positions().note(AnyHashable(cell.row), position)
        if spec.active?.wrappedValue != cell { spec.active?.wrappedValue = cell }
        if reveals { reveal(position: position, declared: cell.column) }
    }

    func reveal(position: Int, declared: Int) {
        guard let scope = body.parent, columnCount > 0 else { return }
        queue.enqueue(ScrollRequest(scope: scope, key: AnyHashable(TableCellReveal(body: body, position: position,
                                                                                    column: displayOf[clampedDeclared(declared)])),
                                    anchor: nil))
    }

    /// A move to `(position, display)`; the row count and the column count bound it.
    private func move(toPosition position: Int, display: Int) {
        let count = source.count()
        guard count > 0, columnCount > 0 else { return }
        let p = Swift.min(Swift.max(0, position), count - 1), d = Swift.min(Swift.max(0, display), columnCount - 1)
        activate(cell(at: p, display: d), position: p)
    }

    /// With no resolvable active cell every move starts at the first row (`TCM-D`, TBL-N's empty-lead rule).
    private func startFromTheTop() {
        let count = source.count()
        guard count > 0, columnCount > 0 else { return }
        let display = spec.active?.wrappedValue.map { displayOf[clampedDeclared($0.column)] } ?? 0
        move(toPosition: 0, display: display)
    }

    private func stepColumn(_ delta: Int) {
        guard let now = active() else { return startFromTheTop() }
        let next = now.display + delta
        guard next >= 0, next < columnCount else { return }   // consumed at the edge, no wrap
        move(toPosition: now.position, display: next)
    }

    /// Tab: one column, wrapping to the next or previous row; consumed at the very ends.
    private func tab(backward: Bool) {
        guard let now = active() else { return startFromTheTop() }
        let count = source.count()
        if !backward {
            if now.display + 1 < columnCount { move(toPosition: now.position, display: now.display + 1) }
            else if now.position + 1 < count { move(toPosition: now.position + 1, display: 0) }
        } else {
            if now.display > 0 { move(toPosition: now.position, display: now.display - 1) }
            else if now.position > 0 { move(toPosition: now.position - 1, display: columnCount - 1) }
        }
    }

    /// ↑ and ↓: with a row selection the move is the table's own (so ⇧ extends it, `TBL-O`) and the active cell follows the lead;
    /// without one it is the active cell's row plus or minus one.
    private func stepRow(_ direction: ControlKeys.Direction, extends: Bool) {
        let now = active()
        if !selection.selection.isNone {
            // The lead starts from the active row, so a cell set from outside is where the move begins.
            if let now {
                let store = selection.leadStore()
                let stored = store.read()
                if stored?.lead != AnyHashable(now.cell.row) {
                    store.write(AnyHashable(now.cell.row), stored?.anchor ?? AnyHashable(now.cell.row))
                }
            }
            guard let moved = selection.controller().move(direction, extends: extends) else { return }
            let display = now?.display ?? (spec.active?.wrappedValue.map { displayOf[clampedDeclared($0.column)] } ?? 0)
            activate(cell(at: moved.index, display: display), position: moved.index)
            return
        }
        guard let now else { return startFromTheTop() }
        move(toPosition: now.position + (direction == .forward ? 1 : -1), display: now.display)
    }

    private func jumpRow(last: Bool) {
        let count = source.count()
        guard count > 0 else { return }
        guard let now = active() else { return startFromTheTop() }
        move(toPosition: last ? count - 1 : 0, display: now.display)
    }

    private func jumpColumn(last: Bool) {
        guard let now = active() else { return startFromTheTop() }
        move(toPosition: now.position, display: last ? columnCount - 1 : 0)
    }

    private func page(down: Bool) {
        guard let now = active() else { return startFromTheTop() }
        let rows: Int
        if let plan = table?.peek(body, as: TableViewState.self)?.lastPlan, rowHeight > 0 {
            rows = Swift.max(1, Int((plan.viewportHeight - headerHeight) / rowHeight))
        } else {
            rows = 1
        }
        move(toPosition: now.position + (down ? rows : -rows), display: now.display)
    }

    // MARK: Keys

    /// The body's key handler in cell mode (`TCM-E`): cell keys first, then PR C's row keys. While an edit is open the editor owns
    /// the keyboard, and a key it declines is declined here too.
    func keyHandler(fallback: @escaping @MainActor (KeyEvent) -> Bool) -> @MainActor (KeyEvent) -> Bool {
        { @MainActor [self] event in
            if openSession != nil { return false }
            if handle(event) { return true }
            return fallback(event)
        }
    }

    private func handle(_ event: KeyEvent) -> Bool {
        guard columnCount > 0 else { return false }
        let mods = event.modifiers
        let primary = Modifiers.primary
        switch event.charactersIgnoringModifiers {
        case TextEditing.leftArrow, TextEditing.rightArrow:
            let forward = event.charactersIgnoringModifiers == TextEditing.rightArrow
            if mods.isEmpty { stepColumn(forward ? 1 : -1) } else if mods == primary { jumpColumn(last: forward) } else { return false }
            return true
        case TextEditing.upArrow, TextEditing.downArrow:
            let forward = event.charactersIgnoringModifiers == TextEditing.downArrow
            if mods.isEmpty || mods == .shift {
                stepRow(forward ? .forward : .backward, extends: mods == .shift)
            } else if mods == primary {
                jumpRow(last: forward)
            } else {
                return false
            }
            return true
        case "\t", "\u{19}":
            guard mods.isEmpty || mods == .shift else { return false }
            tab(backward: mods == .shift || event.charactersIgnoringModifiers == "\u{19}")
            return true
        case ControlKeys.returnKey:
            if mods.isEmpty {
                guard let now = active(), beginEditing(at: now.cell, position: now.position, replacing: nil) else { return false }
                return true
            }
            if mods == .shift { stepRow(.backward, extends: false); return true }
            return false
        case tableCellF2:
            guard mods.isEmpty, let now = active() else { return false }
            return beginEditing(at: now.cell, position: now.position, replacing: nil)
        case TextEditing.home, TextEditing.end:
            guard mods.isEmpty else { return false }
            jumpColumn(last: event.charactersIgnoringModifiers == TextEditing.end)
            return true
        case TextEditing.pageUp, TextEditing.pageDown:
            guard mods.isEmpty else { return false }
            page(down: event.charactersIgnoringModifiers == TextEditing.pageDown)
            return true
        default:
            guard mods.isDisjoint(with: [.command, .control]), let typed = Self.printable(event.characters),
                  let now = active() else { return false }
            return beginEditing(at: now.cell, position: now.position, replacing: typed)
        }
    }

    /// `characters` when it is one printable character (not a control or a function-key code).
    private static func printable(_ characters: String) -> String? {
        guard characters.count == 1, let scalar = characters.unicodeScalars.first, scalar.value >= 0x20, scalar.value != 0x7f,
              !(0xF700...0xF8FF).contains(scalar.value) else { return nil }
        return characters
    }

    // MARK: Clicks

    /// A cell's click (`TCM-D`): a click on another cell first commits an open edit, then the cell becomes active and the row
    /// click (or, for a table that does not select, the table's focus) follows.
    func click(cell: Cell, position: Int, rowClick: (@MainActor () -> Void)?) -> @MainActor () -> Void {
        { @MainActor [self] in
            if let open = openSession, open.cell != cell { end(open, commit: true, restoreFocus: false) }
            activate(cell, position: position, reveals: false)
            if let rowClick { rowClick() } else { ClickDispatch.focusRequest = body }
        }
    }

    /// A click on the table's empty space commits an open edit and keeps the active cell (`TCM-D`, `TCM-F`).
    func emptySpaceClick() -> @MainActor () -> Void {
        { @MainActor [self] in
            if let open = openSession { end(open, commit: true, restoreFocus: false) }
            ClickDispatch.focusRequest = body
        }
    }

    // MARK: Editing

    /// Begins an edit at `cell` when the cell is editable (`TCM-F`): the session, then `editing` written with the cell.
    func beginEditing(at cell: Cell, position: Int?, replacing typed: String?) -> Bool {
        guard spec.canEdit, spec.isEditable(cell), let initial = spec.text else { return false }
        if let open = openSession { end(open, commit: true, restoreFocus: false) }
        let session = Session(cell: cell, text: typed ?? initial(cell), position: position)
        install(session)
        if spec.editing?.wrappedValue != cell { spec.editing?.wrappedValue = cell }
        if let position { reveal(position: position, declared: cell.column) }
        return true
    }

    /// The caller wrote `editing` (`TCM-H`), seen after the frame: `nil` cancels, another cell cancels the old edit and begins the
    /// new one, the open cell changes nothing.
    func editingChanged(to cell: Cell?) {
        if let open = openSession {
            if open.cell == cell { return }
            end(open, commit: false, restoreFocus: open.editorFocused)
        }
        guard let cell, spec.canEdit, let initial = spec.text else { return }
        let position = selection.space().index(cell.row)
        let session = Session(cell: cell, text: initial(cell), position: position)
        install(session)
        if let position { activate(cell, position: position) } else if spec.active?.wrappedValue != cell { spec.active?.wrappedValue = cell }
    }

    func install(_ session: Session?) {
        guard let table else { return }
        var state = table.peek(body, as: TableViewState.self) ?? TableViewState()
        state.edit = session
        state.editRevision &+= 1
        table.write(body, state)
    }

    /// Ends an edit exactly once (`TCM-F`, the review's top risk): `isOpen` flips first, so no path can end it twice. A commit
    /// calls `onCommit(cell, text)`, then `editing` is written `nil`.
    func end(_ session: Session, commit: Bool, restoreFocus: Bool) {
        guard session.isOpen else { return }
        session.isOpen = false
        if commit { spec.onCommit?(session.cell, session.text) }
        if let table {
            var state = table.peek(body, as: TableViewState.self) ?? TableViewState()
            if (state.edit as? Session) === session { state.edit = nil }
            state.editRevision &+= 1
            if restoreFocus { state.refocus = true }
            table.write(body, state)
        }
        if spec.editing?.wrappedValue == session.cell { spec.editing?.wrappedValue = nil }
    }

    /// Focus left the editor: the edit commits (`TCM-F`).
    func focusLeft() {
        if let open = openSession { end(open, commit: true, restoreFocus: false) }
    }

    /// The table left the hierarchy or its window closed: the edit commits (`TCM-F`).
    func disappeared() {
        if let open = openSession { end(open, commit: true, restoreFocus: false) }
    }

    /// The editor's keys, offered before the field's own (`TCM-E`): Return, ⇧Return and Tab commit and move; Escape cancels;
    /// ⌥Return is the field's own line break; everything else is the field's.
    func editorKey(_ press: KeyPress, session: Session) -> KeyPress.Result {
        let mods = press.modifiers
        switch press.key.character {
        case "\u{1b}":
            end(session, commit: false, restoreFocus: true)
            return .handled
        case "\t", "\u{19}":
            guard mods.isEmpty || mods == .shift else { return .ignored }
            commitAndMove(session, row: 0, tab: mods == .shift || press.key.character == "\u{19}" ? -1 : 1)
            return .handled
        case "\r", "\u{3}":
            let newline: Modifiers = TextEditing.platform == .mac ? [.option, .control] : .option
            guard mods.isDisjoint(with: newline), !mods.contains(.command) else { return .ignored }
            commitAndMove(session, row: mods == .shift ? -1 : 1, tab: 0)
            return .handled
        default:
            return .ignored
        }
    }

    private func commitAndMove(_ session: Session, row: Int, tab: Int) {
        guard session.isOpen else { return }   // a key that reached an editor whose edit just ended moves nothing
        let position = session.position ?? selection.space().index(session.cell.row)
        let cell = session.cell
        end(session, commit: true, restoreFocus: true)
        guard let position, columnCount > 0 else { return }
        let display = displayOf[clampedDeclared(cell.column)]
        let count = source.count()
        if tab != 0 {
            if tab > 0 {
                if display + 1 < columnCount { move(toPosition: position, display: display + 1) }
                else if position + 1 < count { move(toPosition: position + 1, display: 0) }
            } else {
                if display > 0 { move(toPosition: position, display: display - 1) }
                else if position > 0 { move(toPosition: position - 1, display: columnCount - 1) }
            }
        } else if position + row >= 0, position + row < count {
            move(toPosition: position + row, display: display)
        }
    }

    /// A keystroke reached an editor whose cell may be scrolled out: reveal it again (`TCM-G`).
    func revealEditing(_ session: Session) {
        guard session.isOpen, let position = session.position else { return }
        reveal(position: position, declared: session.cell.column)
    }
}
