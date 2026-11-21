import MetalUICore
import MetalUILayout

// `Table` selection, keys and reveal (`TBL-N`, `TBL-O`, `TBL-P`, record 390). The selection model is `List`'s
// (`ListSelectionController`), driven over POSITIONS: a click, an arrow key and an accessibility selection are written once
// there. Everything here is input time: no phase of a steady frame reads a row for the selection's sake.

/// A small LRU of row id to position (`TBL-N`): eight entries, so a click, its ⇧-click and the keys after them find their
/// rows without a scan. A cached position is only a hint; whoever uses one verifies it with one read.
@MainActor
final class TableRowPositionCache {
    static let capacity = 8
    private var entries: [(id: AnyHashable, position: Int)] = []

    /// Remembers `position` for `id`, evicting the least recently noted entry past eight.
    func note(_ id: AnyHashable, _ position: Int) {
        if let index = entries.firstIndex(where: { $0.id == id }) { entries.remove(at: index) }
        entries.append((id, position))
        if entries.count > Self.capacity { entries.removeFirst() }
    }

    /// The position last noted for `id`, or `nil`.
    func position(of id: AnyHashable) -> Int? { entries.last { $0.id == id }?.position }
}

/// The key a table's keyboard move or scroll enqueues on the `DD-G` queue (`TBL-O`): internal, so no caller's `scrollTo` key
/// can equal it, and matched only by the body it names. The body resolves it by position, with no scan (spec 5.2).
struct TableLeadReveal: Hashable {
    let body: GlobalElementID
    let position: Int
}

/// What a click, key or accessibility request needs of one table build (`TBL-N`): the data by position, the selection, and where
/// the lead lives. One per build, shared by every realised row's closures; every method runs at input time.
@MainActor
final class TableSelectionContext<Value: Identifiable> {
    let source: TableSource<Value>
    let rowIndex: (@MainActor (Value.ID) -> Int?)?
    let selection: ListSelection<Value.ID>
    let body: GlobalElementID
    weak var table: StateTable?

    init(source: TableSource<Value>, rowIndex: (@MainActor (Value.ID) -> Int?)?, selection: ListSelection<Value.ID>,
         body: GlobalElementID, table: StateTable) {
        self.source = source
        self.rowIndex = rowIndex
        self.selection = selection
        self.body = body
        self.table = table
    }

    /// The table's position cache, made on first use at the body's state.
    func positions() -> TableRowPositionCache {
        var cache: TableRowPositionCache?
        // `unchanged:` (`TBL-L`): the cache exists after the first use, so a settled table's build writes nothing and stays retained.
        table?.withState(body, initial: TableViewState(), unchanged: TableViewState.sameEntry) { state in
            if state.positions == nil { state.positions = TableRowPositionCache() }
            cache = state.positions
        }
        return cache ?? TableRowPositionCache()
    }

    /// The rows as positions (`TBL-N`): the id at a position is one read; the position of an id is the cached position verified
    /// with one read, then `tableRowIndex` verified the same way, and only then a scan (`List`'s documented cost).
    func space() -> ListRowSpace<Value.ID> {
        let source = self.source, lookup = rowIndex, selection = self.selection
        let cache = positions()
        let count = source.count()
        func holds(_ id: Value.ID, at position: Int) -> Bool {
            position >= 0 && position < count && source.element(position).id == id
        }
        return ListRowSpace(
            count: count,
            id: { position in position >= 0 && position < count ? source.element(position).id : nil },
            index: { id in
                if let cached = cache.position(of: AnyHashable(id)), holds(id, at: cached) { return cached }
                if let found = lookup?(id), holds(id, at: found) { cache.note(AnyHashable(id), found); return found }
                for position in 0..<count where source.element(position).id == id {
                    cache.note(AnyHashable(id), position)
                    return position
                }
                return nil
            },
            firstSelected: {
                let selected = selection.currentSet()
                if selected.isEmpty { return nil }
                if let lookup { return selected.compactMap { lookup($0) }.filter { $0 >= 0 && $0 < count }.min() }
                for position in 0..<count where selected.contains(source.element(position).id) { return position }
                return nil
            })
    }

