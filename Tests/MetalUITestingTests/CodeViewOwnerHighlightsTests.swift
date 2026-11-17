import Testing
import Foundation
import MetalUI
import MetalUIScene
import MetalUITesting

// Owner-keyed range highlights (ruling `CV-BV`, record 373, Alloy plugins #1): each (layer, named owner) is a
// sub-layer; the cross-layer merge walks sub-layers ordered by (layer, priority, name) and the higher priority
// wins each field. PLAIN imports; the harness text system.

private let hueA = 0.111, hueB = 0.222
private func fg(_ hue: Double) -> Color { Color(hue: hue, saturation: 0.8, brightness: 0.9) }
private let wave = CodeUnderline.wavy(Color(red: 1, green: 0, blue: 0))
private let dash = CodeUnderline(.line(.dash), color: Color(red: 0, green: 0, blue: 1))
private let lspOwner = CodeDecorationOwner("lsp", priority: 1)
private let pluginOwner = CodeDecorationOwner("plugin", priority: 5)

/// Whether `body` redraws the views: what they observe changed (`revision` is internal; `findMatches` reads it).
@MainActor private func redraws(_ d: CodeDecorations, _ body: () -> Void) -> Bool {
    final class Flag: @unchecked Sendable { var fired = false }
    let flag = Flag()
    withObservationTracking({ _ = d.findMatches }, onChange: { flag.fired = true })
    body()
    return flag.fired
}

/// The runs' ranges with adjacent ones joined (a tree keeps the pieces an edit splits a run into).
@MainActor private func joined(_ runs: [CodeStyleRun]) -> [Range<Int>] {
    var out: [Range<Int>] = []
    for r in runs.map(\.range) {
        if let last = out.last, last.upperBound == r.lowerBound { out[out.count - 1] = last.lowerBound..<r.upperBound } else { out.append(r) }
    }
    return out
}

private func letters(rows: Int = 12) -> String {
    (0..<rows).map { row in String((0..<40).map { Character(UnicodeScalar(UInt8(97 + ($0 + row) % 26))) }) }.joined(separator: "\n") + "\n"
}

/// Two owners underline the same stretch in one layer; the lower-priority language server keeps the stretch the
/// plugin does not cover, and the plugin's (higher priority) underline wins where they overlap, per stretch.
/// **Mutation:** `setHighlights(owner:)` writing the default tree (ignoring the owner) makes the plugin replace the
/// server's runs wholesale: the server's `0..<10` is gone.
@Test @MainActor func pluginUnderlineDoesNotReplaceLanguageServers() {
    let buffer = CodeBuffer(letters())
    let d = CodeDecorations(buffer: buffer)
    let wavy = d.register(CodeStyle(underline: wave)), dashed = d.register(CodeStyle(underline: dash))
    let all = 0..<buffer.utf8Count
    d.setHighlights([CodeStyleRun(range: 0..<10, style: wavy)], in: all, layer: .diagnostics, asOf: buffer.version, owner: lspOwner)
    d.setHighlights([CodeStyleRun(range: 6..<14, style: dashed)], in: all, layer: .diagnostics, asOf: buffer.version, owner: pluginOwner)
    let line = buffer.snapshot().lineRange(0)
    let got = d.stylingOfLine(line).underlines.map { "\($0.range.lowerBound)..<\($0.range.upperBound):\($0.underline == wave ? "lsp" : "plugin")" }
    #expect(got == ["0..<6:lsp", "6..<14:plugin"], "\(got)")
    #expect(d.highlights(in: all, layer: .diagnostics, owner: lspOwner).map(\.range) == [0..<10], "the server's runs are intact")
    #expect(d.highlights(in: all, layer: .diagnostics, owner: pluginOwner).map(\.range) == [6..<14])
    #expect(d.highlights(in: all, layer: .diagnostics).isEmpty, "the default owner holds nothing")
}

