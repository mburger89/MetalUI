import CoreText
import Foundation
import Testing
import MetalUIFreeType
import MetalUIScene
@testable import MetalUIText

// CoreText is the oracle for the FreeType rasterizer on macOS (ruling FT-H).
//
// The same font file is loaded into both rasterizers: CoreText through
// `CTFontManagerCreateFontDescriptorsFromData`, FreeType through
// `FreeTypeFont(data:size:)`. Glyph ids come from CoreText's cmap lookup and
// FreeType must give the same id. The fonts are `Tests/Fonts/` (FT-G), read by
// path from `#filePath`, not as resources.
//
// What is asserted, and why each bound is what it is:
//
// - `width`, `height`, `left`, `top` are EQUAL for every case (FT-D). No
//   tolerance. Before FreeTypeRaster computed its box from the design-unit
//   outline, 26 of 832 cases disagreed by one pixel (FreeType's 26.6 scaled
//   outline puts Noto Sans "o" at 11 pt at y = 6.0 px, CoreText at 6.006 px).
// - Coverage against the OUTLINE (CoreGraphics filling
//   `CTFontCreatePathForGlyph`'s path into the same bitmap) is within
//   `outlineMaxTolerance`/`outlineMeanTolerance`, for every case.
// - Coverage against `GlyphRaster` (`CTFontDrawGlyphs`, the production
//   contract) is within `glyphRasterMaxTolerance`/`glyphRasterMeanTolerance`,
//   for every case except the `glyphRasterAdjustedSizes` below: at those sizes
//   `CTFontDrawGlyphs` does not draw the outline it reports — it moves ink up
//   by as much as 0.32–0.44 px per size and changes its total by -6% to +13%
//   — while CoreGraphics filling the same path does not.
//   That is a measured, pinned known difference, not a tolerance: the pin
//   (`glyphRasterAdjustsTheseSizesAwayFromTheOutline`) reddens if CoreText
//   stops doing it, so the list cannot go stale silently.
// - `FontKey` from FreeType == `FontKey(resolved:)` from CoreText (FT-F).
//
// Re-measure with `METALUI_FREETYPE_MEASURE=1 swift test --filter
// FreeTypeOracleTests.measure` before changing any constant here.

// MARK: - Tolerances (measured 2026-09-22, macOS 27.0, FreeType 2.14.3)

/// Largest per-pixel |FreeType - CGPath fill|. Measured maxima over all 384
/// inked cases per font: Noto Sans 24, Source Sans 3 38. Margin +12 (about 5%
/// of full coverage).
let outlineMaxTolerance = 50
/// Largest per-case mean |FreeType - CGPath fill| over the bitmap. Measured
/// maxima: Noto Sans 1.303, Source Sans 3 4.278. Margin +1.7.
let outlineMeanTolerance = 6.0
/// Largest per-pixel |FreeType - GlyphRaster| outside the adjusted sizes.
/// Measured maxima: Noto Sans 67, Source Sans 3 59. Margin +13.
let glyphRasterMaxTolerance = 80
/// Largest per-case mean |FreeType - GlyphRaster| outside the adjusted sizes.
/// Measured maxima: Noto Sans 7.024, Source Sans 3 5.388. Margin +2. The
/// adjusted sizes' worst per-case means are 15.708 to 18.576, so this bound
/// also separates them (the pin below relies on it).
let glyphRasterMeanTolerance = 9.0

/// (file, point size, scale) at which `CTFontDrawGlyphs` departs from the
/// glyph's outline. Measured there: worst per-case mean |FreeType -
/// GlyphRaster| 15.7-18.6 and per-pixel up to 220, CoreText's ink centroid up
/// to +0.44 px above FreeType's and its ink total up to 13% larger, while
/// FreeType against the filled outline stays within 25 per pixel. At every
/// other size in `sizes` x `scales` it does not. The glyph set has no case
/// that separates point size from device ppem as the trigger (13 pt x2 and
/// 26 pt x1 measure identically, and neither is adjusted), so none is claimed.
let glyphRasterAdjustedSizes: Set<SizeKey> = [
    SizeKey(file: notoSans, size: 17, scale: 1),
    SizeKey(file: sourceSans, size: 11, scale: 1),
    SizeKey(file: sourceSans, size: 13, scale: 1),
    SizeKey(file: sourceSans, size: 17, scale: 1),
]

// MARK: - The glyph set

