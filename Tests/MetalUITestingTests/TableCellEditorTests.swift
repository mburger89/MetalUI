@testable import MetalUI
import MetalUIPlatform
import MetalUITesting
import Observation
import Testing

// `Table` cell mode, the editor (`TCM-F`, `TCM-G`, `TCM-H`, record 394): beginning, committing, cancelling and keeping an edit, and the
// review's top risk: an edit ends in exactly one `onCommit` or one cancel, never silently. Counts are read after `runUntilIdle` and
// summed over `frameWork`; `Modifiers.primary`; the harness text system; each test names its mutation.

private let returnKey = "\r", tabKey = "\t", escapeKey = "\u{1b}", f2Key = "\u{f705}"

/// A table with the editor on, cell (3, 2) active and the table focused, its body's id and the editor's.
@MainActor private struct Editing {
    let w: TestWindow
    let model: CellModel
    let body: GlobalElementID
    var editor: GlobalElementID { GlobalElementID.child(of: body, at: 0, name: tableEditorName) }

    /// The editor's text as the window's text target sees it, or `nil` when there is none.
    var text: String? { w.window.lastFocusRegistry.textTarget(for: editor)?.text }
    var editorHasFocus: Bool { w.window.focusedElement == editor }
    var tableHasFocus: Bool { w.window.focusedElement == body }

    init(rows: Int = 50, columns: Int = 6, model: CellModel = CellModel(), selection: TableSel? = nil, data: CountingRows? = nil,
         rawPrefix: String = "", editableCell: (@MainActor (TableCell<Int>) -> Bool)? = nil, frozen: Int = 0) async throws {
        self.model = model
        w = try cellTable(rows: rows, columns: columns, frozen: frozen, model: model, selection: selection, data: data,
                          editableCell: editableCell, rawPrefix: rawPrefix)
        try await w.runUntilIdle()
        w.click(at: rowPoint(3, column: 2)); try await w.runUntilIdle()
        body = try #require(w.window.focusedElement, "the table is focused")
    }

    func key(_ character: String, _ modifiers: EventModifiers = []) async throws {
        w.typeKey(KeyEquivalent(Character(character)), modifierFlags: modifiers)
        try await w.runUntilIdle()
    }

    func type(_ text: String) async throws {
        w.typeText(text)
        try await w.runUntilIdle()
    }
}

/// Exactly one commit of `text` for `cell`, and `editing` ended `nil`: the ending every edit owes.
@MainActor private func expectOneCommit(_ model: CellModel, _ cell: TableCell<Int>, _ text: String, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(model.commits.count == 1, "commits \(model.commits)", sourceLocation: sourceLocation)
    #expect(model.commits.first?.cell == cell && model.commits.first?.text == text, "commit \(String(describing: model.commits.first))",
            sourceLocation: sourceLocation)
    #expect(model.editing == nil, "editing ended", sourceLocation: sourceLocation)
    #expect(model.editingWrites == [cell, nil], "editing writes \(model.editingWrites)", sourceLocation: sourceLocation)
}

/// **F1** Return begins an edit with the CALLER'S text, the raw value, not the displayed content, writes `editing` with the cell and
/// gives the editor the focus. Mutation: the editor starts from the displayed content.
@Test @MainActor func returnBeginsEditingWithTheCallersText() async throws {
    let e = try await Editing(rawPrefix: "raw:")
    try await e.key(returnKey)
    #expect(e.text == "raw:r3c2", "editor text \(String(describing: e.text))")
    #expect(e.model.editing == TableCell(row: 3, column: 2) && e.model.editingWrites == [TableCell(row: 3, column: 2)])
    #expect(e.editorHasFocus, "the editor holds the focus")
    #expect(e.model.textCalls == 1, "asked for the text once: \(e.model.textCalls)")
    #expect(e.model.commits.isEmpty)
}

/// **F2** A printable key begins the edit with the text REPLACED by that character, caret at its end. Mutation: the edit starts
/// from the caller's text and the character is lost.
@Test @MainActor func typingACharacterReplacesTheText() async throws {
    let e = try await Editing()
    try await e.type("x")
    #expect(e.text == "x", "editor text \(String(describing: e.text))")
    #expect(e.editorHasFocus)
    try await e.type("y")
    #expect(e.text == "xy", "the caret was at the end: \(String(describing: e.text))")
}

