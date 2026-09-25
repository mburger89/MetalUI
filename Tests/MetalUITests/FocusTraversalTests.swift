import Testing
import Metal
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// TI-J: Tab and shift-Tab move focus between focusable elements in tree order.

@MainActor
private final class Form {
    var name = "Ada"
    var email = ""
    var notes = "old notes"
    var log: [String] = []
    var disabled = false
    var onKeyClaimsTab = false
}

private func key(_ name: String, _ modifiers: Modifiers = []) -> InputEvent {
    .keyDown(KeyEvent(charactersIgnoringModifiers: name, characters: name, modifiers: modifiers, timestamp: 0))
}

/// A name field, a focusable box, an email field (optionally disabled) and a
/// notes editor, in that order.
@MainActor
private func formWindow(_ form: Form, onKey: KeyHandler? = nil) throws -> (Window, FakePlatformWindow) {
    let device = try #require(MTLCreateSystemDefaultDevice())
    return try makeFakeWindow(device: device, size: 300) {
        let column = Column {
            TextField("Name", text: form.name) { form.name = $0 }
            Box().width(Pixels(20)).height(Pixels(20)).focusable()
            TextField("Email", text: form.email) { form.email = $0 }.disabled(form.disabled)
            TextEditor("Notes", text: form.notes) { form.notes = $0 }.height(Pixels(60))
        }
        .alignItems(.stretch)
        return Box { column }.onKey(onKey ?? { _ in false })
    }
}

/// The focused element's position in the tab order, or nil.
@MainActor
private func focusIndex(_ window: Window) -> Int? {
    window.focusedElement.flatMap { window.lastFocusRegistry.tabOrder.firstIndex(of: $0) }
}

@Test @MainActor func tabWalksTheFocusableElementsInTreeOrderAndWraps() throws {
    let form = Form()
    let (window, platform) = try formWindow(form)
    window.drawFrameIfNeeded()
    try #require(window.lastFocusRegistry.tabOrder.count == 4)
    var visited: [Int?] = []
    for _ in 0..<5 {
        #expect(platform.simulateInput(key("\t")))
        window.drawFrameIfNeeded()
        visited.append(focusIndex(window))
    }
    #expect(visited == [0, 1, 2, 3, 0], "first from nothing, then in order, wrapping")
    platform.simulateInput(key("\t", .shift))
    window.drawFrameIfNeeded()
    #expect(focusIndex(window) == 3, "shift-Tab goes back, wrapping")
    platform.simulateInput(key("\u{19}"))     // AppKit's backtab character
    window.drawFrameIfNeeded()
    #expect(focusIndex(window) == 2)
    window.focus(nil)
    platform.simulateInput(key("\t", .shift))
    #expect(focusIndex(window) == 3, "shift-Tab from nothing: the last")
}

@Test @MainActor func tabbingIntoAFieldSelectsItsTextAndAnEditorPassesTabOn() throws {
    let form = Form()
    let (window, platform) = try formWindow(form)
    window.drawFrameIfNeeded()
    platform.simulateInput(key("\t"))          // the name field
    platform.simulateInput(.textInput("Grace"))
    #expect(form.name == "Grace", "the whole text was selected, so typing replaced it")
    window.drawFrameIfNeeded()
    // The editor is last; Tab from it goes on to the first element rather than
    // inserting a tab.
    platform.simulateInput(key("\t", .shift))
    window.drawFrameIfNeeded()
    #expect(focusIndex(window) == 3)
    platform.simulateInput(key("\t"))
    window.drawFrameIfNeeded()
    #expect(focusIndex(window) == 0 && form.notes == "old notes")
}

@Test @MainActor func aDisabledFieldIsSkipped() throws {
    let form = Form()
    form.disabled = true
    let (window, platform) = try formWindow(form)
    window.drawFrameIfNeeded()
    #expect(window.lastFocusRegistry.tabOrder.count == 3)
    platform.simulateInput(key("\t")); platform.simulateInput(key("\t")); platform.simulateInput(key("\t"))
    window.drawFrameIfNeeded()
    #expect(window.lastFocusRegistry.textTarget(for: try #require(window.focusedElement))?.lines != nil,
            "name, box, then straight to the editor")
}

@Test @MainActor func anAppsHandlersSeeTabFirstAndAModifiedTabIsNotTraversal() throws {
    let form = Form()
    let (window, platform) = try formWindow(form) { event in
        guard event.charactersIgnoringModifiers == "\t" else { return false }
        if event.modifiers.contains(.option) { form.log.append("option-tab"); return true }
        if form.onKeyClaimsTab { form.log.append("onKey-tab"); return true }
        return false
    }
    window.drawFrameIfNeeded()
    // `onKey` bubbles along the focus chain, so focus the name field first.
    platform.simulateInput(key("\t"))
    window.drawFrameIfNeeded()
    let name = window.focusedElement
    platform.simulateInput(key("\t", .option))
    #expect(form.log == ["option-tab"] && window.focusedElement == name, "an onKey claim wins")
    #expect(platform.simulateInput(key("\t", .command)) == false && window.focusedElement == name,
            "command-Tab is not traversal")
    form.onKeyClaimsTab = true
    platform.simulateInput(key("\t"))
    #expect(form.log.last == "onKey-tab" && window.focusedElement == name, "a plain Tab an onKey claims")
    form.onKeyClaimsTab = false
    struct Next: Action {}
    window.keymap = Keymap { KeyBinding("tab", Next()) }
    window.onAction = { _ in form.log.append("keymap"); return true }
    platform.simulateInput(key("\t"))
    #expect(form.log.last == "keymap" && window.focusedElement == name, "a keymap binding wins")
}
