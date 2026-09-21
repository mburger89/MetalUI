import Testing
import ReplayFixture

// Distinct byte values everywhere, so a field read from the wrong offset or
// in the wrong byte order changes the decoded fixture.
func sample(runs: [FixtureRun]? = nil) throws -> ReplayFixture {
    let rects = (0..<240).map { UInt8($0 & 0xFF) }              // two rects
    let glyphs = (0..<264).map { UInt8(($0 * 7 + 3) & 0xFF) }   // three glyphs
    return try ReplayFixture(
        width: 3, height: 2, rects: rects, glyphs: glyphs,
        runs: runs ?? [FixtureRun(kind: .rect, start: 0, count: 1),
                       FixtureRun(kind: .glyph, start: 0, count: 3),
                       FixtureRun(kind: .rect, start: 1, count: 1)],
        atlasWidth: 4, atlasHeight: 2, atlas: [9, 8, 7, 6, 5, 4, 3, 2],
        projection: (0..<16).map { Float($0) * 0.5 + 0.25 },
        reference: (0..<24).map { UInt8(200 - $0) })
}

@Test func roundTripPreservesEveryField() throws {
    let fixture = try sample()
    let decoded = try ReplayFixture(decoding: fixture.encoded())
    #expect(decoded == fixture)
    #expect(decoded.rectCount == 2)
    #expect(decoded.glyphCount == 3)
}

@Test func encodingIsLittleEndianWithMagicAndVersion() throws {
    let bytes = try sample().encoded()
    #expect(Array(bytes[0..<8]) == Array("MUIRPLY".utf8) + [0])
    #expect(Array(bytes[8..<12]) == [1, 0, 0, 0])       // version
    #expect(Array(bytes[12..<16]) == [3, 0, 0, 0])      // width
    #expect(Array(bytes[20..<24]) == [120, 0, 0, 0])    // rect stride
    #expect(Array(bytes[24..<28]) == [88, 0, 0, 0])     // glyph stride
}

@Test func everyTruncationIsRejected() throws {
    let bytes = try sample().encoded()
    try #require(bytes.count > 600)
    for length in 0..<bytes.count {
        #expect(throws: FixtureError.self) { try ReplayFixture(decoding: Array(bytes[0..<length])) }
    }
}

@Test func trailingBytesAreRejected() throws {
    #expect(throws: FixtureError.trailingBytes(1)) {
        try ReplayFixture(decoding: try sample().encoded() + [0])
    }
}

@Test func aChangedPrimitiveABIIsRejectedByName() throws {
    var bytes = try sample().encoded()
    bytes[20] = 128   // a 128-byte MUIRect: the shaders' 8-lane read would drift
    #expect(throws: FixtureError.strideMismatch(rect: 128, glyph: 88)) {
        try ReplayFixture(decoding: bytes)
    }
}

@Test func badMagicAndVersionAreRejected() throws {
    var bytes = try sample().encoded()
    bytes[0] = UInt8(ascii: "X")
    #expect(throws: FixtureError.badMagic) { try ReplayFixture(decoding: bytes) }
    bytes = try sample().encoded()
    bytes[8] = 2
    #expect(throws: FixtureError.unsupportedVersion(2)) { try ReplayFixture(decoding: bytes) }
}

@Test func aRunPastItsBufferIsRejected() throws {
    // Records are counted per kind: 3 glyphs exist, 2 rects do.
    #expect(throws: FixtureError.self) { try sample(runs: [FixtureRun(kind: .rect, start: 1, count: 2)]) }
    #expect(throws: FixtureError.self) { try sample(runs: [FixtureRun(kind: .glyph, start: 3, count: 1)]) }
    #expect(throws: FixtureError.self) { try sample(runs: [FixtureRun(kind: .rect, start: 0, count: 0)]) }
    #expect(throws: FixtureError.self) { try sample(runs: [FixtureRun(kind: .glyph, start: .max, count: 2)]) }
    _ = try sample(runs: [FixtureRun(kind: .glyph, start: 2, count: 1)])
}

@Test func anUnknownRunKindIsRejected() throws {
    let fixture = try sample()
    var bytes = fixture.encoded()
    let runsOffset = 8 + 4 + 16 + 4 + fixture.rects.count + 4 + fixture.glyphs.count + 4
    try #require(bytes[runsOffset] == 0)  // first run is a rect
    bytes[runsOffset] = 2
    #expect(throws: FixtureError.badRunKind(2)) { try ReplayFixture(decoding: bytes) }
}

@Test func anOverstatedRunCountIsRejected() throws {
    let fixture = try sample()
    var bytes = fixture.encoded()
    let countOffset = 8 + 4 + 16 + 4 + fixture.rects.count + 4 + fixture.glyphs.count
    bytes.replaceSubrange(countOffset..<countOffset + 4, with: [0xFF, 0xFF, 0xFF, 0x7F])
    #expect(throws: FixtureError.self) { try ReplayFixture(decoding: bytes) }
}

@Test func orderMutationPutsEveryRectRunFirst() throws {
    let mutated = try sample().orderMutatedRuns.map(\.kind)
    #expect(mutated == [.rect, .rect, .glyph])
}

@Test func pixelDifferenceCountsPixelsNotChannels() {
    let a: [UInt8] = [0, 0, 0, 0,  10, 10, 10, 10,  5, 5, 5, 5]
    let b: [UInt8] = [0, 0, 0, 0,  11, 10, 10, 10,  5, 5, 5, 40]  // one step still counts
    let delta = pixelDifference(a, b)
    #expect(delta.pixels == 2)
    #expect(delta.maxDelta == 35)
}
