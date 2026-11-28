import Testing
import Foundation
import MetalUI
import MetalUIScene
import MetalUITesting

// Hidden rows in `CodeView` (`CV-BM`, record 354): the layout of a `CodeFoldState`'s folds. PLAIN imports; the harness
// text system; counters, never a clock. Lines are `line0`, `line1`, ... so every row's place is the pitch times its
// shown index.

@MainActor private struct Fx {
    let window: TestWindow
    let buffer: CodeBuffer
    let decorations: CodeDecorations
    let fold: CodeFoldState
    let geometry: CodeViewGeometry
    let scroll: CodeScrollState
    let clicks: Cell<[CodeGutterHit]>
    let pitch: Float

    /// The top of buffer row `row` (view-local), `nil` when it is not shown.
    func y(_ row: Int) -> Float? {
        let snap = buffer.snapshot()
        return geometry.rects(for: snap.lineRange(row)).first?.origin.y.value
    }

    func redraw() { window.window.setNeedsRedraw(); window.tick() }
    func at(_ row: Int, _ column: Int) -> Int { buffer.snapshot().offset(of: CodePoint(row: row, column: column)) }
    func caret(_ row: Int, _ column: Int) { buffer.selections = [CodeSelection(caret: at(row, column))]; redraw() }
    func heads() -> [[Int]] {
        let snap = buffer.snapshot()
        return buffer.selections.map { let p = snap.point(at: $0.head); return [p.row, p.column] }
    }
}

@MainActor private func foldText(_ lines: Int) -> String { (0..<lines).map { "line\($0)" }.joined(separator: "\n") }

@MainActor private func fixture(lines: Int = 40, folds: [Range<Int>] = [], height: Float = 200, accessibility: Bool = true,
                                setup: (CodeBuffer, CodeDecorations) -> Void = { _, _ in }) throws -> Fx {
    let buffer = CodeBuffer(foldText(lines))
    let decorations = CodeDecorations(buffer: buffer)
    setup(buffer, decorations)
    let fold = CodeFoldState(selectionState: buffer.selectionState, folded: folds)
    let geometry = CodeViewGeometry()
    let scroll = CodeScrollState()
    let clicks = Cell<[CodeGutterHit]>([])
    let window = try harnessWindow(size: sz(400, height), options: .init(accessibilityClientActive: accessibility)) {
        CodeView(buffer: buffer, decorations: decorations).font(size: 12).codeCaretBlink(.off).gutterMarkerLane(true)
            .foldState(fold).geometry(geometry).scrollState(scroll).onGutterBarClick { clicks.value.append($0) }
    }
    window.click(at: pt(60, 3))   // focus
    buffer.selections = [CodeSelection(caret: 0)]
    window.window.setNeedsRedraw(); window.tick()
    return Fx(window: window, buffer: buffer, decorations: decorations, fold: fold, geometry: geometry, scroll: scroll,
              clicks: clicks, pitch: codePitch(scale: 1))
}

private func center(_ r: Bounds<Pixels>) -> Point<Pixels> {
    pt(r.origin.x.value + r.size.width.value / 2, r.origin.y.value + r.size.height.value / 2)
}

// MARK: Layout

