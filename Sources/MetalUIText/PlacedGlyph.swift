import CoreText
import Foundation

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
    /// **No alignment and no direction handling beyond CoreText's own.** Every
    /// line starts at `origin.x`, so a right-to-left paragraph lays its glyphs
    /// out correctly *within* the line (CoreText resolved that when it built
    /// the `CTLine`) and the line itself is still flush left. `text-align` is
    /// not in M2's `Style` at all, so there is nothing to read; when it arrives
    /// it is a per-line x offset computed here from `advance` and the box
    /// width.
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
        let scale = Double(scaleFactor)
        var placed: [PlacedGlyph] = []

        for (index, shapedLine) in lines.enumerated() {
            let baseline = origin.y
                + Double(index) * font.metrics.lineHeight
                + font.metrics.ascent
            let baselineY = Int((baseline * scale).rounded())

            // `CTLineGetGlyphRuns` is documented to return a CFArray of CTRun,
            // so the cast cannot fail for a `CTLine`; it is written as a
            // conditional cast rather than `as!` because a failed force cast
            // here would be a process abort inside paint, and no run at all is
            // the same visible outcome as an empty line.
            guard let runs = CTLineGetGlyphRuns(shapedLine.line) as? [CTRun] else { continue }

            for run in runs {
                let count = CTRunGetGlyphCount(run)
                guard count > 0 else { continue }

                let runFont = resolvedRunFont(of: run, fallingBackTo: font)
                let size = Double(CTFontGetSize(runFont.ctFont))

                var glyphs = [CGGlyph](repeating: 0, count: count)
                var positions = [CGPoint](repeating: .zero, count: count)
                // A zero-length CFRange means "the whole run" for both calls.
                CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
                CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)

                for i in 0..<count {
                    let deviceX = (origin.x + Double(positions[i].x)) * scale
                    let placement = GlyphRaster.subpixelPlacement(forDeviceX: deviceX)
                    // CoreText's run positions are y-**up** from the baseline
                    // (a superscript sits at a positive y), and every device
                    // coordinate in this framework is y-down, so this subtracts.
                    // It is zero for every run M2 can produce — one font, one
                    // size, no attributed runs — and is written out rather than
                    // dropped because a dropped term is invisible until the
                    // first attributed string, which is M6.
                    let y = baselineY - Int((Double(positions[i].y) * scale).rounded())

                    placed.append(PlacedGlyph(
                        key: GlyphKey(font: runFont.key, glyph: glyphs[i], size: size,
                                      subpixelVariant: placement.variant,
                                      scaleFactor: scaleFactor),
                        font: runFont,
                        pixelX: placement.pixelX,
                        baselineY: y))
                }
            }
        }
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
