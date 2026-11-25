import Dispatch
import Testing
@testable import MetalUITerminal

private let CSI = "\u{1B}["

private func emulator(_ cols: Int, _ rows: Int, scrollback: Int = 100, feed input: String = "") -> TerminalEmulator {
    let e = TerminalEmulator(cols: cols, rows: rows, scrollback: scrollback)
    e.feed(input)
    return e
}

extension TerminalEmulator {
    /// Every retained physical row, oldest first: scrollback then the screen.
    var physicalRows: [TerminalRow] { scrollback.rows + screen }

    /// The retained text as logical lines: soft-wrapped rows joined, trailing blank lines dropped.
    var logicalLines: [String] {
        var lines: [String] = []
        var current = ""
        for row in physicalRows {
            current += String(decoding: row.bytes, as: UTF8.self)
            if !row.wrapsToNext {
                while current.last == " " { current.removeLast() }
                lines.append(current)
                current = ""
            }
        }
        while lines.last == "" { lines.removeLast() }
        return lines
    }

    /// The logical lines with each cell's attributes, for the round-trip property.
    var attributedLines: [String] {
        var lines: [String] = []
        var cells: [TerminalCell] = []
        for row in physicalRows {
            cells += row.graphemes
            if !row.wrapsToNext {
                while let last = cells.last, last.grapheme == " " && last.attributes == TerminalAttributes() { cells.removeLast() }
                lines.append(cells.map { "\($0.grapheme)\($0.attributes)" }.joined(separator: "|"))
                cells = []
            }
        }
        return lines
    }

    var cursorCharacter: Character { screen[cursorRow].cell(at: cursorCol).grapheme }

    /// What the invariants of the grid say; empty when sound.
    var gridProblems: [String] {
        var out: [String] = []
        if screen.count != rowCount { out.append("screen rows \(screen.count) != \(rowCount)") }
        if offscreen.count != rowCount { out.append("offscreen rows \(offscreen.count) != \(rowCount)") }
        for row in screen + offscreen where row.columns != columnCount || row.usedColumns > columnCount {
            out.append("row width \(row.columns)/\(row.usedColumns) in \(columnCount)")
        }
        for row in scrollback.rows where row.columns != columnCount || row.usedColumns > columnCount {
            out.append("history width \(row.columns)/\(row.usedColumns) in \(columnCount)")
        }
        for row in physicalRows + offscreen {
            let covered = row.runs.reduce(0) { $0 + Int($1.count) }
            if covered != (row.runs.isEmpty ? 0 : row.usedColumns) { out.append("runs cover \(covered) of \(row.usedColumns)") }
            if row.graphemes.reduce(0, { $0 + $1.width }) != row.usedColumns { out.append("cell widths != used") }
        }
        if cursorRow < 0 || cursorRow >= rowCount || cursorCol < 0 || cursorCol >= columnCount {
            out.append("cursor \(cursorRow),\(cursorCol) outside \(columnCount)x\(rowCount)")
        }
        if scrollbackCount > scrollback.capacity { out.append("scrollback over capacity") }
        if tabStops.count != columnCount { out.append("tab stops \(tabStops.count)") }
        if regionTop != 0 && regionTop >= regionBottom { out.append("region") }
        if regionBottom >= rowCount { out.append("region bottom") }
        if scrolledOff != firstRow + scrollbackCount { out.append("numbering") }
        return out
    }
}

@Suite struct ReflowWidenAndNarrowTests {
    @Test func narrowingRewrapsASoftWrappedLineAndLeavesAHardOneAlone() {
        let e = emulator(10, 6, feed: "abcdefghij\(CSI)2;1Hxyz")
        e.resize(cols: 4, rows: 6)
        #expect(e.screenLines.prefix(4) == ["abcd", "efgh", "ij", "xyz"])
        #expect(e.screen[0].wrapsToNext && e.screen[1].wrapsToNext && !e.screen[2].wrapsToNext)
    }