/// Per field, the higher priority wins, and a field it does not set comes from the lower one: a plugin colour (priority
/// 5) beats the server's (1), the server's underline survives under it, and swapping the priorities swaps the
/// winner. **Mutation:** ordering sub-layers by registration instead of (priority, name) makes the later-registered
/// win in both orders.
@Test @MainActor func higherPriorityWinsPerField() {
    let buffer = CodeBuffer(letters())
    let d = CodeDecorations(buffer: buffer)
    let a = d.register(CodeStyle(foreground: fg(hueA), underline: wave)), b = d.register(CodeStyle(foreground: fg(hueB)))
    let all = 0..<buffer.utf8Count
    d.setHighlights([CodeStyleRun(range: 2..<8, style: a)], in: all, layer: .semantic, asOf: buffer.version, owner: lspOwner)
    d.setHighlights([CodeStyleRun(range: 4..<12, style: b)], in: all, layer: .semantic, asOf: buffer.version, owner: pluginOwner)
    func probe() -> (fg: Color?, underlined: Bool) {
        let painted = d.paintedRuns(in: 4..<6)
        return (painted.first?.style.foreground, painted.first?.style.underline != nil)
    }
    #expect(probe().fg == fg(hueB), "the plugin's colour wins")
    #expect(probe().underlined, "the server's underline is a field the plugin does not set")
    // Swap: the server now outranks the plugin; re-registering re-sorts.
    d.setHighlights([CodeStyleRun(range: 2..<8, style: a)], in: all, layer: .semantic, asOf: buffer.version,
                    owner: CodeDecorationOwner("lsp", priority: 9))
    #expect(probe().fg == fg(hueA), "re-registered with a higher priority: the server's colour wins")
    // A tie goes to the later name.
    d.setHighlights([CodeStyleRun(range: 2..<8, style: a)], in: all, layer: .semantic, asOf: buffer.version,
                    owner: CodeDecorationOwner("lsp", priority: 5))
    #expect(probe().fg == fg(hueB), "equal priority: the later name ('plugin') wins")
    // A named owner in a higher layer beats any priority in a lower one.
    d.setHighlights([CodeStyleRun(range: 4..<6, style: a)], in: all, layer: .diagnostics, asOf: buffer.version,
                    owner: CodeDecorationOwner("low", priority: -3))
    #expect(probe().fg == fg(hueA), "layers order before priorities")
}

