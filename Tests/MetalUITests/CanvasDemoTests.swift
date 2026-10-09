import Testing
import Metal
import MetalUICore
import MetalUIPlatform
import MetalUIDemoContent
@testable import MetalUI

// Input APIs, lane C — the canvas demo (spec
// `docs/superpowers/specs/2026-10-08-input-apis-design.md` §6, §4.3 test 3.35;
// rulings `CI-AE` item 3, `CI-AI`). `METALUI_CANVAS_DEMO=1` opens
// `canvasDemoContent()` in both demos (`MetalUIDemo`, `MetalUISDLDemo`); this
// pins, headlessly, what human checks Y1–Y13 then look at. Red before: the
// demo does not exist at `c101fe6` — the file fails by not compiling.
//
// **Literals derived before the run** (the demo's arithmetic, `CI-AI` item 2):
// a canvas point `c` is drawn at the canvas-local point `pan + c × zoom`; a
// zoom by `f` about the local point `p` keeps the canvas point under `p`, so
// `pan' = p − (p − pan) × f`. ⌘-wheel zooms by `2^(Δy / 100)`.

private func cpt(_ x: Float, _ y: Float) -> Point<Pixels> { Point(x: Pixels(x), y: Pixels(y)) }

/// A 760 × 760 window over the canvas demo, menus native, drawn until clean;
/// the shared model reset first.
@MainActor private func canvasWindow() throws -> (Window, FakePlatformWindow) {
    canvasDemoModel.reset()
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let (window, platform) = try makeFakeWindow(device: device, size: 760) { canvasDemoContent() }
    platform.presentsMenusNatively = true
    canvasSettle(window)
    return (window, platform)
}

@MainActor private func canvasSettle(_ window: Window) {
    window.setNeedsRedraw()
    for _ in 0..<8 where window.needsRedraw { window.drawFrameIfNeeded() }
}

/// The canvas's window origin: the one region carrying a wheel handler.
@MainActor private func canvasOrigin(_ window: Window, sourceLocation: SourceLocation = #_sourceLocation)
    throws -> Point<Pixels> {
    let canvas = try #require(window.lastHitboxes.first { $0.handlers.pointer?.scrollWheel != nil },
                              "the canvas's wheel region", sourceLocation: sourceLocation)
    #expect(canvas.bounds.size.width == 640 && canvas.bounds.size.height == 420, "\(canvas.bounds)",
            sourceLocation: sourceLocation)
    return canvas.bounds.origin
}

private func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.001 }

