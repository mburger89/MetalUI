// SH-I: HarfBuzz shapes in integer design units (SH-D — the `hb_font` scale is
// the face's `unitsPerEm`, and no 26.6 quantization is anywhere in the path),
// so a run's glyph ids, clusters and positions should be identical on every
// platform. These tests pin, for the SH-G corpus in all three bundled fonts,
// the exact glyph-id sequence, the exact cluster sequence, the direction, the
// total advance in design units and an FNV-1a 64 checksum of the per-glyph
// design-unit positions — all RECORDED on macOS (arm64) by running
// `METALUI_PORTABLE_RECORD=1 swift test` here and pasting the printed table.
//
// Plus one end-to-end case: shape a Latin string with HarfBuzz, rasterize every
// glyph it returned with `FreeTypeRaster`, and pin the checksum of the
// concatenated boxes and coverage bytes — the whole non-Apple path, string to
// pixels, in one number.
//
// A failure off macOS is a real finding: the shaper (or FreeType under it) is
// not deterministic across platforms. Report the differing cases; do not re-pin
// from the failing platform.
//
// Fonts are the root package's `Tests/Fonts/` (FT-G, SH-F), read by path from
// `#filePath` — no resources, no CoreText. The oracle that says these numbers
// are *right* is `Tests/MetalUIHarfBuzzTests/HarfBuzzOracleTests.swift`, which
// compares them against CoreText and runs on macOS only; this package asserts
// only that they do not move.

import Foundation
import MetalUIFreeType
import MetalUIHarfBuzz
import MetalUIScene
import Testing

// MARK: - The corpus (the same strings SH-G's CoreText oracle uses)

let notoSans = "NotoSans-Regular.ttf"
let sourceSans = "SourceSans3-Regular.otf"
let notoSansArabic = "NotoSansArabic-Regular.ttf"

struct ShapingCase: Hashable, CustomStringConvertible {
    let font: String
    let name: String
    let text: String
    var description: String { "\(font) \(name)" }
}

/// Plain text, four kerning pairs, three ligature candidates, three combining
/// marks, digits and punctuation — in both Latin faces.
let latinStrings: [(String, String)] = [
    ("plain", "The quick brown fox jumps over the lazy dog"),
    ("kern AV", "AV"),
    ("kern To", "To"),
    ("kern Ty", "Ty"),
    ("kern LT", "LT"),
    ("liga fi", "fi"),
    ("liga fl", "fl"),
    ("liga ffi", "ffi"),
    ("mark e+acute", "e\u{0301}"),
    ("mark a+diaeresis", "a\u{0308}"),
    ("mark n+tilde", "n\u{0303}"),
    ("digits", "0123456789"),
    ("punctuation", ".,;:!?-()'\""),
]

/// A plain word, a sentence with spaces, lam-alef, a word with harakat, and
/// Arabic-Indic digits.
let arabicStrings: [(String, String)] = [
    ("arabic word", "مرحبا"),
    ("arabic sentence", "مرحبا بالعالم"),
    ("arabic lam-alef", "لا"),
    ("arabic harakat", "مَرْحَبًا"),
    ("arabic-indic digits", "٠١٢٣٤٥٦٧٨٩"),
]

/// Every case, in a fixed order: both Latin faces over the Latin strings, then
/// the Arabic face over the Arabic ones. 31 cases.
let corpus: [ShapingCase] =
    [notoSans, sourceSans].flatMap { font in
        latinStrings.map { ShapingCase(font: font, name: $0.0, text: $0.1) }
    }
    + arabicStrings.map { ShapingCase(font: notoSansArabic, name: $0.0, text: $0.1) }

/// The end-to-end case (SH-I): this string, in this face, at this size,
/// rasterized at this variant and scale. Its checksum covers the boxes and the
/// coverage bytes — not the advances, which the corpus pins above already carry
/// — so the string is chosen to make a SHAPING change show up as a different
/// glyph to rasterize: `Affix` forms `ffi` and `fluffy` forms `ffl`/`fl`, so a
/// shaper that stopped applying `liga` would rasterize a different glyph set.
let endToEndCase = ShapingCase(font: notoSans, name: "end-to-end",
                               text: "Affix the fluffy waffle: AV To Ty LT jig!")
