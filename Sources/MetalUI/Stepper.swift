import MetalUICore
import MetalUILayout
import MetalUIPlatform

/// SwiftUI's `Stepper` in its title-string forms (ruling `DD-X`; spec
/// `2026-09-26-controls-and-selection-design.md` §3–§5).
///
/// **Structure** (ST0): an internal legacy `Box` row — the title, 8 points,
/// then a 20×24 control: a column of two 20×12 halves, increment on top, on
/// `.surfaceSecondary` with corner radius 5 and a `.separator` hairline between
/// (the lower half's top border). Each half holds a glyph-free mark (a 7×1.5
/// bar, crossed by a 1.5×7 bar on the increment half). `textW + 28` ×
/// `max(textH, 24)`; the 8 stays with an empty title (28×24). No item field is
/// written on an internal node (`LR-AQ`): every height is declared. The title
/// numbers 0 under the stepper's id, the control 1, its halves 0 and 1 under it.
///
/// **A step** — a click on either half, a focused ↑/↓ (`DD-T`), an
/// accessibility increment/decrement — is `clamp(clamp(value) ± step)`,
/// clamped before (STA4: 5 on 0…3 shows and steps from 3) and after (STA3),
/// and **writes nothing when that equals the value** (STA1, STA2) — where a
/// `Slider` writes an unchanged value (SA2); both measured. With no range there
/// is no clamp (STA5). **The closure form** runs `onIncrement`/`onDecrement`;
/// a nil one makes its direction do nothing and its half no click target
/// (STA6).
///
/// **Accessibility**: the outer node is an `.incrementor` valued by the
/// clamped value (nil for the closure form), labelled by its title through the
/// partial fold (`DD-U`; divergence 82), with the two halves as unlabelled
/// `.button` children. Focusable; a click focuses nothing; a caller's `.onKey`
/// runs first, and a caller's declared role, value or adjustment handler wins.
public struct Stepper: Element, StyledElement {
    // Internal names for the body's parts. The public requirements below
    // spell the full types, so no name is added to the public API.
    typealias Mark = Box<EmptyGroup>
    typealias Plus = Stack<Pair<Mark, Mark>>
    typealias Up = Box<Plus>
    typealias Down = Box<Mark>
    typealias Control = Box<Pair<Up, Down>>
    typealias Body = Box<Pair<Text, Control>>

    public var style: Style
    public var decoration: Decoration = Decoration()
    public var elementID: ElementID?
    public var handlers: Handlers = Handlers()
    private let increment: (@MainActor () -> Void)?
    private let decrement: (@MainActor () -> Void)?
    private let valueText: (@MainActor () -> String)?
    private var box: Body

    /// A stepper over `bounds` (SwiftUI's `Stepper(_:value:in:step:)`).
    public init<V: Strideable>(_ title: String, value: Binding<V>, in bounds: ClosedRange<V>,
                               step: V.Stride = 1) {
        self.init(title, value: value, bounds: bounds, step: step)
    }

    /// An unbounded stepper (SwiftUI's `Stepper(_:value:step:)`): no clamp.
    public init<V: Strideable>(_ title: String, value: Binding<V>, step: V.Stride = 1) {
        self.init(title, value: value, bounds: nil, step: step)
    }

    /// A stepper that runs a closure per direction (SwiftUI's
    /// `Stepper(_:onIncrement:onDecrement:)`); a nil closure disables its
    /// direction. It publishes no value.
    public init(_ title: String, onIncrement: (@MainActor () -> Void)?,
                onDecrement: (@MainActor () -> Void)?) {
        self.init(title: title, increment: onIncrement, decrement: onDecrement, valueText: nil)
    }

    private init<V: Strideable>(_ title: String, value: Binding<V>, bounds: ClosedRange<V>?, step: V.Stride) {
        func stepper(_ direction: ControlKeys.Direction) -> @MainActor () -> Void {
            {
                if let next = ValueStepping.stepped(value.wrappedValue, in: bounds, step: step, direction) {
                    value.wrappedValue = next
                }
            }
        }
        self.init(title: title, increment: stepper(.forward), decrement: stepper(.backward),
                  valueText: {
                      let current = value.wrappedValue
                      return String(describing: bounds.map { ValueStepping.clamp(current, $0) } ?? current)
                  })
    }

