import Foundation
import Testing
import MetalUITextSystem
@testable import MetalUIText

// The shaping cache's hard bound and its caret offsets (`TS-F`, record 411). Counts and entry numbers, never time.

private var font: ResolvedFont { FontResolver.resolve(family: nil, size: 13) }

/// Runs `frames` frames, each calling `body(frame)`, and returns the cache's miss count per frame.
@MainActor private func misses(_ cache: ShapingCache, frames: Int, _ body: (Int) -> Void) -> [Int] {
    var perFrame: [Int] = []
    for frame in 0..<frames {
        let before = cache.misses + cache.caretMisses
        cache.beginFrame()
        body(frame)
        cache.endFrame()
        perFrame.append(cache.misses + cache.caretMisses - before)
    }
    return perFrame
}

/// **1** A working set at or below the budget misses once per string, ever: 60 shapes and 60 caret lines looped for 40 frames
/// under a budget of 128 entries miss 120 times. **Mutations:** `TextCacheBudget.cut`
/// cutting at `entries - 1`; `endFrame` calling `bound` with `entries: 0`.
@MainActor @Test func aWorkingSetAtOrBelowTheBudgetNeverMissesTwice() {
    let cache = ShapingCache(entryLimit: 128, costLimit: 1 << 20)
    let perFrame = misses(cache, frames: 40) { _ in
        for i in 0..<60 {
            _ = cache.shaped("row \(i)", font: font, wrappingAt: 100)
            _ = cache.caretOffsets("caret \(i)", font: font)
        }
    }
    #expect(perFrame.first == 120 && perFrame.dropFirst().allSatisfy { $0 == 0 }, "\(perFrame)")
    #expect(cache.storageCount == 60 && cache.caretStorageCount == 60)
}

/// **2** A live set over the budget is never evicted (`TS-G`, record 421): 100 strings under a budget of 64 miss once each and
/// then never, where the first version (`TS-F`) re-shaped the 36 over the budget every frame, and a window with several large
/// views re-shaped hundreds. The entries stay held. **Mutations:** `bound` offering every entry for eviction (`protectedFrom`
/// raised to the current generation + 1: 36 misses a frame); `protectedFrom` at the current generation only (every other
/// frame misses, the loop alternating halves is test 2b).
@MainActor @Test func aWorkingSetOverTheBudgetIsNeverEvicted() {
    let cache = ShapingCache(entryLimit: 64, costLimit: 1 << 20)
    let perFrame = misses(cache, frames: 12) { _ in
        for i in 0..<100 { _ = cache.shaped("row \(i)", font: font, wrappingAt: 100) }
    }
    #expect(perFrame.first == 100 && perFrame.dropFirst().allSatisfy { $0 == 0 }, "\(perFrame)")
    #expect(cache.storageCount == 100 && cache.evictionCount == 0, "the working set is held whole")
}

/// **2b** Two frames' entries are the working set, not one: a view that alternates between two halves of a list (a blinking
/// caret, a scroll that moves half a window back and forth) never re-shapes either half, and goes stale, and is evicted down to
/// the budget, once it is left alone. **Mutation:** `protectedFrom` at `currentGeneration` (every frame misses the half the
/// frame before did not touch).
@MainActor @Test func theFrameBeforeIsTheWorkingSetToo() {
    let cache = ShapingCache(entryLimit: 16, costLimit: 1 << 20)
    let perFrame = misses(cache, frames: 20) { frame in
        for i in 0..<30 { _ = cache.shaped("half \(frame % 2) row \(i)", font: font, wrappingAt: 100) }
    }
    #expect(perFrame.prefix(2).allSatisfy { $0 == 30 } && perFrame.dropFirst(2).allSatisfy { $0 == 0 }, "\(perFrame)")
    for _ in 0..<3 { cache.beginFrame(); cache.endFrame() }
    #expect(cache.storageCount == 16, "left alone, the 60 entries are stale and go down to the budget: \(cache.storageCount)")
}

