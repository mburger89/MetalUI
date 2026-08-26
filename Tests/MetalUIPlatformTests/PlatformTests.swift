import Testing
import Metal
import AppKit
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

/// Spec §7.9: "`NSApp.effectiveAppearance` … swap[s] the active theme."
///
/// **This was very nearly written off as untestable.** Four comments on this
/// branch said, in one form or another, that no test can see
/// `viewDidChangeEffectiveAppearance` fire because AppKit calls it in response
/// to a system-wide setting a test may not change. Measured: setting
/// `NSApplication.shared.appearance` drives `effectiveAppearance` for every view
/// under it, and the override fires **synchronously** — no run-loop spin, and so
/// no re-entrancy into other main-actor tests. The claim was a prediction about
/// measurement, dressed as a fact (practices doc, shape 10).
///
/// Both directions are asserted. One would pass against a getter hard-coded to
/// the answer it happens to expect, and against a callback that passes a
/// constant.
@MainActor
@Test func theWindowFollowsTheApplicationsEffectiveAppearance() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let platform = AppKitPlatform(device: device)
    let window = try platform.openWindow(title: "Appearance",
                                         size: Size(width: Pixels(200), height: Pixels(200)))

    let saved = NSApplication.shared.appearance
    defer { NSApplication.shared.appearance = saved }

    // Force a known starting point, before the callback is attached, so the
    // machine's own appearance cannot decide how many events this test sees.
    NSApplication.shared.appearance = NSAppearance(named: .aqua)
    #expect(window.appearance == .light)

    var fired: [Appearance] = []
    window.onAppearanceChange = { fired.append($0) }

    NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
    #expect(window.appearance == .dark)
    #expect(fired == [.dark], "the callback must carry the new value, not merely say something changed")

    NSApplication.shared.appearance = NSAppearance(named: .aqua)
    #expect(window.appearance == .light)
    #expect(fired == [.dark, .light])
}
