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

/// One registered hitbox: where it is, who owns it, how it sorts and whether it
/// consumes the point.
///
/// **A struct rather than the tuple `Frame.scrollRegions` uses.** That list has
/// four fields and one reader; this one has four fields, three consumers
/// (hover, active, click dispatch) and a scroll payload still to come when
/// scroll regions fold into it — at which point positional access stops being
/// readable at the call site. The tuple was the right shape for a list scoped
/// to scroll; this one is not scoped.
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
}
