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
    /// The resolved font the glyph comes from.
    public let font: FontKey
    /// A glyph id in ``font`` (`CGGlyph` on Apple platforms, which is this
    /// same `UInt16`; ruling PS-C).
    public let glyph: UInt16
    /// The size in points.
    public let size: Double
    /// Which subpixel horizontal offset the glyph is rasterized at.
    public let subpixelVariant: Int
    /// Device pixels per point the glyph is rasterized for.
    public let scaleFactor: Float

    /// The five components hashed once, at the only initialiser (`HP-B`).
    ///
    /// **Why it is stored.** The atlas probes a `GlyphKey` for every glyph of every visible `Text` on
    /// every built frame; a synthesized `hash(into:)` SipHashed the five components (and the font's
    /// own stored hash) each time. This is `FontKey`'s pattern: a fast reject for `==`, never a proof of
    /// equality, and `hash(into:)` feeds this one `Int`.
    ///
    /// **The mix is a chain of bijections** (xor, multiply by an odd constant, xorshift), so two keys that
    /// differ in exactly one component always store different hashes - deterministic, which is what
    /// `aGlyphKeyHashesFromItsStoredHashAndComparesEqualByFields` reads back. No `Hasher` and no
    /// Foundation (`PS-A`). `size` and `scaleFactor` enter by bit pattern with `-0.0` normalised to
    /// `0.0`, because `==` is IEEE on both (a NaN is unequal to itself and hashes however it likes).
    ///
    /// `package` so the test can read it back and forge a collision; pinned unreachable from outside the
    /// package by guard HP.1.
    package let precomputedHash: Int

    /// A glyph key.
    public init(font: FontKey, glyph: UInt16, size: Double,
                subpixelVariant: Int, scaleFactor: Float) {
        self.font = font
        self.glyph = glyph
        self.size = size
        self.subpixelVariant = subpixelVariant
        self.scaleFactor = scaleFactor
        var state = UInt64(bitPattern: Int64(font.precomputedHash))
        func step(_ value: UInt64) {
            state = (state ^ value) &* 0x9E37_79B9_7F4A_7C15
            state ^= state >> 32
        }
        step(UInt64(glyph))
        step((size + 0.0).bitPattern)
        step(UInt64(bitPattern: Int64(subpixelVariant)))
        step(UInt64((scaleFactor + 0.0).bitPattern))
        self.precomputedHash = Int(bitPattern: UInt(state))
    }

    /// **All five components decide; ``precomputedHash`` only rejects early** (`FontKey.==`'s contract:
    /// safe alone, unsafe together). `aGlyphKeyHashesFromItsStoredHashAndComparesEqualByFields` forges a
    /// collision per component and needs `==` to settle it on the fields.
    public static func == (lhs: GlyphKey, rhs: GlyphKey) -> Bool {
        lhs.precomputedHash == rhs.precomputedHash
            && lhs.glyph == rhs.glyph
            && lhs.subpixelVariant == rhs.subpixelVariant
            && lhs.size == rhs.size
            && lhs.scaleFactor == rhs.scaleFactor
            && lhs.font == rhs.font
    }

    /// Feeds ``precomputedHash`` alone.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(precomputedHash)
    }
}

/// Where one glyph's bitmap sits in the atlas, in atlas pixels, y **down** —
/// the same convention as ``GlyphImage/bytes``.
public struct AtlasSlot: Hashable, Sendable {
    /// The slot's left edge.
    public let x: Int
    /// The slot's top edge.
    public let y: Int
    /// The slot's width.
    public let width: Int
    /// The slot's height.
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

/// A glyph's whole placement: where its bitmap sits in the atlas, and how that
/// bitmap sits relative to the pen.
///
/// **The two halves travel together because they were produced together.**
/// ``AtlasSlot`` is the packer's answer; ``left`` and ``top`` are copies of
/// ``GlyphImage/left`` and ``GlyphImage/top``, carried out of the `rasterize`
/// closure so that a caller which *hits* the cache gets them too. Without this
/// the only route to a bearing on a cache hit is to rasterize the glyph again
/// or to re-derive it from `CTFontGetBoundingRectsForGlyphs` at paint time —
/// and the second is the mistake CLAUDE.md's percentage-inset constraint
/// records, a quantity resolved twice and free to disagree with itself.
public struct PackedGlyph: Hashable, Sendable {
    /// Where the bitmap is, in atlas pixels.
    public let slot: AtlasSlot

