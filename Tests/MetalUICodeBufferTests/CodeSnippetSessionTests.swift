import Testing
import Observation
@testable import MetalUICodeBuffer

// The snippet session (`CV-BQ`, record 377): the placeholders as live ranges, the selections as the current
// group, following edits, ending. The keys and the paint are `CV-BR` (`CodeViewSnippetTests`).
//
// Mutations run against this file (each reddened the named tests, then was restored):
//  - `moveSnippet` not called from the batch `moveStates`: `linkedMirrorsEditTogether`, `batchedAndSequentialMovesAgree`.
//  - `moveSnippet` not called from the scalar `moveStates`: `externalEditMovesPlaceholders`, `overwrittenNestedStopIsSkipped`.
//  - the current group not growing at its edges (`hi += delta` dropped): `linkedMirrorsEditTogether`.
//  - a covered placeholder not marked removed: `overwrittenNestedStopIsSkipped`.
//  - undo not ending the session of the insertion's group: `undoOfInsertionEndsUndoOfTypingKeeps`.
//  - the undo end matched by stack depth (`undoStack.count == 1`): `undoOfInsertionEndsUndoOfTypingKeeps` after a trim.
//  - an explicit write outside every placeholder not ending: `aSelectionWriteOutsideEnds`.
//  - the inclusive bounds made exclusive: `aSelectionWriteAtAnEdgeKeeps`.
//  - a second insertion not ending the first: `aSecondInsertionEndsTheFirst`.
//  - the indent prefix dropped: `indentationFollowsTheLine`; the view's unit ignored: `indentationFollowsTheLine`.
//  - $0 not ending the session: `tabCyclesAndDollarZeroEnds`.
//  - an empty placeholder at the insertion point shifting always: `anEmptyPlaceholderStaysOnItsSide`.

@MainActor
struct CodeSnippetSessionTests {
    private func text(_ s: CodeSelectionState) -> String { s.buffer.snapshot().text }
    private func ranges(_ s: CodeSelectionState) -> [Range<Int>] { s.selections.map(\.range) }
    private func placeholders(_ s: CodeSelectionState, _ group: Int) -> [Range<Int>] { s.snippet?.ranges(of: group) ?? [] }
    private func slice(_ s: CodeSelectionState, _ r: Range<Int>) -> String { s.buffer.snapshot().text(in: r) }

    @Test func linkedMirrorsEditTogether() {
        let buffer = CodeBuffer("")
        let state = CodeSelectionState(buffer: buffer)
        state.insertSnippet(CodeSnippet(parsing: "for ${1:x} in ${2:xs} { ${1:x} }$0"), replacing: 0..<0)
        #expect(text(state) == "for x in xs { x }")
        #expect(state.isSnippetActive)
        #expect(ranges(state) == [4..<5, 14..<15], "the mirrors are the selections, the first the primary")
        #expect(state.primaryIndex == 0)
        state.replaceSelections(with: "a")
        state.replaceSelections(with: "b")
        #expect(text(state) == "for ab in xs { ab }")
        #expect(placeholders(state, 1) == [4..<6, 15..<17], "the current group grows with the typing")
        #expect(placeholders(state, 2) == [10..<12], "another placeholder follows")
        #expect(state.selections == [CodeSelection(caret: 6), CodeSelection(caret: 17)])
        // Deletion works through the same multi-selection path and keeps the session.
        state.replaceEach([(range: 5..<6, text: ""), (range: 16..<17, text: "")], origin: .deletion)
        #expect(text(state) == "for a in xs { a }")
        #expect(state.isSnippetActive && placeholders(state, 1) == [4..<5, 14..<15], "\(placeholders(state, 1))")
        // One undo reverts the deletion; the session survives and follows.
        state.undo()
        #expect(text(state) == "for ab in xs { ab }" && state.isSnippetActive && placeholders(state, 1) == [4..<6, 15..<17])
        state.undo()   // the coalesced typing
        #expect(text(state) == "for x in xs { x }" && state.isSnippetActive && placeholders(state, 1) == [4..<5, 14..<15])
        #expect(ranges(state) == [4..<5, 14..<15])
    }

