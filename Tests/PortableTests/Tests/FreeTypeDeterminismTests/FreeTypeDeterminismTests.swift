// FT-J: FreeType's rasterizer is integer arithmetic, and `FreeTypeRaster`'s
// box arithmetic is IEEE Double, so a glyph's image should be byte-identical
// on every platform. These tests pin, per case, the glyph id, the image's
// width, height, left and top, and an FNV-1a 64-bit checksum of its coverage
// bytes — all RECORDED on macOS (arm64) by running
// `METALUI_PORTABLE_RECORD=1 swift test` here and pasting the printed table.
//
// A failure off macOS is a real finding: FreeType (or our arithmetic around
// it) is not deterministic across platforms. Report the differing cases; do
// not re-pin from the failing platform.
//
// Fonts are the root package's `Tests/Fonts/` (FT-G), read by path from
// `#filePath` — no resources, no CoreText.

import Foundation
import MetalUIFreeType
import MetalUIScene
import Testing

struct PortableCase: Hashable, CustomStringConvertible {
    let font: String
    let character: Unicode.Scalar
    let size: Double
    let variant: Int
    let scale: Float

    var description: String {
        "\(font) '\(character)' \(Int(size))pt v\(variant) @\(Int(scale))x"
    }
}

struct Pinned: Equatable, CustomStringConvertible {
    let glyph: UInt16
    let width: Int
    let height: Int
    let left: Int
    let top: Int
    let checksum: UInt64

    var description: String {
        "glyph \(glyph) \(width)x\(height) left \(left) top \(top) fnv \(hex(checksum))"
    }
}

let fontFiles = ["NotoSans-Regular.ttf", "SourceSans3-Regular.otf"]
let characters: [Unicode.Scalar] = ["o", "g", "W", "j", ".", " "]
let sizes: [Double] = [13, 26]
let variants = [0, 3]
let scales: [Float] = [1, 2]

/// Every case, in a fixed order: font, character, size, variant, scale.
let grid: [PortableCase] = fontFiles.flatMap { font in
    characters.flatMap { character in
        sizes.flatMap { size in
            variants.flatMap { variant in
                scales.map { PortableCase(font: font, character: character, size: size, variant: variant, scale: $0) }
            }
        }
    }
}

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

func fontBytes(_ file: String) throws -> [UInt8] {
    // .../Tests/PortableTests/Tests/FreeTypeDeterminismTests/<this file>
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // FreeTypeDeterminismTests
        .deletingLastPathComponent()   // Tests (of this package)
        .deletingLastPathComponent()   // PortableTests
        .deletingLastPathComponent()   // Tests (of the root package)
        .appendingPathComponent("Fonts").appendingPathComponent(file)
    return [UInt8](try Data(contentsOf: url))
}

/// Rasterizes every case in `grid`, opening each font once per size.
func measure() throws -> [PortableCase: Pinned] {
    var results: [PortableCase: Pinned] = [:]
    for file in fontFiles {
        let data = try fontBytes(file)
        for size in sizes {
            let font = try FreeTypeFont(data: data, size: size)
            for testCase in grid where testCase.font == file && testCase.size == size {
                let glyph = font.glyph(for: testCase.character)
                let image = try FreeTypeRaster.rasterize(glyph: glyph, font: font,
                                                         subpixelVariant: testCase.variant,
                                                         scaleFactor: testCase.scale)
                results[testCase] = Pinned(glyph: glyph, width: image.width, height: image.height,
                                           left: image.left, top: image.top, checksum: fnv1a64(image.bytes))
            }
        }
    }
    return results
}

let recording = ProcessInfo.processInfo.environment["METALUI_PORTABLE_RECORD"] == "1"

@Suite struct FreeTypeDeterminismTests {
    @Test func theChecksumIsFNV1a64() {
        // Published FNV-1a 64 test vectors: "" and "a".
        #expect(fnv1a64([]) == 0xcbf2_9ce4_8422_2325)
        #expect(fnv1a64([0x61]) == 0xaf63_dc4c_8601_ec8c)
    }

    @Test func everyCaseMatchesTheValuesRecordedOnMacOS() throws {
        let measured = try measure()
        try #require(grid.count == 96)
        try #require(expected.count == grid.count, "expected table has \(expected.count) rows for \(grid.count) cases")
        var mismatches = 0
        for (index, testCase) in grid.enumerated() {
            let got = try #require(measured[testCase])
            if got != expected[index] {
                mismatches += 1
                Issue.record("\(testCase): measured \(got), recorded on macOS \(expected[index])")
            }
        }
        #expect(mismatches == 0, "\(mismatches) of \(grid.count) cases differ from macOS")
    }

    @Test func theFontKeyIsReadOffTheFaceAtTheRequestedSize() throws {
        // FT-F off macOS, where the CoreText equality test cannot run: the key
        // carries the face's PostScript name and the size in POINTS as
        // requested (never scaled), with no variations and the identity matrix.
        let names = ["NotoSans-Regular.ttf": "NotoSans-Regular",
                     "SourceSans3-Regular.otf": "SourceSans3-Regular"]
        for file in fontFiles {
            for size in [13.0, 26.0] {
                let key = try FreeTypeFont(data: fontBytes(file), size: size).key
                #expect(key.postScriptName == names[file], "\(file)")
                #expect(key.size == size, "\(file) at \(size)")
                #expect(key.variations.isEmpty, "\(file)")
                #expect(key.matrix.a == 1 && key.matrix.b == 0 && key.matrix.c == 0
                        && key.matrix.d == 1 && key.matrix.tx == 0 && key.matrix.ty == 0, "\(file)")
            }
        }
    }

    @Test func theGridIsNotDegenerate() throws {
        // Guards the pins against a rasterizer that returns nothing: the space
        // is empty, every other glyph has ink, and no two inked cases in one
        // font share a checksum only because both are blank.
        let measured = try measure()
        for testCase in grid {
            let pinned = try #require(measured[testCase])
            if testCase.character == " " {
                #expect(pinned.width == 0 || pinned.height == 0, "\(testCase)")
            } else {
                #expect(pinned.width > 0 && pinned.height > 0 && pinned.glyph != 0, "\(testCase)")
            }
        }
    }

    @Test(.enabled(if: recording, "set METALUI_PORTABLE_RECORD=1 to print the expected table"))
    func record() throws {
        let measured = try measure()
        var lines = ["let expected: [Pinned] = ["]
        for testCase in grid {
            let p = try #require(measured[testCase])
            lines.append("    Pinned(glyph: \(p.glyph), width: \(p.width), height: \(p.height), left: \(p.left), top: \(p.top), checksum: \(hex(p.checksum))),  // \(testCase)")
        }
        lines.append("]")
        print(lines.joined(separator: "\n"))
    }
}