    /// See ``GlyphImage/left`` — device pixels from the pen origin rightwards
    /// to the bitmap's left edge, and negative for a glyph whose ink starts
    /// left of the pen.
    public let left: Int

    /// See ``GlyphImage/top`` — device pixels from the baseline upwards to the
    /// bitmap's top edge. A y-down renderer places the bitmap's top at
    /// `baselineY - top`.
    public let top: Int
}

/// A CPU-side R8 glyph atlas with a shelf packer.
///
/// **Shelf packing**, not a full 2D bin packer: glyphs from one font at one
/// size have nearly uniform height, so a row-at-a-time packer wastes very
/// little and its state is three integers. It never revisits a closed shelf.
///
/// **Space is recovered in two ways, and neither moves a glyph that a frame in
/// flight already holds a rect for** (`GL-A`, `GL-B`):
///
/// - **Growth, inside a frame.** When a glyph does not fit and the atlas is
///   below ``maximumExtent``, ``packed(for:rasterize:)`` doubles the atlas.
///   Every existing slot keeps its pixel coordinates (only the row stride of
///   ``pixels`` changes), so a rect emitted earlier in the same frame, and a
///   retained record from an earlier frame, stay correct. A renderer sees a new
///   ``width`` or ``height`` and uploads the whole of it.
/// - **A rebuild, between frames.** ``reclaim()`` empties the packer and the
///   pixels and bumps ``layoutGeneration``; every glyph is rasterized again on
///   demand, in paint order. ``wantsReclaim`` says when. It may only run when
///   no frame is being built, and every holder of a slot from before it must
///   miss: a retained record keys on ``layoutGeneration``.
///
/// Past ``maximumExtent`` a glyph that does not fit is dropped and
/// ``droppedGlyphs`` counts it.
///
/// The bitmap lives in ``pixels`` and never touches Metal (spec §3.1); a
/// renderer uploads ``dirtyRects`` of it to an `MTLTexture`.
public final class GlyphAtlas {
    /// The atlas width in pixels. Changes only when the atlas grows or is
    /// rebuilt at another size; read it again for every frame.
    public private(set) var width: Int
    /// The atlas height in pixels. See ``width``.
    public private(set) var height: Int

    /// The side, in pixels, the atlas never grows beyond (`GL-C`). An atlas
    /// made without one is exactly as large as it was made and never grows, so
    /// every user that predates growth keeps its packer geometry.
    public let maximumExtent: Int

    /// The width and height the atlas was made with: what ``reclaim()`` never
    /// shrinks below.
    public let initialWidth: Int
    /// See ``initialWidth``.
    public let initialHeight: Int

    /// Advances every time ``reclaim()`` empties the atlas, starting at 0.
    ///
    /// **This is the key a holder of a slot checks** (`GL-D`): a retained paint
    /// record, a transition ghost, a drag snapshot and a raster key all carry
    /// atlas rects, and a rect from generation N names a different glyph, or
    /// none, in generation N+1. Growth does not advance it (growth moves
    /// nothing). Distinct from ``currentGeneration``, which counts frames.
    public private(set) var layoutGeneration = 0

    /// How many times the atlas has doubled (`GL-B`).
    public private(set) var growCount = 0

    /// How many times ``reclaim()`` has run (`GL-A`).
    public private(set) var reclaimCount = 0

    /// How many ``packed(for:rasterize:)`` requests were refused for want of
    /// room, after growth was exhausted (`GL-E`). Counts requests, not distinct
    /// glyphs: a glyph that does not fit is asked for again by every frame that
    /// draws it. Zero for as long as nothing is dropped; never reset.
    public private(set) var droppedGlyphs = 0

