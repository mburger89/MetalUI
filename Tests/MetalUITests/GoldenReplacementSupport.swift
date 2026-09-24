import Foundation
import Testing
import MetalUICore
@testable import MetalUILayout
@testable import MetalUI

// Plan task 7, stage 7a (`docs/superpowers/specs/2026-09-23-engine-stage-7a-design.md`
// §4 and §6; rulings LR-DS, LR-DW): the shared harness of the tests that replace
// the retired WebKit goldens. Each **R** golden (record §48 §4) is replaced by one
// arm that builds the golden's own `Box(style:)` tree — the fixture's CSS
// transcribed field for field, every golden `data-id` on `.id(_:)` as the
// outermost modifier — renders it under the **proposal** authority inside a
// `DifferentialRoot` and asserts the golden's `rounded` boxes (record §48 §5.1)
// literally, off `Frame.elementBounds`.
//
// **Internal on purpose**: lane 2 (`GoldenReplacementStackTests.swift`) reuses
// `goldenArm` rather than copying it — a copy of a pinned harness is unpinned
// (CLAUDE.md, practices). The helper's own decisions are mutation sites: MH (spec
// §6, lane 1) replaces the missing-id `try #require` with a `continue` and shows
// an arm naming an id its tree never declares going green.

/// One expected box of a retired golden, by its `data-id`.
struct GoldenBox: CustomStringConvertible {
    let id: String
    let x, y, width, height: Float

    init(_ id: String, _ x: Float, _ y: Float, _ width: Float, _ height: Float) {
        self.id = id
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    var bounds: Bounds<Pixels> {
        Bounds(origin: Point(x: Pixels(x), y: Pixels(y)),
               size: Size(width: Pixels(width), height: Pixels(height)))
    }

    var description: String { "\(id):\(x),\(y),\(width)x\(height)" }

    /// Parses record §48 §5.1's spelling, `"root:0,0,300x50 x:0,0,60x20 …"`, so an
    /// arm's literals read character for character as the record's row. A malformed
    /// entry traps (a typo in a literal must not become a silently skipped box).
    static func list(_ spelled: String) -> [GoldenBox] {
        spelled.split(separator: " ").map { entry in
            let parts = entry.split(separator: ":")
            precondition(parts.count == 2, "malformed golden box \(entry)")
            let numbers = parts[1].split(separator: ",")
            precondition(numbers.count == 3, "malformed golden box \(entry)")
            let size = numbers[2].split(separator: "x")
            precondition(size.count == 2, "malformed golden box \(entry)")
            guard let x = Float(numbers[0]), let y = Float(numbers[1]),
                  let w = Float(size[0]), let h = Float(size[1]) else {
                preconditionFailure("malformed golden box \(entry)")
            }
            return GoldenBox(String(parts[0]), x, y, w, h)
        }
    }
}

/// The name an element was given with `.id(_:)`, or nil for a positional one.
func goldenName(_ id: GlobalElementID) -> String? {
    if case .named(let name) = id.component { return name.name }
    return nil
}

/// Every recorded element named `name`, with its bounds. A golden's `data-id`s are
/// unique in its fixture, so `goldenArm` requires exactly one.
@MainActor
func bounds(named name: String, in frame: Frame) -> [Bounds<Pixels>] {
    frame.elementBounds.compactMap { goldenName($0.key) == name ? $0.value : nil }
}

/// Renders `make()` under the PROPOSAL authority inside a `window`-sized
/// `DifferentialRoot` and asserts, for the retired golden `golden`:
/// the frame reported nothing (`try #require`, message names the golden and the
/// fields), each expected id names exactly ONE element (`try #require`), and that
/// element's `Frame.elementBounds` rect equals the box exactly.
///
/// `boxes` must be non-empty (`try #require`, shape 13): an arm with no boxes
/// would assert nothing.
@MainActor
func goldenArm<C: ElementGroup>(_ golden: String, window: (Float, Float) = (800, 600),
                                _ boxes: [GoldenBox],
                                sourceLocation: SourceLocation = #_sourceLocation,
                                @ElementBuilder _ make: @MainActor () -> C) throws {
    try checkGoldenArm(golden, window: window, boxes, sourceLocation: sourceLocation, make)
}

/// `goldenArm` with the boxes spelled as record §48 §5.1 spells them
/// (`GoldenBox.list`).
@MainActor
func goldenArm<C: ElementGroup>(_ golden: String, window: (Float, Float) = (800, 600),
                                _ spelled: String,
                                sourceLocation: SourceLocation = #_sourceLocation,
                                @ElementBuilder _ make: @MainActor () -> C) throws {
    try checkGoldenArm(golden, window: window, GoldenBox.list(spelled), sourceLocation: sourceLocation, make)
}

@MainActor
private func checkGoldenArm<C: ElementGroup>(_ golden: String, window: (Float, Float),
                                        _ boxes: [GoldenBox],
                                        sourceLocation: SourceLocation,
                                        _ make: @MainActor () -> C) throws {
    try #require(!boxes.isEmpty, "\(golden): an arm with no expected boxes asserts nothing",
                 sourceLocation: sourceLocation)
    let frame = LayoutDifferential.render(authority: .proposal,
                                          width: window.0, height: window.1, make)
    let reported = frame.unlowerableFields.map(\.description)
    try #require(reported.isEmpty,
                 "\(golden): the proposal authority reported \(reported)",
                 sourceLocation: sourceLocation)
    for box in boxes {
        let matches = bounds(named: box.id, in: frame)
        try #require(matches.count == 1,
                     "\(golden): id \"\(box.id)\" names \(matches.count) elements, not one",
                     sourceLocation: sourceLocation)
        #expect(matches[0] == box.bounds,
                "\(golden): \(box.id) is \(matches[0]), the golden reads \(box)",
                sourceLocation: sourceLocation)
    }
}

