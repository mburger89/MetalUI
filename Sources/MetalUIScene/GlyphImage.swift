/// One glyph, rasterized into an 8-bit coverage bitmap.
///
/// **R8 coverage, not colour.** 0 is no ink, 255 is full ink; the renderer
/// multiplies it by the text colour (`monochromeSprite`, spec §7.1).
public struct GlyphImage: Sendable {
    public let width: Int
    public let height: Int

    /// Coverage, one byte per pixel, row-major, **row 0 is the TOP row**.
    ///
    /// That is `CGBitmapContext`'s own memory order on Apple platforms — its first byte is the
    /// image's top-left pixel even though its drawing origin is bottom-left —
    /// so these bytes reach an `MTLTexture` with no flip. ``GlyphAtlas`` blits
    /// them row by row and its ``GlyphAtlas/pixels`` inherit the convention.
    public let bytes: [UInt8]

    /// Device pixels from the pen origin **rightwards** to the bitmap's left
    /// edge. Negative for a glyph whose ink starts left of the pen, which is
    /// ordinary rather than exotic (an italic `f`, a combining mark).
    ///
    /// **This field and ``top`` are the only way to place the bitmap.** Their
    /// consumer is the glyph emitter: ``GlyphAtlas/packed(for:rasterize:)``
    /// copies both out of here and stores them beside the slot, and
    /// `MetalUI`'s `Frame.draw` builds an `MUIGlyph`'s destination origin from
    /// them. They are computed and stored here rather than left for the
    /// renderer to recompute because the rounding that produced
    /// ``width``/``height`` is the same rounding that produces these:
    /// re-deriving them from `CTFontGetBoundingRectsForGlyphs` at paint time is
    /// the exact mistake CLAUDE.md records for percentage insets — a second
    /// resolution of one quantity, free to disagree with the first.
    public let left: Int

    /// Device pixels from the baseline **upwards** to the bitmap's top edge.
    /// A y-down renderer places the bitmap's top at `baselineY - top`.
    public let top: Int

    /// Not public, following `ShapedLine`'s precedent: a `GlyphImage` whose
    /// `bytes` do not match its `width x height`, or whose bearings do not
    /// match its bitmap, is a lie the type exists to prevent, and only
    /// `GlyphRaster` (in `MetalUIText`) can make them agree. `package` because
    /// the type lives in `MetalUIScene` and its producer does not (ruling
    /// PS-E); no module outside this Swift package can call it, pinned by
    /// `anExternalModuleCannotMakeAGlyphImage`. A consumer outside the package
    /// calls `GlyphRaster.rasterize(glyph:font:subpixelVariant:scaleFactor:)`.
    package init(width: Int, height: Int, bytes: [UInt8], left: Int = 0, top: Int = 0) {
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
    package static let empty = GlyphImage(width: 0, height: 0, bytes: [])

    public var isEmpty: Bool { width == 0 || height == 0 }
}