/// **1** Hidden rows are not laid out: with `2..<8` (and `4..<6` inside it) and `10..<13` folded, row 8 sits at the third
/// shown row after the header, and the nested fold alone stays folded when its outer one opens. **Mutation:** the
/// nested span counted twice (row 8 lands a row too high); the hidden rows built anyway (a y for row 3).
@Test @MainActor func foldedRowsAreNotLaidOutAndNestedFoldsHideOnce() throws {
    let fx = try fixture(folds: [2..<8, 4..<6, 10..<13])
    defer { withExtendedLifetime(fx.window) {} }
    let p = fx.pitch
    for (row, shown) in [(0, 0), (1, 1), (2, 2), (8, 3), (9, 4), (10, 5), (13, 6), (14, 7)] {
        #expect(fx.y(row) == Float(shown) * p, "row \(row): \(String(describing: fx.y(row))), wanted \(Float(shown) * p)")
    }
    for row in [3, 4, 5, 6, 7, 11, 12] { #expect(fx.y(row) == nil, "row \(row) is hidden") }
    fx.fold.unfold(2..<8)
    fx.redraw()
    #expect(fx.y(3) == 3 * p && fx.y(4) == 4 * p && fx.y(5) == nil && fx.y(6) == 5 * p, "the nested fold stays: 4 hides 5")
}

/// **2** The scroll extent is in shown rows: `2..<8` and `10..<13` hide seven rows of 60, so the furthest scroll is
/// seven rows less. **Mutation:** `displayRowCount` ignoring the hidden rows.
@Test @MainActor func theScrollExtentCountsShownRows() throws {
    func furthest(_ folds: [Range<Int>]) throws -> Double {
        let fx = try fixture(lines: 60, folds: folds)
        defer { withExtendedLifetime(fx.window) {} }
        fx.scroll.position = CodeScrollPosition(row: 10_000)
        fx.redraw()
        return fx.scroll.position.row
    }
    let plain = try furthest([]), folded = try furthest([2..<8, 4..<6, 10..<13])
    #expect(abs((plain - folded) - 7) < 1e-9, "plain \(plain), folded \(folded)")
}

/// **3** Virtual rows inside a fold are hidden with it, and one before the header or after the fold is not: a group
/// before row 2 (shown), two lines before row 5 (hidden) and one before row 8 (the first row after the fold, shown).
/// **Mutation:** counting only buffer rows as hidden (row 8 lands two rows low); hiding by gap `<= end` (the group
/// before row 8 vanishes, row 8 lands a row high).
@Test @MainActor func virtualRowsInsideAFoldAreHiddenWithIt() throws {
    let fx = try fixture(folds: [2..<8], height: 300) { _, d in
        virtualRows(d, [CodeVirtualRow(anchor: .before(line: 2), lines: ["A"]),
                        CodeVirtualRow(anchor: .before(line: 5), lines: ["B1", "B2"]),
                        CodeVirtualRow(anchor: .before(line: 8), lines: ["C"])])
    }
    defer { withExtendedLifetime(fx.window) {} }
    let p = fx.pitch
    #expect(fx.y(2) == 3 * p, "A sits above the header: \(String(describing: fx.y(2)))")
    #expect(fx.y(8) == 5 * p, "rows 0 1 A 2, then C, then 8: \(String(describing: fx.y(8)))")
    fx.fold.unfoldAll()
    fx.redraw()
    #expect(fx.y(8) == (8 + 4) * p, "unfolded, all four virtual lines are shown: \(String(describing: fx.y(8)))")
}

/// **4** The layout is cached on the fold state and rebuilt when the folds or the row map change: steady frames build
/// nothing, a fold builds, and a virtual row given afterwards builds and is laid out. **Mutation:** the cache keyed by
/// the fold revision alone (the virtual row is not seen: row 8 stays at the old place); no cache (a build per frame).
@Test @MainActor func theLayoutIsCachedOnTheFoldStateAndFollowsTheRowMap() throws {
    let fx = try fixture(folds: [2..<8])
    defer { withExtendedLifetime(fx.window) {} }
    let before = CodeViewStats.foldLayoutBuilds
    for _ in 0..<3 { fx.redraw() }
    #expect(CodeViewStats.foldLayoutBuilds == before, "steady frames build no layout")
    fx.fold.fold(10..<12)
    fx.redraw()
    #expect(CodeViewStats.foldLayoutBuilds > before)
    let folded = CodeViewStats.foldLayoutBuilds
    #expect(fx.y(8) == 3 * fx.pitch)
    virtualRows(fx.decorations, [CodeVirtualRow(anchor: .before(line: 1), lines: ["V"])])
    fx.redraw()
    #expect(CodeViewStats.foldLayoutBuilds > folded && fx.y(8) == 4 * fx.pitch, "\(String(describing: fx.y(8)))")
}

/// **5** The scroll anchor in a hidden row snaps to its header, and an anchor below a fold keeps its row (its display
/// row falls by the rows hidden above). **Mutation:** the anchor mapped without the snap (the view lands inside the
/// hidden rows' span, at row 5 less the hidden count); the hidden count not subtracted for the later anchor.
@Test @MainActor func aScrollAnchorInAHiddenRowSnapsToItsHeader() throws {
    let fx = try fixture(lines: 80)
    defer { withExtendedLifetime(fx.window) {} }
    fx.scroll.position = CodeScrollPosition(row: 5)
    fx.redraw()
    #expect(fx.scroll.position.row == 5)
    fx.fold.fold(2..<8)
    fx.redraw()
    #expect(fx.scroll.position.row == 2, "the anchor row 5 is hidden: the view starts at the header \(fx.scroll.position.row)")
    fx.scroll.position = CodeScrollPosition(row: 20)
    fx.redraw()
    #expect(fx.y(25) == 0, "shown row 20 is buffer row 25: \(String(describing: fx.y(25)))")
    fx.fold.fold(12..<16)   // three hidden rows above the anchor row
    fx.redraw()
    #expect(fx.y(25) == 0 && fx.scroll.position.row == 17, "the anchor keeps its row: \(fx.scroll.position.row)")
    fx.fold.unfoldAll()
    fx.redraw()
    #expect(fx.y(25) == 0 && fx.scroll.position.row == 25, "\(fx.scroll.position.row)")
}

/// **6** Edits follow: a line added above shifts the fold and the layout with it; an edit inside the hidden rows keeps
/// both; a line break at the end of the header opens it. **Mutation:** a layout not invalidated by the fold's
/// revision (the shifted fold shows the old rows).
@Test @MainActor func editsMoveTheFoldAndTheLayoutFollows() throws {
    let fx = try fixture(folds: [2..<8])
    defer { withExtendedLifetime(fx.window) {} }
    let p = fx.pitch
    fx.buffer.replace(0..<0, with: "top\n")
    fx.redraw()
    #expect(fx.fold.folded == [3..<9] && fx.y(3) == 3 * p && fx.y(4) == nil && fx.y(9) == 4 * p, "\(fx.fold.folded)")
    fx.buffer.replace(fx.at(6, 2)..<fx.at(6, 2), with: "zz")
    fx.redraw()
    #expect(fx.fold.folded == [3..<9] && fx.y(9) == 4 * p, "an edit inside the hidden rows keeps the fold")
    fx.buffer.replace(fx.at(3, 5)..<fx.at(3, 5), with: "\n")
    fx.redraw()
    #expect(fx.fold.folded.isEmpty && fx.y(4) == 4 * p, "a break in the header opens it")
}

// MARK: The placeholder

/// **7** A header ends in a placeholder rectangle after its last glyph, a row high, nil for a line that is not a folded
/// header or is hidden. **Mutation:** the rectangle at the text origin (x before the header's end); `nil` for a
/// folded header (no draw).
@Test @MainActor func theGeometryAnswersThePlaceholderRectOfAFoldedHeader() throws {
    let fx = try fixture(folds: [2..<8])
    defer { withExtendedLifetime(fx.window) {} }
    let rect = try #require(fx.geometry.foldPlaceholderRect(line: 2))
    let text = try #require(fx.geometry.rects(for: fx.buffer.snapshot().lineRange(2)).first)
    #expect(rect.origin.x.value >= text.origin.x.value + text.size.width.value, "after the last glyph")
    #expect(rect.origin.y == text.origin.y && rect.size.height == text.size.height && rect.size.width.value > 0)
    #expect(fx.geometry.foldPlaceholderRect(line: 1) == nil && fx.geometry.foldPlaceholderRect(line: 4) == nil)
    #expect(fx.geometry.foldPlaceholderRect(line: 20) == nil, "not shown or not a header")
    let hit = try #require(fx.geometry.hit(at: center(rect)))
    #expect(hit.foldedLines == 2..<8 && hit.region == .pastLineEnd && hit.row == 2 && hit.character == nil, "\(hit)")
    let beyond = try #require(fx.geometry.hit(at: pt(rect.origin.x.value + rect.size.width.value + 20, rect.origin.y.value + 2)))
    #expect(beyond.foldedLines == nil && beyond.region == .pastLineEnd, "\(beyond)")
    let onText = try #require(fx.geometry.hit(at: pt(text.origin.x.value + 3, text.origin.y.value + 2)))
    #expect(onText.foldedLines == nil)
}

/// **8** A press on the placeholder unfolds and is consumed: the caret and selection stay, and the press beside it
/// places the caret at the header's end and keeps the fold. **Mutation:** the press not consumed (the caret moves to
/// the header's end); the unfold dropped (the fold stays).
@Test @MainActor func aPressOnThePlaceholderUnfoldsAndIsConsumed() throws {
    let fx = try fixture(folds: [2..<8])
    defer { withExtendedLifetime(fx.window) {} }
    let rect = try #require(fx.geometry.foldPlaceholderRect(line: 2))
    fx.window.click(at: pt(rect.origin.x.value + rect.size.width.value + 30, rect.origin.y.value + 2))
    #expect(fx.fold.folded == [2..<8], "a press beside the placeholder keeps the fold")
    #expect(fx.buffer.primarySelection == CodeSelection(caret: fx.at(2, 5)), "and places the caret at the header's end")
    fx.buffer.selections = [CodeSelection(caret: 0)]
    fx.redraw()
    fx.window.click(at: center(rect))
    #expect(fx.fold.folded.isEmpty, "the fold opened")
    #expect(fx.buffer.primarySelection == CodeSelection(caret: 0), "the press was consumed: no caret move")
    #expect(fx.y(3) == 3 * fx.pitch)
}

/// **9** `fold-placeholder-<line>` is a `.button` node over the placeholder, built only while a client collects
/// accessibility. **Mutation:** building the nodes unconditionally (the count rises with no client); a wrong
/// identifier.
@Test @MainActor func thePlaceholderIsAButtonNodeOnlyWhileAClientCollects() throws {
    let before = CodeViewStats.foldPlaceholderNodes
    let quiet = try fixture(folds: [2..<8, 12..<15], accessibility: false)
    quiet.redraw()
    #expect(CodeViewStats.foldPlaceholderNodes == before, "no client, no node")
    withExtendedLifetime(quiet.window) {}
    let fx = try fixture(folds: [2..<8, 12..<15])
    defer { withExtendedLifetime(fx.window) {} }
    let buttons = try fx.window.elements(role: .button)
    let ids = Set(buttons.compactMap(\.identifier))
    #expect(ids == ["fold-placeholder-2", "fold-placeholder-12"], "\(ids)")
    let node = try #require(buttons.first { $0.identifier == "fold-placeholder-2" })
    let rect = try #require(fx.geometry.foldPlaceholderRect(line: 2))
    #expect(node.frame == rect, "\(node.frame) vs \(rect)")
    #expect(CodeViewStats.foldPlaceholderNodes > before)
}

// MARK: Motion

/// **10** Up and down step over the hidden rows, left at the start of the row after a fold goes to the header's end and
/// right at the header's end goes to the next shown row; word motion and extend do the same; nothing opens the fold.
/// **Mutation:** stepping in lines (down from the header lands in row 3, which unfolds the fold); the wrap going to
/// `row - 1`.
@Test @MainActor func motionSkipsHiddenRows() throws {
    let fx = try fixture(lines: 20, folds: [2..<8])
    defer { withExtendedLifetime(fx.window) {} }
    let w = fx.window
    fx.caret(1, 2)
    w.typeKey(.downArrow)
    #expect(fx.heads() == [[2, 2]])
    w.typeKey(.downArrow)
    #expect(fx.heads() == [[8, 2]], "over the hidden rows: \(fx.heads())")
    w.typeKey(.upArrow)
    #expect(fx.heads() == [[2, 2]])
    w.typeKey(.upArrow)
    #expect(fx.heads() == [[1, 2]])
    fx.caret(8, 0)
    w.typeKey(.leftArrow)
    #expect(fx.heads() == [[2, 5]], "left from the row after the fold: the header's end \(fx.heads())")
    w.typeKey(.rightArrow)
    #expect(fx.heads() == [[8, 0]], "right from the header's end: the next shown row \(fx.heads())")
    fx.caret(2, 5)
    w.typeKey(.rightArrow, modifierFlags: codeWord)
    #expect(fx.heads() == [[8, 0]], "a word step does the same \(fx.heads())")
    w.typeKey(.leftArrow, modifierFlags: codeWord)
    #expect(fx.heads() == [[2, 5]])
    fx.caret(2, 2)
    w.typeKey(.downArrow, modifierFlags: .shift)
    #expect(fx.buffer.primarySelection == CodeSelection(anchor: fx.at(2, 2), head: fx.at(8, 2)), "extend steps over too")
    #expect(fx.fold.folded == [2..<8], "no motion opened the fold")
}

/// **11** A fold at the end of the document: down from the last shown row goes to the header's end, never into the
/// hidden rows; and paging steps in shown rows. **Mutation:** `utf8Count` as the target (inside the hidden rows, which
/// opens the fold).
@Test @MainActor func motionPastTheEndStopsAtTheLastShownRow() throws {
    let fx = try fixture(lines: 20, folds: [15..<20])
    defer { withExtendedLifetime(fx.window) {} }
    fx.caret(14, 0)
    fx.window.typeKey(.downArrow)
    #expect(fx.heads() == [[15, 0]])
    fx.window.typeKey(.downArrow)
    #expect(fx.heads() == [[15, 6]], "the end of the header: \(fx.heads())")
    fx.window.typeKey(.end, modifierFlags: codePrimary)
    #expect(fx.heads() == [[15, 6]] && fx.fold.folded == [15..<20], "document end: \(fx.heads()) \(fx.fold.folded)")
}

/// **12** With several carets each skips the hidden rows by itself, and the ones that meet merge. **Mutation:**
/// the multi-caret branch stepping `row + step` (the second caret lands in row 3 and opens the fold).
@Test @MainActor func everyCaretSkipsHiddenRows() throws {
    let fx = try fixture(lines: 20, folds: [2..<8])
    defer { withExtendedLifetime(fx.window) {} }
    let w = fx.window
    func carets(_ points: [(Int, Int)]) { fx.buffer.selectionState.setSelections(points.map { CodeSelection(caret: fx.at($0.0, $0.1)) }, primary: 0); fx.redraw() }
    carets([(1, 2), (2, 2), (9, 1)])
    w.typeKey(.downArrow)
    #expect(fx.heads() == [[2, 2], [8, 2], [10, 1]], "\(fx.heads())")
    w.typeKey(.upArrow)
    #expect(fx.heads() == [[1, 2], [2, 2], [9, 1]], "\(fx.heads())")
    carets([(8, 0), (0, 0), (10, 0)])
    w.typeKey(.leftArrow)
    #expect(fx.heads() == [[0, 0], [2, 5], [9, 5]], "the wraps skip too: \(fx.heads())")
    carets([(1, 0), (2, 0)])
    w.typeKey(.downArrow)
    #expect(fx.heads() == [[2, 0], [8, 0]])
    #expect(fx.fold.folded == [2..<8])
}

// MARK: Markers

/// **13** A folded header's lane marker is the strongest of the hidden rows' (and its own): the higher severity, then
/// the owner of higher priority, then the earlier line. **Mutation:** the first hidden marker (tag 30); the last
/// (tag 60); the lower-priority owner on a tie (tag 40); ignoring the header's own marker.
@Test @MainActor func aFoldedHeaderShowsTheStrongestHiddenMarker() throws {
    let lsp = CodeDecorationOwner("lsp", priority: 1), lint = CodeDecorationOwner("lint", priority: 5)
    func tag(_ marks: [(owner: CodeDecorationOwner, row: Int, severity: Int, tag: UInt64)]) throws -> UInt64? {
        let fx = try fixture(folds: [2..<8]) { _, d in
            for m in marks {
                d.setLineDecorations(marks.filter { $0.owner == m.owner }.map {
                    CodeLineDecoration(lines: $0.row..<($0.row + 1), gutterMarker: CodeGutterMarker("!", severity: $0.severity), tag: $0.tag)
                }, asOf: d.buffer.version, owner: m.owner)
            }
        }
        defer { withExtendedLifetime(fx.window) {} }
        fx.window.click(at: pt(3, 2.5 * fx.pitch))
        return fx.clicks.value.last.map { $0.tag } ?? nil
    }
    #expect(try tag([(lsp, 3, 1, 30), (lsp, 5, 3, 50), (lsp, 6, 3, 60)]) == 50, "severity, then the earlier line")
    #expect(try tag([(lsp, 4, 2, 40), (lint, 6, 2, 66)]) == 66, "a tie: the owner of higher priority")
    #expect(try tag([(lsp, 2, 5, 20), (lsp, 4, 2, 40)]) == 20, "the header's own marker, when the strongest")
    #expect(try tag([(lsp, 9, 5, 90)]) == nil, "a marker below the fold is not the header's")
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

private struct FoldCard: Component, @MainActor Equatable {
    let buffer: CodeBuffer
    let decorations: CodeDecorations
    let fold: CodeFoldState?
    let scroll: CodeScrollState
    var content: some ElementGroup {
        if let fold {
            CodeView(buffer: buffer, decorations: decorations).font(size: 12).showsLineNumbers(false).codeCaretBlink(.off)
                .scrollState(scroll).foldState(fold)
        } else {
            CodeView(buffer: buffer, decorations: decorations).font(size: 12).showsLineNumbers(false).codeCaretBlink(.off)
                .scrollState(scroll)
        }
    }
    static func == (l: FoldCard, r: FoldCard) -> Bool {
        l.buffer === r.buffer && l.decorations === r.decorations && l.fold === r.fold && l.scroll === r.scroll
    }
}

/// A scrolled window over 80 lines, optionally with a fold state holding `folds` (five: two above the viewport, three
/// inside it).
@MainActor private func openCard(attach: Bool, folds: [Range<Int>], carets: Int = 1) async throws -> (TestWindow, CodeBuffer, CodeFoldState?) {
    let buffer = CodeBuffer(foldText(80))
    let decorations = CodeDecorations(buffer: buffer)
    let fold = attach ? CodeFoldState(selectionState: buffer.selectionState) : nil
    let scroll = CodeScrollState(CodeScrollPosition(row: 20))
    let w = try harnessWindow(size: sz(400, 200)) {
        HStack(spacing: 0) {   // the structure of `CodeViewMultiCaretCostTests`, whose literals are master's
            ForEach(0..<1, id: \.self) { _ in
                FoldCard(buffer: buffer, decorations: decorations, fold: fold, scroll: scroll).equatable().frame(width: Pixels(180), height: Pixels(150))
            }
        }
    }
    for _ in 0..<2 { w.window.setNeedsRedraw(); try await w.runUntilIdle() }
    w.click(at: pt(60, 6))
    let snap = buffer.snapshot()
    if carets > 1 {
        buffer.selectionState.setSelections((0..<carets).map { CodeSelection(caret: snap.offset(of: CodePoint(row: 30 + $0, column: 3))) }, primary: 0)
    }
    fold?.folded = folds
    for _ in 0..<4 { w.window.setNeedsRedraw(); try await w.runUntilIdle() }
    return (w, buffer, fold)
}

private let fiveFolds = [2..<5, 8..<11, 22..<25, 27..<30, 32..<35]

@MainActor private func steadyCost(attach: Bool, folds: [Range<Int>]) async throws -> Cost {
    let (w, _, _) = try await openCard(attach: attach, folds: folds)
    defer { withExtendedLifetime(w) {} }
    w.resetFrameWork()
    w.window.setNeedsRedraw(); try await w.runUntilIdle()
    return Cost(totalWork(w), frames: w.frameWork.count)
}

@MainActor private func keystrokeCost(attach: Bool, folds: [Range<Int>]) async throws -> Cost {
    let (w, buffer, _) = try await openCard(attach: attach, folds: folds)
    defer { withExtendedLifetime(w) {} }
    let before = buffer.snapshot().utf8Count
    w.resetFrameWork()
    w.typeText("a")
    try await w.runUntilIdle()
    #expect(buffer.snapshot().utf8Count == before + 1)
    return Cost(totalWork(w), frames: w.frameWork.count)
}

/// **14** A view with no fold state costs what master costs (a steady frame: 2 requests, 0/1/0 retention; a keystroke
/// likewise, on Apple platforms where the frame count is fixed), and a view with a fold state, nothing folded, the
/// same. **Mutation:** an element or a retention taint added for the fold state (requests or misses move).
@Test @MainActor func aViewWithoutFoldsCostsWhatMasterCosts() async throws {
    let steady = try await steadyCost(attach: false, folds: []), keystroke = try await keystrokeCost(attach: false, folds: [])
    #expect(steady == Cost(requests: 1, hits: 1, misses: 0, ineligible: 0, frames: 1)   // `RK-AS`: grafted under the focus (was 2 requests)
    , "steady: \(steady)")
    #if canImport(Darwin)
    #expect(keystroke == Cost(requests: 2, hits: 0, misses: 1, ineligible: 0, frames: 1), "keystroke: \(keystroke)")
    #endif
    let attachedSteady = try await steadyCost(attach: true, folds: []), attachedKeystroke = try await keystrokeCost(attach: true, folds: [])
    #expect(attachedSteady == steady, "attached, nothing folded: \(attachedSteady) vs \(steady)")
    #if canImport(Darwin)
    #expect(attachedKeystroke == keystroke, "\(attachedKeystroke) vs \(keystroke)")
    #else
    #expect(attachedKeystroke.perFrameEquals(keystroke), "\(attachedKeystroke) vs \(keystroke)")
    #endif
}

/// **15** Five folds, two above the viewport and three inside it, cost what the same view costs with nothing folded:
/// steady and keystroke, in requests and retention. **Mutation:** a wrapper element per placeholder (requests grow);
/// the placeholder painted through an element or a retention taint (misses or ineligible move).
@Test @MainActor func fiveFoldsCostWhatNoFoldsCost() async throws {
    let none = try await steadyCost(attach: true, folds: []), five = try await steadyCost(attach: true, folds: fiveFolds)
    #expect(five == none, "steady: \(five) vs \(none)")
    let keyNone = try await keystrokeCost(attach: true, folds: []), keyFive = try await keystrokeCost(attach: true, folds: fiveFolds)
    #if canImport(Darwin)
    #expect(keyFive == keyNone, "keystroke: \(keyFive) vs \(keyNone)")
    #else
    #expect(keyFive.perFrameEquals(keyNone), "keystroke: \(keyFive) vs \(keyNone)")
    #endif
}

/// **16** Idle with folds and three carets, the blink off: no frame, no request. **Mutation:** a fold path noting a
/// deadline or an animation (a frame at each half second).
@Test @MainActor func anIdleViewWithFoldsAndThreeCaretsCostsNothing() async throws {
    let (w, buffer, _) = try await openCard(attach: true, folds: fiveFolds, carets: 3)
    defer { withExtendedLifetime(w) {} }
    #expect(buffer.selections.count == 3)
    w.resetFrameWork()
    let frames = w.framesDrawn
    for _ in 0..<8 { w.advance(by: 0.25) }
    try await w.runUntilIdle()
    #expect(w.framesDrawn == frames && totalWork(w).elementRequests == 0 && !w.window.hasActiveAnimations,
            "frames \(w.framesDrawn - frames), requests \(totalWork(w).elementRequests)")
}