/// `removeDecorations(of:)` drops the owner's sub-layers in every layer and leaves the others and the default tree.
/// **Mutation:** removing only the first layer's sub-layer leaves `.diagnostics` painted.
@Test @MainActor func removeDecorationsClearsHighlights() {
    let buffer = CodeBuffer(letters())
    let d = CodeDecorations(buffer: buffer)
    let a = d.register(CodeStyle(foreground: fg(hueA))), b = d.register(CodeStyle(foreground: fg(hueB)))
    let all = 0..<buffer.utf8Count
    d.setHighlights([CodeStyleRun(range: 0..<5, style: a)], in: all, layer: .syntax, asOf: buffer.version, owner: pluginOwner)
    d.setHighlights([CodeStyleRun(range: 0..<5, style: a)], in: all, layer: .diagnostics, asOf: buffer.version, owner: pluginOwner)
    d.setHighlights([CodeStyleRun(range: 10..<15, style: b)], in: all, layer: .syntax, asOf: buffer.version, owner: lspOwner)
    d.setHighlights([CodeStyleRun(range: 20..<25, style: b)], in: all, layer: .syntax, asOf: buffer.version)
    #expect(redraws(d) { d.removeDecorations(of: pluginOwner) }, "a redraw")
    for layer in CodeHighlightLayer.allCases { #expect(d.highlights(in: all, layer: layer, owner: pluginOwner).isEmpty, "\(layer)") }
    #expect(d.paintedRuns(in: 0..<5).isEmpty)
    #expect(d.paintedRuns(in: 10..<15).count == 1, "another owner stays")
    #expect(d.highlights(in: all, layer: .syntax).map(\.range) == [20..<25], "the default tree stays")
    #expect(!redraws(d) { d.removeDecorations(of: pluginOwner) }, "a second removal is a no-op")
}

/// Named owners are push-only and always valid: the provider is never asked for them, and an edit does not make
/// them stale. **Mutation:** the sub-layer's tree joining `rowsNeedingHighlights` (or its splice leaving `.unknown`
/// payloads) makes the provider asked.
@Test @MainActor func namedOwnerNeverAsksProvider() throws {
    let buffer = CodeBuffer(letters())
    let d = CodeDecorations(buffer: buffer)
    let a = d.register(CodeStyle(foreground: fg(hueA)))
    let all = 0..<buffer.utf8Count
    d.setHighlights([CodeStyleRun(range: 0..<5, style: a)], in: all, layer: .syntax, asOf: buffer.version, owner: pluginOwner)
    let snapshot = buffer.snapshot()
    // Nothing is known in the default syntax tree: it is still asked for every row, named runs notwithstanding.
    #expect(d.rowsNeedingHighlights(in: 0..<12, snapshot: snapshot) == 0..<12)
    // Answer the default tree; then an edit inside the named run stales nothing the provider is asked for.
    d.setHighlights([], in: all, layer: .syntax, asOf: buffer.version)
    #expect(d.rowsNeedingHighlights(in: 0..<12, snapshot: buffer.snapshot()) == nil)
    _ = try buffer.replace(2..<2, with: "ZZ")
    d.sync()
    let after = d.rowsNeedingHighlights(in: 0..<12, snapshot: buffer.snapshot())
    #expect(after == 0..<1, "only the default tree's edit-touched row is stale: \(String(describing: after))")
    #expect(joined(d.highlights(in: 0..<buffer.utf8Count, layer: .syntax, owner: pluginOwner)) == [0..<7], "the run grew with the insert")
}

/// A named sub-layer follows edits like any layer: above, inside and a deletion across its run. **Mutation:** a
/// sub-layer left out of `apply(_:)` keeps its offsets.
@Test @MainActor func subLayerFollowsEdits() throws {
    let buffer = CodeBuffer(letters())
    let d = CodeDecorations(buffer: buffer)
    let a = d.register(CodeStyle(foreground: fg(hueA)))
    let all = 0..<buffer.utf8Count
    d.setHighlights([CodeStyleRun(range: 50..<55, style: a)], in: all, layer: .semantic, asOf: buffer.version, owner: pluginOwner)
    _ = try buffer.replace(0..<0, with: "XYZ")
    #expect(d.highlights(in: 0..<buffer.utf8Count, layer: .semantic, owner: pluginOwner).map(\.range) == [53..<58])
    _ = try buffer.replace(54..<56, with: "")
    #expect(joined(d.highlights(in: 0..<buffer.utf8Count, layer: .semantic, owner: pluginOwner)) == [53..<56])
    // A set as of an older version maps forward through the edits since.
    let old = buffer.version
    _ = try buffer.replace(0..<0, with: "Q")
    d.setHighlights([CodeStyleRun(range: 10..<12, style: a)], in: 0..<buffer.utf8Count - 1, layer: .semantic, asOf: old, owner: pluginOwner)
    #expect(d.highlights(in: 0..<20, layer: .semantic, owner: pluginOwner).map(\.range) == [11..<13])
}

/// A call that changes nothing neither redraws nor creates a sub-layer (`CV-AG`): empty runs on an owner with
/// none, an empty range, the same empty answer twice; a real set does redraw. **Mutation:** bumping the revision
/// unconditionally fails the first three.
@Test @MainActor func setThatChangesNothingDoesNotRedraw() {
    let buffer = CodeBuffer(letters())
    let d = CodeDecorations(buffer: buffer)
    let a = d.register(CodeStyle(foreground: fg(hueA)))
    let all = 0..<buffer.utf8Count
    #expect(!redraws(d) { d.setHighlights([], in: all, layer: .syntax, asOf: buffer.version, owner: pluginOwner) }, "no runs, no sub-layer")
    #expect(!redraws(d) { d.setHighlights([CodeStyleRun(range: 0..<3, style: a)], in: 4..<4, layer: .syntax, asOf: buffer.version, owner: pluginOwner) }, "an empty range")
    #expect(redraws(d) { d.setHighlights([CodeStyleRun(range: 0..<3, style: a)], in: all, layer: .syntax, asOf: buffer.version, owner: pluginOwner) }, "a run")
    #expect(redraws(d) { d.setHighlights([], in: all, layer: .syntax, asOf: buffer.version, owner: pluginOwner) }, "clearing a run")
    #expect(!redraws(d) { d.setHighlights([], in: all, layer: .syntax, asOf: buffer.version, owner: pluginOwner) }, "the same again")
    #expect(!redraws(d) { d.setHighlights([CodeStyleRun(range: 0..<3, style: a)], in: 0..<0, layer: .syntax, asOf: buffer.version, owner: lspOwner) })
}

/// With no named owner nothing about styling changes (`CV-BV` cost rule): the counters and the frame literals are
/// master's. A provider fills the syntax layer, a default-owner semantic layer underlines, the view paints and
/// repaints; the literals are the counters of the unchanged default-owner path (runsVisited, stylingComputations, needingHighlightScans, lines painted, lines shaped, glyphs). **Mutation:** iterating a rebuilt
/// source list per call instead of the cached one, or visiting sub-layers that do not exist, moves `runsVisited`.
@Test @MainActor func noNamedOwnerStylingIsByteIdentical() throws {
    let buffer = CodeBuffer(codeText(lines: 300))
    let decorations = CodeDecorations(buffer: buffer)
    let style = decorations.register(CodeStyle(foreground: fg(hueA)))
    let squiggle = decorations.register(CodeStyle(underline: wave))
    decorations.highlightProvider = RecordingProvider(style: style)
    let window = try codeWindow(buffer: buffer, decorations: decorations)
    for _ in 0..<2 { window.window.setNeedsRedraw(); window.tick() }
    decorations.setHighlights([CodeStyleRun(range: 4..<9, style: squiggle)], in: 0..<buffer.utf8Count, layer: .diagnostics, asOf: buffer.version)
    for _ in 0..<2 { window.window.setNeedsRedraw(); window.tick() }
    let work = totalWork(window)
    let literal = [decorations.runsVisited, decorations.stylingComputations, decorations.needingHighlightScans,
                   work.codeLinesPainted, work.codeLinesShaped, work.codeGlyphsEmitted]
    #expect(literal == [1, 26, 0, 60, 13, 1440], "\(literal)")
}
