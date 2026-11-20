import MetalUICore

// The selection model a `List` shares between its two forms (outline lane 4, ruling `OG-E`; extracted from
// `List.swift`, `DD-Z`, `DD-AC`, `KY6`, `KY8`, behaviour-neutral for the data list).
//
// A selectable list is, to its selection, a sequence of POSITIONS: how many there are, the id at a position, and the
// position of an id. The data `List` answers from its collection (`data[i].id`, a scan for an id); the content
// `List` answers from the visible units of its lazy tree (the selection value of unit `i`, a scan for a value). Nothing
// below knows which it is talking to: a click, an arrow key and an accessibility selection are all written once, here.

/// The rows a selection moves over, as positions `0..<count`. `id(at:)` is `nil` for a position that cannot be
/// selected (a content list's header or spacer row); a data list never answers `nil`.
struct ListRowSpace<ID: Hashable> {
    var count: Int
    /// The id at a position, or `nil` when that row cannot be selected.
    var id: @MainActor (Int) -> ID?
    /// The position of an id, by a scan, or `nil` when no row carries it (a content list's hidden selection, `P-K7`).
    var index: @MainActor (ID) -> Int?
    /// The position of the first selected row, when the list can answer without scanning every row (`TBL-N`): a `Table` over
    /// a million rows answers `nil` for an empty selection without reading one. `nil` here (the default) means the controller
    /// scans `0..<count`, as a `List` does.
    var firstSelected: (@MainActor () -> Int?)? = nil
}

/// Where a list keeps its lead and anchor rows between inputs (`DD-Z` item 7): the data list in its `ListOrigin`, a
/// content list in an entry of its own (the lazy stack's origin is at the list's id and the table keys by id alone).
struct ListLeadStore {
    /// The stored lead and anchor, or `nil` when the state they live in is gone.
    var read: @MainActor () -> (lead: AnyHashable?, anchor: AnyHashable?)?
    var write: @MainActor (_ lead: AnyHashable, _ anchor: AnyHashable) -> Void
}

/// Click, key and accessibility selection over a ``ListRowSpace``.
@MainActor
struct ListSelectionController<ID: Hashable> {
    let space: ListRowSpace<ID>
    let selection: ListSelection<ID>
    let leads: ListLeadStore
    let list: GlobalElementID

    /// The stored lead if it is still selected, else the first selected row in order (`DD-Z` item 7), else nil. Input
    /// time only (`DD-AC` item 4).
    func leadIndex(stored: AnyHashable?, isSelected: (ID) -> Bool) -> Int? {
        if let stored = stored?.base as? ID, isSelected(stored), let index = space.index(stored) { return index }
        if let firstSelected = space.firstSelected { return firstSelected() }
        for index in 0..<space.count {
            if let id = space.id(index), isSelected(id) { return index }
        }
        return nil
    }

    /// The ids of rows `a...b` (either order), inclusive.
    func ids(from a: Int, to b: Int) -> Set<ID> {
        var result = Set<ID>()
        for index in min(a, b)...max(a, b) {
            if let id = space.id(index) { result.insert(id) }
        }
        return result
    }

    /// A row's click (`DD-Z` item 4): selects exactly the row; in a multi list the platform's shortcut modifier toggles
    /// it and ⇧ selects the range from the anchor; a single list selects it whatever the modifiers. A write happens
    /// only when the selection changes. Focuses the list (`DD-Z` item 5) through `ClickDispatch.focusRequest`.
    func rowClick(row: ID) -> @MainActor () -> Void {
        let list = self.list
        let space = self.space
        let selection = self.selection
        let leads = self.leads
        let controller = self
        return {
            ClickDispatch.focusRequest = list
            guard let stored = leads.read() else { return }
            let modifiers = ClickDispatch.modifiers
            var anchor: AnyHashable = AnyHashable(row)
            switch selection {
            case .none:
                return
            case .single(let binding):
                if binding.wrappedValue != row { binding.wrappedValue = row }
            case .multi(let binding):
                let current = binding.wrappedValue
                var next: Set<ID>
                if modifiers.contains(ControlKeys.selectionToggleModifier()) {
                    next = current
                    if next.remove(row) == nil { next.insert(row) }
                } else if modifiers.contains(.shift) {
                    let rowIndex = space.index(row) ?? 0
                    let anchorIndex: Int
                    if let storedAnchor = stored.anchor?.base as? ID, current.contains(storedAnchor),
                       let found = space.index(storedAnchor) {
                        anchorIndex = found
                        anchor = AnyHashable(storedAnchor)
                    } else if let lead = controller.leadIndex(stored: stored.lead, isSelected: current.contains),
                              let leadID = space.id(lead) {
                        anchorIndex = lead
                        anchor = AnyHashable(leadID)
                    } else {
                        anchorIndex = rowIndex
                    }
                    next = controller.ids(from: anchorIndex, to: rowIndex)
                } else {
                    next = [row]
                }
                if next != current { binding.wrappedValue = next }
            }
            leads.write(AnyHashable(row), anchor)
        }
    }

