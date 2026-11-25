import Testing
import Observation
import Foundation
@testable import MetalUICodeBuffer

/// `CodeFoldState`, the fold model (`CV-BL`).
private final class FoldFlag: @unchecked Sendable { var value = false }

@MainActor
struct CodeFoldStateTests {
    /// `count` lines `line0`, `line1`, ... (5 bytes each below line 10).
    private func make(lines count: Int = 12) -> CodeBuffer {
        CodeBuffer((0..<count).map { "line\($0)" }.joined(separator: "\n"))
    }

    private func at(_ b: CodeBuffer, _ row: Int, _ col: Int) -> Int {
        b.snapshot().offset(of: CodePoint(row: row, column: col))
    }

    private func edit(_ b: CodeBuffer, _ from: (Int, Int), _ to: (Int, Int), _ text: String) {
        b.replace(at(b, from.0, from.1)..<at(b, to.0, to.1), with: text)
    }

    // MARK: The edit rules, one row each

    struct Case: Sendable, CustomTestStringConvertible {
        var name: String
        var from: [Int]
        var to: [Int]
        var text: String
        var expected: [Range<Int>]
        var testDescription: String { name }
    }

    nonisolated static let fold = 2..<6   // header line 2, hidden 3, 4 and 5
    nonisolated static let rules: [Case] = [
        Case(name: "above, no break", from: [0, 2], to: [0, 2], text: "x", expected: [2..<6]),
        Case(name: "above, insertion with a break shifts", from: [0, 2], to: [0, 2], text: "\n", expected: [3..<7]),
        Case(name: "above, a deleted line shifts up", from: [0, 0], to: [1, 0], text: "", expected: [1..<5]),
        Case(name: "above, a multi-line replace shifts by the delta", from: [0, 0], to: [1, 5], text: "a\nb\nc", expected: [3..<7]),
        Case(name: "header, insertion without a break keeps", from: [2, 2], to: [2, 2], text: "x", expected: [2..<6]),
        Case(name: "header, replace without a break keeps", from: [2, 1], to: [2, 3], text: "", expected: [2..<6]),
        Case(name: "header, break mid-line opens", from: [2, 2], to: [2, 2], text: "\n", expected: []),
        Case(name: "header, break at the end opens", from: [2, 5], to: [2, 5], text: "\n", expected: []),
        Case(name: "header, pure insertion at column 0 with a break shifts", from: [2, 0], to: [2, 0], text: "\n", expected: [3..<7]),
        Case(name: "header, column 0 insertion of a line shifts", from: [2, 0], to: [2, 0], text: "new\n", expected: [3..<7]),
        Case(name: "header, column 0 insertion of two breaks shifts by two", from: [2, 0], to: [2, 0], text: "\n\n", expected: [4..<8]),
        Case(name: "header, column 0 replace with a break opens", from: [2, 0], to: [2, 2], text: "\n", expected: []),
        Case(name: "body, insertion without a break keeps", from: [4, 1], to: [4, 1], text: "x", expected: [2..<6]),
        Case(name: "body, a break extends the end", from: [4, 1], to: [4, 1], text: "\n", expected: [2..<7]),
        Case(name: "body, a deleted line moves the end up", from: [4, 0], to: [5, 0], text: "", expected: [2..<5]),
        Case(name: "body, a break at the end of the last hidden row extends", from: [5, 5], to: [5, 5], text: "\n", expected: [2..<7]),
        Case(name: "body, a break at column 0 of the first hidden row extends", from: [3, 0], to: [3, 0], text: "\n", expected: [2..<7]),
        Case(name: "crossing from above into the body opens", from: [1, 2], to: [3, 2], text: "", expected: []),
        Case(name: "crossing from above into the header opens", from: [1, 2], to: [2, 2], text: "", expected: []),
        Case(name: "removing the header's line break opens", from: [2, 0], to: [3, 0], text: "", expected: []),
        Case(name: "deleting the whole body opens", from: [2, 5], to: [5, 5], text: "", expected: []),
        Case(name: "crossing the end boundary opens", from: [5, 2], to: [6, 2], text: "", expected: []),
        Case(name: "from the body past the end opens", from: [4, 0], to: [6, 0], text: "", expected: []),
        Case(name: "below, no break", from: [6, 2], to: [6, 2], text: "x", expected: [2..<6]),
        Case(name: "below, a break at column 0 of the next row", from: [6, 0], to: [6, 0], text: "\n", expected: [2..<6]),
        Case(name: "below, a deleted line", from: [7, 0], to: [8, 0], text: "", expected: [2..<6])
    ]

