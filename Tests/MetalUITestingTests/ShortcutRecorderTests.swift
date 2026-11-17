import Foundation
import MetalUI
import MetalUITesting
import Testing

// `ShortcutRecorder` (ruling `KF-AK`, record 366): one test per rule, in a window of a real `App` with a
// `CommandMenu` ⌘K item, a `Button` with a ⌘K shortcut, a `TextField` and the recorder. PLAIN imports, the harness
// text system, so the file runs on every platform. Each test names the mutation that reddens it (recorded in the
// record).

@MainActor private final class RecLog {
    var entries: [String] = []
    func add(_ entry: String) { entries.append(entry) }
    var records: [KeyboardShortcut] = []
}

private struct RecHost: Component {
    let log: RecLog
    var initial: KeyboardShortcut?
    @State var shortcut: KeyboardShortcut?
    @State var text = ""

    var content: some ElementGroup {
        let log = log, shortcut = $shortcut, text = $text
        return VStack(spacing: Pixels(8)) {
            ShortcutRecorder(shortcut.wrappedValue ?? initial,
                             onRecord: { shortcut.wrappedValue = $0; log.records.append($0); log.add("record") },
                             onClear: { shortcut.wrappedValue = nil; log.add("clear") },
                             onCancel: { log.add("cancel") })
            Button("Go") { log.add("button") }.keyboardShortcut("k")
            TextField("name", text: text)
        }
    }
}

@MainActor private struct Rig {
    let app: TestApp
    let w: TestWindow
    let log: RecLog
    var recorder: TestElement { get throws { try w.element(label: "Shortcut") } }
    var isRecording: Bool { (try? recorder.isFocused) ?? false }
}

@MainActor private func settle(_ w: TestWindow) async throws {
    for _ in 0..<3 { w.window.setNeedsRedraw(); try await w.runUntilIdle() }
}

/// The window with the recorder idle: nothing is focused (the recorder is no first-draw seat, R17).
@MainActor private func rig(initial: KeyboardShortcut? = nil) async throws -> Rig {
    let app = try TestApp(textSystem: harnessTextSystem)
    let log = RecLog()
    app.app.commands { CommandMenu("Tools") { Button("Run") { log.add("command") }.keyboardShortcut("k") } }
    let w = try app.openWindow(size: sz(300, 200)) { VStack { RecHost(log: log, initial: initial) } }
    try await settle(w)
    return Rig(app: app, w: w, log: log)
}

/// Starts recording the way a person does: a primary press on the field.
@MainActor private func startRecording(_ r: Rig) async throws {
    r.w.window.focus(nil); r.w.tick()
    try await settle(r.w)
    try r.w.click(r.recorder)
    try await settle(r.w)
    try #require(r.isRecording, "set up: the press starts recording")
    r.log.entries = []
}

/// One key down and up as an SDL-shaped or plain event.
@MainActor private func press(_ r: Rig, _ key: String, _ modifiers: EventModifiers = [], unshifted: String = "",
                              chars: String? = nil) async throws {
    var event = KeyEvent(charactersIgnoringModifiers: key, characters: chars ?? key, modifiers: modifiers,
                         timestamp: r.w.now)
    event.unshiftedKey = unshifted
    r.w.send(.keyDown(event))
    r.w.send(.keyUp(event))
    try await settle(r.w)
}

private let escape = String(KeyEquivalent.escape.character)
private let backspace = String(KeyEquivalent.delete.character)
private let forwardDelete = String(KeyEquivalent.deleteForward.character)

/// **R1** A plain press starts recording, and a key is recorded in its base form: ⌘J records `"j"` + ⌘, `onRecord`
/// runs once, recording ends (focus left) and no cancel follows. Mutation: pass `press.modifiers` as `[]`; or run
/// `onCancel` from the focus loss after a record (the `ended` flag).
@Test @MainActor func aKeyIsRecordedAndEndsTheRecording() async throws {
    let r = try await rig()
    try await startRecording(r)
    try await press(r, "j", .command)
    #expect(r.log.records == [KeyboardShortcut("j", modifiers: .command)], "\(r.log.records)")
    #expect(r.log.entries == ["record"], "exactly one callback and no cancel after: \(r.log.entries)")
    #expect(!r.isRecording)
    #expect(r.log.records.first?.displayText(for: .macOS) == "⌘J")
}

