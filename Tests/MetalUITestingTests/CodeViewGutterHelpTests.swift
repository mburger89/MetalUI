import Testing
import Foundation
@testable import MetalUI
import MetalUIScene
import MetalUITesting

// `CodeView.gutterHelp` (`CV-BT`, record 370): the tooltip of a gutter bar or marker, the view's model-driven `.help`
// (`MN-AJ`) answered from the last frame's plan, in input only. PLAIN imports; the harness text system; windows kept alive.

@MainActor private final class Log { var hits: [CodeGutterHit] = []; var viewHelp: [Point<Pixels>] = [] }

private struct Fx {
    let window: TestWindow
    let log: Log
    let barA: Point<Pixels>, barB: Point<Pixels>, marker: Point<Pixels>, text: Point<Pixels>
}

@MainActor private func fixture(gutterHelp: Bool = true, viewHelp: Bool = true) async throws -> Fx {
    let log = Log()
    let buffer = CodeBuffer(codeText(lines: 40))
    let decorations = CodeDecorations(buffer: buffer)
    decorations.setLineDecorations([
        CodeLineDecoration(lines: 10..<20, gutterBar: .red, tag: 7),
        CodeLineDecoration(lines: 25..<30, gutterBar: .blue, tag: 8),
        CodeLineDecoration(lines: 3..<4, gutterMarker: CodeGutterMarker("!", color: .red), tag: 11),
    ], asOf: buffer.version)
    let window = try harnessWindow(size: sz(400, 600)) {
        var view = CodeView(buffer: buffer, decorations: decorations).font(size: 12).codeCaretBlink(.off).gutterMarkerLane(true)
        if viewHelp { view = view.help { p in log.viewHelp.append(p); return "view" } }
        if gutterHelp {
            view = view.gutterHelp { hit in
                log.hits.append(hit)
                return hit.source == .gutterMarker ? "marker \(hit.tag ?? 0)" : "bar \(hit.tag ?? 0)"
            }
        }
        return view
    }
    try await window.runUntilIdle()
    let bars = gutterBars(window)
    try #require(bars.count == 2)
    let pitch = (bars[1].y - bars[0].y) / 12.5, top = bars[0].y - 15 * pitch
    return Fx(window: window, log: log, barA: pt(bars[0].x, bars[0].y), barB: pt(bars[1].x, bars[1].y),
              marker: pt(3, top + 3.5 * pitch), text: pt(300, bars[0].y))
}

@MainActor private func shown(_ w: TestWindow) -> String? { w.window.visibleTooltip?.text }

/// **1** A bar and a marker answer their hit; the text area falls back to the view's own `.help`. **Mutation:** the
/// provider never asking `gutterHit` (the bar reads "view"); the fallback dropped (the text area reads nil).
@Test @MainActor func gutterHelpAnswersPerHitAndFallsBackToViewHelp() async throws {
    let fx = try await fixture()
    defer { withExtendedLifetime(fx.window) {} }
    let w = fx.window
    w.hover(at: fx.barA); w.advance(by: 1.1)
    #expect(shown(w) == "bar 7", "\(shown(w) as Any)")
    #expect(fx.log.hits.last?.tag == 7 && fx.log.hits.last?.source == .lineDecoration)
    w.hover(at: fx.marker); w.advance(by: 1.1)
    #expect(shown(w) == "marker 11", "\(shown(w) as Any)")
    w.hover(at: fx.text); w.advance(by: 1.1)
    #expect(shown(w) == "view", "\(shown(w) as Any)")
    #expect(!fx.log.viewHelp.isEmpty)
}

/// **2** Without a view `.help` the text area has no tooltip. **Mutation:** the fallback answering a constant.
@Test @MainActor func withoutAViewHelpTheTextAreaHasNoTooltip() async throws {
    let fx = try await fixture(viewHelp: false)
    defer { withExtendedLifetime(fx.window) {} }
    let w = fx.window
    w.hover(at: fx.text); w.advance(by: 2)
    #expect(shown(w) == nil)
    w.hover(at: fx.barA); w.advance(by: 1.1)
    #expect(shown(w) == "bar 7")
}

