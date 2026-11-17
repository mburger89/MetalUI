import Testing
import Observation
@testable import MetalUICodeBuffer

/// Per-view selections: `CodeSelectionState` (`CV-AV`, `CV-AW`, `CV-AX`).
@MainActor
struct SelectionStateTests {
    private func caret(_ o: Int) -> [CodeSelection] { [CodeSelection(caret: o)] }
    private func range(_ a: Int, _ b: Int) -> [CodeSelection] { [CodeSelection(anchor: a, head: b)] }

    // MARK: The default state is the buffer's selection

    @Test func theDefaultStateIsTheBuffersSelection() {
        let buffer = CodeBuffer("0123456789")
        buffer.selections = range(2, 5)
        #expect(buffer.selectionState.selections == range(2, 5))
        buffer.selectionState.select(7..<9, reveal: true)
        #expect(buffer.selections == range(7, 9))
        #expect(buffer.primarySelection == CodeSelection(anchor: 7, head: 9))
        #expect(buffer.revealSerial == buffer.selectionState.revealSerial)
        #expect(buffer.revealSerial == 1)
        #expect(buffer.selectionState === buffer.selectionState)
        #expect(buffer.selectionState.buffer === buffer)
    }

    @Test func observingTheBufferSelectionStillFiresForTheDefaultState() {
        let buffer = CodeBuffer("abc")
        let fired = Flag()
        withObservationTracking { _ = buffer.selections } onChange: { fired.value = true }
        buffer.selectionState.select(1..<2)
        #expect(fired.value)
        let revealed = Flag()
        withObservationTracking { _ = buffer.revealSerial } onChange: { revealed.value = true }
        buffer.select(0..<1)
        #expect(revealed.value)
    }

    // MARK: Independence

    @Test func statesAreIndependent() {
        let buffer = CodeBuffer("0123456789")
        let other = CodeSelectionState(buffer: buffer, selections: caret(8))
        buffer.select(2..<4)
        #expect(other.selections == caret(8))
        other.select(6..<7)
        #expect(buffer.selections == range(2, 4))
        #expect(other.revealSerial == 1)
        #expect(buffer.revealSerial == 1)
        #expect(CodeSelectionState(buffer: buffer, selections: [CodeSelection(caret: 99)]).selections == caret(10))   // clamped
        #expect(CodeSelectionState(buffer: buffer, selections: []).selections == caret(0))
    }

    // MARK: How a state follows an edit it did not make (CV-AW)

    /// Each row: the other state's selections, the edit `start..<end` -> `new`, what the other state holds after.
    fileprivate struct Row: CustomTestStringConvertible, Sendable {
        var name: String
        var before: [CodeSelection]
        var edit: Range<Int>
        var new: String
        var after: [CodeSelection]
        var testDescription: String { name }
    }

    nonisolated private static func c(_ o: Int) -> CodeSelection { CodeSelection(caret: o) }
    nonisolated private static func r(_ a: Int, _ b: Int) -> CodeSelection { CodeSelection(anchor: a, head: b) }

