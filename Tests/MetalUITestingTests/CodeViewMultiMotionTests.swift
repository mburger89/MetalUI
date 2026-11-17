import Testing
import Foundation
import MetalUI
import MetalUIScene
import MetalUITesting

// Motion and editing over every selection (`CV-BH`, `CV-BI`, record 345): each motion maps every selection's head and
// normalizes, vertical motion keeps a goal x per selection, delete / newline / indent / outdent / cut / paste are one
// edit over all of them, copy joins them, and Escape collapses to the primary. PLAIN imports; the harness text
// system; counters, never a clock (the gated timing aside).

@MainActor private func at(_ buffer: CodeBuffer, _ row: Int, _ column: Int) -> Int {
    buffer.snapshot().offset(of: CodePoint(row: row, column: column))
}

/// Carets at `points` (row, column), the one at `primary` (an index into `points`) the primary.
@MainActor private func carets(_ buffer: CodeBuffer, _ points: [(Int, Int)], primary: Int = 0) {
    buffer.selectionState.setSelections(points.map { CodeSelection(caret: at(buffer, $0.0, $0.1)) }, primary: primary)
}

/// Where each selection's head is, as `[row, column]`.
@MainActor private func heads(_ buffer: CodeBuffer) -> [[Int]] {
    let snap = buffer.snapshot()
    return buffer.selections.map { let p = snap.point(at: $0.head); return [p.row, p.column] }
}

@MainActor private func texts(_ buffer: CodeBuffer) -> String { buffer.snapshot().text }

private let abc = "abc\ndef\nghi\n"

// MARK: Motion

/// **1** Left and right move every caret, wrap at line ends and the document's edges, and keep the primary. With
/// three carets. **Mutation:** moving only the primary (`selection`, not each of `sels`) leaves two carets where they
/// were; a wrap computed once for all (the first caret's) puts the others at the wrong row.
@Test @MainActor func leftAndRightMoveEveryCaretAndWrap() throws {
    let (w, buffer) = try editingWindow(abc)
    defer { withExtendedLifetime(w) {} }
    carets(buffer, [(0, 0), (1, 0), (2, 2)], primary: 1)
    w.typeKey(.leftArrow)
    #expect(heads(buffer) == [[0, 0], [0, 3], [2, 1]], "the first stays at the document start, the second wraps up: \(heads(buffer))")
    #expect(buffer.selectionState.primaryIndex == 1, "the primary is still the one that wrapped")
    carets(buffer, [(0, 3), (1, 3), (2, 0)], primary: 2)
    w.typeKey(.rightArrow)
    #expect(heads(buffer) == [[1, 0], [2, 0], [2, 1]], "two wrap down, the third steps: \(heads(buffer))")
    #expect(buffer.selectionState.primaryIndex == 2)
}

/// **2** Carets that meet merge into one, and the primary is the survivor it merged into. **Mutation:** assigning
/// `selections` (primary 0) instead of `setSelections(_, primary:)` makes the first caret the primary (index 0).
@Test @MainActor func caretsThatMeetMergeAndKeepThePrimary() throws {
    let (w, buffer) = try editingWindow(abc)
    defer { withExtendedLifetime(w) {} }
    carets(buffer, [(0, 0), (0, 1), (2, 1)], primary: 2)
    w.typeKey(.leftArrow)
    #expect(heads(buffer) == [[0, 0], [2, 0]], "the first two met: \(heads(buffer))")
    #expect(buffer.selectionState.primaryIndex == 1, "the primary is the third caret, now second")
    carets(buffer, [(0, 0), (0, 1)], primary: 1)
    w.typeKey(.leftArrow)
    #expect(heads(buffer) == [[0, 0]] && buffer.selectionState.primaryIndex == 0, "merged into the one: \(heads(buffer))")
}