    @Test(arguments: rules)
    func theEditRules(_ c: Case) {
        let buffer = make()
        let folds = CodeFoldState(selectionState: buffer.selectionState, folded: [Self.fold])
        let tracked = CodeFoldState(selectionState: buffer.selectionState)
        tracked.foldableRanges = [Self.fold]
        buffer.selections = [CodeSelection(caret: at(buffer, 9, 0))]
        edit(buffer, (c.from[0], c.from[1]), (c.to[0], c.to[1]), c.text)
        #expect(folds.folded == c.expected)
        #expect(tracked.foldableRanges == c.expected)   // the same rules; open is a drop
    }

    @Test func aFoldKeepsAfterAnEditAboveAndTheTextIsStillWhatItWas() {
        let buffer = make()
        let folds = CodeFoldState(selectionState: buffer.selectionState, folded: [2..<6])
        edit(buffer, (0, 0), (0, 0), "a\nb\n")
        #expect(folds.folded == [4..<8])
        #expect(buffer.snapshot().line(4) == "line2")
        #expect(folds.isHidden(line: 5) && folds.isHidden(line: 7))
        #expect(!folds.isHidden(line: 4) && !folds.isHidden(line: 8))
    }

    // MARK: The model

    @Test func normalizationSortsDedupesClampsAndDropsShortRanges() {
        let buffer = make()
        let folds = CodeFoldState(selectionState: buffer.selectionState, folded: [5..<8, 2..<3, 5..<8, -3..<4, 9..<40, 10..<11])
        #expect(folds.folded == [0..<4, 5..<8, 9..<12])
        folds.folded = [7..<9, 1..<2]
        #expect(folds.folded == [7..<9])
        #expect(folds.fold(0..<1) == false)
        #expect(folds.fold(7..<9) == false)
        #expect(folds.fold(0..<3))
        #expect(folds.folded == [0..<3, 7..<9])
        #expect(folds.unfold(1..<3) == false)
        #expect(folds.unfold(0..<3))
        #expect(folds.toggle(4..<6))
        #expect(folds.folded == [4..<6, 7..<9])
        #expect(folds.toggle(4..<6))
        #expect(folds.folded == [7..<9])
        folds.unfoldAll()
        #expect(folds.folded.isEmpty)
        #expect(folds.buffer === buffer && folds.selectionState === buffer.selectionState)
    }

    @Test func nestedFoldsHideTheirUnionAndOpenIndependently() {
        let buffer = make(lines: 20)
        let folds = CodeFoldState(selectionState: buffer.selectionState, folded: [10..<14, 1..<8, 3..<6])
        #expect(folds.folded == [1..<8, 3..<6, 10..<14])
        let hidden = (0..<20).filter { folds.isHidden(line: $0) }
        #expect(hidden == [2, 3, 4, 5, 6, 7, 11, 12, 13])
        // An edit inside the inner body keeps both and extends both.
        edit(buffer, (4, 1), (4, 1), "\n")
        #expect(folds.folded == [1..<9, 3..<7, 11..<15])
        // A break inside the outer body but outside the inner one extends only the outer.
        edit(buffer, (2, 1), (2, 1), "\n")
        #expect(folds.folded == [1..<10, 4..<8, 12..<16])
        // Joining the inner header with the line above opens the inner fold only.
        edit(buffer, (3, 5), (4, 0), "")
        #expect(folds.folded == [1..<9, 11..<15])
        folds.unfold(containing: 5)
        #expect(folds.folded == [11..<15])
        folds.unfold(containing: 10)   // a header is not hidden by its own fold
        #expect(folds.folded == [11..<15])
        folds.unfold(containing: 12)
        #expect(folds.folded.isEmpty)
    }

    // MARK: Selections

