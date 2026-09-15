import MetalUICore
import MetalUILayout
import MetalUIText

// Spec §4.1: "`LayoutPass` / `PrepaintPass` / `PaintPass` are thin structs over
// one `@MainActor final class Frame`, exposing only what is legal in that phase
// — emitting a rect during layout is a compile error."
//
// Each struct below is a reference to the same `Frame` plus a *surface*. The
// enforcement is entirely in what is absent: `LayoutPass` has no `fill` and no
// `bounds(of:)`, so an element that tries either does not build. Nothing here is
// checked at runtime, and nothing here can be checked by a runtime test — see
// `PhaseSeparationTests`, which compiles fixtures against the built module.
//
// The initialisers are `internal`. An element outside `MetalUI` receives a pass
// or has none; it cannot make one.

/// Phase 1. Elements contribute style and layout nodes; the engine has not run,
/// so no resolved geometry exists to ask for.
@MainActor
public struct LayoutPass {
    let frame: Frame

    init(frame: Frame) { self.frame = frame }

    /// The space offered to the root, in logical points.
    public var contentSize: Size<Pixels> { frame.contentSize }

    /// Registers a node with `style` and already-registered `children`, and
    /// returns its id. Children are registered before their parent, so an
    /// element builds bottom-up.
    public func requestNode(style: Style, children: [LayoutNodeID]) -> LayoutNodeID {
        frame.requestNode(style: style, children: children)
    }

    /// Registers a **leaf**: a node with no children that answers for its own
    /// size through `measure` (spec §3.1, §5.5).
    ///
    /// `measure` is `@Sendable` and non-isolated — the engine calls it from
    /// wherever it is running — so what it may capture is decided by the
    /// compiler and not by convention. `Text.requestLayout` is the worked
    /// example: a `@MainActor` cache is capturable (a global-actor class is
    /// implicitly `Sendable`), a `CTFont` is not, and the block must reduce to
    /// a `SizeD` before it returns.
    ///
    /// Public because a leaf is how *anything* that is not a box gets a size —
    /// spec §3.1 names text, images and embedded app content — and an element
    /// outside this module has no other way to report one.
    public func requestLeaf(style: Style,
                            measure: @escaping MeasureFunction) -> LayoutNodeID {
        frame.requestLeaf(style: style, measure: measure)
    }

    // MARK: Native registrars — typed (ruling MC-G)
    //
    // **Every native registrar returns a `ProposalNodeID` and takes them as
    // children**, and `ProposalNodeID`'s initializer is `internal`, so outside
    // `MetalUI` a native child can only be a node one of these returned
    // (`aNativeRegistrarRejectsALegacyChild`,
    // `aProposalLayoutContainerOnlyAcceptsTypedChildren`). They wrap and unwrap
    // around `Frame`'s untyped registrars, which are unchanged and keep the
    // run-time traps of ruling SA-G as the backstop for what the type cannot see
    // (`ProposalNodeID.swift`'s seven holes). Until lane 3 of the
    // modifier-composition track these took and returned `LayoutNodeID`.

    /// Registers a leaf measured by the native SwiftUI-style layout path.
    ///
    /// The closure receives the parent's proposal rather than CSS known and
    /// available spaces. A native node cannot contain a legacy child, and a
    /// legacy node cannot contain a native one: both trap at registration
    /// (ruling SA-G). The typed id makes the first a compile error for any child
    /// a native registrar is handed (ruling MC-G); the traps stay for a legacy
    /// node reached some other way.
    public func requestNativeLeaf(measure: @escaping ProposalMeasureFunction) -> ProposalNodeID {
        ProposalNodeID(frame.requestNativeLeaf(measure: measure))
    }

    /// Registers a native `ZStack`-style overlay container.
    public func requestNativeOverlay(children: [ProposalNodeID],
                                     alignment: ProposalAlignment = .center) -> ProposalNodeID {
        ProposalNodeID(frame.requestNativeOverlay(children: children.map(\.layoutNodeID),
                                                  alignment: alignment))
    }

    /// Registers a native overlay attachment: `overlay` measured against
    /// `child`'s resolved size, without changing it.
    public func requestNativeOverlayAttachment(child: ProposalNodeID, overlay: ProposalNodeID,
                                               alignment: ProposalAlignment = .center) -> ProposalNodeID {
        ProposalNodeID(frame.requestNativeOverlayAttachment(child: child.layoutNodeID,
                                                            overlay: overlay.layoutNodeID,
                                                            alignment: alignment))
    }

    /// Registers a native SwiftUI-style frame around one native child.
    public func requestNativeFrame(child: ProposalNodeID, width: Double? = nil,
                                   height: Double? = nil,
                                   minWidth: Double? = nil, idealWidth: Double? = nil,
                                   maxWidth: Double? = nil,
                                   minHeight: Double? = nil, idealHeight: Double? = nil,
                                   maxHeight: Double? = nil,
                                   alignment: ProposalAlignment = .center) -> ProposalNodeID {
        ProposalNodeID(frame.requestNativeFrame(child: child.layoutNodeID, width: width, height: height,
                                                minWidth: minWidth, idealWidth: idealWidth,
                                                maxWidth: maxWidth,
                                                minHeight: minHeight, idealHeight: idealHeight,
                                                maxHeight: maxHeight,
                                                alignment: alignment))
    }

    /// Registers native outer padding around one native child.
    public func requestNativePadding(child: ProposalNodeID,
                                     insets: Edges<Double>) -> ProposalNodeID {
        ProposalNodeID(frame.requestNativePadding(child: child.layoutNodeID, insets: insets))
    }

