import Foundation
import Testing
import MetalUIPortableText
import MetalUIScene
import MetalUITextSystem
@testable import MetalUI

// R3-10 part 1 (rulings TM-A…TM-G, record 186; probe `docs/probes/text-line-patterns.swift`): dash
// patterns of underline and strikethrough, and the view-level text modifiers. Runs through the portable
// text system (Noto Sans), so Linux and Windows CI run it too: the emitter is shared code (`TM-E`).
// Expected rects are derived from the text system's own line boxes and face metrics.

private let fontURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().appendingPathComponent("Fonts/NotoSans-Regular.ttf")

private func note(_ message: String) -> Comment { Comment(rawValue: message) }

@MainActor
private func portableSystem() throws -> PortableTextSystem {
    PortableTextSystem(resolver: try PortableFontResolver(defaultFont: [UInt8](Data(contentsOf: fontURL))))
}

/// `element` at the window's top-left corner: a flex-start `Row` declared at the window's size.
@MainActor
private func topLeft<G: ElementGroup>(_ element: G) -> some Element {
    element.frame(width: 400, height: 300, alignment: .topLeading)
}

@MainActor
private func frame<G: ElementGroup>(_ element: G, _ system: any TextSystem) -> Frame {
    let frame = Frame(contentSize: Size(width: Pixels(400), height: Pixels(300)), scaleFactor: 1, textSystem: system)
    var root = topLeft(element)
    frame.render(&root)
    return frame
}

/// A thin rect's x, width, y, height.
private struct Bar: Equatable, CustomStringConvertible {
    var x: Double, width: Double, y: Double, height: Double
    init(_ rect: MUIRect) {
        x = Double(rect.bounds.origin.x); width = Double(rect.bounds.size.width)
        y = Double(rect.bounds.origin.y); height = Double(rect.bounds.size.height)
    }
    init(min: Double, max: Double, centre: Double, thickness: Double) {
        x = min; width = max - min; y = centre - thickness / 2; height = thickness
    }
    func matches(_ other: Bar) -> Bool {
        abs(x - other.x) < 1e-3 && abs(width - other.width) < 1e-3 && abs(y - other.y) < 1e-3
            && abs(height - other.height) < 1e-3
    }
    var description: String { "(x \(x), w \(width), y \(y), h \(height))" }
}

/// The thin rects of a frame (underlines, strikethroughs), by y then x.
@MainActor
private func bars(_ frame: Frame) -> [Bar] {
    frame.scene.rects.filter { $0.bounds.size.height < 5 }.map(Bar.init).sorted { ($0.y, $0.x) < ($1.y, $1.x) }
}

private func sameColour(_ color: MUIHsla, _ expected: Hsla) -> Bool {
    color.h == expected.h && color.s == expected.s && color.l == expected.l && color.a == expected.a
}

private func same(_ a: [Bar], _ b: [Bar]) -> Bool {
    a.count == b.count && zip(a, b).allSatisfy { $0.matches($1) }
}

/// The x of every glyph of a frame, by order, and its y.
@MainActor
private func glyphPositions(_ frame: Frame) -> [(x: Double, y: Double)] {
    frame.scene.glyphs.map { (Double($0.bounds.origin.x), Double($0.bounds.origin.y)) }
}

@MainActor
private func samePositions(_ a: [(x: Double, y: Double)], _ b: [(x: Double, y: Double)]) -> Bool {
    a.count == b.count && zip(a, b).allSatisfy { abs($0.x - $1.x) < 1e-3 && abs($0.y - $1.y) < 1e-3 }
}

@MainActor
private protocol Joining { func join(_ parts: [Text]) -> Text }
private struct Plus: Joining {
    @available(*, deprecated, message: "calls the deprecated Text + Text on purpose: the subject of the run-boundary arm (TM-D)")
    func join(_ parts: [Text]) -> Text { parts.dropFirst().reduce(parts[0]) { $0 + $1 } }
}
@MainActor private func joined<J: Joining>(_ witness: J, _ parts: [Text]) -> Text { witness.join(parts) }

