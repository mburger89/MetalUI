import Testing
import MetalUIText

// `FontResolver.resolve(family:size:)` rejects a point size that is not finite
// and positive. Every arm below is one CoreText behaviour that, without the
// precondition, returned a font rather than failing — measured on this OS with
// `CTFontCreateWithName("Menlo", …)` and `CTFontCreateUIFontForLanguage(.system, …)`:
//
// | size   | named family                  | `family: nil` (system font) |
// |--------|-------------------------------|-----------------------------|
// | NaN    | size NaN, `key == key` false  | silently 12pt               |
// | +inf   | size inf, ascent inf          | size inf, ascent inf        |
// | 0      | silently 12pt                 | silently 13pt               |
// | -5     | silently 12pt                 | silently 12pt               |
//
// The NaN/named row is the one that aborted a process: `FontKey`'s synthesized
// `==` made the key unequal to itself, so `ShapingCache.font(for:)` missed the
// font `Text.requestLayout` had just registered, and the measure closure's
// `preconditionFailure` fired blaming cache identity. The other rows never
// trapped — they drew at a size nobody asked for, or with infinite metrics.
//
// Plain `import`, not `@testable`: `resolve` is public, and these arms are about
// what a public caller can reach.

@Test func aNaNSizeTrapsOnTheNamedFamilyPath() async {
    await #expect(processExitsWith: .failure) {
        _ = FontResolver.resolve(family: "Menlo", size: .nan)
    }
}

@Test func aNaNSizeTrapsOnTheSystemFontPath() async {
    await #expect(processExitsWith: .failure) {
        _ = FontResolver.resolve(family: nil, size: .nan)
    }
}

@Test func anInfiniteSizeTraps() async {
    await #expect(processExitsWith: .failure) {
        _ = FontResolver.resolve(family: nil, size: .infinity)
    }
}

@Test func aZeroSizeTraps() async {
    await #expect(processExitsWith: .failure) {
        _ = FontResolver.resolve(family: nil, size: 0)
    }
}

@Test func aNegativeSizeTraps() async {
    await #expect(processExitsWith: .failure) {
        _ = FontResolver.resolve(family: "Menlo", size: -5)
    }
}

/// The `.success` arm: the precondition is not broader than the domain. Both
/// paths, a whole size and a sub-point one (so a `size >= 1` spelling reddens
/// this), and each key is reflexive and carries the size that was asked for.
@Test func aFinitePositiveSizeResolvesOnBothPaths() async {
    await #expect(processExitsWith: .success) {
        for family in [nil, "Menlo"] as [String?] {
            for size in [13.0, 0.5] {
                let key = FontResolver.resolve(family: family, size: size).key
                precondition(key == key)
                precondition(key.size == size)
            }
        }
    }
}
