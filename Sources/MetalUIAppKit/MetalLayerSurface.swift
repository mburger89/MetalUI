#if os(macOS)
import AppKit
import Metal
import QuartzCore
import MetalUIRender

/// Flat single-view surface backed by a CAMetalLayer.
@MainActor
final class MetalLayerSurface: RenderSurface {
    private let layer: CAMetalLayer
    private var currentDrawable: (any CAMetalDrawable)?

    init(device: any MTLDevice) {
        layer = CAMetalLayer()
        layer.device = device
        // Gamma-encoded sRGB compositing; see Renderer.pixelFormat and spec 7.8.
        // Every colour is a gamma sRGB number (`CR-C`), so the layer says so
        // (`LS-A`: it was Display P3 until record 200).
        layer.pixelFormat = Renderer.pixelFormat
        layer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        layer.isOpaque = false
        layer.framebufferOnly = true
    }

    var backingLayer: CAMetalLayer { layer }

    func resize(pixelSize: CGSize, scaleFactor: CGFloat) {
        layer.drawableSize = pixelSize
        layer.contentsScale = scaleFactor
    }

    func nextFrame() throws -> SurfaceFrame {
        guard let drawable = layer.nextDrawable() else {
            // Ordinary condition, not an error. Caller skips and stays dirty.
            throw RenderSurfaceError.noDrawableAvailable
        }
        currentDrawable = drawable

        let view = SurfaceView(
            colorTexture: drawable.texture,
            viewport: MTLViewport(originX: 0, originY: 0,
                                  width: Double(drawable.texture.width),
                                  height: Double(drawable.texture.height),
                                  znear: 0, zfar: 1))
        return SurfaceFrame(views: [view], scaleFactor: Float(layer.contentsScale))
    }

    func present(_ frame: SurfaceFrame, in commandBuffer: any MTLCommandBuffer) {
        present(frame, in: commandBuffer, onPresented: nil)
    }

    func present(_ frame: SurfaceFrame, in commandBuffer: any MTLCommandBuffer,
                 onPresented: (@Sendable (Double) -> Void)?) {
        if let drawable = currentDrawable {
            // `FP-F`: before the present, so the handler is attached to this frame's drawable.
            if let onPresented {
                drawable.addPresentedHandler { onPresented($0.presentedTime) }
            }
            commandBuffer.present(drawable)
            currentDrawable = nil
        }
    }
}
#endif