    /// Registers native fixed-size behavior around one native child.
    public func requestNativeFixedSize(child: ProposalNodeID,
                                       horizontal: Bool = true,
                                       vertical: Bool = true) -> ProposalNodeID {
        ProposalNodeID(frame.requestNativeFixedSize(child: child.layoutNodeID,
                                                    horizontal: horizontal, vertical: vertical))
    }

    /// Registers native aspect-ratio proposal behavior around one native child.
    public func requestNativeAspectRatio(child: ProposalNodeID, ratio: Double,
                                         contentMode: AspectRatioContentMode = .fit) -> ProposalNodeID {
        ProposalNodeID(frame.requestNativeAspectRatio(child: child.layoutNodeID, ratio: ratio,
                                                      contentMode: contentMode))
    }

    /// Registers native stack layout priority around one proposal-layout child.
    public func requestNativeLayoutPriority(child: ProposalNodeID, priority: Double) -> ProposalNodeID {
        ProposalNodeID(frame.requestNativeLayoutPriority(child: child.layoutNodeID, priority: priority))
    }

    /// Registers a native flexible spacer for a native linear stack.
    public func requestNativeSpacer(minLength: Double? = nil) -> ProposalNodeID {
        ProposalNodeID(frame.requestNativeSpacer(minLength: minLength))
    }

    /// Registers a clipped proposal-layout viewport around one native child.
    /// The element owns clipping and the interactive scroll offset; this node
    /// establishes only the parent-proposal/content-measurement relationship.
    public func requestNativeScrollViewport(child: ProposalNodeID,
                                            axis: ProposalStackAxis) -> ProposalNodeID {
        ProposalNodeID(frame.requestNativeScrollViewport(child: child.layoutNodeID, axis: axis))
    }

    /// Registers a native linear stack for the proposal-layout migration.
    public func requestNativeLinearStack(children: [ProposalNodeID], axis: ProposalStackAxis,
                                         spacing: Double = 0,
                                         alignment: ProposalAlignment = .center) -> ProposalNodeID {
        ProposalNodeID(frame.requestNativeLinearStack(children: children.map(\.layoutNodeID), axis: axis,
                                                      spacing: spacing, alignment: alignment))
    }

    /// Registers a custom `ProposalLayout` algorithm over native children.
    ///
    /// The element-side mirror of `LayoutTree.newNativeLayout(_:children:)`.
    /// `ProposalLayoutContainer` is the ready-made element over it; an element
    /// with its own paint or input is a `ProposalElement` that calls
    /// `content.requestProposalGroupLayout` and then this, as `HStack` calls
    /// `requestNativeLinearStack`.
    public func requestNativeLayout(_ layout: some ProposalLayout,
                                    children: [ProposalNodeID]) -> ProposalNodeID {
        ProposalNodeID(frame.requestNativeLayout(layout, children: children.map(\.layoutNodeID)))
    }

    /// Reads back a node's current `Style`, so a caller that registered a node
    /// earlier in this same layout pass can amend rather than replace it.
    /// `StyledComponent`'s only production caller (`Component.swift`).
    ///
    /// **`internal`, not `public`, and deliberately so — narrowed by the fix
    /// wave.** This pair is a read-back-and-overwrite on a raw
    /// `LayoutNodeID`, and a `LayoutNodeID` is not scoped to whoever minted it:
    /// as `public` these two let *any* out-of-module element read and overwrite
    /// the `Style` of any node it can name — a sibling's, a parent's — during
    /// the request phase, with no signal to the node's owner. Nothing outside
    /// `MetalUI` needs that: `StyledComponent` is in-module and amends only the
    /// nodes its own component just returned. Shipping public surface with one
    /// in-module caller is what this repo's inert-API discipline refuses;
    /// widening later is trivial and unshipping is not. Pinned by
    /// `layoutPassStyleAccessorsAreNotPublic` (`ErasureCompileGuards.swift`), which
    /// must use a **plain** import — `@testable` widens `internal` and cannot
    /// demonstrate a narrowing at all (taxonomy shape 16, ruling `TB-N`).
    func style(_ id: LayoutNodeID) -> Style {
        frame.style(id)
    }

    /// Overwrites a node's `Style` in place. `LayoutTree.setStyle`'s only
    /// production caller: registration derives nothing from style, so this is
    /// sound at any point before `computeLayout` runs, which is exactly the
    /// window this pass exists for. **`internal` for the reason stated at
    /// `style(_:)` above**, which is this method's reason more than that one's:
    /// the read is harmless on its own and the overwrite is what makes the pair
    /// reach through a boundary.
    func setStyle(_ id: LayoutNodeID, _ style: Style) {
        frame.setStyle(id, style)
    }

    /// The window's shaping cache (spec §3.2).
    ///
    /// **Internal, unlike everything else on this pass.** It is the one member
    /// here that is not a phase capability: an element author outside `MetalUI`
    /// has no `ResolvedFont` to shape with and no reason to reach a text cache,
    /// while `Text` — which lives inside — needs the instance the window owns so
    /// that shapes survive the frame. Making it public would also make
    /// `ShapingCache`'s whole surface part of `MetalUI`'s API by reachability.
    var shapingCache: ShapingCache { frame.shapingCache }

    /// Whether this frame records accessibility (`Frame.collectsAccessibility`).
    var collectsAccessibility: Bool { frame.collectsAccessibility }

