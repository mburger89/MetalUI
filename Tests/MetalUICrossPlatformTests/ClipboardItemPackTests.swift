import Testing
import MetalUIPlatform

// `ClipboardItemPack` (rulings `CP-C`, `CP-D`; spec test 2.8): the framed multi-item pack SDL carries
// in one private mime. Portable, so macOS pins what Linux and Windows run.

private typealias Entry = ClipboardItemPack.Entry

/// 2.8a — three items (one empty, one with a hostile name, one with empty bytes) round-trip in order.
/// Mutation: write the representation count as the item count.
@Test func theItemPackRoundTripsThreeItemsAnEmptyOneAndAHostileName() throws {
    let items: [[Entry]] = [
        [Entry(identifier: "com.acme.graph", bytes: [1, 2, 3]), Entry(identifier: "public.utf8-plain-text", bytes: Array("hi".utf8))],
        [],
        [Entry(identifier: "Com.Acme/%00 \u{1F600}", bytes: []), Entry(identifier: "x", bytes: [255, 0, 7])],
    ]
    let bytes = try #require(ClipboardItemPack.encode(items))
    let decoded = try #require(ClipboardItemPack.decode(bytes))
    #expect(decoded == items)
}

/// 2.8b — decode answers `nil`, never traps, on every prefix of a valid pack, a bad magic, trailing
/// bytes, an over-count and an over-length. Mutation: skip the `take` bounds check (a truncated pack then
/// decodes or traps, which reddens this test).
@Test func theItemPackDecodesNilOnAnyViolation() throws {
    let items: [[Entry]] = [[Entry(identifier: "a.b", bytes: [9, 9, 9, 9])], [Entry(identifier: "c", bytes: [1])]]
    let bytes = try #require(ClipboardItemPack.encode(items))
    for length in 0..<bytes.count { #expect(ClipboardItemPack.decode(Array(bytes[0..<length])) == nil, "prefix \(length)") }
    var badMagic = bytes
    badMagic[0] ^= 0xff
    #expect(ClipboardItemPack.decode(badMagic) == nil)
    #expect(ClipboardItemPack.decode(bytes + [0]) == nil, "trailing bytes")
    var overCount = bytes
    overCount[4] = 0xff; overCount[5] = 0xff; overCount[6] = 0xff; overCount[7] = 0x7f
    #expect(ClipboardItemPack.decode(overCount) == nil)
    var overLength = bytes
    // the first representation's data length sits after magic(4) count(4) reps(4) nameLen(4) name(3)
    overLength[19] = 0xff; overLength[20] = 0xff; overLength[21] = 0xff; overLength[22] = 0x7f
    #expect(ClipboardItemPack.decode(overLength) == nil)
    #expect(ClipboardItemPack.decode([]) == nil)
}

/// 2.8c — the encoder refuses a pack over its item limit and the mime is the `ClipboardMime` spelling of
/// `com.metalui.clipboard-items`. Mutation: change the mime string.
@Test func theItemPackLimitsAndMimeAreTheRuled() {
    #expect(ClipboardItemPack.encode(Array(repeating: [], count: ClipboardItemPack.maxItems + 1)) == nil)
    #expect(ClipboardItemPack.encode(Array(repeating: [], count: ClipboardItemPack.maxItems)) != nil)
    #expect(ClipboardItemPack.mime == ClipboardMime.mime(forIdentifier: "com.metalui.clipboard-items"))
}
