import MetalUICore
import MetalUILayout

// Shape styles (round 3 item R3-9, rulings `SS-A`…): SwiftUI's `ShapeStyle` as a protocol, its type
// eraser, the tint, and the generic `fill`/`stroke`/`foregroundStyle`/`background` overloads that take
// `some ShapeStyle` beside the concrete `Color`/gradient/`Material` ones.

/// A colour, gradient, material or other fill that can paint a shape, a background or text —
/// SwiftUI's `ShapeStyle` (ruling `SS-A`).
///
/// **`Color`, ``LinearGradient``, ``RadialGradient``, ``Material`` and ``TintShapeStyle`` conform**, as does
/// ``AnyShapeStyle``. Every colour-taking modifier keeps its concrete `Color`, gradient and `Material`
/// overloads and gains one `some ShapeStyle` overload beside them, so an existing call site binds as it did.
///
/// **A third party uses every style generically and may conform by composition**, as in SwiftUI:
/// ``resolve(in:)`` returns another style (`Color`, a gradient, a material, another custom style), which
/// MetalUI resolves in turn against the environment at paint (`SS-B`).
///
/// ```swift
/// struct Brand: ShapeStyle {
///     func resolve(in environment: EnvironmentValues) -> some ShapeStyle {
///         environment.colorScheme == .dark ? Color.white : Color.black
///     }
/// }
/// ```
///
/// A style that resolves to a colour paints text and the built-in controls as that colour; a gradient or
/// material used as a foreground style paints its first stop's colour or its flat tint (divergence 975).
public protocol ShapeStyle: Sendable {
    /// What this style resolves to: another style, ending in ``ResolvedShapeStyle`` or ``Color/Resolved``.
    associatedtype Resolved: ShapeStyle

    /// This style resolved in `environment`: the colour scheme, theme and tint it is painted in.
    func resolve(in environment: EnvironmentValues) -> Resolved
}

// MARK: - The resolved form (internal)

/// The closed set a style resolves to (`SS-A` item 2): the colour, gradient and material paint paths
/// MetalUI already has. A `Color` stays a `Color` — token, dynamic and tint providers resolve at paint
/// against the position's theme, scheme and tint — so the existing colour sites keep their fast path.
enum ShapeStyleStorage: Hashable, Sendable {
    case color(Color)
    case gradient(GradientFill)
    case material(Material)

    /// The colour a text, a control accent or a stroke-of-a-material takes from this style (`SS-C` item 3):
    /// a colour as it is, a gradient its first stop, a material its flat tint.
    var representativeColor: Color {
        switch self {
        case let .color(c): c
        case let .gradient(g): g.gradient.stops.first?.color ?? .clear
        case let .material(m): m.color
        }
    }
}

/// A style whose resolved form needs no environment: the built-ins (`SS-A` item 2).
protocol PrimitiveShapeStyle {
    var storage: ShapeStyleStorage { get }
}

/// `style` resolved to its primitive form in `environment`, following `resolve(in:)` through compositions.
/// A cycle (a style resolving to itself) traps after 32 steps.
func shapeStyleStorage<S: ShapeStyle>(_ style: S, in environment: EnvironmentValues) -> ShapeStyleStorage {
    var current: any ShapeStyle = style
    for _ in 0..<32 {
        if let primitive = current as? any PrimitiveShapeStyle { return primitive.storage }
        if let erased = current as? AnyShapeStyle { return erased.storage(in: environment) }
        current = current.resolve(in: environment)
    }
    preconditionFailure("ShapeStyle.resolve(in:) did not reach a Color, gradient or Material after 32 steps (SS-B)")
}

/// A style resolved against an environment — SwiftUI's resolved shape style, opaque (`SS-A`): the terminal
/// every ``ShapeStyle`` resolves to. It carries no public members; paint it by passing it where a
/// `some ShapeStyle` is taken.
public struct ResolvedShapeStyle: ShapeStyle, Hashable, Sendable, PrimitiveShapeStyle {
    let storage: ShapeStyleStorage

    init(_ storage: ShapeStyleStorage) { self.storage = storage }

    /// A resolved style is its own resolution.
    public func resolve(in environment: EnvironmentValues) -> ResolvedShapeStyle { self }
}

// MARK: - Conformances

extension Color: ShapeStyle, PrimitiveShapeStyle {
    var storage: ShapeStyleStorage { .color(self) }
}

