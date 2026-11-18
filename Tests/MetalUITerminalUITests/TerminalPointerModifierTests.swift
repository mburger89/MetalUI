import Foundation
import MetalUITesting
import MetalUIPlatform
import MetalUITerminal
import Testing
@testable import MetalUI
@testable import MetalUITerminalUI

// The pointer style while the link modifier is held (`TRM-BO`) and the cost of a selection drag (`TRM-BP`), headless on
// `TermRig`. Each test names the mutation it was shown red against (`docs/practices/verifying-tests-can-fail.md`).
// The modifier is `Modifiers.primary` (⌘ on Apple platforms, Ctrl elsewhere), never `.command`.

private func linkTarget(_ q: TerminalLinkQuery) -> TerminalLinkTarget? {
    guard q.phase != .exit, let range = q.rowText.range(of: "http://a.test/x") else { return nil }
    let lo = q.rowText.distance(from: q.rowText.startIndex, to: range.lowerBound)
    let hi = q.rowText.distance(from: q.rowText.startIndex, to: range.upperBound)
    return (lo..<hi).contains(q.cell.col) ? TerminalLinkTarget(columns: lo..<hi, payload: "http://a.test/x") : nil
}

@MainActor private func sum(_ rig: TermRig, _ key: KeyPath<FrameWork, Int>) -> Int {
    rig.window.frameWork.map { $0[keyPath: key] }.reduce(0, +)
}

@MainActor private func linkRig() async throws -> TermRig {
    let rig = try TermRig()
    rig.knobs.link = linkTarget
    await rig.settle()
    rig.feed("see http://a.test/x here\r\nplain second line\r\n")
    await rig.settle()
    return rig
}

/// **1** (`TRM-BO`) The pointing hand follows the primary modifier over a link with no pointer move: hovering the link
/// without it is not the hand; pressing it is (the style is re-resolved at the last pointer location, the host asked
/// `.hover` once); releasing it is not. Mutation: drop `Window.updatePointerStyle` from the modifier path (the hand
/// waits for a move); drop `modifiersChanged:` from the view's `pointerInput` (no link is found without a move).
@MainActor @Test func holdingPrimaryOverALinkShowsThePointingHand() async throws {
    let rig = try await linkRig()
    rig.window.hover(at: rig.point(0, 8))
    await rig.settle()
    #expect(rig.window.pointerStyle != .pointingHand, "no primary, no hand: \(String(describing: rig.window.pointerStyle))")
    let moves = rig.window.platformWindow.pointerStyles.count
    rig.window.pressModifiers(Modifiers.primary)
    #expect(rig.log.links.filter { $0.phase == .hover }.count == 1, "the host is asked once: \(rig.log.links)")
    #expect(rig.window.pointerStyle == .pointingHand, "primary held: \(String(describing: rig.window.pointerStyle))")
    #expect(rig.window.platformWindow.pointerStyles.count == moves + 1, "one platform call")
    rig.window.pressModifiers([])
    #expect(rig.window.pointerStyle != .pointingHand, "released: \(String(describing: rig.window.pointerStyle))")
    #expect(rig.log.links.last?.phase == .exit)
}

/// **2** (`TRM-BO`) Primary held with the pointer on text that is not a link, or outside the view's link, changes nothing:
/// the platform is not asked for a style, and the view shows no hand. Mutation: set the link without consulting the cell
/// (any hover shows the hand); resolve the style for the whole window rather than at the pointer.
@MainActor @Test func holdingPrimaryElsewhereChangesNothing() async throws {
    let rig = try await linkRig()
    rig.window.hover(at: rig.point(1, 3))      // the second line: no link
    await rig.settle()
    let before = rig.window.platformWindow.pointerStyles.count
    rig.window.pressModifiers(Modifiers.primary)
    #expect(rig.window.platformWindow.pointerStyles.count == before, "no style sent")
    #expect(rig.window.pointerStyle != .pointingHand)
    #expect(rig.model.pointer.link == nil)
    rig.window.pressModifiers([])
    #expect(rig.window.platformWindow.pointerStyles.count == before)
    // The pointer outside the window: a modifier change has no location to resolve.
    rig.window.exitPointer()
    await rig.settle()
    let outside = rig.window.platformWindow.pointerStyles.count
    rig.log.links = []
    rig.window.pressModifiers(Modifiers.primary)
    rig.window.pressModifiers([])
    #expect(rig.window.platformWindow.pointerStyles.count == outside, "no pointer, no resolve")
    #expect(rig.log.links.filter { $0.phase == .hover }.isEmpty, "no pointer, no query")
}