let endToEndSize = 13.0
let endToEndVariant = 0
let endToEndScale: Float = 1

// MARK: - What is pinned

struct PinnedRun: Equatable, CustomStringConvertible {
    let ids: [UInt16]
    let clusters: [Int]
    let isRightToLeft: Bool
    /// Sum of the x advances, in design units.
    let advance: Int64
    /// FNV-1a 64 over each glyph's xAdvance, yAdvance, xOffset, yOffset as
    /// little-endian Int32 design units.
    let positions: UInt64

    var description: String {
        "ids \(ids) clusters \(clusters) rtl \(isRightToLeft) advance \(advance) fnv \(hex(positions))"
    }
}

struct PinnedRaster: Equatable, CustomStringConvertible {
    let glyphs: Int
    /// Total coverage bytes over every glyph in the run.
    let coverageBytes: Int
    /// FNV-1a 64 over, per glyph in run order: width, height, left, top as
    /// little-endian Int32, then the coverage bytes.
    let checksum: UInt64

    var description: String {
        "\(glyphs) glyphs, \(coverageBytes) coverage bytes, fnv \(hex(checksum))"
    }
}

// MARK: - Helpers

func fnv1a64(_ bytes: [UInt8]) -> UInt64 {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in bytes {
        hash ^= UInt64(byte)
        hash &*= 0x0000_0100_0000_01b3
    }
    return hash
}

func hex(_ value: UInt64) -> String {
    let digits = String(value, radix: 16)
    return "0x" + String(repeating: "0", count: 16 - digits.count) + digits
}

func appendLittleEndian(_ value: Int32, to bytes: inout [UInt8]) {
    let unsigned = UInt32(bitPattern: value)
    for shift in stride(from: 0, through: 24, by: 8) {
        bytes.append(UInt8(truncatingIfNeeded: unsigned >> UInt32(shift)))
    }
}

func fontBytes(_ file: String) throws -> [UInt8] {
    // .../Tests/PortableTests/Tests/HarfBuzzDeterminismTests/<this file>
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // HarfBuzzDeterminismTests
        .deletingLastPathComponent()   // Tests (of this package)
        .deletingLastPathComponent()   // PortableTests
        .deletingLastPathComponent()   // Tests (of the root package)
        .appendingPathComponent("Fonts").appendingPathComponent(file)
    return [UInt8](try Data(contentsOf: url))
}

enum ShapingMeasurementError: Error, CustomStringConvertible {
    /// A shaped number was not a whole design unit, at a size where SH-D's
    /// conversion is the identity — the unit conversion has changed.
    case fractionalDesignUnit(ShapingCase, Double)
    var description: String {
        switch self {
        case let .fractionalDesignUnit(shapingCase, value):
            return "\(shapingCase): \(value) is not a whole design unit"
        }
    }
}

/// Opens the face at `size == unitsPerEm`, so SH-D's `units × size / unitsPerEm`
/// is the identity and every number the shaper returns **is** a design unit.
/// The first open only reads the face's `unitsPerEm`.
func designUnitFont(_ file: String) throws -> HarfBuzzFont {
    let bytes = try fontBytes(file)
    let probe = try HarfBuzzFont(data: bytes, size: 1)
    return try HarfBuzzFont(data: bytes, size: Double(probe.unitsPerEm))
}

func pin(_ shapingCase: ShapingCase, _ run: ShapedRun) throws -> PinnedRun {
    func unit(_ value: Double) throws -> Int32 {
        guard let exact = Int32(exactly: value) else {
            throw ShapingMeasurementError.fractionalDesignUnit(shapingCase, value)
        }
        return exact
    }
    var bytes: [UInt8] = []
    var advance: Int64 = 0
    for glyph in run.glyphs {
        let xAdvance = try unit(glyph.xAdvance)
        appendLittleEndian(xAdvance, to: &bytes)
        appendLittleEndian(try unit(glyph.yAdvance), to: &bytes)
        appendLittleEndian(try unit(glyph.xOffset), to: &bytes)
        appendLittleEndian(try unit(glyph.yOffset), to: &bytes)
        advance += Int64(xAdvance)
    }
    return PinnedRun(ids: run.glyphs.map(\.id), clusters: run.glyphs.map(\.cluster),
                     isRightToLeft: run.isRightToLeft, advance: advance,
                     positions: fnv1a64(bytes))
}