    /// The innermost active `ScrollView`'s ambient context, or `nil` outside
    /// one — `ScrollView.requestLayout` is the sole publisher, via
    /// `withScrollContext` below.
    ///
    /// **The offset is CURRENT; the viewport extent is ONE FRAME STALE**, and
    /// that split is the whole reason this exists rather than `ScrollView`
    /// simply resolving and clamping the offset itself here. A scroll that
    /// landed before this frame (`Window.applyScroll` writes it, then dirties
    /// the window) is visible; the viewport is pure layout output and cannot
    /// exist until layout runs, so the only way to have one during layout is
    /// to have stored last frame's. `List` is the reader: it knows its own
    /// content extent as `count × rowHeight` and clamps against that itself,
    /// so this value is deliberately unclamped raw state, not a resolved
    /// offset.
    ///
    /// **A `ScrollView`'s very first frame publishes `ScrollContext(offset: 0,
    /// viewportExtent: 0, axis:)`**, because `ScrollState.viewportExtent` has
    /// no writer until `prepaint` has run once. **This is NOT a divide-by-zero
    /// hazard for a reader like `List`**, and an earlier version of this
    /// paragraph wrongly said it was — corrected after `List`'s own arithmetic
    /// was measured. `viewportExtent` only ever appears as a NUMERATOR in that
    /// arithmetic (e.g. `(offset + viewportExtent) / rowHeight`); dividing IT
    /// by zero would need `viewportExtent` to be a divisor somewhere, and it
    /// never is. `0` as a numerator just gives `0`. The real zero-divisor
    /// hazard is a reader's own `rowHeight`, a value this pass knows nothing
    /// about.
    ///
    /// What zero viewport extent DOES cause, for a reader that does not
    /// special-case it: `offset` on that first frame is whatever was last
    /// scrolled to, so a naive window bounds almost nothing around it — a
    /// list with a nonzero row count computes only a couple of rows near
    /// `offset` (measured directly: exactly `overscan`'s worth on each side of
    /// zero), and the rest fills in only once frame two has a real viewport —
    /// a one-frame flash on first appearance. Neither is this pass's defect;
    /// it is an input a consumer (`List`) must design against, and this is the
    /// doc a reader of THIS property will actually open.
    public var scrollContext: ScrollContext? {
        frame.activeScrollContext
    }

    /// The ambient animation transaction for this build, or `nil` — spec §3's
    /// "the next frame build carries that animation as ambient context on the
    /// passes, the way `LayoutPass.scrollContext` already is". Set once per
    /// drawn frame by `Window`, from whatever `withAnimation` parked since the
    /// last build.
    ///
    /// **`internal`, where `scrollContext` above is `public`**, and the
    /// asymmetry is deliberate rather than an oversight: `scrollContext` is
    /// read by `List`, an element, so it must be reachable from outside this
    /// module. This is read only by `animated(_:_:for:pass:)`, and an element
    /// outside `MetalUI` has no animatable state to apply it to — it would be
    /// API with no possible consumer. It becomes `public` in the change that
    /// gives an external element something to do with it.
    var transaction: Animation? { frame.transaction }

    /// Runs `body` with `context` as the innermost active scroll context and
    /// returns whatever `body` returns.
    ///
    /// **Closure form, exactly as `PrepaintPass.clipped(to:offsetBy:_:)`, and
    /// for the same reason**: a push with no matching pop is not expressible,
    /// so a sibling declared after a `ScrollView` (rather than inside it)
    /// cannot inherit a context it was never meant to see. Generic over `R`
    /// so `ScrollView.requestLayout` can thread its subtree's return value
    /// straight out, with no local `!`-typed variable to hoist it through.
    public func withScrollContext<R>(_ context: ScrollContext, _ body: () -> R) -> R {
        frame.pushScrollContext(context)
        defer { frame.popScrollContext() }
        return body()
    }

    /// Runs `body` with **no** active scroll context, whatever was active
    /// outside it — `Deferred`'s layout-phase half of the portal.
    ///
    /// `Deferred` resets the clip stack and the accumulated scroll translation
    /// in `prepaint` and `paint` (`PaintPass.deferred`), so its subtree does
    /// not move with the `ScrollView` it was declared inside. Layout had no
    /// equivalent until this existed, and the mismatch was measurable rather
    /// than theoretical: a `List` inside `Deferred { … }` inside a scroller
    /// windowed against that scroller's offset while paint placed the rows it
    /// chose at their unscrolled positions, so the portal's list emptied out
    /// as the list behind it was scrolled. Building everything is the same
    /// answer a `List` with no enclosing `ScrollView` at all gets, which is
    /// what a subtree that has escaped every scroller is.
    ///
    /// Pushing an absent level rather than popping the enclosing one is
    /// deliberate: popping would expose the *next* `ScrollView` out in a
    /// nested pair, and a portal escapes all of them.
    public func withoutScrollContext<R>(_ body: () -> R) -> R {
        frame.pushAbsentScrollContext()
        defer { frame.popScrollContext() }
        return body()
    }
}

/// Phase 2. Layout has resolved, so absolute bounds are known — but nothing has
/// been painted yet, which is what makes this the only correct place to register
/// hit-test, focus, scroll and accessibility structure.
///
/// **Scroll, general hit-test, focus and accessibility all register now.**
/// `registerScrollRegion` was the first `register…` method this pass gained
/// and `insertHitbox` is the second, and they write to the same hitbox
/// registry on `Frame` — the first is the second with a scroll axis attached
/// (design spec §3.1). Focus is the third, and it has **no method of its
/// own**: `registerHandlers` writes both the hitbox and `Frame`'s focus
/// registry, because an element that binds a click and an element that binds a
/// key are the same element asking through the same `Handlers` value, and two
/// calls would be two chances for a conformer to forget one. `emitAXNode`
/// below is the fourth, and it writes its own store, `Frame.axNodes` (design
/// spec §9), rather than riding `registerHandlers` the way focus does. The
/// data it writes — `Handlers.axNode` — does live alongside the other three,
/// on `Handlers`' own footing; the *call* stays separate because most
/// elements declare nothing accessible at all (`AXNode.isEmpty`), and a
/// conformer gates it on that rather than emitting an entry for every `Box`
/// unconditionally the way `registerHandlers` does for hitboxes and focus.
@MainActor
public struct PrepaintPass {
    let frame: Frame

