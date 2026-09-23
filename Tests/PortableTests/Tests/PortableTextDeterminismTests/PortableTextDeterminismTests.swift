// PT-H: the portable text pipeline — `PortableText.emit`, which shapes with
// HarfBuzz, rasterizes with FreeType and places with `Frame.draw`'s arithmetic
// (PT-D) — should produce the same `Scene` and the same atlas on every
// platform. For each case below, this pins the emitted glyphs' rects (the
// screen quad and the atlas slot, both whole pixels), the run's advance, the
// atlas's dirty rect and an FNV-1a 64 checksum of the whole atlas's coverage —
// all RECORDED on macOS (arm64) by running `METALUI_PORTABLE_RECORD=1 swift
// test` here and pasting the printed table into `Expected.swift`.
//
// The recorder validates every row before printing it (record §26's hazard: a
// table pasted from a run that measured nothing pins nothing): each case must
// emit at least one glyph, ink at least one atlas byte and have a dirty rect.
//
// A failure off macOS is a real finding: the pipeline is not deterministic
// across platforms. Report the differing cases; do not re-pin from the failing
// platform. The oracle that says these numbers are *right* is the root
// package's `Tests/MetalUIPortableTextTests/ApplePathOracleTests.swift` (PT-F),
// which compares them against CoreText on macOS; this package asserts only that
// they do not move.

import Foundation
import MetalUIPortableText
import MetalUIScene
import MetalUIShaderTypes
import Testing

// MARK: - The corpus

let notoSans = "NotoSans-Regular.ttf"
let sourceSans = "SourceSans3-Regular.otf"
let notoSansArabic = "NotoSansArabic-Regular.ttf"

struct EmitCase: Hashable, CustomStringConvertible {
    let font: String
    let text: String
    let size: Double
    let scale: Float
    let originX: Double
    let originY: Double
    var description: String { "\(font) \(size)pt ×\(scale) at (\(originX), \(originY)) \"\(text)\"" }
}

/// Both Latin outline formats (glyf and CFF), both scales, whole and
/// fractional origins (so more than one subpixel variant is drawn), a ligature
/// and kerning string, and one Arabic run — right to left, with the shaper's
/// y offsets on its marks, which the Latin cases never exercise.
let corpus: [EmitCase] = [
    EmitCase(font: notoSans, text: "Hamburg", size: 13, scale: 1, originX: 10, originY: 20),
    EmitCase(font: notoSans, text: "The quick brown fox jumps over the lazy dog.",
             size: 17, scale: 2, originX: 10.37, originY: 30),
    EmitCase(font: sourceSans, text: "Affix the fluffy waffle: AV To Ty", size: 26, scale: 1,
             originX: 3.5, originY: 40),
    EmitCase(font: sourceSans, text: "in a box", size: 11, scale: 2, originX: 7.125, originY: 18),
    EmitCase(font: notoSansArabic, text: "مَرْحَبًا بالعالم", size: 19, scale: 2,
             originX: 5.25, originY: 30),
]

let atlasSide = 512

// MARK: - What is pinned

struct PinnedEmit: Equatable, CustomStringConvertible {
    let glyphs: Int
    /// FNV-1a 64 over, per emitted glyph in scene order: the quad's x, y, w, h
    /// then the atlas slot's x, y, w, h, each a little-endian Int32.
    let rects: UInt64
    /// `emit`'s return value, as the bit pattern of the Double.
    let advance: UInt64
    let dirty: [Int]
    /// FNV-1a 64 over the whole atlas's coverage bytes.
    let coverage: UInt64

