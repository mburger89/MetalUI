import Foundation

/// A value an animation interpolates — SwiftUI's `VectorArithmetic` (C10 lane 2, ruling `LK-I` item 8): a
/// value that adds, subtracts, scales by a `Double` and measures its own length.
///
/// It is the data of an ``Animatable``: ``Animatable/AnimatableData``. `Double`, `CGFloat`, ``Angle``,
/// ``AnimatablePair`` and ``EmptyAnimatableData`` conform, and ``Float``, which is a MetalUI extra
/// (divergence 169). A keyframe track's value is ``Animatable``, not this protocol.
public protocol VectorArithmetic: AdditiveArithmetic {
    /// Multiplies every component of this value by `rhs`.
    mutating func scale(by rhs: Double)

    /// This value's dot product with itself.
    var magnitudeSquared: Double { get }
}

extension VectorArithmetic {
    /// A copy multiplied by `k` — SwiftUI's public `scaled(by:)` (probe `VT12`).
    public func scaled(by k: Double) -> Self {
        var copy = self
        copy.scale(by: k)
        return copy
    }
}

extension Double: VectorArithmetic {
    /// Multiplies this value by `rhs` (``VectorArithmetic``).
    public mutating func scale(by rhs: Double) { self *= rhs }

    /// This value squared (``VectorArithmetic``).
    public var magnitudeSquared: Double { self * self }
}

extension Float: VectorArithmetic {
    /// Multiplies this value by `rhs` (``VectorArithmetic``).
    public mutating func scale(by rhs: Double) { self = Float(Double(self) * rhs) }

    /// This value squared (``VectorArithmetic``).
    public var magnitudeSquared: Double { Double(self) * Double(self) }
}

extension CGFloat: VectorArithmetic {
    /// Multiplies this value by `rhs` (``VectorArithmetic``).
    public mutating func scale(by rhs: Double) { self = CGFloat(Double(self) * rhs) }

    /// This value squared (``VectorArithmetic``).
    public var magnitudeSquared: Double { Double(self) * Double(self) }
}

extension Angle: VectorArithmetic {
    /// Multiplies this angle's radians by `rhs` (``VectorArithmetic``).
    public mutating func scale(by rhs: Double) { radians *= rhs }

    /// This angle's radians squared (``VectorArithmetic``).
    public var magnitudeSquared: Double { radians * radians }
}
