import MetalUICore
import MetalUILayout
import MetalUIRender
import MetalUIText

/// The single owner of one frame's mutable state (spec §4.1).
///
/// `LayoutPass`, `PrepaintPass` and `PaintPass` are thin structs over this
/// class; the state lives here exactly once, and each pass exposes the slice of
/// it that its phase may touch. Making the *passes* own state instead would
/// force it to be copied or shared between phases, which is the bug the split
/// exists to prevent.
///
/// **`init` and every phase operation are `internal` on purpose.** The
/// compile-time guarantee that an element cannot paint during layout rests
/// entirely on an element being unable to obtain a pass it was not handed: from
/// outside `MetalUI` there is no way to construct a `Frame` and no way to
/// construct a `PaintPass`. Inside the module the compiler does not stop you —
/// that half is a convention, and `codeOutsideTheFrameworkCannotFabricateAPaintPass`
/// pins the half that is enforced.
@MainActor
public final class Frame {
    /// The space offered to the root element, in logical points.
    public let contentSize: Size<Pixels>

    /// Logical points to device pixels for this frame's target. Applied once,
    /// in `fill`, so element code never has to think about it.
    public let scaleFactor: Float

    /// This frame's display-link timestamp, in seconds — identical for every
    /// element in this frame, because it is read once here rather than by each
    /// element calling a wall clock.
    ///
    /// **A borrowed M4 primitive** (spec §8 of the clipping/scroll design): the
    /// input to a time-based animation, not an animation system. Defaulted to
    /// `0` so every existing `Frame(...)` call site in the corpus and the test
    /// suite keeps compiling unchanged; `Window` is the only production caller
    /// that passes a real one.
    public let timestamp: Double

    /// The last known mouse position, or `nil` before any mouse event has ever
    /// reached the window. `Window` is the only owner of "last known" — it
    /// survives across frames the way `timestamp`'s underlying clock does not —
    /// and hands the current value in here on construction, the same way it
    /// hands in `theme` and `timestamp`.
    ///
    /// This is the input `resolveHover(at:)` reads at the prepaint/paint
    /// boundary (design spec §3.3). Defaulted to `nil` for the same reason
    /// `timestamp` defaults to `0`: every existing `Frame(...)` call site keeps
    /// compiling, and a frame built with no position registers no hover at all
    /// — there is nothing to resolve against.
    let mousePosition: Point<Pixels>?

    /// The element holding "active" state this frame — the hitbox that
    /// received `mouseDown` and has not yet seen `mouseUp` (design spec §3.4).
    ///
    /// **Handed in from `Window`, not computed here**, because active state
    /// must survive the frames between `mouseDown` and `mouseUp` and a `Frame`
    /// does not: it is discarded at the end of `drawFrameIfNeeded`
    /// (`Window.swift`). Keyed by `GlobalElementID` rather than `HitboxID` for
    /// `HitboxID`'s own reason — a per-frame index cannot key anything that
    /// outlives the frame that issued it.
    let activeElement: GlobalElementID?

    /// Set by an element that needs another frame — an in-progress animation.
    ///
    /// **A borrowed M4 primitive** (spec §8 of the clipping/scroll design): the
    /// input to animation, not an animation system. `Window` reads it after
    /// render and marks itself dirty, which unpauses the display link.
    private(set) var wantsAnotherFrame = false

    /// Ask for another frame after this one — for an animation in progress.
    func requestAnotherFrame() { wantsAnotherFrame = true }

    /// True once anything in this frame has reported an `Animation` that is
    /// still interpolating **after this frame's own update** — the property
    /// M4 spec 1 refused to declare without a writer (ruling `RX-O`), and the
    /// one the binding design spec §4.4's idle guard is written in terms of.
    ///
    /// **It must see BOTH animation subsystems, and computing it from layout
    /// alone is the way to get this wrong.** `animated(_:_:for:pass:)`
    /// (`AnimatedStyle.swift`) animates `Style`/`Decoration` from `LayoutPass`
    /// through the `$anim` slot; `animatedColor(_:for:pass:)`
    /// (`AnimatedColor.swift`) animates the resolved background colour from
    /// `PaintPass` through `$anim-color`, because only `PaintPass` carries a
    /// theme. A colour fade on an element whose `Style` never changes raises
    /// nothing during layout, so a layout-only criterion would be a fade that
    /// stops the instant input stops arriving. Both helpers call
    /// `noteActiveAnimation()`; `Window` reads this AFTER the whole of
    /// `render` — layout, prepaint and paint — so the paint-phase contribution
    /// arrives in time with no ordering change.
    ///
    /// **A per-frame answer, not a latch.** It is `false` on the frame a
    /// duration curve lands on its target (termination is exact, so nothing is
    /// left in flight), which is precisely what lets the display link pause on
    /// the frame *after* the last animation ends rather than one frame later.
    ///
    /// **Distinct from `wantsAnotherFrame` above, and after this task nothing
    /// raises both.** `wantsAnotherFrame` means "mark the window DIRTY next
    /// frame" and its one caller is `ScrollView`'s scroll-indicator fade, which
    /// predates the `Animation` type and drives itself by dirtying. This means
    /// "an `Animation` is interpolating", and it keeps the loop running
    /// *without* dirtying the window — so a window mid-fade reports
    /// `needsRedraw == false`, which is true: nobody changed anything.
    private(set) var hasActiveAnimations = false

    /// Report that an `Animation` in this frame is still interpolating.
    func noteActiveAnimation() { hasActiveAnimations = true }

    /// The transaction this build inherited from a `withAnimation` that ran
    /// since the last one — spec §3's "the **next frame build** carries that
    /// animation as ambient context on the passes, the way
    /// `LayoutPass.scrollContext` already is".
    ///
    /// A `let`, for `theme`'s reason: the two halves of one frame must not
    /// resolve the same transition under different animations. `Window` takes
    /// it from `Animation.parkedTransaction` once per drawn frame and hands it
    /// in here; a `Frame` built by a test defaults to `nil` and its callers
    /// fall back to the lexical `Animation.pendingTransaction`.
    let transaction: Animation?

    /// CSS's `rem` basis for `Length.rem`. One value per frame.
    ///
    /// **M2 came and went without making this settable, and that was a
    /// decision rather than an oversight.** This comment used to predict that
    /// "the text system may make it settable in M2". It did not: `Text` carries
    /// its own `fontSize` in points and never consults this value, and `Frame`
    /// is only ever constructed with the 16 default from `Window` — so a `rem`
    /// still resolves against 16 whatever font a `Text` is using. The two are
    /// unrelated quantities that share a word: this one is the *document* root
    /// font size CSS resolves `rem` against, and M2 supplies a *per-element*
    /// size. Wiring one to the other needs a root-level text style, which no
    /// element has. Measured rather than assumed: `grep -rn "rootFontSize:"
    /// Sources/ Tests/` finds no caller that passes it to a `Frame` at all, so
    /// the default below is the only value the engine has ever seen.
    let rootFontSize: Double

    /// The active theme (spec §7.9), fixed for the whole frame.
    ///
    /// A `let`, so the two halves of one frame cannot resolve the same token
    /// differently: a theme swapped mid-paint would give the first half of the
    /// tree light colours and the second half dark ones, and every rect would
    /// still be individually correct. `Window` swaps the theme *between* frames
    /// and marks §4.4's dirty flag.
    ///
    /// Reachable from `PaintPass` only. Nothing in layout or prepaint consumes a
    /// colour — `LayoutPass` contributes `Style`, which has no colour field at
    /// all, and `PrepaintPass` reads resolved rects — so exposing it there would
    /// be an API with no reader. Adding it to another pass is one forwarding
    /// property when a phase acquires a use for it.
    let theme: Theme

    /// Layout nodes for this frame.
    ///
    /// **A `LayoutNodeID` *can* outlive the frame that minted it, which is why
    /// the tree is stamped.** It was tempting to argue the opposite — a `Frame`
    /// is built per frame, its tree is never `reset`, so id and storage die
    /// together — but that is a claim about the tree, not about the id, and the
    /// id is a `Sendable` value an element may copy anywhere. The carrier that
    /// makes m1a's ruling C-3 reachable here is `pass.withState`: its `S` is
    /// unconstrained, so an element may stash a `LayoutNodeID` in the
    /// cross-frame state table and read it back next frame, against a tree that
    /// no longer knows it. Nothing in the type system prevents that, and a
    /// stored property on a reused element value is a second, narrower route.
    ///
    /// So the hazard is closed rather than argued away: every `Frame` draws a
    /// fresh generation from `nextTreeGeneration`, and `LayoutTree` rejects an
    /// id from any other. A stale id now traps at the accessor instead of
    /// silently returning whatever node shares its index.
    let tree: LayoutTree

    /// Source of `LayoutTree` generations, one per `Frame`, never reused.
    ///
    /// A plain `static var` and not an atomic: it is isolated to the main actor
    /// by `Frame`'s own `@MainActor`, so the compiler — not a comment — is what
    /// rules out a concurrent increment. `UInt64` at one per frame overflows
    /// after about 10^11 years at 120 Hz.
    private static var nextTreeGeneration: UInt64 = 1

