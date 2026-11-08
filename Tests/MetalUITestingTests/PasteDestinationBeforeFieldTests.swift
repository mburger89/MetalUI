import Foundation
import MetalUI
import MetalUIPlatform
import MetalUITesting
import Testing

// Alloy gap G10 (ruling `CB-T`, record 242): ⌘V in a focused `TextEditor`/`TextField` is offered to the innermost
// `pasteDestination` on the focus chain (the field's own or an ancestor's) BEFORE the field pastes its text. An
// image-only clipboard therefore reaches the destination; one it declines (no matching type, or its validator
// empties the list) falls through to the field's text paste. `Graph` (own type plus a text fallback) and `Blob`
// (own type only, the image stand-in) are `ClipboardTypesTests`' types. MetalUI's own rule: SwiftUI's order was
// not measured (the probe cannot read a pasteboard-less NSHostingView's destination), so it is recorded as MetalUI's.

@MainActor private final class PasteModel {
    var text = "hello"
    var blobs: [[Blob]] = []
    var graphs: [[Graph]] = []
}

private enum Host: String, CaseIterable, Sendable, CustomTestStringConvertible {
    case editorItself, editorInAContainer, fieldItself
    var testDescription: String { rawValue }
}

@MainActor private func pasteWindow(_ m: PasteModel, _ host: Host,
                                    validator: @escaping @MainActor ([Blob]) -> [Blob] = { $0 }) throws -> TestWindow {
    let binding = Binding<String>(get: { m.text }, set: { m.text = $0 })
    let window: TestWindow
    switch host {
    case .editorItself:
        window = try harnessWindow {
            TextEditor("Note", text: binding)
                .pasteDestination(for: Blob.self, action: { m.blobs.append($0) }, validator: validator)
        }
    case .editorInAContainer:
        window = try harnessWindow {
            VStack(spacing: 0) { TextEditor("Note", text: binding) }
                .pasteDestination(for: Blob.self, action: { m.blobs.append($0) }, validator: validator)
        }
    case .fieldItself:
        window = try harnessWindow {
            TextField("Note", text: binding)
                .pasteDestination(for: Blob.self, action: { m.blobs.append($0) }, validator: validator)
        }
    }
    try window.focus(window.element(label: "Note"))
    window.typeKey(.end)
    return window
}

/// 1 — **an image-only clipboard reaches the destination** and the text is untouched, on the editor itself, on
/// a container around it, and on a field. **Red before:** the field's own ⌘V ran first and consumed the key
/// (nothing pasted, no destination call). **Mutation:** delete the `offerPasteToDestinationBeforeTheField` line
/// in `dispatchTextKey` — all three redden.
@Test(arguments: Host.allCases) @MainActor
private func anImageOnlyClipboardReachesThePasteDestinationOfAFocusedField(host: Host) throws {
    let m = PasteModel()
    let window = try pasteWindow(m, host)
    window.setClipboard(items: [Blob(bytes: [1, 2, 3])])
    window.typeKey("v", modifierFlags: .primary)
    #expect(m.blobs == [[Blob(bytes: [1, 2, 3])]], "the destination ran once with the decoded item")
    #expect(m.text == "hello", "the field pasted nothing")
}

/// 2 — **a text clipboard pastes text** when the destination imports a type that is not on it. **Mutation:**
/// make the offer return `true` whenever a destination exists (`return true` before calling it).
@Test(arguments: Host.allCases) @MainActor
private func aTextClipboardPastesTextWhenTheDestinationImportsNothingOnIt(host: Host) throws {
    let m = PasteModel()
    let window = try pasteWindow(m, host)
    window.setClipboard(text: " world")
    window.typeKey("v", modifierFlags: .primary)
    #expect(m.blobs.isEmpty, "the destination found no Blob and declined")
    #expect(m.text == "hello world", "the field pasted the text")
}

