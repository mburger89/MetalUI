import Testing
import Metal
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// Round 3, item R3-1 (rulings `BY-A`…, `docs/superpowers/2026-10-31-styles-decisions.md`): `ButtonStyle` and
// `PrimitiveButtonStyle` as open protocols, applied through the environment, and the two new built-ins
// `.borderedProminent` and `.link`. SwiftUI's shape is the authority; every look is MetalUI's (the probe capture is
// blind to it, `PX21`). Helpers are `ButtonTests.swift`'s `control…` and `ButtonSemanticsTests.swift`'s `ix…`.

// MARK: - Fixtures

private let styleBlue = Color(srgb: 0, 0, 1, 1)
private let styleRed = Color(srgb: 1, 0, 0, 1)

/// A custom `ButtonStyle`: the label padded 10 a side over a fill that is red while pressed, blue otherwise.
private struct PaddedStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some ElementGroup {
        configuration.label.padding(10).background(configuration.isPressed ? styleRed : styleBlue)
    }
}

/// A custom style that records the configuration it was handed.
@MainActor
private final class StyleSpy {
    var roles: [ButtonRole?] = []
    var pressed: [Bool] = []
}

private struct SpyStyle: ButtonStyle {
    let spy: StyleSpy
    func makeBody(configuration: Configuration) -> some ElementGroup {
        spy.roles.append(configuration.role)
        spy.pressed.append(configuration.isPressed)
        return configuration.label
    }
}

/// A `PrimitiveButtonStyle` that fires the action itself, on a click of its label: the SwiftUI shape.
private struct ClickTriggerStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some ElementGroup {
        configuration.label.onClick { configuration.trigger() }
    }
}

/// A `PrimitiveButtonStyle` that fires the action twice per click.
private struct DoubleTriggerStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some ElementGroup {
        configuration.label.onClick { configuration.trigger(); configuration.trigger() }
    }
}

/// A `PrimitiveButtonStyle` that never triggers.
private struct NeverTriggerStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some ElementGroup { configuration.label }
}

/// A style that reads the environment through a property wrapper on the style struct itself.
private struct EnvironmentStyle: ButtonStyle {
    @Environment(\.controlSize) private var size
    func makeBody(configuration: Configuration) -> some ElementGroup {
        configuration.label.padding(size == .large ? 30 : 10)
    }
}

@MainActor
private func rectColours(_ window: Window) -> [Hsla] {
    window.lastScene.rects.map { ixHsla($0.background) }
}

private func hsla(_ color: Color) -> Hsla { color.resolved(theme: .light, scheme: .light) }

// MARK: - 1 a custom ButtonStyle

/// **1.** A custom style replaces the chrome: the button is the body's size (the label padded 10 a side) and draws
/// the body's one fill, not the bordered chrome's fill and border. Mutation `BY-M1` (the custom path falls back to
/// the bordered chrome) reddens it.
@Test @MainActor func aCustomButtonStyleReplacesTheChrome() throws {
    let text = try controlTextSize("Go")
    let frame = try controlRender(controlRoot { Button("Go") {}.buttonStyle(PaddedStyle()) })
    let button = try controlBounds(frame, controlID([0, 0]))
    #expect(button.size.width.value == text.width.value + 20, "the label padded 10 a side: \(button.size)")
    #expect(button.size.height.value == text.height.value + 20, "and 10 top and bottom: \(button.size)")
    let rects = frame.finalizedScene().rects
    #expect(rects.count == 1, "the body's one fill, no border rect: \(rects.count)")
    #expect(ixSame(ixHsla(try #require(rects.first).background), hsla(styleBlue)), "the body's blue")
}

