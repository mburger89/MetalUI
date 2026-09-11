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

    /// Swept exactly as `storage` is, by the same ``endFrame()`` call. A
    /// caller who bounds only `storage` and forgets this dictionary has
    /// fixed nothing — it grows exactly the same way, unbounded, with
    /// nothing able to see it. (The first test written against this bound
    /// read only `storage`'s count for exactly that reason, and passed
    /// while this dictionary kept growing; the test now reads both.)
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

    /// Entry count, for tests. `storage` stays private.
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
    /// catch re-entrant calls the same way the atlas's does. Internal rather
    /// than `public`, unlike the atlas's: nothing outside this file reads it.
    private(set) var isBuildingFrame = false

    /// Advances by one on every ``beginFrame()``, starting at 1 for the first
    /// frame — the same convention as `GlyphAtlas.currentGeneration`, so 0
    /// stays a generation nothing was ever stamped with. Internal for the
    /// same reason as ``isBuildingFrame``.
    private(set) var currentGeneration = 0

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

    /// The per-dictionary size `endFrame()`'s sweep triggers on — **a
    /// trigger, not a ceiling.** `sweep(_:)` guards on `dict.count >
    /// sweepThreshold` and then removes only *stale* entries, so
    /// `count <= sweepThreshold` is not an invariant this type enforces: a
    /// workload whose live, every-frame-touched working set is itself over
    /// this number will settle above it and stay there, by design — the
    /// sweep can never remove something the current frame just touched (see
    /// ``endFrame()``), so it structurally cannot shrink a resident set that
    /// large. That is correct, not a bug: it is what keeps a small threshold
    /// from thrashing a workload whose real working set exceeds it, at the
    /// cost of re-shaping forever instead of caching. The actual invariant
    /// is narrower than "stays under N": *nothing older than
    /// `staleAfterGenerations` survives a frame in which the dictionary was
    /// over this threshold.*
    ///
    /// `storage` and `minContent` are swept independently against this same
    /// number — they hold different things and there is no reason one's
    /// growth should starve the other's budget.
    ///
    /// **Measured against `demoLikeRows(40)`, the test harness modelled on
    /// the demo's scroller — not against the demo itself, whose own list is
    /// longer and whose visible window is smaller.**
    ///
    /// Two different quantities, and confusing them is what this paragraph
    /// exists to stop. **Touched per steady-state frame: 64 `storage`
    /// entries and 16 `minContent` ones** — 16 being the windowed row count,
    /// not the data's 40. **Resident** (what actually sits in the
    /// dictionaries) is **207 and 40**, because the first frame builds every
    /// row — a `ScrollView`'s viewport extent is not known until its own
    /// `prepaint` has run once — and nothing ever evicts those entries at
    /// this threshold. 207 is 81% of 256, roughly 1.24x headroom, not the
    /// 3x the touched-per-frame figure alone would suggest.
    ///
    /// The touched figure is measured rather than counted, and the method is
    /// worth knowing because it is the only instrument here: set this
    /// constant to **1** so the sweep fires every frame, and read what the
    /// dictionaries settle to. An entry touched this frame can never be
    /// stale, so the resident set collapses to exactly what the last
    /// `staleAfterGenerations` frames touched — 64 and 16.
    ///
    /// 256 was still chosen over a value closer to 207: spec §6
    /// measured no cost difference between a 276-entry and a 733-entry
    /// cache, so there is room to be generous without chasing a speed
    /// target, and a threshold barely above one measurement is the kind of
    /// number that turns into thrashing the next time the demo changes.
    static let sweepThreshold = 256

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

    /// A font **request** — `Text`'s `(fontFamily, fontSize)` — as opposed to
    /// the resolved identity ``FontKey`` describes. `size` is compared and
    /// hashed by `bitPattern`, exactly as ``Key``'s `width` is, so the key is
    /// total and reflexive for every `Double`. For every size
    /// ``FontResolver/resolve(family:size:)`` admits (finite and positive)
    /// bit-pattern equality and `==` agree; the spelling is for totality, not
    /// for a case that reaches a stored entry — a NaN request misses, calls
    /// the resolver, and traps there before anything is stored.
    ///
    /// **Keyed on a family name, and that does not break ``FontKey``'s rule.**
    /// The rule is that nothing *downstream of resolution* — a glyph image, a
    /// shape, a metric — may be keyed on the requested name, because
    /// `CTFontCreateWithName` substitutes. This memo caches the resolution
    /// itself: its key is the resolver's own input, and what it hands back
    /// carries the resolved ``FontKey`` every other cache here keys on. Two
    /// requests that resolve to one face ("NoSuchFontXYZ" and "Helvetica")
    /// are two entries holding equal keys, which is correct.
    private struct FontRequest: Hashable {
        var family: String?
        var size: Double

        static func == (lhs: FontRequest, rhs: FontRequest) -> Bool {
            lhs.family == rhs.family && lhs.size.bitPattern == rhs.size.bitPattern
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(family)
            hasher.combine(size.bitPattern)
        }
    }

    /// ``resolveFont(family:size:)``'s memo.
    ///
    /// **Never swept, deliberately, and on the same footing as `fonts`.** It
    /// grows by one entry per distinct `(family, size)` request ever made on
    /// this window's cache, and by nothing else: no frame-varying input
    /// reaches either half of the key. `fontSize` is a stored property of
    /// `Text`, not a `Style` field, so no animation drives it, and nothing in
    /// `Sources/` computes a size or a family. `fonts` has the same growth
    /// shape — one entry per distinct resolved ``FontKey``, which is at most
    /// one per request — and is not swept either, so sweeping this memo alone
    /// would re-resolve fonts whose `CTFont` `fonts` still holds. The two
    /// belong together: **if font size becomes animatable (spec §8's hole) or
    /// `fonts` is ever swept, move both into ``endFrame()``'s sweep as
    /// `Entry`-wrapped dictionaries**, and rewrite `Text.requestLayout`'s
    /// guard argument, which relies on `fonts` never losing an entry.
    private var resolvedFonts: [FontRequest: ResolvedFont] = [:]

    /// Entry count for the font memo, for tests.
    var resolvedFontCount: Int { resolvedFonts.count }

    /// ``FontResolver/resolve(family:size:)``, memoized per request.
    ///
    /// **This is the per-frame entry point, and `FontResolver` is not.**
    /// `Text` resolves its font in `requestLayout` and again in `paint`;
    /// uncached, that is two `CTFont` creations per `Text` per frame, and
    /// CoreText does not memoize them. The memo lives here rather than on
    /// `FontResolver` because this type is already `@MainActor` and
    /// window-owned, and reachable from both phases as `pass.shapingCache`;
    /// making `FontResolver` `@MainActor` instead would isolate every
    /// nonisolated test that calls it. Pinned by
    /// `aWarmFrameReachesTheUncachedFontResolverZeroTimes` (a warm frame makes
    /// zero resolver calls, a cold one exactly one per distinct request) and
    /// `everyComponentOfTheFontRequestDiscriminates`.
    ///
    /// The lookup does not re-stamp or register anything: see `resolvedFonts`
    /// for why it is not swept, and `Text.requestLayout` for the one caller
    /// that also needs ``registerFont(_:)``.
    public func resolveFont(family: String?, size: Double) -> ResolvedFont {
        let request = FontRequest(family: family, size: size)
        if let font = resolvedFonts[request] { return font }
        let font = FontResolver.resolve(family: family, size: size)
        resolvedFonts[request] = font
        return font
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
        // `index(forKey:)` plus an in-place `values[idx]` edit, rather than
        // reading the entry out and writing a whole new one back — measured,
        // the read-then-reassign form costs an extra ~0.11ms of a 4.5ms
        // frame from the second hash lookup and the copy. `index(forKey:)`
        // hashes once; `values[idx]` addresses the bucket directly for both
        // the re-stamp and the read below.
        if let idx = storage.index(forKey: key) {
            hits += 1
            storage.values[idx].generation = currentGeneration
            return storage.values[idx].value
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
        // See `shaped(_:font:wrappingAt:)`'s comment on the same pattern.
        if let idx = minContent.index(forKey: key) {
            minContent.values[idx].generation = currentGeneration
            return minContent.values[idx].value
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
    /// **Only evicts when a dictionary is over ``sweepThreshold``, and only
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
    /// once `dict` is over ``sweepThreshold`` — see ``sweepThreshold``'s own
    /// doc comment for why that makes this a trigger rather than a target
    /// size, and ``endFrame()``'s for why a dictionary can run it safely
    /// where the atlas cannot.
    private func sweep<Key: Hashable, Value>(_ dict: inout [Key: Entry<Value>]) {
        guard dict.count > Self.sweepThreshold else { return }
        let cutoff = currentGeneration - Self.staleAfterGenerations
        for (key, entry) in dict where entry.generation < cutoff {
            dict.removeValue(forKey: key)
        }
    }
}
