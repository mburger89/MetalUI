import Testing
@testable import MetalUIText

/// A fresh resolve per access rather than a stored global, for the same
/// reason `ShapingTests.swift` uses one: `ResolvedFont` holds a `CTFont` and
/// is deliberately not `Sendable`, so the brief's `private let font = …` does
/// not compile at file scope under Swift 6 — "let 'font' is not
/// concurrency-safe" (ruling TX-A; this is the same fix Task 2 already made).
private var font: ResolvedFont { FontResolver.resolve(family: nil, size: 13) }

/// **The only test that can see whether the cache is a cache.** A `store` that
/// never stores leaves every other test green and the engine typesetting on
/// every probe.
@MainActor
@Test func theCacheIsActuallyConsulted() {
    let cache = ShapingCache()
    _ = cache.shaped("hello world", font: font, wrappingAt: 100)
    let after = cache.misses
    _ = cache.shaped("hello world", font: font, wrappingAt: 100)
    #expect(cache.hits > 0)
    #expect(cache.misses == after)
}

/// Width is in the key because wrapping is width-dependent. A key that dropped
/// it would serve one width's line breaks for another's.
@MainActor
@Test func twoWidthsDoNotShareOneEntry() {
    let cache = ShapingCache()
    let narrow = cache.shaped("The quick brown fox jumps over", font: font, wrappingAt: 60)
    let wide = cache.shaped("The quick brown fox jumps over", font: font, wrappingAt: 600)
    #expect(narrow.lines.count > wide.lines.count)
    #expect(cache.misses == 2)
}

@MainActor
@Test func twoFontSizesDoNotShareOneEntry() {
    let cache = ShapingCache()
    let small = cache.shaped("hello", font: FontResolver.resolve(family: nil, size: 13),
                             wrappingAt: nil)
    let large = cache.shaped("hello", font: FontResolver.resolve(family: nil, size: 26),
                             wrappingAt: nil)
    #expect(large.widestLine > small.widestLine)
    #expect(cache.misses == 2)
}

/// The cache is keyed on CONTENT, not on element identity — two elements
/// showing the same string shape once.
@MainActor
@Test func theSameStringFromTwoCallersSharesOneEntry() {
    let cache = ShapingCache()
    _ = cache.shaped("shared", font: font, wrappingAt: 200)
    _ = cache.shaped("shared", font: font, wrappingAt: 200)
    #expect(cache.misses == 1)
    #expect(cache.hits == 1)
}

/// The defect this task fixes: memoizing `Shaper.unbreakableRuns` alone still
/// leaves the per-run shaping loop on the table. This asserts the tokenizer
/// walk itself — the more expensive of the two halves — is skipped on a
/// repeat query, and that the memo returns the number it actually computed
/// rather than a fresh zero from a miss that silently found nothing.
@MainActor
@Test func aSecondMinContentQueryTokenizesNothing() {
    let cache = ShapingCache()
    let s = "Row 1 of 40 — a scrollable list item"

    _ = cache.minContentWidth(s, font: font)
    Shaper.resetUnbreakableRunCalls()
    let second = cache.minContentWidth(s, font: font)

    #expect(Shaper.unbreakableRunCalls == 0)
    // The memo must return the same number it computed, not a fresh zero.
    #expect(second == cache.minContentWidth(s, font: font))
    #expect(second > 0)
}

/// What this pins: the memoized value equals a `max` over the runs' widths,
/// each shaped independently through the (unmemoized-for-this-purpose) cache
/// path — i.e. the memo doesn't just return *some* cached number, it returns
/// the right one.
///
/// **Not a width-independence test** — `minContentWidth(_:font:)` takes no
/// width argument at all, so nothing here varies a width or could redden
/// under a width-related mutation. Width-independence is a type-level
/// guarantee (the signature has no width parameter to smuggle one through),
/// not something this test — or any test — checks. See `MinContentKey`'s doc
/// comment in `ShapingCache.swift` for why width is excluded from the key.
@MainActor
@Test func theMemoizedWidthEqualsTheMaxOverIndependentlyShapedRuns() {
    let cache = ShapingCache()
    let s = "a bb supercalifragilistic dd"

    let w = cache.minContentWidth(s, font: font)
    let longest = Shaper.unbreakableRuns(of: s)
        .map { cache.shaped($0, font: font, wrappingAt: nil).widestLine }
        .max() ?? 0
    #expect(abs(w - longest) < 0.001)
}

// MARK: - Task 7: the generation sweep

/// An entry that stops being asked for eventually falls out of the cache,
/// once the dictionary is actually over ``ShapingCache/entryBound``. Filling
/// the cache with entries that never repeat is what makes the sweep run at
/// all — see ``ShapingCache/endFrame()``'s doc comment: below the bound it
/// sweeps nothing, on purpose.
@MainActor
@Test func anEntryUntouchedForAFrameIsDropped() throws {
    let cache = ShapingCache()

    cache.beginFrame()
    _ = cache.shaped("target string", font: font, wrappingAt: 100)
    cache.endFrame()

    for i in 0..<(ShapingCache.entryBound + 10) {
        cache.beginFrame()
        _ = cache.shaped("filler \(i)", font: font, wrappingAt: 100)
        cache.endFrame()
    }

    // If "target string" survived, this is a hit and `misses` does not move.
    // It doesn't survive, so this re-shapes.
    let missesBefore = cache.misses
    _ = cache.shaped("target string", font: font, wrappingAt: 100)
    #expect(cache.misses == missesBefore + 1)
}

/// The bound must not evict something this frame still needs — that is the
/// atlas's recorded trap in a new place: `GlyphAtlas.evictUnusedSince` has zero
/// callers precisely because freeing an entry there strands its pixels and
/// makes the next frame pack a second copy. A sweep that drops a live entry
/// costs a re-shape every frame forever, which is slower than never evicting.
///
/// `"live string"` is looked up on every single frame across a sweep that
/// runs on most of them (filler entries push the dictionary over the bound
/// from the first frame on) — if the sweep ever dropped a same-frame touch,
/// this would show up as an extra miss somewhere in the loop, and the final
/// lookup below would land on a cold entry.
@MainActor
@Test func aSweepNeverDropsAnEntryTheCurrentFrameTouched() throws {
    let cache = ShapingCache()

    for i in 0..<(ShapingCache.entryBound * 2) {
        cache.beginFrame()
        _ = cache.shaped("live string", font: font, wrappingAt: 100)
        _ = cache.shaped("filler \(i)", font: font, wrappingAt: 100)
        cache.endFrame()
    }

    #expect(cache.misses == 1 + ShapingCache.entryBound * 2, "\"live string\" must miss exactly once — the first lookup — never again")

    let missesBefore = cache.misses
    _ = cache.shaped("live string", font: font, wrappingAt: 100)
    #expect(cache.misses == missesBefore)
}
