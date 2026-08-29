import Foundation

/// A window-level cache over ``Shaper``, keyed on the CONTENT that determines
/// a shape — `(string, font, width)` — rather than on element identity (spec
/// §3.2).
///
/// **Deliberately not the `StateTable`.** `StateTable` (spec §4.3) is for
/// state that *cannot* be recomputed from an element's values: scroll offset,
/// hover, an in-progress drag. A shaped line is not that — it is a pure
/// function of its key — so putting this cache there would key on the
/// *element* rather than the *string*, and two elements showing the same text
/// would shape it twice. This type exists precisely so they don't: two
/// callers offering the same `(string, font, width)` share one entry.
///
/// **Owned by the window beside `StateTable`, `@MainActor` for the same
/// reason.** `MeasureFunction` is `@Sendable` and non-isolated, but a
/// global-actor-isolated class is implicitly `Sendable`, so *this cache* may
/// be captured by that closure even though the values it hands back may not:
/// ``ShapedText`` wraps a `CTLine` and ``ResolvedFont`` wraps a `CTFont`,
/// neither of which is `Sendable`, and `MainActor.assumeIsolated`'s closure
/// must reduce to a `Sendable` result before returning. Callers must not let
/// a `ShapedText` — or a `ResolvedFont` — escape the isolated block.
///
/// **A `ResolvedFont` cannot be captured by a `@Sendable` closure either**,
/// so it cannot travel from wherever a `Text` element is built to the
/// isolated block that later calls ``shaped(_:font:wrappingAt:)``. What
/// *can* travel is ``FontKey`` — it is `Sendable` — so the font itself lives
/// here, registered ahead of time and looked up by key from inside the
/// isolated block: ``registerFont(_:)`` and ``font(for:)`` exist for exactly
/// that call shape, so Task 4's measure function can capture a `ShapingCache`
/// and a `FontKey` and reconstitute the `ResolvedFont` only once it is
/// already on the main actor.
@MainActor
public final class ShapingCache {
    /// `(string, FontKey, width)`. `width` is compared and hashed by
    /// `bitPattern` where present — the same technique `LayoutContext`'s
    /// `MeasureKey` uses for its optional doubles — rather than by `==`,
    /// because IEEE-754 equality is not reflexive for every bit pattern
    /// (NaN) and this cache needs a total, reflexive key comparison instead.
    /// **A near-miss here — two widths a caller considers "the same" landing
    /// on different bit patterns — costs an extra recompute through
    /// ``Shaper``, never a wrong answer**: every miss falls through to the
    /// real typesetter, so the cache can only be slower than optimal, not
    /// incorrect.
    private struct Key: Hashable {
        var string: String
        var font: FontKey
        var width: Double?

        static func == (lhs: Key, rhs: Key) -> Bool {
            lhs.string == rhs.string
                && lhs.font == rhs.font
                && lhs.width?.bitPattern == rhs.width?.bitPattern
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(string)
            hasher.combine(font)
            hasher.combine(width?.bitPattern)
        }
    }

    private var storage: [Key: ShapedText] = [:]
    private var fonts: [FontKey: ResolvedFont] = [:]

    /// Cache observability, and the only way anything outside this file can
    /// see whether the cache is a cache — a ``shaped(_:font:wrappingAt:)``
    /// that never stores would leave every other behavioural test green while
    /// shaping on every single call. Pinned by `theCacheIsActuallyConsulted`.
    private(set) var hits = 0
    private(set) var misses = 0

    /// Every call to ``shaped(_:font:wrappingAt:)``, hit or miss. `hits + misses`
    /// already gives this; it is named separately because the assertion that
    /// matters is the *lookup* count — the per-run loop in `Text`'s min-content
    /// branch drives it, and a hit is not free at 604 ns.
    var lookups: Int { hits + misses }

    /// Entry count, for the bound assertion. `storage` stays private.
    var storageCount: Int { storage.count }

    public init() {}

    /// Makes `font` reachable by its ``FontKey`` from inside a later
    /// `MainActor.assumeIsolated` block, for a caller (Task 4's measure
    /// function) that can carry the `Sendable` key across a `@Sendable`
    /// closure but not the font itself. Re-registering the same key is
    /// idempotent — `FontKey` already identifies the resolved `CTFont`
    /// completely (see its doc comment), so two registrations under one key
    /// describe the same font.
    public func registerFont(_ font: ResolvedFont) {
        fonts[font.key] = font
    }

    /// The font last registered under `key`, if any.
    public func font(for key: FontKey) -> ResolvedFont? {
        fonts[key]
    }

    /// Shapes `string` in `font` at `width`, consulting the cache first.
    ///
    /// Registers `font` under its key as a side effect (see
    /// ``registerFont(_:)``), so a caller that always shapes through this
    /// method never needs to call it separately — only a caller that must
    /// look a font up *before* it has one to shape with (Task 4, across the
    /// isolation boundary) does.
    public func shaped(_ string: String, font: ResolvedFont, wrappingAt width: Double?) -> ShapedText {
        registerFont(font)

        let key = Key(string: string, font: font.key, width: width)
        if let cached = storage[key] {
            hits += 1
            return cached
        }

        misses += 1
        let result = Shaper.shape(string, font: font, wrappingAt: width)
        storage[key] = result
        return result
    }
}
