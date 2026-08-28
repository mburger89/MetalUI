import CoreText
import Foundation
import Metal
import Testing
import MetalUICore
import MetalUILayout
@testable import MetalUIRender
@testable import MetalUIText
@testable import MetalUI

// The glyph emitter — the unit that joins the two halves this milestone built.
//
// **What can be checked here and what cannot.** Spec §4.2 stands: nothing in
// this repo can see a *wrong glyph* — the wrong bitmap in the right slot, where
// the CPU and the GPU agree on a wrong answer together. What Task 7 established
// is that the *geometry* has an oracle the drawing code does not share, and the
// same holds one layer up: a sprite's destination is CoreText's pen position
// plus a bearing the rasterizer computed, and both are readable here without
// going through the emitter. So every position below is checked against
// CoreText, never against what the emitter produced.
//
// **Counting glyphs is not enough, and ruling TX-I is why this file is longer
// than it looks like it needs to be.** An emitter that emitted one sprite per
// *run* rather than per glyph, or that stacked every sprite at the line's
// origin, passes any test that only counts.
// `everyGlyphLandsAtCoreTextsOwnPenPosition` and
// `spriteDestinationsAreThePenPositionPlusTheRasterizersBearings` are the
// discriminators; the counting tests exist for the whitespace and wrapping
// rules, which those two cannot see.
//
// **Every count that a later loop indexes on is a `try #require`, not an
// `#expect`, and that was measured rather than styled.** `#expect` records and
// continues, so a mutation that made the emitter produce *one* glyph per run
// left the first loop below indexing past the end of its own array: `Fatal
// error: Index out of range`, the process dead, **no summary line, and 200 tests
// never run**. That is taxonomy shape 11 arriving through a test rather than
// through a cleanup path — a wrong implementation that truncates the run instead
// of reddening. `#require` throws out of the one test and leaves the suite
// reporting.

/// A fresh resolve per access, for `TextMeasureTests`' reason: `ResolvedFont`
/// holds a `CTFont` and is deliberately not `Sendable`, so a file-scope `let`
/// does not compile under Swift 6 (ruling TX-A).
private var font: ResolvedFont { FontResolver.resolve(family: nil, size: 13) }

private let ctFontKey = NSAttributedString.Key(kCTFontAttributeName as String)

/// No space and no ligature pair in the platform UI font, so one character is
/// one glyph and every glyph has ink. `theSampleIsOneGlyphPerCharacter…` checks
/// that rather than assuming it — a face that ligated here would make every
/// count below quietly measure something else.
private let word = "Handgloves"

/// Nine short words, so a 120pt column wraps it to three lines. The same string
/// `TextMeasureTests` uses, so the two files' numbers are comparable.
private let label = "The quick brown fox jumps over the lazy dog"

/// A `CTLine` built straight from `NSAttributedString` — the oracle, reached
/// without `Shaper`, `ShapedText` or the emitter.
private func ctLine(_ text: String, _ ctFont: CTFont) -> CTLine {
    CTLineCreateWithAttributedString(
        NSAttributedString(string: text, attributes: [ctFontKey: ctFont]))
}

/// CoreText's own answer for where the glyph at `index` starts, from an API the
/// emitter does not call: `CTLineGetOffsetForStringIndex` re-walks the line
/// rather than reporting the positions array `CTRunGetPositions` hands back.
private func ctPenX(_ line: CTLine, _ index: Int) -> Double {
    Double(CTLineGetOffsetForStringIndex(line, index, nil))
}

private func ctGlyphCount(_ line: CTLine) -> Int {
    ((CTLineGetGlyphRuns(line) as? [CTRun]) ?? []).reduce(0) { $0 + CTRunGetGlyphCount($1) }
}

private func ctLineHeight(_ ctFont: CTFont) -> Double {
    Double(CTFontGetAscent(ctFont) + CTFontGetDescent(ctFont) + CTFontGetLeading(ctFont))
}

