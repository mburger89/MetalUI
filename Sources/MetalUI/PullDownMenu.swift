import MetalUICore
import MetalUILayout
import MetalUIPlatform

// Menus, popovers and tooltips, lane 2 — `Menu` as a pull-down button (rulings
// `MN-H`, `MN-AD`; spec `docs/superpowers/specs/2026-10-02-menus-popovers-design.md`
// §2.4, §3.4). The declaration and its storage are `MenuContent.swift`'s (lane
// 1); this file makes it an element. SwiftUI's side is
// `docs/probes/swiftui-menus-popovers.swift`, arm M1 (`AXMenuButton`).

/// The window's handle a frame's elements reach it through to present a menu
/// from input (spec §3.4): owned by `Window`, handed to every frame as
/// `ScrollViewProxy`'s queue is, held weakly so a handler that outlives the
/// window presents nothing.
@MainActor
final class MenuPresenter {
    weak var window: Window?

    init(window: Window?) { self.window = window }

    /// Opens `content` as `id`'s pull-down, anchored at the bounds `id`
    /// recorded in the last frame (`Window.lastPresentationAnchors`).
    func openPullDown(_ id: GlobalElementID, isEnabled: Bool, content: @escaping @MainActor () -> MenuItems) {
        window?.openPullDownMenu(id, isEnabled: isEnabled, content: content)
    }
}

extension Menu: Element, StyledElement {
    /// What `requestLayout` hands the later phases: the chrome's button and
    /// its own layout.
    public struct LayoutState {
        var button: Button<Pair<Label, Text>>
        var inner: Button<Pair<Label, Text>>.LayoutState
    }

    public mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass)
        -> (LayoutNodeID, LayoutState) {
        let label = label
        var button = Button(action: {}) {
            label
            Text(" \u{2304}").accessibilityHidden(true)
        }
        button.style = style
        button.decoration = decoration
        let (node, inner) = button.requestLayout(id, pass: &pass)
        return (node, LayoutState(button: button, inner: inner))
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout LayoutState,
                                  pass: inout PrepaintPass) -> Button<Pair<Label, Text>>.PrepaintState {
        // Lane 2 red stub: the button opens nothing yet.
        layout.button.handlers = handlers
        return layout.button.prepaint(id, bounds: bounds, layout: &layout.inner, pass: &pass)
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout LayoutState,
                               prepaint: inout Button<Pair<Label, Text>>.PrepaintState, pass: inout PaintPass) {
        layout.button.paint(id, bounds: bounds, layout: &layout.inner, prepaint: &prepaint, pass: &pass)
    }
}

extension Window {
    /// Presents `id`'s pull-down menu (`MN-H` item 1) — lane 2 red stub.
    func openPullDownMenu(_ id: GlobalElementID, isEnabled: Bool, content: @escaping @MainActor () -> MenuItems) {}
}