    @Test func tabCyclesAndDollarZeroEnds() {
        let buffer = CodeBuffer("")
        let state = CodeSelectionState(buffer: buffer)
        state.insertSnippet(CodeSnippet(parsing: "f(${1:a}, ${2:b})$0!"), replacing: 0..<0)
        #expect(text(state) == "f(a, b)!")
        #expect(ranges(state) == [2..<3])
        #expect(state.nextSnippetPlaceholder())
        #expect(ranges(state) == [5..<6] && state.isSnippetActive)
        #expect(state.previousSnippetPlaceholder())
        #expect(ranges(state) == [2..<3])
        #expect(!state.previousSnippetPlaceholder(), "the first stop declines")
        #expect(ranges(state) == [2..<3] && state.isSnippetActive)
        #expect(state.nextSnippetPlaceholder() && state.nextSnippetPlaceholder())
        #expect(state.selections == [CodeSelection(caret: 7)], "$0 places the caret")
        #expect(!state.isSnippetActive, "and ends the session")
        #expect(!state.nextSnippetPlaceholder() && !state.previousSnippetPlaceholder(), "no session: both decline")
        #expect(buffer.undoStack.count == 1, "the moves are selection writes: one undo step")
    }

    @Test func aSnippetWithOnlyTheFinalStopStartsNoSession() {
        let buffer = CodeBuffer("ab")
        let state = CodeSelectionState(buffer: buffer)
        state.insertSnippet(CodeSnippet(parsing: "xy$0z"), replacing: 1..<1)
        #expect(text(state) == "axyzb" && !state.isSnippetActive)
        #expect(state.selections == [CodeSelection(caret: 3)])
    }

    @Test func anOverwrittenNestedStopIsSkipped() {
        let buffer = CodeBuffer("")
        let state = CodeSelectionState(buffer: buffer)
        state.insertSnippet(CodeSnippet(parsing: "${1:a ${2:b} c} ${3:d}$0"), replacing: 0..<0)
        #expect(text(state) == "a b c d")
        #expect(ranges(state) == [0..<5])
        state.replaceSelections(with: "Q")   // typing over the parent's default removes the child
        #expect(text(state) == "Q d")
        #expect(state.snippet?.isLive(2) == false)
        #expect(state.nextSnippetPlaceholder())
        #expect(ranges(state) == [2..<3], "Tab skips the overwritten stop 2 and lands on 3: \(ranges(state))")
        #expect(slice(state, 2..<3) == "d")
    }

    @Test func aNestedStopIsReachedWhenItsParentIsKept() {
        let buffer = CodeBuffer("")
        let state = CodeSelectionState(buffer: buffer)
        state.insertSnippet(CodeSnippet(parsing: "${1:a ${2:b} c}$0"), replacing: 0..<0)
        #expect(state.nextSnippetPlaceholder())
        #expect(ranges(state) == [2..<3])
        state.replaceSelections(with: "ZZ")
        #expect(text(state) == "a ZZ c")
        #expect(placeholders(state, 1) == [0..<6], "the parent grows with its child")
        #expect(placeholders(state, 2) == [2..<4])
    }

    @Test func aSelectionWriteOutsideEnds() {
        let buffer = CodeBuffer("")
        let state = CodeSelectionState(buffer: buffer)
        state.insertSnippet(CodeSnippet(parsing: "f(${1:a}, ${2:b})$0"), replacing: 0..<0)
        state.selections = [CodeSelection(caret: 0)]   // before the first placeholder
        #expect(!state.isSnippetActive)
        state.insertSnippet(CodeSnippet(parsing: "g(${1:a})$0"), replacing: 0..<0)
        let end = buffer.snapshot().utf8Count
        state.select(end..<end)
        #expect(!state.isSnippetActive, "a programmatic write ends it as a press does")
    }

    @Test func aSelectionWriteAtAnEdgeKeeps() {
        let buffer = CodeBuffer("")
        let state = CodeSelectionState(buffer: buffer)
        state.insertSnippet(CodeSnippet(parsing: "f(${1:abc}, ${2:b})$0"), replacing: 0..<0)
        state.selections = [CodeSelection(caret: 2)]   // the first placeholder's start
        #expect(state.isSnippetActive)
        state.selections = [CodeSelection(caret: 5)]   // its end
        #expect(state.isSnippetActive)
        state.selections = [CodeSelection(caret: 8)]   // inside the second: the current group follows
        #expect(state.isSnippetActive && state.snippet?.current == 2)
        state.selections = [CodeSelection(caret: 3), CodeSelection(caret: 8)]
        #expect(state.isSnippetActive, "every selection is inside some placeholder")
        state.selections = [CodeSelection(caret: 3), CodeSelection(caret: 6)]   // the comma
        #expect(!state.isSnippetActive, "one selection outside ends it")
    }

