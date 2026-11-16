import Testing
import Foundation
import Observation
import MetalUI
import MetalUIScene
import MetalUITesting

// Text-anchored presentations of `CodeView` (`CV-AQ`, `CV-AR`, record 282, Alloy G35 E): a popover or a suggestion
// overlay that points at the caret or a range, follows edits and scrolls, and leaves the keys with the view. PLAIN
// imports; the harness text system, so the numbers are the same on every platform.

@Observable @MainActor private final class AnchorModel {
    var shown = true
    var item: Pick?
    /// What the view's `onKeyPress` saw, in order: a key's hex code, or the typed text.
    var keys: [String] = []
    var consumes = true
    var shownBinding: Binding<Bool> { Binding(get: { self.shown }, set: { self.shown = $0 }) }
    var itemBinding: Binding<Pick?> { Binding(get: { self.item }, set: { self.item = $0 }) }
}

private struct Pick: Identifiable { let id: Int }

private let popoverText = "POP"

@MainActor private func popoverBody() -> some ElementGroup {
    Text(popoverText)
}

private enum Kind { case suggestion, popover }

/// The view under test: 60 lines, no line numbers (the text starts at x = 6), a handler for the navigation keys and "a".
@MainActor private func baseView(_ model: AnchorModel, _ buffer: CodeBuffer, _ geometry: CodeViewGeometry) -> CodeView {
    CodeView(buffer: buffer, decorations: CodeDecorations(buffer: buffer)).font(size: 12).showsLineNumbers(false)
        .codeCaretBlink(.off).geometry(geometry)
        .onKeyPress(keys: [.downArrow, .upArrow, .return, .escape, .tab]) { press in
            model.keys.append(String(press.key.character.unicodeScalars.first!.value, radix: 16))
            return model.consumes ? .handled : .ignored
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "a")) { press in
            model.keys.append(press.characters)
            return model.consumes ? .handled : .ignored
        }
}

/// A 400 x 300 window holding the view 400 x 200 high with the presentation of `kind` at `anchor`.
@MainActor private func anchorWindow(_ model: AnchorModel, _ kind: Kind, anchor: CodeTextAnchor, text: String? = nil,
                                     geometry: CodeViewGeometry = CodeViewGeometry(),
                                     buffer: CodeBuffer? = nil) throws -> (TestWindow, CodeBuffer, CodeViewGeometry) {
    let buffer = buffer ?? CodeBuffer(text ?? codeText(lines: 60))
    let window: TestWindow
    switch kind {
    case .suggestion:
        window = try harnessWindow(size: sz(400, 300)) {
            VStack(spacing: 0) {
                baseView(model, buffer, geometry).suggestionOverlay(isPresented: model.shownBinding, attachmentAnchor: anchor) { popoverBody() }
                    .frame(width: Pixels(400), height: Pixels(200))
                Spacer(minLength: 0)
            }
        }
    case .popover:
        window = try harnessWindow(size: sz(400, 300)) {
            VStack(spacing: 0) {
                baseView(model, buffer, geometry).popover(isPresented: model.shownBinding, attachmentAnchor: anchor, arrowEdge: .bottom) { popoverBody() }
                    .frame(width: Pixels(400), height: Pixels(200))
                Spacer(minLength: 0)
            }
        }
    }
    window.tick(); window.tick(); window.tick()
    return (window, buffer, geometry)
}

private extension Bounds where Unit == Pixels {
    var bottom: Float { origin.y.value + size.height.value }
}

@MainActor private func popoverFrame(_ window: TestWindow) throws -> Bounds<Pixels> {
    try window.element(label: popoverText).frame
}

@MainActor private func byteRange(of needle: String, inRow row: Int, _ buffer: CodeBuffer) -> Range<Int> {
    let snap = buffer.snapshot()
    let line = snap.line(row)
    let r = line.range(of: needle)!
    let start = snap.lineRange(row).lowerBound + line.utf8.distance(from: line.startIndex, to: r.lowerBound)
    return start..<(start + needle.utf8.count)
}

private func near(_ a: Float, _ b: Float, _ tolerance: Float = 0.6) -> Bool { abs(a - b) <= tolerance }

/// A text with short ASCII rows, so every row, word and caret position is easy to name.
private let plainText = (0..<60).map { "row\($0) alpha beta gamma\n" }.joined()

