import MetalUICore
import MetalUILayout

// SwiftUI's `Shape` (plan task 11, part 2; rulings `TE-AG`, `TE-AH`, `TE-AQ`
// items 1–3). Since paths, shadows and transforms (`GX-D`) it has SwiftUI's
// `path(in:)` beside `geometry(in:)`, both defaulted: a geometry is a rounded
// rectangle with circular per-corner radii, an ellipse (each drawn by the
// renderer's exact SDF) or a `Path` (rasterized on the CPU, `GX-B`).
// Gradients stay a renderer constraint (spec §9).

/// How a rounded rectangle's corners are drawn — SwiftUI's spelling and its
/// default, `.continuous`.
///
/// **`.continuous` is drawn `.circular`** (divergence 90, `TE-AG` item 2):
/// the renderer's rounded-rect distance is circular, and Apple's continuous
/// curve has no closed form it carries (probe S3: 196 px apart at r 20 on
/// 100×60). The case exists so SwiftUI code spells the same.
public enum RoundedCornerStyle: Sendable, Hashable {
    case circular
    case continuous
}

/// What a ``Shape`` draws inside a rectangle (`TE-AG` item 1, `GX-D`): a
/// rounded rectangle or an ellipse, which the renderer draws exactly, or a
/// ``Path`` with its fill style, rasterized on the CPU.
public struct ShapeGeometry: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case roundedRectangle(Corners<Pixels>, RoundedCornerStyle)
        case ellipse
        case path(Path, FillStyle)
    }

    /// The geometry's bounding rectangle, in the shape's own coordinates.
    public let rect: Bounds<Pixels>
    let kind: Kind

    /// A rectangle with per-corner circular radii, each clamped to
    /// `0…min(width, height) / 2` (probes S4, S5).
    public static func roundedRectangle(_ rect: Bounds<Pixels>, cornerRadii: Corners<Pixels>,
                                        style: RoundedCornerStyle = .continuous) -> ShapeGeometry {
        let limit = max(0, min(rect.size.width.value, rect.size.height.value) / 2)
        func clamped(_ radius: Pixels) -> Pixels { Pixels(min(max(radius.value, 0), limit)) }
        let radii = Corners(topLeft: clamped(cornerRadii.topLeft), topRight: clamped(cornerRadii.topRight),
                            bottomRight: clamped(cornerRadii.bottomRight),
                            bottomLeft: clamped(cornerRadii.bottomLeft))
        return ShapeGeometry(rect: rect, kind: .roundedRectangle(radii, style))
    }

    /// The ellipse inscribed in `rect`.
    public static func ellipse(_ rect: Bounds<Pixels>) -> ShapeGeometry {
        ShapeGeometry(rect: rect, kind: .ellipse)
    }

    /// `path`, in the shape's (window-space) coordinates, filled by `style`
    /// (`GX-D`): its hit test is its winding, and as a clip it traps
    /// (divergence 91).
    public static func path(_ path: Path, style: FillStyle = FillStyle()) -> ShapeGeometry {
        ShapeGeometry(rect: path.boundingRect, kind: .path(path, style))
    }

    /// The path and style of a `.path` geometry, or `nil`.
    var pathAndStyle: (path: Path, style: FillStyle)? {
        if case let .path(path, style) = kind { return (path, style) }
        return nil
    }

    /// The radii the renderer draws: zero for an ellipse or a path.
    var cornerRadii: Corners<Pixels> {
        if case let .roundedRectangle(radii, _) = kind { return radii }
        return Corners(all: Pixels(0))
    }

    /// The rect and radii a clip pushes (`TE-AJ` items 1–2). **An ellipse or
    /// a path traps** (divergence 91, `TE-AJ` item 4, `GX-D`): every
    /// primitive's mask is a rounded rectangle, and a custom `Shape` can return
    /// either at run time, so the check is here, at the clip, not in the type.
    var clipRegion: (bounds: Bounds<Pixels>, radii: Corners<Pixels>) {
        switch kind {
        case let .roundedRectangle(radii, _):
            return (rect, radii)
        case .ellipse:
            preconditionFailure("clipShape(_:) of an ellipse cannot be drawn: every primitive's mask is "
                                + "a rounded rectangle (divergence 91, TE-AJ item 4)")
        case .path:
            preconditionFailure("clipShape(_:) of a path cannot be drawn: every primitive's mask is "
                                + "a rounded rectangle (divergence 91, GX-D)")
        }
    }

    /// Whether `point` lies in this geometry — the hit test of a declared
    /// `.contentShape(_:)` (plan task 12 part 1, ruling `IX-L`). Half-open on
    /// the rect's max edges, as `Bounds.contains` is; inside a rounded corner's
    /// square the point must lie within the corner's circle (a `.continuous`
    /// corner is tested circular, as it draws — divergence 90); an ellipse
    /// tests `(dx/a)² + (dy/b)² ≤ 1`; a path tests its winding under its fill
    /// style (`GX-D`).
    func contains(_ point: Point<Pixels>) -> Bool {
        if case let .path(path, style) = kind { return path.contains(point, eoFill: style.isEOFilled) }
        guard rect.contains(point) else { return false }
        let x = point.x.value, y = point.y.value
        let minX = rect.origin.x.value, minY = rect.origin.y.value
        let w = rect.size.width.value, h = rect.size.height.value
        switch kind {
        case .path:
            return false   // answered above
        case .ellipse:
            let a = w / 2, b = h / 2
            guard a > 0, b > 0 else { return false }
            let dx = (x - (minX + a)) / a, dy = (y - (minY + b)) / b
            return dx * dx + dy * dy <= 1
        case let .roundedRectangle(radii, _):
            func outside(_ r: Float, _ cx: Float, _ cy: Float, _ inCorner: Bool) -> Bool {
                guard r > 0, inCorner else { return false }
                let dx = x - cx, dy = y - cy
                return dx * dx + dy * dy > r * r
            }
            let maxX = minX + w, maxY = minY + h
            let tl = radii.topLeft.value, tr = radii.topRight.value
            let br = radii.bottomRight.value, bl = radii.bottomLeft.value
            if outside(tl, minX + tl, minY + tl, x < minX + tl && y < minY + tl) { return false }
            if outside(tr, maxX - tr, minY + tr, x > maxX - tr && y < minY + tr) { return false }
            if outside(br, maxX - br, maxY - br, x > maxX - br && y > maxY - br) { return false }
            if outside(bl, minX + bl, maxY - bl, x < minX + bl && y > maxY - bl) { return false }
            return true
        }
    }

    /// This geometry moved by `(dx, dy)` — window space for a hitbox.
    func offsetBy(dx: Float, dy: Float) -> ShapeGeometry {
        let moved: Kind
        if case let .path(path, style) = kind {
            moved = .path(path.offsetBy(dx: Pixels(dx), dy: Pixels(dy)), style)
        } else {
            moved = kind
        }
        return ShapeGeometry(rect: Bounds(origin: Point(x: Pixels(rect.origin.x.value + dx),
                                                        y: Pixels(rect.origin.y.value + dy)),
                                          size: rect.size),
                             kind: moved)
    }

    /// The primitive kind the renderer draws (`MUIRect.shape`).
    var primitiveShape: PrimitiveShape {
        if case .ellipse = kind { return .ellipse }
        return .roundedRectangle
    }
}

