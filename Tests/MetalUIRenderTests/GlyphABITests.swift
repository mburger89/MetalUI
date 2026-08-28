import Testing
import CoreText
import Metal
import MetalUICore
import MetalUIShaderTypes
import MetalUIText
@testable import MetalUIRender

// MARK: - CPU-side bookkeeping
//
// Everything in this section runs without a GPU. That matters here more than
// anywhere else in the repo: spec §4.2 records that nothing can see a wrong
// glyph, and the *one* GPU-touching guard below skips on a machine with no
// Metal device. These are what remain green on a headless runner.

private func makeGlyph(order: MUIUInt, x: Float = 0) -> MUIGlyph {
    MUIGlyph(
        bounds: MUIBounds(origin: MUIPoint(x: x, y: 0),
                          size: MUISize(width: 8, height: 12)),
        atlasBounds: MUIBounds(origin: MUIPoint(x: 0, y: 0),
                               size: MUISize(width: 8, height: 12)),
        color: MUIHsla(h: 0, s: 0, l: 1, a: 1),
        order: order,
        _reserved: 0)
}

private func makeRect() -> MUIRect {
    MUIRect(
        bounds: MUIBounds(origin: MUIPoint(x: 0, y: 0),
                          size: MUISize(width: 10, height: 10)),
        contentMask: MUIBounds(origin: MUIPoint(x: 0, y: 0),
                               size: MUISize(width: 100, height: 100)),
        background: MUIHsla(h: 0, s: 0, l: 0, a: 1),
        borderColor: MUIHsla(h: 0, s: 0, l: 0, a: 0),
        cornerRadii: MUICorners(topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0),
        borderWidths: MUIEdges(top: 0, right: 0, bottom: 0, left: 0),
        order: 0,
        _reserved: 0)
}

@Test func sceneKeepsGlyphsAndRectsInSeparateLists() {
    var scene = Scene()
    scene.insert(makeRect())
    scene.insert(makeGlyph(order: 0))
    #expect(scene.rects.count == 1)
    #expect(scene.glyphs.count == 1)
}

/// Stable, so equal orders keep emission sequence — the same guarantee
/// `finalize` already gives rects.
@Test func finalizeSortsGlyphsStablyByOrder() {
    var scene = Scene()
    for (i, order) in ([2, 0, 1, 0] as [MUIUInt]).enumerated() {
        scene.insert(makeGlyph(order: order, x: Float(i)))
    }
    scene.finalize()
    #expect(scene.glyphs.map(\.order) == [0, 0, 1, 2])
    // The two order-0 glyphs keep their emission order: x = 1 then x = 3.
    #expect(scene.glyphs[0].bounds.origin.x == 1)
    #expect(scene.glyphs[1].bounds.origin.x == 3)
}

/// `Renderer.encode` returns early on an empty scene, so a rects-only `isEmpty`
/// draws no text at all in any frame that emitted glyphs and no rect — a `Text`
/// with no background, which is the ordinary case. Silent, and invisible to
/// every other test here: the glyph arrays would still be correct, they would
/// just never be encoded.
@Test func aSceneHoldingOnlyAGlyphIsNotEmpty() {
    var scene = Scene()
    #expect(scene.isEmpty)
    scene.insert(makeGlyph(order: 0))
    #expect(!scene.isEmpty)
}

/// A `clear` that forgot the glyph array would accumulate every glyph ever
/// painted, frame after frame, against `AtlasSlot`s that eviction is free to
/// recycle underneath them. `Frame` clears and refills one `Scene` per frame.
@Test func clearRemovesGlyphsAsWellAsRects() {
    var scene = Scene()
    scene.insert(makeRect())
    scene.insert(makeGlyph(order: 0))
    scene.clear()
    #expect(scene.rects.isEmpty)
    #expect(scene.glyphs.isEmpty)
    #expect(scene.isEmpty)
}

// MARK: - The ABI, across the MSL boundary