/// **F3** Return in the editor commits ONCE with the edited text, ends `editing`, and moves down one row: the active cell is
/// (4, 2), the table has its focus back and a further ↓ moves again. Mutation: the commit runs twice (the guard that an edit ends
/// once is removed, so the focus leaving the editor commits again).
@Test @MainActor func returnCommitsOnceAndMovesDown() async throws {
    let e = try await Editing()
    try await e.key(returnKey)
    try await e.type("Z")
    try await e.key(returnKey)
    expectOneCommit(e.model, TableCell(row: 3, column: 2), "r3c2Z")
    #expect(e.model.active == TableCell(row: 4, column: 2), "moved down: \(String(describing: e.model.active))")
    #expect(e.tableHasFocus, "the table has its focus back")
    #expect(e.text == nil, "the editor is gone")
    try await e.key("\u{f701}")
    #expect(e.model.active == TableCell(row: 5, column: 2), "keys work again")
    #expect(e.model.commits.count == 1)
}

/// **F4** ⇧Return commits and moves up; Tab commits and moves right; ⇧Tab left. Mutation: Tab commits and stays.
@Test @MainActor func shiftReturnAndTabCommitAndMove() async throws {
    let e = try await Editing()
    try await e.key(returnKey); try await e.key(returnKey, .shift)
    #expect(e.model.active == TableCell(row: 2, column: 2) && e.model.commits.count == 1, "⇧Return: \(String(describing: e.model.active))")
    try await e.key(returnKey); try await e.key(tabKey)
    #expect(e.model.active == TableCell(row: 2, column: 3) && e.model.commits.count == 2, "Tab: \(String(describing: e.model.active))")
    try await e.key(returnKey); try await e.key(tabKey, .shift)
    #expect(e.model.active == TableCell(row: 2, column: 2) && e.model.commits.count == 3, "⇧Tab: \(String(describing: e.model.active))")
    #expect(e.tableHasFocus)
}

/// **F5** Tab from the last column commits and wraps to the next row's first column. Mutation: Tab does not wrap an edit.
@Test @MainActor func tabAtTheLastColumnWrapsAfterTheCommit() async throws {
    let e = try await Editing(columns: 3)
    w3: do {
        e.w.click(at: rowPoint(3, column: 2)); try await e.w.runUntilIdle()
        try await e.key(returnKey); try await e.key(tabKey)
        #expect(e.model.active == TableCell(row: 4, column: 0), "wrapped: \(String(describing: e.model.active))")
        #expect(e.model.commits.count == 1)
    }
}

/// **F6** Escape cancels with no callback and the typed text is discarded; the active cell stays and the table has its focus back.
/// Mutation: Escape commits.
@Test @MainActor func escapeCancelsWithNoCallback() async throws {
    let e = try await Editing()
    try await e.key(returnKey)
    try await e.type("Z")
    try await e.key(escapeKey)
    #expect(e.model.commits.isEmpty, "no onCommit: \(e.model.commits)")
    #expect(e.model.editing == nil && e.model.editingWrites == [TableCell(row: 3, column: 2), nil])
    #expect(e.model.active == TableCell(row: 3, column: 2) && e.text == nil && e.tableHasFocus)
    #expect(e.model.overrides.isEmpty, "the typed text went nowhere")
}

/// **F7** The caller writing `editing = nil` cancels: no callback, the editor is gone, and the table has the focus the editor had.
/// Mutation: the cancel commits.
@Test @MainActor func aCallerNilCancels() async throws {
    let e = try await Editing()
    try await e.key(returnKey); try await e.type("Z")
    e.model.editing = nil
    try await e.w.runUntilIdle()
    #expect(e.model.commits.isEmpty, "no onCommit: \(e.model.commits)")
    #expect(e.text == nil, "the editor is gone")
    #expect(e.tableHasFocus, "the table has its focus")
    // The edit never ends twice: moving focus now commits nothing.
    e.w.window.focus(nil); try await e.w.runUntilIdle()
    #expect(e.model.commits.isEmpty)
}