    /// Whether a refusal happened while older glyphs held room a rebuild would
    /// free (`GL-A`): the frame that dropped is missing glyphs, and the next one
    /// need not be. Cleared by ``reclaim()``. A window that sees it set after a
    /// frame asks for one more frame; it is false for a refusal that nothing
    /// could have avoided, so that request cannot repeat forever.
    public private(set) var reclaimRequested = false

    /// Pixels packed since the last rebuild (zero-area glyphs add none).
    private var packedArea = 0
    /// Pixels of the glyphs used since the last ``beginFrame()``, counted once each.
    private var frameLiveArea = 0
    /// Pixels of the glyphs refused since the last ``beginFrame()``.
    private var frameDroppedArea = 0

    /// R8 coverage, row-major, `width` bytes per row, row 0 at the top.
    public private(set) var pixels: [UInt8]

    /// The regions written since the last ``clearDirtyRect()``, empty if nothing has been: a short
    /// list a renderer uploads one `replace(region:)` (or one transfer) at a time, so two first-use
    /// glyphs on distant shelves upload their own areas and not the span between them (`RG-H`).
    ///
    /// A slot extends the last rect when it is on the same shelf row and starts exactly where that
    /// rect ends (the rect's height is the larger of the two); any other slot is a new rect. **At
    /// most eight rects**: the ninth collapses the list to its bounding rect, and from then on every
    /// slot unions into that one rect until ``clearDirtyRect()`` (the list never re-grows after a
    /// collapse within a frame, so it is always a superset of what was written, `RG-I`). The rects
    /// never overlap except through that collapse. ``dirtyRect`` is their union.
    public private(set) var dirtyRects: [(x: Int, y: Int, width: Int, height: Int)] = []

    /// The most rects ``dirtyRects`` holds before it collapses to one bounding rect.
    private static let dirtyRectCap = 8

    /// Whether ``dirtyRects`` has collapsed since the last clear (`RG-I`).
    private var dirtyRectsCollapsed = false

    /// The region written since the last ``clearDirtyRect()``, or `nil` if
    /// nothing has been: the bounding box (union) of ``dirtyRects``. Kept for
    /// readers that want one rectangle.
    public var dirtyRect: (x: Int, y: Int, width: Int, height: Int)? {
        guard var union = dirtyRects.first else { return nil }
        var maxX = union.x + union.width
        var maxY = union.y + union.height
        for rect in dirtyRects.dropFirst() {
            union.x = min(union.x, rect.x)
            union.y = min(union.y, rect.y)
            maxX = max(maxX, rect.x + rect.width)
            maxY = max(maxY, rect.y + rect.height)
        }
        return (union.x, union.y, maxX - union.x, maxY - union.y)
    }

    /// One placed glyph and the generation it was last handed back in.
    ///
    /// **The generation lives beside the glyph, in the one dictionary, rather
    /// than in a second dictionary keyed on the same `GlyphKey`.** A cache hit
    /// is the per-glyph, per-frame path — every glyph of every visible `Text`
    /// on every built frame — and a second dictionary cost it a second full
    /// hash of a `String`-bearing key, only so that ``wantsReclaim`` could read it. This is a private
    /// wrapper rather than a field on ``PackedGlyph`` or ``AtlasSlot`` because
    /// both of those are public and compared in tests against packer geometry
    /// and bearings alone.
    private struct Placement {
        let glyph: PackedGlyph
        var generation: Int
    }

    /// ``Placement/generation`` is the only per-glyph state the rebuild policy
    /// reads (through ``frameLiveArea``). Pinned structurally by
    /// `theGenerationLivesInTheOneDictionaryThatHoldsTheGlyph`.
    private var placed: [GlyphKey: Placement] = [:]

    /// True for the duration of one frame's scene construction — the same shape
    /// as `LayoutTree.isLayingOut`. ``reclaim()`` traps while this is
    /// true: emptying a slot the frame in flight may still hold an `AtlasSlot`
    /// for produces a wrong glyph or a blank, on that one frame, intermittently
    /// (spec §3.5) — the hardest failure in this milestone to reproduce, and
    /// nothing in this repo can see a wrong glyph at all (spec §4.2). This flag
    /// and the precondition on ``reclaim()`` are the whole defence.
    public private(set) var isBuildingFrame = false