/// 1 — a suggestion overlay at the caret sits `spacing` below it and follows it as the user types, one frame after
/// the keystroke's own (the anchor is recorded in the view's prepaint and placed in the next layout, as every
/// anchor is, `MN-M`). **Mutation:** the wrapper recording its bounds (the box ignored) leaves it at the view's origin.
@Test @MainActor func aSuggestionOverlayFollowsTheCaretWithinOneFrameOfTyping() throws {
    let model = AnchorModel()
    let (window, buffer, geometry) = try anchorWindow(model, .suggestion, anchor: .caret, text: plainText)
    window.click(at: pt(60, 6))
    buffer.selections = [CodeSelection(caret: 0)]
    window.window.setNeedsRedraw()
    window.tick(); window.tick()
    let first = try #require(geometry.caretRect())
    var box = try popoverFrame(window)
    #expect(near(box.origin.x.value, first.origin.x.value) && near(box.origin.y.value, first.bottom + 2), "at the caret: \(box) vs \(first)")
    model.consumes = false
    window.typeText("xyz")   // each is offered to onKeyPress (it handles only "a") and typed
    window.tick()
    #expect(buffer.snapshot().line(0).hasPrefix("xyzrow0"))
    let moved = try #require(geometry.caretRect())
    #expect(moved.origin.x.value > first.origin.x.value + 10, "the caret moved right: \(moved)")
    box = try popoverFrame(window)
    #expect(near(box.origin.x.value, moved.origin.x.value) && near(box.origin.y.value, moved.bottom + 2), "followed it: \(box) vs \(moved)")
    // Down a row: the overlay follows vertically too.
    window.typeKey(.downArrow)
    window.tick()
    let down = try #require(geometry.caretRect())
    box = try popoverFrame(window)
    #expect(down.origin.y.value > moved.origin.y.value && near(box.origin.y.value, down.bottom + 2), "\(box) vs \(down)")
}

/// 2 — a range popover recorded as of an older version follows an edit above it: the view maps the range through the
/// log, so it still points at the same word; without `asOf` the offsets are taken as they are. **Mutation:** the
/// `buffer.map` skipped (the range used as given) leaves the popover on the old row.
@Test @MainActor func aRangePopoverFollowsAnEditAboveWithAsOf() throws {
    let model = AnchorModel()
    let buffer = CodeBuffer(plainText)
    let word = byteRange(of: "beta", inRow: 3, buffer)
    let version = buffer.version
    let (window, _, geometry) = try anchorWindow(model, .suggestion, anchor: .range(word, asOf: version), text: nil, buffer: buffer)
    let before = try #require(geometry.rects(for: word).first)
    var box = try popoverFrame(window)
    #expect(near(box.origin.x.value, before.origin.x.value) && near(box.origin.y.value, before.bottom + 2), "\(box) vs \(before)")
    buffer.replace(0..<0, with: "inserted line\nand another\n")
    window.window.setNeedsRedraw()   // an observed write dirties the window asynchronously off Apple (as in G35 A's tests)
    window.tick(); window.tick(); window.tick()
    let moved = try #require(geometry.rects(for: buffer.map(word.lowerBound, from: version, bias: .after)!..<buffer.map(word.upperBound, from: version, bias: .before)!).first)
    #expect(moved.origin.y.value > before.origin.y.value + 10, "the word is two rows lower: \(moved) vs \(before)")
    box = try popoverFrame(window)
    #expect(near(box.origin.x.value, moved.origin.x.value) && near(box.origin.y.value, moved.bottom + 2), "\(box) vs \(moved)")
}

/// 3 — a press on the anchored word dismisses the popover and then reaches the view: the caret is placed in the word
/// (the anchor does not consume it, as a toggling button's would). **Mutation:** `consumesAnchorPress` true for a
/// text anchor leaves the caret where it was.
@Test @MainActor func aPressOnTheAnchoredWordPlacesTheCaretAndDismisses() throws {
    let model = AnchorModel()
    let buffer = CodeBuffer(plainText)
    let word = byteRange(of: "gamma", inRow: 5, buffer)
    let (window, _, geometry) = try anchorWindow(model, .popover, anchor: .range(word), text: nil, buffer: buffer)
    #expect(model.shown)
    let rect = try #require(geometry.rects(for: word).first)
    let target = pt(rect.origin.x.value + rect.size.width.value / 2, rect.origin.y.value + rect.size.height.value / 2)
    #expect(!(try popoverFrame(window)).contains(target), "the popover is not over the word")
    window.click(at: target)
    #expect(!model.shown, "dismissed")
    #expect(word.contains(buffer.primarySelection.head), "the caret went into the word: \(buffer.primarySelection)")
}

