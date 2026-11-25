import Foundation
import Testing
@testable import MetalUIPortableText
import MetalUITextSystem

// The portable system's caret-offsets cache (`TS-F`, record 411): the old computation's answers, kept for the two frames a
// measurement is, and counted apart from shaped lookups.

private let strings = caretContractStrings + ["مرحبا بالعالم", "שלום world", "한글 日本語 中文", "ffi fl AV To"]

/// **1** The cached offsets are `PortableText.caretOffsets`' exactly, on a miss and on a hit, over RTL, combining marks, emoji
/// and CJK, and a second size does not share an entry. **Mutations:** the key leaving out the font; the hit returning the
/// offsets of another string.
@MainActor @Test func portableCaretOffsetsAreTheOldComputationsOnAMissAndOnAHit() throws {
    let resolver = try PortableFontResolver(defaultFont: fontBytes(notoSans))
    try resolver.register(fontBytes(notoSansArabic))
    let system = PortableTextSystem(resolver: resolver)
    let small = system.resolveFont(family: nil, size: 13), large = system.resolveFont(family: nil, size: 26)
    for text in strings {
        for key in [small, large] {
            let oracle = try PortableText.caretOffsets(text, font: resolver.resolve(FontDescriptor(family: nil, size: key.size)))
            for _ in 0..<2 {
                #expect(system.caretOffsets(text, font: key).map(\.bitPattern) == oracle.map(\.bitPattern),
                        "\(text.debugDescription) at \(key.size)")
            }
        }
    }
}

/// **2** A string is laid out once while it is in use: two reads in a frame and the same string in the next are one miss; it
/// survives one frame it was not asked in and not two; the empty string is `[0]` and never a lookup. **Mutations:** the
/// cache not storing; `endFrame` not filtering the caret dictionary (the third assertion); the filter keeping three frames.
@MainActor @Test func aPortableCaretLineIsLaidOutOnceWhileItsStringIsInUse() throws {
    let system = try PortableTextSystem(resolver: PortableFontResolver(defaultFont: fontBytes(notoSans)))
    let key = system.resolveFont(family: nil, size: 13)
    for _ in 0..<4 {
        system.beginFrame()
        for _ in 0..<2 { _ = system.caretOffsets("typed text", font: key) }
        #expect(system.caretOffsets("", font: key) == [0])
        system.endFrame()
    }
    #expect(system.caretMisses == 1 && system.caretHits == 7, "\(system.caretMisses) \(system.caretHits)")
    system.beginFrame(); system.endFrame()   // one frame without it: still held
    system.beginFrame(); _ = system.caretOffsets("typed text", font: key); system.endFrame()
    #expect(system.caretMisses == 1, "held across one idle frame")
    for _ in 0..<2 { system.beginFrame(); system.endFrame() }
    system.beginFrame(); _ = system.caretOffsets("typed text", font: key); system.endFrame()
    #expect(system.caretMisses == 2, "dropped after two")
}

/// **3** The portable tables share one budget on top of their two-frame lifetime (`TS-F`): a frame that lays out 40 strings
/// under a budget of 12 holds a quarter over it at most while it runs and 12 after it. A weight budget of 1000 leaves one of three
/// 600-byte strings. **Mutations:** `endFrame` not calling `bound`; `trimInFrame`
/// removed (the in-frame peak is 40); `removeOlder` cutoff left at three frames (not this test); the weight ignored.
@MainActor @Test func thePortableTablesStayUnderTheBudgetEvenWhenOneFrameLooksUpMoreThanIt() throws {
    let resolver = try PortableFontResolver(defaultFont: fontBytes(notoSans))
    let system = PortableTextSystem(resolver: resolver, entryLimit: 12, costLimit: 1 << 20)
    let key = system.resolveFont(family: nil, size: 13)
    var peak = 0
    for frame in 0..<10 {
        system.beginFrame()
        for i in 0..<40 {
            _ = system.caretOffsets("frame \(frame) string \(i)", font: key)
            peak = max(peak, system.heldEntryCount)
        }
        system.endFrame()
        #expect(system.heldEntryCount <= 12, "frame \(frame): \(system.heldEntryCount)")
    }
    #expect(peak <= 12 * 5 / 4 + 1, "a quarter over inside a frame: \(peak)")
    // A frame a little over the budget but under the in-frame limit is cut at its end, not left a quarter over.
    let overshoot = PortableTextSystem(resolver: resolver, entryLimit: 12, costLimit: 1 << 20)
    let overshootKey = overshoot.resolveFont(family: nil, size: 13)
    overshoot.beginFrame()
    for i in 0..<14 { _ = overshoot.caretOffsets("small overshoot \(i)", font: overshootKey) }
    #expect(overshoot.heldEntryCount == 14)
    overshoot.endFrame()
    #expect(overshoot.heldEntryCount <= 12, "\(overshoot.heldEntryCount)")
    let heavy = PortableTextSystem(resolver: resolver, entryLimit: 100, costLimit: 1000)
    let heavyKey = heavy.resolveFont(family: nil, size: 13)
    heavy.beginFrame()
    for letter in ["a", "b", "c"] { _ = heavy.caretOffsets(String(repeating: letter, count: 600), font: heavyKey) }
    heavy.endFrame()
    #expect(heavy.heldEntryCount == 1, "\(heavy.heldEntryCount)")
}
