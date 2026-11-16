import Foundation
import Testing
@testable import MetalUICodeBuffer

/// The primary selection (`CV-BE`) and the batched multi-range edit (`CV-BF`).
@MainActor
struct MultiSelectionBatchTests {
    private func carets(_ offsets: [Int]) -> [CodeSelection] { offsets.map { CodeSelection(caret: $0) } }

    // MARK: The primary

    @Test func assigningMakesTheFirstInputTheTrackedPrimary() {
        let buffer = CodeBuffer("0123456789")
        buffer.selections = [CodeSelection(caret: 8), CodeSelection(caret: 2), CodeSelection(caret: 5)]
        #expect(buffer.selections == carets([2, 5, 8]))
        #expect(buffer.selectionState.primaryIndex == 2)
        #expect(buffer.primarySelection == CodeSelection(caret: 8))
        buffer.selectionState.setSelections([CodeSelection(caret: 8), CodeSelection(caret: 2), CodeSelection(caret: 5)], primary: 2)
        #expect(buffer.primarySelection == CodeSelection(caret: 5))
        buffer.selection(single: 3)
        #expect(buffer.selectionState.primaryIndex == 0)
    }

    @Test func theTopSelectionIsNotThePrimaryWhenTheLastWasAddedFirstInTheInput() {
        let buffer = CodeBuffer("0123456789")
        buffer.selectionState.setSelections([CodeSelection(caret: 1), CodeSelection(caret: 9)], primary: 1)
        #expect(buffer.primarySelection == CodeSelection(caret: 9))
        #expect(buffer.selectionState.primaryIndex == 1)
    }

    @Test func thePrimaryFollowsTheRangeItMergesInto() {
        let buffer = CodeBuffer("0123456789")
        buffer.selectionState.setSelections([CodeSelection(anchor: 1, head: 4), CodeSelection(caret: 7), CodeSelection(anchor: 3, head: 6)], primary: 2)
        // 1..4 and 3..6 overlap and merge; the primary was the second of them.
        #expect(buffer.selections == [CodeSelection(anchor: 1, head: 6), CodeSelection(caret: 7)])
        #expect(buffer.selectionState.primaryIndex == 0)
        // An edit that merges two carets keeps the primary on the merged one.
        let b2 = CodeBuffer("0123456789")
        b2.selectionState.setSelections(carets([2, 3, 8]), primary: 2)
        #expect(b2.selectionState.primaryIndex == 2)
        b2.replace(2..<3, with: "", origin: .programmatic)   // the caret at 3 (other rule: edit end <= lo) shifts to 2: merge
        #expect(b2.selections == carets([2, 7]))
        #expect(b2.selectionState.primaryIndex == 1)
        b2.selectionState.setSelections(carets([2, 3, 8]), primary: 1)
        b2.replace(2..<3, with: "", origin: .programmatic)
        #expect(b2.selectionState.primaryIndex == 0)
    }

    @Test func aStateWithOneSelectionBehavesAsBefore() {
        let buffer = CodeBuffer("abc")
        buffer.selections = [CodeSelection(anchor: 2, head: 1)]
        #expect(buffer.selectionState.primaryIndex == 0)
        #expect(buffer.primarySelection == CodeSelection(anchor: 2, head: 1))
    }

    @Test func undoRestoresEverySelectionAndThePrimary() {
        let buffer = CodeBuffer("aaa\nbbb\nccc")
        let state = buffer.selectionState
        state.setSelections(carets([1, 5, 9]), primary: 2)
        state.replaceSelections(with: "XY", origin: .paste)
        #expect(buffer.snapshot().text == "aXYaa\nbXYbb\ncXYcc")
        #expect(state.selections == carets([3, 9, 15]))
        #expect(state.primaryIndex == 2)
        state.setSelections(carets([0, 4]), primary: 0)       // a different arrangement before undoing
        #expect(state.undo())
        #expect(buffer.snapshot().text == "aaa\nbbb\nccc")
        #expect(state.selections == carets([1, 5, 9]))
        #expect(state.primaryIndex == 2)
        state.setSelections(carets([0]), primary: 0)
        #expect(state.redo())
        #expect(state.selections == carets([3, 9, 15]))
        #expect(state.primaryIndex == 2)
        #expect(state.primarySelection == CodeSelection(caret: 15))
    }

    // MARK: replaceSelections(withEach:)