    nonisolated fileprivate static let rows: [Row] = [
        Row(name: "insertion before a caret", before: [c(5)], edit: 2..<2, new: "XY", after: [c(7)]),
        Row(name: "insertion after a caret", before: [c(5)], edit: 8..<8, new: "XY", after: [c(5)]),
        Row(name: "insertion at a caret moves it after", before: [c(5)], edit: 5..<5, new: "XY", after: [c(7)]),
        Row(name: "insertion at a range start moves the range", before: [r(5, 7)], edit: 5..<5, new: "XY", after: [r(7, 9)]),
        Row(name: "insertion at a range end changes nothing", before: [r(5, 7)], edit: 7..<7, new: "XY", after: [r(5, 7)]),
        Row(name: "insertion inside a range collapses to the insertion's end", before: [r(3, 8)], edit: 5..<5, new: "XY", after: [c(7)]),
        Row(name: "reversed range keeps its direction when shifted", before: [r(7, 5)], edit: 0..<0, new: "XY", after: [r(9, 7)]),
        Row(name: "deletion before a caret", before: [c(8)], edit: 2..<4, new: "", after: [c(6)]),
        Row(name: "deletion ending at a caret", before: [c(6)], edit: 2..<6, new: "", after: [c(2)]),
        Row(name: "deletion starting at a caret", before: [c(2)], edit: 2..<6, new: "", after: [c(2)]),
        Row(name: "deletion containing a caret", before: [c(5)], edit: 2..<8, new: "", after: [c(2)]),
        Row(name: "deletion containing a range", before: [r(4, 6)], edit: 2..<8, new: "", after: [c(2)]),
        Row(name: "deletion overlapping a range's start", before: [r(4, 8)], edit: 2..<6, new: "", after: [c(2)]),
        Row(name: "deletion overlapping a range's end", before: [r(2, 6)], edit: 4..<8, new: "", after: [c(4)]),
        Row(name: "deletion inside a range", before: [r(2, 8)], edit: 4..<5, new: "", after: [c(4)]),
        Row(name: "replacement containing a caret goes to its end", before: [c(5)], edit: 2..<8, new: "12345678", after: [c(10)]),
        Row(name: "replacement by a shorter text goes to its end", before: [c(5)], edit: 2..<8, new: "Z", after: [c(3)]),
        Row(name: "replacement containing a range", before: [r(4, 6)], edit: 2..<8, new: "ZZZZZZZZ", after: [c(10)]),
        Row(name: "replacement ending at a caret", before: [c(8)], edit: 2..<8, new: "Z", after: [c(3)]),
        Row(name: "replacement starting at a caret", before: [c(2)], edit: 2..<8, new: "Z", after: [c(2)]),
        Row(name: "three carets inside a deletion merge", before: [c(3), c(4), c(5)], edit: 2..<6, new: "", after: [c(2)]),
        Row(name: "multi-range: only the touched range collapses", before: [r(1, 2), r(4, 6), r(8, 9)], edit: 5..<5, new: "Q", after: [r(1, 2), c(6), r(9, 10)]),
        Row(name: "multi-range: a deletion shifts those after it", before: [c(1), r(4, 6), c(9)], edit: 2..<3, new: "", after: [c(1), r(3, 5), c(8)]),
        Row(name: "multi-range: carets before, inside and after a replacement", before: [c(1), c(4), c(9)], edit: 3..<6, new: "ab", after: [c(1), c(5), c(8)]),
    ]

    @Test(arguments: rows) fileprivate func anEditMovesAnotherStateByTheAppKitRule(_ row: Row) {
        let buffer = CodeBuffer("0123456789")
        let other = CodeSelectionState(buffer: buffer, selections: row.before)
        buffer.replace(row.edit, with: row.new, origin: .programmatic)   // the default state acts; `other` follows
        #expect(other.selections == row.after)
    }

    @Test func theRuleHoldsForTypingAndDeletionOriginsToo() {
        for origin in [CodeEditOrigin.typing, .paste, .deletion, .programmatic] {
            let buffer = CodeBuffer("0123456789")
            let other = CodeSelectionState(buffer: buffer, selections: caret(5))
            buffer.replace(5..<5, with: "XY", origin: origin)
            #expect(other.selections == caret(7), "\(origin)")
        }
    }

    // MARK: The acting state keeps today's rule

    @Test func theActingStateStaysStickyAndTheOtherMoves() {
        let buffer = CodeBuffer("abcd")
        let a = CodeSelectionState(buffer: buffer, selections: caret(2))
        let b = CodeSelectionState(buffer: buffer, selections: caret(2))
        a.replaceSelections(with: "X")
        #expect(buffer.snapshot().text == "abXcd")
        #expect(a.selections == caret(3))      // typed text: the actor's caret follows it
        #expect(b.selections == caret(3))      // the other's caret is pushed after the insertion as well
        b.replaceSelections(with: "Y")
        #expect(b.selections == caret(4))
        #expect(a.selections == caret(4))
    }

