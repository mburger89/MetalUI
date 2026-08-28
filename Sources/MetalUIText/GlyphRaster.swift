import CoreText
import Foundation

/// One glyph, rasterized into an 8-bit coverage bitmap.
///
/// **R8 coverage, not colour.** 0 is no ink, 255 is full ink; the renderer
/// multiplies it by the text colour (`monochromeSprite`, spec §7.1).
public struct GlyphImage: Sendable {
    public let width: Int
    public let height: Int

    /// Coverage, one byte per pixel, row-major, **row 0 is the TOP row**.
    ///
    /// That is `CGBitmapContext`'s own memory order — its first byte is the
    /// image's top-left pixel even though its drawing origin is bottom-left —
    /// so these bytes reach an `MTLTexture` with no flip. ``GlyphAtlas`` blits
    /// them row by row and its ``GlyphAtlas/pixels`` inherit the convention.
    public let bytes: [UInt8]

    /// Device pixels from the pen origin **rightwards** to the bitmap's left
    /// edge. Negative for a glyph whose ink starts left of the pen, which is
    /// ordinary rather than exotic (an italic `f`, a combining mark).
    ///
    /// **This field and ``top`` are the only way to place the bitmap**, and
    /// nothing in `Sources/` reads them yet — the consumer is the
    /// `monochromeSprite` draw path. They are computed and stored here rather
    /// than left for the renderer to recompute because the rounding that
    /// produced ``width``/``height`` is the same rounding that produces these:
    /// re-deriving them from `CTFontGetBoundingRectsForGlyphs` at paint time is
    /// the exact mistake CLAUDE.md records for percentage insets — a second
    /// resolution of one quantity, free to disagree with the first.
    public let left: Int

    /// Device pixels from the baseline **upwards** to the bitmap's top edge.
    /// A y-down renderer places the bitmap's top at `baselineY - top`.
    public let top: Int

    /// Internal on purpose, following ``ShapedLine``'s precedent: a
    /// `GlyphImage` whose `bytes` do not match its `width x height`, or whose
    /// bearings do not match its bitmap, is a lie the type exists to prevent,
    /// and only ``GlyphRaster`` can make them agree. A consumer outside this
    /// module that needs one calls ``GlyphRaster/rasterize(glyph:font:subpixelVariant:scaleFactor:)``.
    init(width: Int, height: Int, bytes: [UInt8], left: Int = 0, top: Int = 0) {
        precondition(bytes.count == width * height,
                     "a GlyphImage's bytes must be exactly width x height")
        self.width = width
        self.height = height
        self.bytes = bytes
        self.left = left
        self.top = top
    }

    /// A glyph that covers no pixels — a space, or any glyph whose ink box is
    /// empty. **Not an error and not a failure to rasterize:** whitespace is
    /// the commonest glyph in a paragraph, so this is the ordinary path for it.
    static let empty = GlyphImage(width: 0, height: 0, bytes: [])

    public var isEmpty: Bool { width == 0 || height == 0 }
}

/// Turns a glyph into a CPU coverage bitmap with `CTFontDrawGlyphs`.
///
/// **No Metal, by design rather than by accident** (spec §3.1). This project
/// verifies headlessly — the layout corpus drives WebKit with no GPU and the
/// ABI probe *skips* without a Metal device — so a rasterizer or a packer
/// reachable only behind a `MTLDevice` would be code with no CI.
public enum GlyphRaster {
    /// How many fractional x-positions a glyph is rasterized at.
    ///
    /// **Spec §6.1: without subpixel positioning, spacing visibly wobbles
    /// during horizontal scroll** — every glyph's pen x is rounded to a whole
    /// device pixel, so the gaps between letters gain and lose a pixel as the
    /// text slides. Four variants put the residual error at 1/8 of a device
    /// pixel (see ``subpixelPlacement(forDeviceX:)``), which on a 2x display is
    /// 1/16 pt, at a cost of four atlas entries per glyph rather than one.
    public static let subpixelVariants = 4