    @Test func replaceSelectionsWithEachGivesEachItsOwnText() {
        let buffer = CodeBuffer("a b c")
        let state = buffer.selectionState
        state.setSelections([CodeSelection(anchor: 0, head: 1), CodeSelection(anchor: 2, head: 3), CodeSelection(anchor: 4, head: 5)], primary: 1)
        let before = buffer.version
        state.replaceSelections(withEach: ["one", "", "three!"])
        #expect(buffer.snapshot().text == "one  three!")
        #expect(buffer.version - before == 3)
        #expect(state.selections == carets([3, 4, 11]))
        #expect(state.primaryIndex == 1)
        #expect(state.undo())
        #expect(buffer.snapshot().text == "a b c")
        #expect(state.selections.count == 3)
        #expect(state.primaryIndex == 1)
    }

    @Test func replaceSelectionsWithEachOnTheBufferAndOneSelection() {
        let buffer = CodeBuffer("abc")
        buffer.selections = [CodeSelection(anchor: 1, head: 2)]
        buffer.replaceSelections(withEach: ["ZZ"])
        #expect(buffer.snapshot().text == "aZZc")
        #expect(buffer.selections == carets([3]))
    }

    // MARK: Typing coalesces across carets (Alloy's ruling on CV-BE)

    @Test func typingWithThreeCaretsIsOneUndoStep() {
        let buffer = CodeBuffer("a\nb\nc")
        let state = buffer.selectionState
        state.setSelections(carets([1, 3, 5]), primary: 1)
        state.replaceSelections(with: "x", origin: .typing)
        state.replaceSelections(with: "y", origin: .typing)
        #expect(buffer.snapshot().text == "axy\nbxy\ncxy")
        #expect(buffer.undoStack.count == 1)
        #expect(state.undo())
        #expect(buffer.snapshot().text == "a\nb\nc")
        #expect(state.selections == carets([1, 3, 5]))
        #expect(state.primaryIndex == 1)
        #expect(!buffer.canUndo)
        #expect(state.redo())
        #expect(buffer.snapshot().text == "axy\nbxy\ncxy")
        #expect(state.selections == carets([3, 7, 11]))
        #expect(state.primaryIndex == 1)
    }

    @Test func multiCaretTypingDoesNotCoalesceAfterAnotherEditOrASelectionWrite() {
        let buffer = CodeBuffer("a\nb")
        let state = buffer.selectionState
        state.setSelections(carets([1, 3]), primary: 0)
        state.replaceSelections(with: "x", origin: .typing)
        state.setSelections(state.selections, primary: 0)       // a selection write ends the run
        state.replaceSelections(with: "y", origin: .typing)
        #expect(buffer.undoStack.count == 2)
        state.replaceSelections(with: "z", origin: .paste)
        #expect(buffer.undoStack.count == 3)
    }

    // MARK: Batched == sequential

    private struct Rig {
        var buffer: CodeBuffer
        var states: [CodeSelectionState]
    }

    private static func randomSelections(_ rng: inout SplitMix64, size: Int) -> [CodeSelection] {
        (0..<Int.random(in: 1...6, using: &rng)).map { _ in
            CodeSelection(anchor: Int.random(in: 0...size, using: &rng), head: Int.random(in: 0...size, using: &rng))
        }
    }

    private static func randomEdits(_ rng: inout SplitMix64, size: Int) -> [(range: Range<Int>, text: String)] {
        var edits: [(range: Range<Int>, text: String)] = []
        var at = 0
        let pool = ["", "x", "yz", "\n", "long text"]
        while at <= size, edits.count < 8 {
            let lo = min(size, at + Int.random(in: 0...6, using: &rng))
            let hi = min(size, lo + [0, 0, 1, 3][Int.random(in: 0..<4, using: &rng)])
            edits.append((lo..<hi, pool[Int.random(in: 0..<pool.count, using: &rng)]))
            at = hi
            if lo == size { break }
        }
        return edits
    }

