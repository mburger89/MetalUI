import Foundation
import MetalUI
import MetalUIPlatform
import MetalUIPortableText
import MetalUITesting
import Testing

// `SecureField` (rulings `SCF-A`…`SCF-H`, record 393). Portable: plain imports, the harness's Noto Sans through a
// recording text system, so a literal agrees on macOS, Linux and Windows. Every test names its mutation; each was run
// red and restored (record 393). **Instrument checks**: the glyph and clipboard tests run the same script on a plain
// `TextField` and assert the opposite, so a test that cannot tell a secure field from a plain one fails here.

/// A text system that logs every string handed to it, over the harness's.
@MainActor private final class RecordingTextSystem: TextSystem {
    let inner = harnessTextSystem()
    var seen: [String] = []

    func resolveFont(_ descriptor: FontDescriptor) -> FontKey { inner.resolveFont(descriptor) }
    func fontMetrics(_ font: FontKey) -> TextFontMetrics { inner.fontMetrics(font) }
    func measure(_ string: String, font: FontKey, wrappingAt width: Double?,
                 options: TextLayoutOptions) -> TextMeasurement {
        seen.append(string)
        return inner.measure(string, font: font, wrappingAt: width, options: options)
    }
    func placeGlyphs(_ string: String, font: FontKey, wrappingAt width: Double?, options: TextLayoutOptions,
                     origin: (x: Double, y: Double), scaleFactor: Float) -> [TextGlyph] {
        seen.append(string)
        return inner.placeGlyphs(string, font: font, wrappingAt: width, options: options, origin: origin,
                                 scaleFactor: scaleFactor)
    }
    func caretOffsets(_ string: String, font: FontKey) -> [Double] {
        seen.append(string)
        return inner.caretOffsets(string, font: font)
    }
    func lineRanges(_ string: String, font: FontKey, wrappingAt width: Double?,
                    options: TextLayoutOptions) -> [Range<Int>] {
        seen.append(string)
        return inner.lineRanges(string, font: font, wrappingAt: width, options: options)
    }
    func measure(_ text: StyledText, wrappingAt width: Double?, options: TextLayoutOptions) -> StyledTextMeasurement {
        seen.append(text.string)
        return inner.measure(text, wrappingAt: width, options: options)
    }
    func layOut(_ text: StyledText, wrappingAt width: Double?, options: TextLayoutOptions,
                origin: (x: Double, y: Double), scaleFactor: Float) -> StyledTextLayout {
        seen.append(text.string)
        return inner.layOut(text, wrappingAt: width, options: options, origin: origin, scaleFactor: scaleFactor)
    }
    func decorationMetrics(_ font: FontKey) -> TextDecorationMetrics { inner.decorationMetrics(font) }
    func rasterize(_ key: GlyphKey) -> GlyphImage { inner.rasterize(key) }
    func beginFrame() { inner.beginFrame() }
    func endFrame() { inner.endFrame() }
}

@MainActor private final class Box {
    var text = ""
    var other = ""
    var showsField = true
    var writes: [String] = []
    var redraw: (@MainActor () -> Void)?
    var binding: Binding<String> {
        Binding(get: { self.text }, set: { self.writes.append($0); self.text = $0 })
    }
    var otherBinding: Binding<String> { Binding(get: { self.other }, set: { self.other = $0 }) }
}

private let title = "Pass"

/// A window with a `SecureField` titled `Pass` (or, `secure: false`, a `TextField` of the same title) and a plain
/// `Mild` field to move focus to.
@MainActor private func secureWindow(_ box: Box, secure: Bool = true,
                                     system: RecordingTextSystem = RecordingTextSystem()) throws
    -> (TestWindow, RecordingTextSystem) {
    let window = try TestWindow(size: sz(400, 300), textSystem: { system }) {
        VStack(spacing: 8) {
            if box.showsField {
                if secure { SecureField(title, text: box.binding) } else { TextField(title, text: box.binding) }
            }
            TextField("Mild", text: box.otherBinding)
        }
    }
    box.redraw = { [weak window] in window?.window.setNeedsRedraw() }
    return (window, system)
}

@MainActor private func focusPass(_ window: TestWindow) throws { try window.focus(window.element(label: title)) }

@MainActor private func glyphSignature(_ window: TestWindow) -> [String] {
    window.allGlyphs.map { "\($0.bounds)" }
}

// MARK: Masking

