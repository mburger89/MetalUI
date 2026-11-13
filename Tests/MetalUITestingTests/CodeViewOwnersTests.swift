import Testing
import Foundation
import MetalUI
import MetalUIScene
import MetalUITesting

// Keyed decoration owners and real-row gutter markers of `CodeView` (rulings `CV-AO`, `CV-AP`, record 272, Alloy
// G35 PR D): a diff and a language server decorate one view without erasing each other. PLAIN imports; the
// harness text system. Perf pins count work (`RunTreeStats.nodesVisited`, `CodeDecorations.ownerMerges`), never a clock.

private let markHue = Color(hue: 0.321, saturation: 1, brightness: 1)
private let diff = CodeDecorationOwner("diff", priority: 1)
private let lsp = CodeDecorationOwner("lsp", priority: 5)

@MainActor private func plainText(lines: Int) -> String {
    (0..<lines).map { "row\($0) = x" }.joined(separator: "\n") + "\n"
}

@MainActor private func tint(_ alpha: Float, hue: Double = 0) -> Color { Color(red: 1, green: hue, blue: 0).opacity(Double(alpha)) }

/// Rows 10..<20 of `diff`, tinted and barred; rows 12..<15 of `lsp`, tinted only: the shapes the merge tests use.
@MainActor private func setTwoOwners(_ decorations: CodeDecorations, diffPriority: Int = 9, lspPriority: Int = 1) {
    let v = decorations.buffer.version
    decorations.setLineDecorations([CodeLineDecoration(lines: 10..<20, gutterBar: .blue, background: tint(0.31), tag: 1)],
                                   asOf: v, owner: CodeDecorationOwner("diff", priority: diffPriority))
    decorations.setLineDecorations([CodeLineDecoration(lines: 12..<15, background: tint(0.32, hue: 1), tag: 2)],
                                   asOf: v, owner: CodeDecorationOwner("lsp", priority: lspPriority))
}

/// 1 — two owners merge per field by priority, no blending: the higher priority's tint wins, a field the winner does
/// not set (the bar) comes from the other owner, the bar's tag goes with the bar, and swapping the priorities swaps
/// the winner on the next set. The diff is registered first with the HIGHER priority, so "the owner set last wins"
/// is a different answer. **Mutation:** the merge folding the owners in registration order instead of ascending
/// (priority, name) makes the later-set lsp win rows 12..<15.
@Test @MainActor func twoOwnersMergeByPriorityPerField() throws {
    let buffer = CodeBuffer(plainText(lines: 40))
    let decorations = CodeDecorations(buffer: buffer)
    setTwoOwners(decorations)   // diff 9 over lsp 1
    let both = try #require(decorations.lineDecoration(row: 13))
    #expect(both.background == tint(0.31), "the higher priority's tint, not blended")
    #expect(both.gutterBar == .blue && both.tag == 1)
    #expect(decorations.lineDecoration(row: 11)?.background == tint(0.31))
    #expect(decorations.lineDecoration(row: 20) == nil)
    setTwoOwners(decorations, diffPriority: 1, lspPriority: 5)   // lsp now over diff
    let swapped = try #require(decorations.lineDecoration(row: 13))
    #expect(swapped.background == tint(0.32, hue: 1), "the lsp tint wins now")
    #expect(swapped.gutterBar == .blue && swapped.tag == 1, "the bar the lsp does not set still comes from the diff")
    #expect(decorations.lineDecoration(row: 16)?.background == tint(0.31), "outside the lsp rows the diff's")
    // A tie goes to the later name.
    setTwoOwners(decorations, diffPriority: 3, lspPriority: 3)
    #expect(decorations.lineDecoration(row: 13)?.background == tint(0.32, hue: 1), "lsp > diff by name")
    #expect(decorations.mergedLinesMatchOwners())
    // And it is what is painted.
    let window = try harnessWindow(size: sz(400, 600)) { CodeView(buffer: buffer, decorations: decorations).font(size: 12).codeCaretBlink(.off) }
    let pitch = codePitch(scale: 1)
    let lspRect = try #require(tintRects(window, alpha: 0.32).first)
    #expect(lspRect.bounds.size.height == 3 * pitch && lspRect.bounds.origin.y == 12 * pitch, "\(lspRect.bounds)")
    #expect(tintRects(window, alpha: 0.31).map(\.bounds.size.height).reduce(0, +) == 7 * pitch, "the diff's tint shows only outside the lsp rows")
}

