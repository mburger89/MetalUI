import Testing
@testable import MetalUITerminal

private func ascii(_ s: String) -> [UInt8] { Array(s.utf8) }

private func write(_ row: inout TerminalRow, _ s: String, at column: Int, _ attrs: TerminalAttributes = TerminalAttributes()) {
    ascii(s).withUnsafeBufferPointer { row.writeASCII($0, at: column, attributes: attrs) }
}

private var red: TerminalAttributes {
    var a = TerminalAttributes()
    a.foreground = .indexed(1)
    return a
}
private var boldBlue: TerminalAttributes {
    var a = TerminalAttributes()
    a.bold = true
    a.background = .rgb(0, 0, 255)
    return a
}

/// The capacity this platform's allocator gives `[UInt8]` for an exact `reserveCapacity(n)`; what a tight array is.
private func exactRequestCapacity(_ n: Int) -> Int {
    var reference: [UInt8] = []
    reference.reserveCapacity(n)
    return reference.capacity
}

/// `TerminalRow.heapByteCount`'s formula for that reference array (header plus capacity, 16-byte granules).
private func referenceHeapBytes(forRequest n: Int) -> Int {
    (32 + exactRequestCapacity(n) + 15) / 16 * 16
}

@Suite struct RowStorageTests {
    @Test func plainTextStoresBytesAndNoSpans() {
        var row = TerminalRow(columns: 10)
        write(&row, "hello", at: 0)
        #expect(row.text == "hello" && row.runs.isEmpty && row.bytes.count == 5 && row.usedColumns == 5)
        #expect(row.cell(at: 1).grapheme == "e" && row.cell(at: 1).width == 1)
        #expect(row.cell(at: 7).grapheme == " " && row.cell(at: 7).attributes == TerminalAttributes())
        #expect(row.cell(at: -1).grapheme == " " && row.cell(at: 99).grapheme == " ")
    }

    @Test func attributeSpansAreRunLengthEncoded() {
        var row = TerminalRow(columns: 10)
        write(&row, "ab", at: 0)
        write(&row, "cde", at: 2, red)
        write(&row, "fg", at: 5, red)
        write(&row, "h", at: 7, boldBlue)
        #expect(row.runs.map(\.count) == [2, 5, 1])
        #expect(row.cell(at: 1).attributes == TerminalAttributes())
        #expect(row.cell(at: 2).attributes == red && row.cell(at: 6).attributes == red)
        #expect(row.cell(at: 7).attributes == boldBlue)
        #expect(row.graphemes.map(\.attributes) == [TerminalAttributes(), TerminalAttributes()] + Array(repeating: red, count: 5) + [boldBlue])
    }

    @Test func overwritingSplitsAndMergesSpans() {
        var row = TerminalRow(columns: 10)
        write(&row, "aaaaaa", at: 0, red)
        write(&row, "XX", at: 2, boldBlue)
        #expect(row.runs.map(\.count) == [2, 2, 2])
        write(&row, "YY", at: 2, red)
        #expect(row.runs.map(\.count) == [6])
        #expect(row.text == "aaYYaa")
        write(&row, "zzzzzz", at: 0)
        #expect(row.runs.isEmpty)
    }

    @Test func writingPastTheEndPadsWithDefaultBlanks() {
        var row = TerminalRow(columns: 10)
        write(&row, "a", at: 0, red)
        write(&row, "b", at: 4, red)
        #expect(row.text == "a   b" && row.usedColumns == 5)
        #expect(row.runs.map(\.count) == [1, 3, 1])
        #expect(row.cell(at: 2).attributes == TerminalAttributes())
    }

    @Test func wideCellsOccupyTwoColumnsAndOneGrapheme() {
        var row = TerminalRow(columns: 8)
        write(&row, "a", at: 0)
        row.put("\u{4E2D}", width: 2, at: 1, attributes: red)
        write(&row, "b", at: 3)
        #expect(row.usedColumns == 4 && row.text == "a\u{4E2D}b" && !row.isASCII)
        #expect(row.graphemes.map(\.width) == [1, 2, 1])
        #expect(row.cell(at: 1) == row.cell(at: 2))
        #expect(row.cell(at: 2).attributes == red && row.cell(at: 3).attributes == TerminalAttributes())
        #expect(row.cell(at: 3).grapheme == "b")
    }

    @Test func copiesShareStorageUntilOneWrites() {
        var a = TerminalRow(columns: 20)
        write(&a, String(repeating: "x", count: 18), at: 0)
        var b = a
        #expect(a.bytes.withUnsafeBufferPointer { $0.baseAddress } == b.bytes.withUnsafeBufferPointer { $0.baseAddress })
        write(&b, "Y", at: 0, red)
        #expect(a.text.hasPrefix("x") && b.text.hasPrefix("Y"))
        #expect(a.runs.isEmpty && !b.runs.isEmpty)
        #expect(a != b)
        var c = a
        #expect(c == a)
        write(&c, "x", at: 0)
        #expect(c == a)  // same content: equal, though the storage was copied
    }