// MARK: - The cycle and the unit (TM-C, TM-D)

/// **TM-1** (probe `P`, `TM-C`). Each pattern's cycle, in thicknesses, is the probe's: dot 3 on / 3 off,
/// dash 10 / 5, dashDot 10 / 3 / 3 / 3, dashDotDot 10 / 3 / 3 / 3 / 3 / 3; the last segment is cut at the
/// end. **Mutation:** change one length in `Pattern.cycle` (dash `10` to `9`, the dot's off to `2`, a
/// dashDotDot gap dropped) — each reddens its own row.
@Test func eachPatternsCycleIsTheProbes() {
    func segments(_ pattern: Text.LineStyle.Pattern, unit: Double, to high: Double) -> [[Double]] {
        linePatternSegments(pattern, unit: unit, origin: 0, from: 0, to: high).map { [$0.min, $0.max] }
    }
    #expect(segments(.dot, unit: 1, to: 12) == [[0, 3], [6, 9]])
    #expect(segments(.dash, unit: 2, to: 100) == [[0, 20], [30, 50], [60, 80], [90, 100]])
    #expect(segments(.dashDot, unit: 1, to: 40) == [[0, 10], [13, 16], [19, 29], [32, 35], [38, 40]])
    #expect(segments(.dashDotDot, unit: 1, to: 40) == [[0, 10], [13, 16], [19, 22], [25, 35], [38, 40]])
    #expect(segments(.solid, unit: 1, to: 40) == [[0, 40]])
}

/// **TM-2** (probe `PS`, `TM-D`). The cycle starts "on" at `origin`, not at the interval: an interval
/// beginning mid-cycle is cut from it (the probe measured 8.38 on at 76.62 under a dash), and an
/// interval before `origin` runs the cycle backwards. **Mutation:** start the cycle at `low` (reddens
/// the first arm), `rounded(.down)` to `.up` or `.towardZero` in the first-cycle line (the second).
@Test func theCycleStartsAtTheOriginNotTheInterval() {
    let mid = linePatternSegments(.dash, unit: 1, origin: 0, from: 76.62, to: 100).map { [$0.min, $0.max] }
    #expect(mid.count == 2 && abs(mid[0][0] - 76.62) < 1e-9 && abs(mid[0][1] - 85) < 1e-9
                && abs(mid[1][0] - 90) < 1e-9 && abs(mid[1][1] - 100) < 1e-9, note("\(mid)"))
    let before = linePatternSegments(.dash, unit: 1, origin: 10, from: 5, to: 30).map { [$0.min, $0.max] }
    #expect(before == [[10, 20], [25, 30]], note("\(before)"))
    let straddling = linePatternSegments(.dash, unit: 1, origin: 10, from: -2, to: 12).map { [$0.min, $0.max] }
    #expect(straddling == [[-2, 5], [10, 12]], note("\(straddling)"))
}

/// **TM-3** (probe `T`, `TM-C`). The unit is the thickness rounded up to a whole point, at least one:
/// the probe's eleven sizes (CoreText 0.527 … 4.219 against SwiftUI 1 … 5). **Mutation:** `.up` to
/// `.toNearestOrEven` (0.527 → 1 still, 1.172 → 1: reddens), drop the `max(1,`.
@Test func theUnitIsTheThicknessRoundedUp() {
    let probe: [(Double, Double)] = [(0.527, 1), (0.762, 1), (0.996, 1), (1.0, 1), (1.172, 2), (1.641, 2), (2.109, 3),
                                     (2.812, 3), (4.219, 5), (0.01, 1)]
    for (thickness, unit) in probe {
        #expect(linePatternUnit(thickness: thickness) == unit, note("thickness \(thickness)"))
    }
}

// MARK: - Painted (TM-E)

