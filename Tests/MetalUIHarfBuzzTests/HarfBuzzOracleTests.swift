import CoreText
import Foundation
import Testing
import MetalUIFreeType
import MetalUIScene
import MetalUIHarfBuzz

// CoreText is the oracle for the HarfBuzz shaper on macOS (ruling SH-G).
//
// The same font bytes go into both shapers: CoreText through
// `CTFontManagerCreateFontDescriptorsFromData` -> `CTFontCreateWithFontDescriptor`
// at 13 pt, HarfBuzz through `HarfBuzzFont(data:size:)`. CoreText's answer is a
// `CTLine` over an attributed string carrying that font, read run by run:
// `CTRunGetGlyphs`, `CTRunGetPositions`, `CTRunGetAdvances`,
// `CTRunGetStringIndices` and `CTRunGetStatus`'s `kCTRunStatusRightToLeft`.
// The fonts are `Tests/Fonts/` (FT-G, SH-F), read by path from `#filePath`.
//
// What is asserted: the same glyph-id sequence, the same cluster sequence (as
// UTF-16 offsets, SH-C), the same visual order, and positions and the run
// total within the tolerances below, each set from a measured maximum.
//
// **Two representations of the same placement.** CoreText has no per-glyph
// offset: it folds every mark shift into its advances, so every offset derived
// from `positions - walk(advances)` is zero over the whole corpus (measured:
// max 7.1e-15 pt over 404 values, pinned by
// `coreTextFoldsGlyphOffsetsIntoItsAdvances`). HarfBuzz reports an advance and
// an offset, and in the Arabic mark cases the two conventions differ by as much
// as 2.366 pt of advance and 2.262 pt of offset while drawing the glyph in
// exactly the same place. Comparing the raw numbers would therefore need a
// 2.4 pt tolerance that hides everything; instead the corpus-wide bounds are on
// the quantities the two agree on by definition — where the pen lands
// (`penAdvances`), where the glyph is drawn, and the run total — and the raw
// per-glyph advances are asserted on the 27 cases where HarfBuzz reports no
// offset at all and the two representations coincide.
//
// Ids and clusters are never traded for a tolerance (SH-G). Two cases disagree
// and each is pinned by name, with the experiment that explains it:
// `harfBuzzMergesMarkClustersIntoTheirBase` and
// `harfBuzzGuessesDirectionFromScriptWhereCoreTextRunsBidi`.
//
// Re-measure with `METALUI_HARFBUZZ_MEASURE=1 swift test --build-system native
// --no-parallel --filter HarfBuzzOracleTests/measure` before changing a
// constant here. That run prints, per case, every number below.

// MARK: - Tolerances (measured 2026-09-22, macOS 27.0, HarfBuzz 14.5.0, 13 pt)

/// Largest |HarfBuzz - CoreText| per-glyph pen advance (x or y), in points.
/// Measured maximum over the whole corpus: 1.7763568394002505e-15. The same
/// bound covers the raw per-glyph advances on the offset-free cases, whose
/// measured maximum is the same 1.7763568394002505e-15. Margin: ~560x, which
/// is still four orders of magnitude below a design unit at this size
/// (13/1000 pt = 0.013 pt for Noto Sans).
let advanceTolerance = 1e-12
/// Largest per-glyph offset CoreText reports once its advances are walked —
/// it has none, and this bounds the floating-point residue. Measured maximum:
/// 7.105427357601002e-15 over 404 values.
let offsetTolerance = 1e-12
/// Largest |HarfBuzz - CoreText| drawn glyph position (pen + offset), in
/// points. Measured maximum over the whole corpus: 5.684341886080802e-14.
let positionTolerance = 1e-12
/// Largest |HarfBuzz - CoreText| total run advance, in points. Measured
/// maximum: 5.684341886080802e-14.
let totalAdvanceTolerance = 1e-12

// MARK: - The corpus (SH-G)

let notoSans = "NotoSans-Regular.ttf"
let sourceSans = "SourceSans3-Regular.otf"
let notoSansArabic = "NotoSansArabic-Regular.ttf"
let latinFiles = [notoSans, sourceSans]
/// The size SH-G names. Shaping is done in design units and converted (SH-D),
/// so this scales the answer rather than changing it.
let oracleSize = 13.0

/// One corpus string in one font.
struct ShapingCase: Sendable, CustomStringConvertible, CustomTestStringConvertible {
    let file: String
    let name: String
    let text: String
    /// True when every character is unligated, unmarked ASCII, so the shaped
    /// ids must equal `FreeTypeFont.glyph(for:)` one for one (SH-H).
    let isPlainASCII: Bool
    var description: String { "\(file) \(name)" }
    var testDescription: String { description }
}

