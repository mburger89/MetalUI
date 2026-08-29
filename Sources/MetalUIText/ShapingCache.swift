import Foundation

/// A window-level cache over ``Shaper``, keyed on the CONTENT that determines
/// a shape rather than on element identity (spec §3.2) — `(string, font,
/// width)` for a full shape via ``shaped(_:font:wrappingAt:)``, and
/// `(string, font)` alone for the width-independent min-content memo via
/// ``minContentWidth(_:font:)``.
///
/// **Deliberately not the `StateTable`.** `StateTable` (spec §4.3) is for
/// state that *cannot* be recomputed from an element's values: scroll offset,
/// hover, an in-progress drag. A shaped line is not that — it is a pure
/// function of its key — so putting this cache there would key on the
/// *element* rather than the *string*, and two elements showing the same text
/// would shape it twice. This type exists precisely so they don't: two
/// callers offering the same `(string, font, width)` share one entry.
///
/// **Owned by the window beside `StateTable`, `@MainActor` for the same
/// reason.** `MeasureFunction` is `@Sendable` and non-isolated, but a
/// global-actor-isolated class is implicitly `Sendable`, so *this cache* may
/// be captured by that closure even though the values it hands back may not:
/// ``ShapedText`` wraps a `CTLine` and ``ResolvedFont`` wraps a `CTFont`,
/// neither of which is `Sendable`, and `MainActor.assumeIsolated`'s closure
/// must reduce to a `Sendable` result before returning. Callers must not let
/// a `ShapedText` — or a `ResolvedFont` — escape the isolated block.
///
/// **A `ResolvedFont` cannot be captured by a `@Sendable` closure either**,
/// so it cannot travel from wherever a `Text` element is built to the
/// isolated block that later calls ``shaped(_:font:wrappingAt:)``. What
/// *can* travel is ``FontKey`` — it is `Sendable` — so the font itself lives
/// here, registered ahead of time and looked up by key from inside the
/// isolated block: ``registerFont(_:)`` and ``font(for:)`` exist for exactly
/// that call shape, so Task 4's measure function can capture a `ShapingCache`
/// and a `FontKey` and reconstitute the `ResolvedFont` only once it is
/// already on the main actor.
@MainActor
public final class ShapingCache {
    /// `(string, FontKey, width)`. `width` is compared and hashed by
    /// `bitPattern` where present — the same technique `LayoutContext`'s
    /// `MeasureKey` uses for its optional doubles — rather than by `==`,
    /// because IEEE-754 equality is not reflexive for every bit pattern
    /// (NaN) and this cache needs a total, reflexive key comparison instead.
    /// **A near-miss here — two widths a caller considers "the same" landing
    /// on different bit patterns — costs an extra recompute through
    /// ``Shaper``, never a wrong answer**: every miss falls through to the
    /// real typesetter, so the cache can only be slower than optimal, not
    /// incorrect.
    private struct Key: Hashable {
        var string: String
        var font: FontKey
        var width: Double?

        static func == (lhs: Key, rhs: Key) -> Bool {
            lhs.string == rhs.string
                && lhs.font == rhs.font
                && lhs.width?.bitPattern == rhs.width?.bitPattern
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(string)
            hasher.combine(font)
            hasher.combine(width?.bitPattern)
        }
    }

    /// A cached value stamped with the generation it was last touched in —
    /// hit or inserted — so ``endFrame()`` can tell "used this frame, or
    /// recently enough" from "stale" without a second, parallel dictionary to
    /// keep in sync. Generic over both `storage`'s `ShapedText` and
    /// `minContent`'s `Double` so the sweep in ``endFrame()`` is one function
    /// rather than two copies that could drift.
    private struct Entry<Value> {
        var value: Value
        var generation: Int
    }

    private var storage: [Key: Entry<ShapedText>] = [:]
    private var fonts: [FontKey: ResolvedFont] = [:]

    /// **Keyed on the string and the resolved font, and deliberately NOT on any
    /// width.** Min-content is width-independent by definition — that is what
    /// lets CSS Sizing §4.5 use it as a floor — so folding a width in would miss
    /// on every frame of a resize and cache nothing.
    private struct MinContentKey: Hashable {
        var string: String
        var font: FontKey
    }

    /// **Bounded exactly as `storage` is, by the same sweep — see
    /// ``endFrame()``.** Before Task 7 this was unbounded like `storage`, and
    /// the held-back assertion this milestone added
    /// (`theShapingCacheStaysUnderItsBoundAcrossAWidthSweep`) reads this
    /// dictionary's count as well as `storage`'s for exactly that reason: a
    /// bound enforced on only one of the two would leave the other growing
    /// with nothing able to see it.
    private var minContent: [MinContentKey: Entry<Double>] = [:]

