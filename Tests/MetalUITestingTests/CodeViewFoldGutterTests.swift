import Testing
import Foundation
import MetalUI
import MetalUIScene
import MetalUITesting

// The fold chevron lane of `CodeView` (`CV-BN`, record 358): `foldGutter(showsOnHover:onToggle:)` and
// `CodeViewGeometry.foldChevronRect(line:)`. PLAIN imports; the harness text system; counters, never a clock. No line
// numbers, so the only glyphs left of the text are the chevrons. Lines are `line0`, `line1`, ...

@MainActor private struct Fx {
    let window: TestWindow
    let buffer: CodeBuffer
    let fold: CodeFoldState
    let geometry: CodeViewGeometry
    let clicks: Cell<[CodeGutterHit]>
    let toggles: Cell<[Int]>

    func redraw() { window.window.setNeedsRedraw(); window.tick() }
    func at(_ row: Int, _ column: Int) -> Int { buffer.snapshot().offset(of: CodePoint(row: row, column: column)) }

    /// The glyphs drawn inside the chevron cell of `line`.
    func chevronGlyphs(_ line: Int) -> Int {
        guard let r = geometry.foldChevronRect(line: line) else { return 0 }
        return window.scene.glyphs.filter { g in
            let cx = g.bounds.origin.x + g.bounds.size.width / 2, cy = g.bounds.origin.y + g.bounds.size.height / 2
            return cx >= r.origin.x.value && cx < r.origin.x.value + r.size.width.value
                && cy >= r.origin.y.value && cy < r.origin.y.value + r.size.height.value
        }.count
    }
    /// The glyphs drawn left of the text.
    var gutterGlyphs: Int {
        guard let r = geometry.foldChevronRect(line: 2) ?? geometry.foldChevronRect(line: 0) else { return 0 }
        let edge = r.origin.x.value + r.size.width.value
        return window.scene.glyphs.filter { $0.bounds.origin.x + $0.bounds.size.width / 2 < edge }.count
    }
}

@MainActor private func foldText(_ lines: Int) -> String { (0..<lines).map { "line\($0)" }.joined(separator: "\n") }

@MainActor private func fixture(lines: Int = 40, foldable: [Range<Int>] = [2..<8, 9..<12], gutter: Bool = true, attach: Bool = true,
                                showsOnHover: Bool = true, accessibility: Bool = true, bars: Bool = true) throws -> Fx {
    let buffer = CodeBuffer(foldText(lines))
    let decorations = CodeDecorations(buffer: buffer)
    if bars {
        decorations.setLineDecorations([CodeLineDecoration(lines: 0..<lines, gutterBar: Color(hue: 0.3, saturation: 1, brightness: 1))], asOf: buffer.version)
    }
    let fold = CodeFoldState(selectionState: buffer.selectionState)
    fold.foldableRanges = foldable
    let geometry = CodeViewGeometry()
    let clicks = Cell<[CodeGutterHit]>([])
    let toggles = Cell<[Int]>([])
    let window = try harnessWindow(size: sz(400, 200), options: .init(accessibilityClientActive: accessibility)) {
        let base = CodeView(buffer: buffer, decorations: decorations).font(size: 12).codeCaretBlink(.off).showsLineNumbers(false)
            .geometry(geometry).onGutterBarClick { clicks.value.append($0) }
        let withState = attach ? base.foldState(fold) : base
        return gutter ? withState.foldGutter(showsOnHover: showsOnHover) { toggles.value.append($0) } : withState
    }
    window.click(at: pt(200, 3))   // focus, in the text
    window.window.setNeedsRedraw(); window.tick()
    clicks.value = []
    return Fx(window: window, buffer: buffer, fold: fold, geometry: geometry, clicks: clicks, toggles: toggles)
}

private func center(_ r: Bounds<Pixels>) -> Point<Pixels> {
    pt(r.origin.x.value + r.size.width.value / 2, r.origin.y.value + r.size.height.value / 2)
}

// MARK: Press