/// **2.** `configuration.isPressed` is true exactly while the pointer is pressed **and** over the button
/// (SwiftUI's rule, probe B0–B2), so the body rebuilds red on the press, blue once dragged out, red again back in
/// and blue after the release. Mutation `BY-M2` (`isPressed` is `isActive` alone) reddens the "out" arm.
@Test @MainActor func isPressedIsTrueWhilePressedAndOverTheButton() throws {
    let (window, platform) = try controlWindow { controlRoot { Button("Go") {}.buttonStyle(PaddedStyle()) } }
    let button = try #require(window.lastElementBounds[controlID([0, 0])], "the button's bounds")
    let inside = controlCentre(button)
    let outside = Point(x: Pixels(button.origin.x.value + button.size.width.value + 60), y: inside.y)
    func step(_ event: InputEvent) {
        platform.simulateInput(event)
        window.drawFrameIfNeeded()
    }
    func fill() throws -> Hsla { try #require(rectColours(window).first, "the body's fill") }
    #expect(ixSame(try fill(), hsla(styleBlue)), "at rest: not pressed")
    step(.mouseMoved(MouseEvent(position: inside)))
    #expect(ixSame(try fill(), hsla(styleBlue)), "hovered, not pressed")
    step(.mouseDown(MouseEvent(position: inside)))
    #expect(ixSame(try fill(), hsla(styleRed)), "pressed and over it")
    #expect(!window.needsRedraw, "the first pressed frame is the corrected one: no further frame is owed (BY-D)")
    step(.mouseDragged(MouseEvent(position: outside)))
    #expect(ixSame(try fill(), hsla(styleBlue)), "pressed, dragged out: not pressed (B1)")
    step(.mouseDragged(MouseEvent(position: inside)))
    #expect(ixSame(try fill(), hsla(styleRed)), "dragged back in: pressed again (B1)")
    step(.mouseUp(MouseEvent(position: inside)))
    #expect(ixSame(try fill(), hsla(styleBlue)), "released: not pressed (B0)")
}

/// **3.** The configuration carries the button's role, and a bare frame (no pointer) is not pressed.
@Test @MainActor func theConfigurationCarriesTheRoleAndIsNotPressedAtRest() throws {
    let spy = StyleSpy()
    _ = try controlRender(controlRoot {
        Button("Delete", role: .destructive) {}.buttonStyle(SpyStyle(spy: spy))
        Button("Plain") {}.buttonStyle(SpyStyle(spy: spy))
    })
    #expect(spy.roles == [.destructive, nil], "the roles in tree order: \(spy.roles)")
    #expect(spy.pressed == [false, false], "nothing is pressed")
}

/// **4.** A custom style keeps the button a button: a click, a focused Space, an accessibility press
/// and a keyboard shortcut each run the action once; a disabled button runs none. Mutation `BY-M3` (the custom
/// path registers no handlers) reddens it.
@Test @MainActor func aCustomStyledButtonStaysClickableFocusableAndAccessible() throws {
    let model = ControlModel()
    let (window, platform) = try controlWindow {
        controlRoot {
            Button("Go") { model.count += 1 }.buttonStyle(PaddedStyle()).keyboardShortcut("g")
            Button("Off") { model.count += 100 }.buttonStyle(PaddedStyle()).disabled(true)
        }
    }
    let id = controlID([0, 0])
    controlClick(platform, at: controlCentre(try controlBounds(window.lastFrameBounds(), id)))
    #expect(model.count == 1, "a click runs the action once")
    window.focus(id)
    window.drawFrameIfNeeded()
    try #require(window.focusedElement == id, "a custom-styled button takes focus")
    platform.simulateInput(controlKey(" "))
    #expect(model.count == 2, "Space runs it (Return is not a button key on macOS, `ControlKeys.activatesButton`)")
    platform.simulateInput(controlKey("g", .command))
    #expect(model.count == 3, "the shortcut runs it")
    let tree = try controlTree(window, platform)
    let node = try #require(tree.nodes.first { $0.value.role == .button && $0.value.label == "Go" },
                            "a published button labelled Go")
    #expect(platform.simulateAccessibilityRequest(.press(node.key)))
    #expect(model.count == 4, "an accessibility press runs it")
    let off = try #require(window.lastElementBounds[controlID([0, 1])], "the disabled button's bounds")
    controlClick(platform, at: controlCentre(off))
    #expect(model.count == 4, "a disabled button runs nothing")
}

// MARK: - 2 inheritance through the environment

