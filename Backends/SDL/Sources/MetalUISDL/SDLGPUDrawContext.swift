// Compiled only under the `SDL` trait (ruling PX-H item 2).
#if SDL
import MetalUICore
import MetalUIPlatform
import SDLBridge

/// What an app-owned surface's draw receives on the SDL GPU renderer
/// (MetalView, ruling `MV-F` item 4): the renderer's device, **the frame's own
/// command buffer** (the one `SDLWindowRenderer` records MetalUI's pass into
/// and submits once) and the surface's render target, each an SDL3 pointer for
/// app code that imports SDL3 itself. A `GPUSurface`'s closure gets it as
/// `any GPUSurfaceContext` and downcasts; `clear(red:green:blue:alpha:)` needs
/// no SDL import.
///
/// ```swift
/// GPUSurface(redraw: .continuous) { ctx in
///     guard let sdl = ctx as? SDLGPUDrawContext else { return }
///     // SDL_BeginGPURenderPass(sdl.commandBuffer, …target: sdl.target…) … SDL_EndGPURenderPass
/// }
/// ```
///
/// **The target** is `SDL_GPU_TEXTUREFORMAT_B8G8R8A8_UNORM` (never sRGB:
/// MetalUI composites in gamma space, §7.8), usage colour target + sampler,
/// `pixelSize` texels — the element's laid-out bounds × the window's scale,
/// rounded, clamped to 8192. It persists across frames until the element
/// leaves or resizes: an `.onDemand` surface that is not redrawn shows its last
/// contents. A new target arrives cleared to transparent (`isNewTarget`).
/// **Write premultiplied colour** — the image pipeline composites a texel as
/// premultiplied source-over (`MV-D`).
///
/// **The contract** (`MV-F` items 3 and 5): the draw runs on the main actor,
/// between the renderer's `mui_renderer_begin` and `mui_renderer_finish`,
/// before MetalUI's own pass is begun, so no MetalUI pass is open; it may
/// record any number of passes into `commandBuffer` and must end every pass it
/// begins. It must **not** submit, cancel or wait on `commandBuffer`, acquire
/// a swapchain texture into it, or release `target` — MetalUI submits the
/// buffer once, after its own pass, and owns the target. **A violation is
/// undefined behaviour and is not detected** (SDL3 has no command-buffer state
/// query, unlike Metal's `status`, which `MetalWindowRenderer` traps on).
public struct SDLGPUDrawContext: GPUSurfaceContext {
    /// The renderer's `SDL_GPUDevice *` — the one the target was made on.
    public let device: OpaquePointer
    /// The frame's own `SDL_GPUCommandBuffer *`. Record into it; never submit it.
    public let commandBuffer: OpaquePointer
    /// The surface's `SDL_GPUTexture *` (`B8G8R8A8_UNORM`, colour target +
    /// sampler).
    public let target: OpaquePointer
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

    /// Made only by `SDLWindowRenderer` — app code cannot hand a draw a forged
    /// buffer or target.
    package init(device: OpaquePointer, commandBuffer: OpaquePointer, target: OpaquePointer,
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

    /// Clears the whole target to a premultiplied, gamma-space colour: one
    /// `LOADOP_CLEAR` render pass recorded into ``commandBuffer``, ended at once.
    public func clear(red: Float, green: Float, blue: Float, alpha: Float) {
        _ = mui_gpu_clear_texture(UnsafeMutableRawPointer(commandBuffer), UnsafeMutableRawPointer(target),
                                  red, green, blue, alpha)
    }

    /// A test's non-uniform fill (`MV-Q`): blits all of `source`
    /// (`width`×`height`, nearest) over the target's `(0, 0)` to
    /// ``pixelSize`` — placed by the size the draw was told, so a target made
    /// at any other size composites a different pattern.
    package func blitForTesting(from source: OpaquePointer, width: Int, height: Int) -> Bool {
        mui_gpu_blit_texture(UnsafeMutableRawPointer(commandBuffer), UnsafeMutableRawPointer(source),
                             UInt32(width), UInt32(height), UnsafeMutableRawPointer(target),
                             UInt32(pixelSize.width.value), UInt32(pixelSize.height.value))
    }
}
#endif
