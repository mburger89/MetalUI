import Foundation
import MetalUI
import MetalUICore
import MetalUIPlatform
import MetalUIScene
import MetalUITesting
import Testing

// Alloy gap G29 (`VT-K`, record 261): `TextField(_:text:selectedOffsets:prompt:)` and its `axis:` form route the prompt as
// `selection:prompt:` does (`VT-J`) and keep the offsets binding and the vertical growth. PLAIN imports, headless window.

@MainActor private final class Model {
    var text = "" { didSet { redraw?() } }
    var offsets: Range<Int>? { didSet { redraw?() } }
    var redraw: (@MainActor () -> Void)?
    var textBinding: Binding<String> { Binding(get: { self.text }, set: { self.text = $0 }) }
    var offsetsBinding: Binding<Range<Int>?> { Binding(get: { self.offsets }, set: { self.offsets = $0 }) }
}

private func hsla(_ c: MUIHsla) -> Hsla { Hsla(h: c.h, s: c.s, l: c.l, a: c.a) }
private func same(_ a: Hsla, _ b: Hsla) -> Bool {
    let (x, y) = (a.toRgba(), b.toRgba())
    return abs(x.r - y.r) < 1e-4 && abs(x.g - y.g) < 1e-4 && abs(x.b - y.b) < 1e-4 && abs(x.a - y.a) < 1e-4
}

@MainActor private func fieldWindow(_ model: Model, vertical: Bool, prompt: Text?,
                                    limit: ClosedRange<Int> = 1...4) throws -> TestWindow {
    let window = try harnessWindow(size: sz(300, 200)) {
        Box {
            if vertical {
                TextField("Title", text: model.textBinding, selectedOffsets: model.offsetsBinding, prompt: prompt, axis: .vertical)
                    .lineLimit(limit)
            } else {
                TextField("Title", text: model.textBinding, selectedOffsets: model.offsetsBinding, prompt: prompt)
            }
        }
    }
    model.redraw = { [unowned window] in window.window.setNeedsRedraw() }
    window.tick(); window.tick()
    return window
}

/// 1 - an empty field draws the prompt's string (not the title) in the prompt's colour, in both spellings. Mutation: **M1**
/// `applyPrompt` dropped from the two new initialisers reddens it (the title is drawn, in the default colour).
@Test(arguments: [false, true]) @MainActor
private func anOffsetsFieldDrawsItsPromptInThePromptsColour(vertical: Bool) throws {
    let model = Model()
    let window = try fieldWindow(model, vertical: vertical, prompt: Text("Prompt").foregroundColor(.red))
    #expect(window.scene.glyphs.count == "Prompt".count, "the prompt's string is drawn, not the title")
    let red = try harnessWindow(size: sz(300, 120)) { Box { Text("x").foregroundStyle(Color.red) } }
    red.tick(); red.tick()
    let want = hsla(try #require(red.scene.glyphs.first).color)
    for glyph in window.scene.glyphs { #expect(same(hsla(glyph.color), want), "vertical \(vertical): the prompt's colour") }
}

/// 2 - the offsets binding still tracks the caret. Mutation: **M2** the new initialiser not forwarding `selectedOffsets`
/// (calling `init(_:text:)`) leaves `offsets` nil and reddens it.
@Test(arguments: [false, true]) @MainActor
private func theOffsetsBindingStillTracksTheCaret(vertical: Bool) throws {
    let model = Model()
    let window = try fieldWindow(model, vertical: vertical, prompt: Text("Prompt"))
    try window.focus(window.element(label: "Prompt"))
    window.typeText("hello")
    #expect(model.text == "hello")
    #expect(model.offsets == 5..<5)
    window.typeKey(.leftArrow); window.typeKey(.leftArrow)
    #expect(model.offsets == 3..<3)
    model.offsets = 1..<2
    window.tick()
    window.typeText("X")
    #expect(model.text == "hXllo", "a range written from code is applied")
}

/// 3 - the vertical variant grows with its lines up to the `lineLimit` upper bound. Mutation: **M3** the `axis:` form
/// not setting the axis (`init(_:text:selectedOffsets:)` alone) keeps it one line tall and reddens it.
@Test @MainActor
private func theVerticalOffsetsFieldGrowsPerLineLimit() throws {
    let model = Model()
    model.text = "a"
    let window = try fieldWindow(model, vertical: true, prompt: Text("Prompt"), limit: 1...3)
    func height() throws -> Float { try window.element(label: "Prompt").frame.size.height.value }
    let one = try height()
    model.text = "a\nb"; window.tick(); window.tick()
    let two = try height()
    model.text = "a\nb\nc\nd\ne"; window.tick(); window.tick()
    let capped = try height()
    #expect(two > one, "a second line grows the field: \(one) -> \(two)")
    #expect(capped > two && capped < 5 * one, "capped at three lines: \(capped)")
    model.text = "a\nb\nc"; window.tick(); window.tick()
    #expect(try height() == capped, "three lines and five lines are the same height")
}
