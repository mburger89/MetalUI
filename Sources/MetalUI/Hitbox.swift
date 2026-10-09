import MetalUICore
import MetalUILayout

/// A handle to one hitbox registered during **this** frame's prepaint.
///
/// **It is a dense index into `Frame.hitboxes` and it cannot outlive the frame
/// that issued it.** The list is rebuilt from scratch every frame, so the same
/// element's hitbox takes a different index the moment a sibling above it
/// appears or vanishes — the exact hazard ruling C-3 records for
/// `LayoutNodeID`, and the reason `insertHitbox` takes the owning element's
/// `GlobalElementID` as a *parameter* rather than handing this back as a key.
/// Anything that must survive a frame — a pressed button's active state, a
/// scroller's stored offset — keys on that `GlobalElementID`; this type is for
/// "which of the boxes registered a moment ago is under the cursor", and
/// nothing else.
///
/// Deliberately **not** stamped with a frame generation the way `LayoutNodeID`
/// is stamped with a tree's. That guard exists because a `LayoutNodeID` can be
/// stashed in the cross-frame `StateTable` and read back against a tree that no
/// longer knows it; a `HitboxID` has no such carrier today — it is produced and
/// consumed inside one `render` — and a generation would be a mechanism with no
/// reachable failure to prevent. If a `HitboxID` ever becomes storable, stamp
/// it then.
public struct HitboxID: Hashable, Sendable {
    /// The registration index, `0` for the first hitbox inserted this frame.
    public let index: Int

    /// `internal`, so code outside the framework cannot fabricate a handle to a
    /// hitbox it never registered — the same reason `LayoutNodeID.init` is.
    init(index: Int) { self.index = index }
}

/// One registered hitbox: where it is, who owns it, how it sorts, whether it
/// consumes the point, which axis it scrolls on if it is a scroller, and what
/// it should run if it is clicked.
///
/// **A struct rather than the tuple `Frame.scrollRegions` used to be.** That
/// list had four fields and one reader; this one has six and four consumers
/// (hover, active, wheel routing and click dispatch — the last of which arrived
/// with `onClick`), at which point
/// positional access stops being readable at the call site. The tuple was the
/// right shape for a list scoped to scroll; this one is not scoped — scroll
/// regions folded into it in the task that made wheel routing walk this list
/// (design spec §3.1).
struct Hitbox {
    /// Window-space, **translated by the active offset and intersected with the
    /// active clip** at registration time — where the thing actually paints,
    /// not where the engine stored it. See `Frame.insertHitbox`.
    var bounds: Bounds<Pixels>

    /// The owning element. **The key that survives frames**, and therefore the
    /// one anything cross-frame reads: `HitboxID` is a per-frame index and
    /// cannot be one.
    let id: GlobalElementID

    /// `Frame.activeLayer` at registration. Primary sort key, ahead of
    /// registration order, so a `Deferred` subtree receives events above the
    /// siblings it paints over — see `Frame.topmostHitbox(at:)`.
    let layer: Int

    /// Whether this hitbox consumes a point that lands in it.
    ///
    /// **`false` means "transparent to hit testing", not "invisible"** — CSS's
    /// `pointer-events: none`, roughly. A non-opaque hitbox stays in the list
    /// and stays queryable, and `topmostHitbox(at:)` walks straight through it
    /// to whatever is beneath: it is never that query's answer, even when it is
    /// the only thing under the point. Design spec §3.2.
    let opaque: Bool

    /// The axis this hitbox scrolls on, or `nil` when it is not a scroller —
    /// the scroll payload design spec §3.1 folds `Frame.scrollRegions` into.
    ///
    /// **A field on the record rather than a side table keyed by `HitboxID`.**
    /// Wheel routing needs it at exactly the moment it already has the record
    /// in hand — one array scan, no second lookup — and `Window` has to carry
    /// the list across a frame boundary (`lastHitboxes`), which a side table
    /// would force it to do twice, in lockstep, from two sources. Two lists
    /// that must be rebuilt together is precisely what this task removed; a
    /// side table would have put one back under a different name.
    ///
    /// **A bare `ScrollAxis?`, not a one-field `ScrollPayload` struct.** Only
    /// the axis cannot be recovered from elsewhere: the scroller's id is
    /// `Hitbox.id` already, and the content and viewport extents are not read
    /// here at all — `Window.applyScroll` deliberately writes unbounded and
    /// leaves the clamp to `ScrollChrome.resolvedOffset`, which has the layout
    /// this list does not. Declaring extents nobody reads would be a row in
    /// CLAUDE.md's declared-but-inert table on the day it landed.
    ///
    /// **`opaque` is independent of this.** A scroller registers `opaque: true`
    /// because it consumes the point; a non-opaque hitbox is skipped by
    /// `topmostOpaqueHitbox(in:at:)` and so could never receive a wheel event
    /// however it were flagged here.
    let scroll: ScrollAxis?

