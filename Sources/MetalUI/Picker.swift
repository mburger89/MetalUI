import MetalUICore
import MetalUILayout
import MetalUIPlatform

/// A `Picker`'s look — SwiftUI's call-site spelling, `.pickerStyle(.segmented)`,
/// over a **closed** set (ruling `DD-V` item 4). A struct with static members,
/// so turning it into SwiftUI's protocol later keeps every call site compiling.
///
/// **`.automatic` is segmented, and `.menu` is not offered** — divergence 81:
/// SwiftUI's automatic picker on macOS is a pop-up menu (PK0 = PK1 `.menu`;
/// PA0 `AXPopUpButton`), a presentation with its own keyboard and dismiss
/// rules, plan task 12's (`DD-AB` item 7). `.inline` is not offered either.
/// Pinned by `aMenuPickerStyleIsNotOffered`.
public struct PickerStyle: Sendable, Hashable {
    enum Kind: Sendable, Hashable { case segmented, radioGroup }
    let kind: Kind

    /// Segmented (divergence 81: SwiftUI's is a pop-up menu).
    public static let automatic = PickerStyle(kind: .segmented)
    /// Every segment as wide as the widest (PA1), in a recessed capsule.
    public static let segmented = PickerStyle(kind: .segmented)
    /// A leading-aligned column of radio rows, 6 apart (PK1, PK3).
    public static let radioGroup = PickerStyle(kind: .radioGroup)
}

/// SwiftUI's `Picker(_:selection:content:)` (ruling `DD-V`): a title and a set
/// of options, each an element marked with `.tag(_:)`; selecting an option
/// writes its tag to `selection`.
///
/// **Options are found through a picker scope, not by walking the content**
/// (`DD-V` item 2; an `ElementGroup` cannot be introspected): `Picker` pushes an
/// internal `PickerScope` around its content's layout, and each `TaggedElement`
/// inside reads the innermost, appends its tag (so the picker knows the order
/// for its arrows) and builds its option chrome. **Selection is by value
/// equality** of the tag with the binding's value, typed: a tag of another
/// type selects nothing. A press writes the option's tag (PA1, PA2); a
/// selection matching no tag selects nothing and writes nothing (PA3).
///
/// **Layout** (`DD-V` item 5): the title, 8, the options. Segmented: every
/// segment as wide as the widest (`textW + 24` before equalising, PA1, PK2),
/// 24 tall by strut, in a `.surfaceSecondary` capsule; `n·w` wide where
/// SwiftUI's is `n·w + 1` (PK1, PK3; divergence 81). Radio group: a
/// leading-aligned column 6 apart (PK3; PK1 reads 6.5, divergence 81), each row
/// a 14-point circle, 7, the label — `textW + 21` (PK2/PK3).
///
/// **Keys** (`DD-T`): focusable; ←/↑ select the previous option and →/↓ the
/// next, **without wrapping** — a caller's `.onKey` first, as on `Button`.
/// **Accessibility** (`DD-U`): the picker is a `.radioGroup` labelled by its
/// title through the partial fold (divergence 82: SwiftUI publishes the title
/// as a sibling static text), each option a `.radioButton` labelled by its
/// content, value `"1"` and the `.selected` trait on the chosen one.
///
/// **Structure.** An internal legacy `Box` row: `Text(title)` at 0, then the
/// options `Box` at 1, whose content is an `OptionRow` group over the caller's
/// content — each option's chrome `Box` numbering from 0 under the options
/// `Box`, its strut or circle at 0 and the content at 1 under it.
public struct Picker<SelectionValue: Hashable, Content: ElementGroup>: Element, StyledElement {
    public var style: Style
    public var decoration: Decoration
    public var elementID: ElementID?
    public var handlers: Handlers = Handlers()
    private var selection: Binding<SelectionValue>
    private var pickerStyle: PickerStyle = .automatic
    private var scope: PickerScope
    private var box: Box<Pair<Text, Box<OptionRow<Content>>>>

    public struct Layout {
        var inner: Box<Pair<Text, Box<OptionRow<Content>>>>.Layout
    }

    public struct PrepaintState {
        var inner: Pair<Text, Box<OptionRow<Content>>>.Prepaint
    }