    init(frame: Frame) { self.frame = frame }

    public var contentSize: Size<Pixels> { frame.contentSize }

    /// A node's resolved bounds, absolute to the root.
    public func bounds(of node: LayoutNodeID) -> Bounds<Pixels> { frame.bounds(of: node) }

    /// Runs `body` with `bounds` intersected into the active clip and `offset`
    /// added to the active translation.
    ///
    /// **Closure form rather than push/pop, so an unbalanced stack is not
    /// expressible.** A `pushClip` without its `popClip` would silently clip
    /// every later sibling in the frame.
    ///
    /// **On `PrepaintPass` as well as `PaintPass`, and that is not symmetry for
    /// its own sake**: a scroll region's on-screen position depends on ancestor
    /// scrolls, so a nested `ScrollView` that its parent has scrolled out of
    /// view must not receive wheel events.
    ///
    /// `bounds(of:)` on this pass is unaffected by the stack — it keeps
    /// returning the engine's untranslated geometry, same as `PaintPass`'s.
    /// Translation and clipping are properties of what a pass *does* with
    /// geometry, not of the geometry itself.
    ///
    /// `cornerRadii` defaults to a square clip, so every call site written
    /// before this parameter existed keeps compiling and clipping exactly as
    /// before. It has no direct reader on THIS pass — prepaint emits nothing —
    /// but it keeps the clip stack's radii correct for anything pushed deeper
    /// during prepaint, which matters the moment a `ScrollView` nests inside
    /// a rounded one.
    public func clipped(to bounds: Bounds<Pixels>,
                        offsetBy offset: Point<Pixels>,
                        cornerRadii: Corners<Pixels> = Corners(all: Pixels(0)),
                        _ body: () -> Void) {
        frame.pushClip(bounds, offset: offset, radii: cornerRadii)
        defer { frame.popClip() }
        body()
    }

    /// Records a region that consumes scroll wheel events.
    ///
    /// **`insertHitbox` with a scroll axis attached, into the same list** —
    /// design spec §3.1's fold. Kept as its own spelling because a scroller is
    /// the one kind of hitbox with a payload, and because the two decisions it
    /// makes for its caller (`opaque: true`, and which axis) are the whole of
    /// what distinguishes it.
    ///
    /// Registration happens here rather than in `paint` because §8.1 requires
    /// it after positions resolve and before the first primitive is emitted —
    /// prepaint is the phase between the two.
    public func registerScrollRegion(_ bounds: Bounds<Pixels>, id: GlobalElementID,
                                     axis: ScrollAxis) {
        frame.registerScrollRegion(bounds, id: id, axis: axis)
    }

    /// Registers a hitbox for `id` at `bounds`, returning a handle to it.
    ///
    /// Design spec §3.2, and §8.1 of the framework spec before it: registration
    /// belongs here because prepaint is the only phase where positions have
    /// resolved and nothing has been emitted yet.
    ///
    /// The content mask and the layer come from the active stacks rather than
    /// from parameters — §8.1 sketched `insertHitbox(bounds, contentMask,
    /// opaque:)`, and by the time this landed the clip stack already carried
    /// the mask, so passing one would be a second source for a quantity the
    /// frame already knows. `bounds` is translated and clipped on the way in;
    /// see `Frame.insertHitbox`.
    ///
    /// **`opaque: false` is not "invisible"** — the hitbox is registered and
    /// listed, and `Frame.topmostHitbox(at:)` walks straight through it to
    /// whatever is beneath.
    ///
    /// The returned handle is valid for **this frame only**: the list is
    /// rebuilt each frame. Anything that has to survive a frame keys on the
    /// `GlobalElementID` passed in here instead.
    @discardableResult
    public func insertHitbox(_ bounds: Bounds<Pixels>, id: GlobalElementID,
                             opaque: Bool) -> HitboxID {
        frame.insertHitbox(bounds, id: id, opaque: opaque)
    }

    /// Registers `handlers`: an **opaque** hitbox at `bounds` when it carries a
    /// pointer callback, an entry in this frame's focus registry when it
    /// carries a keyboard one, and nothing at all when it carries neither.
    ///
    /// **Two gates, not one, and the separation is load-bearing.** A hitbox is
    /// opaque, and an opaque hitbox swallows the wheel of any `ScrollView` it
    /// sits inside (`Window.applyScroll`) — so registering one for every
    /// *focusable* element would stop a list of focusable rows scrolling. See
    /// `Handlers` for both gates and `focusabilityAndKeyHandlingRegisterNoPointerHitbox`
    /// for the pin.
    ///
    /// **Focus registration needs no geometry and rides here anyway.** Nothing
    /// on the keyboard side reads `bounds`; the registration is folded into
    /// this call so a conformer writes one line rather than two and cannot
    /// implement half of `StyledElement`'s `handlers` requirement.
    ///
    /// **`insertHitbox` with a handler set attached, into the same list** —
    /// the click half of design spec §3.1's fold, and `registerScrollRegion`'s
    /// exact shape one field over. Kept as its own spelling for
    /// `registerScrollRegion`'s reason: the two decisions it makes for its
    /// caller (`opaque: true`, and *whether to register at all*) are the whole
    /// of what distinguishes it from the general call above.
    ///
    /// **The empty-set gate is the load-bearing half.** An element with no
    /// handlers must not register: an opaque hitbox for every `Box` would
    /// shadow whatever it covers and would swallow the wheel of any
    /// `ScrollView` it sits inside, since Task 7 made a wheel event stop at the
    /// topmost opaque hitbox whatever that hitbox is. So `onClick` is what
    /// makes a box a hit target, and a box without one stays transparent.
    ///
    /// Public rather than internal because `StyledElement` and its `handlers`
    /// requirement are public: an element type outside this module can store a
    /// `Handlers` and would otherwise have no way to make it do anything —
    /// which is precisely CLAUDE.md's declared-and-inert shape, arrived at by
    /// access control instead of by omission.
    ///
    /// **Under `.disabled(true)` it registers no hitbox and no focus**, whatever
    /// `handlers` holds, and a declared AX node gains `.disabled` — the one
    /// disabled gate, read from `environment.isEnabled` (rulings EV-E, EV-F;
    /// see `Frame.registerHandlers`). An element calling it needs no check of
    /// its own.
    public func registerHandlers(_ handlers: Handlers, at bounds: Bounds<Pixels>,
                                 id: GlobalElementID) {
        frame.registerHandlers(handlers, at: bounds, id: id)
    }

