import Foundation
import MetalUITesting
import MetalUIPlatform
import MetalUITerminal
import Testing
@testable import MetalUI
@testable import MetalUITerminalUI

// Terminal phase 5.4 (`TRM-BC`): keys, committed and marked text, paste and focus, headless on `TermRig`. Each test
// names the mutation it was shown red against (`docs/practices/verifying-tests-can-fail.md`).

private func esc(_ s: String) -> [UInt8] { [0x1B] + Array(s.utf8) }

extension TermRig {
    /// The terminal has the focus (the root's first draw may have seated another focusable).
    func focusTerminal() async {
        let order = window.window.lastFocusRegistry.tabOrder
        if let last = order.last { window.window.focus(last) }
        await settle()
        log.inputs = []
    }

    /// One key, delivered the way the platform does: text as `.textInput`, anything else a key down; then a frame.
    func key(_ characters: String, _ modifiers: Modifiers = [], ignoring: String? = nil, keypad: Bool = false) {
        var event = KeyEvent(charactersIgnoringModifiers: ignoring ?? characters, characters: characters,
                             modifiers: modifiers, timestamp: 0)
        event.isKeypad = keypad
        window.send(.keyDown(event))
        window.tick()
    }

    func typed(_ text: String) {
        window.send(.textInput(text))
        window.tick()
    }

    var sent: [[UInt8]] { log.inputs }
    var sentBytes: [UInt8] { log.inputs.flatMap { $0 } }
    func feedModes(_ sequence: String) async { feed(sequence); await settle(); log.inputs = [] }
}

private let up = "\u{F700}", down = "\u{F701}", left = "\u{F702}", right = "\u{F703}", f1 = "\u{F704}", f5 = "\u{F708}"

/// **1** (`REQUIRED`) The matrix: a key press arrives as the bytes the encoder gives it with the view's current modes,
/// once. Letters (as text), Ctrl+C, arrows in normal and application cursor mode, Option+letter with option-as-meta on
/// and off, the keypad in application keypad mode, F-keys, Shift+Tab, Return, Escape, Backspace.
/// Mutation: encode with `TerminalModes()` instead of the current modes (arrows and keypad rows fail); call `onInput`
/// twice per key (every row fails).
@MainActor @Test func aKeyPressIsEncodedWithTheCurrentModesAndSentOnce() async throws {
    let rig = try TermRig()
    await rig.settle()
    await rig.focusTerminal()
    func expect(_ name: String, _ bytes: [UInt8], _ send: () -> Void, line: UInt = #line) {
        rig.log.inputs = []
        send()
        #expect(rig.sent == [bytes], "\(name): \(rig.sent)")
    }
    expect("a", [0x61], { rig.typed("a") })
    expect("A", [0x41], { rig.typed("A") })
    expect("^C", [0x03], { rig.key("c", .control) })
    expect("up", esc("[A"), { rig.key(up) })
    expect("left", esc("[D"), { rig.key(left) })
    expect("F1", esc("OP"), { rig.key(f1) })
    expect("F5", esc("[15~"), { rig.key(f5) })
    expect("shift-tab", esc("[Z"), { rig.key("\t", .shift) })
    expect("return", [0x0D], { rig.key("\r") })
    expect("escape", [0x1B], { rig.key("\u{1B}") })
    expect("backspace", [0x7F], { rig.key("\u{7F}") })
    expect("option-f, composed", Array("ƒ".utf8), { rig.key("ƒ", .option, ignoring: "f") })   // as the platform composed it
    rig.knobs.optionAsMeta = false
    await rig.feedModes("\u{1B}[?1h")   // DECCKM
    expect("up (application)", esc("OA"), { rig.key(up) })
    expect("shift-up (application)", esc("[1;2A"), { rig.key(up, .shift) })
    await rig.feedModes("\u{1B}[?1l")
    expect("up again", esc("[A"), { rig.key(up) })
    // Keypad: ordinary without DECKPAM, SS3 with it.
    expect("keypad 5", [0x35], { rig.key("5", keypad: true) })
    await rig.feedModes("\u{1B}=")
    expect("keypad 5 (application)", esc("Ou"), { rig.key("5", keypad: true) })
    expect("keypad enter (application)", esc("OM"), { rig.key("\r", keypad: true) })
    expect("main-row 5 is not keypad", [0x35], { rig.key("5") })
    await rig.feedModes("\u{1B}>")
}

