import Testing
import Foundation
import MetalUI
import MetalUIScene
import MetalUITesting

// Region cursors of `CodeView` (`CV-BO`, record 368): the I-beam over text, the arrow over the gutter (numbers, marker
// lane, bars) and virtual rows, the pointing hand over a fold chevron that acts, a folded header's `⋯` and (only when
// the app's `onTextClick` acts on a plain click) text. Resolved on input from the last frame's plan by a style
// provider on the view's pointer attachment, so a move within a region is no frame and no platform request. PLAIN
// imports; the harness text system; windows kept alive.

@MainActor private struct Fx {
    let window: TestWindow
    let fold: CodeFoldState
    let geometry: CodeViewGeometry
    var styles: [PlatformPointerStyle] { window.platformWindow.pointerStyles }
}

@MainActor private func fixture(plainClick: Bool = false, defaultClick: Bool = false, wide: Bool = false) async throws -> Fx {
    let text = (0..<40).map { "line\($0)" + (wide ? String(repeating: " word", count: 120) : "") }.joined(separator: "\n")
    let buffer = CodeBuffer(text)
    let decorations = CodeDecorations(buffer: buffer)
    decorations.setLineDecorations([CodeLineDecoration(lines: 0..<40, gutterBar: Color(hue: 0.3, saturation: 1, brightness: 1))], asOf: buffer.version)
    let fold = CodeFoldState(selectionState: buffer.selectionState)
    fold.foldableRanges = [2..<8, 9..<12]
    let geometry = CodeViewGeometry()
    let window = try harnessWindow(size: sz(400, 200)) {
        let base = CodeView(buffer: buffer, decorations: decorations).font(size: 12).codeCaretBlink(.off)
            .showsLineNumbers(true).geometry(geometry).foldState(fold).foldGutter(showsOnHover: false)
        var view = base
        if plainClick { view = base.onTextClick(modifiers: []) { _ in } }
        else if defaultClick { view = base.onTextClick { _ in } }
        return view
    }
    try await window.runUntilIdle()
    return Fx(window: window, fold: fold, geometry: geometry)
}

private func center(_ r: Bounds<Pixels>) -> Point<Pixels> {
    pt(r.origin.x.value + r.size.width.value / 2, r.origin.y.value + r.size.height.value / 2)
}

@MainActor private func frames(_ w: TestWindow, _ body: () -> Void) -> Int {
    let before = w.framesDrawn
    body()
    return w.framesDrawn - before
}

/// **1** Text, gutter, text: the cursor is the I-beam, the arrow, the I-beam again, each change one platform request and no
/// frame. **Mutation:** the provider not attached (the arrow everywhere: the first expectation reddens); `.gutter` answering
/// the I-beam (the second).
@Test @MainActor func movingTextToGutterToTextChangesTheCursorWithoutAFrame() async throws {
    let fx = try await fixture()
    defer { withExtendedLifetime(fx.window) {} }
    let w = fx.window
    w.hover(at: pt(260, 70))   // the entry onto the view is its own frame (hover enter)
    #expect(frames(w) { w.hover(at: pt(250, 60)) } == 0)
    #expect(fx.styles.last == .iBeam, "text: \(fx.styles)")
    let sent = fx.styles.count
    #expect(frames(w) { w.hover(at: pt(5, 60)) } == 0)
    #expect(fx.styles.last == .arrow && fx.styles.count == sent + 1, "gutter: \(fx.styles)")
    #expect(frames(w) { w.hover(at: pt(250, 61)) } == 0)
    #expect(fx.styles.last == .iBeam && fx.styles.count == sent + 2, "text again: \(fx.styles)")
    // Past a line's end and below the last row are still text area: the I-beam, as NSTextView's.
    w.hover(at: pt(390, 60)); #expect(fx.styles.last == .iBeam, "past the line end")
}