    @Test func foldEvictsCarets() {
        let buffer = make()
        let state = buffer.selectionState
        let folds = CodeFoldState(selectionState: state)
        state.selections = [CodeSelection(caret: at(buffer, 4, 2)), CodeSelection(caret: at(buffer, 9, 1))]
        folds.fold(2..<6)
        #expect(state.selections == [CodeSelection(caret: at(buffer, 2, 5)), CodeSelection(caret: at(buffer, 9, 1))])
        #expect(folds.folded == [2..<6])   // the eviction is not an explicit write: it opens nothing
        // A selection from the header into the body keeps its start and moves its hidden end.
        state.selections = [CodeSelection(anchor: at(buffer, 8, 2), head: at(buffer, 9, 2))]
        folds.fold(7..<9)
        #expect(state.selections == [CodeSelection(anchor: at(buffer, 7, 5), head: at(buffer, 9, 2))])
        // Restoring through the setter evicts too, and two carets that meet merge.
        state.selections = [CodeSelection(caret: at(buffer, 10, 0)), CodeSelection(caret: at(buffer, 11, 0))]
        folds.folded = [10..<12]
        #expect(state.selections == [CodeSelection(caret: at(buffer, 10, 0)), CodeSelection(caret: at(buffer, 10, 6))])
        #expect(folds.folded == [10..<12])
    }

    @Test func selectRevealOpensFold() {
        func scenario(_ name: String, _ write: (CodeBuffer, CodeSelectionState) -> Void) {
            let buffer = make()
            let state = buffer.selectionState
            let folds = CodeFoldState(selectionState: state, folded: [2..<6, 8..<11])
            write(buffer, state)
            #expect(folds.folded == [8..<11], Comment(rawValue: name))
        }
        let inFirst = { (b: CodeBuffer) in self.at(b, 4, 1) }
        scenario("selections") { b, s in s.selections = [CodeSelection(caret: inFirst(b))] }
        scenario("select") { b, s in s.select(inFirst(b)..<inFirst(b) + 2) }
        scenario("setSelections") { b, s in s.setSelections([CodeSelection(caret: 0), CodeSelection(caret: inFirst(b))], primary: 1) }
        scenario("buffer.select") { b, _ in b.select(inFirst(b)..<inFirst(b) + 1) }   // find's step
        scenario("buffer.selections") { b, _ in b.selections = [CodeSelection(caret: inFirst(b))] }
        scenario("the head only") { b, s in s.selections = [CodeSelection(anchor: 0, head: inFirst(b))] }
        scenario("the anchor only") { b, s in s.selections = [CodeSelection(anchor: inFirst(b), head: 0)] }
        // A selection that spans a fold, ends shown, leaves it folded.
        let buffer = make()
        let folds = CodeFoldState(selectionState: buffer.selectionState, folded: [2..<6])
        buffer.selections = [CodeSelection(anchor: 0, head: at(buffer, 9, 0))]
        #expect(folds.folded == [2..<6])
        // The header's own end is shown.
        buffer.selections = [CodeSelection(caret: at(buffer, 2, 5))]
        #expect(folds.folded == [2..<6])
    }

    @Test func undoAndRedoRestoreOpenTheFoldsHidingTheirSelections() {
        let buffer = make()
        let state = buffer.selectionState
        let folds = CodeFoldState(selectionState: state)
        state.selections = [CodeSelection(caret: at(buffer, 4, 5))]
        state.replaceSelections(with: "x")            // typed in what will be a hidden row
        state.selections = [CodeSelection(caret: 0)]
        folds.fold(2..<6)
        #expect(state.undo())                         // the step's before-selection is in row 4
        #expect(folds.folded.isEmpty)
        folds.fold(2..<6)
        #expect(state.redo())                         // and its after-selection too
        #expect(folds.folded.isEmpty)
    }

    @Test func editsNeverOpenAFold() {
        let buffer = make()
        let state = buffer.selectionState
        let folds = CodeFoldState(selectionState: state, folded: [2..<6])
        state.selections = [CodeSelection(caret: at(buffer, 9, 0))]
        folds.fold(2..<6)
        state.selections = [CodeSelection(caret: at(buffer, 2, 5))]   // the header's end
        state.replaceSelections(with: "y")
        #expect(folds.folded == [2..<6])
        buffer.replace(at(buffer, 3, 0)..<at(buffer, 3, 0), with: "z")
        #expect(folds.folded == [2..<6])
    }