/// **2** Option-as-meta: with it on, Option+letter is ESC and the letter; off, the encoder sends the composed text.
/// Mutation: ignore `optionAsMeta` (pass false).
@MainActor @Test func optionAsMetaPrefixesEscape() async throws {
    let rig = try TermRig()
    await rig.settle()
    await rig.focusTerminal()
    rig.key("f", .option)
    #expect(rig.sent == [[0x66]], "off: the characters, no prefix: \(rig.sent)")
    rig.knobs.optionAsMeta = true
    rig.window.window.setNeedsRedraw()
    await rig.settle()
    rig.log.inputs = []
    rig.key("f", .option)
    rig.key("B", [.option, .shift], ignoring: "b")
    #expect(rig.sent == [esc("f"), esc("B")], "\(rig.sent)")
    #expect(rig.window.platformWindow.rawOptionKeyRequests.last == true, "the platform is hinted while the view is focused with it on")
}

/// **3** Command keys are not consumed: ⌘K runs a `CommandMenu` action and sends nothing; ⌘Q and a plain ⌘C send nothing
/// and are not handled by the view (they reach the app). Mutation: answer `.handled` for an empty encoding.
@MainActor @Test func commandKeysFallThroughToTheApp() async throws {
    let rig = try TermRig(commands: true)
    await rig.settle()
    await rig.focusTerminal()
    rig.key("k", .command)
    #expect(rig.log.commands == ["go"], "the command ran: \(rig.log.commands)")
    #expect(rig.sent.isEmpty, "nothing was sent: \(rig.sent)")
    let handled = rig.window.send(.keyDown(KeyEvent(charactersIgnoringModifiers: "q", characters: "q", modifiers: .command, timestamp: 0)))
    #expect(!handled && rig.sent.isEmpty, "⌘Q is not consumed: handled \(handled)")
    rig.key("k")   // plain k is the terminal's again
    #expect(rig.sent == [[0x6B]], "\(rig.sent)")
}

/// **4** `keyCaptureExceptions` are honoured: an excepted key skips capture and reaches the app's command, an
/// unlisted one is encoded. Mutation: pass `[]` to `keyCapture(except:)`.
@MainActor @Test func keyCaptureExceptionsReachTheApp() async throws {
    let rig = try TermRig(commands: true)
    rig.knobs.exceptions = [KeyboardShortcut("k", modifiers: [.control])]
    rig.window.window.setNeedsRedraw()
    await rig.settle()
    await rig.focusTerminal()
    // `.keyboardShortcut("k")` is the primary modifier: use it for the command, Control+K as the excepted key.
    rig.key("k", .control)
    #expect(rig.sent.isEmpty, "the excepted Control+K never reached the terminal's encoder: \(rig.sent)")
    rig.key("c", .control)
    #expect(rig.sent == [[0x03]], "an unlisted key is still captured: \(rig.sent)")
}