    /// The callbacks the owning element asked for, or an empty set when this
    /// record is a scroller or a bare hit target.
    ///
    /// **On the record, exactly as `scroll` is, and for the reason `scroll`'s
    /// own doc gives**: `Window` has to carry this list across a frame boundary
    /// (`lastHitboxes`) so that a `mouseUp` arriving with no frame in flight
    /// still finds the handler the button was *drawn* with. A side table keyed
    /// by `GlobalElementID` would be a second list to rebuild in lockstep with
    /// this one — "two lists that must be rebuilt together is precisely what
    /// this task removed", says the paragraph above, and a handler dictionary
    /// would have put one back under a different name. It also means there is
    /// no `Window.lastHandlers`: capturing `lastHitboxes` captures the handler
    /// set with it, and the two cannot disagree about which frame they are
    /// from.
    ///
    /// The consequence for identity is worth stating: dispatch compares
    /// `Hitbox.id` against the pressed `GlobalElementID` and then calls
    /// **this** record's closure, so a click always runs the handler belonging
    /// to the hitbox that was hit, not one looked up by name from somewhere
    /// else.
    let handlers: Handlers

    /// The owning element's window-space origin — translated by the active
    /// offset like `bounds`, but **not** clipped or inset — so a drag's values
    /// are local to the element's own box (plan task 12 part 1, `IX-C` item 5).
    /// Written by `Frame.insertHitbox`; read only by the gesture arena.
    let origin: Point<Pixels>

    /// A declared `.contentShape(_:)`'s geometry in window space — translated
    /// like `bounds` and **not** clipped (the clip is `bounds`' job) — or `nil`
    /// for the rect alone (plan task 12 part 1, ruling `IX-L`). Written by
    /// `Frame.insertHitbox` from `Frame.registerHandlers`; a scroll region never
    /// carries one.
    let shape: ShapeGeometry?

    /// The render effects in force where it was registered (ruling `GX-I`), or
    /// `nil` outside every effect — then `bounds`, `origin` and `shape` are in
    /// window points, as before effects existed. With one, they are in the
    /// **local** space the declarer was laid out and emitted in: `bounds`
    /// clipped only by clips pushed inside the effect, the window point mapped
    /// through `transform.inverse` before it is tested, and `transform.outerClip`
    /// (the clip at the effect's entry, window space) tested first.
    var transform: HitboxTransform? = nil

    /// For a contextual region (menus, `MN-Q`): whether its element was enabled
    /// when it registered — a disabled element's menu opens with every item
    /// disabled (C9). `true` for every other hitbox.
    var contextualEnabled = true

    /// Whether `point` lands in this hitbox — **the single region test** (ruling
    /// `IX-D` item 1): `topmostOpaqueHitbox(in:at:)`, the gesture arena's
    /// ancestor membership and `Window.applyScroll`'s wheel chain all call it,
    /// so a hit region is tested in one place — which is what makes a content
    /// shape reach a click, the arena, hover, active and wheel routing alike
    /// (`IX-L` item 1). Half-open on the max edges, as `Bounds.contains` is.
    /// The clipped rect first, then the shape, so a content shape can only
    /// shrink a hit region the clip already bounds (divergence 43).
    func contains(_ point: Point<Pixels>) -> Bool {
        guard let transform else { return bounds.contains(point) && (shape?.contains(point) ?? true) }
        // Inside render effects (`GX-I`): the outer clip in window space, then
        // the local rect and shape at the inverse-mapped point; a degenerate
        // map (a zero scale) contains nothing.
        guard transform.outerClip.contains(point), let inverse = transform.inverse else { return false }
        let local = inverse.apply(point)
        return bounds.contains(local) && (shape?.contains(local) ?? true)
    }

