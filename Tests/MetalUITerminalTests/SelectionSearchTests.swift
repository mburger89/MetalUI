import Foundation
import Dispatch
import Testing
@testable import MetalUITerminal

private let CSI = "\u{1B}["

private func term(_ cols: Int, _ rows: Int, scrollback: Int = 100, _ input: String = "") -> TerminalEmulator {
    let e = TerminalEmulator(cols: cols, rows: rows, scrollback: scrollback)
    e.feed(input)
    return e
}

private func pos(_ row: Int, _ col: Int) -> TerminalPosition { TerminalPosition(row: row, col: col) }
private func range(_ a: TerminalPosition, _ b: TerminalPosition) -> TerminalRange {
    TerminalRange(lowerBound: a, upperBound: b)
}

extension TerminalEmulator {
    /// The absolute number of the screen's first row.
    var screenTop: Int { firstRow + scrollbackCount }
}

@Suite struct SelectionTextTests {
    @Test func aLinearSelectionTrimsTrailingBlanksPerRow() {
        let e = term(20, 4, "hello   world   \r\nsecond\r\n")
        e.selection = .linear(range(pos(0, 0), pos(1, 19)))
        #expect(e.selectedText() == "hello   world\nsecond")
        e.selection = .linear(range(pos(0, 6), pos(1, 2)))
        #expect(e.selectedText() == "  world\nsec")
    }

    @Test func theEndsMayComeInEitherOrder() {
        let e = term(20, 4, "abcdef\r\nghijkl\r\n")
        e.selection = .linear(range(pos(1, 2), pos(0, 3)))
        #expect(e.selectedText() == "def\nghi")
        #expect(e.selection == .linear(range(pos(1, 2), pos(0, 3))))
    }

    @Test func noSelectionIsNilAndABlankOneIsEmpty() {
        let e = term(10, 3, "x")
        #expect(e.selectedText() == nil)
        e.selection = .linear(range(pos(1, 0), pos(1, 5)))
        #expect(e.selectedText() == "")
    }

    @Test func aSoftWrappedRowJoinsWithoutANewlineAndAHardOneWithOne() {
        let e = term(5, 4, "abcdefgh\r\nxy")
        e.selection = .linear(range(pos(0, 0), pos(2, 4)))
        #expect(e.selectedText() == "abcdefgh\nxy")
        // Break the wrap by a hard line: the same width, no join.
        let hard = term(5, 4, "abcde\r\nfgh")
        hard.selection = .linear(range(pos(0, 0), pos(1, 4)))
        #expect(hard.selectedText() == "abcde\nfgh")
    }

    @Test func aWrappedRowKeepsItsTrailingBlanksBecauseTheyAreText() {
        let e = term(3, 4, "ab cd ef")
        #expect(e.screenLines.prefix(3) == ["ab", "cd", "ef"])
        e.selection = .linear(range(pos(0, 0), pos(2, 2)))
        #expect(e.selectedText() == "ab cd ef")
    }

    @Test func aSelectionEndingInsideAWrappedLineHasNoTrailingNewline() {
        let e = term(5, 4, "abcdefgh")
        e.selection = .linear(range(pos(0, 1), pos(0, 4)))
        #expect(e.selectedText() == "bcde")
    }

    @Test func aWideCharacterIsTakenOnceWhicheverHalfIsSelected() {
        let e = term(10, 2, "a世b")
        e.selection = .linear(range(pos(0, 1), pos(0, 1)))
        #expect(e.selectedText() == "世")
        e.selection = .linear(range(pos(0, 2), pos(0, 2)))
        #expect(e.selectedText() == "世")
        e.selection = .linear(range(pos(0, 0), pos(0, 3)))
        #expect(e.selectedText() == "a世b")
        e.selection = .linear(range(pos(0, 2), pos(0, 3)))
        #expect(e.selectedText() == "世b")
    }

    @Test func aSelectionRunsAcrossTheScrollbackBoundary() {
        let e = term(10, 3, scrollback: 50, (1...8).map { "line\($0)" }.joined(separator: "\r\n"))
        #expect(e.scrollbackCount == 5)
        let top = e.screenTop
        e.selection = .linear(range(pos(top - 2, 2), pos(top + 1, 3)))
        #expect(e.selectedText() == "ne4\nline5\nline6\nline")
        // The same absolute rows after more output scrolled them further.
        e.feed("\r\nmore")
        #expect(e.selectedText() == "ne4\nline5\nline6\nline")
    }

