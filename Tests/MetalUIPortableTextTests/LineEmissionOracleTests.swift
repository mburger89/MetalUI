import CoreText
import Foundation
import Testing
import MetalUIScene
import MetalUIShaderTypes
import MetalUIFreeType
import MetalUIHarfBuzz
@testable import MetalUIPortableText
@testable import MetalUIText

// LB-F and LB-I: MetalUI's Apple path is the oracle for the portable line
// metrics and for `PortableText.emitLines`' placement. Same font file in
// both, via `OracleFont`.
//
// Measured before the assertions were written (`METALUI_LINES_EMIT_MEASURE=1`,
// 2026-09-23, macOS 27.0):
//
// - Metrics, three faces × eleven sizes and five patched variants of each:
//   the two TrueType faces **exactly** CoreText's once read from `hhea` (not
//   FreeType's `FT_Face.ascender`, which follows OS/2 under
//   `USE_TYPO_METRICS`) as a 16.16 fraction of the em; the CFF face within
//   6.4e-5 pt. `lineHeight` equal everywhere but one patched CFF face, pinned.
// - Placement, 26,928 cases (LB-E's wrap corpus at scale 1 and 2), 784,380
//   glyphs: the first version differed in 9,548 cases. Three rules, each from
//   a measured disagreement, took that to 0 (record §31): default ignorables
//   draw nothing; a control or hard-break character without a glyph draws the
//   space glyph; design units scale by `size / unitsPerEm` taken first. What
//   remains is CoreText's glyph 0xFFFF on a line that is nothing but a soft
//   hyphen — the oracle drops it, and `coreTextDrawsNothingForItsDeletedGlyph`
//   says why that is safe.

let metricFontFiles = fontFiles + ["NotoSansArabic-Regular.ttf"]
let metricSizes: [Double] = [9, 11, 12, 13, 14, 15, 16, 17, 22, 26, 31.5]
let emissionScales: [Float] = [1, 2]

struct PlacementDifference: CustomStringConvertible {
    let file: String, size: Double, scale: Float, width: Double?, text: String
    let detail: String
    var description: String {
        "\(file) \(size)pt x\(scale) w=\(width.map { "\($0)" } ?? "nil") \(text.debugDescription): \(detail)"
    }
}

/// One glyph as either path places it: id, whole device pixel, subpixel
/// variant, device baseline row.
struct Placed: Equatable, CustomStringConvertible {
    let id: UInt16, pixelX: Int, variant: Int, baselineY: Int
    var description: String { "#\(id)@\(pixelX).\(variant),\(baselineY)" }
}

func applePlaced(_ text: String, font: ResolvedFont, width: Double?,
                 origin: (x: Double, y: Double), scale: Float) -> [Placed] {
    Shaper.shape(text, font: font, wrappingAt: width)
        .placedGlyphs(at: origin, font: font, scaleFactor: scale)
        .filter { $0.key.glyph != coreTextDeletedGlyph }
        .map { Placed(id: $0.key.glyph, pixelX: $0.pixelX, variant: $0.key.subpixelVariant,
                      baselineY: $0.baselineY) }
}

/// The glyph CoreText reports for a character it deleted (`kCGFontIndexInvalid`).
let coreTextDeletedGlyph: UInt16 = 0xFFFF

func portablePlaced(_ text: String, font: PortableFont, width: Double?,
                    origin: (x: Double, y: Double), scale: Float) throws -> [Placed] {
    try PortableText.placements(text, font: font, origin: origin, wrappingAt: width,
                                scaleFactor: scale).placements.map {
        let split = GlyphImage.subpixelPlacement(forDeviceX: $0.deviceX)
        return Placed(id: $0.id, pixelX: split.pixelX, variant: split.variant, baselineY: $0.baselineY)
    }
}

/// A fractional origin, so neither the pen nor the baseline starts on a
/// pixel boundary.
let emissionOrigin = (x: 3.3, y: 7.6)

