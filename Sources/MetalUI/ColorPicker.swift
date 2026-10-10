import MetalUICore
import MetalUILayout

/// SwiftUI's `ColorPicker(_:selection:supportsOpacity:)` over MetalUI's
/// ``Color`` (C10 lane 1, rulings `LK-C`, `LK-D`, `LK-P`; spec
/// `2026-10-08-controls-looks-design.md` §3.1).
///
/// **One node, `Toggle`'s shape** (`LK-P`): one `Box` — a row, gap 8, cross
/// axis centred — over the label and a **48×24 well** (probe `C0`, `V12`:
/// `79 = 23 + 8 + 48` for "Tint"), so it is one child of any container and
/// takes every `StyledElement` modifier. An empty title draws the well alone,
/// 48×24, no gap (`labelsHidden()`'s answer).
///
/// **The well** is a rounded bezel (radius 5, `.surface` fill, 1-point
/// `.separator` border) showing the selection inset 4 points (radius 3), with
/// a checkerboard behind its right half when the opacity is below 1. It is
/// focusable with the control focus ring; a press, Space or Return, or an
/// accessibility press opens the panel; a press does not focus (divergence
/// 94's rule).
///
/// **The panel** is a `.popover` from the well, **drawn on every platform**
/// (divergence 165: on macOS SwiftUI opens `NSColorPanel`, probe `C3`; the
/// native route is designed and deferred, `LK-C` item 6): a
/// saturation–brightness square, a hue bar, an opacity bar (only with
/// `supportsOpacity`), a swatch and a hex field (`LK-D`). Every move writes the
/// binding (`C4`); **every write is a gamma-sRGB literal**
/// `Color(.sRGB, red:green:blue:opacity:)` (`CR-`), with opacity 1 when
/// `supportsOpacity` is `false` (`C8`). A token, dynamic or palette selection
/// opens at its value resolved in this element's environment, and the first
/// edit replaces it with a literal (`C5`, `C6`).
///
/// **Accessibility** (`C1`): the label is its own text; the well is a
/// `.colorWell` with no label, its value `rgb R G B A` printed as AppKit
/// prints it (`rgb 1 0 0 1`), and a press action.
public struct ColorPicker<Label: ElementGroup>: Element, StyledElement {
    public var style: Style
    public var decoration: Decoration = Decoration()
    public var elementID: ElementID?
    public var handlers: Handlers = Handlers()
    let selection: Binding<Color>
    let supportsOpacity: Bool
    /// `nil` for an empty title: the well alone, no gap.
    let label: Label?
    /// Whether the panel is open — the well's popover binding.
    @State private var isPresented = false

    typealias BodyContent = Pair<OptionalGroup<Label>, PopoverModifier<ColorWell, ColorPickerPanel>>
    typealias Body = Box<BodyContent>

    /// A colour picker bound to `selection`, labelled by `label` — SwiftUI's
    /// `ColorPicker(selection:supportsOpacity:label:)` (`LK-P` item 2).
    /// Without `supportsOpacity` the panel has no opacity control and every
    /// write is opaque.
    public init(selection: Binding<Color>, supportsOpacity: Bool = true, @ElementBuilder label: () -> Label) {
        self.init(selection: selection, supportsOpacity: supportsOpacity, label: label())
    }

    init(selection: Binding<Color>, supportsOpacity: Bool, label: Label?) {
        var style = Style()
        style.flexDirection = .row
        style.alignItems = .center
        style.gap = Axes(both: .pixels(Pixels(label == nil ? 0 : ColorWell.gap)))
        self.style = style
        self.selection = selection
        self.supportsOpacity = supportsOpacity
        self.label = label
    }

    /// The box over the label and the popover-carrying well, built afresh per
    /// layout with this frame's resolved selection.
    private func body(environment: EnvironmentValues) -> Body {
        let resolved = selection.wrappedValue.resolve(in: environment)
        let seed = ColorMath.RGBA(red: Double(resolved.red), green: Double(resolved.green),
                                  blue: Double(resolved.blue), opacity: Double(resolved.opacity))
        let presented = $isPresented
        let selection = selection, supportsOpacity = supportsOpacity
        let well = ColorWell(color: selection.wrappedValue, axValue: ColorMath.axComponents(seed),
                             open: { presented.wrappedValue = true })
        var box = Body(style: style, content: Pair(OptionalGroup(label), well.popover(isPresented: presented) {
            ColorPickerPanel(selection: selection, supportsOpacity: supportsOpacity, seed: seed)
        }))
        box.decoration = decoration
        return box
    }

    /// What `requestLayout` hands the later phases: the box it built and laid
    /// out.
    public struct Layout {
        var body: Body
        var bodyLayout: Body.Layout
    }

