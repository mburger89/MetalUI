@testable import MetalUI
import MetalUITesting
import Testing

// A selectable row keeps its cells' accessibility (`TBL-N`, record 394 "Fixes from Alloy"): Alloy found that with `selection:` each row
// became one button whose label joined the cell texts, and the cells' own elements and `.accessibilityIdentifier`s vanished. A
// row carries its selected state and its press on its own node and merges nothing (`List`'s selectable rows do the same); the
// row-with-cell-children shape is `TBL-T` (PR E).

@MainActor @TableColumnBuilder<RowRef, Never> private func identifiedColumns() -> TableColumnGroup<RowRef, Never> {
    TableColumn("A") { r in Text("a\(r.id)").accessibilityIdentifier("cell-a\(r.id)") }.width(Pixels(100))
    TableColumn("B") { r in Text("b\(r.id)").accessibilityIdentifier("cell-b\(r.id)") }.width(Pixels(100))
}

@MainActor private func dump(_ w: TestWindow) -> String {
    ((try? w.elements(where: { _ in true })) ?? []).prefix(12).map { "\($0.role) id=\($0.identifier ?? "-") label=\($0.label ?? "-") sel=\($0.isSelected)" }.joined(separator: "; ")
}

/// **F-7** With selection on, a cell is found by its `accessibilityIdentifier`, the row reads as selected, and no element's label
/// joins the cells' texts. Mutation: give the row `accessibilityElement(children: .combine)` semantics (a combined label).
@Test @MainActor func aSelectableRowKeepsItsCellsAccessibilityIdentifiers() async throws {
    let model = TableSel()
    model.multi = [1]
    let w = try harnessWindow(size: sz(800, 600)) {
        Table(CountingRows(5), selection: model.multiBinding()) { identifiedColumns() }.tableRowHeight(Pixels(24))
    }
    try await w.runUntilIdle()
    let a = try w.element(identifier: "cell-a1")
    let b = try w.element(identifier: "cell-b1")
    #expect(a.value == "a1" && b.value == "b1", "cells read \(String(describing: a.value)), \(String(describing: b.value)): \(dump(w))")
    let joined = try w.elements(where: { ($0.label ?? "").contains("a1") && ($0.label ?? "").contains("b1") })
    #expect(joined.isEmpty, "a row combined its cells: \(joined.map { $0.label ?? "" })")
    let selected = try w.elements(where: { $0.isSelected })
    #expect(selected.count == 1 && selected.first?.role == .row, "selected elements \(selected.map(\.role)): \(dump(w))")
}

/// **F-8** Cell mode's cells (clickable themselves, over selectable rows) keep their identifiers as a plain table's do. Mutation:
/// register the cell's click with `synthesizesAccessibility: true` (each cell then publishes as a button of its text).
@Test @MainActor func aCellModeTablesCellsKeepTheirIdentifiers() async throws {
    let model = CellModel(), sel = TableSel()
    let w = try harnessWindow(size: sz(800, 600)) {
        Table(CountingRows(5), selection: sel.multiBinding()) { identifiedColumns() }.tableRowHeight(Pixels(24))
            .tableActiveCell(model.activeBinding())
    }
    try await w.runUntilIdle()
    #expect((try? w.element(identifier: "cell-a1")) != nil, "cell-a1 missing: \(dump(w))")
    #expect((try? w.element(identifier: "cell-b2")) != nil, "cell-b2 missing: \(dump(w))")
    let plain = try harnessWindow(size: sz(800, 600)) { Table(CountingRows(5)) { identifiedColumns() }.tableRowHeight(Pixels(24)) }
    try await plain.runUntilIdle()
    #expect((try? plain.element(identifier: "cell-a1")) != nil, "plain: cell-a1 missing: \(dump(plain))")
}