/// **3** Least recently touched goes first: a string touched every frame survives a stream of fresh ones, and one touched
/// once and then left alone does not. **Mutations:** `bound` ordering generations descending; `shaped` not re-stamping a hit.
@MainActor @Test func theLeastRecentlyTouchedEntryIsTheOneEvicted() {
    let cache = ShapingCache(entryLimit: 16, costLimit: 1 << 20)
    _ = cache.shaped("touched once", font: font, wrappingAt: 100)   // generation 0, a frame of its own
    var hotMisses = 0
    for frame in 0..<30 {
        cache.beginFrame()
        let before = cache.misses
        _ = cache.shaped("hot", font: font, wrappingAt: 100)
        if cache.misses != before { hotMisses += 1 }
        for i in 0..<5 { _ = cache.shaped("fresh \(frame) \(i)", font: font, wrappingAt: 100) }
        cache.endFrame()
    }
    #expect(hotMisses == 1, "the hot string missed once, on frame 0")
    #expect(cache.storageCount <= 16 + 12, "the budget for the stale and two frames' six")
    let before = cache.misses
    _ = cache.shaped("touched once", font: font, wrappingAt: 100)
    #expect(cache.misses == before + 1, "the string nobody touched again was evicted")
}

/// **4** A long streaming paragraph (a string that grows a word per frame, shaped at three widths, with its caret line, the
/// way a measure, a draw and a field do) plus a scrolling window of rows: after every frame the cache holds at most the budget
/// of stale entries plus the two frames it must keep (24 each here), and a first draw that misses far more than the budget in
/// one frame is the working set, held whole and then bounded once it is stale (`TS-G`). **Mutations:** `trimInFrame` removed
/// (the in-frame peak of the stale reaches the whole run); `endFrame` not calling `bound`; the stale count ignoring the budget.
@MainActor @Test func aStreamingParagraphAndAScrollingListHoldTheBudgetOfStaleEntries() {
    let limit = 64
    let cache = ShapingCache(entryLimit: limit, costLimit: 1 << 20)
    var paragraph = ""
    var peak = 0
    for frame in 0..<400 {
        cache.beginFrame()
        paragraph += "word\(frame) "
        for width in [Double?.none, 300, 212] { _ = cache.shaped(paragraph, font: font, wrappingAt: width) }
        _ = cache.caretOffsets(paragraph, font: font)
        for row in frame..<(frame + 20) { _ = cache.shaped("row \(row)", font: font, wrappingAt: 120) }
        peak = max(peak, cache.heldEntryCount)
        cache.endFrame()
        #expect(cache.heldEntryCount <= limit + 2 * 24, "frame \(frame): \(cache.heldEntryCount)")
    }
    #expect(peak <= limit * 5 / 4 + 2 * 24 + 1, "a quarter over inside a frame, plus the two frames kept: \(peak)")
    // A first draw that misses ten times the budget in one frame is the working set: held whole, then bounded when stale.
    cache.beginFrame()
    for i in 0..<(10 * limit) { _ = cache.shaped("first draw \(i)", font: font, wrappingAt: nil) }
    #expect(cache.heldEntryCount >= 10 * limit, "\(cache.heldEntryCount)")
    cache.endFrame()
    for _ in 0..<3 { cache.beginFrame(); cache.endFrame() }
    #expect(cache.heldEntryCount <= limit, "stale after the frames it was drawn in: \(cache.heldEntryCount)")
}

/// **4b** The budget of stale entries is one pool: 40 shaped lines and 40 caret lines gone stale together under a budget of 64
/// leave 64, where a budget per table would leave all 80, and each table gives up its share (32 and 32), not the first all it
/// has. **Mutations:** `bound` cutting each table to the limit on its own; `shares` giving the whole allowance to the first
/// table.
@MainActor @Test func theThreeTablesShareOneBudget() {
    let cache = ShapingCache(entryLimit: 64, costLimit: 1 << 20)
    cache.beginFrame()
    for i in 0..<40 {
        _ = cache.shaped("row \(i)", font: font, wrappingAt: 100)
        _ = cache.caretOffsets("caret \(i)", font: font)
    }
    cache.endFrame()
    for _ in 0..<2 { cache.beginFrame(); cache.endFrame() }
    #expect(cache.heldEntryCount == 64 && cache.storageCount + cache.caretStorageCount == 64,
            "\(cache.storageCount) + \(cache.caretStorageCount)")
    #expect(cache.storageCount == 32 && cache.caretStorageCount == 32, "the overage is taken from each table in proportion")
}