/// **F8** The caller writing a cell begins an edit there, reveals the cell and makes it the active cell. Mutation: the edit does
/// not reveal (the row stays off screen).
@Test @MainActor func aCallerCellBeginsAnEditAndRevealsIt() async throws {
    let e = try await Editing(rows: 500)
    e.model.editing = TableCell(row: 300, column: 4)
    try await e.w.runUntilIdle()
    #expect(e.text == "r300c4", "editor text \(String(describing: e.text))")
    #expect(e.model.active == TableCell(row: 300, column: 4), "active \(String(describing: e.model.active))")
    let ring = try #require(ringOrigin(ringRects(e.w, width: 2)), "the cell is realised")
    #expect(ring.y >= 28 && ring.y + 24 <= 600, "the cell is on screen: \(ring)")
    #expect(e.editorHasFocus, "the editor has the focus")
    // Setting another cell cancels the first edit and begins the next.
    e.model.editing = TableCell(row: 301, column: 1)
    try await e.w.runUntilIdle()
    #expect(e.text == "r301c1" && e.model.commits.isEmpty, "the first edit was cancelled: \(e.model.commits)")
}

/// **F9** A click on another cell commits (once), makes that cell active and focuses the table. Mutation: the click leaves the
/// edit open.
@Test @MainActor func aClickElsewhereCommits() async throws {
    let e = try await Editing()
    try await e.key(returnKey); try await e.type("Z")
    e.model.events = []
    e.w.click(at: rowPoint(6, column: 1)); try await e.w.runUntilIdle()
    expectOneCommit(e.model, TableCell(row: 3, column: 2), "r3c2Z")
    #expect(e.model.active == TableCell(row: 6, column: 1) && e.tableHasFocus && e.text == nil)
    #expect(e.model.events == ["commit", "active"], "the commit is the click's first act, before the cell changes: \(e.model.events)")
}

/// **F10** A click in the empty space below the rows commits once and keeps the active cell. Mutation: the empty space has no click.
@Test @MainActor func aClickInEmptySpaceCommits() async throws {
    let e = try await Editing(rows: 5)
    try await e.key(returnKey); try await e.type("Z")
    e.w.click(at: Point(x: Pixels(650), y: Pixels(500))); try await e.w.runUntilIdle()
    expectOneCommit(e.model, TableCell(row: 3, column: 2), "r3c2Z")
    #expect(e.model.active == TableCell(row: 3, column: 2), "the active cell stays")
}

/// **F11** Focus leaving the editor commits (once) with the text; nothing else a window does (a pointer leaving, a modifier change;
/// `Window` has no key-resign event, so a window resigning key reaches no code here) commits or cancels. Mutation: focus leaving
/// cancels.
@Test @MainActor func focusLeavingTheTableCommitsButResigningKeyDoesNot() async throws {
    let e = try await Editing()
    try await e.key(returnKey); try await e.type("Z")
    _ = e.w.send(.pointerExited); _ = e.w.send(.modifiersChanged([])); e.w.tick()
    try await e.w.runUntilIdle()
    #expect(e.model.commits.isEmpty && e.text == "r3c2Z", "the edit waits: \(e.model.commits)")
    e.w.window.focus(nil); try await e.w.runUntilIdle()
    expectOneCommit(e.model, TableCell(row: 3, column: 2), "r3c2Z")
}

/// **F12** The edit survives its cell scrolling out of the window: scroll 5 000 rows away and back, the text is intact, the focus
/// is kept, the cell realised again, and the edit ends with ONE commit holding what was typed. Mutation: the editor is named
/// positionally (keyed by where it sits in the body), so its identity moves with the window.
@Test @MainActor func theEditorSurvivesScrollingItsCellOut() async throws {
    let e = try await Editing(rows: 10_000)
    try await e.key(returnKey); try await e.type("Q")
    try await scrollTable(e.w, x: 0, y: 24 * 5000)
    #expect(e.model.commits.isEmpty && e.model.editing == TableCell(row: 3, column: 2), "the edit is open")
    #expect(e.text == "r3c2Q" && e.editorHasFocus, "text and focus kept while away: \(String(describing: e.text))")
    try await scrollTable(e.w, x: 0, y: -24 * 5000)
    #expect(e.text == "r3c2Q" && e.editorHasFocus, "text and focus kept when back")
    try await e.key(returnKey)
    expectOneCommit(e.model, TableCell(row: 3, column: 2), "r3c2Q")
}

