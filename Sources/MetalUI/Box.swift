import MetalUICore
import MetalUILayout

/// A flex container: one `Style`, one layout node, and its children.
///
/// **This is the whole of Task 4's contribution to layout, and it is where the
/// engine gets its first production caller.** `requestLayout` registers the
/// children's nodes bottom-up and then its own; `prepaint` reads each child's
/// resolved rect back out. Between the two, `Frame.computeRootLayout` runs the
/// flex engine — `Box` never calls it and cannot: `LayoutPass` exposes no way to.
///
/// `Box` paints nothing. Backgrounds, borders and corner radii are Task 5's;
/// what it carries today is layout only, which is why every modifier in
/// `StyledElement` maps to a `Style` property the engine actually reads.
///
/// `Column` and `Row` are this type with a `flexDirection` — see `Stack.swift`.
public struct Box<Content: ElementGroup>: Element, StyledElement {
    public var style: Style
    public var elementID: ElementID?
    public var content: Content

    /// The children as a value, for callers that already have a group.
    public init(style: Style = Style(), content: Content) {
        self.style = style
        self.content = content
    }

    public init(style: Style = Style(), @ElementBuilder content: () -> Content) {
        self.init(style: style, content: content())
    }

    /// Carried from `requestLayout` to the later phases.
    ///
    /// `node` is stored rather than re-derived because there is nothing to
    /// re-derive it from: `LayoutPass.requestNode` mints ids and hands them out
    /// once. `content` is the children's own threaded state.
    public struct Layout {
        public var node: LayoutNodeID
        var content: Content.GroupLayout
    }

    public mutating func requestLayout(_ id: GlobalElementID?,
                                       pass: inout LayoutPass) -> (LayoutNodeID, Layout) {
        // Children first: `requestNode` takes already-registered ids, so a
        // container builds bottom-up and the engine sees a complete subtree.
        let (children, contentLayout) = content.requestGroupLayout(under: id, pass: &pass)
        let node = pass.requestNode(style: style, children: children)
        return (node, Layout(node: node, content: contentLayout))
    }

    public mutating func prepaint(_ id: GlobalElementID?, bounds: Bounds<Pixels>,
                                  layout: inout Layout,
                                  pass: inout PrepaintPass) -> Content.GroupPrepaint {
        // `bounds` is this box's own rect and is deliberately not passed down:
        // the engine stores rects **absolute to the root**, so each child looks
        // its own up rather than being offset by its parent. Adding `bounds`
        // here would double-count every ancestor's origin.
        content.prepaintGroup(under: id, layout: &layout.content, pass: &pass)
    }

    public mutating func paint(_ id: GlobalElementID?, bounds: Bounds<Pixels>,
                               layout: inout Layout, prepaint: inout Content.GroupPrepaint,
                               pass: inout PaintPass) {
        content.paintGroup(under: id, layout: &layout.content,
                           prepaint: &prepaint, pass: &pass)
    }
}

extension Box where Content == EmptyGroup {
    /// A childless box — a sized leaf until M2 brings something to put in one.
    public init(style: Style = Style()) {
        self.init(style: style, content: EmptyGroup())
    }
}

extension Box {
    /// The main axis, and **`Box`'s alone**.
    ///
    /// It is not on `StyledElement` because `Column` and `Row` conform to that
    /// protocol: `Column { … }.flexDirection(.row)` would compile, keep its
    /// `Column<…>` type, and lay its children out horizontally — a type saying
    /// one thing while the style says another. Measured before this was moved:
    /// it did compile, and the second child landed at `x = 40`.
    ///
    /// `.rowReverse` and `.columnReverse` are reached here too; `Column` and
    /// `Row` choose their axis at construction and offer no way to change it.
    public func flexDirection(_ value: FlexDirection) -> Box<Content> {
        modifying { $0.flexDirection = value }
    }
}

// MARK: - Styling

/// An element whose layout inputs are a `Style` the caller may modify.
///
/// The modifiers live here rather than on each container so `Box`, `Column` and
/// `Row` share one definition, and every one of them returns `Self` — a
/// modified `Column<Pair<A, B>>` is still a `Column<Pair<A, B>>`, so §4.6's
/// mitigation 1 survives the chain.
///
/// **Every modifier below maps to a `Style` property the engine reads.** There
/// are deliberately none for `position`, `inset`, `overflow` or `aspectRatio`:
/// those four are CLAUDE.md's remaining inert rows, and a modifier for an inert
/// property is worse than no modifier, because from outside it is
/// indistinguishable from an implemented one. Two live properties are also
/// unreachable from here on purpose:
///
/// - **`margin`'s `.auto` case.** `margin(_:)` takes `Length`, not `Dimension`,
///   so `.auto` cannot be spelled through a modifier at all. It resolves to 0
///   rather than to CSS's "absorb the free space" — see CLAUDE.md — and this is
///   the one inert case a type can keep out of reach rather than document.
/// - **`baseline` alignment**, which falls back to `flexStart` until text
///   metrics exist. It *is* reachable, because `alignItems(_:)` takes the whole
///   enum; CLAUDE.md's row is the guard there, not the type.
@MainActor
public protocol StyledElement: Element {
    var style: Style { get set }
    var elementID: ElementID? { get set }
}

