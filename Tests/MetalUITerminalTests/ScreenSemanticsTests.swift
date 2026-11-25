import Testing
@testable import MetalUITerminal

private let CSI = "\u{1B}["

private func emulator(_ cols: Int, _ rows: Int, scrollback: Int = 10, feed input: String = "") -> TerminalEmulator {
    let e = TerminalEmulator(cols: cols, rows: rows, scrollback: scrollback)
    e.feed(input)
    return e
}

private func replies(_ e: TerminalEmulator) -> String {
    String(decoding: e.drainEvents().flatMap { event -> [UInt8] in
        if case .reply(let bytes) = event { return bytes }
        return []
    }, as: UTF8.self)
}

@Suite struct CursorRegionTests {
    @Test func cursorUpAndDownStopAtTheMarginsOnlyFromInsideTheRegion() {
        let e = emulator(5, 8, feed: "\(CSI)3;6r\(CSI)4;1H\(CSI)99A")
        #expect(e.cursorPosition.row == 2)
        e.feed("\(CSI)99B")
        #expect(e.cursorPosition.row == 5)
        e.feed("\(CSI)1;1H\(CSI)99B")  // from above the region, down stops at the bottom margin
        #expect(e.cursorPosition.row == 5)
        e.feed("\(CSI)8;1H\(CSI)99A")  // from below it, up stops at the top margin
        #expect(e.cursorPosition.row == 2)
        e.feed("\(CSI)8;1H\(CSI)99B")
        #expect(e.cursorPosition.row == 7)
        e.feed("\(CSI)1;1H\(CSI)99A")
        #expect(e.cursorPosition.row == 0)
    }

    @Test func anInvalidRegionIsIgnoredAndTheValidOneHomesTheCursor() {
        let e = emulator(5, 5, feed: "\(CSI)3;3H\(CSI)4;2r")
        #expect(e.regionTop == 0 && e.regionBottom == 4 && e.cursorPosition == (2, 2, false))
        let f = emulator(5, 5, feed: "\(CSI)3;3H\(CSI)4;4r")
        #expect(f.regionTop == 0 && f.regionBottom == 4 && f.cursorPosition.row == 2)
        f.feed("\(CSI)2;4r")
        #expect(f.regionTop == 1 && f.regionBottom == 3 && f.cursorPosition == (0, 0, false))
        f.feed("\(CSI)0;99r")
        #expect(f.regionTop == 0 && f.regionBottom == 4)
        f.feed("\(CSI)2;4r\(CSI)r")
        #expect(f.regionTop == 0 && f.regionBottom == 4)
    }

    @Test func lineOperationsOutsideTheRegionDoNothing() {
        let e = emulator(4, 5, feed: "a\r\nb\r\nc\r\nd\r\ne\(CSI)2;4r\(CSI)1;1H\(CSI)L\(CSI)5;1H\(CSI)M\(CSI)2;1H")
        #expect(e.screenLines == ["a", "b", "c", "d", "e"])
        e.feed("\(CSI)99L")
        #expect(e.screenLines == ["a", "", "", "", "e"])
        #expect(e.cursorPosition == (1, 0, false))
    }

    @Test func scrollUpAndDownCountsAreClampedToTheRegion() {
        let e = emulator(3, 4, feed: "a\r\nb\r\nc\r\nd\(CSI)2;3r\(CSI)99S")
        #expect(e.screenLines == ["a", "", "", "d"])
        e.feed("\(CSI)2;1Hx\(CSI)99T")
        #expect(e.screenLines == ["a", "", "", "d"])
        #expect(e.scrollbackCount == 0 && e.firstRow == 0)
    }

    @Test func scrollingTheWholeScreenKeepsRowsAndAPartialRegionDropsThem() {
        let e = emulator(3, 3, feed: "a\r\nb\r\nc\(CSI)1;2r\(CSI)2;1H\n")
        #expect(e.scrollbackCount == 0)
        #expect(e.screenLines == ["b", "", "c"])
        let f = emulator(3, 3, feed: "a\r\nb\r\nc\(CSI)2;3r\(CSI)3;1H\n")
        #expect(f.scrollbackCount == 0)
        #expect(f.screenLines == ["a", "c", ""])
        let g = emulator(3, 3, feed: "a\r\nb\r\nc\(CSI)S")
        #expect(g.historyLines == ["a"])
        #expect(g.firstRow == 0 && g.rowText(0) == "a" && g.rowText(1) == "b")
    }

