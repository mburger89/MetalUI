import Testing
@testable import MetalUI
@testable import MetalUIText

// Plan task 11 part 1, lane 3 (spec rows 3.19–3.21; rulings TE-G item 4,
// TE-K, TE-L): a `Text` reports `round(ascent)` and its last drawn line's
// baseline, so lane 2's baseline alignment places real text.

@MainActor
private func measured(_ string: String, size: Double = 13, width: Double? = 200,
                      limit: TextLineLimit = TextLineLimit()) -> (LayoutMeasurement, TextFontMetrics) {
    let system = teSystem()
    let key = system.resolveFont(family: nil, size: size)
    let style = ResolvedTextStyle(descriptor: FontDescriptor(size: size), foreground: .textPrimary,
                                  lineLimit: limit, truncation: .tail, alignment: .leading)
    return (proposalTextMeasurement(string, font: key, system: system,
                                    proposal: ProposedSize(width: width, height: nil), style: style),
            system.fontMetrics(key))
}

/// **3.19.** B1: the first baseline is `round(ascent)` — 13 for SF 13
/// (12.568), 25 at 26 (25.137), 11 at 11 (10.635), SwiftUI's numbers exactly —
/// and the last `first + (lines − 1) × lineHeight` with MetalUI's line height:
/// "Hg\nHg" 13 and 29; a wrapped "Hg Hg Hg" at 30 its third line; under a
/// limit the last KEPT line; under `reservesSpace` the actual last line.
///
/// Mutation **M3r**: the ascent unrounded.
@MainActor
@Test func aTextReportsRoundAscentAndItsLastLinesBaseline() throws {
    for (size, first) in [(13.0, 13.0), (26, 25), (11, 11)] {
        let (m, metrics) = measured("Hg", size: size)
        try #require(metrics.ascent != metrics.ascent.rounded(), "\(size): the ascent is fractional")
        #expect(m.firstBaseline == first, "\(size): first \(String(describing: m.firstBaseline))")
        #expect(m.lastBaseline == first, "\(size): one line")
    }
    let (two, metrics) = measured("Hg\nHg")
    let lh = metrics.lineHeight
    #expect(two.firstBaseline == 13 && two.lastBaseline == 13 + lh, "B1 two lines")
    let (wrapped, _) = measured("Hg Hg Hg", width: 30)
    try #require(wrapped.size.height == 3 * lh, "three lines at 30")
    #expect(wrapped.lastBaseline == 13 + 2 * lh, "the wrapped text's third line")
    let (limited, _) = measured(tePara, width: 100, limit: TextLineLimit(min: nil, max: 2))
    #expect(limited.lastBaseline == 13 + lh, "a limit: the last kept line")
    let (reserved, _) = measured("Hi", limit: TextLineLimit(min: 3, max: 3))
    #expect(reserved.size.height == 3 * lh && reserved.lastBaseline == 13, "reservesSpace: the actual last line")
}

/// **3.20.** B2's tree with real `ProposalText`s — 13 pt "Hg", 26 pt "Hg", a
/// two-line 13 pt "Hg\nHg" and a 10 × 10 block — in an `HStack(spacing: 0)`.
/// First-aligned it is 44 tall with offsets 12, 0, 12, 15: SwiftUI's answer
/// exactly (the 26 pt line's height does not enter it). Last-aligned the
/// offsets come from MetalUI's own 26 pt line height (divergence 86): the
/// guides 13, 25, 13 + 16, 10, and the stack `max(guide) + max(below)`.
///
/// Mutation **M3s**: `Text` reports no baseline.
@MainActor
@Test func anHStackAlignsRealTextsByTheirBaselines() throws {
    let system = teSystem()
    let lh13 = system.fontMetrics(system.resolveFont(family: nil, size: 13)).lineHeight
    let lh26 = system.fontMetrics(system.resolveFont(family: nil, size: 26)).lineHeight
    try #require(lh13 == 16)
    func placed(_ alignment: VerticalAlignment) throws -> (stack: Bounds<Pixels>, children: [Bounds<Pixels>]) {
        let frame = try controlRender(controlRoot {
            HStack(alignment: alignment, spacing: Pixels(0)) {
                ProposalText("Hg")
                ProposalText("Hg").font(size: 26)
                ProposalText("Hg\nHg")
                Rectangle(width: Pixels(10), height: Pixels(10), color: .accent)
            }
        })
        let stack = try controlBounds(frame, controlID([0, 0]))
        let children = try (0..<4).map { try controlBounds(frame, controlID([0, 0, $0])) }
        return (stack, children)
    }
    let first = try placed(.firstTextBaseline)
    #expect(first.stack.size.height.value == 44, "B2 first: 44 tall")
    #expect(first.children.map { $0.origin.y.value - first.stack.origin.y.value } == [12, 0, 12, 15],
            "B2 first offsets")

    let guides: [Double] = [13, 25, 13 + lh13, 10]
    let heights: [Double] = [lh13, lh26, 2 * lh13, 10]
    let top = guides.max()!
    let below = zip(heights, guides).map { $0 - $1 }.max()!
    let last = try placed(.lastTextBaseline)
    #expect(Double(last.stack.size.height.value) == top + below, "B2 last: \(top) + \(below)")
    #expect(last.children.map { Double($0.origin.y.value - last.stack.origin.y.value) } == guides.map { top - $0 },
            "B2 last offsets")
    let centre = try placed(.center)
    #expect(centre.children.map { $0.origin.y.value } != first.children.map { $0.origin.y.value },
            "the control: centre alignment places differently")
}

/// **3.21.** A legacy `Row { Text 13; Text 26 }.alignItems(.baseline)` aligns
/// its real texts by their first baselines (TE-L): the 13 pt text sits 12
/// below the 26 pt one, and the row is `25 + max(below)` tall.
///
/// Mutation **M3s** reddens it too.
@MainActor
@Test func aLegacyBaselineRowAlignsRealTexts() throws {
    let system = teSystem()
    let lh13 = system.fontMetrics(system.resolveFont(family: nil, size: 13)).lineHeight
    let lh26 = system.fontMetrics(system.resolveFont(family: nil, size: 26)).lineHeight
    let frame = try controlRender(controlRoot {
        Row {
            Text("Hg")
            Text("Hg").font(size: 26)
        }.alignItems(.baseline)
    })
    let row = try controlBounds(frame, controlID([0, 0]))
    let small = try controlBounds(frame, controlID([0, 0, 0]))
    let large = try controlBounds(frame, controlID([0, 0, 1]))
    #expect(small.origin.y.value - row.origin.y.value == 12)
    #expect(large.origin.y.value == row.origin.y.value)
    #expect(Double(row.size.height.value) == 25 + max(lh13 - 13, lh26 - 25))
}
