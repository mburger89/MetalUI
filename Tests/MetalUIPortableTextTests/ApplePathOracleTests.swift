import CoreText
import Foundation
import Testing
import MetalUIFreeType
import MetalUIHarfBuzz
import MetalUIScene
import MetalUIShaderTypes
@testable import MetalUIPortableText
@testable import MetalUIText

// MetalUI's own Apple path is the oracle for the portable text pipeline
// (ruling PT-F).
//
// Each corpus case emits the same string twice, from the same font file:
//
// - **portable** — `PortableText.emit` (HarfBuzz shapes, FreeType rasterizes,
//   `GlyphImage.subpixelPlacement` splits the pen) into a `Scene` and a
//   `GlyphAtlas`;
// - **Apple** — `Shaper.shape` (CoreText) → `ShapedText.placedGlyphs`
//   (CoreText positions, the same `subpixelPlacement`) → `GlyphRaster` into a
//   second `GlyphAtlas` of the same type, with `Frame.draw`'s arithmetic
//   reproduced inside `emitBothWays` rather than a whole `Frame` driven:
//   reaching `Frame.draw` needs a window, a Metal device, an element tree and
//   a layout pass, all to exercise the four lines that PT-D copied, and those
//   four lines are transcribed here beside their original.
//
// `placedGlyphs(at:)` takes the text box's **top-left**, and puts the baseline
// at `origin.y + ascent`; `PortableText.emit` takes the baseline itself. The
// Apple side therefore passes `baseline - ascent`, so both draw on the same
// baseline — asserted, not assumed, by
// `theTwoPipelinesShareABaseline`.
//
// What is asserted:
//
// - Same glyph **count and order**, and each `MUIGlyph`'s `origin` and `size`
//   **exactly** equal — no tolerance. Measured first: over all 384 cases the
//   measurement test reported `countDifferences=0 geometryDifferences=0`, so
//   equality is what was found, not what was hoped for.
// - Atlas **coverage** per emitted glyph, compared region-scoped exactly as
//   `FT-H` did (each glyph's own slot rectangle out of each atlas), within
//   tolerances measured before they were set. The four (font, size, scale)
//   combinations where `CTFontDrawGlyphs` draws away from the glyph's own
//   outline — record §24's measured, pinned CoreText behaviour, not a
//   FreeType difference — are pinned here too rather than absorbed by a wider
//   bound, and `coreTextDrawsAwayFromItsOutlineAtExactlyTheseSizes` reddens if
//   the list goes stale.
//
// Re-measure with
// `METALUI_PORTABLE_ORACLE_MEASURE=1 swift test --build-system native
//  --no-parallel --filter theMeasuredDifferences`
// before changing any constant here.

// MARK: - Tolerances (measured 2026-09-23, macOS 27.0, FreeType 2.14.3,
//         HarfBuzz 14.5.0; see `theMeasuredDifferences`)

/// Largest per-pixel |portable − Apple| coverage difference over a glyph's own
/// atlas slot, at every (font, size, scale) outside `coreTextAdjustedSizes`.
/// Measured maximum over the 384-case corpus: **67** (Noto Sans 26 pt ×2).
/// Margin +13, about 5% of full coverage.
let coverageMaxTolerance = 80
/// Largest per-glyph mean |portable − Apple| coverage difference over the
/// glyph's own slot, outside `coreTextAdjustedSizes`. Measured maximum:
/// **7.024** (Noto Sans 13 pt ×1). Margin +2. The four adjusted sizes' worst
/// per-glyph means are 17.700 and above, so this bound also separates them —
/// `coreTextDrawsAwayFromItsOutlineAtExactlyTheseSizes` relies on that.
let coverageMeanTolerance = 9.0

/// Inside `coreTextAdjustedSizes`, where `CTFontDrawGlyphs` does not draw the
/// outline CoreText itself reports (record §24, `FT-H`). Measured maximum
/// per-pixel over this corpus: **220** (Noto Sans 17 pt ×1). Margin +20.
let adjustedCoverageMaxTolerance = 240
/// See `adjustedCoverageMaxTolerance`. Measured maximum per-glyph mean:
/// **23.093** (Noto Sans 17 pt ×1); the other three adjusted sizes measure
/// 17.700, 18.048 and 20.987. Margin +2.9.
///
/// These are larger than record §24's 15.7–18.6 for the same four sizes
/// because the glyph set is not the same one: this corpus is whole words, so
/// it weights different glyphs.
let adjustedCoverageMeanTolerance = 26.0

