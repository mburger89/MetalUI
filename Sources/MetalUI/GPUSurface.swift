import MetalUICore
import MetalUILayout
import MetalUIPlatform

/// An app-owned GPU surface (MetalView, rulings `MV-A`…`MV-I`; design spec
/// §7.7): app code encodes its own GPU work into an offscreen render target
/// sized to this element's laid-out bounds × the window's scale, and MetalUI
/// composites the target into the scene at the element's z-order — under the
/// active clip and its corner mask, opacity, layer, transitions and drag
/// preview, exactly as an `Image` in the same place (`MV-D`).
///
/// ```swift
/// GPUSurface(redraw: .continuous) { ctx in
///     if let metal = ctx as? MetalDrawContext { encodeViewport(metal) }
///     else { ctx.clear(red: 0.1, green: 0.1, blue: 0.2, alpha: 1) }
/// }
/// .clipShape(RoundedRectangle(cornerRadius: 12))
/// ```
///
/// **The context** is the backend's (`MV-F` item 4): `MetalDrawContext` on the
/// Metal renderer (the frame's own command buffer and a `bgra8Unorm` target),
/// `SDLGPUDrawContext` on SDL; downcast to the one you encode for, or use the
/// portable `clear(red:green:blue:alpha:)`. Write **premultiplied**,
/// gamma-space colour (§7.8). `MetalView` is the Apple spelling with a typed
/// context.
///
/// **When `draw` runs** (`MV-F` item 3): on the main actor, inside the
/// renderer's `finishFrame`, before MetalUI's own pass — never during the
/// tracked frame build, so reads inside `draw` are **not** tracked. To redraw
/// an `.onDemand` surface, pass what the drawing reads as `value:` (`MV-A`
/// item 4): a `@State` or `@Observable` value read here dirties the window,
/// and the surface redraws when its value differs from the one it last drew
/// (`MV-G` item 2; divergence 103 — SwiftUI's `Canvas` also re-runs whenever
/// its declaring body re-runs). `.continuous` draws every frame it paints.
///
/// **No GPU work** while it is not painted, has a zero-sized target, lies
/// wholly outside the clip or is fully transparent (`MV-G` item 4).
///
/// **Sizing is `Canvas`'s** (`MV-B`, probe G1): the proposal on each axis, 10
/// on a nil axis. **A proposal leaf like `Rectangle`** (`MV-I`): no hitbox,
/// focus entry or accessibility record of its own — `.onTapGesture`,
/// `.gesture`, `.contentShape`, `accessibilityLabel` and a legacy wrapper's
/// `.focusable()`/`.onKey` supply them with no special path.
public struct GPUSurface: ProposalElement {
    let policy: RedrawPolicy
    let value: AnyHashable?
    let draw: @MainActor (any GPUSurfaceContext) -> Void

    /// A surface that redraws per `redraw` — `.onDemand` only on a new or
    /// resized target.
    public init(redraw: RedrawPolicy = .onDemand,
                draw: @escaping @MainActor (any GPUSurfaceContext) -> Void) {
        self.policy = redraw
        self.value = nil
        self.draw = draw
    }

    /// A surface that, `.onDemand`, also redraws whenever `value` differs from
    /// the value it last drew with (`MV-A` item 4).
    public init<V: Hashable>(redraw: RedrawPolicy = .onDemand, value: V,
                             draw: @escaping @MainActor (any GPUSurfaceContext) -> Void) {
        self.policy = redraw
        self.value = AnyHashable(value)
        self.draw = draw
    }

    /// One native leaf answering the proposal, 10 on a nil axis (`MV-B`).
    public mutating func requestProposalLayout(_ id: GlobalElementID,
                                               pass: inout LayoutPass) -> (ProposalNodeID, Void) {
        let node = pass.requestNativeLeaf { proposal in
            LayoutMeasurement(size: SizeD(width: proposal.width ?? 10, height: proposal.height ?? 10))
        }
        return (node, ())
    }

    /// Nothing: no hitbox, focus entry or accessibility record (`MV-I`).
    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout Void, pass: inout PrepaintPass) {}

    /// One quad over `bounds` and this frame's draw request (`Frame.drawSurface`).
    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout Void, prepaint: inout Void, pass: inout PaintPass) {
        pass.frame.drawSurface(id: id, bounds: bounds, policy: policy, value: value, draw: draw)
    }
}
