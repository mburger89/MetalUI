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
    /// recorded in the last frame (`Window.lastPresentationAnchors`): its
    /// drawn bounds in window points, render effects and scroll included
    /// (`MA-B`).
    /// `initialHighlight` is the row an in-window panel opens highlighted
    /// and scrolled to — a menu picker's selection (`SV-Q`).
    /// `isPresented` is a code-driven menu's binding, written `true` once it
    /// is open (`MN-AK`).
    func openPullDown(_ id: GlobalElementID, isEnabled: Bool, initialHighlight: Int? = nil,
                      isPresented: Binding<Bool>? = nil, content: @escaping @MainActor () -> MenuItems) {
        window?.openPullDownMenu(id, isEnabled: isEnabled, initialHighlight: initialHighlight,
                                 isPresented: isPresented, content: content)
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
        // A code-driven menu notes its binding in layout, as a presentation
        // scope does (`MN-AK`): the window reconciles it after the frame.
        if let isPresented {
            let first = pass.frame.tree.nodeCount
            let content = content
            let isEnabled = pass.frame.environmentTop.isEnabled
            let (node, inner) = button.requestLayout(id, pass: &pass)
            pass.frame.notePresentation(isPresented: isPresented,
                                        request: .menu(isEnabled: isEnabled,
                                                       content: { MenuItems([content()]) }),
                                        owner: id, span: (first, pass.frame.tree.nodeCount - 1))
            return (node, LayoutState(button: button, inner: inner))
        }
        let (node, inner) = button.requestLayout(id, pass: &pass)
        return (node, LayoutState(button: button, inner: inner))
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout LayoutState,
                                  pass: inout PrepaintPass) -> Button<Pair<Label, Text>>.PrepaintState {
        // The button's action opens the menu, anchored at this frame's bounds
        // (`MN-H` item 1): a click, Space/Return when focused, an
        // accessibility press — and none of them while disabled, `Button`'s
        // one gate. The menu's own open replaces a caller's `onClick`.
        // `isEnabled` below is belt-and-braces (`MN-AF` item 9): `Button`'s
        // gate already keeps a disabled menu's open from running, so forcing
        // it `true` reddens nothing; it keeps the record honest.
        let presenter = pass.frame.menuPresenter
        let isEnabled = pass.frame.environmentTop.isEnabled
        let content = content
        let isPresented = isPresented
        // The menu's own render effects open inside its button's registration,
        // after this line, so they are passed in (`MA-G`).
        pass.frame.recordPresentationAnchor(id, bounds: bounds, ownEffects: decoration.renderEffects)
        var composed = handlers
        composed.onClick = { [weak presenter] in
            presenter?.openPullDown(id, isEnabled: isEnabled, isPresented: isPresented,
                                    content: { MenuItems([content()]) })
        }
        composed.axNode.menuButtonHint = true   // M1: AXMenuButton (MN-H item 2)
        layout.button.handlers = composed
        return layout.button.prepaint(id, bounds: bounds, layout: &layout.inner, pass: &pass)
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout LayoutState,
                               prepaint: inout Button<Pair<Label, Text>>.PrepaintState, pass: inout PaintPass) {
        layout.button.paint(id, bounds: bounds, layout: &layout.inner, prepaint: &prepaint, pass: &pass)
    }
}

extension Window {
    /// Presents `id`'s pull-down menu at its bottom-leading corner (`MN-H`
    /// item 1): natively there when the platform shows menus, else the drawn
    /// panel below it — the context menu's own path (`MN-C`, `MN-F`), its items
    /// evaluated now, under `id`'s dispatch. The corner is of the label's drawn
    /// bounds, render effects included (`MA-B`). Nothing without an anchor.
    /// A code-driven menu's `isPresented` (`MN-AK`) rides on the session and is
    /// written `true` once the menu is open. Returns whether it opened.
    @discardableResult
    func openPullDownMenu(_ id: GlobalElementID, isEnabled: Bool, initialHighlight: Int? = nil,
                          isPresented: Binding<Bool>? = nil,
                          content: @escaping @MainActor () -> MenuItems) -> Bool {
        guard let bounds = lastPresentationAnchors[id] else { return false }
        let record = ContextMenuRecord(attachment: ContextualAttachment(menu: content, help: nil),
                                       isEnabled: isEnabled, bounds: bounds)
        guard openContextMenu(of: id, record, initialHighlight: initialHighlight) else { return false }
        if let isPresented {
            menuSession?.pullDownBinding = PullDownBinding(owner: id, isPresented: isPresented)
            StateDispatch.dispatching(to: id) { if !isPresented.wrappedValue { isPresented.wrappedValue = true } }
        }
        return true
    }

    /// A session that left (or was replaced by another menu's) closes its
    /// binding (`MN-AK`): `false`, written from the input that ended it. A
    /// session that merely changed — a hover, a submenu — keeps its owner and
    /// writes nothing.
    func menuSessionDidChange(from old: MenuSession?) {
        guard let bound = old?.pullDownBinding, menuSession?.pullDownBinding?.owner != bound.owner else { return }
        StateDispatch.dispatching(to: bound.owner) {
            if bound.isPresented.wrappedValue { bound.isPresented.wrappedValue = false }
        }
    }

    /// After the frame (`MN-AK`; `reconcilePresentations`' place, outside every
    /// phase): a code-driven menu whose binding reads `true` and is not the
    /// open one is opened; the open one whose binding reads `false`, or whose
    /// `Menu` left the tree, is closed. An open that cannot happen (disabled,
    /// no items, no anchor) writes `false` back so the binding does not lie.
    func reconcileMenuBindings() {
        guard !reconcilingMenuBindings else { return }
        reconcilingMenuBindings = true
        defer { reconcilingMenuBindings = false }
        let records = presentations.records.filter { if case .menu = $0.request { true } else { false } }
        if let bound = menuSession?.pullDownBinding {
            let live = records.first { $0.owner == bound.owner }
            if live == nil || bound.isPresented.wrappedValue == false { closePullDownSession() }
        }
        for record in records where record.isPresented.wrappedValue
            && menuSession?.pullDownBinding?.owner != record.owner {
            guard case .menu(let isEnabled, let content) = record.request else { continue }
            let opened = isEnabled && StateDispatch.dispatching(to: record.owner) {
                openPullDownMenu(record.owner, isEnabled: isEnabled, isPresented: record.isPresented, content: content)
            }
            if !opened {
                StateDispatch.dispatching(to: record.owner) { record.isPresented.wrappedValue = false }
            }
            break   // one menu is open at a time
        }
    }

    /// Closes the code-driven session: a native one is told to go (the platform
    /// ignores a menu it is not tracking, and its late outcome is stale), a drawn
    /// one is dropped. The session's own binding is already `false` here.
    private func closePullDownSession() {
        guard let session = menuSession else { return }
        if session.isNative { dismissPresentationOnPlatform(token: session.token) }
        menuSession = nil
        setNeedsRedraw()
    }
}
