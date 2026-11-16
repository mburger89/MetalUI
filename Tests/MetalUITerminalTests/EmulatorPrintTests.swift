import Testing
@testable import MetalUITerminal

@Suite struct EmulatorPrintTests {
    @Test func textWrapsAtTheLastColumnAndPendingWrapHoldsTheCursor() {
        let e = TerminalEmulator(cols: 5, rows: 3)
        e.feed("abcde")
        #expect(e.screenLines == ["abcde", "", ""])
        #expect(e.cursorPosition == (0, 4, true))
        e.feed("f")
        #expect(e.screenLines == ["abcde", "f", ""])
        #expect(e.cursorPosition == (1, 1, false))
    }

    @Test func carriageReturnAndLineFeedClearPendingWrap() {
        let e = TerminalEmulator(cols: 5, rows: 3)
        e.feed("abcde\rX")
        #expect(e.screenLines == ["Xbcde", "", ""])
        e.feed("\u{1B}[3;1Hvwxyz\n")
        #expect(e.cursorPosition.pending == false)
        #expect(e.cursorPosition.col == 4)
    }

    @Test func backspaceFromPendingWrapMovesFromTheLastColumn() {
        let e = TerminalEmulator(cols: 5, rows: 2)
        e.feed("abcde\u{08}X")
        #expect(e.screenLines[0] == "abcXe")
    }

    @Test func withAutowrapOffTheLastColumnIsOverwritten() {
        let e = TerminalEmulator(cols: 4, rows: 2)
        e.feed("\u{1B}[?7labcdefg")
        #expect(e.screenLines == ["abcg", ""])
        #expect(e.modes.autowrap == false)
        #expect(e.cursorPosition == (0, 3, false))
        e.feed("\u{1B}[?7hxy")
        #expect(e.modes.autowrap)
        #expect(e.screenLines == ["abcx", "y"])
    }

    @Test func lineFeedAtTheBottomScrollsIntoScrollback() {
        let e = TerminalEmulator(cols: 6, rows: 2, scrollback: 2)
        e.feed("one\r\ntwo\r\nthree\r\nfour")
        #expect(e.screenLines == ["three", "four"])
        #expect(e.historyLines == ["one", "two"])
        #expect(e.firstRow == 0)
        e.feed("\r\nfive")
        #expect(e.firstRow == 1)
        #expect(e.historyLines == ["two", "three"])
        #expect(e.rowText(0) == nil)
        #expect(e.rowText(1) == "two")
        #expect(e.rowText(3) == "four")
        #expect(e.rowText(4) == "five")
        #expect(e.rowText(5) == nil)
    }

    @Test func zeroScrollbackKeepsNothing() {
        let e = TerminalEmulator(cols: 4, rows: 1, scrollback: 0)
        e.feed("a\r\nb\r\nc")
        #expect(e.screenLines == ["c"])
        #expect(e.firstRow == 2)
        #expect(e.rowText(1) == nil)
    }

    @Test func tabsGoToTheNextMultipleOfEightAndStopAtTheEdge() {
        let e = TerminalEmulator(cols: 12, rows: 1)
        e.feed("a\tb\t\tc")
        #expect(e.screenLines == ["a       b  c"])
        #expect(e.cursorPosition.col == 11)
    }

