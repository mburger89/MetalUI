/// Boilerplate shared by every scalar unit. Deliberately NOT `Numeric`:
/// `Pixels * Pixels` is meaningless and must not compile.
public protocol ScalarUnit: Hashable, Comparable, Sendable, AdditiveArithmetic,
                            ExpressibleByFloatLiteral, ExpressibleByIntegerLiteral {
    var value: Float { get set }
    init(_ value: Float)
}

extension ScalarUnit {
    public init(floatLiteral v: Double) { self.init(Float(v)) }
    public init(integerLiteral v: Int) { self.init(Float(v)) }
    public static var zero: Self { Self(0) }
    public static func < (l: Self, r: Self) -> Bool { l.value < r.value }
    public static func + (l: Self, r: Self) -> Self { Self(l.value + r.value) }
    public static func - (l: Self, r: Self) -> Self { Self(l.value - r.value) }
    public static func * (l: Self, r: Float) -> Self { Self(l.value * r) }
    public static func / (l: Self, r: Float) -> Self { Self(l.value / r) }
    public static prefix func - (v: Self) -> Self { Self(-v.value) }
}

/// Logical points, as the windowing system reports them.
public struct Pixels: ScalarUnit {
    public var value: Float
    public init(_ value: Float) { self.value = value }
    /// Convert to the render target's coordinate space.
    public func scaled(by factor: Float) -> ScaledPixels { ScaledPixels(value * factor) }
}

/// Logical points multiplied by the display scale factor. What shaders see.
public struct ScaledPixels: ScalarUnit {
    public var value: Float
    public init(_ value: Float) { self.value = value }
}

/// Physical device pixels, always integral.
public struct DevicePixels: Hashable, Comparable, Sendable {
    public var value: Int32
    public init(_ value: Int32) { self.value = value }
    public static func < (l: Self, r: Self) -> Bool { l.value < r.value }
}

/// Sizes relative to the root font size.
public struct Rems: ScalarUnit {
    public var value: Float
    public init(_ value: Float) { self.value = value }
}

/// A value that is always required. Has no `auto` case — see `Dimension`.
public enum Length: Hashable, Sendable {
    case pixels(Pixels)
    case rems(Rems)

    /// A **fraction** of the containing block, not a percentage: `0.5` is half.
    /// `resolveLength` is `f * parent`, and every call site in `Sources/` and
    /// in the layout fixtures passes `0.5`, `0.25`, `0.10`.
    ///
    /// **`MetalUI`'s `width(percent:)`/`height(percent:)`/`flexBasis(percent:)`
    /// forward their argument to this case untouched**, so those parameters are
    /// fractions wearing a percentage's name and `width(percent: 50)` means
    /// 5000% — ruling `FR-T`
    /// (`docs/superpowers/2026-09-15-frame-sizing-decisions.md`), pinned by
    /// `aPercentageSizeTakesAFractionAndResolvesAgainstItsContainingBlock`.
    case percent(Float)
}

/// A sizing value, which may be automatic.
public enum Dimension: Hashable, Sendable {
    case length(Length)
    case auto
}