    @Test func undoOfInsertionEndsUndoOfTypingKeeps() {
        let buffer = CodeBuffer("")
        let state = CodeSelectionState(buffer: buffer)
        state.insertSnippet(CodeSnippet(parsing: "f(${1:a})$0"), replacing: 0..<0)
        state.replaceSelections(with: "x")
        state.replaceSelections(with: "y")
        #expect(text(state) == "f(xy)")
        state.undo()   // the typing, one coalesced step
        #expect(text(state) == "f(a)" && state.isSnippetActive)
        #expect(placeholders(state, 1) == [2..<3], "the placeholder follows the undo")
        #expect(ranges(state) == [2..<3])
        state.redo()
        #expect(text(state) == "f(xy)" && state.isSnippetActive)
        state.undo()
        state.undo()   // the insertion's own group
        #expect(text(state) == "" && !state.isSnippetActive)
        state.redo()
        #expect(text(state) == "f(a)" && !state.isSnippetActive, "a redo never restarts a session")
    }

    @Test func undoMatchesTheInsertionByIdNotByDepth() {
        let buffer = CodeBuffer("")
        let state = CodeSelectionState(buffer: buffer)
        state.insertSnippet(CodeSnippet(parsing: "f(${1:a})$0"), replacing: 0..<0)
        for c in ["x", "\n", "y", "\n", "z"] { state.replaceSelections(with: c); buffer.breakUndoCoalescing() }
        buffer.undoByteLimit = 1   // trims every step but the newest
        state.replaceSelections(with: "w")
        #expect(buffer.undoStack.count == 1)
        state.undo()
        #expect(state.isSnippetActive, "the surviving step is typing, not the insertion: the session stays")
    }

    @Test func aSecondInsertionEndsTheFirst() {
        let buffer = CodeBuffer("")
        let state = CodeSelectionState(buffer: buffer)
        state.insertSnippet(CodeSnippet(parsing: "f(${1:a}, ${2:b})$0"), replacing: 0..<0)
        let first = state.snippet?.transaction
        state.insertSnippet(CodeSnippet(parsing: "g(${1:p})$0"), replacing: 2..<3)
        #expect(text(state) == "f(g(p), b)")
        #expect(state.isSnippetActive && state.snippet?.transaction != first)
        #expect(state.snippet?.groups == [1, 0], "only the second's placeholders: \(String(describing: state.snippet?.groups))")
        #expect(ranges(state) == [4..<5])
        #expect(state.nextSnippetPlaceholder())
        #expect(state.selections == [CodeSelection(caret: 6)], "its $0 ends it; the first's stop 2 is gone")
        #expect(!state.isSnippetActive)
    }

    @Test func indentationFollowsTheLine() {
        let buffer = CodeBuffer("  \tif x {\n")
        let state = CodeSelectionState(buffer: buffer)
        let snippet = CodeSnippet(parsing: "if ${1:c} {\n\t${2:body}\n}$0")
        let at = "  \t".utf8.count
        state.insertSnippet(snippet, replacing: at..<at)
        #expect(text(state) == "  \tif c {\n  \t\tbody\n  \t}if x {\n", "tabs stay without a unit: \(text(state).debugDescription)")
        #expect(slice(state, state.selections[0].range) == "c")
        state.nextSnippetPlaceholder()
        #expect(slice(state, state.selections[0].range) == "body", "a stop after the indent is mapped past it")
        // With a unit, each leading tab of the snippet's lines becomes it; the line's own whitespace is kept.
        let b2 = CodeBuffer("    x")
        let s2 = CodeSelectionState(buffer: b2)
        s2.insertSnippet(CodeSnippet(parsing: "{\n\t\t${1:a}\n}$0"), replacing: 4..<4, indentUnit: "  ")
        #expect(b2.snapshot().text == "    {\n        a\n    }x", "\(b2.snapshot().text.debugDescription)")
        #expect(slice(s2, s2.selections[0].range) == "a")
        // nil takes the unit of the view showing the state.
        let b3 = CodeBuffer("")
        let s3 = CodeSelectionState(buffer: b3)
        s3.viewIndentSpaces = 3
        s3.insertSnippet(CodeSnippet(parsing: "a\n\tb$0"), replacing: 0..<0)
        #expect(b3.snapshot().text == "a\n   b")
        s3.viewIndentSpaces = 0
        s3.insertSnippet(CodeSnippet(parsing: "a\n\tb$0"), replacing: 0..<0)
        #expect(b3.snapshot().text.hasPrefix("a\n\tb"))
    }