    @Test func cursorMovementClampsAndDefaultsToOne() {
        let e = TerminalEmulator(cols: 10, rows: 5)
        e.feed("\u{1B}[3;4H")
        #expect(e.cursorPosition == (2, 3, false))
        e.feed("\u{1B}[A\u{1B}[2B\u{1B}[C\u{1B}[3D")
        #expect(e.cursorPosition == (3, 1, false))
        e.feed("\u{1B}[99A\u{1B}[99D")
        #expect(e.cursorPosition == (0, 0, false))
        e.feed("\u{1B}[99;99H")
        #expect(e.cursorPosition == (4, 9, false))
        e.feed("\u{1B}[H")
        #expect(e.cursorPosition == (0, 0, false))
        e.feed("\u{1B}[0;0H\u{1B}[0A\u{1B}[0C")
        #expect(e.cursorPosition == (0, 1, false))
        e.feed("\u{1B}[5G\u{1B}[3d")
        #expect(e.cursorPosition == (2, 4, false))
        e.feed("\u{1B}[2;3f")
        #expect(e.cursorPosition == (1, 2, false))
        e.feed("\u{1B}[2E")
        #expect(e.cursorPosition == (3, 0, false))
        e.feed("\u{1B}[F")
        #expect(e.cursorPosition == (2, 0, false))
    }

    @Test func movingTheCursorClearsPendingWrap() {
        let e = TerminalEmulator(cols: 3, rows: 2)
        e.feed("abc\u{1B}[D")
        #expect(e.cursorPosition == (0, 1, false))
        e.feed("X")
        #expect(e.screenLines == ["aXc", ""])
    }

    @Test func indAndNelAndTheirC1Forms() {
        let e = TerminalEmulator(cols: 6, rows: 3)
        e.feed("ab\u{1B}Dcd\u{1B}Eef")
        #expect(e.screenLines == ["ab", "  cd", "ef"])
        e.feed([0xC2, 0x85, 0x67, 0xC2, 0x84, 0x68])
        #expect(e.screenLines.last?.hasPrefix("h") == false)
        #expect(e.historyLines.count == 2)
    }

    @Test func wideCharactersTakeTwoCellsAndWrapWhole() {
        let e = TerminalEmulator(cols: 5, rows: 3)
        e.feed("ab\u{4E2D}\u{6587}c")
        // "ab" + wide(2) fits 4 columns; the second wide char cannot fit the last column and wraps whole.
        #expect(e.screenLines == ["ab\u{4E2D}", "\u{6587}c", ""])
        #expect(e.screen[0].cell(at: 2).width == 2)
        #expect(e.screen[0].cell(at: 3).grapheme == "\u{4E2D}")
        #expect(e.screen[0].columns == 5)
    }

    @Test func aWideCharacterEndingTheRowLeavesPendingWrap() {
        let e = TerminalEmulator(cols: 4, rows: 2)
        e.feed("ab\u{4E2D}")
        #expect(e.cursorPosition == (0, 3, true))
        e.feed("z")
        #expect(e.screenLines == ["ab\u{4E2D}", "z"])
    }

    @Test func overwritingHalfOfAWideCharacterBlanksTheOtherHalf() {
        let e = TerminalEmulator(cols: 6, rows: 1)
        e.feed("\u{4E2D}\u{6587}\u{1B}[1;2HX")
        #expect(e.screenLines == [" X\u{6587}"])
        e.feed("\u{1B}[1;4HY")
        #expect(e.screenLines == [" X Y"])
    }

    @Test func combiningMarksJoinThePreviousCell() {
        let e = TerminalEmulator(cols: 6, rows: 1)
        e.feed("e\u{301}x")
        #expect(e.screen[0].graphemes.count == 2)
        #expect(e.screen[0].cell(at: 0).grapheme == "e\u{301}")
        #expect(e.cursorPosition.col == 2)
        e.feed("\u{1B}[1;1H\u{301}")  // a mark at the very start has nothing to join
        #expect(e.screen[0].graphemes.count == 2)
    }