    /// Where the lead and anchor rows live: the body's `TableViewState` (`TBL-L`), written through `withState`, which fires no
    /// `onWrite`.
    func leadStore() -> ListLeadStore {
        let body = self.body
        return ListLeadStore(
            read: { [weak table] in
                guard let table else { return nil }
                let state = table.peek(body, as: TableViewState.self)
                return (state?.lead, state?.anchor)
            },
            write: { [weak table] lead, anchor in
                table?.withState(body, initial: TableViewState()) {
                    $0.lead = lead
                    $0.anchor = anchor
                }
            })
    }

    func controller() -> ListSelectionController<Value.ID> {
        ListSelectionController(space: space(), selection: selection, leads: leadStore(), list: body)
    }

    /// A row's click: seeds the row's position (`TBL-N`: a click seeds its own), then the shared selection click.
    func rowClick(row: Value.ID, position: Int) -> @MainActor () -> Void {
        { [self] in
            positions().note(AnyHashable(row), position)
            controller().rowClick(row: row)()
        }
    }

    /// An accessibility client's selection (`IX-AA`): `ids` are the REALISED rows, so the request maps O(window) rows, never
    /// the data. A row the table did not realise refuses the whole request.
    func accessibilityRowSelection(realised ids: [Value.ID], keyed: Bool) -> ActionHandler {
        let body = self.body
        let controller = self.controller()
        return controller.accessibilityRowSelection {
            var byRow: [GlobalElementID: Value.ID] = [:]
            byRow.reserveCapacity(ids.count)
            for id in ids {
                byRow[GlobalElementID.child(of: body, at: 0, name: ElementID.forRow(id, keyed: keyed))] = id
            }
            return byRow
        }
    }

    /// The table's keys (`TBL-O`), after Return: ↑ ↓ move the lead and reveal it; Page Up, Page Down, Home and End scroll only.
    /// ← → and every other key are declined.
    func keyHandler(menu: SelectionContextMenu?, queue: ScrollRequestQueue, rowHeight: Double, headerHeight: Double)
        -> @MainActor (KeyEvent) -> Bool {
        { @MainActor [self] event in
            let selection = self.selection
            if let menu, menu.returnKey(event, selection: Set(selection.currentSet().map { AnyHashable($0) })) { return true }
            guard let scope = body.parent else { return false }
            @MainActor func reveal(_ position: Int, anchor: UnitPoint?) {
                queue.enqueue(ScrollRequest(scope: scope, key: AnyHashable(TableLeadReveal(body: body, position: position)),
                                            anchor: anchor))
            }
            if let move = ControlKeys.listMove(event) {
                guard !selection.isNone,
                      let moved = controller().move(move.direction, extends: move.extends) else { return false }
                positions().note(AnyHashable(moved.id), moved.index)
                reveal(moved.index, anchor: nil)
                return true
            }
            guard let key = ControlKeys.tableScroll(event) else { return false }
            let count = source.count()
            guard count > 0 else { return true }
            switch key {
            case .home: reveal(0, anchor: nil)
            case .end: reveal(count - 1, anchor: nil)
            case .pageUp, .pageDown:
                guard let plan = table?.peek(body, as: TableViewState.self)?.lastPlan, rowHeight > 0 else { return true }
                let page = Swift.max(1, Int((plan.viewportHeight - headerHeight) / rowHeight))
                let top = Int((plan.offsetY / rowHeight).rounded())
                let target = key == .pageDown ? top + page : top - page
                reveal(Swift.min(Swift.max(0, target), count - 1), anchor: .top)
            }
            return true
        }
    }
}

extension ControlKeys {
    /// What a focused `Table`'s scroll keys are (`TBL-O`, probe `K3`).
    enum TableScrollKey { case pageUp, pageDown, home, end }

    /// A focused `Table`'s scroll key: Page Up, Page Down, Home or End with no modifiers; every other key, and any modifier,
    /// declines it. The key scrolls and leaves the selection alone.
    static func tableScroll(_ event: KeyEvent) -> TableScrollKey? {
        guard event.modifiers.isEmpty else { return nil }
        switch event.charactersIgnoringModifiers {
        case TextEditing.pageUp: return .pageUp
        case TextEditing.pageDown: return .pageDown
        case TextEditing.home: return .home
        case TextEditing.end: return .end
        default: return nil
        }
    }
}
