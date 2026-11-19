@testable import MetalUI
import Foundation
import MetalUITesting
import Testing

// Every spelling of `TableColumn`, its modifiers, `TableColumnForEach` and `Table` compiles (`TBL-B`, record 389). The bodies assert
// little: the guard is that the file builds, which is what "SwiftUI's source compiles" means.

private struct Person: Identifiable { let id: Int; var name: String; var age: Int }

/// **B1-5** Every initialiser of spec 1.2 in each title spelling (a `LocalizedStringKey` literal, a `String` value, a `Text`), the
/// three width forms, the alignments, the three `TableColumnForEach` initialisers and the six `Table` initialisers. Mutation: delete
/// any one initialiser from `TableColumn.swift` and this file stops compiling.
@Test @MainActor func everyTableColumnSpellingCompiles() throws {
    let title = "Dynamic"
    let people = [Person(id: 1, name: "A", age: 3)]
    var selection: Person.ID?
    var set = Set<Person.ID>()
    var order = [KeyPathComparator(\Person.name)]
    let single = Binding(get: { selection }, set: { selection = $0 })
    let multi = Binding(get: { set }, set: { set = $0 })
    let sort = Binding(get: { order }, set: { order = $0 })

    // No comparator.
    _ = TableColumn<Person, Never, Text, Text>("Literal") { Text($0.name) }
    _ = TableColumn<Person, Never, Text, Text>(title) { Text($0.name) }
    _ = TableColumn<Person, Never, Text, Text>(Text("Text")) { Text($0.name) }
    _ = TableColumn<Person, Never, Text, Text>("Literal", value: \.name)
    _ = TableColumn<Person, Never, Text, Text>(title, value: \.name)
    _ = TableColumn<Person, Never, Text, Text>(Text("Text"), value: \.name)
    // A key path comparator.
    _ = TableColumn<Person, KeyPathComparator<Person>, Text, Text>("Age", value: \.age) { Text("\($0.age)") }
    _ = TableColumn<Person, KeyPathComparator<Person>, Text, Text>(title, value: \.age) { Text("\($0.age)") }
    _ = TableColumn<Person, KeyPathComparator<Person>, Text, Text>(Text("Age"), value: \.age) { Text("\($0.age)") }
    _ = TableColumn<Person, KeyPathComparator<Person>, Text, Text>("Age", value: \.age, comparator: ReverseComparator<Int>()) { Text("\($0.age)") }
    _ = TableColumn<Person, KeyPathComparator<Person>, Text, Text>(title, value: \.age, comparator: ReverseComparator<Int>()) { Text("\($0.age)") }
    _ = TableColumn<Person, KeyPathComparator<Person>, Text, Text>(Text("Age"), value: \.age, comparator: ReverseComparator<Int>()) { Text("\($0.age)") }
    _ = TableColumn<Person, KeyPathComparator<Person>, Text, Text>("Name", value: \.name)
    _ = TableColumn<Person, KeyPathComparator<Person>, Text, Text>("Name", value: \.name, comparator: .lexical)
    _ = TableColumn<Person, KeyPathComparator<Person>, Text, Text>(title, value: \.name)
    _ = TableColumn<Person, KeyPathComparator<Person>, Text, Text>(Text("Name"), value: \.name)
    // Sort using a comparator of the row.
    _ = TableColumn<Person, KeyPathComparator<Person>, Text, Text>("Name", sortUsing: KeyPathComparator(\Person.name)) { Text($0.name) }
    _ = TableColumn<Person, KeyPathComparator<Person>, Text, Text>(title, sortUsing: KeyPathComparator(\Person.name)) { Text($0.name) }
    _ = TableColumn<Person, KeyPathComparator<Person>, Text, Text>(Text("Name"), sortUsing: KeyPathComparator(\Person.name)) { Text($0.name) }

    // The modifiers.
    let column = TableColumn<Person, Never, Text, Text>("A") { Text($0.name) }
    _ = column.width(Pixels(80))
    _ = column.width(min: Pixels(40), ideal: Pixels(80), max: Pixels(200))
    _ = column.width()
    _ = column.alignment(.numeric).alignment(.leading).alignment(.center).alignment(.trailing).alignment(.automatic)

    // TableColumnForEach: identifiable elements, an id key path, a range.
    _ = TableColumnForEach(people) { person in TableColumn(person.name, value: \Person.name) }
    _ = TableColumnForEach(["a", "b"], id: \.self) { name in TableColumn(name) { (_: Person) in Text(name) } }
    _ = TableColumnForEach(0..<3) { index in TableColumn("c\(index)") { (_: Person) in Text("\(index)") } }

    // Every Table initialiser, and the three MetalUI modifiers on one.
    _ = Table(people) { TableColumn("Name", value: \.name) }
    _ = Table(people, selection: single) { TableColumn("Name", value: \.name) }
    _ = Table(people, selection: multi) { TableColumn("Name", value: \.name) }
    _ = Table(people, sortOrder: sort) { TableColumn("Name", value: \.name); TableColumn("Plain") { Text($0.name) } }
    _ = Table(people, selection: single, sortOrder: sort) { TableColumn("Name", value: \.name) }
    _ = Table(people, selection: multi, sortOrder: sort) { TableColumn("Name", value: \.name) }
        .tableRowHeight(Pixels(30)).tableFrozenColumns(1).tableRowIndex { $0 }
    _ = Table(people) { TableColumn("Name", value: \.name) }.tableColumnHeaders(.hidden)
}

private struct ReverseComparator<Compared: Comparable & Sendable>: SortComparator {
    var order: SortOrder = .forward
    func compare(_ lhs: Compared, _ rhs: Compared) -> ComparisonResult {
        let result: ComparisonResult = lhs < rhs ? .orderedAscending : (lhs > rhs ? .orderedDescending : .orderedSame)
        return order == .forward ? result : (result == .orderedAscending ? .orderedDescending : (result == .orderedDescending ? .orderedAscending : .orderedSame))
    }
}