    @Test func undoDoesNotRefold() {
        let buffer = make()
        let folds = CodeFoldState(selectionState: buffer.selectionState, folded: [2..<6])
        edit(buffer, (2, 5), (2, 5), "\n")      // opens the fold
        #expect(folds.folded.isEmpty)
        #expect(buffer.undo())
        #expect(folds.folded.isEmpty)
        #expect(buffer.redo())
        #expect(folds.folded.isEmpty)
        // A fold that an undo moves is moved like any other edit.
        folds.fold(8..<11)
        edit(buffer, (0, 0), (0, 0), "\n")
        #expect(folds.folded == [9..<12])
        #expect(buffer.undo())
        #expect(folds.folded == [8..<11])
    }

    // MARK: Batches

    @Test func aBatchMovesFoldsLikeTheEventsOneByOne() {
        var rng = SplitMix64(seed: 0xF01D)
        for round in 0..<300 {
            let text = (0..<30).map { "row\($0) abcdefgh" }.joined(separator: "\n")
            let a = CodeBuffer(text), b = CodeBuffer(text)
            b.sequentialMoves = true
            var folds: [Range<Int>] = []
            for _ in 0..<(1 + Int(rng.next() % 6)) {
                let lo = Int(rng.next() % 26)
                folds.append(lo..<(lo + 2 + Int(rng.next() % 5)))
            }
            let fa = CodeFoldState(selectionState: a.selectionState, folded: folds)
            let fb = CodeFoldState(selectionState: b.selectionState, folded: folds)
            fa.foldableRanges = folds; fb.foldableRanges = folds
            // Random ascending, non-overlapping edits.
            var edits: [(range: Range<Int>, text: String)] = []
            let snap = a.snapshot()
            var row = 0
            while row < 30, edits.count < 8 {
                row += Int(rng.next() % 4)
                guard row < 30 else { break }
                let line = snap.lineRange(row)
                let col = line.lowerBound + Int(rng.next() % UInt64(line.count + 1))
                let kind = rng.next() % 5
                switch kind {
                case 0: edits.append((col..<col, "\n"))
                case 1: edits.append((col..<col, "x"))
                case 2: edits.append((line.lowerBound..<line.lowerBound, "n\n"))
                case 3: if row + 1 < 30 { edits.append((col..<snap.lineRange(row + 1).lowerBound, "")); row += 1 }
                default: edits.append((col..<min(col + 2, line.upperBound), "\n\n"))
                }
                row += 1
            }
            edits.sort { $0.range.lowerBound < $1.range.lowerBound }
            var ok = true
            for i in 1..<max(edits.count, 1) where edits[i].range.lowerBound < edits[i - 1].range.upperBound { ok = false }
            guard ok, !edits.isEmpty else { continue }
            a.selectionState.replaceBatch(edits, origin: .programmatic)
            b.selectionState.replaceBatch(edits, origin: .programmatic)
            #expect(fa.folded == fb.folded, "round \(round) folds \(folds) edits \(edits.map { "\($0.range)\($0.text.debugDescription)" })")
            #expect(fa.foldableRanges == fb.foldableRanges, "round \(round)")
            #expect(a.undo() && b.undo())
            #expect(fa.folded == fb.folded, "round \(round) undo")
            #expect(a.redo() && b.redo())
            #expect(fa.folded == fb.folded, "round \(round) redo")
        }
    }

    @Test func aSplicedBatchOfFortyCaretsMovesFoldsLikeTheEventsOneByOne() {
        var rng = SplitMix64(seed: 0x5011)
        for round in 0..<40 {
            let text = (0..<120).map { "row\($0) abcd" }.joined(separator: "\n")
            let a = CodeBuffer(text), b = CodeBuffer(text)
            b.sequentialMoves = true
            let folds = (0..<12).map { _ -> Range<Int> in let lo = Int(rng.next() % 110); return lo..<(lo + 2 + Int(rng.next() % 6)) }
            let fa = CodeFoldState(selectionState: a.selectionState, folded: folds)
            let fb = CodeFoldState(selectionState: b.selectionState, folded: folds)
            let carets = (0..<40).map { i in CodeSelection(caret: a.snapshot().offset(of: CodePoint(row: i * 3, column: Int(rng.next() % 4) == 0 ? 0 : 4))) }
            a.selectionState.setInternal(carets); b.selectionState.setInternal(carets)
            fa.folded = fa.folded; fb.folded = fb.folded
            a.selectionState.replaceSelections(with: "\n"); b.selectionState.replaceSelections(with: "\n")
            #expect(fa.folded == fb.folded, "round \(round)")
            #expect(a.undo() && b.undo())
            #expect(fa.folded == fb.folded, "round \(round) undo")
        }
    }