func placementDifferences() throws -> (cases: Int, glyphs: Int, differences: [PlacementDifference]) {
    var cases = 0, glyphs = 0
    var differences: [PlacementDifference] = []
    for file in fontFiles {
        let font = try OracleFont(file)
        for size in wrapSizes {
            for scale in emissionScales {
                for width in wrapWidths {
                    for text in wrapStrings {
                        if let focus = ProcessInfo.processInfo.environment["METALUI_LINES_EMIT_FOCUS"],
                           !text.contains(focus) { continue }
                        cases += 1
                        let apple = applePlaced(text, font: font.apple(size: size), width: width,
                                                origin: emissionOrigin, scale: scale)
                        let portable = try portablePlaced(text, font: font.portable(size: size),
                                                          width: width, origin: emissionOrigin,
                                                          scale: scale)
                        glyphs += apple.count
                        guard apple != portable else { continue }
                        let detail: String
                        if apple.count != portable.count || ProcessInfo.processInfo.environment["METALUI_LINES_EMIT_FOCUS"] != nil {
                            detail = "\(apple.count) apple glyphs vs \(portable.count)\n  apple    \(apple)\n  portable \(portable)"
                        } else {
                            let i = apple.indices.first { apple[$0] != portable[$0] }!
                            detail = "glyph \(i): apple \(apple[i]) portable \(portable[i])"
                        }
                        differences.append(PlacementDifference(file: file, size: size, scale: scale,
                                                               width: width, text: text, detail: detail))
                    }
                }
            }
        }
    }
    return (cases, glyphs, differences)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["METALUI_LINES_EMIT_MEASURE"] == "1"))
func measureLineEmissionDifferences() throws {
    var worst = (ascent: 0.0, descent: 0.0, leading: 0.0)
    var lineHeightMisses: [String] = []
    for file in metricFontFiles {
        let font = try OracleFont(file)
        for size in metricSizes {
            let portable = try font.portable(size: size).metrics
            let apple = font.apple(size: size).metrics
            worst.ascent = max(worst.ascent, abs(portable.ascent - apple.ascent))
            worst.descent = max(worst.descent, abs(portable.descent - apple.descent))
            worst.leading = max(worst.leading, abs(portable.leading - apple.leading))
            print("METRICS \(file) \(size): portable \(portable.ascent) \(portable.descent) \(portable.leading) \(portable.lineHeight)"
                  + " apple \(apple.ascent) \(apple.descent) \(apple.leading) \(apple.lineHeight)")
            if portable.lineHeight != apple.lineHeight { lineHeightMisses.append("\(file) \(size)") }
        }
    }
    print("METRICS worst ascent=\(worst.ascent) descent=\(worst.descent) leading=\(worst.leading) lineHeightMisses=\(lineHeightMisses)")
    let (cases, glyphs, differences) = try placementDifferences()
    print("PLACEMENT cases=\(cases) glyphs=\(glyphs) differences=\(differences.count)")
    for difference in differences.prefix(40) { print("PLACEMENT \(difference)") }
}

/// A CFF face's metrics against CoreText's. CoreText scales a CFF face's
/// by a further 1 + 17·2⁻²³ (a Float32 value; its origin was searched for and
/// not found — record §31), so they agree to 2.03e-6 × the value: measured
/// worst 6.38e-5 pt (Source Sans 3 at 31.5 pt). Margin ×1.5. A TrueType
/// face's are compared **exactly** (CoreText's 16.16 fraction of the em, LB-F).
let cffMetricTolerance = 1e-4

func expectMetrics(_ portable: PortableFontMetrics, _ apple: FontMetrics, exact: Bool,
                   _ label: String) {
    let tolerance = exact ? 0 : cffMetricTolerance
    #expect(abs(portable.ascent - apple.ascent) <= tolerance, "\(label) ascent \(portable.ascent) vs \(apple.ascent)")
    #expect(abs(portable.descent - apple.descent) <= tolerance, "\(label) descent \(portable.descent) vs \(apple.descent)")
    #expect(abs(portable.leading - apple.leading) <= tolerance, "\(label) leading \(portable.leading) vs \(apple.leading)")
}

/// Whether `file` is a `glyf` face — spelled from the file's sfnt version,
/// not from `FreeTypeFont.format`, which is what the code under test reads.
func isTrueType(_ bytes: [UInt8]) -> Bool { bytes.prefix(4).elementsEqual([0, 1, 0, 0]) }

@Test func portableMetricsMatchCoreTextsAndTheLineHeightExactly() throws {
    for file in metricFontFiles {
        let font = try OracleFont(file)
        let exact = isTrueType(font.data)
        for size in metricSizes {
            let portable = try font.portable(size: size).metrics
            let apple = font.apple(size: size).metrics
            expectMetrics(portable, apple, exact: exact, "\(file) \(size)pt")
            // The number every baseline after the first is spaced by: exact,
            // and computed here from CoreText's three, not read off
            // `FontMetrics.lineHeight` (an oracle that is not the formula).
            let appleLineHeight = (apple.ascent + apple.descent + apple.leading).rounded(.up)
            #expect(portable.lineHeight == appleLineHeight, "\(file) \(size)pt lineHeight")
        }
    }
}