struct CorpusString: Sendable {
    let name: String
    let text: String
    let isPlainASCII: Bool
    init(_ name: String, _ text: String, plainASCII: Bool = false) {
        self.name = name; self.text = text; self.isPlainASCII = plainASCII
    }
}

/// Plain text, the four kerning pairs, the three ligature candidates, three
/// combining-mark sequences, digits and punctuation (SH-G). Both Latin fonts
/// get all of them; which ligatures actually fire differs (Noto Sans forms
/// `fi`, `fl` and `ffi`; Source Sans 3 leaves two glyphs in each case) and the
/// oracle checks agreement, not a particular outcome.
let latinStrings: [CorpusString] = [
    CorpusString("plain", "The quick brown fox jumps over the lazy dog", plainASCII: true),
    CorpusString("kern AV", "AV", plainASCII: true),
    CorpusString("kern To", "To", plainASCII: true),
    CorpusString("kern Ty", "Ty", plainASCII: true),
    CorpusString("kern LT", "LT", plainASCII: true),
    CorpusString("liga fi", "fi"),
    CorpusString("liga fl", "fl"),
    CorpusString("liga ffi", "ffi"),
    CorpusString("mark e+acute", "e\u{0301}"),
    CorpusString("mark a+diaeresis", "a\u{0308}"),
    CorpusString("mark n+tilde", "n\u{0303}"),
    CorpusString("digits", "0123456789", plainASCII: true),
    CorpusString("punctuation", ".,;:!?-()'\"", plainASCII: true),
]

/// A plain word, a sentence with spaces, lam-alef, a word with harakat, and
/// Arabic-Indic digits (SH-G).
let arabicStrings: [CorpusString] = [
    CorpusString("arabic word", "مرحبا"),
    CorpusString("arabic sentence", "مرحبا بالعالم"),
    CorpusString("arabic lam-alef", "لا"),
    CorpusString("arabic harakat", "مَرْحَبًا"),
    CorpusString("arabic-indic digits", "٠١٢٣٤٥٦٧٨٩"),
]

let corpus: [ShapingCase] =
    latinFiles.flatMap { file in
        latinStrings.map { ShapingCase(file: file, name: $0.name, text: $0.text, isPlainASCII: $0.isPlainASCII) }
    }
    + arabicStrings.map {
        ShapingCase(file: notoSansArabic, name: $0.name, text: $0.text, isPlainASCII: $0.isPlainASCII)
    }

let latinCorpus: [ShapingCase] = corpus.filter { $0.file != notoSansArabic }

/// The one case whose glyph ORDER CoreText does not reproduce, pinned by
/// `harfBuzzGuessesDirectionFromScriptWhereCoreTextRunsBidi`. Element-wise
/// comparison is meaningless for it; the run total is still asserted.
let orderPin = "\(notoSansArabic) arabic-indic digits"
/// The one case whose CLUSTERS CoreText does not reproduce, pinned by
/// `harfBuzzMergesMarkClustersIntoTheirBase`. Its ids, order, positions and
/// total are all still asserted.
let clusterPin = "\(notoSansArabic) arabic harakat"

// MARK: - Loading

func fontURL(_ file: String) -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fonts").appendingPathComponent(file)
}

/// The same bytes in both shapers.
struct OracleFont {
    let file: String
    let data: [UInt8]
    let coreText: CTFont
    let harfBuzz: HarfBuzzFont

    init(_ file: String, size: Double = oracleSize) throws {
        self.file = file
        let bytes = try Data(contentsOf: fontURL(file))
        data = [UInt8](bytes)
        let descriptors = CTFontManagerCreateFontDescriptorsFromData(bytes as CFData) as? [CTFontDescriptor] ?? []
        let descriptor = try #require(descriptors.first, "CoreText rejected \(file)")
        coreText = CTFontCreateWithFontDescriptor(descriptor, CGFloat(size), nil)
        harfBuzz = try HarfBuzzFont(data: data, size: size)
    }
}

// MARK: - CoreText's answer

struct OracleGlyph: Equatable {
    let id: UInt16
    /// UTF-16 offset, from `CTRunGetStringIndices`.
    let cluster: Int
    /// From `CTRunGetAdvances`.
    let xAdvance: Double
    let yAdvance: Double
    /// `position - walk(advances)`; zero over this whole corpus, since
    /// CoreText folds mark shifts into its advances.
    let xOffset: Double
    let yOffset: Double
    /// Where the glyph is drawn, in line coordinates (`CTRunGetPositions`).
    let x: Double
    let y: Double
}

struct OracleShaping {
    let glyphs: [OracleGlyph]
    /// `CTLineGetTypographicBounds`' width.
    let advance: Double
    let isRightToLeft: Bool
    /// How many `CTRun`s CoreText split the string into.
    let runCount: Int
}