/// **3** (`TRM-BO`) A modifier change over a view with no link draws no frame, builds nothing and requests no element; over
/// a link it is the underline's one surface-only frame (0 builds, 0 requests). Mutation: observe the modifiers with
/// `onModifierKeysChanged` again (a rebuilt frame: 1 build, 2 requests) or request a redraw on every change.
@MainActor @Test func aModifierChangeDrawsNoFrame() async throws {
    let rig = try await linkRig()
    rig.window.hover(at: rig.point(1, 3))
    await rig.settle()
    rig.window.resetFrameWork()
    let frames = rig.window.framesDrawn, draws = rig.window.surfaceDrawCount
    rig.window.pressModifiers(Modifiers.primary)
    rig.window.pressModifiers([])
    // Off Darwin a dirty mark hops through a task: wait for idle, not a fixed tick (zero frames must hold once idle).
    try await rig.window.runUntilIdle()
    #expect(rig.window.framesDrawn == frames && rig.window.surfaceDrawCount == draws, "off a link: \(rig.window.framesDrawn - frames) frames")
    #expect(sum(rig, \.builds) == 0 && sum(rig, \.elementRequests) == 0)
    rig.window.hover(at: rig.point(0, 8))
    await rig.settle()
    rig.window.resetFrameWork()
    let linked = rig.window.framesDrawn, linkedDraws = rig.window.surfaceDrawCount
    rig.window.pressModifiers(Modifiers.primary)
    try await rig.window.runUntilIdle()
    #expect(rig.window.surfaceDrawCount == linkedDraws + 1, "the underline is one surface draw")
    #expect(rig.window.framesDrawn == linked + 1, "over a link: \(rig.window.framesDrawn - linked) frames")
    #expect(sum(rig, \.builds) == 0 && sum(rig, \.elementRequests) == 0, "surface only: \(sum(rig, \.builds)) \(sum(rig, \.elementRequests))")
    rig.window.pressModifiers([])
    try await rig.window.runUntilIdle()
    #expect(rig.window.surfaceDrawCount == linkedDraws + 2 && sum(rig, \.builds) == 0 && sum(rig, \.elementRequests) == 0)
}

/// **4** (`TRM-BO`, `FP-T`) The generic path: a window without a terminal (or any pointer-style region) pays nothing for a
/// modifier change, and the steady frame is what it was. Literals measured with no terminal in the window, on the code path
/// master has (the hook is behind `lastPointerStyleRegionCount > 0`). Mutation: scan or redraw without that guard
/// (`framesDrawn` moves, or `pointerStyleVisits` counts).
@MainActor @Test func aWindowWithoutATerminalPaysNothingForAModifierChange() async throws {
    let rig = try TermRig(terminal: false)
    await rig.settle()
    rig.window.window.setNeedsRedraw(); rig.window.tick()
    let steady = rig.window.lastFrameWork.elementRequests
    rig.window.hover(at: Point(x: Pixels(5), y: Pixels(5)))
    await rig.settle()
    rig.window.resetFrameWork()
    let frames = rig.window.framesDrawn, visits = rig.window.window.pointerStyleVisits
    rig.window.pressModifiers(Modifiers.primary)
    rig.window.pressModifiers([])
    try await rig.window.runUntilIdle()
    #expect(rig.window.framesDrawn == frames, "\(rig.window.framesDrawn - frames) frames")
    #expect(rig.window.window.pointerStyleVisits == visits, "no hitbox visited")
    #expect(sum(rig, \.builds) == 0 && sum(rig, \.elementRequests) == 0)
    #expect(steady == 0, "steady elementRequests \(steady)")
    print("TRM-BO cost literals: steady frame requests \(steady), modifier change frames \(rig.window.framesDrawn - frames)")
}

/// **5** (`TRM-BP`, flipped by `FP-U`) A selection drag is surface-only: 0 builds, 0 element requests and one surface draw per
/// event, redrawing only the selected row. `TRM-BP` first pinned it at 1 build and the view's own 2 requests and blamed "the
/// window's input tail dirties after every claimed pointer event"; that cause was wrong: the drag is never claimed
/// (`dispatchGestures` declines `.mouseDragged`, `IX-D` item 6, and the terminal's text target is external), it reached the
/// tail, and `FP-T` spared only `.mouseMoved`. `FP-U` widens the helper to an unclaimed drag whose hitbox is unchanged,
/// so the selection (the model's, read by the surface) is what changes and the surface redraw is the frame. Steady frame
/// literal 2 and the old drag literal (1 build, 2 requests, 1 surface draw) were measured on master `328ab5eb`.
/// Mutation: drop `.mouseDragged` from `pointerEventChangesNothing` (1 build and 2 requests per drag again); redraw the
/// whole grid per drag step (`lastRows` grows).
@MainActor @Test func aSelectionDragIsSurfaceOnly() async throws {
    let rig = try TermRig()
    await rig.settle()
    rig.feed("first row of text\r\nsecond row of text\r\nthird\r\n")
    await rig.settle()
    rig.window.window.setNeedsRedraw(); rig.window.tick()
    let steady = rig.window.lastFrameWork.elementRequests
    #expect(steady == 2, "the steady rebuilt frame's requests: \(steady)")
    rig.press(at: rig.point(1, 0))
    for c in 1...6 {
        rig.window.resetFrameWork()
        let draws = rig.window.surfaceDrawCount
        rig.dragged(to: rig.point(1, c)); await rig.frame()
        try await rig.window.runUntilIdle()
        #expect(sum(rig, \.builds) == 0 && sum(rig, \.elementRequests) == 0, "drag \(c): \(sum(rig, \.builds)) builds, \(sum(rig, \.elementRequests)) requests")
        #expect(rig.window.surfaceDrawCount - draws == 1, "one surface draw per drag step: \(rig.window.surfaceDrawCount - draws)")
        #expect(rig.model.statistics.lastRows == [1], "\(rig.model.statistics.lastRows)")
    }
    rig.release(at: rig.point(1, 6))
    print("FP-U literals: steady requests \(steady), drag event 0 builds, 0 requests, 1 surface draw, rows [1]")
}

