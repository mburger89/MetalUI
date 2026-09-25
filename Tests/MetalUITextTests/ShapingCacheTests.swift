import Foundation
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

/// `ShapingCache.resolveFont`'s memo key must carry both halves of a request.
/// A key that dropped `size` would hand 13pt's font to a 26pt request; one that
/// dropped `family` would hand the system font to a `"Menlo"` request. The
/// frame-level count test cannot see either — its rows all ask for one request.
///
/// The expected keys come from the **uncached** resolver, not from the memo,
/// and the three requests are required to resolve to three different fonts
/// first, so a memo returning one arm's font for another's request disagrees.
@MainActor
@Test func everyComponentOfTheFontRequestDiscriminates() {
    let cache = ShapingCache()
    let system13 = cache.resolveFont(family: nil, size: 13).key
    let system26 = cache.resolveFont(family: nil, size: 26).key
    let menlo13 = cache.resolveFont(family: "Menlo", size: 13).key

    let oracle13 = FontResolver.resolve(family: nil, size: 13).key
    let oracle26 = FontResolver.resolve(family: nil, size: 26).key
    let oracleMenlo = FontResolver.resolve(family: "Menlo", size: 13).key
    #expect(oracle13 != oracle26)
    #expect(oracle13 != oracleMenlo)

    #expect(system13 == oracle13)
    #expect(system26 == oracle26)
    #expect(menlo13 == oracleMenlo)
    #expect(cache.resolvedFontCount == 3)
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

// `aSecondMinContentQueryTokenizesNothing` and
// `theMemoizedWidthEqualsTheMaxOverIndependentlyShapedRuns` retired at stage 9
// with the min-content memo they pinned (tokenizer min-content deleted,
// `LR-FD`, record §51).

// MARK: - The generation sweep

/// An entry that stops being asked for eventually falls out of the cache,
/// once the dictionary is actually over ``ShapingCache/sweepThreshold``.
/// Filling the cache with entries that never repeat is what makes the sweep
/// run at all — see ``ShapingCache/endFrame()``'s doc comment: below the
/// threshold it sweeps nothing, on purpose.
@MainActor
@Test func anEntryUntouchedForAFrameIsDropped() {
    let cache = ShapingCache()

    cache.beginFrame()
    _ = cache.shaped("target string", font: font, wrappingAt: 100)
    cache.endFrame()

    for i in 0..<(ShapingCache.sweepThreshold + 10) {
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

/// The sweep must not evict something this frame still needs — that is the
/// atlas's recorded trap in a new place: `GlyphAtlas.evictUnusedSince` has zero
/// callers precisely because freeing an entry there strands its pixels and
/// makes the next frame pack a second copy. A sweep that drops a live entry
/// costs a re-shape every frame forever, which is slower than never evicting.
///
/// `"live string"` is looked up on every single frame across a sweep that
/// runs on most of them (filler entries push the dictionary over the
/// threshold from the first frame on) — if the sweep ever dropped a
/// same-frame touch, this would show up as an extra miss somewhere in the
/// loop, and the final lookup below would land on a cold entry.
@MainActor
@Test func aSweepNeverDropsAnEntryTheCurrentFrameTouched() {
    let cache = ShapingCache()

    for i in 0..<(ShapingCache.sweepThreshold * 2) {
        cache.beginFrame()
        _ = cache.shaped("live string", font: font, wrappingAt: 100)
        _ = cache.shaped("filler \(i)", font: font, wrappingAt: 100)
        cache.endFrame()
    }

    #expect(cache.misses == 1 + ShapingCache.sweepThreshold * 2, "\"live string\" must miss exactly once — the first lookup — never again")

    let missesBefore = cache.misses
    _ = cache.shaped("live string", font: font, wrappingAt: 100)
    #expect(cache.misses == missesBefore)
}

// `aMinContentHitReStampsSoItSurvivesASweepingLoad` retired at stage 9 with the
// min-content memo (`LR-FD`): re-spelled onto `shaped(_:font:wrappingAt:)` it
// would be `aSweepNeverDropsAnEntryTheCurrentFrameTouched` above — a live entry
// looked up (a hit) on every frame of a sweeping load — which pins the storage
// hit branch's re-stamp already (record §51, `LR-FJ`).

/// Touches `count` distinct strings that are never reused across tests, so the
/// dictionary they fill stays over ``ShapingCache/sweepThreshold`` on every
/// frame they are touched — the condition ``ShapingCache/endFrame()``'s sweep
/// guards on. **They are touched EVERY frame on purpose**: an entry the current
/// frame touched is never stale, so a live filler set keeps the sweep firing,
/// where a set left to age would itself be evicted, drop the count back under
/// the threshold and silently stop the sweep partway through the test.
@MainActor
private func touchLiveFillers(_ cache: ShapingCache, count: Int, tag: String) {
    for i in 0..<count {
        _ = cache.shaped("\(tag) filler \(i)", font: font, wrappingAt: 100)
    }
}

/// **What pins `ShapingCache.staleAfterGenerations` at exactly 2**, in both
/// directions, because either half alone leaves the constant free to move.
///
/// The constant was unpinned until this existed: setting it to **1** passed the
/// whole 604-test suite, and its own doc comment claims a concrete purpose — a
/// windowed `List` re-touching a row it dropped for one frame and picked back
/// up the next must not pay a re-shape for that alone. That claim is exactly
/// this arithmetic, so it is assertable.
///
/// `sweep` drops an entry whose `generation < currentGeneration -
/// staleAfterGenerations`. An entry stamped on frame `G` therefore survives the
/// sweeps ending frames `G+1` and `G+2`, and falls out of the one ending
/// `G+3`. The two halves below straddle that boundary from opposite sides:
///
/// - **survives two skipped frames** — reddens at `staleAfterGenerations == 1`,
///   where the sweep ending `G+2` already has cutoff `G+1` and evicts it;
/// - **evicted after three** — reddens at `3` or anything larger, where the
///   sweep ending `G+3` has cutoff `G` or lower and keeps it.
///
/// Both halves read `misses` immediately around the probed lookup alone, so the
/// live fillers' own genuine misses on the same frame are never mistaken for
/// the target's.
///
/// **Re-spelled onto `shaped(_:font:wrappingAt:)` at stage 9** (`LR-FD`): it
/// probed the min-content memo with the tokenizer counter, both deleted; the
/// sweep and `staleAfterGenerations` it pins are shared by both dictionaries
/// (`sweep(_:)` is one generic function), so the storage side carries the same
/// boundary.
@MainActor
@Test func anEntrySurvivesExactlyTwoUntouchedSweptFrames() {
    let fillers = ShapingCache.sweepThreshold + 4

    // Half one: touched on frame 1, skipped on frames 2 and 3, looked up on 4.
    let survives = ShapingCache()
    for frame in 1...4 {
        survives.beginFrame()
        if frame == 1 { _ = survives.shaped("target one", font: font, wrappingAt: 100) }
        touchLiveFillers(survives, count: fillers, tag: "a")
        if frame == 4 {
            let before = survives.misses
            _ = survives.shaped("target one", font: font, wrappingAt: 100)
            #expect(survives.misses == before,
                    "an entry untouched for two swept frames must still be cached")
        }
        survives.endFrame()
    }

    // Half two: the same shape with one more skipped frame, which crosses it.
    let evicted = ShapingCache()
    for frame in 1...5 {
        evicted.beginFrame()
        if frame == 1 { _ = evicted.shaped("target two", font: font, wrappingAt: 100) }
        touchLiveFillers(evicted, count: fillers, tag: "b")
        if frame == 5 {
            let before = evicted.misses
            _ = evicted.shaped("target two", font: font, wrappingAt: 100)
            #expect(evicted.misses == before + 1,
                    "an entry untouched for three swept frames must have been evicted")
        }
        evicted.endFrame()
    }
}

// `aCounterOnlyCountsCallsWithinItsOwnBinding` retired at stage 9 with
// `Shaper.runCallCounter`, the task-local sink whose scope it pinned
// (`LR-FD`, record §51).