/// 2 — setting one owner keeps the others' rows, shifted to the text now: the diff's removed lines follow edits
/// above, then the lsp's rows are set for an OLDER version and land mapped forward, and the diff's rows are where
/// the edits put them, not where they were given. **Mutations:** the multi-owner build dropping the other owners'
/// groups (the last set wins); the scratch map not replaying the edits since `asOf` (the lsp row lands too high).
@Test @MainActor func settingOneOwnerKeepsTheOthersShiftedRows() throws {
    let buffer = CodeBuffer(plainText(lines: 60))
    let decorations = CodeDecorations(buffer: buffer)
    decorations.setVirtualRows([CodeVirtualRow(anchor: .before(line: 20), lines: ["- gone"], background: tint(0.41))],
                               asOf: buffer.version, owner: diff)
    let old = buffer.version
    buffer.replace(0..<0, with: "a\nb\nc\n")   // three rows above: the diff's group is now before row 23
    decorations.setVirtualRows([CodeVirtualRow(anchor: .before(line: 30), lines: ["! note"], background: tint(0.42, hue: 1))],
                               asOf: old, owner: lsp)   // given for the old text: before old row 30, now row 33
    let window = try harnessWindow(size: sz(400, 1200)) { CodeView(buffer: buffer, decorations: decorations).font(size: 12).codeCaretBlink(.off) }
    let pitch = codePitch(scale: 1)
    #expect(decorations.virtualLineCount == 2, "both owners' rows are there")
    #expect(tintRects(window, alpha: 0.41).first?.bounds.origin.y == 23 * pitch, "the diff's group followed the edit: \(tintRects(window, alpha: 0.41).map(\.bounds))")
    #expect(tintRects(window, alpha: 0.42).first?.bounds.origin.y == 34 * pitch, "before row 33, below the diff's one virtual row")
    // The diff replaces its own rows; the lsp's stay.
    decorations.setVirtualRows([], asOf: buffer.version, owner: diff)
    window.window.setNeedsRedraw(); window.tick()
    #expect(decorations.virtualLineCount == 1)
    #expect(tintRects(window, alpha: 0.42).first?.bounds.origin.y == 33 * pitch)
    #expect(tintRects(window, alpha: 0.41).isEmpty)
}

/// 3 — virtual groups of two owners at ONE gap sit in ascending priority, whatever order they were set in, and one
/// owner's groups keep the order given. The lsp (priority 5) is set first, the diff (priority 1) second: the diff's
/// removed lines still come first. **Mutation:** the merge comparing priorities the other way round (or ignoring
/// them, which keeps the set order) puts the diagnostic first.
@Test @MainActor func virtualGroupsOfTwoOwnersAtOneGapOrderByPriority() throws {
    let buffer = CodeBuffer(plainText(lines: 40))
    let decorations = CodeDecorations(buffer: buffer)
    decorations.setVirtualRows([CodeVirtualRow(anchor: .before(line: 5), lines: ["! diag"], background: tint(0.42, hue: 1))],
                               asOf: buffer.version, owner: lsp)
    decorations.setVirtualRows([CodeVirtualRow(anchor: .before(line: 5), lines: ["- one", "- two"], background: tint(0.41)),
                                CodeVirtualRow(anchor: .before(line: 5), lines: ["- three"], background: tint(0.43, hue: 0.5))],
                               asOf: buffer.version, owner: diff)
    let window = try harnessWindow(size: sz(400, 600)) { CodeView(buffer: buffer, decorations: decorations).font(size: 12).codeCaretBlink(.off) }
    let pitch = codePitch(scale: 1)
    #expect(tintRects(window, alpha: 0.41).first?.bounds.origin.y == 5 * pitch, "the diff's first group: display rows 5 and 6")
    #expect(tintRects(window, alpha: 0.43).first?.bounds.origin.y == 7 * pitch, "its second, in the order given")
    #expect(tintRects(window, alpha: 0.42).first?.bounds.origin.y == 8 * pitch, "the diagnostic after all the diff's removed lines")
    // Setting the diff again does not move the diagnostic in front.
    decorations.setVirtualRows([CodeVirtualRow(anchor: .before(line: 5), lines: ["- one"], background: tint(0.41))],
                               asOf: buffer.version, owner: diff)
    window.window.setNeedsRedraw(); window.tick()
    #expect(tintRects(window, alpha: 0.42).first?.bounds.origin.y == 6 * pitch)
}

