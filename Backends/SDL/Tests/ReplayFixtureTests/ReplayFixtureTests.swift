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
    #expect(Array(bytes[8..<12]) == [4, 0, 0, 0])       // version (4 since BB-J)
    #expect(Array(bytes[12..<16]) == [3, 0, 0, 0])      // width
    #expect(Array(bytes[20..<24]) == [120, 0, 0, 0])    // rect stride
    #expect(Array(bytes[24..<28]) == [88, 0, 0, 0])     // glyph stride
    #expect(Array(bytes[36..<40]) == [96, 0, 0, 0])     // backdrop stride (BB-J)
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
    #expect(throws: FixtureError.strideMismatch(rect: 128, glyph: 88, image: 64)) {
        try ReplayFixture(decoding: bytes)
    }
}

@Test func badMagicAndVersionAreRejected() throws {
    var bytes = try sample().encoded()
    bytes[0] = UInt8(ascii: "X")
    #expect(throws: FixtureError.badMagic) { try ReplayFixture(decoding: bytes) }
    bytes = try sample().encoded()
    bytes[8] = 1   // version 1 had no images; its files are re-recorded, never read
    #expect(throws: FixtureError.unsupportedVersion(1)) { try ReplayFixture(decoding: bytes) }
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
    // Version 4: a sixth stride (the backdrop's), the (empty) image bytes
    // and textures, then the (empty) transform and backdrop tables.
    let runsOffset = 8 + 4 + 28 + 4 + fixture.rects.count + 4 + fixture.glyphs.count + 4 + 4 + 4 + 4 + 4
    try #require(bytes[runsOffset] == 0)  // first run is a rect
    bytes[runsOffset] = 4                 // 2 is an image run since version 2, 3 a backdrop since version 4
    #expect(throws: FixtureError.badRunKind(4)) { try ReplayFixture(decoding: bytes) }
}

@Test func anOverstatedRunCountIsRejected() throws {
    let fixture = try sample()
    var bytes = fixture.encoded()
    let countOffset = 8 + 4 + 24 + 4 + fixture.rects.count + 4 + fixture.glyphs.count + 4 + 4
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
    // An image is four float4 lanes, uploaded unpadded (ruling TE-AF).
    #expect(ReplayFixture.imageStride == 64)
    // The transform table is four float4 lanes a record (ruling GX-F).
    #expect(ReplayFixture.transformStride == 64)
}

/// S1.1 — version 2 carries image records and the textures they sample
/// (width, height, premultiplied RGBA8 bytes) after the glyph bytes, and a
/// run of kind 2 indexes the images. Distinct bytes everywhere, so a field
/// written or read at the wrong offset changes the decoded fixture.
@Test func aVersionTwoFixtureRoundTripsImagesAndTextures() throws {
    var image = MUIImage()
    image.bounds = MUIBounds(origin: MUIPoint(x: 1, y: 2), size: MUISize(width: 3, height: 4))
    image.opacity = 0.5
    image.texture = 1
    image.filter = 1
    let images = withUnsafeBytes(of: image) { Array($0) } + withUnsafeBytes(of: MUIImage()) { Array($0) }
    let textures = [FixtureTexture(width: 1, height: 1, pixels: [1, 2, 3, 4]),
                    FixtureTexture(width: 2, height: 1, pixels: [5, 6, 7, 8, 9, 10, 11, 12])]
    let fixture = try ReplayFixture(
        width: 3, height: 2, rects: [], glyphs: [], images: images, textures: textures,
        runs: [FixtureRun(kind: .image, start: 0, count: 1), FixtureRun(kind: .image, start: 1, count: 1)],
        atlasWidth: 1, atlasHeight: 1, atlas: [0],
        projection: [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1],
        reference: (0..<24).map { UInt8($0) })
    let bytes = fixture.encoded()
    // Version 3 since GX-F (the transform table after the textures), 4 since BB-J.
    #expect(Array(bytes[8..<12]) == [UInt8(ReplayFixture.version), 0, 0, 0], "the current version")
    let decoded = try ReplayFixture(decoding: bytes)
    #expect(decoded == fixture)
    #expect(decoded.imageCount == 2)
    #expect(decoded.textures == textures)
    #expect(decoded.imageRecords.first?.texture == 1 && decoded.imageRecords.first?.opacity == 0.5)
    // A texture index past the textures, or a texture of the wrong byte
    // count, is rejected before the bridge could read past a buffer.
    var bad = image; bad.texture = 2
    #expect(throws: FixtureError.self) {
        try ReplayFixture(width: 3, height: 2, rects: [], glyphs: [],
                          images: withUnsafeBytes(of: bad) { Array($0) }, textures: textures,
                          runs: [FixtureRun(kind: .image, start: 0, count: 1)],
                          atlasWidth: 1, atlasHeight: 1, atlas: [0],
                          projection: [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1],
                          reference: [UInt8](repeating: 0, count: 24))
    }
    #expect(throws: FixtureError.self) {
        try ReplayFixture(width: 3, height: 2, rects: [], glyphs: [], images: images,
                          textures: [FixtureTexture(width: 2, height: 2, pixels: [1, 2, 3])] + textures,
                          runs: [], atlasWidth: 1, atlasHeight: 1, atlas: [0],
                          projection: [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1],
                          reference: [UInt8](repeating: 0, count: 24))
    }
    // An image quad is judged at the sprite tolerance, like a glyph's.
    let mask = try ReplayFixture(width: 8, height: 8, rects: [], glyphs: [], images: images,
                                 textures: textures, runs: [], atlasWidth: 1, atlasHeight: 1, atlas: [0],
                                 projection: [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1],
                                 reference: [UInt8](repeating: 0, count: 8 * 8 * 4)).spriteMask()
    #expect(mask[3 * 8 + 2], "inside the image quad (1, 2, 3×4)")
    #expect(!mask[7 * 8 + 7])
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