/// Renders `element` for one frame and hands back the frame and the finished
/// scene. A 512-square atlas rather than the production 1024 only so the test's
/// working set is small; nothing here can fill either.
@MainActor
private func painted<E: Element>(_ element: inout E, width: Double, height: Double = 600,
                                 scaleFactor: Float = 2,
                                 atlas: GlyphAtlas = GlyphAtlas(width: 512, height: 512),
                                 cache: ShapingCache = ShapingCache()) -> (Frame, Scene) {
    let frame = Frame(
        contentSize: Size(width: Pixels(Float(width)), height: Pixels(Float(height))),
        scaleFactor: scaleFactor,
        shapingCache: cache,
        glyphAtlas: atlas)
    frame.render(&element)
    return (frame, frame.finalizedScene())
}

// MARK: - The sample is what it claims to be

/// Taxonomy shape 1, forestalled: every count below reads "one glyph per
/// character", and a face that ligated `word` would make them all measure
/// something else while still passing.
@Test func theSampleIsOneGlyphPerCharacterWithNoWhitespace() {
    #expect(ctGlyphCount(ctLine(word, font.ctFont)) == word.count,
            "the platform UI font ligates \(word); pick another sample")
    #expect(!word.contains(" "))
}

// MARK: - Placement, against CoreText

/// **One of the two tests ruling TX-I asks for.** Counting sprites passes
/// against an emitter that stacks every glyph at the line's origin; this names
/// each glyph's pen position independently and does not.
@MainActor
@Test func everyGlyphLandsAtCoreTextsOwnPenPosition() throws {
    let font = font
    let scale = 2.0
    let originX = 7.0
    // **Two CoreText answers, and they are not the same number.** The oracle
    // here is `CTLineGetOffsetForStringIndex`, which reports where a *caret*
    // goes; the emitter reads `CTRunGetPositions`, which reports where a
    // *glyph* goes. Measured on this string, they agree exactly on eight of the
    // ten glyphs and differ by 0.126953pt — a quarter of a device pixel at 2x —
    // on the two that follow the `o`, because CoreText splits that kerning pair
    // between the two carets and gives the whole of it to the glyph. That is a
    // property of the APIs rather than of this code, so it is absorbed into the
    // tolerance and named rather than worked around.
    //
    //   0.125  the most the subpixel split may lose, by construction
    // + 0.254  the measured caret/pen disagreement, in device pixels
    // = 0.379, rounded up to 0.4 below.
    //
    // The smallest error this must still catch is a glyph placed at the wrong
    // pen entirely, which for this font at 13pt and 2x is at least 6.4 device
    // pixels — sixteen times the tolerance.
    let tolerance = 0.4
    let placed = Shaper.shape(word, font: font, wrappingAt: nil)
        .placedGlyphs(at: (x: originX, y: 0), font: font, scaleFactor: 2)
    try #require(placed.count == word.count)

    let line = ctLine(word, font.ctFont)
    for i in 0..<word.count {
        let expected = (originX + ctPenX(line, i)) * scale
        // The emitter splits a device x into a whole pixel and one of four
        // subpixel variants, so the pair must reconstitute the position — the
        // whole pixel alone would pass against an emitter that dropped the
        // fraction entirely.
        let reconstituted = Double(placed[i].pixelX)
            + Double(placed[i].key.subpixelVariant) / Double(GlyphRaster.subpixelVariants)
        #expect(abs(reconstituted - expected) <= tolerance,
                "glyph \(i): placed at \(reconstituted), CoreText says \(expected)")
    }

    // Not all the same number — which is what "stacked at the origin" would look
    // like to the loop above if the advances were ever reported as zero.
    #expect(Set(placed.map(\.pixelX)).count > 1)
}

