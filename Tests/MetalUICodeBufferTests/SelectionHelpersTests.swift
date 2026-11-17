import Testing
@testable import MetalUICodeBuffer

// The selection helpers on `CodeSelectionState` (`CV-BJ`, record 345): add next occurrence, skip, select all, add a caret
// above or below, collapse to the primary. Buffer-only; the view's reveal is in `CodeViewSelectionHelpersTests`.

@MainActor
struct SelectionHelpersTests {
    struct Case: Sendable, CustomTestStringConvertible {
        var name: String
        var text: String
        /// The starting selections; the first is the primary.
        var start: [Range<Int>]
        /// `add`, `skip` or `all`, run in order.
        var steps: [String]
        var expected: [Range<Int>]
        var primary: Int
        var testDescription: String { name }
    }

    nonisolated static let cases: [Case] = [
        Case(name: "a caret selects its word", text: "foo bar foo baz foo", start: [1..<1], steps: ["add"], expected: [0..<3], primary: 0),
        Case(name: "a second add takes the next word", text: "foo bar foo baz foo", start: [1..<1], steps: ["add", "add"], expected: [0..<3, 8..<11], primary: 1),
        Case(name: "three adds take all three", text: "foo bar foo baz foo", start: [1..<1], steps: ["add", "add", "add"], expected: [0..<3, 8..<11, 16..<19], primary: 2),
        Case(name: "a fourth add wraps onto selected ranges and changes nothing", text: "foo bar foo baz foo", start: [1..<1],
             steps: ["add", "add", "add", "add"], expected: [0..<3, 8..<11, 16..<19], primary: 2),
        Case(name: "a word search skips a longer word containing it", text: "foo foobar foo", start: [1..<1], steps: ["add", "add"], expected: [0..<3, 11..<14], primary: 1),
        Case(name: "an exact selection search does not need whole words", text: "foo foobar", start: [0..<3], steps: ["add"], expected: [0..<3, 4..<7], primary: 1),
        Case(name: "the search is case-sensitive", text: "Foo foo Foo", start: [0..<3], steps: ["add"], expected: [0..<3, 8..<11], primary: 1),
        Case(name: "the search wraps past the end", text: "foo bar foo", start: [8..<11], steps: ["add"], expected: [0..<3, 8..<11], primary: 0),
        Case(name: "no match changes nothing", text: "abc def", start: [0..<3], steps: ["add"], expected: [0..<3], primary: 0),
        Case(name: "no word at a caret changes nothing", text: "ab  cd", start: [3..<3], steps: ["add"], expected: [3..<3], primary: 0),
        Case(name: "an overlapping match is skipped", text: "aaa", start: [0..<2], steps: ["add"], expected: [0..<2], primary: 0),
        Case(name: "a multi-line selection matches across lines", text: "a\nb\na\nb", start: [0..<3], steps: ["add"], expected: [0..<3, 4..<7], primary: 1),
        Case(name: "a word with a non-ASCII scalar is one word", text: "caf\u{E9} caf\u{E9}s caf\u{E9}", start: [2..<2], steps: ["add", "add"], expected: [0..<5, 13..<18], primary: 1),
        Case(name: "an underscore and digits are word characters", text: "a_1 a_1x a_1", start: [1..<1], steps: ["add", "add"], expected: [0..<3, 9..<12], primary: 1),
        Case(name: "skip drops the primary and adds the next", text: "foo foo foo", start: [1..<1], steps: ["add", "add", "skip"], expected: [0..<3, 8..<11], primary: 1),
        Case(name: "skip from a selection moves the one selection on", text: "ab x ab", start: [0..<2], steps: ["skip"], expected: [5..<7], primary: 0),
        Case(name: "skip with a single match keeps it", text: "ab x", start: [0..<2], steps: ["skip"], expected: [0..<2], primary: 0),
        Case(name: "select all takes every occurrence", text: "foo bar foo bar foo", start: [0..<3], steps: ["all"], expected: [0..<3, 8..<11, 16..<19], primary: 0),
        Case(name: "select all keeps the primary on its own match", text: "foo foo foo", start: [4..<7], steps: ["all"], expected: [0..<3, 4..<7, 8..<11], primary: 1),
        Case(name: "select all from a caret uses whole words", text: "foo foobar foo", start: [1..<1], steps: ["all"], expected: [0..<3, 11..<14], primary: 0),
        Case(name: "select all with no match changes nothing", text: "ab  cd", start: [3..<3], steps: ["all"], expected: [3..<3], primary: 0),
        Case(name: "select all replaces other selections", text: "foo x foo y", start: [0..<3, 6..<7], steps: ["all"], expected: [0..<3, 6..<9], primary: 0),
    ]