    /// Cache observability, and the only way anything outside this file can
    /// see whether the cache is a cache — a ``shaped(_:font:wrappingAt:)``
    /// that never stores would leave every other behavioural test green while
    /// shaping on every single call. Pinned by `theCacheIsActuallyConsulted`.
    private(set) var hits = 0
    private(set) var misses = 0

    /// Every call to ``shaped(_:font:wrappingAt:)``, hit or miss. `hits + misses`
    /// already gives this; it is named separately because the assertion that
    /// matters is the *lookup* count — the per-run loop in `Text`'s min-content
    /// branch drives it, and a hit is not free at 604 ns.
    var lookups: Int { hits + misses }

    /// Entry count, for the bound assertion. `storage` stays private.
    var storageCount: Int { storage.count }

    /// Entry count for `minContent`, on the same footing as ``storageCount``
    /// and for the same reason — see `minContent`'s own doc comment.
    var minContentCount: Int { minContent.count }

    /// True for the duration of one frame's layout-and-paint construction —
    /// the same shape as `GlyphAtlas.isBuildingFrame` and
    /// `LayoutTree.isLayingOut`. Unlike the atlas, nothing here traps while
    /// this is true: a dictionary reclaims a removed entry's storage on the
    /// spot, so there is no "stranded pixels" hazard to guard against (see
    /// ``endFrame()``'s doc comment). The flag exists so `beginFrame()` can
    /// catch re-entrant calls the same way the atlas's does.
    public private(set) var isBuildingFrame = false

    /// Advances by one on every ``beginFrame()``, starting at 1 for the first
    /// frame — the same convention as `GlyphAtlas.currentGeneration`, so 0
    /// stays a generation nothing was ever stamped with.
    public private(set) var currentGeneration = 0

    /// An entry survives being untouched for this many generations before
    /// ``endFrame()`` will consider it for eviction. A caller who resolves an
    /// entry's key from a slightly different frame than the one right before
    /// it — a windowed `List` re-touching a row it dropped one frame and
    /// picked back up the next, say — should not pay a re-shape for that
    /// alone; this grace is what keeps the sweep from being trigger-happy
    /// about it. `endFrame()`'s own comment records what it costs when this
    /// is too small: an entry evicted while still live re-shapes every frame
    /// forever, which is slower than never evicting at all.
    private static let staleAfterGenerations = 2

    /// The per-dictionary cap `endFrame()` sweeps against. `storage` and
    /// `minContent` are bounded independently against this same number —
    /// they hold different things and there is no reason one's growth should
    /// starve the other's budget.
    ///
    /// **Sized well above a realistic single frame's live working set, on
    /// purpose.** A 40-row `List` like the demo's touches on the order of 90
    /// `storage` entries and 40 `minContent` ones on every steady-state
    /// frame — every one of them re-touched every frame, so none of them may
    /// ever be evicted (see ``endFrame()``). This bound leaves that working
    /// set roughly 2-3x of headroom for a real app's greater string variety,
    /// while still being a bound rather than "large enough that nobody will
    /// notice" — spec §6 measured no cost difference between a 276-entry and
    /// a 733-entry cache, so this number is not chasing a speed target.
    public static let entryBound = 256

    public init() {}

    /// Makes `font` reachable by its ``FontKey`` from inside a later
    /// `MainActor.assumeIsolated` block, for a caller (Task 4's measure
    /// function) that can carry the `Sendable` key across a `@Sendable`
    /// closure but not the font itself. Re-registering the same key is
    /// idempotent — `FontKey` already identifies the resolved `CTFont`
    /// completely (see its doc comment), so two registrations under one key
    /// describe the same font.
    public func registerFont(_ font: ResolvedFont) {
        fonts[font.key] = font
    }

    /// The font last registered under `key`, if any.
    public func font(for key: FontKey) -> ResolvedFont? {
        fonts[key]
    }

