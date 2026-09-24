import MetalUICore
import MetalUILayout
import MetalUIPlatform

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
/// **Backgrounds and corner radii landed in the M1 Task 5; borders landed in
/// plan task 5's lane 2** (rulings `OM-B`, `OM-M`). This comment said "borders
/// did not" and named `Frame.fill`'s hard-coded `borderColor: .transparent` as
/// the reason — which was a statement about a width derived from
/// `Style.border`, whose percentage case only the engine can resolve.
/// `Decoration.border` declares its widths in `Pixels` instead, so there is
/// nothing to resolve and the blocker does not apply; the layout-affecting
/// `borderWidth(_:)` modifier is deleted rather than kept beside it.
///
/// `Column` and `Row` are this type with a `flexDirection` — see `Flex.swift`.
/// (That file was called `Stack.swift` until the stack-container milestone gave
/// the name to the `Stack` element and renamed this one for what it holds.)
public struct Box<Content: ElementGroup>: Element, StyledElement {
    public var style: Style
    public var decoration: Decoration
    public var elementID: ElementID?
    public var handlers: Handlers
    public var content: Content

    /// The children as a value, for callers that already have a group.
    ///
    /// `handlers` is deliberately **not** an `init` parameter, on
    /// `elementID`'s footing: `onClick(_:)` is the one spelling, so there is a
    /// single place a handler can be attached and a single place to look for
    /// one.
    public init(style: Style = Style(), decoration: Decoration = Decoration(),
                content: Content) {
        self.style = style
        self.decoration = decoration
        self.handlers = Handlers()
        self.content = content
    }

    public init(style: Style = Style(), decoration: Decoration = Decoration(),
                @ElementBuilder content: () -> Content) {
        self.init(style: style, decoration: decoration, content: content())
    }