/// **5.** `.buttonStyle(_:)` on any content reaches every button below through the environment; the nearest writer
/// wins; a button outside the scope keeps the automatic style. Mutation `BY-M4` (the environment write reads the
/// outermost style) reddens the nearest-wins arm.
@Test @MainActor func aButtonStyleIsInheritedThroughTheEnvironmentNearestWriterWinning() throws {
    let text = try controlTextSize("Go")
    let frame = try controlRender(controlRoot {
        Column {
            Button("Go") {}
            Button("Go") {}.buttonStyle(.plain)
        }.buttonStyle(PaddedStyle())
        Button("Go") {}
    })
    let inherited = try controlBounds(frame, controlID([0, 0, 0]))
    let overridden = try controlBounds(frame, controlID([0, 0, 1]))
    let outside = try controlBounds(frame, controlID([0, 1]))
    #expect(inherited.size.width.value == text.width.value + 20, "a button below inherits the custom style")
    #expect(overridden.size == text, "the nearer .plain wins")
    #expect(outside.size.width.value == text.width.value + 24, "outside the scope: the bordered chrome")
}

/// **6.** A style written on a wrapper reaches the button inside it, and a built-in written outside a custom
/// button's own call loses to it (the button's own `.buttonStyle` is the nearest).
@Test @MainActor func aStyleWrittenOnAnOuterGroupReachesAWrappedButton() throws {
    let text = try controlTextSize("Go")
    let frame = try controlRender(controlRoot {
        Column { Button("Go") {}.buttonStyle(PaddedStyle()) }.buttonStyle(.plain)
    })
    let button = try controlBounds(frame, controlID([0, 0, 0]))
    #expect(button.size.width.value == text.width.value + 20, "the button's own style is nearer than the group's")
    // Two environment writers: the inner group's `.plain` is nearer than the outer group's custom style.
    let nested = try controlRender(controlRoot {
        Column { Column { Button("Go") {} }.buttonStyle(.plain) }.buttonStyle(PaddedStyle())
    })
    #expect(try controlBounds(nested, controlID([0, 0, 0, 0])).size == text, "the inner environment writer wins")
}

// MARK: - 3 PrimitiveButtonStyle

/// **7.** A `PrimitiveButtonStyle` owns the interaction: its `configuration.trigger()` runs the action, once per
/// call, and a style that never calls it runs nothing on a click. Mutation `BY-M5` (`trigger` is a no-op) reddens
/// the first two arms; the third is the separating arm.
@Test @MainActor func aPrimitiveStyleRunsTheActionOnlyThroughTrigger() throws {
    func clicks<S: PrimitiveButtonStyle>(_ style: S) throws -> Int {
        let model = ControlModel()
        let (window, platform) = try controlWindow {
            controlRoot { Button("Go") { model.count += 1 }.buttonStyle(style) }
        }
        let button = try #require(window.lastElementBounds[controlID([0, 0])], "the button's bounds")
        controlClick(platform, at: controlCentre(button))
        return model.count
    }
    #expect(try clicks(ClickTriggerStyle()) == 1, "trigger() runs the action once")
    #expect(try clicks(DoubleTriggerStyle()) == 2, "each trigger() runs it")
    #expect(try clicks(NeverTriggerStyle()) == 0, "a style that never triggers runs nothing on a click")
}

/// **8.** Keyboard activation still reaches a primitive-styled button: a focused Space runs the action through
/// the button's own key table (`BY-C`), and the button is focusable.
@Test @MainActor func aPrimitiveStyledButtonIsFocusableAndActivatesFromTheKeyboard() throws {
    let model = ControlModel()
    let (window, platform) = try controlWindow {
        controlRoot { Button("Go") { model.count += 1 }.buttonStyle(NeverTriggerStyle()) }
    }
    let id = controlID([0, 0])
    window.focus(id)
    window.drawFrameIfNeeded()
    try #require(window.focusedElement == id, "a primitive-styled button takes focus")
    platform.simulateInput(controlKey(" "))
    #expect(model.count == 1, "Space runs the action")
}

// MARK: - 4 the new built-ins