/// The line box, face and unit a `Text` of `string` at 13 pt lays out in `system`.
@MainActor
private func lineAndFace(_ system: PortableTextSystem, _ string: String, width: Double? = nil,
                         options: TextLayoutOptions = TextLayoutOptions())
    throws -> (lines: [TextLineBox], face: TextDecorationMetrics, unit: Double) {
    let key = system.resolveFont(FontDescriptor(size: 13))
    let face = system.decorationMetrics(key)
    let measured = system.measure(StyledText(string, style: TextRunStyle(font: key)), wrappingAt: width, options: options)
    return (measured.lines, face, linePatternUnit(thickness: face.underlineThickness))
}

/// **TM-4** (`TM-B`, `TM-E`). A dashed underline paints the pattern's segments over the line's visible
/// extent, at the solid line's y and thickness; a solid one is still one rect (byte for byte as before).
/// **Mutation:** ignore the pattern in `band(_:…)` (always one rect: reddens the dash arm), emit
/// segments for `.solid` (the solid arm).
@MainActor @Test func aDashedUnderlineIsThePatternsSegments() throws {
    let system = try portableSystem()
    let string = "HHHHHHHHHHHHHHHHHHHH"
    let (lines, face, unit) = try lineAndFace(system, string)
    let line = try #require(lines.first)
    let centre = line.baseline - face.underlinePosition
    for pattern in [Text.LineStyle.Pattern.dot, .dash, .dashDot, .dashDotDot] {
        let drawn = bars(frame(Text(string).underline(pattern: pattern), system))
        let expected = linePatternSegments(pattern, unit: unit, origin: line.offsetX,
                                           from: line.offsetX + line.visibleMinX, to: line.offsetX + line.visibleMaxX)
            .map { Bar(min: $0.min, max: $0.max, centre: centre, thickness: face.underlineThickness) }
        try #require(expected.count > 2, "set up: the pattern cuts the line into several pieces")
        #expect(same(drawn, expected), note("\(pattern.kind): drawn \(drawn), expected \(expected)"))
    }
    let solid = bars(frame(Text(string).underline(), system))
    #expect(solid.count == 1, note("solid: \(solid)"))
}

/// **TM-5** (`TM-B`). A text's underline and strikethrough carry their own patterns: dots under, dashes
/// through. **Mutation:** the strikethrough band reading `underlinePattern` (or the reverse) in
/// `drawStyledText`.
@MainActor @Test func theUnderlineAndTheStrikethroughHaveTheirOwnPatterns() throws {
    let system = try portableSystem()
    let string = "HHHHHHHHHHHHHHHHHHHH"
    let (lines, face, unit) = try lineAndFace(system, string)
    let line = try #require(lines.first)
    let drawn = bars(frame(Text(string).underline(pattern: .dot).strikethrough(pattern: .dash), system))
    func expected(_ pattern: Text.LineStyle.Pattern, centre: Double) -> [Bar] {
        linePatternSegments(pattern, unit: unit, origin: line.offsetX, from: line.offsetX + line.visibleMinX,
                            to: line.offsetX + line.visibleMaxX)
            .map { Bar(min: $0.min, max: $0.max, centre: centre, thickness: face.underlineThickness) }
    }
    let strike = expected(.dash, centre: line.baseline - face.strikethroughPosition)
    let under = expected(.dot, centre: line.baseline - face.underlinePosition)
    #expect(same(drawn, strike + under), note("drawn \(drawn)\nexpected \(strike + under)"))
}