/// **5** Committed text (an input method's commit, a dead key's result, the emoji picker) is sent once, UTF-8 encoded;
/// marked text is not sent, is drawn at the cursor over its cells (wide characters take two), and ends on commit.
/// Mutation: send the composition as it changes (the marked-text assertions fail); also draw it nowhere
/// (`markedDraws` stays 0).
@MainActor @Test func markedTextIsDrawnAtTheCursorAndOnlyTheCommitIsSent() async throws {
    let rig = try TermRig()
    await rig.settle()
    await rig.focusTerminal()
    rig.feed("ab")
    await rig.settle()
    #expect(rig.window.setMarkedText("にほ"))
    await rig.frame(); await rig.frame()
    #expect(rig.sent.isEmpty, "marked text is not sent: \(rig.sent)")
    #expect(rig.window.markedText == "にほ")
    #expect(rig.model.statistics.lastMarkedColumns == 2..<6, "two wide characters from the cursor column: \(String(describing: rig.model.statistics.lastMarkedColumns))")
    #expect(rig.model.statistics.markedDraws >= 1)
    // Keys while composing belong to the input method: nothing is captured.
    rig.key(left)
    #expect(rig.sent.isEmpty, "a key while composing is the input method's: \(rig.sent)")
    #expect(rig.window.commitMarkedText("日本"))
    await rig.frame()
    #expect(rig.sent == [Array("日本".utf8)], "sent once, UTF-8: \(rig.sent)")
    #expect(rig.window.markedText == "")
    let drawn = rig.model.statistics.markedDraws
    await rig.frame()
    #expect(rig.model.statistics.markedDraws == drawn, "the marked text is gone from the next draw")
    // Cancel sends nothing.
    rig.log.inputs = []
    #expect(rig.window.setMarkedText("か"))
    #expect(rig.window.cancelMarkedText())
    await rig.frame()
    #expect(rig.sent.isEmpty)
    // A dead-key result and an emoji arrive as text.
    rig.typed("é"); rig.typed("👍🏽")
    #expect(rig.sent == [Array("é".utf8), Array("👍🏽".utf8)], "\(rig.sent)")
}