/// 4 — with the suggestion overlay open, ↑ ↓ Return Tab and Esc reach the view's `onKeyPress` before the view edits:
/// handled, the caret does not move and no newline or tab is inserted; ignored, the view edits as usual. **Mutation:**
/// swapping `dispatchKeyPress` and `dispatchTextKey` in `Window` lets the view take them first (the handled arm
/// reddens).
@Test @MainActor func theNavigationKeysReachOnKeyPressBeforeTheViewWhileHandledAndTheViewEditsWhenIgnored() throws {
    let model = AnchorModel()
    let (window, buffer, _) = try anchorWindow(model, .suggestion, anchor: .caret, text: plainText)
    window.click(at: pt(60, 6))
    buffer.selections = [CodeSelection(caret: 4)]
    window.window.setNeedsRedraw()
    window.tick()
    let text = buffer.snapshot().text
    for key in [KeyEquivalent.downArrow, .upArrow, .return, .tab, .escape] { window.typeKey(key) }
    #expect(model.keys == ["f701", "f700", "d", "9", "1b"], "\(model.keys)")
    #expect(buffer.snapshot().text == text && buffer.primarySelection == CodeSelection(caret: 4), "handled: the view did nothing")
    #expect(model.shown, "and nothing dismissed the overlay")
    model.consumes = false
    window.typeKey(.downArrow)
    #expect(buffer.snapshot().point(at: buffer.primarySelection.head).row == 1, "ignored: ↓ moved the caret")
    window.typeKey(.upArrow)
    #expect(buffer.snapshot().point(at: buffer.primarySelection.head).row == 0)
    window.typeKey(.return)
    #expect(buffer.snapshot().text != text && buffer.snapshot().line(0) == "row0", "ignored: Return inserted a line: \(buffer.snapshot().line(0))")
    window.typeKey(.tab)
    #expect(buffer.snapshot().line(1).hasPrefix("\t") || buffer.snapshot().line(1).hasPrefix(" "), "ignored: Tab inserted indentation")
    #expect(model.shown)
}

/// 5 — a typed character is offered to `onKeyPress` first (`KF-Q`): handled, it is not inserted; ignored, it is. While
/// an input method has marked text it is not offered at all, and a key that reaches the window then is (`KF-AB`).
/// **Mutation:** `dispatchTypedKeyPress` after `dispatchTextInput` inserts the handled "a".
@Test @MainActor func aTypedCharacterReachesOnKeyPressFirst() throws {
    let model = AnchorModel()
    let (window, buffer, _) = try anchorWindow(model, .suggestion, anchor: .caret, text: "hello\n")
    window.click(at: pt(60, 6))
    buffer.selections = [CodeSelection(caret: 0)]
    window.window.setNeedsRedraw()
    window.tick()
    window.typeText("a")
    #expect(model.keys == ["a"] && buffer.snapshot().text == "hello\n", "handled: not inserted: \(model.keys)")
    model.consumes = false
    window.typeText("a")
    #expect(model.keys == ["a", "a"] && buffer.snapshot().text == "ahello\n", "ignored: inserted")
    model.keys = []
    #expect(window.setMarkedText("a"))
    window.typeKey(.downArrow)
    #expect(model.keys == ["f701"], "a key that reaches the window while composing is delivered, as SwiftUI does (KF-AB)")
    #expect(window.commitMarkedText())
    #expect(model.keys == ["f701"], "a commit of marked text is the input method's, never offered: \(model.keys)")
    #expect(buffer.snapshot().text == "ahello\na", "the commit went in at the caret, which the ignored ↓ had moved: \(buffer.snapshot().text.debugDescription)")
}

/// 6 — an open `.popover` takes Escape before the keymap and `onKeyPress` (SwiftUI's popover is dismissed by Esc), where
/// a suggestion overlay leaves it to the app (4). **Mutation:** the popover not in the dismissal stack (a
/// `.suggestion` kind) leaves it open and hands Esc to the handler.
@Test @MainActor func anOpenPopoverTakesEscapeBeforeOnKeyPress() throws {
    let model = AnchorModel()
    let (window, buffer, _) = try anchorWindow(model, .popover, anchor: .caret, text: plainText)
    window.click(at: pt(60, 6))   // not on the popover
    model.shown = true
    window.window.setNeedsRedraw()   // see 2: the write to the model dirties asynchronously off Apple
    window.tick(); window.tick()
    window.typeKey(.escape)
    #expect(!model.shown && model.keys.isEmpty, "Esc dismissed it and went no further: \(model.keys)")
    _ = buffer
}