/// **TM-6** (probe `PS`/`PR`, `TM-D`). The phase belongs to the line, not to the decoration or the run:
/// `Text("HHHH").underline(false) + Text("HHHH").underline(pattern: .dash)` paints the dashes cut from
/// the line's cycle (the probe's first dash is 8.38 on), and two neighbours of one pattern and
/// different colours continue one cycle. **Mutation:** `origin:` the band's `low` instead of the line's
/// start in `band(_:…)` (reddens the first arm); join neighbours of different patterns (pattern left
/// out of the `pending` comparison — reddens the third).
@MainActor @Test func theCycleBelongsToTheLineAndCarriesAcrossRuns() throws {
    let system = try portableSystem()
    let key = system.resolveFont(FontDescriptor(size: 13))
    let (lines, face, unit) = try lineAndFace(system, "HHHHHHHH")
    let line = try #require(lines.first)
    let centre = line.baseline - face.underlinePosition
    func bar(_ s: (min: Double, max: Double)) -> Bar {
        Bar(min: s.min, max: s.max, centre: centre, thickness: face.underlineThickness)
    }
    let firstWidth = system.measure("HHHH", font: key, wrappingAt: nil, options: TextLayoutOptions()).widestLine
    let plainThenDash = joined(Plus(), [Text("HHHH").underline(false), Text("HHHH").underline(pattern: .dash)])
    let drawn = bars(frame(plainThenDash, system))
    let expected = linePatternSegments(.dash, unit: unit, origin: line.offsetX, from: firstWidth,
                                       to: line.offsetX + line.visibleMaxX).map(bar)
    #expect(same(drawn, expected), note("plain then dash: drawn \(drawn), expected \(expected)"))

    let whole = linePatternSegments(.dash, unit: unit, origin: line.offsetX, from: line.offsetX + line.visibleMinX,
                                    to: line.offsetX + line.visibleMaxX).map(bar)
    let colours = joined(Plus(), [Text("HHHH").underline(pattern: .dash, color: .red),
                                  Text("HHHH").underline(pattern: .dash, color: .blue)])
    let two = bars(frame(colours, system))
    // Two colours are two bands, each cut from the one cycle: their union is the whole line's segments.
    let clipped = whole.flatMap { piece -> [Bar] in
        let cut = firstWidth
        var out: [Bar] = []
        if piece.x < cut { out.append(Bar(min: piece.x, max: Swift.min(piece.x + piece.width, cut), centre: centre, thickness: face.underlineThickness)) }
        if piece.x + piece.width > cut { out.append(Bar(min: Swift.max(piece.x, cut), max: piece.x + piece.width, centre: centre, thickness: face.underlineThickness)) }
        return out
    }
    #expect(two.count == clipped.count, note("two colours: drawn \(two), expected \(clipped)"))
    for (a, b) in zip(two.sorted { $0.x < $1.x }, clipped.sorted { $0.x < $1.x }) {
        #expect(a.matches(b), note("two colours: \(a) vs \(b)"))
    }

    let mixed = joined(Plus(), [Text("HHHH").underline(pattern: .dash), Text("HHHH").underline(pattern: .dot)])
    let mixedBars = bars(frame(mixed, system))
    let expectedMixed = linePatternSegments(.dash, unit: unit, origin: line.offsetX, from: line.offsetX + line.visibleMinX, to: firstWidth).map(bar)
        + linePatternSegments(.dot, unit: unit, origin: line.offsetX, from: firstWidth, to: line.offsetX + line.visibleMaxX).map(bar)
    #expect(same(mixedBars, expectedMixed), note("dash then dot: drawn \(mixedBars), expected \(expectedMixed)"))
}

