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
///
/// **The escape has a layout-phase half too, and it is not symmetric with the
/// other two.** `requestLayout` runs its subtree inside
/// `LayoutPass.withoutScrollContext`, so an element that windows against the
/// ambient `ScrollContext` — `List` is the only one today — sees no scroller
/// above it and builds everything, exactly as it would outside every
/// `ScrollView`. That is the layout counterpart of resetting the translation,
/// not of resetting the clip: a portal does not move with the content it
/// covers, so windowing against that content's offset is wrong in the same way
/// sliding with it would be.
///
/// **Its layout meaning** (plan task 7, stage 5, rulings `LR-CH`, `LR-CI`,
/// `LR-CM`; one authority since stage 9). An **in-flow** content is an ordinary
/// member of its parent's flow. A `Deferred` whose content is
/// `.position(.absolute)` is a **presentation root**: the content is lowered
/// as padding inside a window-sized frame, laid out in its own native run before
/// the frame's root, and this element hands its parent a 0×0 placeholder that
/// every lowered container drops — SwiftUI's window-root overlay (probe
/// `swiftui-overlay-presentation.swift` Q1–Q6), outside the presenter's layout as
/// a sheet is (P4/P5). Its containing block is the window whatever surrounds it
/// (stage 9, `LR-FF`: the `deferred.containingBlock`, `.nested` and `.root`
/// reports of `LR-CL` protected a legacy containing block and went with the
/// legacy engine). The paint and prepaint halves and the scroll-context reset are
/// unchanged.
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
        // The portal's third half, and it runs in THIS phase rather than in
        // the two below. `pass.deferred` resets the clip stack and the
        // accumulated scroll translation for prepaint and paint; nothing reset
        // the ambient `LayoutPass.scrollContext`, so a subtree that had escaped
        // a `ScrollView`'s clip was still told how far that `ScrollView` had
        // scrolled — and a `List` inside a portal duly windowed against an
        // offset it does not move by, emptying itself as the list behind it
        // scrolled. See `LayoutPass.withoutScrollContext`.
        let (nodes, contentLayout) = pass.withoutScrollContext {
            content.requestGroupLayout(under: id, at: &cursor, pass: &pass)
        }
        // `content` is a single `Element`, so `requestGroupLayout`'s default
        // (`SingleElementLayout`) always hands back exactly one node — this
        // becomes `Deferred`'s own node, reached through `content`'s own
        // derived child identity rather than `Deferred`'s.
        let node = nodes[0]
        // An ABSOLUTE content makes this `Deferred` a presentation root (plan
        // task 7, stage 5, ruling `LR-CH`); an in-flow content lowers exactly as
        // it always has.
        guard let item = pass.frame.lowering.items[node],
              item.declared.position == .absolute
        else { return (node, LayoutState(content: contentLayout)) }
        return (presentationPlaceholder(for: node, item, pass: &pass),
                LayoutState(content: contentLayout))
    }

    /// The presentation half of `requestLayout` for an absolute content
    /// (rulings `LR-CH`, `LR-CK`): consumes the content's record, lowers it into its own
    /// presentation root against the window (`LayoutPass.lowerPresentation`),
    /// queues that root for `Frame.computeRootLayout` (`LR-CM`) and returns the
    /// 0×0 placeholder every lowered container drops.
    ///
    /// **The placeholder is aliased to the content's element rect**, resolved now
    /// (its W when a stretched axis registered one), so this `Deferred`'s own
    /// `elementBounds` row is its content's — as under the legacy authority
    /// (until stage 9), where the two shared one node.
    private func presentationPlaceholder(for node: LayoutNodeID, _ item: LoweredItem,
                                         pass: inout LayoutPass) -> LayoutNodeID {
        let frame = pass.frame
        // A presentation registered inside this one is laid out against the
        // window too, like every presentation (stage 9, `LR-FF`: the
        // `deferred.nested` report protected a legacy containing block that is
        // gone with the legacy engine).
        _ = frame.lowering.consume(node)
        let root = pass.lowerPresentation(node, item)
        let placeholder = frame.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 0, height: 0)) }
        frame.lowering.record(LoweredItem(declared: Style(), animated: Style(), site: .deferred,
                                          contentAlignment: .topLeading, kind: .presentation),
                              for: placeholder)
        frame.lowering.alias(placeholder, to: frame.lowering.alias(node))
        frame.lowering.presentations.append((placeholder: placeholder, root: root))
        return placeholder
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