/// **F13** A keystroke into an editor whose cell is off screen reveals the cell again. Mutation: typing does not reveal.
@Test @MainActor func aKeystrokeIntoAnOffscreenEditorRevealsIt() async throws {
    let e = try await Editing(rows: 10_000)
    try await e.key(returnKey)
    try await scrollTable(e.w, x: 0, y: 24 * 5000)
    #expect(ringRects(e.w, width: 2).isEmpty, "the cell is away")
    try await e.type("R")
    #expect(e.text == "r3c2R", "the keystroke went in: \(String(describing: e.text))")
    let ring = try #require(ringOrigin(ringRects(e.w, width: 2)), "the cell is back")
    #expect(ring.y >= 28 && ring.y + 24 <= 600, "revealed: \(ring)")
}

/// **F14** ⌥Return inserts a line break and does not commit; the editor shows both lines. Mutation: ⌥Return commits.
@Test @MainActor func optionReturnInsertsALineBreak() async throws {
    let e = try await Editing()
    try await e.key(returnKey); try await e.type("Z")
    try await e.key(returnKey, .option)
    #expect(e.text == "r3c2Z\n", "text \(String(describing: e.text))")
    #expect(e.model.commits.isEmpty && e.model.editing != nil, "still editing")
    try await e.type("W")
    try await e.key(returnKey)
    expectOneCommit(e.model, TableCell(row: 3, column: 2), "r3c2Z\nW")
}

/// **F15** An edit commits even when the text is unchanged. Mutation: an unchanged edit is dropped.
@Test @MainActor func aCommitIsCalledEvenWhenTheTextIsUnchanged() async throws {
    let e = try await Editing()
    try await e.key(returnKey); try await e.key(returnKey)
    expectOneCommit(e.model, TableCell(row: 3, column: 2), "r3c2")
}

/// **F16** `isEditable` gates every way in: Return, F2 and a printable key start nothing on a cell that is not editable, and Return
/// then is the table's own. Mutation: the gate is ignored for a printable key.
@Test @MainActor func aCellThatIsNotEditableStartsNoEdit() async throws {
    let e = try await Editing(editableCell: { $0.column != 2 })
    try await e.key(returnKey); try await e.key(f2Key); try await e.type("x")
    #expect(e.model.editing == nil && e.text == nil && e.model.editingWrites.isEmpty, "no edit")
    e.w.typeKey(.rightArrow); try await e.w.runUntilIdle()   // column 3 is editable
    try await e.key(f2Key)
    #expect(e.model.editing == TableCell(row: 3, column: 3) && e.text == "r3c3", "F2 begins at an editable cell")
}

/// **F17** The editor costs one frame's rebuild per keystroke and rebuilds no more of the table: a keystroke's frames realise exactly
/// `builds x` the steady window, and cost the editor's element requests each build (the plan said "zero cells realised", which no
/// frame can meet, `TBL-M`). Mutation: a build with an open edit realises its rows twice.
@Test @MainActor func typingRebuildsOnlyTheEditor() async throws {
    let e = try await Editing(rows: 5000)
    try await e.key(returnKey)
    e.w.resetFrameWork()
    e.w.window.setNeedsRedraw(); e.w.tick()
    let editing = e.w.lastFrameWork
    #expect(editing.tableRowsRealized > 0)
    e.w.resetFrameWork()
    e.w.typeText("a"); try await e.w.runUntilIdle()
    let typed = e.w.frameWork.reduce(FrameWork(), +)
    #expect(typed.builds >= 1)
    // The window a table realises with no edit open: the reference the typing frames are held to.
    let plain = try await { () async throws -> FrameWork in
        let w = try cellTable(rows: 5000, model: CellModel())
        try await w.runUntilIdle()
        w.resetFrameWork(); w.window.setNeedsRedraw(); w.tick()
        return w.lastFrameWork
    }()
    #expect(typed.tableCellsRealized == typed.builds * plain.tableCellsRealized, "cells \(typed.tableCellsRealized) over \(typed.builds)")
    #expect(typed.tableRowsRealized == typed.builds * plain.tableRowsRealized)
    #expect(typed.elementRequests == typed.builds * editing.elementRequests, "requests \(typed.elementRequests) over \(typed.builds)")
    #expect(editing.elementRequests > plain.elementRequests && editing.elementRequests <= plain.elementRequests + 8,
            "the editor adds a few requests: \(plain.elementRequests) -> \(editing.elementRequests)")
    #expect(typed.tableDataReads <= typed.builds * (plain.tableDataReads + 1), "one verification read per build: \(typed.tableDataReads)")
}

