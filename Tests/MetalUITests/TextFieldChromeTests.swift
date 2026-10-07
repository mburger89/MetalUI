import Testing
import Metal
import MetalUICore
import MetalUILayout
import MetalUIPlatform
import MetalUIScene
@testable import MetalUI

// Spec `docs/superpowers/specs/2026-10-07-port-gaps-medium-design.md` §4.1,
// tests 1.1–1.9 (rulings `MD-B`…`MD-F` in
// `docs/superpowers/2026-10-07-port-gaps-medium-decisions.md`): SwiftUI's
// bordered field as `TextField`'s default, `.textFieldStyle(_:)` on the field
// and on a container, and `TextEditor`'s opaque fill. Every SwiftUI number is
// the probe's (`docs/probes/swiftui-field-chrome.swift`, arms `SZ`, `CS`,
// `NS`, `ENV`, `PX`, `TX`, `ED`).

private func near(_ a: Float, _ b: Float, _ tolerance: Float = 0.01) -> Bool { abs(a - b) < tolerance }
private func near(_ a: Double, _ b: Double, _ tolerance: Double = 0.01) -> Bool { abs(a - b) < tolerance }

/// The size of `field` laid out at its ideal inside a `VStack`
/// (`VStack { field.fixedSize() }`: the stack `[0]`, the fixedSize layer
/// `[0, 0]`, the field `[0, 0, 0]`), with the report required empty.
@MainActor
private func idealSize(_ field: TextField) throws -> Size<Pixels> {
    let report = LayoutDifferential.report(width: 400, height: 300) {
        VStack { field.fixedSize() }
    }
    try #require(report.unlowerable.isEmpty, "\(report.unlowerable)")
    return try #require(report.bounds[controlID([0, 0, 0])], "the field recorded no bounds").size
}

/// The field's frame inside `VStack { … }.textFieldStyle(container)`: the scope
/// is transparent (`EV-B`), so the field is `[0, 0, 0]` under its fixedSize.
@MainActor
private func idealSize(_ field: TextField, inContainerStyled container: TextFieldStyle) throws -> Size<Pixels> {
    let report = LayoutDifferential.report(width: 400, height: 300) {
        VStack { field.fixedSize() }.textFieldStyle(container)
    }
    try #require(report.unlowerable.isEmpty, "\(report.unlowerable)")
    return try #require(report.bounds[controlID([0, 0, 0])], "the field recorded no bounds").size
}

@MainActor
private func field(_ text: String = "") -> TextField {
    TextField("Name", text: .constant(text))
}

// MARK: - 1.1 the default and its size

/// **1.1** (`MD-B`, `MD-C`, `MD-D` item 1; probe `SZ1`–`SZ3`: no style,
/// `.automatic` and `.roundedBorder` answer 47.50×24 for "Name"). A default
/// field's ideal is MetalUI's plain ideal + 12 wide and one line + 8 tall —
/// 36.25 + 12 = 48.25 by 16 + 8 = 24 for the placeholder "Name" at 13 pt (the
/// plain field's 36.25×16 is today's, divergence 131); `.automatic`,
/// `.roundedBorder` and `.squareBorder` equal it; `.plain` is the old field.
///
/// Red before: does not compile. M1.1 (the inset table → 0) reddens the
/// bordered arms.
@Test @MainActor func theDefaultFieldIsTheBorderedOneAndSizesAsSwiftUI() throws {
    let plain = try idealSize(field().textFieldStyle(.plain))
    #expect(near(plain.width.value, 36.25) && plain.height.value == 16,
            "the plain field is today's: \"Name\" + the 1-point caret, one line: \(plain)")
    let bordered = try idealSize(field())
    #expect(near(bordered.width.value, 48.25) && bordered.height.value == 24,
            "M1.1 — the default is the bordered field: plain + 12 by line + 8: \(bordered)")
    #expect(near(bordered.width.value, plain.width.value + 12) && bordered.height.value == plain.height.value + 8)
    for style in [TextFieldStyle.automatic, .roundedBorder, .squareBorder] {
        #expect(try idealSize(field().textFieldStyle(style)) == bordered, "\(style) equals the default")
    }
}