/// The fraction the whole pixel drops is carried by the key rather than lost.
/// Without this, `subpixelPlacement` could return `(Int(x), 0)` and the loop
/// above would still pass on any string whose advances are near-integral.
///
/// Two differentials, and the pair is the point: a **whole** device pixel of
/// origin shift moves every `pixelX` by one and no variant at all, and a
/// **quarter** of one moves the variants. A variant that tracked position
/// rather than fraction would fail the first; a constant variant fails the
/// second.
@MainActor
@Test func theSubpixelVariantCarriesTheFractionRatherThanBeingConstant() {
    let font = font
    let shaped = Shaper.shape(word, font: font, wrappingAt: nil)
    let placed = shaped.placedGlyphs(at: (x: 0, y: 0), font: font, scaleFactor: 2)
    #expect(Set(placed.map(\.key.subpixelVariant)).count > 1,
            "every glyph landed on the same subpixel variant; the fraction is being dropped")

    // 0.5pt at 2x is exactly one device pixel.
    let wholePixel = shaped.placedGlyphs(at: (x: 0.5, y: 0), font: font, scaleFactor: 2)
    #expect(wholePixel.map(\.key.subpixelVariant) == placed.map(\.key.subpixelVariant))
    #expect(wholePixel.map(\.pixelX) == placed.map { $0.pixelX + 1 })

    // 0.125pt at 2x is a quarter of one — exactly one variant step.
    let quarterPixel = shaped.placedGlyphs(at: (x: 0.125, y: 0), font: font, scaleFactor: 2)
    #expect(quarterPixel.map(\.key.subpixelVariant) != placed.map(\.key.subpixelVariant))
}

/// Line `i`'s baseline is `origin.y + i × lineHeight + ascent`, in whole device
/// pixels — with both summands added up from `CTFontGet*` here rather than read
/// off `FontMetrics.lineHeight`, which is the property under test's own summand
/// (shape 12; `lineHeight { ascent }` left the whole suite green once already).
@MainActor
@Test func eachLineSitsOneLineHeightBelowTheLast() {
    let font = font
    let scale = 2.0
    let originY = 11.0
    let shaped = Shaper.shape(label, font: font, wrappingAt: 120)
    #expect(shaped.lines.count == 3, "the sample must wrap to three lines at 120pt")

    let placed = shaped.placedGlyphs(at: (x: 0, y: originY), font: font, scaleFactor: 2)
    let ascent = Double(CTFontGetAscent(font.ctFont))
    let lineHeight = ctLineHeight(font.ctFont)

    for i in 0..<3 {
        let expected = Int(((originY + Double(i) * lineHeight + ascent) * scale).rounded())
        #expect(placed.contains { $0.baselineY == expected },
                "no glyph on line \(i), expected baseline \(expected)")
    }
    // Exactly three distinct baselines, so the three assertions above cannot be
    // satisfied by an emitter that also scattered glyphs at other heights.
    #expect(Set(placed.map(\.baselineY)).count == 3)
}

/// A fallback run is rasterized in the run's own face, not in the requested one.
/// Using the requested font would draw one face's glyph *index* out of another
/// face's outlines — `FontKey`'s bug, arriving through the run instead of
/// through the name, and equally invisible to everything else here.
@MainActor
@Test func aFallbackRunIsKeyedOnTheFontCoreTextActuallyUsed() {
    // Helvetica has no CJK coverage, so CoreText substitutes for the second half
    // of this string and the line carries two runs in two faces.
    let helvetica = FontResolver.resolve(family: "Helvetica", size: 13)
    let placed = Shaper.shape("ab\u{6F22}\u{5B57}", font: helvetica, wrappingAt: nil)
        .placedGlyphs(at: (x: 0, y: 0), font: helvetica, scaleFactor: 2)

    let faces = Set(placed.map(\.key.font.postScriptName))
    #expect(faces.count == 2, "expected a fallback run; got \(faces)")
    #expect(faces.contains(helvetica.key.postScriptName))
}

// MARK: - What reaches the scene

/// Whitespace has no ink, so it takes an atlas entry and no sprite. A sprite per
/// *character* would put a degenerate quad in the instance buffer for every
/// space in a paragraph — 8 of this string's 43.
@MainActor
@Test func spacesGetNoSprite() {
    let font = font
    var text = Text(label)
    let (_, scene) = painted(&text, width: 400)

    let spaces = label.filter { $0 == " " }.count
    #expect(spaces == 8)
    // "How many glyphs are there at all" comes from CoreText's line, not from
    // the emitter.
    #expect(scene.glyphs.count == ctGlyphCount(ctLine(label, font.ctFont)) - spaces)
}

