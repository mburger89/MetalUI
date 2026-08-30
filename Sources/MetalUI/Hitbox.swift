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
/// consumes the point, and — if it is a scroller — which axis it scrolls on.
///
/// **A struct rather than the tuple `Frame.scrollRegions` used to be.** That
/// list had four fields and one reader; this one has five and four consumers
/// (hover, active, wheel routing, and click dispatch to come), at which point
/// positional access stops being readable at the call site. The tuple was the
/// right shape for a list scoped to scroll; this one is not scoped — scroll
/// regions folded into it in the task that made wheel routing walk this list
/// (design spec §3.1).
struct Hitbox {
    /// Window-space, **translated by the active offset and intersected with the
    /// active clip** at registration time — where the thing actually paints,
    /// not where the engine stored it. See `Frame.insertHitbox`.
    let bounds: Bounds<Pixels>

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
    /// leaves the clamp to `ScrollView.resolvedOffset`, which has the layout
    /// this list does not. Declaring extents nobody reads would be a row in
    /// CLAUDE.md's declared-but-inert table on the day it landed.
    ///
    /// **`opaque` is independent of this.** A scroller registers `opaque: true`
    /// because it consumes the point; a non-opaque hitbox is skipped by
    /// `topmostOpaqueHitbox(in:at:)` and so could never receive a wheel event
    /// however it were flagged here.
    let scroll: ScrollAxis?
}

/// The index of the topmost **opaque** hitbox containing `point`, or `nil` when
/// nothing opaque is under it.
///
/// **The single copy of the `(layer, registration index)` ranking.** There were
/// three — `Frame.topmostHitbox(at:)`, `Window.applyScroll` and the scroll-
/// region picker — and two lists for them to disagree about. There is now one
/// of each: this function, over a `[Hitbox]` that either a live `Frame` or the
/// `Window`'s captured copy of the last one can supply. A free function rather
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
/// Half-open on the max edges, because `Bounds.contains` is: two hitboxes
/// sharing an edge cannot both claim it.
func topmostOpaqueHitbox(in hitboxes: [Hitbox], at point: Point<Pixels>) -> Int? {
    hitboxes.enumerated()
        .filter { $0.element.bounds.contains(point) && $0.element.opaque }
        .max { ($0.element.layer, $0.offset) < ($1.element.layer, $1.offset) }
        .map(\.offset)
}