/// 1 (`SCF-A`) — typing "hunter2" draws 7 glyphs that are all the one bullet, and no string containing a typed
/// character is ever given to the text system. **Instrument**: a `TextField` draws 7 distinct shapes and hands the
/// text system the text. **Mutation:** `TextField.shownText` returns `text` (the real text is drawn): reddens the
/// bullet shapes and the recorded strings.
@Test @MainActor func aSecureFieldDrawsOnlyBulletsAndNeverHandsTheTextToTheTextSystem() throws {
    let box = Box()
    let (window, system) = try secureWindow(box)
    try focusPass(window)
    window.typeText("hunter2")
    #expect(box.text == "hunter2")
    // The other field is empty and shows its placeholder; the secure field's glyphs are the ones left of 7 bullets.
    // 7 bullets plus the other field's placeholder "Mild" (4 letters), exactly the glyphs, in the same places, of a plain
    // field that holds seven bullets.
    #expect(window.allGlyphs.count == 11)
    let reference = try TestWindow(size: sz(400, 300), textSystem: harnessTextSystem) {
        VStack(spacing: 8) {
            TextField(title, text: .constant(String(repeating: "\u{2022}", count: 7)))
            TextField("Mild", text: .constant(""))
        }
    }
    #expect(glyphSignature(window) == glyphSignature(reference), "the secure field draws what seven bullets draw")
    let typed = Set("hunter2")   // none of its characters is in "Pass" or "Mild"
    #expect(system.seen.allSatisfy { string in !string.contains(where: { typed.contains($0) }) },
            "no string with a typed character reached the text system: \(system.seen.filter { $0.contains("h") })")

    // Instrument: the plain field draws its text.
    let plainBox = Box()
    let (plain, plainSystem) = try secureWindow(plainBox, secure: false)
    try focusPass(plain)
    plain.typeText("hunter2")
    #expect(glyphSignature(plain) != glyphSignature(reference), "instrument: a plain field draws other glyphs")
    #expect(plainSystem.seen.contains("hunter2"))
}

/// 2 (`SCF-F`) — the accessibility tree has a secure text field with 7 bullets, never the text, and no plain
/// text field for it. **Mutation:** `prepaint` publishes `value: text`.
@Test @MainActor func aSecureFieldPublishesItsRoleAndBulletsNeverItsText() throws {
    let box = Box()
    let (window, _) = try secureWindow(box)
    try focusPass(window)
    window.typeText("hunter2")
    let fields = try window.elements(role: .secureTextField)
    #expect(fields.count == 1)
    #expect(fields.first?.value == String(repeating: "\u{2022}", count: 7))
    #expect(try window.elements(role: .textField).count == 1, "only the Mild field is a plain text field")
    let published = try window.accessibilityTree.nodes.values.compactMap(\.value) + window.accessibilityTree.nodes.values.compactMap(\.label)
    #expect(!published.contains { $0.contains("hunter2") })
}

/// 3 (`SCF-A`) — the binding receives the real text, edit by edit, and a backspace edits it. **Mutation:**
/// `prepaint`'s `TextInputTarget` is given `shownText`: the next edit starts from bullets and writes them.
@Test @MainActor func theBindingWritesTheRealText() throws {
    let box = Box()
    let (window, _) = try secureWindow(box)
    try focusPass(window)
    window.typeText("hunter2")
    #expect(box.writes == ["h", "hu", "hun", "hunt", "hunte", "hunter", "hunter2"])
    window.typeKey(.delete)
    #expect(box.text == "hunter")
}

// MARK: Clipboard

/// 4 (`SCF-C`) — select all and ⌘C leave the clipboard as it was, ⌘X cuts nothing, and the text stays. **Instrument**: the
/// same keys on a `TextField` copy and cut. **Mutation:** delete the `case "c" where secure, "x" where secure` arm of
/// `TextEditing.key`.
@Test @MainActor func copyAndCutDoNothingInASecureField() throws {
    let box = Box()
    let (window, _) = try secureWindow(box)
    window.setClipboard(text: "sentinel")
    try focusPass(window)
    window.typeText("hunter2")
    window.typeKey("a", modifierFlags: .primary)
    window.typeKey("c", modifierFlags: .primary)
    #expect(window.platformWindow.clipboard == "sentinel")
    window.typeKey("x", modifierFlags: .primary)
    #expect(window.platformWindow.clipboard == "sentinel")
    #expect(box.text == "hunter2", "a cut removed nothing")

    let plainBox = Box()
    let (plain, _) = try secureWindow(plainBox, secure: false)
    plain.setClipboard(text: "sentinel")
    try focusPass(plain)
    plain.typeText("hunter2")
    plain.typeKey("a", modifierFlags: .primary)
    plain.typeKey("c", modifierFlags: .primary)
    #expect(plain.platformWindow.clipboard == "hunter2", "instrument: a plain field copies")
}

/// 5 (`SCF-C`) — ⌘V inserts at the caret, and over a selection replaces it. **Mutation:** the secure arm returns before
/// the paste case too (`case "v" where secure`).
@Test @MainActor func pasteInsertsIntoASecureField() throws {
    let box = Box()
    let (window, _) = try secureWindow(box)
    try focusPass(window)
    window.typeText("ab")
    window.setClipboard(text: "XY")
    window.typeKey("v", modifierFlags: .primary)
    #expect(box.text == "abXY")
    window.typeKey("a", modifierFlags: .primary)
    window.typeKey("v", modifierFlags: .primary)
    #expect(box.text == "XY")
}

// MARK: Graphemes