let notoSans = "NotoSans-Regular.ttf"       // TrueType outlines (glyf)
let sourceSans = "SourceSans3-Regular.otf"  // CFF outlines ('CFF ')
let fontFiles = [notoSans, sourceSans]

/// Overshoot (o, O), ascender and descenders (b, g, p, y), a dot, an x-height
/// letter, wide glyphs (W, M), negative left bearing (j, f), and a space.
let characters: [Character] = ["o", "O", "b", "g", "p", "y", ".", "x", "W", "M", "j", "f", " "]
let sizes: [Double] = [11, 13, 17, 26]
let scales: [Float] = [1, 2]

struct SizeKey: Hashable, CustomStringConvertible {
    let file: String
    let size: Double
    let scale: Float
    var description: String { "\(file) \(size)pt x\(scale)" }
}

// MARK: - Loading

struct OracleFont {
    let file: String
    let data: [UInt8]
    let descriptor: CTFontDescriptor

    init(_ file: String) throws {
        self.file = file
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fonts").appendingPathComponent(file)
        let bytes = try Data(contentsOf: url)
        data = [UInt8](bytes)
        let descriptors = CTFontManagerCreateFontDescriptorsFromData(bytes as CFData) as? [CTFontDescriptor] ?? []
        descriptor = try #require(descriptors.first, "CoreText rejected \(file)")
    }

    func ctFont(size: Double) -> CTFont { CTFontCreateWithFontDescriptor(descriptor, CGFloat(size), nil) }
}

/// CoreText's glyph for a character, which must also be FreeType's.
func ctGlyph(_ font: CTFont, _ character: Character) throws -> CGGlyph {
    var units = Array(String(character).utf16)
    var glyphs = [CGGlyph](repeating: 0, count: units.count)
    try #require(CTFontGetGlyphsForCharacters(font, &units, &glyphs, units.count), "no glyph for \(character)")
    return glyphs[0]
}

// MARK: - Comparison

/// One rasterized case from both rasterizers, plus the outline fill.
struct OracleCase {
    let key: SizeKey
    let character: Character
    let variant: Int
    let coreText: GlyphImage
    let freeType: GlyphImage
    /// CoreGraphics filling the glyph's path into `coreText`'s rectangle.
    let outline: [UInt8]

    var label: String { "\(key) '\(character)' variant \(variant)" }
}

/// Per-pixel |a - b| over two bitmaps of the same rectangle.
struct CoverageDiff {
    let max: Int
    let mean: Double
    init(_ a: [UInt8], _ b: [UInt8]) {
        precondition(a.count == b.count)
        var largest = 0, sum = 0
        for i in a.indices {
            let d = abs(Int(a[i]) - Int(b[i]))
            largest = Swift.max(largest, d); sum += d
        }
        max = largest
        mean = a.isEmpty ? 0 : Double(sum) / Double(a.count)
    }
}

/// Vertical ink centroid, in device pixels up from the bitmap's bottom edge.
func inkCentroidY(_ image: GlyphImage) -> Double {
    var weighted = 0.0, total = 0.0
    for row in 0..<image.height {
        for column in 0..<image.width {
            let c = Double(image.bytes[row * image.width + column])
            weighted += c * (Double(image.height - row) - 0.5); total += c
        }
    }
    return weighted / total
}

func outlineFill(_ font: CTFont, _ glyph: CGGlyph, into image: GlyphImage,
                 variant: Int, scale: Float) -> [UInt8] {
    guard !image.isEmpty, let path = CTFontCreatePathForGlyph(font, glyph, nil) else { return [] }
    var bytes = [UInt8](repeating: 0, count: image.width * image.height)
    bytes.withUnsafeMutableBytes { buffer in
        guard let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: image.width,
                                      space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
        context.setShouldAntialias(true)
        context.setFillColor(gray: 1, alpha: 1)
        // GlyphRaster's transform: device x = p * scale + dx - left.
        let dx = Double(variant) / Double(GlyphImage.subpixelVariants)
        context.translateBy(x: CGFloat(dx - Double(image.left)), y: CGFloat(image.height - image.top))
        context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        context.addPath(path)
        context.fillPath()
    }
    return bytes
}

