import MetalUICore
import MetalUILayout

// Fill, stroke and strokeBorder (plan task 11, part 2; ruling `TE-AI`).
// Colours are `ColorToken`s (spec §7.9); there is no `ShapeStyle`, no
// gradient and no `StrokeStyle` (spec §9).

extension Shape {
    /// Fills the shape with the foreground style (`foregroundStyle ??
    /// .textPrimary`, `TE-AH`) — SwiftUI's `fill()`.
    public func fill() -> ShapeView<Self> {
        ShapeView(shape: self, layers: [.fill(nil)])
    }

    /// Fills the shape with `token`; it wins over the foreground style
    /// (probe F3).
    public func fill(_ token: ColorToken) -> ShapeView<Self> {
        ShapeView(shape: self, layers: [.fill(token)])
    }

    /// Strokes the shape's outline, centred on its edge (probe K1): the
    /// ``strokeBorder(_:lineWidth:)`` of the shape outset by half the width,
    /// its radii grown by half the width where they are not zero (K6, K7,
    /// K12). Changes no layout (K5); a width ≤ 0 draws nothing (K9).
    public func stroke(_ token: ColorToken, lineWidth: Pixels = Pixels(1)) -> ShapeView<Self> {
        ShapeView(shape: self, layers: [.stroke(token, lineWidth)])
    }

    /// Strokes inside the shape's edge (probe K2). A corner whose radius is
    /// under half the width draws square outside (K11); a width over half the
    /// shorter side fills (K10). Offered on every `Shape` — every geometry
    /// MetalUI draws is insettable (`TE-AG` item 3).
    public func strokeBorder(_ token: ColorToken, lineWidth: Pixels = Pixels(1)) -> ShapeView<Self> {
        ShapeView(shape: self, layers: [.strokeBorder(token, lineWidth)])
    }
}

/// A shape with fills and strokes — SwiftUI's `_ShapeView`. Its layers paint
/// in declaration order, so `.fill(a).stroke(b)` strokes over the fill
/// (probe F4); each paints its own colour, never the shape's stored one
/// (`TE-AQ` item 2). Lays out exactly as its shape does.
public struct ShapeView<S: Shape>: Element {
    /// The shape laid out and painted.
    public var shape: S

    enum Layer: Sendable, Equatable {
        case fill(ColorToken?)
        case stroke(ColorToken, Pixels)
        case strokeBorder(ColorToken, Pixels)
    }

    var layers: [Layer]

    init(shape: S, layers: [Layer]) {
        self.shape = shape
        self.layers = layers
    }

    /// Adds a fill over the layers so far.
    public func fill(_ token: ColorToken) -> ShapeView<S> {
        ShapeView(shape: shape, layers: layers + [.fill(token)])
    }

    /// Adds a centred stroke over the layers so far.
    public func stroke(_ token: ColorToken, lineWidth: Pixels = Pixels(1)) -> ShapeView<S> {
        ShapeView(shape: shape, layers: layers + [.stroke(token, lineWidth)])
    }

    /// Adds an inside stroke over the layers so far.
    public func strokeBorder(_ token: ColorToken, lineWidth: Pixels = Pixels(1)) -> ShapeView<S> {
        ShapeView(shape: shape, layers: layers + [.strokeBorder(token, lineWidth)])
    }

    public mutating func requestProposalLayout(_ id: GlobalElementID,
                                               pass: inout LayoutPass) -> (ProposalNodeID, S.LayoutState) {
        shape.requestProposalLayout(id, pass: &pass)
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout S.LayoutState, pass: inout PrepaintPass) {}

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout S.LayoutState, prepaint: inout Void,
                               pass: inout PaintPass) {
        let geometry = shape.geometry(in: bounds)
        for layer in layers {
            switch layer {
            case let .fill(token):
                paintShapeFill(geometry, token: token, pass: pass)
            case let .stroke(token, width):
                paintShapeStroke(geometry, token: token, width: width, outset: true, pass: pass)
            case let .strokeBorder(token, width):
                paintShapeStroke(geometry, token: token, width: width, outset: false, pass: pass)
            }
        }
    }
}

extension ShapeView: ProposalElement {}

/// One stroke layer (`TE-AI`). **strokeBorder(w)**: one `MUIRect` over the
/// geometry's rect, border `w`, a clear background, each outer radius kept
/// when at least `w/2` and else 0 (probe K11: a square outer corner), the
/// inner radius the shader's `max(r − w, 0)`. **stroke(w)**: the same over
/// the rect outset by `w/2`, each radius `r > 0 ? r + w/2 : 0` (K1, K6, K7,
/// K12) — which is at least `w/2`, so the strokeBorder rule keeps it. An
/// ellipse takes the ellipse kind, whose band is the inset ellipse's stroke
/// (K8, `TE-AE`). A width ≤ 0 emits nothing (K9).
@MainActor
func paintShapeStroke(_ geometry: ShapeGeometry, token: ColorToken, width: Pixels, outset: Bool,
                      pass: PaintPass) {
    let w = width.value
    guard w > 0 else { return }
    var rect = geometry.rect
    var radii = geometry.cornerRadii
    if outset {
        rect = Bounds(origin: Point(x: Pixels(rect.origin.x.value - w / 2), y: Pixels(rect.origin.y.value - w / 2)),
                      size: Size(width: Pixels(rect.size.width.value + w),
                                 height: Pixels(rect.size.height.value + w)))
        func grown(_ r: Pixels) -> Pixels { r.value > 0 ? Pixels(r.value + w / 2) : Pixels(0) }
        radii = Corners(topLeft: grown(radii.topLeft), topRight: grown(radii.topRight),
                        bottomRight: grown(radii.bottomRight), bottomLeft: grown(radii.bottomLeft))
    }
    func kept(_ r: Pixels) -> Pixels { r.value >= w / 2 ? r : Pixels(0) }
    radii = Corners(topLeft: kept(radii.topLeft), topRight: kept(radii.topRight),
                    bottomRight: kept(radii.bottomRight), bottomLeft: kept(radii.bottomLeft))
    pass.fill(rect, color: .transparent, cornerRadii: radii, borderColor: pass.theme[token],
              borderWidths: Edges(all: width), shape: geometry.primitiveShape)
}