/// Asserts Metal's view of `MUIGlyph` matches Swift's.
///
/// Swift imports the same C header the shader is built from, so C-vs-Swift drift
/// cannot happen. What can is MSL applying different packing or alignment rules
/// to the same declarations, which the Swift compiler cannot see and which shows
/// up as glyphs sampled from the wrong part of the atlas.
///
/// **`bounds` and `atlasBounds` are the pair this exists for.** They are the
/// same type and adjacent, so a layout shift between them produces a shader that
/// samples the destination rectangle out of the atlas — and every value below is
/// distinct precisely so a shifted offset yields a wrong number rather than a
/// coincidental match.
///
/// Skips without a Metal device. CLAUDE.md already lists the ABI probe's skip as
/// a guarantee that must be a required, non-gateable CI job; this test doubles
/// the surface behind that one guarantee.
@Test func metalAndSwiftAgreeOnTheGlyphStructLayout() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let library = try ShaderLibrary.make(device: device)
    let function = try #require(library.makeFunction(name: "abi_probe"))
    let pipeline = try device.makeComputePipelineState(function: function)
    let queue = try #require(device.makeCommandQueue())

    var glyph = MUIGlyph(
        bounds: MUIBounds(origin: MUIPoint(x: 31, y: 32),
                          size: MUISize(width: 33, height: 34)),
        atlasBounds: MUIBounds(origin: MUIPoint(x: 41, y: 42),
                               size: MUISize(width: 43, height: 44)),
        color: MUIHsla(h: 0.125, s: 0.25, l: 0.375, a: 0.5),
        order: 7,
        _reserved: 0)
    var rect = makeRect()

    let slots = 32
    let outBuffer = try #require(device.makeBuffer(length: slots * MemoryLayout<UInt32>.stride,
                                                   options: .storageModeShared))
    let rectBuffer = try #require(device.makeBuffer(bytes: &rect,
                                                    length: MemoryLayout<MUIRect>.stride,
                                                    options: .storageModeShared))
    let glyphBuffer = try #require(device.makeBuffer(bytes: &glyph,
                                                     length: MemoryLayout<MUIGlyph>.stride,
                                                     options: .storageModeShared))

    let commandBuffer = try #require(queue.makeCommandBuffer())
    let encoder = try #require(commandBuffer.makeComputeCommandEncoder())
    encoder.setComputePipelineState(pipeline)
    encoder.setBuffer(outBuffer, offset: 0, index: Int(MUIProbeBufferOut.rawValue))
    encoder.setBuffer(rectBuffer, offset: 0, index: Int(MUIProbeBufferRect.rawValue))
    encoder.setBuffer(glyphBuffer, offset: 0, index: Int(MUIProbeBufferGlyph.rawValue))
    encoder.dispatchThreads(MTLSize(width: 1, height: 1, depth: 1),
                            threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
    encoder.endEncoding()
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()
    #expect(commandBuffer.error == nil)

    let out = outBuffer.contents().bindMemory(to: UInt32.self, capacity: slots)

    #expect(Int(out[13]) == MemoryLayout<MUIGlyph>.size)
    #expect(out[14] == 31)   // bounds.origin.x
    #expect(out[15] == 32)   // bounds.origin.y
    #expect(out[16] == 33)   // bounds.size.width
    #expect(out[17] == 34)   // bounds.size.height
    #expect(out[18] == 41)   // atlasBounds.origin.x
    #expect(out[19] == 42)   // atlasBounds.origin.y
    #expect(out[20] == 43)   // atlasBounds.size.width
    #expect(out[21] == 44)   // atlasBounds.size.height
    #expect(out[22] == 125)  // color.h * 1000
    #expect(out[23] == 250)  // color.s * 1000
    #expect(out[24] == 375)  // color.l * 1000
    #expect(out[25] == 500)  // color.a * 1000
    #expect(out[26] == 7)    // order
}

// MARK: - The draw path, against the CPU atlas as its oracle

