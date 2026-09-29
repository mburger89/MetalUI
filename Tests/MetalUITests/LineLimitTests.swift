import Testing
@testable import MetalUI
@testable import MetalUIText

// Plan task 11 part 1, lane 3 (spec rows 3.8, 3.10, 3.13, 3.23; rulings TE-H,
// TE-R). Line heights and widths come from the frame's text system (its
// `fontMetrics` and `measure` under the same options), never from SwiftUI's
// half-point heights (divergence 86).

/// The default font's line height: 16 at 13 pt, where SwiftUI agrees (X13).
@MainActor
func teLineHeight(_ size: Double = 13) -> Float {
    let system = teSystem()
    return Float(system.fontMetrics(system.resolveFont(family: nil, size: size)).lineHeight)
}

/// The paragraph's natural line count at `width` in the default font.
@MainActor
private func naturalLines(_ string: String = tePara, width: Double) -> Int {
    let system = teSystem()
    let key = system.resolveFont(family: nil, size: 13)
    return Int((system.measure(string, font: key, wrappingAt: width).totalHeight / Double(teLineHeight())).rounded())
}

/// **3.8.** `lineLimit(n)` caps the lines and answers the widest KEPT line
/// (L1's shape: 1, 2, 3, `nil`; 0 and −1 act as 1), through the environment
/// with the nearest writer winning (L6b: `lineLimit(3)` inside `lineLimit(1)`
/// draws three).
///
/// Mutation **M3h**: the limit not passed to the seam.
@MainActor
@Test func aLineLimitCapsLinesAndAnswersTheWidestKeptLine() throws {
    let lh = teLineHeight()
    let natural = naturalLines(width: 100)
    try #require(natural >= 5, "the paragraph must wrap to several lines at 100 (\(natural))")
    let cases: [(Int?, Int)] = [(1, 1), (2, 2), (3, 3), (nil, natural), (0, 1), (-1, 1)]
    for (limit, lines) in cases {
        let b = try teBounds([0, 0, 0]) {
            Text(tePara).lineLimit(limit).frame(width: Pixels(100), alignment: .leading)
        }
        let options = TextLayoutOptions(maxLines: limit.map { max($0, 1) })
        let want = teExpectedSize(tePara, FontDescriptor(size: 13), width: 100, options: options)
        #expect(b.size.height.value == Float(lines) * lh, "limit \(String(describing: limit)): height")
        // The text sits at x = 0 inside a leading-aligned 100-wide frame, so
        // its rounded width is its answer's.
        #expect(b.size.width.value == want.width, "limit \(String(describing: limit)): the widest kept line")
    }
    let one = try teBounds([0, 0, 0, 0]) {
        Column { Text(tePara).lineLimit(3).frame(width: Pixels(100)) }.lineLimit(1)
    }
    #expect(one.size.height.value == 3 * lh, "L6b: the nearest writer")
    let env = try teBounds([0, 0, 0, 0]) { Column { Text(tePara).frame(width: Pixels(100)) }.lineLimit(2) }
    #expect(env.size.height.value == 2 * lh, "L6: a container's limit reaches the text")
}

/// **3.10.** `reservesSpace` and a range's lower bound pad the height and keep
/// the width and the last baseline (L2, L3): "Hi" under `lineLimit(3,
/// reservesSpace: true)` is three lines tall and one wide, its last baseline
/// its first; `2...3` pads "Hi" to two and lets the paragraph take three;
/// `...2` caps it at two; `3...` pads "Hi" to three. An empty string reserves
/// nothing (X10).
///
/// Mutation **M3j**: the lower bound ignored.
@MainActor
@Test func reservesSpaceAndARangesLowerBoundPadTheHeight() throws {
    let lh = teLineHeight()
    let hi = teExpectedSize("Hi", FontDescriptor(size: 13))
    func text(_ make: () -> some ElementGroup) throws -> Bounds<Pixels> {
        try teBounds([0, 0, 0]) { make().frame(width: Pixels(100), alignment: .leading) }
    }
    let reserved = try text { Text("Hi").lineLimit(3, reservesSpace: true) }
    #expect(reserved.size.height.value == 3 * lh && reserved.size.width.value == hi.width, "L2")
    #expect(try text { Text("Hi").lineLimit(3, reservesSpace: false) }.size.height.value == lh, "L2 false")
    #expect(try text { Text("Hi").lineLimit(2...3) }.size.height.value == 2 * lh, "L3 2...3 Hi")
    #expect(try text { Text(tePara).lineLimit(2...3) }.size.height.value == 3 * lh, "L3 2...3 paragraph")
    #expect(try text { Text(tePara).lineLimit(...2) }.size.height.value == 2 * lh, "L3 ...2")
    #expect(try text { Text("Hi").lineLimit(3...) }.size.height.value == 3 * lh, "L3 3...")
    #expect(try text { Text("").lineLimit(2, reservesSpace: true) }.size.height.value
            == (try text { Text("") }).size.height.value, "X10: an empty text reserves nothing")

    // The measurement's baselines (TE-G item 4): the last is the last DRAWN
    // line's, not the reserved height's.
    let system = teSystem()
    let key = system.resolveFont(family: nil, size: 13)
    let style = ResolvedTextStyle(descriptor: FontDescriptor(size: 13), foreground: .textPrimary,
                                  lineLimit: TextLineLimit(min: 3, max: 3), truncation: .tail, alignment: .leading)
    let m = proposalTextMeasurement("Hi", font: key, system: system,
                                    proposal: ProposedSize(width: 100, height: nil), style: style)
    #expect(m.size.height == 3 * Double(lh))
    #expect(m.lastBaseline == m.firstBaseline, "L2: the last baseline is the one line's")
}

