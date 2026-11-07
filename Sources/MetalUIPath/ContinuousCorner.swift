// SwiftUI's `.continuous` rounded corner (divergence 90, ruling `CC-`, record 226).
//
// Read, not fitted: SwiftUI's own Beziers (`Path.forEach`) agree with this model to
// 7.5e-6 absolute over `RoundedRectangle`, `Capsule`, `UnevenRoundedRectangle` and an
// elliptical `cornerSize` (`docs/probes/swiftui-continuous-corners.swift`, CC1..CC4).
//
// **Imports nothing**, like the rest of this target: the constants below are the
// shaders' (`shaders.metal` `CC_*`, `replay.hlsl`), and a test pins each to the
// other.

/// One corner of radius `rx × ry` whose two sides have `roomX` and `roomY` to spare.
package struct ContinuousCornerSpec: Hashable, Sendable {
    package var rx: Double
    package var ry: Double
    package var roomX: Double
    package var roomY: Double
    package init(rx: Double, ry: Double, roomX: Double, roomY: Double) {
        self.rx = rx; self.ry = ry; self.roomX = roomX; self.roomY = roomY
    }
}

package enum ContinuousCorner {
    /// How far along a side a corner reaches, in radii (`1.528664947`).
    package static let extent = 1.528664947
    package static let k0 = 0.631493986
    package static let k1 = 0.074911401
    package static let m1 = 0.372824013
    package static let m2 = 0.169060007
    /// `c1(t) = a1 + b1 t`, `c2(t) = a2 + b2 t`: the first and second control arm of
    /// the outer cubic when the side leaves `t` radii (`t` in `1...extent`).
    package static let a1 = 0.716953795
    package static let b1 = 0.243046205
    package static let a2 = 0.728435369
    package static let b2 = 0.091564631

    /// The three cubics of a corner, **horizontal side first**, in corner-local
    /// coordinates: `x` along the horizontal side and `y` along the vertical side,
    /// both measured from the corner. Four points each (start, two controls, end).
    /// A zero radius is three degenerate cubics at the origin.
    package static func cubics(_ c: ContinuousCornerSpec) -> [[PathPoint]] {
        guard c.rx > 0, c.ry > 0 else {
            return Array(repeating: Array(repeating: PathPoint(0, 0), count: 4), count: 3)
        }
        let tu = min(c.roomX / c.rx, extent), tv = min(c.roomY / c.ry, extent)
        func p(_ u: Double, _ v: Double) -> PathPoint { PathPoint(u * c.rx, v * c.ry) }
        return [[p(tu, 0), p(a1 + b1 * tu, 0), p(a2 + b2 * tu, 0), p(k0, k1)],
                [p(k0, k1), p(m1, m2), p(m2, m1), p(k1, k0)],
                [p(k1, k0), p(0, a2 + b2 * tv), p(0, a1 + b1 * tv), p(0, tv)]]
    }

    /// How far a corner reaches along its horizontal and vertical side.
    package static func reach(_ c: ContinuousCornerSpec) -> (x: Double, y: Double) {
        guard c.rx > 0, c.ry > 0 else { return (0, 0) }
        return (min(c.roomX / c.rx, extent) * c.rx, min(c.roomY / c.ry, extent) * c.ry)
    }

    /// Two corners sharing a side of length `side`: if they overlap, the larger is
    /// cut back to what the smaller leaves, and neither below half the side; two
    /// that are both at least half take half each (probe CC3).
    package static func fitPair(_ a: Double, _ b: Double, _ side: Double) -> (Double, Double) {
        guard side > 0 else { return (0, 0) }
        guard a + b > side else { return (a, b) }
        if min(a, b) >= side / 2 { return (side / 2, side / 2) }
        return a < b ? (a, side - a) : (side - b, b)
    }

    /// `UnevenRoundedRectangle`'s radii fitted to a `width × height` rectangle,
    /// `(topLeft, topRight, bottomRight, bottomLeft)`: the horizontal sides first
    /// (top, then bottom), then the vertical sides (right, then left), each pair by
    /// `fitPair` on the radii as the earlier sides left them. **Measured against
    /// SwiftUI on 2000 random radii: 0 mismatches, where the other 23 orders of the
    /// four sides mismatch 38 to 186; the circular style fits the same way** (probe
    /// CC3, CC3c).
    package static func fit(width: Double, height: Double, topLeft: Double, topRight: Double,
                            bottomRight: Double, bottomLeft: Double)
        -> (topLeft: Double, topRight: Double, bottomRight: Double, bottomLeft: Double) {
        var tl = max(0, topLeft), tr = max(0, topRight), br = max(0, bottomRight), bl = max(0, bottomLeft)
        (tl, tr) = fitPair(tl, tr, width)
        (bl, br) = fitPair(bl, br, width)
        (tr, br) = fitPair(tr, br, height)
        (tl, bl) = fitPair(tl, bl, height)
        return (tl, tr, br, bl)
    }

    /// Whether the renderer's distance can draw these **fitted** radii: it folds a point into the quadrant
    /// of its corner, so every corner's curve (its reach along each side, `reach`) must stay within that
    /// quadrant. Equal radii up to half the shorter side always do; a corner that takes most of a side the
    /// others leave free does not, and is a `Path` (`PG-G`). A corner reaches at least its radius, so a
    /// `true` answer also means no radius needs the shape's clamp to half the shorter side.
    package static func fitsQuadrants(width: Double, height: Double, topLeft: Double, topRight: Double,
                                      bottomRight: Double, bottomLeft: Double) -> Bool {
        func fits(_ r: Double, _ otherH: Double, _ otherV: Double) -> Bool {
            guard r > 0 else { return true }
            let c = ContinuousCornerSpec(rx: r, ry: r, roomX: room(side: width, r: r, other: otherH),
                                         roomY: room(side: height, r: r, other: otherV))
            let reached = reach(c)
            return reached.x <= width / 2 * (1 + 1e-9) && reached.y <= height / 2 * (1 + 1e-9)
        }
        return fits(topLeft, topRight, bottomLeft) && fits(topRight, topLeft, bottomRight)
            && fits(bottomRight, bottomLeft, topRight) && fits(bottomLeft, bottomRight, topLeft)
    }

    /// A side's room for a corner of radius `r` beside one of `other`: the side's
    /// length shared in proportion to the radii (all of it beside a square corner).
    package static func room(side: Double, r: Double, other: Double) -> Double {
        r + other > 0 ? side * r / (r + other) : side
    }
}

