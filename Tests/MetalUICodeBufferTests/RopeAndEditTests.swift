import Testing
@testable import MetalUICodeBuffer

@MainActor
@Suite struct RopeAndEditTests {
    // MARK: Oracle

    @Test func randomEditsMatchAStringOracle() throws {
        var rng = SplitMix64(seed: 0xC0DE_B0FF)
        let text = fixtureText(lines: 2000)
        let buffer = CodeBuffer(text)
        var oracle = Oracle(text)
        let cursor = buffer.makeEditCursor()
        var replayed = Oracle(text)
        for step in 0..<1500 {
            let a = oracle.boundary(&rng)
            let width = Int.random(in: 0..<40, using: &rng) == 0 ? 20_000 : Int.random(in: 0..<30, using: &rng)
            var b = min(oracle.bytes.count, a + width)
            while b < oracle.bytes.count && oracle.bytes[b] & 0xC0 == 0x80 { b += 1 }
            let insert = insertionPool[Int.random(in: 0..<insertionPool.count, using: &rng)]
            buffer.replace(a..<b, with: insert)
            oracle.replace(a..<b, insert)
            let problems = buffer.snapshot().rope.problems()
            try #require(problems.isEmpty, "step \(step): \(problems)")
            if step % 25 == 0 {
                let difference = firstDifference(buffer.snapshot(), oracle, &rng)
                try #require(difference == nil, "step \(step): \(difference ?? "")")
            }
            // The stream replays onto a second oracle: every event is in pre-edit coordinates.
            if case .edits(let events) = cursor.drain() {
                for e in events { replayed.replace(e.range, e.newText) }
            }
            #expect(replayed.bytes == oracle.bytes, "step \(step): the replayed stream drifted")
        }
        #expect(firstDifference(buffer.snapshot(), oracle, &rng, probes: 200) == nil)
    }

    @Test func buildFromBytesAndFromAStringAgree() throws {
        var rng = SplitMix64(seed: 7)
        let text = fixtureText(lines: 3000)
        let fromString = CodeBuffer(text)
        let fromBytes = CodeBuffer(utf8: Array(text.utf8))
        #expect(fromString.snapshot().text == fromBytes.snapshot().text)
        #expect(fromBytes.snapshot().rope.problems().isEmpty)
        #expect(firstDifference(fromBytes.snapshot(), Oracle(text), &rng, probes: 100) == nil)
        #expect(!fromBytes.hadInvalidUTF8)
    }

    @Test func chunkBoundariesNeverSplitAScalarOrACRLF() throws {
        // Cut points land everywhere in these: between the two bytes of a CRLF, inside a 3-byte scalar.
        for text in [String(repeating: "\r\n", count: 3000), String(repeating: "日", count: 2500),
                     String(repeating: "x\r\n", count: 1500), String(repeating: "😀\r\n", count: 900),
                     (0..<400).map { String(repeating: "a", count: $0 % 37) + "\r\n" }.joined()] {
            let rope = CodeBuffer(text).snapshot().rope
            #expect(rope.problems().isEmpty, "\(rope.problems())")
            #expect(CodeBuffer(text).snapshot().text == text)
        }
    }

    @Test func aJoinedCRLFIsRepairedAcrossChunks() throws {
        // Deleting the byte between a chunk's "\r" and the next chunk's "\n" would leave them split.
        var rng = SplitMix64(seed: 99)
        for _ in 0..<40 {
            let text = (0..<900).map { _ in Int.random(in: 0..<3, using: &rng) == 0 ? "\r" : (Int.random(in: 0..<2, using: &rng) == 0 ? "\n" : "ab") }.joined()
            let buffer = CodeBuffer(text)
            var oracle = Oracle(text)
            for _ in 0..<60 {
                let a = oracle.boundary(&rng)
                let b = min(oracle.bytes.count, a + Int.random(in: 0..<4, using: &rng))
                let insert = ["", "\r", "\n", "\r\n", "x"][Int.random(in: 0..<5, using: &rng)]
                buffer.replace(a..<b, with: insert)
                oracle.replace(a..<b, insert)
                #expect(buffer.snapshot().rope.problems().isEmpty)
            }
            #expect(buffer.snapshot().text == oracle.string)
        }
    }

