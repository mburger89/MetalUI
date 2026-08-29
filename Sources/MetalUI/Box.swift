import MetalUICore
import MetalUILayout

/// A flex container: one `Style`, one layout node, and its children.
///
/// **This is where the engine gets its first production caller.**
/// `requestLayout` registers the children's nodes bottom-up and then its own;
/// `prepaint` reads each child's resolved rect back out. Between the two,
/// `Frame.computeRootLayout` runs the flex engine — `Box` never calls it and
/// cannot: `LayoutPass` exposes no way to.
///
/// `Box` carries two independent groups of properties, and the split is the
/// point: `style` is what the flex engine reads, `decoration` is what `paint`
/// reads. They are separate because `Style` lives in `MetalUILayout`, which
/// imports only `MetalUICore` and has no colour field of any kind — a
/// background token could not be put there without giving the layout engine a
/// dependency on the theme.
///
/// **Backgrounds and corner radii landed in Task 5; borders did not.** That
/// sentence used to read "Backgrounds, borders and corner radii are Task 5's",
/// and the border half of it is now false: `Frame.fill` emits
/// `borderColor: .transparent` and offers no way to change it. The mechanism is
/// recorded there — paint has no *resolved* border width to pair a colour with,
/// because the engine computes one inside `contentBox` and does not store it.
///
/// `Column` and `Row` are this type with a `flexDirection` — see `Flex.swift`.
/// (That file was called `Stack.swift` until the stack-container milestone gave
/// the name to the `Stack` element and renamed this one for what it holds.)
public struct Box<Content: ElementGroup>: Element, StyledElement {
    public var style: Style
    public var decoration: Decoration
    public var elementID: ElementID?
    public var content: Content

    /// The children as a value, for callers that already have a group.
    public init(style: Style = Style(), decoration: Decoration = Decoration(),
                content: Content) {
        self.style = style
        self.decoration = decoration
        self.content = content
    }

    public init(style: Style = Style(), decoration: Decoration = Decoration(),
                @ElementBuilder content: () -> Content) {
        self.init(style: style, decoration: decoration, content: content())
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
        let node = pass.requestNode(style: style, children: children)
        return (node, Layout(node: node, content: contentLayout))
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout Layout,
                                  pass: inout PrepaintPass) -> Content.GroupPrepaint {
        // `bounds` is this box's own rect and is deliberately not passed down:
        // the engine stores rects **absolute to the root**, so each child looks
        // its own up rather than being offset by its parent. Adding `bounds`
        // here would double-count every ancestor's origin.
        content.prepaintGroup(layout: &layout.content, pass: &pass)
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout Layout, prepaint: inout Content.GroupPrepaint,
                               pass: inout PaintPass) {
        // Own background first, then children. Every rect is emitted at
        // `order: 0` and `Scene.finalize()` sorts stably, so emission sequence
        // *is* paint order — a container that emitted after its children would
        // paint over them. Reversing these two lines is caught by
        // `aContainerPaintsItsBackgroundBeneathItsChildren`.
        if let token = decoration.background {
            pass.fill(bounds, color: pass.theme[token],
                      cornerRadii: Corners(all: decoration.cornerRadius))
        }
        content.paintGroup(layout: &layout.content,
                           prepaint: &prepaint, pass: &pass)
    }
}

extension Box where Content == EmptyGroup {
    /// A childless box — a sized leaf, and a **0x0** one unless its style says
    /// otherwise: it reports no content size of its own, because it registers
    /// through `requestNode` rather than `requestLeaf`.
    ///
    /// That sentence used to end "…the framework has no leaf that reports a
    /// content size, because `newLeaf` has no production caller". `Text`
    /// (M2 Task 4) is that caller, so the framework does have one now — it is
    /// simply not this type. A `Box` that should size to something must be
    /// given a size or given children.
    public init(style: Style = Style(), decoration: Decoration = Decoration()) {
        self.init(style: style, decoration: decoration, content: EmptyGroup())
    }
}

extension Box {
    /// The main axis, and **`Box`'s alone**.
    ///
    /// It is not on `StyledElement` because `Column`, `Row` and `Stack` all
    /// conform to that protocol: `Column { … }.flexDirection(.row)` would
    /// compile, keep its `Column<…>` type, and lay its children out
    /// horizontally — a type saying one thing while the style says another.
    /// Measured before this was moved: it did compile, and the second child
    /// landed at `x = 40`. `Stack` joined the list in the stack-container
    /// milestone and makes the argument stronger rather than weaker: a
    /// `flexDirection` on a `display: .stack` node is read by nothing at all
    /// (`layOutStack` never consults it), so the modifier would be inert there
    /// as well as misleading.
    ///
    /// `.rowReverse` and `.columnReverse` are reached here too; `Column` and
    /// `Row` choose their axis at construction and offer no way to change it.
    public func flexDirection(_ value: FlexDirection) -> Box<Content> {
        modifying { $0.flexDirection = value }
    }
}