    var description: String {
        "\(glyphs) glyphs, rects \(hex(rects)), advance \(hex(advance)), dirty \(dirty), coverage \(hex(coverage))"
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
    // .../Tests/PortableTests/Tests/PortableTextDeterminismTests/<this file>
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // PortableTextDeterminismTests
        .deletingLastPathComponent()   // Tests (of this package)
        .deletingLastPathComponent()   // PortableTests
        .deletingLastPathComponent()   // Tests (of the root package)
        .appendingPathComponent("Fonts").appendingPathComponent(file)
    return [UInt8](try Data(contentsOf: url))
}

struct NotAWholePixel: Error, CustomStringConvertible {
    let emitCase: EmitCase
    let value: Float
    var description: String { "\(emitCase): \(value) is not a whole pixel" }
}

/// Emits one case into a fresh scene and atlas.
func emit(_ emitCase: EmitCase) throws -> (scene: Scene, atlas: GlyphAtlas, advance: Double) {
    let font = try PortableFont(data: fontBytes(emitCase.font), size: emitCase.size)
    let atlas = GlyphAtlas(width: atlasSide, height: atlasSide)
    var scene = Scene()
    let mask = MUIBounds(origin: MUIPoint(x: 0, y: 0), size: MUISize(width: 4096, height: 4096))
    atlas.beginFrame()
    defer { atlas.endFrame() }
    let advance = try PortableText.emit(emitCase.text, font: font,
                                        origin: (emitCase.originX, emitCase.originY),
                                        scaleFactor: emitCase.scale,
                                        color: MUIHsla(h: 0, s: 0, l: 1, a: 1),
                                        contentMask: mask, into: &scene, atlas: atlas)
    return (scene, atlas, advance)
}

func pin(_ emitCase: EmitCase) throws -> PinnedEmit {
    let (scene, atlas, advance) = try emit(emitCase)
    var bytes: [UInt8] = []
    for glyph in scene.glyphs {
        for value in [glyph.bounds.origin.x, glyph.bounds.origin.y,
                      glyph.bounds.size.width, glyph.bounds.size.height,
                      glyph.atlasBounds.origin.x, glyph.atlasBounds.origin.y,
                      glyph.atlasBounds.size.width, glyph.atlasBounds.size.height] {
            guard let exact = Int32(exactly: value) else { throw NotAWholePixel(emitCase: emitCase, value: value) }
            appendLittleEndian(exact, to: &bytes)
        }
    }
    let dirty = atlas.dirtyRect.map { [$0.x, $0.y, $0.width, $0.height] } ?? []
    return PinnedEmit(glyphs: scene.glyphs.count, rects: fnv1a64(bytes),
                      advance: advance.bitPattern, dirty: dirty, coverage: fnv1a64(atlas.pixels))
}

// MARK: - Line breaking (LB-G)

/// Break opportunities over scripts libunibreak classifies differently —
/// Latin, CJK ideographs (break anywhere), Thai (SA, no dictionary here),
/// Arabic, emoji with a ZWJ sequence, and the hard-break characters.
let breakCorpus = "Hello, world! 日本語のテキスト。 สวัสดีครับ مرحبا بالعالم 👩\u{200D}💻 ok\r\nx\u{2028}y\tz\u{A0}w (a) \"q\" 1,234.5"

struct WrapCase: CustomStringConvertible {
    let font: String, text: String, size: Double, width: Double?
    var description: String { "\(font) \(size)pt w=\(width.map { "\($0)" } ?? "nil") \"\(text)\"" }
}

let wrapCorpus: [WrapCase] = [
    WrapCase(font: notoSans, text: "The quick brown fox jumps over the lazy dog.", size: 13, width: 60),
    WrapCase(font: notoSans, text: "Affix the fluffy waffle: AV To Ty LT jig!", size: 11, width: 7.25),
    WrapCase(font: sourceSans, text: "tab\tseparated\tcolumns and Supercalifragilistic words", size: 17, width: 90),
    WrapCase(font: sourceSans, text: "Ready\nSet\r\nGo\u{2028}now", size: 26, width: nil),
]

/// FNV-1a 64 over each line's range bounds (Int32 LE) and its advance's bit
/// pattern (UInt64 LE), in order, plus the line count.
struct PinnedWrap: Equatable, CustomStringConvertible {
    let lines: Int
    let checksum: UInt64
    var description: String { "\(lines) lines, fnv \(hex(checksum))" }
}

func pinWrap(_ wrapCase: WrapCase) throws -> PinnedWrap {
    let font = try PortableFont(data: fontBytes(wrapCase.font), size: wrapCase.size)
    let lines = try PortableText.lines(wrapCase.text, font: font, wrappingAt: wrapCase.width)
    var bytes: [UInt8] = []
    for line in lines {
        appendLittleEndian(Int32(line.range.lowerBound), to: &bytes)
        appendLittleEndian(Int32(line.range.upperBound), to: &bytes)
        let bits = line.advance.bitPattern
        for shift in stride(from: 0, through: 56, by: 8) { bytes.append(UInt8(truncatingIfNeeded: bits >> UInt64(shift))) }
    }
    return PinnedWrap(lines: lines.count, checksum: fnv1a64(bytes))
}

/// The opportunities as one byte each (0 mandatory, 1 allowed, 2 none).
func breakBytes() -> [UInt8] {
    PortableText.lineBreaks(in: breakCorpus).map { opportunity in
        switch opportunity {
        case .mandatory: return 0
        case .allowed: return 1
        case .none: return 2
        }
    }
}

@Suite struct LineBreakingDeterminismTests {
    @Test func breakOpportunitiesMatchTheValuesRecordedOnMacOS() {
        let bytes = breakBytes()
        #expect(bytes.count == expectedBreakCount)
        #expect(fnv1a64(bytes) == expectedBreakChecksum,
                "measured \(hex(fnv1a64(bytes))), recorded on macOS \(hex(expectedBreakChecksum))")
    }