/// **3** Extending keeps every anchor and moves every head; a plain arrow over ranges collapses each to its edge.
/// **Mutation:** `extend ? s.anchor : target` replaced by the primary's anchor for all.
@Test @MainActor func extendKeepsEachAnchorAndAPlainArrowCollapsesEachToItsEdge() throws {
    let (w, buffer) = try editingWindow(abc)
    defer { withExtendedLifetime(w) {} }
    carets(buffer, [(0, 1), (1, 2)])
    w.typeKey(.rightArrow, modifierFlags: .shift)
    #expect(buffer.selections == [CodeSelection(anchor: at(buffer, 0, 1), head: at(buffer, 0, 2)),
                                  CodeSelection(anchor: at(buffer, 1, 2), head: at(buffer, 1, 3))])
    w.typeKey(.rightArrow, modifierFlags: .shift)
    #expect(buffer.selections == [CodeSelection(anchor: at(buffer, 0, 1), head: at(buffer, 0, 3)),
                                  CodeSelection(anchor: at(buffer, 1, 2), head: at(buffer, 2, 0))], "the second wraps its head")
    w.typeKey(.leftArrow)
    #expect(heads(buffer) == [[0, 1], [1, 2]], "left puts each caret at its range's start: \(heads(buffer))")
}

/// **4** Word, line and document motions run per selection: smart Home goes to the first non-blank and then the
/// start; End goes to the line end; the document motions merge everything into one caret. **Mutation:** the document
/// motions not merging (still two selections).
@Test @MainActor func wordLineAndDocumentMotionsRunPerSelection() throws {
    let (w, buffer) = try editingWindow("foo bar\n  ab\n  cd\n")
    defer { withExtendedLifetime(w) {} }
    carets(buffer, [(0, 0), (1, 4)])
    w.typeKey(.rightArrow, modifierFlags: codeWord)
    #expect(heads(buffer) == [[0, 3], [2, 0]], "a word right; the end of a line wraps: \(heads(buffer))")
    carets(buffer, [(1, 4), (2, 3)])
    w.typeKey(.home)
    #expect(heads(buffer) == [[1, 2], [2, 2]], "smart Home: the first non-blank: \(heads(buffer))")
    w.typeKey(.home)
    #expect(heads(buffer) == [[1, 0], [2, 0]], "and then the start")
    w.typeKey(.end)
    #expect(heads(buffer) == [[1, 4], [2, 4]])
    w.typeKey(.end, modifierFlags: codePrimary)
    #expect(heads(buffer).count == 1 && buffer.primarySelection.head == buffer.snapshot().utf8Count, "document end merges: \(heads(buffer))")
    carets(buffer, [(0, 3), (1, 2)])
    w.typeKey(.home, modifierFlags: codePrimary)
    #expect(heads(buffer) == [[0, 0]], "document start merges")
}

private let ragged = "abcdefghij\nab\nabcdefghij\nabcde\nabcdefghij\nx\n"

/// **5** Vertical motion keeps a goal x for each caret: two carets at columns 8 and 4 pass through a short line
/// and come back to the columns they left. A single remembered x (the primary's) would put the second at 8; none
/// would put the first at the short line's column. **Mutation:** `previous?[i]` replaced by `previous?[0]`; `goalXs`
/// not written (the second step recomputes from the clamped column).
@Test @MainActor func verticalMotionKeepsAGoalXForEachCaretAcrossShortLines() throws {
    let (w, buffer) = try editingWindow(ragged)
    defer { withExtendedLifetime(w) {} }
    carets(buffer, [(0, 8), (2, 4)])
    w.typeKey(.downArrow)
    #expect(heads(buffer) == [[1, 2], [3, 4]], "clamped to the short line, the other kept: \(heads(buffer))")
    w.typeKey(.downArrow)
    #expect(heads(buffer) == [[2, 8], [4, 4]], "each returns to the column it left: \(heads(buffer))")
    w.typeKey(.upArrow)
    w.typeKey(.upArrow)
    #expect(heads(buffer) == [[0, 8], [2, 4]], "and back up: \(heads(buffer))")
    w.typeKey(.rightArrow)
    w.typeKey(.downArrow)
    #expect(heads(buffer) == [[1, 2], [3, 5]], "a horizontal move ends the run: the goals are the new columns \(heads(buffer))")
}