/// **1** A press on a chevron folds its range, a second opens it, and `onToggle` hears the line each time. The press is
/// consumed: the gutter bar under it (the lane overlaps the bar's reach) hears nothing and the caret stays. **Mutation:**
/// the press falling through to `onGutterBarClick` (a click is recorded); `onToggle` not called; the toggle dropped.
@Test @MainActor func aPressOnAChevronTogglesItsRangeAndCallsOnToggle() throws {
    let fx = try fixture()
    defer { withExtendedLifetime(fx.window) {} }
    let caret = fx.buffer.primarySelection
    let rect = try #require(fx.geometry.foldChevronRect(line: 2))
    fx.window.click(at: center(rect))
    #expect(fx.fold.folded == [2..<8], "\(fx.fold.folded)")
    #expect(fx.geometry.foldPlaceholderRect(line: 2) != nil)
    #expect(fx.toggles.value == [2])
    let again = try #require(fx.geometry.foldChevronRect(line: 2))
    fx.window.click(at: center(again))
    #expect(fx.fold.folded.isEmpty && fx.toggles.value == [2, 2], "\(fx.fold.folded) \(fx.toggles.value)")
    #expect(fx.clicks.value.isEmpty, "consumed, never the bar's: \(fx.clicks.value)")
    #expect(fx.buffer.primarySelection == caret, "no caret move")
}

