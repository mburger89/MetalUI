import Foundation
import MetalUI
import MetalUIPlatform
import MetalUITesting
import Testing

// Alloy gaps G11 (the caret bug) and its macOS 14 selection API (ruling `SL-P`, `SL-Q`; record 241).
// A focused `TextField`/`TextEditor` whose bound text is replaced from outside moves its caret to the
// END, as SwiftUI's do (probe `docs/probes/swiftui-text-external-replace.swift`, recorded in `SL-P`), so
// the next typed key lands after the replacement ("/compact X", not "/comXpact "). With a selection
// binding attached the binding wins and the old offset stays, clamped (the probe's `BF-`/`BE-` arms).
// PLAIN imports, public API; the selection binding used is the macOS 14 `selectedOffsets` one, so no
// availability gate stands in these tests.

@MainActor private final class ExtModel {
    var text: String { didSet { redraw?() } }
    var offsets: Range<Int>? { didSet { redraw?() } }
    var published: [Range<Int>?] = []
    var redraw: (@MainActor () -> Void)?
    init(_ text: String) { self.text = text }
    var textBinding: Binding<String> { Binding(get: { self.text }, set: { self.text = $0 }) }
    var offsetsBinding: Binding<Range<Int>?> {
        Binding(get: { self.offsets }, set: { self.published.append($0); self.offsets = $0 })
    }
}

/// Which element, and whether it carries a selection binding.
private enum Kind: String, CaseIterable, Sendable, CustomTestStringConvertible {
    case field, editor, boundField, boundEditor
    var testDescription: String { rawValue }
    var isEditor: Bool { self == .editor || self == .boundEditor }
    var isBound: Bool { self == .boundField || self == .boundEditor }
}

@MainActor private func window(_ model: ExtModel, _ kind: Kind) throws -> TestWindow {
    let window: TestWindow
    switch kind {
    case .field: window = try harnessWindow { TextField("Title", text: model.textBinding) }
    case .editor: window = try harnessWindow { TextEditor("Title", text: model.textBinding) }
    case .boundField:
        window = try harnessWindow { TextField("Title", text: model.textBinding, selectedOffsets: model.offsetsBinding) }
    case .boundEditor:
        window = try harnessWindow { TextEditor("Title", text: model.textBinding, selectedOffsets: model.offsetsBinding) }
    }
    model.redraw = { [unowned window] in window.window.setNeedsRedraw() }
    try window.focus(window.element(label: "Title"))
    return window
}

/// Focus, then the caret at `offset`: End, then Left for the rest.
@MainActor private func place(_ window: TestWindow, caret offset: Int, of count: Int) {
    window.typeKey(.end)
    for _ in 0..<(count - offset) { window.typeKey(.leftArrow) }
}

private struct Replacement: CustomTestStringConvertible, Sendable {
    var name: String, initial: String, caret: Int, new: String
    /// What SwiftUI's field gives after the replacement and one typed X (probe arms F-/E-, identical across both).
    var swiftUI: String
    /// What the old offset gives: X inserted at `min(caret, new.count)` (the probe's bound arms).
    var stale: String {
        let characters = Array(new), at = min(caret, characters.count)
        return String(characters[..<at]) + "X" + String(characters[at...])
    }
    var testDescription: String { name }
    static let all: [Replacement] = [
        .init(name: "extend at the caret (autocomplete)", initial: "/com", caret: 4, new: "/compact ", swiftUI: "/compact X"),
        .init(name: "extend at a mid caret", initial: "ab cd", caret: 2, new: "abXY cd", swiftUI: "abXY cdX"),
        .init(name: "rewrite earlier text, same length", initial: "foo bar", caret: 7, new: "FOO bar", swiftUI: "FOO barX"),
        .init(name: "rewrite earlier text under a mid caret", initial: "foo bar", caret: 3, new: "goo bar", swiftUI: "goo barX"),
        .init(name: "insert before the caret", initial: "foo bar", caret: 7, new: "AAfoo bar", swiftUI: "AAfoo barX"),
        .init(name: "append under a mid caret (an @path mention)", initial: "foo bar", caret: 3, new: "foo bar @path", swiftUI: "foo bar @pathX"),
        .init(name: "append at the end", initial: "foo bar", caret: 7, new: "foo bar @path", swiftUI: "foo bar @pathX"),
        .init(name: "shrink with the caret at the end", initial: "hello world", caret: 11, new: "hello", swiftUI: "helloX"),
        .init(name: "shrink past a mid caret", initial: "hello world", caret: 8, new: "hel", swiftUI: "helX"),
        .init(name: "shrink with the caret inside the kept text", initial: "hello world", caret: 2, new: "hello", swiftUI: "helloX"),
        .init(name: "identical text keeps the caret", initial: "hello", caret: 2, new: "hello", swiftUI: "heXllo"),
        .init(name: "cleared", initial: "hello", caret: 3, new: "", swiftUI: "X"),
        .init(name: "unrelated and longer", initial: "abc", caret: 1, new: "completely different", swiftUI: "completely differentX"),
    ]
}

