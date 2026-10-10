import Testing
import Metal
import MetalUICore
import MetalUIPlatform
import MetalUIDemoContent
@testable import MetalUI

// Key and focus scoping, lane C — the demo (spec
// `docs/superpowers/specs/2026-10-08-key-focus-design.md` §6).
// `METALUI_KEY_FOCUS_DEMO=1` opens `keyFocusDemoContent()` in both demos; this
// pins, headlessly, what human checks KF-1…KF-5 then look at. Red before: the
// demo does not exist at `c62d6ba` — the file fails by not compiling.

private func kfpt(_ x: Float, _ y: Float) -> Point<Pixels> { Point(x: Pixels(x), y: Pixels(y)) }

private func kfCentre(_ b: Bounds<Pixels>) -> Point<Pixels> {
    kfpt(b.origin.x.value + b.size.width.value / 2, b.origin.y.value + b.size.height.value / 2)
}

private func kfKey(_ c: String) -> InputEvent {
    .keyDown(KeyEvent(charactersIgnoringModifiers: c, characters: c, modifiers: [], isRepeat: false, timestamp: 0))
}

@MainActor private func kfSettle(_ window: Window) {
    window.setNeedsRedraw()
    for _ in 0..<8 where window.needsRedraw { window.drawFrameIfNeeded() }
}

/// **Demo** (spec §6). Headless, through a real `Window`: the viewport's size
/// label is right after the first frames (240 × 200, its declared frame); Tab
/// with the pointer over the canvas's key region and nothing focused reaches
/// the canvas after the root (outermost first) and opens the palette; a press
/// on the viewport focuses it (one `KeyboardModifier` layer) and a key then
/// goes to it.
@MainActor
@Test func theKeyFocusDemoRoutesTabOverTheCanvasAndKeysToAClickedViewport() throws {
    keyFocusDemoModel.reset()
    defer { keyFocusDemoModel.reset() }
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let (window, platform) = try makeFakeWindow(device: device, size: 1000) { keyFocusDemoContent() }
    kfSettle(window)
    #expect(keyFocusDemoModel.viewportSize == "240 × 200", "\(keyFocusDemoModel.viewportSize)")

    let canvas = try #require(window.lastHitboxes.first { $0.handlers.isKeyRegion }, "the canvas's key region")
    platform.simulateInput(.mouseMoved(MouseEvent(position: kfCentre(canvas.bounds))))
    #expect(platform.simulateInput(kfKey("\t")), "the canvas claims Tab")
    kfSettle(window)
    #expect(keyFocusDemoModel.trail == ["root", "canvas"], "\(keyFocusDemoModel.trail)")
    #expect(keyFocusDemoModel.paletteOpen, "Tab over the canvas opened the palette")

    let viewport = try #require(window.lastHitboxes.first { $0.handlers.focusesOnPress }, "the viewport's press region")
    platform.simulateInput(.mouseDown(MouseEvent(position: kfCentre(viewport.bounds))))
    platform.simulateInput(.mouseUp(MouseEvent(position: kfCentre(viewport.bounds))))
    #expect(window.focusedElement == viewport.id, "the press focused the viewport")
    kfSettle(window)
    #expect(platform.simulateInput(kfKey("x")))
    #expect(keyFocusDemoModel.trail == ["root", "viewport"] && keyFocusDemoModel.viewportKeys == 1,
            "\(keyFocusDemoModel.trail), \(keyFocusDemoModel.viewportKeys)")
}