    @Test func typedAndPastedTextLeavesTheActingCaretAfterIt() {
        for origin in [CodeEditOrigin.typing, .paste] {
            let buffer = CodeBuffer("ab")
            let a = CodeSelectionState(buffer: buffer, selections: caret(1))
            let b = CodeSelectionState(buffer: buffer, selections: caret(1))
            a.replace(1..<1, with: "XY", origin: origin)
            #expect(a.selections == caret(3), "\(origin)")      // sticky: the insertion pushes the actor's caret
            #expect(b.selections == caret(3), "\(origin)")
        }
    }

    @Test func aProgrammaticInsertAtTheActingCaretDoesNotMoveTheActingCaret() {
        let buffer = CodeBuffer("ab")
        let a = CodeSelectionState(buffer: buffer, selections: caret(1))
        let b = CodeSelectionState(buffer: buffer, selections: caret(1))
        a.replace(1..<1, with: "X")
        #expect(a.selections == caret(1))      // today's rule for the actor (`CV-D`)
        #expect(b.selections == caret(2))      // `CV-AW` for everyone else
    }

    @Test func theActingStateKeepsItsDistanceInAReplacedSpan() {
        let buffer = CodeBuffer("0123456789")
        let a = CodeSelectionState(buffer: buffer, selections: caret(5))
        let b = CodeSelectionState(buffer: buffer, selections: caret(5))
        a.replace(2..<8, with: "abcdef")
        #expect(a.selections == caret(5))      // today's `start + min(o - start, newLength)`
        #expect(b.selections == caret(8))      // `CV-AW`: the end of the replacement
    }

    @Test func aTransactionThroughAStateIsThatStatesStep() {
        let buffer = CodeBuffer("abc")
        let a = CodeSelectionState(buffer: buffer, selections: range(0, 1))
        let b = CodeSelectionState(buffer: buffer, selections: caret(3))
        a.transaction { $0.replace(0..<1, with: "XX"); $0.replace(4..<4, with: "!") }
        #expect(buffer.snapshot().text == "XXbc!")
        #expect(buffer.undoStack.last?.undoSelections == range(0, 1))     // a's selection, not the default state's
        b.undo()
        #expect(b.selections == range(0, 1))
        #expect(buffer.snapshot().text == "abc")
    }

    // MARK: Undo and redo (CV-AX)

    @Test func undoRestoresTheStepsSelectionIntoTheStateThatUndid() {
        let buffer = CodeBuffer("0123456789")
        let a = CodeSelectionState(buffer: buffer, selections: range(2, 4))
        let b = CodeSelectionState(buffer: buffer, selections: caret(9))
        a.replaceSelections(with: "Z")                     // "01Z456789", a = caret 3
        #expect(a.selections == caret(3))
        #expect(b.selections == caret(8))
        a.select(0..<0, reveal: false)
        #expect(b.undo())
        #expect(buffer.snapshot().text == "0123456789")
        #expect(b.selections == range(2, 4))               // the step's selection went into b, the one that undid
        #expect(a.selections == caret(0))                  // a followed the text, was not written
    }

    @Test func undoMovesTheStatesThatDidNotUndo() {
        let buffer = CodeBuffer("0123456789")
        let a = CodeSelectionState(buffer: buffer, selections: range(2, 4))
        let b = CodeSelectionState(buffer: buffer, selections: caret(9))
        a.replaceSelections(with: "Z")
        #expect(a.undo())
        #expect(b.selections == caret(9))                  // 9 -> 8 -> 9: followed the replay both ways
    }

    @Test func redoRestoresTheStepsSelectionIntoTheStateThatRedid() {
        let buffer = CodeBuffer("0123456789")
        let a = CodeSelectionState(buffer: buffer, selections: range(2, 4))
        let b = CodeSelectionState(buffer: buffer, selections: caret(9))
        a.replaceSelections(with: "Z")
        #expect(b.undo())
        b.select(1..<1, reveal: false)
        #expect(b.redo())
        #expect(buffer.snapshot().text == "01Z456789")
        #expect(b.selections == caret(3))                  // the step's after-selection, in the state that redid
    }