/// **6** The input method is positioned at the cursor cell: the area is the cursor's cell, two cells for a wide
/// character, the marked text's width while composing, and it follows output without a rebuild.
/// Mutation: report the zero rect (`caret` returns nil).
@MainActor @Test func theInputMethodAreaFollowsTheCursor() async throws {
    let rig = try TermRig()
    await rig.settle()
    await rig.focusTerminal()
    let cell = try #require(rig.model.cellSize)
    func area() throws -> Bounds<Pixels> { try #require(rig.window.platformWindow.textInputAreas.last ?? nil) }
    let origin = try #require(rig.model.bounds).origin
    var a = try area()
    #expect(abs(Double(a.origin.x.value - origin.x.value)) < 0.01 && abs(Double(a.size.width.value) - cell.width) < 0.01, "\(a)")
    rig.feed("abc")
    await rig.frame()
    let builds = rig.window.lastFrameWork.builds
    a = try area()
    #expect(builds == 0, "the area moved on a surface-only frame")
    #expect(abs(Double(a.origin.x.value - origin.x.value) - 3 * cell.width) < 0.01, "three cells in: \(a)")
    rig.feed("\r\n日")
    await rig.frame()
    rig.feed("\u{1B}[1;1H\u{1B}[2;1H")   // the cursor back onto the wide character's row, column 0
    await rig.frame()
    a = try area()
    #expect(abs(Double(a.size.width.value) - 2 * cell.width) < 0.01, "a wide character is two cells: \(a)")
    #expect(abs(Double(a.origin.y.value - origin.y.value) - cell.height) < 0.01, "second row: \(a)")
    #expect(rig.window.setMarkedText("にほん"))
    await rig.frame()
    a = try area()
    #expect(abs(Double(a.size.width.value) - 6 * cell.width) < 0.01, "the marked text's width: \(a)")
}

/// **7** Paste: ⌘V (primary) on Apple platforms or Ctrl+Shift+V elsewhere sends the clipboard through `encodePaste`:
/// plain with mode 2004 off, bracketed with it on, every ESC stripped; Edit ▸ Paste is enabled while it is focused;
/// off Apple Ctrl+V is the child's own (0x16). Mutation: send the raw text (the ESC is not stripped).
@MainActor @Test func pasteIsEncodedAndBracketedWhenAsked() async throws {
    let rig = try TermRig()
    await rig.settle()
    await rig.focusTerminal()
    let chord: Modifiers = Modifiers.primary == .command ? .command : [.control, .shift]
    let letter = Modifiers.primary == .command ? "v" : "V"
    #expect(rig.window.window.chainClipboardCommands.contains(.paste), "Edit ▸ Paste is live while the terminal is focused")
    _ = rig.window.window.clipboard.write("one\ntwo\u{1B}[31m")
    rig.key(letter, chord, ignoring: "v")
    #expect(rig.sent == [Array("one\ntwo[31m".utf8)], "\(rig.sent)")
    await rig.feedModes("\u{1B}[?2004h")
    rig.key(letter, chord, ignoring: "v")
    #expect(rig.sentBytes == esc("[200~") + Array("one\ntwo[31m".utf8) + esc("[201~"), "\(rig.sentBytes)")
    if Modifiers.primary != .command {
        rig.log.inputs = []
        rig.key("v", .control)
        #expect(rig.sent == [[0x16]], "Ctrl+V is the child's: \(rig.sent)")
    }
}

/// **8** Focus: `ESC [ I` and `ESC [ O` are sent on focus in and out while mode 1004 is on, and nothing with it off;
/// an inactive window reports out. Mutation: send regardless of the mode.
@MainActor @Test func focusEventsAreSentOnlyWithMode1004() async throws {
    let rig = try TermRig(extra: true)
    await rig.settle()
    await rig.focusTerminal()
    rig.window.window.focus(nil)
    await rig.settle()
    rig.window.window.focus(rig.window.window.lastFocusRegistry.tabOrder.last)
    await rig.settle()
    #expect(rig.sent.isEmpty, "mode off: nothing: \(rig.sent)")
    await rig.feedModes("\u{1B}[?1004h")
    rig.window.window.focus(nil)
    await rig.settle()
    #expect(rig.sent == [esc("[O")], "\(rig.sent)")
    rig.window.window.focus(rig.window.window.lastFocusRegistry.tabOrder.last)
    await rig.settle()
    #expect(rig.sent == [esc("[O"), esc("[I")], "\(rig.sent)")
    rig.window.setControlActiveState(.inactive)
    await rig.settle()
    #expect(rig.sent.last == esc("[O"), "\(rig.sent)")
}

/// **9** Input restarts the blink's idle clock: a blinking cursor that stopped after 30 s idle blinks again after a
/// keystroke, a paste or a committed text. Mutation: `send` does not call `noteActivity`.
@MainActor @Test func inputRestartsTheBlinkIdleClock() async throws {
    let rig = try TermRig()
    await rig.settle()
    await rig.focusTerminal()
    rig.feed("\u{1B}[1 q")
    await rig.settle()
    for _ in 0..<70 { await rig.frame(0.5) }   // past the idle limit: solid, nothing scheduled
    #expect(rig.window.window.testingSurfaceDeadlineCount == 0, "idle: no timer")
    let idleDraws = rig.window.surfaceDrawCount
    for _ in 0..<10 { await rig.frame(0.25) }
    #expect(rig.window.surfaceDrawCount == idleDraws, "idle: no draws")
    rig.typed("x")
    let afterKey = rig.window.surfaceDrawCount
    for _ in 0..<12 { await rig.frame(0.1) }
    #expect(rig.window.surfaceDrawCount >= afterKey + 2, "a keystroke restarts the blink: \(rig.window.surfaceDrawCount - afterKey) draws in 1.2 s")
}

/// **10** (`REQUIRED`, cost) A keystroke into a focused view whose output then arrives: the keystroke's own frame
/// costs what any rebuilt frame of this window costs (2 element requests, the view's own, `TRM-BA` item 8), and the
/// output that follows is a surface-only frame of 0 builds and 0 element requests. Mutation: the input handler
/// requests a build per output (builds 1).
@MainActor @Test func aKeystrokeAndItsOutputCostNoElementRequestsBeyondTheSteadyFrame() async throws {
    let rig = try TermRig()
    await rig.settle()
    await rig.focusTerminal()
    rig.window.window.setNeedsRedraw(); rig.window.tick()
    let steady = rig.window.lastFrameWork.elementRequests
    rig.typed("a")
    let keystroke = rig.window.lastFrameWork
    #expect(rig.sent == [[0x61]])
    #expect(keystroke.elementRequests == steady, "the keystroke frame \(keystroke.elementRequests) vs a plain redraw \(steady)")
    #expect(steady == 6, "the view's own six requests (two, and four pointer wrappers, TRM-BD): \(steady)")
    rig.feed("a")
    await rig.frame()
    let output = rig.window.lastFrameWork
    #expect(output.builds == 0 && output.elementRequests == 0 && output.surfaceOnlyFrames == 1,
            "\(output.builds) \(output.elementRequests) \(output.surfaceOnlyFrames)")
}