    /// Primitives emitted during paint. Written only through `fill`.
    private(set) var scene = Scene()

    /// Clip and translation, innermost last. Both are in **logical points**;
    /// `fill` and `draw` scale on the way to the scene as they already do.
    ///
    /// **This is emission state, not geometry.** `bounds(of:)` keeps returning
    /// what the engine computed, untranslated — a child that fills its own
    /// resolved bounds is translated automatically and needs to know nothing
    /// about scrolling. It is the same division `fill` already makes for the
    /// scale factor, and for the same reason: a caller who could see the value
    /// would apply it a second time.
    private var clipStack: [(clip: Bounds<Pixels>, offset: Point<Pixels>, radii: Corners<Pixels>)] = []

    /// The clip currently in effect, in logical points. The whole surface when
    /// no `clipped(to:offsetBy:)` block is active — the same "no clip" answer
    /// `fill`/`draw` always passed before this stack existed.
    var activeClip: Bounds<Pixels> {
        clipStack.last?.clip ?? Bounds(origin: Point(x: Pixels(0), y: Pixels(0)),
                                       size: contentSize)
    }

    /// The corner radii of the clip currently in effect, in logical points.
    /// All zero — a square clip — when no `clipped(to:offsetBy:)` block is
    /// active, or when one is active but was pushed with no radii (every call
    /// site written before this existed).
    var activeClipRadii: Corners<Pixels> {
        clipStack.last?.radii ?? Corners(all: Pixels(0))
    }

    /// The translation currently in effect, in logical points. Zero when no
    /// `clipped(to:offsetBy:)` block is active.
    var activeOffset: Point<Pixels> {
        clipStack.last?.offset ?? Point(x: Pixels(0), y: Pixels(0))
    }

    /// Layers, shaped exactly like `clipStack` above and for the same reason:
    /// `deferred` pushes one, `fill`/`draw` stamp whichever is active, and the
    /// closure form that pushes it keeps the stack balanced.
    private var layerStack: [Int] = []

    /// The layer currently in effect. `0` — ordinary paint order — when no
    /// `deferred` block is active, the same "nothing special" answer
    /// `activeClip` gives an empty `clipStack`.
    var activeLayer: Int { layerStack.last ?? 0 }

    /// `deferred`'s hoist target. One constant, not a counter: design spec §1
    /// rules out an arbitrary stacking-context system, so `Deferred` is a
    /// single hoist and every instance — nested or not — lands on the same
    /// layer.
    static let rootLayer = 1

    /// Pushes the root layer. Balanced by `popLayer`, reached only through
    /// `deferred`'s `defer`.
    func pushLayer() { layerStack.append(Self.rootLayer) }

    /// Pops one level pushed by `pushLayer`.
    func popLayer() { layerStack.removeLast() }

    /// Pushes an **intersected** clip (radii included, see `intersect(_:radii:_:radii:)`)
    /// and an **accumulated** offset.
    ///
    /// Intersection rather than replacement is what makes nesting correct: an
    /// inner clip wider than its outer must not widen it, or a nested scroller
    /// paints over its parent's chrome. Pinned by
    /// `nestedClipsIntersectRatherThanReplace`.
    func pushClip(_ bounds: Bounds<Pixels>, offset: Point<Pixels>,
                 radii: Corners<Pixels> = Corners(all: Pixels(0))) {
        let (clip, clipRadii) = Self.intersect(activeClip, radii: activeClipRadii,
                                               bounds, radii: radii)
        let composed = Point(x: Pixels(activeOffset.x.value + offset.x.value),
                             y: Pixels(activeOffset.y.value + offset.y.value))
        clipStack.append((clip, composed, clipRadii))
    }

    /// Pops one level pushed by `pushClip` (or `pushRootClip` below —
    /// `clipStack` does not distinguish how a level was pushed, only how it is
    /// popped). Callers reach this only through `clipped(to:offsetBy:)`'s or
    /// `deferred`'s `defer`, which is what keeps the stack balanced — see
    /// those methods' doc comments.
    func popClip() { clipStack.removeLast() }

    /// Pushes a clip covering the whole surface with **no accumulated
    /// offset** — `Deferred`'s escape, as opposed to `pushClip`'s intersect-
    /// and-accumulate. `Deferred` is a portal (spec §4.2): a modal painted
    /// from inside a scrolled `ScrollView` must not inherit that scroll's
    /// translation any more than it inherits the viewport's clip, or it would
    /// slide with the content it is meant to cover. Popped exactly like an
    /// ordinary level, by `popClip`.
    func pushRootClip() {
        clipStack.append((Bounds(origin: Point(x: Pixels(0), y: Pixels(0)), size: contentSize),
                          Point(x: Pixels(0), y: Pixels(0)),
                          Corners(all: Pixels(0))))
    }

    /// The innermost active `ScrollView`'s ambient context.
    ///
    /// **What it shares with `clipStack` above is the nesting discipline, and
    /// nothing else.** Both are pushed before descending into a subtree and
    /// popped after via `defer` — through `LayoutPass.withScrollContext` here,
    /// `PrepaintPass`/`PaintPass.clipped(to:offsetBy:)` there — so nesting and
    /// an unbalanced push behave the same way in both. They do **not** share a
    /// phase, a payload or an escape rule: this one exists only during
    /// `requestLayout`, carries a scroll offset rather than a rectangle, and
    /// `Deferred`'s portal reaches it by `pushAbsentScrollContext` below rather
    /// than by `pushRootClip`. An earlier version of this comment said the two
    /// were shaped "exactly alike and for the same reason", which read as
    /// "`Deferred` resets this too" at a time when nothing reset it at all.
    ///
    /// **The element is `ScrollContext?`, not `ScrollContext`, because
    /// `Deferred` must be able to push the ABSENCE of one.** A subtree that has
    /// escaped a scroller's clip and translation has escaped its windowing too,
    /// so it needs the answer a subtree outside every `ScrollView` gets — and
    /// popping the enclosing entry instead would expose the *next* scroller
    /// out, which is a different wrong answer.
    private var scrollContextStack: [ScrollContext?] = []

    /// The scroll context currently in effect, or `nil` outside every
    /// `ScrollView`'s subtree — the same "nothing special" answer `activeClip`
    /// gives an empty `clipStack`. A `nil` pushed by
    /// `pushAbsentScrollContext` reads back identically, by design.
    var activeScrollContext: ScrollContext? {
        scrollContextStack.last ?? nil
    }

    /// Pushes a scroll context. Balanced by `popScrollContext`, reached only
    /// through `LayoutPass.withScrollContext`'s `defer`.
    func pushScrollContext(_ context: ScrollContext) {
        scrollContextStack.append(context)
    }

    /// Pushes the ABSENCE of a scroll context — `Deferred`'s layout-phase
    /// escape, the counterpart to `pushRootClip` on the clip stack.
    ///
    /// A `Deferred` subtree paints against the whole surface at zero offset
    /// (ruling AP-I: escaping the clip without the offset is half a portal),
    /// so a `List` inside one is not being scrolled by the `ScrollView` it was
    /// declared in and must not window against that scroller's offset. Popped
    /// exactly like an ordinary level, by `popScrollContext`.
    func pushAbsentScrollContext() {
        scrollContextStack.append(nil)
    }

    /// Pops one level pushed by `pushScrollContext` or
    /// `pushAbsentScrollContext`.
    func popScrollContext() {
        scrollContextStack.removeLast()
    }

    /// The axis-aligned intersection of two bounds. Either dimension can go to
    /// zero (or below, clamped to zero) when the two do not overlap; it never
    /// goes negative.
    static func intersect(_ a: Bounds<Pixels>, _ b: Bounds<Pixels>) -> Bounds<Pixels> {
        let x0 = max(a.origin.x.value, b.origin.x.value)
        let y0 = max(a.origin.y.value, b.origin.y.value)
        let x1 = min(a.origin.x.value + a.size.width.value,
                     b.origin.x.value + b.size.width.value)
        let y1 = min(a.origin.y.value + a.size.height.value,
                     b.origin.y.value + b.size.height.value)
        return Bounds(origin: Point(x: Pixels(x0), y: Pixels(y0)),
                      size: Size(width: Pixels(max(0, x1 - x0)),
                                 height: Pixels(max(0, y1 - y0))))
    }