// MARK: - 1.2 a container's style

/// **1.2** (`MD-B` item 2; probe `ENV1`–`ENV3`). A container's
/// `.textFieldStyle(.plain)` reaches its field; a field's own style wins over
/// the container's either way round (innermost wins).
///
/// Red before: does not compile. M1.2 (the field ignores the environment's
/// style) reddens the first arm.
@Test @MainActor func aContainerTextFieldStyleReachesItsFieldsAndTheInnermostWins() throws {
    let plain = try idealSize(field().textFieldStyle(.plain))
    let bordered = try idealSize(field())
    try #require(plain != bordered, "set up — the two styles must size differently")
    #expect(try idealSize(field(), inContainerStyled: .plain) == plain,
            "M1.2 — ENV1: the container's .plain reaches the field")
    #expect(try idealSize(field().textFieldStyle(.roundedBorder), inContainerStyled: .plain) == bordered,
            "ENV2: the field's own .roundedBorder wins inside a plain container")
    #expect(try idealSize(field().textFieldStyle(.plain), inContainerStyled: .roundedBorder) == plain,
            "ENV3: the field's own .plain wins inside a bordered container")
}

// MARK: - 1.3 the chrome's look

/// The rect drawn exactly at `bounds` with a 1-point border, if any.
private func chromeRects(_ scene: Scene, at bounds: Bounds<Pixels>) -> [MUIRect] {
    scene.rects.filter { ixBounds($0) == bounds && $0.borderWidths.top == 1 && $0.borderWidths.left == 1 }
}

/// A window holding one field in a 200-wide `Box` (`[0]`), the field `[0, 0]`.
@MainActor
private func fieldWindow(appearance: Appearance = .light, _ make: @escaping @MainActor () -> TextField)
    throws -> (Window, FakePlatformWindow) {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let (window, platform) = try makeFakeWindow(device: device, size: 200, appearance: appearance) {
        Box { make() }
    }
    window.recordsElementBounds = true
    window.drawFrameIfNeeded()
    return (window, platform)
}

@MainActor
private func fieldTarget(_ window: Window) throws -> (bounds: Bounds<Pixels>, target: TextInputTarget) {
    let hitbox = try #require(window.lastHitboxes.first { $0.handlers.textInput != nil }, "the field's hitbox")
    return (hitbox.bounds, try #require(hitbox.handlers.textInput))
}

/// **1.3** (`MD-E` item 1; probe `PX`: the three bordered styles draw
/// identically, radius ~6). The default field paints one rect at its bounds:
/// a `.surface` fill, a 1-point `.separator` border, corner radius 6 — in the
/// light and the dark theme; a `.plain` field paints no such rect.
///
/// Red before: does not compile. M1.3 (radius 6 → 5) reddens the radius arm.
@Test @MainActor func theBorderedChromePaintsTheThemesFillBorderAndRadius() throws {
    var surfaces: [Hsla] = []
    for appearance in [Appearance.light, .dark] {
        let (window, _) = try fieldWindow(appearance: appearance) { field("Hello") }
        let (bounds, _) = try fieldTarget(window)
        let chrome = chromeRects(window.lastScene, at: bounds)
        #expect(chrome.count == 1, "\(appearance): one chrome rect at the field's bounds (\(chrome.count))")
        if let rect = chrome.first {
            #expect(ixSame(ixHsla(rect.background), window.theme[.surface]), "\(appearance): the fill is .surface")
            #expect(ixSame(ixHsla(rect.borderColor), window.theme[.separator]),
                    "\(appearance): the border is .separator")
            #expect(rect.cornerRadii.topLeft == 6 && rect.cornerRadii.bottomRight == 6,
                    "M1.3 — \(appearance): radius 6: \(rect.cornerRadii)")
        }
        surfaces.append(window.theme[.surface])
        let (plainWindow, _) = try fieldWindow(appearance: appearance) { field("Hello").textFieldStyle(.plain) }
        let (plainBounds, _) = try fieldTarget(plainWindow)
        #expect(chromeRects(plainWindow.lastScene, at: plainBounds).isEmpty, "\(appearance): .plain paints no chrome")
        #expect(!plainWindow.lastScene.rects.contains { ixBounds($0) == plainBounds },
                "\(appearance): .plain paints nothing at its bounds")
    }
    #expect(!ixSame(surfaces[0], surfaces[1]), "set up — the light and dark surfaces differ")
}