    @Test func wrappedLinesMatchTheValuesRecordedOnMacOS() throws {
        try #require(expectedWraps.count == wrapCorpus.count)
        for (index, wrapCase) in wrapCorpus.enumerated() {
            let got = try pinWrap(wrapCase)
            #expect(got == expectedWraps[index], "\(wrapCase): measured \(got), recorded on macOS \(expectedWraps[index])")
        }
    }

    /// Not degenerate: every kind of opportunity occurs, and every case
    /// wraps to more than one line.
    @Test func theCorpusIsNotDegenerate() throws {
        let bytes = Set(breakBytes())
        #expect(bytes == [0, 1, 2])
        for wrapCase in wrapCorpus { #expect(try pinWrap(wrapCase).lines > 1, "\(wrapCase)") }
    }

    @Test(.enabled(if: recording, "set METALUI_PORTABLE_RECORD=1 to print the expected values"))
    func record() throws {
        let bytes = breakBytes()
        try #require(Set(bytes) == [0, 1, 2], "the break corpus measured nothing")
        var lines = ["let expectedBreakCount = \(bytes.count)",
                     "let expectedBreakChecksum: UInt64 = \(hex(fnv1a64(bytes)))",
                     "let expectedWraps: [PinnedWrap] = ["]
        for wrapCase in wrapCorpus {
            let pinned = try pinWrap(wrapCase)
            try #require(pinned.lines > 1, "\(wrapCase) did not wrap")
            lines.append("    PinnedWrap(lines: \(pinned.lines), checksum: \(hex(pinned.checksum))),  // \(wrapCase)")
        }
        lines.append("]")
        print(lines.joined(separator: "\n"))
    }
}

// MARK: - Line metrics and multi-line emission (LB-K)

/// Each face's metrics at 13 pt: ascent, descent, leading and lineHeight bit
/// patterns (UInt64 LE), face by face — FNV-1a 64 over all of them.
let metricFaces = [notoSans, sourceSans, "NotoSansArabic-Regular.ttf"]

func metricBytes() throws -> [UInt8] {
    var bytes: [UInt8] = []
    for face in metricFaces {
        let metrics = try PortableFont(data: fontBytes(face), size: 13).metrics
        for value in [metrics.ascent, metrics.descent, metrics.leading, metrics.lineHeight] {
            let bits = value.bitPattern
            for shift in stride(from: 0, through: 56, by: 8) { bytes.append(UInt8(truncatingIfNeeded: bits >> UInt64(shift))) }
        }
    }
    return bytes
}

struct ParagraphCase: CustomStringConvertible {
    let font: String, text: String, size: Double, width: Double, scale: Float
    var description: String { "\(font) \(size)pt ×\(scale) w=\(width) \"\(text)\"" }
}

/// Wrapped paragraphs through `emitLines`, each reaching a rule of LB-H/LB-I:
/// several lines with kerning across a break, a control character and a soft
/// hyphen (substituted and dropped), tabs.
let paragraphCorpus: [ParagraphCase] = [
    ParagraphCase(font: notoSans, text: "The quick brown fox jumps over the lazy dog. AV To Ty\nsoft\u{AD}hyphen\u{AD}ated", size: 13, width: 120, scale: 2),
    ParagraphCase(font: sourceSans, text: "tab\tseparated\tcolumns wrap\u{2028}here and there", size: 17, width: 90, scale: 1),
]

/// A paragraph pinned like an `emit` case: rects, `height` in the advance
/// slot, the atlas's dirty rect and coverage.
func pinParagraph(_ paragraphCase: ParagraphCase) throws -> (pinned: PinnedEmit, lines: Int) {
    let font = try PortableFont(data: fontBytes(paragraphCase.font), size: paragraphCase.size)
    let atlas = GlyphAtlas(width: atlasSide, height: atlasSide)
    var scene = Scene()
    let mask = MUIBounds(origin: MUIPoint(x: 0, y: 0), size: MUISize(width: 4096, height: 4096))
    atlas.beginFrame()
    let paragraph = try PortableText.emitLines(paragraphCase.text, font: font, origin: (3.3, 7.6),
                                               wrappingAt: paragraphCase.width,
                                               scaleFactor: paragraphCase.scale,
                                               color: MUIHsla(h: 0, s: 0, l: 1, a: 1),
                                               contentMask: mask, into: &scene, atlas: atlas)
    atlas.endFrame()
    var bytes: [UInt8] = []
    for glyph in scene.glyphs {
        for value in [glyph.bounds.origin.x, glyph.bounds.origin.y,
                      glyph.bounds.size.width, glyph.bounds.size.height,
                      glyph.atlasBounds.origin.x, glyph.atlasBounds.origin.y,
                      glyph.atlasBounds.size.width, glyph.atlasBounds.size.height] {
            appendLittleEndian(Int32(value), to: &bytes)
        }
    }
    let dirty = atlas.dirtyRect.map { [$0.x, $0.y, $0.width, $0.height] } ?? []
    return (PinnedEmit(glyphs: scene.glyphs.count, rects: fnv1a64(bytes),
                       advance: paragraph.height.bitPattern, dirty: dirty,
                       coverage: fnv1a64(atlas.pixels)), paragraph.lines.count)
}

@Suite struct LineEmissionDeterminismTests {
    @Test func lineMetricsMatchTheValuesRecordedOnMacOS() throws {
        let checksum = fnv1a64(try metricBytes())
        #expect(checksum == expectedMetricsChecksum,
                "measured \(hex(checksum)), recorded on macOS \(hex(expectedMetricsChecksum))")
    }