    /// The axis-aligned intersection of two clips, **carrying radii** — the
    /// half of ruling CL-A's follow-on this milestone closes.
    ///
    /// **Two rounded rects do not intersect into a rounded rect in general**:
    /// the true shape can need a distinct curve at each corner where the two
    /// rounded regions overlap. This function does not attempt that shape. It
    /// uses two cases where a rounded intersection collapses exactly, and
    /// falls back to a square-cornered box otherwise:
    ///
    /// 1. **`outer` has NO rounding at all**, and `inner`'s bounding box sits
    ///    inside `outer`'s (touching an edge is fine — a straight edge has no
    ///    curve to interact with). `outer` then contributes nothing to the
    ///    shape at all, so the intersection is exactly `inner`, radii and all.
    ///    This is the common case: a single top-level `ScrollView` pushes its
    ///    first clip against the frame's whole-surface (zero-radius) default,
    ///    and its own bounds are routinely FLUSH with that default — a
    ///    full-bleed list has no padding to keep it "strictly" inside.
    /// 2. **`inner`'s bounding box sits STRICTLY inside `outer`'s** — not
    ///    touching or crossing any of its four edges — regardless of
    ///    `outer`'s own rounding. The intersection of the two REGIONS still
    ///    reduces to `inner` alone here: `outer`'s curve only removes area
    ///    outside its own bounding box, which `inner` never reaches. This is
    ///    what a NESTED `ScrollView` gets — one rounded clip strictly inside
    ///    another — once ordinary padding is in play.
    ///
    /// **What this gets wrong, on purpose, and why nothing in this corpus
    /// notices.** Case 2's containment check is against `outer`'s bounding
    /// BOX, not its rounded shape: an `inner` clip that sits inside `outer`'s
    /// box but reaches into the disk `outer`'s OWN corner rounds away — a
    /// small `inner` clip tucked into `outer`'s corner — is still accepted as
    /// "strictly inside" and keeps `inner`'s radii un-clipped by `outer`'s
    /// curve there, so a corner of `inner` can paint past where the true
    /// intersection would stop. Not reachable today: `ScrollView` is the only
    /// production caller and nests at most one clip inside another, so no
    /// fixture or test in this corpus nests two DIFFERENTLY-rounded clips
    /// close enough to a shared corner to see it. Whenever neither case
    /// applies — `outer` is itself rounded AND `inner` merely touches or
    /// crosses its bounding box, or is larger than it — this falls back to
    /// the plain intersected box (`intersect(_:_:)` above) with SQUARE
    /// corners: the tighter box, rounding dropped rather than guessed at.
    static func intersect(_ outer: Bounds<Pixels>, radii outerRadii: Corners<Pixels>,
                          _ inner: Bounds<Pixels>, radii innerRadii: Corners<Pixels>)
        -> (bounds: Bounds<Pixels>, radii: Corners<Pixels>) {
        let bounds = intersect(outer, inner)

        let containedNonStrict =
            inner.origin.x.value >= outer.origin.x.value &&
            inner.origin.y.value >= outer.origin.y.value &&
            inner.origin.x.value + inner.size.width.value
                <= outer.origin.x.value + outer.size.width.value &&
            inner.origin.y.value + inner.size.height.value
                <= outer.origin.y.value + outer.size.height.value
        let outerIsSquare = outerRadii.topLeft == Pixels(0) && outerRadii.topRight == Pixels(0) &&
            outerRadii.bottomRight == Pixels(0) && outerRadii.bottomLeft == Pixels(0)
        if outerIsSquare && containedNonStrict {
            return (bounds, innerRadii)
        }

        let strictlyInside =
            inner.origin.x.value > outer.origin.x.value &&
            inner.origin.y.value > outer.origin.y.value &&
            inner.origin.x.value + inner.size.width.value
                < outer.origin.x.value + outer.size.width.value &&
            inner.origin.y.value + inner.size.height.value
                < outer.origin.y.value + outer.size.height.value
        return strictlyInside ? (bounds, innerRadii) : (bounds, Corners(all: Pixels(0)))
    }

    /// Scroll regions registered this frame, in prepaint order — a **derived
    /// view** of `hitboxes` below, not a list of its own.
    ///
    /// **This used to be a second registry and is not one any more** (design
    /// spec §3.1). It was a hitbox list in miniature — bounds intersected with
    /// the active clip, carrying a layer, registered in prepaint, picked by
    /// `(layer, registration order)` — and it differed from the general list in
    /// exactly two ways, both of which were defects rather than features: it
    /// tracked no opacity, so nothing could swallow a wheel event, and it
    /// recorded its bounds **untranslated** while `insertHitbox` translated
    /// them, so a `ScrollView` nested inside an already-scrolled `ScrollView`
    /// registered in the wrong space and lost **part of its hit area** — the
    /// part the untranslated rect misses — to whatever is underneath (ruling
    /// IN-F, pinned by
    /// `aNestedScrollViewInsideAScrolledOneReceivesTheWheelWhereItPaints`).
    /// **Not all of it**, and the difference matters to anyone diagnosing this:
    /// measured on that test's own fixture with the fix reverted, a wheel at
    /// `(100, 120)` went to the OUTER scroller while one at `(100, 170)` still
    /// reached the inner one. "No events at all" was true only of Task 5's
    /// degenerate probe, whose ancestor clip happened to cut the misplaced rect
    /// to zero height; generalising from it would send someone who tests the
    /// lower half of a nested scroller away satisfied.
    ///
    /// Kept as an accessor because a scroller is the one kind of hitbox with a
    /// payload, and "the scrolling ones" is a question several tests ask. The
    /// tuple shape is preserved so every assertion written against the old
    /// registry keeps reading the same fields.
    ///
    /// **Test observability, and it has ZERO production readers** — the same
    /// status `Window.lastScrollRegions` states in its own first line, and the
    /// reason this sentence exists is that the two used to disagree about
    /// saying so. `Window.applyScroll` ranks against `lastHitboxes` directly,
    /// `Window.lastScrollRegions` derives its own view from that same array
    /// rather than calling this one, and every other consumer went with them
    /// when the two lists folded into one.
    ///
    /// **Check with `grep -rn "scrollRegions" Sources/`, which returns five
    /// lines and no call site at all**: this declaration; the line you are
    /// reading and one in `Window.swift`, both doc comments; and two references
    /// in `Hitbox.swift`'s prose. **The pattern is case-sensitive, so it does
    /// NOT match `Window.lastScrollRegions`' own declaration** — it finds one
    /// declaration, not two, and a case-INSENSITIVE sweep
    /// (`grep -rni "scrollregions" Sources/`) is what sees both. No count is
    /// quoted for that one on purpose: it also matches every prose mention,
    /// including this paragraph, so it moves whenever the comments move — the
    /// trap the `evictUnusedSince` row in CLAUDE.md has now been caught by
    /// twice. The load-bearing half is "no call site", which
    /// holds under either pattern; the counting half did not survive being run,
    /// and this paragraph is its second draft. It reads
    /// like a live API and is not one — `LayoutTree.reset(generation:)`'s exact
    /// shape, and CLAUDE.md's declared-but-inert table carries the row.
    ///
    /// **`axis` rides along because routing, not `ScrollState`, is what needs
    /// it.** A `ScrollView` already knows its own axis and maps the stored
    /// scalar offset through it (`ScrollView.delta(_:)`), so `ScrollState`
    /// stays a bare `Double`. `Window.applyScroll` is the reader: it has no
    /// other way to know whether a region wants `delta.x` or `delta.y`.
    ///
    /// **`layer` rides along for the same reason `axis` does: routing is what
    /// needs it, and nothing else can recover it.** A `Deferred` subtree paints
    /// above everything through `Frame.pushLayer`, and a scroller inside one
    /// has to *receive* wheel events above everything too — a tooltip that
    /// paints over its siblings while they take its events is worse than one
    /// that does neither (`PrepaintPass.deferred`). Registration order alone
    /// cannot express that: a hoisted subtree is emitted wherever it was
    /// declared, so it can register before a sibling it paints on top of.
    var scrollRegions:
        [(bounds: Bounds<Pixels>, id: GlobalElementID, axis: ScrollAxis, layer: Int)] {
        hitboxes.compactMap { box in
            box.scroll.map { (box.bounds, box.id, $0, box.layer) }
        }
    }

    /// Records a scroll region — an **opaque hitbox carrying a scroll axis**.
    ///
    /// `opaque: true` because a scroller consumes the point it is under: a
    /// non-opaque record is skipped by `topmostOpaqueHitbox(in:at:)` and could
    /// never receive a wheel event at all.
    ///
    /// Everything about *where* the record lands is `insertHitbox`'s, and that
    /// is the whole point of routing through it — the translating convention
    /// used to be `insertHitbox`'s alone and this function's omission of it was
    /// a live routing defect. See `insertHitbox`.
    func registerScrollRegion(_ bounds: Bounds<Pixels>, id: GlobalElementID, axis: ScrollAxis) {
        _ = insertHitbox(bounds, id: id, opaque: true, scroll: axis)
    }

    /// Hitboxes registered this frame, in prepaint order — **the one list**.
    ///
    /// Rebuilt from scratch every frame, exactly like the `LayoutTree` — which
    /// is why a `HitboxID` is a per-frame handle and every record carries a
    /// `GlobalElementID` for anything that must outlive one.
    private(set) var hitboxes: [Hitbox] = []

