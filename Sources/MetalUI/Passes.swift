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

    /// Logical points to device pixels for this frame's target. Element code
    /// paints in logical points; `fill` applies this.
    public var scaleFactor: Float { frame.scaleFactor }

    public func bounds(of node: LayoutNodeID) -> Bounds<Pixels> { frame.bounds(of: node) }

    /// Emits a filled rect, in logical points.
    public func fill(_ bounds: Bounds<Pixels>, color: Hsla) { frame.fill(bounds, color: color) }
}
