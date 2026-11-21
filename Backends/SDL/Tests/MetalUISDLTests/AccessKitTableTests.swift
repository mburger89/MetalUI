import Testing
import MetalUICore
import MetalUIPlatform
@testable import MetalUISDL
import CAccessKit

// A `Table` as AccessKit sees it (`TBL-T`, record 392; spec 7.5). The data table is `TABLE` with `column_count` and a `row_count` that
// counts the header row; the header row is `ROW` at `row_index` 0 whose cells are `COLUMN_HEADER`s with `column_index` and
// `sort_direction`; a data row is `ROW` at its position plus the header count, its cells `CELL` with `row_index` and `column_index`.
// Names are read from AccessKit's own header (`accesskit-c` 0.23). In cell mode the active cell is the focus and a selected node,
// and the open editor a `TEXT_INPUT` child of that cell.

private func nid(_ name: String) -> AccessibilityNodeID { AccessibilityNodeID(name) }

private func withCNode<T>(_ node: AccessKitSnapshot.Node, _ body: (OpaquePointer) -> T) -> T {
    let c = AccessKitAdapter.cNode(node)
    defer { accesskit_node_free(c) }
    return body(c)
}

/// What the core publishes for the steady window of a million-by-200 table, cut to three columns of two rows: the table (counts of
/// the LOGICAL data), the header row first with its ascending header cell, then rows 498 and 499 with their cells.
private func tableTree(focused: String? = nil, activeCell: Bool = false, editor: Bool = false) -> AccessibilityTree {
    var nodes: [AccessibilityNodeID: AccessibilityNode] = [:]
    nodes[nid("table")] = AccessibilityNode(role: .table, children: [nid("header"), nid("r498"), nid("r499")], rowCount: 1_000_000,
                                            columnCount: 200, headerRowCount: 1)
    nodes[nid("header")] = AccessibilityNode(role: .row, children: [nid("h5"), nid("h6")])
    nodes[nid("h5")] = AccessibilityNode(role: .columnHeader, label: "c5", actions: [.press], columnIndex: 5, sortDirection: .ascending)
    nodes[nid("h6")] = AccessibilityNode(role: .columnHeader, label: "c6", columnIndex: 6)
    nodes[nid("r498")] = AccessibilityNode(role: .row, children: [nid("r498c5"), nid("r498c6")], rowIndex: 498)
    nodes[nid("r498c5")] = AccessibilityNode(role: .cell, isSelected: activeCell, rowIndex: 498, columnIndex: 5)
    nodes[nid("r498c6")] = AccessibilityNode(role: .cell, rowIndex: 498, columnIndex: 6)
    nodes[nid("r499")] = AccessibilityNode(role: .row, children: [nid("r499c5")], rowIndex: 499)
    nodes[nid("r499c5")] = AccessibilityNode(role: .cell, rowIndex: 499, columnIndex: 5)
    if editor {
        nodes[nid("r498c5")]?.children = [nid("editor")]
        nodes[nid("editor")] = AccessibilityNode(role: .textField, value: "r498c5", isFocusable: true)
    }
    return AccessibilityTree(roots: [nid("table")], nodes: nodes, geometry: [:], focused: focused.map(nid))
}

private func snapshot(_ tree: AccessibilityTree, ids: AccessKitIDs) -> AccessKitSnapshot {
    AccessKitSnapshot.translate(tree, title: "", scale: 1, ids: ids)
}

/// **E4-1** A data table is `TABLE` with `column_count` 200 and `row_count` 1 000 001 (the header counted); the header row is `ROW` at
/// `row_index` 0, its cells `COLUMN_HEADER` with their `column_index` and, on the sorted column, `ASCENDING`; row 498 is at
/// `row_index` 499 and its cells at 499 with `column_index` 5 (the header shifts every data row and cell). Mutation: no header shift.
@Test func aTableMapsToAccessKitTableWithHeaderRowCounted() throws {
    let ids = AccessKitIDs()
    let nodes = Dictionary(uniqueKeysWithValues: snapshot(tableTree(), ids: ids).nodes.map { ($0.id, $0) })
    let n = { (name: String) -> UInt64 in ids.number(for: nid(name)) }
    withCNode(try #require(nodes[n("table")])) { c in
        #expect(accesskit_node_role(c) == accesskit_role(ACCESSKIT_ROLE_TABLE.rawValue))
        let rows = accesskit_node_row_count(c), columns = accesskit_node_column_count(c)
        #expect(rows.has_value && rows.value == 1_000_001, "row_count counts the header: \(rows.value)")
        #expect(columns.has_value && columns.value == 200, "column_count \(columns.value)")
    }
    withCNode(try #require(nodes[n("header")])) { c in
        #expect(accesskit_node_role(c) == accesskit_role(ACCESSKIT_ROLE_ROW.rawValue))
        let index = accesskit_node_row_index(c)
        #expect(index.has_value && index.value == 0, "the header row is row 0")
    }
    withCNode(try #require(nodes[n("h5")])) { c in
        #expect(accesskit_node_role(c) == accesskit_role(ACCESSKIT_ROLE_COLUMN_HEADER.rawValue))
        let column = accesskit_node_column_index(c), direction = accesskit_node_sort_direction(c)
        #expect(column.has_value && column.value == 5)
        #expect(direction.has_value && direction.value == UInt8(ACCESSKIT_SORT_DIRECTION_ASCENDING.rawValue), "ascending")
        #expect(accesskit_node_supports_action(c, accesskit_action(ACCESSKIT_ACTION_CLICK.rawValue)), "a sortable header clicks")
    }
    withCNode(try #require(nodes[n("h6")])) { c in
        #expect(!accesskit_node_sort_direction(c).has_value, "an unsorted header has no direction")
    }
    withCNode(try #require(nodes[n("r498")])) { c in
        #expect(accesskit_node_role(c) == accesskit_role(ACCESSKIT_ROLE_ROW.rawValue))
        let index = accesskit_node_row_index(c)
        #expect(index.has_value && index.value == 499, "data row 498 is row 499 under the header: \(index.value)")
    }
    withCNode(try #require(nodes[n("r498c5")])) { c in
        #expect(accesskit_node_role(c) == accesskit_role(ACCESSKIT_ROLE_CELL.rawValue))
        let row = accesskit_node_row_index(c), column = accesskit_node_column_index(c)
        #expect(row.has_value && row.value == 499 && column.has_value && column.value == 5, "cell row \(row.value) column \(column.value)")
    }
    #expect(nodes[n("table")]?.children == [n("header"), n("r498"), n("r499")], "the header is the first child")
}

