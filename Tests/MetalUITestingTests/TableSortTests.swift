@testable import MetalUI
import Foundation
import MetalUITesting
import Observation
import Testing

// `Table` sorting (`TBL-Q`, record 390; probe arms `S1`..`S4`): a header click writes the `sortOrder` binding once and the table
// never sorts the data. Each test names its mutation.

struct SortRow: Identifiable, Hashable {
    let id: Int
    var name: String
    var size: Int
}

private let byName = KeyPathComparator(\SortRow.name)
private let bySize = KeyPathComparator(\SortRow.size)
private func reversed(_ c: KeyPathComparator<SortRow>) -> KeyPathComparator<SortRow> { var r = c; r.order = .reverse; return r }

/// **S1** A first click sorts by the column: nothing sorted, click Name gives `[name+]`. Mutation: return `[]`.
@Test func aFirstClickSortsByTheColumn() {
    #expect(TableSortClick.clicked(byName, in: []) == [byName])
}

/// **S2** A second click reverses it. Mutation: compare the entries INCLUDING `order` (the reversed entry no longer equals the
/// prototype, so the click inserts a second entry instead of flipping).
@Test func aSecondClickReversesIt() {
    let once = TableSortClick.clicked(byName, in: [])
    let twice = TableSortClick.clicked(byName, in: once)
    #expect(twice.count == 1 && twice[0].order == .reverse, "twice \(twice)")
    let thrice = TableSortClick.clicked(byName, in: twice)
    #expect(thrice.count == 1 && thrice[0].order == .forward, "thrice \(thrice)")
}

/// **S3/S4** Another column goes first and its old entry stays behind it (S3: Size on `[name-]` gives `[size+, name-]`); a column
/// already in the list moves to the front KEEPING its order (S4: Name on `[size+, name-]` gives `[name-, size+]`, not reset or
/// flipped). Mutation: append instead of insert at the front.
@Test func anotherColumnGoesFirstAndAnExistingEntryKeepsItsOrder() {
    #expect(TableSortClick.clicked(bySize, in: [reversed(byName)]) == [bySize, reversed(byName)])
    #expect(TableSortClick.clicked(byName, in: [bySize, reversed(byName)]) == [reversed(byName), bySize])
}

@MainActor @Observable final class SortModel {
    var order: [KeyPathComparator<SortRow>] = []
    @ObservationIgnored var writes: [[KeyPathComparator<SortRow>]] = []
    /// The row-ref form (`RowRef` rows) the cost tests use.
    var rowOrder: [KeyPathComparator<RowRef>] = []
    @ObservationIgnored var rowWrites = 0
    func binding() -> Binding<[KeyPathComparator<SortRow>]> {
        Binding(get: { self.order }, set: { self.order = $0; self.writes.append($0) })
    }
}

@MainActor private func sortedTable(_ model: SortModel) throws -> TestWindow {
    let rows = (0..<20).map { SortRow(id: $0, name: "n\($0)", size: $0 % 5) }
    return try harnessWindow(size: sz(800, 600)) {
        Table(rows, sortOrder: model.binding()) {
            TableColumn("Name", value: \SortRow.name).width(Pixels(100))
            TableColumn("Size", value: \SortRow.size) { r in Text("\(r.size)") }.width(Pixels(100))
            TableColumn("Plain") { r in Text("p\(r.id)") }.width(Pixels(100))
        }
        .tableRowHeight(Pixels(24))
    }
}

/// Glyphs and images drawn in the header band (above y 28), in the first 100 points.
@MainActor private func headerInk(_ w: TestWindow) -> Int {
    var count = 0
    for glyph in w.allGlyphs where glyph.bounds.origin.y < 28 && glyph.bounds.origin.x < 100 { count += 1 }
    for image in w.allImages where image.bounds.origin.y < 28 && image.bounds.origin.x < 100 { count += 1 }
    return count
}

/// **S1** A header click writes the sort order once, and the sorted column shows the indicator: the glyphs and images in header
/// column 0 grow by the chevron. Mutation: write the binding twice per click (the writes become two).
@Test @MainActor func aHeaderClickWritesTheSortOrderOnce() async throws {
    let model = SortModel()
    let w = try sortedTable(model)
    try await w.runUntilIdle()
    let before = headerInk(w)
    w.click(at: Point(x: Pixels(50), y: Pixels(14))); try await w.runUntilIdle()
    #expect(model.writes == [[byName]], "writes \(model.writes)")
    #expect(headerInk(w) > before, "the chevron is drawn: \(before) -> \(headerInk(w))")
    w.click(at: Point(x: Pixels(50), y: Pixels(14))); try await w.runUntilIdle()
    #expect(model.writes.count == 2 && model.order == [reversed(byName)], "second click \(model.writes)")
    w.click(at: Point(x: Pixels(150), y: Pixels(14))); try await w.runUntilIdle()
    #expect(model.order == [bySize, reversed(byName)], "size column first, the old entry behind: \(model.order)")
}

/// **S** A column with no comparator ignores header clicks. Mutation: give every column a prototype.
@Test @MainActor func aColumnWithoutAComparatorIgnoresHeaderClicks() async throws {
    let model = SortModel()
    let w = try sortedTable(model)
    try await w.runUntilIdle()
    w.click(at: Point(x: Pixels(250), y: Pixels(14))); try await w.runUntilIdle()
    #expect(model.writes.isEmpty, "writes \(model.writes)")
}
