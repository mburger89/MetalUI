import Testing
import Foundation
import Observation
import MetalUI
import MetalUIScene
import MetalUITesting

// A reveal requested before the view's first frame is applied on its first laid-out frame (`CV-BA`, record 330).
// PLAIN imports; the harness text system; every pin reads state, never a clock.

@MainActor @Observable private final class Mount {
    var shown = false
    var shownTwice = false
    var height = 200.0
}

@MainActor private struct Rig {
    let buffer = CodeBuffer(codeText(lines: 1000))
    let state: CodeSelectionState
    let scroll = CodeScrollState(), scrollTwo = CodeScrollState()
    let mount = Mount()
    let window: TestWindow
    init() throws {
        let buffer = self.buffer, mount = self.mount, scroll = self.scroll, scrollTwo = self.scrollTwo
        let state = CodeSelectionState(buffer: buffer)
        self.state = state
        let decorations = CodeDecorations(buffer: buffer)
        func view(_ s: CodeScrollState) -> CodeView {
            CodeView(buffer: buffer, decorations: decorations).font(size: 12).showsLineNumbers(false)
                .codeCaretBlink(.off).selectionState(state).scrollState(s)
        }
        window = try harnessWindow(size: sz(400, 200)) {
            VStack(spacing: 0) {
                if mount.shown { view(scroll).frame(height: Pixels(Float(mount.height))) }
                if mount.shownTwice { view(scrollTwo).frame(height: Pixels(100)) }
            }
        }
        window.window.setNeedsRedraw(); window.tick()
    }
    func at(_ row: Int) -> Range<Int> {
        let o = buffer.snapshot().offset(of: CodePoint(row: row, column: 0)); return o..<o
    }
    func frames(_ n: Int = 4) { for _ in 0..<n { window.window.setNeedsRedraw(); window.tick() } }
}

/// **1** A reveal requested in the transaction that mounts the view centres the caret line on the first frame.
/// **Mutation:** the first frame honouring no reveal (`reveals = false` for a mount) leaves the view at row 0.
@Test @MainActor func aRevealInTheMountingTransactionIsApplied() async throws {
    let r = try Rig()
    r.state.select(r.at(500), reveal: true)
    r.mount.shown = true
    try await r.window.runUntilIdle()
    r.frames()
    #expect(r.scroll.position.row > 480 && r.scroll.position.row < 500, "centred: \(r.scroll.position.row)")
}

/// **2** A reveal requested while no view is mounted is applied when one mounts later (pending until a view takes it
/// in). **Mutation:** as 1.
@Test @MainActor func aRevealMadeWhileUnmountedIsAppliedOnTheNextMount() async throws {
    let r = try Rig()
    r.state.select(r.at(300), reveal: true)
    r.frames(5)
    r.mount.shown = true
    try await r.window.runUntilIdle()
    r.frames()
    #expect(r.scroll.position.row > 280 && r.scroll.position.row < 300, "\(r.scroll.position.row)")
}

/// **3** A reveal a view already took in is stale for a later mount of another view of that state, and for a remount.
/// **Mutation:** a mount honouring every `revealSerial != 0` (no handled record) scrolls the second view to 400.
@Test @MainActor func aHandledRevealIsStaleForLaterMounts() async throws {
    let r = try Rig()
    r.mount.shown = true
    try await r.window.runUntilIdle()
    r.frames()
    r.state.select(r.at(400), reveal: true)
    try await r.window.runUntilIdle()
    r.frames()
    #expect(r.scroll.position.row > 380, "the first view revealed: \(r.scroll.position.row)")
    r.mount.shownTwice = true
    try await r.window.runUntilIdle()
    r.frames()
    #expect(r.scrollTwo.position.row == 0, "another view mounting later: \(r.scrollTwo.position.row)")
    r.mount.shown = false
    r.frames()
    r.scroll.position = CodeScrollPosition(row: 50)   // the scroll state is adopted on mount; a replayed reveal would override it
    r.mount.shown = true
    try await r.window.runUntilIdle()
    r.frames()
    #expect(r.scroll.position.row == 50, "a remount: \(r.scroll.position.row)")
}