/// (file, point size, scale) at which `CTFontDrawGlyphs` departs from the
/// glyph's own outline — measured by `FT-H` against a CoreGraphics fill of the
/// same path, and reproduced here, since the Apple side of this oracle is that
/// same `CTFontDrawGlyphs`. The difference is CoreText's glyph drawing, not
/// FreeType's and not `PortableText`'s.
let coreTextAdjustedSizes: Set<SizeKey> = [
    SizeKey(file: notoSans, size: 17, scale: 1),
    SizeKey(file: sourceSans, size: 11, scale: 1),
    SizeKey(file: sourceSans, size: 13, scale: 1),
    SizeKey(file: sourceSans, size: 17, scale: 1),
]

// MARK: - The corpus

let notoSans = "NotoSans-Regular.ttf"          // TrueType outlines (glyf)
let sourceSans = "SourceSans3-Regular.otf"     // CFF outlines ('CFF ')
let notoSansArabic = "NotoSansArabic-Regular.ttf"
let fontFiles = [notoSans, sourceSans]

/// Two plain words, a kerning pair, a ligature pair, a string with a space
/// (whose glyph is packed by both pipelines and emitted by neither), and a
/// sentence long enough that a per-glyph pen error accumulates into a whole
/// pixel if there is one.
let corpusStrings = [
    "Hamburg",
    "Wig",
    "AV",
    "fi",
    "in a box",
    "The quick brown fox jumps over the lazy dog.",
]
let sizes: [Double] = [11, 13, 17, 26]
let scales: [Float] = [1, 2]
/// A whole-pixel origin and one that is not, so both pipelines are driven
/// through more than one subpixel variant. At scale 1, `10.37` puts the first
/// glyph in variant 1 and later glyphs wherever their advances land; at scale
/// 2 the same origin lands on a different variant sequence.
let originXs: [Double] = [10.0, 10.37]
/// The baselines both pipelines draw on, in points.
///
/// **`20.8` is not decoration.** Both pipelines round the baseline to a whole
/// device pixel, and at a whole-point baseline `round` and `floor` agree at
/// every scale — a `floor` mutant in `PortableText.emit` passed the whole of
/// this file until this second value was added. `20.8` separates them at
/// scale 1 (21 vs 20) and at scale 2 (41.6 -> 42 vs 41), and sits nowhere
/// near a `.5` boundary, where the ascent round trip on the Apple side could
/// tip either way.
let baselineYs: [Double] = [20.0, 20.8]

/// A failure message built by concatenation. `#expect`'s comment parameter
/// takes a string *literal*, so a message assembled with `+` needs wrapping.
func note(_ message: String) -> Comment { Comment(rawValue: message) }

struct SizeKey: Hashable, CustomStringConvertible {
    let file: String
    let size: Double
    let scale: Float
    var description: String { "\(file) \(size)pt x\(scale)" }
}

struct CorpusCase: CustomStringConvertible {
    let key: SizeKey
    let text: String
    let originX: Double
    let baselineY: Double
    var description: String { "\(key) \"\(text)\" @(\(originX), \(baselineY))" }
}

func corpusCases() -> [CorpusCase] {
    var cases: [CorpusCase] = []
    for file in fontFiles {
        for size in sizes {
            for scale in scales {
                for text in corpusStrings {
                    for originX in originXs {
                        for baseline in baselineYs {
                            cases.append(CorpusCase(key: SizeKey(file: file, size: size,
                                                                 scale: scale),
                                                    text: text, originX: originX,
                                                    baselineY: baseline))
                        }
                    }
                }
            }
        }
    }
    return cases
}

// MARK: - Loading one font file into both pipelines

/// The bytes of `Tests/Fonts/<file>`, by `#filePath` rather than as a resource
/// (`FT-G`).
func fontBytes(_ file: String) throws -> [UInt8] {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fonts").appendingPathComponent(file)
    return [UInt8](try Data(contentsOf: url))
}

