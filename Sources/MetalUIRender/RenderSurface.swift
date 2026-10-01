import Metal
import simd

/// One render destination for a frame.
///
/// Deliberately a list of views with an explicit projection rather than a bare
/// drawable: a stereo backend later returns two views with per-eye matrices and
/// a rate map, and the renderer needs no change (spec 3.2).
public struct SurfaceView {
    /// The texture the view is drawn into.
    public var colorTexture: any MTLTexture
    /// The viewport within the texture.
    public var viewport: MTLViewport
    /// The projection from scaled pixels to clip space.
    public var projection: simd_float4x4
    /// A variable rasterization rate map, if the view uses one.
    public var rasterizationRateMap: (any MTLRasterizationRateMap)?

    /// A view into `colorTexture`.
    public init(colorTexture: any MTLTexture,
                viewport: MTLViewport,
                projection: simd_float4x4 = matrix_identity_float4x4,
                rasterizationRateMap: (any MTLRasterizationRateMap)? = nil) {
        self.colorTexture = colorTexture
        self.viewport = viewport
        self.projection = projection
        self.rasterizationRateMap = rasterizationRateMap
    }
}

/// One frame's destinations: one view for a window, and its scale factor.
public struct SurfaceFrame {
    /// The views to draw the scene into.
    public var views: [SurfaceView]
    /// Device pixels per point for this frame.
    public var scaleFactor: Float
    /// A frame of `views` at `scaleFactor`.
    public init(views: [SurfaceView], scaleFactor: Float) {
        self.views = views
        self.scaleFactor = scaleFactor
    }
}

/// Where a `MetalWindowRenderer` draws: acquires each frame's destinations and
/// presents them (`RS-B`).
@MainActor
public protocol RenderSurface: AnyObject {
    /// Acquire this frame's destinations. Throwing is an ordinary condition
    /// (no drawable available); the caller skips the frame and stays dirty.
    func nextFrame() throws -> SurfaceFrame
    func present(_ frame: SurfaceFrame, in commandBuffer: any MTLCommandBuffer)
}

/// Why a surface could not supply a frame.
public enum RenderSurfaceError: Error, CustomStringConvertible {
    case noDrawableAvailable
    public var description: String { "no drawable available this frame" }
}