/// 1 — **each probe case**: replace the focused field's text from outside, type X, and the text is
/// SwiftUI's, for both the field and the editor (the probe's `F-`/`E-` arms). **Mutation:** in
/// `TextEditing.followExternalText` return before moving the caret (the old behaviour: X lands at
/// the old offset) — every row but the identical one reddens, for both kinds.
@Test(arguments: Replacement.all, [Kind.field, Kind.editor]) @MainActor
private func aReplacedTextPutsTheCaretWhereSwiftUIPutsIt(_ c: Replacement, kind: Kind) throws {
    let model = ExtModel(c.initial)
    let window = try window(model, kind)
    place(window, caret: c.caret, of: c.initial.count)
    model.text = c.new
    window.tick()
    window.typeText("X")
    #expect(model.text == c.swiftUI)
}

/// 2 — **a selection binding wins** (the probe's `BF-`/`BE-` arms): the old offset is kept, clamped to
/// the new text, because the binding still says so. **Mutation:** run `followExternalText` for a bound
/// field too (the `else` of `bound` dropped) — the cases whose caret is not at the end redden.
@Test(arguments: Replacement.all, [Kind.boundField, Kind.boundEditor]) @MainActor
private func aSelectionBindingKeepsTheOldOffsetAcrossAReplacement(_ c: Replacement, kind: Kind) throws {
    let model = ExtModel(c.initial)
    let window = try window(model, kind)
    place(window, caret: c.caret, of: c.initial.count)
    #expect(model.offsets == c.caret..<c.caret, "the binding read the placed caret")
    model.text = c.new
    window.tick()
    window.typeText("X")
    #expect(model.text == c.stale)
}

/// 3 — an edit of the field's own is not a replacement: typing, then undo, then typing again never
/// jumps the caret to the end. **Mutation:** drop `state.seenText = newText` from `recording`
/// (typing mid-text then jumps to the end on the next frame).
@Test(arguments: [Kind.field, Kind.editor]) @MainActor
private func theFieldsOwnEditsNeverMoveTheCaretToTheEnd(kind: Kind) throws {
    let model = ExtModel("hello")
    let window = try window(model, kind)
    place(window, caret: 2, of: 5)
    window.typeText("X")
    window.typeText("Y")
    #expect(model.text == "heXYllo")
    window.typeKey("z", modifierFlags: .primary)
    window.typeText("Z")
    #expect(model.text == "heZllo", "undo took both typed keys back (one group) and the caret stays at 2, not the end")
}

/// 4 — two replacements in a row, with no keystroke between, each one moves the caret to the end of
/// its own text (an `@path` appended twice). **Mutation:** keep `seenText` at its first value.
@Test(arguments: [Kind.field, Kind.editor]) @MainActor
private func consecutiveReplacementsEachMoveTheCaret(kind: Kind) throws {
    let model = ExtModel("ab")
    let window = try window(model, kind)
    place(window, caret: 1, of: 2)
    model.text = "ab @one"
    window.tick()
    window.typeKey(.leftArrow)
    window.typeKey(.leftArrow)
    model.text = "ab @one @two"
    window.tick()
    window.typeText("X")
    #expect(model.text == "ab @one @twoX")
}

// MARK: G11 — the selection binding on macOS 14