    /// Whether this frame records accessibility (`Frame.collectsAccessibility`).
    var collectsAccessibility: Bool { frame.collectsAccessibility }

    /// `registerHandlers` with what only an in-module conformer can say to an
    /// accessibility client: a text leaf's string, and whether it synthesizes a
    /// node at all (ruling AB-Y). Its two callers are `Text.prepaint` and
    /// `OnTapModifier.prepaint`. See `Frame.registerHandlers`.
    func registerHandlers(_ handlers: Handlers, at bounds: Bounds<Pixels>,
                          id: GlobalElementID, accessibleText: String? = nil,
                          synthesizesAccessibility: Bool = true) {
        frame.registerHandlers(handlers, at: bounds, id: id, accessibleText: accessibleText,
                               synthesizesAccessibility: synthesizesAccessibility)
    }

    /// Runs `body` with pointer hitbox registration enabled or disabled.
    ///
    /// This scope deliberately leaves focus and keyboard registration live.
    /// SwiftUI-style hit-testing modifiers answer whether pointer events enter
    /// a subtree; they do not erase that subtree's keyboard behaviour.
    public func allowsHitTesting(_ enabled: Bool, _ body: () -> Void) {
        guard !enabled else {
            body()
            return
        }
        frame.withHitTestingDisabled(body)
    }

    /// Records `node` as `id`'s accessibility node, resolving its `frame` to
    /// `bounds` and its `children` to the ids given — design spec §9.
    ///
    /// **The same phase, and the same shape, as `insertHitbox` and
    /// `registerHandlers` above** (`Passes.swift:238,278` — this task's own
    /// brief cites both): prepaint is the only phase where positions have
    /// resolved and nothing has been emitted yet, so it is the only correct
    /// place to register accessibility structure alongside hit-test and focus
    /// structure. Emitting here rather than in `paint` is also what makes
    /// culled content naturally excluded — an element `paint` never visits
    /// never calls this either.
    ///
    /// `node`'s own `frame` and `children` are ignored on the way in and
    /// overwritten by `bounds` and `children` — see `AXNode`'s own doc on why
    /// a declared value carries neither meaningfully.
    ///
    /// Returns the resolved node, for a caller that wants to build a parent's
    /// own children list from what its children just emitted without a second
    /// lookup into `Frame.axNodes`.
    @discardableResult
    public func emitAXNode(_ node: AXNode, at bounds: Bounds<Pixels>, id: GlobalElementID,
                           children: [GlobalElementID]) -> AXNode {
        frame.emitAXNode(node, at: bounds, id: id, children: children)
    }

    /// Runs `body` with the layer hoisted to the root layer and the clip
    /// stack reset to the whole surface — `Deferred`'s portal (design spec
    /// §4.2). See `PaintPass.deferred(_:)` for the full account of why a
    /// portal resets both.
    ///
    /// **On this pass, and not only `PaintPass`, because of hit-testing.**
    /// Both registries — scroll regions and hitboxes — are built here, in
    /// prepaint: a tooltip that paints above its siblings while receiving
    /// events as if it were still beneath them is worse than one that does
    /// neither. Both halves of the portal have a reader on this pass, and they
    /// close different holes:
    ///
    /// - the **clip reset**, because a hitbox is recorded against whatever clip
    ///   is active at registration time, so something registered inside
    ///   `deferred` is recorded against the whole surface rather than an
    ///   ancestor `ScrollView`'s viewport. It also takes the reset *offset*,
    ///   which is what stops a modal's scrim from tracking a scroll it is not
    ///   in flow for (ruling AP-I) — and since scroll regions fold into the
    ///   same list, that now holds for a scroller inside a portal too;
    /// - the **layer hoist**, because every registration carries `activeLayer`
    ///   and `topmostOpaqueHitbox(in:at:)` ranks by it. A hoisted subtree is
    ///   still *emitted* where it was declared, so it can register before
    ///   something it paints on top of; registration order alone would then
    ///   hand the event to the covered element.
    ///
    /// Closure form rather than push/pop, for the reason `clipped(to:offsetBy:)`
    /// above already gives: an unbalanced stack is not expressible.
    public func deferred(_ body: () -> Void) {
        frame.pushLayer()
        frame.pushRootClip()
        defer {
            frame.popClip()
            frame.popLayer()
        }
        body()
    }
}

/// Phase 3. Primitives are emitted here and nowhere else.
@MainActor
public struct PaintPass {
    let frame: Frame

