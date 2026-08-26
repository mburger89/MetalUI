import MetalUICore
import MetalUILayout

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
}

/// Phase 2. Layout has resolved, so absolute bounds are known — but nothing has
/// been painted yet, which is what makes this the only correct place to register
/// hit-test, focus, scroll and accessibility structure.
///
/// **It registers none of them today, and the omission is in `Frame`, not
/// here.** `Frame` owns no hitbox, focus, scroll or accessibility store, so
/// there is nothing for a `register…` method to write into and none is
/// declared. `bounds(of:)` and `contentSize` are the entire surface. Adding a
/// registry means a store on `Frame` and a method here; input and focus bring
/// theirs (M3), accessibility brings its own (§9).
@MainActor
public struct PrepaintPass {
    let frame: Frame

    init(frame: Frame) { self.frame = frame }

    public var contentSize: Size<Pixels> { frame.contentSize }

    /// A node's resolved bounds, absolute to the root.
    public func bounds(of node: LayoutNodeID) -> Bounds<Pixels> { frame.bounds(of: node) }
}

/// Phase 3. Primitives are emitted here and nowhere else.
@MainActor
public struct PaintPass {
    let frame: Frame

    init(frame: Frame) { self.frame = frame }

    public var contentSize: Size<Pixels> { frame.contentSize }

    public func bounds(of node: LayoutNodeID) -> Bounds<Pixels> { frame.bounds(of: node) }

    /// Emits a filled rect, **in logical points**.
    ///
    /// The display scale factor is applied here, once, on the way to the scene.
    /// Element code neither needs it nor can reach it: this pass deliberately
    /// exposes no `scaleFactor`, because an element that found one would have no
    /// way to know it had already been applied, and pre-scaling its bounds
    /// double-scales them on any Retina display.
    public func fill(_ bounds: Bounds<Pixels>, color: Hsla) { frame.fill(bounds, color: color) }
}

// MARK: - Cross-frame state (§4.3)

// Three identical methods rather than one protocol extension, and the
// duplication is deliberate.
//
// A `StatefulPass` protocol would need `var frame: Frame { get }` as a public
// requirement, which forces `frame` public on all three passes — and that hands
// element authors the whole `Frame` surface, defeating the phase separation this
// file exists to enforce. Emitting a primitive during layout would become
// `pass.frame.fill(...)`, a compile *success*. Three one-line bodies is the
// cheaper price. Measured: `error: property 'frame' must be declared public
// because it matches a requirement in public protocol 'StatefulPass'`.
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
    /// An element with no identity gets scratch state discarded on return — not
    /// an error, and why identity does not resume below an anonymous element.
    /// See `GlobalElementID.child(of:_:)`.
    @MainActor
    public func withState<S>(_ id: GlobalElementID?,
                             initial: @autoclosure () -> S,
                             _ body: (inout S) -> Void) {
        frame.stateTable.withState(id, initial: initial(), body)
    }
}

extension PrepaintPass {
    /// See `LayoutPass.withState(_:initial:_:)`.
    @MainActor
    public func withState<S>(_ id: GlobalElementID?,
                             initial: @autoclosure () -> S,
                             _ body: (inout S) -> Void) {
        frame.stateTable.withState(id, initial: initial(), body)
    }
}

extension PaintPass {
    /// See `LayoutPass.withState(_:initial:_:)`.
    @MainActor
    public func withState<S>(_ id: GlobalElementID?,
                             initial: @autoclosure () -> S,
                             _ body: (inout S) -> Void) {
        frame.stateTable.withState(id, initial: initial(), body)
    }
}