    @Test func originModeAddressesRelativeToTheRegionAndClamps() {
        let e = emulator(5, 6, feed: "\(CSI)3;5r\(CSI)?6h")
        #expect(e.cursorPosition == (2, 0, false))
        e.feed("\(CSI)2;2H")
        #expect(e.cursorPosition == (3, 1, false))
        e.feed("\(CSI)99d")
        #expect(e.cursorPosition.row == 4)
        e.feed("\(CSI)6n")
        #expect(replies(e) == "\(CSI)3;2R")
        e.feed("\(CSI)?6l")
        #expect(e.cursorPosition == (0, 0, false) && !e.modes.originMode)
        e.feed("\(CSI)6n")
        #expect(replies(e) == "\(CSI)1;1R")
    }

    @Test func tabStopsClampAtTheEdgesAndBackTabStopsAtTheFirstColumn() {
        let e = emulator(20, 1, feed: "\(CSI)99I")
        #expect(e.cursorPosition.col == 19)
        e.feed("\(CSI)99Z")
        #expect(e.cursorPosition.col == 0)
        e.feed("\(CSI)2I")
        #expect(e.cursorPosition.col == 16)
        e.feed("\t\t")
        #expect(e.cursorPosition.col == 19)
        e.feed("\(CSI)2g")  // not a defined TBC mode: no change
        e.feed("\(CSI)1;1H\t")
        #expect(e.cursorPosition.col == 8)
    }
}

@Suite struct EditTests {
    @Test func insertingAndDeletingNextToAWideCharacterBlanksItsOtherHalf() {
        let wide = "\u{4E2D}"
        let e = emulator(6, 3, feed: "a\(wide)b\(CSI)1;3H\(CSI)@")
        // The insert lands inside the wide cell, which loses both halves.
        #expect(e.screenLines[0] == "a   b")
        e.feed("\(CSI)2;1Ha\(wide)b\(CSI)2;3H\(CSI)P")
        #expect(e.screenLines[1] == "a b")
        e.feed("\(CSI)3;1H\(wide)\(wide)\(wide)\(CSI)3;2H\(CSI)X")
        #expect(e.screenLines[2] == "  \(wide)\(wide)")
    }

    @Test func aWideCharacterPushedOffTheEndIsDroppedWhole() {
        let e = emulator(5, 1, feed: "ab\u{4E2D}c\(CSI)1;1H\(CSI)@")
        #expect(e.screenLines == [" ab\u{4E2D}"])
        e.feed("\(CSI)1;1H\(CSI)@")
        // "  ab" plus half of the wide cell, which cannot stay.
        #expect(e.screenLines == ["  ab"])
    }

    @Test func shiftedCellsKeepTheirRendition() {
        let e = emulator(8, 1, feed: "ab\(CSI)31mcd\(CSI)0mef\(CSI)1;2H\(CSI)2@")
        #expect(e.screenLines == ["a  bcdef"])
        #expect(e.screen[0].cell(at: 4).attributes.foreground == .indexed(1))
        #expect(e.screen[0].cell(at: 5).attributes.foreground == .indexed(1))
        #expect(e.screen[0].cell(at: 3).attributes == TerminalAttributes())
        e.feed("\(CSI)1;2H\(CSI)3P")
        #expect(e.screenLines == ["acdef"])
        #expect(e.screen[0].cell(at: 1).attributes.foreground == .indexed(1))
        #expect(e.screen[0].cell(at: 3).attributes == TerminalAttributes())
    }

    @Test func eraseToTheEndTrimsStorageAndEndsTheSoftWrap() {
        let e = emulator(4, 2, feed: "abcdef\(CSI)1;3H\(CSI)K")
        #expect(e.screen[0].text == "ab" && e.screen[0].usedColumns == 2)
        #expect(!e.screen[0].wrapsToNext)
        #expect(e.screen[0].runs.isEmpty)
    }

    @Test func eraseAtAPendingWrapErasesTheLastCellAndKeepsThePendingWrap() {
        let e = emulator(4, 1, feed: "abcd\(CSI)K")
        #expect(e.screenLines == ["abc"])
        #expect(e.cursorPosition == (0, 3, true))
        e.feed("\(CSI)@")
        #expect(e.cursorPosition.pending == false)
    }

