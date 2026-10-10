import Testing
import Metal
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// C10 lane 1: the drawn colour panel (rulings `LK-C` item 5, `LK-D`; spec
// `2026-10-08-controls-looks-design.md` §3.1, §4.1). SwiftUI has no drawn
// panel to measure, so every rule here is MetalUI's (`LK-D`), except the
// binding's: every write is a gamma-sRGB literal (`C4`–`C6`), opacity 1
// without `supportsOpacity` (`C8`). Helpers are `ColorPickerTests.swift`'s
// `picker…` and `ButtonTests.swift`'s `control…`.
//
// The panel's parts (`LK-D` item 1): a 200×150 square (x = saturation 0…1,
// y = brightness 1…0), a 200×14 hue bar, a 200×14 opacity bar only with
// `supportsOpacity`, then a 24×24 swatch and the hex field. Every expected
// colour below is the HSB → sRGB arithmetic of the point pressed, derived
// before the run.

/// A press-and-release at `(x, y)` inside `bounds`, then a frame.
@MainActor
private func click(_ window: Window, _ platform: FakePlatformWindow, _ bounds: Bounds<Pixels>,
                   _ x: Float, _ y: Float) {
    let point = Point(x: controlPx(bounds.origin.x.value + x), y: controlPx(bounds.origin.y.value + y))
    platform.simulateInput(.mouseDown(MouseEvent(position: point)))
    platform.simulateInput(.mouseUp(MouseEvent(position: point)))
    controlRedraw(window)
}

/// The panel's bars (hue, then opacity when shown), top to bottom.
@MainActor
private func bars(_ window: Window) -> [(id: GlobalElementID, bounds: Bounds<Pixels>)] {
    pickerBounds(window, width: 200, height: 14)
}

/// The hex field's published text.
@MainActor
private func hexText(_ window: Window, _ platform: FakePlatformWindow) throws -> String {
    let tree = try controlTree(window, platform)
    let field = try #require(tree.nodes.first { $0.value.role == .textField }, "no hex field published")
    return field.value.value ?? ""
}

/// Types `text` into the hex field over whatever it holds, then Return.
@MainActor
private func submitHex(_ text: String, _ window: Window, _ platform: FakePlatformWindow) throws {
    let field = try #require(window.lastHitboxes.last { $0.handlers.textInput != nil }, "no hex field")
    controlClick(platform, at: controlCentre(field.bounds))
    controlRedraw(window)
    platform.simulateInput(controlKey("a", TextEditing.platform == .mac ? .command : .control))
    platform.simulateInput(.textInput(text))
    controlRedraw(window)
    platform.simulateInput(controlKey("\r"))
    controlRedraw(window)
}

/// Components within 1e-4 of `expected` (Float storage, `CR-`).
private func near(_ color: Color?, _ expected: (Double, Double, Double, Double)) -> Bool {
    guard let color else { return false }
    let r = color.resolve(in: EnvironmentValues())
    return abs(Double(r.red) - expected.0) < 1e-4 && abs(Double(r.green) - expected.1) < 1e-4
        && abs(Double(r.blue) - expected.2) < 1e-4 && abs(Double(r.opacity) - expected.3) < 1e-4
}

// MARK: - Pointer (LK-D item 3)

/// **1.24.** A press on the square at (¼, ½) of a hue-0 colour writes
/// saturation 0.25 and brightness 0.5: chroma 0.125, so `Color(.sRGB, red:
/// 0.5, green: 0.375, blue: 0.375)` exactly — the axes swapped would write
/// s 0.5, b 0.75, `(0.75, 0.375, 0.375)`. (The first spelling pressed at
/// (¼, ¼), where swapping the axes writes the same colour: the mutation
/// stayed green on it.) Mutation: swap the axes.
@Test @MainActor func aDragOnTheSquareWritesSaturationAndBrightness() throws {
    let model = PickerModel(Color(.sRGB, red: 1, green: 0, blue: 0))
    let (window, platform) = try pickerWindow { ColorPicker("Tint", selection: model.binding) }
    let square = try pickerOpen(window, platform)
    click(window, platform, square, 50, 75)
    #expect(model.writes.first == Color(.sRGB, red: 0.5, green: 0.375, blue: 0.375, opacity: 1),
            "\(model.writes)")
}