/// **6** Vertical carets that land together merge; at the document's edges a caret goes to the start or end.
/// **Mutation:** the document-start branch (`row < 0`) leaves the caret where it was.
@Test @MainActor func verticalMotionMergesAndGoesToTheDocumentEdges() throws {
    let (w, buffer) = try editingWindow(ragged)
    defer { withExtendedLifetime(w) {} }
    carets(buffer, [(0, 5), (0, 8)])
    w.typeKey(.downArrow)
    #expect(heads(buffer) == [[1, 2]], "both clamped to the same column and merged: \(heads(buffer))")
    carets(buffer, [(0, 3), (1, 1)])
    w.typeKey(.upArrow)
    #expect(heads(buffer) == [[0, 0], [0, 1]], "the first goes to the start, the second to its column: \(heads(buffer))")
    carets(buffer, [(4, 3), (5, 1)])
    w.typeKey(.downArrow)
    #expect(heads(buffer).count == 2 && heads(buffer)[0] == [5, 1], "one to the last row, the other to the end: \(heads(buffer))")
}

/// **7** A page motion moves every caret by the same number of rows, and a line with a tab or a wide scalar (not
/// plain ASCII) goes through the layout. **Mutation:** the page rows computed per caret from its own row.
@Test @MainActor func pageMotionMovesEveryCaretAndNonAsciiLinesUseTheLayout() throws {
    let (w, buffer) = try editingWindow(codeText(lines: 60))
    defer { withExtendedLifetime(w) {} }
    carets(buffer, [(0, 3), (5, 2)])
    w.typeKey(.pageDown)
    let moved = heads(buffer)
    #expect(moved.count == 2 && moved[0][0] > 2 && moved[1][0] - moved[0][0] == 5, "the same rows for both: \(moved)")
    // Row 1 of `codeText` starts with a tab; row 3 has emoji: both are laid out, never an ASCII column.
    carets(buffer, [(0, 4), (2, 4)])
    w.typeKey(.downArrow)
    let rows = heads(buffer).map { $0[0] }
    #expect(rows == [1, 3], "\(heads(buffer))")
}

// MARK: Editing

/// **8** Backspace at three carets removes one character at each as one undo step, and undo restores every caret
/// and the primary; redo does the same. **Mutation:** deleting only the primary's range; the undo selections stored
/// without the primary index.
@Test @MainActor func backspaceAtSeveralCaretsIsOneStepAndUndoRestoresAllCarets() throws {
    let (w, buffer) = try editingWindow(abc)
    defer { withExtendedLifetime(w) {} }
    carets(buffer, [(0, 2), (1, 2), (2, 2)], primary: 1)
    let before = buffer.selections
    w.typeKey(.delete)
    #expect(texts(buffer) == "ac\ndf\ngi\n")
    #expect(heads(buffer) == [[0, 1], [1, 1], [2, 1]] && buffer.selectionState.primaryIndex == 1)
    w.typeKey("z", modifierFlags: codePrimary)
    #expect(texts(buffer) == abc, "one undo step for all three")
    #expect(buffer.selections == before && buffer.selectionState.primaryIndex == 1, "every caret and the primary are back: \(heads(buffer))")
    w.typeKey("z", modifierFlags: [codePrimary, .shift])
    #expect(texts(buffer) == "ac\ndf\ngi\n" && buffer.selectionState.primaryIndex == 1, "redo too")
}

/// **9** Forward delete, and a backspace at a line start joining lines, at several carets; a caret that has nothing
/// to remove (the document start) is skipped while the others apply. **Mutation:** a no-op caret ending the command
/// (`guard !edits.isEmpty` replaced by a return on the first nil range).
@Test @MainActor func deleteForwardAndAtLineStartsAndATrivialCaret() throws {
    let (w, buffer) = try editingWindow(abc)
    defer { withExtendedLifetime(w) {} }
    carets(buffer, [(0, 0), (1, 0), (2, 3)])
    w.typeKey(.delete)
    #expect(texts(buffer) == "abcdef\ngh\n", "the first caret has nothing before it, the second joins the lines, the third removes `i`: \(texts(buffer).debugDescription)")
    #expect(heads(buffer) == [[0, 0], [0, 3], [1, 2]], "\(heads(buffer))")
}

