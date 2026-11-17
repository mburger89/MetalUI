import Foundation
import MetalUITesting
import MetalUIPlatform
import MetalUITerminal
import Testing
@testable import MetalUI
@testable import MetalUITerminalUI

// Terminal phase 5.5 (`TRM-BD`), selection, copy, links and cost. Each test names the mutation it was shown red against.

private func linkTarget(_ q: TerminalLinkQuery) -> TerminalLinkTarget? {
    guard q.phase != .exit, let range = q.rowText.range(of: "http://a.test/x") else { return nil }
    let lo = q.rowText.distance(from: q.rowText.startIndex, to: range.lowerBound)
    let hi = q.rowText.distance(from: q.rowText.startIndex, to: range.upperBound)
    return (lo..<hi).contains(q.cell.col) ? TerminalLinkTarget(columns: lo..<hi, payload: "http://a.test/x") : nil
}

@MainActor private func sum(_ rig: TermRig, _ key: KeyPath<FrameWork, Int>) -> Int { rig.window.frameWork.map { $0[keyPath: key] }.reduce(0, +) }

/// **7** (`REQUIRED`) A drag selects linearly (inclusive of both end cells), ⌥-drag a block, and the text reads back; a click
/// without moving out of its cell selects nothing and a new click clears the old selection. (⌥ is Terminal.app's block key.)
/// Mutation: ignore ⌥ (the block case reads linear); extend the end by one cell; keep the selection on a plain click.
@MainActor @Test func draggingSelectsAndOptionDraggingSelectsABlock() async throws {
    let rig = try TermRig()
    await rig.settle()
    rig.feed("hello world\r\nsecond line\r\n")
    await rig.settle()
    rig.window.drag(from: rig.point(0, 0), to: rig.point(0, 4))
    #expect(await rig.selectedText() == "hello")
    guard case .linear? = await rig.selection() else { Issue.record("not linear"); return }
    rig.window.drag(from: rig.point(0, 1), to: rig.point(1, 3), modifierFlags: .option)
    #expect(await rig.selectedText() == "ell\neco")
    guard case .block? = await rig.selection() else { Issue.record("not block"); return }
    rig.window.click(at: rig.point(5, 5))
    #expect(await rig.selection() == nil, "a click clears")
    rig.press(at: rig.point(0, 2)); rig.dragged(to: rig.point(0, 2)); rig.release(at: rig.point(0, 2))
    #expect(await rig.selection() == nil, "a drag within the cell selects nothing")
    #expect(rig.sent.isEmpty)
}

/// **8** Double-click selects the word, triple-click the logical line; ⇧-click extends the nearer end.
/// Mutation: swap word and line; extend the far end.
@MainActor @Test func wordLineAndShiftExtend() async throws {
    let rig = try TermRig()
    await rig.settle()
    rig.feed("hello world foo\r\n")
    await rig.settle()
    rig.window.doubleClick(at: rig.point(0, 7))
    #expect(await rig.selectedText() == "world")
    for n in 1...3 {
        rig.press(at: rig.point(0, 7), clickCount: n); rig.release(at: rig.point(0, 7))
    }
    #expect(await rig.selectedText() == "hello world foo")
    rig.window.drag(from: rig.point(0, 0), to: rig.point(0, 4))
    _ = await rig.selection()
    rig.window.click(at: rig.point(0, 9), modifierFlags: .shift)
    #expect(await rig.selectedText() == "hello worl")
    rig.window.click(at: rig.point(0, 2), modifierFlags: .shift)
    #expect(await rig.selectedText() == "llo worl", "the nearer end (the start) moved")
}

/// **9** ⌘C copies the selected text; with no selection it writes nothing.
/// Mutation: copy the whole row; copy without the text fetch.
@MainActor @Test func commandCCopiesTheSelection() async throws {
    let rig = try TermRig()
    await rig.settle()
    rig.feed("hello world\r\n")
    await rig.settle()
    rig.window.typeKey("c", modifierFlags: .command)
    #expect(rig.window.clipboardRepresentations.isEmpty)
    rig.window.drag(from: rig.point(0, 6), to: rig.point(0, 10))
    await rig.settle()
    rig.window.typeKey("c", modifierFlags: .command)
    #expect(rig.window.platformWindow.clipboard == "world", "\(String(describing: rig.window.platformWindow.clipboard))")
    #expect(rig.sent.isEmpty)
}

