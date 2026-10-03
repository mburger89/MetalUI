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
/// MetalUI's and moves no size. `.switch`, `.button` and `ToggleStyle` are not
/// offered (`DD-AB` item 7).
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

    public mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass)
        -> (LayoutNodeID, Box<Pair<Box<EmptyGroup>, Label>>.Layout) {
        let on = isOn.wrappedValue
        let environment = pass.frame.environmentTop
        var indicator = Style()
        indicator.size = Size(width: .length(.pixels(Pixels(14))), height: .length(.pixels(Pixels(14))))
        box.style = style
        box.decoration = decoration
        // The focus ring (`IX-H` item 2), unless the caller declared one.
        if box.decoration.focusBorder == nil { box.decoration.focusBorder = controlRing(environment) }
        // The on indicator's accent only in the key window (`IX-H` item 1).
        box.content.first = Box(style: indicator,
                                decoration: Decoration(background: on ? controlAccent(environment) : .surface,
                                                       cornerRadius: Pixels(3),
                                                       border: on ? nil : BorderStyle(.separator, width: Pixels(1))))
        return box.requestLayout(id, pass: &pass)
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout Box<Pair<Box<EmptyGroup>, Label>>.Layout,
                                  pass: inout PrepaintPass) -> Pair<Box<EmptyGroup>, Label>.Prepaint {
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
        box.handlers = composed
        return box.prepaint(id, bounds: bounds, layout: &layout, pass: &pass)
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout Box<Pair<Box<EmptyGroup>, Label>>.Layout,
                               prepaint: inout Pair<Box<EmptyGroup>, Label>.Prepaint,
                               pass: inout PaintPass) {
        // The disabled look (`IX-G` item 2): the whole subtree in one 0.5 scope.
        pass.paintControl(disabled: !pass.frame.environmentTop.isEnabled) {
            box.paint(id, bounds: bounds, layout: &layout, prepaint: &prepaint, pass: &pass)
        }
    }
}

extension Toggle where Label == Text {
    /// A toggle labelled by `title` (SwiftUI's `Toggle(_:isOn:)`).
    public init(_ title: String, isOn: Binding<Bool>) {
        self.init(isOn: isOn) { Text(title) }
    }
}
