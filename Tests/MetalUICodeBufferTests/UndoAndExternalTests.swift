import Observation
import Testing
@testable import MetalUICodeBuffer

@MainActor
@Suite struct UndoAndExternalTests {
    // MARK: Undo

    @Test func typingCoalescesIntoOneStepAndRestoresTheSelection() throws {
        let buffer = CodeBuffer("hello world")
        buffer.select(6..<11, reveal: false)
        buffer.replaceSelections(with: "x")        // replaces the selection: its own step
        buffer.replaceSelections(with: "y")
        buffer.replaceSelections(with: "z")
        #expect(buffer.snapshot().text == "hello xyz")
        #expect(buffer.undoStack.count == 1)        // x, y, z are one step
        buffer.undo()
        #expect(buffer.snapshot().text == "hello world")
        #expect(buffer.selections == [CodeSelection(anchor: 6, head: 11)])   // restored exactly
        buffer.redo()
        #expect(buffer.snapshot().text == "hello xyz")
        #expect(buffer.selections == [CodeSelection(caret: 9)])
        #expect(buffer.canUndo && !buffer.canRedo)
    }

    @Test func typingThatIsNotAdjacentOrIsInterruptedStartsANewStep() throws {
        let buffer = CodeBuffer("")
        buffer.replaceSelections(with: "a")
        buffer.replaceSelections(with: "b")         // "ab": one step
        buffer.select(0..<0)                         // a caret move ends the group
        buffer.replaceSelections(with: "c")          // "cab"
        buffer.replaceSelections(with: "d")          // "cdab": joins "c"
        #expect(buffer.undoStack.count == 2)
        buffer.breakUndoCoalescing()
        buffer.replaceSelections(with: "e")          // "cdeab": its own step
        #expect(buffer.undoStack.count == 3)
        buffer.selections = [CodeSelection(caret: 0)]
        buffer.replaceSelections(with: "f")          // typed at 0, not where "cde" ended
        #expect(buffer.undoStack.count == 4)
        #expect(buffer.snapshot().text == "fcdeab")
        buffer.undo()
        #expect(buffer.snapshot().text == "cdeab")
        buffer.undo()
        #expect(buffer.snapshot().text == "cdab")
        buffer.undo()
        #expect(buffer.snapshot().text == "ab")
        buffer.undo()
        #expect(buffer.snapshot().text == "")
    }

    @Test func backspaceAndForwardDeleteCoalesceInTheirOwnKind() throws {
        let buffer = CodeBuffer("abcdefgh")
        buffer.selections = [CodeSelection(caret: 5)]
        for k in stride(from: 5, to: 2, by: -1) { buffer.replace((k - 1)..<k, with: "", origin: .deletion) }   // backspace x3
        #expect(buffer.snapshot().text == "abfgh")
        #expect(buffer.undoStack.count == 1)
        buffer.undo()
        #expect(buffer.snapshot().text == "abcdefgh")
        for _ in 0..<3 { buffer.replace(2..<3, with: "", origin: .deletion) }                                    // forward delete x3
        #expect(buffer.snapshot().text == "abfgh")
        #expect(buffer.undoStack.count == 1)
        buffer.undo()
        #expect(buffer.snapshot().text == "abcdefgh")
        // Typing after a deletion is not merged into it.
        buffer.replace(0..<1, with: "", origin: .deletion)
        buffer.replace(0..<0, with: "Q", origin: .typing)
        #expect(buffer.undoStack.count == 2)
    }

    @Test func undoAndRedoEmitOrdinaryEventsNamingTheStep() throws {
        let buffer = CodeBuffer("abc")
        let cursor = buffer.makeEditCursor()
        let tx = buffer.replace(1..<2, with: "XYZ", origin: .paste)
        buffer.undo()
        buffer.redo()
        guard case .edits(let events) = cursor.drain() else { return }
        #expect(events.map(\.origin) == [.paste, .undo(tx), .redo(tx)])
        #expect(Set(events.map(\.transaction)).count == 3)
        #expect(events.map(\.version) == [1, 2, 3])
        #expect(buffer.snapshot().text == "aXYZc")
    }

    @Test func aNewEditClearsTheRedoStackAndTransactionsAreOneStep() throws {
        let buffer = CodeBuffer("abc")
        buffer.transaction { b in
            b.replace(0..<1, with: "1")
            b.replace(2..<3, with: "3")
        }
        #expect(buffer.undoStack.count == 1)
        buffer.undo()
        #expect(buffer.snapshot().text == "abc")
        #expect(buffer.canRedo)
        buffer.replace(0..<0, with: ">")
        #expect(!buffer.canRedo)
        #expect(buffer.undo())
        #expect(!buffer.canUndo)
        #expect(buffer.undo() == false)
    }