/// 3 — **a clipboard with both prefers the destination when it accepts**: a `Graph` is on the clipboard as its
/// own type and as text; a destination for `Graph` takes it, the text stays. The control: the same clipboard
/// under a destination for `Blob` (declines) pastes the text fallback. **Mutation:** offer the paste after
/// `TextEditing.key` instead of before.
@Test @MainActor
private func aClipboardWithBothPrefersTheDestinationThatAccepts() throws {
    let m = PasteModel()
    let binding = Binding<String>(get: { m.text }, set: { m.text = $0 })
    let window = try harnessWindow {
        TextEditor("Note", text: binding).pasteDestination(for: Graph.self) { m.graphs.append($0) }
    }
    try window.focus(window.element(label: "Note"))
    window.typeKey(.end)
    window.setClipboard(items: [Graph(label: "g")])
    window.typeKey("v", modifierFlags: .primary)
    #expect(m.graphs == [[Graph(label: "g")]])
    #expect(m.text == "hello", "the text fallback was not pasted as well")

    let other = PasteModel()
    let control = try pasteWindow(other, .editorItself)
    control.setClipboard(items: [Graph(label: "g")])
    control.typeKey("v", modifierFlags: .primary)
    #expect(other.blobs.isEmpty)
    #expect(other.text == "hellograph g", "a destination that imports another type declines and the text is pasted")
}

/// 4 — **a validator that empties the list declines**, so the text is pasted (`CB-F`: nothing imported is a
/// decline). **Mutation:** ignore the `Bool` the destination answers.
@Test @MainActor
private func aDeclinedPasteFallsThroughToTheFieldsText() throws {
    let m = PasteModel()
    let window = try pasteWindow(m, .editorItself, validator: { _ in [] })
    window.setClipboard(items: [Graph(label: "g")])   // its text fallback is the only thing the field can paste
    window.typeKey("v", modifierFlags: .primary)
    #expect(m.blobs.isEmpty)
    #expect(m.text == "hellograph g")

    let both = PasteModel()
    let second = try pasteWindow(both, .editorItself, validator: { _ in [] })
    second.setClipboard(items: [Blob(bytes: [9])])
    second.typeKey("v", modifierFlags: .primary)
    #expect(both.blobs.isEmpty && both.text == "hello", "declined, and an image-only clipboard has no text to paste")
}

/// 5 — **no destination: the field pastes as it always did.** **Mutation:** return `true` from the offer
/// whenever the key is ⌘V.
@Test @MainActor
private func aFieldWithNoDestinationStillPastesText() throws {
    let m = PasteModel()
    let binding = Binding<String>(get: { m.text }, set: { m.text = $0 })
    let window = try harnessWindow { TextEditor("Note", text: binding) }
    try window.focus(window.element(label: "Note"))
    window.typeKey(.end)
    window.setClipboard(text: "!")
    window.typeKey("v", modifierFlags: .primary)
    #expect(m.text == "hello!")
}

/// 6 — the real image type: a PNG on the clipboard (`ImageData`, `SOC-H`) under `pasteDestination(for: ImageData.self)`
/// on a focused editor reaches the destination with its format, and the text stays (Alloy's case).
/// **Mutation:** as 1.
@Test @MainActor
private func aPngOnTheClipboardReachesAnImageDataDestinationOfAFocusedEditor() throws {
    let m = PasteModel()
    var received: [[ImageData]] = []
    let binding = Binding<String>(get: { m.text }, set: { m.text = $0 })
    let window = try harnessWindow {
        TextEditor("Note", text: binding).pasteDestination(for: ImageData.self) { received.append($0) }
    }
    try window.focus(window.element(label: "Note"))
    window.typeKey(.end)
    let png = ImageData(data: Data([0x89, 0x50, 0x4e, 0x47, 1, 2]), contentType: .png)
    window.setClipboard(items: [png])
    window.typeKey("v", modifierFlags: .primary)
    #expect(received == [[png]])
    #expect(m.text == "hello")
}
