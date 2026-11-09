import Testing
import Metal
import MetalUICore
import MetalUILayout
import MetalUIPlatform
import MetalUIScene
@testable import MetalUI

// Alloy gap G18, the keys (`VT-F`, record 253): Return, ⇧Return and Enter submit a vertical `TextField`, ⌥↩ and ⌃↩ (Alt+Enter
// elsewhere) insert a line break, ⌘↩ passes on, and a paste keeps its newlines. SwiftUI's table is the probe's arm K
// (`docs/probes/swiftui-vertical-text-field.swift`).

private func near(_ a: Float, _ b: Float, _ tolerance: Float = 0.01) -> Bool { abs(a - b) < tolerance }

@MainActor
private final class Draft {
    var text: String
    var submits = 0
    init(_ text: String = "") { self.text = text }
}

private func pt(_ x: Float, _ y: Float) -> Point<Pixels> { Point(x: Pixels(x), y: Pixels(y)) }

private func key(_ name: String, _ modifiers: Modifiers = []) -> InputEvent {
    .keyDown(KeyEvent(charactersIgnoringModifiers: name, characters: name, modifiers: modifiers, timestamp: 0))
}

@MainActor
private func open<E: Element>(size: Int = 400, _ make: @escaping @MainActor () -> E) throws -> (Window, FakePlatformWindow) {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let (window, platform) = try makeFakeWindow(device: device, size: size, content: make)
    window.drawFrameIfNeeded()
    return (window, platform)
}

@MainActor
private func fieldHit(_ window: Window) throws -> Hitbox {
    try #require(window.lastHitboxes.first { $0.handlers.textInput != nil }, "the field's hitbox")
}

@MainActor
private func composer(_ draft: Draft) throws -> (Window, FakePlatformWindow) {
    try open {
        Box {
            VStack(alignment: .leading, spacing: 0) {
                TextField("", text: draft.text, axis: .vertical, onChange: { draft.text = $0 })
                    .onSubmit { draft.submits += 1 }.lineLimit(1...8).frame(width: Pixels(200))
            }
        }
    }
}

@MainActor
private func focus(_ window: Window, _ platform: FakePlatformWindow) throws {
    let hit = try fieldHit(window)
    platform.simulateInput(.mouseDown(MouseEvent(position: pt(hit.bounds.origin.x.value + 10, hit.bounds.origin.y.value + 8), clickCount: 1)))
    platform.simulateInput(.mouseUp(MouseEvent(position: pt(hit.bounds.origin.x.value + 10, hit.bounds.origin.y.value + 8))))
    window.drawFrameIfNeeded()
}

// MARK: - 17-18 the keys

private func model(_ text: String) -> TextLineModel {
    var model = TextLineModel(lines: [.init(range: 0..<text.count, offsets: (0...text.count).map { Double($0) * 7 },
                                            endsInHardBreak: false)])
    model.lineHeight = 16
    model.visibleHeight = 128
    return model
}

private func press(_ name: String, _ modifiers: Modifiers, platform: TextEditing.Platform, mode: TextEditing.KeyMode = .verticalField,
                   text: String = "ab") -> TextEditing.KeyOutcome {
    var state = TextEditState()
    state.anchor = text.count; state.head = text.count
    return TextEditing.key(KeyEvent(charactersIgnoringModifiers: name, characters: name, modifiers: modifiers, timestamp: 0),
                           text: text, state: state, clipboard: { nil }, platform: platform,
                           lines: mode == .singleLine ? nil : model(text), mode: mode)
}