/// The tree vocabulary of the transcription instrument
/// (`docs/probes/stage-7a-transcription-instrument.patch`), `g`-prefixed because
/// several test files declare a private `px`. Free functions, not members of a
/// suite type: a `@Suite` (or any type holding `@Test`s) adds a suite to the run's
/// summary line, which the stage's exit criterion reads as "in 3 suites".
func gPx(_ v: Float) -> MetalUICore.Dimension { .length(.pixels(Pixels(v))) }
func gPl(_ v: Float) -> Length { .pixels(Pixels(v)) }

/// `width`/`height`: a px size on that axis, `auto` for nil.
func gSize(_ s: inout Style, _ width: Float?, _ height: Float?) {
    s.size = Size(width: width.map { gPx($0) } ?? .auto, height: height.map { gPx($0) } ?? .auto)
}

/// The `flex` shorthand split: grow, shrink, basis.
func gFlex(_ s: inout Style, _ grow: Float, _ shrink: Float, _ basis: MetalUICore.Dimension) {
    s.flexGrow = grow
    s.flexShrink = shrink
    s.flexBasis = basis
}

/// A margin in CSS order: top, right, bottom, left.
func gMargin(_ t: Float, _ r: Float, _ b: Float, _ l: Float) -> Edges<MetalUICore.Dimension> {
    Edges(top: gPx(t), right: gPx(r), bottom: gPx(b), left: gPx(l))
}

/// A padding or border in CSS order: top, right, bottom, left.
func gEdges(_ t: Float, _ r: Float, _ b: Float, _ l: Float) -> Edges<Length> {
    Edges(top: gPl(t), right: gPl(r), bottom: gPl(b), left: gPl(l))
}

func gStyle(_ f: (inout Style) -> Void) -> Style {
    var s = Style()
    f(&s)
    return s
}

/// A childless box named `id`.
@MainActor
func gLeaf(_ id: String, _ f: (inout Style) -> Void) -> Box<EmptyGroup> {
    Box(style: gStyle(f)).id(id)
}

/// A box named `id` over `content`.
@MainActor
func gBox<G: ElementGroup>(_ id: String, _ f: (inout Style) -> Void,
                           @ElementBuilder _ content: () -> G) -> Box<G> {
    Box(style: gStyle(f), content: content()).id(id)
}