/// **1.25.** A press on the hue bar's middle sets hue ½ (180°) and keeps
/// saturation 0.25 and brightness 0.75: `(0.5625, 0.75, 0.75)`. Mutation:
/// reset saturation and brightness on a hue drag.
@Test @MainActor func aDragOnTheHueBarWritesTheHueKeepingSaturationAndBrightness() throws {
    let model = PickerModel(Color(.sRGB, red: 0.75, green: 0.5625, blue: 0.5625))
    let (window, platform) = try pickerWindow { ColorPicker("Tint", selection: model.binding) }
    _ = try pickerOpen(window, platform)
    let hue = try #require(bars(window).first, "no hue bar").bounds
    click(window, platform, hue, 100, 7)
    #expect(model.writes.first == Color(.sRGB, red: 0.5625, green: 0.75, blue: 0.75, opacity: 1), "\(model.writes)")
}

/// **1.26** (C8). Without `supportsOpacity` there is no opacity bar — one
/// 200×14 bar, two with it. Mutation: always show the opacity bar.
@Test @MainActor func theOpacityBarIsAbsentWithoutSupportsOpacity() throws {
    for (supports, count) in [(true, 2), (false, 1)] {
        let model = PickerModel(.red)
        let (window, platform) = try pickerWindow {
            ColorPicker("Tint", selection: model.binding, supportsOpacity: supports)
        }
        _ = try pickerOpen(window, platform)
        #expect(bars(window).count == count, "supportsOpacity \(supports): \(bars(window).count) bars")
    }
}

/// **1.27** (C8). Without `supportsOpacity` every write carries opacity 1,
/// even from a half-transparent selection. Mutation: pass the panel's alpha
/// through.
@Test @MainActor func everyWriteHasOpacityOneWithoutSupportsOpacity() throws {
    let model = PickerModel(Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 0.5))
    let (window, platform) = try pickerWindow {
        ColorPicker("Tint", selection: model.binding, supportsOpacity: false)
    }
    let square = try pickerOpen(window, platform)
    click(window, platform, square, 50, 37.5)
    #expect(model.writes.first == Color(.sRGB, red: 0.75, green: 0.5625, blue: 0.5625, opacity: 1), "\(model.writes)")
}

/// **1.28** (`LK-D` item 4). The hue survives saturation 0 while dragging: from
/// blue (hue ⅔) a drag past the square's top-left writes white (s 0, b 1),
/// and a drag on to (100, above the top) writes `(0.5, 0.5, 1)` — hue ⅔ kept,
/// not white's hue 0, which would write `(1, 0.5, 0.5)`. Mutation: re-seed from
/// the binding every frame.
@Test @MainActor func theHueSurvivesSaturationZeroWhileDragging() throws {
    let model = PickerModel(Color(.sRGB, red: 0, green: 0, blue: 1))
    let (window, platform) = try pickerWindow { ColorPicker("Tint", selection: model.binding) }
    let square = try pickerOpen(window, platform)
    func point(_ x: Float, _ y: Float) -> MouseEvent {
        MouseEvent(position: Point(x: controlPx(square.origin.x.value + x), y: controlPx(square.origin.y.value + y)))
    }
    platform.simulateInput(.mouseDown(point(100, 75)))
    controlRedraw(window)
    platform.simulateInput(.mouseDragged(point(-50, -10)))
    controlRedraw(window)
    platform.simulateInput(.mouseDragged(point(100, -10)))
    controlRedraw(window)
    platform.simulateInput(.mouseUp(point(100, -10)))
    try #require(model.writes.count >= 3, "a press and two moves each write: \(model.writes)")
    #expect(model.writes[model.writes.count - 2] == Color(.sRGB, red: 1, green: 1, blue: 1, opacity: 1),
            "the move past the corner writes white: \(model.writes)")
    #expect(model.writes.last == Color(.sRGB, red: 0.5, green: 0.5, blue: 1, opacity: 1), "\(model.writes)")
    // The drag above runs on the callbacks its press captured, whose seed is
    // still blue — so it alone cannot tell a re-seed from white. The key runs
    // on the latest frame's handler: back at white (a press and a drag past
    // the corner), → writes s 0.01 at hue ⅔, `(0.99, 0.99, 1)`; re-seeded
    // from white it would write hue 0, `(1, 0.99, 0.99)`.
    platform.simulateInput(.mouseDown(point(100, 75)))
    platform.simulateInput(.mouseDragged(point(-50, -10)))
    platform.simulateInput(.mouseUp(point(-50, -10)))
    controlRedraw(window)
    controlRedraw(window)
    try #require(model.writes.last == Color(.sRGB, red: 1, green: 1, blue: 1, opacity: 1), "back at white")
    window.focus(try #require(pickerSquare(window)).id)
    window.drawFrameIfNeeded()
    platform.simulateInput(controlKey(TextEditing.rightArrow))
    #expect(near(model.writes.last, (0.99, 0.99, 1, 1)), "the hue survived white: \(model.writes.last.map { "\($0)" } ?? "nil")")
}