/// **10** Overlapping ranges are unioned into one edit: a selection and a caret whose word-backward range overlaps
/// it delete the union, once, and the carets merge. **Mutation:** the union keeping the first range's end (no `max`).
@Test @MainActor func overlappingDeleteRangesMergeIntoOne() throws {
    let (w, buffer) = try editingWindow("aaaa bbbb cccc\n")
    defer { withExtendedLifetime(w) {} }
    buffer.selectionState.setSelections([CodeSelection(anchor: 2, head: 7), CodeSelection(caret: 9)], primary: 1)
    w.typeKey(.delete, modifierFlags: codeWord)
    #expect(texts(buffer) == "aa cccc\n", "[2,7) and [5,9) are [2,9): \(texts(buffer).debugDescription)")
    #expect(buffer.selections == [CodeSelection(caret: 2)] && buffer.selectionState.primaryIndex == 0)
}

/// **11** Typing and backspacing at several carets coalesce exactly as at one (Alloy's answer 9): a run of typed
/// characters is one undo step and a run of backspaces is one, and a different kind starts a new one. Undo restores
/// every caret each time. **Mutation:** `breakUndoCoalescing()` after a multi-caret `insert` (one step per key).
@Test @MainActor func typingAndBackspacingAtSeveralCaretsCoalesceLikeOneCaret() throws {
    let (w, buffer) = try editingWindow(abc)
    defer { withExtendedLifetime(w) {} }
    carets(buffer, [(0, 3), (1, 3), (2, 3)], primary: 2)
    w.typeText("xyz")
    #expect(texts(buffer) == "abcxyz\ndefxyz\nghixyz\n")
    w.typeKey(.delete)
    w.typeKey(.delete)
    #expect(texts(buffer) == "abcx\ndefx\nghix\n")
    w.typeKey("z", modifierFlags: codePrimary)
    #expect(texts(buffer) == "abcxyz\ndefxyz\nghixyz\n", "the two backspaces were one step")
    w.typeKey("z", modifierFlags: codePrimary)
    #expect(texts(buffer) == abc, "and the three typed characters one step")
    #expect(heads(buffer) == [[0, 3], [1, 3], [2, 3]] && buffer.selectionState.primaryIndex == 2, "every caret and the primary: \(heads(buffer))")
}

/// **12** Return at several carets breaks each line and keeps each line's indentation, one undo step; Tab inserts
/// the indent unit at each caret, and over several-row selections indents every touched row once; Shift-Tab removes
/// one unit from each touched row. **Mutation:** the whitespace taken from the primary's line for all.
@Test @MainActor func newlineIndentAndOutdentAtSeveralCarets() throws {
    let (w, buffer) = try editingWindow("  ab\n\tcd\nef\n")
    defer { withExtendedLifetime(w) {} }
    carets(buffer, [(0, 3), (1, 2), (2, 1)])
    w.typeKey(.return)
    #expect(texts(buffer) == "  a\n  b\n\tc\n\td\ne\nf\n", "each keeps its own indentation: \(texts(buffer).debugDescription)")
    w.typeKey("z", modifierFlags: codePrimary)
    #expect(texts(buffer) == "  ab\n\tcd\nef\n", "one step")
    carets(buffer, [(0, 1), (1, 1), (2, 0)])
    w.typeKey(.tab)
    #expect(texts(buffer) == " \t ab\n\t\tcd\n\tef\n", "a tab at each caret: \(texts(buffer).debugDescription)")
}