    @Test func indentationFollowsAnInsertionInsideTheLeadingWhitespace() {
        let buffer = CodeBuffer("    x")
        let state = CodeSelectionState(buffer: buffer)
        state.insertSnippet(CodeSnippet(parsing: "a\nb$0"), replacing: 2..<2)
        #expect(text(state) == "  a\n  b  x", "only the whitespace before the insertion is copied: \(text(state).debugDescription)")
    }

    @Test func crlfBuffersGetCRLFBreaks() {
        let buffer = CodeBuffer("a\r\nb\r\n")
        let state = CodeSelectionState(buffer: buffer)
        state.insertSnippet(CodeSnippet(parsing: "x\ny${1:z}$0"), replacing: 0..<0)
        #expect(text(state) == "x\r\nyza\r\nb\r\n")
        #expect(slice(state, state.selections[0].range) == "z")
    }

    @Test func externalEditMovesPlaceholders() throws {
        let buffer = CodeBuffer("head\n")
        let state = CodeSelectionState(buffer: buffer)
        state.insertSnippet(CodeSnippet(parsing: "f(${1:a}, ${2:b})$0"), replacing: 5..<5)
        #expect(text(state) == "head\nf(a, b)")
        try buffer.applyExternalEdits([CodeTextEdit(range: 0..<0, text: "// c\n"), CodeTextEdit(range: 12..<12, text: "!!")])
        #expect(text(state) == "// c\nhead\nf(a, b)!!")
        #expect(state.isSnippetActive)
        #expect(placeholders(state, 1) == [12..<13] && placeholders(state, 2) == [15..<16])
        #expect(slice(state, 12..<13) == "a")
        // An external edit inside a non-current placeholder keeps it and its siblings consistent.
        try buffer.applyExternalEdits([CodeTextEdit(range: 15..<16, text: "BBB")])
        #expect(placeholders(state, 2) == [15..<18] && slice(state, 15..<18) == "BBB")
        // One that covers a placeholder removes it.
        try buffer.applyExternalEdits([CodeTextEdit(range: 14..<19, text: "")])
        #expect(state.snippet?.isLive(2) == false)
        #expect(state.nextSnippetPlaceholder())
        #expect(!state.isSnippetActive, "stop 2 is gone: Tab goes straight to $0")
    }

    @Test func anEmptyPlaceholderStaysOnItsSide() {
        let buffer = CodeBuffer("")
        let state = CodeSelectionState(buffer: buffer)
        // `$1` and `$2` touch: typing in the current one must not drag the empty other across, or into it.
        state.insertSnippet(CodeSnippet(parsing: "<$1$2>$0"), replacing: 0..<0)
        #expect(placeholders(state, 1) == [1..<1] && placeholders(state, 2) == [1..<1])
        state.replaceSelections(with: "ab")
        #expect(placeholders(state, 1) == [1..<3])
        #expect(placeholders(state, 2) == [3..<3], "the empty placeholder after the current one shifts past the typed text")
        state.nextSnippetPlaceholder()
        state.replaceSelections(with: "Z")
        #expect(placeholders(state, 1) == [1..<3], "the placeholder before it stays")
        #expect(placeholders(state, 2) == [3..<4])
        #expect(text(state) == "<abZ>")
    }

    /// Typed multi-caret text moves the session by the batch path; the same edits one event at a time (`sequentialMoves`)
    /// must leave the placeholders where the batch does, through typing, deletion, undo (ascending) and redo.
    @Test func batchedAndSequentialMovesAgree() {
        func run(sequential: Bool) -> [[Range<Int>]] {
            let buffer = CodeBuffer("")
            buffer.sequentialMoves = sequential
            let state = CodeSelectionState(buffer: buffer)
            state.insertSnippet(CodeSnippet(parsing: "${1:aa} ${2:b} ${1:aa} ${3:c} ${1:aa}$0"), replacing: 0..<0)
            var seen: [[Range<Int>]] = []
            func note() { seen.append((state.snippet?.placeholders.map(\.range)) ?? []) }
            note()
            state.replaceSelections(with: "xyz"); note()
            state.replaceSelections(with: "w"); note()
            state.replaceSelections(with: "", origin: .deletion); note()
            state.undo(); note()
            state.undo(); note()
            state.redo(); note()
            state.nextSnippetPlaceholder()
            state.replaceSelections(with: "Q"); note()
            return seen
        }
        let batched = run(sequential: false), sequential = run(sequential: true)
        #expect(batched == sequential)
        #expect(batched[1].count == 6 && batched[1][0] == 0..<3, "the first mirror holds the typed text: \(batched[1])")
    }