/// 7 — an `item:` popover names its content by the item and writes `nil` on dismissal.
@Test @MainActor func anItemPopoverAnchorsAtTheRangeAndDismissesToNil() throws {
    let model = AnchorModel()
    model.item = Pick(id: 7)
    let buffer = CodeBuffer(plainText)
    let word = byteRange(of: "alpha", inRow: 2, buffer)
    let geometry = CodeViewGeometry()
    let window = try harnessWindow(size: sz(400, 300)) {
        VStack(spacing: 0) {
            baseView(model, buffer, geometry)
                .popover(item: model.itemBinding, attachmentAnchor: .range(word), arrowEdge: .bottom) { item in
                    Text("\(popoverText) \(item.id)")
                }
                .frame(width: Pixels(400), height: Pixels(200))
            Spacer(minLength: 0)
        }
    }
    window.tick(); window.tick(); window.tick()
    let rect = try #require(geometry.rects(for: word).first)
    let box = try window.element(label: "\(popoverText) 7").frame
    #expect(near(box.origin.y.value, rect.bottom + 8 + 12), "8 pt below the word, content padded by 12: \(box) vs \(rect)")
    #expect(near(box.origin.x.value + box.size.width.value / 2, rect.origin.x.value + rect.size.width.value / 2), "centred on it")
    window.click(at: pt(300, 150))
    #expect(model.item == nil)
}

/// 8 — a range on no shown row anchors at an empty rectangle at the nearest visible edge: below the last shown row, the
/// view's bottom; above the first, its top; and it moves back to the word when the word scrolls in. **Mutation:** the
/// edge fallback answering `nil` (the whole view's bounds) puts the overlay under the view's bottom edge for both.
@Test @MainActor func anOffscreenRangeAnchorsAtTheNearestVisibleEdge() throws {
    let pitch = codePitch(scale: 1)
    // Below the last shown row: the view's bottom edge (y = 200), at the text's left.
    let model = AnchorModel()
    let buffer = CodeBuffer(plainText)
    let far = byteRange(of: "beta", inRow: 50, buffer)
    let (window, _, _) = try anchorWindow(model, .suggestion, anchor: .range(far), text: nil, buffer: buffer)
    var box = try popoverFrame(window)
    #expect(near(box.origin.y.value, 200 + 2) && near(box.origin.x.value, 6), "below the bottom edge: \(box)")
    // Above the first shown row: the view's top edge (y = 0).
    let model2 = AnchorModel()
    let buffer2 = CodeBuffer(plainText)
    let early = byteRange(of: "beta", inRow: 2, buffer2)
    let (window2, _, geometry2) = try anchorWindow(model2, .suggestion, anchor: .range(early), text: nil, buffer: buffer2)
    let onWord = try #require(geometry2.rects(for: early).first)
    box = try popoverFrame(window2)
    #expect(near(box.origin.y.value, onWord.bottom + 2) && near(box.origin.x.value, onWord.origin.x.value), "on the word: \(box)")
    window2.scroll(at: pt(100, 100), byDeltaX: 0, deltaY: -pitch * 10)
    window2.tick(); window2.tick()
    #expect((geometry2.visibleRows?.lowerBound ?? 0) > 2 && geometry2.rects(for: early).isEmpty)
    box = try popoverFrame(window2)
    #expect(near(box.origin.y.value, 0 + 2) && near(box.origin.x.value, 6), "at the view's top edge: \(box)")
    window2.scroll(at: pt(100, 100), byDeltaX: 0, deltaY: pitch * 10)
    window2.tick(); window2.tick()
    let back = try #require(geometry2.rects(for: early).first)
    box = try popoverFrame(window2)
    #expect(near(box.origin.y.value, back.bottom + 2) && near(box.origin.x.value, back.origin.x.value), "back on the word: \(box) vs \(back)")
}

/// 9 — a text anchor is journaled for retained replay (`RW-K`): a view inside an `.equatable()` component that replays
/// still records the anchor, so a popover opened from the replayed frames points at the caret, not at the view's
/// bounds. **Mutation:** recording the text anchor outside the journal (`presentationAnchors[id] =`) leaves the
/// replayed frames without an anchor and the popover unplaced.
private struct AnchorHost: Component, @MainActor Equatable {
    let buffer: CodeBuffer, decorations: CodeDecorations, geometry: CodeViewGeometry, model: AnchorModel
    static func == (a: AnchorHost, b: AnchorHost) -> Bool { a.buffer === b.buffer && a.model === b.model }
    var content: some ElementGroup {
        CodeView(buffer: buffer, decorations: decorations).font(size: 12).showsLineNumbers(false)
            .codeCaretBlink(.off).geometry(geometry)
            .suggestionOverlay(isPresented: model.shownBinding, attachmentAnchor: .caret) { popoverBody() }
            .frame(width: Pixels(400), height: Pixels(200))
    }
}

