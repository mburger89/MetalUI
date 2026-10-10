import MetalUI
import MetalUIScene

/// The renderer of a ``HeadlessPlatformWindow`` (ruling `HT-D` item 2): it
/// presents every frame without a GPU — keeping the frame's `Scene`, accounting
/// the glyph atlas's upload as both GPU renderers do (the dirty rect's area,
/// then `GlyphAtlas.clearDirtyRect()`), counting the image textures no earlier
/// frame referenced, and recording the frame's GPU-surface draw requests
/// **without running them** (there is no GPU context to hand a `GPUSurface`
/// draw; `HT-Q` item 2).
///
/// MetalUI-only, like every declaration in `MetalUITesting` (`HT-B`): SwiftUI
/// has no in-process test harness.
@MainActor
public final class HeadlessWindowRenderer: WindowRenderer {
    /// The device scale factor ``beginFrame()`` answers — the window's, kept in
    /// step by ``HeadlessPlatformWindow/simulateScaleFactorChange(to:)``.
    public internal(set) var scaleFactor: Float

    /// When `true`, the next ``beginFrame()`` answers `nil` — "no drawable this
    /// tick", the window stays dirty and retries — and the flag clears.
    public var failsNextFrame = false

    /// The scene of the last presented frame, in device pixels.
    public private(set) var lastScene = Scene()

    /// How many frames this renderer has presented.
    public private(set) var framesPresented = 0

    /// The last presented frame's app-surface draw requests, in paint order —
    /// recorded, never run (`HT-Q` item 2).
    public private(set) var lastSurfaceRequests: [SurfaceDrawRequest] = []

    /// The glyph-atlas texels the last presented frame uploaded: the area of
    /// the atlas's dirty rect, 0 when nothing changed (a work counter).
    public private(set) var lastAtlasUploadPixels = 0

    /// How many of the last presented frame's image textures the frame before
    /// it did not reference — the uploads a GPU renderer would make.
    public private(set) var lastNewTextures = 0

    /// The texels of ``lastNewTextures``.
    public private(set) var lastNewTexturePixels = 0

    /// Runs once, inside the first ``beginFrame()``, before that frame is
    /// built: the harness's per-window setup (spec §3.1 item 3), since
    /// `App.openWindow` draws the first frame before it returns.
    var onFirstBeginFrame: (@MainActor () -> Void)?

    /// Runs after each presented frame with this renderer's counters updated:
    /// the harness closes its per-frame work record there.
    var onFramePresented: (@MainActor (HeadlessWindowRenderer) -> Void)?

    /// The textures the previous presented frame referenced, by identity —
    /// held, so an identity cannot be reused by a new texture while it counts.
    private var previousTextures: [ObjectIdentifier: ImageTexture] = [:]

    /// A renderer answering `scaleFactor` from ``beginFrame()``.
    public init(scaleFactor: Float = 1) {
        self.scaleFactor = scaleFactor
    }

    /// Answers the window's scale factor, or `nil` once after
    /// ``failsNextFrame`` was set.
    public func beginFrame() -> Float? {
        if let setup = onFirstBeginFrame {
            onFirstBeginFrame = nil
            setup()
        }
        return nil   // STUB (lane 1 red run): draws nothing
    }

    /// Presents the frame: keeps `scene`, accounts and clears the atlas's dirty
    /// rect, counts new textures, records `surfaces` without running them, and
    /// answers `true`.
    public func finishFrame(scene: Scene, atlas: GlyphAtlas, surfaces: [SurfaceDrawRequest]) -> Bool {
        lastScene = scene
        if let dirty = atlas.dirtyRect {
            lastAtlasUploadPixels = dirty.width * dirty.height
            atlas.clearDirtyRect()
        } else {
            lastAtlasUploadPixels = 0
        }
        var current: [ObjectIdentifier: ImageTexture] = [:]
        var newCount = 0
        var newPixels = 0
        for texture in scene.textures {
            let id = ObjectIdentifier(texture)
            guard current[id] == nil else { continue }
            current[id] = texture
            if previousTextures[id] == nil {
                newCount += 1
                newPixels += texture.width * texture.height
            }
        }
        previousTextures = current
        lastNewTextures = newCount
        lastNewTexturePixels = newPixels
        lastSurfaceRequests = surfaces
        framesPresented += 1
        onFramePresented?(self)
        return true
    }
}