    @Test func undoDepthIsCappedByBytes() throws {
        let buffer = CodeBuffer("")
        buffer.undoByteLimit = 2000
        for i in 0..<50 { buffer.replace(0..<0, with: String(repeating: "x", count: 100) + String(i)) }
        #expect(buffer.undoStack.count < 50 && buffer.undoStack.count >= 1)
        var undone = 0
        while buffer.undo() { undone += 1 }
        #expect(undone == buffer.redoStack.count)
    }

    // MARK: External edits

    @Test func externalEditsMoveCaretsLikeTheSelectionRule() throws {
        let buffer = CodeBuffer("0123456789ABCDEFGHIJ")
        buffer.selections = [CodeSelection(caret: 1), CodeSelection(caret: 9), CodeSelection(caret: 18)]
        _ = try buffer.applyExternalEdits([CodeTextEdit(range: 5..<13, text: "abc")])
        #expect(buffer.selections.map(\.head) == [1, 8, 13])     // 9 was 4 bytes into the span; 3 bytes replace it, so 5 + 3
    }

    @Test func externalEditsRunHighestFirstInPreEditCoordinates() throws {
        let text = "alpha\nbeta\ngamma\ndelta"
        let buffer = CodeBuffer(text)
        let cursor = buffer.makeEditCursor()
        let tx = try buffer.applyExternalEdits([
            CodeTextEdit(range: 0..<5, text: "ALPHA!"),
            CodeTextEdit(range: 17..<22, text: "D"),
            CodeTextEdit(range: 11..<11, text: "inserted\n"),
        ])
        #expect(buffer.snapshot().text == "ALPHA!\nbeta\ninserted\ngamma\nD")
        guard case .edits(let events) = cursor.drain() else { return }
        #expect(events.map(\.range) == [17..<22, 11..<11, 0..<5])           // descending, original coordinates
        #expect(events.map(\.origin) == [.external, .external, .external])
        #expect(Set(events.map(\.transaction)) == [tx])
        #expect(events[0].startPoint == CodePoint(row: 3, column: 0))
        #expect(events[1].startPoint == CodePoint(row: 2, column: 0))
        #expect(events.map(\.version) == [1, 2, 3])
    }

