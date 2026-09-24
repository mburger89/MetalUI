@_exported import MetalUIScene

/// What `Text` and `ProposalText` need from a text engine, and nothing more
/// (ruling TS-A): resolve a font, measure a string, place its glyphs, and
/// rasterize one glyph. Two implementations exist — `MetalUIText`'s
/// `CoreTextTextSystem` (CoreText, the Apple path) and `MetalUIPortableText`'s
/// `PortableTextSystem` (HarfBuzz, FreeType, libunibreak) — and an app uses
/// **one**, chosen when its window is made, never per element.
///
/// Fonts are named by their resolved ``FontKey``, never by the request: two
/// requests that resolve to one face are one font (the `FontKey` rule).
@MainActor
public protocol TextSystem: AnyObject, Sendable {
    /// The face `family` names (`nil`: the system's default face) at `size`
    /// points. A name that matches nothing substitutes a face; it never fails.
    /// `size` must be finite and positive.
    func resolveFont(family: String?, size: Double) -> FontKey

    /// `string` in `font`, wrapped at `width` points (`nil`: one line per hard
    /// break).
    func measure(_ string: String, font: FontKey, wrappingAt width: Double?) -> TextMeasurement

    /// CSS's min-content width: the widest unbreakable run, each on a line of
    /// its own (TX-F).
    func minContentWidth(_ string: String, font: FontKey) -> Double

    /// Every glyph of `string` in `font` wrapped at `width`, in a text box
    /// whose top-left is `origin` (points), placed at `scaleFactor`.
    func placeGlyphs(_ string: String, font: FontKey, wrappingAt width: Double?,
                     origin: (x: Double, y: Double), scaleFactor: Float) -> [TextGlyph]

    /// The x offset, in points from the line's start, of every grapheme
    /// boundary of `string` laid out as ONE unwrapped line: `string.count + 1`
    /// values, the first 0, in logical order (ruling TI-E). A caret before
    /// grapheme `i` sits at `offsets[i]`; the last value is the line's width,
    /// `measure(string, font:, wrappingAt: nil).widestLine` for a string with
    /// no hard break. CoreText's answers are the contract: a caret between a
    /// kerned pair sits halfway through the kern, and one inside a ligature
    /// at the face's ligature caret, or at an even split without one. An
    /// empty string is `[0]`. Bidirectional carets are out of scope: for
    /// right-to-left text the values are only specified to be `count + 1`
    /// from 0 (the portable system sums logical advances; CoreText answers
    /// its line's own offsets).
    func caretOffsets(_ string: String, font: FontKey) -> [Double]

    /// The display lines `measure` and `placeGlyphs` break `string` into at
    /// `width` (ruling TI-H), as UTF-16 ranges into `string`, each with its
    /// trailing whitespace and hard break — `CTLineGetStringRange`'s ranges.
    /// `nil` is one line per hard break; a trailing hard break opens no empty
    /// line; an empty string is one empty line.
    func lineRanges(_ string: String, font: FontKey, wrappingAt width: Double?) -> [Range<Int>]

    /// The coverage for `key` — a key this system placed.
    func rasterize(_ key: GlyphKey) -> GlyphImage

    /// Brackets one frame's text work, for per-frame caches.
    func beginFrame()
    func endFrame()
}

/// A measured string: its widest line and its total height, both in points.
public struct TextMeasurement: Sendable, Equatable {
    public let widestLine: Double
    public let totalHeight: Double

    public init(widestLine: Double, totalHeight: Double) {
        self.widestLine = widestLine
        self.totalHeight = totalHeight
    }
}

/// One placed glyph: the atlas key it rasterizes under (font, glyph, size,
/// subpixel variant, scale), the whole device pixel its pen sits on, and the
/// device row of its baseline — what `Frame.draw` turns into a sprite.
public struct TextGlyph: Sendable, Equatable {
    public let key: GlyphKey
    public let pixelX: Int
    public let baselineY: Int

    public init(key: GlyphKey, pixelX: Int, baselineY: Int) {
        self.key = key
        self.pixelX = pixelX
        self.baselineY = baselineY
    }
}
