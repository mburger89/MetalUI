// MetalUIPath — CPU path geometry, flattening, stroking, exact-area
// rasterization, blur and alpha compositing (ruling GX-B). **Imports nothing**:
// pure Swift standard library, no Foundation, no MetalUICore, so a path's
// coverage is the same bytes on macOS, Linux and Windows (pinned by
// `theRasterizerIsBitIdenticalEverywhere`). Every operation is `+ − × ÷ sqrt`
// and comparisons; trigonometry is `PathMath.sinCos`, this target's own. No
// `addingProduct`/fused multiply-add anywhere (`GX-R` item 2).
//
// The API is `package`: `MetalUI` builds the public `Path` over it (lane 3).

/// A point in a path's own space (local points, or device pixels after an
/// affine), in `Double`.
package struct PathPoint: Hashable, Sendable {
    package var x: Double
    package var y: Double
    package init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
    package init(x: Double, y: Double) { self.x = x; self.y = y }
}

/// `x' = a x + c y + tx`, `y' = b x + d y + ty` — the same column convention
/// as the shaders' `MUITransform` (ruling GX-F).
package struct PathAffine: Hashable, Sendable {
    package var a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double
    package init(a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double) {
        self.a = a; self.b = b; self.c = c; self.d = d; self.tx = tx; self.ty = ty
    }
    package static let identity = PathAffine(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)
    package static func translation(_ x: Double, _ y: Double) -> PathAffine {
        PathAffine(a: 1, b: 0, c: 0, d: 1, tx: x, ty: y)
    }
    package static func scale(_ x: Double, _ y: Double) -> PathAffine {
        PathAffine(a: x, b: 0, c: 0, d: y, tx: 0, ty: 0)
    }
    /// A rotation by `radians`, positive clockwise in y-down space.
    package static func rotation(_ radians: Double) -> PathAffine {
        let (s, c) = PathMath.sinCos(radians)
        return PathAffine(a: c, b: s, c: -s, d: c, tx: 0, ty: 0)
    }
    package func apply(_ p: PathPoint) -> PathPoint {
        PathPoint(a * p.x + c * p.y + tx, b * p.x + d * p.y + ty)
    }
    /// `self` after `first`: `self.concatenating(first).apply(p) == self.apply(first.apply(p))`.
    package func concatenating(_ first: PathAffine) -> PathAffine {
        PathAffine(a: a * first.a + c * first.b, b: b * first.a + d * first.b,
                   c: a * first.c + c * first.d, d: b * first.c + d * first.d,
                   tx: a * first.tx + c * first.ty + tx, ty: b * first.tx + d * first.ty + ty)
    }
    package var determinant: Double { a * d - b * c }
    /// The inverse, or `nil` when the map is singular.
    package var inverted: PathAffine? {
        let det = determinant
        guard det != 0, det.isFinite else { return nil }
        let ia = d / det, ib = -b / det, ic = -c / det, id = a / det
        return PathAffine(a: ia, b: ib, c: ic, d: id,
                          tx: -(ia * tx + ic * ty), ty: -(ib * tx + id * ty))
    }
    /// Screen pixels per local pixel, isotropic: `sqrt|det|`.
    package var linearScale: Double { let det = determinant; return (det < 0 ? -det : det).squareRoot() }
}