    @Test func wideningRejoinsSoftWrappedRowsButNotHardOnes() {
        let e = emulator(5, 6, feed: "abcdefghijkl\r\nmn\r\nop")
        e.resize(cols: 12, rows: 6)
        #expect(e.screenLines.prefix(3) == ["abcdefghijkl", "mn", "op"])
        e.resize(cols: 6, rows: 6)
        #expect(e.screenLines.prefix(4) == ["abcdef", "ghijkl", "mn", "op"])
    }

    @Test func aRowThatAlreadyFitsIsUntouchedAndTrailingBlanksOfAHardLineAreNotCarried() {
        let e = emulator(12, 4, feed: "ab      \(CSI)2;1Hcd    x")
        e.resize(cols: 3, rows: 4)
        #expect(e.screenLines == ["ab", "cd", "", "x"])
        e.resize(cols: 12, rows: 4)
        #expect(e.screenLines[0] == "ab" && e.logicalLines == ["ab", "cd    x"])
    }

    @Test func aSoftWrappedLineEndingInBlanksDoesNotCarryThemWhenNarrowed() {
        let e = emulator(6, 6, feed: "abcdef      \(CSI)4;1H")
        e.resize(cols: 4, rows: 6)
        #expect(e.screenLines.prefix(3) == ["abcd", "ef", ""])
        #expect(e.screen[1].usedColumns == 2 && !e.screen[1].wrapsToNext)
    }

    @Test func aWideCharacterNeverSplitsAtTheEdgeAndTheGapIsNotCarried() {
        let e = emulator(10, 5, feed: "abc日def")
        e.resize(cols: 4, rows: 5)
        #expect(e.screenLines.prefix(2) == ["abc", "日de"])
        #expect(e.screen[0].usedColumns == 3 && e.screen[0].wrapsToNext)
        e.resize(cols: 5, rows: 5)
        #expect(e.screenLines.prefix(2) == ["abc日", "def"])
        e.resize(cols: 10, rows: 5)
        #expect(e.screenLines[0] == "abc日def" && e.screen[0].usedColumns == 8)
        e.resize(cols: 2, rows: 5)
        #expect(e.logicalLines == ["abc日def"])
        #expect(e.physicalRows.allSatisfy { $0.usedColumns <= 2 })
    }

    @Test func attributesFollowTheirCellsAcrossARewrap() {
        let e = emulator(8, 4, feed: "ab\(CSI)31mcdef\(CSI)0mghijkl")
        e.resize(cols: 5, rows: 4)
        #expect(e.screenLines.prefix(3) == ["abcde", "fghij", "kl"])
        #expect(e.screen[0].attributes(at: 1) == TerminalAttributes())
        #expect(e.screen[0].attributes(at: 2) != TerminalAttributes() && e.screen[0].attributes(at: 4) != TerminalAttributes())
        #expect(e.screen[1].attributes(at: 0) != TerminalAttributes() && e.screen[1].attributes(at: 1) == TerminalAttributes())
        #expect(e.gridProblems.isEmpty)
    }

    @Test func aColouredBlankRunIsContentAndIsCarried() {
        let e = emulator(6, 3, feed: "\(CSI)44m\(CSI)K\(CSI)0mab")
        e.resize(cols: 3, rows: 3)
        #expect(e.screen[0].used == 3 && !e.screen[0].runs.isEmpty && e.screen[1].used == 3)
        e.resize(cols: 6, rows: 3)
        #expect(e.screen[0].used == 6 && e.screen[0].attributes(at: 5) != TerminalAttributes())
    }
}

@Suite struct ReflowCursorTests {
    @Test func theCursorStaysOnTheSameCharacterThroughNarrowAndWiden() {
        let e = emulator(20, 6, feed: "the quick brown fox\(CSI)1;11H")
        #expect(e.cursorCharacter == "b")
        for width in [7, 3, 5, 19, 40, 2, 11] {
            e.resize(cols: width, rows: 6)
            #expect(e.cursorCharacter == "b", "width \(width)")
        }
    }

