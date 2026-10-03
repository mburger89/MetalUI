import Testing
import Metal
import MetalUICore
import MetalUIPlatform
import MetalUIScene
import MetalUIShaderTypes
@testable import MetalUI
import MetalUIDemoContent

// Lifecycle modifiers, lane 2 — the looks demo's lifecycle section (spec
// `docs/superpowers/specs/2026-10-03-lifecycle-design.md` §5.3 test 10.1 and
// §6; ruling `LC-N`). Each counter is drawn as a bar 8 points per count and 6
// tall in its own colour; nothing else in the looks demo paints a 6-tall rect
// in those colours, so a bar is found by its height and its colour.

private func rgba(_ c: MUIHsla) -> Rgba { Hsla(h: c.h, s: c.s, l: c.l, a: c.a).toRgba() }

private func close(_ a: Rgba, _ b: Rgba, tolerance: Float = 1.0 / 255) -> Bool {
    abs(a.r - b.r) <= tolerance && abs(a.g - b.g) <= tolerance && abs(a.b - b.b) <= tolerance
        && abs(a.a - b.a) <= tolerance
}

// Hand-copied from `LooksDemo.swift`'s `looksLifecycleBar…` colours (another
// module's private constants).
private let appearedColour = Rgba(r: 0.20, g: 0.65, b: 0.35, a: 1)
private let disappearedColour = Rgba(r: 0.85, g: 0.30, b: 0.25, a: 1)
private let changesColour = Rgba(r: 0.25, g: 0.45, b: 0.85, a: 1)

/// The width of the 6-tall bar painted in `colour`, or 0 when none is painted
/// (a zero count draws a zero-width bar, which may emit no rect).
private func barWidth(_ scene: Scene, _ colour: Rgba) -> Float {
    scene.rects.filter { $0.bounds.size.height == 6 && close(rgba($0.background), colour) }
        .map(\.bounds.size.width).max() ?? 0
}

@MainActor
private func click(_ platform: FakePlatformWindow, _ box: Bounds<Pixels>) {
    let point = Point(x: Pixels(box.origin.x.value + box.size.width.value / 2),
                      y: Pixels(box.origin.y.value + box.size.height.value / 2))
    platform.simulateInput(.mouseDown(MouseEvent(position: point)))
    platform.simulateInput(.mouseUp(MouseEvent(position: point)))
}

@MainActor
private func settle(_ window: Window) {
    for _ in 0..<4 where window.needsRedraw { window.drawFrameIfNeeded() }
}

/// The section's controls, found from its stepper: the stepper's increment
/// half is the looks demo's only 20 × 12 clickable hitbox pair's upper one; the
/// "Toggle tile" button is the leftmost clickable hitbox on the stepper's row.
@MainActor
private func controls(_ window: Window) throws -> (toggle: Bounds<Pixels>, increment: Bounds<Pixels>) {
    let clickable = window.lastHitboxes.filter { $0.handlers.onClick != nil }.map(\.bounds)
    let halves = clickable.filter { $0.size.width.value == 20 && $0.size.height.value == 12 }
    try #require(halves.count == 2, "the stepper's two halves: \(halves)")
    let increment = try #require(halves.min { $0.origin.y < $1.origin.y })
    let rowTop = increment.origin.y.value - 12, rowBottom = increment.origin.y.value + 36
    let onRow = clickable.filter {
        let mid = $0.origin.y.value + $0.size.height.value / 2
        return mid > rowTop && mid < rowBottom && $0.origin.x.value + $0.size.width.value < increment.origin.x.value
    }
    let toggle = try #require(onRow.min { $0.origin.x < $1.origin.x }, "no button left of the stepper")
    return (toggle, increment)
}

/// **10.1** (spec §5.3, §6; `LC-N`). `looksDemoContent()` in a fake window:
/// every counter starts at 0; clicking the section's "Toggle tile" twice
/// inserts and removes the tile, so the appear and disappear bars are each 8
/// wide (one count); the stepper's increment changes the value its `onChange`
/// watches, so the change bar is 8. Mutation: the section's `onDisappear`
/// increments the appear counter.
@MainActor
@Test func theLooksLifecycleSectionCountsAppearancesDisappearancesAndChanges() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, platform) = try makeFakeWindow(device: device, size: 1400) { looksDemoContent() }
    window.drawFrameIfNeeded()
    settle(window)
    #expect(barWidth(window.lastScene, appearedColour) == 0, "nothing has appeared yet")
    #expect(barWidth(window.lastScene, disappearedColour) == 0)
    #expect(barWidth(window.lastScene, changesColour) == 0)

    let (toggle, increment) = try controls(window)
    click(platform, toggle)
    settle(window)
    #expect(barWidth(window.lastScene, appearedColour) == 8, "the tile appeared once")
    #expect(barWidth(window.lastScene, disappearedColour) == 0)

    click(platform, toggle)
    settle(window)
    #expect(barWidth(window.lastScene, appearedColour) == 8, "still one appearance")
    #expect(barWidth(window.lastScene, disappearedColour) == 8, "the tile disappeared once")

    click(platform, increment)
    settle(window)
    #expect(barWidth(window.lastScene, changesColour) == 8, "one change")
    #expect(barWidth(window.lastScene, appearedColour) == 8 && barWidth(window.lastScene, disappearedColour) == 8)
    #expect(!window.needsRedraw, "the section settles")
}
