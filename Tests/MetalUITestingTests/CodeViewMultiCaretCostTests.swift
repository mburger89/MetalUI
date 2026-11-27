import Testing
import Foundation
import MetalUI
import MetalUIScene
import MetalUITesting

// What drawing every caret costs (`CV-BG`, record 340): the steady and keystroke frames of a view with 1, 3 and 50
// carets all cost what the one-caret view costs, which is what master costs (literals measured on master 66cfba26,
// where only the primary was drawn). PLAIN imports; the harness text system; counters, never a clock.

private struct Cost: Equatable, CustomStringConvertible {
    var requests = 0, hits = 0, misses = 0, ineligible = 0, frames = 0
    init(requests: Int, hits: Int, misses: Int, ineligible: Int, frames: Int) {
        self.requests = requests; self.hits = hits; self.misses = misses; self.ineligible = ineligible; self.frames = frames
    }
    /// The same work per frame (off Darwin the number of frames a keystroke spans depends on the main-actor hop and
    /// the blink timer, so totals are compared per frame there).
    func perFrameEquals(_ o: Cost) -> Bool {
        frames > 0 && o.frames > 0
            && requests * o.frames == o.requests * frames && hits * o.frames == o.hits * frames
            && misses * o.frames == o.misses * frames && ineligible * o.frames == o.ineligible * frames
    }
    var description: String { "requests \(requests) hits \(hits) misses \(misses) ineligible \(ineligible) frames \(frames)" }
    init(_ f: FrameWork, frames: Int) {
        requests = f.elementRequests; hits = f.retainedHits; misses = f.retainedMisses; ineligible = f.retainedIneligible
        self.frames = frames
    }
}

private struct Card: Component, @MainActor Equatable {
    let buffer: CodeBuffer
    let decorations: CodeDecorations
    let blink: CodeCaretBlink
    var content: some ElementGroup {
        CodeView(buffer: buffer, decorations: decorations).font(size: 12).showsLineNumbers(false).codeCaretBlink(blink)
    }
    static func == (l: Card, r: Card) -> Bool { l.buffer === r.buffer && l.decorations === r.decorations && l.blink == r.blink }
}

/// `carets` carets, one to a row from row 0, at column 3; the first is the primary.
@MainActor private func place(_ buffer: CodeBuffer, carets: Int) {
    let snap = buffer.snapshot()
    let sels = (0..<carets).map { CodeSelection(caret: snap.offset(of: CodePoint(row: $0, column: 3))) }
    buffer.selectionState.setSelections(sels, primary: 0)
}

@MainActor private func open(carets: Int, views: Int, blink: CodeCaretBlink) async throws -> (TestWindow, CodeBuffer) {
    let buffer = CodeBuffer(codeText(lines: 60))
    let decorations = (0..<views).map { _ in CodeDecorations(buffer: buffer) }
    let w = try harnessWindow(size: sz(400, 200)) {
        HStack(spacing: 0) {
            ForEach(0..<views, id: \.self) { i in
                Card(buffer: buffer, decorations: decorations[i], blink: blink).equatable().frame(width: Pixels(180), height: Pixels(150))
            }
        }
    }
    w.click(at: pt(60, 6))
    place(buffer, carets: carets)
    for _ in 0..<4 { w.window.setNeedsRedraw(); try await w.runUntilIdle() }
    return (w, buffer)
}

@MainActor private func steady(carets: Int, views: Int, blink: CodeCaretBlink = .off) async throws -> Cost {
    let (w, _) = try await open(carets: carets, views: views, blink: blink)
    defer { withExtendedLifetime(w) {} }
    w.resetFrameWork()
    w.window.setNeedsRedraw(); try await w.runUntilIdle()
    return Cost(totalWork(w), frames: w.frameWork.count)
}

@MainActor private func keystroke(carets: Int, blink: CodeCaretBlink = .off) async throws -> Cost {
    let (w, buffer) = try await open(carets: carets, views: 1, blink: blink)
    defer { withExtendedLifetime(w) {} }
    w.resetFrameWork()
    w.typeText("a")
    try await w.runUntilIdle()
    #expect(buffer.selections.count == carets)
    return Cost(totalWork(w), frames: w.frameWork.count)
}