// MARK: - 1.4 the focus ring

/// The 2-point rings drawn at `bounds` in `colour`.
private func rings(_ scene: Scene, at bounds: Bounds<Pixels>, _ colour: Hsla) -> [MUIRect] {
    scene.rects.filter {
        ixBounds($0) == bounds && $0.borderWidths.top == 2 && $0.borderWidths.left == 2
            && ixSame(ixHsla($0.borderColor), colour)
    }
}

/// **1.4** (`MD-E` item 2; `IX-H`; probe `NS plain`: `.plain` has no focus
/// ring). A focused bordered field draws the control ring — 2 points in the
/// key accent, radius 6, at its bounds — and none unfocused; in a non-key
/// window the ring is `.separator`; a focused `.plain` field draws none.
///
/// Red before: does not compile. M1.4 (the ring drawn for `.plain`) reddens
/// the last arm.
@Test @MainActor func aFocusedBorderedFieldDrawsTheControlRingAndAPlainOneDoesNot() throws {
    let (window, platform) = try fieldWindow { field("Hello") }
    let (bounds, _) = try fieldTarget(window)
    let accent = window.theme[.accent]
    #expect(rings(window.lastScene, at: bounds, accent).isEmpty, "unfocused: no ring")
    controlClick(platform, at: controlCentre(bounds))
    controlRedraw(window)
    try #require(window.focusedElement == controlID([0, 0]), "a click focuses a field")
    let ring = rings(window.lastScene, at: bounds, accent)
    #expect(ring.count == 1, "focused: one accent ring (\(ring.count))")
    if let r = ring.first { #expect(r.cornerRadii.topLeft == 6, "the ring follows the chrome's radius 6") }
    platform.simulateControlActiveStateChange(to: .inactive)
    controlRedraw(window)
    #expect(rings(window.lastScene, at: bounds, accent).isEmpty, "inactive window: no accent ring")
    #expect(rings(window.lastScene, at: bounds, window.theme[.separator]).count == 1,
            "inactive window: one .separator ring")

    let (plainWindow, plainPlatform) = try fieldWindow { field("Hello").textFieldStyle(.plain) }
    let (plainBounds, _) = try fieldTarget(plainWindow)
    controlClick(plainPlatform, at: controlCentre(plainBounds))
    controlRedraw(plainWindow)
    try #require(plainWindow.focusedElement == controlID([0, 0]), "a click focuses a plain field")
    #expect(!plainWindow.lastScene.rects.contains { $0.borderWidths.top == 2 },
            "M1.4 — a focused .plain field draws no ring")
}

// MARK: - 1.5 disabled

/// **1.5** (`MD-E` item 3; probe `PX disabled` = `PX default`; `TX`: the text
/// dims to about a third). Under `.disabled(true)` the chrome rect is the
/// enabled one, field for field; the glyphs' alpha is the enabled alpha × 0.33,
/// for the text and for the placeholder (itself × 0.45).
///
/// Red before: does not compile. M1.5 (the factor → 1) reddens both glyph arms.
@Test @MainActor func aDisabledFieldKeepsItsChromeAndDimsItsText() throws {
    for text in ["Hello", ""] {
        let (enabled, _) = try fieldWindow { field(text) }
        let device = try #require(MTLCreateSystemDefaultDevice())
        let (gated, _) = try makeFakeWindow(device: device, size: 200) { Box { field(text).disabled(true) } }
        gated.drawFrameIfNeeded()
        let enabledBounds = try #require(enabled.lastScene.rects.first { $0.borderWidths.top == 1 }, "enabled chrome")
        let gatedChrome = try #require(gated.lastScene.rects.first { $0.borderWidths.top == 1 }, "disabled chrome")
        #expect(ixBounds(gatedChrome) == ixBounds(enabledBounds)
                    && ixSame(ixHsla(gatedChrome.background), ixHsla(enabledBounds.background))
                    && ixSame(ixHsla(gatedChrome.borderColor), ixHsla(enabledBounds.borderColor))
                    && gatedChrome.cornerRadii.topLeft == enabledBounds.cornerRadii.topLeft,
                "\(text.isEmpty ? "placeholder" : "text"): the chrome does not change when disabled")
        let on = try #require(enabled.lastScene.glyphs.first, "enabled glyphs").color.a
        let off = gated.lastScene.glyphs
        try #require(!off.isEmpty, "disabled glyphs")
        #expect(off.allSatisfy { near($0.color.a, on * 0.33, 1e-5) },
                "M1.5 — \(text.isEmpty ? "placeholder" : "text"): alpha × 0.33 (\(on) → \(off.map(\.color.a)))")
    }
}