/// **13** A selection over several rows makes Tab and Shift-Tab act on rows, once for rows several selections share.
/// **Mutation:** the rows not unioned (a shared row indented twice).
@Test @MainActor func indentAndOutdentOverSeveralSelectionsTouchEachRowOnce() throws {
    let (w, buffer) = try editingWindow("a\nb\nc\nd\n")
    defer { withExtendedLifetime(w) {} }
    buffer.selectionState.setSelections([CodeSelection(anchor: at(buffer, 0, 0), head: at(buffer, 1, 1)),
                                         CodeSelection(anchor: at(buffer, 1, 0), head: at(buffer, 2, 1)),
                                         CodeSelection(caret: at(buffer, 3, 1))], primary: 0)
    // Overlapping selections normalise: rows 0..2 are one selection, the caret on row 3 another.
    w.typeKey(.tab)
    #expect(texts(buffer) == "\ta\n\tb\n\tc\n\td\n", "every touched row once: \(texts(buffer).debugDescription)")
    w.typeKey(.tab, modifierFlags: .shift)
    #expect(texts(buffer) == "a\nb\nc\nd\n", "and one unit off each")
    w.typeKey("z", modifierFlags: codePrimary)
    #expect(texts(buffer) == "\ta\n\tb\n\tc\n\td\n", "an outdent is one step")
}

// MARK: Clipboard

/// **14** Copy joins every selection's text with the buffer's line ending; a caret contributes its whole line (once
/// per line, without its break); nothing is edited. **Mutation:** the primary's text alone; carets contributing their
/// line each (the same line twice).
@Test @MainActor func copyJoinsSelections() throws {
    let (w, buffer) = try editingWindow("one\ntwo\nthree\n")
    defer { withExtendedLifetime(w) {} }
    carets(buffer, [(0, 1), (2, 2)])
    w.typeKey("c", modifierFlags: codePrimary)
    #expect(w.platformWindow.clipboard == "one\nthree", "\(String(describing: w.platformWindow.clipboard))")
    buffer.selectionState.setSelections([CodeSelection(anchor: at(buffer, 0, 0), head: at(buffer, 0, 2)), CodeSelection(caret: at(buffer, 1, 1))], primary: 0)
    w.typeKey("c", modifierFlags: codePrimary)
    #expect(w.platformWindow.clipboard == "on\ntwo", "a range and a caret: \(String(describing: w.platformWindow.clipboard))")
    carets(buffer, [(0, 0), (0, 2)])
    w.typeKey("c", modifierFlags: codePrimary)
    #expect(w.platformWindow.clipboard == "one", "two carets on one line contribute it once")
    #expect(texts(buffer) == "one\ntwo\nthree\n")
    let (w2, crlf) = try editingWindow("a\r\nb\r\n")
    defer { withExtendedLifetime(w2) {} }
    carets(crlf, [(0, 0), (1, 0)])
    w2.typeKey("c", modifierFlags: codePrimary)
    #expect(w2.platformWindow.clipboard == "a\r\nb", "joined with the buffer's ending: \(String(describing: w2.platformWindow.clipboard))")
}

/// **15** Cut copies the same text and removes each range (a caret's whole line), as one undo step that restores
/// every caret; adjacent lines are removed together. **Mutation:** removing only the primary's range.
@Test @MainActor func cutRemovesEverySelectionAsOneStep() throws {
    let (w, buffer) = try editingWindow("one\ntwo\nthree\nfour\n")
    defer { withExtendedLifetime(w) {} }
    carets(buffer, [(0, 1), (2, 1)], primary: 1)
    let before = buffer.selections
    w.typeKey("x", modifierFlags: codePrimary)
    #expect(w.platformWindow.clipboard == "one\nthree" && texts(buffer) == "two\nfour\n", "\(texts(buffer).debugDescription)")
    w.typeKey("z", modifierFlags: codePrimary)
    #expect(texts(buffer) == "one\ntwo\nthree\nfour\n" && buffer.selections == before && buffer.selectionState.primaryIndex == 1)
    carets(buffer, [(1, 0), (2, 0)])
    w.typeKey("x", modifierFlags: codePrimary)
    #expect(texts(buffer) == "one\nfour\n" && w.platformWindow.clipboard == "two\nthree", "touching ranges: \(texts(buffer).debugDescription)")
    w.typeKey("z", modifierFlags: codePrimary)
    buffer.selectionState.setSelections([CodeSelection(anchor: at(buffer, 0, 1), head: at(buffer, 0, 3)), CodeSelection(anchor: at(buffer, 1, 0), head: at(buffer, 1, 1))], primary: 0)
    w.typeKey("x", modifierFlags: codePrimary)
    #expect(texts(buffer) == "o\nwo\nthree\nfour\n" && w.platformWindow.clipboard == "ne\nt", "ranges: \(texts(buffer).debugDescription)")
}