    // MARK: Snapshots

    @Test func aSnapshotIsUnchangedByLaterEdits() throws {
        let text = fixtureText(lines: 1500)
        let buffer = CodeBuffer(text)
        let early = buffer.snapshot()
        buffer.replace(10..<20, with: "CHANGED")
        let middle = buffer.snapshot()
        let middleText = middle.text
        for i in 0..<300 { let at = advanced(buffer.snapshot(), i * 7, scalars: 0); buffer.replace(at..<advanced(buffer.snapshot(), at, scalars: 1), with: "é") }
        buffer.replace(0..<buffer.utf8Count, with: "")
        #expect(early.text == text)
        #expect(early.version == 0)
        #expect(early.rope.problems().isEmpty)
        #expect(middle.text == middleText)
        #expect(middle.version == 1)
        #expect(buffer.snapshot().text == "")
    }

    @Test func aSnapshotCanBeReadOffTheMainActor() async throws {
        let buffer = CodeBuffer(fixtureText(lines: 500))
        let snap = buffer.snapshot()
        buffer.replace(0..<5, with: "edited")
        let count = await Task.detached { snap.lineCount }.value
        #expect(count == snap.lineCount)
    }

    // MARK: Conversions and lines

    @Test func conversionsAgreeWithTheOracleOnTheFixture() throws {
        var rng = SplitMix64(seed: 3)
        let text = fixtureText(lines: 4000)
        let snap = CodeBuffer(text).snapshot()
        #expect(firstDifference(snap, Oracle(text), &rng, probes: 150) == nil)
        #expect(snap.longestLineScalars >= 2400 * 4)
    }

    @Test func linesAndPointsHandleCRLFAndTheLastLine() throws {
        let snap = CodeBuffer("one\r\ntwo\n\nlast").snapshot()
        #expect(snap.lineCount == 4)
        #expect((0..<4).map { snap.line($0) } == ["one", "two", "", "last"])
        #expect(snap.lineRange(0) == 0..<3)
        #expect(snap.line(9) == "")
        #expect(snap.point(at: 5) == CodePoint(row: 1, column: 0))
        #expect(snap.offset(of: CodePoint(row: 9, column: 9)) == 14)
        #expect(snap.offset(of: CodePoint(row: 0, column: 99)) == 4)
        #expect(CodeBuffer("a\r\nb").lineEnding == .crlf)
        #expect(CodeBuffer("a\nb\r\n").lineEnding == .lf)
        #expect(CodeBuffer("none").lineEnding == .lf)
        #expect(CodeBuffer("").snapshot().lineCount == 1)
    }

    @Test func invalidUTF8IsRepairedAndReported() throws {
        let bad = CodeBuffer(utf8: [0x61, 0xFF, 0x62, 0xC3])
        #expect(bad.hadInvalidUTF8)
        #expect(bad.snapshot().text == "a\u{FFFD}b\u{FFFD}")
        #expect(bad.snapshot().rope.problems().isEmpty)
        #expect(!CodeBuffer(utf8: Array("añ😀".utf8)).hadInvalidUTF8)
    }

    // MARK: The event stream

    @Test func eventsCarryPreEditCoordinatesAndPoints() throws {
        let buffer = CodeBuffer("héllo\nwörld\nthird line")
        let cursor = buffer.makeEditCursor()
        // "wörld" starts at byte 7; the ö is two bytes.
        buffer.replace(8..<11, with: "AB\nCD")
        guard case .edits(let events) = cursor.drain(), let e = events.first else { Issue.record("no event"); return }
        #expect(e.range == 8..<11)
        #expect(e.scalarRange == 7..<9)
        #expect(e.startPoint == CodePoint(row: 1, column: 1))
        #expect(e.oldEndPoint == CodePoint(row: 1, column: 4))   // taken from the OLD text, not the new
        #expect(e.newEndPoint == CodePoint(row: 2, column: 2))
        #expect(e.newText == "AB\nCD")
        #expect(e.version == 1)
    }