    @Test func aBlockSelectionTakesTheSameColumnsOfEveryRow() {
        let e = term(10, 4, "abcdef\r\nghi\r\njklmnop\r\n")
        e.selection = .block(range(pos(0, 1), pos(2, 3)))
        #expect(e.selectedText() == "bcd\nhi\nklm")
        e.selection = .block(range(pos(2, 3), pos(0, 1)))
        #expect(e.selectedText() == "bcd\nhi\nklm")
        e.selection = .block(range(pos(0, 4), pos(2, 2)))
        #expect(e.selectedText() == "cde\ni\nlmn")
    }

    @Test func aBlockSelectionJoinsWrappedRowsWithANewlineAndTakesAWideCharOnce() {
        let e = term(5, 4, "abcdefgh")
        e.selection = .block(range(pos(0, 2), pos(1, 4)))
        #expect(e.selectedText() == "cde\nh")
        let wide = term(10, 3, "a世b\r\ncdefg")
        wide.selection = .block(range(pos(0, 2), pos(1, 3)))
        #expect(wide.selectedText() == "世b\nef")
    }

    @Test func aSelectionIsClampedToTheRowsThatExist() {
        let e = term(6, 3, "abc\r\ndef")
        let top = e.screenTop
        e.selection = .linear(range(pos(top, 1), pos(top + 40, 2)))
        #expect(e.selection == .linear(range(pos(top, 1), pos(top + 2, 5))))
        e.selection = .linear(range(pos(top + 40, 0), pos(top + 50, 0)))
        #expect(e.selection == nil)
        e.selection = .linear(range(pos(top, -4), pos(top, 99)))
        #expect(e.selection == .linear(range(pos(top, 0), pos(top, 5))))
    }

    @Test func aFullLinearSelectionEqualsTheRowTextJoinedByTheWrapRules() throws {
        var rng = SeededRandom(seed: 0x5E1EC7)
        let alphabet = Array("ab cd  efgh世\u{301}z") + ["\r\n", "\r\n"].flatMap { Array($0) }
        for _ in 0..<60 {
            let cols = 4 + Int(rng.next() % 9)
            let rows = 2 + Int(rng.next() % 5)
            let e = term(cols, rows, scrollback: 8)
            var input = ""
            for _ in 0..<Int(rng.next() % 90) { input.append(alphabet[Int(rng.next() % UInt64(alphabet.count))]) }
            e.feed(input)
            let first = e.firstRow
            let last = e.screenTop + rows - 1
            e.selection = .linear(range(pos(first, 0), pos(last, cols - 1)))
            var expected = ""
            for row in first...last {
                let stored = try #require(e.row(at: row))
                let wraps = stored.wrapsToNext && row < last
                if wraps {
                    expected += String(decoding: stored.bytes, as: UTF8.self)
                } else {
                    expected += try #require(e.rowText(row))
                }
                if row < last && !wraps { expected += "\n" }
            }
            #expect(e.selectedText() == expected, "cols \(cols) rows \(rows) input \(input.debugDescription)")
        }
    }
}

@Suite struct SelectionLifecycleTests {
    @Test func aReflowClearsTheSelectionAndAHeightChangeKeepsIt() {
        let e = term(10, 4, "hello\r\nworld")
        e.selection = .linear(range(pos(0, 0), pos(1, 4)))
        e.resize(cols: 10, rows: 6)
        #expect(e.selectedText() == "hello\nworld")
        e.resize(cols: 8, rows: 6)
        #expect(e.selection == nil)
        #expect(e.selectedText() == nil)
        // A selection made after the reflow is of the new generation and survives a height change.
        e.selection = .linear(range(pos(0, 0), pos(0, 3)))
        e.resize(cols: 8, rows: 3)
        #expect(e.selectedText() == "hell")
    }

