import Testing
import Foundation
import MetalUI
import MetalUIScene
import MetalUITesting

// `contentMargins` on a `CodeView` (`CV-AU`, Alloy gap G43 PR 2): a 400 x 300 window, a 40-point top and a 60-point bottom
// `.scrollContent` margin unless a test says otherwise, so the visible area is y = 40...240. Rows are read through
// `CodeViewGeometry` (the last drawn frame), which reports a row's rectangle whether or not it is under a margin.

@MainActor private func marginedCode<G: ElementGroup>(_ view: G, top: Float, bottom: Float, placement: ContentMarginPlacement) -> some ElementGroup {
    view.contentMargins(.top, Pixels(top), for: placement).contentMargins(.bottom, Pixels(bottom), for: placement)
}

@MainActor private func marginFixture(lines: Int = 200, top: Float = 40, bottom: Float = 60,
                                      placement: ContentMarginPlacement = .scrollContent,
                                      scroll: CodeScrollState? = nil)
    throws -> (window: TestWindow, buffer: CodeBuffer, geometry: CodeViewGeometry) {
    let buffer = CodeBuffer(codeText(lines: lines))
    let decorations = CodeDecorations(buffer: buffer)
    let geometry = CodeViewGeometry()
    let window = try harnessWindow(size: sz(400, 300)) {
        VStack(spacing: 0) {
            if let scroll {
                marginedCode(CodeView(buffer: buffer, decorations: decorations).font(size: 12).codeCaretBlink(.off).geometry(geometry).scrollState(scroll), top: top, bottom: bottom, placement: placement)
            } else {
                marginedCode(CodeView(buffer: buffer, decorations: decorations).font(size: 12).codeCaretBlink(.off).geometry(geometry), top: top, bottom: bottom, placement: placement)
            }
        }
    }
    window.window.setNeedsRedraw(); window.tick()
    return (window, buffer, geometry)
}

/// The rectangle of the start of buffer row `row` (zero-width, so an empty last line has one too).
@MainActor private func rowRect(_ f: (window: TestWindow, buffer: CodeBuffer, geometry: CodeViewGeometry), _ row: Int) -> Bounds<Pixels>? {
    let start = f.buffer.snapshot().lineRange(row).lowerBound
    return f.geometry.rects(for: start..<start).first
}

@MainActor private func scrollTo(_ f: (window: TestWindow, buffer: CodeBuffer, geometry: CodeViewGeometry), _ delta: Float) {
    f.window.scroll(at: pt(200, 150), byDeltaX: 0, deltaY: delta)
    f.window.window.setNeedsRedraw(); f.window.tick()
}

/// **CV-AU.** At scroll 0 row 0 sits at the top margin, and at the end of the scroll the last row ends at the bottom
/// margin's edge (240); the control starts at 0 and ends at the view's bottom. Mutation: the insets dropped from
/// `maxTopPx` and the row placement (row 0 at 0).
@Test @MainActor func codeViewRowsSitInsideTheMarginsAtBothEnds() throws {
    let f = try marginFixture()
    let pitch = codePitch(scale: 1)
    #expect(rowRect(f, 0)?.origin.y.value == 40, "row 0 at \(String(describing: rowRect(f, 0)))")
    scrollTo(f, -1_000_000)
    let last = try #require(rowRect(f, f.buffer.snapshot().lineCount - 1))
    #expect(last.origin.y.value + pitch == 240, "last row bottom \(last.origin.y.value + pitch)")
    let none = try marginFixture(top: 0, bottom: 0)
    #expect(rowRect(none, 0)?.origin.y.value == 0)
    scrollTo(none, -1_000_000)
    let end = try #require(rowRect(none, none.buffer.snapshot().lineCount - 1))
    #expect(end.origin.y.value + pitch == 300, "control: \(end.origin.y.value + pitch)")
}

/// **CV-AU.** Rows still render under the margin: scrolled by 30, row 0 sits at 10, is in `visibleRows` and a glyph of
/// it is drawn above y = 40. Mutation: the row window starting at `topPx / pitch` (rows under the margin dropped, then
/// row 0 absent).
@Test @MainActor func rowsUnderTheMarginsAreStillBuiltAndDrawn() throws {
    let f = try marginFixture()
    scrollTo(f, -30)
    #expect(rowRect(f, 0)?.origin.y.value == 10, "row 0 at \(String(describing: rowRect(f, 0)))")
    #expect(f.geometry.visibleRows?.contains(0) == true)
    let drawn = f.window.scene.glyphs.contains { glyph in
        let low = max(glyph.bounds.origin.y, glyph.contentMask.origin.y)
        let high = min(glyph.bounds.origin.y + glyph.bounds.size.height, glyph.contentMask.origin.y + glyph.contentMask.size.height)
        return high > low && low < 30
    }
    #expect(drawn, "a glyph is drawn above y = 30, inside the top margin")
    scrollTo(f, -1_000_000)
    scrollTo(f, 30)   // 30 points back up from the end: the last row is 30 below the bottom margin's edge
    let last = try #require(rowRect(f, f.buffer.snapshot().lineCount - 1))
    #expect(last.origin.y.value < 300 && f.geometry.visibleRows?.contains(199) == true)
}

