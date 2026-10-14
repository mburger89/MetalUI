import Testing
import MetalUITestSupport

// Hot paths lane 1 guard (`HP-B`, spec test 10): the `GlyphKey` stored hash is `package`, so a plain
// import of `MetalUIText` cannot read it. A `@testable` test sees `package` members and cannot show this.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUIText not found - guard skipped"

/// **HP.1.** An external module cannot read `GlyphKey.precomputedHash`; the control reads the public
/// surface of the same key in the same file shape, so the pair differs only in that member.
@Test(.enabled(if: canTypecheck(module: "MetalUIText"), skipReason))
func hp1AGlyphKeysStoredHashIsNotSpellableOutsideThePackage() throws {
    let read = try typecheckFile("""
        func probe(_ key: GlyphKey) -> Int { key.precomputedHash }
        """, importing: "MetalUIText")
    let control = try typecheckFile("""
        func probe(_ key: GlyphKey) -> Int { key.hashValue &+ Int(key.glyph) }
        """, importing: "MetalUIText")
    print("HP.1 GlyphKey stored hash: read succeeded=\(read.succeeded) messages=[\(read.messages)]; "
          + "control succeeded=\(control.succeeded)")
    try #require(control.succeeded && !read.succeeded,
                 "the control must compile and the negative must not:\ncontrol:\n\(control.output)\nread:\n\(read.output)")
    #expect(read.messages.contains("precomputedHash"), "rejected for the member:\n\(read.output)")
}
