import Testing
import AppKit
import Foundation
import MetalUICore
@testable import MetalUIPlatform
@testable import MetalUIAppKit
@testable import MetalUI

// A `Table` through the AppKit bridge (`TBL-T`, record 392; spec 7.4; probe `docs/probes/swiftui-table.swift` arm `A1`): a data table is
// an `AXTable` (SwiftUI's is an `AXOutline` with no counts; `TBL-AB`) with `AXRowCount`, `AXColumnCount`, `AXHeader` and
// `AXColumnHeaderUIElements`; its rows are `AXRow`s with subrole `AXTableRow`, each cell an `AXCell` with `AXRowIndexRange` and
// `AXColumnIndexRange`; its header cells are `AXButton`s with subrole `AXSortButton` and an `AXSortDirection`. A `List` stays an
// `AXOutline`. In a cell-mode table the active cell is `AXFocused` and `AXSelected`, and the open editor is an `AXTextField` inside it.

private typealias Request = MetalUIPlatform.AccessibilityRequest

@MainActor private final class Running: AccessibilityClientSignal {
    func observe(_ handler: @escaping @MainActor (Bool) -> Void) { handler(true) }
}

@MainActor private final class NoPoster: AccessibilityNotificationPosting {
    func post(_ notification: NSAccessibility.Notification, for element: Any) {}
}

private struct Row: Identifiable { let id: Int }

/// `0..<count` as rows, every read O(1) (the row-source contract, `TBL-D`).
private struct RowSource: RandomAccessCollection {
    let count: Int
    init(_ count: Int) { self.count = count }
    var startIndex: Int { 0 }
    var endIndex: Int { count }
    subscript(position: Int) -> Row { Row(id: position) }
}

@MainActor private final class Order {
    var order: [KeyPathComparator<Row>] = [KeyPathComparator(\Row.id)]
    var binding: Binding<[KeyPathComparator<Row>]> { Binding(get: { self.order }, set: { self.order = $0 }) }
}

@MainActor private final class Cells {
    var active: TableCell<Int>?
    var editing: TableCell<Int>?
    var activeBinding: Binding<TableCell<Int>?> { Binding(get: { self.active }, set: { self.active = $0 }) }
    var editingBinding: Binding<TableCell<Int>?> { Binding(get: { self.editing }, set: { self.editing = $0 }) }
}

@MainActor private struct Rig {
    let window: Window
    let platform: FakePlatformWindow
    let bridge: AppKitAccessibilityBridge
    let host: NSWindow

    init(size: Int = 800, _ content: @escaping @MainActor () -> some Element) throws {
        (window, platform) = try controlWindow(size: size, content)
        platform.simulateAccessibilityRequest(.activate)
        host = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled], backing: .buffered, defer: true)
        host.isReleasedWhenClosed = false
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        host.contentView = view
        bridge = AppKitAccessibilityBridge(signal: Running(), poster: NoPoster())
        let platform = self.platform
        bridge.onRequest = { platform.simulateAccessibilityRequest($0) }
        bridge.hostView = view
        republish(frames: 8)
    }

    func republish(frames: Int = 3) {
        for _ in 0..<frames { controlRedraw(window) }
        if let tree = platform.publishedAccessibilityTrees.last { bridge.publish(tree) }
    }

    var tree: AccessibilityTree { bridge.tree }

    func element(_ matches: (AccessibilityNode) -> Bool) throws -> AppKitAccessibilityElement {
        let id = try #require(tree.nodes.first { matches($0.value) }?.key, "no such node")
        return bridge.element(for: id)
    }
}

@MainActor private func dataTable(_ order: Order, rows: Int = 1_000_000) -> some Element {
    Table(RowSource(rows), sortOrder: order.binding) {
        TableColumn("Id", value: \Row.id) { r in Text("\(r.id)") }.width(Pixels(100))
        TableColumnForEach(1..<200) { c in TableColumn("c\(c)") { r in Text("r\(r.id)c\(c)") }.width(Pixels(100)) }
    }.tableRowHeight(Pixels(24))
}