// MARK: - Styling

/// What a styled element paints for itself, as opposed to what it lays out
/// (spec §7.9).
///
/// **`background` is a `ColorToken`, never an `Hsla`.** §7.9: "Colors in
/// element code are semantic tokens … never literals." Resolution happens once
/// per frame, in `paint`, against `PaintPass.theme` — which is what makes a
/// theme swap a repaint rather than a rebuild of every element value.
///
/// `nil` means "paint nothing here", which is not the same as any colour: a
/// fully transparent background would still emit a rect, and rects are what the
/// renderer's per-frame budget is spent on.
///
/// **There is no `borderColor`, deliberately.** See `Frame.fill` for the
/// mechanism — the resolved border width does not survive the engine, so a
/// colour would have nothing to be drawn at.
public struct Decoration: Sendable, Hashable {
    public var background: ColorToken?
    public var cornerRadius: Pixels

    public init(background: ColorToken? = nil, cornerRadius: Pixels = Pixels(0)) {
        self.background = background
        self.cornerRadius = cornerRadius
    }
}

/// An element whose layout inputs are a `Style` the caller may modify.
///
/// The modifiers live here rather than on each container so `Box`, `Column`,
/// `Row` and `Stack` share one definition, and every one of them returns
/// `Self` — a modified `Column<Pair<A, B>>` is still a `Column<Pair<A, B>>`, so
/// §4.6's mitigation 1 survives the chain.
///
/// **Not every modifier means something on every conformer**, and the list
/// above is where that starts to bite. `Stack` conforms as of the
/// stack-container milestone, and `flexGrow`/`flexShrink`/`flexBasis` are inert
/// on it (there is no main axis) while `alignSelf` is inert on its *children*
/// — see `Display.stack`'s own doc comment for the mechanism in each case.
///
/// **Every modifier below maps to a `Style` property the engine reads.** There
/// are deliberately none for `overflow` or `aspectRatio`: those two are
/// CLAUDE.md's remaining inert rows, and a modifier for an inert property is
/// worse than no modifier, because from outside it is indistinguishable from an
/// implemented one. `position` and `inset` were on that list until the engine
/// read them; they gained `position(_:)`/`inset(_:)` in the same change that
/// deleted their rows, which is ruling AL-6's rule running in the other
/// direction. Two live properties are also unreachable from here on purpose:
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
    var decoration: Decoration { get set }
    var elementID: ElementID? { get set }
}

extension StyledElement {
    func modifying(_ change: (inout Style) -> Void) -> Self {
        var copy = self
        change(&copy.style)
        return copy
    }

    func decorating(_ change: (inout Decoration) -> Void) -> Self {
        var copy = self
        change(&copy.decoration)
        return copy
    }

    // MARK: Identity

    /// Names this element among its siblings, **replacing** the position it
    /// would otherwise be identified by (§4.3).
    ///
    /// It does not *create* identity — every element has one. What a name buys
    /// is stability under a change of position: an unnamed element's identity is
    /// its index in its container's flat child list, so inserting a sibling
    /// above it or reordering a list resets its cross-frame state, and a name
    /// carries that state with the element instead. Naming a leaf under an
    /// unnamed container is therefore useful on its own — identity no longer
    /// stops at an unnamed ancestor, and the ancestor's own positional
    /// component is still part of the leaf's path.
    public func id(_ name: String) -> Self {
        var copy = self
        copy.elementID = ElementID(name)
        return copy
    }

    // MARK: Paint (spec §7.9)

    /// Fills this element's border box with a **semantic token**, resolved
    /// against the frame's theme when `paint` runs.
    ///
    /// There is no `Hsla` overload. A literal colour would paint identically in
    /// both appearances while looking exactly like a themed one at the call
    /// site, which is §7.9's whole objection to literals.
    public func background(_ token: ColorToken) -> Self {
        decorating { $0.background = token }
    }

