import Testing
import MetalUITextSystem
@testable import MetalUIPortableText

// R4-2 PR B (`DS-F`, record 203): `TextFontMetrics.capHeight` through the portable system is the face's
// `OS/2.sCapHeight` scaled by `size / unitsPerEm`. Pure (no CoreText), so it runs on Linux and Windows. The
// literals are the faces' own: Noto Sans 714 and Source Sans 3 660 per mille of the em (record 202 section 2,
// equal to `CTFontGetCapHeight` at 13 pt: 9.282 and 8.58, probe `swiftui-default-spacing-run.txt` DS2).

@MainActor
private func capHeight(_ file: String, size: Double) throws -> Double? {
    let resolver = try PortableFontResolver(defaultFont: fontBytes(file))
    let system = PortableTextSystem(resolver: resolver)
    return system.fontMetrics(system.resolveFont(FontDescriptor(family: nil, size: size))).capHeight
}

/// Mutation: `capHeight` read from `sxHeight` (the x-height, 6.968 and 6.318 at 13), or left `nil`.
@MainActor
@Test(arguments: [(notoSans, 0.714), (sourceSans, 0.660)]) func theCapHeightIsTheFacesOS2Value(file: String, perEm: Double) throws {
    for size in [13.0, 26, 48] {
        let cap = try #require(try capHeight(file, size: size), "\(file) at \(size) reports a cap height")
        #expect(abs(cap - perEm * size) < 1e-6, "\(file) at \(size): \(cap) vs \(perEm * size)")
    }
}