    @Test func eraseWithABackgroundFillsTheRowAndScrollingBringsInTintedRows() {
        let e = emulator(3, 2, feed: "\(CSI)42m\(CSI)2J")
        #expect(e.screen[0].cell(at: 2).attributes.background == .indexed(2))
        #expect(e.screen[1].cell(at: 0).attributes.background == .indexed(2))
        e.feed("\(CSI)0m\(CSI)44m\(CSI)2;1H\n")
        #expect(e.screen[1].cell(at: 1).attributes.background == .indexed(4))
        #expect(e.screen[0].cell(at: 1).attributes.background == .indexed(2))
        #expect(e.scrollbackCount == 1)
    }

    @Test func insertAndDeleteLinesDamageOnlyTheRowsTheyTouch() {
        let e = emulator(4, 6, feed: "a\r\nb\r\nc\r\nd\r\ne\r\nf\(CSI)2;5r\(CSI)3;1H")
        _ = e.publishSnapshot()
        e.feed("\(CSI)L")
        #expect(e.publishSnapshot().damagedRows.map(\.index) == [2, 3, 4])
        #expect(e.screenLines == ["a", "b", "", "c", "d", "f"])
        e.feed("\(CSI)2M")
        #expect(e.screenLines == ["a", "b", "d", "", "", "f"])
    }

    @Test func repeatRepeatsTheLastPrintedCharacterIncludingWideAndTranslatedOnes() {
        let e = emulator(10, 2, feed: "\(CSI)3b")
        #expect(e.screenLines == ["", ""])
        e.feed("\u{4E2D}\(CSI)2b")
        #expect(e.screenLines[0] == "\u{4E2D}\u{4E2D}\u{4E2D}")
        e.feed("\u{1B}(0q\(CSI)2b")
        #expect(e.screenLines[0].hasSuffix("───"))
    }

    @Test func insertModeShiftsAWideCharacterIn() {
        let e = emulator(6, 1, feed: "abc\(CSI)1;1H\(CSI)4h\u{4E2D}")
        #expect(e.screenLines == ["\u{4E2D}abc"])
        #expect(e.cursorPosition.col == 2)
    }

    @Test func alignmentPatternResetsTheRegionAndHomesTheCursor() {
        let e = emulator(3, 3, feed: "\(CSI)2;3r\(CSI)3;3H\u{1B}#8")
        #expect(e.screenLines == ["EEE", "EEE", "EEE"])
        #expect(e.regionTop == 0 && e.regionBottom == 2 && e.cursorPosition == (0, 0, false))
    }
}

@Suite struct SaveRestoreAndResetTests {
    @Test func saveAndRestoreCarryPositionPenOriginModeCharsetAndPendingWrap() {
        let e = emulator(4, 4, feed: "\(CSI)2;3r\(CSI)?6h\(CSI)3;1H\u{1B}(0\(CSI)31mabcd\u{1B}7")
        #expect(e.cursorPosition == (2, 3, true))
        e.feed("\u{1B}(B\(CSI)0m\(CSI)?6l\(CSI)H")
        e.feed("\u{1B}8")
        #expect(e.cursorPosition == (2, 3, true))
        #expect(e.modes.originMode)
        #expect(e.pen.foreground == .indexed(1))
        #expect(e.charsets[0] == .decGraphics)
    }

    @Test func restoreWithNothingSavedGoesHomeWithDefaults() {
        let e = emulator(4, 4, feed: "\(CSI)31m\(CSI)3;3H\u{1B}8")
        #expect(e.cursorPosition == (0, 0, false))
        #expect(e.pen == TerminalAttributes())
    }

    @Test func eachScreenHasItsOwnSavedCursor() {
        let e = emulator(6, 3, feed: "\(CSI)2;2H\u{1B}7\(CSI)?1049h\(CSI)3;4H\u{1B}7\(CSI)H\(CSI)?1049l")
        #expect(e.cursorPosition == (1, 1, false))
        e.feed("\(CSI)H\(CSI)?1049h\u{1B}8")
        #expect(e.cursorPosition == (2, 3, false))
    }