extension PathGeometry {
    /// A rectangle with continuous corners of radii `topLeft…bottomLeft` (already
    /// fitted: `ContinuousCorner.fit`), SwiftUI's start (the right edge, midway
    /// between where the top-right corner ends and the bottom-right one begins) and
    /// order (down, then clockwise). A square corner is a line to the corner.
    package mutating func addContinuousRoundedRect(x: Double, y: Double, width: Double, height: Double,
                                                   topLeft: Double, topRight: Double,
                                                   bottomRight: Double, bottomLeft: Double) {
        func spec(_ r: Double, _ otherH: Double, _ otherV: Double) -> ContinuousCornerSpec {
            ContinuousCornerSpec(rx: r, ry: r,
                                 roomX: ContinuousCorner.room(side: width, r: r, other: otherH),
                                 roomY: ContinuousCorner.room(side: height, r: r, other: otherV))
        }
        addContinuousCorners(x: x, y: y, width: width, height: height,
                             topLeft: spec(topLeft, topRight, bottomLeft), topRight: spec(topRight, topLeft, bottomRight),
                             bottomRight: spec(bottomRight, bottomLeft, topRight),
                             bottomLeft: spec(bottomLeft, bottomRight, topLeft))
    }

    /// A rectangle with continuous elliptical corners `rx × ry`; the pair scales
    /// together, keeping its ratio, until it fits half the sides (probe CC4).
    package mutating func addContinuousRoundedRect(x: Double, y: Double, width: Double, height: Double,
                                                   rx: Double, ry: Double) {
        let rx = max(0, rx), ry = max(0, ry)
        guard rx > 0, ry > 0 else { addRect(x: x, y: y, width: width, height: height); return }
        let k = min(1, width / 2 / rx, height / 2 / ry)
        let c = ContinuousCornerSpec(rx: rx * k, ry: ry * k, roomX: width / 2, roomY: height / 2)
        addContinuousCorners(x: x, y: y, width: width, height: height, topLeft: c, topRight: c,
                             bottomRight: c, bottomLeft: c)
    }

    private mutating func addContinuousCorners(x: Double, y: Double, width: Double, height: Double,
                                               topLeft: ContinuousCornerSpec, topRight: ContinuousCornerSpec,
                                               bottomRight: ContinuousCornerSpec, bottomLeft: ContinuousCornerSpec) {
        let x1 = x + width, y1 = y + height
        move(to: PathPoint(x1, y + (topRight.ry + (height - bottomRight.ry)) / 2))
        // `vertical`: the corner is entered along its vertical side (the right-hand corners
        // going down and the left-hand ones going up), so its cubics run in reverse.
        func corner(_ c: ContinuousCornerSpec, _ ox: Double, _ oy: Double, _ sx: Double, _ sy: Double,
                    vertical: Bool) {
            var segments = ContinuousCorner.cubics(c)
            if vertical { segments = segments.reversed().map { Array($0.reversed()) } }
            func g(_ p: PathPoint) -> PathPoint { PathPoint(ox + sx * p.x, oy + sy * p.y) }
            addLine(to: g(segments[0][0]))
            guard c.rx > 0, c.ry > 0 else { return }
            for s in segments { addCurve(to: g(s[3]), control1: g(s[1]), control2: g(s[2])) }
        }
        corner(bottomRight, x1, y1, -1, -1, vertical: true)
        corner(bottomLeft, x, y1, 1, -1, vertical: false)
        corner(topLeft, x, y, 1, 1, vertical: true)
        corner(topRight, x1, y, -1, 1, vertical: false)
        closeSubpath()
    }
}