    @Test func externalEditsAreRefusedAtomically() throws {
        let buffer = CodeBuffer("héllo wörld")
        let v = buffer.version
        #expect(throws: CodeBufferError.invalidRange) {
            try buffer.applyExternalEdits([CodeTextEdit(range: 0..<1, text: "a"), CodeTextEdit(range: 0..<3, text: "b")])   // overlap
        }
        #expect(throws: CodeBufferError.invalidRange) {
            try buffer.applyExternalEdits([CodeTextEdit(range: 2..<4, text: "x")])           // inside the é
        }
        #expect(throws: CodeBufferError.invalidRange) {
            try buffer.applyExternalEdits([CodeTextEdit(range: 5..<99, text: "x")])
        }
        #expect(buffer.version == v)
        #expect(buffer.snapshot().text == "héllo wörld")
    }

    @Test func staleVersionIsRefused() throws {
        let buffer = CodeBuffer("abc")
        let v = buffer.version
        buffer.replace(0..<1, with: "x")
        #expect(throws: CodeBufferError.stale(current: 1)) {
            try buffer.applyExternalEdits([CodeTextEdit(range: 0..<1, text: "y")], expectingVersion: v)
        }
        #expect(throws: CodeBufferError.stale(current: 1)) { try buffer.applyExternalReplacement("zzz", expectingVersion: v) }
        _ = try buffer.applyExternalEdits([CodeTextEdit(range: 0..<1, text: "y")], expectingVersion: 1)
        #expect(buffer.snapshot().text == "ybc")
    }

    @Test func anExternalEditIsNotAnUndoStepAndTheUsersStepsSurviveIt() throws {
        let buffer = CodeBuffer("0123456789")
        buffer.select(0..<0, reveal: false)
        buffer.replaceSelections(with: "X")                  // X0123456789
        buffer.select(8..<8, reveal: false)
        buffer.replaceSelections(with: "Y")                  // X0123456Y789
        #expect(buffer.snapshot().text == "X0123456Y789")
        _ = try buffer.applyExternalEdits([CodeTextEdit(range: 3..<3, text: "--")])   // clear of both steps
        #expect(buffer.snapshot().text == "X01--23456Y789")
        #expect(buffer.undoStack.count == 2)
        buffer.undo()                                         // removes Y, which moved to byte 10
        #expect(buffer.snapshot().text == "X01--23456789")
        buffer.undo()
        #expect(buffer.snapshot().text == "01--23456789")
    }

    @Test func anUndoStepThatOverlapsAnExternalEditIsDroppedWithEveryOlderOne() throws {
        let buffer = CodeBuffer("0123456789")
        buffer.select(0..<0, reveal: false)
        buffer.replaceSelections(with: "A")                  // older step, far from the edit
        buffer.select(6..<6, reveal: false)
        buffer.replaceSelections(with: "B")                  // the step the external edit overlaps
        buffer.select(12..<12, reveal: false)
        buffer.replaceSelections(with: "C")                  // newer step, far from the edit
        #expect(buffer.snapshot().text == "A01234B56789C")
        _ = try buffer.applyExternalEdits([CodeTextEdit(range: 5..<7, text: "__")])
        #expect(buffer.snapshot().text == "A0123__56789C")
        #expect(buffer.undoStack.count == 1)                  // only C survives
        buffer.undo()
        #expect(buffer.snapshot().text == "A0123__56789")
        #expect(!buffer.canUndo)                              // B and A are gone
    }

    @Test func redoEntriesAreMappedThroughExternalEditsToo() throws {
        let buffer = CodeBuffer("abcdef")
        buffer.select(5..<5, reveal: false)
        buffer.replaceSelections(with: "ZZ")                 // abcdeZZf
        buffer.undo()
        _ = try buffer.applyExternalEdits([CodeTextEdit(range: 0..<0, text: ">>>")])
        buffer.redo()
        #expect(buffer.snapshot().text == ">>>abcdeZZf")
    }

    // MARK: Whole-text replacement

    @Test func replacementDiffsIntoFewHunks() throws {
        var lines = (0..<400).map { "line \($0) text é" }
        let buffer = CodeBuffer(lines.joined(separator: "\n"))
        let cursor = buffer.makeEditCursor()
        lines[10] = "changed ten"
        lines.remove(at: 100)
        lines.insert("brand new", at: 250)
        lines[399 - 1] = "changed tail 😀"
        let target = lines.joined(separator: "\n")
        let tx = try buffer.applyExternalReplacement(target)
        #expect(tx != nil)
        #expect(buffer.snapshot().text == target)
        guard case .edits(let events) = cursor.drain() else { return }
        #expect(events.count == 4)
        #expect(events.allSatisfy { $0.origin == .external })
        #expect(!buffer.canUndo)
        #expect(try buffer.applyExternalReplacement(target) == nil)
    }

    @Test func replacementOfARandomRewriteIsExact() throws {
        var rng = SplitMix64(seed: 41)
        for round in 0..<30 {
            var lines = (0..<Int.random(in: 0..<60, using: &rng)).map { "l\($0 % 7) \($0 % 3)" }
            let buffer = CodeBuffer(lines.joined(separator: "\n"))
            for _ in 0..<Int.random(in: 0..<10, using: &rng) {
                switch Int.random(in: 0..<3, using: &rng) {
                case 0 where !lines.isEmpty: lines.remove(at: Int.random(in: 0..<lines.count, using: &rng))
                case 1: lines.insert("new\(Int.random(in: 0..<5, using: &rng))", at: Int.random(in: 0...lines.count, using: &rng))
                default: if !lines.isEmpty { lines[Int.random(in: 0..<lines.count, using: &rng)] = "x\r" }
                }
            }
            let target = lines.joined(separator: "\n") + (round % 5 == 0 ? "\n" : "")
            _ = try buffer.applyExternalReplacement(target)
            #expect(buffer.snapshot().text == target, "round \(round)")
            #expect(buffer.snapshot().rope.problems().isEmpty)
        }
    }

    @Test func aHugeRewriteFallsBackToOneHunk() throws {
        let old = (0..<3000).map { "old \($0)" }.joined(separator: "\n")
        let new = (0..<3000).map { "new \($0)" }.joined(separator: "\n")
        let buffer = CodeBuffer(old)
        let cursor = buffer.makeEditCursor()
        _ = try buffer.applyExternalReplacement(new)
        #expect(buffer.snapshot().text == new)
        if case .edits(let e) = cursor.drain() { #expect(e.count == 1) }
    }

    // MARK: Observation

    @Test func versionAndSelectionsAreObservable() throws {
        let buffer = CodeBuffer("abc")
        let version = Flag(), selection = Flag(), count = Flag()
        withObservationTracking { _ = buffer.version } onChange: { version.fired = true }
        withObservationTracking { _ = buffer.selections } onChange: { selection.fired = true }
        buffer.replace(0..<1, with: "x")
        #expect(version.fired)
        #expect(selection.fired)       // the edit moved them
        withObservationTracking { _ = buffer.lineCount } onChange: { count.fired = true }
        buffer.replace(0..<0, with: "\n")
        #expect(count.fired)
    }
}

private final class Flag: @unchecked Sendable { var fired = false }