/// Packs `characters` of the platform UI font into a fresh atlas and hands back
/// the atlas and one slot per character.
///
/// The atlas is 2x-rasterized because that is what a Retina window asks for and
/// because a 1x bitmap of 13pt text is a handful of pixels — too few for a
/// per-pixel comparison to say much.
@MainActor
private func packedAtlas(_ characters: [Character], size: Double = 13,
                         scaleFactor: Float = 2) throws -> (GlyphAtlas, [AtlasSlot]) {
    let font = FontResolver.resolve(family: nil, size: size)
    let atlas = GlyphAtlas(width: 128, height: 128)
    atlas.beginFrame()
    defer { atlas.endFrame() }

    var slots: [AtlasSlot] = []
    for character in characters {
        var utf16 = Array(String(character).utf16)
        var glyphIDs = [CGGlyph](repeating: 0, count: utf16.count)
        let ok = CTFontGetGlyphsForCharacters(font.ctFont, &utf16, &glyphIDs, utf16.count)
        try #require(ok, "the platform UI font has no glyph for \(character)")
        let key = GlyphKey(font: font.key, glyph: glyphIDs[0], size: size,
                           subpixelVariant: 0, scaleFactor: scaleFactor)
        let slot = try #require(atlas.slot(for: key) {
            GlyphRaster.rasterize(glyph: glyphIDs[0], font: font,
                                  subpixelVariant: 0, scaleFactor: scaleFactor)
        })
        slots.append(slot)
    }
    return (atlas, slots)
}

private func sprite(_ slot: AtlasSlot, at origin: (x: Float, y: Float),
                    color: Hsla, order: MUIUInt = 0) -> MUIGlyph {
    MUIGlyph(
        bounds: MUIBounds(origin: MUIPoint(x: origin.x, y: origin.y),
                          size: MUISize(width: Float(slot.width), height: Float(slot.height))),
        atlasBounds: MUIBounds(origin: MUIPoint(x: Float(slot.x), y: Float(slot.y)),
                               size: MUISize(width: Float(slot.width), height: Float(slot.height))),
        color: MUIHsla(color),
        order: order,
        _reserved: 0)
}

private func alpha(_ pixels: [UInt8], _ x: Int, _ y: Int, width: Int) -> UInt8 {
    pixels[(y * width + x) * 4 + 3]
}

/// The one thing in this milestone that can see a wrong atlas coordinate, and
/// the reason it can is that it has an oracle the shader does not share:
/// `GlyphAtlas.pixels`, produced entirely on the CPU by CoreText and a shelf
/// packer that never learns Metal exists.
///
/// **Spec §4.2 says "no test in this repo can see a wrong glyph, a wrong atlas
/// coordinate, or a blank run", and that is too broad by exactly one layer.** It
/// is true end to end — nothing here can tell that the *right* glyph id was
/// rasterized, or that the shaper placed it at the right pen position, because
/// both halves would move together. It is false of the renderer's sampling
/// geometry: with the atlas bytes in hand, a sprite that samples the wrong texel
/// produces a different byte, and this asserts every byte.
///
/// Two glyphs, drawn side by side in one scene, and both bitmaps asserted:
/// with one, an `atlasBounds` the shader ignored in favour of `bounds` would
/// still land on the only slot there is.
@Test @MainActor func aGlyphSpriteBlitsExactlyTheAtlasPixelsItPointsAt() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let renderer = try Renderer(device: device)
    let (atlas, slots) = try packedAtlas(["H", "g"])
    let (h, g) = (slots[0], slots[1])

    // The atlas must be non-uniform for any of this to discriminate: a wrong
    // coordinate into a constant bitmap reads the same value as a right one.
    // (Taxonomy shape 1 — the failure that a per-pixel comparison looks immune
    // to and is not.)
    func bytes(_ slot: AtlasSlot) -> [UInt8] {
        (0..<slot.height).flatMap { row in
            (0..<slot.width).map { column in
                atlas.pixels[(slot.y + row) * atlas.width + slot.x + column]
            }
        }
    }
    let hBytes = bytes(h)
    let gBytes = bytes(g)
    #expect(Set(hBytes).count > 2, "a flat bitmap cannot distinguish a wrong sample")
    #expect(hBytes != gBytes, "two identical bitmaps cannot distinguish a wrong slot")

    let side = 128
    var scene = Scene()
    // Origins chosen so neither sprite touches the other or an edge, and so the
    // two differ on both axes: a destination that dropped `origin.y` would still
    // pass with both glyphs on the same row.
    scene.insert(sprite(h, at: (x: 8, y: 6), color: .white))
    scene.insert(sprite(g, at: (x: 60, y: 40), color: .white))
    scene.finalize()
    renderer.upload(atlas)

    let pixels = try renderer.renderOffscreen(
        scene, size: Size(width: DevicePixels(Int32(side)), height: DevicePixels(Int32(side))))

    // White at full alpha over a cleared target: the premultiplied result's
    // alpha byte IS the coverage byte, with no arithmetic in between. Any
    // rounding would show as an off-by-one, so this is asserted exactly.
    func expectBlit(_ slot: AtlasSlot, at origin: (x: Int, y: Int), _ label: String) {
        var mismatches: [String] = []
        for row in 0..<slot.height {
            for column in 0..<slot.width {
                let expected = atlas.pixels[(slot.y + row) * atlas.width + slot.x + column]
                let actual = alpha(pixels, origin.x + column, origin.y + row, width: side)
                if expected != actual {
                    mismatches.append("(\(column),\(row)) atlas \(expected) vs drawn \(actual)")
                }
            }
        }
        #expect(mismatches.isEmpty,
                "\(label): \(mismatches.count) of \(slot.width * slot.height) pixels differ — \(mismatches.prefix(6).joined(separator: ", "))")
    }
    expectBlit(h, at: (x: 8, y: 6), "H")
    expectBlit(g, at: (x: 60, y: 40), "g")

    // And nothing outside the two sprites: a sprite whose destination size came
    // from the atlas's dimensions rather than the slot's would cover the target.
    #expect(alpha(pixels, 2, 2, width: side) == 0)
    #expect(alpha(pixels, 120, 120, width: side) == 0)
}