/// Shapes with CoreText: one `CTLine`, read run by run in visual order.
func coreTextShape(_ text: String, font: CTFont) -> OracleShaping {
    let attributed = NSAttributedString(
        string: text, attributes: [kCTFontAttributeName as NSAttributedString.Key: font])
    let line = CTLineCreateWithAttributedString(attributed)
    let runs = (CTLineGetGlyphRuns(line) as? [CTRun]) ?? []
    var glyphs: [OracleGlyph] = []
    var anyRightToLeft = false
    for run in runs {
        let count = CTRunGetGlyphCount(run)
        guard count > 0 else { continue }
        let range = CFRangeMake(0, count)
        var ids = [CGGlyph](repeating: 0, count: count)
        var positions = [CGPoint](repeating: .zero, count: count)
        var advances = [CGSize](repeating: .zero, count: count)
        var indices = [CFIndex](repeating: 0, count: count)
        CTRunGetGlyphs(run, range, &ids)
        CTRunGetPositions(run, range, &positions)
        CTRunGetAdvances(run, range, &advances)
        CTRunGetStringIndices(run, range, &indices)
        let rightToLeft = CTRunGetStatus(run).contains(.rightToLeft)
        anyRightToLeft = anyRightToLeft || rightToLeft
        var penX = positions[0].x, penY = positions[0].y
        for index in 0..<count {
            glyphs.append(OracleGlyph(
                id: UInt16(ids[index]), cluster: Int(indices[index]),
                xAdvance: Double(advances[index].width), yAdvance: Double(advances[index].height),
                xOffset: Double(positions[index].x - penX), yOffset: Double(positions[index].y - penY),
                x: Double(positions[index].x), y: Double(positions[index].y)))
            penX += advances[index].width
            penY += advances[index].height
        }
    }
    var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
    let width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
    return OracleShaping(glyphs: glyphs, advance: Double(width),
                         isRightToLeft: anyRightToLeft, runCount: runs.count)
}

// MARK: - HarfBuzz's answer, in CoreText's coordinates

/// Where HarfBuzz's renderer draws each glyph: pen + offset, the pen walking
/// the advances from the run's origin.
func placedPositions(_ run: ShapedRun) -> [(x: Double, y: Double)] {
    var penX = 0.0, penY = 0.0
    var placed: [(x: Double, y: Double)] = []
    for glyph in run.glyphs {
        placed.append((penX + glyph.xOffset, penY + glyph.yOffset))
        penX += glyph.xAdvance; penY += glyph.yAdvance
    }
    return placed
}

/// The step from each glyph's drawn position to the next one's — CoreText's
/// idea of a per-glyph advance, since it carries no offsets of its own. For
/// HarfBuzz that is `xAdvance + nextOffset - offset`, the last glyph closing
/// on the run total.
func penAdvances(_ run: ShapedRun) -> [(x: Double, y: Double)] {
    run.glyphs.indices.map { index in
        let glyph = run.glyphs[index]
        let next = index + 1 < run.glyphs.count ? run.glyphs[index + 1] : nil
        return (glyph.xAdvance + (next?.xOffset ?? 0) - glyph.xOffset,
                glyph.yAdvance + (next?.yOffset ?? 0) - glyph.yOffset)
    }
}

/// Both answers for one case.
struct Comparison {
    let shapingCase: ShapingCase
    let harfBuzz: ShapedRun
    let coreText: OracleShaping

    init(_ shapingCase: ShapingCase, font: OracleFont) throws {
        self.shapingCase = shapingCase
        harfBuzz = try HarfBuzzShaper.shape(shapingCase.text, font: font.harfBuzz)
        coreText = coreTextShape(shapingCase.text, font: font.coreText)
    }

    var idsAgree: Bool { harfBuzz.glyphs.map(\.id) == coreText.glyphs.map(\.id) }
    var clustersAgree: Bool { harfBuzz.glyphs.map(\.cluster) == coreText.glyphs.map(\.cluster) }
    /// True when HarfBuzz reports no offsets, so its raw advances are already
    /// in CoreText's representation.
    var harfBuzzUsesNoOffsets: Bool {
        harfBuzz.glyphs.allSatisfy { $0.xOffset == 0 && $0.yOffset == 0 }
    }