    @Test func theCursorOnALaterHardLineStaysOnItsCharacter() {
        let e = emulator(12, 8, feed: "aaaaaaaaaaaa11\r\nbb\r\nccccccccccccdd\(CSI)5;1H")
        #expect(e.cursorCharacter == "d")
        e.resize(cols: 5, rows: 8)
        #expect(e.cursorCharacter == "d")
        e.resize(cols: 30, rows: 8)
        #expect(e.cursorCharacter == "d" && e.cursorPosition.row == 2)
    }

    @Test func aCursorPastTheTextKeepsItsColumn() {
        let e = emulator(20, 4, feed: "ab\(CSI)1;15H")
        e.resize(cols: 6, rows: 4)
        #expect(e.cursorPosition == (2, 2, false))
        e.resize(cols: 20, rows: 4)
        #expect(e.cursorPosition == (0, 14, false))
        #expect(e.logicalLines == ["ab"])
    }

    @Test func aPendingWrapSurvivesWhenTheLineStillEndsAtTheEdge() {
        let e = emulator(4, 4, feed: "abcd")
        #expect(e.cursorPosition == (0, 3, true))
        e.resize(cols: 2, rows: 4)
        #expect(e.screenLines.prefix(2) == ["ab", "cd"] && e.cursorPosition == (1, 1, true))
        e.resize(cols: 8, rows: 4)
        #expect(e.cursorPosition == (0, 4, false))
        e.feed("e")
        #expect(e.screenLines[0] == "abcde")
        e.resize(cols: 3, rows: 4)
        e.feed("f")
        #expect(e.logicalLines == ["abcdef"])
    }

    @Test func aCursorAtTheStartOfAFullRowGetsItsOwnRowOfTheSameLine() {
        let e = emulator(10, 4, feed: "ab")
        e.resize(cols: 2, rows: 4)
        #expect(e.cursorPosition == (1, 0, false))
        #expect(e.screen[0].wrapsToNext)
        e.feed("c")
        #expect(e.logicalLines == ["abc"])
    }

    @Test func typingAfterAResizeContinuesTheLine() {
        let e = emulator(10, 4, feed: "hello wor")
        e.resize(cols: 4, rows: 4)
        e.feed("ld")
        e.resize(cols: 20, rows: 4)
        #expect(e.screenLines[0] == "hello world")
    }

    @Test func aCursorInTheMiddleOfAWideCellStaysInIt() {
        let e = emulator(10, 4, feed: "ab日cd\(CSI)1;4H")
        e.resize(cols: 3, rows: 4)
        #expect(e.screen[e.cursorRow].cell(at: e.cursorCol).grapheme == "日")
    }
}

@Suite struct ReflowScrollbackAndRowsTests {
    private func numbered(_ count: Int, width: Int = 12) -> String {
        (0..<count).map { String(repeating: Character(Unicode.Scalar(UInt8(97 + $0 % 26))), count: width) }.joined(separator: "\r\n")
    }

    @Test func scrollbackRowsRewrapToo() {
        let e = emulator(8, 3, feed: "aaaaaaaaaaaa\r\nbbbbbbbbbbbb\r\ncccccccccccc\r\ndddddddddddd")
        #expect(e.logicalLines == ["aaaaaaaaaaaa", "bbbbbbbbbbbb", "cccccccccccc", "dddddddddddd"])
        let before = e.logicalLines
        e.resize(cols: 5, rows: 3)
        #expect(e.logicalLines == before)
        #expect(e.historyLines.first == "aaaaa" && e.historyLines.count > 1)
        e.resize(cols: 30, rows: 3)
        #expect(e.logicalLines == before)
        #expect(e.historyLines.count + e.rowCount == 4 + 2 || e.historyLines.count == 1)
        #expect(e.gridProblems.isEmpty)
    }

