import CoreText
import Foundation

/// What identifies one rasterized glyph bitmap, per spec §6.1.
///
/// Five components, and §6.1 chose each. Dropping any one collapses two
/// distinct bitmaps onto one slot, which paints the wrong glyph —
/// `everyComponentOfTheGlyphKeyDiscriminates` is what keeps none of them
/// quietly decorative.
///
/// - ``font`` — the identity of the **resolved** `CTFont`, never a family or
///   PostScript name. §6.1 measured why: requesting `"SFMono-Regular"` by name
///   on this machine returns a font whose PostScript name is `Helvetica`, so a
///   name-keyed atlas serves one face's images for another's outlines. See
///   ``FontKey``.
/// - ``glyph`` — the glyph id within that face.
/// - ``size`` — the point size. **This is deliberately redundant with
///   ``FontKey/size`` today, and the redundancy is the point.** Ruling TX-C
///   records that M5's linear-advance requirement is solved by carrying the
///   target size in the font *matrix*, under which `CTFontGetSize` reports the
///   reference size and `FontKey`'s size component stops discriminating. This
///   component is the one that survives that change.
/// - ``subpixelVariant`` — which of ``GlyphRaster/subpixelVariants`` fractional
///   x-offsets the bitmap was rasterized at. Without it, one bitmap serves all
///   four positions and text wobbles as it scrolls (§6.1).
/// - ``scaleFactor`` — device pixels per point. Without it a 1x bitmap is
///   served to a 2x display and the text is fuzzy — spec §4.2 names exactly
///   that symptom, and nothing in this repo can see it.
public struct GlyphKey: Hashable, Sendable {
    public let font: FontKey
    public let glyph: CGGlyph
    public let size: Double
    public let subpixelVariant: Int
    public let scaleFactor: Float

    public init(font: FontKey, glyph: CGGlyph, size: Double,
                subpixelVariant: Int, scaleFactor: Float) {
        self.font = font
        self.glyph = glyph
        self.size = size
        self.subpixelVariant = subpixelVariant
        self.scaleFactor = scaleFactor
    }
}

/// Where one glyph's bitmap sits in the atlas, in atlas pixels, y **down** —
/// the same convention as ``GlyphImage/bytes``.
public struct AtlasSlot: Hashable, Sendable {
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int

    /// Internal on purpose, for ``ShapedLine``'s reason: only ``GlyphAtlas``
    /// can make a slot's rectangle agree with the pixels actually written
    /// there, and a forged slot is a wrong-glyph bug that nothing in this repo
    /// can see. A consumer outside this module obtains one from
    /// ``GlyphAtlas/slot(for:rasterize:)``.
    init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// A CPU-side R8 glyph atlas with a shelf packer.
///
/// **Shelf packing**, not a full 2D bin packer: glyphs from one font at one
/// size have nearly uniform height, so a row-at-a-time packer wastes very
/// little and its state is three integers. It never revisits a closed shelf.
///
/// The bitmap lives in ``pixels`` and never touches Metal (spec §3.1); a
/// renderer uploads ``dirtyRect`` of it to an `MTLTexture`.
public final class GlyphAtlas {
    public let width: Int
    public let height: Int

    /// R8 coverage, row-major, `width` bytes per row, row 0 at the top.
    public private(set) var pixels: [UInt8]

    /// The region written since the last ``clearDirtyRect()``, or `nil` if
    /// nothing has been. The union of every slot filled in that period — a
    /// bounding box rather than a list, because the consumer is one
    /// `replaceRegion` call.
    public private(set) var dirtyRect: (x: Int, y: Int, width: Int, height: Int)?

    private var placed: [GlyphKey: AtlasSlot] = [:]

    /// The shelf packer's whole state. `shelfY` is the current shelf's top,
    /// `shelfHeight` the tallest glyph on it so far, `cursorX` the next free
    /// column on it.
    private var shelfY = 0
    private var shelfHeight = 0
    private var cursorX = 0