@Test @MainActor func retainedReplayKeepsTheAnchor() throws {
    let model = AnchorModel()
    model.shown = false
    let buffer = CodeBuffer(plainText)
    let decorations = CodeDecorations(buffer: buffer)
    let geometry = CodeViewGeometry()
    let tick = Tick()
    let window = try harnessWindow(size: sz(400, 300)) {
        VStack(spacing: 0) {
            Text("\(tick.value)").frame(width: Pixels(40), height: Pixels(10))
            AnchorHost(buffer: buffer, decorations: decorations, geometry: geometry, model: model).equatable()
            Spacer(minLength: 0)
            TextField("other", text: Binding(get: { "" }, set: { _ in })).accessibilityIdentifier("other").frame(width: Pixels(100), height: Pixels(24))
        }
    }
    buffer.selections = [CodeSelection(caret: 9)]
    window.window.setNeedsRedraw()
    try window.click(try window.element(identifier: "other"))   // the view starts focused; a focused view never replays
    #expect(try window.focusedElement?.identifier == "other")   // the view starts focused; a focused or hovered view never replays
    window.resetFrameWork()
    for _ in 0..<4 { tick.value += 1; window.window.setNeedsRedraw(); window.tick() }
    if !rsVerifying { #expect(window.frameWork.reduce(FrameWork(), +).retainedHits >= 4, "the host replays while the popover is closed") }
    model.shown = true
    window.window.setNeedsRedraw()   // see 2
    window.tick()
    // Placed in the very frame it was presented in: the replayed frames before it kept the anchor (a ledger without it
    // leaves the popover one frame late, `RW-K`).
    let box = try popoverFrame(window)
    let caret = try #require(geometry.caretRect())
    #expect(near(box.origin.x.value, caret.origin.x.value) && near(box.origin.y.value, caret.bottom + 2 + 10),
            "at the caret under the 10 pt row: \(box) vs \(caret)")
}

@Observable @MainActor private final class Tick { var value = 0 }


// MARK: chained presentations (`CV-BC`, `CV-BD`, record 332, Alloy code-intel #4)

private let sugLabel = "SUG"

private enum ChainOrder: CaseIterable { case suggestionFirst, popoverFirst }

@MainActor @ElementBuilder
private func chainedView(_ model: AnchorModel, _ buffer: CodeBuffer, _ geometry: CodeViewGeometry, _ order: ChainOrder,
                         popoverAnchor: CodeTextAnchor) -> some ElementGroup {
    switch order {
    case .suggestionFirst:
        baseView(model, buffer, geometry)
            .suggestionOverlay(isPresented: model.shownBinding, attachmentAnchor: .caret) { Text(sugLabel) }
            .popover(item: model.itemBinding, attachmentAnchor: popoverAnchor, arrowEdge: .bottom) { _ in Text(popoverText) }
            .frame(width: Pixels(400), height: Pixels(200))
    case .popoverFirst:
        baseView(model, buffer, geometry)
            .popover(item: model.itemBinding, attachmentAnchor: popoverAnchor, arrowEdge: .bottom) { _ in Text(popoverText) }
            .suggestionOverlay(isPresented: model.shownBinding, attachmentAnchor: .caret) { Text(sugLabel) }
            .frame(width: Pixels(400), height: Pixels(200))
    }
}

@MainActor private func chainedWindow(_ model: AnchorModel, _ buffer: CodeBuffer, _ geometry: CodeViewGeometry, _ order: ChainOrder,
                                      popoverAnchor: CodeTextAnchor) async throws -> TestWindow {
    let window = try harnessWindow(size: sz(400, 300)) {
        VStack(spacing: 0) {
            chainedView(model, buffer, geometry, order, popoverAnchor: popoverAnchor)
            Spacer(minLength: 0)
        }
    }
    try await window.runUntilIdle()
    window.click(at: pt(60, 6))   // focuses the view, caret on row 0 (a press on the anchored text dismisses a popover: open it after)
    buffer.selections = [CodeSelection(caret: 0)]
    model.item = Pick(id: 1)
    window.window.setNeedsRedraw()
    try await window.runUntilIdle()
    window.tick(); window.tick()
    return window
}