    @Test func multiCaretTypingMovesFoldsOnce() {
        let buffer = make(lines: 12)
        let state = buffer.selectionState
        let folds = CodeFoldState(selectionState: state, folded: [4..<8])
        state.selections = [CodeSelection(caret: at(buffer, 0, 0)), CodeSelection(caret: at(buffer, 1, 0)), CodeSelection(caret: at(buffer, 10, 0))]
        state.replaceSelections(with: "\n")
        #expect(folds.folded == [6..<10])
        state.undo()
        #expect(folds.folded == [4..<8])
    }

    // MARK: The foldable ranges

    @Test func foldableRangesFollowEditsAndDropWhereAFoldWouldOpen() {
        let buffer = make()
        let folds = CodeFoldState(selectionState: buffer.selectionState)
        folds.foldableRanges = [8..<11, 2..<6, 3..<5, 2..<6, 0..<1]
        #expect(folds.foldableRanges == [2..<6, 3..<5, 8..<11])
        edit(buffer, (0, 0), (0, 0), "\n")
        #expect(folds.foldableRanges == [3..<7, 4..<6, 9..<12])
        edit(buffer, (4, 5), (4, 5), "\n")   // the end of the header of 3..<7's body... a break inside 3..<7's body
        #expect(folds.foldableRanges.contains(3..<8))
        #expect(folds.folded.isEmpty)
    }

    @Test func setFoldableRangesMapsThroughLaterEditsAndDropsWhatCannotBeMapped() {
        let buffer = make()
        let folds = CodeFoldState(selectionState: buffer.selectionState)
        let v0 = buffer.version
        edit(buffer, (0, 0), (0, 0), "\n")        // shifts everything by one
        edit(buffer, (9, 5), (10, 0), "")         // joins rows 9 and 10: crosses 8..<11's end? rows 9..10 inside its body
        edit(buffer, (4, 2), (4, 2), "\n")        // a break in the header of 4..<7 (as shifted): opens it
        #expect(folds.setFoldableRanges([3..<6, 7..<12, 2..<4], asOf: v0))
        // 3..<6 -> 4..<7 -> opened by the header break (dropped); 2..<4 -> 3..<5 -> the break is in its last
        // hidden row: 3..<6; 7..<12 -> 8..<13 -> the join inside its body: 8..<12 -> shifted by the break: 9..<13
        #expect(folds.foldableRanges == [3..<6, 9..<13])
        // Current version: applied as given.
        #expect(folds.setFoldableRanges([1..<3], asOf: buffer.version))
        #expect(folds.foldableRanges == [1..<3])
        // From the future: refused, unchanged.
        #expect(folds.setFoldableRanges([6..<9], asOf: buffer.version + 5) == false)
        #expect(folds.foldableRanges == [1..<3])
    }

    @Test func setFoldableRangesRefusesAVersionTheLogNoLongerReaches() {
        let buffer = make()
        buffer.editLogMinimumEvents = 2
        let folds = CodeFoldState(selectionState: buffer.selectionState)
        let v0 = buffer.version
        for _ in 0..<20 { edit(buffer, (9, 0), (9, 0), "x") }
        #expect(folds.setFoldableRanges([2..<5], asOf: v0) == false)
        #expect(folds.foldableRanges.isEmpty)
        #expect(folds.setFoldableRanges([2..<5], asOf: buffer.version - 1))
        #expect(folds.foldableRanges == [2..<5])
    }

    // MARK: Observation and costs