/// **3.6** (MetalView, ruling `MV-C` item 4; spec §10's "an SDL replay fixture
/// holding a surface" is not built). A surface's content is app-defined GPU
/// work no fixture holds, so recording a scene's surface run traps by name
/// rather than mapping it onto an image run that would sample a texture the
/// fixture never carried. Green on arrival (lane 1's trap). Mutation **M3h**:
/// map `.surface` to `.image`.
@Test func aSceneWithASurfaceIsNotRecordable() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        var scene = Scene()
        var quad = MUIImage()
        quad.bounds = MUIBounds(origin: MUIPoint(x: 0, y: 0), size: MUISize(width: 4, height: 4))
        scene.insert(quad, surface: SurfaceTarget(id: SurfaceID(rawValue: 1), width: 4, height: 4))
        scene.finalize()
        _ = scene.drawList.map { FixtureRun(scene: $0) }
    }
    let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(stderr.contains("cannot record a surface"), "aborted, but not at the fixture's check:\n\(stderr)")
}

/// S1.1 (ruling GX-F) — version 3 (and every later one) carries the scene's `MUITransform` table
/// (64 bytes a record) after the textures, and a fixture made from a scene
/// carries its table; a table that is not whole records is rejected.
@Test func aVersionThreeFixtureRoundTripsTransforms() throws {
    #expect(ReplayFixture.transformStride == 64)
    var scene = Scene()
    var rect = MUIRect()
    rect.bounds = MUIBounds(origin: MUIPoint(x: 1, y: 1), size: MUISize(width: 2, height: 2))
    let t = MUITransform(a: 0, b: 1, c: -1, d: 0, tx: 3, ty: 0, pixelScale: 1, _reserved: 0,
                         outerMask: MUIBounds(origin: MUIPoint(x: 0, y: 0), size: MUISize(width: 4, height: 4)),
                         outerMaskRadii: MUICorners(topLeft: 1, topRight: 2, bottomRight: 3, bottomLeft: 4))
    scene.insert(rect, transform: t)
    scene.finalize()
    let fixture = try ReplayFixture(scene: scene, atlas: GlyphAtlas(width: 1, height: 1), width: 4, height: 4,
                                    projection: [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1],
                                    reference: [UInt8](repeating: 0, count: 64))
    #expect(fixture.transforms == withUnsafeBytes(of: t) { Array($0) })
    let bytes = fixture.encoded()
    #expect(Array(bytes[8..<12]) == [UInt8(ReplayFixture.version), 0, 0, 0], "the current version carries the table")
    let decoded = try ReplayFixture(decoding: bytes)
    #expect(decoded == fixture)
    #expect(decoded.transforms.count == 64)
    var bad = fixture
    bad.transforms = [1, 2, 3]
    #expect(throws: FixtureError.self) { try bad.validate() }
}

// MARK: - Backdrops (ruling BB-J, version 4)

private func backdropRecord(order: UInt32 = 0, sigma: Float = 52) -> MUIBackdrop {
    let box = MUIBounds(origin: MUIPoint(x: 1, y: 2), size: MUISize(width: 6, height: 4))
    let none = MUICorners(topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0)
    return MUIBackdrop(bounds: box, contentMask: box, maskCornerRadii: none, cornerRadii: none,
                       tint: MUIHsla(h: 0.1, s: 0.2, l: 0.3, a: 0.4), order: order, shape: 0, sigma: sigma, opacity: 0.5)
}

private func backdropScene() -> Scene {
    var scene = Scene()
    var rect = MUIRect()
    rect.bounds = MUIBounds(origin: MUIPoint(x: 0, y: 0), size: MUISize(width: 8, height: 8))
    scene.insert(rect)
    scene.insert(backdropRecord())
    scene.finalize()
    return scene
}