    @Test func compactingTrimsBlanksAndSizesArraysExactly() {
        var row = TerminalRow(columns: 80)
        for _ in 0..<7 { write(&row, "ab ", at: row.usedColumns) }  // grows by doubling: spare capacity
        write(&row, "   ", at: row.usedColumns)
        let compact = row.compacted()
        #expect(compact.text == row.text && compact.usedColumns == 20)
        #expect(compact.bytes.capacity < 64)
        // "Exactly" is what the allocator hands back for an exact request: macOS and aarch64 Linux give 24 bytes for
        // 20 (64 heap bytes), while CI's x86_64 runner measured 80 for the same row (an allocator rounding that
        // `compact` cannot undo).
        // So the bound is 64 or the reference array's own size, whichever is larger: tight on every platform.
        // `compact` reallocates only when more than 16 bytes are spare, so the capacity may keep up to 16 spare where the
        // growth left little (Windows CI: the doubled capacity was within 16 of 20).
        #expect(compact.bytes.capacity <= max(exactRequestCapacity(20), 20 + 16))
        #expect(compact.heapByteCount <= max(64, referenceHeapBytes(forRequest: 20), (32 + 20 + 16 + 15) / 16 * 16))
        #expect(compact.columns == 80)
    }
}

@Suite struct ScrollbackRingTests {
    @Test func theOldestRowIsEvictedAtCapacity() {
        var ring = ScrollbackRing(capacity: 3)
        for i in 0..<5 {
            var row = TerminalRow(columns: 4)
            write(&row, String(i), at: 0)
            ring.append(row)
        }
        #expect(ring.count == 3)
        #expect((0..<3).map { ring[$0].text } == ["2", "3", "4"])
    }
}

@Suite struct ScrollbackCensusTests {
    /// The 4 MB budget of spec section 2.1 rule 8, measured by counting every byte the scrollback holds: its
    /// array, and the capacity of every row's two arrays (header and 16-byte granules included).
    @Test func tenThousandRowsOfOneHundredTwentyASCIIColumnsFitInFourMegabytes() {
        let e = TerminalEmulator(cols: 120, rows: 24, scrollback: 10_000)
        let line = String(repeating: "0123456789abcdefghijklmnopqrstuvwxyz", count: 4).prefix(120)
        var chunk = ""
        for i in 0..<10_500 {
            chunk += String(line.dropFirst(i % 7)) + String(line.prefix(i % 7)) + "\r\n"
            if i % 500 == 499 { e.feed(chunk); chunk = "" }
        }
        #expect(e.scrollbackCount == 10_000)
        #expect(e.firstRow == 477)  // 10 500 lines + the cursor row = 10 501 rows, 24 on screen, 10 000 kept
        let census = e.scrollback.byteCensus
        print("scrollback census: \(census) bytes for \(e.scrollbackCount) rows (\(census / e.scrollbackCount) per row)")
        #expect(census <= 4_000_000)
        #expect(census >= 10_000 * 120, "the census must at least count the text itself")
        #expect(e.rowText(e.firstRow)?.count == 120)
    }

    @Test func eachRowIsTheTextPlusOneSmallHeaderNotACellPerCharacter() {
        var row = TerminalRow(columns: 120)
        write(&row, String(repeating: "q", count: 120), at: 0)
        let compact = row.compacted()
        #expect(compact.heapByteCount <= max(120 + 48, referenceHeapBytes(forRequest: 120)))
        #expect(MemoryLayout<TerminalRow>.stride <= 40)
    }
}

/// `TRM-BL`: `setAttributes` edits the spans in place; whatever a random series of overwrites does, every column reads what
/// a per-column model says, the spans cover exactly the stored columns, no two neighbours are equal and an all-default row has
/// no spans. Mutation: not merging equal neighbours fails the neighbour check; a wrong splice index fails the per-column one.
@Suite struct RowSetAttributesTests {
    @Test func randomOverwritesMatchAPerColumnModel() {
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next(_ n: Int) -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int((seed >> 33) % UInt64(n))
        }
        var palette: [TerminalAttributes] = [TerminalAttributes()]
        for index in 1...3 {
            var a = TerminalAttributes()
            a.foreground = .indexed(UInt8(index))
            palette.append(a)
        }
        for round in 0..<300 {
            var row = TerminalRow(columns: 40)
            var model = [TerminalAttributes](repeating: TerminalAttributes(), count: 40)
            var stored = 0
            for _ in 0..<(1 + next(12)) {
                let start = next(40), length = 1 + next(40 - start)
                let attrs = palette[next(palette.count)]
                let text = String(repeating: "x", count: length)
                text.utf8.withContiguousStorageIfAvailable { row.writeASCII($0, at: start, attributes: attrs) }
                for column in start..<(start + length) { model[column] = attrs }
                stored = max(stored, start + length)
            }
            for column in 0..<40 {
                #expect(row.attributes(at: column) == (column < stored ? model[column] : TerminalAttributes()), "round \(round) column \(column)")
            }
            if row.runs.isEmpty {
                #expect(model[0..<stored].allSatisfy { $0 == TerminalAttributes() }, "round \(round) lost its spans")
            } else {
                #expect(row.runs.reduce(0) { $0 + Int($1.count) } == stored, "round \(round) covers \(stored)")
                #expect(!zip(row.runs, row.runs.dropFirst()).contains { $0.attributes == $1.attributes }, "round \(round) neighbours")
                #expect(!(row.runs.count == 1 && row.runs[0].attributes == TerminalAttributes()), "round \(round) one default span")
            }
        }
    }
}