    @Test func wrappedParagraphsMatchTheValuesRecordedOnMacOS() throws {
        try #require(expectedParagraphs.count == paragraphCorpus.count)
        for (index, paragraphCase) in paragraphCorpus.enumerated() {
            let got = try pinParagraph(paragraphCase).pinned
            #expect(got == expectedParagraphs[index],
                    "\(paragraphCase): measured \(got), recorded on macOS \(expectedParagraphs[index])")
        }
    }

    /// Not degenerate: every paragraph wraps and inks.
    @Test func theCorpusIsNotDegenerate() throws {
        for paragraphCase in paragraphCorpus {
            let (pinned, lines) = try pinParagraph(paragraphCase)
            #expect(lines > 2 && pinned.glyphs > 20 && pinned.dirty.count == 4, "\(paragraphCase)")
        }
    }

    @Test(.enabled(if: recording, "set METALUI_PORTABLE_RECORD=1 to print the expected values"))
    func record() throws {
        var lines = ["let expectedMetricsChecksum: UInt64 = \(hex(fnv1a64(try metricBytes())))",
                     "let expectedParagraphs: [PinnedEmit] = ["]
        for paragraphCase in paragraphCorpus {
            let (pinned, count) = try pinParagraph(paragraphCase)
            try #require(count > 2 && pinned.glyphs > 20 && pinned.dirty.count == 4, "\(paragraphCase) measured nothing")
            lines.append("    PinnedEmit(glyphs: \(pinned.glyphs), rects: \(hex(pinned.rects)), advance: \(hex(pinned.advance)), "
                         + "dirty: \(pinned.dirty), coverage: \(hex(pinned.coverage))),  // \(paragraphCase)")
        }
        lines.append("]")
        print(lines.joined(separator: "\n"))
    }
}

