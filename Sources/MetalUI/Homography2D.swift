import MetalUICore
import MetalUIPrimitives
import MetalUIPath

// 3D render effects (`PJ-`, record 193). A 3x3 projective map of the plane.

/// A projective map of the plane, `x′ = (a x + c y + tx) / w`, `y′ = (b x + d y + ty) / w`,
/// `w = g x + h y + i` — an ``Affine2D`` with the bottom row of the 3×3 matrix kept (`PJ-A`).
///
/// **Every operation has an affine fast path**: two affine operands run ``Affine2D``'s own formulas and
/// the result is that value, so an affine effect is bit-identical to what it was before this type
/// existed. A projective result is never silently flattened: a reader that needs an affine asks for
/// ``affine`` and handles `nil`.
///
/// Composition reads right to left, as ``Affine2D``'s does. `scaledToDevice` scales the translation and
/// divides `g`, `h` by the scale (`S · M · S⁻¹`), leaving `i`.
struct Homography2D: Equatable, Sendable {
    var a: Double = 1, b: Double = 0, c: Double = 0, d: Double = 1
    var tx: Double = 0, ty: Double = 0
    var g: Double = 0, h: Double = 0, i: Double = 1

    static let identity = Homography2D()

    init() {}

    init(a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double,
         g: Double = 0, h: Double = 0, i: Double = 1) {
        self.a = a; self.b = b; self.c = c; self.d = d
        self.tx = tx; self.ty = ty
        self.g = g; self.h = h; self.i = i
    }

    init(_ affine: Affine2D) {
        a = affine.a; b = affine.b; c = affine.c; d = affine.d
        tx = affine.tx; ty = affine.ty
    }

    /// Whether the bottom row is `(0, 0, 1)` — the map is an ``Affine2D``.
    var isAffine: Bool { g == 0 && h == 0 && i == 1 }

    var isIdentity: Bool { self == .identity }

    /// The map as an affine one, or `nil` when it is projective.
    var affine: Affine2D? {
        isAffine ? Affine2D(a: a, b: b, c: c, d: d, tx: tx, ty: ty) : nil
    }

    /// The 3×3 determinant (`MUITransform` lane 4's last float is this for a projective record).
    var det3: Double {
        a * (d * i - ty * h) - c * (b * i - ty * g) + tx * (b * h - d * g)
    }

    /// The affine determinant for an affine map, `det3` otherwise.
    var determinant: Double { isAffine ? a * d - b * c : det3 }

    /// `(x, y)` mapped, or `nil` when it lands on or behind the eye (`w ≤ 0`, `PJ-C`).
    func apply(_ x: Double, _ y: Double) -> (x: Double, y: Double)? {
        if isAffine { return (a * x + c * y + tx, b * x + d * y + ty) }
        let w = g * x + h * y + i
        guard w > 0 else { return nil }
        return ((a * x + c * y + tx) / w, (b * x + d * y + ty) / w)
    }

    /// `point` mapped, or `nil` behind the eye.
    func apply(_ point: Point<Pixels>) -> Point<Pixels>? {
        guard let p = apply(Double(point.x.value), Double(point.y.value)) else { return nil }
        return Point(x: Pixels(Float(p.x)), y: Pixels(Float(p.y)))
    }

    /// The homogeneous denominator at `(x, y)`.
    func w(_ x: Double, _ y: Double) -> Double { isAffine ? 1 : g * x + h * y + i }

    /// Whether every corner of the rectangle lands in front of the eye (`w > 0`): a view with one corner at
    /// or behind it draws nothing at all (`PJ-C`, measured).
    func isInFront(of rect: Bounds<Pixels>) -> Bool {
        if isAffine { return true }
        let x0 = Double(rect.origin.x.value), y0 = Double(rect.origin.y.value)
        let x1 = x0 + Double(rect.size.width.value), y1 = y0 + Double(rect.size.height.value)
        return w(x0, y0) > 0 && w(x1, y0) > 0 && w(x0, y1) > 0 && w(x1, y1) > 0
    }

    /// Whether every corner of the device-pixel rectangle lands in front of the eye with `w > 0`.
    func isInFront(of bounds: MUIBounds) -> Bool {
        if isAffine { return true }
        let x0 = Double(bounds.origin.x), y0 = Double(bounds.origin.y)
        let x1 = x0 + Double(bounds.size.width), y1 = y0 + Double(bounds.size.height)
        return w(x0, y0) > 0 && w(x1, y0) > 0 && w(x0, y1) > 0 && w(x1, y1) > 0
    }