    public init(_ title: String, selection: Binding<SelectionValue>,
                @ElementBuilder content: () -> Content) {
        var style = Style()
        style.flexDirection = .row
        style.alignItems = .center
        style.gap = Axes(both: .pixels(Pixels(8)))
        self.style = style
        self.decoration = Decoration()
        self.selection = selection
        self.scope = PickerScope(
            matches: { tag in (tag.base as? SelectionValue).map { $0 == selection.wrappedValue } ?? false },
            write: { tag in if let value = tag.base as? SelectionValue { selection.wrappedValue = value } })
        self.box = Box(style: style, content: Pair(Text(title), Box(content: OptionRow(content: content(),
                                                                                      equalWidth: true))))
    }

    /// This picker in `style` (SwiftUI's `.pickerStyle(_:)`).
    public func pickerStyle(_ style: PickerStyle) -> Picker {
        var copy = self
        copy.pickerStyle = style
        return copy
    }

    public mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Layout) {
        var options = Style()
        options.flexDirection = pickerStyle.kind == .segmented ? .row : .column
        switch pickerStyle.kind {
        case .segmented:
            box.content.second.decoration = Decoration(background: .surfaceSecondary, cornerRadius: Pixels(6))
        case .radioGroup:
            options.gap = Axes(both: .pixels(Pixels(6)))
            options.alignItems = .flexStart
            box.content.second.decoration = Decoration()
        }
        box.content.second.style = options
        box.content.second.content.equalWidth = pickerStyle.kind == .segmented
        box.style = style
        box.decoration = decoration
        scope.kind = pickerStyle.kind
        scope.tags.removeAll()
        PickerScope.stack.append(scope)
        defer { PickerScope.stack.removeLast() }
        let (node, inner) = box.requestLayout(id, pass: &pass)
        return (node, Layout(inner: inner))
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout Layout, pass: inout PrepaintPass) -> PrepaintState {
        let scope = self.scope
        var composed = handlers
        composed.isFocusable = true
        let callerKey = handlers.onKey
        composed.onKey = { event in
            if let callerKey, callerKey(event) { return true }
            guard let direction = ControlKeys.pickerMove(event) else { return false }
            scope.move(direction)
            return true
        }
        if composed.axNode.role == .generic { composed.axNode.role = .radioGroup }
        box.handlers = composed
        return PrepaintState(inner: box.prepaint(id, bounds: bounds, layout: &layout.inner, pass: &pass))
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout,
                               prepaint: inout PrepaintState, pass: inout PaintPass) {
        box.paint(id, bounds: bounds, layout: &layout.inner, prepaint: &prepaint.inner, pass: &pass)
    }
}

/// The innermost `Picker`'s selection, style and option order, read by each
/// `TaggedElement` inside it during layout (`DD-V` item 2).
///
/// **A class**, so the tags a frame's options append are the ones the picker's
/// arrow handler — built in the same frame's prepaint — reads at input time.
/// **A `@MainActor` static stack**, pushed by `Picker.requestLayout` around its
/// content and popped by `defer`, so it is balanced on every exit. An option
/// pushes `nil` around its own content (a barrier), so a tag nested inside an
/// option is transparent rather than a second option. Only layout reads it:
/// an option's choice of chrome is carried to prepaint and paint in its layout
/// state, so the stack is not pushed around those phases.
@MainActor
final class PickerScope {
    static var stack: [PickerScope?] = []
    static var current: PickerScope? { stack.last ?? nil }

    let matches: @MainActor (AnyHashable) -> Bool
    let write: @MainActor (AnyHashable) -> Void
    var kind: PickerStyle.Kind = .segmented
    /// This frame's options' tags, in declaration order.
    var tags: [AnyHashable] = []

    init(matches: @escaping @MainActor (AnyHashable) -> Bool,
         write: @escaping @MainActor (AnyHashable) -> Void) {
        self.matches = matches
        self.write = write
    }

    /// Selects the previous or next option, **without wrapping** (`DD-T` item
    /// 2); at an end it writes nothing. With nothing selected, forward selects
    /// the first option and backward the last.
    func move(_ direction: ControlKeys.Direction) {
        guard !tags.isEmpty else { return }
        let target: Int
        if let current = tags.firstIndex(where: matches) {
            target = direction == .forward ? current + 1 : current - 1
        } else {
            target = direction == .forward ? 0 : tags.count - 1
        }
        guard tags.indices.contains(target) else { return }
        write(tags[target])
    }
}