/// A wrapped `Text` emits every line's glyphs, not just the first.
@MainActor
@Test func everyWrappedLineEmitsItsGlyphs() {
    let font = font
    var text = Text(label)
    let (_, scene) = painted(&text, width: 120)

    #expect(Shaper.shape(label, font: font, wrappingAt: 120).lines.count == 3)
    // Three distinct sprite rows at least — a sprite's y varies within a line
    // with the glyph's own ascender, so this counts *lines* by bucketing on the
    // largest y, which is where a descender-free glyph's box bottom sits.
    let rows = Set(scene.glyphs.map { Int(($0.bounds.origin.y / 10).rounded(.down)) })
    #expect(rows.count >= 3)
    #expect(scene.glyphs.count == ctGlyphCount(ctLine(label, font.ctFont)) - 8)
}

/// **The second test ruling TX-I asks for**, and the only one that reaches
/// `GlyphImage.left`/`.top`.
///
/// Every sprite's destination is the pen position plus the rasterizer's own
/// bearings, recomputed here from `CTLineGetOffsetForStringIndex` and
/// `GlyphRaster` — never read back off the emitter. An emitter that ignored the
/// bearings and blitted at the pen would be out by a couple of device pixels per
/// glyph, differently per glyph: invisible to a count, and visible on screen as
/// text that sits wrong and unevenly.
///
/// The **differential** is the second half. The text is painted twice, in a
/// container padded by 9 points and by 0, and every sprite must move by exactly
/// 9 × the scale factor on both axes — which is what an emitter that ignored
/// `bounds.origin` and drew at the window's corner would fail.
@MainActor
@Test func spriteDestinationsAreThePenPositionPlusTheRasterizersBearings() throws {
    let font = font
    let scale = 2.0
    let pad = 9.0
    let boxWidth = 400.0 - 2 * pad

    var padded = Column { Text(word) }.padding(Pixels(Float(pad))).alignItems(.stretch)
    let (_, scene) = painted(&padded, width: 400)
    try #require(scene.glyphs.count == word.count)

    // The `Text` sits at the container's content origin, which is the padding on
    // both axes: the root fills the offered 400 (CLAUDE.md divergence 4) and is
    // itself at (0, 0), and `alignItems(.stretch)` puts the child at x = padding.
    //
    // The *placement* is `ShapedText.placedGlyphs`, whose own oracle is CoreText
    // — `everyGlyphLandsAtCoreTextsOwnPenPosition` above. What this test pins is
    // the layer between that and the scene: the bearings and the slot size. So
    // the two tests together have an oracle at every step, and neither uses the
    // code it checks as its own expectation.
    let placed = Shaper.shape(word, font: font, wrappingAt: boxWidth)
        .placedGlyphs(at: (x: pad, y: pad), font: font, scaleFactor: 2)
    try #require(placed.count == scene.glyphs.count)

    for i in 0..<placed.count {
        let image = GlyphRaster.rasterize(glyph: placed[i].key.glyph, font: placed[i].font,
                                          subpixelVariant: placed[i].key.subpixelVariant,
                                          scaleFactor: 2)
        let sprite = scene.glyphs[i]
        #expect(sprite.bounds.origin.x == Float(placed[i].pixelX + image.left),
                "glyph \(i) x: \(sprite.bounds.origin.x) vs \(placed[i].pixelX + image.left)")
        #expect(sprite.bounds.origin.y == Float(placed[i].baselineY - image.top),
                "glyph \(i) y: \(sprite.bounds.origin.y) vs \(placed[i].baselineY - image.top)")
        // A 1:1 blit: the destination and the source are the bitmap's own size.
        #expect(sprite.bounds.size.width == Float(image.width))
        #expect(sprite.bounds.size.height == Float(image.height))
        #expect(sprite.atlasBounds.size.width == Float(image.width))
        #expect(sprite.atlasBounds.size.height == Float(image.height))
    }

    // The bearings are not all zero, so the four assertions above are not
    // silently comparing the pen to itself — shape 1, which a per-glyph
    // comparison looks immune to and is not.
    #expect(placed.indices.contains { i in
        let image = GlyphRaster.rasterize(glyph: placed[i].key.glyph, font: placed[i].font,
                                          subpixelVariant: placed[i].key.subpixelVariant,
                                          scaleFactor: 2)
        return image.left != 0
    }, "every left bearing is 0; this test cannot see a dropped bearing")

    // **The differential.** The same text in a container padded by 0 must put
    // every sprite exactly `pad × scale` up and to the left — which an emitter
    // that ignored `bounds.origin` and drew at the window's corner fails, and
    // which the per-glyph loop above cannot see because it hands the emitter's
    // own origin to the oracle.
    var unpadded = Column { Text(word) }.alignItems(.stretch)
    let (_, flush) = painted(&unpadded, width: 400)
    try #require(flush.glyphs.count == scene.glyphs.count)
    for i in 0..<flush.glyphs.count {
        #expect(scene.glyphs[i].bounds.origin.x - flush.glyphs[i].bounds.origin.x
                == Float(pad * scale))
        #expect(scene.glyphs[i].bounds.origin.y - flush.glyphs[i].bounds.origin.y
                == Float(pad * scale))
    }
}