/// **R2** Plain letters record (no validation): `a` is `"a"` with no modifier. Mutation: refuse a key with no
/// modifier.
@Test @MainActor func aPlainLetterRecords() async throws {
    let r = try await rig()
    try await startRecording(r)
    try await press(r, "a")
    #expect(r.log.records == [KeyboardShortcut("a", modifiers: [])])
}

/// **R3** The key is lower-cased: an upper-case "P" reported with ⇧⌘ (AppKit, no `unshiftedKey`) records `"p"`.
/// Mutation: drop the `lowercased()` in `baseKey`.
@Test @MainActor func theKeyIsLowerCased() async throws {
    let r = try await rig()
    try await startRecording(r)
    try await press(r, "P", [.shift, .command], chars: "P")
    #expect(r.log.records == [KeyboardShortcut("p", modifiers: [.shift, .command])], "\(r.log.records)")
}

/// **R4** AppKit-shaped ⇧/ (`charactersIgnoringModifiers` "?", `unshiftedKey` "/") records `"/"` + ⇧: the one form
/// (Alloy's answer 3). Mutation: read `press.key` instead of `unshiftedKey`.
@Test @MainActor func anAppKitShiftedKeyRecordsItsBaseKey() async throws {
    let r = try await rig()
    try await startRecording(r)
    try await press(r, "?", .shift, unshifted: "/")
    #expect(r.log.records == [KeyboardShortcut("/", modifiers: .shift)], "\(r.log.records)")
}

/// **R5** SDL-shaped ⇧/ (the unshifted "/" with Shift) records the same shortcut as R4. Mutation: as R4 (the SDL path
/// would still pass, so this one pins that both forms are equal, not that either is read).
@Test @MainActor func anSDLShiftedKeyRecordsTheSameShortcut() async throws {
    let r = try await rig()
    try await startRecording(r)
    try await press(r, "/", .shift, unshifted: "/", chars: "?")
    #expect(r.log.records == [KeyboardShortcut("/", modifiers: .shift)], "\(r.log.records)")
    #expect(r.log.records.first?.displayText(for: .macOS) == "⇧/")
    #expect(r.log.records.first?.displayText(for: .linux) == "Shift+/")
}

/// **R6** ⇧Tab recorded with another modifier is `"\t"` whichever way the platform spells it: AppKit's "\u{19}" and
/// SDL's "\t". Mutation: drop the `\u{19}` to `\t` read in `baseKey`.
@Test @MainActor func aBacktabWithAnotherModifierRecordsAsTab() async throws {
    let r = try await rig()
    try await startRecording(r)
    try await press(r, "\u{19}", [.shift, .control])
    try await startRecording(r)
    try await press(r, "\t", [.shift, .control], unshifted: "\t")
    let expected = KeyboardShortcut(.tab, modifiers: [.shift, .control])
    #expect(r.log.records == [expected, expected], "\(r.log.records)")
}

/// **R7** Bare Escape cancels (`onCancel` once, nothing recorded) and ends recording. Mutation: record Escape as a
/// key; or drop the `ended` flag (a second cancel from the focus loss).
@Test @MainActor func bareEscapeCancelsOnce() async throws {
    let r = try await rig()
    try await startRecording(r)
    try await press(r, escape)
    #expect(r.log.entries == ["cancel"], "\(r.log.entries)")
    #expect(r.log.records.isEmpty && !r.isRecording)
}

/// **R8** Bare ⌫ clears, and bare ⌦ clears (Windows calls it Delete). Mutation: drop either test in `of`.
@Test @MainActor func bareBackspaceAndForwardDeleteClear() async throws {
    let r = try await rig(initial: KeyboardShortcut("j"))
    for key in [backspace, forwardDelete] {
        try await startRecording(r)
        try await press(r, key)
        #expect(r.log.entries == ["clear"], "\(r.log.entries)")
        #expect(r.log.records.isEmpty && !r.isRecording)
    }
}