    @Test func enteringTheAlternateScreenTwiceDoesNotSaveTwiceAndLeavingWithoutEnteringIsANoOp() {
        let e = emulator(6, 3, feed: "\(CSI)1;3H\(CSI)?1049h\(CSI)3;1H\(CSI)?1049h\(CSI)?1049l")
        #expect(e.cursorPosition == (0, 2, false) && !e.modes.alternateScreen)
        e.feed("\(CSI)3;5H\(CSI)?1049l")
        #expect(e.cursorPosition == (2, 4, false))
    }

    @Test func entering1049GivesABlankAlternateScreenButEntering47KeepsItsContents() {
        let a = emulator(6, 2, feed: "\(CSI)?1049hxyz\(CSI)?1049l\(CSI)?1049h")
        #expect(a.screenLines == ["", ""])
        let b = emulator(6, 2, feed: "\(CSI)?47hxyz\(CSI)?47l\(CSI)?47h")
        #expect(b.screenLines == ["xyz", ""])
    }

    @Test func theAlternateScreenSwitchPublishesAFullFrame() {
        let e = emulator(6, 3, feed: "text")
        _ = e.publishSnapshot()
        e.feed("\(CSI)?1049h")
        let snapshot = e.publishSnapshot()
        #expect(snapshot.isFullFrame && snapshot.modes.alternateScreen && snapshot.damagedRows.count == 3)
        e.feed("\(CSI)?1049l")
        let back = e.publishSnapshot()
        #expect(back.isFullFrame && back.damagedRows[0].row.text == "text")
    }

    @Test func softResetRestoresTheTerminalStateAndLeavesTheScreen() {
        let e = emulator(6, 3, feed: "abc\(CSI)2;3r\(CSI)?6h\(CSI)?25l\(CSI)?7l\(CSI)4h\(CSI)31m\u{1B}(0\(CSI)5 q\u{1B}=\(CSI)?1h\(CSI)?2004h\(CSI)!p")
        #expect(e.modes.cursorVisible && e.modes.autowrap && !e.modes.originMode)
        #expect(!e.modes.applicationKeypad && !e.modes.applicationCursorKeys)
        #expect(e.modes.cursorStyle == TerminalCursorStyle(shape: .block, blinking: false))
        #expect(e.modes.bracketedPaste)  // untouched
        #expect(e.regionTop == 0 && e.regionBottom == 2 && e.pen == TerminalAttributes())
        #expect(!e.insertMode && e.charsets[0] == .ascii)
        #expect(e.screenLines[0] == "abc")
    }

    @Test func hardResetClearsTheScreenAndEveryModeButKeepsScrollback() {
        let e = emulator(6, 2, feed: "1\r\n2\r\n3\(CSI)?1049h\(CSI)?1h\(CSI)2;2r\(CSI)31m\u{1B}c")
        #expect(e.publishSnapshot().isFullFrame)
        #expect(e.screenLines == ["", ""])
        #expect(e.historyLines == ["1"])
        #expect(e.modes == TerminalModes() && !e.onAlternate)
        #expect(e.cursorPosition == (0, 0, false) && e.pen == TerminalAttributes())
        #expect(e.regionTop == 0 && e.regionBottom == 1)
    }
}