extension Color.Resolved: ShapeStyle, PrimitiveShapeStyle {
    var storage: ShapeStyleStorage {
        .color(Color(srgb: red, green, blue, opacity))
    }

    /// A resolved colour is a literal.
    public func resolve(in environment: EnvironmentValues) -> ResolvedShapeStyle {
        ResolvedShapeStyle(storage)
    }
}

extension LinearGradient: ShapeStyle, PrimitiveShapeStyle {
    var storage: ShapeStyleStorage { .gradient(.linear(self)) }

    /// A gradient resolves to itself; its stops' colours resolve at paint.
    public func resolve(in environment: EnvironmentValues) -> ResolvedShapeStyle {
        ResolvedShapeStyle(storage)
    }
}

extension RadialGradient: ShapeStyle, PrimitiveShapeStyle {
    var storage: ShapeStyleStorage { .gradient(.radial(self)) }

    /// A gradient resolves to itself; its stops' colours resolve at paint.
    public func resolve(in environment: EnvironmentValues) -> ResolvedShapeStyle {
        ResolvedShapeStyle(storage)
    }
}

extension Material: ShapeStyle, PrimitiveShapeStyle {
    var storage: ShapeStyleStorage { .material(self) }

    /// A material resolves to itself; its blur and tint are drawn at paint.
    public func resolve(in environment: EnvironmentValues) -> ResolvedShapeStyle {
        ResolvedShapeStyle(storage)
    }
}

// Colour's own `resolve(in:)` returns ``Color/Resolved`` (CR-H item 4); that is the witness.

// MARK: - The tint (SS-D)

/// The tint a `.tint(_:)` above wrote, as a style — SwiftUI's `TintShapeStyle` (ruling `SS-D`): `fill(.tint)`,
/// `foregroundStyle(.tint)`. It resolves to ``Color/accentColor``: the nearest `.tint(_:)`, else the theme's
/// accent.
public struct TintShapeStyle: ShapeStyle, Hashable, Sendable, PrimitiveShapeStyle {
    /// A tint style.
    public init() {}

    var storage: ShapeStyleStorage { .color(.accentColor) }

    /// The accent colour in `environment`.
    public func resolve(in environment: EnvironmentValues) -> ResolvedShapeStyle {
        ResolvedShapeStyle(storage)
    }
}

extension ShapeStyle where Self == TintShapeStyle {
    /// The tint style: the nearest `.tint(_:)`, else the theme's accent.
    public static var tint: TintShapeStyle { TintShapeStyle() }
}

// MARK: - AnyShapeStyle (SS-E)

/// A type-erased ``ShapeStyle`` — SwiftUI's `AnyShapeStyle` (ruling `SS-E`). Wrapping a built-in style keeps its
/// paint path (a wrapped `Color` paints as that `Color`); wrapping a custom style keeps it until paint, where it
/// resolves against the environment. Two erased styles are equal when they wrap equal built-ins, or the same
/// custom value type that is itself `Equatable` and equal; any other custom style equals nothing, so a
/// retained subtree holding one repaints (never a stale hit).
public struct AnyShapeStyle: ShapeStyle, Equatable, @unchecked Sendable {
    enum Form {
        case primitive(ShapeStyleStorage)
        case custom(CustomBox)
    }

    final class CustomBox: @unchecked Sendable {
        let style: any ShapeStyle
        let equals: (Any) -> Bool

        init(_ style: any ShapeStyle) {
            self.style = style
            if let comparable = style as? any Equatable {
                equals = { other in shapeStyleValuesEqual(comparable, other) }
            } else {
                equals = { _ in false }
            }
        }
    }

    let form: Form

    /// Erases `style`.
    public init<S: ShapeStyle>(_ style: S) {
        if let erased = style as? AnyShapeStyle {
            form = erased.form
        } else if let primitive = style as? any PrimitiveShapeStyle {
            form = .primitive(primitive.storage)
        } else {
            form = .custom(CustomBox(style))
        }
    }

    init(storage: ShapeStyleStorage) { form = .primitive(storage) }

    /// The erased style resolved in `environment`: a wrapped custom style resolves through its own
    /// `resolve(in:)`.
    public func resolve(in environment: EnvironmentValues) -> ResolvedShapeStyle {
        ResolvedShapeStyle(storage(in: environment))
    }

    func storage(in environment: EnvironmentValues) -> ShapeStyleStorage {
        switch form {
        case let .primitive(storage): storage
        case let .custom(box): shapeStyleStorage(box.style, in: environment)
        }
    }

