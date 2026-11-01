import MetalUIPath

// A public 2D affine map for `Path`'s `transform:` parameters (ruling `PG-E`).
// SwiftUI spells it `CGAffineTransform`; MetalUI carries no CoreGraphics type
// across its portable seam (`GX-C`), and Foundation's `AffineTransform` would
// collide with this module's importers, so it is `Transform2D` (divergence 945).

/// An affine map of the plane — the type of `Path`'s `transform:` parameters
/// and of ``Path/applying(_:)``, SwiftUI's `CGAffineTransform`.
///
/// `x' = a·x + c·y + tx`, `y' = b·x + d·y + ty`: CoreGraphics' column
/// convention, in `Double`. ``concatenating(_:)`` applies the receiver first
/// and its argument second; the `translatedBy`, `scaledBy` and `rotated`
/// builders apply their **new** step first and the receiver second, as
/// `CGAffineTransform`'s do (probe AR7: translate(5, 7) then `rotated(by: 90°)`
/// maps (10, 0) to (5, 17)). A positive rotation turns the positive angle
/// direction, visually clockwise in y-down space.
public struct Transform2D: Hashable, Sendable {
    /// The x scale / rotation term.
    public var a: Double
    /// The y shear term of x.
    public var b: Double
    /// The x shear term of y.
    public var c: Double
    /// The y scale / rotation term.
    public var d: Double
    /// The x translation.
    public var tx: Double
    /// The y translation.
    public var ty: Double

    /// A transform from its six components.
    public init(a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double) {
        self.a = a; self.b = b; self.c = c; self.d = d; self.tx = tx; self.ty = ty
    }

    /// The map that changes nothing.
    public static let identity = Transform2D(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)

    /// A translation by `(x, y)`.
    public init(translationX x: Double, y: Double) { self.init(a: 1, b: 0, c: 0, d: 1, tx: x, ty: y) }

    /// A scale by `(x, y)` about the origin.
    public init(scaleX x: Double, y: Double) { self.init(a: x, b: 0, c: 0, d: y, tx: 0, ty: 0) }

    /// A rotation by `angle` about the origin.
    public init(rotationAngle angle: Angle) {
        let affine = PathAffine.rotation(angle.radians)
        self.init(a: affine.a, b: affine.b, c: affine.c, d: affine.d, tx: 0, ty: 0)
    }

    /// Whether this is exactly ``identity``.
    public var isIdentity: Bool { self == .identity }

    var affine: PathAffine { PathAffine(a: a, b: b, c: c, d: d, tx: tx, ty: ty) }

    /// This transform followed by `other` — `CGAffineTransform.concatenating(_:)`.
    public func concatenating(_ other: Transform2D) -> Transform2D {
        let m = other.affine.concatenating(affine)
        return Transform2D(a: m.a, b: m.b, c: m.c, d: m.d, tx: m.tx, ty: m.ty)
    }

    /// A translation by `(x, y)` applied first, then this transform.
    public func translatedBy(x: Double, y: Double) -> Transform2D {
        Transform2D(translationX: x, y: y).concatenating(self)
    }

    /// A scale by `(x, y)` applied first, then this transform.
    public func scaledBy(x: Double, y: Double) -> Transform2D {
        Transform2D(scaleX: x, y: y).concatenating(self)
    }

    /// A rotation by `angle` applied first, then this transform.
    public func rotated(by angle: Angle) -> Transform2D {
        Transform2D(rotationAngle: angle).concatenating(self)
    }

    /// The map that undoes this one, or this transform when it is singular
    /// (`CGAffineTransform.inverted()`'s answer).
    public func inverted() -> Transform2D {
        guard let m = affine.inverted else { return self }
        return Transform2D(a: m.a, b: m.b, c: m.c, d: m.d, tx: m.tx, ty: m.ty)
    }
}