    init(frame: Frame) { self.frame = frame }

    public var contentSize: Size<Pixels> { frame.contentSize }

    /// A node's resolved bounds, absolute to the root, **untranslated**.
    ///
    /// This is engine geometry, not what lands in the scene: `fill` and `draw`
    /// apply the active clip/translate stack (`clipped(to:offsetBy:)` below) on
    /// the way to the scene, so a caller who filled its own `bounds(of:)`
    /// result inside a `clipped` block is translated automatically. Reading a
    /// translation back out here so a caller could apply it a second time is
    /// exactly the hazard this pass avoids by exposing no `scaleFactor`.
    public func bounds(of node: LayoutNodeID) -> Bounds<Pixels> { frame.bounds(of: node) }

    /// The width layout **measured** this node at, before `roundStoredRects`
    /// rounded it — for an element that must re-derive its own content and
    /// needs to ask the question layout asked.
    ///
    /// **`bounds(of:)` above is the width to LAY OUT against; this is the width
    /// to MEASURE against, and confusing them is what divergence 8 was.** The
    /// rounded box is what the node occupies and what its siblings closed
    /// against; the unrounded width is what its own measure function was given.
    /// They differ by under a point and that is enough: `Text.paint` re-asking
    /// `CTTypesetter` at the rounded width put a whole extra line in a box one
    /// line tall, about half the time, as a function of `frac(x + width)`.
    ///
    /// **Width only, and no origin** — see `LayoutTree.measuredWidth(_:)`.
    /// Painting at a fractional origin is the thing rounding exists to prevent.
    public func measuredWidth(of node: LayoutNodeID) -> Double {
        frame.tree.measuredWidth(node)
    }

    /// The active theme (spec §7.9): the nearest `.theme(_:)`, else the
    /// window's (ruling EV-G).
    ///
    /// This is the whole of "propagated through the frame context": an element
    /// that wants a colour resolves a `ColorToken` against this, and there is no
    /// other way to obtain one. Nothing here reads global state, and nothing
    /// cascades — `Style` has no colour field for a cascade to inherit through,
    /// and a scoped theme is a value handed out at a position, not a property
    /// written into every node.
    ///
    /// **Deliberately not on `LayoutPass` or `PrepaintPass`.** Neither phase can
    /// consume a colour: layout contributes `Style`, which has no colour field,
    /// and prepaint reads resolved rects. See `Frame.theme`.
    public var theme: Theme { frame.theme }

    /// This frame's display-link timestamp, in seconds. Identical for every
    /// element in one frame.
    public var timestamp: Double { frame.timestamp }

    /// Ask for another frame after this one — for an animation in progress.
    public func requestAnotherFrame() { frame.requestAnotherFrame() }

    /// The ambient animation transaction for this build, or `nil`. The paint
    /// half of `LayoutPass.transaction` — `animatedColor(_:for:pass:)` reads
    /// it, for the same reason and with the same visibility.
    var transaction: Animation? { frame.transaction }

    /// Emits a filled rect, **in logical points**.
    ///
    /// The display scale factor is applied here, once, on the way to the scene.
    /// Element code neither needs it nor can reach it: this pass deliberately
    /// exposes no `scaleFactor`, because an element that found one would have no
    /// way to know it had already been applied, and pre-scaling its bounds
    /// double-scales them on any Retina display. `cornerRadii` is scaled with
    /// them, for the same reason.
    ///
    /// **The active clip/translate stack is applied here too, for the same
    /// reason.** `bounds` is offset by `clipped(to:offsetBy:)`'s accumulated
    /// translation and the emitted rect's mask is the intersected clip, both
    /// scaled to match. `bounds(of:)` above never reflects either, so `bounds`
    /// passed in here is always untranslated engine geometry — the same
    /// geometry a caller outside any `clipped` block would pass, and the two
    /// look identical to a caller either way, which is the point.
    public func fill(_ bounds: Bounds<Pixels>, color: Hsla,
                     cornerRadii: Corners<Pixels> = Corners(all: Pixels(0)),
                     borderColor: Hsla = .transparent,
                     borderWidths: Edges<Pixels> = Edges(all: Pixels(0))) {
        frame.fill(bounds, color: color, cornerRadii: cornerRadii,
                   borderColor: borderColor, borderWidths: borderWidths)
    }

    /// Multiplies the opacity of every primitive emitted by `body`.
    public func opacity(_ value: Float, _ body: () -> Void) {
        precondition((0...1).contains(value), "opacity must be in 0...1")
        frame.pushOpacity(value)
        defer { frame.popOpacity() }
        body()
    }

    /// Runs `body` with `bounds` intersected into the active clip and `offset`
    /// added to the active translation. See `PrepaintPass.clipped(to:offsetBy:_:)`
    /// for why this exists on both passes and why a closure rather than
    /// push/pop.
    ///
    /// **This is what makes `fill` and `draw` translate and clip automatically**
    /// — a child inside this block that fills its own `bounds(of:)` result
    /// scrolls correctly while knowing nothing about scrolling, exactly as
    /// `fill`'s doc above says it needs no `scaleFactor`.
    ///
    /// `cornerRadii` rounds the mask every `fill`/`draw` inside `body` is cut
    /// to — the mechanism ruling CL-A records. Defaults to a square clip, so
    /// every call site written before this parameter existed keeps compiling
    /// and painting identically.
    public func clipped(to bounds: Bounds<Pixels>,
                        offsetBy offset: Point<Pixels>,
                        cornerRadii: Corners<Pixels> = Corners(all: Pixels(0)),
                        _ body: () -> Void) {
        frame.pushClip(bounds, offset: offset, radii: cornerRadii)
        defer { frame.popClip() }
        body()
    }