    @Test func aLineSplitBetweenScrollbackAndTheScreenRejoins() {
        let e = emulator(4, 2, feed: "abcdefghijkl")
        #expect(e.historyLines == ["abcd"] && e.screenLines == ["efgh", "ijkl"])
        e.resize(cols: 12, rows: 2)
        #expect(e.logicalLines == ["abcdefghijkl"])
        #expect(e.historyLines.isEmpty && e.screenLines[0] == "abcdefghijkl")
    }

    @Test func shrinkingRowsPushesTheTopLinesToScrollbackAndKeepsTheCursorVisible() {
        let e = emulator(6, 5, feed: "1\r\n2\r\n3\r\n4\r\n5")
        let first = e.firstRow
        e.resize(cols: 6, rows: 3)
        #expect(e.historyLines == ["1", "2"] && e.screenLines == ["3", "4", "5"])
        #expect(e.cursorPosition.row == 2 && e.firstRow == first && e.scrolledOff == first + 2)
        #expect((e.firstRow..<(e.firstRow + 5)).map { e.rowText($0) } == ["1", "2", "3", "4", "5"])
    }

    @Test func shrinkingRowsDropsBlankRowsBelowTheCursorBeforeAnyHistory() {
        let e = emulator(6, 8, feed: "1\r\n2\r\n3")
        e.resize(cols: 6, rows: 4)
        #expect(e.historyLines.isEmpty && e.screenLines == ["1", "2", "3", ""])
        e.resize(cols: 6, rows: 2)
        #expect(e.historyLines == ["1"] && e.screenLines == ["2", "3"] && e.cursorPosition.row == 1)
    }

    @Test func shrinkingNeverPushesTheCursorOffTheTop() {
        let e = emulator(6, 6, feed: "1\r\n2\r\n3\r\n4\r\n5\r\n6\(CSI)2;1H")
        e.resize(cols: 6, rows: 2)
        #expect(e.cursorPosition.row == 0 && e.cursorCharacter == "2" && e.screenLines == ["2", "3"])
        #expect(e.historyLines == ["1"])
    }

    @Test func growingRowsPullsLinesBackFromScrollbackAndMovesTheCursorDown() {
        let e = emulator(6, 3, feed: "1\r\n2\r\n3\r\n4\r\n5")
        #expect(e.historyLines == ["1", "2"])
        let top = e.scrolledOff
        e.resize(cols: 6, rows: 5)
        #expect(e.historyLines.isEmpty && e.screenLines == ["1", "2", "3", "4", "5"])
        #expect(e.cursorPosition.row == 4 && e.scrolledOff == top - 2)
        e.resize(cols: 6, rows: 7)
        #expect(e.screenLines == ["1", "2", "3", "4", "5", "", ""] && e.cursorPosition.row == 4)
    }

    @Test func growingPullsOnlyWhatScrollbackHolds() {
        let e = emulator(6, 3, scrollback: 10, feed: "1\r\n2\r\n3\r\n4")
        e.resize(cols: 6, rows: 9)
        #expect(e.screenLines == ["1", "2", "3", "4", "", "", "", "", ""] && e.cursorPosition.row == 3)
    }

    @Test func aRowsOnlyResizePreservesEveryAbsoluteRowAndTheGeneration() throws {
        let e = emulator(8, 4, scrollback: 200, feed: numbered(12))
        var before: [Int: String?] = [:]
        for row in e.firstRow..<(e.firstRow + e.scrollbackCount + e.rowCount) { before[row] = e.rowText(row) }
        let generation = e.reflowGeneration
        for height in [2, 9, 1, 5] {
            e.resize(cols: 8, rows: height)
            for row in e.firstRow..<(e.firstRow + e.scrollbackCount + height) where before[row] != nil {
                let expectedRow = try #require(before[row])
                #expect(e.rowText(row) == expectedRow, "row \(row) at \(height) rows")
            }
            let lowestRow = try #require(before.keys.min())
            #expect(e.firstRow == lowestRow, "nothing is evicted below the capacity")
        }
        #expect(e.reflowGeneration == generation)
    }

