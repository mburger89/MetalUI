import Testing
import Foundation
import MetalUI
import MetalUIScene
import MetalUITesting

// What the selection helpers do in a view (`CV-BJ`, record 345): they reveal the new primary with the least scroll, not
// centred, and cost a frame what a plain selection write costs. PLAIN imports; the harness text system; state, never a clock.

/// 1000 rows `row N`, with `needle` on rows 0, 100 and 500.
private func needleText() -> String {
    (0..<1000).map { [0, 100, 500].contains($0) ? "row \($0) needle" : "row \($0)" }.joined(separator: "\n")
}

private struct Card: Component, @MainActor Equatable {
    let buffer: CodeBuffer
    let decorations: CodeDecorations
    let state: CodeSelectionState
    let scroll: CodeScrollState
    var content: some ElementGroup {
        CodeView(buffer: buffer, decorations: decorations).font(size: 12).showsLineNumbers(false)
            .codeCaretBlink(.off).selectionState(state).scrollState(scroll)
    }
    static func == (l: Card, r: Card) -> Bool { l.buffer === r.buffer && l.decorations === r.decorations && l.state === r.state && l.scroll === r.scroll }
}

@MainActor private struct Rig {
    let buffer = CodeBuffer(needleText())
    let state: CodeSelectionState
    let scroll = CodeScrollState()
    let window: TestWindow
    init() throws {
        let buffer = self.buffer, scroll = self.scroll
        let state = CodeSelectionState(buffer: buffer)
        self.state = state
        let decorations = CodeDecorations(buffer: buffer)
        window = try harnessWindow(size: sz(400, 200)) {
            Card(buffer: buffer, decorations: decorations, state: state, scroll: scroll).equatable().frame(width: Pixels(380), height: Pixels(180))
        }
        window.window.setNeedsRedraw(); window.tick()
    }
    func needle(_ row: Int) -> Range<Int> {
        let o = buffer.snapshot().offset(of: CodePoint(row: row, column: 0))
        return (o + (row == 0 ? 6 : row < 10 ? 6 : row < 100 ? 7 : 8))..<(o + (row == 0 ? 12 : row < 100 ? 13 : 14))
    }
    func settle() async throws { try await window.runUntilIdle(); for _ in 0..<3 { window.window.setNeedsRedraw(); window.tick() } }
}

/// **1** Skipping to a match below the view scrolls it in by the least distance (its row ends at the bottom), where
/// `select(_:reveal: true)` centres it. **Mutation:** the helper bumping `revealSerial` (centres) leaves the two
/// positions equal; the plan ignoring `nearestRevealSerial` leaves the view at row 0.
@Test @MainActor func aHelperRevealsWithTheLeastScrollNotCentred() async throws {
    let centred = try Rig()
    centred.state.select(centred.needle(0), reveal: false)
    try await centred.settle()
    centred.state.select(centred.needle(100), reveal: true)
    try await centred.settle()

    let r = try Rig()
    r.state.select(r.needle(0), reveal: false)
    try await r.settle()
    #expect(r.scroll.position.row == 0)
    #expect(r.state.skipToNextOccurrence())
    #expect(r.state.primarySelection.range == r.needle(100))
    try await r.settle()
    let top = r.scroll.position.row, centredTop = centred.scroll.position.row
    #expect(centredTop > 90 && centredTop < 100, "centred \(centredTop)")
    #expect(top < centredTop && top > 80 && top <= 100, "least scroll \(top) against centred \(centredTop)")
    withExtendedLifetime((centred, r)) {}
}

/// **2** A match already in view does not scroll the view, and addCaret reveals too. **Mutation:** the reveal
/// centring regardless of visibility (the position moves).
@Test @MainActor func aVisibleResultDoesNotScroll() async throws {
    let r = try Rig()
    r.state.select(r.needle(0), reveal: false)
    r.scroll.position = CodeScrollPosition(row: 0)
    try await r.settle()
    r.state.setSelections([CodeSelection(caret: 3)], primary: 0)
    #expect(r.state.addCaret(lineDelta: 1))
    try await r.settle()
    #expect(r.scroll.position.row == 0, "\(r.scroll.position.row)")
    for _ in 0..<40 { _ = r.state.addCaret(lineDelta: 1) }
    try await r.settle()
    let head = r.buffer.snapshot().point(at: r.state.primarySelection.head).row
    #expect(head == 41 && r.scroll.position.row > 25 && r.scroll.position.row <= 41, "head \(head), top \(r.scroll.position.row)")
}

/// **3** A view mounted after a helper ran does not scroll for it (the first frame only records the serial).
/// **Mutation:** the first frame honouring a nonzero `nearestRevealSerial`.
@Test @MainActor func aHelperBeforeTheFirstFrameScrollsNothing() async throws {
    let buffer = CodeBuffer(needleText())
    let state = CodeSelectionState(buffer: buffer)
    state.select(0..<0, reveal: false)
    state.setSelections([CodeSelection(anchor: 10, head: 12)], primary: 0)
    _ = state.selectAllOccurrences()
    let scroll = CodeScrollState()
    let decorations = CodeDecorations(buffer: buffer)
    let w = try harnessWindow(size: sz(400, 200)) {
        CodeView(buffer: buffer, decorations: decorations).font(size: 12).showsLineNumbers(false)
            .codeCaretBlink(.off).selectionState(state).scrollState(scroll)
    }
    try await w.runUntilIdle()
    #expect(scroll.position.row == 0)
}

private struct Cost: Equatable, CustomStringConvertible {
    var requests = 0, hits = 0, misses = 0, ineligible = 0
    var description: String { "requests \(requests) hits \(hits) misses \(misses) ineligible \(ineligible)" }
}

/// **4** A frame after a helper costs the same element requests as after the equivalent plain selection write
/// (literal). **Mutation:** the plan or the state doing per-selection or per-match work in the frame (requests move).
@Test @MainActor func aHelperFrameCostsWhatAPlainSelectionWriteCosts() async throws {
    func measure(_ write: (Rig) -> Void) async throws -> Cost {
        let r = try Rig()
        r.state.select(r.needle(0), reveal: false)
        try await r.settle()
        r.window.resetFrameWork()
        write(r)
        r.window.window.setNeedsRedraw()
        try await r.window.runUntilIdle()
        let f = totalWork(r.window)
        return Cost(requests: f.elementRequests, hits: f.retainedHits, misses: f.retainedMisses, ineligible: f.retainedIneligible)
    }
    let helper = try await measure { r in _ = r.state.skipToNextOccurrence() }
    let plain = try await measure { r in r.state.setSelections([CodeSelection(anchor: r.needle(100).lowerBound, head: r.needle(100).upperBound)], primary: 0) }
    #expect(helper == plain, "\(helper) vs \(plain)")
    #expect(helper == Cost(requests: 1, hits: 0, misses: 1, ineligible: 0), "\(helper)")
}
