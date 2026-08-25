import Testing
import Metal
import MetalUICore
@testable import MetalUIPlatform

@MainActor
@Test func openWindowProducesASurfaceSizedToItsContent() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let platform = AppKitPlatform(device: device)
    let window = try platform.openWindow(title: "Test",
                                         size: Size(width: Pixels(400), height: Pixels(300)))

    #expect(window.contentSize.width.value == 400)
    #expect(window.contentSize.height.value == 300)
    #expect(window.scaleFactor >= 1.0)

    let frame = try window.surface.nextFrame()
    #expect(frame.views.count == 1)
    // Surface is sized in device pixels, so it tracks the scale factor.
    #expect(frame.views[0].colorTexture.width == Int(400 * window.scaleFactor))
    #expect(frame.scaleFactor == window.scaleFactor)
}

@MainActor
@Test func windowTitleRoundTrips() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let platform = AppKitPlatform(device: device)
    let window = try platform.openWindow(title: "Initial",
                                         size: Size(width: Pixels(200), height: Pixels(200)))
    #expect(window.title == "Initial")
    window.title = "Changed"
    #expect(window.title == "Changed")
}
