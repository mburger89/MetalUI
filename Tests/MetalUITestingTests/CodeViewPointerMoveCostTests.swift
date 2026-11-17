@testable import MetalUI
import MetalUIScene
import MetalUITesting
import Testing

// What a pointer move that changes nothing visible costs (`FP-T`, record 360, Alloy: the fold-gutter work measured one
// frame and two plain state writes per move over a `CodeView`). The two writes were never the scroll chrome's: they are
// the frame's own retention writes (the focus slot and the accessibility node of the focusable view), taken in every
// frame the view is in; the frame came from `Window`'s input fallback, which dirtied the window for every unclaimed
// event. A move that stays on the same topmost hitbox, with no tooltip and no `onInput`, now asks for no frame, so the
// writes go with it. The harness text system; windows kept alive.

private let rowText = (0..<80).map { "row\($0) alpha beta gamma\n" }.joined()

@MainActor private func codeWindow(gutter: Bool = true, hover: (@MainActor (CodeHoverPhase) -> Void)? = nil,
                                   button: Bool = false, geometry: CodeViewGeometry = CodeViewGeometry()) throws -> TestWindow {
    let buffer = CodeBuffer(rowText)
    return try harnessWindow {
        VStack(spacing: 0) {
            if button { Button("Target") {}.frame(width: Pixels(400), height: Pixels(30)) }
            let base = CodeView(buffer: buffer, decorations: CodeDecorations(buffer: buffer)).font(size: 12)
                .showsLineNumbers(gutter).codeCaretBlink(.off).geometry(geometry)
            if let hover {
                base.onTextHover(delay: .milliseconds(300), perform: hover).frame(width: Pixels(400), height: Pixels(200))
            } else {
                base.frame(width: Pixels(400), height: Pixels(200))
            }
            Spacer(minLength: 0)
        }
    }
}

/// Frames drawn and plain-and-compared state writes while `body` runs.
@MainActor private func cost(_ w: TestWindow, _ body: () -> Void) -> (frames: Int, writes: Int) {
    let frames = w.framesDrawn, writes = w.window.stateTable.writeCount
    body()
    return (w.framesDrawn - frames, w.window.stateTable.writeCount - writes)
}

/// 1 — N moves over a `CodeView`'s text and over its gutter cost no frame and no state write. With the overlay scrollbars
/// shown (a wheel just before) the fade is an animation that draws frames of its own, so the moved window is compared with a
/// twin that is only ticked: the same frames and writes, the moves adding none. Before: 1 frame and 2 plain writes a move
/// (measured: 4 moves, 4 frames, 8 plain writes, with the scrollbars hidden).
/// **Mutation:** `pointerMoveChangesNothing` returning `false` (every move dirties again).
@Test @MainActor func movesOverACodeViewsTextAndGutterCostNothing() async throws {
    let w = try codeWindow(), twin = try codeWindow()
    for x in [w, twin] { try await x.runUntilIdle(); x.hover(at: pt(100, 60)); x.advance(by: 3) }
    // Scrollbars hidden (faded): the literal.
    w.send(.mouseMoved(MouseEvent(position: pt(110, 61), modifiers: [], clickCount: 1, buttonNumber: 0, timestamp: w.now)))
    #expect(!w.window.needsRedraw, "the move itself leaves the window clean, before any tick")
    let text = cost(w) { for i in 0..<4 { w.hover(at: pt(100 + Float(i * 7), 60 + Float(i))) } }
    #expect(text.frames == 0 && text.writes == 0, "moves within the text: \(text)")
    let gutter = cost(w) { for i in 0..<4 { w.hover(at: pt(6 + Float(i), 40 + Float(i * 9))) } }
    #expect(gutter.frames == 0 && gutter.writes == 0, "moves within the gutter: \(gutter)")
    // Scrollbars shown: the moved window costs what the still twin does.
    for x in [w, twin] { x.scroll(at: pt(100, 60), byDeltaX: 0, deltaY: -20) }
    let moved = cost(w) { for i in 0..<4 { w.hover(at: pt(100 + Float(i * 7), 60)); w.hover(at: pt(8, 40 + Float(i))) } }
    let still = cost(twin) { for _ in 0..<8 { twin.tick() } }
    #expect(moved.frames == still.frames && moved.writes == still.writes, "scrollbars shown: moved \(moved) vs still \(still)")
}