@Suite struct ReplyTests {
    @Test func repliesQueueInOrderAndDrainingEmptiesTheQueue() {
        let e = emulator(10, 5, feed: "\(CSI)c\(CSI)5n\(CSI)2;3H\(CSI)6n")
        #expect(e.drainEvents() == [.reply(Array("\(CSI)?62;22c".utf8)), .reply(Array("\(CSI)0n".utf8)),
                                    .reply(Array("\(CSI)2;3R".utf8))])
        #expect(e.drainEvents() == [])
    }

    @Test func aReplyCutByTheEndOfAFeedCompletesWithTheNext() {
        let e = emulator(10, 5, feed: "\(CSI)")
        #expect(e.drainEvents() == [])
        e.feed("6")
        e.feed("n")
        #expect(replies(e) == "\(CSI)1;1R")
    }

    @Test func requestsWithOtherParametersAreNotAnswered() {
        let e = emulator(10, 5, feed: "\(CSI)1c\(CSI)>1c\(CSI)7n\(CSI)=c\(CSI)?5n")
        #expect(e.drainEvents() == [])
    }

    @Test func theCursorReportOfAPendingWrapIsTheLastColumn() {
        let e = emulator(4, 2, feed: "abcd\(CSI)6n\(CSI)?6n")
        #expect(replies(e) == "\(CSI)1;4R\(CSI)?1;4;1R")
    }

    @Test func modeReportsFollowTheModes() {
        let e = emulator(10, 5)
        let modes: [(Int, String, String)] = [(1, "h", "l"), (6, "h", "l"), (7, "l", "h"), (12, "h", "l"), (25, "l", "h"),
                                              (1000, "h", "l"), (1002, "h", "l"), (1003, "h", "l"), (1004, "h", "l"),
                                              (1005, "h", "l"), (1006, "h", "l"), (2004, "h", "l"), (1049, "h", "l")]
        for (number, change, undo) in modes {
            let defaultOn = number == 7 || number == 25
            e.feed("\(CSI)?\(number)$p")
            #expect(replies(e) == "\(CSI)?\(number);\(defaultOn ? 1 : 2)$y", "default of \(number)")
            e.feed("\(CSI)?\(number)\(change)\(CSI)?\(number)$p")
            #expect(replies(e) == "\(CSI)?\(number);\(defaultOn ? 2 : 1)$y", "changed \(number)")
            e.feed("\(CSI)?\(number)\(undo)")
        }
        e.feed("\(CSI)?69$p\(CSI)?5$p\(CSI)4$p\(CSI)4h\(CSI)4$p\(CSI)20$p")
        #expect(replies(e) == "\(CSI)?69;4$y\(CSI)?5;0$y\(CSI)4;2$y\(CSI)4;1$y\(CSI)20;4$y")
    }

    @Test func belIsAnEventAndConsecutiveBellsCoalesce() {
        let e = emulator(4, 1, feed: "\u{07}\u{07}")
        #expect(e.drainEvents() == [.bell])
        e.feed("\u{07}\(CSI)5n\u{07}")
        #expect(e.drainEvents() == [.bell, .reply(Array("\(CSI)0n".utf8)), .bell])
    }

    @Test func aBellInsideAnOscIsATerminatorNotAnEvent() {
        let e = emulator(4, 1, feed: "\u{1B}]0;t\u{07}")
        #expect(e.drainEvents() == [.title("t")])
    }

    @Test func theQueueIsBoundedAtAThousandAndTwentyFourEvents() {
        let e = emulator(4, 1, feed: String(repeating: "\(CSI)5n", count: 2000))
        #expect(e.drainEvents().count == 1024)
        #expect(e.drainEvents().isEmpty)
    }

    @Test func eventsCompareByValue() {
        #expect(TerminalEvent.reply([1]) == .reply([1]) && TerminalEvent.reply([1]) != .reply([2]))
        #expect(TerminalEvent.title("a") != .bell)
    }
}

@Suite struct SGRTests {
    private func pen(_ sequence: String) -> TerminalAttributes {
        let e = emulator(4, 1, feed: "\(CSI)\(sequence)m")
        return e.pen
    }

    @Test func theSemicolonAndColonFormsOfTheSameColourAgree() {
        var rgb = TerminalAttributes()
        rgb.foreground = .rgb(1, 2, 3)
        #expect(pen("38;2;1;2;3") == rgb)
        #expect(pen("38:2:1:2:3") == rgb)
        #expect(pen("38:2::1:2:3") == rgb)
        #expect(pen("38:2:9:1:2:3") == rgb)
        var indexed = TerminalAttributes()
        indexed.background = .indexed(200)
        #expect(pen("48;5;200") == indexed)
        #expect(pen("48:5:200") == indexed)
    }

    @Test func aColourFollowedByMoreAttributesAppliesThem() {
        var a = TerminalAttributes()
        a.foreground = .rgb(1, 2, 3)
        a.bold = true
        a.background = .indexed(4)
        #expect(pen("1;38;2;1;2;3;44") == a)
        #expect(pen("38:2::1:2:3;1;44") == a)
    }

    @Test func malformedExtendedColoursChangeNothingAndStopTheSequence() {
        for bad in ["38", "38;5", "38;2;1;2", "38;5;256;1", "38;2;1;2;300;1", "38;7;1", "38:5", "38:2:1:2"] {
            #expect(pen("1;\(bad)") == pen("1"), "\(bad)")
        }
    }

