@testable import MetalUI
import MetalUIPlatform
import MetalUITesting
import Testing

// `Table` keys, reveal, double click, Return, the context menu and a caller's scroll request (`TBL-N`, `TBL-O`, `TBL-P`,
// record 390; spec 5.2). Counts are read after `runUntilIdle`; `Modifiers.primary` for toggles; the harness text system; each
// test names its mutation.

/// An 800 x 600 selectable table of `rows` rows and `columns` 100-wide columns whose cells are named `r<id>c<column>`.
@MainActor func namedSelectableTable(rows: Int, columns: Int, frozen: Int = 0, model: TableSel, data: CountingRows? = nil,
                                     primary: (@MainActor (Set<Int>) -> Void)? = nil,
                                     menu: (@MainActor (Set<Int>) -> Void)? = nil) throws -> TestWindow {
    let source = data ?? CountingRows(rows)
    return try harnessWindow(size: sz(800, 600)) {
        let table = Table(source, selection: model.multiBinding()) {
            TableColumnForEach(0..<columns) { c in
                TableColumn("c\(c)") { r in Text("r\(r.id)c\(c)").id("r\(r.id)c\(c)") }.width(Pixels(100))
            }
        }
        .tableRowHeight(Pixels(24))
        .tableFrozenColumns(frozen)
        return table.contextMenu(forSelectionType: Int.self, menu: { (ids: Set<Int>) in
            // swiftlint:disable:next redundant_discardable_let - inside a result builder `let _ =` is a declaration; `_ =` would be a stray statement
            let _ = menu?(ids)
            Button("Act") {}
        }, primaryAction: primary)
    }
}

/// Row `row`'s frame in WINDOW space: the row's own hitbox (its content-space frame translated by the scroller), found through the
/// focused body's id. `origin.x` is minus the horizontal offset and `origin.y` the row's top.
@MainActor private func rowFrame(_ w: TestWindow, _ row: Int) throws -> Bounds<Pixels> {
    let body = try #require(w.window.focusedElement, "the table holds the focus")
    let id = GlobalElementID.child(of: body, at: 0, name: ElementID.forRow(row, keyed: false))
    return try #require(w.window.lastHitboxes.last { $0.id == id }, "row \(row) is realised").bounds
}

/// **K1/Reveal** ↓ moves the lead and reveals it below the header and over the same horizontal band: the lead on the last fully
/// visible row, ↓: the new row lies inside `28...600`, and the columns have not moved horizontally. Mutations: reveal x from 0
/// (the columns jump back to the left).
@Test @MainActor func arrowKeysMoveTheLeadAndRevealItBelowTheHeader() async throws {
    let model = TableSel()
    let w = try namedSelectableTable(rows: 100, columns: 20, model: model)
    try await w.runUntilIdle()
    try await scrollTable(w, x: 300, y: 0)
    w.click(at: rowPoint(22)); try await w.runUntilIdle()
    #expect(model.multi == [22])
    #expect((try? w.frame(ofID: "r22c10")) != nil && (try? w.frame(ofID: "r22c0")) == nil, "scrolled right: columns 2...11")
    w.typeKey(.downArrow); try await w.runUntilIdle()
    #expect(model.multi == [23])
    let moved = try rowFrame(w, 23)
    #expect(moved.origin.y.value >= 28 && moved.origin.y.value + moved.size.height.value <= 600, "row 23 is revealed: \(moved)")
    #expect((try? w.frame(ofID: "r23c10")) != nil && (try? w.frame(ofID: "r23c0")) == nil, "the horizontal band did not move")
}

/// **K1/Reveal-up** Scrolled so the lead row is above the viewport's top, ↑ reveals the previous row BELOW the header
/// (its frame starts at 28, not under it). Mutation: omit the header from the reveal rect (the row then lands at 0).
@Test @MainActor func anUpwardRevealClearsTheHeader() async throws {
    let model = TableSel()
    let w = try namedSelectableTable(rows: 100, columns: 3, model: model)
    try await w.runUntilIdle()
    w.click(at: rowPoint(10)); try await w.runUntilIdle()
    try await scrollTable(w, x: 0, y: 1200)
    w.typeKey(.upArrow); try await w.runUntilIdle()
    #expect(model.multi == [9])
    let row = try rowFrame(w, 9)
    #expect(row.origin.y.value == 28, "row 9 sits under the header, at the top: \(row)")
}

/// **K3** Page Down scrolls by a page of rows and does not touch the selection: from the top with row 0 selected, row 23 (a page of
/// `floor(572 / 24) = 23` rows on) is at the top below the header and the binding wrote nothing more. Probe `K3` measured Home and
/// End only; Page Up/Down stay "scroll only" (TBL-O). Mutation: Page Down moves the lead instead.
@Test @MainActor func pageDownScrollsByAPageWithoutChangingTheSelection() async throws {
    let model = TableSel()
    let w = try namedSelectableTable(rows: 200, columns: 3, model: model)
    try await w.runUntilIdle()
    w.click(at: rowPoint(0)); try await w.runUntilIdle()
    model.multiWrites = []
    w.typeKey(.pageDown); try await w.runUntilIdle()
    let down = try rowFrame(w, 23)
    #expect(down.origin.y.value == 28, "row 23 is the top row: \(down)")
    w.typeKey(.pageUp); try await w.runUntilIdle()
    let up = try rowFrame(w, 0)
    #expect(up.origin.y.value == 28, "back at the top: \(up)")
    #expect(model.multiWrites.isEmpty && model.multi == [0], "no write: \(model.multiWrites)")
}

