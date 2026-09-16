/// The input callbacks an element has asked to receive — `StyledElement`'s
/// fourth stored requirement, alongside `style`, `decoration` and `elementID`.
///
/// **A type of its own rather than a field on either of the other two, and both
/// exclusions are mechanical.** `Style` lives in `MetalUILayout`, which may
/// import only `MetalUICore` (CLAUDE.md's build constraint), and it is compared
/// field-by-field on whole-value equality by
/// `everyPublicModifierWritesItsOwnFieldAndOnlyThatField` — a closure field
/// makes `Style` unequatable and takes that test with it. `Decoration` is paint
/// data: read only by each conformer's own `paint` (`Box.paint`, `Stack.paint`,
/// `Text.paint`) and nothing else, while a handler is read in `prepaint` by the
/// frame and afterwards by the window.
///
/// **Empty is the default and it means "not a hit target".** A `Handlers` with
/// no callback set registers no hitbox at all — see
/// `PrepaintPass.registerHandlers(_:at:id:)` — which is what keeps an ordinary
/// `Box` transparent to the pointer and, more sharply, keeps every box inside a
/// `ScrollView` from swallowing that scroller's wheel.
///
/// **The pointer gate and the keyboard gate are SEPARATE, and conflating them
/// would be a live defect rather than an untidiness.** `isPointerTarget` gates
/// the hitbox and `isKeyTarget` gates the focus registry. A single "asked for
/// something" gate would make every focusable element an *opaque* hitbox — and
/// an opaque hitbox swallows the wheel of any `ScrollView` it sits inside
/// (`Window.applyScroll`), so a list of focusable rows would stop scrolling.
/// Pinned by `focusabilityAndKeyHandlingRegisterNoPointerHitbox`.
///
/// **Both gates sit behind a third, and that one IS shared: the environment's
/// `isEnabled`** (rulings EV-E, EV-F). `Frame.registerHandlers` reads it once;
/// under `.disabled(true)` neither gate is consulted — no hitbox, whatever
/// `isPointerTarget` says, and no focus registration, whatever `isKeyTarget`
/// says. The two stay separate for an ENABLED element, which is the case the
/// paragraph above is about. The handlers themselves are untouched: re-enabling
/// registers the same set on the next frame (`reEnablingRestoresClicksButNotFocus`).
///
/// **A fourth gate is pointer-only on purpose: `allowsHitTesting`** (plan task
/// 5's lane 3, ruling `OM-T`). Unlike `isEnabled` it covers the hitbox and
/// nothing else — focus, keys, a declared `AXNode` and the accessibility record
/// all keep working under it, and SwiftUI keeps the same two halves (probe
/// `swiftui-allows-hit-testing-side-effects`, arms A1 and K1). "Disabled" is a
/// statement about a control; "hit testing off" is a statement about the
/// pointer.
///
/// **Bubble-only, and today that means "the topmost opaque handler wins".**
/// Design spec §3.5 cuts the capture phase, because an opaque hitbox already
/// swallows, which is the case framework spec §8.2 names capture for. What is
/// also absent — and is worth knowing before writing a nested pair — is
/// *chaining*: a click resolves to one hitbox and stops, so an `onClick` on a
/// container whose child also has one never sees a click that landed on the
/// child. There is no ancestry on a `Hitbox` to walk, exactly as there is no
/// scroll chaining in `Window.applyScroll` and for the same reason. Adding it
/// means putting a parent link on the registration, not changing dispatch.
public struct Handlers {
    /// Run when this element is clicked: pressed and released on **this same
    /// element**, with the pointer free to leave and return in between.
    ///
    /// `@MainActor` because everything that could reach it is: `Window`'s input
    /// path, the `StateTable` a handler will almost always write, and
    /// `StyledElement` itself. Typing it here rather than relying on the
    /// closure's context means a handler that captures a non-`Sendable` value
    /// is a compile error at the call site rather than a data race later.
    ///
    /// **One handler, and a second `onClick(_:)` REPLACES the first rather than
    /// adding to it.** `.onClick { a }.onClick { b }` runs only `b`, and still
    /// registers one hitbox. That is what every other modifier on
    /// `StyledElement` does — each writes one field — and it is written down
    /// because the name sounds additive in a way `background(_:)` does not, so
    /// "attach a second handler" is a plausible misreading with no diagnostic
    /// behind it.
    public var onClick: (@MainActor () -> Void)?