@MainActor private func frameOf(_ window: TestWindow, _ label: String) throws -> Bounds<Pixels> { try window.element(label: label).frame }

/// 10 — a suggestion overlay at the caret and an `item:` popover at a word, chained on one view, both show in one frame,
/// each at its own anchor; typing moves only the caret's, the word's stays. Both orders. **Mutation:** one shared box
/// (the second `anchored` replacing the first, as the single `textAnchorBox` did) leaves the first wrapper at the view's
/// bounds, and in the other order the overlay on the word's anchor.
@Test @MainActor func aSuggestionOverlayAndAnItemPopoverPresentTogether() async throws {
    for order in ChainOrder.allCases {
        let model = AnchorModel()
        let buffer = CodeBuffer(plainText)
        let word = byteRange(of: "gamma", inRow: 5, buffer)
        let geometry = CodeViewGeometry()
        // `asOf`: typing on row 0 moves the word's bytes, and the anchor follows the word, not the offsets.
        let window = try await chainedWindow(model, buffer, geometry, order, popoverAnchor: .range(word, asOf: buffer.version))
        defer { withExtendedLifetime(window) {} }
        let caret = try #require(geometry.caretRect())
        let wordRect = try #require(geometry.rects(for: word).first)
        var sug = try frameOf(window, sugLabel), pop = try frameOf(window, popoverText)
        #expect(near(sug.origin.x.value, caret.origin.x.value) && near(sug.origin.y.value, caret.bottom + 2), "\(order) overlay at the caret: \(sug) vs \(caret)")
        #expect(near(pop.origin.y.value, wordRect.bottom + 8 + 12) && near(pop.origin.x.value + pop.size.width.value / 2, wordRect.origin.x.value + wordRect.size.width.value / 2),
                "\(order) popover at the word: \(pop) vs \(wordRect)")
        let popBefore = pop
        model.consumes = false
        window.typeText("xyz")
        try await window.runUntilIdle()
        let moved = try #require(geometry.caretRect())
        #expect(moved.origin.x.value > caret.origin.x.value + 10)
        sug = try frameOf(window, sugLabel); pop = try frameOf(window, popoverText)
        #expect(near(sug.origin.x.value, moved.origin.x.value) && near(sug.origin.y.value, moved.bottom + 2), "\(order) overlay followed the caret: \(sug) vs \(moved)")
        #expect(near(pop.origin.x.value, popBefore.origin.x.value) && near(pop.origin.y.value, popBefore.origin.y.value), "\(order) popover stayed: \(pop) vs \(popBefore)")
    }
}

/// 11 — three chained presentations (an overlay and two popovers) each resolve their own anchor: three different
/// places in one frame. **Mutation:** the anchor loop in the view's prepaint stopping after the first box leaves the
/// later wrappers at the view's bounds.
@Test @MainActor func threeChainedPresentationsResolveTheirOwnAnchors() async throws {
    let model = AnchorModel()
    let buffer = CodeBuffer(plainText)
    let geometry = CodeViewGeometry()
    let first = byteRange(of: "alpha", inRow: 3, buffer), second = byteRange(of: "gamma", inRow: 8, buffer)
    let second2 = Binding<Bool>.constant(true)
    let window = try harnessWindow(size: sz(400, 300)) {
        VStack(spacing: 0) {
            baseView(model, buffer, geometry)
                .popover(item: model.itemBinding, attachmentAnchor: .range(first), arrowEdge: .bottom) { _ in Text("ONE") }
                .suggestionOverlay(isPresented: model.shownBinding, attachmentAnchor: .caret) { Text(sugLabel) }
                .popover(isPresented: second2, attachmentAnchor: .range(second), arrowEdge: .bottom) { Text("TWO") }
                .frame(width: Pixels(400), height: Pixels(200))
            Spacer(minLength: 0)
        }
    }
    defer { withExtendedLifetime(window) {} }
    try await window.runUntilIdle()
    window.click(at: pt(60, 6))
    buffer.selections = [CodeSelection(caret: 0)]
    model.item = Pick(id: 1)
    window.window.setNeedsRedraw()
    try await window.runUntilIdle()
    window.tick(); window.tick()
    let caret = try #require(geometry.caretRect())
    let r1 = try #require(geometry.rects(for: first).first), r2 = try #require(geometry.rects(for: second).first)
    let one = try frameOf(window, "ONE"), two = try frameOf(window, "TWO"), sug = try frameOf(window, sugLabel)
    #expect(near(one.origin.y.value, r1.bottom + 8 + 12), "ONE under the first word: \(one) vs \(r1)")
    #expect(near(two.origin.y.value, r2.bottom + 8 + 12), "TWO under the second word: \(two) vs \(r2)")
    #expect(near(sug.origin.y.value, caret.bottom + 2) && near(sug.origin.x.value, caret.origin.x.value), "overlay at the caret: \(sug) vs \(caret)")
}