    @Test func aBatchMovesEveryStateAsTheSequentialPathDoes() {
        var rng = SplitMix64(seed: 0xBA7C4)
        let base = String(repeating: "abcdefghij\n", count: 6)
        let origins: [CodeEditOrigin] = [.typing, .paste, .programmatic, .deletion]
        for round in 0..<400 {
            let a = CodeBuffer(base), b = CodeBuffer(base)
            b.sequentialMoves = true
            var statesA = [a.selectionState], statesB = [b.selectionState]
            for _ in 0..<3 {
                statesA.append(CodeSelectionState(buffer: a)); statesB.append(CodeSelectionState(buffer: b))
            }
            for i in statesA.indices {
                let sels = Self.randomSelections(&rng, size: base.utf8.count)
                let p = Int.random(in: 0..<sels.count, using: &rng)
                statesA[i].setSelections(sels, primary: p); statesB[i].setSelections(sels, primary: p)
            }
            let cursorA = a.makeEditCursor(), cursorB = b.makeEditCursor()
            for step in 0..<6 {
                let actingIndex = Int.random(in: 0..<statesA.count, using: &rng)
                let size = a.utf8Count
                let edits = Self.randomEdits(&rng, size: size)
                let origin = origins[Int.random(in: 0..<origins.count, using: &rng)]
                let op = Int.random(in: 0..<4, using: &rng)
                let beforeSels = statesA.map(\.selections)
                let ctx = "topB \(b.undoStack.last?.inverse.map { "\($0.range)\($0.text.debugDescription)" } ?? []) beforeB \(statesB.map { $0.selections.map { "\($0.anchor)-\($0.head)" } }) top \(a.undoStack.last?.inverse.map { "\($0.range)\($0.text.debugDescription)" } ?? []) op \(op) acting \(actingIndex) origin \(origin) edits \(edits.map { "\($0.range)\($0.text.debugDescription)" }) before \(beforeSels.map { $0.map { "\($0.anchor)-\($0.head)" } })"
                switch op {
                case 0:
                    // external
                    let ext = edits.map { CodeTextEdit(range: $0.range, text: $0.text) }
                    _ = try? a.applyExternalEdits(ext); _ = try? b.applyExternalEdits(ext)
                case 1:
                    statesA[actingIndex].undo(); statesB[actingIndex].undo()
                case 2:
                    statesA[actingIndex].redo(); statesB[actingIndex].redo()
                default:
                    statesA[actingIndex].replaceBatch(edits, origin: origin)
                    statesB[actingIndex].replaceBatch(edits, origin: origin)
                }
                #expect(a.snapshot().text == b.snapshot().text, "round \(round) step \(step)")
                for i in statesA.indices {
                    #expect(statesA[i].selections == statesB[i].selections, "round \(round) step \(step) state \(i) \(ctx)")
                    #expect(statesA[i].primaryIndex == statesB[i].primaryIndex, "round \(round) step \(step) state \(i) primary")
                }
                if case .edits(let ea) = cursorA.drain(), case .edits(let eb) = cursorB.drain() {
                    #expect(ea.map(\.range) == eb.map(\.range) && ea.map(\.newText) == eb.map(\.newText), "round \(round) step \(step) log")
                } else { Issue.record("resync") }
            }
        }
    }