/// **16** A paste of as many lines as selections gives each its line (a trailing break ignored); any other count
/// gives each the whole text; one selection always takes the whole text. One undo step restores every caret.
/// **Mutation:** the count test `==` made `<=`; a spread with one selection.
@Test @MainActor func pasteSpreadsNLinesOverNSelections() throws {
    let (w, buffer) = try editingWindow("1\n2\n3\n")
    defer { withExtendedLifetime(w) {} }
    carets(buffer, [(0, 1), (1, 1), (2, 1)], primary: 1)
    let before = buffer.selections
    w.setClipboard(text: "A\nB\nC")
    w.typeKey("v", modifierFlags: codePrimary)
    #expect(texts(buffer) == "1A\n2B\n3C\n", "a line each: \(texts(buffer).debugDescription)")
    #expect(heads(buffer) == [[0, 2], [1, 2], [2, 2]] && buffer.selectionState.primaryIndex == 1)
    w.typeKey("z", modifierFlags: codePrimary)
    #expect(texts(buffer) == "1\n2\n3\n" && buffer.selections == before && buffer.selectionState.primaryIndex == 1)
    w.setClipboard(text: "A\nB\nC\n")
    w.typeKey("v", modifierFlags: codePrimary)
    #expect(texts(buffer) == "1A\n2B\n3C\n", "one trailing break is ignored")
    w.typeKey("z", modifierFlags: codePrimary)
    w.setClipboard(text: "A\nB")
    w.typeKey("v", modifierFlags: codePrimary)
    #expect(texts(buffer) == "1A\nB\n2A\nB\n3A\nB\n", "two lines over three: the whole text at each: \(texts(buffer).debugDescription)")
    w.typeKey("z", modifierFlags: codePrimary)
    w.setClipboard(text: "X")
    w.typeKey("v", modifierFlags: codePrimary)
    #expect(texts(buffer) == "1X\n2X\n3X\n")
    w.typeKey("z", modifierFlags: codePrimary)
    carets(buffer, [(0, 1)])
    w.setClipboard(text: "A\nB")
    w.typeKey("v", modifierFlags: codePrimary)
    #expect(texts(buffer) == "1A\nB\n2\n3\n", "one selection takes the whole text")
}

/// **17** A copy of several carets pasted over as many carets spreads back, the round trip VS Code makes.
@Test @MainActor func aCopyOfSeveralCaretsPastesBackOneLineEach() throws {
    let (w, buffer) = try editingWindow("one\ntwo\nthree\n")
    defer { withExtendedLifetime(w) {} }
    carets(buffer, [(0, 0), (1, 0), (2, 0)])
    w.typeKey("c", modifierFlags: codePrimary)
    #expect(w.platformWindow.clipboard == "one\ntwo\nthree")
    w.typeKey("v", modifierFlags: codePrimary)
    #expect(texts(buffer) == "oneone\ntwotwo\nthreethree\n", "\(texts(buffer).debugDescription)")
}

// MARK: Escape

