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
    /// The face `descriptor` asks for (ruling TE-C item 1, TE-W): its
    /// `family` (`nil`: the system's default face) at its `size` in points,
    /// then the face of that family nearest its `weight`, then its italic
    /// face, and, for the system face, its `design`. A name that matches
    /// nothing substitutes a face; a weight, slope or design the family lacks
    /// keeps the face it has — nothing is synthesised. It never fails. The
    /// size must be finite and positive.
    func resolveFont(_ descriptor: FontDescriptor) -> FontKey

    /// `font`'s vertical metrics, in points (ruling TE-C item 2): the values
    /// `measure` and `placeGlyphs` lay lines out with.
    func fontMetrics(_ font: FontKey) -> TextFontMetrics

    /// `string` in `font`, wrapped at `width` points (`nil`: one line per hard
    /// break), laid out under `options` (ruling TE-C item 3): the widest kept
    /// (or truncated) line, and `kept lines × lineHeight`.
    func measure(_ string: String, font: FontKey, wrappingAt width: Double?,
                 options: TextLayoutOptions) -> TextMeasurement

    /// Every glyph of `string` in `font` wrapped at `width` under `options`, in
    /// a text box whose top-left is `origin` (points), placed at `scaleFactor`.
    func placeGlyphs(_ string: String, font: FontKey, wrappingAt width: Double?,
                     options: TextLayoutOptions,
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
    /// line; an empty string is one empty line. Under a line limit (ruling
    /// TE-C item 3), only the kept lines, the truncated last one standing for
    /// the whole rest of the string (its range runs to the string's end).
    func lineRanges(_ string: String, font: FontKey, wrappingAt width: Double?,
                    options: TextLayoutOptions) -> [Range<Int>]

    /// The coverage for `key` — a key this system placed.
    func rasterize(_ key: GlyphKey) -> GlyphImage

    /// Brackets one frame's text work, for per-frame caches.
    func beginFrame()
    func endFrame()
}

extension TextSystem {
    /// The face `family` names (`nil`: the system's default face) at `size`
    /// points — ``resolveFont(_:)`` with no weight, slope or design, the
    /// spelling every caller used before ruling TE-C.
    public func resolveFont(family: String?, size: Double) -> FontKey {
        resolveFont(FontDescriptor(family: family, size: size))
    }

    /// `measure` with no line limit, tail truncation and leading alignment —
    /// the spelling every caller used before ruling TE-C.
    public func measure(_ string: String, font: FontKey, wrappingAt width: Double?) -> TextMeasurement {
        measure(string, font: font, wrappingAt: width, options: TextLayoutOptions())
    }

    /// `placeGlyphs` under the default options (ruling TE-C).
    public func placeGlyphs(_ string: String, font: FontKey, wrappingAt width: Double?,
                            origin: (x: Double, y: Double), scaleFactor: Float) -> [TextGlyph] {
        placeGlyphs(string, font: font, wrappingAt: width, options: TextLayoutOptions(),
                    origin: origin, scaleFactor: scaleFactor)
    }

    /// `lineRanges` under the default options (ruling TE-C).
    public func lineRanges(_ string: String, font: FontKey, wrappingAt width: Double?) -> [Range<Int>] {
        lineRanges(string, font: font, wrappingAt: width, options: TextLayoutOptions())
    }
}

/// A system face's design (ruling TE-B item 1): SwiftUI's `Font.Design`
/// at the seam. CoreText answers it with the system font's design trait
/// (SF, New York, SF Rounded, SF Mono); the portable system with a family the
/// app registered for it (`PortableFontResolver.register(design:family:)`),
/// else the default face.
public enum FontDesign: Hashable, Sendable {
    case `default`, serif, rounded, monospaced
}

/// A font request at the seam (ruling TE-C item 1): a family (`nil`: the
/// system face), a size in points, and optionally a weight, a slope and — for
/// the system face only — a design.
///
/// `weight` is CoreText's weight-trait scale, −1…1 (SwiftUI's nine weights
/// are −0.8, −0.6, −0.4, 0, 0.23, 0.3, 0.4, 0.56, 0.62); `nil` asks for no
/// particular weight, so a named face keeps its own ("HelveticaNeue-Bold"
/// stays bold), where `0` asks for the family's regular face. A request is
/// not an identity: two descriptors can resolve to one ``FontKey``.
public struct FontDescriptor: Hashable, Sendable {
    /// The family or PostScript name; `nil` is the system font.
    public var family: String?
    /// The size in points.
    public var size: Double
    /// The weight trait, -1…1; `nil` keeps the face's own weight.
    public var weight: Double?
    /// Whether an italic face is requested.
    public var italic: Bool
    /// The system font's design (default, serif, rounded, monospaced).
    public var design: FontDesign