/// 5 — **the offsets binding reads and writes the caret and the selection** with no availability gate
/// (`TextSelection` is `RangeSet`'s, macOS 15; `Range<Int>` is not): a typed key publishes the caret
/// after it, a write moves the caret on the next frame, a range selects, a stale range clamps. The test
/// is written with no `@available`, so it does not compile unless the initialisers are available at the
/// deployment target (macOS 14), and `theOffsetsInitialisersCarryNoAvailabilityGate` greps the source.
/// **Mutation:** in `reconcile` drop the `Range<Int>` branch (every write then does nothing).
@Test(arguments: [Kind.boundField, Kind.boundEditor]) @MainActor
private func theOffsetsBindingReadsAndWritesTheCaretAndTheSelection(kind: Kind) throws {
    let model = ExtModel("hello")
    let window = try window(model, kind)
    place(window, caret: 5, of: 5)
    #expect(model.offsets == 5..<5)
    window.typeText("!")
    #expect(model.text == "hello!")
    #expect(model.offsets == 6..<6, "typing published the caret after the insertion")

    model.offsets = 2..<2
    window.tick()
    window.typeText("X")
    #expect(model.text == "heXllo!", "a caret written from code was applied on the next frame")
    #expect(model.offsets == 3..<3)

    model.offsets = 1..<4
    window.tick()
    window.typeText("Y")
    #expect(model.text == "hYlo!", "a written range is selected and typing replaces it")

    model.offsets = 40..<50
    window.tick()
    window.typeText("Z")
    #expect(model.text == "hYlo!Z", "a stale range clamps to the end")

    window.typeKey("a", modifierFlags: .primary)
    #expect(model.offsets == 0..<6, "select-all publishes the whole range")
}

/// 6 — **no availability check stands on the offsets path.** The two `selectedOffsets` initialisers
/// and the `Range<Int>` branch of `reconcile` carry no `@available` and no `#available(macOS 15`
/// before the branch; the harness cannot run macOS 14, so the source is the proof (`SL-Q`).
/// **Mutation:** `@available(macOS 15, *)` on the editor's initialiser fails the build of this file's tests
/// ("only available in macOS 15"); the source-order check is a convention, not a hazard (the offsets cast
/// is the first branch so the common path asks no availability question).
@Test func theOffsetsInitialisersCarryNoAvailabilityGate() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Sources/MetalUI")
    for name in ["TextField.swift", "TextEditor.swift"] {
        let lines = try String(contentsOf: root.appendingPathComponent(name), encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let index = try #require(lines.firstIndex { $0.contains("selectedOffsets: Binding<Range<Int>?>") }, "\(name) has the initialiser")
        var above = index - 1
        while above >= 0, lines[above].trimmingCharacters(in: .whitespaces).hasPrefix("///") { above -= 1 }
        #expect(!lines[above].contains("@available"), "\(name): the initialiser's attributes carry no availability")
        #expect(!lines[index].contains("@available"))
    }
    let reconcile = try String(contentsOf: root.appendingPathComponent("TextEditing.swift"), encoding: .utf8)
    let offsetsBranch = try #require(reconcile.range(of: "binding.base as? Range<Int>"))
    let gate = try #require(reconcile.range(of: "#available(macOS 15, *), let value = binding.base as? TextSelection"))
    #expect(offsetsBranch.lowerBound < gate.lowerBound, "the offsets cast is tried before the macOS 15 check")
}

// MARK: Focus gating

/// 7 — **only a focused field follows**: a field that lost focus forgets the text it saw, so a text replaced
/// while it was away does not turn the click that focuses it into "a replacement" (the caret would jump from
/// the clicked place to the end). Focus A, type, Tab to B, replace A's text, click near A's start, type: the
/// key lands at the click. **Mutation:** drop the `guard focused` in `followExternalText` (the key lands at the end).
@Test @MainActor
private func aReplacementWhileAFieldWasUnfocusedDoesNotMoveALaterClick() throws {
    let model = ExtModel("seed")
    var other = ""
    let window = try harnessWindow {
        VStack(spacing: 8) {
            TextField("Title", text: model.textBinding)
            TextField("Other", text: Binding(get: { other }, set: { other = $0 }))
        }
    }
    model.redraw = { [unowned window] in window.window.setNeedsRedraw() }
    try window.focus(window.element(label: "Title"))
    window.typeText("a")
    window.typeKey(.tab)
    model.text = "0123456789"
    window.tick()
    let frame = try window.element(label: "Title").frame
    window.click(at: Point(x: Pixels(frame.origin.x.value + 3), y: Pixels(frame.origin.y.value + frame.size.height.value / 2)))
    window.typeText("Y")
    #expect(model.text.hasPrefix("Y0") || model.text.hasPrefix("0Y"), "the key landed at the click: \(model.text)")
}