/// 4 — an edit costs logarithmic work per owner: one newline above decorations and virtual rows of two owners, at
/// 1 000 and 100 000 rows with a decoration and a group every ten rows (100 and 10 000 runs per owner), visits a
/// small constant more nodes at the larger size, and nothing like the runs. **Mutation:** an edit that rebuilds the
/// merged tree from the owners' runs (O(runs)) visits ten thousand.
@Test @MainActor func anEditCostsLogarithmicWorkPerOwner() throws {
    var visited: [Int] = []
    for rows in [1_000, 100_000] {
        let buffer = CodeBuffer(String(repeating: "x\n", count: rows))
        let decorations = CodeDecorations(buffer: buffer)
        let v = buffer.version
        for owner in [diff, lsp] {
            decorations.setLineDecorations(stride(from: 20, to: rows - 5, by: 10).map {
                CodeLineDecoration(lines: $0..<($0 + 3), gutterBar: .blue, background: tint(0.3), tag: UInt64($0))
            }, asOf: v, owner: owner)
            decorations.setVirtualRows(stride(from: 20, to: rows - 5, by: 10).map {
                CodeVirtualRow(anchor: .before(line: $0), lines: ["v"])
            }, asOf: v, owner: owner)
        }
        decorations.sync()
        let start = buffer.snapshot().offset(of: CodePoint(row: 5, column: 0))
        let before = RunTreeStats.nodesVisited
        buffer.replace(start..<start, with: "\n")
        decorations.sync()
        visited.append(RunTreeStats.nodesVisited - before)
        #expect(decorations.lineDecoration(row: 21)?.tag == 20, "row 20 moved to 21")
        #expect(decorations.mergedLinesMatchOwners())
    }
    #expect(visited[1] - visited[0] <= 150, "nodes visited for one newline at 1k and 100k rows: \(visited)")
    #expect(visited[1] < 700, "and not proportional to the runs: \(visited)")
}

/// 5 — a set costs time linear in the groups and runs, and a frame costs no merge: giving a second owner 500 and
/// then 8 000 groups (and line decorations) visits nodes in proportion (16 times the groups, at most 18 times the
/// nodes), a repaint of the idle view merges nothing and builds nothing, and a single owner never merges.
/// **Mutations:** `CodeRowMap.build` appending by `merge` (O(groups log groups)) breaks the ratio; the merge run
/// from `sync()` or the plan (every frame) moves `ownerMerges`.
@Test @MainActor func setCostIsLinearInGroupsAndZeroPerFrame() throws {
    var costs: [Int] = []
    for groups in [500, 8_000] {
        let buffer = CodeBuffer(String(repeating: "x\n", count: groups * 3))
        let decorations = CodeDecorations(buffer: buffer)
        let v = buffer.version
        decorations.setLineDecorations([CodeLineDecoration(lines: 0..<5, background: tint(0.3))], asOf: v)
        #expect(decorations.ownerMerges == 0, "one owner: the merged tree is the owner's, no merge")
        decorations.setVirtualRows([CodeVirtualRow(anchor: .before(line: 1), lines: ["d"])], asOf: v)
        let rows = (0..<groups).map { CodeVirtualRow(anchor: .before(line: 3 * $0), lines: ["v"]) }
        let lines = (0..<groups).map { CodeLineDecoration(lines: (3 * $0)..<(3 * $0 + 2), background: tint(0.3), tag: UInt64($0)) }
        let before = RunTreeStats.nodesVisited
        decorations.setVirtualRows(rows, asOf: v, owner: lsp)
        decorations.setLineDecorations(lines, asOf: v, owner: lsp)
        costs.append(RunTreeStats.nodesVisited - before)
        #expect(decorations.ownerMerges == 2, "one merge per set")
        let window = try harnessWindow(size: sz(400, 200)) { CodeView(buffer: buffer, decorations: decorations).font(size: 12).codeCaretBlink(.off) }
        let merges = decorations.ownerMerges
        window.window.setNeedsRedraw(); window.tick()
        window.window.setNeedsRedraw(); window.tick()
        #expect(decorations.ownerMerges == merges, "an idle repaint merges nothing")
    }
    #expect(costs[1] >= 10 * costs[0] && costs[1] <= 18 * costs[0], "nodes visited by a set at 500 and 8 000 groups: \(costs)")
}

/// A one-line row-0 band's glyphs, as (minimum x, maximum x), for the row at `row`.
@MainActor private func glyphExtent(_ window: TestWindow, row: Int) -> (min: Float, max: Float)? {
    let pitch = codePitch(scale: 1)
    let xs = window.scene.glyphs.filter { $0.bounds.origin.y >= Float(row) * pitch - 1 && $0.bounds.origin.y < Float(row + 1) * pitch }
        .map { $0.bounds.origin.x }
    guard let lo = xs.min(), let hi = xs.max() else { return nil }
    return (lo, hi)
}