/// Faces whose `hhea` and OS/2 numbers disagree, or that have a line gap —
/// none of the bundled faces does. CoreText reads `hhea` whatever
/// `USE_TYPO_METRICS` says (both Noto faces set it), so these separate
/// `hhea` from FreeType's `FT_Face.ascender`, which honours the flag.
@Test func facesWithPatchedMetricsMatchCoreText() throws {
    for file in metricFontFiles {
        let bytes = try fontBytes(file)
        for patch in patchedFaces {
            let patched = try patch.apply(bytes)
            let apple = try coreTextMetrics(patched, size: 10)
            let portable = try PortableFont(data: patched, size: 10).metrics
            expectMetrics(portable, apple, exact: isTrueType(bytes), "\(file) \(patch.name)")
            let appleLineHeight = (apple.ascent + apple.descent + apple.leading).rounded(.up)
            if file == "SourceSans3-Regular.otf" && patch.name == "hhea descender -400" {
                continue   // pinned below
            }
            #expect(portable.lineHeight == appleLineHeight, "\(file) \(patch.name) lineHeight")
        }
    }
}

/// Pinned wrong on purpose: a CFF face whose `ascent + descent + leading` is
/// a whole number of points is one point taller on CoreText, whose CFF
/// scaling runs 2e-6 high and so carries the sum just past the integer that
/// `ceil` would keep. Source Sans 3 with its `hhea` descender patched to
/// −400 at 10 pt: 10 + 4 = 14 here, 14.0000284 → 15 on CoreText. No bundled
/// face at any measured size sums to a whole number, so no real text sees it.
/// Reddens if either side changes.
@Test func aCFFFaceWhoseLineSumIsWholeIsOnePointTallerOnCoreText() throws {
    let patched = try patching("hhea", at: 6, to: -400, fontBytes("SourceSans3-Regular.otf"))
    let apple = try coreTextMetrics(patched, size: 10)
    let portable = try PortableFont(data: patched, size: 10).metrics
    #expect(portable.lineHeight == 14)
    #expect((apple.ascent + apple.descent + apple.leading).rounded(.up) == 15)
}

/// The metrics are each face's own, not one face's numbers or a constant:
/// the three bundled faces disagree on every one of them at 12 pt (line
/// heights 17, 16 and 26; at 13 pt the two Latin faces share 18).
@Test func eachFaceHasItsOwnMetrics() throws {
    let metrics = try metricFontFiles.map { try OracleFont($0).portable(size: 12).metrics }
    try #require(metrics.count == 3)
    #expect(Set(metrics.map(\.ascent)).count == 3)
    #expect(Set(metrics.map(\.descent)).count == 3)
    #expect(Set(metrics.map(\.lineHeight)).count == 3)
}

@Test func everyWrapCorpusCasePlacesTheSameGlyphsAsMetalUIsApplePath() throws {
    let (cases, glyphs, differences) = try placementDifferences()
    try #require(cases == 26_928)
    #expect(glyphs > 700_000)
    #expect(differences.isEmpty, "\(differences.count) cases differ; first: \(differences.first.map { "\($0)" } ?? "")")
}

/// Dropping CoreText's 0xFFFF glyph from the oracle is safe only because the
/// Apple path draws nothing for it.
@Test func coreTextDrawsNothingForItsDeletedGlyph() throws {
    for file in fontFiles {
        let font = try OracleFont(file).apple(size: 17)
        for scale: Float in [1, 2] {
            #expect(GlyphRaster.rasterize(glyph: coreTextDeletedGlyph, font: font,
                                          subpixelVariant: 0, scaleFactor: scale).isEmpty)
        }
    }
}

/// The substitutions are visible, not bookkeeping: `.notdef` has ink in both
/// Latin faces, so a newline drawn as HarfBuzz shapes it would draw a box.
@Test func notdefHasInkInEveryLatinFace() throws {
    for file in fontFiles {
        let font = try OracleFont(file).portable(size: 17)
        let notdef = try FreeTypeRaster.rasterize(glyph: 0, font: font.raster, subpixelVariant: 0, scaleFactor: 1)
        #expect(notdef.bytes.contains { $0 > 0 }, "\(file)")
    }
}