    /// Forty edits or more take one rope splice instead of one rope edit each; text, log (points, scalar ranges,
    /// versions), selections and undo must still equal the one-by-one result, CRLF seams included.
    @Test func aSplicedBatchEqualsTheOneByOneResult() {
        var rng = SplitMix64(seed: 4242)
        let line = "é日\r\nab\n\r\n😀 x\n"
        let base = String(repeating: line, count: 60)
        let pool = ["", "x", "\r", "\n", "\r\n", "é", "ab\ncd"]
        for round in 0..<60 {
            let a = CodeBuffer(base), b = CodeBuffer(base)
            b.sequentialMoves = true
            let cursorA = a.makeEditCursor(), cursorB = b.makeEditCursor()
            let extraA = CodeSelectionState(buffer: a), extraB = CodeSelectionState(buffer: b)
            let n = base.utf8.count
            var edits: [(range: Range<Int>, text: String)] = []
            var at = 0
            let boundaries = Oracle(base)
            while edits.count < 70 {
                var lo = min(n, at + Int.random(in: 0...12, using: &rng))
                while lo < n && boundaries.bytes[lo] & 0xC0 == 0x80 { lo += 1 }
                var hi = Bool.random(using: &rng) ? lo : min(n, lo + Int.random(in: 1...3, using: &rng))
                while hi < n && boundaries.bytes[hi] & 0xC0 == 0x80 { hi += 1 }
                edits.append((lo..<hi, pool[Int.random(in: 0..<pool.count, using: &rng)]))
                at = hi
                if at >= n - 4 { break }
            }
            let sels = edits.map { CodeSelection(caret: $0.range.upperBound) }
            for st in [a.selectionState, extraA] { st.setSelections(sels, primary: 3) }
            for st in [b.selectionState, extraB] { st.setSelections(sels, primary: 3) }
            a.selectionState.replaceBatch(edits, origin: .typing); b.selectionState.replaceBatch(edits, origin: .typing)
            #expect(a.snapshot().text == b.snapshot().text, "round \(round)")
            #expect(a.version == b.version)
            #expect(a.selections == b.selections && extraA.selections == extraB.selections)
            #expect(a.selectionState.primaryIndex == b.selectionState.primaryIndex)
            if case .edits(let ea) = cursorA.drain(), case .edits(let eb) = cursorB.drain() {
                #expect(ea.count == eb.count)
                for (x, y) in zip(ea, eb) {
                    #expect(x.version == y.version && x.range == y.range && x.scalarRange == y.scalarRange && x.startPoint == y.startPoint
                            && x.oldEndPoint == y.oldEndPoint && x.newEndPoint == y.newEndPoint && x.newText == y.newText, "round \(round) event \(x.version)")
                }
            } else { Issue.record("resync") }
            #expect(a.selectionState.undo() && b.selectionState.undo())
            #expect(a.snapshot().text == base && b.snapshot().text == base)
            #expect(a.selections == b.selections && extraA.selections == extraB.selections)
            #expect(a.selectionState.redo() && b.selectionState.redo())
            #expect(a.snapshot().text == b.snapshot().text)
        }
    }

    @Test func typingAtManyCaretsMatchesTheSequentialPath() {
        var rng = SplitMix64(seed: 77)
        for _ in 0..<100 {
            let text = String(repeating: "word ", count: 30)
            let a = CodeBuffer(text), b = CodeBuffer(text)
            b.sequentialMoves = true
            let sels = (0..<Int.random(in: 2...20, using: &rng)).map { _ in
                let lo = Int.random(in: 0...text.utf8.count, using: &rng)
                return CodeSelection(anchor: lo, head: min(text.utf8.count, lo + Int.random(in: 0...3, using: &rng)))
            }
            let other = CodeSelectionState(buffer: a), otherB = CodeSelectionState(buffer: b)
            other.setSelections(sels.reversed(), primary: 0); otherB.setSelections(sels.reversed(), primary: 0)
            a.selectionState.setSelections(sels, primary: 0); b.selectionState.setSelections(sels, primary: 0)
            for t in ["a", "", "bcd"] {
                a.selectionState.replaceSelections(with: t, origin: .typing)
                b.selectionState.replaceSelections(with: t, origin: .typing)
            }
            #expect(a.snapshot().text == b.snapshot().text)
            #expect(a.selections == b.selections && other.selections == otherB.selections)
            #expect(a.selectionState.primaryIndex == b.selectionState.primaryIndex)
            while a.canUndo { #expect(a.selectionState.undo() && b.selectionState.undo()); #expect(a.selections == b.selections && other.selections == otherB.selections) }
        }
    }

    // MARK: Cost

    @Test func aBatchMovesEachStateOnceNotOncePerEvent() {
        let buffer = CodeBuffer(String(repeating: "line\n", count: 60))
        let others = (0..<2).map { _ in CodeSelectionState(buffer: buffer, selections: carets([3, 12, 20])) }
        let state = buffer.selectionState
        state.selections = (0..<50).map { CodeSelection(caret: $0 * 5) }
        let live = buffer.liveStateCount
        #expect(live == 3)
        var count = buffer.stateMoveCount
        state.replaceSelections(with: "x", origin: .typing)
        #expect(buffer.stateMoveCount - count == live)            // states x 1, not x 50
        count = buffer.stateMoveCount
        #expect(state.undo())
        #expect(buffer.stateMoveCount - count == live)
        count = buffer.stateMoveCount
        #expect(state.redo())
        #expect(buffer.stateMoveCount - count == live)
        count = buffer.stateMoveCount
        _ = try? buffer.applyExternalEdits([CodeTextEdit(range: 0..<1, text: "q"), CodeTextEdit(range: 10..<11, text: "r")])
        #expect(buffer.stateMoveCount - count == live)
        withExtendedLifetime(others) {}
    }

    @Test func theSequentialHookMovesOncePerEvent() {
        let buffer = CodeBuffer(String(repeating: "line\n", count: 60))
        buffer.sequentialMoves = true
        buffer.selections = (0..<50).map { CodeSelection(caret: $0 * 5) }
        let count = buffer.stateMoveCount
        buffer.selectionState.replaceSelections(with: "x", origin: .typing)
        #expect(buffer.stateMoveCount - count == 50)
    }

    // MARK: Timing (gated)

    @Test(.enabled(if: ProcessInfo.processInfo.environment["METALUI_RUN_CODE_PERF"] == "1"))
    func oneTypedCharacterWithTenThousandCaretsIsFast() {
        let lines = 10_000
        let buffer = CodeBuffer(String(repeating: "let value = 1\n", count: lines))
        let state = buffer.selectionState
        state.selections = (0..<lines).map { CodeSelection(caret: $0 * 14 + 3) }
        #expect(state.selections.count == lines)
        let clock = ContinuousClock()
        let elapsed = clock.measure { state.replaceSelections(with: "x", origin: .typing) }
        let ms = Double(elapsed.components.attoseconds) / 1e15 + Double(elapsed.components.seconds) * 1000
        print("PERF 10000 carets one character: \(ms) ms")
        #expect(state.selections.count == lines)
        #expect(state.selections[0] == CodeSelection(caret: 4))
        #expect(ms <= 10)
    }
}

private extension CodeBuffer {
    func selection(single o: Int) { selections = [CodeSelection(caret: o)] }
}
