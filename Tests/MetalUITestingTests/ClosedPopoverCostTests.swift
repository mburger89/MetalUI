import Testing
import Foundation
import Observation
import MetalUI
import MetalUIScene
import MetalUITesting

// What a CLOSED popover costs a frame (`MN-AR`, record 340). A closed `PopoverModifier` of any form is not a request:
// each closed case below equals its twin without the modifier, a steady frame and a keystroke frame both. The open
// cases are measured literals (the wrapper counts while it presents).

@Observable @MainActor private final class ClosedModel {
    var shown = false
    var item: Int?
    var shownBinding: Binding<Bool> { Binding(get: { self.shown }, set: { self.shown = $0 }) }
    var itemBinding: Binding<ClosedPick?> { Binding(get: { self.item.map(ClosedPick.init) }, set: { self.item = $0?.id }) }
}

private struct ClosedPick: Identifiable { let id: Int }

private struct Counts: Equatable, CustomStringConvertible {
    var requests = 0, hits = 0, misses = 0, ineligible = 0
    init(_ f: FrameWork) {
        requests = f.elementRequests; hits = f.retainedHits; misses = f.retainedMisses; ineligible = f.retainedIneligible
    }
    init(_ r: Int, _ h: Int, _ m: Int, _ i: Int) { requests = r; hits = h; misses = m; ineligible = i }
    var description: String { "requests \(requests) hits \(hits) misses \(misses) ineligible \(ineligible)" }
}

private struct Bar: Component, @MainActor Equatable {
    nonisolated static func == (a: Bar, b: Bar) -> Bool { true }
    var content: some ElementGroup { Text("bar").frame(width: Pixels(40), height: Pixels(10)) }
}

private enum Shape { case none, plain, plainOpen, code, codeThenModifiers, codeOpen, suggestion, overlayClosed, overlayNone }

@MainActor private func codeBase(_ buffer: CodeBuffer) -> CodeView {
    CodeView(buffer: buffer, decorations: CodeDecorations(buffer: buffer)).font(size: 12).showsLineNumbers(false)
        .codeCaretBlink(.off)
}

@MainActor @ElementBuilder private func tree(_ s: Shape, _ model: ClosedModel, _ buffer: CodeBuffer) -> some ElementGroup {
    switch s {
    case .none:
        Text("hello").frame(width: Pixels(100), height: Pixels(20))
    case .plain:
        Text("hello").popover(isPresented: model.shownBinding) { Text("P") }.frame(width: Pixels(100), height: Pixels(20))
    case .plainOpen:
        Text("hello").popover(isPresented: model.shownBinding) { Text("P") }.frame(width: Pixels(100), height: Pixels(20))
    case .overlayNone:
        Text("hello").frame(width: Pixels(100), height: Pixels(20))
    case .overlayClosed:
        Text("hello").anchoredOverlay(isPresented: model.shownBinding, at: Point(x: Pixels(5), y: Pixels(5))) { Text("O") }
            .frame(width: Pixels(100), height: Pixels(20))
    case .code:
        codeBase(buffer).popover(item: model.itemBinding, attachmentAnchor: .range(0..<4)) { _ in Text("POP") }
    case .suggestion:
        codeBase(buffer).suggestionOverlay(isPresented: model.shownBinding, attachmentAnchor: .caret) { Text("SUG") }
    case .codeThenModifiers:
        codeBase(buffer).popover(item: model.itemBinding, attachmentAnchor: .range(0..<4)) { _ in Text("POP") }
            .frame(width: Pixels(400), height: Pixels(200)).accessibilityIdentifier("code")
    case .codeOpen:
        codeBase(buffer).popover(item: model.itemBinding, attachmentAnchor: .range(0..<4)) { _ in Text("POP") }
            .frame(width: Pixels(400), height: Pixels(200))
    }
}

/// The twin of `s` without the modifier.
@MainActor @ElementBuilder private func twin(_ s: Shape, _ buffer: CodeBuffer) -> some ElementGroup {
    switch s {
    case .code, .suggestion: codeBase(buffer)
    case .codeThenModifiers: codeBase(buffer).frame(width: Pixels(400), height: Pixels(200)).accessibilityIdentifier("code")
    default: Text("hello").frame(width: Pixels(100), height: Pixels(20))
    }
}