/// The corpus reaches each of the three LB-I rules and the 0xFFFF drop, so
/// none of them is vacuously satisfied.
@Test func theEmissionCorpusReachesEveryRule() throws {
    let font = try OracleFont("SourceSans3-Regular.otf")
    let apple = font.apple(size: 26)
    let portable = try font.portable(size: 26)
    var ignorableDropped = 0, controlsSubstituted = 0, deleted = 0
    for text in wrapStrings {
        let units = Array(text.utf16)
        let ignorable = PortableText.ignorableUnits(of: text, count: units.count)
        for glyph in try HarfBuzzShaper.shape(text, font: portable.shaping).glyphs {
            if ignorable[glyph.cluster] { ignorableDropped += 1 }
            if glyph.id == 0, PortableText.isControl(units[glyph.cluster])
                || PortableText.isHardBreak(units[glyph.cluster]) { controlsSubstituted += 1 }
        }
        deleted += Shaper.shape(text, font: apple, wrappingAt: 4)
            .placedGlyphs(at: (0, 0), font: apple, scaleFactor: 1)
            .filter { $0.key.glyph == coreTextDeletedGlyph }.count
    }
    #expect(ignorableDropped > 0)
    #expect(controlsSubstituted > 0)
    #expect(deleted > 0)
}

// MARK: - Faces with the vertical metrics patched

/// `font` with the big-endian Int16 at `offset` into table `tag` set to
/// `value` — to give a face a line gap, or `hhea` and OS/2 numbers that
/// disagree, which no bundled face has.
func patching(_ tag: String, at offset: Int, to value: Int16, _ font: [UInt8]) throws -> [UInt8] {
    func u16(_ at: Int) -> Int { Int(font[at]) << 8 | Int(font[at + 1]) }
    func u32(_ at: Int) -> Int { u16(at) << 16 | u16(at + 2) }
    for index in 0..<u16(4) {
        let record = 12 + 16 * index
        guard font[record..<record + 4].elementsEqual(tag.utf8) else { continue }
        var patched = font
        let at = u32(record + 8) + offset
        let bits = UInt16(bitPattern: value)
        patched[at] = UInt8(bits >> 8)
        patched[at + 1] = UInt8(bits & 0xff)
        return patched
    }
    throw PortableTextError("no \(tag) table")
}

/// CoreText's metrics for a face given as bytes.
func coreTextMetrics(_ bytes: [UInt8], size: Double) throws -> FontMetrics {
    let descriptors = CTFontManagerCreateFontDescriptorsFromData(Data(bytes) as CFData) as? [CTFontDescriptor] ?? []
    let descriptor = try #require(descriptors.first)
    return FontMetrics(of: CTFontCreateWithFontDescriptor(descriptor, CGFloat(size), nil))
}

/// `hhea`: ascender 4, descender 6, lineGap 8. OS/2: sTypoAscender 68,
/// sTypoDescender 70, sTypoLineGap 72, fsSelection 62 (bit 7 USE_TYPO_METRICS).
struct MetricPatch: Sendable {
    let name: String, table: String, offset: Int, value: Int16
    func apply(_ font: [UInt8]) throws -> [UInt8] { try patching(table, at: offset, to: value, font) }
}
let patchedFaces = [
    MetricPatch(name: "hhea lineGap 200", table: "hhea", offset: 8, value: 200),
    MetricPatch(name: "OS/2 typoLineGap 200", table: "OS/2", offset: 72, value: 200),
    MetricPatch(name: "hhea ascender 1200", table: "hhea", offset: 4, value: 1200),
    MetricPatch(name: "OS/2 typoAscender 1200", table: "OS/2", offset: 68, value: 1200),
    MetricPatch(name: "hhea descender -400", table: "hhea", offset: 6, value: -400),
]

@Test(.enabled(if: ProcessInfo.processInfo.environment["METALUI_LINES_EMIT_MEASURE"] == "1"))
func measurePatchedFaceMetrics() throws {
    for file in metricFontFiles {
        let bytes = try fontBytes(file)
        for face in patchedFaces {
            let name = face.name
            let patched = try face.apply(bytes)
            let apple = try coreTextMetrics(patched, size: 10)
            let portable = try PortableFont(data: patched, size: 10).metrics
            print("PATCHED \(file) \(name): apple \(apple.ascent) \(apple.descent) \(apple.leading) \(apple.lineHeight)"
                  + " portable \(portable.ascent) \(portable.descent) \(portable.leading) \(portable.lineHeight)")
        }
    }
}