/// **TM-7** (probe `PL`, `PS` centred, `TM-D`). Each wrapped line restarts the cycle at its own start,
/// including a centred line whose start is offset from the box. **Mutation:** `origin: x` without
/// `+ lines[line].offsetX` in `band(_:…)` (reddens: the centred second line starts mid-cycle).
@MainActor @Test func eachWrappedLineStartsItsOwnCycle() throws {
    let system = try portableSystem()
    let string = "HHHHHHHH HHHH HHHHHHH"
    let text = Text(string).underline(pattern: .dash).multilineTextAlignment(.center)
        .background(.surface).frame(width: 90)
    let painted = frame(text, system)
    let drawn = bars(painted)
    // The lines are the ones the text system lays out at the width the box was painted at; the box is the
    // text's background rect.
    let box = try #require(painted.scene.rects.first { sameColour($0.background, painted.resolve(.surface)) })
    let boxX = Double(box.bounds.origin.x), boxY = Double(box.bounds.origin.y)
    let options = TextLayoutOptions(alignment: .center)
    // Paint wraps at the width layout measured (`pass.measuredWidth`): the widest line at the 90-point proposal,
    // unrounded, while the box's origin is the rounded layout one.
    let key = system.resolveFont(FontDescriptor(size: 13))
    let measuredWidth = system.measure(StyledText(string, style: TextRunStyle(font: key)), wrappingAt: 90,
                                       options: options).widestLine
    let (lines, face, unit) = try lineAndFace(system, string, width: measuredWidth, options: options)
    try #require(lines.count >= 3 && Set(lines.map { Double($0.offsetX).rounded() }).count >= 2,
                 "set up: several lines with different centred offsets: \(lines.map { $0.offsetX })")
    var expected: [Bar] = []
    for line in lines {
        let centre = boxY + line.baseline - face.underlinePosition
        expected += linePatternSegments(.dash, unit: unit, origin: boxX + line.offsetX,
                                        from: boxX + line.offsetX + line.visibleMinX,
                                        to: boxX + line.offsetX + line.visibleMaxX)
            .map { Bar(min: $0.min, max: $0.max, centre: centre, thickness: face.underlineThickness) }
    }
    #expect(same(drawn, expected.sorted { ($0.y, $0.x) < ($1.y, $1.x) }), note("drawn \(drawn)\nexpected \(expected)"))
}

// MARK: - View-level modifiers (TM-A)

/// **TM-8** (probe `V`, `W`; `TM-A`). Kerning, tracking and a baseline offset written above a `Text`
/// reach it exactly as the `Text`'s own do; a `Text`'s own value wins over the environment's; the
/// nearest writer wins, `0` included. **Mutation:** drop `view.kerning` from the `??` chain in
/// `resolveRichText` (reddens the kerning arms), `view.tracking`, `view.baselineOffset` likewise;
/// swap the order so the environment beats the run's own (the own-wins arm).
@MainActor @Test func aViewLevelSpacingReachesTheTextBelowAndTheTextsOwnWins() throws {
    let system = try portableSystem()
    func xs(_ g: some ElementGroup) -> [(x: Double, y: Double)] { glyphPositions(frame(g, system)) }
    let plain = xs(Text("AAAA"))
    for (name, own, view) in [
        ("kerning", Text("AAAA").kerning(5), Column { Text("AAAA") }.kerning(5)),
        ("tracking", Text("AAAA").tracking(5), Column { Text("AAAA") }.tracking(5)),
    ] as [(String, Text, EnvironmentScope<Column<Text>>)] {
        try #require(!samePositions(xs(own), plain), "set up: \(name) moves the glyphs")
        #expect(samePositions(xs(view), xs(own)), note("\(name) above equals \(name) on the Text"))
    }
    let raised = xs(Text("AAAA").baselineOffset(6))
    // The line grows to hold the raised glyphs (RT-G), so their y can stay put: the box is the witness.
    func height(_ text: Text) -> Double {
        let resolved = resolveRichText(text.content, own: text.styleRequest, rich: text.rich,
                                       in: EnvironmentValues(), system: system)
        return richTextMeasurement(resolved, system: system, proposal: ProposedSize(width: nil, height: nil)).size.height
    }
    try #require(height(Text("AAAA").baselineOffset(6)) > height(Text("AAAA").kerning(0)), "set up: a baseline offset grows the line")
    #expect(samePositions(xs(Column { Text("AAAA") }.baselineOffset(6)), raised), "baselineOffset above")
    // The raised glyphs' y can stay put while the line grows (RT-G): a second text below is the witness.
    func belowY(_ top: Text) -> Double? {
        glyphPositions(frame(Column { top; Text("B") }, system)).last?.y
    }
    let ownBelow = belowY(Text("AAAA").baselineOffset(6))
    try #require(ownBelow != nil && ownBelow != belowY(Text("AAAA").kerning(0)), "set up: the line below moves down")
    let viewBelow = glyphPositions(frame(Column { Text("AAAA"); Text("B") }.baselineOffset(6), system)).last?.y
    #expect(viewBelow == ownBelow, "baselineOffset above grows the line as the Text's own does")

    let two = xs(Text("AAAA").kerning(2))
    #expect(samePositions(xs(Column { Text("AAAA").kerning(2) }.kerning(5)), two), "own kerning 2 beats the environment's 5")
    #expect(samePositions(xs(Column { Column { Text("AAAA") }.kerning(2) }.kerning(5)), two), "the nearest writer wins")
    #expect(samePositions(xs(Column { Column { Text("AAAA") }.kerning(0) }.kerning(5)), xs(Text("AAAA").kerning(0))),
            "an inner 0 resets an outer 5")
}