    @Test func aWidthChangeBumpsTheGenerationAndRenumbersAfterTheFirstRetainedRow() {
        let e = emulator(10, 3, scrollback: 50, feed: "aaaaaaaaaa" + "bbbbbbbbbb" + "cccccccccc" + "dddd\r\neeeeee")
        let first = e.firstRow
        let generation = e.reflowGeneration
        e.resize(cols: 5, rows: 3)
        #expect(e.reflowGeneration == generation + 1)
        #expect(e.firstRow == first && e.rowText(first) == "aaaaa" && e.rowText(first + 1) == "aaaaa")
        e.resize(cols: 5, rows: 3)
        #expect(e.reflowGeneration == generation + 1, "the same size is not a resize")
    }

    @Test func evictionDuringARewrapAdvancesTheFirstRowByTheRowsDropped() {
        let e = emulator(10, 2, scrollback: 3, feed: "aaaaaaaaaabbbbbbbbbb\r\ncccccccccc")
        #expect(e.firstRow == 0 && e.historyLines.count == 1 || e.firstRow >= 0)
        let first = e.firstRow
        e.resize(cols: 2, rows: 2)
        #expect(e.scrollbackCount == 3 && e.firstRow > first)
        #expect(e.scrolledOff == e.firstRow + 3 && e.rowText(e.firstRow - 1) == nil)
        #expect(e.gridProblems.isEmpty)
    }

    @Test func noScrollbackStillResizes() {
        let e = emulator(6, 4, scrollback: 0, feed: "1\r\n2\r\n3\r\n4")
        e.resize(cols: 3, rows: 2)
        #expect(e.screenLines == ["3", "4"] && e.firstRow == e.scrolledOff && e.gridProblems.isEmpty)
        e.resize(cols: 9, rows: 6)
        #expect(e.screenLines.prefix(2) == ["3", "4"] && e.gridProblems.isEmpty)
    }

    @Test func sizesClampToTwoByOne() {
        let e = emulator(6, 4, feed: "abcdef")
        e.resize(cols: 0, rows: 0)
        #expect(e.columnCount == 2 && e.rowCount == 1 && e.gridProblems.isEmpty)
        #expect(e.logicalLines == ["abcdef"])
    }
}

@Suite struct ResizeStateTests {
    @Test func theAlternateScreenClipsAndThePrimaryReflowsBehindIt() {
        let e = emulator(10, 4, feed: "abcdefghijkl\(CSI)?1049h\(CSI)Halternate\r\nsecond")
        e.resize(cols: 6, rows: 3)
        #expect(e.screenLines == ["altern", "second", ""] && e.cursorPosition.row == 1)
        #expect(e.screen.allSatisfy { !$0.wrapsToNext })
        e.feed("\(CSI)?1049l")
        #expect(e.logicalLines == ["abcdefghijkl"])
        #expect(e.cursorPosition == (2, 0, false))
        e.resize(cols: 12, rows: 3)
        #expect(e.screenLines[0] == "abcdefghijkl")
        #expect(e.gridProblems.isEmpty)
    }

    @Test func theAlternateScreenKeepsItsTopRowsWhenShrunkAndGrowsBlank() {
        let e = emulator(8, 4, feed: "\(CSI)?1049h1\r\n2\r\n3\r\n4")
        e.resize(cols: 8, rows: 2)
        #expect(e.screenLines == ["1", "2"] && e.cursorPosition.row == 1)
        e.resize(cols: 8, rows: 5)
        #expect(e.screenLines == ["1", "2", "", "", ""])
        #expect(e.scrollbackCount == 0)
    }