    /// Advances by one on every ``beginFrame()``, starting at 1 for the first
    /// frame. 0 is deliberately never a live generation: a glyph packed before
    /// the atlas's first ``beginFrame()`` is stamped 0, which is older than any
    /// frame's. There
    /// is no "never stamped" state to reason about — every entry in `placed`
    /// carries its generation from the moment it is inserted.
    public private(set) var currentGeneration = 0

    /// The shelf packer's whole state. `shelfY` is the current shelf's top,
    /// `shelfHeight` the tallest glyph on it so far, `cursorX` the next free
    /// column on it.
    private var shelfY = 0
    private var shelfHeight = 0
    private var cursorX = 0

    /// An empty atlas of `width` by `height` pixels; both must be positive.
    ///
    /// `maximumExtent` is the largest side it may grow to (`GL-C`); the default,
    /// and anything smaller than the starting size, means it never grows.
    public init(width: Int, height: Int, maximumExtent: Int? = nil) {
        precondition(width > 0 && height > 0, "an atlas must have a positive extent")
        self.width = width
        self.height = height
        self.initialWidth = width
        self.initialHeight = height
        self.maximumExtent = max(maximumExtent ?? 0, width, height)
        self.pixels = [UInt8](repeating: 0, count: width * height)
    }

    /// The slot holding `key`'s bitmap, rasterizing and packing it on first
    /// request, or `nil` if the atlas has no room for it and cannot grow.
    ///
    /// Sugar over ``packed(for:rasterize:)`` for a caller that needs only the
    /// atlas rectangle — the tests that assert packer geometry, which is why
    /// the two entry points exist rather than one. A **drawing** caller needs
    /// the bearings as well and must use `packed`, because they are the only
    /// way to place the bitmap relative to the pen.
    public func slot(for key: GlyphKey, rasterize: () -> GlyphImage) -> AtlasSlot? {
        packed(for: key, rasterize: rasterize)?.slot
    }

    /// The slot holding `key`'s bitmap **and the bearings that place it**,
    /// rasterizing and packing it on first request, or `nil` if the atlas has
    /// no room for it.
    ///
    /// `rasterize` is called **at most once per key** — that is the whole point
    /// of the cache, `CTFontDrawGlyphs` being far and away the expensive part
    /// of drawing text, and `theSameKeyReturnsTheSameSlotWithoutRasterizingTwice`
    /// is what pins it. The bearings are stored with the slot for the same
    /// reason: on a cache hit `rasterize` does not run, so a caller that read
    /// `left`/`top` off the returned ``GlyphImage`` would have them on the
    /// first frame and not on the second.
    ///
    /// If the atlas is full it first grows (below ``maximumExtent``, `GL-B`); a
    /// `nil` return means it could not, is counted in ``droppedGlyphs`` and is
    /// **not cached**: a rebuild may relieve it, so a key refused today must be
    /// free to succeed tomorrow.
    public func packed(for key: GlyphKey, rasterize: () -> GlyphImage) -> PackedGlyph? {
        // `index(forKey:)` plus an in-place `values[idx]` edit, the pattern
        // `ShapingCache.shaped(_:font:wrappingAt:)` documents: it hashes the key
        // once, and `values[idx]` addresses the bucket directly for both the
        // re-stamp and the read. A `placed[key]` read followed by a
        // `placed[key] = …` write would hash it twice.
        if let idx = placed.index(forKey: key) {
            // Stamped once per frame: the first use also counts the glyph's
            // pixels as live, which is what ``wantsReclaim`` reads. A later use
            // in the same frame touches nothing.
            if placed.values[idx].generation != currentGeneration {
                placed.values[idx].generation = currentGeneration
                let slot = placed.values[idx].glyph.slot
                frameLiveArea &+= slot.width &* slot.height
            }
            return placed.values[idx].glyph
        }

        let image = rasterize()
        // A whitespace glyph occupies no pixels. It still gets a slot — an
        // empty one — so that the caller's lookup succeeds and `rasterize` is
        // not re-run for every space in a paragraph, which is the commonest
        // glyph there is. It touches neither the packer's state nor the dirty
        // rect, because a zero-area blit writes nothing.
        guard !image.isEmpty else {
            let empty = PackedGlyph(slot: AtlasSlot(x: 0, y: 0, width: 0, height: 0),
                                    left: 0, top: 0)
            placed[key] = Placement(glyph: empty, generation: currentGeneration)
            return empty
        }

        guard let slot = place(width: image.width, height: image.height) ?? growAndPlace(width: image.width,
                                                                                         height: image.height)
        else {
            // Past the cap (`GL-E`). Not cached: a rebuild may make room.
            droppedGlyphs &+= 1
            frameDroppedArea &+= image.width &* image.height
            // Room a rebuild would free exists only if older frames hold some.
            if packedArea > frameLiveArea { reclaimRequested = true }
            return nil
        }
        blit(image, into: slot)
        packedArea &+= slot.width &* slot.height
        frameLiveArea &+= slot.width &* slot.height
        let entry = PackedGlyph(slot: slot, left: image.left, top: image.top)
        placed[key] = Placement(glyph: entry, generation: currentGeneration)
        return entry
    }