/// **TM-9** (probe `V`, `W`; `TM-A`). A view-level underline or strikethrough paints what the `Text`'s
/// own would, pattern and colour included; a `Text`'s own underline of any pattern replaces it whole
/// (the probe: a solid black own inside a dashed red view is solid black); `underline(false)` on the
/// `Text` or on a nearer view is "none". **Mutation:** `rich.underline ?? view.underline` to
/// `view.underline ?? rich.underline` (the own-wins arm), drop `view.underline` (the first arm), treat
/// an inactive style as unset (the `false` arms).
@MainActor @Test func aViewLevelLineIsTheTextsOwnAndTheTextsOwnReplacesItWhole() throws {
    let system = try portableSystem()
    let string = "HHHHHHHHHHHHHHHH"
    func lines(_ g: some ElementGroup) -> [Bar] { bars(frame(g, system)) }
    let own = lines(Text(string).underline(true, pattern: .dash, color: .red))
    try #require(own.count > 2)
    #expect(same(lines(Column { Text(string) }.underline(true, pattern: .dash, color: .red)), own), "dashed underline above")
    let struck = lines(Text(string).strikethrough(true, pattern: .dot))
    try #require(struck.count > 2)
    #expect(same(lines(Column { Text(string) }.strikethrough(true, pattern: .dot)), struck), "dotted strikethrough above")
    #expect(lines(Column { Text(string).underline() }.underline(pattern: .dash)).count == 1, "a solid own replaces the dashed environment")
    #expect(lines(Column { Text(string).underline(false) }.underline()).isEmpty, "underline(false) on the Text")
    #expect(lines(Column { Column { Text(string) }.underline(false) }.underline()).isEmpty, "underline(false) on a nearer view")
    // The colour of the environment's line is the line's own, not the text's foreground.
    let frameRed = frame(Column { Text(string) }.underline(true, pattern: .dash, color: .red), system)
    let red = frameRed.resolve(.red)
    #expect(frameRed.scene.rects.filter { $0.bounds.size.height < 5 }.allSatisfy {
        $0.background.h == red.h && $0.background.s == red.s && $0.background.l == red.l
    })
}

/// **TM-10** (`TM-F`, probe `W`). A view-level `bold()` is a weight of last resort: bold on a font
/// naming none, beaten by the text's own weight, an environment `fontWeight` in either nesting order
/// and a weight the font itself names (a `.light` font stays light); `bold(false)` removes an outer one.
/// **Mutation:** `font.weightOverride == nil` dropped from the condition (the light-font arm), `??
/// bold` moved before `environment.fontWeight` (the nesting arms), `isBold` ignored (the first arm).
@MainActor @Test func aViewLevelBoldIsAWeightOfLastResort() {
    func weight(_ request: TextStyleRequest = TextStyleRequest(), _ configure: (inout EnvironmentValues) -> Void) -> Double? {
        var environment = EnvironmentValues()
        configure(&environment)
        return resolveTextStyle(request, in: environment).descriptor.weight
    }
    let bold = Font.Weight.bold.value, light = Font.Weight.light.value
    #expect(weight { $0.isBold = true } == bold, "bold on the default font")
    #expect(weight { _ in } != bold, "set up: the default weight is not bold")
    #expect(weight { $0.isBold = true; $0.fontWeight = .light } == light, "an environment weight beats bold")
    #expect(weight(TextStyleRequest(weight: .light)) { $0.isBold = true } == light, "the text's own weight beats bold")
    #expect(weight { $0.isBold = true; $0.font = .system(size: 13, weight: .light) } == light, "a .light font stays light")
    #expect(weight { $0.isBold = true; $0.font = .headline } == bold, "a text style's own weight gives way")
    #expect(weight { $0.isBold = false; $0.fontWeight = nil } != bold, "bold(false)")
}