    @Test func aSelectionPartlyEvictedIsClippedAndAWhollyEvictedOneIsCleared() {
        let e = term(10, 2, scrollback: 3, "a1\r\na2\r\na3\r\na4\r\na5\r\na6")
        #expect(e.firstRow == 1 && e.rowText(1) == "a2")
        e.selection = .linear(range(pos(1, 1), pos(3, 1)))
        #expect(e.selectedText() == "2\na3\na4")
        e.feed("\r\na7")   // evicts row 1
        #expect(e.firstRow == 2)
        #expect(e.selection == .linear(range(pos(2, 0), pos(3, 1))))
        #expect(e.selectedText() == "a3\na4")
        e.feed("\r\na8\r\na9\r\na10")
        #expect(e.selection == nil)
    }

    @Test func outputOverwritingTheSelectedCellsClearsIt() {
        let e = term(10, 4, "hello\r\nworld")
        e.selection = .linear(range(pos(0, 1), pos(0, 3)))
        e.feed("\(CSI)2;1Hxx")   // another row
        #expect(e.selectedText() == "ell")
        e.feed("\(CSI)1;1Hh")   // the same row, outside the selected columns
        #expect(e.selectedText() == "ell")
        e.feed("\(CSI)1;3HX")   // inside
        #expect(e.selection == nil)
    }

    @Test func outputThatOnlyScrollsTheSelectionKeepsIt() {
        let e = term(10, 3, scrollback: 50, "one\r\ntwo\r\nthree")
        e.selection = .linear(range(pos(0, 0), pos(1, 2)))
        for n in 0..<10 { e.feed("\r\nrow\(n)") }
        #expect(e.selectedText() == "one\ntwo")
    }

    @Test func eraseInDisplayOverTheSelectionClearsIt() {
        let e = term(10, 3, "one\r\ntwo")
        e.selection = .linear(range(pos(0, 0), pos(0, 2)))
        e.feed("\(CSI)2J")
        #expect(e.selection == nil)
    }

    @Test func aSwitchToTheAlternateScreenAndBackClearsIt() {
        let e = term(10, 3, "one")
        e.selection = .linear(range(pos(0, 0), pos(0, 2)))
        e.feed("\(CSI)?1049h")
        #expect(e.selection == nil)
        e.feed("\(CSI)Halt")
        e.selection = .linear(range(pos(0, 0), pos(0, 2)))
        #expect(e.selectedText() == "alt")
        e.feed("\(CSI)?1049l")
        #expect(e.selection == nil)
    }

    @Test func aSelectionOverBlankCellsStillClearsOnTheSwitch() {
        let e = term(10, 3, "one")
        e.selection = .linear(range(pos(2, 0), pos(2, 4)))
        e.feed("\(CSI)?47h")
        #expect(e.selection == nil)
        e.selection = .linear(range(pos(2, 0), pos(2, 4)))
        e.feed("\(CSI)?47l")
        #expect(e.selection == nil)
    }

    @Test func theSnapshotCarriesTheSelectionAndAChangeIsAVersion() {
        let e = term(10, 3, "one")
        let before = e.publishSnapshot()
        #expect(before.selection == nil)
        #expect(e.publishSnapshot().version == before.version)
        e.selection = .block(range(pos(0, 0), pos(0, 1)))
        let after = e.publishSnapshot()
        #expect(after.selection == .block(range(pos(0, 0), pos(0, 1))))
        #expect(after.version > before.version)
        #expect(!after.isFullFrame && after.damagedRows.isEmpty)
        e.selection = nil
        #expect(e.publishSnapshot().selection == nil)
    }
}

@Suite struct ViewportTests {
    private func scrolled() -> TerminalEmulator {
        term(10, 3, scrollback: 20, (1...10).map { "r\($0)" }.joined(separator: "\r\n"))
    }