/// **F18** An idle editor costs what an idle `TextField` does: no frames at all (the caret does not blink). Mutation: the body asks
/// another frame every build while editing.
@Test @MainActor func anIdleEditorCostsAnIdleTextField() async throws {
    let e = try await Editing()
    try await e.key(returnKey); try await e.type("ab")
    e.w.resetFrameWork()
    try await e.w.runUntilIdle()
    #expect(e.w.frameWork.reduce(FrameWork(), +).builds == 0, "frames while the editor sits idle: \(e.w.frameWork.count)")
    let field = try harnessWindow(size: sz(300, 100)) { TextField("x", text: "ab") { _ in } }
    try await field.runUntilIdle(); field.window.focus(nil)
    field.resetFrameWork(); try await field.runUntilIdle()
    #expect(field.frameWork.reduce(FrameWork(), +).builds == 0, "an idle TextField draws no frames either")
}

// MARK: - Ending an edit exactly once (the review's top risk)

/// **X1** A data reload under the edit leaves it open: the row's cell is replaced by other rows' data, the editor holds its last
/// frame, and the edit still ends in exactly one commit. Mutation: an unresolvable row cancels the edit.
@Test @MainActor func aReloadThatDropsTheRowLeavesTheEditOpenAndCommitsOnce() async throws {
    let model = CellModel(), rows = RowsModel(50)
    let w = try cellTableOver(model: model, data: { rows.rows })
    try await w.runUntilIdle()
    w.click(at: rowPoint(3, column: 2)); try await w.runUntilIdle()
    let body = try #require(w.window.focusedElement)
    let editor = GlobalElementID.child(of: body, at: 0, name: tableEditorName)
    w.typeKey(KeyEquivalent("\r")); try await w.runUntilIdle()
    w.typeText("Z"); try await w.runUntilIdle()
    rows.rows.removeAll { $0.id == 3 }
    try await w.runUntilIdle()
    #expect(model.commits.isEmpty && model.editing == TableCell(row: 3, column: 2), "the edit stays open: \(model.commits)")
    #expect(w.window.lastFocusRegistry.textTarget(for: editor)?.text == "r3c2Z" && w.window.focusedElement == editor)
    w.typeKey(KeyEquivalent("\r")); try await w.runUntilIdle()
    expectOneCommit(model, TableCell(row: 3, column: 2), "r3c2Z")
}

/// **X2** A sort under the edit: the editor follows its row to the new position and the edit ends in one commit. Mutation: the
/// editor keeps its old position.
@Test @MainActor func aSortUnderTheEditMovesTheEditorWithItsRow() async throws {
    let model = CellModel(), rows = RowsModel(50)
    let w = try cellTableOver(model: model, data: { rows.rows })
    try await w.runUntilIdle()
    w.click(at: rowPoint(3, column: 2)); try await w.runUntilIdle()
    let body = try #require(w.window.focusedElement)
    w.typeKey(KeyEquivalent("\r")); try await w.runUntilIdle()
    w.typeText("Z"); try await w.runUntilIdle()
    let before = try #require(w.window.lastHitboxes.last { $0.id == GlobalElementID.child(of: body, at: 0, name: tableEditorName) }).bounds
    rows.rows.reverse()
    try await w.runUntilIdle()
    let after = try #require(w.window.lastHitboxes.last { $0.id == GlobalElementID.child(of: body, at: 0, name: tableEditorName) }).bounds
    #expect(before.origin.y.value == 28 + 3 * 24 && after.origin.y.value == 28 + 46 * 24, "moved from \(before) to \(after)")
    #expect(model.commits.isEmpty)
    w.typeKey(KeyEquivalent("\r")); try await w.runUntilIdle()
    expectOneCommit(model, TableCell(row: 3, column: 2), "r3c2Z")
}

