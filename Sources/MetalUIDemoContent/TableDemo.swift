import Foundation
import MetalUI

/// The table demo (`TBL-V`, record 389), reached with `METALUI_TABLE_DEMO=1 swift run MetalUIDemo`: a `Table` over a synthetic
/// source of 1 000 000 rows by 200 columns, with the "#" column frozen, three sortable `value:` columns, a `Set` selection, a context
/// menu and `tableRowIndex { $0 }`.
///
/// The rows are cheap handles (`TableDemoRow`, an ordinal) behind a `RandomAccessCollection` whose `count` and subscript are O(1), as the
/// row-source contract asks (`TBL-D`); the cell values are computed from the ordinal, so nothing is stored per row. A header click
/// writes the sort order, which this demo reads only for its direction (the source reverses itself, O(1)); the table never sorts data.
/// A click selects (⌘ toggles, ⇧ selects a range), ↑ ↓ move the selection, Page Up/Down/Home/End scroll, a header click on a sortable
/// column writes the sort order (the leading column shows a chevron), and a right-click opens the menu (`TBL-N`..`TBL-Q`, record 390).
///
/// **The human look** (group TBL of `docs/verification/human-checks.md`): scrolling a trackpad or a wheel through 1 000 000 x 200 shows no
/// blank band, the header stays at the top while the rows scroll and moves with the columns across, the "#" column stays at the
/// leading edge, and a diagonal flick locks to one axis. Nothing here is in the default demo, so the offscreen images do not move.
/// The tree is its own function (the Windows 1 MB stack rule).
@MainActor
public func tableDemoContent() -> some Element {
    tableDemoRoot()
}

@MainActor
private func tableDemoRoot() -> some Element {
    VStack(alignment: .leading, spacing: Pixels(8)) {
        ProposalText("Table: 1 000 000 rows x 200 columns, windowed on both axes")
            .font(size: 16)
        TableDemoBody()
    }
    .padding(Edges(all: Pixels(12)))
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(.background)
}

/// One row of the synthetic source: an ordinal, with every cell computed from it.
struct TableDemoRow: Identifiable, Sendable {
    let id: Int
    var name: String { "Row \(id)" }
    var value: Int { (id &* 7919) % 10_000 }
    var group: Int { id % 97 }
}

/// 1 000 000 rows with O(1) `count` and subscript; `descending` reads them backwards.
struct TableDemoRows: RandomAccessCollection {
    let count: Int
    let descending: Bool
    var startIndex: Int { 0 }
    var endIndex: Int { count }
    subscript(position: Int) -> TableDemoRow { TableDemoRow(id: descending ? count - 1 - position : position) }
}

private let tableDemoRowCount = 1_000_000

private struct TableDemoBody: Component {
    @State var selection = Set<Int>()
    @State var sortOrder = [KeyPathComparator(\TableDemoRow.id)]

    var content: some ElementGroup {
        let descending = sortOrder.first?.order == .reverse
        Table(TableDemoRows(count: tableDemoRowCount, descending: descending), selection: $selection, sortOrder: $sortOrder) {
            TableColumn("#") { row in Text("\(row.id)") }.width(Pixels(90)).alignment(.numeric)
            TableColumn("Name", value: \.name).width(min: Pixels(80), ideal: Pixels(120), max: Pixels(300))
            TableColumn("Value", value: \.value) { row in Text("\(row.value)") }.width(Pixels(90)).alignment(.numeric)
            TableColumn("Group", value: \.group) { row in Text("\(row.group)") }.width(Pixels(80))
            TableColumnForEach(0..<196) { column in
                TableColumn("Column \(column)") { row in Text("\(row.id &* (column + 1) % 1000)") }.width(Pixels(100))
            }
        }
        .tableFrozenColumns(1)
        .tableRowIndex { descending ? tableDemoRowCount - 1 - $0 : $0 }
        .contextMenu(forSelectionType: Int.self) { rows in
            Button("Copy \(rows.count) row\(rows.count == 1 ? "" : "s")") {}
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