    @Test func modesFollowSetAndReset() {
        let e = TerminalEmulator(cols: 4, rows: 2)
        #expect(e.modes == TerminalModes())
        e.feed("\u{1B}[?1h\u{1B}[?2004h\u{1B}[?1004h\u{1B}[?25l\u{1B}[?1002h\u{1B}[?1006h\u{1B}=")
        #expect(e.modes.applicationCursorKeys && e.modes.bracketedPaste && e.modes.focusEvents)
        #expect(!e.modes.cursorVisible && e.modes.applicationKeypad)
        #expect(e.modes.mouseTracking == .buttonEvent && e.modes.mouseEncoding == .sgr)
        e.feed("\u{1B}[?1l\u{1B}[?1000h\u{1B}[?1000l\u{1B}[?1002l\u{1B}[?1006l\u{1B}>\u{1B}[?25h\u{1B}[?2004l\u{1B}[?1004l")
        #expect(e.modes == TerminalModes())
    }

    @Test func unsupportedSequencesAreDroppedWithoutDisturbingText() {
        let e = TerminalEmulator(cols: 8, rows: 2)
        e.feed("a\u{1B}[1;31mb\u{1B}]0;t\u{07}c\u{1B}P1qxx\u{1B}\\d\u{1B}_a\u{1B}\\e")
        #expect(e.screenLines == ["abcde", ""])
    }
}

@Suite struct SnapshotPublishTests {
    @Test func theFirstPublishIsAFullFrameAndLaterOnesListOnlyDamage() {
        let e = TerminalEmulator(cols: 6, rows: 3)
        let first = e.publishSnapshot()
        #expect(first.isFullFrame && first.damagedRows.map(\.index) == [0, 1, 2])
        let idle = e.publishSnapshot()
        #expect(!idle.isFullFrame && idle.damagedRows.isEmpty)
        #expect(idle.version == first.version)
        e.feed("\u{1B}[2;1Hhi")
        let next = e.publishSnapshot()
        #expect(next.damagedRows.map(\.index) == [1])
        #expect(next.damagedRows[0].row.text == "hi")
        #expect(next.version > idle.version)
        #expect(next.size == TerminalSize(cols: 6, rows: 3) && next.viewportOffset == 0)
        #expect(next.selection == nil && next.links.isEmpty)
    }

    @Test func aCursorOnlyChangeBumpsTheVersionWithoutDamage() {
        let e = TerminalEmulator(cols: 6, rows: 3)
        let a = e.publishSnapshot()
        e.feed("\u{1B}[2;2H")
        let b = e.publishSnapshot()
        #expect(b.damagedRows.isEmpty && b.version > a.version && b.cursor.row == 1)
    }

    @Test func scrollingDamagesEveryRow() {
        let e = TerminalEmulator(cols: 4, rows: 3)
        _ = e.publishSnapshot()
        e.feed("a\r\nb\r\nc\r\nd")
        #expect(e.publishSnapshot().damagedRows.map(\.index) == [0, 1, 2])
    }

    @Test func anUndamagedRowSharesStorageWithTheEarlierSnapshot() {
        let e = TerminalEmulator(cols: 8, rows: 3)
        e.feed("keep\r\n")
        let a = e.publishSnapshot()
        e.feed("\u{1B}[3;1Hnew")
        let b = e.publishSnapshot()
        let keptA = a.damagedRows[0].row
        #expect(b.damagedRows.map(\.index) == [2])
        #expect(e.screen[0].bytes.withUnsafeBufferPointer { $0.baseAddress } == keptA.bytes.withUnsafeBufferPointer { $0.baseAddress })
    }

    @Test func sizesClampToTwoByOne() {
        #expect(TerminalSize(cols: 0, rows: -3) == TerminalSize(cols: 2, rows: 1))
        let e = TerminalEmulator(cols: 0, rows: 0)
        #expect(e.publishSnapshot().size == TerminalSize(cols: 2, rows: 1))
    }

    @Test func positionsOrderByRowThenColumn() {
        #expect(TerminalPosition(row: 1, col: 9) < TerminalPosition(row: 2, col: 0))
        #expect(TerminalPosition(row: 2, col: 1) < TerminalPosition(row: 2, col: 3))
        #expect(!(TerminalPosition(row: 2, col: 3) < TerminalPosition(row: 2, col: 3)))
    }
}