    /// Records a hitbox at the rect it actually **paints** at: translated by
    /// the active offset, then intersected with the active clip, carrying the
    /// active layer.
    ///
    /// **The translation is what makes a hit land on the pixels the user is
    /// pointing at.** `PaintPass.fill` adds `activeOffset` before emitting, so
    /// a row inside a `ScrollView` scrolled by 30 draws thirty points above
    /// where `bounds(of:)` reports it; a hitbox recorded at the untranslated
    /// rect would sit thirty points below what is on screen, and the error
    /// would grow with the scroll.
    ///
    /// **`registerScrollRegion` used to omit it, and that was a live routing
    /// defect** — ruling IN-F, fixed by folding it through here. `ScrollView.prepaint`
    /// registers *outside* its OWN `clipped(to:offsetBy:)` block, which zeroes
    /// only its own contribution; an **ancestor** scroller's is still in
    /// effect, because the inner element's whole `prepaint` runs inside the
    /// outer's block. Measured through a real `Frame.render` with the outer
    /// scrolled by 50: the inner scroller registered `(0, 150) 200x50` — 50pt
    /// low and cut in half by the ancestor clip — while painting at
    /// `(0, 100) 200x100`, so a wheel over its visible top half went to the
    /// OUTER scroller instead.
    ///
    /// The **clipped** bounds, not the raw ones: a nested scroller positioned
    /// outside its ancestor's viewport window must not receive events for the
    /// area it cannot actually show. Storing the raw, un-intersected bounds
    /// instead would let an event land on a region the user cannot see.
    ///
    /// `id` is a parameter rather than something derived here because the
    /// returned `HitboxID` is a per-frame index and cannot key anything that
    /// survives a frame — hover, active state and a scroller's offset all need
    /// the element's own id. Every prepaint site has one in hand already.
    ///
    /// `scroll` and `handlers` both default to empty — an ordinary hitbox is
    /// neither a scroller nor a click target — so the public
    /// `PrepaintPass.insertHitbox` needs no payload parameter, and
    /// `registerScrollRegion` and `registerHandlers` stay the two spellings
    /// that supply one each.
    func insertHitbox(_ bounds: Bounds<Pixels>, id: GlobalElementID,
                      opaque: Bool, scroll: ScrollAxis? = nil,
                      handlers: Handlers = Handlers()) -> HitboxID {
        let translated = Bounds(
            origin: Point(x: Pixels(bounds.origin.x.value + activeOffset.x.value),
                          y: Pixels(bounds.origin.y.value + activeOffset.y.value)),
            size: bounds.size)
        hitboxes.append(Hitbox(bounds: Self.intersect(activeClip, translated),
                               id: id, layer: activeLayer, opaque: opaque, scroll: scroll,
                               handlers: handlers))
        return HitboxID(index: hitboxes.count - 1)
    }

    /// Records a click target — an **opaque hitbox carrying a handler set** —
    /// and does nothing at all when `handlers` is empty.
    ///
    /// **The empty case is the interesting one**, and it is why this exists
    /// rather than every element calling `insertHitbox` behind its own `guard`.
    /// A hitbox registered for an element that asked for nothing would be
    /// opaque, would shadow whatever it covers, and — since Task 7 folded
    /// scroll regions into this list — would swallow the wheel of any
    /// `ScrollView` it sits inside. Every `Box` in this framework is a
    /// potential caller, so that gate has to be in one place and not in six.
    ///
    /// `opaque: true` for the same reason a scroller is: a click target
    /// consumes the point. Non-opaque would mean a modal scrim could not
    /// swallow clicks aimed at what it covers, which is the sibling property of
    /// the wheel swallow this milestone's exit criterion 4 is about.
    func registerHandlers(_ handlers: Handlers, at bounds: Bounds<Pixels>,
                          id: GlobalElementID) {
        // The keyboard side first, and unconditionally: focus registration is
        // not gated on the pointer gate below, and an element can ask for one
        // without the other. `register` gates itself on `isKeyTarget`.
        focusRegistry.register(handlers, id: id)
        // **Independent of `isKeyTarget`/`isFocusable` — this is "was the
        // currently-focused id produced this frame at all", not "did it ask
        // to stay focused".** `Box.prepaint`, `Stack.prepaint` and
        // `Text.prepaint` call this unconditionally for every produced element
        // of their type (see this method's own doc), so it is the one
        // per-frame signal that fires for `focusedElement` whether or not
        // `handlers` asks for anything. `resolveFocus()` needs exactly that
        // to tell "still produced, gave up `.focusable()`" (clear at once)
        // apart from "not produced this frame" (fall back to the state
        // table's retention window) — `focusRegistry.isFocusable(_:)` alone
        // cannot make that distinction, since a produced-but-uninterested
        // element and an unproduced one both read `false` there.
        if let focused = focusedElement, id == focused {
            focusedElementProducedThisFrame = true
            // Rides `StateTable`'s own tombstone mechanism rather than a
            // focus-specific grace period (design spec §5) — a distinct
            // slot, `$focus`, so this can never collide with a `@State`
            // slot (always a CHILD of the element's own id, named
            // `"$state\(n)"`) or with a `ScrollView`'s own
            // `withState(id, ...)` entry (keyed directly on its own id,
            // typed `ScrollState` — writing `Bool` there would silently
            // clobber it, per `StateTable.write`'s own doc on mismatched
            // types). `resolveFocus()` reads this back with `peek`, which
            // returns non-nil for a live OR a tombstoned entry and nil only
            // once it is actually reaped.
            //
            // **KNOWN, and ruled "record, do not fix" at the whole-branch
            // review: this write is not gated on `handlers.isKeyTarget`, so a
            // `$focus` slot can be written for an element that was never
            // legitimately focusable.** `Window.focus(x)` on a produced but
            // non-focusable `x` reaches here and writes the slot *before*
            // `resolveFocus()` clears the focus later in the same frame. Below
            // `StateTable.sweepThreshold` that slot is never reaped, so a later
            // `Window.focus(x)` made while `x` is NOT produced then **sticks**:
            // `resolveFocus`'s fallback tests only `peek(...) != nil` and never
            // asks whether the slot was written by a frame that also found `x`
            // focusable. The consequence is a wrongly-sticky focus on an
            // element that has never been a key target — not a clobber, not a
            // crash, and not reachable without an explicit `Window.focus` call
            // on a non-focusable element.
            //
            // **Deliberately not fixed, and the reason is the SHAPE of the fix
            // rather than its size.** The obvious patch — gate this write on
            // `isKeyTarget` — cannot be applied on its own, because the
            // *produced* signal set immediately above must stay ungated: it is
            // the only per-frame evidence distinguishing "gave up
            // `.focusable()`" (clear at once) from "not produced" (fall back to
            // retention), and `anElementThatStopsBeingFocusableLosesFocus`
            // depends on exactly that. A correct fix must therefore SEPARATE
            // two things that today share one conditional — keep
            // `focusedElementProducedThisFrame` ungated, gate the slot write on
            // `isKeyTarget`, and clear the slot in `resolveFocus`'s
            // produced-but-not-focusable branch so a stale one cannot outlive
            // the frame that invalidated it. That is a change to the focus
            // contract rather than a patch, and it does not go in unreviewed in
            // the last commit before a merge — the same judgement
            // `Window.applyScroll` was given during the input milestone.
            stateTable.withState(Self.focusRetentionSlot(for: focused),
                                 initial: true) { _ in }
        }
        if handlers.isPointerTarget {
            _ = insertHitbox(bounds, id: id, opaque: true, handlers: handlers)
        }
        // **Accessibility rides here too, and it was not always here.** The
        // gate used to live in `Box.prepaint` alone, so `Stack.prepaint` and
        // `Text.prepaint` — which call this and nothing else — dropped a
        // declared `handlers.axNode` silently.
        // `aDeclaredAXNodeIsEmittedByEveryConformerThatRegistersHandlers`
        // (`AXEmitSiteTests.swift`) is the per-conformer pin. No-op unless
        // something set `handlers.axNode` to something other than `AXNode()`
        // — `AXNode.isEmpty`'s own doc names this as `Handlers`' "empty means
        // not a hit target" rule, one type over.
        //
        // **Kept LAST in this method**, so the `$ax` write follows the
        // `$focus` write above — `Box.prepaint`'s order before this moved, and
        // the order `theSevenRetentionSlotsAreMutuallyDistinct`
        // (`AXNodeTests.swift`) calls the two in by hand. **That test does not
        // pin this ordering, and it is not what keeps it red:** it calls
        // `registerHandlers` with an empty `axNode` and then `emitAXNode`
        // itself. Measured when this moved: its `"$ax"` → `"$focus"` collision
        // mutation reddens it (its `$focus` assertion) with this call last,
        // and ALSO with this call moved above `focusRegistry.register`.
        //
        // **`children` is always `[]` from here**: a generic
        // `Content: ElementGroup` hands `requestGroupLayout` a flat
        // `[LayoutNodeID]`, not a `GlobalElementID` per child
        // (`ElementGroup.swift`), so no container can name its own children's
        // ids without a change to that protocol's associated types (ruling
        // `TB-M`). Whoever assembles a real tree either extends `ElementGroup`
        // for it or walks `GlobalElementID.parent` over the flat `axNodes` map.
        if !handlers.axNode.isEmpty {
            emitAXNode(handlers.axNode, at: bounds, id: id, children: [])
        }
    }

    /// The state-table key that backs a focused id's retention window — see
    /// `registerHandlers`'s own doc for why it must be a distinct slot rather
    /// than `id` itself. `at: 0` is inert: `GlobalElementID.child(of:at:name:)`
    /// always prefers `name` when one is supplied.
    private static func focusRetentionSlot(for id: GlobalElementID) -> GlobalElementID {
        .child(of: id, at: 0, name: ElementID("$focus"))
    }

    // MARK: - Accessibility (design spec §9)

