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
    /// ``present(_:in:)`` that also reports when the frame reached the screen (`FP-F`): `onPresented` gets the
    /// drawable's `presentedTime` in seconds (`CACurrentMediaTime`'s clock; 0 when the frame was dropped), on
    /// an arbitrary thread. The default presents without reporting.
    func present(_ frame: SurfaceFrame, in commandBuffer: any MTLCommandBuffer,
                 onPresented: (@Sendable (_ presentedTime: Double) -> Void)?)
}

extension RenderSurface {
    /// Presents without reporting (`FP-F`).
    public func present(_ frame: SurfaceFrame, in commandBuffer: any MTLCommandBuffer,
                        onPresented: (@Sendable (_ presentedTime: Double) -> Void)?) {
        present(frame, in: commandBuffer)
    }
}

/// Why a surface could not supply a frame.
public enum RenderSurfaceError: Error, CustomStringConvertible {
    case noDrawableAvailable
    public var description: String { "no drawable available this frame" }
}

/// A surface the latency experiments can reach (`FP-L`): `package`, so `RenderSurface` (public) is unchanged.
/// `MetalWindowRenderer` asks with a cast, once, at creation.
@MainActor
package protocol ExperimentalRenderSurface: RenderSurface {
    /// Device pixels per point, known without acquiring a drawable; `nil` when only a drawable knows it (the
    /// renderer then acquires early, as without the experiment).
    var scaleFactorWithoutDrawable: Float? { get }
    /// Runs right after the frame's command buffer was committed. A surface presenting with a transaction
    /// (`METALUI_EXP_TRANSACTION`) waits for the buffer to be scheduled and presents its drawable here.
    func didCommit(_ frame: SurfaceFrame, commandBuffer: any MTLCommandBuffer)
}