/// **3.35** (`CI-AE` item 3, spec §6). Headless, through a real `Window`: a
/// middle drag moves the pan by its translation; a pinch and a ⌘-wheel each
/// keep the canvas point under the pointer fixed; a spatial tap selects the
/// node under it and an empty point clears it; the platform is asked for the
/// crosshair over empty canvas and the pointing hand over a node; a right-click
/// on a node opens a menu naming it.
@MainActor
@Test func theCanvasDemoPansZoomsAboutThePointerPicksAndShowsACrosshair() throws {
    let (window, platform) = try canvasWindow()
    let o = try canvasOrigin(window)
    func at(_ x: Float, _ y: Float) -> Point<Pixels> { cpt(o.x.value + x, o.y.value + y) }
    let model = canvasDemoModel

    // A middle drag from local (300, 200) by (60, 40): pan (0, 0) → (60, 40).
    platform.simulateInput(.otherMouseDown(MouseEvent(position: at(300, 200), buttonNumber: 2)))
    platform.simulateInput(.otherMouseDragged(MouseEvent(position: at(330, 220), buttonNumber: 2)))
    platform.simulateInput(.otherMouseDragged(MouseEvent(position: at(360, 240), buttonNumber: 2)))
    platform.simulateInput(.otherMouseUp(MouseEvent(position: at(360, 240), buttonNumber: 2)))
    #expect(near(model.panX, 60) && near(model.panY, 40), "middle drag: \(model.panX), \(model.panY)")
    canvasSettle(window)

    // A pinch at local (160, 140): canvas point ((160 − 60) / 1, (140 − 40) / 1)
    // = (100, 100); magnification 1.5 → zoom 1.5, pan (160 − 150, 140 − 150) = (10, −10).
    platform.simulateInput(.magnify(MagnifyEvent(position: at(160, 140), magnification: 0, phase: .began)))
    platform.simulateInput(.magnify(MagnifyEvent(position: at(160, 140), magnification: 0.5, phase: .changed)))
    platform.simulateInput(.magnify(MagnifyEvent(position: at(160, 140), magnification: 0, phase: .ended)))
    #expect(near(model.zoom, 1.5), "pinch zoom: \(model.zoom)")
    #expect(near(model.panX, 10) && near(model.panY, -10), "pinch pan: \(model.panX), \(model.panY)")
    canvasSettle(window)

    // ⌘-wheel Δy 100 at local (200, 150): zoom × 2 → 3; canvas point
    // ((200 − 10) / 1.5, (150 + 10) / 1.5); pan' = (200 − 190 × 2, 150 − 160 × 2) = (−180, −170).
    platform.simulateInput(.scrollWheel(ScrollEvent(position: at(200, 150), delta: cpt(0, 100),
                                                    modifiers: [.command])))
    #expect(near(model.zoom, 3), "⌘-wheel zoom: \(model.zoom)")
    #expect(near(model.panX, -180) && near(model.panY, -170), "⌘-wheel pan: \(model.panX), \(model.panY)")

    // A plain wheel pans by its delta: (−180 + 7, −170 − 11).
    platform.simulateInput(.scrollWheel(ScrollEvent(position: at(200, 150), delta: cpt(7, -11))))
    #expect(near(model.panX, -173) && near(model.panY, -181), "wheel pan: \(model.panX), \(model.panY)")

    // Back to the identity view: node 0 ("Sketch", canvas (40, 60), 120 × 56)
    // is drawn at local (40, 60).
    model.reset()
    canvasSettle(window)
    platform.simulateInput(.mouseDown(MouseEvent(position: at(60, 80))))
    platform.simulateInput(.mouseUp(MouseEvent(position: at(60, 80))))
    #expect(model.selected == 0, "a tap on Sketch: \(String(describing: model.selected))")
    canvasSettle(window)

    // The pointer over empty canvas, then over node 0.
    platform.simulateInput(.mouseMoved(MouseEvent(position: at(20, 400))))
    #expect(platform.pointerStyles.last == .crosshair, "\(platform.pointerStyles)")
    platform.simulateInput(.mouseMoved(MouseEvent(position: at(60, 80))))
    #expect(platform.pointerStyles.last == .pointingHand, "\(platform.pointerStyles)")

    // A tap on empty canvas clears the selection.
    platform.simulateInput(.mouseDown(MouseEvent(position: at(20, 400))))
    platform.simulateInput(.mouseUp(MouseEvent(position: at(20, 400))))
    #expect(model.selected == nil, "a tap on empty canvas: \(String(describing: model.selected))")

    // A right-click on node 1 ("Extrude", canvas (220, 40)) opens, on the
    // release (a secondary drag is declared, `CI-F` item 4), a menu naming it.
    let menusBefore = platform.presentedMenus.count
    platform.simulateInput(.rightMouseDown(MouseEvent(position: at(240, 60), buttonNumber: 1)))
    #expect(platform.presentedMenus.count == menusBefore, "no menu on the press")
    platform.simulateInput(.rightMouseUp(MouseEvent(position: at(240, 60), buttonNumber: 1)))
    let menu = try #require(platform.presentedMenus.last?.menu, "a menu on the release")
    #expect(menu.items.first?.title == "Inspect Extrude", "\(menu.items.map(\.title))")
    withExtendedLifetime(window) {}
}
