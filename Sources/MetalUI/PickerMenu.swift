import MetalUICore
import MetalUILayout
import MetalUIPlatform
import MetalUITextSystem

// Platform services, lane 3 — the menu `Picker`'s pull-down (rulings `SV-P`,
// `SV-AA`, `SV-S`, `SV-Q`; spec §4.3). `Picker.swift` owns the style and the
// option discovery; this file is the button: `Menu`'s chrome (a `Button` with a
// ` ⌄` indicator, `MN-H` item 1) whose label is an option sink — the caller's
// content, each `.tag`ged option recording itself and laying out nothing —
// followed by the selected option's title in a box as wide as the widest
// option's. The sink comes first, so the label reads this frame's options.

/// A menu picker's pull-down button (`SV-P` items 2, 4–6): `Menu`'s recipe —
/// the anchor recorded in prepaint, a click, Space (Return off Apple) or an
/// accessibility press opening the recorded options through
/// `Window.openPullDownMenu`, none of them while disabled (`Button`'s one
/// gate) — published as a `.popUpButton` labelled by the picker's title, its
/// value the selected option's title.
struct PickerMenuButton<Content: ElementGroup>: Element {
    typealias Chrome = Button<Pair<OptionSink<Content>, PickerMenuLabel>>
    var button: Chrome
    let scope: PickerScope
    let title: String

    init(content: Content, scope: PickerScope, title: String, pickerID: GlobalElementID) {
        self.scope = scope
        self.title = title
        let label = Pair(OptionSink(content: content), PickerMenuLabel(scope: scope, pickerID: pickerID))
        self.button = Button(action: {}) { label }
    }

    mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass)
        -> (LayoutNodeID, Chrome.LayoutState) {
        button.requestLayout(id, pass: &pass)
    }

    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Chrome.LayoutState,
                           pass: inout PrepaintPass) -> Chrome.PrepaintState {
        let presenter = pass.frame.menuPresenter
        let isEnabled = pass.frame.environmentTop.isEnabled
        let scope = scope
        pass.frame.recordPresentationAnchor(id, bounds: bounds)
        var composed = button.handlers
        composed.onClick = { [weak presenter] in
            // The options the last layout recorded, as toggles, the selected
            // one on (`P1` `state=on`) and highlighted on an in-window open
            // (`SV-Q`); choosing one writes its tag (`P1` pick=1).
            let selected = scope.options.firstIndex { scope.matches($0.tag) }
            presenter?.openPullDown(id, isEnabled: isEnabled, initialHighlight: selected) {
                MenuItems([PickerMenuOptions(scope: scope)])
            }
        }
        composed.axNode.popUpButtonHint = true   // SV-S: AXPopUpButton (P0–P3)
        composed.axNode.label = title
        composed.axNode.value = scope.selectedTitle
        button.handlers = composed
        return button.prepaint(id, bounds: bounds, layout: &layout, pass: &pass)
    }

    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Chrome.LayoutState,
                        prepaint: inout Chrome.PrepaintState, pass: inout PaintPass) {
        button.paint(id, bounds: bounds, layout: &layout, prepaint: &prepaint, pass: &pass)
    }
}

/// A menu picker's options as menu items, evaluated at open (`MN-D` item 4):
/// one toggle per recorded option, on for the selected one; choosing writes
/// the option's tag.
@MainActor
struct PickerMenuOptions: MenuContent {
    let nodes: [MenuNode]

    init(scope: PickerScope) {
        nodes = scope.options.map { option in
            let tag = option.tag
            return MenuNode(kind: .toggle, title: option.title, isEnabled: true, isOn: scope.matches(tag),
                            run: { scope.write(tag) })
        }
    }

    func _menuNodes(in context: _MenuContext) -> _MenuNodes {
        _MenuNodes(nodes.map { node in
            var node = node
            node.isEnabled = context.isEnabled
            return node
        })
    }
}

/// The caller's content inside a menu picker's button, taking **one**
/// identity slot whatever the option count (`SV-P` item 3): its options record
/// themselves into the picker's scope and register no node; its children
/// number from 0 under the sink's own id.
struct OptionSink<Content: ElementGroup>: ElementGroup {
    var content: Content