    public mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Layout) {
        var body = body(environment: pass.frame.environmentTop)
        let (node, layout) = body.requestLayout(id, pass: &pass)
        return (node, Layout(body: body, bodyLayout: layout))
    }

    /// What `prepaint` hands `paint`: the box's own prepaint.
    public struct Prepaint {
        var body: BodyContent.GroupPrepaint
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout,
                                  pass: inout PrepaintPass) -> Prepaint {
        layout.body.handlers = handlers
        return Prepaint(body: layout.body.prepaint(id, bounds: bounds, layout: &layout.bodyLayout, pass: &pass))
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout,
                               prepaint: inout Prepaint, pass: inout PaintPass) {
        // The disabled look (`IX-G` item 2): the whole subtree in one 0.5 scope.
        pass.paintControl(disabled: !pass.frame.environmentTop.isEnabled) {
            layout.body.paint(id, bounds: bounds, layout: &layout.bodyLayout, prepaint: &prepaint.body, pass: &pass)
        }
    }
}

extension ColorPicker where Label == Text {
    /// A colour picker labelled by `titleKey` — SwiftUI's
    /// `ColorPicker(_:selection:supportsOpacity:)` (`LK-C` item 1). An empty
    /// title draws the well alone.
    public init(_ titleKey: String, selection: Binding<Color>, supportsOpacity: Bool = true) {
        self.init(selection: selection, supportsOpacity: supportsOpacity,
                  label: titleKey.isEmpty ? nil : Text(titleKey))
    }
}

/// A `ColorPicker`'s well (`LK-C` items 3, 7): a 48×24 leaf, `Slider`'s
/// shape — `registerAndScope` in `prepaint`, `paintDecoration` in `paint`.
struct ColorWell: Element, StyledElement {
    var style = Style()
    var decoration = Decoration()
    var elementID: ElementID?
    var handlers = Handlers()
    /// The selection, resolved at paint.
    let color: Color
    /// `rgb R G B A` (`C1`).
    let axValue: String
    /// Opens the panel, from input.
    let open: @MainActor () -> Void

    nonisolated static let width = 48.0
    nonisolated static let height = 24.0
    /// The label-to-well spacing (`C0`).
    nonisolated static let gap: Float = 8

    init(color: Color, axValue: String, open: @escaping @MainActor () -> Void) {
        self.color = color
        self.axValue = axValue
        self.open = open
    }

    struct Layout { var node: LayoutNodeID }

    mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Layout) {
        let node = pass.lowerLegacyLeaf(style, declared: style, site: .colorPicker) {
            pass.frame.requestNativeLeaf { _ in
                LayoutMeasurement(size: SizeD(width: Self.width, height: Self.height))
            }
        }
        return (node, Layout(node: node))
    }

    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout,
                           pass: inout PrepaintPass) {
        let open = self.open
        var composed = handlers
        if composed.onClick == nil { composed.onClick = open }
        composed.isFocusable = true
        let callerKey = handlers.onKey
        composed.onKey = { event in
            if let callerKey, callerKey(event) { return true }
            guard event.modifiers.isEmpty,
                  event.charactersIgnoringModifiers == ControlKeys.space
                    || event.charactersIgnoringModifiers == ControlKeys.returnKey else { return false }
            open()
            return true
        }
        composed.axNode.colorWellHint = true
        if composed.axNode.value == nil { composed.axNode.value = axValue }
        pass.registerAndScope(composed, decoration, at: bounds, for: id) { }
    }

    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout,
                        prepaint: inout Void, pass: inout PaintPass) {
        var decorated = decoration
        // The focus ring (`IX-H` item 2), unless the caller declared one.
        if decorated.focusBorder == nil { decorated.focusBorder = controlRing(pass.frame.environmentTop) }
        let color = color
        pass.paintDecoration(decorated, in: bounds, for: id) {
            pass.fill(bounds, color: pass.theme[.surface], cornerRadii: Corners(all: Pixels(5)),
                      borderColor: pass.theme[.separator], borderWidths: Edges(all: Pixels(1)))
            let inner = ColorPanelDrawing.inset(bounds, by: 4)
            let fill = pass.resolve(color)
            if fill.a < 1 {
                // The NSColorWell convention: a checkerboard behind the right half.
                let halfWidth = inner.size.width.value / 2
                let half = Bounds(origin: Point(x: Pixels(inner.origin.x.value + halfWidth), y: inner.origin.y),
                                  size: Size(width: Pixels(halfWidth), height: inner.size.height))
                pass.drawImage(ColorPanelImages.checker(columns: 5, rows: 4).texture, in: half, filter: .nearest)
            }
            pass.fill(inner, color: fill, cornerRadii: Corners(all: Pixels(3)))
        }
    }
}
