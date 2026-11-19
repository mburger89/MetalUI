import Foundation
import MetalUICore
import MetalUILayout

// `Table`'s column vocabulary (`TBL-B`, record 389): the content protocols, the result builder, the erased group and
// `TableColumnForEach`. A column is keyed by its place in the builder, never by its position on screen (`ID-B`'s rule, mirrored).

/// A column or a group of columns: SwiftUI's `TableColumnContent`.
///
/// `TableColumn`, `TableColumnGroup` and `TableColumnForEach` conform. The requirement list is the two associated types; what
/// a `Table` reads from a conformer is internal.
@MainActor
public protocol TableColumnContent<TableRowValue, TableColumnSortComparator> {
    /// The row value the column's cells are built from.
    associatedtype TableRowValue: Identifiable
    /// The comparator the column sorts by, `Never` for a column that does not sort.
    associatedtype TableColumnSortComparator: SortComparator
}

/// The rows of a table: SwiftUI's `TableRowContent`. Only `TableForEachContent` conforms in this version (the rows form is not
/// offered, `TBL-U`); `Table`'s `Rows` stays a generic parameter so it can be added later without breaking anything.
@MainActor
public protocol TableRowContent<TableRowValue> {
    /// The row value.
    associatedtype TableRowValue: Identifiable
}

/// The rows of a `Table` built from a collection: SwiftUI's `TableForEachContent`.
///
/// An empty placeholder, never built by an app, as `ListContentRows` is for a content `List`: it only gives `Table`'s `Rows`
/// parameter its type.
public struct TableForEachContent<Data: RandomAccessCollection>: TableRowContent where Data.Element: Identifiable {
    /// The row value.
    public typealias TableRowValue = Data.Element
}

// MARK: - Keys

/// A column's identity (`TBL-B`): its structural slot path in the builder, or, for a `TableColumnForEach` element, the path and the
/// element's id. Display position is never identity.
enum TableColumnKey: Hashable {
    case slot([UInt16])
    case element([UInt16], AnyHashable)
}

/// A column with its type removed: what a `Table` reads, one per column per build.
struct AnyTableColumn<RowValue: Identifiable> {
    var key: TableColumnKey
    /// The component naming this column's cells and header cell.
    var elementID: ElementID
    var title: Text
    var width: TableColumnWidthSpec
    var alignment: TableColumnAlignment
    /// Builds one body cell for `row`, named `elementID`.
    var makeCell: @MainActor (RowValue, ElementID) -> AnyTableCell
    /// The comparator value a header click sorts by, `nil` for a column that does not sort.
    var sortPrototype: AnyHashable?

    /// This column under `key` (a `TableColumnForEach` element's), its element id recomputed.
    func rekeyed(_ newKey: TableColumnKey) -> AnyTableColumn<RowValue> {
        var copy = self
        copy.key = newKey
        copy.elementID = Self.name(for: newKey)
        return copy
    }

    static func name(for key: TableColumnKey) -> ElementID {
        if case .element = key { return ElementID.forColumn(key, keyed: true) }
        return ElementID.forColumn(key, keyed: false)
    }
}

/// What the builder and `TableColumnGroup` ask of a column conformer: its columns, given its structural slot.
@MainActor
protocol TableColumnResolving: TableColumnContent {
    /// The columns this content stands for under `slot`. A static column is one; a `TableColumnForEach` re-resolves its data on
    /// every call (O(elements), counted in `tableColumnsResolved`).
    func resolveColumns(slot: [UInt16]) -> [AnyTableColumn<TableRowValue>]
}

extension TableColumnResolving {
    /// `resolveColumns` through an existential: the columns as `[AnyTableColumn<TableRowValue>]`, boxed.
    func resolveErased(slot: [UInt16]) -> Any { resolveColumns(slot: slot) }
}

// MARK: - The group and the builder

