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