    /// Maxima over the glyphs, or nil when the two disagree on the count.
    var maxima: (advance: Double, offset: Double, penAdvance: Double, position: Double)? {
        guard harfBuzz.glyphs.count == coreText.glyphs.count else { return nil }
        var advance = 0.0, offset = 0.0, penAdvance = 0.0, position = 0.0
        let placed = placedPositions(harfBuzz)
        let pen = penAdvances(harfBuzz)
        // CoreText's line origin is the first glyph's pen, which HarfBuzz
        // calls 0; both are therefore read from their own origin.
        let originX = coreText.glyphs.first.map { $0.x - $0.xOffset } ?? 0
        let originY = coreText.glyphs.first.map { $0.y - $0.yOffset } ?? 0
        for index in harfBuzz.glyphs.indices {
            let a = harfBuzz.glyphs[index], b = coreText.glyphs[index]
            advance = max(advance, abs(a.xAdvance - b.xAdvance), abs(a.yAdvance - b.yAdvance))
            offset = max(offset, abs(a.xOffset - b.xOffset), abs(a.yOffset - b.yOffset))
            penAdvance = max(penAdvance, abs(pen[index].x - b.xAdvance), abs(pen[index].y - b.yAdvance))
            position = max(position, abs(placed[index].x - (b.x - originX)),
                           abs(placed[index].y - (b.y - originY)))
        }
        return (advance, offset, penAdvance, position)
    }

    var totalAdvanceDifference: Double { abs(harfBuzz.advance - coreText.advance) }
}

/// One `OracleFont` per file, reused across the corpus.
func comparisons() throws -> [Comparison] {
    var fonts: [String: OracleFont] = [:]
    var result: [Comparison] = []
    for shapingCase in corpus {
        let font: OracleFont
        if let cached = fonts[shapingCase.file] {
            font = cached
        } else {
            font = try OracleFont(shapingCase.file)
            fonts[shapingCase.file] = font
        }
        result.append(try Comparison(shapingCase, font: font))
    }
    return result
}

// MARK: - Tests

@Suite struct HarfBuzzOracleTests {

    // MARK: SH-F — the Arabic font

    /// The bundled Arabic face really is one: an Arabic `cmap` and the OpenType
    /// joining features, read back from the file the oracle loads.
    @Test func theArabicFontHasAnArabicCmapAndJoiningFeatures() throws {
        let font = try OracleFont(notoSansArabic)
        // The letters, marks, digits and space the Arabic corpus needs.
        for scalar: Unicode.Scalar in ["\u{0627}", "\u{0644}", "\u{0645}", "\u{0631}",
                                       "\u{062D}", "\u{0628}", "\u{0639}", "\u{064E}",
                                       "\u{0652}", "\u{064B}", "\u{0660}", "\u{0669}", " "] {
            var units = Array(String(scalar).utf16)
            var glyphs = [CGGlyph](repeating: 0, count: units.count)
            let mapped = CTFontGetGlyphsForCharacters(font.coreText, &units, &glyphs, units.count)
            #expect(mapped, "no glyph for U+\(String(scalar.value, radix: 16, uppercase: true))")
            #expect(glyphs[0] != 0)
        }
        let gsub = try #require(CTFontCopyTable(font.coreText, CTFontTableTag(kCTFontTableGSUB), []) as Data?)
        let substitution = layoutTableTags(gsub)
        #expect(substitution.scripts.contains("arab"))
        // The joining set, plus the lam-alef ligature and mark composition.
        for tag in ["init", "medi", "fina", "rlig", "ccmp", "liga"] {
            #expect(substitution.features.contains(tag), "GSUB has no '\(tag)'")
        }
        let gpos = try #require(CTFontCopyTable(font.coreText, CTFontTableTag(kCTFontTableGPOS), []) as Data?)
        let positioning = layoutTableTags(gpos)
        for tag in ["kern", "mark", "mkmk"] {
            #expect(positioning.features.contains(tag), "GPOS has no '\(tag)'")
        }
        // It carries no Latin letters, so a Latin string in this face would be
        // all .notdef — which is why the Latin corpus never uses it.
        var latin = Array("Aa".utf16)
        var latinGlyphs = [CGGlyph](repeating: 0, count: latin.count)
        #expect(!CTFontGetGlyphsForCharacters(font.coreText, &latin, &latinGlyphs, latin.count))
        #expect(latinGlyphs == [0, 0])
    }

    // MARK: SH-G — ids, clusters, order and direction

    @Test(arguments: corpus)
    func glyphIdsAgreeWithCoreText(shapingCase: ShapingCase) throws {
        guard shapingCase.description != orderPin else { return }
        let comparison = try Comparison(shapingCase, font: OracleFont(shapingCase.file))
        #expect(comparison.harfBuzz.glyphs.map(\.id) == comparison.coreText.glyphs.map(\.id))
    }

    @Test(arguments: corpus)
    func clusterSequencesAgreeWithCoreText(shapingCase: ShapingCase) throws {
        guard shapingCase.description != orderPin, shapingCase.description != clusterPin else { return }
        let comparison = try Comparison(shapingCase, font: OracleFont(shapingCase.file))
        #expect(comparison.harfBuzz.glyphs.map(\.cluster) == comparison.coreText.glyphs.map(\.cluster))
    }

