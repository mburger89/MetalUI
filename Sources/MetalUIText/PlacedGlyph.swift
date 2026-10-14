import CoreText
import Foundation
import MetalUITextSystem

/// One glyph of a shaped text, resolved onto the **device pixel grid** and
/// ready to be looked up in a ``GlyphAtlas``.
///
/// **This is the seam that keeps CoreText out of `MetalUI` and Metal out of
/// `MetalUIText`.** Walking a `CTLine`'s runs, reading each glyph's pen
/// position and deciding which subpixel variant carries the remainder is
/// CoreText work, so it lives here; turning the answer into an `MUIGlyph` needs
/// the shader ABI, so that lives one module up. Neither module gains an import
/// it did not have.
///
/// **Not `Sendable`**, and by construction rather than by omission: ``font`` is
/// a ``ResolvedFont``, which wraps a `CTFont` and carries no such guarantee.
/// ``key`` is the `Sendable` half, exactly as it is on the shaping cache.
public struct PlacedGlyph {
    /// What the atlas is keyed on for this glyph, at this subpixel variant and
    /// this scale factor.
    public let key: GlyphKey

    /// The font of the **run** this glyph came from, which is not necessarily
    /// the font the text was shaped with: CoreText substitutes per run for a
    /// character the requested face has no glyph for. Rasterizing with the
    /// requested font instead would draw a glyph id from one face out of
    /// another face's outlines — the same class of error ``FontKey`` exists to
    /// prevent, arriving through the run rather than through the name.
    public let font: ResolvedFont

    /// The whole device pixel the bitmap is blitted at, from
    /// ``GlyphRaster/subpixelPlacement(forDeviceX:)``. The fraction that was
    /// dropped here is carried by ``GlyphKey/subpixelVariant`` instead, which
    /// is what stops the residual accumulating into visible wobble.
    public let pixelX: Int

    /// The glyph's baseline, in whole device pixels, y **down** from the text
    /// box's top edge plus whatever origin the caller supplied.
    public let baselineY: Int
}

/// What one shape's placement has read, computed and remembered (`HP-A`): a class so the `ShapedText`
/// struct stays a value and every copy shares it; it lives as long as the shape does (the shaping cache's
/// two-frame lifetime). The counters are work counters for pins, never time.
final class PlacementBox {
    /// One run of a line, read from CoreText once: its font, point size, glyph ids and pen positions.
    struct Run {
        let font: ResolvedFont
        let size: Double
        let glyphs: [CGGlyph]
        let positions: [CGPoint]
    }

    /// The memo's key: origin and scale by bit pattern, and the requested font (it decides the baseline
    /// arithmetic and which run fonts fall back to it).
    struct MemoKey: Equatable {
        let x: UInt64
        let y: UInt64
        let scale: UInt32
        let font: FontKey
    }

    /// Times a line's runs were read back from CoreText.
    var runReads = 0
    /// Times a whole placement pass ran (a memo miss).
    var placementsComputed = 0
    /// `GlyphKey`s built.
    var keysBuilt = 0
    /// Times a finished `StyledTextLayout` was built from the placed glyphs.
    var layoutsBuilt = 0
    /// Every line's runs, read once, for the font in `linesFont`.
    var lines: [[Run]]?
    var linesFont: FontKey?
    /// The finished placement at `memoKey`, one entry (a second origin in one frame replaces it).
    var memoKey: MemoKey?
    var memo: [PlacedGlyph] = []

    /// A styled shape's memo (`HP-D`): the placed glyphs and segments at one origin and scale, and the
    /// finished layout built from them by `owner` (which registers the glyphs' fonts), nil whenever the
    /// placement was recomputed.
    struct StyledKey: Equatable {
        let x: UInt64
        let y: UInt64
        let scale: UInt32
    }
    var styledKey: StyledKey?
    var styledPlaced: (glyphs: [(PlacedGlyph, Int)], segments: [TextRunSegment])?
    var layout: StyledTextLayout?
    weak var layoutOwner: AnyObject?
}