/// **5b** (`FP-U`) A reporting terminal's secondary drag is the button arena's (`CI-F`), not the unclaimed tail's: with
/// button-event tracking on (`?1002`) a right press and a drag per cell send one report each and ask the window for no
/// build: 0 builds, 0 element requests, and every frame drawn is a surface-only one (the view's own surface trigger, measured
/// 1 per event; the plan expected none, the view redraws its surface itself). Mutation: an unconditional `setNeedsRedraw()`
/// in the button-arena branch of `Window.init`'s input handler (a build and the view's requests per event appear).
@MainActor @Test func aReportingSecondaryDragSendsBytesAndAsksForNoBuild() async throws {
    let rig = try TermRig()
    await rig.settle()
    rig.feed("first row of text\r\nsecond row of text\r\n")
    await rig.mouseMode("1002")
    rig.window.send(.rightMouseDown(MouseEvent(position: rig.point(1, 1), buttonNumber: MouseButton.secondary.buttonNumber)))
    try await rig.window.runUntilIdle()
    rig.log.inputs = []
    rig.window.resetFrameWork()
    let frames = rig.window.framesDrawn
    for c in 2...6 {
        let reports = rig.log.inputs.count
        rig.window.send(.rightMouseDragged(MouseEvent(position: rig.point(1, c), buttonNumber: MouseButton.secondary.buttonNumber)))
        try await rig.window.runUntilIdle()
        #expect(rig.log.inputs.count == reports + 1, "step \(c): one report: \(rig.log.inputs.count - reports)")
    }
    #expect(sum(rig, \.builds) == 0 && sum(rig, \.elementRequests) == 0, "\(sum(rig, \.builds)) builds, \(sum(rig, \.elementRequests)) requests")
    #expect(sum(rig, \.surfaceOnlyFrames) == rig.window.framesDrawn - frames, "every frame is surface-only: \(sum(rig, \.surfaceOnlyFrames)) of \(rig.window.framesDrawn - frames)")
    rig.window.send(.rightMouseUp(MouseEvent(position: rig.point(1, 6), buttonNumber: MouseButton.secondary.buttonNumber)))
    try await rig.window.runUntilIdle()
}

/// **6** (`TRM-BP`) An autoscroll step (the drag held still past the edge) is a timed surface redraw stepped from `draw`: 0
/// builds, 0 element requests, one surface draw, and the redrawn rows are the viewport's (it scrolled). Mutation: step the
/// autoscroll from an input event or a state write (a build per step).
@MainActor @Test func anAutoscrollStepIsSurfaceOnly() async throws {
    let rig = try TermRig()
    await rig.settle()
    await rig.fill(80)
    rig.wheel(at: rig.point(2, 2), dy: 1000)
    await rig.settle()
    rig.press(at: rig.point(10, 3))
    rig.dragged(to: rig.pointBelowEdge(rows: 3))
    await rig.frame(0.05); await rig.frame(0.05)
    for step in 0..<4 {
        rig.window.resetFrameWork()
        let draws = rig.window.surfaceDrawCount, offset = rig.viewportOffset
        await rig.frame(0.05)
        #expect(rig.viewportOffset != offset, "step \(step) scrolled")
        #expect(sum(rig, \.builds) == 0 && sum(rig, \.elementRequests) == 0, "step \(step): \(sum(rig, \.builds)) builds \(sum(rig, \.elementRequests)) requests")
        #expect(rig.window.surfaceDrawCount - draws == 1, "one surface draw: \(rig.window.surfaceDrawCount - draws)")
    }
    rig.release(at: rig.pointBelowEdge(rows: 3))
}
