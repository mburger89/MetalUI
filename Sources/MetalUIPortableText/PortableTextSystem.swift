import MetalUIFreeType
import MetalUITextSystem

/// The portable path behind the ``TextSystem`` seam (ruling TS-C): fonts
/// from a ``PortableFontResolver``, wrapping from ``PortableText/lines(_:font:wrappingAt:)``,
/// placement from ``PortableText/emitLines`` (the same arithmetic, without
/// the atlas), and rasterization by FreeType — each measured equal to the
/// Apple path by its own oracle (`LB-`, `PT-`, `FN-`).
///
/// A thrown error below means a font file that opened and then failed to
/// shape, which no oracle has produced; it traps with the reason rather than
/// drawing nothing.
@MainActor
public final class PortableTextSystem: TextSystem {
    /// The resolver fonts are opened through.
    public let resolver: PortableFontResolver
    private var fonts: [FontKey: PortableFont] = [:]

    /// `(string, font, width, options)` — the options are part of the key
    /// (ruling TE-C item 3): a line limit or truncation mode is a different
    /// layout of the same string.
    private struct MeasureKey: Hashable {
        let string: String
        let font: FontKey
        let width: Double?
        let options: TextLayoutOptions
    }
    private var measurements = BoundedTable<MeasureKey, TextMeasurement>()
    /// The origin-free lines of a plain text (ruling GT-E), same key and same
    /// two-frame lifetime: a label that only moves places cached lines. Styled
    /// text is not cached here (ruling GT-H).
    private var layouts = BoundedTable<MeasureKey, [LaidOutLine]>()
    /// A styled text's measurement key (ruling RT-F item 5): the whole value,
    /// so two run splits of one string are two entries.
    private struct StyledKey: Hashable {
        let text: StyledText
        let width: Double?
        let options: TextLayoutOptions
    }
    private var styledMeasurements = BoundedTable<StyledKey, StyledTextMeasurement>()
    /// Styled measurements answered from an entry, and computed (ruling
    /// RT-F item 5) — what a warm styled frame is counted by.
    private(set) var styledHits = 0
    private(set) var styledMisses = 0
    /// The caret offsets of a string (`TS-F`), by `(string, font)`, on the same two-frame lifetime: a text field reads them in
    /// prepaint and in paint, and a key stroke changes the string once.
    private struct CaretKey: Hashable {
        let string: String
        let font: FontKey
    }
    private var caretOffsetsByString = BoundedTable<CaretKey, [Double]>()
    /// `PortableText.caretOffsets` calls this system made, and the lookups an entry answered.
    private(set) var caretMisses = 0
    private(set) var caretHits = 0
    private var generation = 0
    /// This frame's lookups for `METALUI_TRACE_SHAPING` (`TS-E`): a shape is a hit when a measurement or a laid-out line list
    /// answers, a miss when `PortableText.layOut` runs (the shaping), and a styled measure counts as the cache above does.
    private var trace = ShapingTrace.Recorder()
    /// `PortableText.layOut` calls this system made for plain text — what the
    /// layout cache (ruling GT-E) is counted by.
    private(set) var layOutCount = 0

    /// The portable text system over `resolver`'s registered fonts — HarfBuzz,
    /// FreeType and libunibreak, no CoreText (`TS-C`).
    public convenience init(resolver: PortableFontResolver) {
        self.init(resolver: resolver, entryLimit: TextCacheBudget.entries, costLimit: TextCacheBudget.cost)
    }

    /// A system with its own cache budget, for a test that has to cross it without laying out thousands of strings.
    init(resolver: PortableFontResolver, entryLimit: Int, costLimit: Int) {
        precondition(entryLimit > 0 && costLimit > 0, "a cache bound is positive")
        self.resolver = resolver
        self.entryLimit = entryLimit
        self.costLimit = costLimit
    }

    /// The budget the four cache tables share (`TS-F`).
    private let entryLimit: Int
    private let costLimit: Int

    /// Resolves `descriptor` against the registered fonts and returns its key.
    public func resolveFont(_ descriptor: FontDescriptor) -> FontKey {
        let font = trapping { try resolver.resolve(descriptor) }
        fonts[font.key] = font
        // A fallback's glyphs are keyed on the fallback's own face (FB-A).
        for fallback in font.fallbacks where fonts[fallback.key] == nil { fonts[fallback.key] = fallback }
        return font.key
    }

    /// The resolved font's metrics.
    public func fontMetrics(_ font: FontKey) -> TextFontMetrics {
        let portable = registered(font)
        let metrics = portable.metrics
        return TextFontMetrics(ascent: metrics.ascent, descent: metrics.descent, leading: metrics.leading,
                               lineHeight: metrics.lineHeight, capHeight: portable.capHeight)
    }