    private func run(_ c: Case) -> (CodeSelectionState, CodeBuffer) {
        let b = CodeBuffer(c.text)
        let state = b.selectionState
        state.setSelections(c.start.map { CodeSelection(anchor: $0.lowerBound, head: $0.upperBound) }, primary: 0)
        for step in c.steps {
            switch step {
            case "add": #expect(state.addNextOccurrence())
            case "skip": #expect(state.skipToNextOccurrence())
            default: #expect(state.selectAllOccurrences())
            }
        }
        return (state, b)
    }

    /// **1** The table of ⌘D, skip and select-all rules. **Mutations:** `.wholeWord` dropped from the caret's word
    /// search; the case folded (`.caseInsensitive`); the search starting at 0 instead of the primary's end; no
    /// wrapping; matches overlapping a selection accepted; the new selection not made the primary.
    @Test(arguments: SelectionHelpersTests.cases) func theRules(_ c: Case) {
        let (state, _) = run(c)
        #expect(state.selections.map(\.range) == c.expected, "\(c.name): \(state.selections.map(\.range))")
        #expect(state.primaryIndex == c.primary, "\(c.name): primary \(state.primaryIndex)")
    }

    /// **2** At the limit nothing is added and `false` comes back; select all selects the first `limit` and says so.
    /// **Mutation:** the guard `stored.count < limit` removed or `<=`.
    @Test func capReturnsFalseAtLimit() {
        let b = CodeBuffer("a a a a")
        let s = b.selectionState
        s.selections = [CodeSelection(anchor: 0, head: 1)]
        #expect(s.addNextOccurrence(limit: 2))
        #expect(s.selections.count == 2)
        #expect(!s.addNextOccurrence(limit: 2))
        #expect(s.selections.count == 2)
        #expect(!s.addCaret(lineDelta: 1, limit: 2))
        #expect(!s.selectAllOccurrences(limit: 3))
        #expect(s.selections.count == 3)
        #expect(s.selectAllOccurrences(limit: 4))
        #expect(s.selections.count == 4)
    }

    /// **3** A helper creates no undo step, does not change what undo reverts, and ends typing coalescing.
    /// **Mutation:** a helper writing through a transaction (the stack grows), or not calling `setSelections`
    /// (the two typed characters coalesce into one step).
    @Test func helpersAreUndoNeutral() {
        let b = CodeBuffer("foo foo\nx")
        let s = b.selectionState
        s.selections = [CodeSelection(caret: 9)]
        s.replaceSelections(with: "a")
        let steps = b.undoStack.count
        let text = b.snapshot().text
        s.selections = [CodeSelection(caret: 1)]
        _ = s.addNextOccurrence(); _ = s.addNextOccurrence(); _ = s.skipToNextOccurrence()
        _ = s.selectAllOccurrences(); _ = s.addCaret(lineDelta: 1); s.collapseToPrimary()
        #expect(b.undoStack.count == steps && b.snapshot().text == text && b.canUndo)
        s.selections = [CodeSelection(caret: 11)]
        s.replaceSelections(with: "b")
        s.collapseToPrimary()
        s.replaceSelections(with: "c")
        #expect(b.undoStack.count == steps + 2, "the helper ended coalescing: \(b.undoStack.count)")
    }

    /// **4** The goal column survives short lines, counts graphemes, and expands tabs. **Mutation:** the column
    /// taken from the previous caret each time (no goal), bytes for graphemes, or a tab counted as one column.
    @Test func addCaretKeepsColumnAcrossShortLines() {
        let b = CodeBuffer("abcdef\nab\nabcdef")
        let s = b.selectionState
        s.selections = [CodeSelection(caret: 5)]
        #expect(s.addCaret(lineDelta: 1))
        #expect(s.selections.map(\.head) == [5, 9] && s.primaryIndex == 1)
        #expect(s.addCaret(lineDelta: 1))
        #expect(s.selections.map(\.head) == [5, 9, 15] && s.primaryIndex == 2)
        #expect(s.goalColumn == 5)
        s.selections = [CodeSelection(caret: 15)]   // any explicit write resets the goal
        #expect(s.goalColumn == nil)
        #expect(s.addCaret(lineDelta: -1))
        #expect(s.selections.map(\.head) == [9, 15])   // column 5 clamped to the short line
        #expect(s.addCaret(lineDelta: -1))
        #expect(s.selections.map(\.head) == [5, 9, 15])

        let t = CodeBuffer("\tx\nabcdefgh\nab")
        let ts = t.selectionState
        ts.selections = [CodeSelection(caret: 2)]   // after the tab and the x: column 5
        _ = ts.addCaret(lineDelta: 1)
        #expect(ts.selections.map(\.head) == [2, 3 + 5], "tab width 4: \(ts.selections.map(\.head))")
        let w = CodeBuffer("\tx\nabcdefgh")
        let ws = w.selectionState
        ws.selections = [CodeSelection(caret: 2)]
        _ = ws.addCaret(lineDelta: 1, tabWidth: 8)   // column 9, past the end of the 8-character line
        #expect(ws.selections.map(\.head) == [2, 3 + 8])
        let up = CodeBuffer("abcdefgh\n\tx")
        let ups = up.selectionState
        ups.selections = [CodeSelection(caret: 6)]
        _ = ups.addCaret(lineDelta: 1)   // column 6: after the tab (4) and the x (5), clamped to the end
        #expect(ups.selections.map(\.head) == [6, 9 + 2])

        let g = CodeBuffer("e\u{301}xyz\nabcd")
        let gs = g.selectionState
        gs.selections = [CodeSelection(caret: 3)]   // after the accented grapheme and the x: column 2
        _ = gs.addCaret(lineDelta: 1)
        #expect(gs.selections.map(\.head) == [3, 6 + 2], "graphemes: \(gs.selections.map(\.head))")
    }