/// **2** A move within one region costs no frame and no new request. **Mutation:** the style resolved against a fresh value
/// each time cannot be built; the pin is `updatePointerStyle`'s compared send, reddened by dropping its `guard style != ...`.
@Test @MainActor func movesWithinARegionCostNoFrameAndNoRequest() async throws {
    let fx = try await fixture()
    defer { withExtendedLifetime(fx.window) {} }
    let w = fx.window
    w.hover(at: pt(250, 60))
    let sent = fx.styles.count
    let f = frames(w) { for i in 0..<5 { w.hover(at: pt(200 + Float(i * 9), 50 + Float(i * 11))) } }
    #expect(f == 0 && fx.styles.count == sent, "text: \(f) frames, \(fx.styles.count - sent) requests")
    w.hover(at: pt(4, 40))
    let sentGutter = fx.styles.count
    let g = frames(w) { for i in 0..<5 { w.hover(at: pt(3 + Float(i), 30 + Float(i * 20))) } }
    #expect(g == 0 && fx.styles.count == sentGutter, "gutter: \(g) frames, \(fx.styles.count - sentGutter) requests")
}

/// **3** A chevron that acts and a folded header's `⋯` are the pointing hand; the chevron cell of a line with no chevron is
/// the gutter's arrow. **Mutation:** the chevron branch dropped (arrow); the `foldedLines` branch dropped (I-beam).
@Test @MainActor func aChevronAndAFoldPlaceholderAreThePointingHand() async throws {
    let fx = try await fixture()
    defer { withExtendedLifetime(fx.window) {} }
    let w = fx.window
    let chevron = try #require(fx.geometry.foldChevronRect(line: 2))
    w.hover(at: center(chevron))
    #expect(fx.styles.last == .pointingHand, "chevron: \(fx.styles)")
    let plain = try #require(fx.geometry.foldChevronRect(line: 2)).origin
    w.hover(at: pt(plain.x.value + 1, plain.y.value + 3 * 16 + 2))   // a row below: line 5 starts no range
    #expect(fx.styles.last == .arrow, "no chevron there: \(fx.styles)")
    w.click(at: center(chevron))   // fold 2..<8
    try await w.runUntilIdle()
    let mark = try #require(fx.geometry.foldPlaceholderRect(line: 2))
    w.hover(at: pt(300, 5)); #expect(fx.styles.last == .iBeam)
    let sent = fx.styles.count
    #expect(frames(w) { w.hover(at: center(mark)) } == 0)
    #expect(fx.styles.last == .pointingHand && fx.styles.count == sent + 1, "placeholder: \(fx.styles)")
}

/// **4** Text is the hand only for an `onTextClick` that acts on a plain click (`modifiers: []`); the default (⌘/Ctrl) one
/// leaves the I-beam, as does no handler. **Mutation:** `linksOnPlainClick` always true (the default case reddens); always
/// false (the plain case).
@Test @MainActor func textIsTheHandOnlyWhenOnTextClickActsOnAPlainClick() async throws {
    for (name, kind, expected) in [("plain", 1, PlatformPointerStyle.pointingHand), ("default", 2, .iBeam), ("none", 0, .iBeam)] {
        let fx = try await fixture(plainClick: kind == 1, defaultClick: kind == 2)
        defer { withExtendedLifetime(fx.window) {} }
        fx.window.hover(at: pt(200, 60))   // on "line..." text? the row's text ends early: use the first glyph
        let rect = try #require(fx.geometry.rects(for: 0..<3).first)
        fx.window.hover(at: pt(rect.origin.x.value + 4, rect.origin.y.value + 4))
        #expect(fx.styles.last == expected, "\(name): \(fx.styles)")
        fx.window.hover(at: pt(390, rect.origin.y.value + 4))   // past the line's end: never a target
        #expect(fx.styles.last == .iBeam, "\(name) past the end: \(fx.styles)")
    }
}

/// **5** Regions follow scrolling: after a horizontal scroll the gutter is still the arrow at the same x, and the text beside
/// it the I-beam. **Mutation:** the gutter test using text-space x (not the plan's): the arrow reddens.
@Test @MainActor func regionCursorsRespectHorizontalScrolling() async throws {
    let fx = try await fixture(wide: true)
    defer { withExtendedLifetime(fx.window) {} }
    let w = fx.window
    w.scroll(at: pt(250, 60), byDeltaX: -200, deltaY: 0)
    for _ in 0..<5 { w.advance(by: 0.1) }
    try await w.runUntilIdle()
    w.hover(at: pt(5, 60)); #expect(fx.styles.last == .arrow, "gutter after scroll: \(fx.styles)")
    w.hover(at: pt(250, 60)); #expect(fx.styles.last == .iBeam, "text after scroll: \(fx.styles)")
    w.hover(at: pt(6, 61)); #expect(fx.styles.last == .arrow)
}