    /// Carried from `requestLayout` to the later phases.
    ///
    /// `node` is stored rather than re-derived because there is nothing to
    /// re-derive it from: the registrar (`Frame.requestNode`, or the lowering's
    /// outermost kernel node under the proposal authority, ruling LR-A) mints ids
    /// and hands them out once. `content` is the children's own threaded state.
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
        // M4 spec 3 §5: substitutes any animatable field mid-transition,
        // storing the result back on `self` — `paint` reads `self.decoration`
        // later in this same frame, so this is what makes `cornerRadius`
        // animation (and any other decoration field this helper animates)
        // reach the screen rather than only the layout node.
        let declared = style
        (style, decoration) = animated(style, decoration, for: id, pass: &pass)
        // The site's own authority check (plan task 7, ruling LR-C). Under the
        // proposal authority the (animated) style is lowered onto kernel nodes;
        // the checks read the declared one (`LegacyLowering.swift`). A childless
        // `Box` lowers since lane 2, a `Box` with children — and so `Row` and
        // `Column` — since lane 3; a field outside the lowering table traps by
        // name, or is reported with a 0×0 native leaf in its place under
        // diagnostics.
        let node = pass.lowersToProposal
            ? pass.lowerLegacyNode(style, declared: declared, children: children, site: .box)
            : pass.frame.requestNode(style: style, children: children)
        return (node, Layout(node: node, content: contentLayout))
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout Layout,
                                  pass: inout PrepaintPass) -> Content.GroupPrepaint {
        // Before the children, so a child's own click target registers LATER
        // and therefore ranks above this one — `topmostOpaqueHitbox` breaks a
        // layer tie by registration index, and a child paints over its parent.
        // The hitbox is a no-op unless `onClick(_:)` was called. The same call
        // registers focus and emits a declared `handlers.axNode` — see
        // `Frame.registerHandlers`, which holds all three gates so that `Box`,
        // `Stack` and `Text` cannot disagree about any of them.
        //
        // Through `registerAndScope` since plan task 5's lane 2, because a
        // `Decoration` now carries a SCOPE (`clipsContent`) as well as fields
        // that only ever produced one emission — see `DecorationScope.swift`.
        //
        // `bounds` is this box's own rect and is deliberately not passed down to
        // the children: the engine stores rects **absolute to the root**, so
        // each child looks its own up rather than being offset by its parent.
        // Adding `bounds` here would double-count every ancestor's origin.
        return pass.registerAndScope(handlers, decoration, at: bounds, for: id) {
            content.prepaintGroup(layout: &layout.content, pass: &pass)
        }
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout Layout, prepaint: inout Content.GroupPrepaint,
                               pass: inout PaintPass) {
        // Own background first, then children. Every rect is emitted at
        // `order: 0` and `Scene.finalize()` sorts stably, so emission sequence
        // *is* paint order — a container that emitted after its children would
        // paint over them. Reversing these two lines is caught by
        // `aContainerPaintsItsBackgroundBeneathItsChildren`.
        //
        // The pointer and keyboard states are consulted inside
        // `animatedBackground(_:for:pass:)`, which resolves the
        // `focusBackground ?? hoverBackground ?? background` chain and animates
        // the one resulting value. It is shared with `Stack.paint` and
        // `Text.paint` — see its doc for the precedence and why only the
        // element-keyed `isHovered` overload is reachable from here.
        //
        // **All four of those calls now go through `paintDecoration`** (plan
        // task 5, lane 2): the background is still emitted first and the
        // children still follow it, but the border is a SECOND emission after
        // them (`OM-V` — SwiftUI's `.border` is an overlay), and opacity and
        // the clip are scopes rather than emissions, so they have to wrap the
        // recursion rather than precede it.
        pass.paintDecoration(decoration, in: bounds, for: id) {
            content.paintGroup(layout: &layout.content,
                               prepaint: &prepaint, pass: &pass)
        }
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
/// **A border IS reachable as of plan task 5** (rulings `OM-B`, `OM-M`), and
/// this doc said it was not. The blocker `Frame.fill` records is a *resolved
/// width derived from `Style.border`* — an `Edges<Length>` whose percentage
/// case has to resolve against the containing block's width, which the engine
/// computes inside `contentBox` and then discards. `BorderStyle` below declares
/// its widths in `Pixels`, which have nothing to resolve, so that blocker does
/// not apply to it. The layout-affecting `borderWidth(_:)` modifier that wrote
/// `Style.border` is deleted (`OM-M`); `Style.border` itself stays, engine-side
/// and reachable only through `Box(style:)`.
public struct Decoration: Sendable, Hashable {
    public var background: ColorToken?
    public var cornerRadius: Pixels

    /// The background to paint instead of `background` while the pointer is
    /// over this element, or `nil` to paint `background` either way.
    ///
    /// **A token swap was the whole of what this framework could express for a
    /// pointer state, and that sentence is now false** (`OM-B`, `OM-L`):
    /// `hoverBorder` and `focusBorder` below are the ring, resolved through the
    /// same precedence by the same helper. A caller who wants a ring no longer
    /// nests two filled boxes. This field is unchanged and is still the right
    /// spelling for a hover *fill*.
    ///
    /// **`nil` is not "no hover", it is "no hover *paint*".** Hover is resolved
    /// for every element that registers a hitbox whether or not it declares one
    /// of these; this field only says whether the resolved answer changes what
    /// is drawn.
    public var hoverBackground: ColorToken?

    /// The background to paint instead of `background` — and instead of
    /// `hoverBackground` — while this element holds keyboard focus.
    ///
    /// **Focus outranks hover when both are declared and both are true**, and
    /// it is a decision rather than an ordering accident: hover follows the
    /// pointer and a user recovers it by moving, focus is where the keyboard is
    /// pointing and has no other indication. Reversing the two makes a focused
    /// element lose its only affordance whenever the pointer happens to rest on
    /// it — which is exactly when a user is about to type.
    /// `animatedBackground(_:for:pass:)` is the one site (shared by `Box`,
    /// `Stack` and `Text`); `focusOutranksHoverWhenAnElementIsBoth` pins it on
    /// `Box` and `everyBackgroundPaintingSiteHonoursHoverAndFocus` on all three.
    public var focusBackground: ColorToken?

    // MARK: Plan task 5, lane 2 — appended, never reordered

    /// The border to draw inside this element's own box, or `nil` to draw none.
    ///
    /// **Paint-only, and drawn INSIDE the box**, which is where SwiftUI's
    /// `.border` draws (probe `swiftui-border-clip-paint` B1/B2: the border
    /// colour at (1, 1) and (3, 3), the content at (6, 6) on a 40x40 at width
    /// 4) and what `MUIRect.borderWidths` already means to the fragment shader.
    /// It contributes no layout node and moves no number, as SwiftUI's does not
    /// (probe `swiftui-outer-modifier-order` L2).
    ///
    /// **It is emitted AFTER the children, not before them** (`OM-V`).
    /// SwiftUI's `.border` is an overlay — a child filling the whole box does
    /// not hide it (probe arm B3) — and MetalUI's children live inside the same
    /// box the border is drawn inside, so a single emission before them would
    /// be covered by any filling child. That would make `focusBorder` invisible
    /// on the exact call it exists for. `paintDecoration(_:in:for:pass:content:)`
    /// is the one site.
    public var border: BorderStyle?

    /// The border to draw instead of `border` while the pointer is over this
    /// element. `nil` means "no hover *border*", exactly as `hoverBackground`'s
    /// `nil` means no hover fill, and it needs an `onClick` for the same reason.
    public var hoverBorder: BorderStyle?

    /// **The focus ring** (`OM-L`): the border to draw instead of `border` —
    /// and instead of `hoverBorder` — while this element holds keyboard focus.
    ///
    /// Focus outranks hover, the same precedence `focusBackground` states one
    /// field up, and it is stated once rather than twice:
    /// `resolvedBorder(_:for:pass:)` and `animatedBackground(_:for:pass:)` share
    /// `effectiveForPointerState(_:_:_:for:pass:)`, so the two chains cannot
    /// drift apart.
    ///
    /// The ring is drawn **inside** the element's box, because that is the only
    /// border geometry the renderer has. AppKit's own focus ring is a halo
    /// *outside* the control's bounds; MetalUI's is not, and that is a recorded
    /// difference rather than a claim about SwiftUI — SwiftUI exposes no
    /// focus-ring drawing for an arbitrary view at all, so there is nothing to
    /// probe. What was probed is that focus changes no layout
    /// (`swiftui-outer-modifier-order` L8), which is the property a ring must
    /// not violate.
    ///
    /// It needs `focusable()` AND something to move focus, on
    /// `focusBackground`'s footing: clicking does not focus.
    public var focusBorder: BorderStyle?

    /// Multiplies the opacity of everything this element paints — its own
    /// background and border included — and of everything inside it.
    ///
    /// **`private(set)`** (`OM-Y`): `Decoration` is public and reachable through
    /// `Box(style:decoration:)`, so a plain stored `var` would let
    /// `d.opacity = 2` reach `PaintPass.opacity`'s `precondition((0...1))` far
    /// from the call site that wrote it, or multiply the frame's opacity above
    /// 1 when it never reaches that precondition at all. Set it through
    /// `setOpacity(_:)` or the memberwise `init` below, both of which trap
    /// outside `0...1`.
    ///
    /// **The scope includes this element's own fill** (`OM-N`), so
    /// `.background(x).opacity(0.5)` fades the panel — SwiftUI's G3, agreeing —
    /// and `.opacity(0.5).background(x)` fades it too, where SwiftUI's G4 leaves
    /// a background written after an opacity opaque. Both are fields of one
    /// `Decoration`, so only one of the two orders can be right; the one a
    /// caller actually writes was chosen. Recorded divergence, and the
    /// **proposal** path already answers the second order SwiftUI's way
    /// (`OM-AA` a), so the two paths disagree with each other as well.
    ///
    /// **One field, so a second `.opacity(_:)` on the same element REPLACES the
    /// first rather than multiplying into it** (`OM-AH`) — the same mechanism
    /// once more. `Frame.activeOpacity` multiplies *scopes*, and this field
    /// contributes exactly one.
    public private(set) var opacity: Float

    /// Whether this element clips what it contains to its own box, rounded by
    /// `cornerRadius`.
    ///
    /// **Separate from `cornerRadius`, deliberately** (`OM-G`). SwiftUI's
    /// `.cornerRadius` clips its content; MetalUI's rounds a fill and clips
    /// nothing, and making it clip would change all sixteen of the demo's
    /// `cornerRadius` call sites as a side effect of an audit.
    /// `.cornerRadius(12).clipped()` is the spelling for SwiftUI's
    /// `.cornerRadius(12)`.
    ///
    /// The clip is pushed in **both** prepaint and paint, as `ScrollView` does,
    /// so a hitbox inside a clipped box is registered against the clip rather
    /// than escaping it.
    public var clipsContent: Bool

    /// Traps outside `0...1`, so the failure names the assignment rather than
    /// the `pass.opacity` call a frame later. See `opacity`.
    public mutating func setOpacity(_ value: Float) {
        Self.validateOpacity(value)
        opacity = value
    }

    static func validateOpacity(_ value: Float) {
        precondition(value.isFinite && (0...1).contains(value),
                     "opacity must be a finite value in 0...1, got \(value)")
    }

    public init(background: ColorToken? = nil, cornerRadius: Pixels = Pixels(0),
                hoverBackground: ColorToken? = nil,
                focusBackground: ColorToken? = nil,
                border: BorderStyle? = nil,
                hoverBorder: BorderStyle? = nil,
                focusBorder: BorderStyle? = nil,
                opacity: Float = 1,
                clipsContent: Bool = false) {
        Self.validateOpacity(opacity)
        self.background = background
        self.cornerRadius = cornerRadius
        self.hoverBackground = hoverBackground
        self.focusBackground = focusBackground
        self.border = border
        self.hoverBorder = hoverBorder
        self.focusBorder = focusBorder
        self.opacity = opacity
        self.clipsContent = clipsContent
    }
}

/// A paint-only border: a semantic colour and four widths in points.
///
/// **The widths are `Pixels`, not `Length`, and that is what makes this cheap**
/// (`OM-B`). A `Length` percentage resolves against the containing block's
/// width, which only the engine knows and which it discards; points resolve
/// against nothing, so paint can pair a colour with a width without the
/// `LayoutTree` plumbing `Frame.fill`'s doc names as the blocker.
///
/// **`widths` is `public private(set)`** (`OM-Y`). A negative width reaches
/// `max(halfSize - border, 0.0)` in the fragment shader
/// (`shaders.metal:129-133`) and produces an inner rect LARGER than the outer
/// one, with no diagnostic anywhere above it. Every WRITE is validated, not
/// only every `init` — a public stored `var` beside a validating initializer is
/// a door beside an open window. `withWidths(_:)` is the only other way in, and
/// it validates identically.
public struct BorderStyle: Sendable, Hashable {
    /// Resolved once per frame against `PaintPass.theme`, exactly as
    /// `Decoration.background` is: a border is a semantic token, never a
    /// literal (spec §7.9).
    public var color: ColorToken

    /// Points, drawn inside the element's box. See this type's doc for why the
    /// setter is private.
    public private(set) var widths: Edges<Pixels>

    /// Traps on a negative or non-finite width. Pinned by an exit test.
    public init(_ color: ColorToken, width: Pixels) {
        self.init(color, widths: Edges(all: width))
    }

    /// Traps on a negative or non-finite width on any edge.
    public init(_ color: ColorToken, widths: Edges<Pixels>) {
        Self.validate(widths)
        self.color = color
        self.widths = widths
    }

    /// The only other way to set `widths`; validates identically.
    public func withWidths(_ widths: Edges<Pixels>) -> BorderStyle {
        BorderStyle(color, widths: widths)
    }

    static func validate(_ widths: Edges<Pixels>) {
        for (edge, value) in [("top", widths.top), ("right", widths.right),
                              ("bottom", widths.bottom), ("left", widths.left)] {
            precondition(value.value.isFinite && value.value >= 0,
                         "border width must be finite and non-negative, got \(value.value) on \(edge)")
        }
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

    /// The input callbacks this element asked for — see `Handlers`.
    ///
    /// **A requirement rather than a defaulted extension property, and the
    /// difference is a silent bug.** A default of `{ get { Handlers() } set {} }`
    /// would let a conformer that stores nothing compile, and `.onClick { … }`
    /// on it would then return an element with the handler thrown away: an API
    /// that exists, compiles and does nothing, which is the exact shape
    /// CLAUDE.md's declared-and-inert table exists to keep out of this
    /// framework. Requiring it makes a forgetful conformer a compile error.
    ///
    /// Storing it is still only half the job — a conformer must also call
    /// `PrepaintPass.registerHandlers(_:at:id:)` in its own `prepaint`, and
    /// nothing can enforce *that*. `onClickIsLiveOnEveryConformerThatCanRegisterOne`
    /// is the guard, one case per conformer.
    var handlers: Handlers { get set }
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

    func handling(_ change: (inout Handlers) -> Void) -> Self {
        var copy = self
        change(&copy.handlers)
        return copy
    }

    // MARK: Input (design spec §3.5)

    /// Runs `handler` when this element is clicked — pressed **and** released
    /// on this same element, with the pointer free to leave and return in
    /// between.
    ///
    /// **This is what makes an element a hit target.** A `Box` with no handler
    /// registers no hitbox at all, so it is transparent to the pointer and,
    /// more sharply, does not swallow the wheel of a `ScrollView` it sits
    /// inside. Adding a handler flips both: the element registers an **opaque**
    /// hitbox at its own bounds, so it also shadows whatever it covers.
    ///
    /// **The one cost that will surprise a reader who knows a browser**: an
    /// `onClick` inside a `ScrollView` swallows that scroller's wheel over its
    /// own rect, because a wheel event stops at the topmost opaque hitbox and
    /// scrolls only if that hitbox is itself a scroller. Accepted deliberately
    /// — non-opaque would stop a modal scrim swallowing clicks aimed at what is
    /// under it, which is worse — and pinned by
    /// `aClickTargetInsideAScrollViewSwallowsTheWheel`. The named fix is at
    /// `Window.applyScroll`.
    ///
    /// **Bubble-only, and there is no chaining**: a click resolves to one
    /// hitbox and stops, so an `onClick` on a container never sees a click that
    /// landed on a child with its own. See `Handlers`.
    ///
    /// **A second `onClick` REPLACES the first**, exactly as a second
    /// `background(_:)` does — `.onClick { a }.onClick { b }` runs only `b` and
    /// registers one hitbox. Said out loud because the name sounds additive in
    /// a way the other modifiers do not, and nothing diagnoses the misreading.
    ///
    /// **What `handler` captures outlives the frame that built it, so do not
    /// close over the `Window`.** The handler is stored on the `Hitbox` this
    /// element registers, and `Window.lastHitboxes` keeps the most recent
    /// frame's records for as long as the window lives — nothing clears it. So
    /// `.onClick { window.doThing() }` is a retain cycle: `Window` →
    /// `lastHitboxes` → the closure → `Window`. Nothing inside the framework
    /// closes one (`lastHitboxes = frame.hitboxes` copies an array of structs
    /// and retains no `Frame`), and only a *caller* can create one. The remedy
    /// is the ordinary one — capture `[weak window]`, or capture the piece of
    /// state the handler actually writes rather than the window that owns it,
    /// which is what `@State` is for and what a handler should almost always
    /// be doing instead.
    public func onClick(_ handler: @escaping @MainActor () -> Void) -> Self {
        handling { $0.onClick = handler }
    }

    // MARK: Focus (design spec §4.2)

    /// Lets this element **hold** keyboard focus.
    ///
    /// **It does not take focus, and nothing in this framework takes it for
    /// you.** Focus moves only through `Window.focus(_:)`; clicking a focusable
    /// element does *not* focus it, because focus-by-click is a policy decision
    /// this framework has not made. What this modifier buys is eligibility: a
    /// focused id that is not registered as focusable on a given frame is
    /// **cleared** at that frame's prepaint/paint boundary
    /// (`Frame.resolveFocus()`), so without this, focus set on an element
    /// evaporates on the next frame.
    ///
    /// **It is NOT a pointer hit target**, unlike `onClick(_:)`: a focusable
    /// element registers no hitbox, so it stays transparent to the pointer and
    /// does not swallow the wheel of a `ScrollView` it sits inside. That
    /// separation is the reason `Handlers` carries two gates rather than one.
    ///
    /// **A focus ring is yours to draw.** Nothing here paints one — read
    /// `PaintPass.isFocused(_:)` from an element's own `paint`. There is no
    /// focus ring in the framework at all today, which is why the milestone's
    /// human look asks specifically whether focus is *visible*.
    ///
    /// **`.hidden()` does NOT hide an element from focus, and the consequence
    /// is keystrokes vanishing into something nobody can see.** Measured
    /// through a real `Window`: a `.focusable().onKey { … }.hidden()` box
    /// registers as focusable, `Window.focus(_:)` on it sticks, it **claims**
    /// the keystroke so `Window.onInput` never sees it, and it keeps focus
    /// across the next frame — `Frame.resolveFocus()` cannot clear it, because
    /// the element's `prepaint` really did run and really did register.
    ///
    /// **The pointer side is protected and this is not, which is the part that
    /// surprises.** A hidden `onClick` box registers a hitbox at `(0, 0) 0×0`
    /// — the engine leaves a `display: .none` node at the tree's zero rect — so
    /// geometry makes it unhittable by accident. Focus registration reads no
    /// geometry at all, deliberately (that is the design's own argument for
    /// riding on `registerHandlers`), so `display: .none` is invisible to it.
    ///
    /// CLAUDE.md's `hidden()` row ends "safe on `Box`es and wrong on anything
    /// that draws"; it is now also wrong on anything **focusable**. Not fixed
    /// here: the standing blocker for that whole row is that nothing in paint
    /// or prepaint consults `Style.display`, and the fix is one check in
    /// `Element`'s group walk rather than a special case here.
    public func focusable() -> Self {
        handling { $0.isFocusable = true }
    }

    /// Runs `handler` when a key event reaches this element — because it holds
    /// focus, or because it is an **ancestor** of whatever does.
    ///
    /// **Return `true` to claim the keystroke and `false` to pass it on.** The
    /// event walks the focused element's id chain outward, innermost first, and
    /// stops at the first handler that returns `true`; a `false` sends it to
    /// the next ancestor, and past the root to `Window.onInput`. So a container
    /// can bind a shortcut for its whole subtree, and a child can decline a key
    /// it does not recognise without knowing what is bound above it.
    ///
    /// **This does not make the element focusable** — see `focusable()`. The
    /// two are separate because an ancestor handling keys is not a place the
    /// user's keyboard should land, and a text field is focusable before
    /// anything is bound to it.
    ///
    /// **`keyDown` only.** `KeyEvent` carries no down/up discriminator, so a
    /// handler receiving both could not tell them apart; a `keyUp` falls
    /// through to `Window.onInput` instead.
    ///
    /// **What `handler` captures outlives the frame that built it** — the same
    /// retain-cycle hazard `onClick(_:)` above states in full, arriving here
    /// through `Window.lastFocusRegistry` rather than through `lastHitboxes`.
    /// Capture `[weak window]`, or capture the state the handler writes.
    ///
    /// **A second `onKey` REPLACES the first**, exactly as a second `onClick`
    /// does.
    public func onKey(_ handler: @escaping @MainActor (KeyEvent) -> Bool) -> Self {
        handling { $0.onKey = handler }
    }

    // MARK: Actions and key contexts (design spec §4.1, §4.3)

    /// Runs `handler` when an action of type `type` reaches this element —
    /// because it holds focus, or because it is an **ancestor** of whatever
    /// does.
    ///
    /// **Registration is the claim, so there is no `Bool` to return.** An
    /// action stops at the first element along the focus chain registered for
    /// its type; unlike `onKey(_:)`, which sees every keystroke and must be
    /// able to decline one, this sees only the type it asked for. An action
    /// nobody registers for reaches `Window.onAction` and, failing that, is not
    /// claimed at all — the keystroke then falls through to the raw key bubble
    /// rather than vanishing.
    ///
    /// **It runs BEFORE `onKey(_:)`, and that ordering is the design.** A
    /// keymap is a declaration of intent and a raw key handler is the escape
    /// hatch, so a bound keystroke never reaches `onKey` and an unbound one
    /// always does. The two bubbles walk the same chain and are otherwise
    /// independent.
    ///
    /// **This does not make the element focusable** — see `focusable()` — and
    /// it registers no pointer hitbox, exactly as `onKey(_:)` does not.
    ///
    /// **A second `onAction` for the SAME type replaces the first**; one for a
    /// different type is added alongside it. That is the one place this
    /// framework's "each modifier writes one field" rule reads as additive, and
    /// it is because the field is a dictionary keyed by the type.
    ///
    /// **What `handler` captures outlives the frame that built it** — the
    /// retain-cycle hazard `onClick(_:)` states in full, arriving here through
    /// `Window.lastFocusRegistry`.
    public func onAction<A: Action>(_ type: A.Type,
                                    _ handler: @escaping @MainActor (A) -> Void) -> Self {
        handling { handlers in
            handlers.actions[ObjectIdentifier(type)] = { action in
                // Force-cast rather than a conditional one, and deliberately.
                // The key written here is `ObjectIdentifier(A.self)` and
                // `dispatchAction` looks up by
                // `ObjectIdentifier(type(of: action))`, so the two agree by
                // construction. A `guard … else { return }` would turn any
                // future break in that agreement into a handler that silently
                // never runs — this repo's most-recorded failure shape.
                //
                // **It is NOT unreachable, and this comment said it was until
                // a mutation proved otherwise.** Making
                // `FocusRegistry.actionHandler(for:type:)` ignore its `type`
                // argument reaches this cast immediately: the suite dies with
                // signal 6 and **no summary line**, which is a crash rather
                // than a red test (taxonomy shape 11) and is the cost of
                // choosing the loud spelling. The pin for the type-keying
                // itself is a *behavioural* test —
                // `anActionBubblesPastAnElementThatDoesNotHandleIt` — and the
                // measurement is that it reddens alone when the same mutation
                // is paired with a conditional cast here.
                handler(action as! A)
            }
        }
    }

    /// Contributes a **key context** for this element and its whole subtree —
    /// framework spec §8.3's `.keyContext("Editor", ["mode": "code"])`.
    ///
    /// A `Keymap` binding may name a context predicate (`"Editor"`,
    /// `"Editor && mode == code"`), and it fires only where that predicate is
    /// satisfied by the contexts along the focused element's ancestor chain.
    ///
    /// **Any element may contribute one, focusable or not** — that is the
    /// point. The pane names `Editor`; the focused leaf inside it knows nothing
    /// about contexts and still gets the pane's bindings, because matching runs
    /// over the chain rather than over the focused element alone.
    ///
    /// **The innermost contributor wins** when two bindings for one keystroke
    /// are both satisfied: a binding predicated on a context contributed deeper
    /// in the chain beats one predicated on a shallower context, and a binding
    /// with no context at all is the outermost of all. See `matchKeymap`.
    ///
    /// **It registers no pointer hitbox and does not make the element
    /// focusable.** Contributing a context is a keyboard-side ask only.
    ///
    /// **A second `keyContext` REPLACES the first**, as every other modifier
    /// here does — one element contributes one context.
    public func keyContext(_ name: String, _ values: [String: String] = [:]) -> Self {
        handling { $0.keyContext = KeyContext(name, values) }
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

    /// Fills with `token` instead of `background(_:)` while the pointer is over
    /// this element.
    ///
    /// **It does not make the element a hit target, and on its own it does
    /// nothing at all.** Hover resolves against the frame's hitbox list, and
    /// `onClick(_:)` is the only thing that puts an element into that list
    /// (`PrepaintPass.registerHandlers`) — so `.hoverBackground(.accent)` with
    /// no `.onClick { … }` compiles, paints the plain background forever and
    /// has no diagnostic. Pairing it with a click handler is what makes it
    /// live; pinned by `hoverBackgroundWithoutAClickHandlerNeverPaints`.
    ///
    /// Deliberately not folded into `onClick(_:)`: an element may want the hit
    /// target without the affordance — a whole row that is clickable while the
    /// highlight lives on a child — and one modifier writes one field.
    public func hoverBackground(_ token: ColorToken) -> Self {
        decorating { $0.hoverBackground = token }
    }

    /// Fills with `token` instead of `background(_:)` — and instead of
    /// `hoverBackground(_:)` — while this element holds keyboard focus.
    ///
    /// **This is the framework's only focus affordance, and it is a fill rather
    /// than a ring for a mechanical reason**: nothing above the renderer can
    /// ask for a border at all (`Frame.fill`, and CLAUDE.md's declared-but-inert
    /// table). Two nested filled boxes are the spelling for a ring today.
    ///
    /// **It needs `focusable()` AND something to move focus.** Focus never
    /// moves on its own here — clicking does not focus, see `Window.focus(_:)`
    /// — so an element declaring this and nothing else paints its plain
    /// background forever, exactly as `hoverBackground(_:)` does without a
    /// click handler.
    public func focusBackground(_ token: ColorToken) -> Self {
        decorating { $0.focusBackground = token }
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
    //
    // **These eight write THIS element's own CSS box. `.frame(...)` is
    // SwiftUI's spelling and it is a different operation** — plan task 4's
    // sizing inventory, rulings `FR-F`, `FR-G` and `FR-H`
    // (`docs/superpowers/2026-09-15-frame-sizing-decisions.md`).
    //
    // A modifier here overwrites a field of the receiver's `Style` and returns
    // `Self`. `.frame(...)` wraps the receiver in a new outer layer of a
    // `ModifiedElement` and returns that. The difference is observable, and
    // `theSizingModifiersWriteTheirOwnElementsBoxRatherThanWrappingIt` pinned
    // it on the legacy tree until stage 7b retired it (record §49 §4 row 204):
    // each of the eight left `LayoutTree.nodeCount` exactly where the
    // unmodified element left it, and `.frame(width:)` added one. The type-level
    // half is `legacyModifierChainsInferOneConcreteType`'s
    // (`Tests/MetalUITests/ModifiedElementTests.swift`). Three consequences a
    // caller meets:
    //
    // - `Box(decoration:).width(36)` paints a 36pt-wide decorated box;
    //   `Box(decoration:).frame(width: 36)` paints the decoration at the
    //   child's own size inside a 36pt layer (the design session's scratch
    //   L8, `FR-F`; UNPINNED — no committed test renders a decoration inside
    //   a frame).
    // - a `hoverBackground` declared *before* a `.frame` stays on the inner
    //   element, at the inner element's size, as a `.background` before a
    //   `.frame` does in SwiftUI (`docs/probes/swiftui-modifier-order.swift`,
    //   arm O1: the inner leaf reads 20×20 inside a 60×60 frame). A handler
    //   declared before a `.frame` stays there too (scratch L4: a 0×0 hitbox
    //   at (30, 20), `FR-F`); that SwiftUI's gesture hit area does the same is
    //   by reading, unprobed.
    // - the clamps below cancelled flex §4.5's automatic minimum on the legacy
    //   engine, where a frame layer's `minSize` could not reach into its child;
    //   under the proposal authority there is no automatic minimum, and a
    //   growing box's zero minimum is `.frame(minHeight: 0, maxHeight:
    //   .infinity)` (`minHeight`'s comment, ruling `LR-ET`).
    //
    // **All eight are deprecated since plan task 7's stage 8** (rulings `LR-EU`,
    // amending `FR-I` and `FR-H`; spec
    // `docs/superpowers/specs/2026-09-24-engine-stage-8-design.md`). `FR-I` kept
    // them undeprecated because the branch gates on 0 `warning:` and a
    // deprecation means migrating every caller in the same change; stage 8 made
    // that one move — the demo converted to `.frame` by `LR-ES`'s recipe, every
    // test either converted (class F), moved to the test target's
    // undeprecated `css*` helpers that write the same `Style` field (class K,
    // `Tests/MetalUITests/CSSSizing.swift`), or kept inside a deprecated
    // protocol witness where the modifier itself is the subject (class D,
    // `LR-EW`). Each carries a `message:`, not a `renamed:` (`LR-EU` item 2): a
    // `renamed:` fix-it rewrites `.width(x)` to `.frame(width: x)` in place and
    // silently skips the rest of the recipe — a background left before its
    // frame, a sized container's content re-centred (`LR-ES` R2, R3). The two
    // `fraction:` spellings are deprecated with no replacement: a fraction of
    // the containing block has no SwiftUI counterpart and traps under the
    // proposal authority (`LR-AI`), which production runs since stage 6b. The
    // guard is `theSizingModifiersAreDeprecatedTowardFrame`
    // (`FrameSizingCompileGuards.swift`). The fields they write, and these
    // modifiers, go with `Style.size`/`minSize`/`maxSize` at stage 10.

    /// Writes this element's own CSS `width`. SwiftUI's spelling is
    /// `.frame(width:)`, which wraps instead — see the section comment above.
    @available(*, deprecated, message: "use .frame(width:), which wraps this element in a layer instead of writing its own box (LR-ES)")
    public func width(_ points: Pixels) -> Self {
        modifying { $0.size.width = .length(.pixels(points)) }
    }

    /// Writes this element's own CSS `height`. SwiftUI's spelling is
    /// `.frame(height:)`, which wraps instead — see the section comment above.
    @available(*, deprecated, message: "use .frame(height:), which wraps this element in a layer instead of writing its own box (LR-ES)")
    public func height(_ points: Pixels) -> Self {
        modifying { $0.size.height = .length(.pixels(points)) }
    }

    /// This element's own CSS `width`, as a **fraction** of the containing
    /// block's width: `width(fraction: 0.5)` is half. SwiftUI has no
    /// counterpart at all, which is why this one was kept as an explicit
    /// MetalUI divergence with a test (`FR-H`) while production ran the legacy
    /// engine — and why stage 8 deprecates it with no replacement (`LR-EU` item
    /// 3: unlowerable under the proposal authority, `LR-AI`); its nearest,
    /// `containerRelativeFrame`, resolves against a named container rather
    /// than a containing block. Pinned on the legacy authority by
    /// `aFractionSizeResolvesAgainstItsContainingBlock` until stage 7b retired
    /// it (record §49 §4 row 203); under the proposal authority a fraction is
    /// reported by name (`percentagesStillReportByNameWithTheirOwner`).
    ///
    /// **Renamed from `width(percent:)`** (ruling `CN-O`), whose label said
    /// percentage while `Length.percent` is `f * parent` in `resolveLength`, so
    /// `width(percent: 50)` meant 5000% (ruling `FR-T`). The old spelling is
    /// kept, deprecated, with its meaning unchanged.
    ///
    /// The **root** is not a special case: ruling `SZ-A` made `resolveRootSize`
    /// resolve a root fraction against the extent that axis was offered
    /// (oracle `rootPercentageMatchesWebKit`, in `SizingFixtureTests.swift`,
    /// retired with the goldens by stage 7a and the file by 7b); the test's root
    /// arm keeps that honest through the public modifier.
    @available(*, deprecated, message: "a fraction of the containing block has no SwiftUI counterpart and is unlowerable under the proposal layout authority (LR-AI); declare a length with .frame(width:)")
    public func width(fraction: Float) -> Self {
        modifying { $0.size.width = .length(.percent(fraction)) }
    }

    /// This element's own CSS `height`, as a **fraction** of the containing
    /// block's height — see `width(fraction:)` for the unit and for the
    /// divergence `FR-H` keeps it under.
    @available(*, deprecated, message: "a fraction of the containing block has no SwiftUI counterpart and is unlowerable under the proposal layout authority (LR-AI); declare a length with .frame(height:)")
    public func height(fraction: Float) -> Self {
        modifying { $0.size.height = .length(.percent(fraction)) }
    }

    /// The old name of `width(fraction:)`, deprecated by ruling `CN-O`: the
    /// argument is a FRACTION, so `width(percent: 50)` is 5000%. Unchanged
    /// meaning; guard `thePercentSizingModifiersAreDeprecatedRenamesOfFraction`.
    @available(*, deprecated, renamed: "width(fraction:)")
    public func width(percent: Float) -> Self {
        width(fraction: percent)
    }

    /// The old name of `height(fraction:)` — see `width(percent:)`.
    @available(*, deprecated, renamed: "height(fraction:)")
    public func height(percent: Float) -> Self {
        height(fraction: percent)
    }

    /// Writes this element's own CSS `min-width`. SwiftUI's spelling is
    /// `.frame(minWidth:)`, which wraps instead — and, as `minHeight(_:)`
    /// records, the two were not interchangeable at a value of 0 on the legacy
    /// engine.
    @available(*, deprecated, message: "use .frame(minWidth:), which wraps this element in a layer instead of writing its own box (LR-ES)")
    public func minWidth(_ points: Pixels) -> Self {
        modifying { $0.minSize.width = .length(.pixels(points)) }
    }

    /// Writes this element's own CSS `min-height`. SwiftUI's spelling is
    /// `.frame(minHeight:)`, which wraps instead.
    ///
    /// **On the legacy engine a zero here was the only way to cancel flex
    /// §4.5's automatic (content-based) minimum, and no frame layer could do
    /// it** — ruling `FR-G`, measured on the demo's own shape (a `flexGrow(1)`,
    /// `flexBasis(0)` box holding 400pt of content in a 200pt `Column` under an
    /// 80pt header): `.minHeight(Pixels(0))` shrank the content to 120; with no
    /// minimum, or with `.frame(minHeight: 0)` and the grow on either the layer
    /// or the inner box, it stayed 400 — the layer's `minSize` is the *layer's*
    /// minimum, and the element inside kept its own automatic one.
    ///
    /// **Amended by stage 8** (`LR-ET`): under the proposal authority, which
    /// production runs since stage 6b, there is no automatic minimum. A greedy
    /// frame's lower bound is its content unless it declares a minimum —
    /// SwiftUI's rule (probe `swiftui-engine-stage-8.swift` F0/F1: 400 without,
    /// 120 with `minHeight: 0`) — so the cancellation's spelling is
    /// **`.frame(minHeight: 0, maxHeight: .infinity)`** on the growing box,
    /// pinned by `aGreedyFrameAnswersBelowItsContentOnlyWithAZeroMinimum`
    /// (`FrameSizingTests`). FR-G's one live caller, the demo scroller box's
    /// `.minHeight(Pixels(0))`, had been inert since stage 6b (its lowered
    /// `ScrollView` fills its proposal; record §50 §3, O1/O2) and is gone with
    /// the demo's conversion. This modifier, on a grown axis, still answers the
    /// same under the proposal authority (it is the greedy frame's minimum,
    /// `LR-AG`) until stage 10 deletes it.
    @available(*, deprecated, message: "use .frame(minHeight:), which wraps this element in a layer instead of writing its own box (LR-ES); a growing box's zero minimum is .frame(minHeight: 0, maxHeight: .infinity) (LR-ET)")
    public func minHeight(_ points: Pixels) -> Self {
        modifying { $0.minSize.height = .length(.pixels(points)) }
    }

    /// Writes this element's own CSS `max-width`. SwiftUI's spelling is
    /// `.frame(maxWidth:)`, which wraps instead — and differs in more than the
    /// node: a legacy frame clamps at its maximum but never grows toward its
    /// proposal, where SwiftUI's does (ruling `FR-E`).
    @available(*, deprecated, message: "use .frame(maxWidth:), which wraps this element in a layer instead of writing its own box (LR-ES)")
    public func maxWidth(_ points: Pixels) -> Self {
        modifying { $0.maxSize.width = .length(.pixels(points)) }
    }

    /// Writes this element's own CSS `max-height`. SwiftUI's spelling is
    /// `.frame(maxHeight:)`, which wraps instead — see `maxWidth(_:)`.
    @available(*, deprecated, message: "use .frame(maxHeight:), which wraps this element in a layer instead of writing its own box (LR-ES)")
    public func maxHeight(_ points: Pixels) -> Self {
        modifying { $0.maxSize.height = .length(.pixels(points)) }
    }

    // MARK: Box model

    /// Adds padding outside this element, as a SwiftUI modifier does.
    ///
    /// The engine's `Style.padding` remains border-box padding, but the public
    /// modifier applies it to a new outer layer of a `ModifiedElement` (MC-A).
    /// A fixed-size child keeps its declared size; its caller sees an outer
    /// footprint enlarged by the padding. Repeating the modifier adds a layer,
    /// so padding composes, and the chain's type stays `ModifiedElement<Base>`.
    public func padding(_ points: Pixels) -> ModifiedElement<LayerBase> {
        padding(Edges(all: .pixels(points)))
    }

    /// The per-edge form of `padding(_:)`; edges are applied to the new outer
    /// layer rather than overwriting this element's own style.
    ///
    /// **This is one of the three modifiers through which `Length.rems` is
    /// publicly reachable** (ruling `FR-Q` and its addendum, with
    /// `margin(_ edges:)` and — through `Dimension`, which wraps a `Length` —
    /// `inset(_ edges:)`; `gap` takes `Pixels` only, and there is no rem
    /// *sizing* modifier anywhere. `FR-Q` counted four: its fourth,
    /// `borderWidth(_ edges:)`, was deleted by the outer-modifiers track in
    /// the same integration, ruling `OM-M`, and the paint-only `border` that
    /// replaced it takes `Pixels`). A rem resolves in
    /// `MetalUILayout/Resolve.swift` against `Frame.rootFontSize` — a single
    /// per-frame `let`, default 16, not a per-element font size. `ResolveTests`
    /// pinned it until stage 7b retired that file (record §49 row 173); the
    /// lowering's rem resolution is pinned by the rem arms of
    /// `aLoweredFixedSizeBoxAgreesWithTheLegacyBoxInEveryObservation` and
    /// `aDeferredAbsoluteBoxLowersAgainstTheWindowOnEveryInsetShape` (record
    /// §49 §6.1, M1l). SwiftUI has neither, so it is a
    /// MetalUI divergence kept under `FR-H`'s disposition; it is a box-model
    /// unit rather than a frame parameter, so plan task 4 left it alone.
    public func padding(_ edges: Edges<Length>) -> ModifiedElement<LayerBase> {
        var style = Style()
        style.padding = edges
        return _wrap(ModifierLayer(style: style))
    }

    /// Item margins. Takes `Length`, so `.auto` is unspellable — see
    /// `StyledElement`'s note.
    public func margin(_ points: Pixels) -> Self {
        modifying { $0.margin = Edges(all: .length(.pixels(points))) }
    }

    /// See `margin(_:)` — `.auto` is deliberately out of reach. A per-edge
    /// `Length` may be `.rems`, one of the three public rem entry points
    /// (`FR-Q`, less the deleted `borderWidth`; see `padding(_ edges:)` for the
    /// inventory).
    public func margin(_ edges: Edges<Length>) -> Self {
        modifying {
            $0.margin = Edges(top: .length(edges.top), right: .length(edges.right),
                              bottom: .length(edges.bottom), left: .length(edges.left))
        }
    }

    // `borderWidth(_:)` lived here and is DELETED (ruling `OM-M`). It wrote
    // `Style.border`, which the engine consumed inside `contentBox` and
    // discarded: on a content-sized box it moved the layout by twice the width
    // and on any box it painted nothing at all. That is worse than inert, and
    // CLAUDE.md's declared-but-inert table exists to remove that shape rather
    // than annotate it. The name belongs to the paint-only `border(_:width:)`
    // at the end of this extension; `Style.border` stays engine-side, reachable
    // only through `Box(style:)`, on `margin: .auto`'s footing.
    // `borderWidthIsNoLongerSpellable` (`DecorationCompileGuards.swift`) pins
    // the removal against a plain import.

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

    /// A **fraction** of the containing block's main axis: `0.5` is half —
    /// the third modifier with `width(fraction:)`'s unit (ruling `CN-O`).
    public func flexBasis(fraction: Float) -> Self {
        modifying { $0.flexBasis = .length(.percent(fraction)) }
    }

    /// The old name of `flexBasis(fraction:)`, deprecated by ruling `CN-O`
    /// (`FR-T`'s third site): `flexBasis(percent: 50)` is 5000%.
    @available(*, deprecated, renamed: "flexBasis(fraction:)")
    public func flexBasis(percent: Float) -> Self {
        flexBasis(fraction: percent)
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
    /// when there is none.
    ///
    /// **That does NOT by itself make "positioned against the window" spellable
    /// from anywhere in the tree, and the exception is a whole clipper.** This
    /// modifier decides where layout *places* the box; it says nothing about
    /// what paint then *does* with the emission. A clip and a scroll offset are
    /// carried on `Frame`'s clip stack, which is structural — every ancestor's
    /// `clipped(to:offsetBy:)` applies to everything emitted beneath it,
    /// containing block or not. So an `.absolute` box inside a `ScrollView`
    /// lands at its window-space coordinates and is then masked to the
    /// viewport and translated by the scroll, which for a box positioned
    /// against the window generally means it draws nothing and slides away.
    /// CSS couples the two — a descendant whose containing block sits outside
    /// an `overflow` clipper escapes that clipper — and design spec §2 declines
    /// to reproduce the coupling, because it would entangle layer resolution
    /// with containing-block resolution. CLAUDE.md's divergence 11.
    ///
    /// **`Deferred` is the escape**, and it is a separate decision from this
    /// one for that reason: it resets the clip stack to the whole surface and
    /// the offset to zero, so `Deferred { Box().position(.absolute)… }` is the
    /// spelling that does cover the window from anywhere in the tree.
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
    ///
    /// A `Dimension` wraps a `Length`, so an edge may be `.length(.rems(…))`:
    /// this is the public reach to `Length.rems` that the `FR-Q` inventory
    /// missed and its addendum added (its fourth then; the third now that
    /// `borderWidth` is gone, `OM-M`) (lane 3's verifier measured
    /// an absolute box's `.inset(left: .length(.rems(Rems(2))))` at x = 32
    /// against a 0px control's 0, root font size 16; `placeAbsolute` resolves
    /// each edge with `rootFontSize`). See `padding(_ edges:)` for the
    /// inventory.
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
    /// rather than from the item list; `Sources/MetalUIDemoContent/DemoContent.swift`'s modal
    /// does exactly that, and carries the vanishing-`if` identity caveat at its
    /// call site. CLAUDE.md's declared-but-inert table has the row.
    ///
    /// **Everything above is the legacy authority.** Under the proposal
    /// authority (stage 6b, ruling `LR-DH`) a hidden node lowers **as if
    /// shown** — it keeps its space, as SwiftUI's `hidden()` does — and joins
    /// `Frame.hiddenNodes`: it and its subtree paint nothing (a hidden `Text`
    /// emits no glyph), register their pointer hitboxes under the
    /// `hitTestingDisabled` scope and publish nothing to accessibility.
    public func hidden() -> Self {
        modifying { $0.display = .none }
    }

    // MARK: Paint-only decoration (plan task 5, lane 2)
    //
    // **Appended at the END of this extension, and that placement is a merge
    // decision rather than taste.** Plan task 4 (frame/sizing) is editing the
    // same extension for `width`/`height`/min/max in a parallel worktree;
    // added-lines-at-a-known-anchor is a conflict a human resolves in one
    // glance, an interleave is not. The outer-modifiers spec §5.1 and §8 both
    // say so. New modifiers go below this comment, not above it.
    //
    // Every one of the eight is **paint-only**: it writes `Decoration` and
    // contributes no layout node, exactly as SwiftUI's equivalents do (probe
    // `swiftui-outer-modifier-order`, arms L2…L9 — `.border`, `.opacity`,
    // `.clipShape` and five others all leave a 20x20 leaf 20x20 where
    // `.padding(8)` reads 36x36). `everyOuterModifierIsWrapsOrPaintOnlyOr
    // DistributesAsTheMatrixSays` is the per-modifier pin and
    // `everyPublicModifierWritesItsOwnFieldAndOnlyThatField` the field pin.
    //
    // §5.1 specifies ELEVEN modifiers for this task; lane 2 shipped the
    // **eight** it could make live. `allowsHitTesting(_:)` and the two
    // `contentShape(inset:)` overloads need `Handlers.allowsHitTesting` and
    // `Handlers.contentShapeInset` plus the prepaint wiring — shipping them
    // with lane 2 would have been three modifiers that compile and do nothing,
    // which is the shape this whole task exists to remove. Ruling `OM-AE`.
    // Lane 3 shipped them; they are under the "Hit testing" MARK at the end
    // of this extension.

    /// Draws a border of `token`, `width` points wide on all four edges,
    /// **inside** this element's own box.
    ///
    /// Paint-only: it adds no node and changes no size, as SwiftUI's `.border`
    /// does not (probe `swiftui-outer-modifier-order` L2). The border is
    /// emitted AFTER this element's children, so a child that fills the box
    /// does not hide it (`OM-V`, probe arm B3).
    ///
    /// **Rounded by this element's own `cornerRadius`, and SwiftUI's is not.**
    /// `.border(c, w).cornerRadius(r)` in SwiftUI clips a *square* border by the
    /// radius, leaving the corner arc's interior unbordered; MetalUI emits one
    /// rounded bordered rect whose stroke follows the arc. Both are fields of
    /// one `Decoration`, so the order is not observable here at all — a
    /// recorded divergence, pinned by
    /// `aRoundedBorderFollowsTheArcWhereSwiftUIsClippedSquareBorderDoesNot`
    /// (`OM-W`).
    ///
    /// Traps on a negative or non-finite width — see `BorderStyle`.
    public func border(_ token: ColorToken, width: Pixels) -> Self {
        decorating { $0.border = BorderStyle(token, width: width) }
    }

    /// The per-edge form of `border(_:width:)`.
    public func border(_ token: ColorToken, widths: Edges<Pixels>) -> Self {
        decorating { $0.border = BorderStyle(token, widths: widths) }
    }

    /// Draws this border instead of `border(_:width:)`'s while the pointer is
    /// over this element.
    ///
    /// **It does not make the element a hit target**, exactly as
    /// `hoverBackground(_:)` does not: `onClick(_:)` is the only thing that puts
    /// an element into the hitbox list, so `.hoverBorder(…)` alone compiles and
    /// draws the plain border forever.
    public func hoverBorder(_ token: ColorToken, width: Pixels) -> Self {
        decorating { $0.hoverBorder = BorderStyle(token, width: width) }
    }

    /// The per-edge form of `hoverBorder(_:width:)`.
    public func hoverBorder(_ token: ColorToken, widths: Edges<Pixels>) -> Self {
        decorating { $0.hoverBorder = BorderStyle(token, widths: widths) }
    }

    /// **The focus ring**: draws this border instead of `border(_:width:)`'s —
    /// and instead of `hoverBorder(_:width:)`'s — while this element holds
    /// keyboard focus (`OM-L`).
    ///
    /// Until this existed the framework's only focus affordance was
    /// `focusBackground(_:)`'s token swap, which a human reviewer could not read
    /// as an affordance at all ("a judgement about two dark greys", CLAUDE.md's
    /// human-verification table).
    ///
    /// It needs `focusable()` AND something to move focus: clicking does not
    /// focus (`Window.focus(_:)` is the only mover), so an element declaring
    /// this and nothing else draws its plain border forever.
    public func focusBorder(_ token: ColorToken, width: Pixels) -> Self {
        decorating { $0.focusBorder = BorderStyle(token, width: width) }
    }

    /// The per-edge form of `focusBorder(_:width:)`.
    public func focusBorder(_ token: ColorToken, widths: Edges<Pixels>) -> Self {
        decorating { $0.focusBorder = BorderStyle(token, widths: widths) }
    }

    /// Multiplies the opacity of everything this element paints — its own
    /// background and border included — and of everything inside it.
    ///
    /// Traps outside `0...1`, at the call site rather than a frame later inside
    /// `PaintPass.opacity`.
    ///
    /// **Opacity SCOPES multiply; two calls on ONE element do not** (`OM-AH`).
    /// `Frame.activeOpacity` composes nested scopes by multiplication, so a
    /// faded element inside a faded one reads a quarter — but a second call here
    /// writes the same `Decoration.opacity` field, so the last one wins and
    /// `.opacity(0.5).opacity(0.5)` reads **0.5**. SwiftUI's G1/G2 are one view
    /// with two calls and read the equivalent of 0.25 (rgb(1.00,0.58,0.58) after
    /// one, rgb(1.00,0.80,0.80) after two). Recorded divergence — `OM-H`'s
    /// not-expressible mechanism in its fifth instance — pinned by
    /// `aSecondOpacityOnOneElementReplacesTheFirstWhereSwiftUIMultiplies`. The
    /// spelling that multiplies puts a scope between the two calls: a nested
    /// `Box`, or a layer (`.opacity(0.5).padding(2).opacity(0.5)` reads 0.25).
    ///
    /// **`.opacity(0.5).background(x)` fades the background too, and SwiftUI's
    /// does not** (G4). See `Decoration.opacity` for why that order was the one
    /// given up, and `OM-N`/`OM-AA` for the two divergences it produces.
    public func opacity(_ value: Float) -> Self {
        Decoration.validateOpacity(value)
        return decorating { $0.setOpacity(value) }
    }

    /// Clips this element's children to its own box, rounded by its
    /// `cornerRadius`.
    ///
    /// **Separate from `cornerRadius(_:)`** (`OM-G`): SwiftUI's `.cornerRadius`
    /// clips its content and MetalUI's rounds a fill, so
    /// `.cornerRadius(12).clipped()` is the spelling for SwiftUI's
    /// `.cornerRadius(12)`. Making the radius clip on its own would move all
    /// sixteen of the demo's call sites and is task 11's.
    ///
    /// The clip is pushed in prepaint as well as paint, so a hitbox inside is
    /// registered against it — `clippedAlsoClipsTheHitboxesInsideIt`.
    public func clipped() -> Self {
        decorating { $0.clipsContent = true }
    }

    // MARK: Hit testing (plan task 5, lane 3)
    //
    // The last three of §5.1's eleven. They are **prepaint-only**, not
    // paint-only: they change what is registered for hit testing and emit
    // nothing at all. New modifiers still go at the END of this extension —
    // see the lane 2 MARK above for why.

    /// Whether pointer events may reach this element **and everything inside
    /// it** — SwiftUI's `.allowsHitTesting(_:)`.
    ///
    /// **`false` kills this element's own `onClick` as well as its subtree's**,
    /// in either order: `.onClick { }.allowsHitTesting(false)` and
    /// `.allowsHitTesting(false).onClick { }` are both dead, which is SwiftUI's
    /// answer in both orders too (probe `swiftui-content-shape-hit-region`,
    /// arms N1 and N2). Ruling `OM-T`.
    ///
    /// **The scope covers the layer it is written on and everything inside it,
    /// not the layers written after it.** With a wrapping modifier between the
    /// two, the orders differ: `.allowsHitTesting(false).padding(40).onClick { }`
    /// scopes the inner layer and the outer layer's click is live, while
    /// `.padding(40).allowsHitTesting(false).onClick { }` is dead. SwiftUI reads
    /// 0 / 0 in both (probe arms X1, X2) — a recorded divergence, `OM-AL`,
    /// which is `OM-I`'s default-region divergence seen across a layer (arm X3:
    /// SwiftUI's own answer becomes 1 / 1 once a `.contentShape(Rectangle())`
    /// gives the outer gesture a region). Write the scope LAST to dim a chain.
    ///
    /// **It is a pointer decision and nothing else.** A focusable element under
    /// it still holds focus and still answers keys; a declared `AXNode` is still
    /// emitted and an accessibility client still sees the element. SwiftUI keeps
    /// the same two halves (probe `swiftui-allows-hit-testing-side-effects`,
    /// arms A1 and K1). For "this control is off", write `.disabled(true)`,
    /// which takes the keyboard side with it (rulings `EV-E`, `EV-F`).
    ///
    /// **Hover and `isActive` follow the hitbox**, because both are resolved
    /// from the hitbox list: an element with hit testing off is never hovered,
    /// so a `hoverBackground(_:)` on it never paints (pinned for hover by
    /// `aHoverBackgroundNeverPaintsUnderAllowsHitTestingFalse`; `isActive` is
    /// by reading, unpinned — no built-in element paints a pressed state).
    ///
    /// A `ScrollView` inside the scope still scrolls (`OM-AK`) — see
    /// `Handlers.allowsHitTesting`.
    public func allowsHitTesting(_ enabled: Bool) -> Self {
        handling { $0.allowsHitTesting = enabled }
    }

    /// Insets this element's hit region from its own box — MetalUI's rect-only
    /// subset of SwiftUI's `.contentShape(_:)` (`OM-J`).
    ///
    /// **`.contentShape(Rectangle())` is MetalUI's DEFAULT, which is why this
    /// modifier takes an inset instead** (`OM-I`). SwiftUI derives a view's hit
    /// region from what it draws, so a stack with an empty middle is not
    /// hittable there until `.contentShape(Rectangle())` makes it so (probe
    /// `swiftui-content-shape-hit-region`, H1 vs H2); every MetalUI element that
    /// registers a hitbox is hittable over its whole frame already. Shipping the
    /// SwiftUI spelling would be an API that compiles and does nothing. What
    /// SwiftUI can express and MetalUI could not is a region **smaller** than
    /// the frame (H3), and in a rect-only hitbox world an inset is the whole of
    /// it. The identity case is `inset: Pixels(0)` — a parameter value, not a
    /// second no-op spelling.
    ///
    /// **It configures a hit region; it does not create one** (`OM-AB`).
    /// `onClick(_:)` is still the only thing that makes an element a pointer
    /// target, so this on an element without one writes the field and registers
    /// nothing — the same shape as `hoverBackground(_:)` with no `onClick`.
    /// **On a chain, write it after the last wrapping modifier**, on the layer
    /// that carries the `onClick`: `.contentShape(inset: 20).padding(40)
    /// .onClick { }` leaves the inset on the inner element and the padded
    /// layer hittable over its whole frame, where SwiftUI honours the inset
    /// (probe arm S1; a divergence pinned by
    /// `aContentShapeWrittenBeforeAWrappingModifierDoesNotReachAClickWrittenAfterIt`).
    ///
    /// **It moves neither the accessibility frame nor the focus registration**:
    /// the inset is applied at one site, to the bounds `Frame.registerHandlers`
    /// hands `insertHitbox`, and everything else that call registers keeps the
    /// element's own box.
    ///
    /// A **negative** inset grows the region past the element's box, as
    /// SwiftUI's does (H5). MetalUI's grown region is still intersected with the
    /// active clip, as every hitbox is; SwiftUI's is not (H6, `OM-AJ`).
    public func contentShape(inset: Pixels) -> Self {
        handling { $0.contentShapeInset = Edges(all: inset) }
    }

    /// The per-edge form of `contentShape(inset:)`.
    public func contentShape(inset: Edges<Pixels>) -> Self {
        handling { $0.contentShapeInset = inset }
    }
}