    @Test func versionsRiseByExactlyOnePerEvent() throws {
        let buffer = CodeBuffer("abcdef")
        let cursor = buffer.makeEditCursor()
        buffer.replace(0..<1, with: "x")
        buffer.replace(2..<2, with: "y")
        buffer.transaction { b in
            b.replace(0..<0, with: "1")
            b.replace(1..<1, with: "2")
        }
        buffer.undo()                // reverts the transaction: two more events
        _ = try buffer.applyExternalEdits([CodeTextEdit(range: 0..<1, text: "q"), CodeTextEdit(range: 3..<4, text: "r")])
        guard case .edits(let events) = cursor.drain() else { Issue.record("resync"); return }
        #expect(events.map(\.version) == Array(1...UInt64(events.count)))
        #expect(events.count == 8)
        #expect(buffer.version == 8)
    }

    @Test func aSlowCursorIsToldToResync() throws {
        let buffer = CodeBuffer(fixtureText(lines: 200))
        buffer.editLogByteLimit = 400
        buffer.editLogMinimumEvents = 0
        let slow = buffer.makeEditCursor()
        let fast = buffer.makeEditCursor()
        for i in 0..<60 {
            buffer.replace(i..<i, with: String(repeating: "z", count: 20))
            if i % 5 == 0 { _ = fast.drain() }
        }
        guard case .resync(let snap) = slow.drain() else { Issue.record("expected resync"); return }
        #expect(snap.text == buffer.snapshot().text)
        #expect(snap.version == buffer.version)
        #expect(slow.version == buffer.version)
        buffer.replace(0..<0, with: "n")
        guard case .edits(let after) = slow.drain() else { Issue.record("expected edits"); return }
        #expect(after.count == 1)
        if case .edits(let f) = fast.drain() { #expect(f.count <= 1) }
    }

    @Test func mapCarriesAnOffsetThroughTheLog() throws {
        let buffer = CodeBuffer("0123456789")
        let v0 = buffer.version
        buffer.replace(2..<2, with: "AAA")      // insert before 5
        buffer.replace(0..<1, with: "")         // delete before it
        #expect(buffer.map(5, from: v0, bias: .before) == 7)
        // At an insertion point, bias decides.
        let v = buffer.version
        buffer.replace(4..<4, with: "XY")
        #expect(buffer.map(4, from: v, bias: .before) == 4)
        #expect(buffer.map(4, from: v, bias: .after) == 6)
        // Inside replaced text it collapses.
        let w = buffer.version
        buffer.replace(3..<8, with: "!")
        #expect(buffer.map(5, from: w, bias: .before) == 3)
        #expect(buffer.map(5, from: w, bias: .after) == 4)
        #expect(buffer.map(9, from: w, bias: .before) == 5)
        #expect(buffer.map(0, from: buffer.version + 1, bias: .before) == nil)
    }

    @Test func mapReturnsNilOnceTheLogIsTrimmed() throws {
        let buffer = CodeBuffer("abc")
        buffer.editLogMinimumEvents = 0
        buffer.editLogByteLimit = 0
        let v0 = buffer.version
        buffer.replace(0..<0, with: "zz")
        buffer.replace(0..<0, with: "zz")
        #expect(buffer.map(1, from: v0, bias: .before) == nil)
        #expect(buffer.map(1, from: buffer.version, bias: .before) == 1)
    }

    // MARK: Selections

    @Test func selectionsMoveWithEdits() throws {
        let buffer = CodeBuffer("0123456789ABCDEFGHIJ")
        // Replace 8..<16 (8 bytes) with 3. Before the span: unchanged. Inside: 2 bytes in stays 2 bytes in,
        // 7 bytes in clamps to the 3 inserted. After it: shifted by -5.
        buffer.selections = [CodeSelection(caret: 2), CodeSelection(caret: 10), CodeSelection(caret: 15), CodeSelection(caret: 18)]
        buffer.replace(8..<16, with: "abc")
        #expect(buffer.selections.map(\.head) == [2, 10, 11, 13])
    }

    @Test func aCaretInsideAReplacedSpanKeepsItsDistanceWhenTheTextIsTheSameSize() throws {
        let buffer = CodeBuffer("0123456789")
        buffer.selections = [CodeSelection(caret: 5)]
        buffer.replace(2..<8, with: "abcdef")
        #expect(buffer.selections == [CodeSelection(caret: 5)])
        buffer.replace(2..<8, with: "ab")
        #expect(buffer.selections == [CodeSelection(caret: 4)])    // 3 bytes in, clamped to the 2 inserted
        buffer.selections = [CodeSelection(caret: 3)]
        buffer.replace(2..<4, with: "WXYZ")
        #expect(buffer.selections == [CodeSelection(caret: 3)])    // 1 byte in stays 1 byte in
    }

    @Test func typingMovesTheCaretPastTheInsertionButAProgrammaticInsertDoesNot() throws {
        let buffer = CodeBuffer("ab")
        buffer.selections = [CodeSelection(caret: 1)]
        buffer.replace(1..<1, with: "X")
        #expect(buffer.selections == [CodeSelection(caret: 1)])
        buffer.replaceSelections(with: "Y")
        #expect(buffer.selections == [CodeSelection(caret: 2)])
        #expect(buffer.snapshot().text == "aYXb")
    }

    @Test func selectionsAreSortedAndMerged() throws {
        let buffer = CodeBuffer("0123456789")
        buffer.selections = [CodeSelection(caret: 7), CodeSelection(anchor: 4, head: 2), CodeSelection(caret: 3), CodeSelection(caret: 7)]
        #expect(buffer.selections == [CodeSelection(anchor: 4, head: 2), CodeSelection(caret: 7)])
        buffer.selections = [CodeSelection(anchor: 0, head: 99)]
        #expect(buffer.selections == [CodeSelection(anchor: 0, head: 10)])
        buffer.selections = []
        #expect(buffer.selections == [CodeSelection(caret: 0)])
    }

    @Test func replacingEverySelectionIsOneTransaction() throws {
        let buffer = CodeBuffer("a b c")
        buffer.selections = [CodeSelection(caret: 1), CodeSelection(caret: 3), CodeSelection(caret: 5)]
        let cursor = buffer.makeEditCursor()
        buffer.replaceSelections(with: "-")
        #expect(buffer.snapshot().text == "a- b- c-")
        #expect(buffer.selections.map(\.head) == [2, 5, 8])
        guard case .edits(let events) = cursor.drain() else { return }
        #expect(Set(events.map(\.transaction)).count == 1)
        #expect(events.map(\.range.lowerBound) == [5, 3, 1])      // highest first, in pre-edit coordinates
        buffer.undo()
        #expect(buffer.snapshot().text == "a b c")
        #expect(buffer.selections.map(\.head) == [1, 3, 5])
    }

    @Test func selectBumpsTheRevealSerialOnlyWhenAsked() throws {
        let buffer = CodeBuffer("hello")
        let s = buffer.revealSerial
        buffer.select(1..<3, reveal: false)
        #expect(buffer.revealSerial == s)
        buffer.select(1..<3)
        #expect(buffer.revealSerial == s + 1)
        #expect(buffer.selections == [CodeSelection(anchor: 1, head: 3)])
    }

    @Test func readOnlyRefusesEdits() throws {
        let buffer = CodeBuffer("abc")
        buffer.isReadOnly = true
        buffer.replace(0..<1, with: "x")
        #expect(buffer.snapshot().text == "abc")
        #expect(buffer.version == 0)
        #expect(throws: CodeBufferError.readOnly) { try buffer.applyExternalEdits([CodeTextEdit(range: 0..<1, text: "x")]) }
        buffer.select(1..<2)
        #expect(buffer.selections == [CodeSelection(anchor: 1, head: 2)])
    }
}