    /// Every accessibility node emitted this frame, keyed by the element that
    /// emitted it.
    ///
    /// **A dictionary rather than a list**, unlike `hitboxes` — nothing here
    /// ranks records against each other (there is no "topmost" question for an
    /// AX node), so the only operation any caller performs is "look up `id`",
    /// which `hitboxes` would need a linear scan for. `Hitbox`'s per-frame
    /// `HitboxID` handle exists to keep a dense array cheap to index; an
    /// `AXNode` has no equivalent because nothing needs one.
    ///
    /// **Rebuilt from scratch every frame**, on `hitboxes` and `focusRegistry`'s
    /// own footing: an element not produced this frame emits nothing here, so
    /// this dictionary alone answers only "was `id` produced THIS frame", not
    /// "does `id` still exist". **That is deliberately not this property's
    /// job any more** — `axNode(for:)` below is the durable, tombstone-aware
    /// query (design spec §9); this one stays exactly what Task 5 shipped, a
    /// per-frame view, because Task 7 and any future tree walk still want
    /// "what was produced this frame" as a distinct question from "is this id
    /// still valid".
    private(set) var axNodes: [GlobalElementID: AXNode] = [:]

    /// Records `node` as `id`'s accessibility node, resolving its `frame` and
    /// `children` from the parameters rather than from whatever `node` itself
    /// carried — see `AXNode`'s own doc on why a declared value's `frame` and
    /// `children` are not meaningful on the way in.
    ///
    /// **Also persists a durable copy, under a dedicated retention slot —
    /// this is what makes `axNode(for:)` below possible at all.** `axNodes`
    /// itself is rebuilt from scratch every frame (see its own doc), so an id
    /// not produced THIS frame is simply absent from it — a dictionary miss a
    /// caller cannot tell apart from "never existed". Design spec §9 needs
    /// more than that: a handle an AX client still holds must survive and
    /// report itself invalid, not vanish. `StateTable` already has exactly
    /// that mechanism (Tasks 1-2 of this milestone: an entry's `value`
    /// outlives the frame that stopped producing it, and `isLive` says
    /// whether it was actually produced). Riding it here is Task 4's rule
    /// applied a second time — "validity is `StateTable.isLive`, not a second
    /// liveness notion" — so this writes to a distinct child slot of `id`,
    /// never `id` itself, on `focusRetentionSlot`'s exact footing: `id` is
    /// already `ScrollView`'s own `withState(id, …)` key, typed `ScrollState`,
    /// and writing an `AXNode` there would silently clobber it (mismatched
    /// types are `StateTable.write`'s own documented clobber hazard).
    @discardableResult
    func emitAXNode(_ node: AXNode, at bounds: Bounds<Pixels>, id: GlobalElementID,
                    children: [GlobalElementID]) -> AXNode {
        var resolved = node
        resolved.frame = bounds
        resolved.children = children
        resolved.isValid = true
        axNodes[id] = resolved
        stateTable.withState(Self.axRetentionSlot(for: id), initial: resolved) { $0 = resolved }
        return resolved
    }

    /// The state-table key that backs an AX handle's retention window — see
    /// `emitAXNode`'s own doc for why it must be a distinct slot rather than
    /// `id` itself. `at: 0` is inert, on `focusRetentionSlot`'s footing:
    /// `GlobalElementID.child(of:at:name:)` always prefers `name` when one is
    /// supplied.
    private static func axRetentionSlot(for id: GlobalElementID) -> GlobalElementID {
        .child(of: id, at: 0, name: ElementID("$ax"))
    }

    /// The durable accessibility record for `id` — design spec §9's actual
    /// requirement, and the reason `emitAXNode` above writes a second copy.
    /// `Frame.axNodes[id]` only ever answers "was this produced THIS frame";
    /// this answers "was `id` produced by the last COMPLETED frame" — exactly
    /// the query an AX client holding `id` across frames needs, and see the
    /// next paragraph for why that is not quite "is it current right now".
    ///
    /// **`.isValid` is `StateTable.isLive` at the retention slot, read fresh
    /// on every call — not a value snapshotted at emission.** A node stored
    /// while its element was being produced would read `isValid == true`
    /// forever if that flag were captured once; deriving it here, from the
    /// same table Task 4's focus retention and every `@State` slot already
    /// use, is what keeps this one liveness notion rather than a second one
    /// that could disagree with it.
    ///
    /// **That derivation has a one-frame read lag, and it is documented here
    /// rather than closed.** `StateTable.isLive` reflects the sweep at the
    /// END of the last COMPLETED frame (`Frame.render`'s `stateTable.sweep()`
    /// call); an element that stops being produced mid-frame is not noticed
    /// until that frame's own sweep runs, so a query made DURING the frame it
    /// vanished in still reads `isValid == true` — even though
    /// `Frame.axNodes[id]` for that very frame is already `nil`. Measured on
    /// this exact shape: emit, sweep (confirms — still `true`), construct the
    /// next frame with nothing re-emitting — `axNode(for:).isValid` is still
    /// `true` while `axNodes[id]` is already `nil` — sweep that frame, and
    /// only then does `isValid` become `false`. **The lag is one-directional
    /// and self-correcting**: it can only report valid one frame too long,
    /// never invalid too early, and it always resolves by the next sweep. A
    /// lag-free answer needs a per-frame production signal alongside
    /// `StateTable.isLive` — the shape `Frame.focusedElementProducedThisFrame`
    /// gives focus — which is a second signal on top of the one liveness
    /// notion this task's brief forbids adding; not built here for that
    /// reason.
    ///
    /// `nil` only once the slot is actually reaped by `sweep()`'s existing
    /// bound (`StateTable.staleAfterGenerations`/`sweepThreshold`) — the same
    /// bound divergence 12 and 17 already ride, not a new one invented here.
    /// Until then, an id that was never emitted at all is indistinguishable
    /// from one reaped long ago (`nil` either way); an id whose element
    /// merely stopped being produced is not — it comes back with
    /// `.isValid == false`, the tombstone spec §9 asks for, rather than
    /// vanishing or dangling. **This reaped→`nil` transition is unpinned by
    /// any test** — the obvious fixture (a fixed set of filler keys) falls
    /// back under `sweepThreshold` before reaching it and the slot then
    /// survives forever reporting `isValid == false`, never `nil`; reaching
    /// the reap needs fresh keys every frame holding the table above
    /// `sweepThreshold`, which no test here does. Left unmeasured rather than
    /// given a test that cannot express the defect (MP-J's shape) — see this
    /// task's fix-round report.
    func axNode(for id: GlobalElementID) -> AXNode? {
        let slot = Self.axRetentionSlot(for: id)
        guard var node = stateTable.peek(slot, as: AXNode.self) else { return nil }
        node.isValid = stateTable.isLive(slot)
        return node
    }

    // MARK: - Focus (design spec §4.2)

    /// What each element asked for on the keyboard side this frame, built
    /// during `prepaint` by `registerHandlers` above.
    ///
    /// **Registered in prepaint, alongside hitboxes and for the same reason**
    /// (§4.2, and §8.1 before it): it is the one phase where positions have
    /// resolved and nothing has been emitted yet. Focus itself needs no
    /// geometry — nothing here reads `bounds` — but the registration rides on
    /// the call that does, so a conformer that registers its click target
    /// registers its focusability in the same line and cannot forget one.
    ///
    /// `Window` captures this after the frame the way it captures `hitboxes`,
    /// because the frame is gone by the time a key event arrives.
    private(set) var focusRegistry = FocusRegistry()

    /// The focused element for this frame — handed in from `Window`, then
    /// possibly **cleared here** by `resolveFocus()` — see that method's own
    /// doc for the actual rule, which is no longer just "if this frame did
    /// not produce it": an id the state table still retains, live or
    /// tombstoned, survives a frame that did not produce it (divergence 17).
    ///
    /// A `var` rather than a `let`, unlike `activeElement`, and that difference
    /// is the whole of §4.2's dangling rule: `Window` reads this back after
    /// `render` returns, so the clearing decision is made against the registry
    /// the frame actually built rather than against the previous frame's.
    private(set) var focusedElement: GlobalElementID?

    /// Whether `registerHandlers` saw `focusedElement` produced this frame —
    /// **independent of what it asked for**, unlike `focusRegistry.isFocusable`.
    /// See `registerHandlers`'s own doc. Defaults `false`; nothing has to reset
    /// it between frames because `Frame` itself is rebuilt fresh every frame
    /// (`Window.drawFrameIfNeeded`).
    private var focusedElementProducedThisFrame = false

