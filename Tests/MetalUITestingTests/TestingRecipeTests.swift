import MetalUI
import MetalUITesting
import Observation
import Testing

// The worked example in `docs/testing.md` ("Recipe: typing into a canvas
// app's field"), compiled and run for real so the doc cannot rot. Change
// this file and the doc together. Plain imports, portable: `.primary` is ⌘ on
// macOS and Ctrl elsewhere (`SG-B`), and the platform's editing shortcuts
// use the same modifier, so the chord is the same code on every platform.
// Mutations (branch checker): drop `modifierFlags: .primary` from the chord,
// or remove `.hoverKeyRegion()`.

@Observable @MainActor final class RecipeModel {
    var text = ""
    var committed: [String] = []
    var log: [String] = []
}

@Test @MainActor func typingIntoAFieldCommitsOnTheShortcutReturnAndAClickInAKeyRegionResignsFocus() throws {
    let model = RecipeModel()
    let window = try harnessWindow {
        VStack(spacing: 0) {
            TextField("Name", text: model.text) { model.text = $0 }
                .onSubmit { model.log.append("submit") }
                .frame(width: Pixels(200), height: Pixels(24))
                .accessibilityIdentifier("name")
                .onKeyPress(keys: [.return]) { press in
                    guard press.modifiers.contains(.primary) else { return .ignored }
                    model.committed.append(model.text)
                    return .handled
                }
                .onKeyPress(keys: [.escape]) { _ in
                    model.log.append("escape")
                    return .handled
                }
            Box().frame(width: Pixels(100), height: Pixels(100)).background(.surface)
                .hoverKeyRegion()
                .id("canvas")
        }
    }

    // Focus the field: a click focuses a TextField.
    let field = try window.element(identifier: "name")
    try window.click(field)
    #expect(try window.focusedElement?.identifier == "name")

    // Text arrives as text input; the shortcut-modified Return commits.
    window.typeText("Ada")
    #expect(model.text == "Ada")
    window.typeKey(.return, modifierFlags: .primary)
    #expect(model.committed == ["Ada"], "the chord reached onKeyPress")
    #expect(model.log.isEmpty, "and did not submit the field")

    // Plain Return is declined by the handler and submits; Escape is claimed.
    window.typeKey(.return)
    window.typeKey(.escape)
    #expect(model.log == ["submit", "escape"])
    #expect(model.committed == ["Ada"], "a plain Return commits nothing")

    // A click inside the key region outside the field clears focus.
    let canvas = try window.frame(ofID: "canvas")
    window.click(at: Point(x: canvas.origin.x + Pixels(50), y: canvas.origin.y + Pixels(50)))
    #expect(try window.focusedElement == nil)
    #expect(model.text == "Ada", "the committed text is untouched")
}