    /// `self ∘ inner`: `inner` first, then `self`.
    func concatenating(_ inner: Homography2D) -> Homography2D {
        if let l = affine, let r = inner.affine { return Homography2D(l.concatenating(r)) }
        let r0 = (a, c, tx), r1 = (b, d, ty), r2 = (g, h, i)
        func row(_ r: (Double, Double, Double)) -> (Double, Double, Double) {
            (r.0 * inner.a + r.1 * inner.b + r.2 * inner.g,
             r.0 * inner.c + r.1 * inner.d + r.2 * inner.h,
             r.0 * inner.tx + r.1 * inner.ty + r.2 * inner.i)
        }
        let p = row(r0), q = row(r1), s = row(r2)
        return Homography2D(a: p.0, b: q.0, c: p.1, d: q.1, tx: p.2, ty: q.2, g: s.0, h: s.1, i: s.2)
    }

    /// The inverse map, or `nil` when it is degenerate.
    var inverted: Homography2D? {
        if let affine { return affine.inverted.map(Homography2D.init) }
        let det = det3
        guard det != 0, det.isFinite else { return nil }
        // The adjugate over the determinant.
        let ia = (d * i - ty * h) / det, ic = (tx * h - c * i) / det, itx = (c * ty - tx * d) / det
        let ib = (ty * g - b * i) / det, id = (a * i - tx * g) / det, ity = (tx * b - a * ty) / det
        let ig = (b * h - d * g) / det, ih = (c * g - a * h) / det, ii = (a * d - b * c) / det
        return Homography2D(a: ia, b: ib, c: ic, d: id, tx: itx, ty: ity, g: ig, h: ih, i: ii)
    }

    /// A translation plus a uniform positive scale — the maps a paint scope flattens on the CPU.
    var isUniformPositiveScaleTranslation: Bool { isAffine && b == 0 && c == 0 && a == d && a > 0 }

    /// The map in device pixels for a scene drawn at `scale` device pixels per point: `S · M · S⁻¹`.
    func scaledToDevice(_ scale: Float) -> Homography2D {
        if let affine { return Homography2D(affine.scaledToDevice(scale)) }
        let s = Double(scale)
        return Homography2D(a: a, b: b, c: c, d: d, tx: tx * s, ty: ty * s, g: g / s, h: h / s, i: i)
    }

    static func translation(x: Double, y: Double) -> Homography2D { Homography2D(Affine2D.translation(x: x, y: y)) }

    /// This map about the point `(ox, oy)` instead of the origin: `T(o) · self · T(−o)`.
    func about(_ ox: Double, _ oy: Double) -> Homography2D {
        Homography2D.translation(x: ox, y: oy).concatenating(self)
            .concatenating(Homography2D.translation(x: -ox, y: -oy))
    }

    /// `T(d) · self · T(−d)`. An affine map keeps the formula it always used, so a canonical move stays
    /// bit-identical (`PF-`).
    func conjugatedByTranslation(_ dx: Double, _ dy: Double) -> Homography2D {
        if isAffine {
            return Homography2D(Affine2D(a: a, b: b, c: c, d: d,
                                         tx: tx + (dx - (a * dx + c * dy)), ty: ty + (dy - (b * dx + d * dy))))
        }
        return about(dx, dy)
    }

    /// This map conjugated by the reflection about the vertical line `x = cx` (`LD-C`, a right-to-left
    /// site): `F · self · F` with `F: x → 2 cx − x`.
    func reflected(aboutX cx: Double) -> Homography2D {
        let f = Homography2D(Affine2D(a: -1, b: 0, c: 0, d: 1, tx: 2 * cx, ty: 0))
        return f.concatenating(self).concatenating(f)
    }

    /// The axis-aligned bounding box of `bounds` mapped (its four corners). A rectangle with a corner on or
    /// behind the eye collapses to an empty box at its origin (nothing is drawn there, `PJ-C`).
    func boundingBox(of bounds: Bounds<Pixels>) -> Bounds<Pixels> {
        if let affine { return affine.boundingBox(of: bounds) }
        guard isInFront(of: bounds) else { return Bounds(origin: bounds.origin, size: Size(width: Pixels(0), height: Pixels(0))) }
        let r = corners(x: Double(bounds.origin.x.value), y: Double(bounds.origin.y.value),
                        w: Double(bounds.size.width.value), h: Double(bounds.size.height.value))
        return Bounds(origin: Point(x: Pixels(Float(r.x)), y: Pixels(Float(r.y))),
                      size: Size(width: Pixels(Float(r.w)), height: Pixels(Float(r.h))))
    }