/// Coverage is a blend weight on the tint, not a colour of its own (spec §7.8).
/// White-on-black and black-on-white are symmetric under a red/blue swap, which
/// is the transposition `channelsAreNotTransposed` exists for on the rect path —
/// the glyph path has its own `hsla_to_srgba` call site and its own premultiply.
@Test @MainActor func glyphsAreTintedByTheirColorAndScaledByCoverage() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let renderer = try Renderer(device: device)
    let (atlas, slots) = try packedAtlas(["H"])
    let slot = slots[0]
    renderer.upload(atlas)

    // The most-covered pixel in the bitmap, so the tint is read where coverage
    // is highest and the assertion does not depend on which stem is thickest.
    var best = (index: 0, coverage: UInt8(0))
    for row in 0..<slot.height {
        for column in 0..<slot.width {
            let c = atlas.pixels[(slot.y + row) * atlas.width + slot.x + column]
            if c > best.coverage { best = (row * slot.width + column, c) }
        }
    }
    #expect(best.coverage > 200, "the sample point must be near-opaque for a tint assertion")
    let (peakRow, peakColumn) = (best.index / slot.width, best.index % slot.width)

    let side = 64
    func draw(_ color: Hsla) throws -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        var scene = Scene()
        scene.insert(sprite(slot, at: (x: 4, y: 4), color: color))
        scene.finalize()
        let pixels = try renderer.renderOffscreen(
            scene, size: Size(width: DevicePixels(Int32(side)), height: DevicePixels(Int32(side))))
        let i = ((4 + peakRow) * side + 4 + peakColumn) * 4
        return (pixels[i + 2], pixels[i + 1], pixels[i], pixels[i + 3])
    }

    let red = try draw(.rgb(0xFF0000))
    #expect(red.r > 200)
    #expect(red.g < 40)
    #expect(red.b < 40)

    let blue = try draw(.rgb(0x0000FF))
    #expect(blue.r < 40)
    #expect(blue.g < 40)
    #expect(blue.b > 200)

    // Coverage scales alpha: a 25%-alpha tint over a cleared target lands at a
    // quarter of the coverage the opaque one did. Without this the shader could
    // ignore `sample.r` entirely and paint solid rectangles, which every
    // assertion above would still pass — the peak pixel is near-opaque.
    let opaque = try draw(Hsla(h: 0, s: 0, l: 1, a: 1))
    let quarter = try draw(Hsla(h: 0, s: 0, l: 1, a: 0.25))
    #expect(abs(Int(quarter.a) - Int(opaque.a) / 4) <= 2,
            "quarter-alpha tint gave \(quarter.a) where a quarter of \(opaque.a) was expected")
}