/// 2 — the same for a `ScrollView` and a `List`, the shared chrome and input path.
/// **Mutation:** as 1.
@Test @MainActor func movesOverAScrollViewAndAListCostNothing() async throws {
    struct Row: Identifiable { let id: Int }
    let scroll = try harnessWindow {
        ScrollView(.vertical) { VStack(spacing: 0) { ForEach(0..<60, id: \.self) { Text("row \($0)").frame(width: Pixels(300), height: Pixels(20)) } } }
    }
    let list = try harnessWindow {
        List((0..<60).map(Row.init), rowHeight: Pixels(20)) { row in Text("row \(row.id)") }
    }
    for (name, w) in [("ScrollView", scroll), ("List", list)] {
        try await w.runUntilIdle()
        w.hover(at: pt(100, 60))
        w.scroll(at: pt(100, 60), byDeltaX: 0, deltaY: -20)
        w.advance(by: 3)   // the fade is done: the move's own cost
        let c = cost(w) { for i in 0..<4 { w.hover(at: pt(100 + Float(i * 3), 60 + Float(i))) } }
        #expect(c.frames == 0 && c.writes == 0, "\(name): \(c)")
    }
}

/// 3 — a move that changes something still costs its frame: onto another hitbox (a `Button` beside the view), and the first
/// reveal of the overlay scrollbars (the wheel). **Mutation:** the hitbox comparison dropped (`true`): the first reddens.
@Test @MainActor func aMoveThatChangesTheHoveredHitboxOrARevealStillCostsAFrame() async throws {
    let w = try codeWindow(button: true)
    try await w.runUntilIdle()
    w.hover(at: pt(100, 100))
    let onto = cost(w) { w.hover(at: pt(100, 15)) }   // the button
    #expect(onto.frames >= 1, "onto the button: \(onto)")
    let back = cost(w) { w.hover(at: pt(100, 100)) }
    #expect(back.frames >= 1, "and back onto the view: \(back)")
    let reveal = cost(w) { w.scroll(at: pt(100, 100), byDeltaX: 0, deltaY: -20) }
    #expect(reveal.frames >= 1, "the first reveal: \(reveal)")
}

/// 4 — the text hover still triggers: a move into text from a blank row writes the hover track (a frame), the rest of the
/// delay passes and `.active` arrives; moves within the same grapheme cost nothing.
/// **Mutation:** `pointerMoveChangesNothing` skipping a change of grapheme too is not reachable (the hitbox is one), so the
/// guard here is the hover callback's own write: the attachment dropped from the view (no phases).
@Test @MainActor func theTextHoverStillTriggersAndAMoveWithinOneGraphemeCostsNothing() async throws {
    var phases: [CodeHoverPhase] = []
    let geometry = CodeViewGeometry()
    let w = try codeWindow(gutter: false, hover: { phases.append($0) }, geometry: geometry)
    try await w.runUntilIdle()
    w.hover(at: pt(300, 150))   // past the line's end
    let rect = try #require(geometry.rects(for: 0..<4).first)
    let inside = pt(rect.origin.x.value + 3, rect.origin.y.value + rect.size.height.value / 2)
    let enter = cost(w) { w.hover(at: inside) }
    #expect(enter.frames >= 1 && enter.writes >= 1, "entering a target writes the track: \(enter)")
    let within = cost(w) { w.hover(at: pt(inside.x.value + 1, inside.y.value)); w.hover(at: pt(inside.x.value, inside.y.value + 1)) }
    #expect(within.frames == 0 && within.writes == 0, "within the grapheme: \(within)")
    w.advance(by: 0.5)
    #expect(phases.contains { if case .active = $0 { true } else { false } }, "the delay fires: \(phases)")
}

