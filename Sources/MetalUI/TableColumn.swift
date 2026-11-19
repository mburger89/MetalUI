import Foundation
import MetalUICore
import MetalUILayout

// `TableColumn` (`TBL-B`, `TBL-G`, `TBL-K`, record 389): a title, a cell builder, a width and an alignment. Class A except the
// cell content type (`ElementGroup`, so a `Component` or an `.equatable()` cell is accepted, as a `ViewBuilder` accepts any view).

/// How a column's cells sit in the column: SwiftUI's `TableColumnAlignment`.
public struct TableColumnAlignment: Hashable, Sendable {
    enum Kind: Hashable, Sendable { case automatic, leading, center, trailing, numeric }
    let kind: Kind

    /// The platform's choice: leading.
    public static let automatic = TableColumnAlignment(kind: .automatic)
    /// Against the leading edge.
    public static let leading = TableColumnAlignment(kind: .leading)
    /// Centred in the column.
    public static let center = TableColumnAlignment(kind: .center)
    /// Against the trailing edge.
    public static let trailing = TableColumnAlignment(kind: .trailing)
    /// For numbers: against the trailing edge. SwiftUI's `numeric(_:)` form with a locale is not offered (`TBL-U`).
    public static let numeric = TableColumnAlignment(kind: .numeric)

    /// Whether cells sit against the trailing edge.
    var isTrailing: Bool { kind == .trailing || kind == .numeric }
    var isCentered: Bool { kind == .center }
}

/// One column of a `Table`: SwiftUI's `TableColumn`.
///
/// A column has a title, a function from a row to the cell's content and, when the table sorts, a comparator. Its width comes
/// from `width(_:)` or `width(min:ideal:max:)` (a fixed width cannot be resized). A cell shorter than its column is aligned by
/// `alignment(_:)`; a cell wider or taller than the column and the table's row is clipped (divergence 1105).
public struct TableColumn<RowValue: Identifiable, Sort: SortComparator, Content: ElementGroup, Label: Element>: TableColumnContent {
    /// The row value.
    public typealias TableRowValue = RowValue
    /// The comparator.
    public typealias TableColumnSortComparator = Sort

    var title: Text
    var content: @MainActor (RowValue) -> Content
    var spec = TableColumnWidthSpec()
    var cellAlignment = TableColumnAlignment.automatic
    var sortPrototype: AnyHashable?

    init(title: Text, sortPrototype: AnyHashable?, content: @escaping @MainActor (RowValue) -> Content) {
        self.title = title
        self.sortPrototype = sortPrototype
        self.content = content
    }

    /// This column fixed at `width` points: not resizable, and it takes no share of a surplus.
    public func width(_ width: Pixels) -> Self {
        var copy = self
        copy.spec = TableColumnWidthSpec(fixed: Double(width.value))
        return copy
    }

    /// This column's smallest, preferred and largest widths, each optional. With none (`width()`) the column takes the default.
    public func width(min: Pixels? = nil, ideal: Pixels? = nil, max: Pixels? = nil) -> Self {
        var copy = self
        copy.spec = TableColumnWidthSpec(fixed: nil, min: min.map { Double($0.value) }, ideal: ideal.map { Double($0.value) },
                                         max: max.map { Double($0.value) })
        return copy
    }

    /// How this column's cells sit in it. SwiftUI returns `some TableColumnContent`; this returns the column (divergence 1110).
    public func alignment(_ alignment: TableColumnAlignment) -> Self {
        var copy = self
        copy.cellAlignment = alignment
        return copy
    }
}

extension TableColumn: TableColumnResolving {
    func resolveColumns(slot: [UInt16]) -> [AnyTableColumn<RowValue>] {
        let key = TableColumnKey.slot(slot)
        let content = self.content, alignment = cellAlignment
        return [AnyTableColumn(key: key, elementID: AnyTableColumn<RowValue>.name(for: key), title: title, width: spec,
                               alignment: alignment,
                               makeCell: { row, name in
                                   TableCellHolder(TableCellBox(content: LegacyContent(content(row)), alignment: alignment, columnID: name))
                               },
                               sortPrototype: sortPrototype)]
    }
}

// MARK: - Inits with no comparator (`Sort == Never`)

extension TableColumn where Sort == Never, Label == Text {
    /// A column titled `title` whose cells `content` builds from the row.
    public init(_ title: LocalizedStringKey, @ElementBuilder content: @escaping @MainActor (RowValue) -> Content) {
        self.init(title: Text(title), sortPrototype: nil, content: content)
    }

    /// A column titled `title` (a string, shown verbatim) whose cells `content` builds from the row.
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, @ElementBuilder content: @escaping @MainActor (RowValue) -> Content) {
        self.init(title: Text(verbatim: String(title)), sortPrototype: nil, content: content)
    }

    /// A column titled with `title` whose cells `content` builds from the row.
    public init(_ title: Text, @ElementBuilder content: @escaping @MainActor (RowValue) -> Content) {
        self.init(title: title, sortPrototype: nil, content: content)
    }
}

extension TableColumn where Sort == Never, Content == Text, Label == Text {
    /// A column titled `title` showing the string at `value` in each row.
    public init(_ title: LocalizedStringKey, value: KeyPath<RowValue, String>) {
        self.init(title: Text(title), sortPrototype: nil, content: { Text(verbatim: $0[keyPath: value]) })
    }