// MARK: - 1.6 the text sits inside the chrome

/// **1.6** (`MD-D` item 3; `TI-E`). A focused default field holding "Hello",
/// caret at the end: the `TextInputTarget`'s `originX` is the bounds' x + 6
/// (scroll 0); the caret rect's x is `originX + caretOffsets.last`; its y is
/// the bounds' y + 4 + (content height − line) / 2. A `.plain` field: + 0.
///
/// Red before: does not compile. M1.6 (`geometry` handed the outer bounds)
/// reddens the bordered arm.
@Test @MainActor func theTextAndCaretSitInsideTheChrome() throws {
    for (style, h, v) in [(TextFieldStyle.automatic, Float(6), Float(4)), (.plain, 0, 0)] {
        let (window, platform) = try fieldWindow { field("Hello").textFieldStyle(style) }
        let (bounds, _) = try fieldTarget(window)
        controlClick(platform, at: controlCentre(bounds))   // past the text's end: the caret after "Hello"
        controlRedraw(window)
        let (_, target) = try fieldTarget(window)
        let last = try #require(target.caretOffsets.last)
        #expect(near(Float(target.originX), bounds.origin.x.value + h),
                "M1.6 — \(style): the text starts \(h) inside the bounds: \(target.originX) vs \(bounds)")
        #expect(near(target.caretRect.origin.x.value, Float(target.originX + last)),
                "\(style): the caret at the end of \"Hello\": \(target.caretRect)")
        let line = target.caretRect.size.height.value
        let content = bounds.size.height.value - 2 * v
        #expect(near(target.caretRect.origin.y.value, bounds.origin.y.value + v + max(0, content - line) / 2),
                "\(style): the line centred in the content rect: \(target.caretRect) in \(bounds)")
    }
}

// MARK: - 1.7 control size

/// **1.7** (`MD-D` items 1 and 4; probe `CS1` small: 3.5 vertically, `CS3`
/// mini, `CS2` large = regular). The bordered height is the plain height (one
/// line in the control size's default font, `TE-F`) + 7 at `.small`, + 8 at
/// `.mini` and `.large`.
///
/// Red before: does not compile. M1.7 (small's inset 3.5 → 4) reddens the
/// small arm.
@Test @MainActor func theChromeFollowsControlSize() throws {
    for (size, added) in [(ControlSize.small, Float(7)), (.mini, 8), (.large, 8), (.regular, 8)] {
        func height(_ style: TextFieldStyle) throws -> Float {
            let report = LayoutDifferential.report(width: 400, height: 300) {
                VStack { field().textFieldStyle(style).fixedSize() }.controlSize(size)
            }
            try #require(report.unlowerable.isEmpty, "\(report.unlowerable)")
            return try #require(report.bounds[controlID([0, 0, 0])]).size.height.value
        }
        let plain = try height(.plain), bordered = try height(.automatic)
        #expect(near(bordered, plain + added, 0.51),
                "M1.7 — \(size): bordered \(bordered) = plain \(plain) + \(added)")
    }
}

// MARK: - 1.8 still greedy

/// One child measured at an infinite width, recorded.
private final class Recorded: @unchecked Sendable { var atInfinity: SizeD? }

