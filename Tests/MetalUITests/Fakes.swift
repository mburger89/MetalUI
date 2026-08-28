import Metal
import MetalUICore
import MetalUIPlatform
import MetalUIRender
import simd
@testable import MetalUI

/// A `RenderSurface` that renders into a plain offscreen texture and can be
/// told to fail. The real `MetalLayerSurface` needs a window on screen, so the
/// frame loop's failure path is unreachable from the AppKit backend in a test.
@MainActor
final class FakeRenderSurface: RenderSurface {
    /// When true, `nextFrame()` throws `.noDrawableAvailable` — the everyday
    /// "no drawable this tick" condition of spec 3.2, not an error.
    var failsNextFrame = false

    private(set) var nextFrameCalls = 0
    private(set) var presentCalls = 0

    private let texture: any MTLTexture
    private let size: Int

    init(device: any MTLDevice, size: Int = 64) throws {
        self.size = size
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: Renderer.pixelFormat, width: size, height: size, mipmapped: false)
        descriptor.usage = .renderTarget
        // **`.shared`, not `.private`**, so a test can read back what the window
        // actually drew. That is the only way to see a defect whose symptom is
        // "the first frame is blank": `lastScene` holds the right primitives
        // either way, and the AppKit surface renders into a drawable no test can
        // sample. See `aWindowUploadsTheAtlasBeforeEncodingSoTheFirstFrameOfTextIsNotBlank`.
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw RendererError.bufferAllocationFailed
        }
        self.texture = texture
    }

    /// The command buffer the window last presented into, so `readPixels` can
    /// wait on the right one. `Window.drawFrameIfNeeded` commits without
    /// waiting, and a barrier committed on a *different* queue would not be
    /// ordered against it.
    private var lastCommandBuffer: (any MTLCommandBuffer)?

    /// The BGRA bytes of the most recently rendered frame, row-major.
    func readPixels() -> [UInt8] {
        lastCommandBuffer?.waitUntilCompleted()
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        pixels.withUnsafeMutableBytes { raw in
            texture.getBytes(raw.baseAddress!,
                             bytesPerRow: size * 4,
                             from: MTLRegionMake2D(0, 0, size, size),
                             mipmapLevel: 0)
        }
        return pixels
    }

    func nextFrame() throws -> SurfaceFrame {
        nextFrameCalls += 1
        if failsNextFrame { throw RenderSurfaceError.noDrawableAvailable }
        let view = SurfaceView(
            colorTexture: texture,
            viewport: MTLViewport(originX: 0, originY: 0,
                                  width: Double(size), height: Double(size),
                                  znear: 0, zfar: 1),
            projection: matrix_identity_float4x4)
        return SurfaceFrame(views: [view], scaleFactor: 1)
    }

    func present(_ frame: SurfaceFrame, in commandBuffer: any MTLCommandBuffer) {
        presentCalls += 1
        lastCommandBuffer = commandBuffer
    }
}

/// A `PlatformWindow` that records display-link pausing, so the "idles at zero
/// cost" claim (spec 4.4) can be asserted instead of observed by hand.
@MainActor
final class FakePlatformWindow: PlatformWindow {
    let fakeSurface: FakeRenderSurface

    /// Every `setDisplayLinkPaused` argument, in call order.
    private(set) var pauseCalls: [Bool] = []
    private(set) var displayLinkStarted = false

    var contentSize: Size<Pixels>
    var scaleFactor: Float = 1
    var surface: any RenderSurface { fakeSurface }
    var title: String = "Fake"

    /// Settable, unlike AppKit's, which is a live read of `effectiveAppearance`.
    ///
    /// The fake is here so a `Window` test can pick an appearance without
    /// touching application-wide state — **not** because the AppKit path is
    /// untestable. It is:
    /// `theWindowFollowsTheApplicationsEffectiveAppearance` in
    /// `MetalUIPlatformTests` drives the real one through
    /// `NSApplication.shared.appearance`.
    var appearance: Appearance = .light

    var onInput: ((InputEvent) -> Bool)?
    var onResize: ((Size<Pixels>, Float) -> Void)?
    var onAppearanceChange: ((Appearance) -> Void)?
    var onClose: (() -> Void)?

    /// Change the appearance and notify, the way AppKit does: the getter already
    /// reports the new value by the time the callback runs.
    func simulateAppearanceChange(to newAppearance: Appearance) {
        appearance = newAppearance
        onAppearanceChange?(newAppearance)
    }

    /// Resize the way `AppKitWindow.syncSurfaceGeometry` does: the reported
    /// content size is already the new one when `onResize` fires.
    func simulateResize(to newSize: Size<Pixels>) {
        contentSize = newSize
        onResize?(newSize, scaleFactor)
    }

    /// Deliver an input event the way `MetalHostView` does, and return what the
    /// window said about it. AppKit reads that answer to decide whether to keep
    /// propagating the event, so a test that ignored the return value would not
    /// notice a window that always claimed "unhandled".
    @discardableResult
    func simulateInput(_ event: InputEvent) -> Bool {
        onInput?(event) ?? false
    }

    init(device: any MTLDevice, size: Int = 64) throws {
        self.fakeSurface = try FakeRenderSurface(device: device, size: size)
        self.contentSize = Size(width: Pixels(Float(size)), height: Pixels(Float(size)))
    }

    func startDisplayLink(_ tick: @escaping () -> Void) {
        displayLinkStarted = true
    }

    func setDisplayLinkPaused(_ paused: Bool) {
        pauseCalls.append(paused)
    }
}

/// A `Window` over the fakes above.
///
/// `Window.init` is internal, so `@testable import MetalUI` reaches it with no
/// production change.
///
/// **Only the failure and idle paths are genuinely unreachable through
/// `App.openWindow`**, and for one shared reason: they need a surface that
/// refuses to vend a drawable, which the AppKit one does only for a window that
/// is off screen. The fake supplies `failsNextFrame`.
///
/// **Resize and appearance are NOT in that category**, and this doc said resize
/// was until it was measured. Both drive end to end through a real
/// `AppKitPlatform` window, synchronously and with no run-loop spin —
/// `aRealAppKitResizeDirtiesTheWindowAndTheNextFrameReflows` below, and
/// `theWindowReportsAContentSizeChangeThroughOnResize` /
/// `theWindowFollowsTheApplicationsEffectiveAppearance` in
/// `MetalUIPlatformTests`. The fake is used for them only because it is cheaper
/// to point at a size or an appearance than to reach through
/// `NSApplication.shared.windows` for the `NSWindow`.
@MainActor
func makeFakeWindow<Root: Element>(
    device: any MTLDevice,
    size: Int = 64,
    appearance: Appearance = .light,
    content: @escaping @MainActor () -> Root
) throws -> (Window, FakePlatformWindow) {
    let platformWindow = try FakePlatformWindow(device: device, size: size)
    platformWindow.appearance = appearance
    let renderer = try Renderer(device: device)
    let window = Window(platformWindow: platformWindow,
                        renderer: renderer,
                        startsDisplayLink: false,
                        content: content)
    return (window, platformWindow)
}