    /// Doubles the atlas until `width x height` fits or ``maximumExtent`` stops
    /// it (`GL-B`). Every slot keeps its coordinates, so nothing already handed
    /// out moves.
    private func growAndPlace(width w: Int, height h: Int) -> AtlasSlot? {
        while width < maximumExtent || height < maximumExtent {
            resize(toWidth: min(width * 2, maximumExtent), height: min(height * 2, maximumExtent))
            growCount += 1
            if let slot = place(width: w, height: h) { return slot }
        }
        return nil
    }

    /// Re-lays ``pixels`` out at a new extent, each row at the same (x, y). The
    /// whole atlas is dirty afterwards, because a renderer's texture of the old
    /// size is replaced, not extended.
    private func resize(toWidth newWidth: Int, height newHeight: Int) {
        var next = [UInt8](repeating: 0, count: newWidth * newHeight)
        let copyWidth = min(width, newWidth)
        let copyHeight = min(height, newHeight)
        next.withUnsafeMutableBufferPointer { destination in
            pixels.withUnsafeBufferPointer { source in
                for row in 0..<copyHeight {
                    (destination.baseAddress! + row * newWidth)
                        .update(from: source.baseAddress! + row * width, count: copyWidth)
                }
            }
        }
        pixels = next
        width = newWidth
        height = newHeight
        markEverythingDirty()
    }

    private func markEverythingDirty() {
        dirtyRects = [(0, 0, width, height)]
        dirtyRectsCollapsed = true
    }

    /// Whether a rebuild at the next frame boundary would free room worth the
    /// cost of rasterizing the working set again (`GL-A`).
    ///
    /// True when a refusal asked for one (``reclaimRequested``), or when the
    /// packer has used three quarters of its rows **and** at least a quarter of
    /// what it packed was not touched by the last frame. An atlas full of
    /// glyphs the last frame used has nothing to give back; growing, not
    /// rebuilding, is what that one needs. **One integer comparison when the
    /// atlas is not nearly full.**
    public var wantsReclaim: Bool {
        if reclaimRequested { return true }
        guard (shelfY + shelfHeight) &* 4 >= height &* 3 else { return false }
        return (packedArea &- frameLiveArea) &* 4 >= packedArea
    }

