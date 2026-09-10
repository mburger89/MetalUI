import MetalUICore
import MetalUILayout

/// Where a `Stack` places each child within itself.
///
/// SwiftUI's nine-position `Alignment`, and its spelling, because SwiftUI is
/// this framework's design authority (ruling EP-5). One value covers both axes;
/// `Stack.init` translates it into the substrate's `alignItems` (block axis) and
/// `justifyItems` (inline axis).
public enum Alignment: Sendable, Equatable {
    case topLeading,    top,    topTrailing
    case leading,       center, trailing
    case bottomLeading, bottom, bottomTrailing

    var blockAxis: AlignItems {
        switch self {
        case .topLeading, .top, .topTrailing:             return .flexStart
        case .leading, .center, .trailing:                return .center
        case .bottomLeading, .bottom, .bottomTrailing:    return .flexEnd
        }
    }

    var inlineAxis: JustifyItems {
        switch self {
        case .topLeading, .leading, .bottomLeading:       return .start
        case .top, .center, .bottom:                      return .center
        case .topTrailing, .trailing, .bottomTrailing:    return .end
        }
    }
}

/// A container that layers its children at the same position.
///
/// The container sizes to its largest child on each axis — independently, so the
/// widest and the tallest child may be different children — and every child is
/// placed within that box by `alignment`.
///
/// **Not absolute positioning.** A `Stack`'s children participate in its sizing.
/// Absolutely-positioned children are removed from flow and contribute nothing
/// to their parent's size; that is a different feature, the one modals and
/// popovers need, and it is live — `.position(.absolute)` is filtered out of a
/// `Stack`'s item list by `layOutStack` exactly as it is out of a flex
/// container's, and placed afterwards against its containing block. A `Stack`
/// child that is absolute is therefore not layered by `alignment` at all.
///
/// **Children paint in declaration order, first at the back.** That ordering is
/// only real because `Scene.finalize`'s draw list orders primitives across types
/// — before it, every rect drew beneath every glyph regardless of `order`, so a
/// background could not be layered under text.
///
/// **The default is `.center`, which is SwiftUI's answer and not CSS's.** A CSS
/// one-cell grid stretches its items; `ZStack` centres them at their natural
/// size. Ruling EP-5 takes SwiftUI's, as EP-8 already did for `Column`/`Row`.
///
/// **A `Stack` differs from a `Box` only in the `Style` it builds** — `display`,
/// `alignItems` and `justifyItems`, all set once in `init` and never touched
/// again. The three phase methods below are `Box`'s, unchanged: this type does
/// not wrap a `Box` the way `Column`/`Row` do, because its stored properties
/// already match `Box`'s exactly and there is nothing left to delegate.
public struct Stack<Content: ElementGroup>: Element, StyledElement {
    public var style: Style
    public var decoration: Decoration
    public var elementID: ElementID?
    public var handlers: Handlers
    public var content: Content

    public init(alignment: Alignment = .center,
                elementID: ElementID? = nil,
                @ElementBuilder content: () -> Content) {
        var style = Style()
        style.display = .stack
        style.alignItems = alignment.blockAxis
        style.justifyItems = alignment.inlineAxis
        self.style = style
        self.decoration = Decoration()
        self.elementID = elementID
        self.handlers = Handlers()
        self.content = content()
    }

    /// Carried from `requestLayout` to the later phases. Identical in shape to
    /// `Box.Layout` — see its doc comment for why `node` is stored rather than
    /// re-derived.
    public struct Layout {
        public var node: LayoutNodeID
        var content: Content.GroupLayout
    }

    public mutating func requestLayout(_ id: GlobalElementID,
                                       pass: inout LayoutPass) -> (LayoutNodeID, Layout) {
        // Children first: `requestNode` takes already-registered ids, so a
        // container builds bottom-up and the engine sees a complete subtree.
        //
        // The cursor starts at 0 here and nowhere else: it is this container's
        // own flat child index space, so a child's identity depends on its
        // position among *its* siblings and not on how many elements the frame
        // has visited. `prepaintGroup` and `paintGroup` need no cursor — each
        // member stored its id during this call.
        var cursor = 0
        let (children, contentLayout) = content.requestGroupLayout(under: id, at: &cursor,
                                                                   pass: &pass)
        // M4 spec 3 §5 — see `Box.requestLayout`'s identical line. Stored
        // back on `self` so `paint`'s read of `self.decoration` later this
        // frame sees the substituted (possibly mid-transition) values.
        (style, decoration) = animated(style, decoration, for: id, pass: &pass)
        let node = pass.requestNode(style: style, children: children)
        return (node, Layout(node: node, content: contentLayout))
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout Layout,
                                  pass: inout PrepaintPass) -> Content.GroupPrepaint {
        // Before the children, so a child's click target ranks above this one
        // — see `Box.prepaint`, whose body this mirrors line for line.
        pass.registerHandlers(handlers, at: bounds, id: id)
        // `bounds` is this stack's own rect and is deliberately not passed
        // down: the engine stores rects **absolute to the root**, so each
        // child looks its own up rather than being offset by its parent.
        // Adding `bounds` here would double-count every ancestor's origin.
        return content.prepaintGroup(layout: &layout.content, pass: &pass)
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout Layout, prepaint: inout Content.GroupPrepaint,
                               pass: inout PaintPass) {
        // Own background first, then children, so a background never paints
        // over a child — see `Box.paint`'s comment for why emission order is
        // paint order.
        // Through `animatedColor`, exactly as `Box.paint` does — see that
        // call site and `AnimatedColor.swift`'s top doc.
        //
        // **Wired by Task 5 rather than by Task 4b, which introduced the
        // helper and deliberately scoped itself to `Box`.** That exclusion was
        // accepted by both of its reviews on the stated ground that the hole
        // was "not live today" (ruling V: nothing could animate in production
        // at all). Task 5 is the change that removes that ground, so leaving
        // it would ship a live animation subsystem in which a
        // `Box {}.background(.accent)` fades under a transaction and a
        // `Stack {}.background(.accent)` snaps, with no diagnostic — spec §5's
        // own named hazard in its colour form, and CLAUDE.md's inert-table
        // shape.
        //
        // There is no `??` chain here because `Stack` paints
        // `decoration.background` alone: it registers no hitbox of its own for
        // `isHovered`/`isFocused` to key on, so `hoverBackground` and
        // `focusBackground` on a `Stack` are inert with or without this.
        if let color = animatedColor(decoration.background, for: id, pass: &pass) {
            pass.fill(bounds, color: color,
                      cornerRadii: Corners(all: decoration.cornerRadius))
        }
        content.paintGroup(layout: &layout.content,
                           prepaint: &prepaint, pass: &pass)
    }
}