/// A glyph packed after the first upload must reach the GPU on the next one.
///
/// The atlas hands the renderer a `dirtyRect` and expects it to be uploaded and
/// then cleared; a renderer that uploaded only on texture creation, or that
/// never cleared the rect, or that cleared it without uploading, all produce the
/// same visible symptom — a glyph that is blank on the frame it first appears,
/// or forever. Nothing else in the repo exercises a second upload.
@Test @MainActor func aGlyphPackedAfterTheFirstUploadStillReachesTheGPU() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let renderer = try Renderer(device: device)

    let font = FontResolver.resolve(family: nil, size: 13)
    let atlas = GlyphAtlas(width: 128, height: 128)

    func pack(_ character: Character) throws -> AtlasSlot {
        var utf16 = Array(String(character).utf16)
        var glyphIDs = [CGGlyph](repeating: 0, count: utf16.count)
        try #require(CTFontGetGlyphsForCharacters(font.ctFont, &utf16, &glyphIDs, utf16.count))
        let key = GlyphKey(font: font.key, glyph: glyphIDs[0], size: 13,
                           subpixelVariant: 0, scaleFactor: 2)
        return try #require(atlas.slot(for: key) {
            GlyphRaster.rasterize(glyph: glyphIDs[0], font: font,
                                  subpixelVariant: 0, scaleFactor: 2)
        })
    }

    atlas.beginFrame()
    _ = try pack("H")
    atlas.endFrame()
    renderer.upload(atlas)
    #expect(atlas.dirtyRect == nil, "upload is the consumer clearDirtyRect exists for")

    atlas.beginFrame()
    let second = try pack("W")
    atlas.endFrame()
    #expect(atlas.dirtyRect != nil, "the second glyph must have dirtied the atlas")
    renderer.upload(atlas)

    let side = 64
    var scene = Scene()
    scene.insert(sprite(second, at: (x: 4, y: 4), color: .white))
    scene.finalize()
    let pixels = try renderer.renderOffscreen(
        scene, size: Size(width: DevicePixels(Int32(side)), height: DevicePixels(Int32(side))))

    var mismatches = 0
    var ink = 0
    for row in 0..<second.height {
        for column in 0..<second.width {
            let expected = atlas.pixels[(second.y + row) * atlas.width + second.x + column]
            if expected > 0 { ink += 1 }
            if expected != alpha(pixels, 4 + column, 4 + row, width: side) { mismatches += 1 }
        }
    }
    #expect(ink > 0, "the second glyph must have ink for a blank to be distinguishable")
    #expect(mismatches == 0, "\(mismatches) pixels of the second glyph differ from the atlas")
}

/// A renderer with no texture for this atlas must upload the WHOLE of it, dirty
/// rect or not.
///
/// **Found by a mutation that reddened nothing.** Replacing `upload`'s
/// texture-creation branch with the dirty-rect one left all 428 tests green,
/// because every other test here packs its glyphs and uploads them in that
/// order — dirty and live are the same region, so the two branches agree. They
/// diverge exactly when a renderer meets an atlas whose pixels are already
/// clean: a second window on the same atlas, or the atlas-replaced-wholesale
/// path `GlyphAtlas.evictUnusedSince` names, where a fresh texture's undefined
/// contents would be filled from a region covering none of the resident glyphs.
/// The symptom is every earlier glyph blank — spec §4.2's third failure mode,
/// arriving from the renderer rather than from eviction.
@Test @MainActor func anAtlasWithNoDirtyRectStillUploadsInFullToANewTexture() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let (atlas, slots) = try packedAtlas(["H"])
    let slot = slots[0]

    // The first renderer takes the dirty rect and clears it, exactly as a
    // frame loop would. The second has never seen this atlas.
    let first = try Renderer(device: device)
    first.upload(atlas)
    #expect(atlas.dirtyRect == nil)

    let second = try Renderer(device: device)
    second.upload(atlas)

    let side = 64
    var scene = Scene()
    scene.insert(sprite(slot, at: (x: 4, y: 4), color: .white))
    scene.finalize()
    let pixels = try second.renderOffscreen(
        scene, size: Size(width: DevicePixels(Int32(side)), height: DevicePixels(Int32(side))))

    var mismatches = 0
    var ink = 0
    for row in 0..<slot.height {
        for column in 0..<slot.width {
            let expected = atlas.pixels[(slot.y + row) * atlas.width + slot.x + column]
            if expected > 0 { ink += 1 }
            if expected != alpha(pixels, 4 + column, 4 + row, width: side) { mismatches += 1 }
        }
    }
    #expect(ink > 0, "the glyph must have ink for a blank to be distinguishable")
    #expect(mismatches == 0,
            "\(mismatches) pixels differ — the second renderer uploaded less than the whole atlas")
}