/// 6 — a real-row marker sits in a lane that the text never moves for, or replaces the number. With the lane
/// reserved, the text of every row is where it is without markers, and the marker is in the lane left of the
/// numbers; by default the lane appears when the first marker is given and then stays (it does not leave when the
/// markers do); with the lane off, the text never moves and the marker takes its row's number. **Mutation:** the
/// lane's width depending on the markers present (reserved only while a marker exists) moves the text when the
/// last marker goes.
@Test @MainActor func aRealRowMarkerReplacesTheNumberOrSitsInTheLane() throws {
    func fixture(_ lane: Bool?) throws -> (TestWindow, CodeDecorations) {
        let buffer = CodeBuffer(plainText(lines: 30))
        let decorations = CodeDecorations(buffer: buffer)
        let base = CodeView(buffer: buffer, decorations: decorations).font(size: 12).codeCaretBlink(.off)
        let view = lane.map { base.gutterMarkerLane($0) } ?? base
        let window = try harnessWindow(size: sz(400, 600)) { view }
        return (window, decorations)
    }
    func setMarkers(_ d: CodeDecorations, on: Bool) {
        d.setLineDecorations(on ? [CodeLineDecoration(lines: 3..<4, gutterMarker: CodeGutterMarker("!", color: markHue), tag: 11)] : [],
                             asOf: d.buffer.version, owner: lsp)
    }
    func redraw(_ w: TestWindow) { w.window.setNeedsRedraw(); w.tick() }
    let pitch = codePitch(scale: 1)

    // Reserved from the first frame: nothing moves when markers come and go.
    let (reserved, rd) = try fixture(true)
    let textX = try #require(glyphExtent(reserved, row: 3)).max
    let numberX = try #require(glyphExtent(reserved, row: 3)).min
    setMarkers(rd, on: true); redraw(reserved)
    let withMarker = try #require(glyphExtent(reserved, row: 3))
    #expect(withMarker.max == textX, "the text did not move")
    let marks = reserved.scene.glyphs.filter { abs($0.color.h - 0.321) < 0.001 && $0.bounds.origin.y < 4 * pitch && $0.bounds.origin.y >= 3 * pitch }
    #expect(marks.count == 1 && marks[0].bounds.origin.x < numberX, "the marker is in the lane, left of the numbers: \(marks.map(\.bounds)) vs \(numberX)")
    #expect(reserved.scene.glyphs.filter { $0.bounds.origin.y >= 3 * pitch && $0.bounds.origin.y < 4 * pitch && $0.bounds.origin.x == numberX }.count == 1,
            "and the line number is still there")
    setMarkers(rd, on: false); redraw(reserved)
    #expect(glyphExtent(reserved, row: 3)?.max == textX && glyphExtent(reserved, row: 3)?.min == numberX, "the lane stays when the markers go")

    // The default: no lane until a marker is given, then the lane stays.
    let (auto, ad) = try fixture(nil)
    let before = try #require(glyphExtent(auto, row: 3)).max
    setMarkers(ad, on: true); redraw(auto)
    let laneWidth = try #require(glyphExtent(auto, row: 3)).max - before
    #expect(laneWidth > 0 && textX == before + laneWidth, "the lane is the width a reserved lane has: \(laneWidth)")
    setMarkers(ad, on: false); redraw(auto)
    #expect(glyphExtent(auto, row: 3)?.max == before + laneWidth, "sticky: the text does not move back when the markers go")

    // The lane off: a marker replaces its row's number and the text never moves.
    let (off, od) = try fixture(false)
    let offText = try #require(glyphExtent(off, row: 3)).max
    let digits = off.scene.glyphs.filter { $0.bounds.origin.y >= 3 * pitch && $0.bounds.origin.y < 4 * pitch && $0.bounds.origin.x < offText - 40 }.count
    setMarkers(od, on: true); redraw(off)
    #expect(glyphExtent(off, row: 3)?.max == offText, "no lane: the text did not move")
    let replaced = off.scene.glyphs.filter { $0.bounds.origin.y >= 3 * pitch && $0.bounds.origin.y < 4 * pitch && $0.bounds.origin.x < offText - 40 }
    #expect(digits == 1 && replaced.count == 1 && abs(replaced[0].color.h - 0.321) < 0.001, "the one-digit number became the marker: \(digits) \(replaced.map(\.color))")
}

