import Foundation
import Testing
import MetalUICore
import MetalUIPlatform
import MetalUIPortableText
@testable import MetalUI
@_spi(Checks) @testable import MetalUISDL
import SDLBridge

// `SpatialTapGesture.Value.clickCount` end to end on SDL (ruling `IF-O`): SDL's `clicks` field of a
// pushed button-down/up reaches the gesture value through `translate`, `Window` and the arena. An `App`
// over a hidden, offscreen-rendering `SDLPlatform` (`TF-C`), so the first frame builds under every driver.

private let fonts = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Tests/Fonts")

@MainActor private final class TapLog { var counts: [Int] = [] }

/// **IF-O.** Two press/release pairs at one point with `clicks` 1 then 2 give a `count: 1` spatial tap
/// the values 1 then 2.
/// Mutation: hard-code `clickCount: 1` where `SpatialTapGesture.Value` is built (or `Int(event.clicks)`
/// replaced by 1 in `SDLPlatform`'s translation).
@MainActor
@Test func anSDLDoubleClickGivesASpatialTapClickCountTwo() throws {
    #if os(macOS)
    armMainRunLoopExitCheck()
    #endif
    let font = [UInt8](try Data(contentsOf: fonts.appendingPathComponent("NotoSans-Regular.ttf")))
    let resolver = try PortableFontResolver(defaultFont: font)
    let platform = try SDLPlatform(hiddenWindows: true, offscreenRenderers: true)
    let app = App(platform: platform, textSystem: { PortableTextSystem(resolver: resolver) })
    platform.pumpEvents()
    let log = TapLog()
    let window = try app.openWindow(title: "spatial tap", size: Size(width: Pixels(120), height: Pixels(80))) {
        Box().frame(width: Pixels(120), height: Pixels(80))
            .gesture(SpatialTapGesture().onEnded { log.counts.append($0.clickCount) })
    }
    platform.pumpEvents()
    let sdl = try #require(window.platformWindow as? SDLWindow)
    func push(_ kind: Int, clicks: Int32) {
        var event = MUIEvent()
        event.kind = UInt32(kind); event.window_id = sdl.id
        event.x = 60; event.y = 40; event.clicks = clicks
        #expect(mui_push_event(&event))
    }
    for n: Int32 in 1...2 {
        push(MUI_EVENT_MOUSE_DOWN, clicks: n)
        push(MUI_EVENT_MOUSE_UP, clicks: n)
    }
    platform.pumpEvents()
    #expect(log.counts == [1, 2], "\(log.counts)")
    withExtendedLifetime(window) {}
}