/// Every case for one font file.
func oracleCases(_ file: String) throws -> [OracleCase] {
    let font = try OracleFont(file)
    var cases: [OracleCase] = []
    for size in sizes {
        let ct = font.ctFont(size: size)
        let resolved = ResolvedFont(ctFont: ct)
        let ft = try FreeTypeFont(data: font.data, size: size)
        for character in characters {
            let glyph = try ctGlyph(ct, character)
            for scale in scales {
                for variant in 0..<GlyphImage.subpixelVariants {
                    let a = GlyphRaster.rasterize(glyph: glyph, font: resolved, subpixelVariant: variant, scaleFactor: scale)
                    let b = try FreeTypeRaster.rasterize(glyph: glyph, font: ft, subpixelVariant: variant, scaleFactor: scale)
                    cases.append(OracleCase(key: SizeKey(file: file, size: size, scale: scale),
                                            character: character, variant: variant, coreText: a, freeType: b,
                                            outline: outlineFill(ct, glyph, into: a, variant: variant, scale: scale)))
                }
            }
        }
    }
    return cases
}

// MARK: - Tests

@Suite("FreeType against the CoreText oracle (FT-H)")
struct FreeTypeOracleTests {
    static let expectedCaseCount = sizes.count * characters.count * scales.count * GlyphImage.subpixelVariants

    @Test("each font file carries the outline format it is here to exercise", arguments: [
        (notoSans, "glyf"), (sourceSans, "CFF "),
    ])
    func outlineFormat(file: String, table: String) throws {
        let font = try OracleFont(file)
        // The array holds raw `CTFontTableTag`s, not CFNumbers: read each
        // element's pointer bits (bridging it to [Int] crashes).
        let tags = try #require(CTFontCopyAvailableTables(font.ctFont(size: 12), []))
        let tables = (0..<CFArrayGetCount(tags)).map { index in
            let tag = UInt32(truncatingIfNeeded: Int(bitPattern: CFArrayGetValueAtIndex(tags, index)))
            return String((0..<4).map { Character(Unicode.Scalar(UInt8((tag >> (24 - 8 * UInt32($0))) & 0xFF))) })
        }
        try #require(!tables.isEmpty)
        #expect(tables.contains(table))
        #expect(!tables.contains("fvar"), "static faces only (FT-F)")
    }

    @Test("FreeType's cmap gives CoreText's glyph id", arguments: fontFiles)
    func glyphIDs(file: String) throws {
        let font = try OracleFont(file)
        let ft = try FreeTypeFont(data: font.data, size: 13)
        let ct = font.ctFont(size: 13)
        for character in characters {
            let glyph = try ctGlyph(ct, character)
            #expect(glyph != 0, "'\(character)' is .notdef in \(file)")
            #expect(ft.glyph(for: character.unicodeScalars.first!) == glyph, "'\(character)' in \(file)")
        }
    }

    @Test("FontKey from FreeType equals FontKey(resolved:) for the same file and size (FT-F)",
          arguments: fontFiles, sizes)
    func fontKeys(file: String, size: Double) throws {
        let font = try OracleFont(file)
        let ft = try FreeTypeFont(data: font.data, size: size)
        let ct = font.ctFont(size: size)
        #expect(ft.key == FontKey(resolved: ct))
        #expect(ft.key == ResolvedFont(ctFont: ct).key)
    }

    @Test("width, height, left and top are equal in every case (FT-D, no tolerance)", arguments: fontFiles)
    func geometry(file: String) throws {
        let cases = try oracleCases(file)
        try #require(cases.count == Self.expectedCaseCount)
        var inked = 0
        for c in cases {
            #expect(c.freeType.width == c.coreText.width, "width: \(c.label)")
            #expect(c.freeType.height == c.coreText.height, "height: \(c.label)")
            #expect(c.freeType.left == c.coreText.left, "left: \(c.label)")
            #expect(c.freeType.top == c.coreText.top, "top: \(c.label)")
            if c.character == " " {
                #expect(c.coreText.isEmpty && c.freeType.isEmpty, "a space is empty in both: \(c.label)")
            } else {
                #expect(!c.coreText.isEmpty && !c.freeType.isEmpty, "\(c.label)")
                inked += 1
            }
        }
        #expect(inked == Self.expectedCaseCount / characters.count * (characters.count - 1))
    }

    @Test("coverage matches the glyph's outline filled by CoreGraphics, in every case", arguments: fontFiles)
    func coverageAgainstOutline(file: String) throws {
        let cases = try oracleCases(file).filter { !$0.coreText.isEmpty }
        try #require(cases.count == Self.expectedCaseCount / characters.count * (characters.count - 1))
        for c in cases {
            try #require(c.freeType.bytes.count == c.outline.count, "\(c.label)")
            let diff = CoverageDiff(c.freeType.bytes, c.outline)
            #expect(diff.max <= outlineMaxTolerance, "max \(diff.max): \(c.label)")
            #expect(diff.mean <= outlineMeanTolerance, "mean \(diff.mean): \(c.label)")
        }
    }

