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
    let counter = Shaper.RunCallCounter()
    let second = Shaper.$runCallCounter.withValue(counter) {
        cache.minContentWidth(s, font: font)
    }

    #expect(counter.count == 0)
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

/// `minContentWidth`'s hit branch re-stamps the entry's generation exactly
/// as `shaped`'s does — but nothing pinned that half before this test, and
/// it is the sharper of the two to lose: every visible row's string is a
/// min-content *hit* every frame in the demo's own `List`, so a hit that
/// does not re-stamp ages every one of them out the moment the dictionary
/// first crosses the threshold, and the whole list starts re-tokenizing on
/// every frame.
///
/// `"target"` is looked up every frame across enough sweep-eligible frames
/// to cross `staleAfterGenerations` many times over; a hit that fails to
/// re-stamp would let it go stale and fall out, and the next lookup would
/// retokenize.
///
/// **The tokenizer-call counter is now a task-local sink each caller binds
/// its own instance of (see `Shaper.runCallCounter`), which is what lets
/// `target`'s contribution be isolated without a reset-and-check dance.** A
/// filler `minContentWidth` call is a genuine miss on every iteration, but it
/// is made with no counter bound at all, so it is simply not observed —
/// unlike the old global, where every main-thread caller moved the same
/// counter and isolating `target`'s call meant resetting immediately before
/// it and reading back before touching filler. A fresh counter is still
/// bound around each iteration's `target` lookup, and the assertion still
/// lives inside the loop, because what is being pinned is "no retokenization
/// on frame `i`" rather than a single total.
@MainActor
@Test func aMinContentHitReStampsSoItSurvivesASweepingLoad() {
    let cache = ShapingCache()
    let target = "target of 4000 — a scrollable list item"

    cache.beginFrame()
    _ = cache.minContentWidth(target, font: font)
    cache.endFrame()

    for i in 0..<(ShapingCache.sweepThreshold * 2) {
        cache.beginFrame()
        let counter = Shaper.RunCallCounter()
        Shaper.$runCallCounter.withValue(counter) {
            _ = cache.minContentWidth(target, font: font)
        }
        #expect(counter.count == 0, "target retokenized on frame \(i)")
        _ = cache.minContentWidth("filler \(i) of 4000 — a scrollable list item", font: font)
        cache.endFrame()
    }
}

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
        _ = cache.minContentWidth("\(tag) filler \(i)", font: font)
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
/// Both halves read the tokenizer counter rather than `hits`/`misses`, since a
/// re-shape after eviction is precisely a re-tokenization; a fresh counter is
/// bound immediately around the probed lookup alone, so the live fillers'
/// own genuine misses on the same frame — made with no counter bound — are
/// never observed and cannot be mistaken for the target's.
@MainActor
@Test func anEntrySurvivesExactlyTwoUntouchedSweptFrames() {
    let fillers = ShapingCache.sweepThreshold + 4

    // Half one: touched on frame 1, skipped on frames 2 and 3, looked up on 4.
    let survives = ShapingCache()
    for frame in 1...4 {
        survives.beginFrame()
        if frame == 1 { _ = survives.minContentWidth("target one", font: font) }
        touchLiveFillers(survives, count: fillers, tag: "a")
        if frame == 4 {
            let counter = Shaper.RunCallCounter()
            Shaper.$runCallCounter.withValue(counter) {
                _ = survives.minContentWidth("target one", font: font)
            }
            #expect(counter.count == 0,
                    "an entry untouched for two swept frames must still be cached")
        }
        survives.endFrame()
    }

    // Half two: the same shape with one more skipped frame, which crosses it.
    let evicted = ShapingCache()
    for frame in 1...5 {
        evicted.beginFrame()
        if frame == 1 { _ = evicted.minContentWidth("target two", font: font) }
        touchLiveFillers(evicted, count: fillers, tag: "b")
        if frame == 5 {
            let counter = Shaper.RunCallCounter()
            Shaper.$runCallCounter.withValue(counter) {
                _ = evicted.minContentWidth("target two", font: font)
            }
            #expect(counter.count == 1,
                    "an entry untouched for three swept frames must have been evicted")
        }
        evicted.endFrame()
    }
}

/// **Replaces `theRunCounterIgnoresCallsMadeOffTheMainThread`, whose name
/// stopped describing what the counter guarantees once it stopped being a
/// `@MainActor` global.** That test pinned "a call from another executor is
/// never counted" — true of the old main-thread guard, and no longer true at
/// all: `Shaper.runCallCounter` is a `@TaskLocal`, so a call made from any
/// executor counts as long as the task making it inherited the binding. What
/// is invariant now is **scope**, not thread, and this test pins that
/// instead.
///
/// - **A `Task.detached` closure does not inherit the binding**, by
///   design — detached tasks start with no inherited task-local state — so
///   50 calls made there are invisible to a counter bound in the calling
///   task, regardless of which thread they run on.
/// - **A `TaskGroup` child DOES inherit it**, and runs off the main actor
///   while doing so — `addTask`'s closures are not actor-isolated to their
///   parent — so a call made there still counts. This is the half that would
///   have failed under the old main-thread guard and is exactly the
///   behaviour change ``Shaper/runCallCounter``'s doc comment calls out.
///
/// See ``Shaper/runCallCounter``'s doc comment for the data race the
/// `@MainActor` global replaced, and for the cross-test flake replacing the
/// global with a task-local sink was written to fix.
@MainActor
@Test func aCounterOnlyCountsCallsWithinItsOwnBinding() async {
    let detachedCounter = Shaper.RunCallCounter()
    await Shaper.$runCallCounter.withValue(detachedCounter) {
        await Task.detached {
            for _ in 0..<50 { _ = Shaper.unbreakableRuns(of: "off the main thread entirely") }
        }.value
    }
    #expect(detachedCounter.count == 0,
            "a detached task does not inherit the binding, so its calls must be invisible to it")

    // The positive control: a call made by a task that DID inherit the
    // binding counts even though it did not run on the main actor — this is
    // a test about the binding's scope, not about main-thread isolation.
    let inheritedCounter = Shaper.RunCallCounter()
    await Shaper.$runCallCounter.withValue(inheritedCounter) {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { _ = Shaper.unbreakableRuns(of: "inherited, off the main actor") }
            await group.waitForAll()
        }
    }
    #expect(inheritedCounter.count == 1,
            "a non-detached child task inherits the binding, so its call must count")
}