/// A rect and a glyph in one scene, in one render pass, through two pipelines.
/// The pipelines share an encoder, so binding state set by one leaking into the
/// other is a real failure mode — and it is asymmetric: the glyph pipeline binds
/// a texture the rect pipeline does not.
@Test @MainActor func aRectAndAGlyphBothDrawInOneScene() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let renderer = try Renderer(device: device)
    let (atlas, slots) = try packedAtlas(["H"])
    renderer.upload(atlas)

    let side = 64
    var scene = Scene()
    scene.insert(MUIRect(
        bounds: Bounds(origin: Point(x: ScaledPixels(0), y: ScaledPixels(0)),
                       size: Size(width: ScaledPixels(64), height: ScaledPixels(64))),
        contentMask: Bounds(origin: Point(x: ScaledPixels(0), y: ScaledPixels(0)),
                            size: Size(width: ScaledPixels(64), height: ScaledPixels(64))),
        background: .rgb(0x0000FF), borderColor: .rgb(0x0000FF),
        cornerRadii: Corners(all: ScaledPixels(0)),
        borderWidths: Edges(all: ScaledPixels(0)),
        order: 0))
    scene.insert(sprite(slots[0], at: (x: 4, y: 4), color: .rgb(0xFF0000)))
    scene.finalize()

    let pixels = try renderer.renderOffscreen(
        scene, size: Size(width: DevicePixels(Int32(side)), height: DevicePixels(Int32(side))))

    // Away from the glyph: the rect's blue, untouched.
    let far = ((60 * side) + 60) * 4
    #expect(pixels[far] > 200, "b")          // BGRA readback: index 0 is blue
    #expect(pixels[far + 2] < 40, "r")

    // The glyph's most-covered pixel: red over the blue, so red must dominate.
    var best = (row: 0, column: 0, coverage: UInt8(0))
    let slot = slots[0]
    for row in 0..<slot.height {
        for column in 0..<slot.width {
            let c = atlas.pixels[(slot.y + row) * atlas.width + slot.x + column]
            if c > best.coverage { best = (row, column, c) }
        }
    }
    let hit = (((4 + best.row) * side) + 4 + best.column) * 4
    #expect(pixels[hit + 2] > 200, "the glyph's red must be on top")
    #expect(pixels[hit] < 60, "the rect's blue must be mostly covered")
}

