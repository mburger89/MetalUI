import MetalUICore
import MetalUILayout
import MetalUIPath

// Paths, shadows and transforms, lane 3 — SwiftUI's `Path` (rulings `GX-B`,
// `GX-C`, `GX-D`). Spec
// `docs/superpowers/specs/2026-10-02-paths-shadows-transforms-design.md` §1 and
// §4.1; SwiftUI's side is `docs/probes/swiftui-paths-shadows-transforms.swift`,
// arms PA1–PA9.

/// A vector outline — SwiftUI's `Path`, over MetalUI's geometry
/// (`Point<Pixels>`, `Bounds<Pixels>`; no `CGPoint` crosses the portable seam,
/// `GX-C`).
///
/// A path is a list of subpaths of lines, quadratic and cubic Béziers; arcs,
/// ellipses and rounded rectangles are stored as cubics of at most 90° each.
/// **As a view** it answers its proposal like every shape (nil → 10, probe PA1)
/// and draws its own coordinates from its layout origin, neither scaled to nor
/// clipped by its frame (PA1, PA1b), filled with `foregroundStyle ??
/// .textPrimary` (PA8). It is rasterized on the CPU in device pixels, after
/// every render effect, so it stays crisp under `scaleEffect` and
/// `rotationEffect` (T16, `GX-B`), and drawn as an image. A `Path` view whose
/// path changes snaps under animation (N7).
///
/// **`clockwise` reads in y-up terms**, as SwiftUI's does: `clockwise: false`
/// from 0° to 90° sweeps through the below-right quadrant (PA3). An open
/// subpath fills as if closed (PA6). `.continuous` rounded corners are drawn
/// circular (divergence 90).
public struct Path: Shape, Equatable, Sendable {
    var storage: PathGeometry

    /// An empty path.
    nonisolated public init() { storage = PathGeometry() }

    nonisolated init(storage: PathGeometry) { self.storage = storage }

    /// A closed rectangle.
    nonisolated public init(_ rect: Bounds<Pixels>) {
        self.init()
        addRect(rect)
    }

    /// A rounded rectangle whose corners have `cornerRadius` (clamped to half
    /// the shorter side).
    nonisolated public init(roundedRect rect: Bounds<Pixels>, cornerRadius: Pixels,
                style: RoundedCornerStyle = .continuous) {
        self.init()
        addRoundedRect(in: rect, cornerSize: Size(width: cornerRadius, height: cornerRadius), style: style)
    }

    /// A rounded rectangle whose corners are `cornerSize` ellipse quadrants.
    nonisolated public init(roundedRect rect: Bounds<Pixels>, cornerSize: Size<Pixels>,
                style: RoundedCornerStyle = .continuous) {
        self.init()
        addRoundedRect(in: rect, cornerSize: cornerSize, style: style)
    }

    /// The ellipse inscribed in `rect` (equal to `Ellipse()`'s, probe PA5).
    nonisolated public init(ellipseIn rect: Bounds<Pixels>) {
        self.init()
        addEllipse(in: rect)
    }

    /// A path built by `build` — SwiftUI's `Path { path in … }`.
    nonisolated public init(_ build: (inout Path) -> Void) {
        self.init()
        build(&self)
    }

    nonisolated private static func point(_ p: Point<Pixels>) -> PathPoint {
        PathPoint(Double(p.x.value), Double(p.y.value))
    }

    nonisolated private static func point(_ p: PathPoint) -> Point<Pixels> {
        Point(x: Pixels(Float(p.x)), y: Pixels(Float(p.y)))
    }

    /// Starts a new subpath at `point`.
    nonisolated public mutating func move(to point: Point<Pixels>) { storage.move(to: Self.point(point)) }

    /// A line from the current point to `point` (a move on an empty path).
    nonisolated public mutating func addLine(to point: Point<Pixels>) { storage.addLine(to: Self.point(point)) }

    /// A line through each of `points`, the first a move when the path is
    /// empty — SwiftUI's `addLines(_:)`, which starts a new subpath.
    nonisolated public mutating func addLines(_ points: [Point<Pixels>]) {
        guard let first = points.first else { return }
        move(to: first)
        for point in points.dropFirst() { addLine(to: point) }
    }

