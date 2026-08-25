import Metal
import simd

/// One render destination for a frame.
///
/// Deliberately a list of views with an explicit projection rather than a bare
/// drawable: a stereo backend later returns two views with per-eye matrices and
/// a rate map, and the renderer needs no change (spec 3.2).
public struct SurfaceView {
    public var colorTexture: any MTLTexture
    public var viewport: MTLViewport
    public var projection: simd_float4x4
    public var rasterizationRateMap: (any MTLRasterizationRateMap)?

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

public struct SurfaceFrame {
    public var views: [SurfaceView]
    public var scaleFactor: Float
    public init(views: [SurfaceView], scaleFactor: Float) {
        self.views = views
        self.scaleFactor = scaleFactor
    }
}

@MainActor
public protocol RenderSurface: AnyObject {
    /// Acquire this frame's destinations. Throwing is an ordinary condition
    /// (no drawable available); the caller skips the frame and stays dirty.
    func nextFrame() throws -> SurfaceFrame
    func present(_ frame: SurfaceFrame, in commandBuffer: any MTLCommandBuffer)
}

public enum RenderSurfaceError: Error, CustomStringConvertible {
    case noDrawableAvailable
    public var description: String { "no drawable available this frame" }
}
