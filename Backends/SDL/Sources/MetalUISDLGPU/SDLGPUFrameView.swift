// Compiled only under the `SDL` trait (ruling PX-H item 2; GA-B).
#if SDL
import Foundation
import MetalUISDL

/// A typed view of a surface draw's frame (ruling `GA-H`): the **frame's own**
/// command buffer to record passes and copies into, and the surface's target
/// as a texture. It is non-owning and declares no verb that would end the
/// frame's buffer — a surface draw hands that to MetalUI (`MV-F`). Take it from
/// ``MetalUISDL/SDLGPUDrawContext/view`` inside the draw; never keep it past
/// the draw's return.
public final class SDLGPUFrameView {
    /// The window renderer's device, borrowed (ruling `GA-D`): create pipelines,
    /// textures and buffers with it, keep them no longer than the window.
    public let device: SDLGPUDevice
    /// The frame's command buffer. Passes and copies recorded here run before
    /// MetalUI's own pass, in the frame's one submission.
    public let commandBuffer: SDLGPUCommandBuffer
    /// The surface's target (`B8G8R8A8_UNORM`, colour target and sampler, premultiplied),
    /// borrowed: MetalUI creates, resizes and releases it, this texture never does.
    public let target: SDLGPUTexture

    @MainActor init(context: SDLGPUDrawContext) {
        let device = SDLGPUDevice(borrowingRaw: context.device)
        self.device = device
        let buffer = SDLGPUCommandBuffer(raw: context.commandBuffer, device: device)
        buffer.isFrame = true
        commandBuffer = buffer
        target = SDLGPUTexture(
            raw: context.target,
            description: SDLGPUTextureDescription(
                width: Int(context.pixelSize.width.value), height: Int(context.pixelSize.height.value),
                format: .b8g8r8a8Unorm, usage: [.sampler, .colorTarget]),
            device: device, owned: false)
    }

    /// The target's size in device pixels.
    public var pixelSize: (width: Int, height: Int) {
        (target.description.width, target.description.height)
    }

    /// Begins a render pass in the frame's buffer; see
    /// ``SDLGPUCommandBuffer/beginRenderPass(color:depth:)``. End it before the
    /// draw returns.
    public func beginRenderPass(color: SDLGPUColorAttachment, depth: SDLGPUDepthAttachment? = nil) -> SDLGPURenderPass? {
        commandBuffer.beginRenderPass(color: color, depth: depth)
    }
}

extension SDLGPUDrawContext {
    /// The typed view of this draw's frame (ruling `GA-H`). Each call makes a
    /// new view over the same buffer and target.
    @MainActor public var view: SDLGPUFrameView { SDLGPUFrameView(context: self) }
}
#endif