/// 5 — a pending tooltip keeps its frames (its timer rides the display link a dirty window starts): a move within a `.help`
/// element dirties the window, where the same move over an element with no help (test 1) leaves it clean, and the bubble
/// shows after the delay. **Mutation:** the `.idle` guard removed (the in-region move leaves the window clean).
@Test @MainActor func aMoveOverAHelpedElementStillAsksForAFrameAndTheTooltipShows() async throws {
    let w = try harnessWindow { Box().frame(width: Pixels(200), height: Pixels(100)).background(.accent).help("Explains") }
    try await w.runUntilIdle()
    w.hover(at: pt(200, 150))
    #expect(!w.window.needsRedraw, "settled after the first move's frame")
    w.send(.mouseMoved(MouseEvent(position: pt(205, 152), modifiers: [], clickCount: 1, buttonNumber: 0, timestamp: w.now)))
    #expect(w.window.needsRedraw, "a pending tooltip keeps the display link running")
    w.tick()
    w.advance(by: 2)
    #expect(w.window.visibleTooltip?.text == "Explains")
}

/// 6 — the scrollbar's fade is the same with and without moves in between: twins, one wheeled and left, one wheeled and moved
/// over every 0.1 s step, draw the same thumb at every step of a simulated clock, through to its end.
/// **Mutation:** `lastScrollTime` stamped by the move (the pointer-move frame refreshes it: the moved twin's thumb stays
/// longer); here, a move arm that wrote the stamp would break the equality.
@Test @MainActor func theScrollbarFadeIsTheSameWithMovesInBetween() async throws {
    let still = try codeWindow(), moved = try codeWindow()
    for w in [still, moved] { try await w.runUntilIdle(); w.hover(at: pt(100, 60)); w.scroll(at: pt(100, 60), byDeltaX: 0, deltaY: -20) }
    var thumbs: [[Float]] = []
    for step in 0..<30 {
        still.advance(by: 0.1)
        moved.hover(at: pt(100 + Float(step % 5), 60))
        moved.advance(by: 0.1)
        let a = still.scene.rects.last.map { [Float($0.background.a)] } ?? [], b = moved.scene.rects.last.map { [Float($0.background.a)] } ?? []
        #expect(a == b, "step \(step): \(a) != \(b)")
        thumbs.append(b)
    }
    #expect(Set(thumbs.map { $0.first ?? -1 }).count > 2, "the fade actually ramps: \(thumbs.prefix(12))")
}

/// 7 — the pointer style is resolved on the move from the last frame's hitboxes (`updatePointerStyle`), not in a frame, so a
/// move that skips its frame still updates the cursor: a style region inside the view's one topmost hitbox (the left 100 points
/// say `.link`, the rest nothing) sends `link` on entering it and the default on leaving, with no frame drawn for either.
/// `CodeView` and the scroll chrome set no region-dependent cursor of their own today, so the pin is the mechanism: style regions
/// are looked up on the move (`PointerStyle.swift`), never per frame. **Mutation:** `pointerMoveChangesNothing` returning `false`
/// reddens the frame expectation only.
@Test @MainActor func aMoveWithinOneHitboxStillUpdatesTheCursorWithoutAFrame() async throws {
    let buffer = CodeBuffer(rowText)
    let w = try harnessWindow {
        ZStack(alignment: .topLeading) {
            CodeView(buffer: buffer, decorations: CodeDecorations(buffer: buffer)).font(size: 12).showsLineNumbers(true)
                .codeCaretBlink(.off).frame(width: Pixels(400), height: Pixels(300))
            Rectangle(width: Pixels(100), height: Pixels(300), color: .clear).pointerStyle(.link)
        }
    }
    try await w.runUntilIdle()
    w.hover(at: pt(250, 100))
    let sends = w.platformWindow.pointerStyles
    let into = cost(w) { w.hover(at: pt(50, 100)) }
    let entered = w.platformWindow.pointerStyles
    #expect(entered.count == sends.count + 1 && entered.last != sends.last, "the link cursor on entering: \(sends) -> \(entered)")
    let out = cost(w) { w.hover(at: pt(250, 101)) }
    let left = w.platformWindow.pointerStyles
    #expect(left.count == entered.count + 1 && left.last == sends.last, "and the old one on leaving: \(left)")
    #expect(into.frames == 0 && out.frames == 0, "and neither move drew a frame (the skip is live): \(into), \(out)")
}