    /// Run when a key event reaches this element — either because it holds
    /// focus, or because it is an ancestor of whatever does.
    ///
    /// **Returns whether it claimed the event**, unlike `onClick` above, and
    /// that is the whole bubbling contract: `true` stops the walk, `false`
    /// passes the keystroke to the next ancestor outward. An element can
    /// therefore look at a key and decline it without knowing what else is
    /// bound anywhere above it.
    ///
    /// **`keyDown` only.** `KeyEvent` carries no down/up discriminator, so a
    /// handler receiving both could not tell them apart and would fire twice
    /// per keystroke with no way to opt out; a `keyUp` falls through to
    /// `Window.onInput` instead. Pinned by
    /// `aKeyUpIsNotDispatchedToTheFocusChain`.
    public var onKey: KeyHandler?

    /// Whether this element may **hold** focus.
    ///
    /// **Separate from `onKey` on purpose, and neither implies the other.** A
    /// container binding a shortcut for its whole subtree handles keys without
    /// ever being the focused thing; a text field is focusable before anything
    /// is bound to it. One combined flag could express neither, and the pair is
    /// asserted rather than argued by
    /// `aFocusableElementNeedsNoHandlerAndAHandlerNeedsNoFocusability`.
    ///
    /// **It is also what keeps focus from dangling.** `Frame.resolveFocus()`
    /// clears the window's focus when the focused id is not in this frame's
    /// focus registry, and this flag is what puts an id there — so an element
    /// that stops being produced, *or* stops being focusable, loses focus at
    /// the prepaint/paint boundary.
    public var isFocusable: Bool = false

    /// Handlers for **bound actions**, keyed by `ObjectIdentifier` of the
    /// action type (design spec §4.1).
    ///
    /// **A dictionary rather than a single closure, because unlike `onClick`
    /// and `onKey` these do not conflict**: an element handling `Copy` and an
    /// element handling `Paste` are the same element, and each
    /// `onAction(_:_:)` writes its own key. A second `onAction` for the *same*
    /// type does replace the first, which is the field-per-modifier rule one
    /// level down.
    ///
    /// **Keyed on the type rather than carried by the closure** so dispatch can
    /// ask "does this element handle this action" without running anything —
    /// which is what lets an action bubble *past* an element that registered
    /// for a different type.
    public var actions: [ObjectIdentifier: ActionHandler] = [:]

    /// The key context this element contributes, or `nil` — framework spec
    /// §8.3's `.keyContext("Editor", ["mode": "code"])`.
    ///
    /// **Contributed by any element, focusable or not** (design spec §4.3, and
    /// a ruling): an ancestor pane names the context while the focused thing
    /// inside it is a leaf that knows nothing about contexts, which is the
    /// whole reason matching runs innermost-first *from the chain* rather than
    /// asking the focused element alone.
    ///
    /// **It is not a pointer target either.** Like `isFocusable`, this goes
    /// through `isKeyTarget` and never through `isPointerTarget`, so a pane
    /// that names a context stays transparent to the pointer and does not
    /// swallow the wheel of a `ScrollView` it sits inside.
    public var keyContext: KeyContext?

    /// The accessibility data this element declares — design spec §9's role,
    /// label, value, traits and actions. `frame` and `children` on the value
    /// stored here are always `AXNode`'s own defaults and cannot be otherwise
    /// — `AXNode`'s own `internal(set)` on both is what enforces that, not a
    /// convention this comment states; they are filled in by
    /// `PrepaintPass.emitAXNode(_:at:id:children:)`, not by a caller.
    ///
    /// **On `Handlers` rather than a fifth `StyledElement` requirement, and the
    /// grounds are this type's own**: AX emission rides the exact registration
    /// call `registerHandlers` already makes (`Frame.registerHandlers` — see there;
    /// reached from `Box`, `Stack` and `Text`'s `prepaint`), so it
    /// is read in `prepaint` by the frame, on `Handlers`' own footing and not
    /// `Decoration`'s (paint data, read only by each conformer's own `paint` —
    /// see this file's own top-of-struct doc). A fifth stored requirement
    /// would additionally need a stored property on every
    /// `StyledElement` conformer that does not already forward to a `Box`
    /// (`Stack`, `List`, `Text` each declare their own `handlers`, unlike
    /// `Column`/`Row`, which forward to an internal `Box`) — riding `Handlers`
    /// costs none of that, because every conformer already stores one.
    ///
    /// **Unlike every other member of this struct, `AXNode` carries no
    /// closure and is `Equatable`** (see `AXActionKind`'s own doc for why
    /// "actions" is descriptive rather than a callback table) — so it does not
    /// take `Handlers` any further from being comparable than it already was,
    /// and `ModifierTests.swift`'s `HandlerShape` projection can carry it as a
    /// whole-value field rather than needing per-member flags the way the
    /// closure-holding members do.
    public var axNode: AXNode = AXNode()