/// One font file, opened in the portable pipeline and in CoreText.
final class OracleFont {
    let file: String
    let data: [UInt8]
    private let descriptor: CTFontDescriptor
    private var portableCache: [Double: PortableFont] = [:]
    private var appleCache: [Double: ResolvedFont] = [:]

    init(_ file: String) throws {
        self.file = file
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fonts").appendingPathComponent(file)
        let bytes = try Data(contentsOf: url)
        data = [UInt8](bytes)
        let descriptors = CTFontManagerCreateFontDescriptorsFromData(bytes as CFData)
            as? [CTFontDescriptor] ?? []
        descriptor = try #require(descriptors.first, "CoreText rejected \(file)")
    }

    func portable(size: Double) throws -> PortableFont {
        if let cached = portableCache[size] { return cached }
        let font = try PortableFont(data: data, size: size)
        portableCache[size] = font
        return font
    }

    func apple(size: Double) -> ResolvedFont {
        if let cached = appleCache[size] { return cached }
        let font = ResolvedFont(ctFont: CTFontCreateWithFontDescriptor(descriptor,
                                                                      CGFloat(size), nil))
        appleCache[size] = font
        return font
    }
}

/// The corpus' two Latin faces, opened once per test.
func oracleFonts() throws -> [String: OracleFont] {
    var fonts: [String: OracleFont] = [:]
    for file in fontFiles { fonts[file] = try OracleFont(file) }
    return fonts
}

// MARK: - The two emissions

/// What either pipeline put on screen for one glyph: where the sprite goes,
/// and which atlas rectangle it samples.
struct EmittedGlyph: Equatable {
    let originX: Float
    let originY: Float
    let width: Float
    let height: Float
    /// The atlas rectangle this sprite samples. Spelled out rather than held
    /// as an `AtlasSlot` because that type's memberwise initializer is
    /// internal to `MetalUIScene`, and the portable side reads its slot back
    /// out of an `MUIGlyph` as four floats anyway.
    let slotX: Int
    let slotY: Int
    let slotWidth: Int
    let slotHeight: Int
}

/// One case, emitted both ways, with both atlases kept so their coverage can
/// be compared slot by slot.
struct Emission {
    let portable: [EmittedGlyph]
    let portableAtlas: GlyphAtlas
    let apple: [EmittedGlyph]
    let appleAtlas: GlyphAtlas
    /// The device baseline each pipeline rounded to, which must agree before
    /// any rect comparison means anything.
    let portableBaselineY: Int
    let appleBaselineY: Int
}

let contentMask = MUIBounds(origin: MUIPoint(x: 0, y: 0),
                            size: MUISize(width: 4000, height: 4000))
let inkColor = MUIHsla(h: 0, s: 0, l: 0, a: 1)

