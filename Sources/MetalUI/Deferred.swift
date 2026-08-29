import MetalUICore
import MetalUILayout

/// A portal: hoists its one child above every sibling's paint order and
/// escapes clipping, without introducing a layout node of its own.
///
/// **`Deferred` contributes no `Style` and no node of its own** — its own
/// resolved node is exactly `content`'s. But it DOES derive a proper child
/// identity for `content`, the same way `Box`/`ScrollView` derive one for
/// each of their children: `requestLayout` calls
/// `content.requestGroupLayout(under: id, at: &cursor, pass:)` rather than
/// forwarding `id` straight through, so `content`'s own `.id()` is honoured
/// and `content` is one level deeper than `Deferred` in the identity path,
/// not sharing `Deferred`'s own id outright. `prepaint`/`paint` read back the
/// id and node `requestLayout` stored, via `content.prepaintGroup`/
/// `paintGroup`, and wrap each in `pass.deferred { … }`.
///
/// **On both phases, and the reason is hit-testing, not symmetry.** The
/// scroll-region registry is built in `prepaint`; a tooltip that paints above
/// its siblings while still receiving wheel events as though it were beneath
/// them is worse than one that does neither (`PrepaintPass.deferred`'s doc
/// comment).
///
/// **What "escapes clipping" costs, on purpose.** `pass.deferred` resets the
/// clip stack to the whole surface and the translation to zero for `body`'s
/// duration — see `PaintPass.deferred` — so a modal wrapped in `Deferred`
/// inside a `ScrollView` covers the window rather than being clipped to (or
/// scrolling with) the viewport. CSS would clip such a descendant unless its
/// containing block sat outside the clipper; this framework does not
/// reproduce that coupling (design spec §2, §7.2).
public struct Deferred<Content: Element>: Element {
    public var elementID: ElementID?
    public var content: Content

    public init(elementID: ElementID? = nil, @ElementBuilder content: () -> Content) {
        self.elementID = elementID
        self.content = content()
    }

    public struct LayoutState {
        var content: Content.GroupLayout
    }

    public mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass)
        -> (LayoutNodeID, LayoutState) {
        var cursor = 0
        let (nodes, contentLayout) = content.requestGroupLayout(under: id, at: &cursor, pass: &pass)
        // `content` is a single `Element`, so `requestGroupLayout`'s default
        // (`SingleElementLayout`) always hands back exactly one node — this
        // becomes `Deferred`'s own node, reached through `content`'s own
        // derived child identity rather than `Deferred`'s.
        return (nodes[0], LayoutState(content: contentLayout))
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout LayoutState,
                                  pass: inout PrepaintPass) -> Content.GroupPrepaint {
        var result: Content.GroupPrepaint!
        pass.deferred {
            result = content.prepaintGroup(layout: &layout.content, pass: &pass)
        }
        return result
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout LayoutState,
                               prepaint: inout Content.GroupPrepaint,
                               pass: inout PaintPass) {
        pass.deferred {
            content.paintGroup(layout: &layout.content, prepaint: &prepaint, pass: &pass)
        }
    }
}
