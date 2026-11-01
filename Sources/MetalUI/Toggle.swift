import MetalUICore
import MetalUILayout
import MetalUIPlatform

/// SwiftUI's `Toggle(isOn:)` in its macOS automatic style, the checkbox (ruling
/// `DD-S`; probe TG0 = TG1 `.checkbox`, 53×16 over a 32-point label).
///
/// **One look**: a 14×14 indicator `Box` (corner radius 3, `.accent` when on —
/// `.separator` when on outside the key window, `IX-H` item 1 —
/// `.surface` with a 1-point `.separator` border when off), 7 points, then the
/// label — `14 + 7 + textW` × `max(14, textH)`. Only the sum 21 is measured
/// (TG0: 53 − 32; the radio row's 21 agrees, PK2/PK3); the 14/7 split is
/// MetalUI's and moves no size. That is the `.checkbox` style, the macOS default;
/// `.toggleStyle(_:)` offers `.switch`, `.button` and the open ``ToggleStyle`` (`BY-H`).
///
/// **A click, a focused Space and an accessibility press each write `!isOn`
/// once** (TA0: `on set true`). Focusable, no click focus (`DD-T`); a caller's
/// `.onKey` runs first and a caller's `.onClick` replaces the write, as on
/// `Button`. Published as `.checkBox` with value `"1"`/`"0"`, labelled by its
/// label through the full fold (`DD-U` item 2); a caller's declared label or
/// value wins.
///
/// **The indicator is a `Box`**, so its fill animates under `withAnimation`
/// through `animatedBackground` with no new code, and a caller sees one
/// `$anim-color` slot under the indicator's id (positional 0 under the
/// toggle's); the label numbers from 1. The border appearing and vanishing
/// snaps (a paint-only `Decoration` field).
public struct Toggle<Label: ElementGroup>: Element, StyledElement {
    public var style: Style
    public var decoration: Decoration
    public var elementID: ElementID?
    public var handlers: Handlers = Handlers()
    var isOn: Binding<Bool>
    var box: Box<Pair<Box<EmptyGroup>, Label>>
    /// This toggle's own style (`.toggleStyle(_:)` directly on a `Toggle`), nearer than the environment's.
    var ownStyle: ResolvedToggleStyle?

    /// A checkbox bound to `isOn`, labelled by `label`; a click, Space when
    /// focused or an accessibility press flips it. SwiftUI's
    /// `Toggle(isOn:label:)` (`DD-S`).
    public init(isOn: Binding<Bool>, @ElementBuilder label: () -> Label) {
        var style = Style()
        style.flexDirection = .row
        style.alignItems = .center
        style.gap = Axes(both: .pixels(Pixels(7)))
        self.style = style
        self.decoration = Decoration()
        self.isOn = isOn
        self.box = Box(style: style, content: Pair(Box(), label()))
    }

    /// The switch's track and knob metrics (`BY-I`; MetalUI's, unmeasured).
    static var switchTrack: (width: Float, height: Float) { (38, 22) }
    static var switchKnob: Float { 18 }
    static var switchInset: Float { 2 }

    /// What `requestLayout` hands the later phases: a built-in look's box layout, or a custom style's erased body.
    public struct Layout {
        enum Inner {
            /// A built-in look, with the environment its label is drawn in (`.button` while on: white), if any.
            case builtIn(Box<Pair<Box<EmptyGroup>, Label>>.Layout, EnvironmentValues?, ToggleLook)
            /// A custom style's body: the erased element.
            case custom(AnyElement)
        }
        var inner: Inner
    }

    /// What `prepaint` hands `paint`.
    public struct PrepaintState {
        enum Inner {
            case builtIn(Pair<Box<EmptyGroup>, Label>.Prepaint)
            case custom
        }
        var inner: Inner
    }

