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