    @Test func underlineStylesAndTheirColour() {
        #expect(pen("4").underlineStyle == .single)
        #expect(pen("4:0").underlineStyle == .none)
        #expect(pen("4:1").underlineStyle == .single)
        #expect(pen("4:2").underlineStyle == .double)
        #expect(pen("4:3").underlineStyle == .curly)
        #expect(pen("4:4").underlineStyle == .dotted)
        #expect(pen("4:5").underlineStyle == .dashed)
        #expect(pen("4:9").underlineStyle == .single)
        #expect(pen("21").underlineStyle == .double && pen("21").underline)
        #expect(pen("4;24").underlineStyle == .none)
        #expect(pen("58;5;7").underlineColor == .indexed(7))
        #expect(pen("58:2::1:2:3;59").underlineColor == .default)
    }

    @Test func everyFlagAndItsReset() {
        let on: [(String, KeyPath<TerminalAttributes, Bool>)] = [
            ("1", \.bold), ("2", \.dim), ("3", \.italic), ("5", \.blink), ("6", \.blink), ("7", \.inverse),
            ("8", \.hidden), ("9", \.strikethrough)
        ]
        for (code, path) in on { #expect(pen(code)[keyPath: path], "SGR \(code)") }
        #expect(!pen("1;22").bold && !pen("2;22").dim && !pen("1;2;22").dim)
        #expect(!pen("3;23").italic && !pen("5;25").blink && !pen("7;27").inverse)
        #expect(!pen("8;28").hidden && !pen("9;29").strikethrough)
        #expect(pen("1;3;4;5;7;8;9;0") == TerminalAttributes())
        #expect(pen("") == TerminalAttributes() && pen(";") == TerminalAttributes())
    }

    @Test func theSixteenColoursAndTheirDefaults() {
        for n in 0..<8 {
            #expect(pen("\(30 + n)").foreground == .indexed(UInt8(n)))
            #expect(pen("\(40 + n)").background == .indexed(UInt8(n)))
            #expect(pen("\(90 + n)").foreground == .indexed(UInt8(8 + n)))
            #expect(pen("\(100 + n)").background == .indexed(UInt8(8 + n)))
        }
        #expect(pen("31;39").foreground == .default && pen("41;49").background == .default)
    }

    @Test func unknownCodesAreIgnoredAndTheRestStillApplies() {
        #expect(pen("66;1;200;3") == pen("1;3"))
    }

    @Test func theRenditionIsWrittenWithTheText() {
        let e = emulator(6, 1, feed: "\(CSI)1;31mab\(CSI)0mcd")
        #expect(e.screen[0].cell(at: 1).attributes.bold && e.screen[0].cell(at: 1).attributes.foreground == .indexed(1))
        #expect(e.screen[0].cell(at: 2).attributes == TerminalAttributes())
        #expect(e.screen[0].runs.count == 2)
    }
}

@Suite struct CharsetTests {
    @Test func specialGraphicsMapEveryCodeOfTheSet() {
        var codes = ""
        for code in 0x5F...0x7E { codes.unicodeScalars.append(Unicode.Scalar(UInt8(code))) }
        let e = emulator(40, 2, feed: "\u{1B}(0" + codes)
        #expect(e.screenLines[0] == " ◆▒␉␌␍␊°±␤␋┘┐┌└┼⎺⎻─⎼⎽├┤┴┬│≤≥π≠£·")
    }

    @Test func charactersOutsideTheGraphicsRangeAndNonAsciiPassThrough() {
        let e = emulator(10, 1, feed: "\u{1B}(0A~\u{E9}[")
        #expect(e.screenLines == ["A·\u{E9}["])
    }

    @Test func theUKSetShowsThePoundForHash() {
        let e = emulator(10, 1, feed: "\u{1B}(A#a\u{1B}(B#")
        #expect(e.screenLines == ["\u{A3}a#"])
    }

    @Test func designatingG1DoesNotChangeG0UntilShiftOut() {
        let e = emulator(10, 1, feed: "\u{1B})0q\u{0E}q\u{0F}q")
        #expect(e.screenLines == ["q─q"])
    }

    @Test func aResetBetweenShiftsLeavesNoStaleTranslation() {
        let e = emulator(10, 1, feed: "\u{1B}(0\u{1B}c" + "q")
        #expect(e.screenLines == ["q"])
        #expect(!e.translating)
    }
}