    /// Measures `string` wrapped at `width` (`nil` is one line per hard break)
    /// under `options`.
    public func measure(_ string: String, font: FontKey, wrappingAt width: Double?,
                        options: TextLayoutOptions) -> TextMeasurement {
        let key = MeasureKey(string: string, font: font, width: width, options: options)
        if let index = measurements.dict.index(forKey: key) {
            if ShapingTrace.active { trace.hit() }
            measurements.dict.values[index].generation = generation
            return measurements.dict.values[index].value
        }
        let portable = registered(font)
        let lines = laidOut(key, portable).map(\.line)
        let value = TextMeasurement(widestLine: lines.reduce(0) { max($0, $1.advance) },
                                    totalHeight: Double(lines.count) * portable.metrics.lineHeight)
        measurements.insert(key, value, generation: generation, cost: TextCacheBudget.overhead)
        trimInFrame()
        return value
    }

    /// The caret's x offset before each character and after the last (`TI-E`).
    ///
    /// Cached by `(string, font)` for the two frames a measurement is (`TS-F`); the empty string is `[0]` without a lookup.
    public func caretOffsets(_ string: String, font: FontKey) -> [Double] {
        guard !string.isEmpty else { return [0] }
        let key = CaretKey(string: string, font: font)
        if let index = caretOffsetsByString.dict.index(forKey: key) {
            caretHits += 1
            if ShapingTrace.active { trace.hit() }
            caretOffsetsByString.dict.values[index].generation = generation
            return caretOffsetsByString.dict.values[index].value
        }
        caretMisses += 1
        if ShapingTrace.active {
            trace.miss(ShapingTrace.quoted(string) + "(caretOffsets " + ShapingTrace.describe(font) + ")")
        }
        let offsets = trapping { try PortableText.caretOffsets(string, font: registered(font)) }
        caretOffsetsByString.insert(key, offsets, generation: generation, cost: TextCacheBudget.weight(of: string))
        trimInFrame()
        return offsets
    }

    /// Each display line's character range when `string` is wrapped at `width`.
    public func lineRanges(_ string: String, font: FontKey, wrappingAt width: Double?,
                           options: TextLayoutOptions) -> [Range<Int>] {
        let key = MeasureKey(string: string, font: font, width: width, options: options)
        return laidOut(key, registered(font)).map(\.line.range)
    }

    /// The glyphs of `string` laid out at `width`, placed on the device pixel
    /// grid.
    public func placeGlyphs(_ string: String, font: FontKey, wrappingAt width: Double?,
                            options: TextLayoutOptions,
                            origin: (x: Double, y: Double), scaleFactor: Float) -> [TextGlyph] {
        let portable = registered(font)
        let key = MeasureKey(string: string, font: font, width: width, options: options)
        let placements = PortableText.placements(of: laidOut(key, portable), font: portable, origin: origin,
                                                 wrappingAt: width, options: options, scaleFactor: scaleFactor)
        return placements.map { placement in
            let split = GlyphImage.subpixelPlacement(forDeviceX: placement.deviceX)
            return TextGlyph(key: GlyphKey(font: placement.font.key, glyph: placement.id, size: placement.font.size,
                                           subpixelVariant: split.variant, scaleFactor: scaleFactor),
                             pixelX: split.pixelX, baselineY: placement.baselineY)
        }
    }

    // MARK: Styled text (ruling RT-F)

    /// Measures `text` (rulings RT-F, RT-G, RT-H, RT-I), cached by the whole
    /// value under the same two-frame lifetime as plain measurements.
    public func measure(_ text: StyledText, wrappingAt width: Double?,
                        options: TextLayoutOptions) -> StyledTextMeasurement {
        let key = StyledKey(text: text, width: width, options: options)
        if let index = styledMeasurements.dict.index(forKey: key) {
            styledHits += 1
            if ShapingTrace.active { trace.hit() }
            styledMeasurements.dict.values[index].generation = generation
            return styledMeasurements.dict.values[index].value
        }
        styledMisses += 1
        if ShapingTrace.active { trace.miss(ShapingTrace.entry(text, width: width, options: options)) }
        let fonts = text.runs.map { registered($0.style.font) }
        let value = trapping {
            try PortableText.styledLines(text, fonts: fonts, wrappingAt: width, options: options).measurement
        }
        styledMeasurements.insert(key, value, generation: generation, cost: TextCacheBudget.overhead)
        trimInFrame()
        return value
    }

    /// Lays `text` out as ``measure(_:wrappingAt:options:)`` does and places
    /// every glyph, with its run, and every run segment.
    public func layOut(_ text: StyledText, wrappingAt width: Double?, options: TextLayoutOptions,
                       origin: (x: Double, y: Double), scaleFactor: Float) -> StyledTextLayout {
        let fonts = text.runs.map { registered($0.style.font) }
        if ShapingTrace.active { trace.bypass(ShapingTrace.entry(text, width: width, options: options)) }
        return trapping {
            try PortableText.styledLayout(text, fonts: fonts, wrappingAt: width, options: options, origin: origin,
                                          scaleFactor: scaleFactor)
        }
    }

    /// `font`'s `post` underline position and thickness and half its
    /// x-height, scaled `units × (size / unitsPerEm)` — `CTFontGetUnderlinePosition`'s
    /// numbers (ruling RT-J item 2, measured equal on the three test faces).
    public func decorationMetrics(_ font: FontKey) -> TextDecorationMetrics {
        let face = registered(font).raster
        let scale = face.size / Double(face.unitsPerEm)
        return TextDecorationMetrics(underlinePosition: Double(face.underlinePosition) * scale,
                                     underlineThickness: Double(face.underlineThickness) * scale,
                                     strikethroughPosition: Double(face.xHeight) * scale / 2)
    }

