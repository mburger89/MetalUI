import Metal
import Testing
import MetalUICore
import MetalUIPlatform
import MetalUIRender
import MetalUIScene
@testable import MetalUI

/// `METALUI_EXP_LATE_DRAWABLE` at the renderer (`FP-L`): `nextFrame()` is not called until the late acquire, a
/// failed acquire drops the frame, and `didCommit` runs after the commit. Mutations: `beginFrameDeferringDrawable`
/// calling `beginFrame()`; the failure path leaving `deferred` set; `didCommit` never called.
@MainActor
@Test func aLateDrawableIsNotAcquiredUntilAskedAndAFailedAcquireDropsTheFrame() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let surface = try FakeRenderSurface(device: device)
    surface.scaleFactor = 2
    let renderer = MetalWindowRenderer(renderer: try Renderer(device: device), surface: surface)

    #expect(renderer.beginFrameDeferringDrawable() == 2)
    #expect(surface.nextFrameCalls == 0, "set-up needs no drawable")
    #expect(renderer.acquireDeferredDrawable())
    #expect(surface.nextFrameCalls == 1)
    #expect(renderer.finishFrame(scene: Scene(), atlas: GlyphAtlas(width: 64, height: 64), surfaces: []))
    #expect(surface.presentCalls == 1 && surface.commitCalls == 1, "presented, then didCommit")

    surface.failsNextFrame = true
    #expect(renderer.beginFrameDeferringDrawable() == 2)
    #expect(renderer.acquireDeferredDrawable() == false)
    #expect(renderer.finishFrame(scene: Scene(), atlas: GlyphAtlas(width: 64, height: 64), surfaces: []) == false, "nothing pending")
    #expect(surface.commitCalls == 1)
}