    /// A quadratic Bézier from the current point to `point`.
    nonisolated public mutating func addQuadCurve(to point: Point<Pixels>, control: Point<Pixels>) {
        storage.addQuadCurve(to: Self.point(point), control: Self.point(control))
    }

    /// A cubic Bézier from the current point to `point`.
    nonisolated public mutating func addCurve(to point: Point<Pixels>, control1: Point<Pixels>, control2: Point<Pixels>) {
        storage.addCurve(to: Self.point(point), control1: Self.point(control1), control2: Self.point(control2))
    }

    /// A circular arc about `center` — a line (or a move) to its start, then
    /// cubics of at most 90°. `clockwise` reads in y-up terms (PA3).
    nonisolated public mutating func addArc(center: Point<Pixels>, radius: Pixels, startAngle: Angle, endAngle: Angle,
                                clockwise: Bool) {
        storage.addArc(center: Self.point(center), radius: Double(radius.value), startAngle: startAngle.radians,
                       endAngle: endAngle.radians, clockwise: clockwise)
    }

    /// The arc of `radius` tangent to the lines from the current point to
    /// `tangent1End` and from there to `tangent2End`.
    nonisolated public mutating func addArc(tangent1End: Point<Pixels>, tangent2End: Point<Pixels>, radius: Pixels) {
        storage.addArc(tangent1End: Self.point(tangent1End), tangent2End: Self.point(tangent2End),
                       radius: Double(radius.value))
    }

    /// A closed rectangle subpath, clockwise on screen.
    nonisolated public mutating func addRect(_ rect: Bounds<Pixels>) {
        storage.addRect(x: Double(rect.origin.x.value), y: Double(rect.origin.y.value),
                        width: Double(rect.size.width.value), height: Double(rect.size.height.value))
    }

    /// A closed rectangle subpath for each of `rects`.
    nonisolated public mutating func addRects(_ rects: [Bounds<Pixels>]) {
        for rect in rects { addRect(rect) }
    }

    /// A closed rounded-rectangle subpath with `cornerSize` corners, each
    /// clamped to half its side. `.continuous` is drawn circular
    /// (divergence 90).
    nonisolated public mutating func addRoundedRect(in rect: Bounds<Pixels>, cornerSize: Size<Pixels>,
                                        style: RoundedCornerStyle = .continuous) {
        storage.addRoundedRect(x: Double(rect.origin.x.value), y: Double(rect.origin.y.value),
                               width: Double(rect.size.width.value), height: Double(rect.size.height.value),
                               rx: Double(cornerSize.width.value), ry: Double(cornerSize.height.value))
    }

    /// The closed ellipse inscribed in `rect`.
    nonisolated public mutating func addEllipse(in rect: Bounds<Pixels>) {
        storage.addEllipse(x: Double(rect.origin.x.value), y: Double(rect.origin.y.value),
                           width: Double(rect.size.width.value), height: Double(rect.size.height.value))
    }

    /// Every subpath of `path`.
    nonisolated public mutating func addPath(_ path: Path) { storage.append(path.storage) }

    /// Closes the current subpath with a line back to its start.
    nonisolated public mutating func closeSubpath() { storage.closeSubpath() }

    /// Whether the path has no elements.
    nonisolated public var isEmpty: Bool { storage.isEmpty }

    /// The end of the last element, or `nil` on an empty path.
    nonisolated public var currentPoint: Point<Pixels>? { storage.currentPoint.map(Self.point) }

    /// The smallest rectangle holding the path's outline (its flattened
    /// curves, not their control points); a zero rectangle when empty.
    nonisolated public var boundingRect: Bounds<Pixels> {
        var minX = Double.infinity, minY = Double.infinity, maxX = -Double.infinity, maxY = -Double.infinity
        for line in Flattener.flatten(storage, tolerance: Self.hitTolerance) {
            for p in line.points {
                minX = min(minX, p.x); minY = min(minY, p.y); maxX = max(maxX, p.x); maxY = max(maxY, p.y)
            }
        }
        guard minX <= maxX else {
            return Bounds(origin: Point(x: Pixels(0), y: Pixels(0)), size: Size(width: Pixels(0), height: Pixels(0)))
        }
        return Bounds(origin: Point(x: Pixels(Float(minX)), y: Pixels(Float(minY))),
                      size: Size(width: Pixels(Float(maxX - minX)), height: Pixels(Float(maxY - minY))))
    }