    @Test func undoWithNothingToUndoLeavesTheSelection() {
        let buffer = CodeBuffer("abc")
        let a = CodeSelectionState(buffer: buffer, selections: caret(2))
        #expect(!a.undo())
        #expect(!a.redo())
        #expect(a.selections == caret(2))
    }

    // MARK: Coalescing per state

    @Test func typingInTwoStatesNeverCoalesces() {
        let buffer = CodeBuffer("")
        let a = CodeSelectionState(buffer: buffer)
        let b = CodeSelectionState(buffer: buffer)
        a.replaceSelections(with: "a")
        a.replaceSelections(with: "b")                     // one run in a
        #expect(buffer.undoStack.count == 1)
        b.replaceSelections(with: "c")                     // another state: a new step
        #expect(buffer.undoStack.count == 2)
        a.replaceSelections(with: "d")                     // back to a: ends b's run, a new step
        #expect(buffer.undoStack.count == 3)
        a.replaceSelections(with: "e")
        #expect(buffer.undoStack.count == 3)
        #expect(a.undo())
        #expect(buffer.snapshot().text == "abc")
        #expect(b.undo())
        #expect(buffer.snapshot().text == "ab")
        #expect(a.undo())
        #expect(buffer.snapshot().text == "")
    }

    @Test func oneStateTypingStillCoalescesWhenAnotherOneIsMoved() {
        let buffer = CodeBuffer("")
        let a = CodeSelectionState(buffer: buffer)
        _ = CodeSelectionState(buffer: buffer)
        for ch in "abc" { a.replaceSelections(with: String(ch)) }
        #expect(buffer.undoStack.count == 1)               // the buffer moving the other state does not end the run
    }

    @Test func anExplicitSelectionWriteOnAnyStateEndsTheRun() {
        let buffer = CodeBuffer("")
        let a = CodeSelectionState(buffer: buffer)
        let b = CodeSelectionState(buffer: buffer)
        a.replaceSelections(with: "a")
        b.select(0..<0, reveal: false)                     // b is not the typing state
        a.replaceSelections(with: "b")
        #expect(buffer.undoStack.count == 2)
        a.replaceSelections(with: "c")
        buffer.selections = caret(0)                       // the default state's write
        a.replaceSelections(with: "d")
        #expect(buffer.undoStack.count == 3)
    }

    @Test func aDefaultStateAloneStillCoalescesAsBefore() {
        let buffer = CodeBuffer("")
        for ch in "abc" { buffer.replaceSelections(with: String(ch)) }
        #expect(buffer.undoStack.count == 1)
        buffer.undo()
        #expect(buffer.snapshot().text == "")
    }

    // MARK: External edits

    @Test func externalEditsMoveEveryLiveState() throws {
        let buffer = CodeBuffer("0123456789ABCDEFGHIJ")
        let a = CodeSelectionState(buffer: buffer, selections: caret(1))
        let b = CodeSelectionState(buffer: buffer, selections: caret(9))
        let c = CodeSelectionState(buffer: buffer, selections: caret(18))
        _ = try buffer.applyExternalEdits([CodeTextEdit(range: 5..<13, text: "abc")])
        #expect(a.selections == caret(1))
        #expect(b.selections == caret(8))
        #expect(c.selections == caret(13))
        _ = try buffer.applyExternalReplacement("XYZ")
        #expect(buffer.selections.count == 1)
    }

    @Test func anExternalInsertAtACaretLeavesEveryCaretInFront() throws {
        // No acting state: the default state alone moves as it did before states existed, and so does any other.
        let buffer = CodeBuffer("abcd")
        buffer.selections = caret(2)
        let other = CodeSelectionState(buffer: buffer, selections: caret(2))
        _ = try buffer.applyExternalEdits([CodeTextEdit(range: 2..<2, text: "XY")])
        #expect(buffer.selections == caret(2))
        #expect(other.selections == caret(2))
    }