/// **18** Escape with several selections collapses to the primary (its range kept) and is claimed; with one it is
/// declined, so it keeps travelling. An `onKeyPress` handling Escape runs first and keeps the selections.
/// **Mutation:** collapsing with one selection claims the key (handled true); collapsing to the first selection
/// instead of the primary; the collapse running before `onKeyPress`.
@Test @MainActor func escapeIsClaimedOnlyWithSeveralSelections() throws {
    final class Model { var handle = false }
    let model = Model()
    let buffer = CodeBuffer("abc\ndef\nghi\n")
    let w = try harnessWindow(size: sz(400, 200)) {
        CodeView(buffer: buffer, decorations: CodeDecorations(buffer: buffer)).font(size: 12).showsLineNumbers(false)
            .onKeyPress(.escape) { model.handle ? .handled : .ignored }
    }
    defer { withExtendedLifetime(w) {} }
    w.click(at: pt(60, 6))
    func escape() -> Bool {
        let event = KeyEvent(charactersIgnoringModifiers: "\u{1b}", characters: "\u{1b}", modifiers: [], timestamp: w.now)
        return w.send(.keyDown(event))
    }
    buffer.selectionState.setSelections([CodeSelection(caret: 1), CodeSelection(anchor: 5, head: 7), CodeSelection(caret: 9)], primary: 1)
    model.handle = true
    #expect(escape(), "the app's handler claimed it")
    #expect(buffer.selections.count == 3, "and the selections are untouched")
    model.handle = false
    #expect(escape(), "claimed by the view")
    #expect(buffer.selections == [CodeSelection(anchor: 5, head: 7)], "the primary alone, keeping its range: \(buffer.selections)")
    #expect(!escape(), "with one selection the key is declined")
    #expect(buffer.selections == [CodeSelection(anchor: 5, head: 7)], "and changes nothing")
}

// MARK: Cost and timing

private struct Cost: Equatable, CustomStringConvertible {
    var requests = 0, hits = 0, misses = 0, ineligible = 0, frames = 0
    init(requests: Int, hits: Int, misses: Int, ineligible: Int, frames: Int) {
        self.requests = requests; self.hits = hits; self.misses = misses; self.ineligible = ineligible; self.frames = frames
    }
    /// The same work per frame (off Darwin the number of frames a keystroke spans depends on the main-actor hop and
    /// the blink timer, so totals are compared per frame there).
    func perFrameEquals(_ o: Cost) -> Bool {
        frames > 0 && o.frames > 0
            && requests * o.frames == o.requests * frames && hits * o.frames == o.hits * frames
            && misses * o.frames == o.misses * frames && ineligible * o.frames == o.ineligible * frames
    }
    var description: String { "requests \(requests) hits \(hits) misses \(misses) ineligible \(ineligible) frames \(frames)" }
    init(_ f: FrameWork, frames: Int) {
        requests = f.elementRequests; hits = f.retainedHits; misses = f.retainedMisses; ineligible = f.retainedIneligible
        self.frames = frames
    }
}

private struct Card: Component, @MainActor Equatable {
    let buffer: CodeBuffer
    let decorations: CodeDecorations
    var content: some ElementGroup {
        CodeView(buffer: buffer, decorations: decorations).font(size: 12).showsLineNumbers(false).codeCaretBlink(.off)
    }
    static func == (l: Card, r: Card) -> Bool { l.buffer === r.buffer && l.decorations === r.decorations }
}

private enum Keystroke: String, CaseIterable {
    case typed, backspace, right, down, newline, tab, paste
}