/// The tint is a theme token, so the same `Text` paints two different colours in
/// the two appearances — and `nil` means `.textPrimary` rather than an
/// unthemed literal, which is the failure this token exists to prevent.
@MainActor
@Test func glyphsAreTintedByTheThemeAndDefaultToTextPrimary() throws {
    // `MUIHsla` is a C struct with no `Equatable`, so the four components are
    // compared by hand rather than the struct — and all four, because two
    // theme colours can share three of them.
    func tint(_ theme: Theme, _ text: Text) -> [Float] {
        let frame = Frame(contentSize: Size(width: Pixels(400), height: Pixels(600)),
                          scaleFactor: 2, theme: theme)
        var root = text
        frame.render(&root)
        // `first` rather than `[0]`: an emitter that produced nothing would
        // otherwise kill the process here rather than redden this test.
        guard let c = frame.finalizedScene().glyphs.first?.color else { return [] }
        return [c.h, c.s, c.l, c.a]
    }
    func components(_ c: Hsla) -> [Float] { [c.h, c.s, c.l, c.a] }

    let light = tint(.light, Text(word))
    #expect(light == components(Theme.light.textPrimary))
    #expect(tint(.dark, Text(word)) == components(Theme.dark.textPrimary))
    #expect(tint(.light, Text(word).foregroundColor(.accent)) == components(Theme.light.accent))
    #expect(light != components(Theme.light.accent))
}

// MARK: - The atlas across frames

/// **A per-frame atlas would re-rasterize every glyph on every frame**, and
/// every pixel assertion in the repo would still pass — the bitmaps are
/// identical, only the work is not. This is the test that can see it: the second
/// frame of the same text must pack nothing.
///
/// `dirtyRect` is the observable. `clearDirtyRect` stands in for the upload the
/// window does between frames, so a second frame that packed even one glyph
/// leaves a non-`nil` rect behind. The third frame is the positive control — a
/// different string does dirty the atlas, so a `dirtyRect` that never became
/// non-`nil` could not pass this.
@MainActor
@Test func theAtlasSurvivesTheFrameThatFilledIt() {
    let atlas = GlyphAtlas(width: 512, height: 512)
    let cache = ShapingCache()

    var first = Text(word)
    _ = painted(&first, width: 400, atlas: atlas, cache: cache)
    #expect(atlas.dirtyRect != nil, "the first frame must have packed something")
    atlas.clearDirtyRect()

    var second = Text(word)
    _ = painted(&second, width: 400, atlas: atlas, cache: cache)
    #expect(atlas.dirtyRect == nil, "the second frame re-rasterized glyphs it already had")

    var third = Text("Zwitschermaschine")
    _ = painted(&third, width: 400, atlas: atlas, cache: cache)
    #expect(atlas.dirtyRect != nil, "new glyphs must still reach the atlas")
}