    // MARK: Lifetime

    @Test func releasedStatesAreDroppedAndStopCosting() {
        let buffer = CodeBuffer("0123456789")
        _ = buffer.selectionState
        var extra: CodeSelectionState? = CodeSelectionState(buffer: buffer, selections: caret(5))
        weak var weakExtra = extra
        #expect(buffer.liveStateCount == 2)
        var before = buffer.stateMoveCount
        buffer.replace(0..<0, with: "x")
        #expect(buffer.stateMoveCount - before == 2)
        extra = nil
        #expect(weakExtra == nil)
        before = buffer.stateMoveCount
        buffer.replace(0..<0, with: "y")
        #expect(buffer.stateMoveCount - before == 1)       // back to the default state only
        #expect(buffer.liveStateCount == 1)
        #expect(buffer.registeredStateCount == 1)         // swept from the registry, not just skipped
    }

    @Test func anEditWithNoExtraStatesMapsExactlyOneState() {
        // The perf guard: the work per event is one state's selections, as before states existed.
        let buffer = CodeBuffer(String(repeating: "line\n", count: 100))
        let before = buffer.stateMoveCount
        for i in 0..<50 { buffer.replace(i..<i, with: "x", origin: .typing) }
        #expect(buffer.stateMoveCount - before == 50)
        let tx = buffer.transaction { b in for i in 0..<10 { b.replace(i..<i, with: "y") } }
        _ = tx
        #expect(buffer.stateMoveCount - before == 60)
    }

    // MARK: Notification

    @Test func aStateTheEditDidNotMoveIsNotNotified() {
        let buffer = CodeBuffer("0123456789")
        let before = CodeSelectionState(buffer: buffer, selections: caret(1))
        let after = CodeSelectionState(buffer: buffer, selections: caret(9))
        let unmoved = Flag(), moved = Flag()
        withObservationTracking { _ = before.selections } onChange: { unmoved.value = true }
        withObservationTracking { _ = after.selections } onChange: { moved.value = true }
        buffer.replace(5..<5, with: "XY")
        #expect(!unmoved.value)
        #expect(moved.value)
        #expect(before.selections == caret(1))
        #expect(after.selections == caret(11))
    }

    @Test func theDefaultStateIsStillNotifiedByEveryEdit() {
        // Compatibility: the buffer's selection woke observers on every edit, moved or not.
        let buffer = CodeBuffer("0123456789")
        buffer.selections = caret(1)
        let fired = Flag()
        withObservationTracking { _ = buffer.selections } onChange: { fired.value = true }
        buffer.replace(5..<5, with: "XY")
        #expect(fired.value)
    }
    // MARK: mutationSerial (CV-BG)

    /// The serial rises on every stored change (an assignment, a primary-only change, an edit that moves the
    /// selections) and not on one that changes nothing. **Mutation:** not bumping in `setSelections` (the first check).
    @Test func theMutationSerialRisesOnEachStoredChangeAndOnlyThen() {
        let buffer = CodeBuffer("0123456789")
        let state = CodeSelectionState(buffer: buffer, selections: [CodeSelection(caret: 1), CodeSelection(caret: 5)])
        var serial = state.mutationSerial
        state.selections = [CodeSelection(caret: 2), CodeSelection(caret: 6)]
        #expect(state.mutationSerial > serial, "an assignment"); serial = state.mutationSerial
        state.setSelections(state.selections, primary: 1)
        #expect(state.mutationSerial > serial, "only the primary changed"); serial = state.mutationSerial
        buffer.replace(8..<8, with: "XY")
        #expect(state.mutationSerial == serial, "an edit after both selections moves neither")
        buffer.replace(0..<0, with: "Z")
        #expect(state.mutationSerial > serial, "an edit before them moves both")
    }
}

private final class Flag: @unchecked Sendable { var value = false }
