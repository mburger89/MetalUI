import MetalUICore
import MetalUILayout

// SwiftUI's `Shape` (plan task 11, part 2; rulings `TE-AG`, `TE-AH`, `TE-AQ`
// items 1–3). Its `path(in:)` is narrowed to the two geometries the renderer
// draws (`TE-AD`): a rounded rectangle with circular per-corner radii and an
// ellipse. A `Path`, gradients and `StrokeStyle` are renderer constraints
// (spec §9).

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

/// What a ``Shape`` draws inside a rectangle — SwiftUI's `Path`, narrowed to
/// what MetalUI's renderer can draw (`TE-AG` item 1).
public struct ShapeGeometry: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case roundedRectangle(Corners<Pixels>, RoundedCornerStyle)
        case ellipse
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

    /// The radii the renderer draws: zero for an ellipse.
    var cornerRadii: Corners<Pixels> {
        if case let .roundedRectangle(radii, _) = kind { return radii }
        return Corners(all: Pixels(0))
    }

    /// The rect and radii a clip pushes (`TE-AJ` items 1–2). **An ellipse
    /// traps** (divergence 91, `TE-AJ` item 4): every primitive's mask is a
    /// rounded rectangle, and a custom `Shape` can return an ellipse at run
    /// time, so the check is here, at the clip, not in the type.
    var clipRegion: (bounds: Bounds<Pixels>, radii: Corners<Pixels>) {
        guard case let .roundedRectangle(radii, _) = kind else {
            preconditionFailure("clipShape(_:) of an ellipse cannot be drawn: every primitive's mask is "
                                + "a rounded rectangle (divergence 91, TE-AJ item 4)")
        }
        return (rect, radii)
    }

    /// Whether `point` lies in this geometry — the hit test of a declared
    /// `.contentShape(_:)` (plan task 12 part 1, ruling `IX-L`). Half-open on
    /// the rect's max edges, as `Bounds.contains` is; inside a rounded corner's
    /// square the point must lie within the corner's circle (a `.continuous`
    /// corner is tested circular, as it draws — divergence 90); an ellipse
    /// tests `(dx/a)² + (dy/b)² ≤ 1`.
    func contains(_ point: Point<Pixels>) -> Bool {
        guard rect.contains(point) else { return false }
        let x = point.x.value, y = point.y.value
        let minX = rect.origin.x.value, minY = rect.origin.y.value
        let w = rect.size.width.value, h = rect.size.height.value
        switch kind {
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
        ShapeGeometry(rect: Bounds(origin: Point(x: Pixels(rect.origin.x.value + dx),
                                                 y: Pixels(rect.origin.y.value + dy)),
                                   size: rect.size),
                      kind: kind)
    }

    /// The primitive kind the renderer draws (`MUIRect.shape`).
    var primitiveShape: PrimitiveShape {
        if case .ellipse = kind { return .ellipse }
        return .roundedRectangle
    }
}

/// SwiftUI's `Shape`: a proposal leaf that answers its proposal and draws a
/// geometry (`TE-AG`, `TE-AQ` item 1).
///
/// **A `ProposalElement`, not a bare `Element`**: an outside conformer writes
/// ``geometry(in:)`` alone, and this protocol's extension supplies the phases,
/// so it sits in an `HStack` (guard `anOutsideShapeNeedsOnlyItsGeometry`).
/// `Sendable` is SwiftUI's own refinement. A bare shape registers no hitbox,
/// focus entry or accessibility record, and snaps under animation.
public protocol Shape: ProposalElement, Sendable {
    /// SwiftUI's `path(in:)`, narrowed to what the renderer draws (TE-AG).
    func geometry(in rect: Bounds<Pixels>) -> ShapeGeometry

    /// SwiftUI's `sizeThatFits(_:)`. Default: the proposal, a nil axis 10
    /// (probe S1).
    nonisolated func sizeThatFits(_ proposal: ProposedSize) -> SizeD
}

/// A shape's layout state: its one native leaf.
public struct ShapeLayout {
    var node: LayoutNodeID
}

extension Shape {
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

/// The fill every bare shape and every `.fill` layer emits: one `MUIRect`
/// over the geometry's rect, `nil` meaning the foreground style.
@MainActor
func paintShapeFill(_ geometry: ShapeGeometry, token: ColorToken?, pass: PaintPass) {
    let resolved = token ?? pass.environment.foregroundStyle ?? .textPrimary
    pass.fill(geometry.rect, color: pass.theme[resolved], cornerRadii: geometry.cornerRadii,
              shape: geometry.primitiveShape)
}