/// 6 (`SCF-A`) — "a👨‍👩‍👧b" is 3 graphemes (and 10 UTF-16 units): 3 bullets, Left moves over the whole family emoji and
/// Backspace deletes it whole. **Mutation:** `mask` counts `text.utf16.count` (10 bullets).
@Test @MainActor func theCaretMovesByGraphemeOverBullets() throws {
    let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}"
    let box = Box()
    let (window, _) = try secureWindow(box)
    try focusPass(window)
    window.typeText("a\(family)b")
    #expect(box.text.count == 3 && box.text.utf16.count == 10)
    #expect(try window.elements(role: .secureTextField).first?.value == "\u{2022}\u{2022}\u{2022}")
    window.typeKey(.end)
    window.typeKey(.leftArrow)
    window.typeKey(.leftArrow)
    window.typeText("X")
    #expect(box.text == "aX\(family)b", "two lefts from the end sit after the 'a': the second crossed the family whole")
    window.typeKey(.end)
    window.typeKey(.leftArrow)
    window.typeKey(.delete)
    #expect(box.text == "aXb", "one backspace removed the whole family")
}

// MARK: Input method

/// 7 (`SCF-E`) — marked text is ignored: nothing is marked, the bullets do not grow, the binding is untouched, and there
/// is nothing to commit. **Instrument**: a `TextField` shows it. **Mutation:** delete the `if target.secure { return true }`
/// line in `Window`'s `.textComposition` case.
@Test @MainActor func markedTextIsIgnoredInASecureField() throws {
    let box = Box()
    let (window, _) = try secureWindow(box)
    try focusPass(window)
    window.typeText("ab")
    let before = window.allGlyphs.count
    #expect(window.setMarkedText("ni"))
    #expect(window.markedText == "")
    #expect(window.allGlyphs.count == before)
    #expect(!window.commitMarkedText(), "nothing is marked to commit")
    #expect(box.text == "ab")

    let plainBox = Box()
    let (plain, _) = try secureWindow(plainBox, secure: false)
    try focusPass(plain)
    plain.typeText("ab")
    plain.setMarkedText("ni")
    #expect(plain.markedText == "ni", "instrument: a plain field composes")
}

/// 8 (`SCF-D`) — the word key sees one word, so ⌥← (⌃← off a Mac) goes to the start and never to a word boundary.
/// **Mutation:** the word keys read `characters` instead of `wordCharacters`.
@Test @MainActor func wordMovementNeverRevealsWhereTheWordsAre() throws {
    let box = Box()
    let (window, _) = try secureWindow(box)
    try focusPass(window)
    window.typeText("foo bar")
    #if os(macOS)
    window.typeKey(.leftArrow, modifierFlags: .option)
    #else
    window.typeKey(.leftArrow, modifierFlags: .control)
    #endif
    window.typeText("X")
    #expect(box.text == "Xfoo bar")
}

// MARK: Secure keyboard entry

/// 9 (`SCF-B`) — focus enters: one enable; focus moves to another field: one disable; back and the window closes: one
/// more enable and one more disable. **Mutation:** delete `runDisappearancesForClose`'s `syncSecureTextInput()` line (the
/// close leaves the hold on).
@Test @MainActor func secureInputIsBalancedAcrossFocusBlurAndWindowClose() throws {
    let box = Box()
    let (window, _) = try secureWindow(box)
    #expect(window.platformWindow.secureTextInputRequests == [])
    try focusPass(window)
    #expect(window.platformWindow.secureTextInputRequests == [true])
    try window.focus(window.element(label: "Mild"))
    #expect(window.platformWindow.secureTextInputRequests == [true, false])
    try focusPass(window)
    window.close()
    #expect(window.platformWindow.secureTextInputRequests == [true, false, true, false])
}

/// 10 (`SCF-B`) — removing the focused field releases the hold. **Mutation:** `syncSecureTextInput` keeps a sent
/// hold while anything is focused (`wanted = … || (sentSecureTextInput && focusedElement != nil)`).
@Test @MainActor func removingTheFocusedSecureFieldReleasesSecureInput() throws {
    let box = Box()
    let (window, _) = try secureWindow(box)
    try focusPass(window)
    #expect(window.platformWindow.secureTextInputRequests == [true])
    box.showsField = false
    box.redraw?()
    window.tick()
    #expect(window.platformWindow.secureTextInputRequests == [true, false])
}

// MARK: Steady frame

/// 11 (`SCF-B`) — a window with no `SecureField` never talks to the secure-input hook and its frame work is what it was
/// before the field existed: the typing script's summed `elementRequests` is the literal measured on this branch's tip, which
/// has no secure field in the tree to cost it anything. **Mutation:** drop `syncSecureTextInput`'s `guard wanted != sentSecureTextInput`: a request per frame.
@Test @MainActor func aWindowWithoutASecureFieldKeepsItsFrameWorkAndSendsNothing() async throws {
    let box = Box()
    let (window, _) = try secureWindow(box, secure: false)
    try focusPass(window)
    window.typeText("abc")
    window.typeKey("a", modifierFlags: .primary)
    window.typeKey("c", modifierFlags: .primary)
    try await window.runUntilIdle()
    #expect(window.platformWindow.secureTextInputRequests == [])
    let requests = window.frameWork.reduce(0) { $0 + $1.elementRequests }
    #expect(requests == 10, "\(requests) element requests over \(window.frameWork.count) frames")
}
