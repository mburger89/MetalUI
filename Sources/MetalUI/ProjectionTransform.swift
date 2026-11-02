// 3D render effects (`PJ-`, record 193; divergence 1068).

/// A 3×3 projective map of the plane — SwiftUI's `ProjectionTransform`, with `Double` fields and no
/// `init(CATransform3D)` (divergence 1068).
///
/// Row vectors, in the view's own points, as SwiftUI measured: `x′ = (x·m11 + y·m21 + m31) / w`,
/// `y′ = (x·m12 + y·m22 + m32) / w`, `w = x·m13 + y·m23 + m33`. A view with any corner at `w ≤ 0` draws
/// nothing. The ``Transform2D`` form is the same map with `m13 = m23 = 0`, `m33 = 1`.
public struct ProjectionTransform: Hashable, Sendable {
    /// Row 1, column 1.
    public var m11: Double
    /// Row 1, column 2.
    public var m12: Double
    /// Row 1, column 3 (the x term of `w`).
    public var m13: Double
    /// Row 2, column 1.
    public var m21: Double
    /// Row 2, column 2.
    public var m22: Double
    /// Row 2, column 3 (the y term of `w`).
    public var m23: Double
    /// Row 3, column 1 (the x translation).
    public var m31: Double
    /// Row 3, column 2 (the y translation).
    public var m32: Double
    /// Row 3, column 3 (the constant term of `w`).
    public var m33: Double

    /// The identity map.
    public init() {
        m11 = 1; m12 = 0; m13 = 0
        m21 = 0; m22 = 1; m23 = 0
        m31 = 0; m32 = 0; m33 = 1
    }

    /// The affine map `transform` as a projection.
    public init(_ transform: Transform2D) {
        m11 = transform.a; m12 = transform.b; m13 = 0
        m21 = transform.c; m22 = transform.d; m23 = 0
        m31 = transform.tx; m32 = transform.ty; m33 = 1
    }

    /// Whether this is exactly the identity.
    public var isIdentity: Bool { self == ProjectionTransform() }

    /// Whether the map is affine (`m13 = m23 = 0` and `m33 = 1`).
    public var isAffine: Bool { m13 == 0 && m23 == 0 && m33 == 1 }

    var homography: Homography2D {
        Homography2D(a: m11, b: m12, c: m21, d: m22, tx: m31, ty: m32, g: m13, h: m23, i: m33)
    }

    init(_ homography: Homography2D) {
        m11 = homography.a; m12 = homography.b; m13 = homography.g
        m21 = homography.c; m22 = homography.d; m23 = homography.h
        m31 = homography.tx; m32 = homography.ty; m33 = homography.i
    }

    /// Inverts this map in place; a singular map is left unchanged (`ProjectionTransform.invert()`'s answer).
    @discardableResult
    public mutating func invert() -> Bool {
        guard let inverse = homography.inverted else { return false }
        self = ProjectionTransform(inverse)
        return true
    }

    /// The inverse, or this map when it is singular.
    public func inverted() -> ProjectionTransform {
        guard let inverse = homography.inverted else { return self }
        return ProjectionTransform(inverse)
    }

    /// This map followed by `rhs` (`ProjectionTransform.concatenating(_:)`, row-vector order).
    public func concatenating(_ rhs: ProjectionTransform) -> ProjectionTransform {
        ProjectionTransform(rhs.homography.concatenating(homography))
    }
}
