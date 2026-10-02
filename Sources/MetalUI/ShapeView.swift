import MetalUICore
import MetalUILayout

// Fill, stroke and strokeBorder (plan task 11, part 2; ruling `TE-AI`), and
// since paths, shadows and transforms their `FillStyle`/`StrokeStyle` forms
// (`GX-E`). Colours are `ColorToken`s (spec §7.9); there is no `ShapeStyle`
// and no gradient (spec §9).

extension Shape {
    /// Fills the shape with the foreground style (`foregroundStyle ??
    /// .textPrimary`, `TE-AH`) — SwiftUI's `fill()`.
    public func fill() -> ShapeView<Self> {
        ShapeView(shape: self, layers: [.fill(nil, nil)])
    }

    /// Fills the shape with `token`; it wins over the foreground style
    /// (probe F3).
    public func fill(_ token: ColorToken) -> ShapeView<Self> {
        ShapeView(shape: self, layers: [.fill(token, nil)])
    }

    /// Fills the shape with the foreground style under `style` — SwiftUI's
    /// `fill(style:)` (`GX-E`; even-odd, probe PA2).
    public func fill(style: FillStyle) -> ShapeView<Self> {
        ShapeView(shape: self, layers: [.fill(nil, style)])
    }

    /// Fills the shape with `token` under `style` (`GX-E`).
    public func fill(_ token: ColorToken, style: FillStyle) -> ShapeView<Self> {
        ShapeView(shape: self, layers: [.fill(token, style)])
    }

    /// Strokes the shape's outline with `style`, centred on its edge — SwiftUI's
    /// `stroke(_:style:)` (`GX-E`; probe ST1–ST10). A built-in shape stroked
    /// with only a width (a miter join, no dash) keeps the renderer's exact
    /// band; anything else is stroked on the CPU and drawn as an image.
    public func stroke(_ token: ColorToken, style: StrokeStyle) -> ShapeView<Self> {
        ShapeView(shape: self, layers: [.stroke(token, style)])
    }

    /// Strokes inside the shape's edge with `style` — the shape inset by half
    /// the width, stroked (`GX-E`, `TE-AE`'s rule).
    public func strokeBorder(_ token: ColorToken, style: StrokeStyle) -> ShapeView<Self> {
        ShapeView(shape: self, layers: [.strokeBorder(token, style)])
    }

    /// Strokes the shape's outline, centred on its edge (probe K1): the
    /// ``strokeBorder(_:lineWidth:)`` of the shape outset by half the width,
    /// its radii grown by half the width where they are not zero (K6, K7,
    /// K12). Changes no layout (K5); a width ≤ 0 draws nothing (K9).
    public func stroke(_ token: ColorToken, lineWidth: Pixels = Pixels(1)) -> ShapeView<Self> {
        ShapeView(shape: self, layers: [.stroke(token, StrokeStyle(lineWidth: lineWidth))])
    }

    /// Strokes inside the shape's edge (probe K2). A corner whose radius is
    /// under half the width draws square outside (K11); a width over half the
    /// shorter side fills (K10). Offered on every `Shape` — every geometry
    /// MetalUI draws is insettable (`TE-AG` item 3).
    public func strokeBorder(_ token: ColorToken, lineWidth: Pixels = Pixels(1)) -> ShapeView<Self> {
        ShapeView(shape: self, layers: [.strokeBorder(token, StrokeStyle(lineWidth: lineWidth))])
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
        /// A fill; `nil` style means the geometry's own (a path's) or nonzero.
        case fill(ColorToken?, FillStyle?)
        case stroke(ColorToken, StrokeStyle)
        case strokeBorder(ColorToken, StrokeStyle)
    }

    var layers: [Layer]

    init(shape: S, layers: [Layer]) {
        self.shape = shape
        self.layers = layers
    }

    /// Adds a fill over the layers so far.
    public func fill(_ token: ColorToken) -> ShapeView<S> {
        ShapeView(shape: shape, layers: layers + [.fill(token, nil)])
    }

    /// Adds a fill under `style` over the layers so far (`GX-E`).
    public func fill(_ token: ColorToken, style: FillStyle) -> ShapeView<S> {
        ShapeView(shape: shape, layers: layers + [.fill(token, style)])
    }

    /// Adds a centred stroke over the layers so far.
    public func stroke(_ token: ColorToken, lineWidth: Pixels = Pixels(1)) -> ShapeView<S> {
        ShapeView(shape: shape, layers: layers + [.stroke(token, StrokeStyle(lineWidth: lineWidth))])
    }

    /// Adds a centred stroke under `style` over the layers so far (`GX-E`).
    public func stroke(_ token: ColorToken, style: StrokeStyle) -> ShapeView<S> {
        ShapeView(shape: shape, layers: layers + [.stroke(token, style)])
    }

    /// Adds an inside stroke over the layers so far.
    public func strokeBorder(_ token: ColorToken, lineWidth: Pixels = Pixels(1)) -> ShapeView<S> {
        ShapeView(shape: shape, layers: layers + [.strokeBorder(token, StrokeStyle(lineWidth: lineWidth))])
    }

    /// Adds an inside stroke under `style` over the layers so far (`GX-E`).
    public func strokeBorder(_ token: ColorToken, style: StrokeStyle) -> ShapeView<S> {
        ShapeView(shape: shape, layers: layers + [.strokeBorder(token, style)])
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
            case let .fill(token, style):
                paintShapeFill(geometry, token: token, style: style, pass: pass)
            case let .stroke(token, style):
                paintStyledStroke(shape, geometry, bounds: bounds, token: token, style: style, outset: true,
                                  pass: pass)
            case let .strokeBorder(token, style):
                paintStyledStroke(shape, geometry, bounds: bounds, token: token, style: style, outset: false,
                                  pass: pass)
            }
        }
    }
}

extension ShapeView: ProposalElement {}

/// One stroke layer under `style` (`GX-E`). **Routing keeps every existing
/// stroke on its primitive**: a built-in geometry (a rounded rectangle or an
/// ellipse) whose style is plain apart from its width draws the SDF band
/// (`paintShapeStroke`, unchanged). Anything else — a round or bevel join, a
/// dash, any path — is stroked on the CPU: `stroke` strokes the outline
/// itself, `strokeBorder` the shape's outline in its rect inset by half the
/// width (`TE-AE`'s rule). A width ≤ 0 draws nothing (ST10).
@MainActor
func paintStyledStroke<S: Shape>(_ shape: S, _ geometry: ShapeGeometry, bounds: Bounds<Pixels>,
                                 token: ColorToken, style: StrokeStyle, outset: Bool, pass: PaintPass) {
    guard style.lineWidth.value > 0 else { return }
    if geometry.pathAndStyle == nil && style.isPlainBand {
        paintShapeStroke(geometry, token: token, width: style.lineWidth, outset: outset, pass: pass)
        return
    }
    let path: Path
    if outset {
        path = geometry.pathAndStyle?.path ?? Path(geometry)
    } else {
        let half = style.lineWidth.value / 2
        let inset = Bounds(origin: Point(x: Pixels(bounds.origin.x.value + half),
                                         y: Pixels(bounds.origin.y.value + half)),
                           size: Size(width: Pixels(max(0, bounds.size.width.value - 2 * half)),
                                      height: Pixels(max(0, bounds.size.height.value - 2 * half))))
        let g = shape.geometry(in: inset)
        path = g.pathAndStyle?.path ?? Path(g)
    }
    pass.drawPath(path, stroke: style, color: pass.theme[token])
}

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