    /// Shapes `string` in `font` at `width`, consulting the cache first.
    ///
    /// Registers `font` under its key as a side effect (see
    /// ``registerFont(_:)``), so a caller that always shapes through this
    /// method never needs to call it separately — only a caller that must
    /// look a font up *before* it has one to shape with (Task 4, across the
    /// isolation boundary) does.
    public func shaped(_ string: String, font: ResolvedFont, wrappingAt width: Double?) -> ShapedText {
        registerFont(font)

        let key = Key(string: string, font: font.key, width: width)
        if let cached = storage[key] {
            hits += 1
            storage[key] = Entry(value: cached.value, generation: currentGeneration)
            return cached.value
        }

        misses += 1
        let result = Shaper.shape(string, font: font, wrappingAt: width)
        storage[key] = Entry(value: result, generation: currentGeneration)
        return result
    }

    /// The width of the longest unbreakable run — CSS's min-content — memoized.
    ///
    /// **Memoizing the result rather than the runs is the point.** Caching
    /// `Shaper.unbreakableRuns` alone removes the tokenizer walk and leaves the
    /// per-run shaping lookups behind; measured, that is ~0.79 ms of a 4.97 ms
    /// frame still on the table. Storing the width collapses the tokenizer walk
    /// and the whole loop into one dictionary hit.
    public func minContentWidth(_ string: String, font: ResolvedFont) -> Double {
        let key = MinContentKey(string: string, font: font.key)
        if let cached = minContent[key] {
            minContent[key] = Entry(value: cached.value, generation: currentGeneration)
            return cached.value
        }
        var width = 0.0
        for run in Shaper.unbreakableRuns(of: string) {
            width = max(width, shaped(run, font: font, wrappingAt: nil).widestLine)
        }
        minContent[key] = Entry(value: width, generation: currentGeneration)
        return width
    }

    /// Begins one frame's worth of shaping. Every ``shaped(_:font:wrappingAt:)``
    /// or ``minContentWidth(_:font:)`` call made before the matching
    /// ``endFrame()`` stamps its entry with the generation this call
    /// establishes — the same contract as `GlyphAtlas.beginFrame()`.
    ///
    /// Brackets **layout and paint both**, unlike the atlas's bracket, which
    /// wraps only paint. A `Text`'s `MeasureFunction` shapes during layout
    /// (`textMeasure`, for both the `.definite` and `.minContent` branches)
    /// and `Text.paint` shapes again at the box's final rounded width — both
    /// touches belong to the same frame, and `endFrame()`'s sweep must see
    /// both as live. `Frame.render` calls this before `requestLayout` runs
    /// and this type's `endFrame()` after `paint` returns, for that reason.
    public func beginFrame() {
        precondition(!isBuildingFrame, "beginFrame called while a frame is already being built")
        isBuildingFrame = true
        currentGeneration += 1
    }

    /// Ends the frame ``beginFrame()`` began, then sweeps both dictionaries.
    ///
    /// **Only evicts when a dictionary is over ``entryBound``, and only
    /// entries untouched for ``staleAfterGenerations``.** An entry this
    /// frame touched has `generation == currentGeneration`, which is never
    /// stale, so this can never drop something the frame just built —
    /// unlike `GlyphAtlas.evictUnusedSince(_:)`, which traps if called mid-
    /// frame for exactly that hazard, nothing here needs to trap: eviction
    /// only ever runs between frames, from this one call site.
    ///
    /// **A dictionary reclaims a removed entry's storage immediately.** That
    /// is what makes this safe where the atlas's `evictUnusedSince(_:)` is
    /// not: the atlas's shelf packer never revisits a closed shelf, so
    /// freeing a `GlyphKey` there strands its pixels and the next request
    /// for it packs a *second* copy further down — calling it every frame
    /// would make the atlas fill faster, which is why it has zero
    /// production callers. `Dictionary.removeValue` has no such reclaim
    /// problem: the slot is simply free, and a later re-touch is an ordinary
    /// cache miss followed by an ordinary insert.
    public func endFrame() {
        precondition(isBuildingFrame, "endFrame called without a matching beginFrame")
        isBuildingFrame = false
        sweep(&storage)
        sweep(&minContent)
    }

    /// Drops every entry untouched for ``staleAfterGenerations``, but only
    /// once `dict` is over ``entryBound`` — see ``endFrame()``'s doc comment
    /// for why eviction is a bound rather than a target size, and this
    /// type's own doc comment for why a dictionary can run it safely where
    /// the atlas cannot.
    private func sweep<Key: Hashable, Value>(_ dict: inout [Key: Entry<Value>]) {
        guard dict.count > Self.entryBound else { return }
        let cutoff = currentGeneration - Self.staleAfterGenerations
        for (key, entry) in dict where entry.generation < cutoff {
            dict.removeValue(forKey: key)
        }
    }
}