/// **10** (`REQUIRED`) A drag held past the bottom or top edge scrolls the viewport on timed frames and the selection's end
/// follows the edge; releasing stops it.
/// Mutation: no autoscroll step; keep stepping after the release.
@MainActor @Test func aDragPastTheEdgeAutoscrolls() async throws {
    let rig = try TermRig()
    await rig.settle()
    await rig.fill(80)
    rig.wheel(at: rig.point(2, 2), dy: 1000)   // to the top of scrollback
    await rig.settle()
    let start = rig.viewportOffset
    #expect(start > 20)
    rig.press(at: rig.point(10, 3))
    rig.dragged(to: rig.pointBelowEdge(rows: 3))
    for _ in 0..<5 { await rig.frame(0.05); await rig.frame(0.05) }
    #expect(rig.viewportOffset < start - 5, "scrolled forward: \(start) -> \(rig.viewportOffset)")
    let selection = try #require(await rig.selection())
    guard case .linear(let range) = selection else { Issue.record("not linear"); return }
    #expect(max(range.lowerBound.row, range.upperBound.row) == (rig.model.snapshot?.topRow ?? 0) + (rig.model.snapshot?.size.rows ?? 0) - 1)
    rig.release(at: rig.pointBelowEdge(rows: 3))
    await rig.settle()
    let stopped = rig.viewportOffset
    for _ in 0..<6 { await rig.frame(0.05) }
    #expect(rig.viewportOffset == stopped, "released: no more scrolling")
}

/// **11** (`REQUIRED`) ⌘-hover asks `onLink(.hover)` once per cell change (never without ⌘), `.exit` when the cell is left,
/// ⌘ is released or the pointer leaves, and ⌘-click sends `.activate`; the pointing hand shows over a link and goes away.
/// Mutation: query on every move; send no exit; no pointer style.
@MainActor @Test func commandHoverQueriesOncePerCell() async throws {
    let rig = try TermRig()
    rig.knobs.link = linkTarget
    await rig.settle()
    rig.feed("see http://a.test/x here\r\n")
    await rig.settle()
    rig.window.hover(at: rig.point(0, 6))
    #expect(rig.log.links.isEmpty, "no ⌘, no query")
    rig.window.pressModifiers(.command)
    let top = rig.model.snapshot?.topRow ?? 0
    func cell(_ c: Int) -> TerminalPosition { TerminalPosition(row: top, col: c) }
    let text = "see http://a.test/x here"
    #expect(rig.log.links == [TerminalLinkQuery(cell: cell(6), rowText: text, phase: .hover)], "\(rig.log.links)")
    var nudged = rig.point(0, 6); nudged.x = nudged.x + Pixels(1)
    rig.window.hover(at: nudged)
    #expect(rig.log.links.count == 1, "within the cell: no query")
    rig.window.hover(at: rig.point(0, 8))
    #expect(Array(rig.log.links.dropFirst()) == [TerminalLinkQuery(cell: cell(6), rowText: text, phase: .exit),
                                                 TerminalLinkQuery(cell: cell(8), rowText: text, phase: .hover)])
    await rig.settle()
    #expect(rig.model.pointer.link?.columns == 4..<19)
    #expect(rig.window.pointerStyle == .pointingHand, "\(String(describing: rig.window.pointerStyle))")
    rig.log.links = []
    rig.window.click(at: rig.point(0, 8), modifierFlags: .command)
    #expect(rig.log.links.last?.phase == .activate && rig.log.links.last?.cell == cell(8), "\(rig.log.links)")
    rig.log.links = []
    rig.window.hover(at: rig.point(0, 1))
    await rig.settle()
    #expect(rig.model.pointer.link == nil && rig.window.pointerStyle != .pointingHand)
    rig.log.links = []
    rig.window.pressModifiers([])
    #expect(rig.log.links.map(\.phase) == [.exit], "releasing ⌘: \(rig.log.links)")
    rig.window.pressModifiers(.command)
    rig.log.links = []
    rig.window.exitPointer()
    #expect(rig.log.links.map(\.phase) == [.exit], "leaving: \(rig.log.links)")
}

/// **12** OSC 8 hyperlinks are offered: the host is asked first, and when it answers nothing the run of cells with the
/// link id is the target; ⌘-click opens its URL through `openURL`.
/// Mutation: skip the OSC 8 fallback; open on hover.
@MainActor @Test func osc8LinksAreOffered() async throws {
    let rig = try TermRig()
    await rig.settle()
    rig.feed("\u{1B}]8;;https://osc.test/p\u{07}docs\u{1B}]8;;\u{07} tail\r\n")
    await rig.settle()
    rig.window.pressModifiers(.command)
    rig.window.hover(at: rig.point(0, 2))
    await rig.settle()
    #expect(rig.log.links.map(\.phase) == [.hover], "the host was asked")
    #expect(rig.model.pointer.link == TerminalLinkHit(row: rig.model.snapshot?.topRow ?? 0, columns: 0..<4,
                                                      payload: "https://osc.test/p", fromHost: false))
    #expect(rig.log.opened.isEmpty)
    rig.window.click(at: rig.point(0, 2), modifierFlags: .command)
    #expect(rig.log.opened == [URL(string: "https://osc.test/p")!], "\(rig.log.opened)")
    rig.window.hover(at: rig.point(0, 6))
    await rig.settle()
    #expect(rig.model.pointer.link == nil)
}