    /// Splits a device-space pen position into the whole pixel to blit at and
    /// the rasterization variant that carries the remainder — §6.1's "pick
    /// nearest".
    ///
    /// `pixelX + variant / subpixelVariants` is the nearest representable
    /// position to `x`, so the residual is at most `1 / (2 * subpixelVariants)`
    /// of a device pixel. Note the carry: a fraction that rounds up to a whole
    /// pixel returns the **next** `pixelX` with variant 0, never a variant
    /// equal to ``subpixelVariants``, which would index a bitmap that is not
    /// rasterized.
    ///
    /// **No production caller yet** — the consumer is the `monochromeSprite`
    /// draw path, which is a later task. It lives here rather than there
    /// because it is the other half of ``rasterize(glyph:font:subpixelVariant:scaleFactor:)``'s
    /// `subpixelVariant` argument: without it that argument has no defined
    /// meaning, and a renderer would be free to invent a different one.
    public static func subpixelPlacement(forDeviceX x: Double) -> (pixelX: Int, variant: Int) {
        let whole = floor(x)
        let variant = Int(((x - whole) * Double(subpixelVariants)).rounded())
        if variant >= subpixelVariants { return (Int(whole) + 1, 0) }
        return (Int(whole), variant)
    }

    /// The horizontal offset, in **device pixels**, that `variant` rasterizes at.
    static func subpixelOffset(variant: Int) -> Double {
        Double(variant) / Double(subpixelVariants)
    }

    /// Device pixels of empty margin added on every side of the ink box.
    ///
    /// Antialiasing spreads coverage slightly beyond the outline's design
    /// bounding box, and `floor`/`ceil` alone would clip it. Pinned by
    /// `aRasterizedBitmapIsTightAroundItsInkAndDoesNotClipIt`, which asserts
    /// both halves — an empty outermost border (nothing clipped) *and* ink
    /// within two pixels of every edge (nothing wasted).
    ///
    /// It doubles as the atlas gutter. ``GlyphAtlas`` deliberately packs slots
    /// edge to edge: linear filtering at a sprite's boundary samples at most
    /// half a texel outside it, and this margin is already inside the slot, so
    /// a second gutter in the packer would be padding the padding.
    static let inkPadding = 1