/// **K3** Home and End scroll to the ends: after End the last row's bottom is at 600; after Home row 0 is at 28. Nothing is written.
@Test @MainActor func homeAndEndScrollToTheEnds() async throws {
    let model = TableSel()
    let w = try namedSelectableTable(rows: 100, columns: 3, model: model)
    try await w.runUntilIdle()
    w.click(at: rowPoint(2)); try await w.runUntilIdle()
    model.multiWrites = []
    w.typeKey(.end); try await w.runUntilIdle()
    let last = try rowFrame(w, 99)
    #expect(last.origin.y.value + last.size.height.value == 600, "the last row ends at 600: \(last)")
    w.typeKey(.home); try await w.runUntilIdle()
    let first = try rowFrame(w, 0)
    #expect(first.origin.y.value == 28, "row 0 is at the top: \(first)")
    #expect(model.multiWrites.isEmpty)
}

/// **K4** ← and → are declined: the key is not handled, nothing is written and nothing scrolls.
@Test @MainActor func leftAndRightArrowsAreDeclined() async throws {
    let model = TableSel()
    let w = try namedSelectableTable(rows: 100, columns: 20, model: model)
    try await w.runUntilIdle()
    w.click(at: rowPoint(2)); try await w.runUntilIdle()
    model.multiWrites = []
    let left = rawKey(w, KeyEquivalent("\u{f702}")), right = rawKey(w, KeyEquivalent("\u{f703}"))
    try await w.runUntilIdle()
    #expect(!left && !right, "declined: \(left) \(right)")
    #expect(model.multiWrites.isEmpty)
    let still = try rowFrame(w, 2)
    #expect(still.origin.x.value == 0, "no scroll: \(still)")
}

/// **K6 (divergence 1109)** There is no type-select: typing a cell's text selects nothing.
@Test @MainActor func typingDoesNotSelectARow() async throws {
    let model = TableSel()
    let w = try namedSelectableTable(rows: 20, columns: 3, model: model)
    try await w.runUntilIdle()
    w.click(at: rowPoint(2)); try await w.runUntilIdle()
    model.multiWrites = []
    w.typeText("r7c0"); try await w.runUntilIdle()
    #expect(model.multiWrites.isEmpty, "typing wrote \(model.multiWrites)")
}

/// **K5** Return runs the primary action with the whole selection: click row 3, primary-click row 5, Return gives `{3, 5}`.
/// Mutation: pass `[row]` of the lead.
@Test @MainActor func returnRunsThePrimaryActionOnTheSelection() async throws {
    let model = TableSel()
    var acted: [Set<Int>] = []
    let w = try namedSelectableTable(rows: 30, columns: 3, model: model, primary: { acted.append($0) })
    try await w.runUntilIdle()
    w.click(at: rowPoint(3)); try await w.runUntilIdle()
    w.click(at: rowPoint(5), modifierFlags: Modifiers.primary); try await w.runUntilIdle()
    w.typeKey(KeyEquivalent("\r")); try await w.runUntilIdle()
    #expect(acted == [[3, 5]], "acted \(acted)")
}

/// **P-M3** A double click selects the row and runs the primary action with it: `{8}`.
@Test @MainActor func aDoubleClickRunsThePrimaryActionWithItsRow() async throws {
    let model = TableSel()
    var acted: [Set<Int>] = []
    let w = try namedSelectableTable(rows: 30, columns: 3, model: model, primary: { acted.append($0) })
    try await w.runUntilIdle()
    w.doubleClick(at: rowPoint(8)); try await w.runUntilIdle()
    #expect(acted == [[8]], "acted \(acted)")
    #expect(model.multi == [8])
}

/// **Reveal** A key reveal of a distant row resolves without a scan: 1M rows, End reads only the new window (at most 30 rows).
/// Mutation: resolve the reveal the `List` way, by scanning the data for the row.
@Test @MainActor func aKeyRevealOfADistantRowResolvesWithoutAScan() async throws {
    let model = TableSel()
    let data = CountingRows(1_000_000)
    let w = try namedSelectableTable(rows: 0, columns: 3, model: model, data: data)
    try await w.runUntilIdle()
    w.click(at: rowPoint(0)); try await w.runUntilIdle()
    data.resetCounts()
    w.typeKey(.end); try await w.runUntilIdle()
    try await w.runUntilIdle()
    #expect(data.subscriptReads <= 30 * 2, "reads \(data.subscriptReads)")
    let last = try rowFrame(w, 999_999)
    #expect(last.origin.y.value + last.size.height.value == 600, "the last row is realised at the bottom: \(last)")
    #expect(data.subscriptReads >= 28, "the window was read: \(data.subscriptReads)")
}