    @Test func theOffsetClampsToTheScrollbackAndPublishesAFullFrame() {
        let e = scrolled()
        #expect(e.scrollbackCount == 7)
        _ = e.publishSnapshot()
        e.scrollViewport(toOffset: 2)
        let s = e.publishSnapshot()
        #expect(s.viewportOffset == 2 && s.isFullFrame)
        #expect(s.damagedRows.map(\.index) == [0, 1, 2])
        #expect(s.damagedRows.map(\.row.text) == ["r6", "r7", "r8"])
        e.scrollViewport(toOffset: 500)
        #expect(e.publishSnapshot().viewportOffset == 7)
        e.scrollViewport(toOffset: -3)
        let live = e.publishSnapshot()
        #expect(live.viewportOffset == 0 && live.isFullFrame)
        #expect(live.damagedRows.map(\.row.text) == ["r8", "r9", "r10"])
    }

    @Test func aRepeatedOffsetIsNotAChange() {
        let e = scrolled()
        e.scrollViewport(toOffset: 3)
        _ = e.publishSnapshot()
        let version = e.publishSnapshot().version
        e.scrollViewport(toOffset: 3)
        let again = e.publishSnapshot()
        #expect(again.version == version && !again.isFullFrame)
    }

    @Test func outputWhileScrolledBackKeepsTheSameRowsInView() {
        let e = scrolled()
        e.scrollViewport(toOffset: 3)
        _ = e.publishSnapshot()
        e.feed("\r\nr11\r\nr12")
        let s = e.publishSnapshot()
        #expect(s.viewportOffset == 5)
        #expect(s.damagedRows.map(\.row.text) == ["r5", "r6", "r7"])
    }

    @Test func theCursorFollowsTheViewportAndHidesWhenOffTheBottom() {
        let e = scrolled()
        e.scrollViewport(toOffset: 1)
        let cursor = e.publishSnapshot().cursor
        #expect(cursor.row == 3 && !cursor.visible)
        e.scrollViewport(toOffset: 0)
        #expect(e.publishSnapshot().cursor.row == 2)
    }

    @Test func theAlternateScreenHasNoScrollbackToScrollAndEnteringResetsTheOffset() {
        let e = scrolled()
        e.scrollViewport(toOffset: 4)
        e.feed("\(CSI)?1049h")
        #expect(e.publishSnapshot().viewportOffset == 0)
        e.scrollViewport(toOffset: 4)
        #expect(e.publishSnapshot().viewportOffset == 0)
    }

    @Test func eraseScrollbackBringsTheViewportBack() {
        let e = scrolled()
        e.scrollViewport(toOffset: 4)
        e.feed("\(CSI)3J")
        #expect(e.publishSnapshot().viewportOffset == 0)
    }
}

@Suite struct SearchTests {
    @Test func forwardFindsTheFirstMatchAtOrAfterFrom() {
        let e = term(20, 4, "one two one\r\nthree one\r\n")
        let first = e.search("one", from: pos(0, 0), backwards: false)
        #expect(first == range(pos(0, 0), pos(0, 2)))
        #expect(e.search("one", from: pos(0, 1), backwards: false) == range(pos(0, 8), pos(0, 10)))
        #expect(e.search("one", from: pos(0, 8), backwards: false) == range(pos(0, 8), pos(0, 10)))
        #expect(e.search("one", from: pos(0, 9), backwards: false) == range(pos(1, 6), pos(1, 8)))
        #expect(e.search("one", from: pos(1, 7), backwards: false) == nil)
    }

    @Test func backwardsFindsTheLastMatchEndingBeforeFrom() {
        let e = term(20, 4, "one two one\r\nthree one\r\n")
        #expect(e.search("one", from: pos(3, 0), backwards: true) == range(pos(1, 6), pos(1, 8)))
        #expect(e.search("one", from: pos(1, 6), backwards: true) == range(pos(0, 8), pos(0, 10)))
        #expect(e.search("one", from: pos(1, 8), backwards: true) == range(pos(0, 8), pos(0, 10)))
        #expect(e.search("one", from: pos(1, 9), backwards: true) == range(pos(1, 6), pos(1, 8)))
        #expect(e.search("one", from: pos(0, 8), backwards: true) == range(pos(0, 0), pos(0, 2)))
        #expect(e.search("one", from: pos(0, 0), backwards: true) == nil)
    }

    @Test func aSearchDoesNotWrapAround() {
        let e = term(20, 3, "needle\r\nhay")
        #expect(e.search("needle", from: pos(1, 0), backwards: false) == nil)
        #expect(e.search("needle", from: pos(0, 3), backwards: true) == nil)
    }