/// **13** (`REQUIRED`) Cost. A window dirties itself for every pointer event (`Window`'s input tail; `FP-T`, #363, spares only an
/// unclaimed move within one hitbox and is not on this base), so the pointer wiring is judged against a twin window with no
/// terminal: the same hover script draws the same frames and builds, plain and with ⌘ over a link, and the callbacks add no
/// frame of their own. Entering a link builds once more (the pointer style); a build costs the view's own requests. A selection
/// drag event is one build and the same requests as a plain redraw, and its surface redraw touches only the selected row.
/// Mutation: request a redraw on every hover; write the pointer-style state on every query.
@MainActor @Test func pointerCostsAreThoseOfAnyPointerEvent() async throws {
    func script(_ rig: TermRig, command: Bool) async -> (frames: Int, builds: Int, draws: Int) {
        await rig.settle()
        if command { rig.window.pressModifiers(.command); await rig.settle() }
        rig.window.resetFrameWork()
        let frames = rig.window.framesDrawn, draws = rig.window.surfaceDrawCount
        for c in 0..<20 { rig.window.hover(at: rig.point(0, c)); await rig.pump() }
        var p = rig.point(1, 3)
        for _ in 0..<5 { p.x = p.x + Pixels(0.5); rig.window.hover(at: p) }
        await rig.pump()
        return (rig.window.framesDrawn - frames, sum(rig, \.builds), rig.window.surfaceDrawCount - draws)
    }
    let twin = try TermRig(terminal: false)
    let base = await script(twin, command: false)
    let plain = try TermRig()
    plain.knobs.link = linkTarget
    plain.feed("see http://a.test/x here http://a.test/x\r\nsecond line of text\r\n")
    let plainResult = await script(plain, command: false)
    #expect(plainResult.frames == base.frames && plainResult.builds == base.builds && plainResult.draws == base.draws,
            "plain hover: \(plainResult) vs the twin \(base)")
    #expect(plain.log.links.isEmpty)
    let twinCommand = try TermRig(terminal: false)
    let baseCommand = await script(twinCommand, command: true)
    let linked = try TermRig()
    linked.knobs.link = linkTarget
    linked.feed("see http://a.test/x here http://a.test/x\r\nsecond line of text\r\n")
    // Row 0 is the link row: moves within it and onto text, the link entered once.
    let withCommand = await script(linked, command: true)
    #expect(withCommand.frames <= baseCommand.frames + 1 && withCommand.builds <= baseCommand.builds + 1,
            "⌘ hover over a link row: \(withCommand) vs \(baseCommand)")
    #expect(linked.log.links.filter { $0.phase == .hover }.count == 21, "one query per cell change: 20 cells of row 0 and the move to row 1, none for 5 nudges within a cell: \(linked.log.links.count)")
    // Moving within the link: no more frames than the twin.
    let rig = linked
    rig.window.hover(at: rig.point(0, 6)); await rig.settle()
    rig.window.resetFrameWork()
    let frames = rig.window.framesDrawn
    rig.window.hover(at: rig.point(0, 7)); rig.window.hover(at: rig.point(0, 12)); await rig.pump()
    let move = rig.window.framesDrawn - frames
    let twinFrames = twinCommand.window.framesDrawn
    twinCommand.window.hover(at: rig.point(0, 7)); twinCommand.window.hover(at: rig.point(0, 12)); await twinCommand.pump()
    #expect(move == twinCommand.window.framesDrawn - twinFrames, "within a link \(move) frames")
    #expect(sum(rig, \.builds) == move, "each is the plain rebuild: \(sum(rig, \.builds)) builds")
    // A selection drag: one build and the plain redraw's requests per event; the surface redraws the selected row only.
    rig.window.pressModifiers([])
    await rig.settle()
    rig.window.window.setNeedsRedraw(); rig.window.tick()
    let steady = rig.window.lastFrameWork.elementRequests
    rig.press(at: rig.point(1, 0))
    for c in 1...6 {
        rig.window.resetFrameWork()
        rig.dragged(to: rig.point(1, c)); await rig.frame()
        #expect(sum(rig, \.builds) == 1 && sum(rig, \.elementRequests) == steady, "drag \(c): builds \(sum(rig, \.builds)) requests \(sum(rig, \.elementRequests)) vs \(steady)")
        #expect(rig.model.statistics.lastRows == [1], "only the selected row redraws: \(rig.model.statistics.lastRows)")
    }
    rig.release(at: rig.point(1, 6))
    print("TRM-BD cost literals: steady \(steady), plain hover \(plainResult) twin \(base), command hover \(withCommand) twin \(baseCommand)")
}