/// The work of one `key` with `count` carets, one to a row from row 0 at column 3, the first the primary.
@MainActor private func cost(of key: Keystroke, carets count: Int) async throws -> Cost {
    let buffer = CodeBuffer(codeText(lines: 80))
    let decorations = CodeDecorations(buffer: buffer)
    let w = try harnessWindow(size: sz(400, 200)) {
        Card(buffer: buffer, decorations: decorations).equatable().frame(width: Pixels(380), height: Pixels(180))
    }
    defer { withExtendedLifetime(w) {} }
    w.click(at: pt(60, 6))
    let snap = buffer.snapshot()
    buffer.selectionState.setSelections((0..<count).map { CodeSelection(caret: snap.offset(of: CodePoint(row: $0, column: 3))) }, primary: 0)
    w.setClipboard(text: "pasted")
    for _ in 0..<4 { w.window.setNeedsRedraw(); try await w.runUntilIdle() }
    w.resetFrameWork()
    switch key {
    case .typed: w.typeText("a")
    case .backspace: w.typeKey(.delete)
    case .right: w.typeKey(.rightArrow)
    case .down: w.typeKey(.downArrow)
    case .newline: w.typeKey(.return)
    case .tab: w.typeKey(.tab)
    case .paste: w.typeKey("v", modifierFlags: codePrimary)
    }
    try await w.runUntilIdle()
    return Cost(totalWork(w), frames: w.frameWork.count)
}

/// **20** A keystroke frame costs the same with 3 and 50 carets as with 1 caret, for every command that now runs
/// over all selections, and the one-caret literal is what master measured (`typed`: the `CV-BG` literal; the keys are
/// measured on master c9b7c7c0 at the same fixture: each is 1 request, 0 hits, 1 miss, 0 ineligible, 1 frame). **Mutation:** a per-caret element or a retention taint in the multi path.
@Test @MainActor func aKeystrokeCostsWhatItDidWithOneCaretWhateverTheCaretCount() async throws {
    for key in Keystroke.allCases {
        let one = try await cost(of: key, carets: 1)
        #if canImport(Darwin)
        let master = Cost(requests: 1, hits: 0, misses: 1, ineligible: 0, frames: 1)
        #expect(one == master, "\(key.rawValue), 1 caret: \(one)")
        #endif
        for n in [3, 50] {
            let many = try await cost(of: key, carets: n)
            #if canImport(Darwin)
            #expect(many == one, "\(key.rawValue), \(n) carets: \(many) vs one caret \(one)")
            #else
            #expect(many.perFrameEquals(one), "\(key.rawValue), \(n) carets: \(many) vs one caret \(one)")
            #endif
        }
    }
}

/// **21** (gated, release: `METALUI_RUN_CODE_PERF=1 swift test -c release --filter tenThousandCaretsTakeOneKeystrokeUnderAFrame`)
/// 10 000 carets on 10 000 lines: one typed character, one backspace and one arrow, each edit + normalize + the
/// frame's plan within 16 ms. Prints the measured times.
@Test(.enabled(if: ProcessInfo.processInfo.environment["METALUI_RUN_CODE_PERF"] == "1")) @MainActor
func tenThousandCaretsTakeOneKeystrokeUnderAFrame() async throws {
    let rows = 10_000
    let buffer = CodeBuffer(String(repeating: "abcdefgh\n", count: rows))
    let w = try harnessWindow(size: sz(400, 200)) {
        CodeView(buffer: buffer, decorations: CodeDecorations(buffer: buffer)).font(size: 12).showsLineNumbers(false)
    }
    defer { withExtendedLifetime(w) {} }
    w.click(at: pt(60, 6))
    buffer.selectionState.setSelections((0..<rows).map { CodeSelection(caret: $0 * 9 + 3) }, primary: 0)
    for _ in 0..<4 { w.window.setNeedsRedraw(); try await w.runUntilIdle() }
    func time(_ label: String, _ body: () -> Void) -> Double {
        let start = ContinuousClock.now
        body()
        let d = ContinuousClock.now - start
        let ms = Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
        print("PERF \(label): \(ms) ms")
        return ms
    }
    let typed = time("typed char, 10000 carets") { w.typeText("x") }
    let back = time("backspace, 10000 carets") { w.typeKey(.delete) }
    let right = time("arrow right, 10000 carets") { w.typeKey(.rightArrow) }
    let down = time("arrow down, 10000 carets") { w.typeKey(.downArrow) }
    #expect(buffer.selections.count == rows)
    #expect(typed <= 16 && back <= 16 && right <= 16 && down <= 16, "typed \(typed), backspace \(back), right \(right), down \(down)")
}
