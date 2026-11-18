import Testing
import Foundation
import MetalUI
import MetalUIScene
import MetalUITesting

// The change lane of `CodeView` (`CV-BS`, record 375): a version-control mark in a lane between the numbers and the fold
// chevrons, beside the gutter bar. PLAIN imports; the harness text system; counters, never a clock.

private let addedHue = Color(hue: 0.321, saturation: 1, brightness: 1)
private let modifiedHue = Color(hue: 0.6, saturation: 1, brightness: 1)
private let deletedHue = Color(hue: 0.9, saturation: 1, brightness: 1)
private let authorHue = Color(hue: 0.1, saturation: 1, brightness: 1)
private let git = CodeDecorationOwner("git", priority: 2)
private let author = CodeDecorationOwner("author", priority: 1)

private func text(_ lines: Int) -> String { (0..<lines).map { "line\($0)" }.joined(separator: "\n") }

@MainActor private struct Fx {
    let window: TestWindow
    let buffer: CodeBuffer
    let decorations: CodeDecorations
    let clicks: Cell<[CodeGutterHit]>
    let fold: CodeFoldState
    func redraw() { window.window.setNeedsRedraw(); window.tick() }
    /// The x of the left of the first text glyph on row `row`, in points.
    @MainActor func textX(row: Int) -> Float? {
        let pitch = codePitch(scale: 1)
        return window.scene.glyphs.filter { $0.bounds.origin.y >= Float(row) * pitch - 1 && $0.bounds.origin.y < Float(row + 1) * pitch }
            .map { $0.bounds.origin.x }.max()
    }
    /// The rects of `hue`, top to bottom.
    @MainActor func rects(_ hue: Double) -> [MUIBounds] {
        window.scene.rects.filter { abs(Double($0.background.h) - hue) < 0.002 }.map(\.bounds).sorted { $0.origin.y < $1.origin.y }
    }
}

@MainActor private func fixture(lane: Bool? = nil, lines: Int = 30, folds: [Range<Int>] = [],
                                setup: (CodeDecorations) -> Void = { _ in }) throws -> Fx {
    let buffer = CodeBuffer(text(lines))
    let decorations = CodeDecorations(buffer: buffer)
    setup(decorations)
    let clicks = Cell<[CodeGutterHit]>([])
    let fold = CodeFoldState(selectionState: buffer.selectionState, folded: folds)
    let base = CodeView(buffer: buffer, decorations: decorations).font(size: 12).codeCaretBlink(.off).foldState(fold)
        .onGutterBarClick { clicks.value.append($0) }
    let view = lane.map { base.changeLane($0) } ?? base
    let window = try harnessWindow(size: sz(400, 600)) { view }
    return Fx(window: window, buffer: buffer, decorations: decorations, clicks: clicks, fold: fold)
}

@MainActor private func setChanges(_ d: CodeDecorations, _ decorations: [CodeLineDecoration] = [
    CodeLineDecoration(lines: 3..<7, tag: 7, changeBar: .added(addedHue)),
    CodeLineDecoration(lines: 10..<12, tag: 8, changeBar: .modified(modifiedHue))]) {
    d.setLineDecorations(decorations, asOf: d.buffer.version, owner: git)
}