func emitBothWays(_ testCase: CorpusCase, fonts: [String: OracleFont]) throws -> Emission {
    let oracle = try #require(fonts[testCase.key.file])
    let scale = testCase.key.scale

    // Portable: the whole pipeline under test, called exactly as a backend
    // would call it.
    let portableFont = try oracle.portable(size: testCase.key.size)
    var scene = Scene()
    let portableAtlas = GlyphAtlas(width: 2048, height: 2048)
    portableAtlas.beginFrame()
    try PortableText.emit(testCase.text, font: portableFont,
                          origin: (x: testCase.originX, y: testCase.baselineY), scaleFactor: scale,
                          color: inkColor, contentMask: contentMask,
                          into: &scene, atlas: portableAtlas)
    portableAtlas.endFrame()

    let portable = scene.glyphs.map {
        EmittedGlyph(originX: $0.bounds.origin.x, originY: $0.bounds.origin.y,
                     width: $0.bounds.size.width, height: $0.bounds.size.height,
                     slotX: Int($0.atlasBounds.origin.x),
                     slotY: Int($0.atlasBounds.origin.y),
                     slotWidth: Int($0.atlasBounds.size.width),
                     slotHeight: Int($0.atlasBounds.size.height))
    }

    // Apple: CoreText shaping, CoreText placement, CoreText rasterization,
    // through the same `GlyphAtlas`, with `Frame.draw`'s arithmetic.
    let appleFont = oracle.apple(size: testCase.key.size)
    let shaped = Shaper.shape(testCase.text, font: appleFont, wrappingAt: nil)
    let placed = shaped.placedGlyphs(at: (x: testCase.originX,
                                          y: testCase.baselineY - appleFont.metrics.ascent),
                                     font: appleFont, scaleFactor: scale)
    let appleAtlas = GlyphAtlas(width: 2048, height: 2048)
    appleAtlas.beginFrame()
    var apple: [EmittedGlyph] = []
    for glyph in placed {
        // `Frame.draw`, with no active offset, clip or opacity to fold in.
        guard let packed = appleAtlas.packed(for: glyph.key, rasterize: {
            GlyphRaster.rasterize(glyph: glyph.key.glyph, font: glyph.font,
                                  subpixelVariant: glyph.key.subpixelVariant,
                                  scaleFactor: glyph.key.scaleFactor)
        }) else { continue }
        guard packed.slot.width > 0, packed.slot.height > 0 else { continue }
        apple.append(EmittedGlyph(originX: Float(glyph.pixelX + packed.left),
                                  originY: Float(glyph.baselineY - packed.top),
                                  width: Float(packed.slot.width),
                                  height: Float(packed.slot.height),
                                  slotX: packed.slot.x, slotY: packed.slot.y,
                                  slotWidth: packed.slot.width,
                                  slotHeight: packed.slot.height))
    }
    appleAtlas.endFrame()

    return Emission(portable: portable, portableAtlas: portableAtlas,
                    apple: apple, appleAtlas: appleAtlas,
                    portableBaselineY: Int((testCase.baselineY * Double(scale)).rounded()),
                    appleBaselineY: placed.first?.baselineY
                        ?? Int((testCase.baselineY * Double(scale)).rounded()))
}

// MARK: - Coverage

/// A glyph's own bytes out of an atlas — region-scoped, as `FT-H` compared
/// them: nothing outside the slot is read, so a difference in *packing* can
/// never read as a difference in *ink*.
func coverage(_ atlas: GlyphAtlas, _ glyph: EmittedGlyph) -> [UInt8] {
    var bytes: [UInt8] = []
    bytes.reserveCapacity(glyph.slotWidth * glyph.slotHeight)
    for row in 0..<glyph.slotHeight {
        let start = (glyph.slotY + row) * atlas.width + glyph.slotX
        bytes.append(contentsOf: atlas.pixels[start..<(start + glyph.slotWidth)])
    }
    return bytes
}

/// Per-pixel |a − b| over two bitmaps of the same rectangle.
struct CoverageDiff {
    let max: Int
    let mean: Double
    init(_ a: [UInt8], _ b: [UInt8]) {
        precondition(a.count == b.count)
        var worst = 0
        var total = 0
        for i in a.indices {
            let d = abs(Int(a[i]) - Int(b[i]))
            worst = Swift.max(worst, d)
            total += d
        }
        max = worst
        mean = a.isEmpty ? 0 : Double(total) / Double(a.count)
    }
}

// MARK: - Geometry

/// Checks the **harness's** coordinate translation, not the pipeline's:
/// `placedGlyphs(at:)` takes a text-box top-left and `PortableText.emit` takes
/// a baseline, so the Apple side is handed `baseline - ascent`, and this is
/// what says the two sides then landed on the same device row. Drop the
/// `- ascent` and this reddens first; without it, every rect comparison in
/// this file would be comparing two runs drawn a whole ascent apart.
@Test func theTwoPipelinesShareABaseline() throws {
    let fonts = try oracleFonts()
    for testCase in corpusCases() where testCase.text == "Hamburg" {
        let emission = try emitBothWays(testCase, fonts: fonts)
        #expect(emission.portableBaselineY == emission.appleBaselineY,
                "\(testCase): baselines \(emission.portableBaselineY) vs \(emission.appleBaselineY)")
    }
}

