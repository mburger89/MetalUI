import Metal
import MetalUICore
import MetalUIPlatform

/// What an app-owned surface's draw receives on the Metal renderer
/// (MetalView, ruling `MV-F` item 4): the renderer's device, **the frame's own
/// command buffer** (the one MetalUI encodes its own pass into and commits —
/// spec §7.7's "SAME buffer as the UI") and the surface's render target.
/// `MetalView`'s closure is handed one directly; a `GPUSurface`'s gets it as
/// `any GPUSurfaceContext` and downcasts.
///
/// ```swift
/// MetalView { ctx in
///     let pass = ctx.renderPassDescriptor()
///     guard let encoder = ctx.commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
///     // … the app's pipeline, sized from ctx.pixelSize …
///     encoder.endEncoding()
/// }
/// ```
///
/// **The target** is `bgra8Unorm` (never `_sRGB`: MetalUI composites in gamma
/// space, §7.8), usage render target + shader read, private storage,
/// hazard-tracked (`MV-E` item 4, `MV-L` item 5), `pixelSize` texels — the
/// element's laid-out bounds × the window's scale, rounded, clamped to 8192.
/// It persists across frames until the element leaves or resizes: an
/// `.onDemand` surface that is not redrawn shows its last contents. A new
/// target arrives cleared to transparent (`isNewTarget`). **Write
/// premultiplied colour** — the image pipeline composites a texel as
/// premultiplied source-over (`MV-D`).
///
/// **The contract** (`MV-F` items 3 and 5): the draw runs on the main actor
/// before MetalUI's own pass is begun, so no MetalUI encoder is open; it may
/// encode any number of passes into `commandBuffer`, and must end every
/// encoder it begins. It must **not** commit, enqueue, present, wait on or
/// otherwise schedule `commandBuffer` — MetalUI commits it once, after its
/// own pass, and **traps** if a draw left it anything but `.notEnqueued`. No
/// depth attachment is provided (`MV-F` item 6): allocate one sized from
/// `pixelSize` if the drawing needs it.
///
/// `import MetalUI` makes this type visible; calling `MTLCommandBuffer`'s and
/// `MTLDevice`'s methods needs `import Metal` in the app's file too.
public struct MetalDrawContext: GPUSurfaceContext {
    /// The renderer's device — the one the target was made on.
    public let device: any MTLDevice
    /// The frame's own command buffer. Encode into it; never commit it.
    public let commandBuffer: any MTLCommandBuffer
    /// The surface's render target (`bgra8Unorm`, render target + shader
    /// read, private storage).
    public let target: any MTLTexture
    /// The target's size in device pixels.
    public let pixelSize: Size<DevicePixels>
    /// The window's scale factor this frame.
    public let scaleFactor: Float
    /// The frame's display-link target timestamp in seconds (spec §4.4).
    public let time: Double
    /// The renderer's count of frames finished before this one.
    public let frameIndex: UInt64
    /// Whether the target was created (and cleared to transparent) this frame.
    public let isNewTarget: Bool

    /// Made only by `MetalWindowRenderer` — app code cannot hand a draw a
    /// forged buffer or target (guard `theMetalViewSpellingsCompileFromAPlainImport`).
    package init(device: any MTLDevice, commandBuffer: any MTLCommandBuffer, target: any MTLTexture,
                 pixelSize: Size<DevicePixels>, scaleFactor: Float, time: Double, frameIndex: UInt64,
                 isNewTarget: Bool) {
        self.device = device
        self.commandBuffer = commandBuffer
        self.target = target
        self.pixelSize = pixelSize
        self.scaleFactor = scaleFactor
        self.time = time
        self.frameIndex = frameIndex
        self.isNewTarget = isNewTarget
    }

    /// A render pass over ``target`` alone — colour attachment 0, the given
    /// load action and clear colour (premultiplied, gamma space), store action
    /// `.store`. `.load` keeps the target's previous contents.
    public func renderPassDescriptor(loadAction: MTLLoadAction = .clear,
                                     clearColor: MTLClearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0))
        -> MTLRenderPassDescriptor {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = loadAction
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = clearColor
        return pass
    }

    /// Clears the whole target to a premultiplied, gamma-space colour: one
    /// load-op-clear pass into ``commandBuffer``, ended at once.
    public func clear(red: Float, green: Float, blue: Float, alpha: Float) {
        let pass = renderPassDescriptor(
            loadAction: .clear,
            clearColor: MTLClearColor(red: Double(red), green: Double(green), blue: Double(blue), alpha: Double(alpha)))
        commandBuffer.makeRenderCommandEncoder(descriptor: pass)?.endEncoding()
    }
}