    /// A column titled `title` (a string, shown verbatim) showing the string at `value` in each row.
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, value: KeyPath<RowValue, String>) {
        self.init(title: Text(verbatim: String(title)), sortPrototype: nil, content: { Text(verbatim: $0[keyPath: value]) })
    }

    /// A column titled with `title` showing the string at `value` in each row.
    public init(_ title: Text, value: KeyPath<RowValue, String>) {
        self.init(title: title, sortPrototype: nil, content: { Text(verbatim: $0[keyPath: value]) })
    }
}

// MARK: - Inits that sort by a key path (`Sort == KeyPathComparator<RowValue>`)

extension TableColumn where Sort == KeyPathComparator<RowValue>, Label == Text {
    /// A column that sorts by the comparable value at `value`, its cells built by `content`.
    public init<V: Comparable>(_ title: LocalizedStringKey, value: KeyPath<RowValue, V> & Sendable,
                               @ElementBuilder content: @escaping @MainActor (RowValue) -> Content) {
        self.init(title: Text(title), sortPrototype: AnyHashable(KeyPathComparator(value)), content: content)
    }

    /// A column titled `title` (a string) that sorts by the comparable value at `value`.
    @_disfavoredOverload
    public init<S: StringProtocol, V: Comparable>(_ title: S, value: KeyPath<RowValue, V> & Sendable,
                                                  @ElementBuilder content: @escaping @MainActor (RowValue) -> Content) {
        self.init(title: Text(verbatim: String(title)), sortPrototype: AnyHashable(KeyPathComparator(value)), content: content)
    }

    /// A column titled with `title` that sorts by the comparable value at `value`.
    public init<V: Comparable>(_ title: Text, value: KeyPath<RowValue, V> & Sendable,
                               @ElementBuilder content: @escaping @MainActor (RowValue) -> Content) {
        self.init(title: title, sortPrototype: AnyHashable(KeyPathComparator(value)), content: content)
    }

    /// A column that sorts by the value at `value` with `comparator`.
    public init<V, C: SortComparator>(_ title: LocalizedStringKey, value: KeyPath<RowValue, V> & Sendable, comparator: C,
                                      @ElementBuilder content: @escaping @MainActor (RowValue) -> Content)
    where C.Compared == V {
        self.init(title: Text(title), sortPrototype: AnyHashable(KeyPathComparator(value, comparator: comparator)), content: content)
    }

    /// A column titled `title` (a string) that sorts by the value at `value` with `comparator`.
    @_disfavoredOverload
    public init<S: StringProtocol, V, C: SortComparator>(_ title: S, value: KeyPath<RowValue, V> & Sendable, comparator: C,
                                                         @ElementBuilder content: @escaping @MainActor (RowValue) -> Content)
    where C.Compared == V {
        self.init(title: Text(verbatim: String(title)),
                  sortPrototype: AnyHashable(KeyPathComparator(value, comparator: comparator)), content: content)
    }

    /// A column titled with `title` that sorts by the value at `value` with `comparator`.
    public init<V, C: SortComparator>(_ title: Text, value: KeyPath<RowValue, V> & Sendable, comparator: C,
                                      @ElementBuilder content: @escaping @MainActor (RowValue) -> Content)
    where C.Compared == V {
        self.init(title: title, sortPrototype: AnyHashable(KeyPathComparator(value, comparator: comparator)), content: content)
    }
}

extension TableColumn where Sort == KeyPathComparator<RowValue>, Content == Text, Label == Text {
    /// A column showing, and sorting by, the string at `value`, compared with `comparator`.
    public init(_ title: LocalizedStringKey, value: KeyPath<RowValue, String> & Sendable,
                comparator: String.StandardComparator = .localizedStandard) {
        self.init(title: Text(title), sortPrototype: AnyHashable(KeyPathComparator(value, comparator: comparator)),
                  content: { Text(verbatim: $0[keyPath: value]) })
    }

    /// A column titled `title` (a string) showing, and sorting by, the string at `value`.
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, value: KeyPath<RowValue, String> & Sendable,
                                   comparator: String.StandardComparator = .localizedStandard) {
        self.init(title: Text(verbatim: String(title)), sortPrototype: AnyHashable(KeyPathComparator(value, comparator: comparator)),
                  content: { Text(verbatim: $0[keyPath: value]) })
    }

    /// A column titled with `title` showing, and sorting by, the string at `value`.
    public init(_ title: Text, value: KeyPath<RowValue, String> & Sendable, comparator: String.StandardComparator = .localizedStandard) {
        self.init(title: title, sortPrototype: AnyHashable(KeyPathComparator(value, comparator: comparator)),
                  content: { Text(verbatim: $0[keyPath: value]) })
    }
}

// MARK: - Inits that sort by a given comparator

extension TableColumn where Sort.Compared == RowValue, Label == Text {
    /// A column that sorts rows with `comparator`.
    public init(_ title: LocalizedStringKey, sortUsing comparator: Sort,
                @ElementBuilder content: @escaping @MainActor (RowValue) -> Content) {
        self.init(title: Text(title), sortPrototype: AnyHashable(comparator), content: content)
    }

    /// A column titled `title` (a string) that sorts rows with `comparator`.
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, sortUsing comparator: Sort,
                                   @ElementBuilder content: @escaping @MainActor (RowValue) -> Content) {
        self.init(title: Text(verbatim: String(title)), sortPrototype: AnyHashable(comparator), content: content)
    }

    /// A column titled with `title` that sorts rows with `comparator`.
    public init(_ title: Text, sortUsing comparator: Sort,
                @ElementBuilder content: @escaping @MainActor (RowValue) -> Content) {
        self.init(title: title, sortPrototype: AnyHashable(comparator), content: content)
    }
}