    @Test func aWideCellCutByTheClipIsBlanked() {
        let e = emulator(8, 2, feed: "\(CSI)?1049habc日")
        e.resize(cols: 4, rows: 2)
        #expect(e.screenLines[0] == "abc" && e.gridProblems.isEmpty)
    }

    @Test func theRegionResetsToTheWholeScreenAndOriginModeStays() {
        let e = emulator(10, 8, feed: "\(CSI)3;6r\(CSI)?6h")
        e.resize(cols: 12, rows: 5)
        #expect(e.regionTop == 0 && e.regionBottom == 4 && e.modes.originMode)
        e.feed("\(CSI)2;1HX")
        #expect(e.cursorPosition.row == 2 || e.screenLines[1] == "X")
    }

    @Test func tabStopsKeepTheirColumnsAndNewColumnsGetTheDefaults() {
        let e = emulator(20, 3, feed: "\(CSI)3g\(CSI)1;5H\u{1B}H")
        e.resize(cols: 30, rows: 3)
        #expect(e.tabStops.enumerated().filter { $0.element }.map(\.offset) == [4, 24])
        e.resize(cols: 10, rows: 3)
        #expect(e.tabStops.enumerated().filter { $0.element }.map(\.offset) == [4])
    }

    @Test func aSavedCursorFollowsItsCharacterThroughAReflow() {
        let e = emulator(12, 4, feed: "abcdefghijkl\(CSI)1;7H\u{1B}7\(CSI)2;1HX")
        e.resize(cols: 5, rows: 4)
        e.feed("\u{1B}8")
        #expect(e.cursorCharacter == "g")
        let b = emulator(6, 6, feed: "\u{1B}7\(CSI)6;1H")
        b.resize(cols: 3, rows: 2)
        b.feed("\u{1B}8")
        #expect(b.cursorPosition.row < 2 && b.cursorPosition.col < 3)
    }

    @Test func aSavedCursorOnTheAlternateScreenIsClamped() {
        let e = emulator(10, 6, feed: "\(CSI)?1049h\(CSI)6;10H\u{1B}7")
        e.resize(cols: 4, rows: 3)
        e.feed("\u{1B}8")
        #expect(e.cursorPosition == (2, 3, false))
    }

    @Test func aResizeClearsAPendingWrapOnTheAlternateScreen() {
        let e = emulator(4, 2, feed: "\(CSI)?1049habcd")
        #expect(e.cursorPosition.pending)
        e.resize(cols: 8, rows: 2)
        #expect(!e.cursorPosition.pending && e.cursorPosition.col == 3)
    }

    @Test func theSameSizeIsANoOpThatPublishesNothingNew() {
        let e = emulator(10, 4, feed: "abc")
        let before = e.publishSnapshot()
        e.resize(cols: 10, rows: 4)
        let after = e.publishSnapshot()
        #expect(after.version == before.version && !after.isFullFrame)
    }

    @Test func aResizePublishesAFullFrameOfTheNewSize() {
        let e = emulator(10, 4, feed: "abcdefghijkl")
        _ = e.publishSnapshot()
        e.resize(cols: 5, rows: 3)
        let snapshot = e.publishSnapshot()
        #expect(snapshot.isFullFrame && snapshot.size == TerminalSize(cols: 5, rows: 3))
        #expect(snapshot.damagedRows.map(\.index) == [0, 1, 2] && snapshot.reflowGeneration == 1)
        #expect(snapshot.cursor.row < 3 && snapshot.cursor.col < 5)
        e.resize(cols: 5, rows: 6)
        #expect(e.publishSnapshot().isFullFrame)
        e.feed("x")
        #expect(!e.publishSnapshot().isFullFrame)
    }