    /// Runs `body` with the layer hoisted to the root layer and the clip
    /// stack reset to the whole surface — `Deferred`'s portal (design spec
    /// §4.2).
    ///
    /// **Two things, and the second is the surprising one.** The layer hoist
    /// is what makes `fill`/`draw` inside `body` stamp `Frame.rootLayer`, so
    /// `Scene.finalize()`'s `(layer, order, sequence)` sort draws the whole
    /// subtree after every ordinary-layer sibling, whatever their own
    /// `order`. The clip reset is what makes it a **portal** rather than a
    /// plain layer hoist: `body` runs with `activeClip` at the whole surface
    /// and `activeOffset` at zero, not with whatever an ancestor
    /// `clipped(to:offsetBy:)` left active. A modal inside a `ScrollView`
    /// therefore covers the window instead of being clipped to the scroll
    /// viewport and sliding with its content — the resulting divergence from
    /// CSS (which clips an absolutely-positioned descendant unless its
    /// containing block sits outside the clipper) is recorded in the design
    /// spec §2 and §7.2, and is deliberate: do not "fix" it toward CSS.
    ///
    /// Closure form, exactly as `clipped(to:offsetBy:)` above, so an
    /// unbalanced stack — one that hoists without ever restoring — is not
    /// expressible.
    public func deferred(_ body: () -> Void) {
        frame.pushLayer()
        frame.pushRootClip()
        defer {
            frame.popClip()
            frame.popLayer()
        }
        body()
    }

    // MARK: - Text
    //
    // Three internal members, for `LayoutPass.shapingCache`'s reason and one
    // more. They are not phase capabilities: an element author outside
    // `MetalUI` has no `ResolvedFont` to shape with, no `PlacedGlyph` to draw
    // and — the extra reason — no business seeing a scale factor at all, which
    // is stated at `fill` above. Making any of them public would put
    // `ShapingCache`'s and `GlyphAtlas`'s whole surface into `MetalUI`'s API by
    // reachability, and would hand an element the double-scaling hazard `fill`
    // exists to remove.
    //
    // Text is inside this module, so it needs no public seam. When an element
    // *outside* it needs to draw glyphs, the public API is a `Text`-shaped one
    // rather than these three.

    /// The window's shaping cache (spec §3.2). See `LayoutPass.shapingCache`.
    var shapingCache: ShapingCache { frame.shapingCache }

    /// Logical points to device pixels for this frame's target.
    ///
    /// **The one place in the paint phase that may read it**, because a glyph
    /// bitmap is rasterized on the device grid and its placement is therefore
    /// stated there and not in points. `fill` applies the same factor itself
    /// and must not be handed pre-scaled bounds.
    var scaleFactor: Float { frame.scaleFactor }

    /// Emits one glyph sprite. See `Frame.draw(_:color:)`.
    func draw(_ glyph: PlacedGlyph, color: Hsla) {
        frame.draw(glyph, color: color)
    }

    // MARK: - Hover and active (design spec §3.3, §3.4)

    /// Whether `id` — a handle returned from **this frame's** `insertHitbox`
    /// call, in `prepaint` — is the topmost hitbox under the pointer.
    ///
    /// Resolved once, at the prepaint/paint boundary (`Frame.resolveHover(at:)`),
    /// against every hitbox the frame registered — not computed here and not
    /// per-call, so two elements asking in the same frame see the same answer
    /// regardless of which asks first, and there is no one-frame lag between a
    /// hitbox registering and this returning the right thing for it.
    ///
    /// A `HitboxID` is the right key here, not `GlobalElementID`: hover is
    /// per-frame state resolved from a position, the opposite of `isActive`
    /// below, which must survive frames `HitboxID` cannot (see `HitboxID`'s own
    /// doc comment).
    public func isHovered(_ id: HitboxID) -> Bool {
        frame.hoveredHitbox == id
    }

    /// Whether the pointer is over the hitbox `id` registered — the same
    /// question as the overload above, asked with the key an element actually
    /// has.
    ///
    /// **Not a second mechanism.** It reads the one resolution
    /// `Frame.resolveHover(at:)` performed, through `Frame.hoveredElement`, so
    /// the two overloads cannot disagree about a frame.
    ///
    /// **It exists because `registerHandlers` returns nothing.** The
    /// `HitboxID`-keyed overload is the precise one and is what
    /// `PrepaintPass.insertHitbox`'s callers should use, a `HitboxID` naming
    /// one registration; but `PrepaintPass.registerHandlers(_:at:id:)` — the
    /// path every `StyledElement` takes — hands back no index, so `Box` and
    /// every other conformer has only its `GlobalElementID` when `paint` runs.
    /// Adding a return value there instead would change `Box.PrepaintState`,
    /// which is `Content.GroupPrepaint`, and ripple through every container's
    /// associated types; this overload is the same answer for one line.
    ///
    /// The two keys coincide only because an element registers at most one
    /// hitbox — see `Frame.hoveredElement` for the whole of that argument.
    public func isHovered(_ id: GlobalElementID) -> Bool {
        frame.hoveredElement == id
    }

    /// Whether `id` is holding "active" state — the element whose hitbox
    /// received `mouseDown` and has not yet seen `mouseUp` (design spec §3.4).
    ///
    /// Keyed by `GlobalElementID`, unlike `isHovered(_:)` above, because active
    /// state is cross-frame by definition: it must survive every frame between
    /// the two events, including one in which the element holding it was
    /// rebuilt. `Window` is the sole writer — see `Frame.activeElement`'s doc
    /// comment for why a `Frame` cannot own it.
    public func isActive(_ id: GlobalElementID) -> Bool {
        frame.activeElement == id
    }

