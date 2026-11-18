import Testing
import AppKit
import Metal
import MetalUICore
import MetalUIAppKit
import MetalUIScene
@testable import MetalUI
@testable import MetalUIRender

// `FP-V`, record 387: `App.init()` builds the Metal pipelines on a background
// thread while the main thread pays for `NSApplication.shared`.

private let pureRed = Color(Hsla(h: 0, s: 1, l: 0.5, a: 1))
private let size200 = Size(width: DevicePixels(200), height: DevicePixels(200))

/// Where `makePipelines` ran, and what it built.
private struct Built: @unchecked Sendable {
    var pipelines: RendererPipelines
    var onMainThread: Bool
}

/// **1.** `Renderer.makePipelines(device:)` is callable off the main actor, and a renderer built from its result draws the same
/// pixels as `Renderer(device:)`. Mutation **O1** (`makePipelines` builds the rect pipeline from the glyph
/// shaders: nothing is drawn). The thread pin documents the call site; it is not mutation-checked.
@Test @MainActor func pipelinesBuildOffTheMainThreadAndDrawLikeAPlainRenderer() async throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let built = try await Task.detached {
        Built(pipelines: try Renderer.makePipelines(device: device), onMainThread: pthread_main_np() != 0)
    }.value
    #expect(!built.onMainThread, "the build ran on a background thread")

    let split = try Renderer(device: device, pipelines: built.pipelines)
    let plain = try Renderer(device: device)
    let element = pureRed.frame(width: Pixels(40), height: Pixels(30)).padding(Edges(all: Pixels(8)))
    let scene = effectFrame(element).finalizedScene()
    let a = try split.renderOffscreen(scene, size: size200)
    let b = try plain.renderOffscreen(scene, size: size200)
    #expect(a == b, "the same pixels")
    #expect(a.contains { $0 != 0 }, "something was drawn")
}

/// **2.** `App()` on the overlapped path still yields the AppKit platform on a Metal device with the default menu bar
/// installed. Mutation **O3** (the shared initialiser skips `installMenuBar()`: fails on `mainMenu`).
@Test @MainActor func anAppBuiltWithTheOverlapHasAWorkingAppKitPlatform() throws {
    _ = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    NSApplication.shared.mainMenu = nil
    let app = try App()
    #expect(app.device != nil)
    #expect(app.platform is AppKitPlatform)
    #expect(NSApplication.shared.mainMenu != nil, "the default bar is installed")
    let window = try app.openWindow(title: "Overlap", size: Size(width: Pixels(64), height: Pixels(64)),
                                    startsDisplayLink: false) {
        pureRed.frame(width: Pixels(10), height: Pixels(10))
    }
    _ = window
}