/// 7 — removing an owner clears only its line decorations and virtual rows; the other owners' stay, and the default
/// owner can be removed like any. **Mutation:** removal that resets every tree.
@Test @MainActor func removeDecorationsClearsOnlyThatOwner() throws {
    let buffer = CodeBuffer(plainText(lines: 40))
    let decorations = CodeDecorations(buffer: buffer)
    setTwoOwners(decorations)
    decorations.setLineDecorations([CodeLineDecoration(lines: 30..<32, background: tint(0.33))], asOf: buffer.version)
    decorations.setVirtualRows([CodeVirtualRow(anchor: .before(line: 5), lines: ["- gone"])], asOf: buffer.version, owner: diff)
    decorations.setVirtualRows([CodeVirtualRow(anchor: .before(line: 6), lines: ["! diag"])], asOf: buffer.version, owner: lsp)
    #expect(decorations.virtualLineCount == 2)
    decorations.removeDecorations(of: lsp)
    #expect(decorations.virtualLineCount == 1, "the diff's removed line stays")
    #expect(decorations.lineDecoration(row: 13)?.background == tint(0.31), "the diff's tint shows through where the lsp's was")
    #expect(decorations.lineDecoration(row: 30)?.background == tint(0.33), "the default owner's stay")
    #expect(decorations.mergedLinesMatchOwners())
    decorations.removeDecorations(of: CodeDecorationOwner("never-set"))
    decorations.removeDecorations(of: .default)
    #expect(decorations.lineDecoration(row: 30) == nil && decorations.lineDecoration(row: 11) != nil)
    decorations.removeDecorations(of: diff)
    #expect(decorations.virtualLineCount == 0 && decorations.lineDecoration(row: 11) == nil)
}

/// 8 — a click on a marker reports its row, tag and owner, `.gutterMarker`, and neither moves the caret nor selects;
/// a click on a bar reports the bar's owner, and a virtual row its group's; the default owner reads as `nil`.
/// **Mutation:** the hit built without `ownerOf` (owner `nil`) or with the first row of the frame.
@Test @MainActor func aMarkerClickReportsRowAndOwner() throws {
    let clicks = Cell<[CodeGutterHit]>([])
    let buffer = CodeBuffer(plainText(lines: 40))
    let decorations = CodeDecorations(buffer: buffer)
    decorations.setLineDecorations([CodeLineDecoration(lines: 6..<9, gutterBar: .blue, tag: 4)], asOf: buffer.version, owner: diff)
    decorations.setLineDecorations([CodeLineDecoration(lines: 8..<9, gutterMarker: CodeGutterMarker("!"), tag: 12),
                                    CodeLineDecoration(lines: 2..<3, gutterMarker: CodeGutterMarker("?"), tag: 13)],
                                   asOf: buffer.version, owner: lsp)
    decorations.setVirtualRows([CodeVirtualRow(anchor: .before(line: 20), lines: ["- x"], gutterBar: .green, tag: 5)],
                               asOf: buffer.version, owner: diff)
    let window = try harnessWindow(size: sz(400, 600)) {
        CodeView(buffer: buffer, decorations: decorations).font(size: 12).codeCaretBlink(.off)
            .onGutterBarClick { clicks.value.append($0) }
    }
    let pitch = codePitch(scale: 1)
    buffer.selections = [CodeSelection(caret: 0)]
    window.click(at: pt(3, 8.5 * pitch))   // the lane
    #expect(clicks.value == [CodeGutterHit(lines: 8..<9, tag: 12, source: .gutterMarker, displayRow: 8, owner: lsp)], "\(clicks.value)")
    window.click(at: pt(3, 2.5 * pitch))
    #expect(clicks.value.last == CodeGutterHit(lines: 2..<3, tag: 13, source: .gutterMarker, displayRow: 2, owner: lsp))
    #expect(buffer.primarySelection == CodeSelection(caret: 0), "a marker press neither moves the caret nor selects")
    let barX = try #require(gutterBars(window).first).x
    window.click(at: pt(barX, 7.5 * pitch))
    #expect(clicks.value.last == CodeGutterHit(lines: 6..<9, tag: 4, source: .lineDecoration, displayRow: 7, owner: diff), "\(clicks.value.last as Any)")
    window.click(at: pt(barX, 20.5 * pitch))
    #expect(clicks.value.last == CodeGutterHit(lines: 20..<21, tag: 5, source: .virtualRow, displayRow: 20, owner: diff), "\(clicks.value.last as Any)")
    // A lane press where no marker is drawn still selects the line (no hit, so the handler is not called).
    let count = clicks.value.count
    window.click(at: pt(3, 4.5 * pitch))
    #expect(clicks.value.count == count)
    #expect(buffer.snapshot().text(in: buffer.primarySelection.range) == buffer.snapshot().line(4) + "\n")
}