    /// The flattening tolerance `contains` and `boundingRect` use, in path
    /// units — finer than the rasterizer's device tolerance, so a hit test
    /// agrees with the drawn outline to a hundredth of a point.
    nonisolated static let hitTolerance = 0.01

    /// Whether `point` is inside the path under nonzero winding, or even-odd
    /// when `eoFill` — SwiftUI's `contains(_:eoFilled:)`. Every subpath counts
    /// as closed (PA6). This is the hit test of `contentShape(_:)` over a path
    /// (`GX-D`).
    nonisolated public func contains(_ point: Point<Pixels>, eoFill: Bool = false) -> Bool {
        let x = Double(point.x.value), y = Double(point.y.value)
        var winding = 0
        for line in Flattener.flatten(storage, tolerance: Self.hitTolerance) where line.points.count > 2 {
            let points = line.points
            for i in 0..<points.count {
                let a = points[i], b = points[(i + 1) % points.count]
                if a.y <= y {
                    if b.y > y && (b.x - a.x) * (y - a.y) - (x - a.x) * (b.y - a.y) > 0 { winding += 1 }
                } else if b.y <= y && (b.x - a.x) * (y - a.y) - (x - a.x) * (b.y - a.y) < 0 {
                    winding -= 1
                }
            }
        }
        return eoFill ? winding % 2 != 0 : winding != 0
    }

    /// This path moved by `(dx, dy)`.
    nonisolated public func offsetBy(dx: Pixels, dy: Pixels) -> Path {
        Path(storage: storage.applying(.translation(Double(dx.value), Double(dy.value))))
    }

    // MARK: Shape

    /// The path itself, whatever the rect — its coordinates are its own (PA1).
    public func path(in rect: Bounds<Pixels>) -> Path { self }

    /// The path moved to `rect`'s origin, filled nonzero (`GX-D`).
    public func geometry(in rect: Bounds<Pixels>) -> ShapeGeometry {
        .path(offsetBy(dx: rect.origin.x, dy: rect.origin.y))
    }
}

extension Path {
    /// The outline of a rounded rectangle or an ellipse geometry, for
    /// `Shape.path(in:)`'s default (`GX-D`): per-corner circular quarter arcs
    /// as cubics, the same corners the renderer's SDF draws.
    nonisolated init(_ geometry: ShapeGeometry) {
        self.init()
        let r = geometry.rect
        let x = Double(r.origin.x.value), y = Double(r.origin.y.value)
        let w = Double(r.size.width.value), h = Double(r.size.height.value)
        switch geometry.kind {
        case .ellipse:
            storage.addEllipse(x: x, y: y, width: w, height: h)
        case let .path(path, _):
            storage = path.storage
        case let .roundedRectangle(radii, _):
            let k = Path.cornerKappa
            let tl = Double(radii.topLeft.value), tr = Double(radii.topRight.value)
            let br = Double(radii.bottomRight.value), bl = Double(radii.bottomLeft.value)
            let x1 = x + w, y1 = y + h
            storage.move(to: PathPoint(x + tl, y))
            storage.addLine(to: PathPoint(x1 - tr, y))
            if tr > 0 {
                storage.addCurve(to: PathPoint(x1, y + tr), control1: PathPoint(x1 - tr + tr * k, y),
                                 control2: PathPoint(x1, y + tr - tr * k))
            }
            storage.addLine(to: PathPoint(x1, y1 - br))
            if br > 0 {
                storage.addCurve(to: PathPoint(x1 - br, y1), control1: PathPoint(x1, y1 - br + br * k),
                                 control2: PathPoint(x1 - br + br * k, y1))
            }
            storage.addLine(to: PathPoint(x + bl, y1))
            if bl > 0 {
                storage.addCurve(to: PathPoint(x, y1 - bl), control1: PathPoint(x + bl - bl * k, y1),
                                 control2: PathPoint(x, y1 - bl + bl * k))
            }
            storage.addLine(to: PathPoint(x, y + tl))
            if tl > 0 {
                storage.addCurve(to: PathPoint(x + tl, y), control1: PathPoint(x, y + tl - tl * k),
                                 control2: PathPoint(x + tl - tl * k, y))
            }
            storage.closeSubpath()
        }
    }

    /// A quarter circle's control-arm fraction (`4/3 (√2 − 1)`).
    nonisolated static let cornerKappa = PathGeometry.kappa
}