    /// A font request; only `size` is required.
    public init(family: String? = nil, size: Double, weight: Double? = nil,
                italic: Bool = false, design: FontDesign = .default) {
        self.family = family
        self.size = size
        self.weight = weight
        self.italic = italic
        self.design = design
    }
}

/// A face's vertical metrics at one size, in points (ruling TE-C item 2) —
/// `FontMetrics` on the CoreText path, `PortableFontMetrics` on the portable
/// one. `lineHeight` is `ceil(ascent + descent + leading)` on both (the line
/// advance every multi-line layout uses; divergence 86).
public struct TextFontMetrics: Hashable, Sendable {
    /// Distance from the baseline to the top of the line, in points.
    public let ascent: Double
    /// Distance from the baseline to the bottom of the line, in points.
    public let descent: Double
    /// Extra space between lines, in points.
    public let leading: Double
    /// The line advance, `ceil(ascent + descent + leading)` (divergence 86).
    public let lineHeight: Double

    /// Metrics from their four values.
    public init(ascent: Double, descent: Double, leading: Double, lineHeight: Double) {
        self.ascent = ascent
        self.descent = descent
        self.leading = leading
        self.lineHeight = lineHeight
    }
}

/// Which end of a line a truncation keeps (ruling TE-I): `.tail` keeps the
/// start, `.head` the end, `.middle` both ends — `CTLineTruncationType`'s
/// `.end`, `.start` and `.middle`.
public enum TextTruncation: Hashable, Sendable {
    case tail, head, middle
}

/// Where each line sits inside the text's box (ruling TE-J): left, centred or
/// right, by the line's width without its trailing whitespace.
public enum TextLineAlignment: Hashable, Sendable {
    case leading, center, trailing
}

/// How `measure`, `placeGlyphs` and `lineRanges` lay a string out beyond
/// wrapping (ruling TE-C item 3, amended by TE-T): at most `maxLines` lines
/// (`nil`: no limit; below 1 acts as 1), the last one truncated with `…`
/// (U+2026) in `truncation`'s mode when text is dropped at a definite width,
/// and each line aligned by `alignment`. The defaults — no limit, tail,
/// leading — lay out exactly as the spellings without `options:` always did.
public struct TextLayoutOptions: Hashable, Sendable {
    /// The most lines laid out; `nil` is unlimited.
    public var maxLines: Int?
    /// Where an over-long last line is cut and the ellipsis placed.
    public var truncation: TextTruncation
    /// How each line is aligned within the wrapping width.
    public var alignment: TextLineAlignment

    /// Layout options; the defaults lay out as the spellings without
    /// `options:`.
    public init(maxLines: Int? = nil, truncation: TextTruncation = .tail,
                alignment: TextLineAlignment = .leading) {
        self.maxLines = maxLines
        self.truncation = truncation
        self.alignment = alignment
    }
}

/// A measured string: its widest line and its total height, both in points.
public struct TextMeasurement: Sendable, Equatable {
    /// The widest line's width, in points.
    public let widestLine: Double
    /// The height of all lines together, in points.
    public let totalHeight: Double

    /// A measurement from its two values.
    public init(widestLine: Double, totalHeight: Double) {
        self.widestLine = widestLine
        self.totalHeight = totalHeight
    }
}

/// One placed glyph: the atlas key it rasterizes under (font, glyph, size,
/// subpixel variant, scale), the whole device pixel its pen sits on, and the
/// device row of its baseline — what `Frame.draw` turns into a sprite.
public struct TextGlyph: Sendable, Equatable {
    /// The atlas key of the glyph image to draw.
    public let key: GlyphKey
    /// The device pixel column the glyph's pen sits on.
    public let pixelX: Int
    /// The device pixel row of the glyph's baseline.
    public let baselineY: Int

    /// A placed glyph.
    public init(key: GlyphKey, pixelX: Int, baselineY: Int) {
        self.key = key
        self.pixelX = pixelX
        self.baselineY = baselineY
    }
}