/// SwiftUI's `Shape`: a proposal leaf that answers its proposal and draws a
/// geometry (`TE-AG`, `TE-AQ` item 1, `GX-D`).
///
/// **A `ProposalElement`, not a bare `Element`**: an outside conformer writes
/// ``geometry(in:)`` or SwiftUI's ``path(in:)`` alone — both are defaulted in
/// terms of the other — and this protocol's extension supplies the phases, so
/// it sits in an `HStack` (guards `anOutsideShapeNeedsOnlyItsGeometry`,
/// `anOutsideShapeCanWritePathInAlone`). **A conformer implementing neither
/// traps naming `GX-D`** at its first paint, rather than recursing.
/// `Sendable` is SwiftUI's own refinement. A bare shape registers no hitbox,
/// focus entry or accessibility record, and snaps under animation.
public protocol Shape: ProposalElement, Sendable {
    /// What the shape draws in `rect`, in **window-space** coordinates (the
    /// rect is the shape's laid-out bounds). Default: ``path(in:)`` of the
    /// local rect, moved to `rect`'s origin, filled nonzero.
    func geometry(in rect: Bounds<Pixels>) -> ShapeGeometry

    /// SwiftUI's `path(in:)`: the outline in the shape's **local** rect,
    /// origin (0, 0) (probe PA9); the framework moves it to the layout origin.
    /// Default: ``geometry(in:)``'s rounded rectangle or ellipse as a path.
    func path(in rect: Bounds<Pixels>) -> Path