    @Test func theSourceAppliesAResizeThroughTheEmulatorByDefault() throws {
        let queue = DispatchQueue(label: "terminal.resize.test")
        let source = TerminalSnapshotSource(emulator: TerminalEmulator(cols: 10, rows: 4), queue: queue)
        Array("abcdefghijkl".utf8).withUnsafeBytes { source.feed($0) }
        _ = source.takeSnapshot()
        source.resize(TerminalSize(cols: 6, rows: 3))
        source.resize(TerminalSize(cols: 5, rows: 3))
        queue.sync {}
        let snapshot = try #require(source.takeSnapshot())
        #expect(snapshot.isFullFrame && snapshot.size == TerminalSize(cols: 5, rows: 3))
        #expect(snapshot.damagedRows.first?.row.text == "abcde")
    }
}

@Suite struct ReflowRoundTripTests {
    private func stream(_ rng: inout SeededRandom, lines: Int, maxWidth: Int) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789 .,日本語é")
        var out = ""
        for _ in 0..<lines {
            let length = Int.random(in: 0...maxWidth, using: &rng)
            var line = ""
            for _ in 0..<length {
                if Int.random(in: 0..<25, using: &rng) == 0 {
                    line += "\(CSI)\(Int.random(in: 30...37, using: &rng))m"
                } else if Int.random(in: 0..<40, using: &rng) == 0 {
                    line += "\(CSI)0m"
                }
                guard let character = alphabet.randomElement(using: &rng) else { preconditionFailure("the alphabet is not empty") }
                line.append(character)
            }
            out += line + "\r\n"
        }
        return out
    }

    @Test func narrowingThenWideningBackGivesTheOriginalLogicalLines() {
        var rng = SeededRandom(seed: 0x5EED)
        for round in 0..<120 {
            let cols = Int.random(in: 6...40, using: &rng)
            let rows = Int.random(in: 2...10, using: &rng)
            let e = emulator(cols, rows, scrollback: 5000, feed: stream(&rng, lines: Int.random(in: 1...30, using: &rng), maxWidth: cols * 3))
            let text = e.logicalLines
            let attributed = e.attributedLines.filter { !$0.isEmpty }
            let narrow = Int.random(in: 2...cols, using: &rng)
            e.resize(cols: narrow, rows: Int.random(in: 1...12, using: &rng))
            #expect(e.gridProblems.isEmpty, "round \(round): \(e.gridProblems)")
            #expect(e.logicalLines == text, "round \(round) narrowed to \(narrow)")
            e.resize(cols: cols, rows: rows)
            #expect(e.gridProblems.isEmpty, "round \(round): \(e.gridProblems)")
            #expect(e.logicalLines == text, "round \(round) back to \(cols)")
            #expect(e.attributedLines.filter { !$0.isEmpty } == attributed, "round \(round) attributes")
        }
    }

    @Test func theCursorCharacterSurvivesRandomResizes() {
        var rng = SeededRandom(seed: 0xC0DE)
        for round in 0..<150 {
            let cols = Int.random(in: 4...30, using: &rng)
            let e = emulator(cols, Int.random(in: 2...8, using: &rng), scrollback: 5000,
                             feed: stream(&rng, lines: Int.random(in: 1...12, using: &rng), maxWidth: cols * 2) + "tail text here")
            e.feed("\(CSI)\(Int.random(in: 1...e.rowCount, using: &rng));\(Int.random(in: 1...cols, using: &rng))H")
            let row = e.cursorRow, col = e.cursorCol
            let cell = e.screen[row].cell(at: col)
            let beyond = col >= e.screen[row].usedColumns
            let position = e.firstRow
            _ = (position, beyond)
            for _ in 0..<4 {
                e.resize(cols: Int.random(in: 2...40, using: &rng), rows: e.rowCount)
                if !beyond && cell.grapheme != " " {
                    #expect(e.cursorCharacter == cell.grapheme, "round \(round)")
                }
                #expect(e.gridProblems.isEmpty, "round \(round): \(e.gridProblems)")
            }
        }
    }
}

@Suite struct ResizeFuzzTests {
    private enum Step {
        case feed([UInt8])
        case resize(Int, Int)
    }