/// A dirty upload after the texture has been encoded must allocate a REPLACEMENT
/// rather than write into the one an in-flight frame may still be sampling.
///
/// **Found by the M2 whole-branch review, not by any assertion — and no
/// assertion in this repo can see the race itself.** `Window.drawFrameIfNeeded`
/// commits a frame's command buffer and never waits; the live path has no
/// semaphore (`grep -n "waitUntil" Sources/` finds one line, in
/// `renderOffscreen`, which is test support). So a `texture.replace` on the next
/// frame writes pixels the previous frame's draw may be reading, and the atlas
/// is the only resource exposed to that — every other thing `encode` binds is a
/// fresh per-frame `makeBuffer`. The symptom is one torn or wrong glyph on
/// exactly the frame that packs a new one: a resize, new text, a font-size
/// change.
///
/// **What this test can and cannot do.** It cannot observe the race — the
/// window is a GPU-timing one and `renderOffscreen` waits, which is the same
/// reason nothing else here can see spec §4.2's three. What it pins is the
/// *invariant that makes the race impossible*: a texture is written only while
/// unencoded, so the identity assertion below is the mechanism and the pixel
/// assertion is that the replacement carries the whole atlas rather than an
/// empty one. Both halves are needed — returning a fresh blank texture would
/// satisfy the first alone, and that is spec §4.2's third failure mode arriving
/// by a different road.
///
/// **Measured `--no-parallel`, suite 445, one mutation at a time — all four
/// redden this test and NOTHING else**, which is the point: no other test in the
/// repo is sensitive to any of them.
///
/// 1. `sizeChanged || false && wouldMutateAnEncodedTexture` — the fix reverted.
/// 2. `wouldMutateAnEncodedTexture = atlasTextureWasEncoded` — the
///    `dirtyRect != nil` conjunct dropped, so clean frames churn.
/// 3. `atlasTextureWasEncoded = false` in `encodeGlyphs` — the flag never set.
/// 4. `if needsFullUpload, atlas.dirtyRect == nil` — the replacement refilled
///    from the dirty rect instead of the whole atlas.
///
/// Mutation 4 is the one that justifies the pixel half.
/// `anAtlasWithNoDirtyRectStillUploadsInFullToANewTexture` looks like it should
/// catch it and does not: its atlas has no dirty rect, so that mutation leaves
/// it on the full-upload path. This is the only guard for "a *replacement*
/// texture carries the whole atlas".
@Test @MainActor func aDirtyUploadAfterEncodingReplacesTheTextureRatherThanWritingIntoIt() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let renderer = try Renderer(device: device)

    let font = FontResolver.resolve(family: nil, size: 13)
    let atlas = GlyphAtlas(width: 128, height: 128)

    func pack(_ character: Character) throws -> AtlasSlot {
        var utf16 = Array(String(character).utf16)
        var glyphIDs = [CGGlyph](repeating: 0, count: utf16.count)
        try #require(CTFontGetGlyphsForCharacters(font.ctFont, &utf16, &glyphIDs, utf16.count))
        let key = GlyphKey(font: font.key, glyph: glyphIDs[0], size: 13,
                           subpixelVariant: 0, scaleFactor: 2)
        return try #require(atlas.slot(for: key) {
            GlyphRaster.rasterize(glyph: glyphIDs[0], font: font,
                                  subpixelVariant: 0, scaleFactor: 2)
        })
    }

    atlas.beginFrame()
    let first = try pack("H")
    atlas.endFrame()
    renderer.upload(atlas)
    let beforeEncoding = try #require(renderer.atlasTexture)

    // Bind it. From here the texture is off limits to the CPU.
    let side = 64
    let size = Size(width: DevicePixels(Int32(side)), height: DevicePixels(Int32(side)))
    var firstScene = Scene()
    firstScene.insert(sprite(first, at: (x: 4, y: 4), color: .white))
    firstScene.finalize()
    _ = try renderer.renderOffscreen(firstScene, size: size)

    // An upload with nothing dirty must NOT churn a new texture — without the
    // `dirtyRect != nil` conjunct in `upload`, every steady-state frame would
    // allocate a whole atlas.
    renderer.upload(atlas)
    #expect(renderer.atlasTexture === beforeEncoding,
            "a clean upload after encoding reallocated; steady-state frames will churn")

    atlas.beginFrame()
    let second = try pack("W")
    atlas.endFrame()
    try #require(atlas.dirtyRect != nil, "the second glyph must have dirtied the atlas")
    renderer.upload(atlas)

    #expect(renderer.atlasTexture !== beforeEncoding,
            "a dirty upload wrote into the texture the previous frame encoded")

    // The replacement must carry the whole atlas, not just what was dirty: the
    // FIRST glyph is the one a dirty-rect-only refill would blank.
    var scene = Scene()
    scene.insert(sprite(first, at: (x: 4, y: 4), color: .white))
    scene.insert(sprite(second, at: (x: 4, y: 30), color: .white, order: 1))
    scene.finalize()
    let pixels = try renderer.renderOffscreen(scene, size: size)

    for (slot, originY) in [(first, 4), (second, 30)] {
        var mismatches = 0
        var ink = 0
        for row in 0..<slot.height {
            for column in 0..<slot.width {
                let expected = atlas.pixels[(slot.y + row) * atlas.width + slot.x + column]
                if expected > 0 { ink += 1 }
                if expected != alpha(pixels, 4 + column, originY + row, width: side) {
                    mismatches += 1
                }
            }
        }
        #expect(ink > 0, "the glyph at y=\(originY) must have ink for a blank to be visible")
        #expect(mismatches == 0,
                "\(mismatches) pixels differ at y=\(originY) after the texture was replaced")
    }
}

