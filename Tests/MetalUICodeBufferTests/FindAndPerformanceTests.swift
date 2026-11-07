import Testing
@testable import MetalUICodeBuffer

// MARK: Find

private func naiveFind(_ hay: [UInt8], _ query: String, fold: Bool, whole: Bool, limit: Int?) -> [Range<Int>] {
    func f(_ b: UInt8) -> UInt8 { fold && b >= 0x41 && b <= 0x5A ? b | 0x20 : b }
    func isWord(_ b: UInt8) -> Bool {
        (b >= 0x30 && b <= 0x39) || (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A) || b == 0x5F || b >= 0x80
    }
    let q = query.utf8.map(f)
    var out: [Range<Int>] = []
    if q.isEmpty { return out }
    var i = 0
    while i + q.count <= hay.count {
        if (0..<q.count).allSatisfy({ f(hay[i + $0]) == q[$0] }),
           !whole || ((i == 0 || !isWord(hay[i - 1])) && (i + q.count == hay.count || !isWord(hay[i + q.count]))) {
            out.append(i..<i + q.count)
            if let limit, out.count >= limit { break }
            i += q.count
        } else { i += 1 }
    }
    return out
}

@MainActor
@Suite struct FindTests {
    @Test func rangesMatchANaiveSearchAcrossChunkBoundaries() throws {
        var rng = SplitMix64(seed: 11)
        let text = fixtureText(lines: 1500) + "\nFoo foo FOO_x foo9 xfoo foo."
        let snap = CodeBuffer(text).snapshot()
        let bytes = Array(text.utf8)
        for query in ["foo", "FOO", "emoji", "é ü", "日本語", "😀", "\r\n", "ab", "func f1(x: Int)", "tabs", "a", "w1é w2é"] {
            for fold in [false, true] {
                for whole in [false, true] {
                    var options: CodeFindOptions = []
                    if fold { options.insert(.caseInsensitive) }
                    if whole { options.insert(.wholeWord) }
                    let limit: Int? = Int.random(in: 0..<3, using: &rng) == 0 ? 7 : nil
                    #expect(snap.ranges(of: query, options: options, limit: limit)
                            == naiveFind(bytes, query, fold: fold, whole: whole, limit: limit), "\(query) fold \(fold) whole \(whole)")
                }
            }
        }
        #expect(snap.ranges(of: "").isEmpty)
        #expect(snap.ranges(of: "foo", limit: 0).isEmpty)
        #expect(snap.ranges(of: "Foo", options: .wholeWord).count == 1)
    }

    @Test func aMatchSpanningTwoChunksIsFound() throws {
        // Every cut point of a 4000-byte run is somewhere inside a long needle repeated through it.
        let text = String(repeating: "needle-in-haystack ", count: 400)
        let snap = CodeBuffer(text).snapshot()
        #expect(snap.ranges(of: "needle-in-haystack").count == 400)
        #expect(snap.ranges(of: "k needle").count == 399)
    }
}

// MARK: Counted work

/// Nodes visited by `body`, read off `RopeStats`.
@MainActor private func visits(_ body: () -> Void) -> Int {
    let before = RopeStats.nodesVisited
    body()
    return RopeStats.nodesVisited - before
}

@MainActor
@Suite(.serialized) struct CodeBufferWorkTests {
    private static let small = CodeBuffer(fixtureText(lines: 1_000))
    private static let large = CodeBuffer(fixtureText(lines: 100_000))

    /// The largest node count one keystroke-sized edit visits, over `edits` random positions.
    private func worstEdit(_ buffer: CodeBuffer, edits: Int, seed: UInt64) -> (max: Int, mean: Double) {
        var rng = SplitMix64(seed: seed)
        var worst = 0, total = 0
        for i in 0..<edits {
            let at = randomBoundary(buffer.snapshot(), &rng)
            let v = visits {
                if i % 2 == 0 { buffer.replace(at..<at, with: "é") } else { buffer.replace(at..<advanced(buffer.snapshot(), at, scalars: 1), with: "") }
            }
            worst = max(worst, v)
            total += v
        }
        return (worst, Double(total) / Double(edits))
    }

    @Test func buildTouchesEachNodeOnceAndIsLinear() throws {
        for lines in [1_000, 100_000] {
            let text = fixtureText(lines: lines)
            let before = RopeStats.nodesVisited
            let rope = CodeBuffer(text).snapshot().rope
            let built = RopeStats.nodesVisited - before
            #expect(built == rope.nodeCount, "each node is created exactly once")
            let bytes = text.utf8.count
            #expect(rope.chunkCount * Rope.maxChunk >= bytes)
            #expect(rope.chunkCount * 256 <= bytes, "chunks average at least 256 bytes")
            #expect(rope.nodeCount * 2048 <= bytes, "an inner or leaf node per at least 2 KB")
            #expect(rope.problems().isEmpty)
        }
    }