@MainActor private func measure(_ s: Shape, withModifier: Bool, open: Bool = false) async throws -> (steady: Counts, keystroke: Counts) {
    let model = ClosedModel()
    let buffer = CodeBuffer((0..<60).map { "row\($0) alpha beta gamma\n" }.joined())
    let isCode: Bool = { switch s { case .code, .suggestion, .codeThenModifiers, .codeOpen: true; default: false } }()
    let window = try harnessWindow(size: sz(400, 300)) {
        VStack(spacing: 0) {
            Bar().equatable()
            if withModifier { tree(s, model, buffer) } else { twin(s, buffer) }
            Spacer(minLength: 0)
        }
    }
    defer { withExtendedLifetime(window) {} }
    try await window.runUntilIdle()
    if isCode {
        window.click(at: pt(60, 26))
        buffer.selections = [CodeSelection(caret: 0)]
    }
    if open { model.shown = true; model.item = 1 }
    window.window.setNeedsRedraw()
    try await window.runUntilIdle()
    for _ in 0..<3 { window.window.setNeedsRedraw(); window.tick() }
    let steady = Counts(window.lastFrameWork)
    if isCode { window.typeText("x") } else { window.window.setNeedsRedraw(); window.tick() }
    return (steady, Counts(window.lastFrameWork))
}

@MainActor private func expectClosedEqualsTwin(_ s: Shape) async throws {
    let with = try await measure(s, withModifier: true)
    let without = try await measure(s, withModifier: false)
    #expect(with.steady == without.steady && with.keystroke == without.keystroke,
            "closed steady \(with.steady) vs \(without.steady) | keystroke \(with.keystroke) vs \(without.keystroke)")
}

@Test @MainActor func aClosedPlainPopoverCostsWhatNoPopoverCosts() async throws { try await expectClosedEqualsTwin(.plain) }
@Test @MainActor func aClosedAnchoredOverlayCostsWhatNoOverlayCosts() async throws { try await expectClosedEqualsTwin(.overlayClosed) }
@Test @MainActor func aClosedTextAnchoredPopoverCostsWhatNoPopoverCosts() async throws { try await expectClosedEqualsTwin(.code) }
@Test @MainActor func aClosedSuggestionOverlayCostsWhatNoOverlayCosts() async throws { try await expectClosedEqualsTwin(.suggestion) }
@Test @MainActor func aClosedPopoverFollowedByModifiersCostsWhatNoPopoverCosts() async throws { try await expectClosedEqualsTwin(.codeThenModifiers) }

/// Literals of the closed cases (the twins' own: a `Text` frame 3 requests, a bare `CodeView` 2, with `.frame` and
/// an identifier 3; the bar is 1 of them), so the equality above cannot hold at a shifted baseline.
@Test @MainActor func theClosedCasesCostTheirMeasuredLiterals() async throws {
    let cases: [(Shape, Int)] = [(.plain, 3), (.overlayClosed, 3), (.code, 2), (.suggestion, 2), (.codeThenModifiers, 3)]
    for (s, requests) in cases {
        let c = try await measure(s, withModifier: true)
        let want = Counts(requests, 1, 0, 0)
        #expect(c.steady == want && c.keystroke == want, "\(s): steady \(c.steady) | keystroke \(c.keystroke)")
    }
}

/// Open cases keep their counts (wrapper 1 + chrome and content): measured on master, unchanged.
@Test @MainActor func theOpenCasesCostWhatTheyDid() async throws {
    for s in [Shape.plainOpen, .codeOpen] {
        let c = try await measure(s, withModifier: true, open: true)
        let want = Counts(7, 1, 0, 0)
        #expect(c.steady == want && c.keystroke == want, "\(s): steady \(c.steady) | keystroke \(c.keystroke)")
    }
}

/// Opening, closing and opening again never remounts the `CodeView`: its scroll offset and selection survive.
@Test @MainActor func openingAndClosingAPopoverKeepsTheCodeViewsState() async throws {
    let model = ClosedModel()
    let buffer = CodeBuffer((0..<60).map { "row\($0) alpha beta gamma\n" }.joined())
    let geometry = CodeViewGeometry()
    let window = try harnessWindow(size: sz(400, 300)) {
        codeBase(buffer).geometry(geometry).popover(item: model.itemBinding, attachmentAnchor: .range(0..<4)) { _ in Text("POP") }
            .frame(width: Pixels(400), height: Pixels(200))
    }
    defer { withExtendedLifetime(window) {} }
    try await window.runUntilIdle()
    let pitch = codePitch(scale: 1)
    window.scroll(at: pt(100, 100), byDeltaX: 0, deltaY: -pitch * 10)
    window.tick(); window.tick()
    let selection = CodeSelection(caret: buffer.snapshot().lineRange(12).lowerBound + 2)
    buffer.selections = [selection]
    window.tick()
    let first = try #require(geometry.visibleRows).lowerBound
    #expect(first == 10)
    for round in 0..<2 {
        model.item = 1
        window.window.setNeedsRedraw(); try await window.runUntilIdle()
        #expect(geometry.visibleRows?.lowerBound == first && buffer.primarySelection == selection, "open \(round)")
        model.item = nil
        window.window.setNeedsRedraw(); try await window.runUntilIdle()
        #expect(geometry.visibleRows?.lowerBound == first && buffer.primarySelection == selection, "closed \(round)")
    }
}
