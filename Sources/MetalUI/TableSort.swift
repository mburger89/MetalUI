import Foundation
import MetalUICore

// `Table` sorting (`TBL-Q`, record 390): a header click writes the `sortOrder` binding, once. The table never sorts the data; the
// app does, as in SwiftUI. The rule is the one probe arms `S1`..`S4` measured on SwiftUI's own table.

/// The sort order a header click makes (`TBL-Q`, probe `S1`..`S4`).
enum TableSortClick {
    /// Whether `a` and `b` are the same comparator once their `order` is ignored.
    static func sameIgnoringOrder<S: SortComparator>(_ a: S, _ b: S) -> Bool {
        var a = a, b = b
        a.order = .forward
        b.order = .forward
        return a == b
    }

    /// The sort order after a click on the column whose comparator is `prototype`, given the current `order`:
    ///
    /// - the column is already first (compared ignoring `order`): its `order` flips (`S2`);
    /// - the column is elsewhere in the list: that entry moves to the front **keeping its order** (`S4`);
    /// - the column is not in the list: `prototype` goes to the front and the others stay behind it (`S1`, `S3`).
    static func clicked<S: SortComparator>(_ prototype: S, in order: [S]) -> [S] {
        if let first = order.first, sameIgnoringOrder(first, prototype) {
            var flipped = order
            flipped[0].order = first.order == .forward ? .reverse : .forward
            return flipped
        }
        if let index = order.firstIndex(where: { sameIgnoringOrder($0, prototype) }) {
            var moved = order
            let entry = moved.remove(at: index)
            moved.insert(entry, at: 0)
            return moved
        }
        return [prototype] + order
    }
}

/// A table's `sortOrder` binding with its comparator type removed (`TBL-Q`): the table reads the leading entry to draw the
/// indicator and writes the clicked order.
@MainActor
struct TableSortControl {
    /// Reads the binding once and answers, for a column's prototype, the order it leads with, or `nil` if it does not lead.
    var leading: @MainActor () -> (@MainActor (AnyHashable) -> SortOrder?)
    /// Applies a click on the column whose prototype this is: one write of the binding.
    var click: @MainActor (AnyHashable) -> Void

    init<Sort: SortComparator>(_ binding: Binding<[Sort]>) {
        leading = {
            let first = binding.wrappedValue.first
            return { prototype in
                guard let first, let typed = prototype.base as? Sort, TableSortClick.sameIgnoringOrder(first, typed) else { return nil }
                return first.order
            }
        }
        click = { prototype in
            guard let typed = prototype.base as? Sort else { return }
            binding.wrappedValue = TableSortClick.clicked(typed, in: binding.wrappedValue)
        }
    }
}