/// **R9** With a modifier Delete and Escape record like any other key: ⌘⌫ and ⌥Esc. Mutation: test only the key, not
/// the modifiers, for cancel and clear.
@Test @MainActor func deleteAndEscapeWithAModifierRecord() async throws {
    let r = try await rig()
    try await startRecording(r)
    try await press(r, backspace, .command)
    try await startRecording(r)
    try await press(r, escape, .option)
    #expect(r.log.records == [KeyboardShortcut(.delete, modifiers: .command),
                              KeyboardShortcut(.escape, modifiers: .option)], "\(r.log.records)")
    #expect(!r.log.entries.contains("cancel") && !r.log.entries.contains("clear"), "\(r.log.entries)")
}

/// **R10** A modifier-only press, a key repeat and a key-up alone record nothing and recording goes on.
/// Mutation: drop the `.down` phase filter (a release records); or the repeat guard; or hear `.modifiersChanged`.
@Test @MainActor func modifierOnlyRepeatAndReleaseAreIgnored() async throws {
    let r = try await rig()
    try await startRecording(r)
    r.w.pressModifiers([.command, .shift])
    r.w.pressModifiers([])
    var repeated = KeyEvent(charactersIgnoringModifiers: "j", characters: "j", modifiers: .command, isRepeat: true,
                            timestamp: r.w.now)
    repeated.unshiftedKey = ""
    r.w.send(.keyDown(repeated))
    r.w.send(.keyUp(KeyEvent(charactersIgnoringModifiers: "j", characters: "j", modifiers: .command,
                             timestamp: r.w.now)))
    try await settle(r.w)
    #expect(r.log.records.isEmpty && r.log.entries.isEmpty, "\(r.log.records) \(r.log.entries)")
    #expect(r.isRecording)
}

/// **R11** Bare Tab and ⇧Tab are not taken: focus moves on, which cancels once; ⌃Tab and ⌥Tab record. Mutation:
/// record a bare Tab; or treat ⇧Tab "\u{19}" as another key and record it.
@Test @MainActor func bareTabMovesOnAndCancelsButControlTabRecords() async throws {
    for (key, mods) in [("\t", EventModifiers()), ("\u{19}", .shift), ("\t", .shift)] {
        let r = try await rig()
        try await startRecording(r)
        try await press(r, key, mods)
        #expect(r.log.entries == ["cancel"], "tab \(mods): \(r.log.entries)")
        #expect(r.log.records.isEmpty && !r.isRecording)
    }
    let r = try await rig()
    try await startRecording(r)
    try await press(r, "\t", .control)
    try await startRecording(r)
    try await press(r, "\t", .option)
    #expect(r.log.records == [KeyboardShortcut(.tab, modifiers: .control), KeyboardShortcut(.tab, modifiers: .option)],
            "\(r.log.records)")
}

/// **R13** Neither the `CommandMenu` ⌘K item nor the `Button` ⌘K shortcut runs while recording: ⌘K records. After the
/// recording they run. Mutation: drop `.keyCapture()` (both run, nothing records).
@Test @MainActor func menuItemsAndButtonsDoNotRunWhileRecording() async throws {
    let r = try await rig()
    try await startRecording(r)
    try await press(r, "k", .primary)
    #expect(r.log.records == [KeyboardShortcut("k", modifiers: .primary)])
    #expect(r.log.entries == ["record"], "neither the item nor the button ran: \(r.log.entries)")
    // `.primary` is ⌘ on Apple and Ctrl elsewhere, the modifier the shortcuts below use.
    // Once recording ended the button's shortcut is live again (focus is nowhere; the item runs as a command).
    try await press(r, "k", .primary)
    #expect(r.log.entries.contains("command") || r.log.entries.contains("button"), "\(r.log.entries)")
}

/// **R14** Losing focus to another element (a press on the text field) cancels exactly once, then nothing more.
/// Mutation: drop the focus `onChange`; or call `onCancel` twice (focus loss and a window-resign path).
@Test @MainActor func focusMovingElsewhereCancelsOnce() async throws {
    let r = try await rig()
    try await startRecording(r)
    try r.w.click(r.w.elements(role: .textField)[0])
    try await settle(r.w)
    #expect(r.log.entries == ["cancel"], "\(r.log.entries)")
    try await settle(r.w)
    #expect(r.log.entries == ["cancel"], "still one: \(r.log.entries)")
}

