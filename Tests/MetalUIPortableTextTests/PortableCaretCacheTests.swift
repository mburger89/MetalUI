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
