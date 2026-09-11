import CoreText
import Foundation

/// A font as CoreText actually resolved it, paired with the identity
/// (``FontKey``) and the metrics that were read back off it.
///
/// Deliberately **not** `Sendable`: `CTFont` is a CoreFoundation class and
/// carries no such guarantee. ``key`` and ``metrics`` are `Sendable` on their
/// own and are what crosses a boundary; the `CTFont` stays where it was made.
public struct ResolvedFont {
    public let ctFont: CTFont
    public let key: FontKey
    public let metrics: FontMetrics

    init(ctFont: CTFont) {
        self.ctFont = ctFont
        self.key = FontKey(resolved: ctFont)
        self.metrics = FontMetrics(of: ctFont)
    }
}

/// Turns a *request* — an optional family name and a point size — into a
/// ``ResolvedFont``.
public enum FontResolver {
    /// Resolves `family` at `size`. `family: nil` means the platform UI font.
    ///
    /// **The returned font's identity may not be the requested one, and that is
    /// the point.** `CTFontCreateWithName` substitutes rather than failing, so
    /// callers must key caches on ``ResolvedFont/key`` and never on `family` —
    /// see ``FontKey`` for §6.1's measurement.
    ///
    /// ## A requirement this deliberately does not meet, for M5
    ///
    /// **Ruling TX-C.** M5's zoomable canvas wants glyph *advances* proportional
    /// to point size, so that zoom folds into the atlas key's size component and
    /// a zoom step needs no re-shaping. This function does not deliver that, and
    /// removing the `opsz` pin that M2 Task 1 first shipped is what makes the
    /// gap honest rather than half-closed. The requirement is recorded here; the
    /// numbers below are what a canvas implementer needs and what an M2 reader
    /// must not mistake for a live variable on their own surface.
    ///
    /// All advances quoted are the **`CTLineGetTypographicBounds` metric** —
    /// what a shaped line actually measures, kerning included — over §6.2's
    /// 28-character string, and are per point unless stated.
    ///
    /// 1. **The optical-size axis is already constant across every size M2
    ///    ships.** Unpinned, `CTFontCreateUIFontForLanguage(.system, …)` resolves
    ///    `opsz` to `clamp(size, 17, 96)`: it reads **17 at 6, 8, 10, 12, 13, 14,
    ///    16 and 17pt alike**, tracks the point size from 18 to 96, and sticks at
    ///    96 above that. UI chrome and a code editor live at 8–17pt, where the
    ///    axis is pinned already, by the clamp. §6.2's "the axis tracks the point
    ///    size (13pt → 17, 26 → 26, 52 → 52)" is true only over 17–96pt, and
    ///    reading it as a general statement is what made a pin look necessary.
    /// 2. **Pinning `opsz` to the axis default therefore buys no linearity where
    ///    M2 lives, and costs the optical cut.** Measured against unpinned: −11.74%
    ///    at 8pt, −12.05% at 10, −12.33% at 12, −12.48% at 13, −12.60% at 14,
    ///    −12.83% at 16, −12.99% at 17 — then shrinking through 18–26pt and
    ///    **bit-identical from 28pt up**, the axis default being 28. That is not
    ///    merely narrower text: it is SF's *display* cut rendered at text size,
    ///    the exact trade the optical axis exists to avoid.
    /// 3. **A pin would not have obtained proportionality anyway.** With `opsz`
    ///    held fixed, advance-per-point still moves with size and is
    ///    non-monotonic — 12.13574 at 13pt, 11.61621 at 18pt, 12.65527 at 32pt —
    ///    settling on a bit-identical 12.2998046875 from **80pt** upward. The
    ///    residual is a hinting-driven, size-dependent advance adjustment,
    ///    quantized in integer **design units** (2048 per em) rather than at
    ///    integer ppem: a 0.125pt sweep from 12.000 to 13.000 moves the measured
    ///    advance at every step (168.357422, 169.945374, 171.362427, …), which
    ///    ppem quantization could not do.
    /// 4. **What would obtain it**, if M5 needs exactness: fix the ppem —
    ///    resolve at one reference size and carry the target size in the font
    ///    *matrix*. Measured, that is exactly proportional. It is a different
    ///    font model from this one: `CTFontGetSize` then reports the reference
    ///    size, so ``FontKey``'s identity would rest on ``FontKey/matrix``
    ///    instead of ``FontKey/size``, which every cache keyed on a `FontKey`
    ///    would feel. It belongs to the milestone that needs it.
    ///
    /// ## `size` must be finite and positive, and this traps otherwise
    ///
    /// **CoreText does not reject a bad size, and this is where one would
    /// otherwise enter every cache in the framework.** Measured on this OS with
    /// `CTFontCreateWithName("Menlo", …)` and the system-font call below:
    ///
    /// | size | named family | `family: nil` |
    /// |---|---|---|
    /// | NaN | `CTFontGetSize` is NaN | 12pt |
    /// | +inf | size and ascent infinite | size and ascent infinite |
    /// | 0 | 12pt | 13pt |
    /// | -5, -inf | 12pt | 12pt |
    ///
    /// The NaN/named cell is the one that aborted a process: ``FontKey``'s
    /// synthesized `==` compares `size` by IEEE equality, so the key was
    /// unequal to itself and `Text.requestLayout`'s measure closure could not
    /// find the font it had just registered. Every other cell draws at a size
    /// nobody asked for, or with infinite metrics, and says nothing. Both
    /// production callers — `Text`'s layout and paint phases, through
    /// ``ShapingCache/resolveFont(family:size:)`` — reach this function, so
    /// the precondition sits here rather than on either of them. A tiny
    /// positive size (1e-300 was probed) is admitted and resolves to a font
    /// with vanishing metrics: degenerate, but finite and self-equal.
    ///
    /// **Uncached.** Each call creates a `CTFont`; CoreText does not memoize
    /// `CTFontCreateUIFontForLanguage`. Per-frame callers go through
    /// ``ShapingCache/resolveFont(family:size:)``, which does.
    public static func resolve(family: String?, size: Double) -> ResolvedFont {
        // Counted only for a caller that bound a counter; see `resolveCallCounter`.
        Self.resolveCallCounter?.bump()
        precondition(size.isFinite && size > 0, """
            FontResolver.resolve(family:size:) needs a finite, positive point size; \
            got \(size). CoreText would not reject it: it substitutes 12 or 13pt, \
            or keeps a NaN or infinite size, and a NaN makes FontKey unequal to itself.
            """)
        let font: CTFont
        if let family {
            font = CTFontCreateWithName(family as CFString, CGFloat(size), nil)
        } else {
            // `CTFontCreateUIFontForLanguage` is documented to return nil for an
            // unsupported ui-font/language pair. `.system` with a nil language
            // is the one pair the system font is defined for, so the fallback
            // below is unreachable in the sense that no argument this function
            // can construct reaches it — it exists because the API is optional,
            // not because a case is expected.
            font = CTFontCreateUIFontForLanguage(.system, CGFloat(size), nil)
                ?? CTFontCreateWithName("Helvetica" as CFString, CGFloat(size), nil)
        }
        return ResolvedFont(ctFont: font)
    }

    /// Counts calls to ``resolve(family:size:)`` made while the calling task
    /// has a ``CallCounter`` bound to ``resolveCallCounter`` — the same
    /// instrument, for the same reasons, as `Shaper.RunCallCounter`: a
    /// `@TaskLocal` rather than a static, because this function is called from
    /// nonisolated tests the runner schedules concurrently, and a shared
    /// counter would describe two callers instead of one. See that type's doc
    /// comment for the race that forced the shape.
    final class CallCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        func bump() { lock.lock(); defer { lock.unlock() }; n += 1 }
        /// The number of ``FontResolver/resolve(family:size:)`` calls made
        /// while this instance was bound to ``FontResolver/resolveCallCounter``.
        var count: Int { lock.lock(); defer { lock.unlock() }; return n }
        init() {}
    }

    /// `nil` in production, where nothing binds it. **`internal`, a test
    /// instrument and not API**: both test targets that read it import
    /// `MetalUIText` with `@testable`.
    @TaskLocal static var resolveCallCounter: CallCounter?
}