/// **4** Two views mounting in one transaction with a pending reveal both apply it. **Mutation:** dropping the
/// same-frame clause (`revealHandledFrame === frame`) leaves the second at row 0.
@Test @MainActor func twoViewsMountingTogetherBothApplyThePendingReveal() async throws {
    let r = try Rig()
    r.state.select(r.at(500), reveal: true)
    r.mount.shown = true; r.mount.shownTwice = true
    try await r.window.runUntilIdle()
    r.frames()
    #expect(r.scroll.position.row > 480 && r.scrollTwo.position.row > 490, "\(r.scroll.position.row) \(r.scrollTwo.position.row)")
}

/// **5** A first frame without a viewport leaves the reveal pending; the first frame with one applies it.
/// **Mutation:** dropping the viewport guard consumes the reveal at zero height and the view stays at row 0.
@Test @MainActor func aZeroSizedFirstFrameKeepsTheRevealPending() async throws {
    let r = try Rig()
    r.mount.height = 0
    r.state.select(r.at(500), reveal: true)
    r.mount.shown = true
    try await r.window.runUntilIdle()
    r.frames()
    r.mount.height = 200
    try await r.window.runUntilIdle()
    r.frames()
    #expect(r.scroll.position.row > 480 && r.scroll.position.row < 500, "\(r.scroll.position.row)")
}

private struct Card: Component, @MainActor Equatable {
    let buffer: CodeBuffer
    let decorations: CodeDecorations
    let state: CodeSelectionState
    var content: some ElementGroup {
        CodeView(buffer: buffer, decorations: decorations).font(size: 12).showsLineNumbers(false).codeCaretBlink(.off).selectionState(state)
    }
    static func == (l: Card, r: Card) -> Bool { l.buffer === r.buffer && l.decorations === r.decorations && l.state === r.state }
}

private struct Steady: Equatable { var requests = 0, hits = 0, misses = 0, ineligible = 0 }

/// **6** A view with no pending reveal (one taken in at mount, one a view already handled) costs what it did on
/// master ab099a02: one retained card 4 requests / 0 hits / 1 miss / 0 ineligible, two 5 / 1 / 1 / 0.
@Test @MainActor func aSteadyFrameWithAHandledRevealCostsWhatItDidBefore() throws {
    func run(views: Int) throws -> Steady {
        let buffer = CodeBuffer(codeText(lines: 60))
        let decorations = (0..<views).map { _ in CodeDecorations(buffer: buffer) }
        let state = CodeSelectionState(buffer: buffer)
        state.select(0..<0, reveal: true)   // pending at mount, handled by the first frame
        let w = try harnessWindow(size: sz(400, 200)) {
            HStack(spacing: 0) {
                Box().frame(width: Pixels(20), height: Pixels(20)).focusable()
                ForEach(0..<views, id: \.self) { i in
                    Card(buffer: buffer, decorations: decorations[i], state: state).equatable()
                        .frame(width: Pixels(180), height: Pixels(150))
                }
            }
        }
        for _ in 0..<4 { w.window.setNeedsRedraw(); w.tick() }
        w.resetFrameWork()
        w.window.setNeedsRedraw(); w.tick()
        let f = totalWork(w)
        return Steady(requests: f.elementRequests, hits: f.retainedHits, misses: f.retainedMisses, ineligible: f.retainedIneligible)
    }
    let one = try run(views: 1), two = try run(views: 2)
    #expect(one == Steady(requests: 4, hits: 0, misses: 1, ineligible: 0), "\(one)")
    #expect(two == Steady(requests: 5, hits: 1, misses: 1, ineligible: 0), "\(two)")
}