/// An integer pixel rectangle.
package struct RasterRect: Hashable, Sendable {
    package var x: Int, y: Int, width: Int, height: Int
    package init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x; self.y = y; self.width = max(0, width); self.height = max(0, height)
    }
    package var isEmpty: Bool { width == 0 || height == 0 }
    package var maxX: Int { x + width }
    package var maxY: Int { y + height }
    package var area: Int { width * height }
    package func intersection(_ o: RasterRect) -> RasterRect {
        let x0 = max(x, o.x), y0 = max(y, o.y)
        let x1 = min(maxX, o.maxX), y1 = min(maxY, o.maxY)
        return RasterRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }
    package func union(_ o: RasterRect) -> RasterRect {
        if isEmpty { return o }
        if o.isEmpty { return self }
        let x0 = min(x, o.x), y0 = min(y, o.y)
        return RasterRect(x: x0, y: y0, width: max(maxX, o.maxX) - x0, height: max(maxY, o.maxY) - y0)
    }
    /// The smallest integer rectangle holding `[minX, maxX] × [minY, maxY]`.
    package static func enclosing(minX: Double, minY: Double, maxX: Double, maxY: Double) -> RasterRect {
        guard minX.isFinite, minY.isFinite, maxX.isFinite, maxY.isFinite, minX <= maxX, minY <= maxY else {
            return RasterRect(x: 0, y: 0, width: 0, height: 0)
        }
        let limit = 1_000_000_000.0
        let x0 = Int(max(-limit, min(limit, minX)).rounded(.down))
        let y0 = Int(max(-limit, min(limit, minY)).rounded(.down))
        let x1 = Int(max(-limit, min(limit, maxX)).rounded(.up))
        let y1 = Int(max(-limit, min(limit, maxY)).rounded(.up))
        return RasterRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }
}

/// An 8-bit coverage (alpha) mask over an integer device rectangle,
/// row-major.
package struct AlphaMask: Hashable, Sendable {
    package var rect: RasterRect
    package var alpha: [UInt8]
    package init(rect: RasterRect, alpha: [UInt8]) {
        precondition(alpha.count == rect.area, "AlphaMask: \(alpha.count) bytes for \(rect.width)×\(rect.height)")
        self.rect = rect; self.alpha = alpha
    }
    package static let empty = AlphaMask(rect: RasterRect(x: 0, y: 0, width: 0, height: 0), alpha: [])
    /// The value at device pixel (x, y), 0 outside.
    package func value(atX x: Int, y: Int) -> UInt8 {
        guard x >= rect.x, y >= rect.y, x < rect.maxX, y < rect.maxY else { return 0 }
        return alpha[(y - rect.y) * rect.width + (x - rect.x)]
    }
}