/// **3.13.** A finite height proposal caps the lines at `max(1, ⌊h /
/// lineHeight⌋)` (X9, L5): 47.9 → 2 and 48 → 3 at a 16 pt line, 5 → 1; the
/// smaller of it and the limit wins; `reservesSpace` still reserves; an
/// infinite height is unlimited; a `nil` width with a height is one line.
///
/// Mutation **M3l**: `ceil` for `floor`.
@MainActor
@Test func aFiniteHeightProposalCapsTheLines() throws {
    let lh = teLineHeight()
    try #require(lh == 16, "the X9 arms are written for a 16 pt line")
    try #require(naturalLines(width: 100) >= 5)
    // The frame answers its own height; the text's own rect is its answer.
    func textHeight(_ height: Float, _ make: @escaping () -> some ElementGroup) throws -> Float {
        let frame = try controlRender(controlRoot {
            make().frame(width: Pixels(100), height: Pixels(height), alignment: .top)
        })
        return try controlBounds(frame, controlID([0, 0, 0])).size.height.value
    }
    #expect(try textHeight(47.9) { Text(tePara) } == 2 * lh, "47.9 → 2")
    #expect(try textHeight(48) { Text(tePara) } == 3 * lh, "48 → 3")
    #expect(try textHeight(5) { Text(tePara) } == lh, "never below 1")
    #expect(try textHeight(100) { Text(tePara).lineLimit(2) } == 2 * lh, "the limit is smaller")
    #expect(try textHeight(40) { Text(tePara).lineLimit(4) } == 2 * lh, "the height is smaller")
    #expect(try textHeight(20) { Text("Hi").lineLimit(3, reservesSpace: true) } == 3 * lh,
            "reservesSpace reserves under a short proposal (X9)")

    let system = teSystem()
    let key = system.resolveFont(family: nil, size: 13)
    let style = ResolvedTextStyle(descriptor: FontDescriptor(size: 13), foreground: .textPrimary,
                                  lineLimit: TextLineLimit(), truncation: .tail, alignment: .leading)
    let infinite = proposalTextMeasurement(tePara, font: key, system: system,
                                           proposal: ProposedSize(width: 100, height: .infinity), style: style)
    #expect(infinite.size.height == Double(naturalLines(width: 100)) * Double(lh), "infinity is unlimited")
    let unwrapped = proposalTextMeasurement(tePara, font: key, system: system,
                                            proposal: ProposedSize(width: nil, height: 20), style: style)
    #expect(unwrapped.size.height == Double(lh), "a nil width is one line")
    #expect(unwrapped.size.width == system.measure(tePara, font: key, wrappingAt: nil).widestLine)
}

/// **3.23.** A stack shares its height with a wrapping text as SwiftUI does
/// (ruling TE-R, probe `swiftui-text-in-stacks.swift`): the text is flexible
/// between one line and its natural height, so least-flexible-first serves it
/// its share. K1 — `VStack(spacing: 0) { ProposalText; Spacer }` 100 wide at
/// heights 60, 100, 200 — draws 1, 3 and 6 lines; K2 — a 40-tall block at 80
/// — 2. K2 on a legacy `Column` (gap 0) of a `Text` and a 40-tall `Box`: 2.
/// Line counts, from the frame's own 16 pt line, never SwiftUI's half-point
/// heights (divergence 77).
///
/// Red before: every arm draws 6. Mutation **M3u**: the measure ignores a
/// finite height proposal.
@MainActor
@Test func aStackSharesItsHeightWithAWrappingTextAsSwiftUIDoes() throws {
    let lh = teLineHeight()
    try #require(naturalLines(width: 100) == 6, "K0: six lines at width 100")
    func lines(_ height: Float, spacer: Bool) throws -> Int {
        let frame = try controlRender(controlRoot(height: 300) {
            VStack(spacing: Pixels(0)) {
                ProposalText(tePara)
                if spacer { Spacer() } else { Rectangle(width: Pixels(100), height: Pixels(40), color: .accent) }
            }.frame(width: Pixels(100), height: Pixels(height))
        }, height: 300)
        let text = try controlBounds(frame, controlID([0, 0, 0, 0]))
        return Int((text.size.height.value / lh).rounded())
    }
    #expect(try lines(60, spacer: true) == 1, "K1 60")
    #expect(try lines(100, spacer: true) == 3, "K1 100")
    #expect(try lines(200, spacer: true) == 6, "K1 200 (the separating control)")
    #expect(try lines(80, spacer: false) == 2, "K2 80")

    let legacy = try controlRender(controlRoot(height: 300) {
        Column {
            Text(tePara).frame(width: Pixels(100))
            Box().frame(width: Pixels(100), height: Pixels(40))
        }.frame(height: Pixels(80))
    }, height: 300)
    let text = try controlBounds(legacy, controlID([0, 0, 0, 0, 0]))
    #expect(Int((text.size.height.value / lh).rounded()) == 2, "K2 on a legacy Column")
}