/// A `Picker`'s options container's content (`DD-V` item 5). **Segmented**
/// (`equalWidth`): it consumes and plans its options' lowered records, as
/// `ListRows` does, and places them with `EqualWidthRow` — every segment as
/// wide as the widest (PA1). Each is planned as a child of a column whose
/// `alignItems` stretches, so a segment's width is a greedy frame **aliased as
/// its rect** (`LR-AC`): its fill, hitbox and accessibility frame are the
/// equalised width, not its own. **Radio group**: it hands its content's nodes
/// to the enclosing column `Box` unchanged.
///
/// Its record is registered under site `box`: it is part of the picker's
/// options `Box`, which consumes it, and a report can be reached only through
/// its options, which are internal `Box`es declaring no item field.
struct OptionRow<Content: ElementGroup>: ElementGroup {
    var content: Content
    var equalWidth: Bool

    mutating func requestGroupLayout(under parent: GlobalElementID?, at cursor: inout Int,
                                     pass: inout LayoutPass) -> ([LayoutNodeID], Content.GroupLayout) {
        let (nodes, layout) = content.requestGroupLayout(under: parent, at: &cursor, pass: &pass)
        guard equalWidth else { return (nodes, layout) }
        let received = nodes.map { pass.frame.lowering.consume($0) }
        var planningParent = Style()
        planningParent.flexDirection = .column
        planningParent.size.width = .length(.pixels(Pixels(0)))  // no one-child elision (as `ListRows`)
        var fields: [UnlowerableField] = []
        let plans = pass.planLegacyItems(received, parent: planningParent, parentKind: .flex(isRow: false),
                                         parentSite: .box, fields: &fields)
        let node: LayoutNodeID
        if fields.isEmpty {
            node = pass.frame.requestNativeLayout(EqualWidthRow(),
                                                  children: pass.registerLegacyItems(nodes, plans))
        } else {
            for field in fields.dropLast() { pass.frame.noteUnlowerable(field) }
            node = pass.frame.unlowerable(fields[fields.count - 1])
        }
        let recorded = pass.recordLoweredItem(node, animated: Style(), declared: Style(), site: .box,
                                              contentAlignment: .topLeading, kind: .leaf)
        return ([recorded], layout)
    }

    mutating func prepaintGroup(layout: inout Content.GroupLayout,
                                pass: inout PrepaintPass) -> Content.GroupPrepaint {
        content.prepaintGroup(layout: &layout, pass: &pass)
    }

    mutating func paintGroup(layout: inout Content.GroupLayout, prepaint: inout Content.GroupPrepaint,
                             pass: inout PaintPass) {
        content.paintGroup(layout: &layout, prepaint: &prepaint, pass: &pass)
    }
}

/// Every subview as wide as the widest subview's ideal width, side by side from
/// the leading edge, as tall as the tallest (`DD-V` item 5; PA1: Alpha, Beta,
/// Gamma all 70).
struct EqualWidthRow: ProposalLayout {
    private func widest(_ subviews: MeasurementSubviews) -> Double {
        var widest = 0.0
        for index in subviews.indices {
            widest = Swift.max(widest, subviews[index].sizeThatFits(ProposedSize(width: nil, height: nil)).size.width)
        }
        return widest
    }

    func sizeThatFits(proposal: ProposedSize, subviews: MeasurementSubviews) -> LayoutMeasurement {
        let width = widest(subviews)
        var tallest = 0.0
        for index in subviews.indices {
            tallest = Swift.max(tallest, subviews[index].sizeThatFits(ProposedSize(width: width, height: nil)).size.height)
        }
        return LayoutMeasurement(size: SizeD(width: width * Double(subviews.count), height: tallest))
    }

    func placeSubviews(in bounds: LayoutRect, proposal: ProposedSize, subviews: PlacementSubviews) {
        var width = 0.0
        for index in subviews.indices {
            width = Swift.max(width, subviews[index].sizeThatFits(ProposedSize(width: nil, height: nil)).size.width)
        }
        for index in subviews.indices {
            subviews[index].place(at: Point(x: bounds.x + Double(index) * width, y: bounds.y),
                                  anchor: .topLeading, proposal: ProposedSize(width: width, height: bounds.height))
        }
    }
}