    /// Whether `id` holds keyboard focus — what a focus ring is drawn from
    /// (design spec §4.2).
    ///
    /// Keyed by `GlobalElementID` for `isActive`'s reason: focus is window
    /// state that survives every frame between the two events that move it, and
    /// a per-frame index cannot key anything that outlives its frame.
    ///
    /// **This is the frame's RESOLVED answer, not the value `Window` handed
    /// in.** `Frame.resolveFocus()` runs at the prepaint/paint boundary and
    /// clears a focused id this frame did not produce, so an element that
    /// vanished — or stopped being `.focusable()` — reads as unfocused on the
    /// very frame that drops it rather than one frame late.
    ///
    /// **Paint only, and unlike `isActive` that is a measured restriction
    /// rather than symmetry.** During `prepaint` the focus registry is still
    /// being built, so the clearing above has not happened yet and this would
    /// answer from the pre-clearing value: measured, a focused element that has
    /// stopped registering as focusable reads `true` in its own `prepaint` and
    /// `false` in its own `paint` in the same frame.
    /// `queryingFocusDuringPrepaintDoesNotCompile` is the guard.
    public func isFocused(_ id: GlobalElementID) -> Bool {
        frame.focusedElement == id
    }
}

// MARK: - Cross-frame state (§4.3)

// Three identical methods rather than one protocol extension, and the
// duplication is deliberate.
//
// A `StatefulPass` protocol would need `var frame: Frame { get }` as a public
// requirement, which forces `frame` public on all three passes — and that hands
// element authors the whole `Frame` surface, defeating the phase separation this
// file exists to enforce. Measured: `error: property 'frame' must be declared
// public because it matches a requirement in public protocol 'StatefulPass'`.
//
// **The leak is `pass.frame.scaleFactor`, not `pass.frame.fill(...)`.** An
// earlier version of this comment named `fill`, which is wrong — `Frame.fill` is
// internal, so it stays uncallable from outside the module even with `frame`
// public. `scaleFactor` is public on `Frame`, so it would become reachable
// through any pass — including `PaintPass`, whose own doc says it must not be,
// because `fill` has already applied it and a caller who applies it again
// double-scales. Verified from an external module both ways.
//
// An *internal* `StatefulPass` protocol compiles, but then `withState` is
// inaccessible to element authors outside the module — which the compile guards
// in `PhaseSeparationTests` now catch.
//
// Available in **all three** phases, unlike everything else here. Phase
// separation stops an element doing a phase's work in the wrong phase;
// cross-frame state is not a phase's work. A scroll offset is read during layout
// to decide what is visible, updated during prepaint from the last frame's
// input, and read again during paint. Restricting it to one phase would force
// elements to smuggle it through `LayoutState`, which is the aliasing hazard
// `AnyElementBox` exists to avoid.

extension LayoutPass {
    /// Read-modify-write this element's cross-frame state, creating it from
    /// `initial` on first access (§4.3).
    ///
    /// **Every element has an identity, so there is no unidentified case.** This
    /// took a `GlobalElementID?` and discarded an unnamed element's state as
    /// scratch; structural identity replaced that with a `.positional` component
    /// derived from the element's index in its container, and the compiler now
    /// enforces the presence of a key rather than a comment describing one. See
    /// `ElementGroup.requestGroupLayout` for where the index comes from.
    @MainActor
    public func withState<S>(_ id: GlobalElementID,
                             initial: @autoclosure () -> S,
                             _ body: (inout S) -> Void) {
        frame.stateTable.withState(id, initial: initial(), body)
    }
}

extension PrepaintPass {
    /// See `LayoutPass.withState(_:initial:_:)`.
    @MainActor
    public func withState<S>(_ id: GlobalElementID,
                             initial: @autoclosure () -> S,
                             _ body: (inout S) -> Void) {
        frame.stateTable.withState(id, initial: initial(), body)
    }
}

extension PaintPass {
    /// See `LayoutPass.withState(_:initial:_:)`.
    @MainActor
    public func withState<S>(_ id: GlobalElementID,
                             initial: @autoclosure () -> S,
                             _ body: (inout S) -> Void) {
        frame.stateTable.withState(id, initial: initial(), body)
    }
}

// MARK: - Environment (rulings EV-C, EV-L)
//
// **Get-only on all three passes, and readable in all three.** A setter here
// would be an unscoped push: a write in one element's phase would change what
// every later sibling reads, the cascade leak ruling EV-A exists to prevent.
// Writers are modifiers (`EnvironmentScope`). Pinned by the typecheck guard
// `environmentValuesCannotBeWrittenThroughAPass`.
//
// **No phase-only guard** (ruling EV-L): within one frame and one scope the
// three accessors return identical values, because the root is fixed before
// the frame starts and a scope re-pushes the values it computed in layout.
// There is no prepaint/paint boundary for a value to lie across. The theme is
// not reachable here — `EnvironmentValues.theme` is internal and
// `PaintPass.theme` is its only reader (ruling EV-G).
//
// Each read is a copy of the frame's current environment and counts one
// `Frame.environmentSnapshotCount` (ruling EV-O).

extension LayoutPass {
    /// The environment at this element's position. See the section note above.
    public var environment: EnvironmentValues { frame.environmentSnapshot() }
}

extension PrepaintPass {
    /// The environment at this element's position. See the section note above.
    public var environment: EnvironmentValues { frame.environmentSnapshot() }
}

extension PaintPass {
    /// The environment at this element's position. See the section note above.
    public var environment: EnvironmentValues { frame.environmentSnapshot() }
}
