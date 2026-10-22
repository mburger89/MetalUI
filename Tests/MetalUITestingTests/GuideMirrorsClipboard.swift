import MetalUI
import MetalUITesting
import Testing

// Clipboard extras — the mirror of the multi-item and `PasteButton` block of `docs/guides/input.md` (round 2 item 6; `CP-C`,
// `DG-C`, `DG-D`): copied BY HAND between the `// guide:` and `// end guide` markers, byte for byte, so the ordinary build compiles
// it on every platform; `GuideDocCheck.swift` compares it with the guide. `InputGraph` is block #9's. Below it, the tests the
// guide pins. Mutations: write the first item only (the destination receives one); enable the button always (the empty-clipboard
// arm reddens).

// guide: input #11
/// What a paste destination and a paste button received, in order.
@MainActor
final class InputPasteModel {
    var pasted: [InputGraph] = []
    var buttonPasted: [InputGraph] = []
}

/// A source that copies two graphs, a destination for ⌘V and a paste button.
@MainActor
func inputPasteRoot(_ model: InputPasteModel) -> some Element {
    VStack(alignment: .leading) {
        Box().frame(width: Pixels(120), height: Pixels(40)).background(.surface)
            .accessibilityIdentifier("pair-source")
            .focusable()
            .copyable([InputGraph(nodes: 1), InputGraph(nodes: 2)])
        Box().frame(width: Pixels(120), height: Pixels(40)).background(.surface)
            .accessibilityIdentifier("pair-destination")
            .focusable()
            .pasteDestination(for: InputGraph.self) { model.pasted += $0 }
        PasteButton(payloadType: InputGraph.self) { model.buttonPasted += $0 }
    }
}
// end guide

#if os(macOS)
private let guidePrimary: EventModifiers = .command
#else
private let guidePrimary: EventModifiers = .control
#endif

/// A copy of two graphs pastes both, in order, at the destination; the button then pastes both too.
/// Mutation: write the first item only.
@Test @MainActor func theInputGuideACopyOfTwoItemsPastesBothInOrder() throws {
    let model = InputPasteModel()
    let window = try harnessWindow { inputPasteRoot(model) }
    window.typeKey(.tab)
    window.typeKey("c", modifierFlags: guidePrimary)
    window.typeKey(.tab)
    window.typeKey("v", modifierFlags: guidePrimary)
    #expect(model.pasted == [InputGraph(nodes: 1), InputGraph(nodes: 2)])
    #expect(model.buttonPasted.isEmpty, "⌘V is the destination's, not the button's")
}

/// The button is dimmed on an empty clipboard, enabled once a graph is on it, and a click pastes every item.
/// Mutation: always enabled (the first expectation reddens).
@Test @MainActor func theInputGuideAPasteButtonFollowsTheClipboard() throws {
    let model = InputPasteModel()
    let window = try harnessWindow { inputPasteRoot(model) }
    #expect(try !window.element(label: "Paste").isEnabled, "nothing on the clipboard")
    window.setClipboard(items: [InputGraph(nodes: 5), InputGraph(nodes: 6)])
    window.tick()
    #expect(try window.element(label: "Paste").isEnabled)
    try window.click(try window.element(label: "Paste"))
    #expect(model.buttonPasted == [InputGraph(nodes: 5), InputGraph(nodes: 6)])
}
