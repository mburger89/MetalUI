import MetalUICore
import MetalUILayout

/// One component of an element's identity path.
///
/// **Identity semantics are not implemented here.** This type exists because
/// spec §4.1's protocol names it; the side table keyed on a `GlobalElementID`,
/// marked on access and swept after each frame (§4.3), is its own task. Nothing
/// in `MetalUI` reads an `elementID` yet — `Frame.render` passes `nil` down all
/// three phases. Recorded in CLAUDE.md's inert table so the silence at this
/// declaration does not read as "implemented" (ruling AL-6).
public struct ElementID: Hashable, Sendable {
    public let name: String
    public init(_ name: String) { self.name = name }
}

/// An element's identity: the **path** of `ElementID` components from the root,
/// not the local id (§4.3).
///
/// The path is what distinguishes two elements that carry the same local id
/// under different parents. A table keyed on the local id alone would let them
/// share state, and no layout or paint assertion can see that.
public struct GlobalElementID: Hashable, Sendable {
    public var path: [ElementID]
    public init(_ path: [ElementID]) { self.path = path }
}

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
/// The `pass` parameter of each phase is a different type, and each exposes only
/// what that phase may do. Emitting a primitive during `requestLayout` is a
/// **compile error**, not a runtime check — see `PhaseSeparationTests`.
///
/// **Accepted cost (§4.1):** building an element must be synchronous and cheap.
/// No I/O and no heavy allocation.
@MainActor
public protocol Element {
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