/// 12 — with a popover and a suggestion overlay both open, the first Escape dismisses the popover (an open popover takes
/// Escape first, `MN-N`) and the overlay stays; the second reaches the view's `onKeyPress`. **Mutation:** the overlay
/// registering a dismissal (or the popover not) lets Escape reach the handler on the first press.
@Test @MainActor func escapeDismissesThePopoverFirstThenReachesOnKeyPress() async throws {
    for order in ChainOrder.allCases {
        let model = AnchorModel()
        let buffer = CodeBuffer(plainText)
        let geometry = CodeViewGeometry()
        let window = try await chainedWindow(model, buffer, geometry, order, popoverAnchor: .range(byteRange(of: "gamma", inRow: 5, buffer)))
        defer { withExtendedLifetime(window) {} }
        window.typeKey(.escape)
        #expect(model.item == nil && model.keys.isEmpty && model.shown, "\(order) first Esc: the popover only: \(model.keys)")
        window.typeKey(.escape)
        #expect(model.keys == ["1b"] && model.shown, "\(order) second Esc reached onKeyPress: \(model.keys)")
    }
}

/// 13 — dismissing one presentation leaves the other at its own anchor: the overlay's after the popover went, and the
/// popover's after the overlay was turned off. **Mutation:** the wrapper that stays recording the view's bounds (its box
/// dropped with the other's) moves it.
@Test @MainActor func dismissingOneKeepsTheOthersAnchor() async throws {
    let model = AnchorModel()
    let buffer = CodeBuffer(plainText)
    let word = byteRange(of: "gamma", inRow: 5, buffer)
    let geometry = CodeViewGeometry()
    let window = try await chainedWindow(model, buffer, geometry, .suggestionFirst, popoverAnchor: .range(word))
    defer { withExtendedLifetime(window) {} }
    let sugBefore = try frameOf(window, sugLabel), popBefore = try frameOf(window, popoverText)
    model.item = nil
    window.window.setNeedsRedraw(); try await window.runUntilIdle(); window.tick()
    #expect(throws: (any Error).self) { _ = try frameOf(window, popoverText) }
    let sugAfter = try frameOf(window, sugLabel)
    #expect(near(sugAfter.origin.x.value, sugBefore.origin.x.value) && near(sugAfter.origin.y.value, sugBefore.origin.y.value), "\(sugAfter) vs \(sugBefore)")
    model.item = Pick(id: 1); model.shown = false
    window.window.setNeedsRedraw(); try await window.runUntilIdle(); window.tick()
    #expect(throws: (any Error).self) { _ = try frameOf(window, sugLabel) }
    let popAfter = try frameOf(window, popoverText)
    #expect(near(popAfter.origin.x.value, popBefore.origin.x.value) && near(popAfter.origin.y.value, popBefore.origin.y.value), "\(popAfter) vs \(popBefore)")
}

/// 14 — both anchors survive retained replay (`RW-K`), each journaled under its own wrapper: a view in an `.equatable()`
/// component that replays places an overlay and a popover opened afterwards in the very frame they open in. **Mutation:**
/// journaling only the first wrapper's anchor (or recording outside the journal) leaves the other one frame late.
private struct ChainedHost: Component, @MainActor Equatable {
    let buffer: CodeBuffer, decorations: CodeDecorations, geometry: CodeViewGeometry, model: AnchorModel, word: Range<Int>
    static func == (a: ChainedHost, b: ChainedHost) -> Bool { a.buffer === b.buffer && a.model === b.model }
    var content: some ElementGroup {
        CodeView(buffer: buffer, decorations: decorations).font(size: 12).showsLineNumbers(false)
            .codeCaretBlink(.off).geometry(geometry)
            .suggestionOverlay(isPresented: model.shownBinding, attachmentAnchor: .caret) { Text(sugLabel) }
            .popover(item: model.itemBinding, attachmentAnchor: .range(word), arrowEdge: .bottom) { _ in Text(popoverText) }
            .frame(width: Pixels(400), height: Pixels(200))
    }
}