    @Test("coverage matches GlyphRaster at every size CoreText draws as outlined", arguments: fontFiles)
    func coverageAgainstGlyphRaster(file: String) throws {
        let cases = try oracleCases(file).filter { !$0.coreText.isEmpty && !glyphRasterAdjustedSizes.contains($0.key) }
        let adjusted = glyphRasterAdjustedSizes.filter { $0.file == file }.count
        try #require(cases.count == (sizes.count * scales.count - adjusted) * (characters.count - 1)
                     * GlyphImage.subpixelVariants)
        for c in cases {
            try #require(c.freeType.bytes.count == c.coreText.bytes.count, "\(c.label)")
            let diff = CoverageDiff(c.freeType.bytes, c.coreText.bytes)
            #expect(diff.max <= glyphRasterMaxTolerance, "max \(diff.max): \(c.label)")
            #expect(diff.mean <= glyphRasterMeanTolerance, "mean \(diff.mean): \(c.label)")
        }
    }

    /// The known difference, pinned: at these sizes `CTFontDrawGlyphs` moves
    /// ink up and away from the outline for every inked glyph but the dot.
    @Test("GlyphRaster departs from the outline at exactly the adjusted sizes", arguments: fontFiles)
    func glyphRasterAdjustsTheseSizesAwayFromTheOutline(file: String) throws {
        let cases = try oracleCases(file).filter { !$0.coreText.isEmpty && $0.character != "." }
        var worstMeanBySize: [SizeKey: Double] = [:]
        for c in cases {
            try #require(c.freeType.bytes.count == c.coreText.bytes.count, "\(c.label)")
            let mean = CoverageDiff(c.freeType.bytes, c.coreText.bytes).mean
            worstMeanBySize[c.key] = max(worstMeanBySize[c.key] ?? 0, mean)
        }
        try #require(worstMeanBySize.count == sizes.count * scales.count)
        for (key, worst) in worstMeanBySize {
            #expect((worst > glyphRasterMeanTolerance) == glyphRasterAdjustedSizes.contains(key),
                    "\(key): worst per-case mean |FreeType - GlyphRaster| \(worst)")
        }
    }

    /// Prints the numbers every constant above was set from.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["METALUI_FREETYPE_MEASURE"] == "1"),
          arguments: fontFiles)
    func measure(file: String) throws {
        let cases = try oracleCases(file)
        let agree = cases.filter {
            $0.coreText.width == $0.freeType.width && $0.coreText.height == $0.freeType.height
                && $0.coreText.left == $0.freeType.left && $0.coreText.top == $0.freeType.top
        }.count
        print("MEASURE \(file): geometry agrees in \(agree)/\(cases.count) cases")
        let inked = cases.filter { !$0.coreText.isEmpty && $0.coreText.bytes.count == $0.freeType.bytes.count }
        for size in sizes { for scale in scales {
            let key = SizeKey(file: file, size: size, scale: scale)
            let group = inked.filter { $0.key == key }
            let vsCT = group.map { CoverageDiff($0.freeType.bytes, $0.coreText.bytes) }
            let vsPath = group.map { CoverageDiff($0.freeType.bytes, $0.outline) }
            let shifts = group.map { inkCentroidY($0.coreText) - inkCentroidY($0.freeType) }
            let inkRatio = group.map { Double($0.coreText.bytes.reduce(0) { $0 + Int($1) })
                / Double($0.freeType.bytes.reduce(0) { $0 + Int($1) }) }
            print(String(format: "MEASURE   %@ %4.0fpt x%.0f  vsGlyphRaster max %3d worstMean %6.3f | vsOutline max %3d worstMean %6.3f | ctInkUp %+.2f..%+.2f px | ctInk/ftInk %.2f..%.2f",
                         file, size, Double(scale),
                         vsCT.map(\.max).max()!, vsCT.map(\.mean).max()!,
                         vsPath.map(\.max).max()!, vsPath.map(\.mean).max()!,
                         shifts.min()!, shifts.max()!, inkRatio.min()!, inkRatio.max()!))
        } }
    }
}