    @Test func foldedIsObservableAndAnUnrelatedEditDoesNotWakeIt() {
        let buffer = make()
        let folds = CodeFoldState(selectionState: buffer.selectionState, folded: [2..<6])
        let fired = FoldFlag()
        withObservationTracking { _ = folds.folded } onChange: { fired.value = true }
        edit(buffer, (8, 0), (8, 0), "x")     // below: nothing moves
        #expect(!fired.value)
        edit(buffer, (0, 0), (0, 0), "\n")
        #expect(fired.value)
    }

    @Test func withNoFoldStateTheStateMoveCountIsUnchanged() {
        func run(withFold: Bool) -> Int {
            let buffer = make(lines: 40)
            let keep = withFold ? CodeFoldState(selectionState: buffer.selectionState, folded: [2..<6]) : nil
            let before = buffer.stateMoveCount
            buffer.selections = (0..<10).map { CodeSelection(caret: $0 * 6) }
            buffer.selectionState.replaceSelections(with: "x")
            edit(buffer, (3, 0), (3, 0), "\n")
            _ = buffer.undo()
            withExtendedLifetime(keep) {}
            return buffer.stateMoveCount - before
        }
        #expect(run(withFold: false) == run(withFold: true))
        let buffer = make()
        #expect(buffer.liveFoldStateCount == 0)
        do { let f = CodeFoldState(selectionState: buffer.selectionState); #expect(buffer.liveFoldStateCount == 1); withExtendedLifetime(f) {} }
        edit(buffer, (0, 0), (0, 0), "x")   // prunes the dead one
        #expect(buffer.liveFoldStateCount == 0)
    }

    private func thousandFolds() -> (CodeBuffer, CodeFoldState) {
        let buffer = CodeBuffer((0..<5000).map { "line\($0)" }.joined(separator: "\n"))
        let folds = CodeFoldState(selectionState: buffer.selectionState, folded: (0..<1000).map { (5 * $0 + 1)..<(5 * $0 + 4) })
        return (buffer, folds)
    }

    @Test func anEditVisitsLogFPlusTheTailAndNothingBefore() {
        let (buffer, folds) = thousandFolds()
        #expect(folds.folded.count == 1000)
        // A break at the header of fold 900: the 100 folds from it on shift; the 900 before are not visited.
        var before = folds.foldsVisited
        edit(buffer, (5 * 900, 0), (5 * 900, 0), "\n")
        var visited = folds.foldsVisited - before
        #expect(visited <= 11 + 100, "visited \(visited)")
        #expect(visited >= 100)
        #expect(folds.folded[900] == 4502..<4505 && folds.folded[899] == 4496..<4499)
        // An edit with no net line change visits the binary search and the one fold it touches.
        before = folds.foldsVisited
        edit(buffer, (5 * 500 + 1, 1), (5 * 500 + 1, 1), "z")
        visited = folds.foldsVisited - before
        #expect(visited <= 12, "visited \(visited)")
        // An edit past every fold visits only the search.
        before = folds.foldsVisited
        edit(buffer, (4999, 0), (4999, 0), "q")
        visited = folds.foldsVisited - before
        #expect(visited <= 11, "visited \(visited)")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["METALUI_RUN_CODE_PERF"] == "1"))
    func anEditCostsAtMostFiftyMicrosecondsAtAThousandFolds() {
        let (buffer, folds) = thousandFolds()
        let plain = CodeBuffer((0..<5000).map { "line\($0)" }.joined(separator: "\n"))
        let n = 2000
        func time(_ b: CodeBuffer) -> Double {
            let clock = ContinuousClock()
            let t = clock.measure {
                for i in 0..<n {
                    // Worst case: a line break at row 0 shifts every fold, then its removal shifts them back.
                    if i.isMultiple(of: 2) { b.replace(0..<0, with: "\n") } else { b.replace(0..<1, with: "") }
                }
            }
            return (Double(t.components.attoseconds) / 1e18 + Double(t.components.seconds)) / Double(n) * 1e6
        }
        let withFolds = time(buffer)
        let without = time(plain)
        print("PERF per edit, 1000 folds shifting every one: \(withFolds) us (no fold state: \(without) us)")
        #expect(folds.folded.count == 1000)
        #expect(withFolds <= 50)
    }
}