/// A path: subpaths of move/line/quad/cubic/close elements. Arcs, ellipses
/// and rounded rectangles are stored as cubics of at most 90° each
/// (ruling GX-C), so flattening sees only polynomial segments.
package struct PathGeometry: Hashable, Sendable {
    package enum Element: Hashable, Sendable {
        case move(PathPoint)
        case line(PathPoint)
        case quad(control: PathPoint, to: PathPoint)
        case cubic(control1: PathPoint, control2: PathPoint, to: PathPoint)
        case close
    }

    package private(set) var elements: [Element] = []
    /// Where the current subpath started (a `close` returns there).
    private var subpathStart: PathPoint?
    /// The end of the last element, `nil` before the first `move`.
    package private(set) var currentPoint: PathPoint?

    package init() {}

    package var isEmpty: Bool { elements.isEmpty }

    package mutating func move(to p: PathPoint) {
        elements.append(.move(p)); subpathStart = p; currentPoint = p
    }
    /// A line from the current point; with none, a `move` (CoreGraphics'
    /// answer for a drawing call on an empty path).
    package mutating func addLine(to p: PathPoint) {
        guard currentPoint != nil else { move(to: p); return }
        elements.append(.line(p)); currentPoint = p
    }
    package mutating func addQuadCurve(to p: PathPoint, control: PathPoint) {
        guard currentPoint != nil else { move(to: p); return }
        elements.append(.quad(control: control, to: p)); currentPoint = p
    }
    package mutating func addCurve(to p: PathPoint, control1: PathPoint, control2: PathPoint) {
        guard currentPoint != nil else { move(to: p); return }
        elements.append(.cubic(control1: control1, control2: control2, to: p)); currentPoint = p
    }
    package mutating func closeSubpath() {
        guard currentPoint != nil else { return }
        if case .close? = elements.last { return }
        elements.append(.close); currentPoint = subpathStart
    }

    /// A closed rectangle, (minX, minY) → (maxX, minY) → (maxX, maxY) →
    /// (minX, maxY): the positive-angle (visually clockwise, y-down) direction
    /// CoreGraphics' `addRect` takes.
    package mutating func addRect(x: Double, y: Double, width: Double, height: Double) {
        move(to: PathPoint(x, y))
        addLine(to: PathPoint(x + width, y))
        addLine(to: PathPoint(x + width, y + height))
        addLine(to: PathPoint(x, y + height))
        closeSubpath()
    }

    /// `4/3 (√2 − 1)`: the control-arm fraction of a quarter circle as one cubic.
    package static let kappa = 0.5522847498307936

    /// The ellipse inscribed in the rectangle: four cubics, starting at
    /// (maxX, midY), positive angle direction.
    package mutating func addEllipse(x: Double, y: Double, width: Double, height: Double) {
        let rx = width / 2, ry = height / 2, cx = x + rx, cy = y + ry
        let kx = rx * Self.kappa, ky = ry * Self.kappa
        move(to: PathPoint(cx + rx, cy))
        addCurve(to: PathPoint(cx, cy + ry), control1: PathPoint(cx + rx, cy + ky), control2: PathPoint(cx + kx, cy + ry))
        addCurve(to: PathPoint(cx - rx, cy), control1: PathPoint(cx - kx, cy + ry), control2: PathPoint(cx - rx, cy + ky))
        addCurve(to: PathPoint(cx, cy - ry), control1: PathPoint(cx - rx, cy - ky), control2: PathPoint(cx - kx, cy - ry))
        addCurve(to: PathPoint(cx + rx, cy), control1: PathPoint(cx + kx, cy - ry), control2: PathPoint(cx + rx, cy - ky))
        closeSubpath()
    }

    /// A rectangle with elliptical corners of radii (rx, ry), each clamped to
    /// half its side — circular quarter arcs as cubics (divergence 90: a
    /// `.continuous` corner is drawn circular too).
    package mutating func addRoundedRect(x: Double, y: Double, width: Double, height: Double,
                                         rx: Double, ry: Double) {
        let rx = max(0, min(rx, width / 2)), ry = max(0, min(ry, height / 2))
        guard rx > 0, ry > 0 else { addRect(x: x, y: y, width: width, height: height); return }
        let kx = rx * Self.kappa, ky = ry * Self.kappa
        let x1 = x + width, y1 = y + height
        move(to: PathPoint(x + rx, y))
        addLine(to: PathPoint(x1 - rx, y))
        addCurve(to: PathPoint(x1, y + ry), control1: PathPoint(x1 - rx + kx, y), control2: PathPoint(x1, y + ry - ky))
        addLine(to: PathPoint(x1, y1 - ry))
        addCurve(to: PathPoint(x1 - rx, y1), control1: PathPoint(x1, y1 - ry + ky), control2: PathPoint(x1 - rx + kx, y1))
        addLine(to: PathPoint(x + rx, y1))
        addCurve(to: PathPoint(x, y1 - ry), control1: PathPoint(x + rx - kx, y1), control2: PathPoint(x, y1 - ry + ky))
        addLine(to: PathPoint(x, y + ry))
        addCurve(to: PathPoint(x + rx, y), control1: PathPoint(x, y + ry - ky), control2: PathPoint(x + rx - kx, y))
        closeSubpath()
    }

    /// SwiftUI's `addArc(center:radius:startAngle:endAngle:clockwise:)`: a
    /// line (or a move, on an empty path) to the arc's start, then cubics of
    /// at most 90°. **`clockwise` reads in y-up terms** (probe PA3): `false`
    /// sweeps the positive angle direction, which is visually clockwise in
    /// y-down space. A sweep larger than a turn is one turn.
    package mutating func addArc(center: PathPoint, radius: Double, startAngle: Double, endAngle: Double,
                                 clockwise: Bool) {
        let turn = 6.283185307179586
        var sweep = endAngle - startAngle
        if clockwise {
            if sweep > 0 { sweep -= turn * ((sweep / turn).rounded(.down) + 1) }
            if sweep < -turn { sweep = -turn }
        } else {
            if sweep < 0 { sweep += turn * ((-sweep / turn).rounded(.down) + 1) }
            if sweep > turn { sweep = turn }
        }
        let (s0, c0) = PathMath.sinCos(startAngle)
        let start = PathPoint(center.x + radius * c0, center.y + radius * s0)
        if currentPoint == nil { move(to: start) } else { addLine(to: start) }
        guard radius > 0, sweep != 0 else { return }
        let quarter = 1.5707963267948966
        let magnitude = sweep < 0 ? -sweep : sweep
        var count = Int((magnitude / quarter).rounded(.up))
        if count < 1 { count = 1 }
        let step = sweep / Double(count)
        let (sq, cq) = PathMath.sinCos(step / 4)
        let k = 4.0 / 3.0 * (sq / cq)
        var a0 = startAngle
        var p0 = start, sin0 = s0, cos0 = c0
        for i in 1...count {
            let a1 = i == count ? startAngle + sweep : a0 + step
            let (sin1, cos1) = PathMath.sinCos(a1)
            let p3 = PathPoint(center.x + radius * cos1, center.y + radius * sin1)
            let p1 = PathPoint(p0.x - k * radius * sin0, p0.y + k * radius * cos0)
            let p2 = PathPoint(p3.x + k * radius * sin1, p3.y - k * radius * cos1)
            addCurve(to: p3, control1: p1, control2: p2)
            a0 = a1; p0 = p3; sin0 = sin1; cos0 = cos1
        }
    }

    /// SwiftUI's `addArc(tangent1End:tangent2End:radius:)` (CoreGraphics'
    /// `addArc(tangent1End:tangent2End:radius:)`): a line from the current
    /// point to where a circle of `radius` touches the first tangent, then the
    /// arc to where it touches the second. Collinear points, a zero radius or
    /// no current point give a line to `tangent1End`.
    package mutating func addArc(tangent1End t1: PathPoint, tangent2End t2: PathPoint, radius: Double) {
        guard let p0 = currentPoint else { move(to: t1); return }
        let ux = p0.x - t1.x, uy = p0.y - t1.y, vx = t2.x - t1.x, vy = t2.y - t1.y
        let ul = (ux * ux + uy * uy).squareRoot(), vl = (vx * vx + vy * vy).squareRoot()
        guard radius > 0, ul > 0, vl > 0 else { addLine(to: t1); return }
        let u = PathPoint(ux / ul, uy / ul), v = PathPoint(vx / vl, vy / vl)
        let cosPhi = u.x * v.x + u.y * v.y          // the angle at the corner
        let cross = u.x * v.y - u.y * v.x
        guard cross != 0, cosPhi > -1, cosPhi < 1 else { addLine(to: t1); return }
        // Distance from the corner to each tangent point: r · cot(φ/2).
        let distance = radius * ((1 + cosPhi) / (1 - cosPhi)).squareRoot()
        let a = PathPoint(t1.x + u.x * distance, t1.y + u.y * distance)
        let b = PathPoint(t1.x + v.x * distance, t1.y + v.y * distance)
        addLine(to: a)
        // The arc sweeps α = π − φ; cos α = −cos φ. One cubic per half when
        // α exceeds 90°, the midpoint on the bisector.
        let cosAlpha = -cosPhi
        // Corner-to-centre distance r / sin(φ/2); sin(φ/2) = sqrt((1 − cos φ)/2).
        let sinHalfPhi = ((1 - cosPhi) / 2).squareRoot()
        let bisx = u.x + v.x, bisy = u.y + v.y
        let bl = (bisx * bisx + bisy * bisy).squareRoot()
        let centre = PathPoint(t1.x + bisx / bl * radius / sinHalfPhi, t1.y + bisy / bl * radius / sinHalfPhi)
        func arcPiece(from p: PathPoint, to q: PathPoint, cosSweep: Double) {
            // tan(θ/4) from cos θ: cos(θ/2) = sqrt((1 + cos θ)/2), tan(x/2) = sqrt((1 − cos x)/(1 + cos x)).
            let cosHalf = ((1 + cosSweep) / 2).squareRoot()
            let k = 4.0 / 3.0 * ((1 - cosHalf) / (1 + cosHalf)).squareRoot()
            // Tangent arms point from each end toward the other along the circle.
            let rpx = p.x - centre.x, rpy = p.y - centre.y, rqx = q.x - centre.x, rqy = q.y - centre.y
            let turn = rpx * rqy - rpy * rqx > 0 ? 1.0 : -1.0
            let c1 = PathPoint(p.x - turn * k * rpy, p.y + turn * k * rpx)
            let c2 = PathPoint(q.x + turn * k * rqy, q.y - turn * k * rqx)
            addCurve(to: q, control1: c1, control2: c2)
        }
        if cosAlpha >= 0 {
            arcPiece(from: a, to: b, cosSweep: cosAlpha)
        } else {
            let mx = t1.x - centre.x, my = t1.y - centre.y
            let ml = (mx * mx + my * my).squareRoot()
            let m = PathPoint(centre.x + mx / ml * radius, centre.y + my / ml * radius)
            let cosHalfSweep = ((1 + cosAlpha) / 2).squareRoot()
            arcPiece(from: a, to: m, cosSweep: cosHalfSweep)
            arcPiece(from: m, to: b, cosSweep: cosHalfSweep)
        }
    }

    /// Every element of `other`, as its own subpaths.
    package mutating func append(_ other: PathGeometry) {
        for element in other.elements {
            switch element {
            case .move(let p): move(to: p)
            case .line(let p): addLine(to: p)
            case .quad(let c, let p): addQuadCurve(to: p, control: c)
            case .cubic(let c1, let c2, let p): addCurve(to: p, control1: c1, control2: c2)
            case .close: closeSubpath()
            }
        }
    }

    /// Every point mapped by `t` — exact for Béziers (an affine map of the
    /// control points is the map of the curve).
    package func applying(_ t: PathAffine) -> PathGeometry {
        var out = PathGeometry()
        for element in elements {
            switch element {
            case .move(let p): out.move(to: t.apply(p))
            case .line(let p): out.addLine(to: t.apply(p))
            case .quad(let c, let p): out.addQuadCurve(to: t.apply(p), control: t.apply(c))
            case .cubic(let c1, let c2, let p): out.addCurve(to: t.apply(p), control1: t.apply(c1), control2: t.apply(c2))
            case .close: out.closeSubpath()
            }
        }
        return out
    }

    /// The box of every point and control point, or `nil` when empty.
    package var controlPointBounds: (minX: Double, minY: Double, maxX: Double, maxY: Double)? {
        var minX = Double.infinity, minY = Double.infinity, maxX = -Double.infinity, maxY = -Double.infinity
        func add(_ p: PathPoint) {
            minX = min(minX, p.x); minY = min(minY, p.y); maxX = max(maxX, p.x); maxY = max(maxY, p.y)
        }
        for element in elements {
            switch element {
            case .move(let p), .line(let p): add(p)
            case .quad(let c, let p): add(c); add(p)
            case .cubic(let c1, let c2, let p): add(c1); add(c2); add(p)
            case .close: break
            }
        }
        return minX <= maxX ? (minX, minY, maxX, maxY) : nil
    }
}
