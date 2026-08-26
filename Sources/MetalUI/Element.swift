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
/// **None of those four exist yet, and this is the phase's whole justification,
/// so read the list as a design rationale rather than a description.** `Frame`
/// holds no hitbox registry, no cull state, no AX node store and no overlay
/// list, and `PrepaintPass` declares no `register…` method — check by grepping
/// `PrepaintPass` for members, not by re-reading this paragraph. Hit-testing and
/// focus arrive in M3, accessibility nodes with §9, overlay hoisting with §4.5.
/// The phase is built now because retrofitting a middle pass later would change
/// every `Element` signature.
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

    /// The element's local identity, or `nil` for an element with no state to
    /// carry across frames.
    var elementID: ElementID? { get }

    /// Contribute style and a layout node. The flex engine runs on the root
    /// after every element has been visited, so no resolved size is available
    /// here — asking for one does not compile.
    mutating func requestLayout(_ id: GlobalElementID?, pass: inout LayoutPass)
        -> (LayoutNodeID, LayoutState)

    /// Layout has resolved, so absolute bounds are known — this is the first
    /// phase that may ask for them. Emitting a primitive here does not compile.
    ///
    /// **Nothing can be registered here yet.** The phase exists so that
    /// hitboxes, focus handles, scroll regions and accessibility nodes are
    /// recorded after positions resolve and before the first primitive is
    /// emitted — but `Frame` holds no registry for any of them and
    /// `PrepaintPass` therefore exposes no way to add one. Reading resolved
    /// bounds is the whole of what this phase can currently do. Each registry is
    /// a store on `Frame` plus one method on `PrepaintPass`; input and focus
    /// bring theirs (M3), accessibility brings its own (§9).
    mutating func prepaint(_ id: GlobalElementID?, bounds: Bounds<Pixels>,
                           layout: inout LayoutState, pass: inout PrepaintPass) -> PrepaintState

    /// Emit GPU primitives into the scene.
    mutating func paint(_ id: GlobalElementID?, bounds: Bounds<Pixels>,
                        layout: inout LayoutState, prepaint: inout PrepaintState,
                        pass: inout PaintPass)
}

extension Element {
    /// Most elements have nothing to carry across frames.
    public var elementID: ElementID? { nil }
}