    public init(width: Int, height: Int) {
        precondition(width > 0 && height > 0, "an atlas must have a positive extent")
        self.width = width
        self.height = height
        self.pixels = [UInt8](repeating: 0, count: width * height)
    }

    /// The slot holding `key`'s bitmap, rasterizing and packing it on first
    /// request, or `nil` if the atlas has no room for it.
    ///
    /// `rasterize` is called **at most once per key** — that is the whole point
    /// of the cache, `CTFontDrawGlyphs` being far and away the expensive part
    /// of drawing text, and `theSameKeyReturnsTheSameSlotWithoutRasterizingTwice`
    /// is what pins it.
    ///
    /// A `nil` return is **not cached**: the atlas being full is a state that
    /// eviction is meant to relieve, so a key refused today must be free to
    /// succeed tomorrow.
    public func slot(for key: GlyphKey, rasterize: () -> GlyphImage) -> AtlasSlot? {
        if let existing = placed[key] { return existing }

        let image = rasterize()
        // A whitespace glyph occupies no pixels. It still gets a slot — an
        // empty one — so that the caller's lookup succeeds and `rasterize` is
        // not re-run for every space in a paragraph, which is the commonest
        // glyph there is. It touches neither the packer's state nor the dirty
        // rect, because a zero-area blit writes nothing.
        guard !image.isEmpty else {
            let empty = AtlasSlot(x: 0, y: 0, width: 0, height: 0)
            placed[key] = empty
            return empty
        }

        guard let slot = place(width: image.width, height: image.height) else { return nil }
        blit(image, into: slot)
        placed[key] = slot
        return slot
    }

    /// Forgets the dirty region, after a consumer has uploaded it.
    ///
    /// Without this the rect only ever grows, and a renderer re-uploads the
    /// whole of it every frame — which would still be *correct*, and is exactly
    /// the kind of silently-inert API this repo has been bitten by, so the
    /// resetting half is written now rather than assumed. Pinned by
    /// `theDirtyRectIsTheUnionOfWhatWasWrittenAndClears`.
    public func clearDirtyRect() {
        dirtyRect = nil
    }

    /// Finds room for a `width x height` bitmap and commits the packer to it.
    ///
    /// **Nothing is mutated on failure.** The atlas being full for a tall glyph
    /// does not mean it is full for a short one, and a packer that advanced its
    /// cursor before checking would leave a hole behind every refusal.
    private func place(width w: Int, height h: Int) -> AtlasSlot? {
        // Bigger than the atlas itself: no shelf can ever hold it, so this is
        // not the "try the next shelf" case below.
        guard w <= width, h <= height else { return nil }

        var x = cursorX
        var y = shelfY
        var shelf = shelfHeight
        if x + w > width {
            // The current shelf is full across. Open the next one *below the
            // whole of it* — below `shelfHeight`, not below this glyph — which
            // is the one arithmetic that keeps shelves from overlapping when
            // their glyphs differ in height.
            y = shelfY + shelfHeight
            x = 0
            shelf = 0
        }
        guard y + max(shelf, h) <= height else { return nil }

        cursorX = x + w
        shelfY = y
        shelfHeight = max(shelf, h)
        return AtlasSlot(x: x, y: y, width: w, height: h)
    }

    private func blit(_ image: GlyphImage, into slot: AtlasSlot) {
        for row in 0..<image.height {
            let source = row * image.width
            let destination = (slot.y + row) * width + slot.x
            pixels.replaceSubrange(destination..<(destination + image.width),
                                   with: image.bytes[source..<(source + image.width)])
        }
        markDirty(slot)
    }

    private func markDirty(_ slot: AtlasSlot) {
        guard let current = dirtyRect else {
            dirtyRect = (slot.x, slot.y, slot.width, slot.height)
            return
        }
        let minX = min(current.x, slot.x)
        let minY = min(current.y, slot.y)
        let maxX = max(current.x + current.width, slot.x + slot.width)
        let maxY = max(current.y + current.height, slot.y + slot.height)
        dirtyRect = (minX, minY, maxX - minX, maxY - minY)
    }
}