// MARK: - The context menu (`TBL-P`)

/// **P-M1** A row's menu gets the selection when the row is part of it, else the row alone, and opening it does not change the
/// selection: selection `{3, 5}`; right-click on 5 gives `{3, 5}`, on 8 gives `{8}`, the selection stays. Mutation: always `[row]`.
@Test @MainActor func aRowsContextMenuGetsTheSelectionOrItsRow() async throws {
    let model = TableSel()
    var menus: [Set<Int>] = []
    let w = try namedSelectableTable(rows: 30, columns: 3, model: model, menu: { menus.append($0) })
    try await w.runUntilIdle()
    w.click(at: rowPoint(3)); try await w.runUntilIdle()
    w.click(at: rowPoint(5), modifierFlags: Modifiers.primary); try await w.runUntilIdle()
    menus = []
    model.multiWrites = []
    w.rightClick(at: rowPoint(5)); try await w.runUntilIdle()
    #expect(menus.last == [3, 5], "menus \(menus)")
    try? w.dismissMenu()
    w.rightClick(at: rowPoint(8)); try await w.runUntilIdle()
    #expect(menus.last == [8], "menus \(menus)")
    try? w.dismissMenu()
    #expect(model.multi == [3, 5] && model.multiWrites.isEmpty, "the selection is unchanged: \(model.multi) \(model.multiWrites)")
}

/// **P-M2** The table's empty space gets `[]` and still builds a menu: 5 rows, a right-click below them. Mutation: no empty-space
/// attachment (no menu is built).
@Test @MainActor func emptySpaceGetsTheEmptySet() async throws {
    let model = TableSel()
    var menus: [Set<Int>] = []
    let w = try namedSelectableTable(rows: 5, columns: 3, model: model, menu: { menus.append($0) })
    try await w.runUntilIdle()
    menus = []
    w.rightClick(at: Point(x: Pixels(50), y: Pixels(400))); try await w.runUntilIdle()
    #expect(menus.last == [], "menus \(menus)")
}

// MARK: - A caller's scroll request (`TBL-D`, `TBL-O`)

@MainActor private final class ProxyHolder { var proxy: ScrollViewProxy? }

/// A selectable table under a `ScrollViewReader`, with or without `tableRowIndex`.
@MainActor private func readerTable(rows: Int, lookup: Bool, model: TableSel, data: CountingRows, holder: ProxyHolder) throws -> TestWindow {
    try harnessWindow(size: sz(800, 600)) {
        VStack(spacing: Pixels(0)) {
            ScrollViewReader { proxy in
                // swiftlint:disable:next redundant_discardable_let - inside a result builder `let _ =` is a declaration; `_ =` would be a stray statement
                let _ = holder.proxy = proxy
                if lookup {
                    Table(data, selection: model.multiBinding()) { selectableColumns() }.tableRowHeight(Pixels(24)).tableRowIndex { $0 }
                } else {
                    Table(data, selection: model.multiBinding()) { selectableColumns() }.tableRowHeight(Pixels(24))
                }
            }
        }
    }
}

/// **C5-1** `scrollTo(rowID)` goes through `tableRowIndex`: 1M rows, `scrollTo(900_000)` reads at most the new window and row
/// 900 000 is on screen. Mutation: ignore the lookup (the table scans for the id: about 900 000 reads).
@Test @MainActor func scrollToARowIDUsesTheRowIndexLookup() async throws {
    let model = TableSel()
    let data = CountingRows(1_000_000)
    let holder = ProxyHolder()
    let w = try readerTable(rows: 1_000_000, lookup: true, model: model, data: data, holder: holder)
    try await w.runUntilIdle()
    w.click(at: rowPoint(0)); try await w.runUntilIdle()
    data.resetCounts()
    holder.proxy?.scrollTo(900_000)
    try await w.runUntilIdle()
    #expect(data.subscriptReads <= 30 * 2, "reads \(data.subscriptReads)")
    let frame = try rowFrame(w, 900_000)
    #expect(frame.origin.y.value >= 28 && frame.origin.y.value + frame.size.height.value <= 600, "row 900 000 is on screen: \(frame)")
}

/// **C5-2** Without a lookup `scrollTo` scans: 10 000 rows, `scrollTo(9_999)` reads at least 10 000 rows (the documented cost).
@Test @MainActor func scrollToWithoutALookupScans() async throws {
    let model = TableSel()
    let data = CountingRows(10_000)
    let holder = ProxyHolder()
    let w = try readerTable(rows: 10_000, lookup: false, model: model, data: data, holder: holder)
    try await w.runUntilIdle()
    w.click(at: rowPoint(0)); try await w.runUntilIdle()
    data.resetCounts()
    holder.proxy?.scrollTo(9_999)
    try await w.runUntilIdle()
    #expect(data.subscriptReads >= 10_000, "reads \(data.subscriptReads)")
    let frame = try rowFrame(w, 9_999)
    #expect(frame.origin.y.value + frame.size.height.value == 600, "the last row is on screen: \(frame)")
}