@MainActor private func idle(carets: Int) async throws -> Cost {
    let (w, _) = try await open(carets: carets, views: 1, blink: .off)
    defer { withExtendedLifetime(w) {} }
    w.resetFrameWork()
    try await w.runUntilIdle()
    return Cost(totalWork(w), frames: w.frameWork.count)
}

/// **1** A steady frame of one retained view and of two costs the same with 1, 3 and 50 carets, and what master
/// costs (2 requests, 0/1/0 retention; 3 requests, 1/1/0). **Mutation:** a wrapper element per caret (the request
/// count grows with the carets); carets painted through an element or a retention taint (misses or ineligible move).
@Test @MainActor func aSteadyFrameCostsWhatItDidWithOneCaretWhateverTheCaretCount() async throws {
    for n in [1, 3, 50] {
        let one = try await steady(carets: n, views: 1), two = try await steady(carets: n, views: 2)
        #expect(one == Cost(requests: 2, hits: 1, misses: 0, ineligible: 0, frames: 1), "\(n) carets, one view: \(one)")
        #expect(two == Cost(requests: 3, hits: 2, misses: 0, ineligible: 0, frames: 1), "\(n) carets, two views: \(two)")
    }
}

/// **2** A keystroke frame costs the same with 1, 3 and 50 carets (the same typed character at each), blink off and
/// on; the blinking view is retention-ineligible (its caret is a function of the clock), as on master.
/// **Mutation:** a per-caret retention taint or element.
@Test @MainActor func aKeystrokeFrameCostsWhatItDidWithOneCaretWhateverTheCaretCount() async throws {
    // Off Darwin the typed key's dirty mark hops to the main actor through a `Task`, so the keystroke spans two
    // frames there for one caret as for fifty; the literal is pinned on Apple platforms, and everywhere the cost must
    // not depend on the caret count.
    let baseOff = try await keystroke(carets: 1), baseOn = try await keystroke(carets: 1, blink: .on)
    #if canImport(Darwin)
    #expect(baseOff == Cost(requests: 2, hits: 0, misses: 1, ineligible: 0, frames: 1), "1 caret, blink off: \(baseOff)")
    #expect(baseOn == Cost(requests: 2, hits: 0, misses: 0, ineligible: 1, frames: 1), "1 caret, blink on: \(baseOn)")
    #endif
    for n in [3, 50] {
        let off = try await keystroke(carets: n), on = try await keystroke(carets: n, blink: .on)
        #if canImport(Darwin)
        #expect(off == baseOff, "\(n) carets, blink off: \(off) vs one caret \(baseOff)")
        #expect(on == baseOn, "\(n) carets, blink on: \(on) vs one caret \(baseOn)")
        #else
        #expect(off.perFrameEquals(baseOff), "\(n) carets, blink off: \(off) vs one caret \(baseOff)")
        #expect(on.perFrameEquals(baseOn), "\(n) carets, blink on: \(on) vs one caret \(baseOn)")
        #endif
    }
}

/// **3** With the blink off, an idle view with three carets costs nothing: no frame, no request. **Mutation:** a
/// caret path noting a deadline or an animation when the blink is off (a frame at each half second).
@Test @MainActor func anIdleViewWithThreeSolidCaretsCostsNothing() async throws {
    let (w, _) = try await open(carets: 3, views: 1, blink: .off)
    defer { withExtendedLifetime(w) {} }
    #expect(caretBars(w).count == 3)
    w.resetFrameWork()
    let frames = w.framesDrawn
    for _ in 0..<8 { w.advance(by: 0.25) }
    try await w.runUntilIdle()
    #expect(w.framesDrawn == frames && totalWork(w).elementRequests == 0 && !w.window.hasActiveAnimations,
            "frames \(w.framesDrawn - frames), requests \(totalWork(w).elementRequests)")
    let cost = try await idle(carets: 3)
    #expect(cost.requests == 0 && cost.frames == 0, "\(cost)")
}
