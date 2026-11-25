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

/// **1** A working set at or below the cap misses once per string, ever: 60 strings looped for 40 frames under a cap of 64
/// shape 60 times, in the plain, the styled-free and the caret dictionaries alike. **Mutations:** `bound` evicting at
/// `entries - 1`; `endFrame` calling `bound` with `entries: 0`.
@MainActor @Test func aWorkingSetAtOrBelowTheCapNeverMissesTwice() {
    let cache = ShapingCache(entryCap: 64, costCap: 1 << 19)
    let perFrame = misses(cache, frames: 40) { _ in
        for i in 0..<60 {
            _ = cache.shaped("row \(i)", font: font, wrappingAt: 100)
            _ = cache.caretOffsets("caret \(i)", font: font)
        }
    }
    #expect(perFrame.first == 120 && perFrame.dropFirst().allSatisfy { $0 == 0 }, "\(perFrame)")
    #expect(cache.storageCount == 60 && cache.caretStorageCount == 60)
}

/// **2** A live set over the cap re-shapes the overage and no more, every frame, and holds the cap: 100 strings under a cap
/// of 64 miss 36 a frame after the first, not 100 (the loop a strict LRU turns into all misses). **Mutations:** `bound`
/// evicting the newest generation first (the hot string below is lost); `bound` stopping at `entries * 2` (the count
/// check); the within-generation drop keyed by insertion order (every frame misses 100).
@MainActor @Test func aWorkingSetOverTheCapReShapesTheOverageAndNoMore() {
    let cache = ShapingCache(entryCap: 64, costCap: 1 << 19)
    let perFrame = misses(cache, frames: 12) { _ in
        for i in 0..<100 { _ = cache.shaped("row \(i)", font: font, wrappingAt: 100) }
    }
    #expect(perFrame.first == 100, "\(perFrame)")
    #expect(perFrame.dropFirst().allSatisfy { $0 == 36 }, "the overage, 100 - 64, every frame: \(perFrame)")
    #expect(cache.storageCount == 64, "held at the cap after a frame")
}

/// **3** Least recently touched goes first: a string touched every frame survives a stream of fresh ones, and one touched
/// once and then left alone does not. **Mutations:** `bound` ordering generations descending; `shaped` not re-stamping a hit.
@MainActor @Test func theLeastRecentlyTouchedEntryIsTheOneEvicted() {
    let cache = ShapingCache(entryCap: 16, costCap: 1 << 19)
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
    #expect(cache.storageCount <= 16)
    let before = cache.misses
    _ = cache.shaped("touched once", font: font, wrappingAt: 100)
    #expect(cache.misses == before + 1, "the string nobody touched again was evicted")
}

/// **4** A long streaming paragraph (a string that grows a word per frame, shaped at two widths, the way a measure and a draw
/// do) plus a scrolling window of rows stays under the cap after every frame and under twice the cap inside one, in all
/// three dictionaries. **Mutations:** `trimInFrame` removed (the in-frame peak reaches the frame's miss count); `endFrame`
/// not bounding `caretStorage`.
@MainActor @Test func aStreamingParagraphAndAScrollingListStayUnderTheCap() {
    let cap = 32
    let cache = ShapingCache(entryCap: cap, costCap: 1 << 19)
    var paragraph = ""
    var peak = 0
    for frame in 0..<400 {
        cache.beginFrame()
        paragraph += "word\(frame) "
        for width in [Double?.none, 300, 212] { _ = cache.shaped(paragraph, font: font, wrappingAt: width) }
        _ = cache.caretOffsets(paragraph, font: font)
        for row in frame..<(frame + 20) { _ = cache.shaped("row \(row)", font: font, wrappingAt: 120) }
        peak = max(peak, cache.storageCount, cache.caretStorageCount)
        cache.endFrame()
        #expect(cache.storageCount <= cap && cache.caretStorageCount <= cap, "frame \(frame)")
    }
    #expect(peak <= 2 * cap, "inside a frame the bound is twice the cap: \(peak)")
    // A first draw that misses far more than the cap in one frame is held to twice the cap before its frame ends.
    cache.beginFrame()
    for i in 0..<(10 * cap) { _ = cache.shaped("first draw \(i)", font: font, wrappingAt: nil) }
    #expect(cache.storageCount <= 2 * cap + 1, "\(cache.storageCount)")
    cache.endFrame()
    #expect(cache.storageCount <= cap)
}

/// **5** The byte bound holds when the count bound would not: three 600-byte strings under a cost cap of 1000 leave at most
/// one, however few entries there are. **Mutation:** `bound` ignoring `cost`.
@MainActor @Test func aFewHugeStringsAreBoundedByTheirWeight() {
    let cache = ShapingCache(entryCap: 1000, costCap: 1000)
    cache.beginFrame()
    for letter in ["a", "b", "c"] { _ = cache.shaped(String(repeating: letter, count: 600), font: font, wrappingAt: 200) }
    cache.endFrame()
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
    "tab\there", "ffi fl AV To", "한글 日本語 中文",
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
