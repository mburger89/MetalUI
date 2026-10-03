import MetalUICore

// Paths, shadows and transforms, lane 2 (ruling `GX-C`'s value type, `GX-H`'s
// reader). Spec `docs/superpowers/specs/2026-10-02-paths-shadows-transforms-design.md` §1.

/// A geometric angle — SwiftUI's `Angle`, read by `rotationEffect(_:anchor:)`
/// (and, from lane 3, `Path.addArc`). Stored in radians; `degrees` is derived.
///
/// Positive angles turn **visually clockwise** in MetalUI's y-down window
/// coordinates, as SwiftUI's do (probe `swiftui-paths-shadows-transforms.swift`
/// arms T1, T2, T2b). The sine and cosine an effect reads come from
/// `MetalUIPath`'s own `sinCos`, so one angle gives the same affine on every
/// platform (`GX-H`).
public struct Angle: Hashable, Comparable, Sendable {
    /// The angle in radians.
    public var radians: Double

    /// The angle in degrees: `radians × 180 / π`. Setting it sets `radians`.
    public var degrees: Double {
        get { radians * 180 / Double.pi }
        set { radians = newValue * Double.pi / 180 }
    }

    /// The zero angle.
    public init() { radians = 0 }

    /// An angle of `radians` radians.
    public init(radians: Double) { self.radians = radians }

    /// An angle of `degrees` degrees.
    public init(degrees: Double) { self.radians = degrees * Double.pi / 180 }

    /// An angle of `radians` radians.
    public static func radians(_ radians: Double) -> Angle { Angle(radians: radians) }

    /// An angle of `degrees` degrees.
    public static func degrees(_ degrees: Double) -> Angle { Angle(degrees: degrees) }

    /// The zero angle.
    public static let zero = Angle()

    /// Orders by `radians`.
    public static func < (lhs: Angle, rhs: Angle) -> Bool { lhs.radians < rhs.radians }

    /// The sum of two angles.
    public static func + (lhs: Angle, rhs: Angle) -> Angle { Angle(radians: lhs.radians + rhs.radians) }

    /// The difference of two angles.
    public static func - (lhs: Angle, rhs: Angle) -> Angle { Angle(radians: lhs.radians - rhs.radians) }

    /// The negated angle.
    public static prefix func - (angle: Angle) -> Angle { Angle(radians: -angle.radians) }

    /// The angle scaled by `rhs`.
    public static func * (lhs: Angle, rhs: Double) -> Angle { Angle(radians: lhs.radians * rhs) }

    /// The angle scaled by `lhs`.
    public static func * (lhs: Double, rhs: Angle) -> Angle { Angle(radians: lhs * rhs.radians) }

    /// The angle divided by `rhs`.
    public static func / (lhs: Angle, rhs: Double) -> Angle { Angle(radians: lhs.radians / rhs) }

    /// Adds `rhs` to `lhs`.
    public static func += (lhs: inout Angle, rhs: Angle) { lhs = lhs + rhs }

    /// Subtracts `rhs` from `lhs`.
    public static func -= (lhs: inout Angle, rhs: Angle) { lhs = lhs - rhs }
}
