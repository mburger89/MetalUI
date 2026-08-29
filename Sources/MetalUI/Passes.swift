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

    /// The window's shaping cache (spec §3.2).
    ///
    /// **Internal, unlike everything else on this pass.** It is the one member
    /// here that is not a phase capability: an element author outside `MetalUI`
    /// has no `ResolvedFont` to shape with and no reason to reach a text cache,
    /// while `Text` — which lives inside — needs the instance the window owns so
    /// that shapes survive the frame. Making it public would also make
    /// `ShapingCache`'s whole surface part of `MetalUI`'s API by reachability.
    var shapingCache: ShapingCache { frame.shapingCache }

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
/// **Scroll registers now; general hit-test, focus and accessibility still do
/// not.** `registerScrollRegion` below is the first `register…` method this
/// pass gained, and it is deliberately scoped to scroll rather than general —
/// see its doc comment. `Frame` still owns no hitbox, focus or accessibility
/// store, so there is nothing for a broader `register…` method to write into
/// and none is declared; input and focus bring theirs (M3), accessibility
/// brings its own (§9).
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
    /// **A hitbox list scoped to scroll, not the general hit-test system** —
    /// see `Frame.scrollRegions`'s doc comment for the split and what §8.1
    /// widens later.
    ///
    /// Registration happens here rather than in `paint` because §8.1 requires
    /// it after positions resolve and before the first primitive is emitted —
    /// prepaint is the phase between the two.
    public func registerScrollRegion(_ bounds: Bounds<Pixels>, id: GlobalElementID,
                                     axis: ScrollAxis) {
        frame.registerScrollRegion(bounds, id: id, axis: axis)
    }

    /// Runs `body` with the layer hoisted to the root layer and the clip
    /// stack reset to the whole surface — `Deferred`'s portal (design spec
    /// §4.2). See `PaintPass.deferred(_:)` for the full account of why a
    /// portal resets both.
    ///
    /// **On this pass, and not only `PaintPass`, because of hit-testing.**
    /// The scroll-region registry is built here, in prepaint — a tooltip that
    /// paints above its siblings while receiving wheel events as if it were
    /// still beneath them is worse than one that does neither. Both halves of
    /// the portal have a reader on this pass, and they close different holes:
    ///
    /// - the **clip reset**, because `registerScrollRegion` records a region
    ///   intersected against whatever clip is active at registration time, so
    ///   a region registered inside `deferred` is recorded against the whole
    ///   surface rather than an ancestor `ScrollView`'s viewport;
    /// - the **layer hoist**, because the registration carries `activeLayer`
    ///   and `Window.applyScroll` orders candidates by it. A hoisted subtree is
    ///   still *emitted* where it was declared, so it can register before a
    ///   region it paints on top of; registration order alone would then hand
    ///   the wheel to the covered scroller. `Frame.scrollRegions` carries the
    ///   reasoning.
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

    /// The active theme (spec §7.9).
    ///
    /// This is the whole of "propagated through the frame context": an element
    /// that wants a colour resolves a `ColorToken` against this, and there is no
    /// other way to obtain one. Nothing here reads global state, and nothing
    /// cascades — `Style` has no colour field for a cascade to inherit through.
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
                     cornerRadii: Corners<Pixels> = Corners(all: Pixels(0))) {
        frame.fill(bounds, color: color, cornerRadii: cornerRadii)
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