    /// Drops focus when the focused element was not produced this frame AND
    /// is no longer retained by the state table (design spec §4.2, closing
    /// CLAUDE.md's divergence 17).
    ///
    /// **Called once per frame, from `render`, at the prepaint/paint boundary
    /// — beside `resolveHover(at:)` and for its reason.** "Was it produced" is
    /// not knowable until every element's `prepaint` has run, so asking earlier
    /// would answer from a half-built registry; asking later, after `paint`,
    /// would let this frame paint a focus ring for an element it has already
    /// decided is not focused.
    ///
    /// **Two separate questions, and conflating them is the trap.** "Is
    /// `focused` still `.focusable()` right now" is `focusRegistry.isFocusable`;
    /// an element that answers no to that but WAS produced this frame (it
    /// simply stopped asking to be focusable) loses focus on the spot — the
    /// existing contract, pinned by `anElementThatStopsBeingFocusableLosesFocus`,
    /// and nothing here weakens it. "Was `focused` produced at all this frame"
    /// is `focusedElementProducedThisFrame`, and only when that is ALSO false —
    /// nothing at `focused`'s position in the tree ran `prepaint` — does this
    /// fall back to the state table. **One notion of "still exists", not two**
    /// (design spec §5): rather than a focus-specific grace period, an id that
    /// stops being produced keeps focus for exactly as long as
    /// `StateTable` retains its `$focus` slot — live or tombstoned, the same
    /// `staleAfterGenerations` bound divergence 12's `@State` entries get,
    /// because it rides the identical `sweep()`/reap. Once that slot is
    /// actually reaped, `peek` returns `nil` and focus clears here, one frame
    /// after the reap happened.
    ///
    /// **"The same `staleAfterGenerations` bound" above is the CEILING, not the
    /// behaviour an ordinary tree gets — and three consequences follow that
    /// nobody designed in.** The reap runs only on a sweep where
    /// `storage.count` exceeds `StateTable.sweepThreshold` (**256**), so below
    /// that the `$focus` slot is never reaped and focus on a permanently
    /// removed element is retained **indefinitely**. All three measured through
    /// a real `Window` on 2026-09-02:
    ///
    /// 1. **Retained indefinitely.** Focus an element behind an `if`, remove
    ///    it, render **60** more frames — `focusedElement` is still that id.
    ///    Intended per design spec §5; the indefiniteness is what §5 did not
    ///    say, and it is CLAUDE.md divergence 18's mechanism seen from the
    ///    focus side rather than the `@State` side.
    /// 2. **The dismissed subtree's still-produced ANCESTORS keep claiming its
    ///    keystrokes**, and this is the consequence with no pin.
    ///    `focusChain(from:)` walks the retained id's parent chain; those
    ///    ancestors are produced and registered, so an ancestor's `onKey` and
    ///    `keyContext` stay live for a subtree the user dismissed. Measured
    ///    with a root carrying `onKey`: a keystroke after removal runs the
    ///    ancestor's handler, where before this milestone it fell through to
    ///    `Window.onInput`. **`focusOnAnElementThatStopsBeingProducedIsRetainedWithinTheWindow`
    ///    does not catch it, by accident rather than by design** — it asserts
    ///    `raw == ["window"]`, which reads as "the event reached the window",
    ///    and only holds because that fixture's ancestors carry no `onKey`.
    /// 3. **Focus is RESTORED on return** — 60 absent frames, bring the element
    ///    back, and its own `onKey` runs again. That half is divergence 17's
    ///    closure working as intended.
    ///
    /// **All three require a CONFIRMING FRAME, which is easy to trip over.**
    /// `registerHandlers` writes the `$focus` slot only while the focused id is
    /// actually being produced, so `Window.focus(x)` followed by removal with
    /// no frame rendered in between retains nothing — measured by getting it
    /// wrong first, in a probe that skipped the frame and looked like a
    /// refutation of all three. `focusSetWithNoConfirmingFrameHasNothingToRetain`
    /// is that boundary's pin.
    ///
    /// A free method rather than a step inlined into `render`, so a test can
    /// drive `PrepaintPass` directly and resolve focus explicitly, exactly as
    /// `resolveHover(at:)` allows.
    func resolveFocus() {
        guard let focused = focusedElement else { return }
        if focusRegistry.isFocusable(focused) { return }
        if focusedElementProducedThisFrame {
            focusedElement = nil
            return
        }
        if stateTable.peek(Self.focusRetentionSlot(for: focused), as: Bool.self) == nil {
            focusedElement = nil
        }
    }

    /// The topmost **opaque** hitbox containing `point`, or `nil` when nothing
    /// opaque is under it.
    ///
    /// A thin wrapper over `topmostOpaqueHitbox(in:at:)`, which is the single
    /// copy of the ranking and carries its reasoning. `Window` calls the same
    /// function against its own captured copy of the last frame's list, because
    /// the frame that built it is gone by the time an input event arrives.
    func topmostHitbox(at point: Point<Pixels>) -> HitboxID? {
        topmostOpaqueHitbox(in: hitboxes, at: point).map { HitboxID(index: $0) }
    }

    /// This frame's answer to "what is the pointer over", written once by
    /// `resolveHover(at:)` and read by `PaintPass.isHovered(_:)`. `nil` until
    /// `resolveHover` runs, and `nil` again if it runs with nothing under the
    /// pointer.
    private(set) var hoveredHitbox: HitboxID?

    /// The topmost hitbox under the pointer, resolved **once**, against every
    /// hitbox registered so far — design spec §3.3.
    ///
    /// **Called exactly once per frame, from `render`, at the prepaint/paint
    /// boundary — after `prepaint` has returned and before `glyphAtlas.beginFrame()`.**
    /// "Topmost wins" is not knowable until every hitbox has registered, so
    /// resolving during registration (or before it) would give an answer that
    /// depends on declaration order rather than on the finished list. Resolving
    /// here, rather than lazily on first query during `paint`, is what makes
    /// `PaintPass.isHovered(_:)` a plain equality check with no one-frame lag:
    /// every element's `paint` sees the same answer regardless of which of them
    /// asks first.
    ///
    /// A free function rather than folded into `render` itself so a test can
    /// drive `PrepaintPass` directly — the idiom the rest of `HitboxTests.swift`
    /// already uses — and resolve hover explicitly, with no element and no
    /// `Frame.render` call in the way.
    func resolveHover(at point: Point<Pixels>?) {
        hoveredHitbox = point.flatMap { topmostHitbox(at: $0) }
    }

    /// Which **element** owns `hoveredHitbox`, or `nil` when nothing is
    /// hovered.
    ///
    /// **A derived view of `hoveredHitbox`, not a second piece of state** —
    /// there is one resolution per frame and this reads its answer, so the two
    /// cannot disagree. It exists because an element in `paint` has its own
    /// `GlobalElementID` and *not* its `HitboxID`:
    /// `PrepaintPass.registerHandlers(_:at:id:)` returns nothing, so a
    /// conformer has nowhere to keep the index even if it wanted one. See
    /// `PaintPass.isHovered(_ id: GlobalElementID)`.
    ///
    /// **The two keys coincide today and the reason is worth stating**, since
    /// it is what makes this lookup exact rather than approximate: an element
    /// registers at most one hitbox — `registerHandlers` is the only production
    /// path into the list for a handler set and it is called once per element
    /// per frame — so "this element's hitbox is hovered" and "the hovered
    /// hitbox belongs to this element" are the same question. An element that
    /// registered two would make this answer `true` for both, where the
    /// `HitboxID`-keyed query would still separate them.
    var hoveredElement: GlobalElementID? {
        hoveredHitbox.map { hitboxes[$0.index].id }
    }

    /// The cross-frame state table (§4.3).
    ///
    /// **Not owned here — `Frame` is per-frame and this outlives it.** The
    /// window owns it and hands the same instance to every frame; that is the
    /// whole point, and a `Frame` that constructed its own would give every
    /// element fresh state each frame while every test still passed.
    let stateTable: StateTable

    /// The shaping cache (spec §3.2), owned **by the window** exactly as
    /// `stateTable` is, and handed to every frame.
    ///
    /// **A per-frame cache would be a cache that never hits.** It would re-shape
    /// every string on every frame — through CoreText, three times per text item
    /// per layout, since §4.5's automatic minimum probes every item — while
    /// leaving the entire suite green, because a single-frame test cannot tell
    /// a warm cache from a cold one. That is the `StateTable` hazard in a second
    /// place, and `twoFramesShareOneShapingCacheRatherThanReShapingEachFrame`
    /// is the test that can see it: it renders two frames and asserts the miss
    /// count did not double.
    ///
    /// It is keyed on content — `(string, FontKey, width)` — not on element
    /// identity, so two `Text`s showing the same string share one entry and a
    /// `Text` that moves keeps its shape.
    let shapingCache: ShapingCache

    /// The glyph atlas (spec §3.5), owned **by the window** for exactly the
    /// reasons `stateTable` and `shapingCache` are, and with a sharper
    /// consequence than either.
    ///
    /// **A per-frame atlas would re-rasterize every glyph on every frame** —
    /// `CTFontDrawGlyphs` per glyph per variant, the single most expensive step
    /// in drawing text — *and* would upload a whole fresh texture to the GPU
    /// each time, while every test in the repo stayed green: a single-frame
    /// test cannot tell a warm atlas from a cold one, and the pixels are
    /// identical either way. `theAtlasSurvivesTheFrameThatFilledIt` is what can
    /// see it.
    ///
    /// It is keyed on ``MetalUIText/GlyphKey`` — face, glyph id, size, subpixel
    /// variant and scale factor — so two `Text`s in one font share every glyph
    /// they have in common, and a window dragged onto a display with a
    /// different backing scale re-rasterizes rather than serving a 1x bitmap
    /// into a 2x frame.
    let glyphAtlas: GlyphAtlas

