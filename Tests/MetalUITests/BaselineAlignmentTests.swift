import Testing
import MetalUICore
import MetalUILayout
@testable import MetalUI

// Plan task 11 part 1, lane 2 (spec rows 2.7, 2.9 and 2.11; rulings TE-K,
// TE-L): the element halves of baseline alignment. `HStack(alignment:
// .firstTextBaseline/.lastTextBaseline)` reaches the kernel's baseline
// alignment, and a legacy `Row`'s `alignItems(.baseline)` lowers to it (a
// `Column`'s to its start edge). The children are synthetic leaves reporting
// B2's heights and baselines (`docs/probes/swiftui-text-semantics.swift`) at
// whole-point widths, so every rect is B2's vertical numbers exactly; a real
// `Text` reports baselines only from lane 3.

@MainActor
private final class BaselineProbe {
    var bounds: [String: Bounds<Pixels>] = [:]

    func leaf(_ name: String, _ width: Double, _ height: Double, first: Double? = nil,
              last: Double? = nil) -> BaselineLeaf {
        BaselineLeaf(name: name, probe: self, width: width, height: height, first: first, last: last ?? first)
    }

    /// B2's four children: the 13 pt text, the 26 pt one, the two-line one, the colour.
    var b2: (BaselineLeaf, BaselineLeaf, BaselineLeaf, BaselineLeaf) {
        (leaf("13", 18, 16, first: 13), leaf("26", 34, 30, first: 25), leaf("2line", 18, 32, first: 13, last: 29),
         leaf("colour", 10, 10))
    }

    func rects(_ names: [String]) -> [Bounds<Pixels>?] { names.map { bounds[$0] } }
}

/// A fixed-size proposal leaf reporting the given baselines and recording its
/// prepaint bounds by name.
private struct BaselineLeaf: ProposalElement {
    let name: String
    let probe: BaselineProbe
    let width: Double, height: Double
    let first: Double?, last: Double?

    func requestProposalLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (ProposalNodeID, Void) {
        let (w, h, f, l) = (width, height, first, last)
        return (pass.requestNativeLeaf { _ in
            LayoutMeasurement(size: SizeD(width: w, height: h), firstBaseline: f, lastBaseline: l)
        }, ())
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, pass: inout PrepaintPass) {
        probe.bounds[name] = bounds
    }

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, prepaint: inout Void,
               pass: inout PaintPass) {}
}

private func b(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> Bounds<Pixels> {
    Bounds(origin: Point(x: Pixels(x), y: Pixels(y)), size: Size(width: Pixels(w), height: Pixels(h)))
}

private let b2Names = ["13", "26", "2line", "colour"]

/// **2.7.** `HStack(alignment: .firstTextBaseline)` and `.lastTextBaseline`
/// (spacing 0) place B2's children as the kernel's 2.2 and 2.3 do: y 12, 0,
/// 12, 15 and 16, 4, 0, 19 — and `.top`, the control, 0 throughout.
@MainActor
@Test func hStackTextBaselineCasesReachTheKernel() throws {
    for (alignment, ys) in [(VerticalAlignment.firstTextBaseline, [12, 0, 12, 15] as [Float]),
                            (.lastTextBaseline, [16, 4, 0, 19]), (.top, [0, 0, 0, 0])] {
        let probe = BaselineProbe()
        let (a, c, d, e) = probe.b2
        let report = LayoutDifferential.report(width: 200, height: 100) {
            HStack(alignment: alignment, spacing: Pixels(0)) { a; c; d; e }
        }
        try #require(report.unlowerable.isEmpty, "\(report.unlowerable)")
        #expect(probe.rects(b2Names) == [b(0, ys[0], 18, 16), b(18, ys[1], 34, 30), b(52, ys[2], 18, 32),
                                         b(70, ys[3], 10, 10)], "\(alignment)")
    }
}

/// **2.9.** A legacy `Row`'s `alignItems(.baseline)` lowers to first-baseline
/// alignment (TE-L): B2's children at y 12, 0, 12, 15, nothing reported. A
/// `Column`'s lowers as `flexStart` — its cross axis is horizontal, where a
/// baseline falls back to the start edge — so a 18- and a 34-wide child both
/// sit at x 0, where the default `Column` centres the narrow one at 8.
@MainActor
@Test func aLegacyBaselineRowLowersToFirstTextBaselineAndAColumnToItsStart() throws {
    let probe = BaselineProbe()
    let (a, c, d, e) = probe.b2
    let row = LayoutDifferential.report(width: 200, height: 100) {
        Row { a; c; d; e }.alignItems(.baseline)
    }
    try #require(row.unlowerable.isEmpty, "\(row.unlowerable)")
    #expect(probe.rects(b2Names) == [b(0, 12, 18, 16), b(18, 0, 34, 30), b(52, 12, 18, 32), b(70, 15, 10, 10)])

    for (baseline, narrowX) in [(true, Float(0)), (false, 8)] {
        let columnProbe = BaselineProbe()
        let narrow = columnProbe.leaf("narrow", 18, 16, first: 13)
        let wide = columnProbe.leaf("wide", 34, 30, first: 25)
        let column = LayoutDifferential.report(width: 200, height: 100) {
            if baseline { Column { narrow; wide }.alignItems(.baseline) } else { Column { narrow; wide } }
        }
        try #require(column.unlowerable.isEmpty, "\(column.unlowerable)")
        #expect(columnProbe.rects(["narrow", "wide"]) == [b(narrowX, 0, 18, 16), b(0, 16, 34, 30)],
                "baseline \(baseline)")
    }
}

/// **2.11.** A child's `alignSelf(.baseline)` is consumed without a report
/// under a baseline row — the child aligns so already; a text-less box's guide
/// is its height, so a 10-tall box sits with its bottom on the 13 pt text's
/// baseline (y 3) — and everywhere else is a permanent refusal by name
/// (`box.alignSelf.baseline`, owner `nil`; TE-L).
@MainActor
@Test func anAlignSelfBaselineIsConsumedUnderABaselineRowAndRefusedByNameElsewhere() throws {
    let probe = BaselineProbe()
    let text = probe.leaf("13", 18, 16, first: 13)
    let consumed = LayoutDifferential.report(width: 200, height: 100) {
        Row { text; Box().cssWidth(Pixels(10)).cssHeight(Pixels(10)).alignSelf(.baseline) }.alignItems(.baseline)
    }
    #expect(consumed.unlowerable.isEmpty, "\(consumed.unlowerable)")
    #expect(probe.bounds["13"] == b(0, 0, 18, 16))
    #expect(consumed.bounds.values.contains(b(18, 3, 10, 10)), "\(consumed.bounds.values)")

    let refused = LayoutDifferential.report(width: 200, height: 100) {
        Row { text; Box().cssWidth(Pixels(10)).cssHeight(Pixels(10)).alignSelf(.baseline) }
    }
    let entry = UnlowerableField(site: .box, field: "alignSelf.baseline")
    #expect(refused.unlowerable == [entry], "\(refused.unlowerable)")
    #expect(entry.owner == nil)
}