/// A host whose table can leave the hierarchy.
@MainActor private func toggledTable(model: CellModel, shown: ShownModel) throws -> TestWindow {
    try harnessWindow(size: sz(800, 600)) {
        VStack(spacing: Pixels(0)) {
            if shown.on {
                cellTableValue(data: CountingRows(50), model: model)
            }
        }
    }
}

@MainActor @Observable private final class ShownModel { var on = true }

/// **X3** The table leaving the hierarchy commits (once), as focus leaving does. Mutation: leaving the hierarchy does nothing
/// (no disappearance note).
@Test @MainActor func theTableLeavingTheHierarchyCommitsOnce() async throws {
    let model = CellModel(), shown = ShownModel()
    let w = try toggledTable(model: model, shown: shown)
    try await w.runUntilIdle()
    w.click(at: rowPoint(3, column: 2)); try await w.runUntilIdle()
    w.typeKey(KeyEquivalent("\r")); try await w.runUntilIdle()
    w.typeText("Z"); try await w.runUntilIdle()
    shown.on = false
    try await w.runUntilIdle()
    expectOneCommit(model, TableCell(row: 3, column: 2), "r3c2Z")
}

/// **X4** The window closing commits (once). Mutation: closing does nothing.
@Test @MainActor func theWindowClosingCommitsOnce() async throws {
    let e = try await Editing()
    try await e.key(returnKey); try await e.type("Z")
    e.w.window.runDisappearancesForClose()
    expectOneCommit(e.model, TableCell(row: 3, column: 2), "r3c2Z")
    e.w.window.runDisappearancesForClose()
    #expect(e.model.commits.count == 1, "a second close finds nothing")
}

/// **X6** A second Return that reaches the editor before the next frame (the edit just ended, its editor not yet gone) commits
/// nothing more and moves nothing more. Mutation: `end` does not check the edit is still open.
@Test @MainActor func aSecondReturnBeforeTheNextFrameCommitsNothingMore() async throws {
    let e = try await Editing()
    try await e.key(returnKey); try await e.type("Z")
    #expect(rawCellKey(e.w, returnKey))
    #expect(rawCellKey(e.w, returnKey), "the editor still takes the key")
    try await e.w.runUntilIdle()
    expectOneCommit(e.model, TableCell(row: 3, column: 2), "r3c2Z")
    #expect(e.model.active == TableCell(row: 4, column: 2), "moved once: \(String(describing: e.model.active))")
}

/// **X5** An edit that commits through Return is not committed again by what follows: the table losing the focus afterwards, the
/// window closing, and the table leaving all find the edit already ended. Mutation: an ended edit stays in the table's state and
/// reads as open.
@Test @MainActor func anEndedEditNeverCommitsAgain() async throws {
    let e = try await Editing()
    try await e.key(returnKey); try await e.type("Z"); try await e.key(returnKey)
    e.w.window.focus(nil); try await e.w.runUntilIdle()
    e.w.window.runDisappearancesForClose()
    expectOneCommit(e.model, TableCell(row: 3, column: 2), "r3c2Z")
}

/// **F19** A cell that is not editable leaves Return to the table: with a `contextMenu` primary action, Return on such a cell runs
/// the action with the selection, as PR C's Return does, and no edit begins. Mutation: cell mode swallows the keys it does not take.
@Test @MainActor func returnOnACellThatIsNotEditableRunsThePrimaryAction() async throws {
    let model = CellModel(), sel = TableSel()
    var acted: [Set<Int>] = []
    let w = try harnessWindow(size: sz(800, 600)) {
        cellTableValue(data: CountingRows(50), model: model, selection: sel, editableCell: { _ in false })
            .contextMenu(forSelectionType: Int.self, menu: { _ in Button("Act") {} }, primaryAction: { acted.append($0) })
    }
    try await w.runUntilIdle()
    w.click(at: rowPoint(3, column: 2)); try await w.runUntilIdle()
    w.typeKey(KeyEquivalent("\r")); try await w.runUntilIdle()
    #expect(acted == [[3]], "acted \(acted)")
    #expect(model.editing == nil)
}