    init(contentSize: Size<Pixels>, scaleFactor: Float, rootFontSize: Double = 16,
         stateTable: StateTable = StateTable(),
         shapingCache: ShapingCache = ShapingCache(),
         glyphAtlas: GlyphAtlas = GlyphAtlas(width: Window.atlasExtent,
                                             height: Window.atlasExtent),
         theme: Theme = .light,
         timestamp: Double = 0,
         mousePosition: Point<Pixels>? = nil,
         activeElement: GlobalElementID? = nil,
         focusedElement: GlobalElementID? = nil,
         transaction: Animation? = nil) {
        self.tree = LayoutTree(generation: Frame.nextTreeGeneration)
        Frame.nextTreeGeneration += 1
        self.contentSize = contentSize
        self.scaleFactor = scaleFactor
        self.rootFontSize = rootFontSize
        self.stateTable = stateTable
        self.shapingCache = shapingCache
        self.glyphAtlas = glyphAtlas
        self.theme = theme
        self.timestamp = timestamp
        self.mousePosition = mousePosition
        self.activeElement = activeElement
        self.focusedElement = focusedElement
        self.transaction = transaction
    }

    // MARK: - Layout phase

    func requestNode(style: Style, children: [LayoutNodeID]) -> LayoutNodeID {
        tree.newNode(style: style, children: children)
    }

    /// Registers a **leaf** — a childless node that reports its own content size
    /// through `measure` (spec §3.1).
    ///
    /// This is `newLeaf`'s only production call site. Everything the engine can
    /// do with a measured content size — §9.2's content branch, §4.5's automatic
    /// minimum, an `auto` cross size — was reachable only for containers before
    /// it existed, because `tree.measure()` was `nil` on every production node.
    func requestLeaf(style: Style, measure: @escaping MeasureFunction) -> LayoutNodeID {
        tree.newLeaf(style: style, measure: measure)
    }

    func requestNativeLeaf(measure: @escaping NativeMeasureFunction) -> LayoutNodeID {
        tree.newNativeLeaf(measure: measure)
    }

    func requestNativeOverlay(children: [LayoutNodeID],
                              alignment: NativeAlignment = .center) -> LayoutNodeID {
        tree.newNativeOverlay(children: children, alignment: alignment)
    }

    func requestNativeFrame(child: LayoutNodeID, width: Double? = nil,
                            height: Double? = nil,
                            minWidth: Double? = nil, idealWidth: Double? = nil,
                            maxWidth: Double? = nil,
                            minHeight: Double? = nil, idealHeight: Double? = nil,
                            maxHeight: Double? = nil,
                            alignment: NativeAlignment = .center) -> LayoutNodeID {
        tree.newNativeFrame(child: child, width: width, height: height,
                            minWidth: minWidth, idealWidth: idealWidth,
                            maxWidth: maxWidth,
                            minHeight: minHeight, idealHeight: idealHeight,
                            maxHeight: maxHeight,
                            alignment: alignment)
    }

    func requestNativePadding(child: LayoutNodeID,
                              insets: Edges<Double>) -> LayoutNodeID {
        tree.newNativePadding(child: child, insets: insets)
    }

    func requestNativeLinearStack(children: [LayoutNodeID], axis: NativeStackAxis,
                                  spacing: Double = 0,
                                  alignment: NativeAlignment = .center) -> LayoutNodeID {
        tree.newNativeLinearStack(children: children, axis: axis, spacing: spacing,
                                  alignment: alignment)
    }

    /// Reads back a node's current `Style` — `StyledComponent`'s read half of
    /// amend-in-place (`Component.swift`), the first production caller of
    /// `LayoutTree.setStyle`'s sibling `style(_:)`.
    func style(_ id: LayoutNodeID) -> Style {
        tree.style(id)
    }

    /// Overwrites a node's `Style` after it has already been registered.
    /// `StyledComponent`'s write half: a modifier on a `Component` distributes
    /// by amending each of its top-level nodes' styles in place rather than by
    /// wrapping them in a new one (spec §5).
    func setStyle(_ id: LayoutNodeID, _ style: Style) {
        tree.setStyle(id, style)
    }

    /// Runs the flex engine over the tree, between `requestLayout` and
    /// `prepaint`. Not reachable from any pass: elements contribute nodes, the
    /// frame runs the engine on the finished root.
    func computeRootLayout(root: LayoutNodeID) {
        if tree.isNativeLayoutNode(root) {
            _ = tree.computeNativeLayout(
                root: root,
                proposal: ProposedSize(width: Double(contentSize.width.value),
                                       height: Double(contentSize.height.value)),
                in: LayoutRect(x: 0, y: 0,
                               width: Double(contentSize.width.value),
                               height: Double(contentSize.height.value))
            )
            return
        }
        computeLayout(
            tree,
            root: root,
            available: AvailableSpaceSize(
                width: .definite(Double(contentSize.width.value)),
                height: .definite(Double(contentSize.height.value))),
            rootFontSize: rootFontSize)
    }

    // MARK: - Post-layout phases

    /// A node's resolved bounds, **absolute to the root** — the engine stores
    /// absolute rects, so no parent offset is added here.
    func bounds(of node: LayoutNodeID) -> Bounds<Pixels> {
        let rect = tree.layout(node)
        return Bounds(
            origin: Point(x: Pixels(Float(rect.x)), y: Pixels(Float(rect.y))),
            size: Size(width: Pixels(Float(rect.width)), height: Pixels(Float(rect.height))))
    }

    // MARK: - Paint phase

    /// Emits one filled rect, optionally with rounded corners.
    ///
    /// Borders and explicit z-order are still ahead (§7.3): every rect here is
    /// emitted at `order: 0`, and `Scene.finalize()` sorts stably, so equal
    /// orders keep emission sequence — which is why a container's own
    /// background paints under its children provided it emits first.
    /// `bounds` is translated by `activeOffset` and `contentMask` is
    /// `activeClip`, both scaled to match — the whole surface and zero offset
    /// when no `clipped(to:offsetBy:)` block is active, which is why no
    /// existing call site's output moves.
    ///
    /// **`borderColor` is `.transparent` and there is no way to set it**, even
    /// though `MUIRect` carries it and the fragment shader draws it — the M0
    /// demo proved that end to end. The blocker is the *width*, not the colour:
    /// a border width is `Style.border`, an `Edges<Length>` whose percentage
    /// case resolves against the **containing block's width**, and the engine
    /// computes that inside `contentBox` and discards it rather than storing it
    /// on the node. So paint has no resolved width to pair a colour with, and
    /// re-resolving one here against the box's own width is the exact mistake
    /// CLAUDE.md's percentage-inset constraint records. Storing the resolved
    /// edges on `LayoutTree` is what unblocks it.
    func fill(_ bounds: Bounds<Pixels>, color: Hsla,
              cornerRadii: Corners<Pixels> = Corners(all: Pixels(0))) {
        let translated = Bounds(
            origin: Point(x: Pixels(bounds.origin.x.value + activeOffset.x.value),
                          y: Pixels(bounds.origin.y.value + activeOffset.y.value)),
            size: bounds.size)
        scene.insert(MUIRect(
            bounds: translated.scaled(by: scaleFactor),
            contentMask: activeClip.scaled(by: scaleFactor),
            maskCornerRadii: activeClipRadii.scaled(by: scaleFactor),
            background: color,
            borderColor: .transparent,
            cornerRadii: cornerRadii.scaled(by: scaleFactor),
            borderWidths: Edges(all: ScaledPixels(0)),
            order: 0), layer: activeLayer)
    }