/// The second frame of the same text places its sprites exactly where the first
/// did — which is the entire reason `GlyphAtlas.packed(for:rasterize:)` stores
/// `GlyphImage.left`/`.top` beside the slot instead of letting the caller read
/// them off the `rasterize` closure's return value.
///
/// **Found by a mutation that reddened nothing, and it was the finding rather
/// than a broken instrument.** Storing `left: 0, top: 0` while still *returning*
/// the real bearings from the miss path left all 442 tests green: every other
/// test in the repo draws each glyph exactly once against a fresh atlas, so the
/// cache-hit path had no coverage at all. On screen it is text that is correct
/// on the frame it appears and jumps by a pixel or two on the next one.
///
/// Both frames share one atlas *and* one shaping cache, so the second frame hits
/// every cache this milestone built.
@MainActor
@Test func theSecondFrameOfTheSameTextPlacesItsSpritesIdentically() throws {
    let atlas = GlyphAtlas(width: 512, height: 512)
    let cache = ShapingCache()
    func geometry(_ scene: Scene) -> [Float] {
        scene.glyphs.flatMap {
            [$0.bounds.origin.x, $0.bounds.origin.y, $0.bounds.size.width, $0.bounds.size.height,
             $0.atlasBounds.origin.x, $0.atlasBounds.origin.y]
        }
    }

    var first = Text(word)
    let (_, firstScene) = painted(&first, width: 400, atlas: atlas, cache: cache)
    try #require(firstScene.glyphs.count == word.count)

    var second = Text(word)
    let (_, secondScene) = painted(&second, width: 400, atlas: atlas, cache: cache)

    #expect(geometry(secondScene) == geometry(firstScene))
    // The second frame really did hit the atlas rather than repacking, which is
    // what makes this a statement about the cache-hit path.
    #expect(atlas.currentGeneration == 2)
}

/// `beginFrame` / `endFrame` bracket the paint phase, which is what makes
/// `evictUnusedSince`'s precondition enforceable at all: eviction traps while a
/// frame is being built, and without the bracket there is no frame to be inside.
///
/// **The flag is asserted from inside `paint`**, which is the only place it is
/// true, through an element written for the purpose. Asserting it after `render`
/// only shows `endFrame` ran; an emitter that never called `beginFrame` would
/// pass that and leave every slot stamped generation 0.
@MainActor
@Test func theAtlasFrameBracketsWrapThePaintPhase() {
    final class Observer {
        var duringPaint: Bool?
        var generationDuringPaint: Int?
    }
    struct Probe: Element {
        let atlas: GlyphAtlas
        let observer: Observer
        var elementID: ElementID? { nil }
        mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass)
            -> (LayoutNodeID, Void) {
            (pass.requestNode(style: Style(), children: []), ())
        }
        mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout Void, pass: inout PrepaintPass) {}
        mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                            layout: inout Void, prepaint: inout Void, pass: inout PaintPass) {
            observer.duringPaint = atlas.isBuildingFrame
            observer.generationDuringPaint = atlas.currentGeneration
        }
    }

    let atlas = GlyphAtlas(width: 64, height: 64)
    let observer = Observer()
    #expect(!atlas.isBuildingFrame)
    #expect(atlas.currentGeneration == 0)

    var probe = Probe(atlas: atlas, observer: observer)
    _ = painted(&probe, width: 100, atlas: atlas)

    #expect(observer.duringPaint == true, "paint ran outside the atlas's frame brackets")
    #expect(observer.generationDuringPaint == 1)
    #expect(!atlas.isBuildingFrame, "endFrame did not run")

    var second = Probe(atlas: atlas, observer: observer)
    _ = painted(&second, width: 100, atlas: atlas)
    #expect(observer.generationDuringPaint == 2, "each frame must take its own generation")
}

// MARK: - Through the window, to the GPU

