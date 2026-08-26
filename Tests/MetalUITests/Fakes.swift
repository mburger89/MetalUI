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
        descriptor.storageMode = .private
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw RendererError.bufferAllocationFailed
        }
        self.texture = texture
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
/// production change. The failure, idle and resize paths are unreachable through
/// `App.openWindow` for one shared reason: the AppKit surface only produces a
/// drawable for a window that is actually on screen. The **appearance** path is
/// not in that list — `MetalUIPlatformTests` drives the real AppKit one — and
/// the fake is used here only to keep a `Window` test from reaching for
/// application-wide state.
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