    /// Emits one glyph sprite, taking its bitmap from the atlas and rasterizing
    /// it there on first sight.
    ///
    /// **Everything here is already in device pixels and nothing is scaled**,
    /// which is the opposite of `fill` above and is deliberate. A glyph bitmap
    /// is rasterized *on* the device grid — `GlyphKey` carries the scale factor
    /// and `GlyphImage`'s bearings are in device pixels — so the conversion has
    /// already happened, in `ShapedText.placedGlyphs`, once. Scaling again here
    /// would double-scale exactly the way `PaintPass.fill`'s doc warns about.
    ///
    /// **The bearings come from the atlas, not from a second look at the
    /// font.** `PackedGlyph.left`/`.top` are the values the rasterizer computed
    /// with the same `floor`/`ceil` that produced the bitmap's width and height;
    /// re-deriving them from `CTFontGetBoundingRectsForGlyphs` here is the
    /// percentage-inset mistake CLAUDE.md records — one quantity resolved twice,
    /// free to disagree with itself by a pixel.
    ///
    /// Two returns without an error, and they are different situations:
    ///
    /// - **The atlas is full** (`nil`). Nothing this frame can do about it: the
    ///   packer never revisits a closed shelf, so there is no smaller correct
    ///   answer than dropping the glyph. It is silent because a `throw` here
    ///   would take down a frame that is otherwise entirely drawable.
    /// - **The glyph has no ink** (a zero-area slot — a space, and the
    ///   commonest glyph in a paragraph). Emitting it would add an instance
    ///   whose quad is degenerate and whose sampler reads nothing; the atlas
    ///   still records it so `rasterize` is not re-run for every space.
    ///
    /// `contentMask` is `activeClip`, scaled exactly as `fill` above scales
    /// it. **The offset is scaled here too, and that is the one place this
    /// method is not the mirror of `fill`.** `fill` receives points and scales
    /// the whole translated rect at the end; `draw`'s `bounds` are already in
    /// device pixels, so `activeOffset` — still in points, the space the clip
    /// stack is pushed in — has to be multiplied by `scaleFactor` before it is
    /// added, not after. Adding it unscaled would shift glyphs by the scale
    /// factor's worth of points on a Retina display and by nothing at 1x,
    /// which is exactly the kind of bug a 1x-only test cannot see.
    func draw(_ placed: PlacedGlyph, color: Hsla) {
        guard let packed = glyphAtlas.packed(for: placed.key, rasterize: {
            GlyphRaster.rasterize(glyph: placed.key.glyph, font: placed.font,
                                  subpixelVariant: placed.key.subpixelVariant,
                                  scaleFactor: placed.key.scaleFactor)
        }) else { return }
        guard packed.slot.width > 0, packed.slot.height > 0 else { return }

        let bounds = Bounds(
            origin: Point(x: ScaledPixels(Float(placed.pixelX + packed.left)),
                          y: ScaledPixels(Float(placed.baselineY - packed.top))),
            size: Size(width: ScaledPixels(Float(packed.slot.width)),
                       height: ScaledPixels(Float(packed.slot.height))))
        let dx = activeOffset.x.value * scaleFactor
        let dy = activeOffset.y.value * scaleFactor
        let placedBounds = Bounds(
            origin: Point(x: ScaledPixels(bounds.origin.x.value + dx),
                          y: ScaledPixels(bounds.origin.y.value + dy)),
            size: bounds.size)
        scene.insert(MUIGlyph(bounds: placedBounds, slot: packed.slot,
                              contentMask: activeClip.scaled(by: scaleFactor),
                              maskCornerRadii: activeClipRadii.scaled(by: scaleFactor),
                              color: color, order: 0), layer: activeLayer)
    }

    /// This frame's primitives, in paint order. Call after `render`.
    ///
    /// A copy, so `scene` stays the *emission* record: a test that asserts
    /// which element painted first reads `scene`, and one that asserts what the
    /// GPU receives reads this.
    func finalizedScene() -> Scene {
        var finalized = scene
        finalized.finalize()
        return finalized
    }

    // MARK: - Driving the three phases

    /// Walks `element` through layout, prepaint and paint, running the flex
    /// engine in between.
    ///
    /// Builds the root's `GlobalElementID` from the element's own `elementID`
    /// and hands it down, then **sweeps after the frame** (§4.3).
    ///
    /// Only the root's path is built here. Every deeper path comes from a
    /// container calling `GlobalElementID.child(of:at:name:)` through
    /// `ElementGroup`'s conformances, so a deep tree is identified all the way
    /// down **whether or not any container on the path is named** — an unnamed
    /// one contributes its own positional component instead of stopping the
    /// path. See `ElementGroup.swift` for the cursor that supplies the index.
    func render<E: Element>(_ element: inout E) {
        // The root is the only id with no parent, and the only one this file
        // builds. `at: 0` is not inert: an unnamed root element takes
        // `.positional(0)`, which is what gives a `Row { … }` rendered straight
        // into a frame an identity for its children to hang from. A named root
        // takes `.named` instead — the constructor decides, here as everywhere.
        let rootID = GlobalElementID.child(of: nil, at: 0, name: element.elementID)

        // `Frame.render` calls the root's `requestLayout` directly rather than
        // through `ElementGroup`'s default `requestGroupLayout` — that method
        // never runs for the root at all — so this is a second, independent
        // seeding site. A root element with `@State` would otherwise never be
        // bound to a table or an id.
        StateBinder.bind(element, table: stateTable, id: rootID)

        // Unlike the atlas's bracket below, this one wraps layout as well as
        // paint: a `Text`'s `MeasureFunction` shapes during `requestLayout`
        // and `Text.paint` shapes again at the box's final rounded width, and
        // `ShapingCache.endFrame()`'s sweep must see both touches as this
        // frame's before it can tell them from stale ones. See
        // `ShapingCache.beginFrame()`'s own doc comment.
        shapingCache.beginFrame()

        var layoutPass = LayoutPass(frame: self)
        let (root, layoutState) = element.requestLayout(rootID, pass: &layoutPass)
        var state = layoutState

        computeRootLayout(root: root)
        let rootBounds = bounds(of: root)

        var prepaintPass = PrepaintPass(frame: self)
        var prepaintState = element.prepaint(rootID, bounds: rootBounds,
                                             layout: &state, pass: &prepaintPass)

        // Hover resolves HERE — after `prepaint` has returned, so every
        // hitbox the frame will ever have is already registered, and before
        // `paint` runs, so `PaintPass.isHovered(_:)` has no one-frame lag
        // (design spec §3.3). See `resolveHover(at:)`'s own doc for why this
        // must not move to either side of this call.
        resolveHover(at: mousePosition)

        // Focus resolves HERE too, and for the same reason one phase later
        // would be wrong: `paint` must not draw a focus ring for an element
        // this frame has already decided is not focused. See `resolveFocus()`.
        resolveFocus()

        // The atlas's frame brackets go around the paint phase and nothing
        // else, because scene construction is the whole of what they protect:
        // `GlyphAtlas.evictUnusedSince` traps while a frame is being built, so
        // that a glyph this scene still holds an `AtlasSlot` for cannot be
        // dropped underneath it (spec §3.5). They also stamp every slot handed
        // out here with this frame's generation, which is what eviction reads.
        //
        // **Not a `defer`, and the reason is a mechanism rather than taste.**
        // The only way `paint` fails to reach `endFrame` is a Swift trap, and a
        // trap aborts the process — there is no later frame to be left with
        // `isBuildingFrame` still true. A `defer` here would be insurance
        // against a case that cannot occur, and would additionally hold the
        // bracket open across `stateTable.sweep()` below, which is not scene
        // construction.
        glyphAtlas.beginFrame()
        var paintPass = PaintPass(frame: self)
        element.paint(rootID, bounds: rootBounds,
                      layout: &state, prepaint: &prepaintState, pass: &paintPass)
        glyphAtlas.endFrame()
        shapingCache.endFrame()

        // After the frame, not before — but **not for the reason it is tempting
        // to write down.** Sweeping first does *not* discard everything the
        // previous frame established: `marked` is cleared only inside `sweep()`,
        // so a sweep at frame start still sees the previous frame's marks. The
        // real cost of that ordering is a **one-frame LIVENESS lag** — an
        // element that stops being produced reports `isLive == true` for one
        // extra frame. (Before the tombstones milestone this was a one-frame
        // *eviction* lag — the entry's whole value stayed an extra frame — but
        // `sweep()` no longer evicts anything, so the wrong ordering now only
        // delays the `isLive` flag, not the value.) Witnessed by
        // `anElementThatStopsBeingProducedLosesLivenessButKeepsItsValue`
        // (`StateTableTests.swift`, formerly `…IsSweptByTheNextFrame`), which
        // is this ordering's own dedicated pin, through its `isLive`
        // assertions — `peek`/`count` no longer discriminate the mutation at
        // all, because nothing `sweep()` does is deletion any more.
        //
        // **Not the only test that reddens, and this was measured rather than
        // assumed after a review caught the stale claim.** Moving this call
        // to right after `StateBinder.bind` above reddens 3, not 1:
        // the pin above, plus `flippingAnEitherBranchResetsTheBranchesState`
        // and `anElementAfterAVanishingIfAdoptsTheVanishedElementsState`
        // (`IdentityTests.swift`). Both are two-frame `IdentityTests` cases
        // whose tombstones-milestone inversion added an `isLive` assertion on
        // an abandoned branch's entry — the same one-frame liveness lag this
        // ordering pin exists for, reached incidentally rather than by design.
        // They are not a second ordering guard: nothing about their own
        // purpose (branch state resets rather than carries; a vacated slot is
        // not "reserved") depends on sweep ordering, and a future edit should
        // not preserve their `isLive` lines *for* this reason.
        stateTable.sweep()
    }
}

extension Size where Unit == Pixels {
    func scaled(by factor: Float) -> Size<ScaledPixels> {
        Size<ScaledPixels>(width: width.scaled(by: factor), height: height.scaled(by: factor))
    }
}

extension Corners where Unit == Pixels {
    func scaled(by factor: Float) -> Corners<ScaledPixels> {
        Corners<ScaledPixels>(
            topLeft: topLeft.scaled(by: factor), topRight: topRight.scaled(by: factor),
            bottomRight: bottomRight.scaled(by: factor), bottomLeft: bottomLeft.scaled(by: factor))
    }
}

extension Bounds where Unit == Pixels {
    /// Logical points to the render target's space. Every component is scaled,
    /// including the origin — scaling the size alone leaves everything but the
    /// top-left element in the wrong place on a Retina display.
    func scaled(by factor: Float) -> Bounds<ScaledPixels> {
        Bounds<ScaledPixels>(
            origin: Point(x: origin.x.scaled(by: factor), y: origin.y.scaled(by: factor)),
            size: size.scaled(by: factor))
    }
}
