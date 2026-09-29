import Testing
import Metal
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// Plan task 12, part 1, lane 2 — `Button`'s role, style and pressed look
// (ruling `IX-E`; spec `docs/superpowers/specs/2026-09-29-interaction-design.md`
// §6, tests 2.1–2.3). SwiftUI's answers are arms of
// `docs/probes/swiftui-interaction.swift` (B0–B5) and
// `swiftui-controls-and-selection.swift` (BT0–BT3); every look (the wash, the
// 60 % label) is MetalUI's choice — the probe's capture is blind to it (`PX21`,
// `PX22`). Fixtures reuse `ButtonTests`' `control…` helpers.

// MARK: - Fixtures

@MainActor
func ixSceneBytes<E: Element>(_ make: () -> E) -> [[UInt8]] {
    let frame = Frame(contentSize: Size(width: Pixels(400), height: Pixels(200)), scaleFactor: 1)
    var root = make()
    frame.render(&root)
    let scene = frame.finalizedScene()
    return [scene.rects.withUnsafeBytes { Array($0) }, scene.glyphs.withUnsafeBytes { Array($0) }]
}

func ixHsla(_ c: MUIHsla) -> Hsla { Hsla(h: c.h, s: c.s, l: c.l, a: c.a) }

func ixSame(_ a: Hsla, _ b: Hsla, tolerance: Float = 1e-4) -> Bool {
    abs(a.h - b.h) < tolerance && abs(a.s - b.s) < tolerance && abs(a.l - b.l) < tolerance
        && abs(a.a - b.a) < tolerance
}

func ixBounds(_ r: MUIRect) -> Bounds<Pixels> {
    Bounds(origin: Point(x: Pixels(r.bounds.origin.x), y: Pixels(r.bounds.origin.y)),
           size: Size(width: Pixels(r.bounds.size.width), height: Pixels(r.bounds.size.height)))
}

// MARK: - 2.1 role

/// **2.1** (B4c: a `.cancel` button alone ignores Escape; B4d: a `.destructive`
/// one ignores Return; B5: the click runs its action). A role binds no key and
/// changes nothing drawn: the scene of a role-carrying button is byte-for-byte
/// the role-less one's. M2a (`.cancel` binds Escape) reddens it.
@Test @MainActor func aButtonRoleBindsNoKeyAndChangesNothingDrawn() throws {
    let model = ControlModel()
    let (window, platform) = try controlWindow {
        controlRoot {
            Button("Cancel", role: .cancel) { model.keys.append("cancel") }
            Button("Delete", role: .destructive) { model.keys.append("delete") }
        }
    }
    platform.simulateInput(controlKey("\u{1b}"))
    platform.simulateInput(controlKey("\r"))
    #expect(model.keys == [], "a role binds no key (B4c, B4d): \(model.keys)")

    let delete = try #require(window.lastElementBounds[controlID([0, 1])], "the second button's bounds")
    controlClick(platform, at: controlCentre(delete))
    #expect(model.keys == ["delete"], "a click runs a role-carrying button's action (B5)")

    for role in [ButtonRole.cancel, .destructive, .confirm, .close] {
        let plain = ixSceneBytes { controlRoot { Button("Go") {} } }
        let roled = ixSceneBytes { controlRoot { Button("Go", role: role) {} } }
        #expect(plain == roled, "a role changes nothing drawn (\(role))")
        let labelled = ixSceneBytes { controlRoot { Button(role: role, action: {}) { Text("Go") } } }
        #expect(plain == labelled, "the label form draws the same (\(role))")
    }
}

// MARK: - 2.2 style

/// **2.2** (BT1: a `.plain` and a `.borderless` button are 17×16 over a 17×16
/// `Text("Go")`; BT0: the bordered chrome is `textW + 24` × `max(textH, 24)`).
/// `.plain` and `.borderless` are the label's size and draw no chrome rect;
/// `.bordered` and `.automatic` are today's chrome. M2b (`.plain` keeps the
/// padding) reddens it.
@Test @MainActor func plainAndBorderlessButtonsAreTheirLabelsSize() throws {
    let text = try controlTextSize("Go")
    for style in [ButtonStyle.plain, .borderless] {
        let frame = try controlRender(controlRoot { Button("Go") {}.buttonStyle(style) })
        let button = try controlBounds(frame, controlID([0, 0]))
        #expect(button.size == text, "\(style): the label's size, \(button.size) vs \(text)")
        #expect(frame.finalizedScene().rects.isEmpty, "\(style) draws no chrome rect")
    }
    for style in [ButtonStyle.bordered, .automatic] {
        let frame = try controlRender(controlRoot { Button("Go") {}.buttonStyle(style) })
        let button = try controlBounds(frame, controlID([0, 0]))
        #expect(button.size.width.value == text.width.value + 24, "\(style): textW + 24")
        #expect(button.size.height.value == max(text.height.value, 24), "\(style): max(textH, 24)")
    }
    #expect(ixSceneBytes { controlRoot { Button("Go") {}.buttonStyle(.automatic) } }
                == ixSceneBytes { controlRoot { Button("Go") {} } },
            ".automatic is today's chrome, byte for byte")
    // A caller's fill survives `.plain`, written before or after it.
    for before in [true, false] {
        let button = before ? Button("Go") {}.background(.accent).buttonStyle(.plain)
                            : Button("Go") {}.buttonStyle(.plain).background(.accent)
        let frame = try controlRender(controlRoot { button })
        #expect(frame.finalizedScene().rects.count == 1, "a caller's .background survives .plain (before: \(before))")
    }
}