@Test func everyCorpusCasePlacesTheSameGlyphsAsMetalUIsApplePath() throws {
    let fonts = try oracleFonts()
    for testCase in corpusCases() {
        let emission = try emitBothWays(testCase, fonts: fonts)
        #expect(emission.portable.count == emission.apple.count,
                "\(testCase): \(emission.portable.count) portable glyphs vs \(emission.apple.count)")
        guard emission.portable.count == emission.apple.count else { continue }
        for (i, (p, a)) in zip(emission.portable, emission.apple).enumerated() {
            // Exact equality, in order: PT-F's expectation, and what the
            // measurement test found. `origin` is where the sprite lands and
            // `size` is the bitmap's, so a single-pixel difference in either
            // is a visible difference in the drawn run.
            #expect(p.originX == a.originX && p.originY == a.originY,
                    note("\(testCase) glyph \(i): origin (\(p.originX), \(p.originY))"
                         + " vs (\(a.originX), \(a.originY))"))
            #expect(p.width == a.width && p.height == a.height,
                    note("\(testCase) glyph \(i): size \(p.width)x\(p.height)"
                         + " vs \(a.width)x\(a.height)"))
        }
    }
}

@Test func theTwoShapersAgreeOnTheGlyphSequenceForEveryCorpusString() throws {
    let fonts = try oracleFonts()
    for file in fontFiles {
        let oracle = try #require(fonts[file])
        for size in sizes {
            let portableFont = try oracle.portable(size: size)
            let appleFont = oracle.apple(size: size)
            // The atlas keys on FreeType's `FontKey` on one side and
            // CoreText's on the other (`FT-F`); if those ever diverged the
            // rect comparison would still pass while the two pipelines drew
            // from different cache entries.
            #expect(portableFont.key == appleFont.key, "\(file) \(size)pt: font keys differ")
            for text in corpusStrings {
                let portableIDs = try HarfBuzzShaper.shape(text, font: portableFont.shaping)
                    .glyphs.map(\.id)
                let appleIDs = Shaper.shape(text, font: appleFont, wrappingAt: nil)
                    .placedGlyphs(at: (x: 0, y: 0), font: appleFont, scaleFactor: 1)
                    .map(\.key.glyph)
                #expect(portableIDs == appleIDs,
                        "\(file) \(size)pt \"\(text)\": \(portableIDs) vs \(appleIDs)")
            }
        }
    }
}

@Test func noCorpusGlyphCarriesAShapingOffset() throws {
    // **Why a test asserts something the pipeline does not depend on.**
    // Mutating `(pen + glyph.xOffset)` down to `pen` in `PortableText.emit`
    // reddens nothing in this file. That is not a hole in the assertions: it
    // is that HarfBuzz reports every glyph of this Latin corpus with a zero
    // offset on both axes, so the mutant is the same arithmetic on this
    // input, not a different answer that went unnoticed. Record §26 measured
    // the same thing from the other side (CoreText has no per-glyph offset at
    // all, and folds it into its advances); the cases that do carry offsets
    // are Arabic marks, and PT-F's corpus is Latin by ruling.
    //
    // This reddens the day a corpus string starts producing an offset, which
    // is the day the pen-walk mutant becomes visible and this comment stops
    // being true.
    let fonts = try oracleFonts()
    for file in fontFiles {
        let oracle = try #require(fonts[file])
        for size in sizes {
            let portableFont = try oracle.portable(size: size)
            for text in corpusStrings {
                let run = try HarfBuzzShaper.shape(text, font: portableFont.shaping)
                for (i, glyph) in run.glyphs.enumerated() {
                    #expect(glyph.xOffset == 0 && glyph.yOffset == 0,
                            note("\(file) \(size)pt \"\(text)\" glyph \(i): offset "
                                 + "(\(glyph.xOffset), \(glyph.yOffset))"))
                }
            }
        }
    }
}

// MARK: - Coverage