    /// `point` in the space `bounds` and `origin` are in — the window point
    /// itself outside every effect, mapped through the stored inverse inside
    /// one (`GX-P` item 3).
    func localPoint(_ point: Point<Pixels>) -> Point<Pixels> {
        guard let inverse = transform?.inverse else { return point }
        return inverse.apply(point)
    }
}

/// What a hitbox registered inside render effects stores (ruling `GX-I`): the
/// inverse of the composed map (window points → the declarer's local points),
/// `nil` when the map is degenerate (a zero scale — the hitbox then contains
/// nothing), and the clip in force at the outermost effect's entry, in window
/// points.
struct HitboxTransform {
    let inverse: Affine2D?
    let outerClip: Bounds<Pixels>
}

/// A declared `.contentShape(_:)`'s shape, boxed so `Handlers` carries one
/// reference (ruling `IX-L`; `IX-N`'s Windows stack budget) — never a `Shape`
/// existential stored inline.
final class ContentShape {
    private let geometryIn: @MainActor (Bounds<Pixels>) -> ShapeGeometry

    @MainActor
    init<S: Shape>(_ shape: S) {
        geometryIn = { shape.geometry(in: $0) }
    }

    /// The shape's geometry inside `rect`.
    @MainActor
    func geometry(in rect: Bounds<Pixels>) -> ShapeGeometry { geometryIn(rect) }
}

/// The index of the topmost **opaque** hitbox containing `point`, or `nil` when
/// nothing opaque is under it.
///
/// **The single copy of the `(layer, registration index)` ranking.** There were
/// three — `Frame.topmostHitbox(at:)`, `Window.topmostHitboxOwner(at:)` and
/// `Window.applyScroll`, which was itself the scroll-region picker — and two
/// lists for them to disagree about. There is now one of each: this function,
/// over a `[Hitbox]` that either a live `Frame` or the `Window`'s captured copy
/// of the last one can supply. A free function rather
/// than a method on `Frame` because the window's copy outlives the frame that
/// built it, and rather than a method on `Array` because it is not general —
/// it is this framework's dispatch rule.
///
/// Layer first, because a hoisted `Deferred` subtree is still *emitted* where
/// it was declared and can therefore register before something it paints over;
/// registration order alone would hand the point to the covered element.
///
/// **A non-opaque hitbox does not stop the walk** (design spec §3.2), which is
/// why `opaque` is a *filter* here rather than a test applied to the winner: an
/// ineligible record must not be able to shadow an eligible one beneath it.
/// Written the other way round — take the topmost hit, then check whether it is
/// opaque — this would return `nil` wherever a decorative overlay covers a real
/// target, which is the whole failure §3.2's sentence exists to prevent.
///
/// This function has **no reverse walk to get wrong** because the filter makes
/// every candidate eligible; "topmost" is then just the maximum. The index is
/// unique, so no two candidates can compare equal.
///
/// **Design spec §3.2 says dispatch "walks in reverse", and this is what that
/// sentence became.** The behaviour it specifies is unchanged — the record a
/// reverse walk would have stopped at is the maximum of the same ordering — but
/// the wording no longer describes the code, and it also predates the `layer`
/// term, which a reverse walk over registration order cannot express at all.
/// The spec carries a note pointing back here. Do not "restore" a reverse walk
/// to match the prose, and do not add a fourth copy of this rule.
///
/// Half-open on the max edges, because `Bounds.contains` is: two hitboxes
/// sharing an edge cannot both claim it.
func topmostOpaqueHitbox(in hitboxes: [Hitbox], at point: Point<Pixels>) -> Int? {
    topmostHitbox(in: hitboxes, at: point, where: \.opaque)
}

/// The topmost hitbox containing `point` among those `eligible` admits — the
/// one `(layer, registration index)` ranking, with the eligibility as a
/// parameter (drag and drop, ruling `DN-F` item 1). ``topmostOpaqueHitbox(in:at:)``
/// is this with the opaque filter; a drop target is this with "carries a drop
/// destination"; the arena's draggable member is this with "carries a
/// draggable". **The ordering exists here and nowhere else** — the rule above,
/// unchanged, so do not add a second copy of it for a new eligibility.
func topmostHitbox(in hitboxes: [Hitbox], at point: Point<Pixels>, where eligible: (Hitbox) -> Bool) -> Int? {
    hitboxes.enumerated()
        .filter { $0.element.contains(point) && eligible($0.element) }
        .max { ($0.element.layer, $0.offset) < ($1.element.layer, $1.offset) }
        .map(\.offset)
}
