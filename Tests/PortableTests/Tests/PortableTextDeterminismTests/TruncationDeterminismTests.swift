// TE-C item 3, TE-T (spec row 1.11): a line limit's truncation and each line
// alignment through `emitLines(options:)` — rects, height, atlas dirty rect
// and coverage — RECORDED on macOS by `METALUI_PORTABLE_RECORD=1 swift test`
// here and pasted into `ExpectedTruncation.swift`. The oracle that says the
// numbers are right is the root package's `TruncationOracleTests` and
// `TextSystemSeamTests` (1.5–1.7), which compare the same layouts against
// CoreText's truncated line on macOS; this asserts only that they do not move
// on Linux and Windows.

import Foundation
import MetalUIPortableText
import MetalUIScene
import MetalUIShaderTypes
import MetalUITextSystem
import Testing

struct TruncationCase: CustomStringConvertible {
    let text: String, size: Double, width: Double, scale: Float, options: TextLayoutOptions
    var description: String {
        "\(size)pt ×\(scale) w=\(width) maxLines=\(options.maxLines.map(String.init) ?? "nil") "
            + "\(options.truncation) \(options.alignment) \(text.debugDescription)"
    }
}

let alphaBeta = "Alpha beta gamma delta epsilon zeta eta theta"
let quickFox = "The quick brown fox jumps over the lazy dog, twice over."

/// Row 1.6's three modes, row 1.7's alignments at both scales, and TE-T's
/// paragraph rule (a hard break in the rest) — all Noto Sans.
let truncationCorpus: [TruncationCase] = [
    TruncationCase(text: alphaBeta, size: 13, width: 100, scale: 1, options: TextLayoutOptions(maxLines: 2, truncation: .tail)),
    TruncationCase(text: alphaBeta, size: 13, width: 100, scale: 1, options: TextLayoutOptions(maxLines: 2, truncation: .head)),
    TruncationCase(text: alphaBeta, size: 13, width: 100, scale: 1, options: TextLayoutOptions(maxLines: 2, truncation: .middle)),
    TruncationCase(text: quickFox, size: 15, width: 100, scale: 1,
                   options: TextLayoutOptions(maxLines: 2, alignment: .center)),
    TruncationCase(text: quickFox, size: 15, width: 100, scale: 2,
                   options: TextLayoutOptions(maxLines: 3, truncation: .middle, alignment: .trailing)),
    TruncationCase(text: "Ready\nSet\nGo", size: 13, width: 100, scale: 2,
                   options: TextLayoutOptions(maxLines: 2, alignment: .center)),
]

func pinTruncation(_ truncationCase: TruncationCase,
                   font given: PortableFont? = nil) throws -> (pinned: PinnedEmit, lines: Int) {
    let font = try given ?? PortableFont(data: fontBytes(notoSans), size: truncationCase.size)
    let atlas = GlyphAtlas(width: atlasSide, height: atlasSide)
    var scene = Scene()
    let mask = MUIBounds(origin: MUIPoint(x: 0, y: 0), size: MUISize(width: 4096, height: 4096))
    atlas.beginFrame()
    let paragraph = try PortableText.emitLines(truncationCase.text, font: font, origin: (3.3, 7.6),
                                               wrappingAt: truncationCase.width, scaleFactor: truncationCase.scale,
                                               color: MUIHsla(h: 0, s: 0, l: 1, a: 1), contentMask: mask,
                                               options: truncationCase.options, into: &scene, atlas: atlas)
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

@Suite struct TruncationDeterminismTests {
    @Test func truncatedAndAlignedEmissionIsByteIdentical() throws {
        try #require(expectedTruncations.count == truncationCorpus.count,
                     "\(expectedTruncations.count) recorded rows for \(truncationCorpus.count) cases")
        for (index, truncationCase) in truncationCorpus.enumerated() {
            let got = try pinTruncation(truncationCase).pinned
            #expect(got == expectedTruncations[index],
                    "\(truncationCase): measured \(got), recorded on macOS \(expectedTruncations[index])")
        }
    }

    /// **1.12** (plan task 11 part 1, lane 2; ruling TE-C item 1): a bold
    /// italic request on a resolver whose Noto Sans has only its Regular face
    /// (beside two other families' regular faces) selects that face and emits
    /// row 0's recorded bytes exactly — no other family's face, no
    /// synthesis, on every platform CI runs.
    @Test func aWeightedRequestOnARegularOnlyResolverEmitsTheRegularFaceByteIdentically() throws {
        try #require(!expectedTruncations.isEmpty)
        let resolver = try PortableFontResolver(defaultFont: fontBytes(notoSans))
        try resolver.register(fontBytes("SourceSans3-Regular.otf"))
        try resolver.register(fontBytes("NotoSansArabic-Regular.ttf"))
        for weight in [0.4, 0.62, -0.4] {
            let font = try resolver.resolve(FontDescriptor(family: "Noto Sans", size: truncationCorpus[0].size,
                                                           weight: weight, italic: true))
            #expect(font.key.postScriptName == "NotoSans-Regular", "weight \(weight)")
            #expect(try pinTruncation(truncationCorpus[0], font: font).pinned == expectedTruncations[0],
                    "weight \(weight)")
        }
    }

    @Test(.enabled(if: recording, "set METALUI_PORTABLE_RECORD=1 to print the expected values"))
    func record() throws {
        var lines = ["let expectedTruncations: [PinnedEmit] = ["]
        for truncationCase in truncationCorpus {
            let (pinned, count) = try pinTruncation(truncationCase)
            try #require(count >= 2 && pinned.glyphs > 5 && pinned.dirty.count == 4,
                         "\(truncationCase) measured nothing")
            lines.append("    PinnedEmit(glyphs: \(pinned.glyphs), rects: \(hex(pinned.rects)), advance: \(hex(pinned.advance)), "
                         + "dirty: \(pinned.dirty), coverage: \(hex(pinned.coverage))),  // \(truncationCase)")
        }
        lines.append("]")
        print(lines.joined(separator: "\n"))
    }
}
