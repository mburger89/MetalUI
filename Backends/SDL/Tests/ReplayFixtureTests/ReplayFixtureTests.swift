import Testing
import ReplayFixture
import MetalUIScene
import MetalUIShaderTypes

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

@Test func aThresholdCountsOnlyPixelsBeyondIt() {
    let a: [UInt8] = [0, 0, 0, 0,  10, 10, 10, 10,  5, 5, 5, 5]
    let b: [UInt8] = [0, 0, 0, 0,  11, 10, 10, 10,  5, 5, 5, 40]
    #expect(pixelDifference(a, b, above: 1).pixels == 1)
    #expect(pixelDifference(a, b, above: 35).pixels == 0)
    #expect(pixelDifference(a, b, above: 34).pixels == 1)
    #expect(pixelDifference(a, b, above: 35).maxDelta == 35)
}

// MARK: - Parity

func floats(_ values: [Float]) -> [UInt8] {
    values.flatMap { v in withUnsafeBytes(of: v.bitPattern.littleEndian) { Array($0) } }
}

/// A 20×10 target with one glyph quad at (5, 2, 4×3).
func glyphFixture(projection: [Float] = [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1],
                  reference: [UInt8]? = nil) throws -> ReplayFixture {
    let record = floats([5, 2, 4, 3]) + [UInt8](repeating: 0, count: 88 - 16)
    return try ReplayFixture(width: 20, height: 10, rects: [], glyphs: record,
        runs: [FixtureRun(kind: .glyph, start: 0, count: 1)],
        atlasWidth: 1, atlasHeight: 1, atlas: [0], projection: projection,
        reference: reference ?? [UInt8](repeating: 100, count: 20 * 10 * 4))
}

func marked(_ mask: [Bool], width: Int) -> (x: ClosedRange<Int>, y: ClosedRange<Int>)? {
    let points = mask.indices.filter { mask[$0] }.map { ($0 % width, $0 / width) }
    guard let first = points.first else { return nil }
    return (points.map(\.0).min()!...points.map(\.0).max()!, first.1...points.map(\.1).max()!)
}

@Test func glyphBoundsReadTheRecordsFirstFourFloats() throws {
    let b = try #require(try glyphFixture().glyphBounds.first)
    #expect(b.x == 5 && b.y == 2 && b.width == 4 && b.height == 3)
}

@Test func theGlyphMaskIsTheQuadGrownByOnePixel() throws {
    // Quad spans x 5..<9, y 2..<5; grown: x 4...10, y 1...6.
    let area = try #require(marked(try glyphFixture().glyphMask(), width: 20))
    #expect(area.x == 4...10)
    #expect(area.y == 1...6)
}

@Test func theGlyphMaskFollowsTheProjection() throws {
    // Scale 0.5 about the centre (10, 5): x 5..9 -> 7.5..9.5, y 2..5 -> 3.5..5.
    let scaled: [Float] = [0.5,0,0,0, 0,0.5,0,0, 0,0,1,0, 0,0,0,1]
    let area = try #require(marked(try glyphFixture(projection: scaled).glyphMask(), width: 20))
    #expect(area.x == 6...11)
    #expect(area.y == 2...6)
}

@Test func parityJudgesInsideAndOutsideGlyphsSeparately() throws {
    let fixture = try glyphFixture()
    var output = fixture.reference
    output[(3 * 20 + 6) * 4] += 8          // inside the quad: at the glyph tolerance
    output[(9 * 20 + 18) * 4 + 1] += 1     // far outside: one rounding step
    let parity = fixture.parity(of: output)
    #expect(parity.inside.pixels == 1 && parity.inside.maxDelta == 8)
    #expect(parity.outside.pixels == 1 && parity.outside.maxDelta == 1)
    #expect(parity.passes)
}

@Test func twoStepsOutsideGlyphsFail() throws {
    let fixture = try glyphFixture()
    var output = fixture.reference
    output[(9 * 20 + 18) * 4 + 2] += 2
    #expect(!fixture.parity(of: output).passes)
}

@Test func beyondTheGlyphToleranceInsideAQuadFails() throws {
    let fixture = try glyphFixture()
    var output = fixture.reference
    output[(3 * 20 + 6) * 4] += 9          // literal: the bound is 8 (Vulkan's 4 sub-texel bits)
    #expect(!fixture.parity(of: output).passes)
}

@Test func theGlyphToleranceDoesNotReachPastTheGrownQuad() throws {
    let fixture = try glyphFixture()
    var output = fixture.reference
    output[(3 * 20 + 11) * 4] += 3         // x 11: one pixel past the grown edge
    let parity = fixture.parity(of: output)
    #expect(parity.outside.maxDelta == 3)
    #expect(!parity.passes)
}

// MARK: - From MetalUIScene

@Test func thePrimitiveABIIsTheOneTheShadersRead() {
    // replay.hlsl reads a rect as 8 float4 lanes and a glyph as 6, after the
    // bridge pads 120 -> 128 and 88 -> 96. A struct change must redden here.
    #expect(ReplayFixture.rectStride == 120)
    #expect(ReplayFixture.glyphStride == 88)
}

@Test func aFixtureFromASceneCarriesItsPrimitivesDrawListAndAtlas() throws {
    var scene = Scene()
    var rect = MUIRect()
    rect.bounds = MUIBounds(origin: MUIPoint(x: 1, y: 2), size: MUISize(width: 3, height: 4))
    rect.order = 2
    var glyph = MUIGlyph()
    glyph.bounds = MUIBounds(origin: MUIPoint(x: 5, y: 6), size: MUISize(width: 7, height: 8))
    glyph.order = 1
    scene.insert(rect)
    scene.insert(glyph)
    scene.insert(rect)
    scene.finalize()
    // finalize sorts by order: glyph (1) before both rects (2) — two runs.
    try #require(scene.drawList.count == 2)

    let atlas = GlyphAtlas(width: 4, height: 2)
    let fixture = try ReplayFixture(scene: scene, atlas: atlas, width: 3, height: 2,
                                    projection: [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1],
                                    reference: [UInt8](repeating: 0, count: 3 * 2 * 4))
    #expect(fixture.rectCount == 2 && fixture.glyphCount == 1)
    #expect(fixture.runs == [FixtureRun(kind: .glyph, start: 0, count: 1),
                             FixtureRun(kind: .rect, start: 0, count: 2)])
    #expect(fixture.atlasWidth == 4 && fixture.atlasHeight == 2 && fixture.atlas == atlas.pixels)
    let record = try #require(fixture.glyphRecords.first)
    #expect(record.bounds.origin.x == 5 && record.bounds.size.height == 8 && record.order == 1)
    #expect(try ReplayFixture(decoding: fixture.encoded()) == fixture)
}