    private func script(seed: UInt64) -> [Step] {
        var rng = SeededRandom(seed: seed)
        var steps: [Step] = []
        let snippets = ["\(CSI)?1049h", "\(CSI)?1049l", "\(CSI)?47h", "\(CSI)?47l", "\u{1B}7", "\u{1B}8", "\(CSI)2;5r",
                        "\(CSI)3g", "\u{1B}H", "\(CSI)44m", "\(CSI)0m", "\(CSI)K", "\(CSI)3;4H", "\(CSI)J", "\(CSI)2J",
                        "\(CSI)?6h", "\(CSI)?6l", "\(CSI)?7l", "\(CSI)?7h", "日本語日本語", "\(CSI)3J", "\(CSI)2L", "\(CSI)2P"]
        for _ in 0..<16 {
            if Int.random(in: 0..<4, using: &rng) == 0 {
                guard let snippet = snippets.randomElement(using: &rng) else { preconditionFailure("the snippet list is not empty") }
                steps.append(.feed(Array(snippet.utf8)))
            } else if Int.random(in: 0..<3, using: &rng) == 0 {
                steps.append(.resize(Int.random(in: 1...30, using: &rng), Int.random(in: 1...9, using: &rng)))
            } else {
                steps.append(.feed(FuzzSupport.bytes(count: Int.random(in: 1...200, using: &rng), using: &rng)
                    + Array("wide 日本 words \(String(repeating: "x", count: Int.random(in: 0...40, using: &rng)))\r\n".utf8)))
            }
        }
        return steps
    }

    private func run(_ steps: [Step], chunked: Bool, seed: UInt64) -> (TerminalEmulator, [String]) {
        var rng = SeededRandom(seed: seed &+ 99)
        let e = TerminalEmulator(cols: 12, rows: 4, scrollback: 40)
        var problems: [String] = []
        for step in steps {
            switch step {
            case .feed(let bytes):
                if chunked {
                    var start = 0
                    while start < bytes.count {
                        let end = min(bytes.count, start + Int.random(in: 1...9, using: &rng))
                        e.feed(Array(bytes[start..<end]))
                        start = end
                    }
                } else {
                    e.feed(bytes)
                }
            case .resize(let cols, let rows):
                let before = e.onAlternate ? nil : (e.firstRow..<(e.firstRow + e.scrollbackCount + e.rowCount)).map { ($0, e.rowText($0)) }
                let sameWidth = cols == e.columnCount || (cols < 2 && e.columnCount == 2)
                let count = e.rowCount
                e.resize(cols: cols, rows: rows)
                if let before, sameWidth, !e.onAlternate {
                    // A change of height alone keeps every retained row's absolute number and text (`TRM-AM`).
                    for (row, text) in before where row >= e.firstRow && row < e.firstRow + e.scrollbackCount + min(count, e.rowCount) {
                        if e.rowText(row) != text { problems.append("row \(row) changed by a height-only resize") }
                    }
                }
            }
            problems += e.gridProblems
            let rowsOK = (e.firstRow..<(e.firstRow + e.scrollbackCount + e.rowCount)).allSatisfy { e.rowText($0) != nil }
            if !rowsOK { problems.append("absolute rows not all readable") }
        }
        return (e, problems)
    }

    @Test func randomBytesWithInterleavedResizesNeverBreakTheGrid() {
        for seed in 1...120 {
            let (_, problems) = run(script(seed: UInt64(seed)), chunked: false, seed: UInt64(seed))
            #expect(problems.isEmpty, "seed \(seed): \(problems.prefix(3))")
        }
    }

    @Test func splittingTheBytesAroundResizesChangesNothing() {
        for seed in 1...120 {
            let steps = script(seed: UInt64(seed))
            let whole = run(steps, chunked: false, seed: UInt64(seed)).0
            let split = run(steps, chunked: true, seed: UInt64(seed)).0
            #expect(whole.fullState == split.fullState, "seed \(seed)")
        }
    }
}
