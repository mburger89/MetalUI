import Testing
@testable import MetalUITerminal

/// Feeding any partition of a byte stream gives the same state; random bytes never trap and never put the
/// cursor outside the grid.
@Suite struct ChunkSplitInvarianceTests {
    private func run(_ bytes: [UInt8], splitAt cuts: [Int]) -> String {
        let emulator = TerminalEmulator(cols: 10, rows: 4, scrollback: 5)
        var start = 0
        for cut in cuts + [bytes.count] {
            emulator.feed(Array(bytes[start..<cut]))
            start = cut
        }
        return emulator.fullState
    }

    @Test(arguments: 0..<mixedCorpus.count) func everyTwoWaySplitMatchesTheWholeFeed(_ index: Int) {
        let bytes = mixedCorpus[index]
        let whole = run(bytes, splitAt: [])
        for cut in 0...bytes.count {
            #expect(run(bytes, splitAt: [cut]) == whole, "cut \(cut) of corpus \(index)")
        }
    }

    @Test(arguments: 0..<mixedCorpus.count) func byteAtATimeAndSeededPartitionsMatch(_ index: Int) {
        let bytes = mixedCorpus[index]
        let whole = run(bytes, splitAt: [])
        #expect(run(bytes, splitAt: Array(0..<bytes.count)) == whole)
        var rng = SeededRandom(seed: UInt64(index) &+ 7)
        for _ in 0..<60 {
            let cuts = Set((0..<Int.random(in: 1...6, using: &rng)).map { _ in Int.random(in: 0...bytes.count, using: &rng) })
            #expect(run(bytes, splitAt: cuts.sorted()) == whole)
        }
    }

    @Test(arguments: 0..<mixedCorpus.count) func theParserEventsAreChunkInvariantToo(_ index: Int) {
        let bytes = mixedCorpus[index]
        let whole = parse(bytes)
        for cut in 0...bytes.count {
            var parser = VTParser(payloadCap: 4096)
            let recorder = Recorder()
            bytes[..<cut].withUnsafeBufferPointer { parser.feed($0, recorder) }
            bytes[cut...].withUnsafeBufferPointer { parser.feed($0, recorder) }
            #expect(recorder.events == whole, "cut \(cut) of corpus \(index)")
        }
    }

    @Test func aRandomStreamOfEverythingIsChunkInvariant() {
        var rng = SeededRandom(seed: 0xC0FFEE)
        for round in 0..<40 {
            let bytes = FuzzSupport.bytes(count: 300, using: &rng)
            let whole = run(bytes, splitAt: [])
            let cuts = Set((0..<8).map { _ in Int.random(in: 0...bytes.count, using: &rng) }).sorted()
            #expect(run(bytes, splitAt: cuts) == whole, "round \(round)")
        }
    }
}

enum FuzzSupport {
    /// Bytes weighted toward the ones that drive the state machine.
    static func bytes(count: Int, using rng: inout SeededRandom) -> [UInt8] {
        let hot: [UInt8] = [0x1B, 0x5B, 0x5D, 0x50, 0x5F, 0x58, 0x5E, 0x5C, 0x3B, 0x3A, 0x3F, 0x30, 0x31, 0x39, 0x48,
                            0x6D, 0x07, 0x18, 0x1A, 0x0A, 0x0D, 0x08, 0x09, 0xC2, 0x9B, 0x9C, 0x9D, 0x90, 0xE2, 0x82,
                            0xAC, 0xF0, 0x9F, 0xFF, 0x20, 0x41, 0x7F, 0x68, 0x6C]
        return (0..<count).map { _ in
            Int.random(in: 0..<4, using: &rng) == 0 ? UInt8.random(in: 0...255, using: &rng) : hot.randomElement(using: &rng)!
        }
    }
}

@Suite struct ParserFuzzTests {
    @Test func randomBytesNeverTrapAndTheCursorStaysInTheGrid() {
        var rng = SeededRandom(seed: 0xF022)
        for round in 0..<400 {
            let cols = Int.random(in: 1...25, using: &rng)
            let rows = Int.random(in: 1...8, using: &rng)
            let emulator = TerminalEmulator(cols: cols, rows: rows, scrollback: Int.random(in: 0...6, using: &rng),
                                            payloadCap: Int.random(in: 0...32, using: &rng))
            for _ in 0..<4 {
                emulator.feed(FuzzSupport.bytes(count: Int.random(in: 1...400, using: &rng), using: &rng))
                let snap = emulator.publishSnapshot()
                let c = snap.cursor
                #expect(c.row >= 0 && c.row < emulator.rowCount && c.col >= 0 && c.col < emulator.columnCount,
                        "round \(round): cursor \(c) outside \(emulator.columnCount)x\(emulator.rowCount)")
                #expect(emulator.screen.count == emulator.rowCount)
                #expect(emulator.screen.allSatisfy { $0.usedColumns <= emulator.columnCount })
                #expect(emulator.scrollbackCount <= emulator.scrollback.capacity)
                #expect((emulator.firstRow..<(emulator.firstRow + emulator.scrollbackCount + emulator.rowCount))
                    .allSatisfy { emulator.rowText($0) != nil })
            }
        }
    }

    @Test func pureNoiseWithNoBiasAlsoSurvives() {
        var rng = SeededRandom(seed: 99)
        let emulator = TerminalEmulator(cols: 7, rows: 3, scrollback: 2)
        for _ in 0..<200 {
            emulator.feed((0..<256).map { _ in UInt8.random(in: 0...255, using: &rng) })
        }
        let c = emulator.publishSnapshot().cursor
        #expect(c.row < 3 && c.col < 7)
    }
}