/// 9 — the merged line decorations match an array model under random owner sets and edits: three owners of different
/// priorities give random decorations (tint, bar with tag, marker), newlines are inserted and removed at random, and
/// every row's merged payload equals the model's per-field highest-priority answer. **Mutation:** the edit path
/// splicing the owner trees but not the merged tree.
@Test @MainActor func mergedLineDecorationsMatchAnArrayModelUnderRandomSetsAndEdits() throws {
    struct Cell3: Equatable { var tint: Int?; var bar: Int?; var tag: Int?; var marker: Int? }
    var state: UInt64 = 0xDEC0
    func next(_ bound: Int) -> Int {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Int((state >> 33) % UInt64(max(1, bound)))
    }
    let owners = [CodeDecorationOwner("a", priority: 2), CodeDecorationOwner("b", priority: 7), CodeDecorationOwner("c", priority: 7)]
    func color(_ i: Int) -> Color { tint(0.2, hue: Double(i) / 10) }
    for round in 0..<25 {
        let rows = 20 + next(40)
        let buffer = CodeBuffer(String(repeating: "x\n", count: rows))
        let decorations = CodeDecorations(buffer: buffer)
        var model: [[Cell3]] = Array(repeating: Array(repeating: Cell3(), count: rows + 1), count: owners.count)
        for step in 0..<14 {
            if step % 4 < 2 {
                let o = next(owners.count)
                var list: [CodeLineDecoration] = []
                var cells = Array(repeating: Cell3(), count: model[o].count)
                var at = next(4)
                while at < model[o].count - 1 {
                    let len = 1 + next(4)
                    let hi = min(at + len, model[o].count - 1)
                    let t = next(3) == 0 ? nil : 1 + next(9), b = next(3) == 0 ? nil : 1 + next(9), m = next(3) == 0 ? nil : 1 + next(9)
                    if t != nil || b != nil || m != nil {
                        list.append(CodeLineDecoration(lines: at..<hi, gutterBar: b.map(color), background: t.map(color),
                                                       gutterMarker: m.map { CodeGutterMarker("\($0)") }, tag: UInt64(o)))
                        for r in at..<hi { cells[r] = Cell3(tint: t, bar: b, tag: b == nil ? nil : o, marker: m) }
                    }
                    at = hi + next(5)
                }
                decorations.setLineDecorations(list, asOf: buffer.version, owner: owners[o])
                model[o] = cells
            } else {
                let row = next(model[0].count - 2)
                let start = buffer.snapshot().offset(of: CodePoint(row: row, column: 0))
                if next(3) == 0, row + 1 < model[0].count - 2 {   // delete a line break
                    let end = buffer.snapshot().offset(of: CodePoint(row: row + 1, column: 0))
                    buffer.replace((end - 1)..<end, with: "")
                    for o in 0..<owners.count { model[o].remove(at: row + 1) }
                } else {
                    buffer.replace(start..<start, with: "\n")   // splits `row`: the new row after it takes its decoration
                    for o in 0..<owners.count { model[o].insert(model[o][row], at: row + 1) }
                }
            }
            decorations.sync()
            #expect(decorations.mergedLinesMatchOwners(), "round \(round) step \(step)")
            // Highest priority wins each field; a tie goes to the later name.
            let order = owners.indices.sorted { (owners[$0].priority, owners[$0].name) < (owners[$1].priority, owners[$1].name) }
            for row in 0..<(model[0].count - 1) {
                var want = Cell3()
                for o in order {
                    let c = model[o][row]
                    if c.tint != nil { want.tint = c.tint }
                    if c.bar != nil { want.bar = c.bar; want.tag = c.tag }
                    if c.marker != nil { want.marker = c.marker }
                }
                let got = decorations.lineDecoration(row: row)
                #expect(got?.background == want.tint.map(color) && got?.gutterBar == want.bar.map(color)
                        && got?.tag == want.tag.map(UInt64.init) && got?.marker?.text == want.marker.map { "\($0)" },
                        "round \(round) step \(step) row \(row): \(String(describing: got)) vs \(want)")
            }
        }
    }
}