private struct AskInfinite: ProposalLayout {
    let recorded: Recorded
    func sizeThatFits(proposal: ProposedSize, subviews: MeasurementSubviews) -> LayoutMeasurement {
        recorded.atInfinity = subviews[0].sizeThatFits(ProposedSize(width: .infinity, height: nil)).size
        return subviews[0].sizeThatFits(proposal)
    }
    func placeSubviews(in bounds: LayoutRect, proposal: ProposedSize, subviews: PlacementSubviews) {
        subviews[0].place(at: Point(x: bounds.x, y: bounds.y), proposal: proposal)
    }
}

/// **1.8** (`MD-D` item 1; `PE-D` unchanged; probe `SZ` `inf → inf×24`). In
/// an `HStack` at 200 a bordered field is 200 × 24 — the chrome is inside the
/// offered width; at an infinite width it answers infinity × 24.
///
/// Red before: does not compile. M1.8 (the chrome adds 12 to an offered width)
/// reddens the 200 arm.
@Test @MainActor func aBorderedFieldIsStillGreedy() throws {
    let report = LayoutDifferential.report(width: 200, height: 100) {
        HStack { field() }
    }
    try #require(report.unlowerable.isEmpty, "\(report.unlowerable)")
    let bounds = try #require(report.bounds[controlID([0, 0])], "the field")
    #expect(bounds.size.width.value == 200 && bounds.size.height.value == 24,
            "M1.8 — the offered width whole, 24 tall: \(bounds)")

    let recorded = Recorded()
    let frame = LayoutDifferential.render(width: 400, height: 300) {
        ProposalLayoutContainer(AskInfinite(recorded: recorded)) { LegacyContent(field()) }
    }
    try #require(frame.unlowerableFields.isEmpty, "\(frame.unlowerableFields)")
    let infinite = try #require(recorded.atInfinity)
    #expect(infinite.width == .infinity && infinite.height == 24, "∞ wide → ∞ × 24: \(infinite)")
}

// MARK: - 1.9 TextEditor

/// **1.9** (`MD-F`; probe `ED`: an opaque text background, square, no border;
/// `ED2`: `.plain` none). A default `TextEditor` paints one `.surface` rect at
/// its bounds, radius 0, no border; `.textEditorStyle(.plain)` paints none; the
/// glyph origins are identical in both (no placement change, `MD-F` item 3).
///
/// Red before: does not compile. M1.9 (the fill skipped) reddens the first arm.
@Test @MainActor func theTextEditorDrawsAnOpaqueFillAndPlainDrawsNone() throws {
    func editorWindow(_ make: @escaping @MainActor (TextEditor) -> TextEditor) throws -> Window {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let (window, _) = try makeFakeWindow(device: device, size: 200) {
            Box { make(TextEditor(text: .constant("Hello\nworld"))) }
        }
        window.drawFrameIfNeeded()
        return window
    }
    let automatic = try editorWindow { $0 }
    let bounds = try #require(automatic.lastHitboxes.first { $0.handlers.textInput != nil }).bounds
    let surface = automatic.theme[.surface]
    let fills = automatic.lastScene.rects.filter { ixBounds($0) == bounds }
    #expect(fills.count == 1, "M1.9 — one rect at the editor's bounds (\(fills.count))")
    if let fill = fills.first {
        #expect(ixSame(ixHsla(fill.background), surface), "the fill is .surface")
        #expect(fill.cornerRadii.topLeft == 0 && fill.borderWidths.top == 0, "square, no border")
    }
    #expect(try editorWindow { $0.textEditorStyle(.automatic) }.lastScene.rects.filter { ixBounds($0) == bounds }.count == 1,
            ".automatic is the default")
    let plain = try editorWindow { $0.textEditorStyle(.plain) }
    #expect(!plain.lastScene.rects.contains { ixBounds($0) == bounds }, ".plain paints no fill")
    let origins = { (w: Window) in w.lastScene.glyphs.map { [$0.bounds.origin.x, $0.bounds.origin.y] } }
    try #require(!origins(automatic).isEmpty)
    #expect(origins(automatic) == origins(plain), "the text is placed identically")
}