/// The columns a `TableColumnBuilder` block produced, erased: SwiftUI's `TableColumnGroup`.
///
/// `Table`'s `Columns` is always this type in MetalUI (divergence 1110): the builder's result, with the block's statements
/// flattened to columns in declaration order.
public struct TableColumnGroup<RowValue: Identifiable, Sort: SortComparator>: TableColumnContent {
    /// The row value.
    public typealias TableRowValue = RowValue
    /// The comparator.
    public typealias TableColumnSortComparator = Sort

    /// One builder statement's columns, given the slot path that statement owns.
    typealias Part = @MainActor ([UInt16]) -> [AnyTableColumn<RowValue>]
    var parts: [Part]

    init(parts: [Part]) { self.parts = parts }

    /// Every statement's columns in order, statement `i` owning slot `slot + [i]`.
    func resolve(slot: [UInt16]) -> [AnyTableColumn<RowValue>] {
        var out: [AnyTableColumn<RowValue>] = []
        for (index, part) in parts.enumerated() { out.append(contentsOf: part(slot + [UInt16(truncatingIfNeeded: index)])) }
        return out
    }
}

extension TableColumnGroup: TableColumnResolving {
    func resolveColumns(slot: [UInt16]) -> [AnyTableColumn<RowValue>] { resolve(slot: slot) }
}

/// Builds the columns of a `Table`: SwiftUI's `TableColumnBuilder`.
///
/// Each statement owns one structural slot, so a column's key survives an `if` above or beside it (an `if` is one slot whatever
/// it produces, and a branch adds a component, as `ID-B` does for a view). A column with no comparator (`Never`) is accepted
/// in a sorted table and lifted to one that sorts by nothing.
@resultBuilder
public struct TableColumnBuilder<RowValue: Identifiable, Sort: SortComparator> {
    /// A column, a group or a `TableColumnForEach` with this builder's row value and comparator.
    @MainActor
    public static func buildExpression<C: TableColumnContent>(_ content: C) -> TableColumnGroup<RowValue, Sort>
    where C.TableRowValue == RowValue, C.TableColumnSortComparator == Sort {
        TableColumnGroup(parts: [Self.part(of: content)])
    }

    /// A column with no comparator, in a table that sorts: it joins the block and sorts by nothing.
    @MainActor @_disfavoredOverload
    public static func buildExpression<C: TableColumnContent>(_ content: C) -> TableColumnGroup<RowValue, Sort>
    where C.TableRowValue == RowValue, C.TableColumnSortComparator == Never {
        TableColumnGroup(parts: [Self.part(of: content, lifting: true)])
    }

    /// `content`'s columns under a slot. A `lifting` column has no comparator of its own: its prototype is cleared, so a click on
    /// its header writes nothing.
    @MainActor
    private static func part<C: TableColumnContent>(of content: C, lifting: Bool = false) -> TableColumnGroup<RowValue, Sort>.Part {
        guard let resolving = content as? any TableColumnResolving else { return { _ in [] } }
        return { slot in
            let columns = resolving.resolveErased(slot: slot) as? [AnyTableColumn<RowValue>] ?? []
            guard lifting else { return columns }
            return columns.map { column in var lifted = column; lifted.sortPrototype = nil; return lifted }
        }
    }

    /// An empty block.
    @MainActor
    public static func buildBlock() -> TableColumnGroup<RowValue, Sort> { TableColumnGroup(parts: []) }

    /// A block's first statement, unchanged.
    @MainActor
    public static func buildPartialBlock(first: TableColumnGroup<RowValue, Sort>) -> TableColumnGroup<RowValue, Sort> { first }

    /// The next statement's columns after the ones before it.
    @MainActor
    public static func buildPartialBlock(accumulated: TableColumnGroup<RowValue, Sort>,
                                         next: TableColumnGroup<RowValue, Sort>) -> TableColumnGroup<RowValue, Sort> {
        TableColumnGroup(parts: accumulated.parts + next.parts)
    }