    /// The same in device pixels.
    func boundingBox(of bounds: MUIBounds) -> MUIBounds {
        if let affine { return affine.boundingBox(of: bounds) }
        let x0 = Double(bounds.origin.x), y0 = Double(bounds.origin.y)
        let x1 = x0 + Double(bounds.size.width), y1 = y0 + Double(bounds.size.height)
        guard w(x0, y0) > 0, w(x1, y0) > 0, w(x0, y1) > 0, w(x1, y1) > 0 else {
            return MUIBounds(origin: bounds.origin, size: MUISize(width: 0, height: 0))
        }
        let r = corners(x: x0, y: y0, w: Double(bounds.size.width), h: Double(bounds.size.height))
        return MUIBounds(origin: MUIPoint(x: Float(r.x), y: Float(r.y)), size: MUISize(width: Float(r.w), height: Float(r.h)))
    }

    private func corners(x: Double, y: Double, w: Double, h: Double) -> (x: Double, y: Double, w: Double, h: Double) {
        let cs = [(x, y), (x + w, y), (x, y + h), (x + w, y + h)].compactMap { apply($0.0, $0.1) }
        guard let first = cs.first else { return (x, y, 0, 0) }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in cs.dropFirst() {
            minX = min(minX, p.x); maxX = max(maxX, p.x); minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        return (minX, minY, maxX - minX, maxY - minY)
    }

    // MARK: - The effects' constructors

    /// SwiftUI's `rotation3DEffect` as a map over `rect` (`PJ-B`): view-local `v = (x − ax, y − ay, −anchorZ)`,
    /// right-handed Rodrigues about the normalised axis, eye distance `d = max(W, H) / perspective`,
    /// `w = 1 − v′z / d`, screen `(ax + v′x / w, ay + v′y / w)`; `anchorZ` is not added back. An exactly zero angle or a
    /// zero axis is the identity (measured, even with `anchorZ` set); a negative `perspective` is the negated angle;
    /// `perspective == 0` is orthographic.
    static func rotation3D(radians: Double, axis: (x: Double, y: Double, z: Double), anchor: (x: Double, y: Double),
                           anchorZ: Double, perspective: Double, size: (width: Double, height: Double),
                           origin: (x: Double, y: Double)) -> Homography2D {
        let length = (axis.x * axis.x + axis.y * axis.y + axis.z * axis.z).squareRoot()
        guard radians != 0, length > 0, length.isFinite, radians.isFinite else { return .identity }
        var theta = radians
        var p = perspective
        if p < 0 { theta = -theta; p = -p }
        let ux = axis.x / length, uy = axis.y / length, uz = axis.z / length
        let (s, c) = PathMath.sinCos(theta)
        let t = 1 - c
        // R, row by row (right-handed).
        let r00 = c + ux * ux * t, r01 = ux * uy * t - uz * s, r02 = ux * uz * t + uy * s
        let r10 = uy * ux * t + uz * s, r11 = c + uy * uy * t, r12 = uy * uz * t - ux * s
        let r20 = uz * ux * t - uy * s, r21 = uz * uy * t + ux * s, r22 = c + uz * uz * t
        let extent = max(size.width, size.height)
        let k = p == 0 || extent <= 0 ? 0 : p / extent
        let ax = origin.x + anchor.x * size.width, ay = origin.y + anchor.y * size.height
        // The matrix acts on window points: the view-local offset from the anchor is `(x − ax, y − ay)`.
        let g = -r20 * k, h = -r21 * k
        let i = 1 + r22 * anchorZ * k + (r20 * ax + r21 * ay) * k
        // X numerator: ax · w + v′x, with v′x = r00 (x − ax) + r01 (y − ay) − r02 anchorZ.
        let a = r00 + ax * g, cc = r01 + ax * h
        let tx = -r00 * ax - r01 * ay - r02 * anchorZ + ax * i
        let b = r10 + ay * g, d = r11 + ay * h
        let ty = -r10 * ax - r11 * ay - r12 * anchorZ + ay * i
        return Homography2D(a: a, b: b, c: cc, d: d, tx: tx, ty: ty, g: g, h: h, i: i)
    }
}