    @Test func aKeystrokeVisitsLogarithmicallyManyNodes() throws {
        let a = worstEdit(Self.small, edits: 400, seed: 5)
        let b = worstEdit(Self.large, edits: 400, seed: 6)
        let chunks = Self.large.snapshot().rope.chunkCount
        let logN = Int.bitWidth - (chunks - 1).leadingZeroBitCount     // ceil(log2 n)
        #expect(b.max <= 4 * logN, "max \(b.max) of ceil(log2 \(chunks)) = \(logN)")
        let smallLog = Int.bitWidth - (Self.small.snapshot().rope.chunkCount - 1).leadingZeroBitCount
        #expect(a.max <= 4 * smallLog, "max \(a.max) of ceil(log2 n) = \(smallLog)")
        // Independent of n: 100x the lines costs only the extra levels of the tree.
        let extraLevels = Self.large.snapshot().rope.height - Self.small.snapshot().rope.height
        #expect(b.mean - a.mean <= Double(extraLevels * 12), "extra levels \(extraLevels)")
        #expect(Self.large.snapshot().rope.problems().isEmpty)
    }

    @Test func anExternalEditOfASmallHunkIsIndependentOfTheLineCount() throws {
        func external(_ buffer: CodeBuffer) throws -> Int {
            let n = buffer.utf8Count
            var rng = SplitMix64(seed: 77)
            let at = randomBoundary(buffer.snapshot(), &rng)
            let at2 = advanced(buffer.snapshot(), at, scalars: 4000)
            return try visits {
                _ = try? buffer.applyExternalEdits([
                    CodeTextEdit(range: at..<advanced(buffer.snapshot(), at, scalars: 5), text: "patched"),
                    CodeTextEdit(range: at2..<at2, text: "new line\n"),
                ], expectingVersion: buffer.version)
            }
        }
        let a = try external(CodeBuffer(fixtureText(lines: 1_000)))
        let b = try external(CodeBuffer(fixtureText(lines: 100_000)))
        let extra = CodeBuffer(fixtureText(lines: 100_000)).snapshot().rope.height - CodeBuffer(fixtureText(lines: 1_000)).snapshot().rope.height
        #expect(b - a <= extra * 24, "100k \(b) vs 1k \(a)")
        #expect(b <= 8 * (Int.bitWidth - (CodeBuffer(fixtureText(lines: 100_000)).snapshot().rope.chunkCount - 1).leadingZeroBitCount))
    }

    @Test func nodeStorageStaysWithin1Point3TimesTheText() throws {
        var rng = SplitMix64(seed: 21)
        for lines in [2_000, 100_000] {
            let text = fixtureText(lines: lines)
            let buffer = CodeBuffer(text)
            let built = Double(buffer.snapshot().rope.storageBytes) / Double(buffer.utf8Count)
            // Typing, backspacing and the occasional paste, which splits and merges chunks.
            for i in 0..<4_000 {
                let at = randomBoundary(buffer.snapshot(), &rng)
                switch i % 5 {
                case 0, 1, 2: buffer.replace(at..<at, with: "ab")
                case 3: buffer.replace(at..<advanced(buffer.snapshot(), at, scalars: 3), with: "")
                default: buffer.replace(at..<at, with: String(repeating: "paste é ", count: 40))
                }
            }
            let edited = Double(buffer.snapshot().rope.storageBytes) / Double(buffer.utf8Count)
            #expect(built <= 1.3)
            #expect(edited <= 1.3)
            #expect(buffer.snapshot().rope.problems().isEmpty)
        }
    }

    @Test func aSnapshotTakeIsConstantWork() throws {
        let v = visits { for _ in 0..<1000 { _ = Self.large.snapshot() } }
        #expect(v == 0)
    }
}

/// A random scalar boundary of a snapshot.
func randomBoundary(_ snap: CodeSnapshot, _ rng: inout SplitMix64) -> Int {
    var o = Int.random(in: 0...snap.utf8Count, using: &rng)
    while !snap.isScalarBoundary(o) { o += 1 }
    return o
}

/// The offset `scalars` scalars after `offset` (clamped to the end).
func advanced(_ snap: CodeSnapshot, _ offset: Int, scalars: Int) -> Int {
    snap.utf8Offset(ofScalar: min(snap.scalarCount, snap.scalarOffset(ofUTF8: offset) + scalars))
}