    /// `if` with no `else`: one slot, its branch one level below it.
    @MainActor
    public static func buildOptional(_ group: TableColumnGroup<RowValue, Sort>?) -> TableColumnGroup<RowValue, Sort> {
        TableColumnGroup(parts: [{ slot in group?.resolve(slot: slot + [0]) ?? [] }])
    }

    /// The `if` branch of an `if`/`else`.
    @MainActor
    public static func buildEither(first: TableColumnGroup<RowValue, Sort>) -> TableColumnGroup<RowValue, Sort> {
        TableColumnGroup(parts: [{ slot in first.resolve(slot: slot + [0]) }])
    }

    /// The `else` branch of an `if`/`else`.
    @MainActor
    public static func buildEither(second: TableColumnGroup<RowValue, Sort>) -> TableColumnGroup<RowValue, Sort> {
        TableColumnGroup(parts: [{ slot in second.resolve(slot: slot + [1]) }])
    }

    /// `if #available`.
    @MainActor
    public static func buildLimitedAvailability(_ group: TableColumnGroup<RowValue, Sort>) -> TableColumnGroup<RowValue, Sort> { group }
}

// MARK: - TableColumnForEach

/// Columns made from a collection, as `ForEach` makes views: SwiftUI's `TableColumnForEach`.
///
/// The collection is read on every build (O(columns), no element is built); only the windowed columns' cells are ever built. A
/// column is keyed by its element's id, so the surviving columns of a changed collection keep their cells' `@State`.
public struct TableColumnForEach<Data: RandomAccessCollection, ID: Hashable, RowValue: Identifiable, Sort: SortComparator,
                                 Content: TableColumnContent>: TableColumnContent
where Content.TableRowValue == RowValue, Content.TableColumnSortComparator == Sort {
    /// The row value.
    public typealias TableRowValue = RowValue
    /// The comparator.
    public typealias TableColumnSortComparator = Sort

    var data: Data
    var idOf: (Data.Element) -> ID
    var content: @MainActor (Data.Element) -> Content

    /// Columns over identifiable `data`, one per element.
    @MainActor
    public init(_ data: Data, @TableColumnBuilder<RowValue, Sort> content: @escaping @MainActor (Data.Element) -> Content)
    where ID == Data.Element.ID, Data.Element: Identifiable {
        self.data = data
        self.idOf = { $0.id }
        self.content = content
    }

    /// Columns over `data`, one per element, identified by `id`.
    @MainActor
    public init(_ data: Data, id: KeyPath<Data.Element, ID>,
                @TableColumnBuilder<RowValue, Sort> content: @escaping @MainActor (Data.Element) -> Content) {
        self.data = data
        self.idOf = { $0[keyPath: id] }
        self.content = content
    }

    /// Columns over a range of integers, one per integer, identified by it.
    @MainActor
    public init(_ data: Range<Int>, @TableColumnBuilder<RowValue, Sort> content: @escaping @MainActor (Int) -> Content)
    where Data == Range<Int>, ID == Int {
        self.data = data
        self.idOf = { $0 }
        self.content = content
    }
}

extension TableColumnForEach: TableColumnResolving {
    func resolveColumns(slot: [UInt16]) -> [AnyTableColumn<RowValue>] {
        var out: [AnyTableColumn<RowValue>] = []
        out.reserveCapacity(data.count)
        for element in data {
            let id = AnyHashable(idOf(element))
            let built = content(element)
            guard let resolving = built as? any TableColumnResolving,
                  let inner = resolving.resolveErased(slot: []) as? [AnyTableColumn<RowValue>] else { continue }
            for (index, column) in inner.enumerated() {
                // `TBL-B`: (the ForEach's slot, the element's id); several columns per element add the inner position.
                let path = inner.count > 1 ? slot + [UInt16(truncatingIfNeeded: index)] : slot
                out.append(column.rekeyed(.element(path, id)))
            }
        }
        return out
    }
}
