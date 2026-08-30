import MetalUICore
import MetalUILayout

/// The unit of composition: a lightweight value rebuilt every frame and walked
/// three times (spec §4.1).
///
/// **The tree is rebuilt from scratch each frame — there is no diffing and no
/// persistent node graph.** State that must survive a rebuild lives in a side
/// table keyed by `GlobalElementID`; that dictionary plus its mark-and-sweep is
/// the entire reconciliation story.
///
/// **Why three phases and not two.** `prepaint` needs resolved positions —
/// layout has run by then — but must precede painting, because hit-test
/// registration in paint order, offscreen culling, accessibility node emission
/// and overlay hoisting all have to happen before the first primitive is
/// emitted.
///
/// **Two of those four exist now and two do not**, and the paragraph here said
/// *none* of them did — true when it was written, false since the input-and-state
/// milestone. `Frame` owns a hitbox registry (hit-test registration, hover,
/// active, wheel routing and click dispatch all read it) and `PrepaintPass`
/// declares `insertHitbox`, `registerScrollRegion` and `registerHandlers`;
/// overlay hoisting exists too, as `PrepaintPass.deferred`/`PaintPass.deferred`.
/// What is still absent is **cull state** and an **AX node store** — check by
/// grepping `PrepaintPass` for members, not by re-reading this paragraph.
/// Accessibility nodes arrive with §9. The phase was built before any of it,
/// because retrofitting a middle pass later would change every `Element`
/// signature.
///
/// The `pass` parameter of each phase is a different type, and each exposes only
/// what that phase may do. Emitting a primitive during `requestLayout` is a
/// **compile error**, not a runtime check — see `PhaseSeparationTests`.
///
/// **Accepted cost (§4.1):** building an element must be synchronous and cheap.
/// No I/O and no heavy allocation.
///
/// **Refines `ElementGroup`, so every element is also a list of one.** That is
/// what lets a result builder fold `Column { Label(…); Button(…) }` into
/// `Column<Pair<Label, Button>>` — the type §4.6 names — with nothing boxed and
/// no wrapper node between the column and its children. The three group methods
/// come from a default implementation in `ElementGroup.swift`; conformers write
/// only the three below.
@MainActor
public protocol Element: ElementGroup {
    /// Whatever `requestLayout` needs to hand to the later phases. Threaded
    /// `inout` so an element can mutate it in place rather than copy it.
    associatedtype LayoutState

    /// Whatever `prepaint` needs to hand to `paint`.
    associatedtype PrepaintState

    /// The element's local name among its siblings, or `nil` to be identified by
    /// **position** instead (§4.3).
    ///
    /// `nil` is not "no identity": `ElementGroup` supplies a `.positional`
    /// component from the container's child cursor, so an unnamed element still
    /// holds cross-frame state. What a name buys is survival across a change of
    /// position — a reorder, or a sibling inserted above.
    var elementID: ElementID? { get }

    /// Contribute style and a layout node. The flex engine runs on the root
    /// after every element has been visited, so no resolved size is available
    /// here — asking for one does not compile.
    mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass)
        -> (LayoutNodeID, LayoutState)

    /// Layout has resolved, so absolute bounds are known — this is the first
    /// phase that may ask for them. Emitting a primitive here does not compile.
    ///
    /// **Three of the four registries this phase exists for are live now, and
    /// this paragraph said none of them were.** It was written before any
    /// existed and read "nothing can be registered here yet"; that expired at
    /// the input-and-state milestone and is corrected rather than quietly
    /// deleted, per this repo's rule about false claims. The phase exists so
    /// that hitboxes, focus handles, scroll regions and accessibility nodes are
    /// recorded after positions resolve and before the first primitive is
    /// emitted. **Hitboxes and scroll regions** share one registry on `Frame`
    /// (`insertHitbox`, `registerScrollRegion`, `registerHandlers`);
    /// **focus** has its own, written by that same `registerHandlers` call
    /// rather than by a method of its own. **Accessibility** is still absent —
    /// `Frame` holds no store for it and `PrepaintPass` exposes no way to add
    /// one; it arrives with §9. Check by grepping `PrepaintPass` for members,
    /// not by re-reading this paragraph.
    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                           layout: inout LayoutState, pass: inout PrepaintPass) -> PrepaintState

    /// Emit GPU primitives into the scene.
    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                        layout: inout LayoutState, prepaint: inout PrepaintState,
                        pass: inout PaintPass)
}

extension Element {
    /// Most elements have nothing to carry across frames.
    public var elementID: ElementID? { nil }
}