    @Test func aMatchCanSpanASoftWrapButNotAHardBreak() {
        let e = term(5, 4, "abc xyzzy\r\nxyzzy")
        // "abc x" / "yzzy" soft-wrapped; "xyzzy" a separate hard line.
        #expect(e.search("c xy", from: pos(0, 0), backwards: false) == range(pos(0, 2), pos(1, 0)))
        #expect(e.search("zyx", from: pos(0, 0), backwards: false) == nil)
        let hard = term(5, 4, "abcde\r\nfghij")
        #expect(hard.search("efg", from: pos(0, 0), backwards: false) == nil)
        let wrapped = term(5, 4, "abcdefghij")
        #expect(wrapped.search("efg", from: pos(0, 0), backwards: false) == range(pos(0, 4), pos(1, 1)))
        #expect(wrapped.search("efg", from: pos(2, 0), backwards: true) == range(pos(0, 4), pos(1, 1)))
    }

    @Test func noMatchAndUnsearchableNeedlesAnswerNil() {
        let e = term(10, 2, "abc")
        #expect(e.search("zzz", from: pos(0, 0), backwards: false) == nil)
        #expect(e.search("", from: pos(0, 0), backwards: false) == nil)
        #expect(e.search("a\nb", from: pos(0, 0), backwards: false) == nil)
        #expect(e.search("ABC", from: pos(0, 0), backwards: false) == nil)
    }

    @Test func aNeedleWithWideCharactersReturnsTheirColumns() {
        let e = term(12, 2, "ab世界cd世")
        #expect(e.search("世界", from: pos(0, 0), backwards: false) == range(pos(0, 2), pos(0, 5)))
        #expect(e.search("界c", from: pos(0, 0), backwards: false) == range(pos(0, 4), pos(0, 6)))
        #expect(e.search("世", from: pos(0, 3), backwards: false) == range(pos(0, 8), pos(0, 9)))
        #expect(e.search("世", from: pos(0, 9), backwards: true) == range(pos(0, 2), pos(0, 3)))
    }

    @Test func aMatchNeverStartsOrEndsInsideACell() {
        let e = term(10, 2, "e\u{301}x")
        #expect(e.search("e", from: pos(0, 0), backwards: false) == nil)
        #expect(e.search("e\u{301}", from: pos(0, 0), backwards: false) == range(pos(0, 0), pos(0, 0)))
    }

    @Test func itSearchesScrollbackFromAnyPositionInIt() {
        let e = term(10, 3, scrollback: 50, (1...12).map { "row\($0) x" }.joined(separator: "\r\n"))
        let top = e.firstRow
        #expect(e.search("row3", from: pos(top, 0), backwards: false) == range(pos(top + 2, 0), pos(top + 2, 3)))
        #expect(e.search("row3", from: pos(top + 5, 0), backwards: true) == range(pos(top + 2, 0), pos(top + 2, 3)))
        #expect(e.search("row12", from: pos(top, 0), backwards: false) == range(pos(e.screenTop + 2, 0), pos(e.screenTop + 2, 4)))
        // Positions before the first retained row start at it; after the last, backwards starts at the end.
        #expect(e.search("row1", from: pos(-9, 0), backwards: false) == range(pos(top, 0), pos(top, 3)))
        #expect(e.search("row12", from: pos(top + 900, 0), backwards: true) == range(pos(e.screenTop + 2, 0), pos(e.screenTop + 2, 4)))
        #expect(e.search("row12", from: pos(top + 900, 0), backwards: false) == nil)
    }

    @Test func aFoundRangeCanBeAssignedAsTheSelection() throws {
        let e = term(5, 4, "say hello there")
        let found = try #require(e.search("hello", from: pos(0, 0), backwards: false))
        e.selection = .linear(found)
        #expect(e.selectedText() == "hello")
    }
}