    /// Rasterizes the glyph `key` names with FreeType; an empty image if it
    /// cannot.
    public func rasterize(_ key: GlyphKey) -> GlyphImage {
        (try? FreeTypeRaster.rasterize(glyph: key.glyph, font: registered(key.font).raster,
                                       subpixelVariant: key.subpixelVariant,
                                       scaleFactor: key.scaleFactor)) ?? .empty
    }

    /// Starts a frame for the cache's sweep bookkeeping.
    public func beginFrame() { generation += 1 }

    /// Drops measurements no frame has asked for since the previous one — the
    /// same two-frame lifetime `ShapingCache` gives its entries.
    public func endFrame() {
        if ShapingTrace.active { trace.finish(frame: generation, system: "portable") }
        let cutoff = generation - 1
        measurements.removeOlder(than: cutoff)
        layouts.removeOlder(than: cutoff)
        styledMeasurements.removeOlder(than: cutoff)
        caretOffsetsByString.removeOlder(than: cutoff)
        bound(inFrame: false)
    }

    /// The entries and weight the four tables hold together, against `TextCacheBudget` (`TS-F`): the two-frame lifetime
    /// alone lets a frame that looked up a great deal of text keep all of it for the next.
    private var heldEntries: Int { measurements.count + layouts.count + styledMeasurements.count + caretOffsetsByString.count }
    private var heldCost: Int { measurements.cost + layouts.cost + styledMeasurements.cost + caretOffsetsByString.cost }

    /// Inside a frame an eviction runs once the tables are a quarter over the budget.
    private func trimInFrame() {
        if heldEntries > TextCacheBudget.inFrameLimit(entryLimit) || heldCost > TextCacheBudget.inFrameLimit(costLimit) { bound(inFrame: true) }
    }

    /// Evicts the least recently touched entries, oldest generation first, until the tables fit the budget.
    private func bound(inFrame: Bool) {
        let current = inFrame ? generation : nil
        var stamps: [(generation: Int, cost: Int)] = []
        stamps.reserveCapacity(heldEntries)
        measurements.appendStamps(to: &stamps, inFrame: current)
        layouts.appendStamps(to: &stamps, inFrame: current)
        styledMeasurements.appendStamps(to: &stamps, inFrame: current)
        caretOffsetsByString.appendStamps(to: &stamps, inFrame: current)
        guard let cut = TextCacheBudget.cut(&stamps, entries: entryLimit, cost: costLimit) else { return }
        let share = TextCacheBudget.shares(of: cut.allowance, among: [
            measurements.count(atRank: cut.generation, inFrame: current), layouts.count(atRank: cut.generation, inFrame: current),
            styledMeasurements.count(atRank: cut.generation, inFrame: current), caretOffsetsByString.count(atRank: cut.generation, inFrame: current)])
        measurements.evict(olderThan: cut.generation, inFrame: current, andUpTo: share[0])
        layouts.evict(olderThan: cut.generation, inFrame: current, andUpTo: share[1])
        styledMeasurements.evict(olderThan: cut.generation, inFrame: current, andUpTo: share[2])
        caretOffsetsByString.evict(olderThan: cut.generation, inFrame: current, andUpTo: share[3])
    }

    /// Entry count of all four tables, for tests.
    var heldEntryCount: Int { heldEntries }

    /// The entries and weight the last finished frame touched, for tests and probes.
    package func liveSet() -> (entries: Int, cost: Int) {
        let tables = [measurements.live(in: generation), layouts.live(in: generation),
                      styledMeasurements.live(in: generation), caretOffsetsByString.live(in: generation)]
        return (tables.reduce(0) { $0 + $1.entries }, tables.reduce(0) { $0 + $1.cost })
    }

    /// The origin-free lines of `key`'s string.
    private func laidOut(_ key: MeasureKey, _ portable: PortableFont) -> [LaidOutLine] {
        if let index = layouts.dict.index(forKey: key) {
            if ShapingTrace.active { trace.hit() }
            layouts.dict.values[index].generation = generation
            return layouts.dict.values[index].value
        }
        layOutCount += 1
        if ShapingTrace.active {
            trace.miss(ShapingTrace.entry(key.string, font: key.font, width: key.width, options: key.options))
        }
        let lines = trapping {
            try PortableText.layOut(key.string, font: portable, wrappingAt: key.width, options: key.options)
        }
        layouts.insert(key, lines, generation: generation, cost: TextCacheBudget.weight(of: key.string))
        trimInFrame()
        return lines
    }

    private func registered(_ key: FontKey) -> PortableFont {
        guard let font = fonts[key] else {
            preconditionFailure("PortableTextSystem: \(key) was not resolved by this text system")
        }
        return font
    }

    private func trapping<T>(_ body: () throws -> T) -> T {
        do { return try body() } catch {
            preconditionFailure("PortableTextSystem: \(error)")
        }
    }
}
