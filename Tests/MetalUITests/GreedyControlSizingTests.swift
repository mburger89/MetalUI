import Foundation
import Testing
import MetalUICore
import MetalUILayout
@testable import MetalUI

// Ruling `PE-D` (`docs/superpowers/2026-10-06-proposal-controls-decisions.md`;
// spec `2026-10-06-proposal-controls-design.md` §6.1 tests 1.9 and 1.23, moved
// to lane 2 by `PE-O`): the three greedy controls — `TextField`, `TextEditor`,
// `Slider` — answer an **infinite** proposal with infinity, as SwiftUI's do
// (probe `docs/probes/swiftui-controls-in-stacks.swift`, arms FL3/FL4 `inf ->
// infx24`, FL5 `infxinf`, FL6 `infx16`), and keep their ideal at `nil`.
//
// Why it matters: a stack orders its children by their answer at an infinite
// proposal (`CN-B`). A control answering its ideal there is served first, as
// if it hugged, and takes only its share of the row (`FM0`'s slider: 180
// where SwiftUI's is 321).

/// One child measured at the probe's proposals, recorded by `Ask`.
private final class Answers: @unchecked Sendable {
    var sizes: [String: SizeD] = [:]
}

/// The probe's proposals, by the names spec §1.3 uses.
private let probeProposals: [(String, ProposedSize)] = [
    ("zero", ProposedSize(width: 0, height: 0)),
    ("ideal", ProposedSize(width: nil, height: nil)),
    ("inf", ProposedSize(width: .infinity, height: .infinity)),
    ("infWidth", ProposedSize(width: .infinity, height: nil)),
    ("w200", ProposedSize(width: 200, height: nil)),
    ("h200", ProposedSize(width: nil, height: 200)),
    ("w50", ProposedSize(width: 50, height: nil)),
]

/// A recording layout: measures its one subview at every probe proposal, then
/// answers and places it at its own proposal.
private struct Ask: ProposalLayout {
    let answers: Answers

    func sizeThatFits(proposal: ProposedSize, subviews: MeasurementSubviews) -> LayoutMeasurement {
        for (name, offer) in probeProposals {
            answers.sizes[name] = subviews[0].sizeThatFits(offer).size
        }
        return subviews[0].sizeThatFits(proposal)
    }

    func placeSubviews(in bounds: LayoutRect, proposal: ProposedSize, subviews: PlacementSubviews) {
        subviews[0].place(at: Point(x: bounds.x, y: bounds.y), proposal: proposal)
    }
}

/// A legacy element where a proposal container expects proposal content — a
/// test-local copy of `LoweringItemTests`' `LegacyUnderProposal` (the
/// semantics `PE-C`'s `LegacyContent` makes public in lane 1), so this file
/// needs no builder from lane 1.
@MainActor
private struct UnderProposal<Content: ElementGroup>: ProposalElementGroup {
    var content: Content

    init(_ content: Content) { self.content = content }

    mutating func requestGroupLayout(under parent: GlobalElementID?, at cursor: inout Int,
                                     pass: inout LayoutPass) -> ([LayoutNodeID], Content.GroupLayout) {
        content.requestGroupLayout(under: parent, at: &cursor, pass: &pass)
    }

    mutating func requestProposalGroupLayout(under parent: GlobalElementID?, at cursor: inout Int,
                                             pass: inout LayoutPass) -> ([ProposalNodeID], Content.GroupLayout) {
        let (nodes, layout) = content.requestGroupLayout(under: parent, at: &cursor, pass: &pass)
        return (nodes.map { ProposalNodeID($0) }, layout)
    }

    mutating func prepaintGroup(layout: inout Content.GroupLayout,
                                pass: inout PrepaintPass) -> Content.GroupPrepaint {
        content.prepaintGroup(layout: &layout, pass: &pass)
    }

    mutating func paintGroup(layout: inout Content.GroupLayout, prepaint: inout Content.GroupPrepaint,
                             pass: inout PaintPass) {
        content.paintGroup(layout: &layout, prepaint: &prepaint, pass: &pass)
    }
}

/// `control`'s answers to the probe's proposals inside a proposal container,
/// with the frame's report required empty.
@MainActor
private func answers<E: ElementGroup>(_ control: E) throws -> [String: SizeD] {
    let answers = Answers()
    let frame = LayoutDifferential.render(width: 400, height: 300) {
        ProposalLayoutContainer(Ask(answers: answers)) { UnderProposal(control) }
    }
    try #require(frame.unlowerableFields.isEmpty, "the fixture reported \(frame.unlowerableFields)")
    try #require(answers.sizes.count == probeProposals.count, "Ask measured \(answers.sizes.keys.sorted())")
    return answers.sizes
}

private func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.01 }