    /// SwiftUI's `sizeThatFits(_:)`. Default: the proposal, a nil axis 10
    /// (probe S1).
    nonisolated func sizeThatFits(_ proposal: ProposedSize) -> SizeD
}

/// A shape's layout state: its one native leaf.
public struct ShapeLayout {
    var node: LayoutNodeID
}

/// The reentrancy check for `Shape`'s two defaulted requirements (`GX-D`):
/// each default calls the other, so a conformer that implements neither would
/// recurse forever. A default pushes its shape's type and which default is
/// running; the other default, entered for the **same** type directly under
/// it, traps naming `GX-D`. Another shape's default called from inside a
/// conformer's own `path(in:)` is a different type and passes.
@MainActor
enum ShapeRequirementDefaults {
    enum Which { case geometry, path }
    static var running: [(type: ObjectIdentifier, which: Which)] = []

    static func run<S: Shape, R>(_ shape: S, _ which: Which, _ body: () -> R) -> R {
        let type = ObjectIdentifier(S.self)
        if let top = running.last, top.type == type, top.which != which {
            preconditionFailure("\(S.self) implements neither geometry(in:) nor path(in:): each defaults to "
                                + "the other, so a Shape must implement one (GX-D)")
        }
        running.append((type, which))
        defer { running.removeLast() }
        return body()
    }
}

extension Shape {
    /// ``path(in:)`` of the local rect (origin (0, 0), PA9), moved to `rect`'s
    /// origin and filled nonzero (`GX-D`).
    public func geometry(in rect: Bounds<Pixels>) -> ShapeGeometry {
        ShapeRequirementDefaults.run(self, .geometry) {
            let local = Bounds(origin: Point(x: Pixels(0), y: Pixels(0)), size: rect.size)
            return .path(path(in: local).offsetBy(dx: rect.origin.x, dy: rect.origin.y))
        }
    }

    /// ``geometry(in:)``'s rounded rectangle or ellipse as a path — the
    /// built-ins' answer, the same circular corners the SDF draws (`GX-D`).
    public func path(in rect: Bounds<Pixels>) -> Path {
        ShapeRequirementDefaults.run(self, .path) { Path(geometry(in: rect)) }
    }

    public nonisolated func sizeThatFits(_ proposal: ProposedSize) -> SizeD {
        SizeD(width: proposal.width ?? 10, height: proposal.height ?? 10)
    }

    /// One native leaf measured by ``sizeThatFits(_:)``.
    public mutating func requestProposalLayout(_ id: GlobalElementID,
                                               pass: inout LayoutPass) -> (ProposalNodeID, ShapeLayout) {
        let shape = self
        let node = pass.requestNativeLeaf { LayoutMeasurement(size: shape.sizeThatFits($0)) }
        return (node, ShapeLayout(node: node.layoutNodeID))
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout ShapeLayout, pass: inout PrepaintPass) {}

    /// The bare fill: `foregroundStyle ?? .textPrimary` (`TE-AH`; probes F1,
    /// F2).
    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout ShapeLayout, prepaint: inout Void,
                               pass: inout PaintPass) {
        paintShapeFill(geometry(in: bounds), token: nil, pass: pass)
    }
}

/// The fill every bare shape and every `.fill` layer emits, `nil` meaning the
/// foreground style: one `MUIRect` over a rounded rectangle or an ellipse;
/// a path (or any fill style a built-in's SDF cannot honour — no antialiasing)
/// rasterized and drawn as an image (`GX-B`). `style` overrides a path
/// geometry's own fill style when given.
@MainActor
func paintShapeFill(_ geometry: ShapeGeometry, token: ColorToken?, style: FillStyle? = nil, pass: PaintPass) {
    let resolved = token ?? pass.environment.foregroundStyle ?? .textPrimary
    let color = pass.theme[resolved]
    if let (path, own) = geometry.pathAndStyle {
        pass.drawPath(path, fill: style ?? own, color: color)
        return
    }
    if let style, !style.isAntialiased {
        pass.drawPath(Path(geometry), fill: style, color: color)
        return
    }
    pass.fill(geometry.rect, color: color, cornerRadii: geometry.cornerRadii,
              shape: geometry.primitiveShape)
}