    /// Rasterizes `glyph` from `font` at `scaleFactor` device pixels per point,
    /// shifted right by `subpixelVariant / subpixelVariants` of a device pixel.
    ///
    /// ## Grayscale antialiasing only
    ///
    /// Spec §6.1: macOS retired LCD subpixel antialiasing. The context is
    /// `DeviceGray` and font smoothing is switched off explicitly rather than
    /// left to the default, because the default is a *system setting* — a
    /// machine with LCD smoothing forced on would otherwise produce colour
    /// fringing baked into a single-channel bitmap, where two of the three
    /// channels are simply discarded.
    ///
    /// ## Colour glyphs are a recorded gap, not a handled case
    ///
    /// Spec §6.1 routes colour glyphs (emoji, `COLR`/`sbix`) to a **polychrome**
    /// atlas and skips tinting. There is no polychrome atlas in M2, and this
    /// function does not detect one either. **What an emoji does today is
    /// therefore specific and worth naming:** `CTFontDrawGlyphs` renders it into
    /// this `DeviceGray` context as a luminance silhouette, it packs into the R8
    /// atlas like any other glyph, and the renderer multiplies it by the text
    /// colour — so it paints as a flat monochrome blob in the text's colour
    /// rather than as an emoji. It is not blank and it does not trap, which is
    /// exactly why this comment exists: nothing in the repo can see it. The fix
    /// is a second atlas and a second draw path, not a branch here.
    public static func rasterize(glyph: CGGlyph, font: ResolvedFont,
                                 subpixelVariant: Int, scaleFactor: Float) -> GlyphImage {
        // Both bounds are closed by construction at the only production source
        // of these arguments: `subpixelPlacement(forDeviceX:)` carries rather
        // than returning `subpixelVariants`, and a scale factor is a window's
        // backing scale, which AppKit defines as positive. Neither is a value
        // layout can drive to a boundary, which is the distinction ruling TX-E
        // draws for the measure function's zero extent.
        precondition(subpixelVariant >= 0 && subpixelVariant < subpixelVariants,
                     "subpixel variant \(subpixelVariant) is outside 0..<\(subpixelVariants)")
        precondition(scaleFactor > 0, "a scale factor must be positive")

        let scale = Double(scaleFactor)
        let dx = subpixelOffset(variant: subpixelVariant)

        var g = glyph
        let ink = CTFontGetBoundingRectsForGlyphs(font.ctFont, .default, &g, nil, 1)
        // An empty rect is what CoreText reports for a glyph with no outline —
        // a space, and also what it returns for glyph 0 in some faces. `.isNull`
        // is checked as well as emptiness because CTFont reports failure that
        // way, and CGRect.null's coordinates are infinite: they would survive
        // the arithmetic below as an Int conversion trap.
        guard !ink.isNull, !ink.isEmpty else { return .empty }

        let pad = inkPadding
        let x0 = Int(floor(Double(ink.minX) * scale + dx)) - pad
        let y0 = Int(floor(Double(ink.minY) * scale)) - pad
        let x1 = Int(ceil(Double(ink.maxX) * scale + dx)) + pad
        let y1 = Int(ceil(Double(ink.maxY) * scale)) + pad
        let width = x1 - x0
        let height = y1 - y0
        guard width > 0, height > 0 else { return .empty }

        var bytes = [UInt8](repeating: 0, count: width * height)
        let drawn: Bool = bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else {
                // Unreachable for any argument this function can construct:
                // width and height are positive by the guard above and a
                // DeviceGray/8bpc/alpha-none combination is one CoreGraphics
                // supports. It is handled rather than force-unwrapped because
                // the API is optional, not because a case is expected — the
                // same shape as `FontResolver`'s UI-font fallback.
                return false
            }
            context.setShouldAntialias(true)
            context.setAllowsAntialiasing(true)
            // Grayscale AA only (§6.1), stated rather than inherited.
            context.setShouldSmoothFonts(false)
            context.setAllowsFontSmoothing(false)
            // Subpixel *quantization* is what would defeat this whole function:
            // it snaps the pen to a fraction CoreGraphics chooses, so every
            // variant would rasterize identically and the atlas would hold four
            // copies of one bitmap. Pinned by
            // `twoSubpixelVariantsRasterizeDifferentCoverage`.
            context.setAllowsFontSubpixelPositioning(true)
            context.setShouldSubpixelPositionFonts(true)
            context.setAllowsFontSubpixelQuantization(false)
            context.setShouldSubpixelQuantizeFonts(false)

            // The bitmap is black (0 = no coverage) and the glyph is painted
            // white, so a byte reads directly as coverage.
            context.setFillColor(gray: 1, alpha: 1)

            // User space is points; device space is pixels. A point p lands at
            // p * scale + (dx - x0) horizontally and p * scale - y0 vertically,
            // which puts the ink box's bottom-left corner `pad` pixels in from
            // the bitmap's bottom-left corner. `dx` is post-scale because a
            // subpixel offset is defined in device pixels.
            context.translateBy(x: CGFloat(dx - Double(x0)), y: CGFloat(-Double(y0)))
            context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))

            var origin = CGPoint.zero
            CTFontDrawGlyphs(font.ctFont, &g, &origin, 1, context)
            return true
        }
        guard drawn else { return .empty }

        return GlyphImage(width: width, height: height, bytes: bytes,
                          left: x0, top: y1)
    }
}