/// **1.29** (`LK-D` item 4). A binding write from outside while the panel is
/// open re-seeds it: after a write from the panel on red, an outside write of
/// blue, then a press at (¾, ¼), writes hue ⅔ at s 0.75, b 0.75 — `(0.1875,
/// 0.1875, 0.75)`, not red's hue `(0.75, 0.1875, 0.1875)`. Mutation: never
/// re-seed.
@Test @MainActor func anOutsideWriteWhileOpenReSeedsThePanel() throws {
    let model = PickerModel(Color(.sRGB, red: 1, green: 0, blue: 0))
    let (window, platform) = try pickerWindow { ColorPicker("Tint", selection: model.binding) }
    let square = try pickerOpen(window, platform)
    click(window, platform, square, 50, 37.5)
    try #require(model.writes.count >= 1, "set up: the panel wrote")
    model.color = Color(.sRGB, red: 0, green: 0, blue: 1)
    controlRedraw(window)
    click(window, platform, square, 150, 37.5)
    #expect(model.writes.last == Color(.sRGB, red: 0.1875, green: 0.1875, blue: 0.75, opacity: 1), "\(model.writes)")
}

/// **1.30** (`LK-C` item 5). A dynamic selection in a dark window opens at
/// its resolved dark half (the field reads `#0000FF`) and a hue press writes a
/// plain literal (`(0, 1, 1)`, hue ½ at blue's s 1, b 1); a token selection
/// (`.accent`) opens at the dark theme's accent. Mutation: seed from the light
/// half regardless of the scheme.
@Test @MainActor func aTokenSelectionOpensAtItsResolvedValueAndTheFirstEditWritesALiteral() throws {
    let dynamic = Color(light: Color(.sRGB, red: 1, green: 0, blue: 0), dark: Color(.sRGB, red: 0, green: 0, blue: 1))
    let model = PickerModel(dynamic)
    let (window, platform) = try pickerWindow(appearance: .dark) { ColorPicker("Tint", selection: model.binding) }
    _ = try pickerOpen(window, platform)
    #expect(try hexText(window, platform) == "#0000FF", "the dark half")
    let hue = try #require(bars(window).first, "no hue bar").bounds
    click(window, platform, hue, 100, 7)
    #expect(model.writes.first == Color(.sRGB, red: 0, green: 1, blue: 1, opacity: 1), "a literal: \(model.writes)")

    let token = PickerModel(.accent)
    let (tokenWindow, tokenPlatform) = try pickerWindow(appearance: .dark) {
        ColorPicker("Tint", selection: token.binding)
    }
    _ = try pickerOpen(tokenWindow, tokenPlatform)
    let accent = tokenWindow.darkTheme[.accent].toRgba()
    let expected = ColorMath.hexString(ColorMath.RGBA(red: Double(accent.r), green: Double(accent.g),
                                                      blue: Double(accent.b), opacity: Double(accent.a)),
                                       includesAlpha: false)
    let lightAccent = tokenWindow.lightTheme[.accent].toRgba()
    try #require(ColorMath.hexString(ColorMath.RGBA(red: Double(lightAccent.r), green: Double(lightAccent.g),
                                                    blue: Double(lightAccent.b), opacity: 1),
                                     includesAlpha: false) != expected,
                 "set up: the two themes' accents differ")
    #expect(try hexText(tokenWindow, tokenPlatform) == expected, "the dark theme's accent")
}

// MARK: - The hex field (LK-D item 6)