private func backdropFixture() throws -> ReplayFixture {
    try ReplayFixture(scene: backdropScene(), atlas: GlyphAtlas(width: 1, height: 1), width: 8, height: 8,
                      projection: [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1],
                      reference: [UInt8](repeating: 0, count: 8 * 8 * 4))
}

/// **3.1** (ruling `BB-B`, `BB-J`). The backdrop record is 96 bytes of six
/// `float4` lanes, and `replay.hlsl` reads each field from the lane
/// `BB-B`'s table names: bounds 0, mask 16, mask radii 32, radii 48, tint 64,
/// then order 80, shape 84, sigma 88, opacity 92. A re-ordered or padded
/// struct fails here, not as a silently shifted blur. Mutation: pad the struct
/// (`MUIBackdrop` gains a field).
@Test func theBackdropABIIsTheOneTheShadersRead() {
    #expect(MemoryLayout<MUIBackdrop>.stride == 96)
    #expect(MemoryLayout<MUIBackdrop>.size == 96)
    #expect(ReplayFixture.backdropStride == 96)
    #expect(MemoryLayout<MUIBackdrop>.offset(of: \.bounds) == 0)
    #expect(MemoryLayout<MUIBackdrop>.offset(of: \.contentMask) == 16)
    #expect(MemoryLayout<MUIBackdrop>.offset(of: \.maskCornerRadii) == 32)
    #expect(MemoryLayout<MUIBackdrop>.offset(of: \.cornerRadii) == 48)
    #expect(MemoryLayout<MUIBackdrop>.offset(of: \.tint) == 64)
    #expect(MemoryLayout<MUIBackdrop>.offset(of: \.order) == 80)
    #expect(MemoryLayout<MUIBackdrop>.offset(of: \.shape) == 84)
    #expect(MemoryLayout<MUIBackdrop>.offset(of: \.sigma) == 88)
    #expect(MemoryLayout<MUIBackdrop>.offset(of: \.opacity) == 92)
}

/// **3.6** (ruling `BB-J`). The version is 4; a fixture written before it —
/// version 3 (no backdrop stride, no backdrop table) and version 2 (no
/// transform stride or table either) — still loads, to the same fixture;
/// version 1 stays refused. The old files are built from the new encoding by
/// removing exactly the fields the old layouts lack. Mutation: bump
/// `version` without the reader's older arms.
@Test func theFixtureVersionIsFourAndOldVersionsStillLoad() throws {
    #expect(ReplayFixture.version == 4)
    let fixture = try sample()
    let v4 = fixture.encoded()
    // v3: drop the backdrop stride (offset 36) and the empty backdrop table
    // (a u32 0 after the transform table).
    let transformTableOffset = 8 + 4 + 28 + 4 + fixture.rects.count + 4 + fixture.glyphs.count + 4 + 4
    var v3 = v4
    try #require(Array(v3[transformTableOffset..<transformTableOffset + 8]) == [0, 0, 0, 0, 0, 0, 0, 0],
                 "an empty transform table, then an empty backdrop table")
    v3.removeSubrange(transformTableOffset + 4..<transformTableOffset + 8)
    v3.removeSubrange(36..<40)
    v3[8] = 3
    let decoded3 = try ReplayFixture(decoding: v3)
    #expect(decoded3 == fixture)
    // v2: drop the transform stride (offset 32) and its table as well.
    var v2 = v3
    v2.removeSubrange(transformTableOffset - 4..<transformTableOffset)   // v3 is 4 shorter before the table
    v2.removeSubrange(32..<36)
    v2[8] = 2
    #expect(try ReplayFixture(decoding: v2) == fixture)
    var v1 = v4
    v1[8] = 1
    #expect(throws: FixtureError.unsupportedVersion(1)) { try ReplayFixture(decoding: v1) }
    var v5 = v4
    v5[8] = 5
    #expect(throws: FixtureError.unsupportedVersion(5)) { try ReplayFixture(decoding: v5) }
}

/// **3.4** (ruling `BB-J`, `MV-C` item 4). A scene's backdrop run is recorded
/// as a `.backdrop` run (no longer a trap), the fixture carries the 96-byte
/// records and round-trips, and a surface run still traps (the surface test
/// above). Mutation: restore the trap for `.backdrop` in `FixtureRun(scene:)`.
@Test func aFixtureRunRecordsABackdropAndStillTrapsOnASurface() throws {
    let scene = backdropScene()
    let kinds = scene.drawList.map { FixtureRun(scene: $0).kind }
    #expect(kinds == [.rect, .backdrop])
    let fixture = try backdropFixture()
    #expect(fixture.backdropCount == 1)
    #expect(fixture.backdrops == withUnsafeBytes(of: backdropRecord()) { Array($0) })
    #expect(fixture.backdropRecords.first?.sigma == 52)
    #expect(fixture.runs.last == FixtureRun(kind: .backdrop, start: 0, count: 1))
    #expect(try ReplayFixture(decoding: fixture.encoded()) == fixture)
}