/// **11** (`REQUIRED`, cost) An editor keystroke in a window that also holds a terminal costs what it did before
/// the terminal had input wiring: literal, measured on master `8790e4d9`. Mutation: `TerminalView` adds an element.
@MainActor @Test func anEditorKeystrokeIsUnaffectedByTheTerminalsInputWiring() async throws {
    let rig = try TermRig(extra: true)
    await rig.settle()
    let editor = try rig.window.element(identifier: "ed")
    try rig.window.focus(editor)
    await rig.settle()
    for _ in 0..<2 { rig.window.window.setNeedsRedraw(); rig.window.tick() }
    rig.window.typeText("z")
    let work = rig.window.lastFrameWork
    #expect(rig.sent.isEmpty, "the terminal heard nothing")
    #expect(work.elementRequests == 8 && work.builds == 1, "\(work.elementRequests) requests, \(work.builds) builds")
}

/// **12** The `KeyPress` overload is the core encoder over the press spelled as a `TerminalKey`: modifiers, the key
/// and the keypad flag carry over, and a Command press is `[]`. Mutation: drop the keypad flag (the keypad row fails)
/// or map Option to Control.
@MainActor @Test func theKeyPressOverloadForwardsToTheCoreEncoder() {
    let modes: TerminalModes = {
        var m = TerminalModes()
        m.applicationKeypad = true
        return m
    }()
    func press(_ key: Character, _ characters: String, _ mods: Modifiers, keypad: Bool = false) -> KeyPress {
        KeyPress(phase: .down, key: KeyEquivalent(key), characters: characters, modifiers: mods, isKeypad: keypad)
    }
    #expect(TerminalEncoder.encodeKey(press("c", "\u{3}", .control), modes: modes, optionAsMeta: false) == [0x03])
    #expect(TerminalEncoder.encodeKey(press("f", "ƒ", .option), modes: modes, optionAsMeta: true) == esc("f"))
    #expect(TerminalEncoder.encodeKey(press("f", "ƒ", .option), modes: modes, optionAsMeta: false) == Array("ƒ".utf8))
    #expect(TerminalEncoder.encodeKey(press("7", "7", [], keypad: true), modes: modes, optionAsMeta: false) == esc("Ow"))
    #expect(TerminalEncoder.encodeKey(press("7", "7", []), modes: modes, optionAsMeta: false) == [0x37])
    #expect(TerminalEncoder.encodeKey(press("k", "k", .command), modes: modes, optionAsMeta: true) == [])
    #expect(TerminalEncoder.encodeKey(press("\u{F700}", "", [.shift, .control]), modes: modes, optionAsMeta: false) == esc("[1;6A"))
}

/// **13** Marked text laid over a row (`TerminalRow.overlaying`) covers the cells from the column, two per wide
/// character, clipped at the last column, and draws glyphs and an underline the plain row does not: the recorded
/// instances grow by the glyphs plus at least one rect. Mutation: lay the text over one cell per character
/// (the covered columns fail).
@MainActor @Test func markedTextOverlayCoversTheCellsAndDrawsUnderlined() throws {
    let base = try #require(terminalRows("ab").first)
    var underline = TerminalAttributes()
    underline.underlineStyle = .single
    let (row, covered, caret) = base.overlaying("にほ", at: 2, attributes: underline, caretCharacter: 1)
    #expect(covered == 2..<6 && caret == 4, "\(covered) \(caret)")
    #expect(row.text.hasPrefix("abにほ"), "\(row.text)")
    let (clipped, clippedCovered, _) = base.overlaying("にほ", at: 79, attributes: underline)
    #expect(clippedCovered == 79..<79 && !clipped.text.contains("に"), "a wide character that does not fit is dropped")
    let (painter, _) = notoPainter()
    let plain = makeSink(), over = makeSink()
    painter.draw(base, at: 0, columns: 80, origin: (0, 0), into: plain)
    painter.draw(row, at: 0, columns: 80, origin: (0, 0), into: over)
    #expect(over.glyphs.count >= plain.glyphs.count + 3, "two glyphs and an underline rect: \(plain.glyphs.count) -> \(over.glyphs.count)")
}