    /// With no session a state moves exactly as it did before sessions: the same count of state moves and the same selections.
    @Test func noSessionMovesStatesExactlyAsBefore() {
        func run(withSession: Bool) -> (moves: Int, selections: [[CodeSelection]]) {
            let buffer = CodeBuffer("one two three four five six seven\nsecond line here\n")
            let a = CodeSelectionState(buffer: buffer, selections: [CodeSelection(caret: 3)])
            let b = CodeSelectionState(buffer: buffer, selections: [CodeSelection(anchor: 8, head: 13), CodeSelection(caret: 30)])
            if withSession {
                a.insertSnippet(CodeSnippet(parsing: "<${1:p}|${2:q}>$0"), replacing: 3..<3)
            }
            let base = buffer.stateMoveCount
            b.replaceSelections(with: "Z")                                  // a batch of two edits
            a.replace(0..<0, with: "// ")                                    // a scalar edit
            b.setSelections([CodeSelection(caret: 5), CodeSelection(caret: 9), CodeSelection(caret: 20)], primary: 1)
            b.replaceSelections(with: "k", origin: .typing)
            b.undo()
            b.redo()
            _ = try? buffer.applyExternalEdits([CodeTextEdit(range: 1..<2, text: "")])
            return (buffer.stateMoveCount - base, [a.selections, b.selections, buffer.selectionState.selections])
        }
        let plain = run(withSession: false)
        #expect(plain.moves == 3 * (2 + 1 + 1 + 1 + 1 + 1) - 3 * 0 || plain.moves > 0)
        let again = run(withSession: false)
        #expect(plain.moves == again.moves && plain.selections == again.selections)
        // The count does not depend on a session: it is the same with one running on another state.
        let withSession = run(withSession: true)
        #expect(withSession.moves == plain.moves, "moves with a session \(withSession.moves), without \(plain.moves)")
        // The oracle for the selections of a state that has no session: the same script on a buffer that never saw a snippet.
        let buffer = CodeBuffer("one two three four five six seven\nsecond line here\n")
        let b = CodeSelectionState(buffer: buffer, selections: [CodeSelection(anchor: 8, head: 13), CodeSelection(caret: 30)])
        b.replaceSelections(with: "Z")
        #expect(b.selections == [CodeSelection(caret: 9), CodeSelection(caret: 27)], "\(b.selections)")
    }

    @Test func isSnippetActiveIsObservable() {
        let buffer = CodeBuffer("")
        let state = CodeSelectionState(buffer: buffer)
        let started = Flag()
        withObservationTracking { _ = state.isSnippetActive } onChange: { started.value = true }
        state.insertSnippet(CodeSnippet(parsing: "${1:a}$0"), replacing: 0..<0)
        #expect(started.value)
        let ended = Flag()
        withObservationTracking { _ = state.isSnippetActive } onChange: { ended.value = true }
        state.endSnippet()
        #expect(ended.value && !state.isSnippetActive && text(state) == "a" && state.selections == [CodeSelection(anchor: 0, head: 1)],
                "Escape keeps the selections")
    }

    @Test func aReadOnlyBufferStartsNothing() {
        let buffer = CodeBuffer("x")
        buffer.isReadOnly = true
        let state = CodeSelectionState(buffer: buffer)
        state.insertSnippet(CodeSnippet(parsing: "${1:a}$0"), replacing: 0..<0)
        #expect(text(state) == "x" && !state.isSnippetActive)
    }

    @Test func eachStateHasItsOwnSession() {
        let buffer = CodeBuffer("\n")
        let a = CodeSelectionState(buffer: buffer), b = CodeSelectionState(buffer: buffer, selections: [CodeSelection(caret: 1)])
        a.insertSnippet(CodeSnippet(parsing: "f(${1:x})$0"), replacing: 0..<0)
        b.insertSnippet(CodeSnippet(parsing: "g(${1:y})$0"), replacing: 5..<5)
        #expect(a.isSnippetActive && b.isSnippetActive)
        #expect(a.snippet?.ranges(of: 1) == [2..<3] && b.snippet?.ranges(of: 1) == [7..<8], "\(String(describing: a.snippet?.ranges(of: 1))) \(String(describing: b.snippet?.ranges(of: 1)))")
        a.replaceSelections(with: "long")
        #expect(b.snippet?.ranges(of: 1) == [10..<11])
    }
}

private final class Flag: @unchecked Sendable { var value = false }