/// **`upload` must precede `encode`**, and the failure it prevents is only
/// visible on the frame a glyph first appears: the scene holds an `AtlasSlot`
/// for a bitmap the GPU does not have yet, so the text is blank once and correct
/// forever after. Reading `lastScene` cannot see it — the sprites are all there
/// — so this reads the rendered pixels back.
///
/// Skips without a Metal device, like the ABI probe; CLAUDE.md's "guarantees
/// that lapse under configuration" covers it.
@MainActor
@Test func aWindowUploadsTheAtlasBeforeEncodingSoTheFirstFrameOfTextIsNotBlank() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let (window, platform) = try makeFakeWindow(device: device, size: 128) {
        Text(word)
    }
    // `makeFakeWindow` does not paint eagerly the way `App.openWindow` does, so
    // this is genuinely the window's first frame.
    #expect(window.framesDrawn == 0)
    window.drawFrameIfNeeded()
    #expect(window.framesDrawn == 1)
    #expect(window.lastScene.glyphs.count == word.count)

    let pixels = platform.fakeSurface.readPixels()
    let inked = stride(from: 3, to: pixels.count, by: 4).count { pixels[$0] > 0 }
    #expect(inked > 0, "the first frame of text rendered blank")

    // And the ink is where the sprites said it would be: every inked pixel lies
    // inside some sprite's destination rectangle. A window that drew text at the
    // wrong scale, or that never applied the destination origin, fails this
    // while still passing the count above.
    let boxes = window.lastScene.glyphs.map { $0.bounds }
    var outside = 0
    for y in 0..<128 {
        for x in 0..<128 where pixels[(y * 128 + x) * 4 + 3] > 0 {
            let inSome = boxes.contains { box in
                Float(x) >= box.origin.x && Float(x) < box.origin.x + box.size.width
                    && Float(y) >= box.origin.y && Float(y) < box.origin.y + box.size.height
            }
            if !inSome { outside += 1 }
        }
    }
    #expect(outside == 0, "\(outside) inked pixels fell outside every sprite's box")
}

/// The window owns **one** atlas across frames, and nothing else can see that.
///
/// `theAtlasSurvivesTheFrameThatFilledIt` pins `Frame`'s half — a frame uses the
/// atlas it was handed. This pins the window's: a `Window` that built a fresh
/// `GlyphAtlas` per frame would re-rasterize and re-upload everything on every
/// frame and render **byte-identical pixels**, so no pixel comparison and no
/// scene assertion anywhere can distinguish it. `currentGeneration` can: it
/// advances once per `beginFrame`, so two frames on one atlas read 2 and two
/// frames on two atlases read 1.
@MainActor
@Test func aWindowKeepsOneAtlasAcrossFrames() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let (window, _) = try makeFakeWindow(device: device, size: 128) { Text(word) }

    window.drawFrameIfNeeded()
    #expect(window.glyphAtlas.currentGeneration == 1)
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    #expect(window.framesDrawn == 2)
    #expect(window.glyphAtlas.currentGeneration == 2,
            "the window built a second atlas rather than keeping one")
}