/// What `.tag(_:)` returns (ruling `DD-V` items 2 and 6). **Public only because
/// `.tag` returns it** (SwiftUI's returns `some View`); its initialiser is
/// internal.
///
/// **Inside a `Picker`** it is an option: during layout it reads the innermost
/// `PickerScope`, appends its tag, and builds its chrome — a segment `Box`
/// (horizontal padding 12, 24 tall by a zero-width strut, `.surface` when
/// selected, corner radius 5) or a radio row (a 14-point circle `Box`, corner
/// radius 7, `.accent` when selected or `.surface` with a `.separator` border,
/// 7, then the content). The chrome takes the option's slot, named by the
/// content's `.id` when it has one; its handlers write the tag on a click and
/// declare `.radioButton`, value `"1"`/`"0"`, `.selected` when chosen.
///
/// **Outside a picker it is transparent** (`DD-V` item 6; record §05's row: a
/// tag is stored and read by nothing there): it forwards **every** `Element`
/// requirement — the group entry, so the content takes the slot at its own id
/// with its own `@State` bound and its own lowered record passed through; the
/// three phases; and `elementID` — never only the phases (`DD-AC` item 5).
public struct TaggedElement<Content: Element>: Element {
    var content: Content
    var tag: AnyHashable
    private var chrome: Chrome?

    typealias Chrome = Box<Pair<Box<EmptyGroup>, Content>>

    init(content: Content, tag: AnyHashable) {
        self.content = content
        self.tag = tag
    }

    public var elementID: ElementID? { content.elementID }

    /// Which way this frame's layout went, carried to prepaint and paint.
    public struct GroupLayout { var state: Either<Content.GroupLayout, SingleElementLayout<Chrome>> }
    public struct GroupPrepaint { var state: Either<Content.GroupPrepaint, Chrome.PrepaintState> }
    public struct LayoutState { var state: Either<Content.LayoutState, Chrome.Layout> }
    public struct PrepaintState { var state: Either<Content.PrepaintState, Chrome.PrepaintState> }

    /// A bare (outside a picker) or option phase state.
    enum Either<Bare, Option> {
        case bare(Bare)
        case option(Option)
    }

    /// The option chrome for `scope`, or `nil` outside a picker.
    private func makeChrome(_ scope: PickerScope) -> Chrome {
        let selected = scope.matches(tag)
        scope.tags.append(tag)
        var row = Style()
        row.flexDirection = .row
        row.alignItems = .center
        var lead = Style()
        var chrome: Chrome
        switch scope.kind {
        case .segmented:
            row.justifyContent = .center
            row.padding.left = .pixels(Pixels(12))
            row.padding.right = .pixels(Pixels(12))
            lead.size = Size(width: .length(.pixels(Pixels(0))), height: .length(.pixels(Pixels(24))))
            chrome = Box(style: row,
                         decoration: Decoration(background: selected ? .surface : nil, cornerRadius: Pixels(5)),
                         content: Pair(Box(style: lead), content))
        case .radioGroup:
            row.gap = Axes(both: .pixels(Pixels(7)))
            lead.size = Size(width: .length(.pixels(Pixels(14))), height: .length(.pixels(Pixels(14))))
            let circle = Decoration(background: selected ? .accent : .surface, cornerRadius: Pixels(7),
                                    border: selected ? nil : BorderStyle(.separator, width: Pixels(1)))
            chrome = Box(style: row, content: Pair(Box(style: lead, decoration: circle), content))
        }
        chrome.elementID = content.elementID
        let tag = self.tag
        chrome.handlers.onClick = { scope.write(tag) }
        chrome.handlers.axNode = AXNode(role: .radioButton, value: selected ? "1" : "0",
                                        traits: selected ? [.selected] : [])
        return chrome
    }

    /// Runs `body` with a barrier pushed, so a tag inside this option's content
    /// is transparent.
    private static func behindBarrier<T>(_ body: () -> T) -> T {
        PickerScope.stack.append(nil)
        defer { PickerScope.stack.removeLast() }
        return body()
    }