/// **9.** `.borderedProminent`: the bordered metrics, an accent fill with no border, and a white label. The
/// separating arm is the bordered style's `.surfaceSecondary` fill and the theme's text colour.
@Test @MainActor func borderedProminentIsAnAccentFillWithAWhiteLabel() throws {
    let text = try controlTextSize("Go")
    let frame = try controlRender(controlRoot { Button("Go") {}.buttonStyle(.borderedProminent) })
    let button = try controlBounds(frame, controlID([0, 0]))
    #expect(button.size.width.value == text.width.value + 24, "the bordered metrics: textW + 24")
    #expect(button.size.height.value == max(text.height.value, 24), "and max(textH, 24)")
    let scene = frame.finalizedScene()
    let rect = try #require(scene.rects.first, "a chrome fill")
    #expect(ixSame(ixHsla(rect.background), Theme.light[.accent]), "the accent fill")
    #expect(rect.borderWidths.left == 0 && rect.borderWidths.top == 0, "no border")
    let glyph = try #require(scene.glyphs.first, "the label's glyphs")
    #expect(ixSame(ixHsla(glyph.color), hsla(.white)), "a white label")
    let plain = try controlRender(controlRoot { Button("Go") {}.buttonStyle(.bordered) }).finalizedScene()
    #expect(!ixSame(ixHsla(try #require(plain.rects.first).background), ixHsla(rect.background)),
            "the separating arm: bordered's fill is not the accent")
    #expect(!ixSame(ixHsla(try #require(plain.glyphs.first).color), hsla(.white)), "and its label is not white")
}

/// **10.** `.link`: the label alone at its own size (no chrome rect), in the accent colour; pressed it dims to
/// 60 % like `.plain`. The separating arm is `.plain`'s theme-coloured label.
@Test @MainActor func linkIsAnAccentColoredLabelWithNoChrome() throws {
    let text = try controlTextSize("Go")
    let frame = try controlRender(controlRoot { Button("Go") {}.buttonStyle(.link) })
    let button = try controlBounds(frame, controlID([0, 0]))
    #expect(button.size == text, "the label's size, as .plain")
    let scene = frame.finalizedScene()
    #expect(scene.rects.isEmpty, "no chrome rect")
    let glyph = try #require(scene.glyphs.first, "the label's glyphs")
    #expect(ixSame(ixHsla(glyph.color), Theme.light[.accent]), "the accent colour")
    let plain = try controlRender(controlRoot { Button("Go") {}.buttonStyle(.plain) }).finalizedScene()
    #expect(!ixSame(ixHsla(try #require(plain.glyphs.first).color), ixHsla(glyph.color)),
            "the separating arm: .plain's label is not the accent")
}

/// **11.** The built-ins are values of public types, usable as SwiftUI spells them, and the glass styles keep
/// working through the new protocol (their chrome is the glass the old struct drew).
@Test @MainActor func theBuiltInStylesAreValuesOfTheirOwnTypes() throws {
    let styles: [any PrimitiveButtonStyle] = [.automatic, .bordered, .borderless, .plain, .borderedProminent, .link,
                                              .glass, .glassProminent]
    #expect(styles.count == 8)
    #expect(PlainButtonStyle() == PlainButtonStyle() && AnyHashable(PlainButtonStyle()) != AnyHashable(BorderedButtonStyle()))
    let bytes = styles.map { style in ixSceneBytes { controlRoot { Button("Go") {}.buttonStyle(style) } } }
    #expect(bytes[0] == bytes[1], ".automatic is .bordered, byte for byte")
    #expect(bytes[2] == bytes[3], ".borderless and .plain draw alike (BT1)")
    #expect(bytes[0] != bytes[3] && bytes[0] != bytes[4] && bytes[3] != bytes[5] && bytes[4] != bytes[5],
            "the separating arms: bordered, prominent, plain and link differ")
}

/// **12.** A style's `@Environment` is bound (`BY-K`): a `.controlSize(.large)` scope reaches the property on the style
/// struct, so the body pads 30, and a button outside the scope reads the default and pads 10. Mutation `BY-M8` (the
/// custom path does not bind the style) reddens the first arm: an unbound `@Environment` reads the defaults.
@Test @MainActor func aStyleStructsEnvironmentPropertiesAreBound() throws {
    let text = try controlTextSize("Go")
    let frame = try controlRender(controlRoot {
        Column { Button("Go") {} }.controlSize(.large)
        Button("Go") {}
    }.buttonStyle(EnvironmentStyle()))
    let inside = try controlBounds(frame, controlID([0, 0, 0]))
    let outside = try controlBounds(frame, controlID([0, 1]))
    #expect(inside.size.width.value == text.width.value + 60, "the scope's .large reaches the style: \(inside.size)")
    #expect(outside.size.width.value == text.width.value + 20, "outside the scope: the default")
}