@Suite struct WordAndLineTests {
    @Test func aWordIsLettersDigitsAndTheDefaultPunctuation() {
        let e = term(40, 2, "cd ~/src/my-app_1.swift: ok (x)")
        #expect(e.wordRange(at: pos(0, 6)) == range(pos(0, 3), pos(0, 23)))
        #expect(e.wordRange(at: pos(0, 0)) == range(pos(0, 0), pos(0, 1)))
        #expect(e.wordRange(at: pos(0, 28)) == range(pos(0, 28), pos(0, 28)))
        // A custom set.
        #expect(e.wordRange(at: pos(0, 6), wordCharacters: "") == range(pos(0, 5), pos(0, 7)))
    }

    @Test func blanksAndOtherCharactersSelectTheirOwnRun() {
        let e = term(40, 2, "ab   (( cd")
        #expect(e.wordRange(at: pos(0, 3)) == range(pos(0, 2), pos(0, 4)))
        #expect(e.wordRange(at: pos(0, 5)) == range(pos(0, 5), pos(0, 6)))
        // Past the text the blank run reaches the last column.
        #expect(e.wordRange(at: pos(0, 20)) == range(pos(0, 10), pos(0, 39)))
        #expect(e.wordRange(at: pos(0, 40)) == nil)
        #expect(e.wordRange(at: pos(9, 0)) == nil)
    }

    @Test func aWordCrossesASoftWrapAndASelectionOfItReadsBack() throws {
        let e = term(5, 4, "xx abcdefgh yy")
        let word = try #require(e.wordRange(at: pos(0, 4)))
        #expect(word == range(pos(0, 3), pos(2, 0)))
        e.selection = .linear(word)
        #expect(e.selectedText() == "abcdefgh")
    }

    @Test func theGapColumnLeftByAWideCharacterThatDidNotFitIsNotABlank() {
        let e = term(5, 3, "abcd世ef")
        #expect(e.screenLines.prefix(2) == ["abcd", "世ef"])
        #expect(e.wordRange(at: pos(0, 0)) == range(pos(0, 0), pos(1, 3)))
    }

    @Test func aWideCharacterIsOneCellOfAWord() {
        let e = term(20, 2, "a世b c")
        #expect(e.wordRange(at: pos(0, 2)) == range(pos(0, 0), pos(0, 3)))
    }

    @Test func aLineIsTheWholeLogicalLine() throws {
        let e = term(5, 5, "abcdefghij\r\nxy\r\n")
        #expect(e.lineRange(at: pos(1, 2)) == range(pos(0, 0), pos(1, 4)))
        #expect(e.lineRange(at: pos(0, 0)) == range(pos(0, 0), pos(1, 4)))
        #expect(e.lineRange(at: pos(2, 1)) == range(pos(2, 0), pos(2, 4)))
        e.selection = .linear(try #require(e.lineRange(at: pos(0, 3))))
        #expect(e.selectedText() == "abcdefghij")
        #expect(e.lineRange(at: pos(40, 0)) == nil)
    }
}

@Suite struct SelectionSourceTests {
    @Test func selectionAndSearchRunOnTheQueueThroughPerform() throws {
        let queue = DispatchQueue(label: "terminal.selection.test")
        let source = TerminalSnapshotSource(emulator: TerminalEmulator(cols: 20, rows: 4), queue: queue)
        Array("find the needle here\r\nsecond".utf8).withUnsafeBytes { source.feed($0) }
        let result = SnapshotBox<(String?, TerminalRange?)>()
        let done = DispatchSemaphore(value: 0)
        source.perform { emulator in
            let found = emulator.search("needle", from: pos(0, 0), backwards: false)
            emulator.selection = found.map { .linear($0) }
            emulator.scrollViewport(toOffset: 1)
            result.set((emulator.selectedText(), found))
            done.signal()
        }
        #expect(done.wait(timeout: .now() + 5) == .success)
        let (text, found) = try #require(result.get())
        #expect(text == "needle" && found == range(pos(0, 9), pos(0, 14)))
        queue.sync {}   // `perform` publishes after its closure returns; wait for that publish before taking the snapshot
        let snapshot = try #require(source.takeSnapshot())
        #expect(snapshot.selection == .linear(range(pos(0, 9), pos(0, 14))))
    }
}

private final class SnapshotBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T?
    func set(_ new: T) { lock.lock(); value = new; lock.unlock() }
    func get() -> T? { lock.lock(); defer { lock.unlock() }; return value }
}