    /// Rounds all four corners of the background by the same radius.
    ///
    /// **Paint only — it does not affect layout or clip the children.** The
    /// engine has no corner-radius input (`Style` carries none), and `Box`
    /// itself never calls `PaintPass.clipped(to:offsetBy:cornerRadii:)` — it
    /// has no clip of its own at all, rounded or square, so a child painted
    /// into its corner shows square regardless of this radius. **This is no
    /// longer because the clip stack cannot carry a radius** — ruling CL-A's
    /// follow-on gave it one, and `ScrollView.cornerRadius(_:)` is the one
    /// production caller that uses it, rounding the clip it pushes around its
    /// own content. `Box` simply pushes no clip for this radius to round;
    /// wiring one in is a `Box`-specific follow-on, not a stack limitation.
    public func cornerRadius(_ points: Pixels) -> Self {
        decorating { $0.cornerRadius = points }
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

    /// Border **width**, which is layout. **There is no border colour anywhere
    /// in the framework**, so a border width changes where the children sit and
    /// draws nothing: `Frame.fill` emits `borderColor: .transparent` and
    /// `borderWidths: 0` unconditionally, and the blocker recorded there is the
    /// *resolved width*, not the colour — the engine computes it inside
    /// `contentBox` and discards it rather than storing it on the node.
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

    // MARK: Out of flow

    /// Whether this box participates in its container's flow, and whether it is
    /// the containing block its absolutely-positioned descendants are placed
    /// against.
    ///
    /// `.absolute` removes the box from both collection sites, so it contributes
    /// nothing to its container's measured size, and places it by `inset(_:)`
    /// against the nearest ancestor whose position is not `.static` — the root
    /// when there is none, which is what makes "positioned against the window"
    /// spellable from anywhere in the tree.
    ///
    /// **`.relative` is half-implemented and this modifier is what makes that
    /// reachable.** It does make a box a containing block, which is its whole
    /// purpose here; it does *not* shift the box by its own inset the way CSS
    /// does. CLAUDE.md carries the row, on the same footing as `.baseline` on
    /// `alignItems(_:)`.
    public func position(_ value: Position) -> Self {
        modifying { $0.position = value }
    }

    /// The four offsets an `.absolute` box is placed by, against its containing
    /// block. Inert on a `.static` or `.relative` box, exactly as in CSS.
    ///
    /// Takes `Dimension` rather than `Length`, unlike `margin(_:)`, because
    /// `.auto` is this property's default and its meaning is defined: an axis
    /// with neither inset given sizes to its own content and sits at the
    /// containing block's origin. **That last part diverges from CSS**, which
    /// uses the box's static position instead — CLAUDE.md's divergence 9.
    ///
    /// Percentages resolve **per axis**: `left`/`right` against the containing
    /// block's width, `top`/`bottom` against its height. This is not the
    /// padding/border rule, where CSS resolves every percentage against width.
    public func inset(_ edges: Edges<Dimension>) -> Self {
        modifying { $0.inset = edges }
    }

    /// The same offset on all four edges. `inset(Pixels(0))` on an `auto`-sized
    /// box fills its containing block, since each axis then stretches between
    /// its two given insets.
    public func inset(_ points: Pixels) -> Self {
        modifying { $0.inset = Edges(all: .length(.pixels(points))) }
    }

    // MARK: Participation

    /// `display: none` — the element and its subtree contribute no box.
    ///
    /// It still runs all three phases and still registers its nodes; the engine
    /// filters it out of its parent's item list, so its rect stays at the zero
    /// `LayoutTree` initialised it with.
    ///
    /// **This is a LAYOUT modifier and paint does not honour it. A hidden
    /// subtree containing a `Text` still emits glyphs, at the surface's own
    /// origin.** Nothing in `Sources/MetalUI` reads `Style.display` during
    /// paint: `Box.paint` fills its bounds and recurses into
    /// `content.paintGroup` unconditionally, so a hidden `Box`'s own fill is
    /// harmlessly degenerate (a zero-size rect) while its children paint from
    /// the zero rect's origin — which, a hidden node never having been placed,
    /// is `(0, 0)` in surface coordinates rather than anywhere near where the
    /// element was written. `Text.paint` then re-shapes at
    /// `max(bounds.width, smallestWrapWidth)`, and `smallestWrapWidth` is 0.5,
    /// so the string wraps after **every character** and stacks one glyph per
    /// line down the window's left edge.
    ///
    /// Measured, not read: `Column { Box { Text("Hi") }.width(80).height(20).hidden(); … }`
    /// in a 400×300 frame emits the expected zero rect **and two glyphs**, at
    /// `(0, 2)` and `(−1, 18)` — the second negative in x, its left side
    /// bearing carrying it outside the surface entirely.
    ///
    /// So `hidden()` is safe on a subtree of `Box`es and wrong on anything that
    /// draws its own content. Use a conditional in the `@ElementBuilder` block
    /// instead — `if showIt { … }` — which removes the element from the tree
    /// rather than from the item list; `Sources/MetalUIDemo/main.swift`'s modal
    /// does exactly that, and carries the vanishing-`if` identity caveat at its
    /// call site. CLAUDE.md's declared-but-inert table has the row.
    public func hidden() -> Self {
        modifying { $0.display = .none }
    }
}
