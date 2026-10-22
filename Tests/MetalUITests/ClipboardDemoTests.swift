import Testing
import MetalUI
import MetalUITesting
@testable import MetalUIDemoContent

// The clipboard demo (`METALUI_CLIPBOARD_DEMO=1`, spec §6, rulings `CB-A`…`CB-C`) under the
// harness: Tab to the source, copy, Tab to the destination, paste shows the node count; a cut
// drops the count; pasting into the text field shows the fallback text. Mutation: the demo's
// `copyable` dropped (the destination reads "nothing pasted yet").

#if os(macOS)
private let demoPrimary: EventModifiers = .command
#else
private let demoPrimary: EventModifiers = .control
#endif

@Test @MainActor func theClipboardDemoCopiesAGraphAndPastesItAndItsTextFallback() throws {
    clipboardDemoModel.reset()
    let window = try TestWindow(size: Size(width: Pixels(920), height: Pixels(560)), content: clipboardDemoContent)
    window.typeKey(.tab)                         // the source
    window.typeKey("c", modifierFlags: demoPrimary)
    #expect(window.clipboardRepresentations.map(\.type.identifier)
            == ["com.metalui.demo.graph", "public.utf8-plain-text"])
    window.typeKey(.tab)                         // the destination
    window.typeKey("v", modifierFlags: demoPrimary)
    #expect(clipboardDemoModel.received == "3 nodes")

    window.typeKey(.tab, modifierFlags: .shift)  // back to the source
    window.typeKey("x", modifierFlags: demoPrimary)
    #expect(clipboardDemoModel.nodes == 2)

    window.typeKey(.tab)
    window.typeKey(.tab)                         // the text field
    window.typeKey("v", modifierFlags: demoPrimary)
    #expect(clipboardDemoModel.field == "graph with 3 nodes", "the field pasted the fallback text")
}

/// The several-items section (`CP-B`, `CP-C`): the pair source copies two graphs, the pair destination lists both, and the paste
/// button is dimmed on an empty clipboard and pastes both once a graph is on it. Tab order: source, destination, field, pair
/// source, pair destination, button. Mutation: the pair source's `copyable` dropped to one graph (the destination reads one item).
@Test @MainActor func theClipboardDemoCopiesTwoGraphsAndAPasteButtonPastesThem() throws {
    clipboardDemoModel.reset()
    let window = try TestWindow(size: Size(width: Pixels(920), height: Pixels(760)), content: clipboardDemoContent)
    #expect(try !window.element(label: "Paste").isEnabled, "nothing on the clipboard")
    for _ in 0..<4 { window.typeKey(.tab) }      // the pair source
    window.typeKey("c", modifierFlags: demoPrimary)
    #expect(window.clipboardItems.count == 2)
    window.typeKey(.tab)                         // the pair destination
    window.typeKey("v", modifierFlags: demoPrimary)
    #expect(clipboardDemoModel.receivedAll == "1, 2 nodes (2 items)")
    window.tick()
    #expect(try window.element(label: "Paste").isEnabled, "graphs are on the clipboard")
    try window.click(try window.element(label: "Paste"))
    #expect(clipboardDemoModel.buttonReceived == "2 graphs, 3 nodes")
}