/// **5** The byte bound holds when the count bound would not: three 600-byte strings gone stale under a weight budget of 1000
/// leave at most one, however few entries there are; while they are in use they are all kept. **Mutation:** `bound` ignoring
/// `cost`.
@MainActor @Test func aFewHugeStringsAreBoundedByTheirWeightOnceStale() {
    let cache = ShapingCache(entryLimit: 1000, costLimit: 1000)
    cache.beginFrame()
    for letter in ["a", "b", "c"] { _ = cache.shaped(String(repeating: letter, count: 600), font: font, wrappingAt: 200) }
    cache.endFrame()
    #expect(cache.storageCount == 3, "in use: \(cache.storageCount)")
    for _ in 0..<2 { cache.beginFrame(); cache.endFrame() }
    #expect(cache.storageCount == 1, "\(cache.storageCount)")
}

/// **6** The font memos hold one entry per distinct request, however many frames run and however much text streams
/// through: the bound of the two never-swept dictionaries is the app's distinct fonts. **Mutation:** `shaped` registering a
/// per-string font key.
@MainActor @Test func theFontMemosGrowWithDistinctFontsAndNotWithText() {
    let cache = ShapingCache()
    var text = ""
    for frame in 0..<200 {
        cache.beginFrame()
        text += "w\(frame) "
        let resolved = cache.resolveFont(family: nil, size: 13)
        _ = cache.shaped(text, font: resolved, wrappingAt: 200)
        _ = cache.caretOffsets(text, font: cache.resolveFont(family: nil, size: 13))
        cache.endFrame()
    }
    #expect(cache.resolvedFontCount == 1 && cache.registeredFontCount == 1)
    _ = cache.resolveFont(family: nil, size: 14)
    #expect(cache.resolvedFontCount == 2 && cache.registeredFontCount == 1, "registered by `shaped`, not by a resolve")
}

// MARK: - Caret offsets

private let strings = [
    "hello world", "", "a", "مرحبا بالعالم", "שלום world", "e\u{301}a\u{301}\u{302}x", "👨‍👩‍👧‍👦 family 🇺🇸 flag 👍🏽",
    "tab\there", "ffi fl AV To", "한글 日本語 中文"
]

/// **7** The cached offsets are the old computation's, exactly (bit for bit), on a miss and on a hit, over strings with RTL,
/// combining marks, emoji, a tab and CJK, and two fonts do not share an entry. **Mutations:** the key leaving out the font
/// (the 26 pt read returns 13 pt's); `caretOffsets` returning the offsets of a different string on a hit.
@MainActor @Test func cachedCaretOffsetsAreTheShapersOffsets() {
    let cache = ShapingCache()
    let small = font, large = FontResolver.resolve(family: nil, size: 26)
    for string in strings {
        let oracle = Shaper.caretOffsets(string, font: small)
        for _ in 0..<2 {
            let got = cache.caretOffsets(string, font: small)
            #expect(got.map(\.bitPattern) == oracle.map(\.bitPattern), "\(string)")
        }
        #expect(cache.caretOffsets(string, font: large).map(\.bitPattern) == Shaper.caretOffsets(string, font: large).map(\.bitPattern),
                "a second font: \(string)")
    }
}

/// **8** A string is typeset once while it is in use: two reads in a frame (prepaint, paint) and the same string next frame
/// are one miss; the empty string is `[0]` and never a lookup. **Mutations:** the cache not storing; the empty-string guard
/// removed (the empty string counts a miss).
@MainActor @Test func aCaretLineIsTypesetOnceWhileItsStringIsInUse() {
    let cache = ShapingCache()
    for _ in 0..<5 {
        cache.beginFrame()
        for _ in 0..<2 { _ = cache.caretOffsets("typed text", font: font) }
        #expect(cache.caretOffsets("", font: font) == [0])
        cache.endFrame()
    }
    #expect(cache.caretMisses == 1 && cache.caretHits == 9, "\(cache.caretMisses) \(cache.caretHits)")
    #expect(cache.misses == 0 && cache.hits == 0, "shaped lookups are counted apart")
}
