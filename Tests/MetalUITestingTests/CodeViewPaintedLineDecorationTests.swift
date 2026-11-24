import Testing
import Foundation
import MetalUI
import MetalUIScene
import MetalUITesting

// `CodeDecorations.paintedLineDecoration(row:)` (`CV-BZ`, Alloy: a plugin's tests read the decorations back instead of
// scanning rects for 3 pt bars): the merged, per-field-owner result the view paints. PLAIN imports; the harness text
// system. Narrow builder blocks (`PE-K`): every view is one `CodeView` chain.

private let planHue = Color(hue: 0.1, saturation: 1, brightness: 1)
private let diffHue = Color(hue: 0.6, saturation: 1, brightness: 1)
private let markHue = Color(hue: 0.321, saturation: 1, brightness: 1)
private let plugin = CodeDecorationOwner("plugin", priority: 1)
private let diff = CodeDecorationOwner("diff", priority: 9)

private func text(_ lines: Int) -> String { (0..<lines).map { "line\($0) = x" }.joined(separator: "\n") + "\n" }
private func tint(_ alpha: Float, hue: Double = 0) -> Color { Color(red: 1, green: hue, blue: 0).opacity(Double(alpha)) }

@MainActor private func window(_ buffer: CodeBuffer, _ decorations: CodeDecorations) throws -> TestWindow {
    try harnessWindow(size: sz(400, 600)) { CodeView(buffer: buffer, decorations: decorations).font(size: 12).codeCaretBlink(.off) }
}

/// The tint alphas and bar hues the last frame paints over buffer row `row`, read from the scene.
@MainActor private func scenePaint(_ window: TestWindow, row: Int) -> (tints: [Float], bars: [Double], markers: [Double]) {
    let pitch = codePitch(scale: 1)
    let top = Float(row) * pitch, bottom = top + pitch
    func covers(_ b: MUIBounds) -> Bool { b.origin.y <= top + 0.5 && b.origin.y + b.size.height >= bottom - 0.5 }
    let rects = window.scene.rects.filter { covers($0.bounds) }
    let tints = rects.filter { $0.bounds.size.width > 50 && $0.background.a < 0.99 }.map(\.background.a).sorted()
    let bars = rects.filter { $0.bounds.size.width == 3 }.map { Double($0.background.h) }.sorted()
    let markers = window.scene.glyphs.filter { $0.bounds.origin.y >= top - 1 && $0.bounds.origin.y < bottom && abs($0.color.h - 0.321) < 0.001 }
        .map { Double($0.color.h) }
    return (tints, bars, markers)
}

/// 1 - two owners on a shared row: the higher priority wins the tint and the bar, and the result names it; swapping
/// the priorities swaps the winner; a tie goes to the later name; each field has its own owner (the bar the winner
/// does not set comes from the other). **Mutations:** `backgroundOwner` picked from the ascending order's first
/// instead of last entry; the bar owner read as the default.
@Test @MainActor func theHigherPriorityOwnerWinsTheTintAndBarAndIsNamed() throws {
    let buffer = CodeBuffer(text(30))
    let decorations = CodeDecorations(buffer: buffer)
    func set(_ pluginPriority: Int, _ diffPriority: Int) {
        let v = buffer.version
        decorations.setLineDecorations([CodeLineDecoration(lines: 10..<16, gutterBar: planHue, background: tint(0.31), tag: 1)],
                                       asOf: v, owner: CodeDecorationOwner("plugin", priority: pluginPriority))
        decorations.setLineDecorations([CodeLineDecoration(lines: 12..<14, gutterBar: diffHue, background: tint(0.32), tag: 2)],
                                       asOf: v, owner: CodeDecorationOwner("diff", priority: diffPriority))
    }
    set(1, 9)   // diff over plugin
    let shared = try #require(decorations.paintedLineDecoration(row: 12))
    #expect(shared.background == tint(0.32) && shared.backgroundOwner == "diff")
    #expect(shared.gutterBar == CodePaintedGutterBar(color: diffHue, lines: 12..<14, tag: 2, owner: "diff"))
    let only = try #require(decorations.paintedLineDecoration(row: 10))
    #expect(only.background == tint(0.31) && only.backgroundOwner == "plugin")
    #expect(only.gutterBar == CodePaintedGutterBar(color: planHue, lines: 10..<12, tag: 1, owner: "plugin"),
            "the plugin's bar is cut where the diff's takes over: \(String(describing: only.gutterBar))")
    set(9, 1)   // plugin over diff
    let swapped = try #require(decorations.paintedLineDecoration(row: 12))
    #expect(swapped.background == tint(0.31) && swapped.backgroundOwner == "plugin")
    #expect(swapped.gutterBar?.owner == "plugin" && swapped.gutterBar?.color == planHue && swapped.gutterBar?.lines == 10..<16)
    set(3, 3)   // a tie: the later name
    #expect(decorations.paintedLineDecoration(row: 12)?.backgroundOwner == "plugin")
    // Per field: the diff sets only a tint, the plugin a bar.
    decorations.setLineDecorations([CodeLineDecoration(lines: 10..<16, gutterBar: planHue, tag: 1)], asOf: buffer.version, owner: plugin)
    decorations.setLineDecorations([CodeLineDecoration(lines: 12..<14, background: tint(0.32))], asOf: buffer.version, owner: diff)
    let split = try #require(decorations.paintedLineDecoration(row: 12))
    #expect(split.backgroundOwner == "diff" && split.gutterBar?.owner == "plugin", "each field names its own winner")
    #expect(split.gutterBar?.lines == 10..<16)
}

