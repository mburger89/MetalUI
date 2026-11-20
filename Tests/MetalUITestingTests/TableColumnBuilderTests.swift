@testable import MetalUI
import Foundation
import MetalUITesting
import Testing

// `TableColumnBuilder`'s structural keys and the lift of a column with no comparator (`TBL-B`, record 389). No window: the builder is
// pure, so the group's `resolve(slot:)` is read directly.

private struct Named: Identifiable { let id: Int; var name: String; var size: Int }

@MainActor private func plain(@TableColumnBuilder<Named, Never> _ build: () -> TableColumnGroup<Named, Never>) -> TableColumnGroup<Named, Never> {
    build()
}

@MainActor private func sorted(@TableColumnBuilder<Named, KeyPathComparator<Named>> _ build: () -> TableColumnGroup<Named, KeyPathComparator<Named>>)
    -> TableColumnGroup<Named, KeyPathComparator<Named>> {
    build()
}

@MainActor private func titles(_ columns: [AnyTableColumn<Named>]) -> [String] {
    columns.map { column in
        switch column.key {
        case .slot(let path): return path.map(String.init).joined(separator: ".")
        case .element(_, let id): return "\(id)"
        }
    }
}

/// **B1-1** Three columns flatten in declaration order and each is keyed by its slot: `[.slot([0]), .slot([1]), .slot([2])]`.
/// Mutation: key a column by its flattened index through a wrapper level (`slot + [0]`): the keys gain a component and the
/// comparison fails.
@Test @MainActor func theBuilderFlattensColumnsInDeclarationOrderWithStructuralKeys() {
    let group = plain {
        TableColumn("A") { _ in Text("a") }
        TableColumn("B") { _ in Text("b") }
        TableColumn("C") { _ in Text("c") }
    }
    let columns = group.resolve(slot: [])
    #expect(columns.map(\.key) == [.slot([0]), .slot([1]), .slot([2])])
    #expect(columns.map { $0.title.content.string } == ["A", "B", "C"])
}

/// **B1-2** A conditional column keeps its siblings' keys: C is `.slot([2])` whether `flag` is true or false, and B sits in its
/// own branch slot. Mutation: key a column by its flattened index (the position among the columns that exist): C becomes 1
/// when the flag is false and the two readings differ.
@Test @MainActor func aConditionalColumnKeepsItsSiblingsKeys() {
    func columns(flag: Bool) -> [AnyTableColumn<Named>] {
        plain {
            TableColumn("A") { _ in Text("a") }
            if flag { TableColumn("B") { _ in Text("b") } }
            TableColumn("C") { _ in Text("c") }
        }.resolve(slot: [])
    }
    let on = columns(flag: true), off = columns(flag: false)
    #expect(on.count == 3 && off.count == 2)
    #expect(on.last?.key == .slot([2]))
    #expect(off.last?.key == .slot([2]))
    #expect(on[1].key == .slot([1, 0, 0]), "B's key \(on[1].key)")
}

/// **B1-3** A `TableColumnForEach` column is keyed by its element's id, so "x" keeps its key when the ids reorder.
/// Mutation: key by element offset: "x" is first in one and second in the other, so the keys differ.
@Test @MainActor func aForEachColumnIsKeyedByItsElementID() {
    func key(of id: String, in ids: [String]) -> TableColumnKey? {
        plain {
            TableColumnForEach(ids, id: \.self) { name in TableColumn(name) { _ in Text(name) } }
        }.resolve(slot: []).first { $0.key == .element([0], AnyHashable(id)) }?.key
    }
    #expect(key(of: "x", in: ["x", "y"]) == .element([0], AnyHashable("x")))
    #expect(key(of: "x", in: ["y", "x"]) == .element([0], AnyHashable("x")))
    let order = plain {
        TableColumnForEach(["y", "x"], id: \.self) { name in TableColumn(name) { _ in Text(name) } }
    }.resolve(slot: []).map(\.key)
    #expect(order == [.element([0], AnyHashable("y")), .element([0], AnyHashable("x"))])
}

/// **B1-4** A `Never` column lifts into a sorted table's builder: a `value:` column carries a prototype and a content-only one
/// carries none. Mutation: lift with `sortPrototype = AnyHashable(0)`, so the content-only column's prototype is non-nil.
@Test @MainActor func aNeverSortColumnLiftsIntoASortedTablesBuilder() {
    let group = sorted {
        TableColumn("Name", value: \.name)
        TableColumn("Plain") { _ in Text("p") }
    }
    let columns = group.resolve(slot: [])
    #expect(columns.count == 2)
    #expect(columns[0].sortPrototype != nil)
    #expect(columns[1].sortPrototype == nil)
}