// MARK: - Min- and max-content (roadmap item 3)

/// Strings whose runs and content widths are pinned: the break corpus (so
/// the `"en-strict"` tailoring and every script in it), curly quotes, small
/// kana.
let contentCorpus = [breakCorpus, "“Quoted,” she said, ‘and nested.’ „German“", "ぁぃぅ small kana 々 ok",
                     "a bb supercalifragilistic dd\nwell-known thing"]

/// FNV-1a 64 over each string's runs (UTF-8, NUL-terminated) and its min-
/// and max-content bit patterns in Noto Sans at 13 pt.
func contentBytes() throws -> [UInt8] {
    let font = try PortableFont(data: fontBytes(notoSans), size: 13)
    var bytes: [UInt8] = []
    for text in contentCorpus {
        for run in PortableText.unbreakableRuns(of: text) { bytes += Array(run.utf8) + [0] }
        for value in [try PortableText.minContentWidth(text, font: font), try PortableText.maxContentWidth(text, font: font)] {
            let bits = value.bitPattern
            for shift in stride(from: 0, through: 56, by: 8) { bytes.append(UInt8(truncatingIfNeeded: bits >> UInt64(shift))) }
        }
    }
    return bytes
}

@Suite struct ContentSizeDeterminismTests {
    @Test func runsAndContentWidthsMatchTheValuesRecordedOnMacOS() throws {
        let checksum = fnv1a64(try contentBytes())
        #expect(checksum == expectedContentChecksum,
                "measured \(hex(checksum)), recorded on macOS \(hex(expectedContentChecksum))")
    }

    @Test(.enabled(if: recording, "set METALUI_PORTABLE_RECORD=1 to print the expected value"))
    func record() throws {
        let font = try PortableFont(data: fontBytes(notoSans), size: 13)
        for text in contentCorpus {
            try #require(PortableText.unbreakableRuns(of: text).count > 2, "\(text) measured nothing")
            try #require(try PortableText.minContentWidth(text, font: font) > 0)
        }
        print("let expectedContentChecksum: UInt64 = \(hex(fnv1a64(try contentBytes())))")
    }
}

// MARK: - Font resolution (roadmap item 4)

/// Each query and the face it resolves to on macOS, where the root package's
/// `FontResolverOracleTests` checks the same answers against CoreText. Pinned
/// here as literals: name decoding and case folding must not move off macOS.
let expectedResolutions: [(query: String?, face: String)] = [
    (nil, "NotoSans-Regular"), ("Noto Sans", "NotoSans-Regular"), ("NOTO SANS", "NotoSans-Regular"),
    ("notosans-regular", "NotoSans-Regular"), ("Noto Sans Regular", "NotoSans-Regular"),
    ("noto sans arabic regular", "NotoSansArabic-Regular"), ("NotoSansArabic-Regular", "NotoSansArabic-Regular"),
    ("source sans 3", "SourceSans3-Regular"), ("SOURCESANS3-REGULAR", "SourceSans3-Regular"),
    ("Source Sans 3 Regular", "NotoSans-Regular"), (" Noto Sans", "NotoSans-Regular"), ("Nöto Sans", "NotoSans-Regular"),
    ("Source Sans", "NotoSans-Regular"), ("", "NotoSans-Regular"),
]

