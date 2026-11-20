import Foundation
@testable import MetalUI
import MetalUIPlatform
import MetalUITesting
import Testing

// `SecureField`'s plaintext after the editing (`SCF-I`, `SCF-J`), its submit and focus, and its steady frames
// (`SCF-K`). Portable and plain: the edit state is read through `@testable`. Each test names its mutation.

@MainActor private final class Model {
    var text = ""
    var showsField = true
    var submits = 0
    var focused = false
    var binding: Binding<String> { Binding(get: { self.text }, set: { self.text = $0 }) }
}

private struct Host: Component {
    let model: Model
    @FocusState var isFocused: Bool
    var content: some ElementGroup {
        VStack(spacing: 8) {
            if model.showsField {
                SecureField("Pass", text: model.binding)
                    .onSubmit { model.submits += 1 }
                    .focused($isFocused)
            }
            TextField("Mild", text: .constant(""))
            Text(isFocused ? "focus-in" : "focus-out")
        }
    }
}

@MainActor private func hostWindow(_ model: Model) throws -> TestWindow {
    let window = try TestWindow(size: sz(400, 300), textSystem: harnessTextSystem) { VStack(spacing: 0) { Host(model: model) } }
    window.window.setNeedsRedraw()
    window.tick()
    return window
}

private func editedStateHoldsNoPlaintext(_ state: TextEditState) -> Bool {
    state.history == TextEditHistory() && state.seenText == nil && !"\(state)".contains("hunter")
}

/// 1 (`SCF-I`) — undo works while focused (AppKit's secure field undoes: probe `undo.swift` in record 393), and the
/// snapshots, `lastText` and the last-seen text are gone from the edit state after blur, after the field's removal and
/// after the window closes. **Mutation:** delete `forgetSecureEdits(of:)` from `focusedElement`'s `didSet`.
@Test @MainActor func aSecureFieldsUndoSnapshotsDoNotOutliveItsFocus() throws {
    let model = Model()
    let window = try hostWindow(model)
    try window.focus(window.element(label: "Pass"))
    let id = try #require(window.window.focusedElement)
    window.typeText("hunter2")
    #expect("\(window.window.editState(id))".contains("hunter"), "instrument: while focused the state holds the text")
    window.typeKey("z", modifierFlags: .primary)
    #expect(model.text.count < 7, "undo works while focused: \(model.text.count) characters")
    try window.focus(window.element(label: "Mild"))
    #expect(editedStateHoldsNoPlaintext(window.window.editState(id)), "after blur")

    // Removal while focused.
    try window.focus(window.element(label: "Pass"))
    window.typeText("hunter2")
    model.showsField = false
    window.window.setNeedsRedraw()
    window.tick()
    #expect(editedStateHoldsNoPlaintext(window.window.editState(id)), "after removal")

    // Window close while focused.
    model.showsField = true
    window.window.setNeedsRedraw()
    window.tick()
    try window.focus(window.element(label: "Pass"))
    let again = try #require(window.window.focusedElement)
    window.typeText("hunter2")
    window.close()
    #expect(editedStateHoldsNoPlaintext(window.window.editState(again)), "after the window closes")
}

/// 2 (`SCF-J`) — no description, debug description, mirror, `dump`, element-tree or accessibility-tree dump of a secure
/// field prints its text. **Mutation:** `TextInputTarget.customMirror` prints `text`; or `SecureField.description` reads
/// `field.text`.
@Test @MainActor func noDumpOrDescriptionOfASecureFieldPrintsItsText() throws {
    let model = Model()
    model.text = "hunter2"
    let window = try hostWindow(model)
    try window.focus(window.element(label: "Pass"))
    let id = try #require(window.window.focusedElement)
    var dumps: [String] = []
    let field = SecureField("Pass", text: model.binding)
    dumps.append(String(describing: field))
    dumps.append(String(reflecting: field))
    var out = ""
    dump(field, to: &out)
    dumps.append(out)
    out = ""
    dump(field.field, to: &out)
    dumps.append(out)
    let target = try #require(window.window.lastFocusRegistry.textTarget(for: id))
    out = ""
    dump(target, to: &out)
    dumps.append(out)
    dumps.append(String(describing: target))
    out = ""
    dump(try window.accessibilityTree, to: &out)
    dumps.append(out)
    dumps.append(String(describing: try window.elements(role: .secureTextField)))
    dumps.append(String(describing: try window.accessibilityTree))
    for (index, text) in dumps.enumerated() {
        #expect(!text.contains("hunter2"), "dump \(index) printed the text")
    }
    #expect(dumps[0].contains("\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}"), "instrument: bullets are printed")
    var plain = ""
    dump(TextField("x", text: model.binding), to: &plain)
    #expect(plain.contains("hunter2"), "instrument: a plain field's dump does print its text")
}

/// 3 (`SCF-K`) — `.onSubmit` runs on Return and `.focused` follows the focus both ways. **Mutation:** `SecureField.onSubmit`
/// returns `self` unchanged.
@Test @MainActor func aSecureFieldSubmitsAndReportsItsFocus() throws {
    let model = Model()
    let window = try hostWindow(model)
    #expect(try !window.elements(where: { $0.value == "focus-out" }).isEmpty)
    try window.focus(window.element(label: "Pass"))
    window.typeText("abc")
    #expect(try !window.elements(where: { $0.value == "focus-in" }).isEmpty)
    window.typeKey(.return)
    #expect(model.submits == 1)
    try window.focus(window.element(label: "Mild"))
    window.tick()
    #expect(try !window.elements(where: { $0.value == "focus-out" }).isEmpty)
}

/// 4 (`SCF-K`) — an idle unfocused and an idle focused secure field ask for no frame: with nothing changing, further
/// ticks draw nothing and request no element. **Mutation:** `syncSecureTextInput` marks the window dirty
/// (`setNeedsRedraw()`) each time it runs.
@Test @MainActor func anIdleSecureFieldAsksForNoFrames() async throws {
    let model = Model()
    let window = try hostWindow(model)
    try await window.runUntilIdle()
    var drawn = window.framesDrawn
    for _ in 0..<5 { window.tick() }
    #expect(window.framesDrawn == drawn, "unfocused: no frame")
    try window.focus(window.element(label: "Pass"))
    window.typeText("abc")
    try await window.runUntilIdle()
    drawn = window.framesDrawn
    window.resetFrameWork()
    for _ in 0..<5 { window.tick() }
    #expect(window.framesDrawn == drawn, "focused: no frame")
    #expect(window.frameWork.reduce(0) { $0 + $1.elementRequests } == 0)
}