/// **1** With no change bar given, the gutter has no lane and draws exactly what it does with the lane off: the same
/// glyphs and rects whether or not the view's decorations carry other marks (a gutter bar), and the same as a view that
/// has change bars but `.changeLane(false)`. **Mutation:** the lane reserved always (the text moves 4 points).
@Test @MainActor func noChangeBarsNoLaneNoCost() throws {
    func snapshot(_ fx: Fx) -> [String] {
        fx.window.scene.glyphs.map { "\($0.bounds)" } + fx.window.scene.rects.map { "\($0.bounds) \($0.background)" }
    }
    let plain = try fixture { $0.setLineDecorations([CodeLineDecoration(lines: 3..<7, gutterBar: authorHue)], asOf: $0.buffer.version, owner: author) }
    defer { withExtendedLifetime(plain.window) {} }
    let off = try fixture(lane: false) {
        $0.setLineDecorations([CodeLineDecoration(lines: 3..<7, gutterBar: authorHue)], asOf: $0.buffer.version, owner: author)
        setChanges($0)
    }
    defer { withExtendedLifetime(off.window) {} }
    #expect(snapshot(plain) == snapshot(off), "no change bars and a lane switched off draw the same")
    let bare = try fixture()
    defer { withExtendedLifetime(bare.window) {} }
    let reserved = try fixture(lane: true)
    defer { withExtendedLifetime(reserved.window) {} }
    let x = try #require(bare.textX(row: 3))
    #expect(x == 52, "the text origin of a 30-line file without a lane: \(x)")
    #expect(try #require(reserved.textX(row: 3)) == x + 4, "a reserved lane is 4 points")
}

/// **2** By default the lane appears when the first change bar is given and then stays, the text moving once, by the
/// width of a reserved lane; `true` reserves it from the first frame so nothing moves. **Mutation:** a lane
/// whose width depends on the marks present (the text moves back when they go).
@Test @MainActor func changeLaneAppearsOnceAndStays() throws {
    let auto = try fixture()
    defer { withExtendedLifetime(auto.window) {} }
    let before = try #require(auto.textX(row: 3))
    setChanges(auto.decorations); auto.redraw()
    let after = try #require(auto.textX(row: 3))
    #expect(after == before + 4, "\(before) -> \(after)")
    setChanges(auto.decorations, []); auto.redraw()
    #expect(auto.textX(row: 3) == after, "the text does not move back when the marks go")
    #expect(auto.rects(0.321).isEmpty)
    let reserved = try fixture(lane: true)
    defer { withExtendedLifetime(reserved.window) {} }
    let first = try #require(reserved.textX(row: 3))
    setChanges(reserved.decorations); reserved.redraw()
    #expect(reserved.textX(row: 3) == first && first == after, "reserved: nothing moves")
}

/// **3** A change bar and a gutter bar of two owners show on one row side by side: both rects over rows 3..<7, the change
/// bar left of the gutter bar, not overlapping, each 3 points wide, with the lane left of the text and right of the numbers.
/// **Mutation:** the change bar drawn at the gutter bar's x (they overlap).
@Test @MainActor func gitAndAuthorBarsShowOnOneRow() throws {
    let fx = try fixture {
        setChanges($0)
        $0.setLineDecorations([CodeLineDecoration(lines: 3..<7, gutterBar: authorHue)], asOf: $0.buffer.version, owner: author)
    }
    defer { withExtendedLifetime(fx.window) {} }
    let pitch = codePitch(scale: 1)
    let change = try #require(fx.rects(0.321).first), bar = try #require(fx.rects(0.1).first)
    #expect(change.size.width == 3 && bar.size.width == 3)
    #expect(change.origin.y == bar.origin.y && change.size.height == bar.size.height && change.origin.y == 3 * pitch)
    #expect(change.origin.x + 3 <= bar.origin.x, "side by side: \(change) \(bar)")
    let textX = try #require(fx.textX(row: 3))
    #expect(bar.origin.x + 3 <= textX)
    let number = fx.window.scene.glyphs.filter { $0.bounds.origin.y >= 3 * pitch - 1 && $0.bounds.origin.y < 4 * pitch && $0.bounds.origin.x < change.origin.x }
    #expect(!number.isEmpty && number.allSatisfy { $0.bounds.origin.x + $0.bounds.size.width <= change.origin.x }, "numbers, then the lane")
}

