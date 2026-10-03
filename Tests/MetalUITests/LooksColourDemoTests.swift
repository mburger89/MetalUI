import Testing
import Metal
import MetalUICore
import MetalUIPlatform
import MetalUIScene
import MetalUIShaderTypes
@testable import MetalUI
import MetalUIDemoContent

// Colour and colour scheme, lane 3 — the looks demo's colour section (spec
// `docs/superpowers/specs/2026-10-03-colour-design.md` §6.3 test 3.1 and §7).
// The section's swatches are 28 × 28 `Color` views; nothing else in the looks
// demo paints a 28 × 28 rect, so a swatch is found by its size and its colour.

private func rgba(_ c: MUIHsla) -> Rgba { Hsla(h: c.h, s: c.s, l: c.l, a: c.a).toRgba() }

private func close(_ a: Rgba, _ b: Rgba, tolerance: Float = 1.0 / 255) -> Bool {
    abs(a.r - b.r) <= tolerance && abs(a.g - b.g) <= tolerance && abs(a.b - b.b) <= tolerance
        && abs(a.a - b.a) <= tolerance
}

private func hex(_ v: UInt32) -> Rgba {
    Rgba(r: Float((v >> 16) & 0xFF) / 255, g: Float((v >> 8) & 0xFF) / 255, b: Float(v & 0xFF) / 255, a: 1)
}

/// The colours of every 28 × 28 rect: the swatches.
private func swatches(_ scene: Scene) -> [Rgba] {
    scene.rects.filter { $0.bounds.size.width == 28 && $0.bounds.size.height == 28 }.map { rgba($0.background) }
}

private func shows(_ scene: Scene, _ want: Rgba) -> Bool {
    swatches(scene).contains { close($0, want) }
}

// Hand-derived from the spellings in `looksColourSection()` and the probe's
// table (spec §3.2): `.red` is FF383C light, FF4245 dark.
private let redLight = hex(0xFF383C)
private let redDark = hex(0xFF4245)
/// The section's `Color(light:dark:)` swatch.
private let dynamicLight = Rgba(r: 0.95, g: 0.75, b: 0.20, a: 1)
private let dynamicDark = Rgba(r: 0.20, g: 0.30, b: 0.75, a: 1)
/// `LooksBrand.defaultValue`'s halves, and the demo's dark override.
private let brandLight = Rgba(r: 0.55, g: 0.25, b: 0.85, a: 1)
private let brandDarkDefault = Rgba(r: 0.70, g: 0.45, b: 0.95, a: 1)
private let brandDarkOverride = Rgba(r: 0.30, g: 0.85, b: 0.70, a: 1)
/// The section's fixed literal, `Color(red: 0.2, green: 0.4, blue: 0.6)`.
private let literal = Rgba(r: 0.2, g: 0.4, b: 0.6, a: 1)

/// A looks-demo window as `MetalUIDemo` opens it with `METALUI_LOOKS_DEMO=1`:
/// the dark variant carries the demo's palette override.
@MainActor
private func looksWindow(_ device: any MTLDevice, appearance: ColorScheme) throws -> (Window, FakePlatformWindow) {
    let (window, platform) = try makeFakeWindow(device: device, size: 1400, appearance: appearance) {
        looksDemoContent()
    }
    window.darkTheme[LooksBrand.self] = looksBrandDarkOverride
    return (window, platform)
}

/// Presses the colour section's scheme toggle: the lowest clickable hitbox
/// (the section is the demo's last row, below every transition button).
@MainActor
private func pressSchemeToggle(_ window: Window, _ platform: FakePlatformWindow) throws {
    let toggle = try #require(window.lastHitboxes.filter { $0.handlers.onClick != nil }
        .max { $0.bounds.origin.y < $1.bounds.origin.y })
    let point = Point(x: toggle.bounds.origin.x + Pixels(4), y: toggle.bounds.origin.y + Pixels(4))
    platform.simulateInput(.mouseDown(MouseEvent(position: point)))
    platform.simulateInput(.mouseUp(MouseEvent(position: point)))
}

/// **3.1** (spec §6.3, §7). `looksDemoContent()` in a light and a dark fake
/// window: the `.red` swatch is FF383C / FF4245, the `Color(light:dark:)`
/// swatch flips, the fixed literal does not, and the palette swatch shows
/// `LooksBrand`'s light default in the light window and the demo's dark
/// override (not the key's dark default) in the dark one. Then the toggle:
/// System → Light → Dark forces the whole window (`CR-L`) from input.
/// Mutation: the demo's dynamic swatch written as a light-only literal.
@MainActor
@Test func theLooksColourSectionPaintsLiteralDynamicAndPaletteColours() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())

    let (light, _) = try looksWindow(device, appearance: .light)
    light.drawFrameIfNeeded()
    let lightScene = light.lastScene
    try #require(swatches(lightScene).count >= 21, "the swatch row: \(swatches(lightScene).count)")
    #expect(shows(lightScene, redLight) && !shows(lightScene, redDark), "red, light: \(swatches(lightScene))")
    #expect(shows(lightScene, dynamicLight) && !shows(lightScene, dynamicDark), "dynamic, light")
    #expect(shows(lightScene, literal), "the fixed literal, light")
    #expect(shows(lightScene, brandLight) && !shows(lightScene, brandDarkOverride), "palette, light")

    let (dark, platform) = try looksWindow(device, appearance: .dark)
    dark.drawFrameIfNeeded()
    let darkScene = dark.lastScene
    #expect(shows(darkScene, redDark) && !shows(darkScene, redLight), "red, dark: \(swatches(darkScene))")
    #expect(shows(darkScene, dynamicDark) && !shows(darkScene, dynamicLight), "dynamic, dark")
    #expect(shows(darkScene, literal), "the fixed literal, dark")
    #expect(shows(darkScene, brandDarkOverride) && !shows(darkScene, brandDarkDefault),
            "palette, dark: the demo's override, not the key's default")

    // The toggle, from input: System → Light forces the dark window light.
    try pressSchemeToggle(dark, platform)
    for _ in 0..<3 where dark.needsRedraw { dark.drawFrameIfNeeded() }
    #expect(dark.colorScheme == .light, "System → Light")
    #expect(shows(dark.lastScene, redLight) && shows(dark.lastScene, brandLight), "forced light")
    #expect(platform.preferredColorSchemeRequests.last == .light)

    // Light → Dark.
    try pressSchemeToggle(dark, platform)
    for _ in 0..<3 where dark.needsRedraw { dark.drawFrameIfNeeded() }
    #expect(dark.colorScheme == .dark, "Light → Dark")
    #expect(shows(dark.lastScene, redDark) && shows(dark.lastScene, brandDarkOverride), "forced dark")

    // Dark → System: back to the platform's appearance, the preference cleared.
    try pressSchemeToggle(dark, platform)
    for _ in 0..<3 where dark.needsRedraw { dark.drawFrameIfNeeded() }
    #expect(dark.colorScheme == .dark)
    #expect(platform.preferredColorSchemeRequests.last == .some(nil), "\(platform.preferredColorSchemeRequests)")
}