    /// The primitive form when it needs no environment, `nil` for a custom style.
    var primitiveStorage: ShapeStyleStorage? {
        if case let .primitive(storage) = form { return storage }
        return nil
    }

    public static func == (lhs: AnyShapeStyle, rhs: AnyShapeStyle) -> Bool {
        switch (lhs.form, rhs.form) {
        case let (.primitive(a), .primitive(b)): a == b
        case let (.custom(a), .custom(b)): a === b || a.equals(b.style)
        default: false
        }
    }
}

private func shapeStyleValuesEqual<T: Equatable>(_ lhs: T, _ rhs: Any) -> Bool {
    guard let rhs = rhs as? T else { return false }
    return lhs == rhs
}

// MARK: - Lowering for builder-time sinks (SS-C item 2)

extension ShapeStyle {
    /// The primitive form for a sink that stores a fill before any environment exists (`Box.background`,
    /// a layout modifier). A custom composition resolves in a bare `EnvironmentValues()` there (divergence 976).
    func builderStorage() -> ShapeStyleStorage {
        if let primitive = self as? any PrimitiveShapeStyle { return primitive.storage }
        if let erased = self as? AnyShapeStyle, let storage = erased.primitiveStorage { return storage }
        return shapeStyleStorage(self, in: EnvironmentValues())
    }
}

// MARK: - Shape sites (SS-C)

extension Shape {
    /// Fills the shape with `style` — SwiftUI's `fill(_:)` over any ``ShapeStyle`` (`SS-C`). A `Color`, a
    /// gradient or a `Material` binds to its own overload and paints as before; this one is for ``AnyShapeStyle``,
    /// ``TintShapeStyle`` and custom compositions, resolved against the environment at paint.
    public func fill<S: ShapeStyle>(_ style: S) -> ShapeView<Self> {
        ShapeView(shape: self, layers: [.styleFill(AnyShapeStyle(style), nil)])
    }

    /// Fills the shape with `style` under `fillStyle` (`SS-C`).
    public func fill<S: ShapeStyle>(_ style: S, style fillStyle: FillStyle) -> ShapeView<Self> {
        ShapeView(shape: self, layers: [.styleFill(AnyShapeStyle(style), fillStyle)])
    }

    /// Strokes the shape's outline with `style`, centred on its edge (`SS-C`).
    public func stroke<S: ShapeStyle>(_ style: S, lineWidth: Pixels = Pixels(1)) -> ShapeView<Self> {
        ShapeView(shape: self, layers: [.styleStroke(AnyShapeStyle(style), StrokeStyle(lineWidth: lineWidth))])
    }

    /// Strokes the shape's outline with `style` under `strokeStyle` (`SS-C`).
    public func stroke<S: ShapeStyle>(_ style: S, style strokeStyle: StrokeStyle) -> ShapeView<Self> {
        ShapeView(shape: self, layers: [.styleStroke(AnyShapeStyle(style), strokeStyle)])
    }

    /// Strokes inside the shape's edge with `style` (`SS-C`).
    public func strokeBorder<S: ShapeStyle>(_ style: S, lineWidth: Pixels = Pixels(1)) -> ShapeView<Self> {
        ShapeView(shape: self, layers: [.styleStrokeBorder(AnyShapeStyle(style), StrokeStyle(lineWidth: lineWidth))])
    }

    /// Strokes inside the shape's edge with `style` under `strokeStyle` (`SS-C`).
    public func strokeBorder<S: ShapeStyle>(_ style: S, style strokeStyle: StrokeStyle) -> ShapeView<Self> {
        ShapeView(shape: self, layers: [.styleStrokeBorder(AnyShapeStyle(style), strokeStyle)])
    }
}

extension ShapeView {
    /// Adds a fill by `style` over the layers so far (`SS-C`).
    public func fill<T: ShapeStyle>(_ style: T) -> ShapeView<S> {
        ShapeView(shape: shape, layers: layers + [.styleFill(AnyShapeStyle(style), nil)])
    }

    /// Adds a fill by `style` under `fillStyle` over the layers so far (`SS-C`).
    public func fill<T: ShapeStyle>(_ style: T, style fillStyle: FillStyle) -> ShapeView<S> {
        ShapeView(shape: shape, layers: layers + [.styleFill(AnyShapeStyle(style), fillStyle)])
    }

