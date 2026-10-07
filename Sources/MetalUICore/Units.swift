/// Boilerplate shared by every scalar unit. Deliberately NOT `Numeric`:
/// `Pixels * Pixels` is meaningless and must not compile.
public protocol ScalarUnit: Hashable, Comparable, Sendable, AdditiveArithmetic,
                            ExpressibleByFloatLiteral, ExpressibleByIntegerLiteral {
    var value: Float { get set }
    init(_ value: Float)
}

extension ScalarUnit {
    /// A value from a floating-point literal: `Pixels` can be written `12.5`.
    public init(floatLiteral v: Double) { self.init(Float(v)) }
    /// A value from an integer literal: `Pixels` can be written `12`.
    public init(integerLiteral v: Int) { self.init(Float(v)) }
    /// Zero in this unit.
    public static var zero: Self { Self(0) }
    /// Orders two values of the same unit.
    public static func < (l: Self, r: Self) -> Bool { l.value < r.value }
    /// The sum of two values of the same unit.
    public static func + (l: Self, r: Self) -> Self { Self(l.value + r.value) }
    /// The difference of two values of the same unit.
    public static func - (l: Self, r: Self) -> Self { Self(l.value - r.value) }
    /// The value scaled by a unitless factor.
    public static func * (l: Self, r: Float) -> Self { Self(l.value * r) }
    /// The value divided by a unitless factor.
    public static func / (l: Self, r: Float) -> Self { Self(l.value / r) }
    /// The value negated.
    public static prefix func - (v: Self) -> Self { Self(-v.value) }
}

/// Logical points, as the windowing system reports them.
public struct Pixels: ScalarUnit {
    /// The number of points.
    public var value: Float
    /// A length of `value` points.
    public init(_ value: Float) { self.value = value }
    /// Convert to the render target's coordinate space.
    public func scaled(by factor: Float) -> ScaledPixels { ScaledPixels(value * factor) }
}

extension Pixels {
    /// An infinite length — SwiftUI's `.infinity`, so `.frame(maxWidth:
    /// .infinity)` is written as in SwiftUI (ruling `PE-F` item 2,
    /// `docs/superpowers/2026-10-06-proposal-controls-decisions.md`). The same
    /// value as `Pixels(.infinity)`; where a length must be finite it traps or
    /// is refused exactly as that spelling is.
    public static var infinity: Pixels { Pixels(.infinity) }
}

/// Logical points multiplied by the display scale factor. What shaders see.
public struct ScaledPixels: ScalarUnit {
    /// The number of scaled pixels.
    public var value: Float
    /// A length of `value` scaled pixels.
    public init(_ value: Float) { self.value = value }
}

/// Physical device pixels, always integral.
public struct DevicePixels: Hashable, Comparable, Sendable {
    /// The number of device pixels.
    public var value: Int32
    /// A length of `value` device pixels.
    public init(_ value: Int32) { self.value = value }
    /// Orders two device-pixel values.
    public static func < (l: Self, r: Self) -> Bool { l.value < r.value }
}

/// Sizes relative to the root font size.
public struct Rems: ScalarUnit {
    /// The number of root font sizes.
    public var value: Float
    /// A length of `value` rems.
    public init(_ value: Float) { self.value = value }
}

/// A value that is always required. Has no `auto` case — see `Dimension`.
public enum Length: Hashable, Sendable {
    case pixels(Pixels)
    case rems(Rems)

    /// A **fraction** of the containing block, not a percentage: `0.5` is half.
    /// It resolves to `f * parent` (the CSS engine's `resolveLength`, deleted at
    /// stage 9, and the lowering's own reading; a lowered percentage reports by
    /// name), and every call site in `Sources/` passes `0.5`, `0.25`, `0.10`.
    ///
    /// **`MetalUI`'s `width(fraction:)`/`height(fraction:)`/`flexBasis(fraction:)`
    /// forward their argument to this case untouched**, pinned on the legacy
    /// authority by `aFractionSizeResolvesAgainstItsContainingBlock` until stage
    /// 7b retired it (record §49 §4 row 203). Their old `percent:`
    /// names, fractions wearing a percentage's name (`width(percent: 50)` means
    /// 5000%, ruling `FR-T`), are deprecated renames (ruling `CN-O`,
    /// `docs/superpowers/2026-09-16-containers-decisions.md`).
    case percent(Float)
}

/// A sizing value, which may be automatic.
public enum Dimension: Hashable, Sendable {
    case length(Length)
    case auto
}
