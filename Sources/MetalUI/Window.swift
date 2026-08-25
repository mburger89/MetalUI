import Metal
import MetalUICore
import MetalUIRender
import MetalUIPlatform

/// Fills the scene for one frame. Replaced by the element pipeline in M1.
public typealias FrameContent = @MainActor (inout Scene, Size<ScaledPixels>) -> Void

@MainActor
public final class Window {
    private let platformWindow: any PlatformWindow
    private let renderer: Renderer
    private let content: FrameContent
    private var scene = Scene()

    /// Set by input, resize, or content invalidation. A frame is built only
    /// when this (or an active animation) says so — an idle window costs
    /// nothing (spec 4.4).
    public private(set) var needsRedraw: Bool = true

    /// Test observability: how many frames actually reached the GPU.
    public private(set) var framesDrawn: Int = 0

    init(platformWindow: any PlatformWindow,
         renderer: Renderer,
         content: @escaping FrameContent,
         startsDisplayLink: Bool = true) {
        self.platformWindow = platformWindow
        self.renderer = renderer
        self.content = content

        platformWindow.onResize = { [weak self] _, _ in self?.setNeedsRedraw() }
        platformWindow.onInput = { [weak self] _ in
            self?.setNeedsRedraw()
            return false
        }
        // Tests pass false so frame counts stay deterministic: a running link
        // could tick between assertions and inflate `framesDrawn`.
        if startsDisplayLink {
            platformWindow.startDisplayLink { [weak self] in self?.drawFrameIfNeeded() }
        }
    }

    public func setNeedsRedraw() {
        needsRedraw = true
        platformWindow.setDisplayLinkPaused(false)
    }

    public func drawFrameIfNeeded() {
        guard needsRedraw else {
            // Nothing to do: let the display idle rather than spinning.
            platformWindow.setDisplayLinkPaused(true)
            return
        }
        needsRedraw = false

        let frame: SurfaceFrame
        do {
            frame = try platformWindow.surface.nextFrame()
        } catch {
            // No drawable is an ordinary condition. Stay dirty and retry.
            needsRedraw = true
            return
        }

        guard let view = frame.views.first,
              let commandBuffer = renderer.commandQueue.makeCommandBuffer() else {
            needsRedraw = true
            return
        }

        let size = Size(width: ScaledPixels(Float(view.viewport.width)),
                        height: ScaledPixels(Float(view.viewport.height)))

        scene.clear()
        content(&scene, size)
        scene.finalize()

        do {
            try renderer.encode(scene, view: view, in: commandBuffer)
        } catch {
            needsRedraw = true
            return
        }

        platformWindow.surface.present(frame, in: commandBuffer)
        commandBuffer.commit()
        framesDrawn += 1
    }
}
