import Foundation
import MetalUICore
import MetalUILayout

// `Table` (`TBL-A`, `TBL-B`, `TBL-D`, `TBL-E`, `TBL-F`, `TBL-H`, record 389): SwiftUI's multi-column table, with its rows AND its
// columns virtualised. It owns its scroller, a `ProposalScrollView([.horizontal, .vertical])` around an internal `TableBody`
// (SwiftUI's shape: a table is greedy and self-scrolling), so the body knows its own origin and needs no `ListOrigin`-style
// measurement. The per-frame work depends on the viewport, never on the row or column count (`TBL-M`).

/// A multi-column table of `Value` rows, virtualised on both axes: SwiftUI's `Table`.
///
/// ```swift
/// Table(people, selection: $selection) {
///     TableColumn("Name", value: \.name)
///     TableColumn("Age") { person in Text("\(person.age)") }.width(60).alignment(.numeric)
/// }
/// ```
///
/// **The row source.** `Data` is any `RandomAccessCollection` whose `count` and `subscript(position)` are O(1): the table reads
/// `data.count` once per build and `data[i]` once per realised row, never the rest, so a million rows cost what ten do (`TBL-D`).
/// A paged source should hold cheap handles, `RowRef { ordinal, source }`, with `id = ordinal` and the cell values fetched from
/// its page cache.
///
/// **Rows are one uniform height** (divergence 1105): `tableRowHeight(_:)`, 24 points by default. A cell taller than the row is
/// clipped, where SwiftUI sizes the row to its content. **A table scrolls both ways** and answers its proposal on each axis, 0
/// where it has none (a table inside a vertical `ScrollView` needs a frame). **Columns** keep their resolved width and the table
/// scrolls across, never shrinking them to fit; a surplus grows the columns that have room.
///
/// `Columns` is always `TableColumnGroup<Value, Sort>` and `alignment(_:)` returns a `TableColumn` (divergence 1110). The rows form
/// (`Table(of:columns:rows:)`, `TableRow`), column customisation and `tableStyle` are not offered.
public struct Table<Value: Identifiable, Rows: TableRowContent, Columns: TableColumnContent>: Element, ProposalElement
where Rows.TableRowValue == Value, Columns.TableRowValue == Value {
    var source: TableSource<Value>
    var resolveColumns: @MainActor () -> [AnyTableColumn<Value>]
    var rowHeight = Double(TableMetrics.rowHeight)
    var frozenCount = 0
    var rowIndexLookup: (@MainActor (Value.ID) -> Int?)?
    var selection: ListSelection<Value.ID> = .none
    var sort: TableSortControl?
    var menu: SelectionContextMenu?
    @State var columnState = TableColumnState()
    var inner: EnvironmentScope<ProposalScrollView<TableBody<Value>>>?

    init(source: TableSource<Value>, resolveColumns: @escaping @MainActor () -> [AnyTableColumn<Value>],
         selection: ListSelection<Value.ID> = .none, sort: TableSortControl? = nil) {
        self.source = source
        self.resolveColumns = resolveColumns
        self.selection = selection
        self.sort = sort
    }

    // MARK: MetalUI-only modifiers (class M; write them directly on the table, before other modifiers)

    /// Every row's height (MetalUI-only, `TBL-F`): rows are uniform, 24 points by default, which is what makes a million rows
    /// cost a division. A non-positive or non-finite height counts as the default.
    public func tableRowHeight(_ height: Pixels) -> Self {
        var copy = self
        copy.rowHeight = height.value.isFinite && height.value > 0 ? Double(height.value) : Double(TableMetrics.rowHeight)
        return copy
    }

    /// Keeps the first `count` declared columns at the leading edge while the rest scroll under them (MetalUI-only, `TBL-H`).
    /// `count` is clamped to `0...` the number of columns; frozen columns cannot be dragged to another place.
    public func tableFrozenColumns(_ count: Int) -> Self {
        var copy = self
        copy.frozenCount = Swift.max(0, count)
        return copy
    }

    /// Tells the table how to find a row's position from its id (MetalUI-only, `TBL-D`): `lookup` returns the position in the
    /// data or `nil`. Without it a lookup by id scans the data, as a `List`'s does; with it every id lookup is O(1).
    public func tableRowIndex(_ lookup: @escaping @MainActor (Value.ID) -> Int?) -> Self {
        var copy = self
        copy.rowIndexLookup = lookup
        return copy
    }

    // MARK: The element

    /// The table's layout record.
    public struct Layout {
        var node: LayoutNodeID
        var inner: EnvironmentScopeLayout<SingleElementLayout<ProposalScrollView<TableBody<Value>>>>
    }

    /// The table's prepaint record.
    public struct Prepaint {
        var inner: EnvironmentScope<ProposalScrollView<TableBody<Value>>>.GroupPrepaint
    }

    public mutating func requestProposalLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (ProposalNodeID, Layout) {
        let headerHeight = pass.frame.environmentTop.tableColumnHeaders == .hidden ? 0 : Double(TableMetrics.headerHeight)
        // `OG-N`: the nearest `contextMenu(forSelectionType:)` above, when its identifier type is the rows' (`TBL-P`).
        menu = pass.frame.environmentTop.selectionContextMenu.flatMap { $0.applies(to: Value.ID.self) ? $0 : nil }
        var body = TableBody(source: source, resolveColumns: resolveColumns, rowHeight: rowHeight, frozenCount: frozenCount,
                             headerHeight: headerHeight, columnState: columnState)
        body.selection = selection
        body.rowIndex = rowIndexLookup
        body.sort = sort
        body.menu = menu
        var scrolled = ProposalScrollView([.horizontal, .vertical]) { body }
            .contentMargins(.top, Pixels(Float(headerHeight)), for: .scrollIndicators)
        var cursor = 0
        let (nodes, innerLayout) = scrolled.requestProposalGroupLayout(under: id, at: &cursor, pass: &pass)
        inner = scrolled
        let node = pass.requestNativeLayout(TableFrameLayout(), children: nodes)
        return (node, Layout(node: node.layoutNodeID, inner: innerLayout))
    }

    private static func emptySpaceHandlers(_ menu: SelectionContextMenu) -> Handlers {
        var handlers = Handlers()
        handlers.contextual = menu.listAttachment(over: nil)
        return handlers
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout,
                                  pass: inout PrepaintPass) -> Prepaint {
        // The table's empty space takes the menu's `[]` form (`OG-P`, `P-M2`); rows are above it and take their own.
        if let menu { pass.registerHandlers(Self.emptySpaceHandlers(menu), at: bounds, id: id) }
        var scrolled = inner!
        let result = scrolled.prepaintGroup(layout: &layout.inner, pass: &pass)
        inner = scrolled
        return Prepaint(inner: result)
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout,
                               prepaint: inout Prepaint, pass: inout PaintPass) {
        var scrolled = inner!
        scrolled.paintGroup(layout: &layout.inner, prepaint: &prepaint.inner, pass: &pass)
        inner = scrolled
    }
}

