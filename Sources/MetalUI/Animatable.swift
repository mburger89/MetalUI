import Foundation

// SwiftUI's `Animatable` (R4-3 PR D, rulings `VA-`; probe `docs/probes/swiftui-animatable.swift`).
// A type that exposes the numbers an animation interpolates as one `VectorArithmetic` value. The protocol is
// NONISOLATED, as SwiftUI's is (`VT`), so `Double`, `CGFloat` and a keyframe timeline stay free of isolation.

/// A type whose animating data is a ``VectorArithmetic`` value — SwiftUI's `Animatable`.
///
/// A ``Shape`` is `Animatable`: under a transaction that changes its ``animatableData``, the shape is painted
/// at the interpolated data (`VA1`). A shape that declares nothing has ``EmptyAnimatableData`` and snaps (`VA2`).
///
/// **The setter must not write an `@Observable`**: a shape's data is interpolated while the frame paints, and
/// a write from a phase is silently stale (CLAUDE.md "Write state from input, never from a phase").
///
/// ``Float`` also conforms, a MetalUI extra (divergence 169): SwiftUI's `Float` is a `VectorArithmetic` but not
/// `Animatable`, so a `Float` track written for MetalUI still compiles and a port never breaks on the superset.
public protocol Animatable {
    /// The data being animated.
    associatedtype AnimatableData: VectorArithmetic

    /// The data a transaction interpolates.
    var animatableData: AnimatableData { get set }
}

extension Animatable where Self: VectorArithmetic {
    /// A ``VectorArithmetic`` type animates as itself.
    public var animatableData: Self {
        get { self }
        set { self = newValue }
    }
}

extension Animatable where AnimatableData == EmptyAnimatableData {
    /// A type with no animating data (``EmptyAnimatableData``): the default, which snaps.
    public var animatableData: EmptyAnimatableData {
        get { EmptyAnimatableData() }
        // swiftlint:disable:next unused_setter_value
        set {}
    }
}

/// The animatable data of a type that animates nothing — SwiftUI's `EmptyAnimatableData`.
public struct EmptyAnimatableData: VectorArithmetic, Sendable {
    /// The one value.
    public init() {}
    /// Adds nothing (``AdditiveArithmetic``).
    public static func + (lhs: EmptyAnimatableData, rhs: EmptyAnimatableData) -> EmptyAnimatableData { lhs }
    /// Subtracts nothing (``AdditiveArithmetic``).
    public static func - (lhs: EmptyAnimatableData, rhs: EmptyAnimatableData) -> EmptyAnimatableData { lhs }
    /// Zero (``AdditiveArithmetic``).
    public static var zero: EmptyAnimatableData { EmptyAnimatableData() }
    /// Scales nothing (``VectorArithmetic``).
    public mutating func scale(by rhs: Double) {}
    /// Zero (``VectorArithmetic``).
    public var magnitudeSquared: Double { 0 }
}

/// Two animating values as one — SwiftUI's `AnimatablePair`.
public struct AnimatablePair<First: VectorArithmetic, Second: VectorArithmetic>: VectorArithmetic {
    /// The first value.
    public var first: First
    /// The second value.
    public var second: Second

    /// A pair of `first` and `second`.
    public init(_ first: First, _ second: Second) {
        self.first = first
        self.second = second
    }

    /// Both components zero (``AdditiveArithmetic``).
    public static var zero: AnimatablePair { AnimatablePair(First.zero, Second.zero) }
    /// Componentwise sum (``AdditiveArithmetic``).
    public static func + (lhs: AnimatablePair, rhs: AnimatablePair) -> AnimatablePair {
        AnimatablePair(lhs.first + rhs.first, lhs.second + rhs.second)
    }
    /// Componentwise difference (``AdditiveArithmetic``).
    public static func - (lhs: AnimatablePair, rhs: AnimatablePair) -> AnimatablePair {
        AnimatablePair(lhs.first - rhs.first, lhs.second - rhs.second)
    }
    /// Scales both components (``VectorArithmetic``).
    public mutating func scale(by rhs: Double) {
        first.scale(by: rhs)
        second.scale(by: rhs)
    }
    /// The sum of both components' squared lengths (``VectorArithmetic``).
    public var magnitudeSquared: Double { first.magnitudeSquared + second.magnitudeSquared }
}

extension AnimatablePair: Sendable where First: Sendable, Second: Sendable {}
extension AnimatablePair: Equatable where First: Equatable, Second: Equatable {}

extension Double: Animatable {
    /// A `Double` animates as itself.
    public typealias AnimatableData = Double

    /// Itself.
    public var animatableData: Double {
        get { self }
        set { self = newValue }
    }
}

extension CGFloat: Animatable {
    /// A `CGFloat` animates as itself.
    public typealias AnimatableData = CGFloat

    /// Itself.
    public var animatableData: CGFloat {
        get { self }
        set { self = newValue }
    }
}

extension Angle: Animatable {
    /// An `Angle` animates as itself (its radians).
    public typealias AnimatableData = Angle

    /// Itself.
    public var animatableData: Angle {
        get { self }
        set { self = newValue }
    }
}

/// A MetalUI extra (divergence 169): SwiftUI's `Float` is not `Animatable`.
extension Float: Animatable {
    /// A `Float` animates as itself.
    public typealias AnimatableData = Float

    /// Itself.
    public var animatableData: Float {
        get { self }
        set { self = newValue }
    }
}

extension UnitPoint: Animatable {
    /// `x` and `y`.
    public typealias AnimatableData = AnimatablePair<Double, Double>
    /// `x` and `y` as a pair.
    public var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(x, y) }
        set { x = newValue.first; y = newValue.second }
    }
}

extension CGPoint: Animatable {
    /// `x` and `y`.
    public typealias AnimatableData = AnimatablePair<CGFloat, CGFloat>
    /// `x` and `y` as a pair.
    public var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(x, y) }
        set { x = newValue.first; y = newValue.second }
    }
}

extension CGSize: Animatable {
    /// `width` and `height`.
    public typealias AnimatableData = AnimatablePair<CGFloat, CGFloat>
    /// `width` and `height` as a pair.
    public var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(width, height) }
        set { width = newValue.first; height = newValue.second }
    }
}

extension CGRect: Animatable {
    /// The origin and the size.
    public typealias AnimatableData = AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>>

    /// The origin and the size as a pair.
    public var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(AnimatablePair(origin.x, origin.y), AnimatablePair(size.width, size.height)) }
        set {
            origin = CGPoint(x: newValue.first.first, y: newValue.first.second)
            size = CGSize(width: newValue.second.first, height: newValue.second.second)
        }
    }
}

extension EdgeInsets: Animatable {
    /// The four insets.
    public typealias AnimatableData = AnimatablePair<CGFloat, AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>>>
    /// The four insets, in SwiftUI's order: top, leading, bottom, trailing.
    public var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>>> {
        get {
            AnimatablePair(CGFloat(top.value), AnimatablePair(CGFloat(leading.value),
                AnimatablePair(CGFloat(bottom.value), CGFloat(trailing.value))))
        }
        set {
            top = Pixels(Float(newValue.first))
            leading = Pixels(Float(newValue.second.first))
            bottom = Pixels(Float(newValue.second.second.first))
            trailing = Pixels(Float(newValue.second.second.second))
        }
    }
}