/// **17** (`VT-F`; probe K, run for both platforms). Return, ⇧Return and Enter submit and insert nothing; ⌥↩ and ⌃↩ on a Mac
/// (Alt+Enter elsewhere) insert a line break; the platform's shortcut modifier's Return (⌘↩, ⌃↩ elsewhere) is not claimed.
///
/// Mutations, each on the table of `TextEditing.key` (a Mac unless said): M17a Return inserting (the `.verticalField` check
/// dropped) reddens "Return submits"; M17b ⇧ among the newline modifiers reddens "⇧Return submits"; M17c ⌥ out of them reddens
/// "⌥↩ inserts"; M17d ⌃ out of the Mac's reddens "⌃↩ inserts"; M17e the shortcut case disabled reddens "⌘↩ is unclaimed";
/// M17f Alt not the newline modifier elsewhere reddens "Alt+Enter inserts".
@Test func returnSubmitsAndTheNewlineModifiersInsertInAVerticalField() {
    for name in ["\r", "\u{3}"] {
        for modifiers: Modifiers in [[], .shift] {
            for platform in [TextEditing.Platform.mac, .other] {
                let outcome = press(name, modifiers, platform: platform)
                #expect(outcome.submitted && outcome.handled && outcome.text == nil, "\(platform) \(modifiers) Return submits and inserts nothing")
            }
        }
    }
    // A Mac.
    #expect(press("\r", .option, platform: .mac).text == "ab\n" && !press("\r", .option, platform: .mac).submitted, "⌥↩ inserts")
    #expect(press("\r", .control, platform: .mac).text == "ab\n", "⌃↩ inserts a line break (not U+2028)")
    #expect(!press("\r", .command, platform: .mac).handled, "⌘↩ is unclaimed")
    // Elsewhere.
    #expect(press("\r", .option, platform: .other).text == "ab\n", "Alt+Enter inserts")
    #expect(!press("\r", .control, platform: .other).handled, "⌃Enter passes on")
    // The editor still inserts on a plain Return and the one-line field still submits on any (control).
    #expect(press("\r", [], platform: .mac, mode: .editor).text == "ab\n")
    #expect(press("\r", .option, platform: .mac, mode: .singleLine).submitted, "divergence: the one-line field submits on ⌥↩")
}

/// **17b**: the same through a `Window`: a Return runs `onSubmit` once and the text does not change; ⌥↩ inserts a line break
/// and does not submit; without an `onSubmit` Return is not claimed and keeps bubbling.
///
/// Mutation M17g: `Window` passing `.editor` for a vertical field (the mode mapping) reddens the first arm (Return inserts).
@Test @MainActor func returnInAWindowSubmitsOnceAndInsertsNothing() throws {
    let draft = Draft("hi")
    let (window, platform) = try composer(draft)
    try focus(window, platform)
    platform.simulateInput(key(TextEditing.downArrow, .command))
    #expect(platform.simulateInput(key("\r")), "Return is claimed")
    #expect(platform.simulateInput(key("\r", .shift)))
    #expect(draft.submits == 2 && draft.text == "hi", "submitted twice, inserted nothing: \(draft.submits) \(draft.text.debugDescription)")
    // Divergence 233: SwiftUI also selects all after a submit; here the caret stays where it was.
    let state = try #require(window.stateTable.peek(try fieldHit(window).id, as: TextEditState.self))
    #expect(state.selection.isEmpty && state.head == 2, "no select-all after a submit: \(state.selection)")
    platform.simulateInput(key("\r", .option))
    #expect(draft.text == "hi\n" && draft.submits == 2, "⌥↩ inserts: \(draft.text.debugDescription)")
    platform.simulateInput(key("\r", .command))
    #expect(draft.text == "hi\n" && draft.submits == 2, "⌘↩ does neither")
    // No onSubmit: not claimed.
    let (bare, barePlatform) = try open {
        Box { TextField("", text: "x", axis: .vertical, onChange: { _ in }).frame(width: Pixels(200)) }
    }
    try focus(bare, barePlatform)
    #expect(!barePlatform.simulateInput(key("\r")), "no onSubmit: Return keeps bubbling")
}

/// **18** (`VT-F`): a paste keeps its newlines in a vertical field (a one-line field joins them). Through a `Window`, so the
/// mode the window passes is under test.
///
/// Mutation M18: `Window` passing `.singleLine` for a vertical field (or `TextEditing.key` choosing `singleLine(pasted)` for it)
/// reddens it.
@Test @MainActor func aPasteKeepsItsNewlinesInAVerticalField() throws {
    let draft = Draft("")
    let (window, platform) = try composer(draft)
    try focus(window, platform)
    platform.clipboard = "one\ntwo\r\nthree"
    platform.simulateInput(key("v", .command))
    #expect(draft.text == "one\ntwo\nthree", "newlines kept (CRLF normalised): \(draft.text.debugDescription)")
    platform.simulateInput(.textInput("a\nb"))
    #expect(draft.text.hasSuffix("a\nb"), "an input method's commit keeps them too: \(draft.text.debugDescription)")
}