    public mutating func requestGroupLayout(under parent: GlobalElementID?, at cursor: inout Int,
                                            pass: inout LayoutPass) -> ([LayoutNodeID], GroupLayout) {
        guard let scope = PickerScope.current else {
            chrome = nil
            let (nodes, layout) = content.requestGroupLayout(under: parent, at: &cursor, pass: &pass)
            return (nodes, GroupLayout(state: .bare(layout)))
        }
        var built = makeChrome(scope)
        let (nodes, layout) = Self.behindBarrier {
            built.requestGroupLayout(under: parent, at: &cursor, pass: &pass)
        }
        chrome = built
        return (nodes, GroupLayout(state: .option(layout)))
    }

    public mutating func prepaintGroup(layout: inout GroupLayout, pass: inout PrepaintPass) -> GroupPrepaint {
        switch layout.state {
        case .bare(var inner):
            let prepaint = content.prepaintGroup(layout: &inner, pass: &pass)
            layout.state = .bare(inner)
            return GroupPrepaint(state: .bare(prepaint))
        case .option(var inner):
            guard var built = chrome else { preconditionFailure(Self.mismatch) }
            let prepaint = built.prepaintGroup(layout: &inner, pass: &pass)
            chrome = built
            layout.state = .option(inner)
            return GroupPrepaint(state: .option(prepaint))
        }
    }

    public mutating func paintGroup(layout: inout GroupLayout, prepaint: inout GroupPrepaint,
                                    pass: inout PaintPass) {
        switch (layout.state, prepaint.state) {
        case (.bare(var inner), .bare(var innerPrepaint)):
            content.paintGroup(layout: &inner, prepaint: &innerPrepaint, pass: &pass)
            layout.state = .bare(inner)
            prepaint.state = .bare(innerPrepaint)
        case (.option(var inner), .option(var innerPrepaint)):
            guard var built = chrome else { preconditionFailure(Self.mismatch) }
            built.paintGroup(layout: &inner, prepaint: &innerPrepaint, pass: &pass)
            chrome = built
            layout.state = .option(inner)
            prepaint.state = .option(innerPrepaint)
        default:
            preconditionFailure(Self.mismatch)
        }
    }

    public mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, LayoutState) {
        guard let scope = PickerScope.current else {
            chrome = nil
            let (node, state) = content.requestLayout(id, pass: &pass)
            return (node, LayoutState(state: .bare(state)))
        }
        var built = makeChrome(scope)
        let (node, state) = Self.behindBarrier { built.requestLayout(id, pass: &pass) }
        chrome = built
        return (node, LayoutState(state: .option(state)))
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout LayoutState,
                                  pass: inout PrepaintPass) -> PrepaintState {
        switch layout.state {
        case .bare(var inner):
            let prepaint = content.prepaint(id, bounds: bounds, layout: &inner, pass: &pass)
            layout.state = .bare(inner)
            return PrepaintState(state: .bare(prepaint))
        case .option(var inner):
            guard var built = chrome else { preconditionFailure(Self.mismatch) }
            let prepaint = built.prepaint(id, bounds: bounds, layout: &inner, pass: &pass)
            chrome = built
            layout.state = .option(inner)
            return PrepaintState(state: .option(prepaint))
        }
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout LayoutState,
                               prepaint: inout PrepaintState, pass: inout PaintPass) {
        switch (layout.state, prepaint.state) {
        case (.bare(var inner), .bare(var innerPrepaint)):
            content.paint(id, bounds: bounds, layout: &inner, prepaint: &innerPrepaint, pass: &pass)
            layout.state = .bare(inner)
            prepaint.state = .bare(innerPrepaint)
        case (.option(var inner), .option(var innerPrepaint)):
            guard var built = chrome else { preconditionFailure(Self.mismatch) }
            built.paint(id, bounds: bounds, layout: &inner, prepaint: &innerPrepaint, pass: &pass)
            chrome = built
            layout.state = .option(inner)
            prepaint.state = .option(innerPrepaint)
        default:
            preconditionFailure(Self.mismatch)
        }
    }

    private static var mismatch: String {
        "TaggedElement: the phase state disagrees with the element about whether it is a picker option — "
            + "its content was rebuilt mid-frame"
    }
}

extension Element {
    /// Marks this element as a `Picker` option whose selection value is
    /// `value` (SwiftUI's `.tag(_:)`, `DD-V` item 1). **Outside a picker it
    /// changes nothing** (`DD-V` item 6).
    public func tag<V: Hashable>(_ value: V) -> TaggedElement<Self> {
        TaggedElement(content: self, tag: AnyHashable(value))
    }
}