@Test func everyCorpusCaseInksTheSameCoverageAsMetalUIsApplePath() throws {
    let fonts = try oracleFonts()
    for testCase in corpusCases() {
        let emission = try emitBothWays(testCase, fonts: fonts)
        guard emission.portable.count == emission.apple.count else { continue }
        let adjusted = coreTextAdjustedSizes.contains(testCase.key)
        let maxBound = adjusted ? adjustedCoverageMaxTolerance : coverageMaxTolerance
        let meanBound = adjusted ? adjustedCoverageMeanTolerance : coverageMeanTolerance
        for (i, (p, a)) in zip(emission.portable, emission.apple).enumerated() {
            guard p.slotWidth == a.slotWidth, p.slotHeight == a.slotHeight else {
                Issue.record("\(testCase) glyph \(i): slot sizes differ, coverage not comparable")
                continue
            }
            let diff = CoverageDiff(coverage(emission.portableAtlas, p),
                                    coverage(emission.appleAtlas, a))
            #expect(diff.max <= maxBound,
                    "\(testCase) glyph \(i): per-pixel \(diff.max) > \(maxBound)")
            #expect(diff.mean <= meanBound,
                    "\(testCase) glyph \(i): mean \(diff.mean) > \(meanBound)")
        }
    }
}

@Test func coreTextDrawsAwayFromItsOutlineAtExactlyTheseSizes() throws {
    let fonts = try oracleFonts()
    var worstMean: [SizeKey: Double] = [:]
    for testCase in corpusCases() {
        let emission = try emitBothWays(testCase, fonts: fonts)
        guard emission.portable.count == emission.apple.count else { continue }
        for (p, a) in zip(emission.portable, emission.apple)
        where p.slotWidth == a.slotWidth && p.slotHeight == a.slotHeight {
            let diff = CoverageDiff(coverage(emission.portableAtlas, p),
                                    coverage(emission.appleAtlas, a))
            worstMean[testCase.key] = Swift.max(worstMean[testCase.key] ?? 0, diff.mean)
        }
    }
    // The list is not decoration: at these sizes and nowhere else,
    // `CTFontDrawGlyphs` moves ink off the outline it reports (record §24),
    // so the ordinary bound cannot hold. If CoreText stops doing it, or
    // starts at another size, this reddens rather than the list quietly
    // covering a real portable-pipeline difference.
    for (key, mean) in worstMean {
        if coreTextAdjustedSizes.contains(key) {
            #expect(mean > coverageMeanTolerance,
                    "\(key) is pinned as adjusted but its worst mean is only \(mean)")
        } else {
            #expect(mean <= coverageMeanTolerance,
                    "\(key) is not pinned as adjusted but its worst mean is \(mean)")
        }
    }
}

// MARK: - The cross-engine check (PT-B)

@Test func aPortableFontWhoseHalvesAreDifferentFilesThrows() throws {
    let noto = try fontBytes(notoSans)
    let source = try fontBytes(sourceSans)
    let arabic = try fontBytes(notoSansArabic)

    // Two Latin faces: same `unitsPerEm`, different glyph order, so the probe
    // catches it.
    #expect(throws: PortableTextError.self) {
        _ = try PortableFont(shapingData: noto, rasterData: source, faceIndex: 0, size: 13)
    }
    #expect(throws: PortableTextError.self) {
        _ = try PortableFont(shapingData: source, rasterData: noto, faceIndex: 0, size: 13)
    }
    // A Latin face shaping for an Arabic face's outlines: the "A" probe is
    // unmapped in the raster face and skipped, and the Arabic probe is what
    // catches this pair.
    #expect(throws: PortableTextError.self) {
        _ = try PortableFont(shapingData: noto, rasterData: arabic, faceIndex: 0, size: 13)
    }
    // The same outlines under a different `unitsPerEm`: every glyph id agrees,
    // so the probe cannot see it, and only the `unitsPerEm` comparison can.
    // All three bundled fonts are 1000 units per em, so without this case that
    // comparison is unreachable — deleting it reddened nothing (measured).
    let rescaled = try withUnitsPerEm(2048, noto)
    #expect(throws: PortableTextError.self) {
        _ = try PortableFont(shapingData: noto, rasterData: rescaled, faceIndex: 0, size: 13)
    }
    // ...and the patched face really is 2048 in both engines, and opens: the
    // throw above is the comparison, not a face that failed to load.
    #expect(throws: Never.self) {
        _ = try PortableFont(shapingData: rescaled, rasterData: rescaled, faceIndex: 0, size: 13)
    }
    #expect(try HarfBuzzFont(data: rescaled, size: 13).unitsPerEm == 2048)
    #expect(try FreeTypeFont(data: rescaled, size: 13).unitsPerEm == 2048)
    // The control: the same bytes in both halves is exactly what the public
    // initializer does, and must not throw.
    #expect(throws: Never.self) {
        _ = try PortableFont(shapingData: noto, rasterData: noto, faceIndex: 0, size: 13)
    }
}