/// **4** A press on a change bar reports the run with the same mark and tag, the tag, `.changeBar` and the owner, and a
/// press 2 points outside the lane still hits; the gutter bar beside it still reports its own hit.
/// **Mutation:** the hit built with the row alone as `lines`, or without `ownerOf`.
@Test @MainActor func changeBarHitReportsSourceTagOwner() throws {
    let fx = try fixture {
        setChanges($0)
        $0.setLineDecorations([CodeLineDecoration(lines: 3..<7, gutterBar: authorHue, tag: 5)], asOf: $0.buffer.version, owner: author)
    }
    defer { withExtendedLifetime(fx.window) {} }
    let pitch = codePitch(scale: 1)
    let change = try #require(fx.rects(0.321).first), bar = try #require(fx.rects(0.1).first)
    fx.window.click(at: pt(change.origin.x + 1, 4.5 * pitch))
    #expect(fx.clicks.value == [CodeGutterHit(lines: 3..<7, tag: 7, source: .changeBar, displayRow: 4, owner: git)], "\(fx.clicks.value)")
    fx.window.click(at: pt(change.origin.x - 1.5, 5.5 * pitch))
    #expect(fx.clicks.value.last == CodeGutterHit(lines: 3..<7, tag: 7, source: .changeBar, displayRow: 5, owner: git), "2 pt slop")
    fx.window.click(at: pt(bar.origin.x + 1, 4.5 * pitch))
    #expect(fx.clicks.value.last == CodeGutterHit(lines: 3..<7, tag: 5, source: .lineDecoration, displayRow: 4, owner: author), "the gutter bar")
    let modified = try #require(fx.rects(0.6).first)
    fx.window.click(at: pt(modified.origin.x + 1, 11.5 * pitch))
    #expect(fx.clicks.value.last == CodeGutterHit(lines: 10..<12, tag: 8, source: .changeBar, displayRow: 11, owner: git))
}

/// **5** `.deletedAbove` draws VS Code's triangle on the row's top edge: one-pixel strips (plain rect fills) whose widths
/// fall from the widest at the row's top edge to one pixel at each end, centred on the edge, tip pointing into the text.
/// **Mutation:** a plain 3 x 2 tick (all strips the same width).
@Test @MainActor func deletedAboveDrawsATriangleAtTheRowTop() throws {
    let fx = try fixture { setChanges($0, [CodeLineDecoration(lines: 5..<6, changeBar: .deletedAbove(deletedHue))]) }
    defer { withExtendedLifetime(fx.window) {} }
    let pitch = codePitch(scale: 1)
    let strips = fx.rects(0.9)
    #expect(strips.count == 5, "\(strips.count)")
    let top = 5 * pitch
    #expect(strips.map { $0.size.height } == Array(repeating: 1, count: strips.count))
    #expect(strips.map { $0.origin.y } == (-2...2).map { top + Float($0) }, "centred on the row's top edge")
    let widths = strips.map { $0.size.width }
    #expect(widths == [1, 1, 3, 1, 1] || (widths[2] == widths.max() && widths[0] < widths[2] && widths[4] < widths[2] && widths[0] == widths[4]), "\(widths)")
    #expect(Set(strips.map { $0.origin.x }).count == 1, "the base is one vertical line, the tip points right")
    #expect(fx.rects(0.321).isEmpty)
}

/// **6** `.changeLane(false)` has no lane and draws no change bars. **Mutation:** bars drawn into the gutter anyway.
@Test @MainActor func changeLaneFalseHidesBars() throws {
    let fx = try fixture(lane: false) { setChanges($0) }
    defer { withExtendedLifetime(fx.window) {} }
    #expect(fx.rects(0.321).isEmpty && fx.rects(0.6).isEmpty)
    let bare = try fixture(lane: false)
    defer { withExtendedLifetime(bare.window) {} }
    #expect(fx.textX(row: 3) == bare.textX(row: 3))
    let pitch = codePitch(scale: 1)
    fx.window.click(at: pt(36, 4.5 * pitch))
    #expect(fx.clicks.value.isEmpty, "no hit")
}

