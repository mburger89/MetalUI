import Testing
import MetalUICore
@testable import MetalUIPlatform

// The neutral tree's table fields (`TBL-T`, record 392): `columnCount`, `columnIndex`, `headerRowCount`, `sortDirection` and the
// `columnHeader` role. `AccessibilityNode` is `Equatable` and `AccessibilityTree.hasSameStructure(as:)` compares nodes, so a platform
// hears a client-visible change to any of them.

private func nid(_ name: String) -> AccessibilityNodeID { AccessibilityNodeID(name) }

private func single(_ node: AccessibilityNode) -> AccessibilityTree {
    AccessibilityTree(roots: [nid("n")], nodes: [nid("n"): node], geometry: [:], focused: nil)
}

/// **E1** Each table field takes part in structure: two trees that differ only in one of `columnCount`, `columnIndex`,
/// `headerRowCount` or `sortDirection` are not `hasSameStructure`, and equal fields are. Mutation: leave a field's assignment out
/// of the initialiser (the field then compares equal whatever it was given).
@Test func theTableFieldsTakePartInStructure() {
    let base = AccessibilityNode(role: .cell, rowIndex: 2, columnIndex: 3)
    #expect(single(base).hasSameStructure(as: single(base)))
    #expect(!single(base).hasSameStructure(as: single(AccessibilityNode(role: .cell, rowIndex: 2, columnIndex: 4))), "columnIndex")
    let table = AccessibilityNode(role: .table, rowCount: 10, columnCount: 4, headerRowCount: 1)
    #expect(!single(table).hasSameStructure(as: single(AccessibilityNode(role: .table, rowCount: 10, columnCount: 5, headerRowCount: 1))), "columnCount")
    #expect(!single(table).hasSameStructure(as: single(AccessibilityNode(role: .table, rowCount: 10, columnCount: 4, headerRowCount: 0))), "headerRowCount")
    let header = AccessibilityNode(role: .columnHeader, columnIndex: 0, sortDirection: .ascending)
    #expect(!single(header).hasSameStructure(as: single(AccessibilityNode(role: .columnHeader, columnIndex: 0, sortDirection: .descending))), "sortDirection")
    #expect(!single(header).hasSameStructure(as: single(AccessibilityNode(role: .columnHeader, columnIndex: 0))), "a sorted header is not an unsorted one")
    // The new fields default to absent, so a node built the old way carries none of them.
    let old = AccessibilityNode(role: .row, rowIndex: 1)
    #expect(old.columnCount == nil && old.columnIndex == nil && old.headerRowCount == nil && old.sortDirection == nil)
}
