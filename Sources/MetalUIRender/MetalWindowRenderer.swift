import Metal
import MetalUIPlatform

/// The Metal ``WindowRenderer`` (ruling RS-B): a shared ``Renderer`` drawing
/// into one window's ``RenderSurface``. Exactly the sequence `Window` ran
/// inline before the seam — next drawable, command buffer, atlas upload
/// **before** encode (so the first frame of text is not blank), encode,
/// present, commit.
@MainActor
public final class MetalWindowRenderer: WindowRenderer {
    /// The renderer that encodes each frame, shared across windows.
    public let renderer: Renderer
    /// The surface that supplies each frame's drawable.
    public let surface: any RenderSurface
    private var pending: (frame: SurfaceFrame, view: SurfaceView, commandBuffer: any MTLCommandBuffer)?

    /// A window renderer drawing with `renderer` into `surface` (`RS-B`).
    public init(renderer: Renderer, surface: any RenderSurface) {
        self.renderer = renderer
        self.surface = surface
    }

    /// Acquires this frame's drawable and returns its scale factor, or `nil`
    /// when no drawable is available (the window stays dirty and retries).
    public func beginFrame() -> Float? {
        pending = nil
        // No drawable is an ordinary condition: the window retries.
        guard let frame = try? surface.nextFrame(),
              let view = frame.views.first,
              let commandBuffer = renderer.commandQueue.makeCommandBuffer() else { return nil }
        pending = (frame, view, commandBuffer)
        return frame.scaleFactor
    }

    /// Encodes `scene` sampling `atlas` into the acquired drawable, presents
    /// and commits; `false` if `beginFrame()` acquired nothing.
    ///
    /// **`surfaces` is ignored until MetalView's lane 2** (spec §8: lane 1's
    /// signature-only hand-off): no target is created or drawn, and
    /// `Renderer.encode` skips `.surface` runs.
    public func finishFrame(scene: Scene, atlas: GlyphAtlas, surfaces: [SurfaceDrawRequest]) -> Bool {
        guard let pending else { return false }
        self.pending = nil
        // The atlas texture is written only while it has never been bound,
        // and a dirty upload after an encode allocates a replacement — so the
        // upload comes first (see `Renderer.upload`).
        renderer.upload(atlas)
        do {
            try renderer.encode(scene, view: pending.view, in: pending.commandBuffer)
        } catch {
            return false
        }
        surface.present(pending.frame, in: pending.commandBuffer)
        pending.commandBuffer.commit()
        return true
    }
}