/// `font` with its `head` table's `unitsPerEm` (offset 18, big-endian UInt16)
/// overwritten. The table checksum is left stale; neither engine verifies it.
func withUnitsPerEm(_ unitsPerEm: UInt16, _ font: [UInt8]) throws -> [UInt8] {
    func u16(_ at: Int) -> Int { Int(font[at]) << 8 | Int(font[at + 1]) }
    func u32(_ at: Int) -> Int { u16(at) << 16 | u16(at + 2) }
    let tables = u16(4)
    for index in 0..<tables {
        let record = 12 + 16 * index
        guard font[record..<record + 4].elementsEqual("head".utf8) else { continue }
        var patched = font
        let offset = u32(record + 8) + 18
        patched[offset] = UInt8(unitsPerEm >> 8)
        patched[offset + 1] = UInt8(unitsPerEm & 0xff)
        return patched
    }
    throw PortableTextError("no head table")
}

// MARK: - Measurement (gated)

/// Prints every number the constants above were set from. Gated because it is
/// a measurement, not an assertion: it must not decide whether the suite is
/// green.
@Test(.enabled(if: ProcessInfo.processInfo.environment["METALUI_PORTABLE_ORACLE_MEASURE"] == "1"))
func theMeasuredDifferences() throws {
    let fonts = try oracleFonts()
    var geometryDifferences = 0
    var countDifferences = 0
    var worst: [SizeKey: (max: Int, mean: Double, glyphs: Int)] = [:]

    for testCase in corpusCases() {
        let emission = try emitBothWays(testCase, fonts: fonts)
        if emission.portable.count != emission.apple.count {
            countDifferences += 1
            print("COUNT \(testCase): \(emission.portable.count) vs \(emission.apple.count)")
            continue
        }
        if emission.portableBaselineY != emission.appleBaselineY {
            print("BASELINE \(testCase): \(emission.portableBaselineY) vs \(emission.appleBaselineY)")
        }
        for (i, (p, a)) in zip(emission.portable, emission.apple).enumerated() {
            if p.originX != a.originX || p.originY != a.originY
                || p.width != a.width || p.height != a.height {
                geometryDifferences += 1
                print("GEOMETRY \(testCase) glyph \(i): "
                      + "(\(p.originX), \(p.originY)) \(p.width)x\(p.height) vs "
                      + "(\(a.originX), \(a.originY)) \(a.width)x\(a.height)")
            }
            guard p.slotWidth == a.slotWidth, p.slotHeight == a.slotHeight else { continue }
            let diff = CoverageDiff(coverage(emission.portableAtlas, p),
                                    coverage(emission.appleAtlas, a))
            let previous = worst[testCase.key] ?? (max: 0, mean: 0, glyphs: 0)
            worst[testCase.key] = (max: Swift.max(previous.max, diff.max),
                                   mean: Swift.max(previous.mean, diff.mean),
                                   glyphs: previous.glyphs + 1)
        }
    }

    print("MEASURE cases=\(corpusCases().count) countDifferences=\(countDifferences) "
          + "geometryDifferences=\(geometryDifferences)")
    print("MEASURE | font | pt x scale | glyphs | worst per-pixel | worst per-glyph mean | adjusted |")
    for key in worst.keys.sorted(by: { ($0.file, $0.size, $0.scale) < ($1.file, $1.size, $1.scale) }) {
        let w = worst[key]!
        print("MEASURE | \(key.file) | \(key.size) x\(key.scale) | \(w.glyphs) | \(w.max) | "
              + String(format: "%.3f", w.mean)
              + " | \(coreTextAdjustedSizes.contains(key) ? "yes" : "no") |")
    }
}