/// **2** Of nested ranges starting on one line the innermost is folded, and a second press opens it. **Mutation:** the
/// outermost chosen (`0..<10` folds); the first of the equal starts rather than the last.
@Test @MainActor func theInnermostRangeStartingOnTheLineIsToggled() throws {
    let fx = try fixture(foldable: [0..<10, 0..<5, 1..<4])
    defer { withExtendedLifetime(fx.window) {} }
    fx.window.click(at: center(try #require(fx.geometry.foldChevronRect(line: 0))))
    #expect(fx.fold.folded == [0..<5], "\(fx.fold.folded)")
    fx.window.click(at: center(try #require(fx.geometry.foldChevronRect(line: 0))))
    #expect(fx.fold.folded.isEmpty, "\(fx.fold.folded)")
    #expect(fx.toggles.value == [0, 0])
}

/// **3** A press in the lane on a line that starts no foldable range is the gutter's own: it selects the line, folds
/// nothing and calls no `onToggle`. **Mutation:** the lane consuming every press.
@Test @MainActor func aPressOnALineWithoutAChevronIsTheGuttersOwn() throws {
    let fx = try fixture()
    defer { withExtendedLifetime(fx.window) {} }
    let lane = try #require(fx.geometry.foldChevronRect(line: 2))
    let pitch = lane.size.height.value
    fx.window.click(at: pt(lane.origin.x.value + lane.size.width.value / 2, lane.origin.y.value - pitch / 2))   // line 1
    #expect(fx.fold.folded.isEmpty && fx.toggles.value.isEmpty)
    #expect(fx.buffer.primarySelection != CodeSelection(caret: 0) || !fx.clicks.value.isEmpty, "the gutter handled it")
}

// MARK: Follow edits

/// **4** The chevrons follow edits: a line typed above shifts them (the rect moves down a row and the old line has
/// none), and an edit that opens a range drops its chevron. **Mutation:** chevrons from a copy of the ranges taken
/// once (they stay on the old lines).
@Test @MainActor func chevronsFollowEdits() throws {
    let fx = try fixture()
    defer { withExtendedLifetime(fx.window) {} }
    let before = try #require(fx.geometry.foldChevronRect(line: 2))
    fx.buffer.replace(0..<0, with: "top\n")
    fx.redraw()
    let after = try #require(fx.geometry.foldChevronRect(line: 3))
    #expect(after.origin.y.value == before.origin.y.value + before.size.height.value, "moved down a row")
    #expect(fx.geometry.foldChevronRect(line: 2) == nil, "the old line starts nothing")
    #expect(fx.fold.foldableRanges == [3..<9, 10..<13], "\(fx.fold.foldableRanges)")
    fx.buffer.replace(fx.at(3, 5)..<fx.at(3, 5), with: "\n")   // a break in the header opens (drops) the range
    fx.redraw()
    #expect(fx.geometry.foldChevronRect(line: 3) == nil, "the dropped range has no chevron")
    #expect(fx.geometry.foldChevronRect(line: 11) != nil, "the other range moved down two lines")
}

// MARK: Hover

/// **5** An open chevron is drawn only while the pointer is over the gutter, a folded one always; the lane is empty
/// before. **Mutation:** open chevrons always drawn (glyphs before the hover); folded ones hover-gated (none when folded).
@Test @MainActor func openChevronsShowOnHoverAndFoldedOnesAlways() throws {
    let fx = try fixture()
    defer { withExtendedLifetime(fx.window) {} }
    #expect(fx.gutterGlyphs == 0, "nothing drawn left of the text: \(fx.gutterGlyphs)")
    let lane = try #require(fx.geometry.foldChevronRect(line: 2))
    fx.window.hover(at: center(lane))
    #expect(fx.chevronGlyphs(2) == 1 && fx.chevronGlyphs(9) == 1, "hovered: \(fx.chevronGlyphs(2)) \(fx.chevronGlyphs(9))")
    fx.window.hover(at: pt(200, 100))
    #expect(fx.gutterGlyphs == 0, "left the gutter: hidden again")
    fx.fold.fold(2..<8)
    fx.redraw()
    #expect(fx.chevronGlyphs(2) == 1 && fx.chevronGlyphs(9) == 0, "folded shows without a hover, open does not")
    fx.window.exitPointer()
}

/// **6** `showsOnHover: false` has no hover attachment: nothing writes the hover flag, open chevrons never show, and a
/// folded one does. **Mutation:** the attachment installed regardless (open chevrons show on hover).
@Test @MainActor func withoutShowsOnHoverOpenChevronsNeverShow() throws {
    let fx = try fixture(showsOnHover: false)
    defer { withExtendedLifetime(fx.window) {} }
    fx.window.hover(at: center(try #require(fx.geometry.foldChevronRect(line: 2))))
    #expect(fx.gutterGlyphs == 0)
    fx.fold.fold(2..<8)
    fx.redraw()
    #expect(fx.chevronGlyphs(2) == 1)
}

// MARK: Geometry and lane

/// **7** The chevron rect is the lane cell of the row, a row high, between the numbers and the text, two space advances
/// wide; `nil` for a line starting no range. **Mutation:** the lane at the left of the numbers; a width of one advance.
@Test @MainActor func theGeometryAnswersTheChevronCell() throws {
    let fx = try fixture()
    defer { withExtendedLifetime(fx.window) {} }
    let rect = try #require(fx.geometry.foldChevronRect(line: 2))
    let text = try #require(fx.geometry.rects(for: fx.at(2, 0)..<fx.at(2, 1)).first)
    #expect(rect.origin.y == text.origin.y && rect.size.height == text.size.height)
    #expect(rect.origin.x.value + rect.size.width.value <= text.origin.x.value, "left of the text")
    #expect(abs(rect.size.width.value - 2 * text.size.width.value) < 1.5, "two advances: \(rect.size.width.value) vs \(text.size.width.value)")
    #expect(fx.geometry.foldChevronRect(line: 1) == nil && fx.geometry.foldChevronRect(line: 30) == nil)
}

/// **8** Without a fold state the lane is not reserved and the call is a no-op: the text sits where it does without the
/// call, there is no rect and no chevron. **Mutation:** the lane reserved by `foldGutter` alone (the text moves).
@Test @MainActor func withoutAFoldStateTheLaneIsAbsent() throws {
    let plain = try fixture(gutter: false, attach: false)
    let bare = try fixture(gutter: true, attach: false)
    defer { withExtendedLifetime(plain.window) {}; withExtendedLifetime(bare.window) {} }
    let a = try #require(plain.geometry.rects(for: plain.at(2, 0)..<plain.at(2, 1)).first)
    let b = try #require(bare.geometry.rects(for: bare.at(2, 0)..<bare.at(2, 1)).first)
    #expect(a.origin.x == b.origin.x, "the text did not move: \(a.origin.x.value) vs \(b.origin.x.value)")
    #expect(bare.geometry.foldChevronRect(line: 2) == nil)
    let with = try fixture()
    defer { withExtendedLifetime(with.window) {} }
    let c = try #require(with.geometry.rects(for: with.at(2, 0)..<with.at(2, 1)).first)
    #expect(c.origin.x.value > a.origin.x.value, "the lane takes room with both set: \(c.origin.x.value) vs \(a.origin.x.value)")
}

// MARK: Accessibility

/// **9** `fold-chevron-<line>` is a `.button` over the chevron cell, valued `expanded` or `collapsed`, built only while a
/// client collects accessibility. **Mutation:** the nodes built unconditionally (the count rises with no client); a wrong
/// identifier or value.
@Test @MainActor func chevronsAreButtonNodesOnlyWhileAClientCollects() throws {
    let before = CodeViewStats.foldChevronNodes
    let quiet = try fixture(accessibility: false)
    quiet.redraw()
    #expect(CodeViewStats.foldChevronNodes == before, "no client, no node")
    withExtendedLifetime(quiet.window) {}
    let fx = try fixture()
    defer { withExtendedLifetime(fx.window) {} }
    fx.fold.fold(9..<12)
    fx.redraw()
    let buttons = try fx.window.elements(role: .button).filter { ($0.identifier ?? "").hasPrefix("fold-chevron-") }
    #expect(Set(buttons.compactMap(\.identifier)) == ["fold-chevron-2", "fold-chevron-9"], "\(buttons.compactMap(\.identifier))")
    let open = try #require(buttons.first { $0.identifier == "fold-chevron-2" })
    let closed = try #require(buttons.first { $0.identifier == "fold-chevron-9" })
    #expect(open.value == "expanded" && closed.value == "collapsed", "\(String(describing: open.value)) \(String(describing: closed.value))")
    #expect(open.frame == (try #require(fx.geometry.foldChevronRect(line: 2))))
    #expect(CodeViewStats.foldChevronNodes > before)
}

// MARK: Cost

private struct Cost: Equatable, CustomStringConvertible {
    var requests = 0, hits = 0, misses = 0, ineligible = 0, frames = 0
    init(requests: Int, hits: Int, misses: Int, ineligible: Int, frames: Int) {
        self.requests = requests; self.hits = hits; self.misses = misses; self.ineligible = ineligible; self.frames = frames
    }
    init(_ f: FrameWork, frames: Int) {
        requests = f.elementRequests; hits = f.retainedHits; misses = f.retainedMisses; ineligible = f.retainedIneligible
        self.frames = frames
    }
    /// The same work per frame (off Darwin a keystroke spans a varying number of frames, `CodeViewMultiCaretCostTests`).
    func perFrameEquals(_ o: Cost) -> Bool {
        frames > 0 && o.frames > 0
            && requests * o.frames == o.requests * frames && hits * o.frames == o.hits * frames
            && misses * o.frames == o.misses * frames && ineligible * o.frames == o.ineligible * frames
    }
    var description: String { "requests \(requests) hits \(hits) misses \(misses) ineligible \(ineligible) frames \(frames)" }
}

private struct GutterCard: Component, @MainActor Equatable {
    let buffer: CodeBuffer
    let decorations: CodeDecorations
    let fold: CodeFoldState
    let gutter: Bool
    var content: some ElementGroup {
        if gutter {
            CodeView(buffer: buffer, decorations: decorations).font(size: 12).showsLineNumbers(false).codeCaretBlink(.off)
                .foldState(fold).foldGutter()
        } else {
            CodeView(buffer: buffer, decorations: decorations).font(size: 12).showsLineNumbers(false).codeCaretBlink(.off)
                .foldState(fold)
        }
    }
    static func == (l: GutterCard, r: GutterCard) -> Bool {
        l.buffer === r.buffer && l.decorations === r.decorations && l.fold === r.fold && l.gutter == r.gutter
    }
}

/// A window of 80 lines with a fold state holding foldable ranges, with or without the fold gutter.
@MainActor private func openCard(gutter: Bool) async throws -> (TestWindow, CodeBuffer) {
    let buffer = CodeBuffer(foldText(80))
    let decorations = CodeDecorations(buffer: buffer)
    let fold = CodeFoldState(selectionState: buffer.selectionState)
    fold.foldableRanges = [2..<5, 8..<11, 12..<20, 22..<25, 27..<30]
    let w = try harnessWindow(size: sz(400, 200)) {
        HStack(spacing: 0) {   // the structure of `CodeViewMultiCaretCostTests`, whose literals are master's
            ForEach(0..<1, id: \.self) { _ in
                GutterCard(buffer: buffer, decorations: decorations, fold: fold, gutter: gutter).equatable()
                    .frame(width: Pixels(180), height: Pixels(150))
            }
        }
    }
    w.click(at: pt(210, 31))   // focus, in the text (the card is centred in the window: its origin is (110, 25))
    for _ in 0..<4 { w.window.setNeedsRedraw(); try await w.runUntilIdle() }
    return (w, buffer)
}

@MainActor private func steadyCost(gutter: Bool) async throws -> Cost {
    let (w, _) = try await openCard(gutter: gutter)
    defer { withExtendedLifetime(w) {} }
    w.resetFrameWork()
    w.window.setNeedsRedraw(); try await w.runUntilIdle()
    return Cost(totalWork(w), frames: w.frameWork.count)
}

@MainActor private func keystrokeCost(gutter: Bool) async throws -> Cost {
    let (w, buffer) = try await openCard(gutter: gutter)
    defer { withExtendedLifetime(w) {} }
    let before = buffer.snapshot().utf8Count
    w.resetFrameWork()
    w.typeText("a")
    try await w.runUntilIdle()
    #expect(buffer.snapshot().utf8Count == before + 1)
    return Cost(totalWork(w), frames: w.frameWork.count)
}

/// **10** A view with a fold gutter costs what the same view without one costs: steady (the literal master's: 2 requests,
/// 0/1/0 retention) and keystroke, with a fold state attached and foldable ranges set. **Mutation:** an element or a
/// retention taint added for the lane (requests or misses move); the chevron glyphs shaped per row (checked in 11).
@Test @MainActor func aFoldGutterCostsWhatNoFoldGutterCosts() async throws {
    let none = try await steadyCost(gutter: false), with = try await steadyCost(gutter: true)
    #expect(none == Cost(requests: 2, hits: 0, misses: 1, ineligible: 0, frames: 1), "steady, no gutter: \(none)")
    #expect(with == none, "steady: \(with) vs \(none)")
    let keyNone = try await keystrokeCost(gutter: false), keyWith = try await keystrokeCost(gutter: true)
    #if canImport(Darwin)
    #expect(keyNone == Cost(requests: 2, hits: 0, misses: 1, ineligible: 0, frames: 1), "keystroke, no gutter: \(keyNone)")
    #expect(keyWith == keyNone, "keystroke: \(keyWith) vs \(keyNone)")
    #else
    #expect(keyWith.perFrameEquals(keyNone), "keystroke: \(keyWith) vs \(keyNone)")
    #endif
}

/// **11** A hover enter and a hover leave are one frame each, at the steady keystroke's request count and retention (the
/// state write taints the replay, as a keystroke does); a move within the gutter is no frame. **Mutation:** the hover
/// flag written on every move (frames on the moves within the gutter); the write not compared (the same).
@Test @MainActor func aHoverEnterAndLeaveCostOneFrameAndAMoveWithinTheGutterNone() async throws {
    let (w, _) = try await openCard(gutter: true)
    defer { withExtendedLifetime(w) {} }
    let keystroke = try await keystrokeCost(gutter: true)
        let inside = [pt(113, 45), pt(115, 65), pt(112, 58), pt(111, 85)]   // the lane is 7 points wide at the card's left
    let outside = pt(260, 45)
    w.hover(at: outside)
    try await w.runUntilIdle()
    w.resetFrameWork()
    w.hover(at: inside[0])
    try await w.runUntilIdle()
    let enter = Cost(totalWork(w), frames: w.frameWork.count)
    #if canImport(Darwin)
    #expect(enter == keystroke, "enter: \(enter) vs keystroke \(keystroke)")
    #else
    #expect(enter.perFrameEquals(keystroke), "enter: \(enter) vs keystroke \(keystroke)")
    #endif
    #expect(enter.frames >= 1)
    w.resetFrameWork()
    let writesBefore = w.window.testingStatePlainWriteCount
    for p in inside.dropFirst() { w.hover(at: p); try await w.runUntilIdle() }
    // A pointer move over the view costs what the view's scroll chrome costs with or without a gutter (a frame and two plain
    // writes each, `CodeViewTextHoverTests` 4): within the gutter the fold gutter adds none to it.
    let moved = (frames: w.frameWork.count, writes: w.window.testingStatePlainWriteCount - writesBefore)
    let (base, _) = try await openCard(gutter: false)
    defer { withExtendedLifetime(base) {} }
    base.hover(at: outside)
    try await base.runUntilIdle()
    base.resetFrameWork()
    let baseBefore = base.window.testingStatePlainWriteCount
    for p in inside.dropFirst() { base.hover(at: p); try await base.runUntilIdle() }
    let baseline = (frames: base.frameWork.count, writes: base.window.testingStatePlainWriteCount - baseBefore)
    #expect(moved == baseline, "moves within the gutter: \(moved) vs the same moves with no fold gutter \(baseline)")
    w.resetFrameWork()
    w.hover(at: outside)
    try await w.runUntilIdle()
    let leave = Cost(totalWork(w), frames: w.frameWork.count)
    #if canImport(Darwin)
    #expect(leave == keystroke, "leave: \(leave) vs keystroke \(keystroke)")
    #else
    #expect(leave.perFrameEquals(keystroke), "leave: \(leave) vs keystroke \(keystroke)")
    #endif
}