    /// Adds a centred stroke by `style` over the layers so far (`SS-C`).
    public func stroke<T: ShapeStyle>(_ style: T, lineWidth: Pixels = Pixels(1)) -> ShapeView<S> {
        ShapeView(shape: shape, layers: layers + [.styleStroke(AnyShapeStyle(style), StrokeStyle(lineWidth: lineWidth))])
    }

    /// Adds a centred stroke by `style` under `strokeStyle` over the layers so far (`SS-C`).
    public func stroke<T: ShapeStyle>(_ style: T, style strokeStyle: StrokeStyle) -> ShapeView<S> {
        ShapeView(shape: shape, layers: layers + [.styleStroke(AnyShapeStyle(style), strokeStyle)])
    }

    /// Adds an inside stroke by `style` over the layers so far (`SS-C`).
    public func strokeBorder<T: ShapeStyle>(_ style: T, lineWidth: Pixels = Pixels(1)) -> ShapeView<S> {
        ShapeView(shape: shape, layers: layers + [.styleStrokeBorder(AnyShapeStyle(style), StrokeStyle(lineWidth: lineWidth))])
    }

    /// Adds an inside stroke by `style` under `strokeStyle` over the layers so far (`SS-C`).
    public func strokeBorder<T: ShapeStyle>(_ style: T, style strokeStyle: StrokeStyle) -> ShapeView<S> {
        ShapeView(shape: shape, layers: layers + [.styleStrokeBorder(AnyShapeStyle(style), strokeStyle)])
    }
}

/// One fill layer by an erased style: resolved at the position's environment, then the colour, gradient or
/// material path the concrete overloads use (`SS-C` item 1).
@MainActor
func paintStyleFill(_ erased: AnyShapeStyle, _ geometry: ShapeGeometry, style: FillStyle?, pass: PaintPass) {
    switch erased.storage(in: pass.frame.environmentTop) {
    case let .color(color): paintShapeFill(geometry, color: color, style: style, pass: pass)
    case let .gradient(fill): paintGradientFill(fill, geometry, style: style, pass: pass)
    case let .material(material): paintShapeMaterial(geometry, material: material, style: style, pass: pass)
    }
}

/// One stroke layer by an erased style. A material strokes in its flat tint (divergence 975).
@MainActor
func paintStyleStroke<S: Shape>(_ erased: AnyShapeStyle, _ shape: S, _ geometry: ShapeGeometry,
                                bounds: Bounds<Pixels>, style: StrokeStyle, outset: Bool, pass: PaintPass) {
    switch erased.storage(in: pass.frame.environmentTop) {
    case let .color(color):
        paintStyledStroke(shape, geometry, bounds: bounds, color: color, style: style, outset: outset, pass: pass)
    case let .material(material):
        paintStyledStroke(shape, geometry, bounds: bounds,
                          color: ShapeStyleStorage.material(material).representativeColor, style: style,
                          outset: outset, pass: pass)
    case let .gradient(fill):
        guard style.lineWidth.value > 0 else { return }
        if outset {
            paintGradientStroke(fill, geometry, style: style, pass: pass)
        } else {
            let half = style.lineWidth.value / 2
            let inset = Bounds(origin: Point(x: Pixels(bounds.origin.x.value + half),
                                             y: Pixels(bounds.origin.y.value + half)),
                               size: Size(width: Pixels(max(0, bounds.size.width.value - 2 * half)),
                                          height: Pixels(max(0, bounds.size.height.value - 2 * half))))
            paintGradientStroke(fill, shape.geometry(in: inset), style: style, pass: pass)
        }
    }
}

// MARK: - Background, border (SS-C)

extension StyledElement {
    /// Fills this element's border box with `style` — SwiftUI's `background(_:)` over any ``ShapeStyle``
    /// (`SS-C`). A `Color`, gradient or `Material` binds to its own overload; this is for ``AnyShapeStyle``,
    /// ``TintShapeStyle`` and compositions. **A box stores its fill before any environment exists**, so a
    /// custom composition resolves in a bare environment here (divergence 976); `.tint` and a `Color` follow the
    /// environment at paint as ever.
    public func background<S: ShapeStyle>(_ style: S) -> Self {
        switch style.builderStorage() {
        case let .color(color): background(color)
        case let .gradient(.linear(gradient)): background(gradient)
        case let .gradient(.radial(gradient)): background(gradient)
        case let .material(material): background(material)
        }
    }