    /// The handlers a toggle registers (`DD-S`): a click, Space, and the check box's accessibility role and value.
    func composedHandlers() -> Handlers {
        let binding = isOn
        let on = binding.wrappedValue
        var composed = handlers
        let toggle = composed.onClick ?? { binding.wrappedValue = !binding.wrappedValue }
        composed.onClick = toggle
        composed.isFocusable = true
        let callerKey = handlers.onKey
        composed.onKey = { event in
            if let callerKey, callerKey(event) { return true }
            guard ControlKeys.togglesToggle(event) else { return false }
            toggle()
            return true
        }
        if composed.axNode.role == .generic { composed.axNode.role = .checkBox }
        if composed.axNode.value == nil { composed.axNode.value = on ? "1" : "0" }
        return composed
    }

    public mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass)
        -> (LayoutNodeID, Layout) {
        let environment = pass.frame.environmentTop
        let resolved = ownStyle ?? environment.toggleStyle
        switch resolved.storage {
        case .look(let look):
            return requestBuiltInLayout(id, look: look, environment: environment, pass: &pass)
        case .custom(let custom):
            return requestCustomLayout(id, style: custom, environment: environment, pass: &pass)
        }
    }

    private mutating func requestBuiltInLayout(_ id: GlobalElementID, look: ToggleLook,
                                               environment: EnvironmentValues, pass: inout LayoutPass)
        -> (LayoutNodeID, Layout) {
        let on = isOn.wrappedValue
        var indicator = Style()
        var indicatorDecoration = Decoration()
        var rowStyle = style
        var decorated = decoration
        var labelEnvironment: EnvironmentValues?
        switch look {
        case .checkbox:
            indicator.size = Size(width: .length(.pixels(Pixels(14))), height: .length(.pixels(Pixels(14))))
            // The on indicator's accent only in the key window (`IX-H` item 1).
            indicatorDecoration = Decoration(background: on ? controlAccent(environment) : .surface,
                                             cornerRadius: Pixels(3),
                                             border: on ? nil : BorderStyle(.separator, width: Pixels(1)))
        case .switch:
            indicator.size = Size(width: .length(.pixels(Pixels(Self.switchTrack.width))),
                                  height: .length(.pixels(Pixels(Self.switchTrack.height))))
            indicator.flexShrink = 0
            indicatorDecoration = Decoration(background: on ? controlAccent(environment) : .surfaceSecondary,
                                             cornerRadius: Pixels(Self.switchTrack.height / 2),
                                             border: on ? nil : BorderStyle(.separator, width: Pixels(1)))
        case .button:
            // The bordered button's metrics (`DD-R` item 4): the strut is the indicator, no gap.
            let metrics = Button<Label>.metrics(environment.controlSize)
            rowStyle.padding.left = .pixels(Pixels(metrics.padding))
            rowStyle.padding.right = .pixels(Pixels(metrics.padding))
            rowStyle.gap = Axes(both: .pixels(Pixels(0)))
            rowStyle.justifyContent = .center
            indicator.size = Size(width: .length(.pixels(Pixels(0))), height: .length(.pixels(Pixels(metrics.height))))
            if decorated.background == nil { decorated.background = Color(on ? controlAccent(environment) : .surfaceSecondary) }
            if decorated.cornerRadius == Pixels(0) { decorated.cornerRadius = Pixels(5) }
            if decorated.border == nil && !on { decorated.border = BorderStyle(.separator, width: Pixels(1)) }
            if on {
                var values = pass.frame.environmentSnapshot()
                values.foregroundStyle = .white
                labelEnvironment = values
            }
        }
        box.style = rowStyle
        box.decoration = decorated
        // The focus ring (`IX-H` item 2), unless the caller declared one.
        if box.decoration.focusBorder == nil { box.decoration.focusBorder = controlRing(environment) }
        box.content.first = Box(style: indicator, decoration: indicatorDecoration)
        let (node, layout) = Button<Label>.enteringLabel(labelEnvironment, pass.frame) {
            box.requestLayout(id, pass: &pass)
        }
        return (node, Layout(inner: .builtIn(layout, labelEnvironment, look)))
    }

    private mutating func requestCustomLayout<S: ToggleStyle>(_ id: GlobalElementID, style custom: S,
                                                             environment: EnvironmentValues,
                                                             pass: inout LayoutPass) -> (LayoutNodeID, Layout) {
        StateBinder.bind(custom, in: pass.frame, id: id)   // `@State`/`@Environment` on the style struct (`BY-K`)
        let configuration = ToggleStyleConfiguration(label: StyleLabel(box.content.second), isOn: isOn)
        var decorated = decoration
        if decorated.focusBorder == nil { decorated.focusBorder = controlRing(environment) }
        var rowStyle = style
        rowStyle.gap = Axes(both: .pixels(Pixels(0)))
        var outer = Box(style: rowStyle, decoration: decorated, content: custom.makeBody(configuration: configuration))
        outer.handlers = composedHandlers()
        var element = AnyElement(outer)
        let node = element.requestLayout(id, pass: &pass)
        return (node, Layout(inner: .custom(element)))
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout Layout, pass: inout PrepaintPass) -> PrepaintState {
        switch layout.inner {
        case .builtIn(var builtIn, let labelEnvironment, let look):
            box.handlers = composedHandlers()
            let result = Button<Label>.enteringLabel(labelEnvironment, pass.frame) {
                box.prepaint(id, bounds: bounds, layout: &builtIn, pass: &pass)
            }
            layout.inner = .builtIn(builtIn, labelEnvironment, look)
            return PrepaintState(inner: .builtIn(result))
        case .custom(var element):
            element.prepaint(id, bounds: bounds, pass: &pass)
            layout.inner = .custom(element)
            return PrepaintState(inner: .custom)
        }
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout Layout, prepaint: inout PrepaintState,
                               pass: inout PaintPass) {
        // The disabled look (`IX-G` item 2): the whole subtree in one 0.5 scope.
        switch layout.inner {
        case .builtIn(var builtIn, let labelEnvironment, let look):
            guard case .builtIn(var builtInPrepaint) = prepaint.inner else { return }
            let on = isOn.wrappedValue
            pass.paintControl(disabled: !pass.frame.environmentTop.isEnabled) {
                Button<Label>.enteringLabel(labelEnvironment, pass.frame) {
                    box.paint(id, bounds: bounds, layout: &builtIn, prepaint: &builtInPrepaint, pass: &pass)
                }
                if look == .switch { paintKnob(bounds: bounds, on: on, pass: &pass) }
            }
            layout.inner = .builtIn(builtIn, labelEnvironment, look)
        case .custom(var element):
            pass.paintControl(disabled: !pass.frame.environmentTop.isEnabled) {
                element.paint(id, bounds: bounds, pass: &pass)
            }
            layout.inner = .custom(element)
        }
    }

    /// The switch's knob (`BY-I`): a white circle inset 2 in the track, at the leading end off and the trailing end
    /// on. The track is the row's first child, vertically centred, so its origin is computed from the row's bounds;
    /// the knob does not slide (divergence 885).
    private func paintKnob(bounds: Bounds<Pixels>, on: Bool, pass: inout PaintPass) {
        let track = Self.switchTrack
        let knob = Self.switchKnob, inset = Self.switchInset
        let trackY = bounds.origin.y.value + (bounds.size.height.value - track.height) / 2
        let x = bounds.origin.x.value + (on ? track.width - knob - inset : inset)
        let rect = Bounds(origin: Point(x: Pixels(x), y: Pixels(trackY + inset)),
                          size: Size(width: Pixels(knob), height: Pixels(knob)))
        pass.fill(rect, color: Hsla(h: 0, s: 0, l: 1, a: 1), cornerRadii: Corners(all: Pixels(knob / 2)))
    }
}

extension Toggle {
    /// This toggle drawn in `style` — SwiftUI's `.toggleStyle(_:)` (`BY-H`). The nearest writer: it outranks a style
    /// inherited through the environment.
    public func toggleStyle<S: ToggleStyle>(_ style: S) -> Self {
        var copy = self
        copy.ownStyle = ResolvedToggleStyle(style)
        return copy
    }
}

extension Toggle where Label == Text {
    /// A toggle labelled by `title` (SwiftUI's `Toggle(_:isOn:)`).
    public init(_ title: String, isOn: Binding<Bool>) {
        self.init(isOn: isOn) { Text(title) }
    }
}
