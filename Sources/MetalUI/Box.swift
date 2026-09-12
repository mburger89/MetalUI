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
        // M4 spec 3 §5: substitutes any animatable field mid-transition,
        // storing the result back on `self` — `paint` reads `self.decoration`
        // later in this same frame, so this is what makes `cornerRadius`
        // animation (and any other decoration field this helper animates)
        // reach the screen rather than only the layout node.
        (style, decoration) = animated(style, decoration, for: id, pass: &pass)
        let node = pass.requestNode(style: style, children: children)
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
        pass.registerHandlers(handlers, at: bounds, id: id)
        // `bounds` is this box's own rect and is deliberately not passed down:
        // the engine stores rects **absolute to the root**, so each child looks
        // its own up rather than being offset by its parent. Adding `bounds`
        // here would double-count every ancestor's origin.
        return content.prepaintGroup(layout: &layout.content, pass: &pass)
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
        if let color = animatedBackground(decoration, for: id, pass: &pass) {
            pass.fill(bounds, color: color,
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

    /// The background to paint instead of `background` while the pointer is
    /// over this element, or `nil` to paint `background` either way.
    ///
    /// **A token swap is the whole of what this framework can express for a
    /// pointer state today, and that is a property of `Frame.fill` rather than
    /// a preference.** A border is the obvious spelling for a hover or focus
    /// affordance and it is unreachable: `Frame.fill` hard-codes
    /// `borderColor: .transparent` and zero widths, because the engine resolves
    /// a border width inside `contentBox` and throws it away, so paint has no
    /// width to pair a colour with (CLAUDE.md's declared-but-inert table). A
    /// caller who wants a ring today nests two filled boxes.
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

    public init(background: ColorToken? = nil, cornerRadius: Pixels = Pixels(0),
                hoverBackground: ColorToken? = nil,
                focusBackground: ColorToken? = nil) {
        self.background = background
        self.cornerRadius = cornerRadius
        self.hoverBackground = hoverBackground
        self.focusBackground = focusBackground
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

    public func width(_ points: Pixels) -> FrameModifier<Self> {
        FrameModifier(content: self, width: points)
    }

    public func height(_ points: Pixels) -> FrameModifier<Self> {
        FrameModifier(content: self, height: points)
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

    // MARK: Box model

    /// Adds padding outside this element, as a SwiftUI modifier does.
    ///
    /// The engine's `Style.padding` remains border-box padding, but the public
    /// modifier applies that style to a new outer box. A fixed-size child thus
    /// keeps its declared size and its caller sees an outer footprint enlarged
    /// by the padding. Repeating the modifier adds another wrapper, so padding
    /// composes rather than replacing an earlier value.
    public func padding(_ points: Pixels) -> Box<Self> {
        padding(Edges(all: .pixels(points)))
    }

    /// The per-edge form of `padding(_:)`; edges are applied to the outer
    /// wrapper rather than overwriting this element's own style.
    public func padding(_ edges: Edges<Length>) -> Box<Self> {
        var wrapper = Box(content: self)
        wrapper.style.padding = edges
        return wrapper
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
