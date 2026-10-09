import MetalUICore
import MetalUILayout
import MetalUIPlatform

// Menus, popovers and tooltips, lane 1 — `.contextMenu` on both vocabularies
// (rulings `MN-E`, `MN-Q`, `MN-U`, `MN-V`; spec §2.3, §3.1). SwiftUI's side is
// `docs/probes/swiftui-menus-popovers.swift`, arms C0–C14.

/// What `.contextMenu` (and lane 3's `.help`) attach to an element: one class
/// box riding `Handlers.contextual` (`MN-Q`). A later `.contextMenu` replaces
/// an earlier one and keeps the help text, and the reverse.
final class ContextualAttachment {
    /// The menu's content, evaluated at each open (`MN-D` item 4), handed the
    /// secondary press's point in the contextual region's local space — `nil`
    /// for a keyboard or accessibility open (ruling `CI-R` item 4). The
    /// location-less spellings ignore it.
    let menu: (@MainActor (Point<Pixels>?) -> MenuItems)?
    /// The tooltip and accessibility help (`MN-P`, lane 3).
    let help: String?

    init(locatedMenu menu: (@MainActor (Point<Pixels>?) -> MenuItems)?, help: String?) {
        self.menu = menu
        self.help = help
    }

    /// An attachment whose menu takes no location (a pull-down `Menu`'s).
    convenience init(menu: (@MainActor () -> MenuItems)?, help: String?) {
        guard let menu else {
            self.init(locatedMenu: nil, help: help)
            return
        }
        self.init(locatedMenu: { (_: Point<Pixels>?) -> MenuItems in menu() }, help: help)
    }

    /// `existing` with its menu replaced by `content`.
    static func menu<M: MenuContent>(_ content: @escaping @MainActor () -> M,
                                     over existing: ContextualAttachment?) -> ContextualAttachment {
        ContextualAttachment(locatedMenu: { _ in MenuItems([content()]) }, help: existing?.help)
    }

    /// `existing` with its menu replaced by the located `content` (`CI-R`).
    static func locatedMenu<M: MenuContent>(_ content: @escaping @MainActor (Point<Pixels>?) -> M,
                                            over existing: ContextualAttachment?) -> ContextualAttachment {
        ContextualAttachment(locatedMenu: { MenuItems([content($0)]) }, help: existing?.help)
    }
}

extension StyledElement {
    /// Attaches a context menu — SwiftUI's `contextMenu(menuItems:)` (ruling
    /// `MN-E`; probe arms C1, C5r).
    ///
    /// Opened by a secondary press (the right button; a control-click on
    /// AppKit), by Shift-F10 or the Menu key off Apple while this element or a
    /// descendant is focused (`MN-G`), and by an accessibility client's
    /// show-menu (C11). `menuItems` runs **at each open** (C4c), in this
    /// element's dispatch (`ID-F`), never in layout or paint — so it may read
    /// `@State` and models freshly (`MN-D` item 4); it is `@escaping` where
    /// SwiftUI's is not, and the call site reads the same.
    ///
    /// The innermost menu under the pointer opens (C8). A covering element
    /// with a pointer handler and no menu blocks it (C14); one that only paints
    /// does not — divergence 114 (`MN-V`). `.allowsHitTesting(false)` keeps it
    /// shut (C13, `MN-U`); a disabled element's menu still opens, every item
    /// disabled (C9). An empty menu opens nothing (C10). On AppKit the menu is
    /// native once the platform presents it; elsewhere MetalUI draws it
    /// (`MN-C`, `MN-F`). A secondary press does nothing else — it runs no
    /// `onClick` or tap (divergence 110, `MN-B`).
    ///
    /// Returns `Self` — no identity level, no `StateTable` entry (`MN-Q`).
    public func contextMenu<M: MenuContent>(
        @MenuContentBuilder menuItems: @escaping @MainActor () -> M) -> Self {
        var copy = self
        copy.handlers.contextual = ContextualAttachment.menu(menuItems, over: handlers.contextual)
        return copy
    }