/// Shapes every corpus case, opening each face once.
func measure() throws -> [ShapingCase: PinnedRun] {
    var fonts: [String: HarfBuzzFont] = [:]
    var results: [ShapingCase: PinnedRun] = [:]
    for shapingCase in corpus {
        let font: HarfBuzzFont
        if let cached = fonts[shapingCase.font] {
            font = cached
        } else {
            font = try designUnitFont(shapingCase.font)
            fonts[shapingCase.font] = font
        }
        results[shapingCase] = try pin(shapingCase, HarfBuzzShaper.shape(shapingCase.text, font: font))
    }
    return results
}

/// The end-to-end path: shape at 13 pt, rasterize every glyph, concatenate.
func measureEndToEnd() throws -> PinnedRaster {
    let bytes = try fontBytes(endToEndCase.font)
    let shaper = try HarfBuzzFont(data: bytes, size: endToEndSize)
    let freeType = try FreeTypeFont(data: bytes, size: endToEndSize)
    let run = try HarfBuzzShaper.shape(endToEndCase.text, font: shaper)
    var stream: [UInt8] = []
    var coverage = 0
    for glyph in run.glyphs {
        let image = try FreeTypeRaster.rasterize(glyph: glyph.id, font: freeType,
                                                 subpixelVariant: endToEndVariant,
                                                 scaleFactor: endToEndScale)
        appendLittleEndian(Int32(image.width), to: &stream)
        appendLittleEndian(Int32(image.height), to: &stream)
        appendLittleEndian(Int32(image.left), to: &stream)
        appendLittleEndian(Int32(image.top), to: &stream)
        stream.append(contentsOf: image.bytes)
        coverage += image.bytes.count
    }
    return PinnedRaster(glyphs: run.glyphs.count, coverageBytes: coverage,
                        checksum: fnv1a64(stream))
}

let recording = ProcessInfo.processInfo.environment["METALUI_PORTABLE_RECORD"] == "1"

// MARK: - Tests

@Suite struct HarfBuzzDeterminismTests {
    @Test func theChecksumIsFNV1a64() {
        // Published FNV-1a 64 test vectors: "" and "a".
        #expect(fnv1a64([]) == 0xcbf2_9ce4_8422_2325)
        #expect(fnv1a64([0x61]) == 0xaf63_dc4c_8601_ec8c)
    }