@Test @MainActor func retainedReplayKeepsBothAnchors() async throws {
    let model = AnchorModel()
    model.shown = false
    let buffer = CodeBuffer(plainText)
    let decorations = CodeDecorations(buffer: buffer)
    let geometry = CodeViewGeometry()
    let word = byteRange(of: "gamma", inRow: 5, buffer)
    let tick = Tick()
    let window = try harnessWindow(size: sz(400, 300)) {
        VStack(spacing: 0) {
            Text("\(tick.value)").frame(width: Pixels(40), height: Pixels(10))
            ChainedHost(buffer: buffer, decorations: decorations, geometry: geometry, model: model, word: word).equatable()
            Spacer(minLength: 0)
            TextField("other", text: Binding(get: { "" }, set: { _ in })).accessibilityIdentifier("other").frame(width: Pixels(100), height: Pixels(24))
        }
    }
    defer { withExtendedLifetime(window) {} }
    try await window.runUntilIdle()
    buffer.selections = [CodeSelection(caret: 9)]
    window.window.setNeedsRedraw()
    try window.click(try window.element(identifier: "other"))
    window.resetFrameWork()
    for _ in 0..<4 { tick.value += 1; window.window.setNeedsRedraw(); window.tick() }
    if !rsVerifying { #expect(window.frameWork.reduce(FrameWork(), +).retainedHits >= 4, "the host replays while both are closed") }
    model.shown = true
    model.item = Pick(id: 1)
    window.window.setNeedsRedraw()
    window.tick()
    let caret = try #require(geometry.caretRect())
    let wordRect = try #require(geometry.rects(for: word).first)
    let sug = try frameOf(window, sugLabel), pop = try frameOf(window, popoverText)
    #expect(near(sug.origin.x.value, caret.origin.x.value) && near(sug.origin.y.value, caret.bottom + 2 + 10), "overlay at the caret under the 10 pt row: \(sug) vs \(caret)")
    #expect(near(pop.origin.y.value, wordRect.bottom + 8 + 12 + 10), "popover at the word under the 10 pt row: \(pop) vs \(wordRect)")
}

/// 15 — only a presented popover holds the text hover's grace (`CV-BD`): leaving the text with only an overlay open ends
/// the hover at once; with a popover open beside it, `.ended` waits the 150 ms. **Mutation:** the overlay's box counted
/// in `CodeTextHoverRuntime.boxes` (the old single box) holds the grace in the first arm.
@Observable @MainActor private final class GraceModel {
    var ends = 0
    var overlay = false
    var popover = false
}

@Test @MainActor func onlyAPopoverHoldsTheHoverGrace() async throws {
    for withPopover in [false, true] {
        let model = GraceModel()
        let buffer = CodeBuffer("row0 alpha beta gamma\n" + String(repeating: "\n", count: 40))
        let geometry = CodeViewGeometry()
        let word = 5..<10
        let window = try harnessWindow(size: sz(400, 300)) {
            VStack(spacing: 0) {
                CodeView(buffer: buffer, decorations: CodeDecorations(buffer: buffer)).font(size: 12).showsLineNumbers(false)
                    .codeCaretBlink(.off).geometry(geometry)
                    .onTextHover(delay: .milliseconds(300)) { phase in
                        if case .active = phase { model.overlay = true; model.popover = withPopover }
                        if phase == .ended { model.ends += 1; model.overlay = false; model.popover = false }
                    }
                    .suggestionOverlay(isPresented: Binding(get: { model.overlay }, set: { model.overlay = $0 }), attachmentAnchor: .range(word)) { Text(sugLabel) }
                    .popover(isPresented: Binding(get: { model.popover }, set: { model.popover = $0 }), attachmentAnchor: .range(word), arrowEdge: .bottom) { Text(popoverText) }
                    .frame(width: Pixels(400), height: Pixels(200))
                Spacer(minLength: 0)
            }
        }
        defer { withExtendedLifetime(window) {} }
        try await window.runUntilIdle()
        let rect = try #require(geometry.rects(for: word).first)
        window.hover(at: pt(rect.origin.x.value + 3, rect.origin.y.value + 3))
        window.advance(by: 0.3)
        window.window.setNeedsRedraw(); try await window.runUntilIdle(); window.tick(); window.tick()
        #expect(model.overlay && model.popover == withPopover, "opened")
        window.hover(at: pt(300, 150))   // an empty row, away from both panels
        if withPopover {
            #expect(model.ends == 0, "the popover holds the grace: \(model.ends)")
            window.advance(by: 0.2)
            #expect(model.ends == 1, "ended after the grace: \(model.ends)")
        } else {
            #expect(model.ends == 1, "an overlay holds none: \(model.ends)")
        }
    }
}