/// **R15** The window resigning key while recording cancels exactly once and the recorder stops recording; becoming
/// key again records nothing and cancels nothing. Mutation: drop the `controlActiveState` `onChange`.
@Test @MainActor func theWindowResigningKeyCancelsOnce() async throws {
    let r = try await rig()
    try await startRecording(r)
    r.w.setControlActiveState(.inactive)
    try await settle(r.w)
    #expect(r.log.entries == ["cancel"], "\(r.log.entries)")
    #expect(!r.isRecording)
    r.w.setControlActiveState(.key)
    try await settle(r.w)
    #expect(r.log.entries == ["cancel"], "\(r.log.entries)")
}

/// **R16** An idle recorder never cancels: no recording, so a window resign or a focus elsewhere calls nothing.
/// Mutation: run `onCancel` on every focus change, not only recording's end.
@Test @MainActor func anIdleRecorderNeverCancels() async throws {
    let r = try await rig()
    r.w.window.focus(nil); r.w.tick()
    try await settle(r.w)
    r.w.setControlActiveState(.inactive); try await settle(r.w)
    r.w.setControlActiveState(.key); try await settle(r.w)
    try r.w.click(r.w.elements(role: .textField)[0])
    try await settle(r.w)
    #expect(r.log.entries.isEmpty, "\(r.log.entries)")
}

/// **R17** The first draw does not start a recording: the window's first-draw seat (`FC-E`) must not land on the
/// recorder, or a settings window would open swallowing ⌘Q. Mutation: build the recorder from
/// `.focusable(interactions: .edit)` (it is then the seat: the value reads "Press Shortcut" at open).
@Test @MainActor func theFirstDrawDoesNotStartARecording() async throws {
    let app = try TestApp(textSystem: harnessTextSystem)
    let log = RecLog()
    let w = try app.openWindow(size: sz(300, 200)) { VStack { RecHost(log: log, initial: nil) } }
    try await settle(w)
    #expect(try w.element(label: "Shortcut").value == "None" && log.entries.isEmpty)
    #expect(try w.element(label: "Shortcut").isFocused == false)
}

/// **R18** Accessibility: a button labelled "Shortcut" whose value is "None", the shortcut's display text, or "Press
/// Shortcut" while recording; an activate starts recording; `accessibilityLabel(_:)` replaces the label. Mutation:
/// drop the `.accessibilityAction`; or the value's "None".
@Test @MainActor func accessibilityRoleLabelValueAndActivate() async throws {
    let r = try await rig()
    var e = try r.recorder
    #expect(e.role == .button && e.label == "Shortcut" && e.value == "None", "\(e)")
    try r.w.performAccessibilityAction(.press, on: e)
    try await settle(r.w)
    e = try r.recorder
    #expect(e.value == "Press Shortcut" && e.isFocused, "\(e)")
    try await press(r, "p", [.shift, .command])
    e = try r.recorder
    #expect(e.value == KeyboardShortcut("p", modifiers: [.shift, .command]).displayText, "\(e)")
    #expect(r.log.entries.last == "record")
}

/// **R19** The displayed text is the shortcut's `displayText` on the platform the code runs on, and it spells the
/// recorded form for both families. Mutation: draw `shortcut.key.character` upper-cased instead of `displayText`.
@Test @MainActor func theDisplayedTextIsTheDisplayTextOfTheShortcut() async throws {
    let shortcut = KeyboardShortcut("p", modifiers: [.shift, .command])
    let r = try await rig(initial: shortcut)
    #expect(try r.recorder.value == shortcut.displayText)
    #expect(shortcut.displayText(for: .macOS) == "⇧⌘P")
    #expect(KeyboardShortcut("p", modifiers: [.shift, .control]).displayText(for: .linux) == "Ctrl+Shift+P")
    // The glyphs reach the scene: the window draws one glyph per character of the text (a shortcut's text, not the
    // placeholder).
    let placeholder = try await rig()
    #expect(r.w.allGlyphs.count != placeholder.w.allGlyphs.count)
}