/// **CV-AU (`CV-AJ`, `CV-AK`).** A point inside the top margin hits the row drawn there: scrolled by 30, (100, 20) is on
/// row 0 (10...), and (100, 5) is on it too once it is scrolled by 60... the margin region answers like any other.
/// Mutation: `hit(at:)` adding the margin to the row tops twice (row 1).
@Test @MainActor func aPointUnderTheTopMarginHitsTheRowDrawnThere() throws {
    let f = try marginFixture()
    scrollTo(f, -30)
    let pitch = codePitch(scale: 1)
    let hit = try #require(f.geometry.hit(at: pt(100, 10 + pitch / 2)))
    #expect(hit.row == 0 && hit.region == .text, "\(hit)")
    let lower = try #require(f.geometry.hit(at: pt(100, 10 + pitch + pitch / 2)))
    #expect(lower.row == 1, "\(lower)")
}

/// **CV-AU.** A caret reveal (typing, an edit) scrolls the least that keeps the caret's line outside the margins: from
/// above, the line ends at the bottom margin's edge (240), not the view's bottom (300); from below it starts at the top
/// margin's edge (40), not the view's top. Mutation: `revealsCaret` measuring the view's height (the first reading 300).
@Test @MainActor func aCaretRevealKeepsTheLineOutsideTheMargins() throws {
    let f = try marginFixture()
    let pitch = codePitch(scale: 1)
    f.window.click(at: pt(60, 140))   // focus the view
    let at = f.buffer.snapshot().lineRange(100).lowerBound
    f.buffer.selections = [CodeSelection(caret: at)]
    f.window.typeText("x")
    f.window.window.setNeedsRedraw(); f.window.tick()
    let below = try #require(f.geometry.caretRect())
    #expect(below.origin.y.value + pitch == 240, "from above: caret line ends at \(below.origin.y.value + pitch)")
    scrollTo(f, -1000)   // the view moves far down: the caret's line is above it
    f.window.typeText("y")
    f.window.window.setNeedsRedraw(); f.window.tick()
    let above = try #require(f.geometry.caretRect())
    #expect(above.origin.y.value == 40, "from below: caret line starts at \(above.origin.y.value)")
}

/// **CV-AU (`CV-V`).** `select(_:reveal: true)` centres the head's row between the margins: its top is at
/// `40 + (200 - pitch) / 2`, not the view's middle. Mutation: the centring using the full height.
@Test @MainActor func revealCentresBetweenTheMargins() throws {
    let f = try marginFixture(lines: 1000)
    let pitch = codePitch(scale: 1)
    let at = f.buffer.snapshot().lineRange(500).lowerBound
    f.buffer.select(at..<at, reveal: true)
    f.window.window.setNeedsRedraw(); f.window.tick()
    let rect = try #require(rowRect(f, 500))
    let expected = 40 + ((200 - pitch) / 2).rounded(.down)
    #expect(abs(rect.origin.y.value - expected) <= 1, "row 500 at \(rect.origin.y.value), wanted about \(expected)")
}

/// **CV-AU (`CV-T`).** The scroll position in display rows is the row at the top of the visible area: assigning row 10
/// puts row 10 at the top margin (40), and at the end the reported row is the last scroll position. Mutation: the
/// adopted position placed against the view's top (row 10 at 0).
@Test @MainActor func theScrollPositionIsTheRowAtTheTopMargin() throws {
    let scroll = CodeScrollState()
    let f = try marginFixture(scroll: scroll)
    scroll.position = CodeScrollPosition(row: 10)
    f.window.window.setNeedsRedraw(); f.window.tick()
    #expect(rowRect(f, 10)?.origin.y.value == 40, "row 10 at \(String(describing: rowRect(f, 10)))")
    #expect(rowRect(f, 0) == nil, "row 0 is above every shown row")
}

/// **CV-AU.** A `.scrollIndicators` margin moves only the indicator: the rows are as unset (row 0 at 0) and the thumb stays
/// at or below 30 after a scroll. Mutation: the indicator inset not carried to the plan.
@Test @MainActor func aScrollIndicatorsMarginLeavesTheRowsAndMovesTheThumb() throws {
    let f = try marginFixture(top: 30, bottom: 30, placement: .scrollIndicators)
    #expect(rowRect(f, 0)?.origin.y.value == 0)
    scrollTo(f, -10)
    let thumb = try #require(f.window.scene.rects.first { $0.bounds.size.width == 3 })
    #expect(thumb.bounds.origin.y >= 30, "thumb top \(thumb.bounds.origin.y)")
}