/// **E3-1** A million-by-200 table reads as an `AXTable` with its LOGICAL counts, an `AXHeader`, and one `AXColumnHeaderUIElements`
/// entry per realised column; its rows are `AXRow`/`AXTableRow` (the header row is not one of them), a cell reports its row and column
/// ranges, and the header cell of the sorted column is an `AXSortButton` reading ascending, the others unknown. Mutations: a data table
/// left an `AXOutline`; the header row counted in `AXRows`; the cell's column range its row's.
@Test @MainActor func aDataTableIsAnAXTableWithTableRows() throws {
    let order = Order()
    let rig = try Rig { dataTable(order) }
    let table = try rig.element { $0.role == .table && $0.columnCount != nil }
    #expect(table.accessibilityRole() == .table, "AXTable")
    #expect(table.accessibilityRowCount() == 1_000_000 && table.accessibilityColumnCount() == 200,
            "rows \(table.accessibilityRowCount()) columns \(table.accessibilityColumnCount())")
    let rows = try #require(table.accessibilityRows() as? [AppKitAccessibilityElement])
    #expect(!rows.isEmpty && rows.allSatisfy { $0.accessibilityRole() == .row && $0.accessibilitySubrole() == .tableRow },
            "rows \(rows.count): \(rows.map { String(describing: $0.accessibilitySubrole()) })")
    #expect(rows.first?.accessibilityIndex() == 0 && rows.dropFirst().first?.accessibilityIndex() == 1, "AXIndex counts from the first data row")
    let cells = try #require(rows[0].accessibilityChildren() as? [AppKitAccessibilityElement])
    #expect(cells.first?.accessibilityRole() == .cell)
    #expect(cells.first?.accessibilityColumnIndexRange() == NSRange(location: 0, length: 1)
            && cells.dropFirst().first?.accessibilityColumnIndexRange() == NSRange(location: 1, length: 1), "column ranges")
    #expect(cells.first?.accessibilityRowIndexRange() == NSRange(location: 0, length: 1), "row range")
    let headers = try #require(table.accessibilityColumnHeaderUIElements() as? [AppKitAccessibilityElement])
    #expect(headers.count == cells.count && headers.count >= 8, "one header per realised column: \(headers.count) against \(cells.count)")
    #expect(headers.allSatisfy { $0.accessibilityRole() == .button && $0.accessibilitySubrole() == .sortButton }, "AXButton/AXSortButton")
    #expect(headers.map { $0.accessibilitySortDirection() }.prefix(2) == [.ascending, .unknown], "directions")
    #expect(table.accessibilityHeader() != nil, "AXHeader")
    // The header is the header row, and is neither an `AXRow` of the table nor a selectable row.
    #expect((table.accessibilityHeader() as? AppKitAccessibilityElement)?.accessibilityRole() == .group)
}

/// **E3-2** A `List` is still an `AXOutline`, its rows `AXOutlineRow`, and it answers no column attributes. Mutation: map every
/// `.table` to `AXTable`.
@Test @MainActor func aListIsStillAnAXOutline() throws {
    let rig = try Rig(size: 300) { ProposalScrollView { List((0..<30).map(Row.init), rowHeight: Pixels(20)) { r in Text("row \(r.id)") } } }
    let list = try rig.element { $0.role == .table }
    #expect(list.accessibilityRole() == .outline, "a list is an AXOutline")
    #expect(!list.isAccessibilitySelectorAllowed(#selector(NSAccessibilityElement.accessibilityColumnCount)), "no column count")
    let rows = try #require(list.accessibilityRows() as? [AppKitAccessibilityElement])
    #expect(!rows.isEmpty && rows.allSatisfy { $0.accessibilitySubrole() == .outlineRow }, "outline rows")
}

/// **E3-3** In a cell-mode table the active cell is `AXFocused` while the table has focus (the host's `AXFocusedUIElement` is that cell)
/// and `AXSelected`; the others are neither. Mutation: report the table body as the focus.
@Test @MainActor func aCellModesActiveCellIsAXFocusedAndAXSelected() throws {
    let cells = Cells()
    cells.active = TableCell(row: 2, column: 1)
    let rig = try Rig {
        Table(RowSource(30)) {
            TableColumnForEach(0..<4) { c in TableColumn("c\(c)") { r in Text("r\(r.id)c\(c)") }.width(Pixels(100)) }
        }.tableRowHeight(Pixels(24)).tableActiveCell(cells.activeBinding)
    }
    let table = try rig.element { $0.role == .table && $0.columnCount != nil }
    rig.platform.simulateAccessibilityRequest(.focus(table.id))
    rig.republish()
    let focused = try #require(rig.bridge.focusedElement() as? AppKitAccessibilityElement, "a focused element")
    #expect(focused.accessibilityRole() == .cell && focused.accessibilityRowIndexRange() == NSRange(location: 2, length: 1)
            && focused.accessibilityColumnIndexRange() == NSRange(location: 1, length: 1), "the focus is the active cell")
    #expect(focused.isAccessibilityFocused() && focused.isAccessibilitySelected())
    let others = rig.tree.nodes.filter { $0.value.role == .cell && $0.key != focused.id }
    #expect(!others.isEmpty && others.allSatisfy { !$0.value.isSelected }, "no other cell is selected")
}

/// **E3-4** The open editor is an `AXTextField` child of the cell it covers, and holds the focus. Mutation: the editor left a child of
/// the table.
@Test @MainActor func theOpenEditorIsAnAXTextFieldInsideItsCell() throws {
    let cells = Cells()
    cells.active = TableCell(row: 2, column: 1)
    let rig = try Rig {
        Table(RowSource(30)) {
            TableColumnForEach(0..<4) { c in TableColumn("c\(c)") { r in Text("r\(r.id)c\(c)") }.width(Pixels(100)) }
        }.tableRowHeight(Pixels(24)).tableActiveCell(cells.activeBinding)
            .tableCellEditing(cells.editingBinding, text: { "r\($0.row)c\($0.column)" }, isEditable: { _ in true }, onCommit: { _, _ in })
    }
    cells.editing = TableCell(row: 2, column: 1)   // the caller's write begins the edit (`TCM-H`)
    rig.republish(frames: 8)
    let editor = try rig.element { $0.role == .textField }
    #expect(editor.accessibilityRole() == .textField)
    let parent = try #require(editor.accessibilityParent() as? AppKitAccessibilityElement)
    #expect(parent.accessibilityRole() == .cell && parent.accessibilityColumnIndexRange() == NSRange(location: 1, length: 1)
            && parent.accessibilityRowIndexRange() == NSRange(location: 2, length: 1), "the editor's parent is the cell")
    #expect(rig.bridge.focusedElement() as? AppKitAccessibilityElement === editor, "the editor is the focus")
}