/// **Every byte the window drew, against the glyph's own rasterized bitmap** —
/// the one oracle the shader does not share, now reaching all the way from a
/// `Text` element rather than from a hand-built sprite.
///
/// Task 7 established this technique on two sprites placed by hand
/// (`aGlyphSpriteBlitsExactlyTheAtlasPixelsItPointsAt`). This runs it through
/// the whole chain the emitter added — shape, place, pack, upload, encode —
/// with nothing but a string as input. An opaque tint over a cleared target
/// makes the premultiplied result's **alpha byte the coverage byte** with no
/// arithmetic in between, so the comparison is exact rather than tolerant;
/// `textPrimary` has `a == 1`, so the default tint qualifies.
///
/// **The expectation is a locally rasterized `GlyphImage`, NOT
/// `sprite.atlasBounds` into `GlyphAtlas.pixels` — and that distinction was
/// measured rather than reasoned.** The first version of this test mapped each
/// window pixel back through the sprite's own `atlasBounds`, which is taxonomy
/// shape 12 in disguise: shifting the source coordinate by **one texel**
/// (`MUIGlyph.init`'s `slot.x + 1`) left it green, because the expectation
/// moved with the mutation. Rasterizing the glyph here instead — from the key
/// the emitter placed, through `GlyphRaster`, which never learns where the
/// packer put it — makes the same mutation redden. A per-pixel comparison looks
/// immune to shape 12 and is not.
///
/// **Only pixels covered by exactly one sprite are compared.** Adjacent glyph
/// boxes can overlap by a pixel — `GlyphRaster.inkPadding` puts a margin on
/// every side — and two premultiplied sprites blended together are legitimately
/// not either one's coverage. The compared, inked and empty counts are all
/// asserted so this cannot pass by comparing nothing, by comparing a blank
/// region, or against a solid rectangle.
///
/// **What this CANNOT see, stated because the temptation is to read it as
/// end-to-end verification.** It is exact about *geometry* and blind to
/// *identity*: in all three of spec §4.2's named failures the CPU and the GPU
/// agree on a wrong answer together, so this test passes unchanged if the
/// atlas served the **wrong glyph** for a key (a `FontKey` collision — the
/// oracle would rasterize the same wrong glyph), if the **subpixel variant**
/// were dropped and text wobbled during a scroll, or if **eviction blanked a
/// run** mid-frame. Those three remain the human look's, and the human look has
/// not happened: the demo has no `Text` in it yet.
///
/// **The cheap non-assertive companion, for whoever needs it next**: print the
/// same `readPixels()` buffer as ASCII art, one character per pixel keyed on
/// the alpha byte. `Text("Hi Wag")` at 22pt comes back legible, which is how
/// this emitter was first confirmed to draw letters rather than rectangles. It
/// asserts nothing and it catches the gross failures in one glance.
@MainActor
@Test func theWindowsPixelsAreExactlyTheGlyphBitmapsItsSpritesStandFor() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let side = 128
    let (window, platform) = try makeFakeWindow(device: device, size: side) { Text(word) }
    window.drawFrameIfNeeded()

    let sprites = window.lastScene.glyphs
    try #require(sprites.count == word.count)

    // The window's surface reports `scaleFactor: 1`, and a `Text` as the root
    // fills the offered width at (0, 0) — CLAUDE.md divergence 4.
    let placed = Shaper.shape(word, font: font, wrappingAt: Double(side))
        .placedGlyphs(at: (x: 0, y: 0), font: font, scaleFactor: 1)
    try #require(placed.count == sprites.count)
    // Emission order is `placedGlyphs`' order and `finalize` sorts stably at one
    // order, so sprite i is glyph i. Checked rather than assumed: a mismatch
    // would make every comparison below compare the wrong pair.
    let images = placed.map {
        GlyphRaster.rasterize(glyph: $0.key.glyph, font: $0.font,
                              subpixelVariant: $0.key.subpixelVariant, scaleFactor: 1)
    }
    for i in 0..<sprites.count {
        try #require(sprites[i].bounds.size.width == Float(images[i].width))
        try #require(sprites[i].bounds.size.height == Float(images[i].height))
    }

    let pixels = platform.fakeSurface.readPixels()
    func contains(_ box: MUIBounds, _ x: Int, _ y: Int) -> Bool {
        Float(x) >= box.origin.x && Float(x) < box.origin.x + box.size.width
            && Float(y) >= box.origin.y && Float(y) < box.origin.y + box.size.height
    }

    var compared = 0
    var inked = 0
    var mismatches: [String] = []
    for y in 0..<side {
        for x in 0..<side {
            let covering = sprites.indices.filter { contains(sprites[$0].bounds, x, y) }
            guard covering.count == 1, let i = covering.first else { continue }
            let column = x - Int(sprites[i].bounds.origin.x)
            let row = y - Int(sprites[i].bounds.origin.y)
            let expected = images[i].bytes[row * images[i].width + column]
            let actual = pixels[(y * side + x) * 4 + 3]
            compared += 1
            if expected > 0 { inked += 1 }
            if expected != actual {
                mismatches.append("(\(x),\(y)) glyph \(i) wants \(expected), drew \(actual)")
            }
        }
    }

    #expect(compared > 200, "only \(compared) pixels were unambiguously covered")
    #expect(inked > 50, "the compared region is almost entirely blank; it cannot discriminate")
    #expect(compared - inked > 20, "no empty pixels compared; a solid rectangle would pass")
    #expect(mismatches.isEmpty,
            "\(mismatches.count) of \(compared) pixels differ — \(mismatches.prefix(6).joined(separator: ", "))")
}