/// An opaque rect at a higher order must cover text beneath it.
///
/// **This is the assertion `Scene.finalize`'s doc comment said could not
/// exist** — "nothing in this repo can see a glyph painted through a rect" —
/// and it could not, while `encode` drew every rect before every glyph. The
/// draw list is what makes it visible, so this test is the draw list's reason
/// for being rather than a detail of it.
///
/// The differential is the second half: the SAME two primitives with the orders
/// swapped must give the opposite answer. Without it this test passes on a
/// renderer that draws nothing but rects.
@Test @MainActor func anOpaqueRectAtAHigherOrderCoversTheTextBeneathIt() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let renderer = try Renderer(device: device)
    let (atlas, slots) = try packedAtlas(["H"])
    let slot = slots[0]
    renderer.upload(atlas)

    let side = 64
    let size = Size(width: DevicePixels(Int32(side)), height: DevicePixels(Int32(side)))

    // A blue rect exactly covering the glyph's box.
    func cover(order: MUIUInt) -> MUIRect {
        MUIRect(bounds: MUIBounds(origin: MUIPoint(x: 4, y: 4),
                                  size: MUISize(width: Float(slot.width),
                                                height: Float(slot.height))),
                contentMask: MUIBounds(origin: MUIPoint(x: 0, y: 0),
                                       size: MUISize(width: Float(side), height: Float(side))),
                background: MUIHsla(h: 0.6, s: 1, l: 0.5, a: 1),
                borderColor: MUIHsla(h: 0, s: 0, l: 0, a: 0),
                cornerRadii: MUICorners(topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0),
                borderWidths: MUIEdges(top: 0, right: 0, bottom: 0, left: 0),
                order: order, _reserved: 0)
    }

    // Find a pixel the glyph definitely inks, so "covered" is meaningful.
    var inkX = -1, inkY = -1
    for row in 0..<slot.height where inkY < 0 {
        for column in 0..<slot.width {
            if atlas.pixels[(slot.y + row) * atlas.width + slot.x + column] > 200 {
                inkX = column; inkY = row; break
            }
        }
    }
    try #require(inkY >= 0, "the glyph must have a near-opaque pixel for this test to mean anything")

    // Rect ABOVE the glyph: the covered pixel is the rect's colour.
    var above = Scene()
    above.insert(sprite(slot, at: (x: 4, y: 4), color: .white, order: 0))
    above.insert(cover(order: 1))
    above.finalize()
    #expect(above.drawList.count == 2)
    let coveredPixels = try renderer.renderOffscreen(above, size: size)

    // Rect BELOW the glyph: the same pixel is the glyph's white.
    var below = Scene()
    below.insert(cover(order: 0))
    below.insert(sprite(slot, at: (x: 4, y: 4), color: .white, order: 1))
    below.finalize()
    #expect(below.drawList.count == 2)
    let textPixels = try renderer.renderOffscreen(below, size: size)

    // BGRA8: index 0 is blue, index 2 is red.
    let hit = (((4 + inkY) * side) + 4 + inkX) * 4
    #expect(coveredPixels[hit] > 200, "the rect's blue must win where it is on top")
    #expect(coveredPixels[hit + 2] < 80, "no white text may show through an opaque rect")
    #expect(textPixels[hit + 2] > 200, "with the orders swapped, the white glyph must win")
}
