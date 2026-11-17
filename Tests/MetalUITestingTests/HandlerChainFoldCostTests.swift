import Testing
import Foundation
import Observation
import MetalUI
import MetalUIScene
import MetalUITesting

@Observable @MainActor private final class FoldModel { var shown = true
    var shownBinding: Binding<Bool> { Binding(get: { self.shown }, set: { self.shown = $0 }) } }

private struct FoldCounts: Equatable, CustomStringConvertible {
    var requests = 0, hits = 0, misses = 0, ineligible = 0
    init(requests: Int, hits: Int, misses: Int, ineligible: Int) {
        self.requests = requests; self.hits = hits; self.misses = misses; self.ineligible = ineligible
    }
    init(_ f: FrameWork) {
        requests = f.elementRequests; hits = f.retainedHits; misses = f.retainedMisses; ineligible = f.retainedIneligible
    }
    var description: String { "requests \(requests) hits \(hits) misses \(misses) ineligible \(ineligible)" }
}

// What two handler modifiers before a `.frame` cost a frame (ruling `KF-AF`, record 352). `.onKeyPress` over a
// `PopoverModifier` (or any group with no layer) makes one wrapper chain; `.onDisappear` makes a `LifecycleScope`
// over it; the `.frame` after then started a second chain around the scope, one more counted request on every
// frame. A wrapper modifier written after a scope over a chain now joins the chain, the scope sitting under it.
// Red before: "keyThenDisappear" and "disappearThenKey" cost 8 against 7.

private enum Shape: String, CaseIterable { case none, keyOnly, disappearOnly, keyThenDisappear, disappearThenKey, bothAfterFrame }

@MainActor private func foldCodeBase(_ buffer: CodeBuffer) -> CodeView {
    CodeView(buffer: buffer, decorations: CodeDecorations(buffer: buffer)).font(size: 12).showsLineNumbers(false)
        .codeCaretBlink(.off)
}

@MainActor @ElementBuilder private func foldCode(_ s: Shape, _ model: FoldModel, _ buffer: CodeBuffer) -> some ElementGroup {
    switch s {
    case .none:
        foldCodeBase(buffer).suggestionOverlay(isPresented: model.shownBinding, attachmentAnchor: .caret) { Text("SUG") }
            .frame(width: Pixels(400), height: Pixels(200)).accessibilityIdentifier("code")
    case .keyOnly:
        foldCodeBase(buffer).suggestionOverlay(isPresented: model.shownBinding, attachmentAnchor: .caret) { Text("SUG") }
            .onKeyPress(.escape) { .ignored }
            .frame(width: Pixels(400), height: Pixels(200)).accessibilityIdentifier("code")
    case .disappearOnly:
        foldCodeBase(buffer).suggestionOverlay(isPresented: model.shownBinding, attachmentAnchor: .caret) { Text("SUG") }
            .onDisappear {}
            .frame(width: Pixels(400), height: Pixels(200)).accessibilityIdentifier("code")
    case .keyThenDisappear:
        foldCodeBase(buffer).suggestionOverlay(isPresented: model.shownBinding, attachmentAnchor: .caret) { Text("SUG") }
            .onKeyPress(.escape) { .ignored }.onDisappear {}
            .frame(width: Pixels(400), height: Pixels(200)).accessibilityIdentifier("code")
    case .disappearThenKey:
        foldCodeBase(buffer).suggestionOverlay(isPresented: model.shownBinding, attachmentAnchor: .caret) { Text("SUG") }
            .onDisappear {}.onKeyPress(.escape) { .ignored }
            .frame(width: Pixels(400), height: Pixels(200)).accessibilityIdentifier("code")
    case .bothAfterFrame:
        foldCodeBase(buffer).suggestionOverlay(isPresented: model.shownBinding, attachmentAnchor: .caret) { Text("SUG") }
            .frame(width: Pixels(400), height: Pixels(200)).accessibilityIdentifier("code")
            .onKeyPress(.escape) { .ignored }.onDisappear {}
    }
}

@MainActor private func foldCosts(_ s: Shape) async throws -> (steady: FoldCounts, keystroke: FoldCounts) {
    let model = FoldModel()
    let buffer = CodeBuffer((0..<60).map { "row\($0) alpha beta gamma\n" }.joined())
    let window = try harnessWindow(size: sz(400, 300)) {
        VStack(spacing: 0) { foldCode(s, model, buffer); Spacer(minLength: 0) }
    }
    defer { withExtendedLifetime(window) {} }
    try await window.runUntilIdle()
    window.click(at: pt(60, 6))
    buffer.selections = [CodeSelection(caret: 0)]
    window.window.setNeedsRedraw()
    try await window.runUntilIdle()
    for _ in 0..<3 { window.window.setNeedsRedraw(); window.tick() }
    let steady = FoldCounts(window.lastFrameWork)
    window.typeText("x")
    return (steady, FoldCounts(window.lastFrameWork))
}

/// The literal a steady frame and a keystroke frame of the Alloy chain cost, every spelling.
private let foldWant = FoldCounts(requests: 7, hits: 0, misses: 0, ineligible: 0)

/// **1** On a `CodeView` with an open suggestion overlay: neither handler, each alone, both in each order, and both
/// after the frame, all cost what the chain with neither does (7 requests; the view is its own retained boundary,
/// so no retained counter moves). Mutation: delete `LifecycleScope._wrap` (the scope then takes the default and
/// the frame starts a second chain): both-before-frame costs 8.
@Test @MainActor func twoHandlersBeforeAFrameCostWhatNeitherCosts() async throws {
    for shape in Shape.allCases {
        let c = try await foldCosts(shape)
        #expect(c.steady == foldWant && c.keystroke == foldWant, "\(shape): steady \(c.steady) | keystroke \(c.keystroke)")
    }
}
