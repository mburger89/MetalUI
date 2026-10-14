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