@Suite struct FontResolverDeterminismTests {
    @Test func queriesResolveToTheFacesRecordedOnMacOS() throws {
        let resolver = try PortableFontResolver(defaultFont: fontBytes(notoSans))
        try resolver.register(fontBytes(sourceSans))
        try resolver.register(fontBytes("NotoSansArabic-Regular.ttf"))
        for (query, face) in expectedResolutions {
            #expect(try resolver.resolve(family: query, size: 13).key.postScriptName == face, "\(String(describing: query))")
        }
    }

    /// Distinguishes a query that matched Source Sans 3 from one that fell back.
    @Test func aSubstitutionIsTheDefaultFace() throws {
        let resolver = try PortableFontResolver(defaultFont: fontBytes(sourceSans))
        try resolver.register(fontBytes(notoSans))
        #expect(try resolver.resolve(family: "Noto  Sans", size: 13).key.postScriptName == "SourceSans3-Regular")
        #expect(try resolver.resolve(family: "noto sans regular", size: 13).key.postScriptName == "NotoSans-Regular")
    }
}

// MARK: - Bidi (roadmap item 12)

/// Mixed-direction paragraphs through `emitLines` with Noto Sans and a Noto
/// Sans Arabic fallback, pinned like a paragraph (rects, height, atlas).
let bidiCorpus = ["مرحبا Hello بالعالم (peace)", "left, then عربي, then 123 and ١٢٣.\nسطر ثاني with English"]

func pinBidi(_ text: String) throws -> PinnedEmit {
    let resolver = try PortableFontResolver(defaultFont: fontBytes(notoSans))
    try resolver.register(fontBytes("NotoSansArabic-Regular.ttf"))
    let font = try resolver.resolve(family: nil, size: 15)
    let atlas = GlyphAtlas(width: atlasSide, height: atlasSide)
    var scene = Scene()
    let mask = MUIBounds(origin: MUIPoint(x: 0, y: 0), size: MUISize(width: 4096, height: 4096))
    atlas.beginFrame()
    let paragraph = try PortableText.emitLines(text, font: font, origin: (3.3, 7.6), wrappingAt: 90, scaleFactor: 2,
                                               color: MUIHsla(h: 0, s: 0, l: 1, a: 1), contentMask: mask,
                                               into: &scene, atlas: atlas)
    atlas.endFrame()
    var bytes: [UInt8] = []
    for glyph in scene.glyphs {
        for value in [glyph.bounds.origin.x, glyph.bounds.origin.y, glyph.bounds.size.width, glyph.bounds.size.height,
                      glyph.atlasBounds.origin.x, glyph.atlasBounds.origin.y,
                      glyph.atlasBounds.size.width, glyph.atlasBounds.size.height] {
            appendLittleEndian(Int32(value), to: &bytes)
        }
    }
    let dirty = atlas.dirtyRect.map { [$0.x, $0.y, $0.width, $0.height] } ?? []
    return PinnedEmit(glyphs: scene.glyphs.count, rects: fnv1a64(bytes), advance: paragraph.height.bitPattern,
                      dirty: dirty, coverage: fnv1a64(atlas.pixels))
}

@Suite struct BidiDeterminismTests {
    @Test func bidiParagraphsMatchTheValuesRecordedOnMacOS() throws {
        try #require(expectedBidi.count == bidiCorpus.count)
        for (text, expected) in zip(bidiCorpus, expectedBidi) {
            let got = try pinBidi(text)
            #expect(got == expected, "\(text): measured \(got), recorded on macOS \(expected)")
        }
    }

    @Test(.enabled(if: recording, "set METALUI_PORTABLE_RECORD=1 to print the expected values"))
    func record() throws {
        var lines = ["let expectedBidi: [PinnedEmit] = ["]
        for text in bidiCorpus {
            let pinned = try pinBidi(text)
            try #require(pinned.glyphs > 20)
            lines.append("    PinnedEmit(glyphs: \(pinned.glyphs), rects: \(hex(pinned.rects)), advance: \(hex(pinned.advance)), dirty: \(pinned.dirty), coverage: \(hex(pinned.coverage))),")
        }
        lines.append("]")
        print(lines.joined(separator: "\n"))
    }
}