/// **3.4b** — a backdrop run past its records, a backdrop table that is not
/// whole 96-byte records and a changed backdrop stride are each refused (the C
/// bridge indexes the table with these runs).
@Test func aBackdropRunPastItsRecordsOrAnOddTableIsRejected() throws {
    var fixture = try backdropFixture()
    fixture.runs = [FixtureRun(kind: .backdrop, start: 0, count: 2)]
    #expect(throws: FixtureError.self) { try fixture.validate() }
    fixture.runs = [FixtureRun(kind: .backdrop, start: 1, count: 1)]
    #expect(throws: FixtureError.self) { try fixture.validate() }
    fixture = try backdropFixture()
    fixture.backdrops.removeLast()
    #expect(throws: FixtureError.self) { try fixture.validate() }
    var bytes = try backdropFixture().encoded()
    bytes[36] = 128
    #expect(throws: FixtureError.self) { try ReplayFixture(decoding: bytes) }
}

/// **3.4c** (ruling `BB-D` 3). The region a replay blurs is the one the window
/// renderer's `Scene.backdropRegion` names: the fixture restates that function
/// over the records it holds, and the two agree for a plain record, one under
/// a quarter turn about its centre, one hanging off the target and one wholly
/// outside it (`nil`). Mutation: skip the clamp in `backdropRegions`.
@Test func aFixtureRestatesTheScenesBackdropRegion() throws {
    var scene = Scene()
    let mask = MUIBounds(origin: MUIPoint(x: 0, y: 0), size: MUISize(width: 64, height: 48))
    let none = MUICorners(topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0)
    func record(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> MUIBackdrop {
        MUIBackdrop(bounds: MUIBounds(origin: MUIPoint(x: x, y: y), size: MUISize(width: w, height: h)),
                    contentMask: mask, maskCornerRadii: none, cornerRadii: none,
                    tint: MUIHsla(h: 0, s: 0, l: 0.5, a: 0.3), order: 0, shape: 0, sigma: 16, opacity: 1)
    }
    scene.insert(record(4.5, 6.25, 20, 10))
    scene.insert(record(50, 40, 40, 30))                      // hangs off the right and bottom
    scene.insert(record(100, 100, 10, 10))                    // wholly outside
    let quarterTurn = MUITransform(a: 0, b: 1, c: -1, d: 0, tx: 40, ty: 4, pixelScale: 1, _reserved: 0,
                                   outerMask: mask, outerMaskRadii: none)
    scene.insert(record(2, 3, 12, 20), transform: quarterTurn)
    scene.finalize()
    let fixture = try ReplayFixture(scene: scene, atlas: GlyphAtlas(width: 1, height: 1), width: 64, height: 48,
                                    projection: [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1],
                                    reference: [UInt8](repeating: 0, count: 64 * 48 * 4))
    let expected = (0..<scene.backdrops.count).map { scene.backdropRegion($0, target: (64, 48)) }
    try #require(expected.count == 4)
    #expect(expected.contains { $0 == nil }, "one record is wholly outside")
    #expect(fixture.backdropRegions == expected)
}

/// **3.2b** (ruling `BB-J`). A backdrop quad is judged at three levels (the
/// measured parity of the blur on Mesa lavapipe is 2, on Metal 0), a sprite at
/// eight, anything else at one: a delta of 3 inside a backdrop quad passes, 4
/// fails, and 2 outside every quad fails. Mutation: judge a backdrop at the
/// sprite tolerance (put it in `spriteMask()`).
@Test func aBackdropQuadIsJudgedAtThreeLevels() throws {
    let fixture = try backdropFixture()          // bounds (1, 2, 6, 4) on an 8 × 8 target
    func pixels(delta: UInt8, at x: Int, _ y: Int) -> [UInt8] {
        var out = fixture.reference
        out[(y * 8 + x) * 4] = delta
        return out
    }
    #expect(ParityTolerance.insideBackdrops == 3)
    #expect(fixture.parity(of: pixels(delta: 3, at: 3, 3)).passes)
    #expect(fixture.parity(of: pixels(delta: 3, at: 3, 3)).backdrop.maxDelta == 3)
    #expect(!fixture.parity(of: pixels(delta: 4, at: 3, 3)).passes)
    #expect(!fixture.parity(of: pixels(delta: 2, at: 7, 0)).passes, "outside every quad: one level")
    #expect(fixture.parity(of: fixture.reference).passes)
}
