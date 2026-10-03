import MetalUICore
import MetalUIPrimitives
import MetalUIPath

// Paths, shadows and transforms, lane 2 (ruling `GX-G`). Spec
// `docs/superpowers/specs/2026-10-02-paths-shadows-transforms-design.md` §6.

/// A 2-D affine map, `x′ = a x + c y + tx`, `y′ = b x + d y + ty` — the
/// layout of `MUITransform`'s first six floats (`GX-F`), in `Double`.
///
/// Used in two spaces: **points** (prepaint: hitboxes and accessibility
/// records, `GX-I`) and **device pixels** (paint, `scaledToDevice`). Composition
/// reads right to left: `outer.concatenating(inner)` maps a point through
/// `inner` first.
struct Affine2D: Equatable, Sendable {
    var a: Double = 1, b: Double = 0, c: Double = 0, d: Double = 1
    var tx: Double = 0, ty: Double = 0

    static let identity = Affine2D()

    var isIdentity: Bool { self == .identity }

    /// `(x, y)` mapped.
    func apply(_ x: Double, _ y: Double) -> (x: Double, y: Double) {
        (a * x + c * y + tx, b * x + d * y + ty)
    }

    /// `point` mapped.
    func apply(_ point: Point<Pixels>) -> Point<Pixels> {
        let p = apply(Double(point.x.value), Double(point.y.value))
        return Point(x: Pixels(Float(p.x)), y: Pixels(Float(p.y)))
    }

    /// `self ∘ inner`: `inner` first, then `self`.
    func concatenating(_ inner: Affine2D) -> Affine2D {
        Affine2D(a: a * inner.a + c * inner.b, b: b * inner.a + d * inner.b,
                 c: a * inner.c + c * inner.d, d: b * inner.c + d * inner.d,
                 tx: a * inner.tx + c * inner.ty + tx, ty: b * inner.tx + d * inner.ty + ty)
    }

    var determinant: Double { a * d - b * c }

    /// `sqrt|det|` — screen units per local unit (`MUITransform.pixelScale`).
    var linearScale: Double { abs(determinant).squareRoot() }

    /// The inverse map, or `nil` when the map is degenerate (a zero scale).
    var inverted: Affine2D? {
        let det = determinant
        guard det != 0, det.isFinite else { return nil }
        let ia = d / det, ib = -b / det, ic = -c / det, id = a / det
        return Affine2D(a: ia, b: ib, c: ic, d: id,
                        tx: -(ia * tx + ic * ty), ty: -(ib * tx + id * ty))
    }

    /// A translation plus a **uniform positive** scale — the maps a paint scope
    /// flattens on the CPU (`GX-G`); every other map becomes a transform record.
    var isUniformPositiveScaleTranslation: Bool { b == 0 && c == 0 && a == d && a > 0 }

    /// The map in device pixels for a scene drawn at `scale` device pixels per
    /// point: `S · M · S⁻¹`, so only the translation scales.
    func scaledToDevice(_ scale: Float) -> Affine2D {
        Affine2D(a: a, b: b, c: c, d: d, tx: tx * Double(scale), ty: ty * Double(scale))
    }

    static func translation(x: Double, y: Double) -> Affine2D { Affine2D(tx: x, ty: y) }

    /// `diag(x, y)` about `(ax, ay)`.
    static func scale(x: Double, y: Double, about ax: Double, _ ay: Double) -> Affine2D {
        Affine2D(a: x, d: y, tx: ax - x * ax, ty: ay - y * ay)
    }

    /// A rotation by `radians` (positive is visually clockwise in y-down
    /// coordinates) about `(ax, ay)`. Sine and cosine from `PathMath.sinCos`,
    /// identical on every platform (`GX-H`).
    static func rotation(radians: Double, about ax: Double, _ ay: Double) -> Affine2D {
        let (s, c) = PathMath.sinCos(radians)
        return Affine2D(a: c, b: s, c: -s, d: c,
                        tx: ax - (c * ax - s * ay), ty: ay - (s * ax + c * ay))
    }

    /// The axis-aligned bounding box of `bounds` mapped (its four corners).
    func boundingBox(of bounds: Bounds<Pixels>) -> Bounds<Pixels> {
        let r = boundingBox(x: Double(bounds.origin.x.value), y: Double(bounds.origin.y.value),
                            w: Double(bounds.size.width.value), h: Double(bounds.size.height.value))
        return Bounds(origin: Point(x: Pixels(Float(r.x)), y: Pixels(Float(r.y))),
                      size: Size(width: Pixels(Float(r.w)), height: Pixels(Float(r.h))))
    }

    /// The same in device pixels.
    func boundingBox(of bounds: MUIBounds) -> MUIBounds {
        let r = boundingBox(x: Double(bounds.origin.x), y: Double(bounds.origin.y),
                            w: Double(bounds.size.width), h: Double(bounds.size.height))
        return MUIBounds(origin: MUIPoint(x: Float(r.x), y: Float(r.y)),
                         size: MUISize(width: Float(r.w), height: Float(r.h)))
    }

    private func boundingBox(x: Double, y: Double, w: Double, h: Double)
        -> (x: Double, y: Double, w: Double, h: Double) {
        let corners = [apply(x, y), apply(x + w, y), apply(x, y + h), apply(x + w, y + h)]
        let minX = corners.map(\.x).min()!, maxX = corners.map(\.x).max()!
        let minY = corners.map(\.y).min()!, maxY = corners.map(\.y).max()!
        return (minX, minY, maxX - minX, maxY - minY)
    }
}