/// **E4-2** A table with its column headers hidden has no header to count: `row_count` is the data's and rows keep their positions.
/// Mutation: always add one.
@Test func aTableWithNoHeaderRowCountsOnlyItsData() throws {
    var tree = tableTree()
    tree.nodes[nid("table")]?.headerRowCount = 0
    tree.nodes[nid("table")]?.children = [nid("r498")]
    let ids = AccessKitIDs()
    let nodes = Dictionary(uniqueKeysWithValues: snapshot(tree, ids: ids).nodes.map { ($0.id, $0) })
    withCNode(try #require(nodes[ids.number(for: nid("table"))])) { c in
        let rows = accesskit_node_row_count(c)
        #expect(rows.has_value && rows.value == 1_000_000, "row_count \(rows.value)")
    }
    withCNode(try #require(nodes[ids.number(for: nid("r498"))])) { c in
        #expect(accesskit_node_row_index(c).value == 498)
    }
}

/// **E4-3** A list is `TABLE` as before: its `row_count` and `row_index` are untouched and it sets no `column_count`. Mutation: shift
/// every table's rows.
@Test func aListsRowIndicesAreNotShifted() throws {
    let tree = AccessibilityTree(roots: [nid("l")], nodes: [nid("l"): AccessibilityNode(role: .table, children: [nid("r")], rowCount: 40),
                                                            nid("r"): AccessibilityNode(role: .row, rowIndex: 7)],
                                 geometry: [:], focused: nil)
    let ids = AccessKitIDs()
    let nodes = Dictionary(uniqueKeysWithValues: snapshot(tree, ids: ids).nodes.map { ($0.id, $0) })
    withCNode(try #require(nodes[ids.number(for: nid("l"))])) { c in
        #expect(accesskit_node_row_count(c).value == 40 && !accesskit_node_column_count(c).has_value)
    }
    withCNode(try #require(nodes[ids.number(for: nid("r"))])) { c in #expect(accesskit_node_row_index(c).value == 7) }
}

/// **E4-4** The active cell of a cell-mode table is AccessKit's focus and its `selected` node, and the other cells are not selected.
/// Mutation: translate the focus to the table, or drop the cell's `selected`.
@Test func theActiveCellIsAccessKitsFocusAndSelected() throws {
    let ids = AccessKitIDs()
    let published = snapshot(tableTree(focused: "r498c5", activeCell: true), ids: ids)
    #expect(published.focus == ids.number(for: nid("r498c5")), "focus \(published.focus)")
    let nodes = Dictionary(uniqueKeysWithValues: published.nodes.map { ($0.id, $0) })
    withCNode(try #require(nodes[ids.number(for: nid("r498c5"))])) { c in
        let selected = accesskit_node_is_selected(c)
        #expect(selected.has_value && selected.value, "the active cell is selected")
    }
    withCNode(try #require(nodes[ids.number(for: nid("r498c6"))])) { c in
        #expect(!(accesskit_node_is_selected(c).has_value && accesskit_node_is_selected(c).value), "another cell is not")
    }
}

/// **E4-5** The open editor is a `TEXT_INPUT` inside its cell, and the focus. Mutation: lift the editor out of its cell.
@Test func theOpenEditorIsATextInputInsideItsCell() throws {
    let ids = AccessKitIDs()
    let published = snapshot(tableTree(focused: "editor", editor: true), ids: ids)
    let nodes = Dictionary(uniqueKeysWithValues: published.nodes.map { ($0.id, $0) })
    let cell = try #require(nodes[ids.number(for: nid("r498c5"))])
    #expect(cell.children == [ids.number(for: nid("editor"))], "the cell holds the editor")
    #expect(published.focus == ids.number(for: nid("editor")))
    withCNode(try #require(nodes[ids.number(for: nid("editor"))])) { c in
        #expect(accesskit_node_role(c) == accesskit_role(ACCESSKIT_ROLE_TEXT_INPUT.rawValue))
    }
}
