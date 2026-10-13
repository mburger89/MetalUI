import MetalUI
import MetalUIScene
import MetalUITesting
import Testing

// C27 lane B — Reduce Transparency through the real `Window` over the headless
// platform (rulings `MT-D`, `MT-G`; spec tests 6 and 15): plain imports, what an
// app's test target writes. The scene's backdrop records are the observable: a
// material is a record while transparency is allowed, a plain opaque rect once
// the platform asks to reduce it.

@MainActor private func materialTree() -> some Element {
    VStack(spacing: 0) {
        Color.clear.frame(width: Pixels(40), height: Pixels(20)).background(.regularMaterial)
    }
}

/// **6 and 15** (`MT-D`, `MT-G`, `HT-X` 1). The window reads the platform window's
/// Reduce Transparency at construction (the option; default `false`, AppKit's answer
/// with the setting off) and again on every change `setReduceTransparency` reports:
/// a material is one backdrop record while off, none and one opaque rect while on.
/// Mutations: drop the stamp in `Window.drawFrame` (every arm but the default);
/// the option ignored by `HeadlessPlatformWindow` (the opened-on arm).
@Test @MainActor func theWindowStampsReduceTransparencyFromItsPlatformWindow() throws {
    let normal = try harnessWindow { materialTree() }
    #expect(normal.scene.backdrops.count == 1, "the default is off: a material blurs")
    let opened = try harnessWindow(options: .init(accessibilityReduceTransparency: true)) { materialTree() }
    #expect(opened.platformWindow.accessibilityReduceTransparency, "the option reaches the platform window")
    #expect(opened.scene.backdrops.isEmpty, "a window opened with it on draws no backdrop in its first frame")
    #expect(opened.scene.rects.contains { $0.bounds.size.width == 40 && $0.bounds.size.height == 20 && $0.background.a == 1 },
            "and an opaque 40 x 20 rect instead")

    normal.setReduceTransparency(true)
    #expect(normal.scene.backdrops.isEmpty, "turned on at run time, the next frame is opaque")
    normal.setReduceTransparency(false)
    #expect(normal.scene.backdrops.count == 1, "and turned off, the blur returns")
}

/// **6** (`MT-D`). A report of the value the window already has does not repaint;
/// a change does. Mutation: drop `Window.accessibilityReduceTransparency`'s `didSet`
/// guard.
@Test @MainActor func reduceTransparencyRedrawsOnceAndNotOnARepeat() throws {
    let window = try harnessWindow { materialTree() }
    window.tick()
    try #require(!window.window.needsRedraw, "settled")
    window.platformWindow.simulateReduceTransparencyChange(to: false)
    #expect(!window.window.needsRedraw, "a repeat of the current value must not repaint")
    window.platformWindow.simulateReduceTransparencyChange(to: true)
    #expect(window.window.needsRedraw, "a change repaints")
    window.tick()
    window.platformWindow.simulateReduceTransparencyChange(to: true)
    #expect(!window.window.needsRedraw, "and a repeat of the new value does not")
}