/// **3** The tooltip appears after the delay, and moving from one bar to another hides it and restarts the delay for
/// the new text; moving within a bar keeps it. **Mutation:** the provider answering one text for every bar.
@Test @MainActor func theTooltipFollowsTheBarUnderThePointer() async throws {
    let fx = try await fixture()
    defer { withExtendedLifetime(fx.window) {} }
    let w = fx.window
    w.hover(at: fx.barA); w.advance(by: 0.5)
    #expect(shown(w) == nil, "before the delay")
    w.advance(by: 0.6)
    #expect(shown(w) == "bar 7")
    w.hover(at: pt(fx.barA.x.value, fx.barA.y.value + 5))
    #expect(shown(w) == "bar 7", "within the bar")
    w.hover(at: fx.barB)
    #expect(shown(w) == nil, "hidden at once")
    w.advance(by: 1.1)
    #expect(shown(w) == "bar 8")
}

/// **4** The provider runs in input only: steady frames never call it. **Mutation:** calling it from the build.
@Test @MainActor func gutterHelpRunsInInputOnly() async throws {
    let fx = try await fixture()
    defer { withExtendedLifetime(fx.window) {} }
    let w = fx.window
    #expect(fx.log.hits.isEmpty, "not asked at build")
    for _ in 0..<3 { w.window.setNeedsRedraw(); try await w.runUntilIdle() }
    #expect(fx.log.hits.isEmpty, "not asked on steady frames")
    w.hover(at: fx.barA)
    let asked = fx.log.hits.count
    #expect(asked > 0)
    for _ in 0..<3 { w.window.setNeedsRedraw(); try await w.runUntilIdle() }
    #expect(fx.log.hits.count == asked, "not asked on frames after the move")
}

// Cost: steady and keystroke frames with and without `gutterHelp`.
private struct Cost: Equatable, CustomStringConvertible {
    var requests = 0, hits = 0, misses = 0, ineligible = 0, frames = 0
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
    let help: Bool
    var content: some ElementGroup {
        if help {
            CodeView(buffer: buffer, decorations: decorations).font(size: 12).showsLineNumbers(false).codeCaretBlink(.off)
                .gutterHelp { _ in "x" }
        } else {
            CodeView(buffer: buffer, decorations: decorations).font(size: 12).showsLineNumbers(false).codeCaretBlink(.off)
        }
    }
    static func == (l: Card, r: Card) -> Bool { l.buffer === r.buffer && l.decorations === r.decorations && l.help == r.help }
}

@MainActor private func measure(help: Bool, typing: Bool) async throws -> Cost {
    let buffer = CodeBuffer(codeText(lines: 60))
    let decorations = CodeDecorations(buffer: buffer)
    let w = try harnessWindow(size: sz(400, 200)) {
        Card(buffer: buffer, decorations: decorations, help: help).equatable().frame(width: Pixels(180), height: Pixels(150))
    }
    defer { withExtendedLifetime(w) {} }
    w.click(at: pt(60, 6))
    for _ in 0..<4 { w.window.setNeedsRedraw(); try await w.runUntilIdle() }
    w.resetFrameWork()
    if typing { w.typeText("a") } else { w.window.setNeedsRedraw() }
    try await w.runUntilIdle()
    return Cost(totalWork(w), frames: w.frameWork.count)
}

/// **5** A view with `gutterHelp` costs what one without costs, on a steady and a keystroke frame. **Mutation:** the
/// modifier wrapping the view in an element or reading the plan per frame.
@Test @MainActor func gutterHelpCostsNothingOnSteadyAndKeystrokeFrames() async throws {
    let steadyOff = try await measure(help: false, typing: false), steadyOn = try await measure(help: true, typing: false)
    let keyOff = try await measure(help: false, typing: true), keyOn = try await measure(help: true, typing: true)
    #if canImport(Darwin)
    #expect(steadyOn == steadyOff, "steady: \(steadyOn) vs \(steadyOff)")
    #expect(keyOn == keyOff, "keystroke: \(keyOn) vs \(keyOff)")
    #else
    #expect(steadyOn.perFrameEquals(steadyOff), "steady: \(steadyOn) vs \(steadyOff)")
    #expect(keyOn.perFrameEquals(keyOff), "keystroke: \(keyOn) vs \(keyOff)")
    #endif
    print("CVBT-COST steady \(steadyOff) keystroke \(keyOff)")
}