    /// Draws a border of `style` around this element — SwiftUI's `border(_:width:)` (`SS-C`). A border is one
    /// colour: a gradient borders in its first stop and a material in its flat tint (divergence 975).
    public func border<S: ShapeStyle>(_ style: S, width: Pixels) -> Self {
        border(style.builderStorage().representativeColor, width: width)
    }
}

extension ProposalElementGroup {
    /// Places `style`, filling this view's bounds, behind it — SwiftUI's `background(_:)` over any
    /// ``ShapeStyle`` (`SS-C`): `background(style, in: Rectangle())`.
    public func background<S: ShapeStyle>(_ style: S) -> BackgroundModifier<Self, ShapeView<Rectangle>> {
        BackgroundModifier(content: self) { Rectangle().fill(style) }
    }

    /// Draws a border of `style` over this subtree without changing its layout (`SS-C`). A border is one
    /// colour: a gradient borders in its first stop and a material in its flat tint (divergence 975).
    public func border<S: ShapeStyle>(_ style: S, width: Pixels,
                                      cornerRadius: Pixels = Pixels(0)) -> ModifiedContent<ProposalBase, LayoutModifier> {
        border(style.builderStorage().representativeColor, width: width, cornerRadius: cornerRadius)
    }
}

extension ElementGroup {
    /// Places `shape`, filled with `style`, behind this view — SwiftUI's `background(_:in:)` over any
    /// ``ShapeStyle`` (`SS-C`).
    public func background<S: ShapeStyle, T: Shape>(_ style: S, in shape: T)
        -> BackgroundModifier<Self, ShapeView<T>> {
        BackgroundModifier(content: self) { shape.fill(style) }
    }
}

// MARK: - foregroundStyle, tint (SS-C, SS-D)

extension ElementGroup {
    /// The glyph colour of every text below that names none, and the default fill of every shape below —
    /// SwiftUI's `foregroundStyle(_:)` over any ``ShapeStyle`` (`SS-C`). The style resolves against the
    /// environment at this scope; a gradient or material, which text cannot paint, takes its first stop's
    /// colour or flat tint (divergence 975). `foregroundStyle(.tint)` follows `.tint(_:)`.
    public func foregroundStyle<S: ShapeStyle>(_ style: S) -> EnvironmentScope<Self> {
        EnvironmentScope(content: self, write: .transform {
            $0.foregroundStyle = shapeStyleStorage(style, in: $0).representativeColor
        })
    }

    /// Tints the controls and the accent colour below — SwiftUI's `tint(_:)` (`SS-D`). The built-in controls'
    /// accent (`.borderedProminent`, a switch or checkbox, a slider's track, a progress bar and ring, a radio
    /// `Picker`'s selection, a list's selected row, a focus ring) and ``Color/accentColor`` read it; `nil`
    /// removes an outer tint. The nearest writer wins.
    public func tint(_ color: Color?) -> EnvironmentScope<Self> {
        environment(\.tint, color)
    }

    /// Tints with any ``ShapeStyle`` (`SS-D`): a gradient or material tints in its first stop's colour or
    /// flat tint (divergence 975). `nil` removes an outer tint.
    public func tint<S: ShapeStyle>(_ style: S?) -> EnvironmentScope<Self> {
        EnvironmentScope(content: self, write: .transform { values in
            values.tint = style.map { shapeStyleStorage($0, in: values).representativeColor }
        })
    }

    /// SwiftUI's deprecated `accentColor(_:)`: the same as ``tint(_:)`` (`SS-D`).
    @available(*, deprecated, renamed: "tint")
    public func accentColor(_ color: Color?) -> EnvironmentScope<Self> {
        environment(\.tint, color)
    }
}

extension Text {
    /// This text's own glyph colour by any ``ShapeStyle`` (`SS-C`). A text stores its colour before any
    /// environment exists, so a custom composition resolves in a bare environment (divergence 976); a gradient
    /// takes its first stop's colour (divergence 975).
    public func foregroundStyle<S: ShapeStyle>(_ style: S) -> Text {
        foregroundStyle(style.builderStorage().representativeColor)
    }
}

extension ProposalText {
    /// This text's own glyph colour by any ``ShapeStyle`` (`SS-C`); see ``Text/foregroundStyle(_:)``.
    public func foregroundStyle<S: ShapeStyle>(_ style: S) -> ProposalText {
        foregroundStyle(style.builderStorage().representativeColor)
    }
}