    /// An accessibility client's selection (plan task 12 part 2, `IX-AA` item 1): the request's rows **replace** the
    /// selection — one row for `AXSelected` in a single or a multi list (LA2, LB3), exactly the given rows for
    /// `AXSelectedRows` (LA3, LB2) — and a single list ignores more than one (LA4). A row this list did not name refuses
    /// the whole request. Writes only a changed selection and stores the lead and anchor as a click does; unlike a click
    /// it asks for no focus (setting `AXSelected` is not a press). `byRow` maps the list's row ids to their selection
    /// ids, built at input time.
    func accessibilityRowSelection(byRow: @escaping @MainActor () -> [GlobalElementID: ID]) -> ActionHandler {
        let selection = self.selection
        let leads = self.leads
        return { action in
            guard let request = action as? AccessibilityRowSelection else { return }
            let byRow = byRow()
            let picked = request.rows.compactMap { byRow[$0] }
            guard picked.count == request.rows.count else { return }
            switch selection {
            case .none:
                return
            case .single(let binding):
                guard picked.count <= 1 else { return }
                if binding.wrappedValue != picked.first { binding.wrappedValue = picked.first }
            case .multi(let binding):
                let next = Set(picked)
                if binding.wrappedValue != next { binding.wrappedValue = next }
            }
            guard let last = picked.last else { return }
            leads.write(AnyHashable(last), AnyHashable(last))
        }
    }

    /// The lead row's position: the stored lead while it is still selected, else the first selected row, else `nil`
    /// (also `nil` for a list with no selection). Input time only.
    func leadPosition() -> Int? {
        guard let stored = leads.read() else { return nil }
        return leadPosition(stored: stored)
    }

    private func leadPosition(stored: (lead: AnyHashable?, anchor: AnyHashable?)) -> Int? {
        switch selection {
        case .none:
            return nil
        case .single(let binding):
            let current = binding.wrappedValue
            return leadIndex(stored: stored.lead, isSelected: { $0 == current })
        case .multi(let binding):
            return leadIndex(stored: stored.lead, isSelected: binding.wrappedValue.contains)
        }
    }

    /// One keyboard move (KY6, KY8): the next/previous selectable row from the lead — with nothing selected, or the
    /// selection hidden (`P-K7`), ↓ the first and ↑ the last — clamped at the ends; a multi list's plain move collapses
    /// to that row and ⇧ selects from the anchor to it; a single list ignores ⇧. Writes only a changed selection; stores
    /// the new lead (and anchor). Returns the new lead's position and id, or nil when the list has no selectable row.
    func move(_ direction: ControlKeys.Direction, extends: Bool) -> (index: Int, id: ID)? {
        let count = space.count
        guard count > 0, let stored = leads.read(), !selection.isNone else { return nil }
        let lead = leadPosition(stored: stored)
        let step = direction == .forward ? 1 : -1
        var position = lead.map { $0 + step } ?? (direction == .forward ? 0 : count - 1)
        var next = lead   // clamped at the end: the lead stays (nil: nothing is selectable)
        while position >= 0, position < count {
            if space.id(position) != nil { next = position; break }
            position += step
        }
        guard let next else { return nil }
        return commit(to: next, extends: extends, stored: stored, lead: lead)
    }

    /// Selects the row at `position` as a plain move would (`OG-E`: ← on a leaf or a collapsed group moves to its
    /// parent): a single list writes it, a multi list collapses to it; stores the lead. `nil` for a list with no
    /// selection or a row that cannot be selected.
    func select(position: Int) -> (index: Int, id: ID)? {
        guard let stored = leads.read(), !selection.isNone, space.id(position) != nil else { return nil }
        return commit(to: position, extends: false, stored: stored, lead: leadPosition(stored: stored))
    }

    private func commit(to next: Int, extends: Bool, stored: (lead: AnyHashable?, anchor: AnyHashable?),
                        lead: Int?) -> (index: Int, id: ID)? {
        guard let row = space.id(next) else { return nil }
        var anchor = AnyHashable(row)
        switch selection {
        case .none:
            return nil
        case .single(let binding):
            if binding.wrappedValue != row { binding.wrappedValue = row }
        case .multi(let binding):
            let current = binding.wrappedValue
            var selected: Set<ID> = [row]
            if extends {
                if let storedAnchor = stored.anchor?.base as? ID, current.contains(storedAnchor),
                   let found = space.index(storedAnchor) {
                    anchor = AnyHashable(storedAnchor)
                    selected = ids(from: found, to: next)
                } else if let lead, let leadID = space.id(lead) {
                    anchor = AnyHashable(leadID)
                    selected = ids(from: lead, to: next)
                }
            }
            if selected != current { binding.wrappedValue = selected }
        }
        leads.write(AnyHashable(row), anchor)
        return (next, row)
    }
}