// MARK: - The initialisers

extension Table {
    /// A table over `data`, the columns `columns` builds.
    @MainActor
    public init<Data: RandomAccessCollection>(_ data: Data, @TableColumnBuilder<Value, Never> columns: () -> Columns)
    where Rows == TableForEachContent<Data>, Data.Element == Value, Columns == TableColumnGroup<Value, Never> {
        let group = columns()
        self.init(source: TableSource(data), resolveColumns: { group.resolve(slot: []) })
    }

    /// A table whose rows select into `selection`, one at a time.
    @MainActor
    public init<Data: RandomAccessCollection>(_ data: Data, selection: Binding<Value.ID?>,
                                              @TableColumnBuilder<Value, Never> columns: () -> Columns)
    where Rows == TableForEachContent<Data>, Data.Element == Value, Columns == TableColumnGroup<Value, Never> {
        let group = columns()
        self.init(source: TableSource(data), resolveColumns: { group.resolve(slot: []) }, selection: .single(selection))
    }

    /// A table whose rows select into the set `selection`.
    @MainActor
    public init<Data: RandomAccessCollection>(_ data: Data, selection: Binding<Set<Value.ID>>,
                                              @TableColumnBuilder<Value, Never> columns: () -> Columns)
    where Rows == TableForEachContent<Data>, Data.Element == Value, Columns == TableColumnGroup<Value, Never> {
        let group = columns()
        self.init(source: TableSource(data), resolveColumns: { group.resolve(slot: []) }, selection: .multi(selection))
    }

    /// A table sorted by `sortOrder`: a header click writes it, and the app sorts `data` (the table never does).
    @MainActor
    public init<Data: RandomAccessCollection, Sort: SortComparator>(_ data: Data, sortOrder: Binding<[Sort]>,
                                                                    @TableColumnBuilder<Value, Sort> columns: () -> Columns)
    where Rows == TableForEachContent<Data>, Data.Element == Value, Sort.Compared == Value,
          Columns == TableColumnGroup<Value, Sort> {
        let group = columns()
        self.init(source: TableSource(data), resolveColumns: { group.resolve(slot: []) }, sort: TableSortControl(sortOrder))
    }

    /// A sorted table whose rows select into `selection`, one at a time.
    @MainActor
    public init<Data: RandomAccessCollection, Sort: SortComparator>(_ data: Data, selection: Binding<Value.ID?>,
                                                                    sortOrder: Binding<[Sort]>,
                                                                    @TableColumnBuilder<Value, Sort> columns: () -> Columns)
    where Rows == TableForEachContent<Data>, Data.Element == Value, Sort.Compared == Value,
          Columns == TableColumnGroup<Value, Sort> {
        let group = columns()
        self.init(source: TableSource(data), resolveColumns: { group.resolve(slot: []) }, selection: .single(selection),
                  sort: TableSortControl(sortOrder))
    }

    /// A sorted table whose rows select into the set `selection`.
    @MainActor
    public init<Data: RandomAccessCollection, Sort: SortComparator>(_ data: Data, selection: Binding<Set<Value.ID>>,
                                                                    sortOrder: Binding<[Sort]>,
                                                                    @TableColumnBuilder<Value, Sort> columns: () -> Columns)
    where Rows == TableForEachContent<Data>, Data.Element == Value, Sort.Compared == Value,
          Columns == TableColumnGroup<Value, Sort> {
        let group = columns()
        self.init(source: TableSource(data), resolveColumns: { group.resolve(slot: []) }, selection: .multi(selection),
                  sort: TableSortControl(sortOrder))
    }
}