    // MARK: Hit testing (plan task 5, lane 3)
    //
    // **Appended at the END of the stored members**, which is a merge decision
    // rather than taste: a parallel track is editing these files, and
    // added-lines-at-a-known-anchor is a conflict a human resolves in one
    // glance where an interleave is not.

    /// Whether pointer events may reach this element **and everything inside
    /// it** — SwiftUI's `.allowsHitTesting(_:)`.
    ///
    /// **It disables the receiver's OWN hitbox as well as its subtree's**
    /// (ruling `OM-T`). `.onClick` and `.allowsHitTesting` write the same
    /// `Handlers` — on a chain, the same outermost `ModifierLayer`'s — so
    /// `Box().onClick { }.allowsHitTesting(false)` has to be dead, and it is:
    /// `PrepaintPass.registerAndScope` opens the scope BEFORE the receiver's
    /// own `registerHandlers` call (`DecorationScope.swift`). SwiftUI reads
    /// 0 / 0 in both orders (probe `swiftui-content-shape-hit-region`, N1 and
    /// N2), so the legacy path's inability to tell the two orders apart is
    /// **agreement** here rather than a divergence.
    ///
    /// **It removes the pointer target and nothing else.**
    /// `Frame.registerHandlers` gates only the hitbox insert on
    /// `hitTestingDisabledDepth`; focus registration, the `$focus` retention
    /// write, the `focusedElementProducedThisFrame` signal, a declared `AXNode`
    /// and the accessibility record all sit above that gate and keep firing.
    /// SwiftUI keeps the same two halves — a `Button` under
    /// `.allowsHitTesting(false)` is still an `AXButton`, and its
    /// `keyboardShortcut` still fires (probe
    /// `swiftui-allows-hit-testing-side-effects`, arms A1 and K1).
    ///
    /// **Not folded into `isPointerTarget`.** That gate answers "did this
    /// element ask for a hitbox at all"; this one is a *scope* that covers
    /// descendants too, and only a scope can reach an `onClick` declared three
    /// levels down.
    ///
    /// **A `ScrollView` inside the scope still scrolls** (ruling `OM-AK`):
    /// `Frame.registerScrollRegion` reaches `insertHitbox` without passing the
    /// depth gate. Recorded rather than changed here, and pinned by
    /// `aScrollRegionInsideAllowsHitTestingFalseIsStillRegistered`.
    public var allowsHitTesting: Bool = true

    /// How far to inset this element's hit region from its own box, or `nil`
    /// for the box itself — a rect-only subset of SwiftUI's
    /// `.contentShape(_:)` (ruling `OM-J`).
    ///
    /// **It configures a hit region; it does not create one** (ruling
    /// `OM-AB`). `Frame.registerHandlers` inserts a hitbox only when
    /// `handlers.isPointerTarget`, so this field on an element with no
    /// `onClick` is written and never read — the same shape as a
    /// `hoverBackground` with no `onClick`, which never paints.
    ///
    /// **Applied in exactly one place**: the bounds `Frame.registerHandlers`
    /// hands `insertHitbox`. Focus registration, the `$focus` write, the
    /// declared `AXNode` and the accessibility record all keep the element's
    /// own bounds, which is what
    /// `aContentShapeMovesNeitherTheAccessibilityFrameNorTheFocusRegistration`
    /// pins.
    ///
    /// A **negative** inset grows the region, as SwiftUI's does (probe
    /// `swiftui-content-shape-hit-region` H5), and the result is still
    /// intersected with the active clip, as every hitbox is — where SwiftUI's
    /// is not (H6, ruling `OM-AJ`). An inset larger than the box leaves an
    /// empty region rather than an inside-out one: `Frame.intersect` clamps a
    /// negative extent to zero and `Bounds.contains` is half-open, so nothing
    /// can hit it.
    public var contentShapeInset: Edges<Pixels>?

    public init() {}

    /// Whether this element is a **pointer** hit target — the hitbox gate.
    ///
    /// `onClick` alone, deliberately: see the type's own doc comment for why
    /// folding focus in here would stop a list of focusable rows scrolling.
    var isPointerTarget: Bool { onClick != nil }

    /// Whether this element has anything to say about the **keyboard** — the
    /// focus-registry gate (`FocusRegistry.register(_:id:)`).
    ///
    /// **Four things now, not two**, and the last two arrived with Task 10: an
    /// action handler and a key context are both keyboard-side asks and both
    /// must reach the registry. `keyContext` in particular *must* be here and
    /// not behind focusability — a pane contributing `Editor` is usually
    /// neither focusable nor a key handler, and gating it on either would make
    /// `.keyContext(_:_:)` an API that compiles and does nothing on exactly the
    /// elements that use it.
    var isKeyTarget: Bool {
        onKey != nil || isFocusable || !actions.isEmpty || keyContext != nil
    }
}