    mutating func requestGroupLayout(under parent: GlobalElementID?, at cursor: inout Int,
                                     pass: inout LayoutPass) -> ([LayoutNodeID], Content.GroupLayout) {
        let id = GlobalElementID.child(of: parent, at: cursor, name: nil)
        cursor += 1
        var inner = 0
        return content.requestGroupLayout(under: id, at: &inner, pass: &pass)
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

/// A menu picker's label (`SV-P` item 2, `SV-AA`): the selected option's
/// title — `""` when no tag matches (`P5`) — in a box as wide as the widest
/// option title, then ` ⌄` (hidden from accessibility, as `Menu`'s). The
/// width is measured through `Frame.textSystem` (`TS-A`) once per change of
/// the titles, the font or the scale (`PickerTitleWidths`).
struct PickerMenuLabel: Element {
    typealias Inner = Box<Pair<Box<Text>, Text>>
    let scope: PickerScope
    let pickerID: GlobalElementID

    struct LayoutState {
        var inner: Inner
        var layout: Inner.Layout
    }

    mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, LayoutState) {
        let frame = pass.frame
        let font = frame.textSystem.resolveFont(resolveTextStyle(TextStyleRequest(), in: frame.environmentTop)
            .descriptor)
        let titles = scope.options.map(\.title)
        let width = frame.pickerTitleWidths.width(for: pickerID, titles: titles, font: font,
                                                  scale: frame.scaleFactor) {
            Float(frame.textSystem.measure($0, font: font, wrappingAt: nil).widestLine)
        }
        var titleStyle = Style()
        titleStyle.size.width = .length(.pixels(Pixels(width.rounded(.up))))
        var row = Style()
        row.flexDirection = .row
        row.alignItems = .center
        var inner = Inner(style: row, content: Pair(Box(style: titleStyle, content: Text(scope.selectedTitle)),
                                                    Text(" \u{2304}").accessibilityHidden(true)))
        let (node, layout) = inner.requestLayout(id, pass: &pass)
        return (node, LayoutState(inner: inner, layout: layout))
    }

    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout LayoutState,
                           pass: inout PrepaintPass) -> Inner.PrepaintState {
        layout.inner.prepaint(id, bounds: bounds, layout: &layout.layout, pass: &pass)
    }

    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout LayoutState,
                        prepaint: inout Inner.PrepaintState, pass: inout PaintPass) {
        layout.inner.paint(id, bounds: bounds, layout: &layout.layout, prepaint: &prepaint, pass: &pass)
    }
}

/// The window-owned cache of each menu picker's widest option title
/// (`SV-AA`): keyed by the picker's id, valid while its titles (in order), its
/// resolved `FontKey` and the display scale are unchanged. Handed to every
/// frame (a `Frame` built outside a window gets a fresh one); entries no build
/// used are dropped after each build (`sweep`), so it holds only live pickers.
@MainActor
final class PickerTitleWidths {
    private struct Entry {
        var titles: [String]
        var font: FontKey
        var scale: Float
        var width: Float
    }

    private var entries: [GlobalElementID: Entry] = [:]
    private var touched: Set<GlobalElementID> = []

    /// The widest of `titles` for `id`, measuring each through `measure` only
    /// when the key differs from the last one stored.
    func width(for id: GlobalElementID, titles: [String], font: FontKey, scale: Float,
               measure: (String) -> Float) -> Float {
        touched.insert(id)
        if let entry = entries[id], entry.font == font, entry.scale == scale, entry.titles == titles {
            return entry.width
        }
        var widest: Float = 0
        for title in titles { widest = max(widest, measure(title)) }
        entries[id] = Entry(titles: titles, font: font, scale: scale, width: widest)
        return widest
    }

    /// Drops the entries no build used since the last sweep.
    func sweep() {
        entries = entries.filter { touched.contains($0.key) }
        touched.removeAll(keepingCapacity: true)
    }
}
