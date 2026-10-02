#if canImport(MetalUIRender)
import MetalUICore
import MetalUILayout
import MetalUIPlatform
import MetalUIRender

/// An app-owned Metal surface (MetalView, ruling `MV-A` item 2; design spec
/// §7.7): `GPUSurface`'s Apple spelling, its closure handed the typed
/// `MetalDrawContext` — the renderer's device, the frame's own command buffer
/// and a `bgra8Unorm` render target the element's laid-out size × the
/// window's scale — which MetalUI composites into the scene at the element's
/// z-order under the active clip, corner mask, opacity, layer, transitions and
/// drag preview, exactly as an `Image` (`MV-D`).
///
/// ```swift
/// import Metal
///
/// MetalView(redraw: .continuous) { ctx in
///     let pass = ctx.renderPassDescriptor()
///     guard let encoder = ctx.commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
///     encoder.setRenderPipelineState(pipeline)
///     encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
///     encoder.endEncoding()          // never commit, present or wait (MV-F item 5)
/// }
/// .clipShape(RoundedRectangle(cornerRadius: Pixels(12)))
/// ```
///
/// Everything `GPUSurface`'s doc says holds here — when the closure runs
/// (inside the renderer's `finishFrame`, before MetalUI's own pass; reads are
/// not tracked), the redraw policy and `value:`, the no-GPU-work cases, sizing
/// (`Canvas`'s, `MV-B`) and input/accessibility (an ordinary proposal leaf,
/// `MV-I`) — because a `MetalView` **is** a `GPUSurface`: layout-, paint- and
/// identity-transparent around one.
///
/// **On a renderer that is not Metal's** — `Backends/SDL`'s on macOS, whose
/// SDL GPU device is not the app's Metal device — the closure would be handed
/// a context that is not a `MetalDrawContext`; a `MetalView` **traps**
/// there, naming `MV-A`, rather than draw a blank viewport with no error. A
/// tree meant for both renderers uses `GPUSurface` and downcasts.
public struct MetalView: ProposalElement {
    var surface: GPUSurface

    /// A Metal surface that redraws per `redraw` — `.onDemand` only on a new
    /// or resized target.
    public init(redraw: RedrawPolicy = .onDemand, draw: @escaping @MainActor (MetalDrawContext) -> Void) {
        surface = GPUSurface(redraw: redraw, draw: Self.drawThunk(draw))
    }

    /// A Metal surface that, `.onDemand`, also redraws whenever `value`
    /// differs from the value it last drew with (`MV-A` item 4).
    public init<V: Hashable>(redraw: RedrawPolicy = .onDemand, value: V,
                             draw: @escaping @MainActor (MetalDrawContext) -> Void) {
        surface = GPUSurface(redraw: redraw, value: value, draw: Self.drawThunk(draw))
    }

    /// The `GPUSurface` closure: downcasts the backend's context, trapping
    /// on one that is not Metal's (`MV-A` item 2; test 2.10).
    static func drawThunk(_ draw: @escaping @MainActor (MetalDrawContext) -> Void)
        -> @MainActor (any GPUSurfaceContext) -> Void {
        { context in
            guard let metal = context as? MetalDrawContext else {
                preconditionFailure("MetalView: the renderer handed a \(type(of: context)), not a MetalDrawContext "
                                    + "— a MetalView draws only on the Metal renderer; use GPUSurface and "
                                    + "downcast to draw on others (MV-A item 2)")
            }
            draw(metal)
        }
    }

    /// The surface's one native leaf (`MV-B`).
    public mutating func requestProposalLayout(_ id: GlobalElementID,
                                               pass: inout LayoutPass) -> (ProposalNodeID, Void) {
        surface.requestProposalLayout(id, pass: &pass)
    }

    /// Nothing, as the surface (`MV-I`).
    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout Void, pass: inout PrepaintPass) {
        surface.prepaint(id, bounds: bounds, layout: &layout, pass: &pass)
    }

    /// The surface's quad and draw request, under this element's own id.
    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout Void, prepaint: inout Void, pass: inout PaintPass) {
        surface.paint(id, bounds: bounds, layout: &layout, prepaint: &prepaint, pass: &pass)
    }
}
#endif