    /// Empties the atlas and sizes it for the working set (`GL-A`, `GL-B`).
    ///
    /// **Only between frames** (`precondition(!isBuildingFrame)`): the packer
    /// and the pixels are reset, so any rect handed out earlier names a
    /// different glyph, or none. ``layoutGeneration`` advances so that whoever
    /// kept one can tell. Every glyph is rasterized again, lazily, by the next
    /// frame that draws it, in paint order - so a rebuilt atlas holds exactly
    /// what a fresh one would after that frame.
    ///
    /// The new size is the smallest power-of-two multiple of the starting size,
    /// not above ``maximumExtent``, whose area is three times what the last
    /// frame used plus what it was refused. An atlas that grew for one busy
    /// frame is therefore small again after a rebuild, and one whose working
    /// set is large does not shrink and then grow again every frame.
    public func reclaim() {
        precondition(!isBuildingFrame,
                     "reclaim called while a frame is being built - the frame in flight holds rects into the atlas it would empty")
        let needed = (frameLiveArea &+ frameDroppedArea) &* 3
        var newWidth = initialWidth
        var newHeight = initialHeight
        while newWidth * newHeight < needed, newWidth < maximumExtent || newHeight < maximumExtent {
            newWidth = min(newWidth * 2, maximumExtent)
            newHeight = min(newHeight * 2, maximumExtent)
        }
        placed.removeAll(keepingCapacity: true)
        shelfY = 0
        shelfHeight = 0
        cursorX = 0
        packedArea = 0
        frameLiveArea = 0
        frameDroppedArea = 0
        reclaimRequested = false
        if newWidth == width, newHeight == height {
            pixels.withUnsafeMutableBufferPointer { $0.update(repeating: 0) }
        } else {
            width = newWidth
            height = newHeight
            pixels = [UInt8](repeating: 0, count: newWidth * newHeight)
        }
        markEverythingDirty()
        layoutGeneration += 1
        reclaimCount += 1
    }

    /// Begins constructing one frame's scene. Every ``packed(for:rasterize:)``
    /// call made before the matching ``endFrame()`` is stamped with the
    /// generation this call establishes, which is what
    /// ``wantsReclaim`` later uses to tell "used this frame" from
    /// "not touched since."
    ///
    /// `precondition(!isBuildingFrame)` guards re-entry — the same shape as
    /// `LayoutTree.beginLayout`'s guard against a nested layout call —
    /// because a nested frame would advance `currentGeneration` out from under
    /// the outer one's in-flight slots.
    public func beginFrame() {
        precondition(!isBuildingFrame, "beginFrame called while a frame is already being built")
        isBuildingFrame = true
        currentGeneration += 1
        frameLiveArea = 0
        frameDroppedArea = 0
    }

    /// Ends the frame ``beginFrame()`` began. After this, and only after this,
    /// ``reclaim()`` may run.
    public func endFrame() {
        isBuildingFrame = false
    }

    /// Forgets the dirty region, after a consumer has uploaded it.
    ///
    /// Without this the rect only ever grows, and a renderer re-uploads the
    /// whole of it every frame — which would still be *correct*, and is exactly
    /// the kind of silently-inert API this repo has been bitten by, so the
    /// resetting half is written now rather than assumed. Pinned by
    /// `theDirtyRectIsTheUnionOfWhatWasWrittenAndClears`.
    public func clearDirtyRect() {
        dirtyRects.removeAll(keepingCapacity: true)
        dirtyRectsCollapsed = false
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
        if dirtyRectsCollapsed, let only = dirtyRects.first {
            dirtyRects[0] = Self.union(only, slot)
            return
        }
        if let last = dirtyRects.last, slot.y == last.y, slot.x == last.x + last.width {
            dirtyRects[dirtyRects.count - 1] = (last.x, last.y, last.width + slot.width,
                                                max(last.height, slot.height))
            return
        }
        dirtyRects.append((slot.x, slot.y, slot.width, slot.height))
        if dirtyRects.count > Self.dirtyRectCap, let bounds = dirtyRect {
            dirtyRects = [bounds]
            dirtyRectsCollapsed = true
        }
    }

    private static func union(_ rect: (x: Int, y: Int, width: Int, height: Int),
                              _ slot: AtlasSlot) -> (x: Int, y: Int, width: Int, height: Int) {
        let minX = min(rect.x, slot.x)
        let minY = min(rect.y, slot.y)
        let maxX = max(rect.x + rect.width, slot.x + slot.width)
        let maxY = max(rect.y + rect.height, slot.y + slot.height)
        return (minX, minY, maxX - minX, maxY - minY)
    }
}