/// **TM-11** (`TM-A`). A view-level `monospaced()` is the `Text`'s own `monospaced()` for the texts below
/// it, and an own `monospaced(false)` wins. Read on the request the run resolves with. **Mutation:** drop
/// `view.monospaced` from the request in `resolveRichText`.
@MainActor @Test func aViewLevelMonospacedIsReadByTheTextBelow() throws {
    let system = try portableSystem()
    func design(_ text: Text, _ configure: (inout EnvironmentValues) -> Void) -> FontKey {
        var environment = EnvironmentValues()
        configure(&environment)
        return resolveRichText(text.content, own: text.styleRequest, rich: text.rich, in: environment, system: system)
            .text.runs[0].style.font
    }
    let off = design(Text("a").underline(false)) { _ in }
    let on = design(Text("a").monospaced()) { _ in }
    let env = design(Text("a").underline(false)) { $0.textMonospaced = true }
    let ownOff = design(Text("a").monospaced(false)) { $0.textMonospaced = true }
    if on != off {
        #expect(env == on, "the environment's monospaced is the Text's own")
        #expect(ownOff == off, "an own monospaced(false) wins")
    } else {
        // The portable system has one face and no designs: the key cannot tell. The request is the pin.
        var environment = EnvironmentValues()
        environment.textMonospaced = true
        #expect(environment.textRich.monospaced == true && Text("a").rich.monospaced == nil)
    }
}

/// **TM-12** (`TM-A`, `RT-F` item 3). The environment's fields are the state of `EnvironmentValues`
/// through `textRich`: each accessor writes exactly its own field and leaves the others, an empty set
/// stores no box, and `isEmpty` sees every field (a new field owes a row). **Mutation:** an accessor
/// writing the wrong field (`textTracking` into kerning), `isEmpty` ignoring one field.
@MainActor @Test func theEnvironmentFieldsAreIndependentAndAnEmptySetStoresNoBox() {
    var environment = EnvironmentValues()
    #expect(environment.textRichBox == nil && environment.textRich.isEmpty)
    environment.textKerning = 1
    environment.textTracking = 2
    environment.textBaselineOffset = 3
    environment.textMonospaced = true
    environment.textUnderline = Text.LineStyle(pattern: .dash)
    environment.textStrikethrough = Text.LineStyle(pattern: .dot, color: .red)
    let fields = environment.textRich
    #expect(fields.kerning == 1 && fields.tracking == 2 && fields.baselineOffset == 3 && fields.monospaced == true
                && fields.underline?.pattern == .dash && fields.strikethrough?.color == .red)
    for clear in [\EnvironmentValues.textKerning, \.textTracking, \.textBaselineOffset] as [WritableKeyPath<EnvironmentValues, Double?>] {
        environment[keyPath: clear] = nil
    }
    environment.textMonospaced = nil
    environment.textUnderline = nil
    environment.textStrikethrough = nil
    #expect(environment.textRichBox == nil, "every field cleared stores no box")
    for set in [{ (e: inout EnvironmentValues) in e.textKerning = 1 }, { $0.textTracking = 1 }, { $0.textBaselineOffset = 1 },
                { $0.textMonospaced = false }, { $0.textUnderline = Text.LineStyle.none }, { $0.textStrikethrough = .single }] as [(inout EnvironmentValues) -> Void] {
        var e = EnvironmentValues()
        set(&e)
        #expect(!e.textRich.isEmpty, "each field alone makes the set non-empty")
    }
}
