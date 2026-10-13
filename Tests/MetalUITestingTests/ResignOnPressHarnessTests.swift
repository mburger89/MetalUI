import MetalUI
import MetalUITesting
import Testing

// C24 end to end over the `MetalUITesting` harness (`HT-`): the MetalCreator
// shape (CT-a) — `.resignsFocusOnPress()` on the app root, a field and an
// inert canvas. Mutation: remove the modifier from the root (red).

@MainActor private final class ResignModel {
    var text = ""
    var committed: [String] = []
}

@Test @MainActor func aClickOnInertChromeEndsInPlaceEditingAndTheCommitSeesTheText() throws {
    let model = ResignModel()
    let window = try harnessWindow {
        VStack(spacing: 0) {
            TextField("Name", text: model.text) { model.text = $0 }
                .frame(width: Pixels(200), height: Pixels(24))
                .accessibilityIdentifier("name")
            Box().frame(width: Pixels(100), height: Pixels(100)).background(.surface).id("chrome")
        }
        .resignsFocusOnPress()
    }
    let field = try window.element(identifier: "name")
    try window.click(field)
    #expect(try window.focusedElement?.identifier == "name")
    window.typeText("Ada")
    #expect(model.text == "Ada")

    let chrome = try window.frame(ofID: "chrome")
    window.click(at: Point(x: chrome.origin.x + Pixels(50), y: chrome.origin.y + Pixels(50)))
    #expect(try window.focusedElement == nil, "the click on inert chrome ended editing")
    model.committed.append(model.text)
    window.typeText("zzz")
    #expect(model.text == "Ada" && model.committed == ["Ada"], "a later typeText changes nothing")
}
