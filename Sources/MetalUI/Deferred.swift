import MetalUICore
import MetalUILayout

/// A portal: hoists its one child above every sibling's paint order and
/// escapes clipping, without introducing a layout node of its own.
///
/// **`Deferred` contributes no `Style` and no node.** `requestLayout` forwards
/// `id` straight to `content.requestLayout(id, pass:)` and returns exactly
/// `content`'s own `(LayoutNodeID, LayoutState)` — `Deferred`'s own
/// `elementID` decides the *identity* `content` is laid out under (as with
/// `Box`/`ScrollView` wrapping their children), but nothing here asks the
/// engine for a node of its own. That is why this task touches no layout and
/// moves no golden: the mechanism lives entirely in `prepaint` and `paint`,
/// where both phases wrap `content`'s own call in `pass.deferred { … }`.
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

    public mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass)
        -> (LayoutNodeID, Content.LayoutState) {
        content.requestLayout(id, pass: &pass)
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout Content.LayoutState,
                                  pass: inout PrepaintPass) -> Content.PrepaintState {
        var result: Content.PrepaintState!
        pass.deferred {
            result = content.prepaint(id, bounds: bounds, layout: &layout, pass: &pass)
        }
        return result
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout Content.LayoutState,
                               prepaint: inout Content.PrepaintState,
                               pass: inout PaintPass) {
        pass.deferred {
            content.paint(id, bounds: bounds, layout: &layout, prepaint: &prepaint, pass: &pass)
        }
    }
}