extension ShapedText {
    /// Every glyph of every line, placed on the device pixel grid.
    ///
    /// `origin` is the text box's top-left corner in **logical points**;
    /// `scaleFactor` is device pixels per point. `font` is the font the text was
    /// shaped with — ``ShapedText`` does not store it, and only its metrics are
    /// read here, for the baseline arithmetic that ``ShapedText/totalHeight``
    /// already uses (`lines.count × lineHeight`, spec §3.4). Each glyph is
    /// rasterized with its **run's** font instead; see ``PlacedGlyph/font``.
    ///
    /// ## The three quantities this resolves, and where each one came from
    ///
    /// - **The baseline of line `i`** is `origin.y + i × lineHeight + ascent`,
    ///   rounded to a whole device pixel. Rounded rather than carried
    ///   fractionally because a glyph bitmap is rasterized on the pixel grid
    ///   and blitted 1:1: a fractional vertical offset would resample every row
    ///   through the linear filter and soften the whole run. The horizontal
    ///   axis is *not* treated this way — that is what the subpixel variants
    ///   are for — and the asymmetry is CoreText's own, and gpui's: text moves
    ///   horizontally far more than it moves by fractions of a line.
    /// - **The pen x** is `origin.x + run position`, scaled, then split by
    ///   ``GlyphRaster/subpixelPlacement(forDeviceX:)`` into a whole pixel and
    ///   one of ``GlyphRaster/subpixelVariants`` variants.
    /// - **The point size in the key** is read off the *run's* font with
    ///   `CTFontGetSize`, not off `font`, for ``PlacedGlyph/font``'s reason.
    ///
    /// ## What this deliberately does not do
    ///
    /// **No direction handling beyond CoreText's own.** Every line starts at
    /// `origin.x` plus its ``ShapedText/lineOffsets`` entry — the alignment
    /// offset `Shaper.shape(_:font:wrappingAt:options:)` computed (ruling
    /// TE-J), 0 for every line of a leading layout — so a right-to-left
    /// paragraph lays its glyphs out correctly *within* the line (CoreText
    /// resolved that when it built the `CTLine`) and a leading line is still
    /// flush left (`EV-K`: `.leading` is the left edge).
    ///
    /// **No clipping to the box.** A caller that hands in a box narrower or
    /// shorter than the shape gets glyphs outside it, on purpose: clamping
    /// here would hide a layout defect inside paint, where nothing could see
    /// it. **This is what used to make CLAUDE.md's divergence 6 (ruling
    /// TX-H) visible for `Row { Text(long) }`** — an item's cross size was
    /// measured from its hypothetical main size rather than its used one, so
    /// a row shrunk narrower than one line still reported a one-line-tall
    /// box while its glyphs wrapped to three. The sizing milestone's Task 8
    /// fixed TX-H, so that particular composition no longer spills; the lack
    /// of clipping itself is unchanged and any other box narrower than its
    /// content still shows glyphs outside it.
    public func placedGlyphs(at origin: (x: Double, y: Double),
                             font: ResolvedFont,
                             scaleFactor: Float) -> [PlacedGlyph] {
        precondition(scaleFactor > 0, "a scale factor must be positive")
        let box = placement
        let key = PlacementBox.MemoKey(x: origin.x.bitPattern, y: origin.y.bitPattern,
                                       scale: scaleFactor.bitPattern, font: font.key)
        if box.memoKey == key { return box.memo }

        let scale = Double(scaleFactor)
        let runLines: [[PlacementBox.Run]]
        if let cached = box.lines, box.linesFont == font.key {
            runLines = cached
        } else {
            box.runReads += 1
            var all: [[PlacementBox.Run]] = []
            all.reserveCapacity(lines.count)
            for shapedLine in lines {
                var out: [PlacementBox.Run] = []
                // `CTLineGetGlyphRuns` is documented to return a CFArray of CTRun, so the cast cannot fail
                // for a `CTLine`; conditional rather than `as!` because a failed force cast would abort
                // inside paint, and no run at all is the same visible outcome as an empty line.
                if let runs = CTLineGetGlyphRuns(shapedLine.line) as? [CTRun] {
                    for run in runs {
                        let count = CTRunGetGlyphCount(run)
                        guard count > 0 else { continue }
                        let runFont = resolvedRunFont(of: run, fallingBackTo: font)
                        var glyphs = [CGGlyph](repeating: 0, count: count)
                        var positions = [CGPoint](repeating: .zero, count: count)
                        // A zero-length CFRange means "the whole run" for both calls.
                        CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
                        CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
                        out.append(PlacementBox.Run(font: runFont, size: Double(CTFontGetSize(runFont.ctFont)),
                                                    glyphs: glyphs, positions: positions))
                    }
                }
                all.append(out)
            }
            box.lines = all
            box.linesFont = font.key
            runLines = all
        }

        box.placementsComputed += 1
        var placed: [PlacedGlyph] = []
        placed.reserveCapacity(runLines.reduce(0) { $0 + $1.reduce(0) { $0 + $1.glyphs.count } })
        for (index, runs) in runLines.enumerated() {
            let baseline = origin.y
                + Double(index) * font.metrics.lineHeight
                + font.metrics.ascent
            let baselineY = Int((baseline * scale).rounded())
            let lineX = origin.x + lineOffsets[index]
            for run in runs {
                for i in 0..<run.glyphs.count {
                    let deviceX = (lineX + Double(run.positions[i].x)) * scale
                    let subpixel = GlyphRaster.subpixelPlacement(forDeviceX: deviceX)
                    // CoreText's run positions are y-**up** from the baseline (a superscript sits at a
                    // positive y), and every device coordinate here is y-down, so this subtracts.
                    let y = baselineY - Int((Double(run.positions[i].y) * scale).rounded())
                    box.keysBuilt += 1
                    placed.append(PlacedGlyph(
                        key: GlyphKey(font: run.font.key, glyph: run.glyphs[i], size: run.size,
                                      subpixelVariant: subpixel.variant, scaleFactor: scaleFactor),
                        font: run.font,
                        pixelX: subpixel.pixelX,
                        baselineY: y))
                }
            }
        }
        box.memoKey = key
        box.memo = placed
        return placed
    }
}

/// The font a run is actually drawn in.
///
/// `requested` is returned unchanged when the run carries the same `CTFont`,
/// which is the common case — one `Text`, one face, no fallback — and the
/// comparison is worth making because building a ``ResolvedFont`` reads a
/// `FontKey` and a `FontMetrics` back off CoreText, per run per frame.
///
/// The `nil` branch is CoreText's optionality rather than an expected case: a
/// run built from an attributed string that carries `kCTFontAttributeName`
/// always reports it back, and ``Shaper`` sets that attribute on every string
/// it typesets. It falls back to the requested font rather than trapping,
/// because a missing attribute would cost one run of slightly wrong glyph
/// images where a `preconditionFailure` costs the process.
private func resolvedRunFont(of run: CTRun, fallingBackTo requested: ResolvedFont)
    -> ResolvedFont {
    let attributes = CTRunGetAttributes(run) as NSDictionary
    guard let value = attributes[kCTFontAttributeName as String] else { return requested }
    let runFont = value as! CTFont
    if CFEqual(runFont, requested.ctFont) { return requested }
    return ResolvedFont(ctFont: runFont)
}