@MainActor private func bmVirtuals(_ b: CodeBuffer, _ d: CodeDecorations) {
    virtualRows(d, [CodeVirtualRow(anchor: .before(line: 2), lines: ["A"]),
                    CodeVirtualRow(anchor: .before(line: 5), lines: ["B1", "B2"]),
                    CodeVirtualRow(anchor: .before(line: 8), lines: ["C"])])
}

/// **17** `scrollRow(forLine:)` and `line(forScrollRow:)` over a fold with virtual rows: shown rows are `l0 l1 A l2 C l8
/// ...`. A shown line round-trips; a hidden line maps to its header's row; a virtual row maps to the line it sits before
/// (the fold's hidden ones are not rows); out of range is `nil`. **Mutation:** `scrollRow` answering the unfolded
/// display row (line 8 -> 12), or `line(forScrollRow:)` ignoring the fold (row 5 -> a hidden line).
@Test @MainActor func scrollRowAndLineConvertOverAFoldAndVirtualRows() throws {
    let fx = try fixture(folds: [2..<8], height: 300, setup: bmVirtuals)
    defer { withExtendedLifetime(fx.window) {} }
    let g = fx.geometry
    for line in [0, 1, 2, 8, 9, 39] {
        let row = try #require(g.scrollRow(forLine: line))
        #expect(g.line(forScrollRow: row) == line, "line \(line) row \(row)")
    }
    #expect(g.scrollRow(forLine: 8) == 5 && g.scrollRow(forLine: 0) == 0 && g.scrollRow(forLine: 2) == 3)
    for hidden in 3..<8 { #expect(g.scrollRow(forLine: hidden) == 3, "hidden line \(hidden) is its header's row") }
    #expect(g.line(forScrollRow: 2) == 2, "A sits before line 2")
    #expect(g.line(forScrollRow: 4) == 8, "C sits before line 8")
    #expect(g.scrollRow(forLine: -1) == nil && g.scrollRow(forLine: 40) == nil)
    #expect(g.line(forScrollRow: -1) == nil && g.line(forScrollRow: 37) == nil)
    #expect(g.line(forScrollRow: 36) == 39)
    fx.fold.unfoldAll()
    fx.redraw()
    #expect(g.scrollRow(forLine: 8) == 12, "unfolded, all four virtual lines count")
}

/// **18** With no fold state, the row map alone answers. **Mutation:** the fold branch taken without a layout (crash or
/// a wrong row).
@Test @MainActor func scrollRowAndLineWithNoFoldState() throws {
    let buffer = CodeBuffer(foldText(10))
    let decorations = CodeDecorations(buffer: buffer)
    bmVirtuals(buffer, decorations)
    let geometry = CodeViewGeometry()
    let window = try harnessWindow(size: sz(400, 300)) {
        CodeView(buffer: buffer, decorations: decorations).font(size: 12).geometry(geometry)
    }
    defer { withExtendedLifetime(window) {} }
    window.window.setNeedsRedraw(); window.tick()
    #expect(geometry.scrollRow(forLine: 2) == 3 && geometry.scrollRow(forLine: 5) == 8 && geometry.scrollRow(forLine: 8) == 12)
    #expect(geometry.line(forScrollRow: 2) == 2 && geometry.line(forScrollRow: 5) == 4 && geometry.line(forScrollRow: 6) == 5 && geometry.line(forScrollRow: 7) == 5)
    #expect(geometry.line(forScrollRow: 11) == 8 && geometry.line(forScrollRow: 13) == 9 && geometry.line(forScrollRow: 14) == nil)
    #expect(CodeViewGeometry().scrollRow(forLine: 0) == nil && CodeViewGeometry().line(forScrollRow: 0) == nil)
}

/// **19** Two views with different folds synced by line show the same top line; synced by raw row they do not.
/// **Mutation:** the destination copying the row (`b.scroll = a.scroll`): the top line differs.
@Test @MainActor func twoViewsWithDifferentFoldsSyncedByLineShowTheSameTopLine() throws {
    let a = try fixture(folds: [2..<8], height: 200, setup: bmVirtuals)
    let b = try fixture(folds: [10..<20], height: 200)
    defer { withExtendedLifetime((a.window, b.window)) {} }
    a.scroll.position = CodeScrollPosition(row: 5)   // shown rows: l0 l1 A l2 C l8 -> line 8 on top
    a.redraw()
    let top = try #require(a.geometry.line(forScrollRow: Int(a.scroll.position.row)))
    #expect(top == 8)
    let row = try #require(b.geometry.scrollRow(forLine: top))
    b.scroll.position = CodeScrollPosition(row: Double(row))
    b.redraw()
    #expect(b.y(top) == 0 && a.y(top) == 0, "both show line \(top) on top: \(String(describing: b.y(top))) \(String(describing: a.y(top)))")
    // The same line past b's fold: a's row 20 is line 23 in a, but row 20 in b is line 30.
    a.scroll.position = CodeScrollPosition(row: 20)
    a.redraw()
    let far = try #require(a.geometry.line(forScrollRow: 20))
    b.scroll.position = CodeScrollPosition(row: 20)
    b.redraw()
    #expect(b.y(far) != 0, "copying the row shows another line")
}