let recording = ProcessInfo.processInfo.environment["METALUI_PORTABLE_RECORD"] == "1"

// MARK: - Tests

@Suite struct PortableTextDeterminismTests {
    @Test func theChecksumIsFNV1a64() {
        #expect(fnv1a64([]) == 0xcbf2_9ce4_8422_2325)
        #expect(fnv1a64([0x61]) == 0xaf63_dc4c_8601_ec8c)
    }

    @Test func everyCaseMatchesTheValuesRecordedOnMacOS() throws {
        try #require(corpus.count == 5)
        try #require(expectedEmits.count == corpus.count,
                     "expected table has \(expectedEmits.count) rows for \(corpus.count) cases")
        var mismatches = 0
        for (index, emitCase) in corpus.enumerated() {
            let got = try pin(emitCase)
            if got != expectedEmits[index] {
                mismatches += 1
                Issue.record("\(emitCase): measured \(got), recorded on macOS \(expectedEmits[index])")
            }
        }
        #expect(mismatches == 0, "\(mismatches) of \(corpus.count) cases differ from macOS")
    }

    /// Guards the pins against a pipeline that emits nothing or inks nothing,
    /// and against two cases that pin the same numbers for the wrong reason: a
    /// case with a space packs the space and emits no quad for it, every case
    /// inks its atlas, and no two cases share a rect or coverage checksum.
    @Test func theCorpusIsNotDegenerate() throws {
        var rectSums = Set<UInt64>(), coverageSums = Set<UInt64>()
        for emitCase in corpus {
            let (scene, atlas, advance) = try emit(emitCase)
            #expect(!scene.glyphs.isEmpty, "\(emitCase)")
            #expect(advance > 0, "\(emitCase)")
            #expect(atlas.pixels.contains { $0 != 0 }, "\(emitCase) inked nothing")
            #expect(atlas.dirtyRect != nil, "\(emitCase)")
            let spaces = emitCase.text.unicodeScalars.filter { $0 == " " }.count
            let visible = emitCase.text.unicodeScalars.count - spaces
            // In Latin, ligatures and precomposed marks make no more glyphs than
            // scalars, and a space makes none. Not in Arabic: this run shapes 16
            // visible scalars to 18 glyphs (measured), as SH-I's harakat row does.
            if emitCase.font != notoSansArabic {
                #expect(scene.glyphs.count <= visible, "\(emitCase)")
            }
            let pinned = try pin(emitCase)
            rectSums.insert(pinned.rects)
            coverageSums.insert(pinned.coverage)
        }
        #expect(rectSums.count == corpus.count)
        #expect(coverageSums.count == corpus.count)
    }

    @Test(.enabled(if: recording, "set METALUI_PORTABLE_RECORD=1 to print the expected table"))
    func record() throws {
        var lines = ["let expectedEmits: [PinnedEmit] = ["]
        for emitCase in corpus {
            let pinned = try pin(emitCase)
            // Validate before printing: a row that measured nothing pins nothing.
            try #require(pinned.glyphs > 0, "\(emitCase) emitted no glyphs")
            try #require(pinned.dirty.count == 4, "\(emitCase) has no dirty rect")
            try #require(pinned.coverage != fnv1a64([UInt8](repeating: 0, count: atlasSide * atlasSide)),
                         "\(emitCase) inked nothing")
            lines.append("    PinnedEmit(glyphs: \(pinned.glyphs), rects: \(hex(pinned.rects)), "
                         + "advance: \(hex(pinned.advance)), dirty: \(pinned.dirty), "
                         + "coverage: \(hex(pinned.coverage))),  // \(emitCase)")
        }
        lines.append("]")
        print(lines.joined(separator: "\n"))
    }
}