    /// Visual order: both arrays run the way the text is drawn, so walking
    /// either one advances the pen left to right and element `i` of one is
    /// element `i` of the other. That is what makes the element-wise
    /// comparisons above a comparison of the same glyph.
    ///
    /// Note what is NOT asserted: that the drawn x positions increase. They do
    /// not, in either shaper — a mark is drawn left of the pen its base left
    /// behind, so `مَرْحَبًا` has four glyphs at a smaller x than their
    /// predecessor in CoreText's positions and in HarfBuzz's. Visual order is
    /// a statement about the PEN, and about which string offsets appear in
    /// which order.
    @Test(arguments: corpus)
    func glyphsAreInVisualOrderInBothShapers(shapingCase: ShapingCase) throws {
        let comparison = try Comparison(shapingCase, font: OracleFont(shapingCase.file))
        try #require(!comparison.harfBuzz.glyphs.isEmpty)
        try #require(!comparison.coreText.glyphs.isEmpty)
        // The pen only ever moves right.
        for glyph in comparison.harfBuzz.glyphs { #expect(glyph.xAdvance >= 0) }
        // Clusters run one way, the way each shaper says the run goes: a
        // right-to-left run visits the string backwards.
        func clustersRunWithTheDirection(_ clusters: [Int], rightToLeft: Bool) -> Bool {
            zip(clusters, clusters.dropFirst()).allSatisfy { rightToLeft ? $1 <= $0 : $1 >= $0 }
        }
        #expect(clustersRunWithTheDirection(comparison.harfBuzz.glyphs.map(\.cluster),
                                            rightToLeft: comparison.harfBuzz.isRightToLeft))
        #expect(clustersRunWithTheDirection(comparison.coreText.glyphs.map(\.cluster),
                                            rightToLeft: comparison.coreText.isRightToLeft))
    }

    @Test(arguments: corpus)
    func directionAgreesWithCoreText(shapingCase: ShapingCase) throws {
        guard shapingCase.description != orderPin else { return }
        let comparison = try Comparison(shapingCase, font: OracleFont(shapingCase.file))
        #expect(comparison.harfBuzz.isRightToLeft == comparison.coreText.isRightToLeft)
        #expect(comparison.harfBuzz.isRightToLeft == (shapingCase.file == notoSansArabic))
    }

    // MARK: SH-G — positions

    @Test(arguments: corpus)
    func drawnPositionsAgreeWithCoreText(shapingCase: ShapingCase) throws {
        guard shapingCase.description != orderPin else { return }
        let comparison = try Comparison(shapingCase, font: OracleFont(shapingCase.file))
        let maxima = try #require(comparison.maxima, "glyph counts differ")
        #expect(maxima.position <= positionTolerance, "drawn position off by \(maxima.position)")
    }

    @Test(arguments: corpus)
    func penAdvancesAgreeWithCoreText(shapingCase: ShapingCase) throws {
        guard shapingCase.description != orderPin else { return }
        let comparison = try Comparison(shapingCase, font: OracleFont(shapingCase.file))
        let maxima = try #require(comparison.maxima, "glyph counts differ")
        #expect(maxima.penAdvance <= advanceTolerance, "pen advance off by \(maxima.penAdvance)")
    }

    /// The raw per-glyph advances, on the cases where HarfBuzz reports no
    /// offset and the two shapers' representations coincide.
    @Test func rawAdvancesAgreeWhereHarfBuzzReportsNoOffsets() throws {
        let offsetFree = try comparisons().filter {
            $0.harfBuzzUsesNoOffsets && $0.shapingCase.description != orderPin
        }
        // 27 of the 31 cases: all 26 Latin ones plus lam-alef. The Arabic
        // word, sentence and harakat carry mark offsets; the digits are the
        // order pin, excluded above.
        try #require(offsetFree.count == 27, "the offset-free set is \(offsetFree.count) cases, not 27")
        for comparison in offsetFree {
            let label = comparison.shapingCase.description
            let maxima = try #require(comparison.maxima, "\(label): glyph counts differ")
            #expect(maxima.advance <= advanceTolerance, "\(label): advance off by \(maxima.advance)")
            #expect(maxima.offset <= offsetTolerance, "\(label): offset off by \(maxima.offset)")
        }
    }

    @Test(arguments: corpus)
    func totalAdvanceAgreesWithCoreText(shapingCase: ShapingCase) throws {
        let comparison = try Comparison(shapingCase, font: OracleFont(shapingCase.file))
        #expect(comparison.totalAdvanceDifference <= totalAdvanceTolerance,
                "total off by \(comparison.totalAdvanceDifference)")
    }

    /// Why the corpus-wide bounds are on pen advances rather than raw ones:
    /// CoreText carries no per-glyph offset at all, so `positions` and
    /// `advances` are the same information twice. Measured over the whole
    /// corpus: every derived offset is zero to 7.105427357601002e-15 pt.
    @Test func coreTextFoldsGlyphOffsetsIntoItsAdvances() throws {
        let offsets = try comparisons().flatMap { $0.coreText.glyphs.flatMap { [$0.xOffset, $0.yOffset] } }
        try #require(offsets.count == 404, "the corpus is \(offsets.count / 2) glyphs, not 202")
        #expect(offsets.map(abs).max() ?? 0 <= offsetTolerance)
        // The separating arm: HarfBuzz does report offsets, in the Arabic mark
        // cases, and they are large — up to 2.262 pt at 13 pt.
        let harakat = try #require(arabicStrings.first { $0.name == "arabic harakat" })
        let run = try HarfBuzzShaper.shape(harakat.text, font: OracleFont(notoSansArabic).harfBuzz)
        #expect(run.glyphs.map(\.xOffset).map(abs).max() ?? 0 > 1.8)
    }

    // MARK: SH-G — the two pinned disagreements

    /// HarfBuzz's default cluster level (`MONOTONE_GRAPHEMES`) merges a mark
    /// into its base, which `ShapedGlyph.cluster`'s contract states ("several
    /// glyphs can share a cluster"); CoreText's string indices number each
    /// character. For `مَرْحَبًا` HarfBuzz answers [8,6,6,6,4,4,2,2,0,0] where
    /// CoreText answers [8,7,6,6,5,4,3,2,1,0] — every difference is a mark
    /// reported at its base's offset instead of its own.
    ///
    /// Measured, not assumed: setting
    /// `hb_buffer_set_cluster_level(buffer, HB_BUFFER_CLUSTER_LEVEL_MONOTONE_CHARACTERS)`
    /// in `HarfBuzzShaper.shape` makes this case's clusters equal CoreText's
    /// exactly and changes no other case in the corpus — no id, no cluster, no
    /// position moves. The difference is the cluster level alone; the shaping
    /// is identical, which the id and position assertions below pin.
    @Test func harfBuzzMergesMarkClustersIntoTheirBase() throws {
        let shapingCase = try #require(corpus.first { $0.description == clusterPin })
        let comparison = try Comparison(shapingCase, font: OracleFont(shapingCase.file))
        #expect(comparison.harfBuzz.glyphs.map(\.cluster) == [8, 6, 6, 6, 4, 4, 2, 2, 0, 0])
        #expect(comparison.coreText.glyphs.map(\.cluster) == [8, 7, 6, 6, 5, 4, 3, 2, 1, 0])
        // Same glyphs, drawn in the same places: only the attribution differs.
        #expect(comparison.idsAgree)
        let maxima = try #require(comparison.maxima)
        #expect(maxima.position <= positionTolerance)
        // Each HarfBuzz cluster is its CoreText character's grapheme base: the
        // base offsets of this string are the even ones.
        for (harfBuzz, coreText) in zip(comparison.harfBuzz.glyphs, comparison.coreText.glyphs) {
            #expect(harfBuzz.cluster <= coreText.cluster)
            #expect(harfBuzz.cluster % 2 == 0)
            #expect(coreText.cluster - harfBuzz.cluster <= 1)
        }
    }

    /// `hb_buffer_guess_segment_properties` takes the direction from the
    /// script (SH-C), and Arabic's horizontal direction is right-to-left — so
    /// a string of nothing but Arabic-Indic digits shapes right-to-left and
    /// comes back reversed. CoreText runs the Unicode bidi algorithm instead:
    /// U+0660..U+0669 are bidi class AN, not strong, so the paragraph has no
    /// strong character, its level is 0, and the digits are laid out left to
    /// right.
    ///
    /// The separating arm, measured: put one strong Arabic letter in front and
    /// CoreText's line turns right-to-left overall (two runs, the letter last
    /// in visual order at cluster 0) while the digits keep ascending — so the
    /// left-to-right answer here is the paragraph level, not a property of the
    /// digit glyphs. HarfBuzz is not a bidi engine and this step shapes one
    /// run (spec, "Not in this step"), so the caller's job is to pass the
    /// direction the bidi algorithm resolved: with `.leftToRight` the shaper
    /// reproduces CoreText exactly, which is what is pinned here.
    @Test func harfBuzzGuessesDirectionFromScriptWhereCoreTextRunsBidi() throws {
        let shapingCase = try #require(corpus.first { $0.description == orderPin })
        let font = try OracleFont(shapingCase.file)
        let coreText = coreTextShape(shapingCase.text, font: font.coreText)
        #expect(!coreText.isRightToLeft)
        #expect(coreText.glyphs.map(\.cluster) == [0, 1, 2, 3, 4, 5, 6, 7, 8, 9])

        let guessed = try HarfBuzzShaper.shape(shapingCase.text, font: font.harfBuzz)
        #expect(guessed.isRightToLeft)
        #expect(guessed.glyphs.map(\.id) == coreText.glyphs.map(\.id).reversed())
        #expect(guessed.glyphs.map(\.cluster) == [9, 8, 7, 6, 5, 4, 3, 2, 1, 0])
        // The same total either way: these glyphs have one advance, 7.436 pt.
        #expect(abs(guessed.advance - coreText.advance) <= totalAdvanceTolerance)

        let directed = try HarfBuzzShaper.shape(shapingCase.text, font: font.harfBuzz,
                                                direction: .leftToRight)
        #expect(!directed.isRightToLeft)
        #expect(directed.glyphs.map(\.id) == coreText.glyphs.map(\.id))
        #expect(directed.glyphs.map(\.cluster) == coreText.glyphs.map(\.cluster))
        let placed = placedPositions(directed)
        for (index, glyph) in coreText.glyphs.enumerated() {
            #expect(abs(placed[index].x - glyph.x) <= positionTolerance)
            #expect(abs(placed[index].y - glyph.y) <= positionTolerance)
        }
    }

    // MARK: SH-H — the ids are FreeType's

    @Test(arguments: latinCorpus)
    func everyShapedLatinGlyphRasterizes(shapingCase: ShapingCase) throws {
        let font = try OracleFont(shapingCase.file)
        let freeType = try FreeTypeFont(data: font.data, size: oracleSize)
        let space = freeType.glyph(for: " ")
        let run = try HarfBuzzShaper.shape(shapingCase.text, font: font.harfBuzz)
        try #require(!run.glyphs.isEmpty)
        for glyph in run.glyphs {
            let image = try FreeTypeRaster.rasterize(glyph: glyph.id, font: freeType,
                                                     subpixelVariant: 0, scaleFactor: 1)
            if glyph.id == space {
                #expect(image.isEmpty, "the space rasterized to \(image.width)x\(image.height)")
            } else {
                #expect(!image.isEmpty, "\(shapingCase.description): glyph \(glyph.id) rasterized empty")
                #expect(image.bytes.contains { $0 > 0 },
                        "\(shapingCase.description): glyph \(glyph.id) has no coverage")
            }
        }
    }

    @Test(arguments: latinCorpus.filter(\.isPlainASCII))
    func plainASCIIIdsEqualFreeTypesCmapLookup(shapingCase: ShapingCase) throws {
        let font = try OracleFont(shapingCase.file)
        let freeType = try FreeTypeFont(data: font.data, size: oracleSize)
        let run = try HarfBuzzShaper.shape(shapingCase.text, font: font.harfBuzz)
        let scalars = Array(shapingCase.text.unicodeScalars)
        try #require(run.glyphs.count == scalars.count,
                     "\(shapingCase.description) is not one glyph per character (\(run.glyphs.count) vs \(scalars.count))")
        for (glyph, scalar) in zip(run.glyphs, scalars) {
            #expect(scalar.isASCII)
            let fromCmap = freeType.glyph(for: scalar)
            #expect(glyph.id == fromCmap,
                    "\(shapingCase.description) '\(scalar)': shaper \(glyph.id), FreeType \(fromCmap)")
        }
    }

    // MARK: Measurement (SH-G: the tolerances above are set from these numbers)

    @Test(.enabled(if: ProcessInfo.processInfo.environment["METALUI_HARFBUZZ_MEASURE"] == "1"))
    func measure() throws {
        var worstAdvance = 0.0, worstOffset = 0.0, worstPen = 0.0, worstPosition = 0.0, worstTotal = 0.0
        var worstOffsetFreeAdvance = 0.0
        for comparison in try comparisons() {
            let ids = comparison.idsAgree ? "ids=" : "IDS DIFFER "
            let clusters = comparison.clustersAgree ? "clusters=" : "CLUSTERS DIFFER "
            if let maxima = comparison.maxima {
                worstAdvance = max(worstAdvance, maxima.advance)
                worstOffset = max(worstOffset, maxima.offset)
                worstPen = max(worstPen, maxima.penAdvance)
                worstPosition = max(worstPosition, maxima.position)
                if comparison.harfBuzzUsesNoOffsets {
                    worstOffsetFreeAdvance = max(worstOffsetFreeAdvance, maxima.advance)
                }
                print("MEASURE \(comparison.shapingCase.description.padding(toLength: 44, withPad: " ", startingAt: 0))"
                      + " n=\(comparison.harfBuzz.glyphs.count) runs=\(comparison.coreText.runCount) "
                      + ids + clusters
                      + " dAdv \(maxima.advance) dOff \(maxima.offset) dPen \(maxima.penAdvance)"
                      + " dPos \(maxima.position) dTotal \(comparison.totalAdvanceDifference)")
            } else {
                print("MEASURE \(comparison.shapingCase) COUNTS DIFFER "
                      + "hb=\(comparison.harfBuzz.glyphs.count) ct=\(comparison.coreText.glyphs.count) "
                      + "runs=\(comparison.coreText.runCount) dTotal=\(comparison.totalAdvanceDifference)")
            }
            worstTotal = max(worstTotal, comparison.totalAdvanceDifference)
            if !comparison.idsAgree || !comparison.clustersAgree
                || comparison.harfBuzz.glyphs.count != comparison.coreText.glyphs.count {
                print("MEASURE     hb ids      \(comparison.harfBuzz.glyphs.map(\.id))")
                print("MEASURE     ct ids      \(comparison.coreText.glyphs.map(\.id))")
                print("MEASURE     hb clusters \(comparison.harfBuzz.glyphs.map(\.cluster))")
                print("MEASURE     ct clusters \(comparison.coreText.glyphs.map(\.cluster))")
                print("MEASURE     hb adv      \(comparison.harfBuzz.glyphs.map { rounded($0.xAdvance) })")
                print("MEASURE     ct adv      \(comparison.coreText.glyphs.map { rounded($0.xAdvance) })")
                print("MEASURE     hb off      \(comparison.harfBuzz.glyphs.map { rounded($0.xOffset) })")
                print("MEASURE     ct off      \(comparison.coreText.glyphs.map { rounded($0.xOffset) })")
            }
        }
        print("MEASURE MAXIMA rawAdvance \(worstAdvance) rawOffset \(worstOffset) "
              + "offsetFreeRawAdvance \(worstOffsetFreeAdvance) "
              + "penAdvance \(worstPen) position \(worstPosition) total \(worstTotal)")

        // The investigation behind the direction pin.
        let arabic = try OracleFont(notoSansArabic)
        let digits = try #require(arabicStrings.first { $0.name == "arabic-indic digits" })
        for direction: ShapingDirection in [.auto, .leftToRight, .rightToLeft] {
            let run = try HarfBuzzShaper.shape(digits.text, font: arabic.harfBuzz, direction: direction)
            print("MEASURE digits \(direction) rtl=\(run.isRightToLeft) ids=\(run.glyphs.map(\.id)) "
                  + "clusters=\(run.glyphs.map(\.cluster))")
        }
        let coreText = coreTextShape(digits.text, font: arabic.coreText)
        print("MEASURE digits CoreText rtl=\(coreText.isRightToLeft) ids=\(coreText.glyphs.map(\.id)) "
              + "clusters=\(coreText.glyphs.map(\.cluster))")
        // The separating arm: the same digits after a strong right-to-left
        // letter come out inside a right-to-left line, still ascending.
        let mixed = coreTextShape("\u{0645}" + digits.text, font: arabic.coreText)
        print("MEASURE digits-after-letter CoreText rtl=\(mixed.isRightToLeft) runs=\(mixed.runCount) "
              + "ids=\(mixed.glyphs.map(\.id)) clusters=\(mixed.glyphs.map(\.cluster))")

        let offsets = try comparisons().flatMap { $0.coreText.glyphs.flatMap { [$0.xOffset, $0.yOffset] } }
        print("MEASURE CoreText derived offsets: max |offset| = \(offsets.map(abs).max() ?? 0) "
              + "over \(offsets.count) values")
    }
}

func rounded(_ value: Double) -> Double { (value * 1e4).rounded() / 1e4 }

// MARK: - OpenType layout table tags

/// The script and feature tags of a `GSUB`/`GPOS` table, read off its bytes:
/// the header's ScriptList and FeatureList offsets, then each record's tag.
func layoutTableTags(_ table: Data) -> (scripts: Set<String>, features: Set<String>) {
    let bytes = [UInt8](table)
    func u16(_ offset: Int) -> Int {
        guard offset >= 0, offset + 1 < bytes.count else { return 0 }
        return Int(bytes[offset]) << 8 | Int(bytes[offset + 1])
    }
    func tag(_ offset: Int) -> String {
        guard offset >= 0, offset + 3 < bytes.count else { return "" }
        return String(decoding: bytes[offset..<(offset + 4)], as: UTF8.self)
    }
    var scripts: Set<String> = [], features: Set<String> = []
    let scriptList = u16(4), featureList = u16(6)
    for index in 0..<u16(scriptList) { scripts.insert(tag(scriptList + 2 + 6 * index)) }
    for index in 0..<u16(featureList) { features.insert(tag(featureList + 2 + 6 * index)) }
    return (scripts, features)
}