/// **7** A folded header shows the first hidden change as `.modified` (whatever it is), and a press on it reports the
/// folded rows. **Mutation:** no folded-header rule (no bar on the header).
@Test @MainActor func aFoldedHeaderShowsTheFirstHiddenChangeAsModified() throws {
    let fx = try fixture(folds: [2..<8]) { setChanges($0, [CodeLineDecoration(lines: 5..<7, tag: 3, changeBar: .added(addedHue))]) }
    defer { withExtendedLifetime(fx.window) {} }
    let pitch = codePitch(scale: 1)
    let marks = fx.rects(0.321)
    #expect(marks.count == 1 && marks[0].origin.y == 2 * pitch && marks[0].size.height == pitch, "\(marks)")
    fx.window.click(at: pt(marks[0].origin.x + 1, 2.5 * pitch))
    #expect(fx.clicks.value == [CodeGutterHit(lines: 2..<8, tag: 3, source: .changeBar, displayRow: 2, owner: git)], "\(fx.clicks.value)")
}

// MARK: Cost

private struct Cost: Equatable, CustomStringConvertible {
    var requests = 0, hits = 0, misses = 0, ineligible = 0, frames = 0
    func perFrameEquals(_ o: Cost) -> Bool {
        frames > 0 && o.frames > 0
            && requests * o.frames == o.requests * frames && hits * o.frames == o.hits * frames
            && misses * o.frames == o.misses * frames && ineligible * o.frames == o.ineligible * frames
    }
    var description: String { "requests \(requests) hits \(hits) misses \(misses) ineligible \(ineligible) frames \(frames)" }
}

private struct Card: Component, @MainActor Equatable {
    let buffer: CodeBuffer
    let decorations: CodeDecorations
    var content: some ElementGroup {
        CodeView(buffer: buffer, decorations: decorations).font(size: 12).showsLineNumbers(false).codeCaretBlink(.off)
    }
    static func == (l: Card, r: Card) -> Bool { l.buffer === r.buffer && l.decorations === r.decorations }
}

@MainActor private func cost(changeBars: Bool, keystroke: Bool) async throws -> Cost {
    let buffer = CodeBuffer(codeText(lines: 60))
    let decorations = CodeDecorations(buffer: buffer)
    if changeBars { setChanges(decorations) }
    let w = try harnessWindow(size: sz(400, 200)) {
        HStack(spacing: 0) {   // the view of `CodeViewMultiCaretCostTests`, whose literals are master's
            ForEach(0..<1, id: \.self) { _ in
                Card(buffer: buffer, decorations: decorations).equatable().frame(width: Pixels(180), height: Pixels(150))
            }
        }
    }
    defer { withExtendedLifetime(w) {} }
    w.click(at: pt(60, 6))
    for _ in 0..<4 { w.window.setNeedsRedraw(); try await w.runUntilIdle() }
    w.resetFrameWork()
    if keystroke { w.typeText("a") } else { w.window.setNeedsRedraw() }
    try await w.runUntilIdle()
    let f = totalWork(w)
    return Cost(requests: f.elementRequests, hits: f.retainedHits, misses: f.retainedMisses, ineligible: f.retainedIneligible, frames: w.frameWork.count)
}

/// **8** The frame costs are those of master (steady 2 requests, 0/1/0 retention; a keystroke the same) with and without
/// change bars: the lane adds no element, no request and no retention change. **Mutation:** a wrapper element for the lane.
@Test @MainActor func changeBarsCostWhatNoneCost() async throws {
    let steadyNone = try await cost(changeBars: false, keystroke: false), steadyBars = try await cost(changeBars: true, keystroke: false)
    #expect(steadyNone == Cost(requests: 2, hits: 0, misses: 1, ineligible: 0, frames: 1), "\(steadyNone)")
    #expect(steadyBars == steadyNone, "\(steadyBars)")
    let keyNone = try await cost(changeBars: false, keystroke: true), keyBars = try await cost(changeBars: true, keystroke: true)
    #if canImport(Darwin)
    #expect(keyNone == Cost(requests: 2, hits: 0, misses: 1, ineligible: 0, frames: 1), "\(keyNone)")
    #expect(keyBars == keyNone, "\(keyBars)")
    #else
    #expect(keyBars.perFrameEquals(keyNone), "\(keyBars) vs \(keyNone)")
    #endif
}