/// **1.31.** The field accepts `#RRGGBB`, `RRGGBB`, `#RGB` and, with
/// `supportsOpacity`, `#RRGGBBAA`; each valid submit writes. Mutation: write
/// only the `#RRGGBB` form.
@Test @MainActor func theHexFieldAcceptsTheFourForms() throws {
    let cases: [(String, (Double, Double, Double, Double))] = [
        ("#FF8000", (1, 128.0 / 255, 0, 1)),
        ("00ff80", (0, 1, 128.0 / 255, 1)),
        ("#08F", (0, 136.0 / 255, 1, 1)),
        ("#FF800080", (1, 128.0 / 255, 0, 128.0 / 255)),
    ]
    for (text, expected) in cases {
        let model = PickerModel(.red)
        let (window, platform) = try pickerWindow { ColorPicker("Tint", selection: model.binding) }
        _ = try pickerOpen(window, platform)
        try submitHex(text, window, platform)
        #expect(model.writes.count == 1 && near(model.writes.last, expected), "\(text): \(model.writes)")
    }
}

/// **1.32.** An invalid string writes nothing and the field reverts to the
/// current colour. Mutation: write on invalid.
@Test @MainActor func anInvalidHexRevertsAndWritesNothing() throws {
    let model = PickerModel(Color(.sRGB, red: 1, green: 0, blue: 0))
    let (window, platform) = try pickerWindow { ColorPicker("Tint", selection: model.binding) }
    _ = try pickerOpen(window, platform)
    try submitHex("#12345", window, platform)
    #expect(model.writes.isEmpty, "\(model.writes)")
    #expect(try hexText(window, platform) == "#FF0000", "reverted")
}

/// **1.33.** Without `supportsOpacity` an alpha hex is refused. Mutation:
/// accept `#RRGGBBAA` regardless.
@Test @MainActor func alphaHexIsRefusedWithoutSupportsOpacity() throws {
    let model = PickerModel(Color(.sRGB, red: 1, green: 0, blue: 0))
    let (window, platform) = try pickerWindow {
        ColorPicker("Tint", selection: model.binding, supportsOpacity: false)
    }
    _ = try pickerOpen(window, platform)
    try submitHex("#00FF0080", window, platform)
    #expect(model.writes.isEmpty, "\(model.writes)")
}

/// **1.34.** The field shows `#RRGGBB` uppercase, `#RRGGBBAA` only when the
/// opacity is below 1 and `supportsOpacity`. Mutation: always 8 digits.
@Test @MainActor func theHexFieldShowsUppercaseWithAlphaOnlyBelowOne() throws {
    let cases: [(Color, Bool, String)] = [
        (Color(.sRGB, red: 1, green: 0.5, blue: 0), true, "#FF8000"),
        (Color(.sRGB, red: 1, green: 0.5, blue: 0, opacity: 0.5), true, "#FF800080"),
        (Color(.sRGB, red: 1, green: 0.5, blue: 0, opacity: 0.5), false, "#FF8000"),
    ]
    for (color, supports, expected) in cases {
        let model = PickerModel(color)
        let (window, platform) = try pickerWindow {
            ColorPicker("Tint", selection: model.binding, supportsOpacity: supports)
        }
        _ = try pickerOpen(window, platform)
        #expect(try hexText(window, platform) == expected, "\(expected)")
    }
}

// MARK: - Keys and accessibility (LK-D items 5, 7)