    private init(title: String, increment: (@MainActor () -> Void)?, decrement: (@MainActor () -> Void)?,
                 valueText: (@MainActor () -> String)?) {
        var style = Style()
        style.flexDirection = .row
        style.alignItems = .center
        style.gap = Axes(both: .pixels(Pixels(8)))
        self.style = style
        self.increment = increment
        self.decrement = decrement
        self.valueText = valueText
        self.box = Body(style: style, content: Pair(Text(title), Self.control()))
    }

    private static func sized(_ width: Float, _ height: Float) -> Style {
        var style = Style()
        style.size = Size(width: .length(.pixels(Pixels(width))), height: .length(.pixels(Pixels(height))))
        return style
    }

    /// The 20×24 control: two 20×12 halves, each centring its mark.
    private static func control() -> Control {
        var half = sized(20, 12)
        half.flexDirection = .row
        half.alignItems = .center
        half.justifyContent = .center
        let ink = Decoration(background: .textPrimary)
        let plus = Plus(alignment: .center) {
            Mark(style: sized(7, 1.5), decoration: ink)
            Mark(style: sized(1.5, 7), decoration: ink)
        }
        let up = Up(style: half, content: plus)
        let down = Down(style: half,
                        decoration: Decoration(border: BorderStyle(.separator,
                                                                   widths: Edges(top: Pixels(1), right: Pixels(0),
                                                                                 bottom: Pixels(0), left: Pixels(0)))),
                        content: Mark(style: sized(7, 1.5), decoration: ink))
        var column = sized(20, 24)
        column.flexDirection = .column
        return Control(style: column,
                       decoration: Decoration(background: .surfaceSecondary, cornerRadius: Pixels(5)),
                       content: Pair(up, down))
    }

    public mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass)
        -> (LayoutNodeID, Box<Pair<Text, Box<Pair<Box<Stack<Pair<Box<EmptyGroup>, Box<EmptyGroup>>>>, Box<Box<EmptyGroup>>>>>>.Layout) {
        box.style = style
        box.decoration = decoration
        return box.requestLayout(id, pass: &pass)
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout Box<Pair<Text, Box<Pair<Box<Stack<Pair<Box<EmptyGroup>, Box<EmptyGroup>>>>, Box<Box<EmptyGroup>>>>>>.Layout,
                                  pass: inout PrepaintPass) -> Pair<Text, Box<Pair<Box<Stack<Pair<Box<EmptyGroup>, Box<EmptyGroup>>>>, Box<Box<EmptyGroup>>>>>.Prepaint {
        let increment = self.increment, decrement = self.decrement
        func run(_ direction: ControlKeys.Direction) {
            (direction == .forward ? increment : decrement)?()
        }
        box.content.second.content.first.handlers.onClick = increment
        box.content.second.content.second.handlers.onClick = decrement
        var composed = handlers
        composed.isFocusable = true
        let callerKey = handlers.onKey
        composed.onKey = { event in
            if let callerKey, callerKey(event) { return true }
            guard let direction = ControlKeys.stepperStep(event) else { return false }
            run(direction)
            return true
        }
        let adjustment = ObjectIdentifier(AccessibilityAdjustment.self)
        if composed.actions[adjustment] == nil {
            composed.actions[adjustment] = { action in
                // The key is `AccessibilityAdjustment`'s, so the cast holds by
                // construction (`Box.onAction`'s reasoning).
                run((action as! AccessibilityAdjustment).direction == .increment ? .forward : .backward)
            }
        }
        if composed.axNode.role == .generic { composed.axNode.role = .incrementor }
        if composed.axNode.value == nil { composed.axNode.value = valueText?() }
        box.handlers = composed
        return box.prepaint(id, bounds: bounds, layout: &layout, pass: &pass)
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout Box<Pair<Text, Box<Pair<Box<Stack<Pair<Box<EmptyGroup>, Box<EmptyGroup>>>>, Box<Box<EmptyGroup>>>>>>.Layout,
                               prepaint: inout Pair<Text, Box<Pair<Box<Stack<Pair<Box<EmptyGroup>, Box<EmptyGroup>>>>, Box<Box<EmptyGroup>>>>>.Prepaint,
                               pass: inout PaintPass) {
        box.paint(id, bounds: bounds, layout: &layout, prepaint: &prepaint, pass: &pass)
    }
}
