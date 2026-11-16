import Testing
import Foundation
import Observation
import MetalUI
import MetalUIScene
import MetalUITesting

// What chaining text-anchored presentations on a `CodeView` costs a frame (`CV-BC`, record 332). The view's anchor
// list is empty for a view with no presentation (no allocation, one `isEmpty` check), so the literals of a frame with
// none, and with one presentation, are exactly what the single `textAnchorBox` produced on master (measured there:
// the same two tests, red under the mutation below); two presentations add the second wrapper and its panel.

@Observable @MainActor private final class CostModel {
    var shown = true
    var item: Int?
    var itemBinding: Binding<CostPick?> { Binding(get: { self.item.map(CostPick.init) }, set: { self.item = $0?.id }) }
    var shownBinding: Binding<Bool> { Binding(get: { self.shown }, set: { self.shown = $0 }) }
}

private struct CostPick: Identifiable { let id: Int }

private struct CostCounts: Equatable, CustomStringConvertible {
    var requests = 0, hits = 0, misses = 0, ineligible = 0
    init(_ f: FrameWork) {
        requests = f.elementRequests
        hits = f.retainedHits
        misses = f.retainedMisses
        ineligible = f.retainedIneligible
    }
    init(requests: Int, hits: Int, misses: Int, ineligible: Int) {
        self.requests = requests; self.hits = hits; self.misses = misses; self.ineligible = ineligible
    }
    var description: String { "requests \(requests) hits \(hits) misses \(misses) ineligible \(ineligible)" }
}

/// A retained sibling, so the retention counters are not all zero.
private struct CostBar: Component, @MainActor Equatable {
    nonisolated static func == (a: CostBar, b: CostBar) -> Bool { true }
    var content: some ElementGroup { Text("bar").frame(width: Pixels(40), height: Pixels(10)) }
}

/// The steady frame's and a keystroke frame's counts of a 400 x 200 view with `presentations` text-anchored
/// presentations chained on it (0, 1: a suggestion overlay, 2: that and a popover).
@MainActor private func costs(presentations: Int) async throws -> (steady: CostCounts, keystroke: CostCounts) {
    let model = CostModel()
    let buffer = CodeBuffer((0..<60).map { "row\($0) alpha beta gamma\n" }.joined())
    let window = try harnessWindow(size: sz(400, 300)) {
        VStack(spacing: 0) {
            CostBar().equatable()
            view(model, buffer, presentations)
            Spacer(minLength: 0)
        }
    }
    defer { withExtendedLifetime(window) {} }
    try await window.runUntilIdle()
    window.click(at: pt(60, 6))
    buffer.selections = [CodeSelection(caret: 0)]
    model.item = presentations > 1 ? 1 : nil   // after the click: a press on the anchored text dismisses a popover
    window.window.setNeedsRedraw()
    try await window.runUntilIdle()
    for _ in 0..<3 { window.window.setNeedsRedraw(); window.tick() }
    let steady = CostCounts(window.lastFrameWork)
    window.typeText("x")
    let keystroke = CostCounts(window.lastFrameWork)
    return (steady, keystroke)
}

@MainActor private func base(_ buffer: CodeBuffer) -> CodeView {
    CodeView(buffer: buffer, decorations: CodeDecorations(buffer: buffer)).font(size: 12).showsLineNumbers(false)
        .codeCaretBlink(.off)
}

@MainActor @ElementBuilder private func view(_ model: CostModel, _ buffer: CodeBuffer, _ presentations: Int) -> some ElementGroup {
    switch presentations {
    case 0:
        base(buffer).frame(width: Pixels(400), height: Pixels(200))
    case 1:
        base(buffer).suggestionOverlay(isPresented: model.shownBinding, attachmentAnchor: .caret) { Text("SUG") }
            .frame(width: Pixels(400), height: Pixels(200))
    default:
        base(buffer).suggestionOverlay(isPresented: model.shownBinding, attachmentAnchor: .caret) { Text("SUG") }
            .popover(item: model.itemBinding, attachmentAnchor: .range(0..<4), arrowEdge: .bottom) { _ in Text("POP") }
            .frame(width: Pixels(400), height: Pixels(200))
    }
}

/// **1** No presentation: a steady frame and a keystroke frame cost what master's did (measured there with the
/// single `textAnchorBox`: 3 requests, 1 retained hit, no miss, none ineligible). Mutation: see test 3's.
@Test @MainActor func aViewWithNoPresentationCostsWhatItDid() async throws {
    let c = try await costs(presentations: 0)
    let want = CostCounts(requests: 3, hits: 1, misses: 0, ineligible: 0)
    #expect(c.steady == want && c.keystroke == want, "steady \(c.steady) | keystroke \(c.keystroke)")
}

/// **2** One presentation (an open suggestion overlay): the same counts as on master (7 requests, 1 hit, 0, 0), both
/// frames. Mutation: `Popover.chrome` wrapping a text-anchored panel's box in a second `Box` adds a request.
@Test @MainActor func oneOpenPresentationCostsWhatItDid() async throws {
    let c = try await costs(presentations: 1)
    let want = CostCounts(requests: 7, hits: 1, misses: 0, ineligible: 0)
    #expect(c.steady == want && c.keystroke == want, "steady \(c.steady) | keystroke \(c.keystroke)")
}

/// **3** Two presentations (an overlay and an item popover): a measured literal, four requests a presented panel,
/// as the first one's (11 requests, 1 hit, 0, 0). Mutation: as test 2's.
@Test @MainActor func twoOpenPresentationsCostTwiceTheOnePanel() async throws {
    let c = try await costs(presentations: 2)
    let want = CostCounts(requests: 11, hits: 1, misses: 0, ineligible: 0)
    #expect(c.steady == want && c.keystroke == want, "steady \(c.steady) | keystroke \(c.keystroke)")
}