/// **1.35.** On the focused square → adds 0.01 saturation and ⇧↑ 0.1
/// brightness; on the hue bar → adds 1°, ⇧← takes 10° (wrapping); on the
/// opacity bar ← takes 0.01. From (h 0, s 0.5, b 0.5) = `(0.5, 0.25, 0.25)`.
/// Mutation: step 0.1 unshifted.
@Test @MainActor func squareAndBarKeysStepByOneHundredthAndShiftByATenth() throws {
    let model = PickerModel(Color(.sRGB, red: 0.5, green: 0.25, blue: 0.25))
    let (window, platform) = try pickerWindow { ColorPicker("Tint", selection: model.binding) }
    _ = try pickerOpen(window, platform)
    func hsba() throws -> [Double] {
        let r = try #require(model.writes.last).resolve(in: EnvironmentValues())
        let hsb = ColorMath.hsb(from: ColorMath.RGB(red: Double(r.red), green: Double(r.green), blue: Double(r.blue)))
        return [hsb.hue, hsb.saturation, hsb.brightness, Double(r.opacity)]
    }
    func close(_ a: [Double], _ b: [Double]) -> Bool { zip(a, b).allSatisfy { abs($0 - $1) < 1e-4 } }
    func press(_ id: GlobalElementID, _ key: String, _ modifiers: Modifiers = []) {
        window.focus(id)
        window.drawFrameIfNeeded()
        platform.simulateInput(controlKey(key, modifiers))
        controlRedraw(window)
    }
    let square = try #require(pickerSquare(window)).id
    press(square, TextEditing.rightArrow)
    let v1 = try hsba()
    #expect(close(v1, [0, 0.51, 0.5, 1]), "→ on the square: \(v1)")
    press(square, TextEditing.upArrow, .shift)
    let v2 = try hsba()
    #expect(close(v2, [0, 0.51, 0.6, 1]), "⇧↑ on the square: \(v2)")
    let hueBar = try #require(bars(window).first).id
    press(hueBar, TextEditing.rightArrow)
    let v3 = try hsba()
    #expect(close(v3, [1.0 / 360, 0.51, 0.6, 1]), "→ on the hue bar: \(v3)")
    press(hueBar, TextEditing.leftArrow, .shift)
    let v4 = try hsba()
    #expect(close(v4, [351.0 / 360, 0.51, 0.6, 1]), "⇧← on the hue bar wraps: \(v4)")
    let opacityBar = try #require(bars(window).last).id
    press(opacityBar, TextEditing.leftArrow)
    let v5 = try hsba()
    #expect(close(v5, [351.0 / 360, 0.51, 0.6, 0.99]), "← on the opacity bar: \(v5)")
}

/// **1.36.** Escape closes the panel (the popover rule, `MN-N`): the square
/// is gone on the next frame. Mutation (the spec's "swallow Escape in the
/// panel" cannot redden — the popovers' stage precedes every key handler —
/// so the separating one): the well's popover binding ignores `false`.
@Test @MainActor func escapeClosesThePanel() throws {
    let model = PickerModel(.red)
    let (window, platform) = try pickerWindow { ColorPicker("Tint", selection: model.binding) }
    let square = try pickerOpen(window, platform)
    _ = square
    window.focus(try #require(pickerSquare(window)).id)
    window.drawFrameIfNeeded()
    platform.simulateInput(controlKey("\u{1b}"))
    controlRedraw(window)
    controlRedraw(window)
    #expect(pickerSquare(window) == nil, "Escape closed the panel")
}

/// **1.37** (`LK-D` item 7). The square is a group labelled "Saturation and
/// brightness" over two adjustable sliders, "Saturation" and "Brightness",
/// in percent; the bars are sliders "Hue" in degrees and "Opacity" in
/// percent; an increment on "Saturation" writes s + 0.01. Mutation: omit the
/// hue node's value.
@Test @MainActor func thePanelsSlidersPublishTheirValues() throws {
    let model = PickerModel(Color(.sRGB, red: 0.5, green: 0.25, blue: 0.25))
    let (window, platform) = try pickerWindow { ColorPicker("Tint", selection: model.binding) }
    _ = try pickerOpen(window, platform)
    let tree = try controlTree(window, platform)
    func slider(_ label: String) -> (key: AccessibilityNodeID, value: AccessibilityNode)? {
        tree.nodes.first { $0.value.role == .slider && $0.value.label == label }
    }
    let group = try #require(tree.nodes.first { $0.value.label == "Saturation and brightness" },
                             "no square group: \(tree.nodes.values.map { ($0.role, $0.label ?? "") })")
    let saturation = try #require(slider("Saturation"))
    let brightness = try #require(slider("Brightness"))
    #expect(group.value.children == [saturation.key, brightness.key], "the square's two children")
    #expect(saturation.value.value == "50%" && brightness.value.value == "50%")
    #expect(slider("Hue")?.value.value == "0°", "hue \(slider("Hue")?.value.value ?? "nil")")
    #expect(slider("Opacity")?.value.value == "100%")
    #expect(saturation.value.actions.contains(.increment) && saturation.value.actions.contains(.decrement))
    #expect(platform.simulateAccessibilityRequest(.increment(saturation.key)))
    #expect(near(model.writes.last, (0.5, 0.5 - 0.5 * 0.51, 0.5 - 0.5 * 0.51, 1)), "\(model.writes)")
}