extension StyledElement {
    func modifying(_ change: (inout Style) -> Void) -> Self {
        var copy = self
        change(&copy.style)
        return copy
    }

    // MARK: Identity

    /// Names this element among its siblings, giving it and its subtree a
    /// `GlobalElementID` and therefore access to cross-frame state (§4.3).
    ///
    /// **Identity does not resume below an unnamed ancestor**: `child(of:_:)`
    /// returns `nil` when either end is anonymous, so naming a leaf under an
    /// unnamed container buys nothing. Name the container too.
    public func id(_ name: String) -> Self {
        var copy = self
        copy.elementID = ElementID(name)
        return copy
    }

    // MARK: Size

    public func width(_ points: Pixels) -> Self {
        modifying { $0.size.width = .length(.pixels(points)) }
    }

    public func height(_ points: Pixels) -> Self {
        modifying { $0.size.height = .length(.pixels(points)) }
    }

    /// A percentage of the **containing block's** corresponding axis.
    ///
    /// On the root this does not do what it says: `resolveRootSize` falls back
    /// to the offered space, so `width(percent: 50)` in an 800-wide window gives
    /// 800 where WebKit gives 400. CLAUDE.md carries the row.
    public func width(percent: Float) -> Self {
        modifying { $0.size.width = .length(.percent(percent)) }
    }

    /// See `width(percent:)` for the root-element caveat.
    public func height(percent: Float) -> Self {
        modifying { $0.size.height = .length(.percent(percent)) }
    }

    public func minWidth(_ points: Pixels) -> Self {
        modifying { $0.minSize.width = .length(.pixels(points)) }
    }

    public func minHeight(_ points: Pixels) -> Self {
        modifying { $0.minSize.height = .length(.pixels(points)) }
    }

    public func maxWidth(_ points: Pixels) -> Self {
        modifying { $0.maxSize.width = .length(.pixels(points)) }
    }

    public func maxHeight(_ points: Pixels) -> Self {
        modifying { $0.maxSize.height = .length(.pixels(points)) }
    }

    // MARK: Box model (spec §5.2 — border-box, so these sit *inside* the size)

    public func padding(_ points: Pixels) -> Self {
        modifying { $0.padding = Edges(all: .pixels(points)) }
    }

    public func padding(_ edges: Edges<Length>) -> Self {
        modifying { $0.padding = edges }
    }

    /// Item margins. Takes `Length`, so `.auto` is unspellable — see
    /// `StyledElement`'s note.
    public func margin(_ points: Pixels) -> Self {
        modifying { $0.margin = Edges(all: .length(.pixels(points))) }
    }

    /// See `margin(_:)` — `.auto` is deliberately out of reach.
    public func margin(_ edges: Edges<Length>) -> Self {
        modifying {
            $0.margin = Edges(top: .length(edges.top), right: .length(edges.right),
                              bottom: .length(edges.bottom), left: .length(edges.left))
        }
    }

    /// Border **width**, which is layout. Border colour is paint and arrives
    /// with Task 5.
    public func borderWidth(_ points: Pixels) -> Self {
        modifying { $0.border = Edges(all: .pixels(points)) }
    }

    public func borderWidth(_ edges: Edges<Length>) -> Self {
        modifying { $0.border = edges }
    }

    // MARK: As a flex container

    public func gap(_ points: Pixels) -> Self {
        modifying { $0.gap = Axes(both: .pixels(points)) }
    }

    public func gap(horizontal: Pixels, vertical: Pixels) -> Self {
        modifying { $0.gap = Axes(horizontal: .pixels(horizontal), vertical: .pixels(vertical)) }
    }

    public func justifyContent(_ value: JustifyContent) -> Self {
        modifying { $0.justifyContent = value }
    }

    /// `.baseline` lays out as `.flexStart` until text metrics exist — the one
    /// case of this enum that does not do what it says. CLAUDE.md carries it.
    public func alignItems(_ value: AlignItems) -> Self {
        modifying { $0.alignItems = value }
    }

    public func alignContent(_ value: AlignContent) -> Self {
        modifying { $0.alignContent = value }
    }

    public func flexWrap(_ value: FlexWrap) -> Self {
        modifying { $0.flexWrap = value }
    }

    // MARK: As a flex item

    public func flexGrow(_ value: Float) -> Self {
        modifying { $0.flexGrow = value }
    }

    public func flexShrink(_ value: Float) -> Self {
        modifying { $0.flexShrink = value }
    }

    public func flexBasis(_ points: Pixels) -> Self {
        modifying { $0.flexBasis = .length(.pixels(points)) }
    }

    public func flexBasis(percent: Float) -> Self {
        modifying { $0.flexBasis = .length(.percent(percent)) }
    }

    /// `.baseline` lays out as `.flexStart` — see `alignItems(_:)`.
    public func alignSelf(_ value: AlignSelf) -> Self {
        modifying { $0.alignSelf = value }
    }

    // MARK: Participation

    /// `display: none` — the element and its subtree contribute no box.
    ///
    /// It still runs all three phases and still registers its nodes; the engine
    /// filters it out of its parent's item list, so its rect stays at the zero
    /// `LayoutTree` initialised it with.
    public func hidden() -> Self {
        modifying { $0.display = .none }
    }
}