    @Test func everyCaseMatchesTheValuesRecordedOnMacOS() throws {
        let measured = try measure()
        try #require(corpus.count == 31)
        try #require(expectedRuns.count == corpus.count,
                     "expected table has \(expectedRuns.count) rows for \(corpus.count) cases")
        var mismatches = 0
        for (index, shapingCase) in corpus.enumerated() {
            let got = try #require(measured[shapingCase])
            if got != expectedRuns[index] {
                mismatches += 1
                Issue.record("\(shapingCase): measured \(got), recorded on macOS \(expectedRuns[index])")
            }
        }
        #expect(mismatches == 0, "\(mismatches) of \(corpus.count) cases differ from macOS")
    }

    /// SH-I's end-to-end case: string → HarfBuzz → FreeType → coverage bytes.
    @Test func theRasterizedRunMatchesTheValueRecordedOnMacOS() throws {
        let measured = try measureEndToEnd()
        #expect(measured == expectedEndToEnd,
                "measured \(measured), recorded on macOS \(expectedEndToEnd)")
    }

    /// Guards the pins against a shaper that returns nothing, or that has
    /// silently stopped applying the features the corpus is made of: every case
    /// has glyphs, the Arabic ones run right to left and the Latin ones do not,
    /// the two kinds of shaping the corpus exists to exercise both fire
    /// (`ffi` is one glyph in Noto Sans, and `AV` kerns negative), and no two
    /// distinct strings in one face shape to the same ids.
    @Test func theCorpusIsNotDegenerate() throws {
        let measured = try measure()
        for shapingCase in corpus {
            let pinned = try #require(measured[shapingCase])
            #expect(!pinned.ids.isEmpty, "\(shapingCase)")
            #expect(!pinned.ids.contains(0), "\(shapingCase) has a .notdef glyph")
            #expect(pinned.advance > 0, "\(shapingCase)")
            #expect(pinned.isRightToLeft == (shapingCase.font == notoSansArabic), "\(shapingCase)")
        }
        let font = try designUnitFont(notoSans)
        // A ligature really forms: three characters, one glyph.
        let ffi = try HarfBuzzShaper.shape("ffi", font: font)
        #expect(ffi.glyphs.count == 1)
        // Kerning really applies: "AV" is narrower than the two glyphs alone.
        let av = try HarfBuzzShaper.shape("AV", font: font)
        let a = try HarfBuzzShaper.shape("A", font: font)
        let v = try HarfBuzzShaper.shape("V", font: font)
        #expect(av.advance < a.advance + v.advance)
        // No two strings in one face collapse onto the same id sequence, which
        // would make a pin agree for the wrong reason.
        for file in [notoSans, sourceSans, notoSansArabic] {
            let inFace = corpus.filter { $0.font == file }
            let sequences = Set(inFace.map { measured[$0]!.ids })
            #expect(sequences.count == inFace.count, "\(file): \(inFace.count) cases, \(sequences.count) id sequences")
        }
    }

    /// The premise the design-unit pins rest on (SH-D): opened at
    /// `size == unitsPerEm` the conversion is the identity, so every shaped
    /// number is a whole design unit — and opened at another size the same run
    /// scales by exactly that ratio. A 26.6 scale anywhere would break both.
    @Test func shapingIsInWholeDesignUnitsAndScalesWithTheSize() throws {
        for file in [notoSans, sourceSans, notoSansArabic] {
            let bytes = try fontBytes(file)
            let upem = try HarfBuzzFont(data: bytes, size: 1).unitsPerEm
            #expect(upem > 0, "\(file)")
            let units = try HarfBuzzFont(data: bytes, size: Double(upem))
            let points = try HarfBuzzFont(data: bytes, size: endToEndSize)
            for shapingCase in corpus where shapingCase.font == file {
                let inUnits = try HarfBuzzShaper.shape(shapingCase.text, font: units)
                let inPoints = try HarfBuzzShaper.shape(shapingCase.text, font: points)
                try #require(inUnits.glyphs.count == inPoints.glyphs.count)
                for glyph in inUnits.glyphs {
                    #expect(Int32(exactly: glyph.xAdvance) != nil, "\(shapingCase): \(glyph.xAdvance)")
                    #expect(Int32(exactly: glyph.xOffset) != nil, "\(shapingCase): \(glyph.xOffset)")
                }
                let ratio = endToEndSize / Double(upem)
                for (unit, point) in zip(inUnits.glyphs, inPoints.glyphs) {
                    #expect(point.id == unit.id, "\(shapingCase)")
                    #expect(point.cluster == unit.cluster, "\(shapingCase)")
                    #expect(abs(point.xAdvance - unit.xAdvance * ratio) <= 1e-12, "\(shapingCase)")
                    #expect(abs(point.xOffset - unit.xOffset * ratio) <= 1e-12, "\(shapingCase)")
                }
            }
        }
    }

    @Test(.enabled(if: recording, "set METALUI_PORTABLE_RECORD=1 to print the expected table"))
    func record() throws {
        let measured = try measure()
        var lines = ["let expectedRuns: [PinnedRun] = ["]
        for shapingCase in corpus {
            let pinned = try #require(measured[shapingCase])
            lines.append("    PinnedRun(ids: \(pinned.ids), clusters: \(pinned.clusters), "
                         + "isRightToLeft: \(pinned.isRightToLeft), advance: \(pinned.advance), "
                         + "positions: \(hex(pinned.positions))),  // \(shapingCase)")
        }
        lines.append("]")
        let raster = try measureEndToEnd()
        lines.append("let expectedEndToEnd = PinnedRaster(glyphs: \(raster.glyphs), "
                     + "coverageBytes: \(raster.coverageBytes), checksum: \(hex(raster.checksum)))")
        print(lines.joined(separator: "\n"))
    }
}