    /// **5** A caret does not go past the first or last line. **Mutation:** clamping to a line instead of ignoring.
    @Test func addCaretAtTheEdgesChangesNothing() {
        let b = CodeBuffer("a\nb")
        let s = b.selectionState
        s.selections = [CodeSelection(caret: 0)]
        #expect(s.addCaret(lineDelta: -1))
        #expect(s.selections.count == 1)
        s.selections = [CodeSelection(caret: 2)]
        #expect(s.addCaret(lineDelta: 1))
        #expect(s.selections.count == 1)
    }

    /// **6** Rows hidden by a registered fold state are passed over, both ways. **Mutation:** the hidden test removed.
    @Test func addCaretSkipsFoldedRows() {
        let b = CodeBuffer("a0\na1\na2\na3\na4\na5")
        let s = b.selectionState
        let folds = CodeFoldState(selectionState: s)
        #expect(folds.fold(1..<4))   // row 1 is the header; 2 and 3 are hidden
        s.selections = [CodeSelection(caret: 3 + 1)]
        #expect(s.addCaret(lineDelta: 1))
        #expect(s.selections.map(\.head) == [4, 13], "from the header past the hidden rows to row 4")
        #expect(s.addCaret(lineDelta: -1))   // back over the hidden rows onto row 1, whose caret is already there
        #expect(s.selections.map(\.head) == [4, 13] && s.primaryIndex == 0)
        withExtendedLifetime(folds) {}
    }

    /// **7** A helper whose new selection lands in a fold opens it. **Mutation:** none needed beyond the write path
    /// (`openFolds` removed from `setSelections` leaves the fold closed).
    @Test func aHelperOpensTheFoldHidingItsSelection() {
        let b = CodeBuffer("x\nfoo\nfoo\ny")
        let s = b.selectionState
        let folds = CodeFoldState(selectionState: s)
        s.selections = [CodeSelection(anchor: 2, head: 5)]
        #expect(folds.fold(1..<3))
        #expect(folds.isHidden(line: 2))
        #expect(s.addNextOccurrence())
        #expect(!folds.isHidden(line: 2) && folds.folded.isEmpty)
    }

    /// **8** Collapse keeps the primary and makes it the only selection. **Mutation:** keeping `selections[0]`.
    @Test func collapseToPrimary() {
        let b = CodeBuffer("a b c")
        let s = b.selectionState
        s.setSelections([CodeSelection(caret: 0), CodeSelection(anchor: 2, head: 3), CodeSelection(caret: 5)], primary: 1)
        s.collapseToPrimary()
        #expect(s.selections == [CodeSelection(anchor: 2, head: 3)] && s.primaryIndex == 0)
    }

    /// **9** Each helper that changes the selections rises `nearestRevealSerial` and never `revealSerial`; one that
    /// changes nothing does not. **Mutation:** a helper bumping `revealSerial` instead (centring).
    @Test func helpersAskForTheNearestReveal() {
        let b = CodeBuffer("foo foo\nfoo")
        let s = b.selectionState
        s.selections = [CodeSelection(caret: 1)]
        let centre = s.revealSerial, nearest = s.nearestRevealSerial
        _ = s.addNextOccurrence()
        #expect(s.nearestRevealSerial == nearest + 1 && s.revealSerial == centre)
        _ = s.addCaret(lineDelta: 1)
        #expect(s.nearestRevealSerial == nearest + 2 && s.revealSerial == centre)
        let before = s.nearestRevealSerial
        let other = CodeBuffer("abc")
        _ = other.selectionState.addNextOccurrence()
        _ = other.selectionState.addCaret(lineDelta: 1)   // no match, no line: nothing changes
        #expect(other.selectionState.nearestRevealSerial == 1)   // only the word selection counted
        #expect(s.nearestRevealSerial == before)
        withExtendedLifetime(other) {}
    }
}