/// 2 - a bar spanning rows 3..<7 reads the same from every row of the span, and not from the rows beside it; the
/// default owner reads as `nil`. **Mutation:** `lines` taken as `row..<(row + 1)`.
@Test @MainActor func aBarSpanReadsTheSameFromEveryRow() throws {
    let buffer = CodeBuffer(text(30))
    let decorations = CodeDecorations(buffer: buffer)
    decorations.setLineDecorations([CodeLineDecoration(lines: 3..<7, gutterBar: planHue, tag: 77)], asOf: buffer.version)
    let first = try #require(decorations.paintedLineDecoration(row: 3))
    #expect(first.gutterBar == CodePaintedGutterBar(color: planHue, lines: 3..<7, tag: 77, owner: nil))
    for row in 3..<7 { #expect(decorations.paintedLineDecoration(row: row) == first, "row \(row)") }
    #expect(decorations.paintedLineDecoration(row: 2) == nil && decorations.paintedLineDecoration(row: 7) == nil)
}

/// 3 - a row's marker is the one `strongestMarker` picks: the owner of higher priority's marker over a more severe
/// one of a lower (the merge keeps one per row), its tag and owner with it, and a marker with no text paints nothing,
/// so a row with only that reads `nil`. **Mutation:** the marker read from the raw payload without the empty-text filter.
@Test @MainActor func aMarkersWinnerFollowsStrongestMarker() throws {
    let buffer = CodeBuffer(text(30))
    let decorations = CodeDecorations(buffer: buffer)
    decorations.setLineDecorations([CodeLineDecoration(lines: 4..<5, gutterMarker: CodeGutterMarker("E", color: markHue, severity: 9), tag: 1)],
                                   asOf: buffer.version, owner: plugin)
    decorations.setLineDecorations([CodeLineDecoration(lines: 4..<5, gutterMarker: CodeGutterMarker("w", severity: 1), tag: 2)],
                                   asOf: buffer.version, owner: diff)
    let row = try #require(decorations.paintedLineDecoration(row: 4))
    let strongest = try #require(decorations.strongestMarker(in: 4..<5))
    #expect(row.gutterMarker == strongest.marker && row.gutterMarker == CodeGutterMarker("w", severity: 1))
    #expect(row.gutterMarkerOwner == "diff" && row.gutterMarkerTag == 2, "priority decides inside one row, not severity")
    decorations.setLineDecorations([CodeLineDecoration(lines: 6..<7, gutterMarker: CodeGutterMarker(""))], asOf: buffer.version, owner: plugin)
    #expect(decorations.paintedLineDecoration(row: 6) == nil, "an empty marker paints nothing")
}

/// 4 - nothing decorates the row, or the row is not one: `nil`. **Mutation:** the result returned for an empty payload.
@Test @MainActor func anUndecoratedRowReadsNil() throws {
    let buffer = CodeBuffer(text(30))
    let decorations = CodeDecorations(buffer: buffer)
    #expect(decorations.paintedLineDecoration(row: 0) == nil, "no decorations at all")
    decorations.setLineDecorations([CodeLineDecoration(lines: 5..<6, background: tint(0.3))], asOf: buffer.version, owner: plugin)
    #expect(decorations.paintedLineDecoration(row: 4) == nil && decorations.paintedLineDecoration(row: 6) == nil)
    #expect(decorations.paintedLineDecoration(row: -1) == nil && decorations.paintedLineDecoration(row: 10_000) == nil)
    #expect(decorations.paintedLineDecoration(row: 5)?.background == tint(0.3))
}

/// 5 - decorations follow edits (`CV-K`): two rows inserted above shift the tint, the bar's span and the marker
/// down by two, and the owners stay; a decoration given for an older version lands mapped forward.
/// **Mutation:** reading before the edit cursor drains (no `sync()`).
@Test @MainActor func anEditAboveShiftsTheReadBackRows() throws {
    let buffer = CodeBuffer(text(30))
    let decorations = CodeDecorations(buffer: buffer)
    let old = buffer.version
    decorations.setLineDecorations([CodeLineDecoration(lines: 5..<8, gutterBar: planHue, background: tint(0.31), gutterMarker: CodeGutterMarker("!"), tag: 3)],
                                   asOf: old, owner: plugin)
    buffer.replace(0..<0, with: "a\nb\n")
    #expect(decorations.paintedLineDecoration(row: 5) == nil, "the old rows are bare now")
    let moved = try #require(decorations.paintedLineDecoration(row: 8))
    #expect(moved.gutterBar == CodePaintedGutterBar(color: planHue, lines: 7..<10, tag: 3, owner: "plugin"))
    #expect(moved.background == tint(0.31) && moved.backgroundOwner == "plugin" && moved.gutterMarker?.text == "!")
    decorations.setLineDecorations([CodeLineDecoration(lines: 20..<21, background: tint(0.32))], asOf: old, owner: diff)   // old row 20
    #expect(decorations.paintedLineDecoration(row: 22)?.backgroundOwner == "diff" && decorations.paintedLineDecoration(row: 20) == nil)
}

/// 6 - agreement: for a scripted set of overlapping owners, bars, tints and markers, what is read back for every row
/// is what the scene holds over that row: the tint alpha, the bar hue and the marker glyph; and again after an edit.
/// **Mutation:** the read-back tint taken from the lower owner (the ascending order not reversed).
@Test @MainActor func theReadBackIsWhatTheViewPaints() throws {
    let buffer = CodeBuffer(text(30))
    let decorations = CodeDecorations(buffer: buffer)
    let v = buffer.version
    decorations.setLineDecorations([CodeLineDecoration(lines: 2..<9, gutterBar: planHue, background: tint(0.31), tag: 1),
                                    CodeLineDecoration(lines: 14..<16, background: tint(0.33), gutterMarker: CodeGutterMarker("p", color: markHue))],
                                   asOf: v, owner: plugin)
    decorations.setLineDecorations([CodeLineDecoration(lines: 5..<12, gutterBar: diffHue, background: tint(0.32), tag: 2),
                                    CodeLineDecoration(lines: 15..<17, gutterMarker: CodeGutterMarker("d", color: markHue))],
                                   asOf: v, owner: diff)
    let win = try window(buffer, decorations)
    let tints = [tint(0.31): Float(0.31), tint(0.32): 0.32, tint(0.33): 0.33]
    let hues = [planHue: 0.1, diffHue: 0.6]
    func agree(_ label: String) throws {
        win.window.setNeedsRedraw(); win.tick()
        var decorated = 0
        for row in 0..<28 {
            let painted = decorations.paintedLineDecoration(row: row)
            let scene = scenePaint(win, row: row)
            let expectedTint = painted?.background.flatMap { tints[$0] }
            #expect(scene.tints.map { Optional($0) } == (expectedTint.map { [$0] } ?? []).map { Optional($0) }, "\(label) tint, row \(row)")
            let expectedBar = painted?.gutterBar.flatMap { hues[$0.color] }
            #expect(scene.bars.count == (expectedBar == nil ? 0 : 1) && scene.bars.allSatisfy { abs($0 - (expectedBar ?? -1)) < 0.002 }, "\(label) bar, row \(row)")
            #expect(scene.markers.count == (painted?.gutterMarker == nil ? 0 : 1), "\(label) marker, row \(row)")
            if painted != nil { decorated += 1 }
        }
        #expect(decorated == 13, "\(label): rows 2..<12 and 14..<17 decorate (\(decorated))")
    }
    try agree("before")
    buffer.replace(0..<0, with: "a\nb\n")   // everything moves two rows down
    #expect(decorations.paintedLineDecoration(row: 4)?.background == tint(0.31))
    try agree("after an edit")
}
