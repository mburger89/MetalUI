import Metal
import MetalUICore
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

    /// The window's app-owned surface render targets (MetalView, ruling
    /// `MV-E`): **per window**, not on the shared ``renderer`` — `SurfaceID`s
    /// are minted per window, so a shared table would see one window's scene
    /// not reference the other's target and release it every frame (`MV-E`
    /// item 3; record §61 §6 item 4's per-window question, answered for
    /// surfaces). `package` for the root package's tests (`MV-L` item 2).
    package private(set) var surfaceTable = SurfaceTargetTable<any MTLTexture>()

    /// Frames finished, ever — each draw context's `frameIndex`.
    private var finishedFrames: UInt64 = 0

    /// Runs the frame's app-owned `surfaces` into its command buffer, then
    /// encodes `scene` sampling `atlas` into the acquired drawable, presents
    /// and commits; `false` if `beginFrame()` acquired nothing.
    ///
    /// **The order is the contract** (`MV-F` item 3): the atlas upload first
    /// (see `Renderer.upload`); then the table resolves this frame's targets
    /// (`MV-E`: created at their device-pixel size, replaced on a resize,
    /// released once no scene target references them); then each surface to
    /// draw — a new target first cleared to transparent (`MV-E` item 5) — runs
    /// its `draw` on the main actor into **this frame's command buffer**,
    /// before MetalUI's own pass is begun, so no MetalUI encoder is open and
    /// the app's GPU work precedes the composite that samples it; then
    /// `Renderer.encode` draws `.surface` runs through the image pipeline with
    /// each run's target bound; then present and commit. One command buffer
    /// on one queue orders frame N+1's write of a target after frame N's
    /// sample of it (targets are hazard-tracked), so there is no double
    /// buffering (`MV-E` item 6).
    ///
    /// A draw that commits, enqueues or otherwise schedules the buffer traps,
    /// naming `MV-F` (item 5).
    public func finishFrame(scene: Scene, atlas: GlyphAtlas, surfaces: [SurfaceDrawRequest]) -> Bool {
        guard let pending else { return false }
        self.pending = nil
        // The atlas texture is written only while it has never been bound,
        // and a dirty upload after an encode allocates a replacement — so the
        // upload comes first (see `Renderer.upload`).
        renderer.upload(atlas)

        let device = renderer.device
        let commandBuffer = pending.commandBuffer
        let toDraw = surfaceTable.update(
            references: scene.surfaceTargets, requests: surfaces,
            create: { target in Self.makeTarget(target, device: device) },
            // Dropping the reference is the release: an in-flight command
            // buffer that still samples the texture keeps it alive (Metal's
            // retained references), exactly as a dropped image texture
            // (`TE-AF`).
            release: { _ in })
        for (request, target, isNew) in toDraw {
            let context = MetalDrawContext(
                device: device, commandBuffer: commandBuffer, target: target,
                pixelSize: Size(width: DevicePixels(Int32(target.width)), height: DevicePixels(Int32(target.height))),
                scaleFactor: request.scaleFactor, time: request.time, frameIndex: finishedFrames,
                isNewTarget: isNew)
            if isNew { context.clear(red: 0, green: 0, blue: 0, alpha: 0) }
            request.draw(context)
            precondition(commandBuffer.status == .notEnqueued,
                         "MetalWindowRenderer: a surface's draw left the frame's command buffer "
                         + "\(commandBuffer.status) — a draw must not commit, enqueue or schedule it (MV-F item 5)")
        }
        var targets: [SurfaceID: any MTLTexture] = [:]
        for target in scene.surfaceTargets {
            if let texture = surfaceTable.handle(for: target.id) { targets[target.id] = texture }
        }

        do {
            try renderer.encode(scene, view: pending.view, in: commandBuffer, surfaces: targets)
        } catch {
            return false
        }
        surface.present(pending.frame, in: commandBuffer)
        commandBuffer.commit()
        // Recorded only once the frame is committed: a failed encode drops
        // the buffer and the draws in it, so an `.onDemand` surface must draw
        // again next frame rather than show a target nothing wrote (`MV-O`
        // item 2).
        for drawn in toDraw { surfaceTable.didDraw(drawn.request) }
        finishedFrames += 1
        return true
    }

    /// A surface's render target (`MV-E` items 2 and 4): `bgra8Unorm` — never
    /// `_sRGB`, §7.8 — render target + shader read, private storage, the
    /// default (tracked) hazard mode — never `.untracked`, which would drop
    /// the cross-frame ordering `MV-E` item 6 rests on (`MV-L` item 5) — at
    /// the target's device-pixel size, each side clamped to 8192 (`Frame`
    /// already clamps; one limit for both renderers). `nil` (no memory) drops
    /// the request this frame.
    private static func makeTarget(_ target: SurfaceTarget, device: any MTLDevice) -> (any MTLTexture)? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: Renderer.pixelFormat,
            width: min(target.width, 8192), height: min(target.height, 8192), mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        return device.makeTexture(descriptor: descriptor)
    }
}