/// **1.9** (`PE-D`). `TextField` and `Slider` at ∞ wide answer ∞ wide (FL3,
/// FL6 `inf -> infx…`), `TextEditor` at ∞×∞ answers ∞×∞ (FL5); at `nil` each
/// keeps its ideal (MetalUI's own: "Hello" plus the 1-point caret, 31.95 for
/// the editor and, with the bordered chrome's 12 since `MD-C`/`MD-D`, 43.95 × 24
/// for the field; the slider's 30 — divergence 131), and a finite offer is still taken whole.
///
/// Red at `e54c3f6`: the infinite arms read the ideal (31.95, 30, 31.95×16).
/// Mutations M1.9a/b/c (each control's change reverted alone) redden their
/// own arm.
@Test @MainActor func theGreedyControlsAnswerAnInfiniteProposalWithInfinity() throws {
    // The bordered default since port gaps, medium (`MD-C` item 2, a size): the
    // ideal + 12 and one line + 8 (`MD-D`); the infinite answer is unchanged.
    let field = try answers(TextField("", text: "Hello", onChange: { _ in }))
    let ideal = try #require(field["ideal"])
    #expect(near(ideal.width, 43.95) && ideal.height == 24,
            "TextField ideal (\"Hello\" + the caret + the chrome's 12): \(ideal)")
    #expect(field["infWidth"]!.width == .infinity && field["infWidth"]!.height == 24,
            "M1.9a — TextField at ∞×nil: \(field["infWidth"]!)")
    #expect(field["inf"]!.width == .infinity && field["inf"]!.height == 24,
            "TextField at ∞×∞ (one line and the chrome tall): \(field["inf"]!)")
    #expect(field["w200"]! == SizeD(width: 200, height: 24), "TextField w200: \(field["w200"]!)")

    let slider = try answers(Slider(value: .constant(0.5)))
    #expect(slider["ideal"]! == SizeD(width: 30, height: 16), "Slider ideal: \(slider["ideal"]!)")
    #expect(slider["infWidth"]! == SizeD(width: .infinity, height: 16),
            "M1.9b — Slider at ∞×nil: \(slider["infWidth"]!)")
    #expect(slider["w200"]! == SizeD(width: 200, height: 16), "Slider w200: \(slider["w200"]!)")

    let editor = try answers(TextEditor(text: "Hello", onChange: { _ in }))
    let editorIdeal = try #require(editor["ideal"])
    #expect(near(editorIdeal.width, 31.95) && editorIdeal.height == 16, "TextEditor ideal: \(editorIdeal)")
    #expect(editor["inf"]!.width == .infinity && editor["inf"]!.height == .infinity,
            "M1.9c — TextEditor at ∞×∞: \(editor["inf"]!)")
    #expect(editor["w200"]! == SizeD(width: 200, height: 16), "TextEditor w200: \(editor["w200"]!)")
    #expect(near(editor["h200"]!.width, 31.95) && editor["h200"]!.height == 200,
            "TextEditor h200: \(editor["h200"]!)")
}

/// **1.23** (`PE-D`'s named exception: a legacy `Row` is the same native
/// stack, so it too serves a greedy control last). `Row(gap: 8) {
/// Text("Speed"); Slider }` framed 368 wide — `FM0`'s row c — centred in a
/// 400-wide root (`CN-J`), so the row spans x 16…384: the label hugs its text
/// at the leading edge and the slider takes the rest, 368 − label − 8
/// (`FM0`: SwiftUI's slider 321 beside a 39-wide label).
///
/// Red at `e54c3f6`: the slider answers 30 at ∞, is served first and takes
/// half the row (180), and the pair is centred (the label at x 87). M1.5's
/// mutation (`Slider`'s `PE-D` reverted) reddens it.
@Test @MainActor func aLegacyRowServesItsSliderLast() throws {
    let frame = try controlRender(
        Row(gap: Pixels(8)) {
            Text("Speed")
            Slider(value: .constant(0.5))
        }.frame(width: 368, height: 16), width: 400, height: 100)
    // `.frame` is one layer: the row takes `[0]`'s inner level (`MC-C`).
    let label = try controlBounds(frame, controlID([0, 0, 0]))
    let slider = try controlBounds(frame, controlID([0, 0, 1]))
    #expect(label.origin.x.value == 16 && (38...40).contains(label.size.width.value),
            "the label hugs its text at the row's leading edge: \(label)")
    #expect(slider.origin.x.value == label.origin.x.value + label.size.width.value + 8
                && slider.origin.x.value + slider.size.width.value == 384,
            "the slider takes the rest, to the row's trailing edge: \(slider)")
    #expect((320...322).contains(slider.size.width.value), "368 − label − 8: \(slider)")
}