    /// A context menu whose builder is handed **where it was opened** — the
    /// secondary press's point in this element's local space (render effects
    /// undone), or `nil` when the menu opens from the keyboard (`MN-G`) or an
    /// accessibility show-menu (C11), where there is no pointer (ruling
    /// `CI-R`). **MetalUI-only**: none of SwiftUI's `contextMenu` signatures
    /// passes a location (probe census). With a secondary `DragGesture` on the
    /// pressed chain the menu opens on the release (`CI-F` item 4) and is
    /// still handed the press's point. Everything else is
    /// `contextMenu(menuItems:)`'s; the closure's arity selects this overload.
    public func contextMenu<M: MenuContent>(
        @MenuContentBuilder menuItems: @escaping @MainActor (Point<Pixels>?) -> M) -> Self {
        var copy = self
        copy.handlers.contextual = ContextualAttachment.locatedMenu(menuItems, over: handlers.contextual)
        return copy
    }
}

extension ProposalElementGroup {
    /// `StyledElement.contextMenu(menuItems:)` on the proposal path: wraps once
    /// in a `ContextualModifier` — one identity level, for its caller only
    /// (`MN-Q`, `DN-P`'s shape).
    public func contextMenu<M: MenuContent>(
        @MenuContentBuilder menuItems: @escaping @MainActor () -> M) -> ContextualModifier<Self> {
        ContextualModifier(content: self, attachment: ContextualAttachment.menu(menuItems, over: nil))
    }

    /// `StyledElement.contextMenu(menuItems:)`'s located form on the proposal
    /// path (`CI-R`): the point is local to this wrapper's bounds.
    public func contextMenu<M: MenuContent>(
        @MenuContentBuilder menuItems: @escaping @MainActor (Point<Pixels>?) -> M) -> ContextualModifier<Self> {
        ContextualModifier(content: self, attachment: ContextualAttachment.locatedMenu(menuItems, over: nil))
    }
}

/// A proposal wrapper carrying a context menu (and lane 3's help) — what the
/// proposal `.contextMenu` returns (ruling `MN-Q`). `GestureModifier`'s recipe:
/// no layout node of its own, its one child numbered from 0 under its id, one
/// identity level for its caller only. It registers the contextual region at
/// its own bounds.
public struct ContextualModifier<Content: ProposalElementGroup>: Element {
    /// The wrapped proposal content.
    public var content: Content
    var attachment: ContextualAttachment

    init(content: Content, attachment: ContextualAttachment) {
        self.content = content
        self.attachment = attachment
    }

    /// The content's layout.
    public struct Layout { var content: Content.GroupLayout }

    public mutating func requestProposalLayout(_ id: GlobalElementID,
                                               pass: inout LayoutPass) -> (ProposalNodeID, Layout) {
        var cursor = 0
        let (children, contentLayout) = content.requestProposalGroupLayout(under: id, at: &cursor,
                                                                           pass: &pass)
        precondition(children.count == 1, "a context menu modifier requires one native child")
        return (children[0], Layout(content: contentLayout))
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout,
                                  pass: inout PrepaintPass) -> Content.GroupPrepaint {
        var handlers = Handlers()
        handlers.contextual = attachment
        // `.help` is `accessibilityHint`'s declaration too (`MN-P` item 1),
        // registered as `AccessibilityModifier` registers it — synthesizing,
        // so the two publish one tree.
        let help = attachment.help
        if let help { handlers.axNode.declarations.hint = help }
        // A wrapper's registration follows an effect written inside it at the
        // same rect (`GX-P` item 1).
        let frame = pass.frame
        return frame.sharingRegistrationsWithEffects(at: bounds, register: {
            pass.registerHandlers(handlers, at: bounds, id: id, accessibleText: nil,
                                  synthesizesAccessibility: help != nil)
        }, content: { content.prepaintGroup(layout: &layout.content, pass: &pass) })
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Layout,
                               prepaint: inout Content.GroupPrepaint, pass: inout PaintPass) {
        content.paintGroup(layout: &layout.content, prepaint: &prepaint, pass: &pass)
    }
}

extension ContextualModifier: ProposalElement {}