// MARK: - 2.3 pressed

/// The rects that are the bordered chrome's pressed wash: `.textPrimary` at 12 %
/// over exactly the button's bounds.
@MainActor
private func washes(_ window: Window, over button: Bounds<Pixels>) -> Int {
    let ink = window.theme[.textPrimary]
    let wash = Hsla(h: ink.h, s: ink.s, l: ink.l, a: ink.a * 0.12)
    return window.lastScene.rects.filter { ixSame(ixHsla($0.background), wash) && ixBounds($0) == button }.count
}

/// **2.3** (B0: pressed from the press to the release; B1: false outside, true
/// again back inside; B2: false once released outside). The bordered chrome
/// paints its wash exactly while the pointer is pressed **and** over the
/// button — `PaintPass.isActive(id) && isHovered(id)` (`IX-E` item 3) — and a
/// `.plain` button draws its label at 60 % instead. M2c (`isActive` alone)
/// reddens the "out" arms.
@Test @MainActor func aButtonPaintsPressedOnlyWhilePressedAndOverIt() throws {
    let (window, platform) = try controlWindow { controlRoot { Button("Go") {} } }
    window.theme = .light
    controlRedraw(window)
    let button = try #require(window.lastElementBounds[controlID([0, 0])], "the button's bounds")
    let inside = controlCentre(button)
    let outside = Point(x: Pixels(button.origin.x.value + button.size.width.value + 60), y: inside.y)
    func step(_ event: InputEvent) {
        platform.simulateInput(event)
        window.drawFrameIfNeeded()
    }
    #expect(washes(window, over: button) == 0, "at rest: no wash")
    step(.mouseMoved(MouseEvent(position: inside)))
    #expect(washes(window, over: button) == 0, "hovered but not pressed: no wash")
    step(.mouseDown(MouseEvent(position: inside)))
    #expect(washes(window, over: button) == 1, "pressed and over it: the wash (B0)")
    step(.mouseDragged(MouseEvent(position: outside)))
    #expect(washes(window, over: button) == 0, "pressed, dragged out: no wash (B1)")
    step(.mouseDragged(MouseEvent(position: inside)))
    #expect(washes(window, over: button) == 1, "dragged back in: the wash again (B1)")
    step(.mouseUp(MouseEvent(position: inside)))
    #expect(washes(window, over: button) == 0, "released: no wash (B0)")

    // `.plain`: the label's glyphs at 60 % while pressed and over it.
    let (plainWindow, plainPlatform) = try controlWindow { controlRoot { Button("Go") {}.buttonStyle(.plain) } }
    plainWindow.theme = .light
    controlRedraw(plainWindow)
    let plain = try #require(plainWindow.lastElementBounds[controlID([0, 0])], "the plain button's bounds")
    let rest = try #require(plainWindow.lastScene.glyphs.first, "the label draws glyphs").color.a
    func glyphAlpha(after event: InputEvent) throws -> Float {
        plainPlatform.simulateInput(event)
        plainWindow.drawFrameIfNeeded()
        return try #require(plainWindow.lastScene.glyphs.first).color.a
    }
    let plainOutside = Point(x: Pixels(plain.origin.x.value + plain.size.width.value + 60),
                             y: controlCentre(plain).y)
    #expect(abs(try glyphAlpha(after: .mouseDown(MouseEvent(position: controlCentre(plain)))) - rest * 0.6) < 1e-4,
            "pressed: the label at 60 %")
    #expect(abs(try glyphAlpha(after: .mouseDragged(MouseEvent(position: plainOutside))) - rest) < 1e-4,
            "dragged out: the label at full opacity")
    #expect(abs(try glyphAlpha(after: .mouseUp(MouseEvent(position: plainOutside))) - rest) < 1e-4,
            "released: full opacity")
}
