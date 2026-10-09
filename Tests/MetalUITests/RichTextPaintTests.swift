import Testing
import MetalUICore
import MetalUIScene
import MetalUITextSystem
@testable import MetalUIText
@testable import MetalUI

// Rich text, lane 2 — the paint of a styled `Text` (ruling RT-J, RT-K; spec
// §4.2 tests 2.4–2.8, 2.11, 2.17). Every expected rect is derived from the
// text system's own face metrics and line boxes for the same runs, the text
// at the window's top-left corner at scale 1, so a scene rect's device bounds
// are points. Helpers (`rtJoin`, `rtFrame`, `rtTopLeft`, `rtKey`, `rtSame`)
// live in `RichTextTests.swift`.

private func note(_ message: String) -> Comment { Comment(rawValue: message) }

/// A decoration rect's geometry: x, width, y, height.
private struct RectGeometry: CustomStringConvertible {
    let x: Double, width: Double, y: Double, height: Double
    init(_ rect: MUIRect) {
        x = Double(rect.bounds.origin.x); width = Double(rect.bounds.size.width)
        y = Double(rect.bounds.origin.y); height = Double(rect.bounds.size.height)
    }
    init(minX: Double, maxX: Double, centre: Double, thickness: Double) {
        x = minX; width = maxX - minX; y = centre - thickness / 2; height = thickness
    }
    init(x: Double, width: Double, y: Double, height: Double) {
        self.x = x; self.width = width; self.y = y; self.height = height
    }
    func matches(_ other: RectGeometry, tolerance: Double = 1e-3) -> Bool {
        abs(x - other.x) < tolerance && abs(width - other.width) < tolerance
            && abs(y - other.y) < tolerance && abs(height - other.height) < tolerance
    }
    var description: String { "(x \(x), w \(width), y \(y), h \(height))" }
}

/// The thin rects a frame painted — underlines and strikethroughs — by x.
@MainActor
private func lines(_ frame: Frame) -> [RectGeometry] {
    frame.scene.rects.filter { $0.bounds.size.height < 5 }.map(RectGeometry.init).sorted { $0.x < $1.x }
}

/// The styled text the system lays out for `pieces`, each `(string, size)` in
/// the system face.
@MainActor
private func measured(_ system: any TextSystem, _ pieces: [(String, Double)]) -> StyledTextMeasurement {
    let text = StyledText(pieces.map(\.0).joined(), runs: pieces.map {
        StyledTextRun(length: $0.0.utf16.count, style: TextRunStyle(font: rtKey(system, $0.1)))
    })
    return system.measure(text, wrappingAt: nil, options: TextLayoutOptions())
}

// MARK: - 2.4

/// **2.4**. Each run's glyphs draw in that run's colour: `ab` red, `cd` blue —
/// two runs of one face, which a `Text` keeps apart at the seam (`RT-R`
/// item 1). Red before: the stub drew every glyph in one colour. Mutation
/// **M2.4**: colour every glyph with run 0's colour.
@MainActor
@Test func aStyledTextPaintsEachRunsColour() throws {
    let frame = rtFrame(rtTopLeft(rtJoin(Text("ab").foregroundColor(.red), Text("cd").foregroundColor(.blue))))
    let glyphs = frame.scene.glyphs
    try #require(glyphs.count == 4, "four glyphs: \(glyphs.count)")
    let red = frame.resolve(.red), blue = frame.resolve(.blue)
    #expect(rtSame(glyphs[0].color, red) && rtSame(glyphs[1].color, red), "ab red: \(glyphs.map(\.color))")
    #expect(rtSame(glyphs[2].color, blue) && rtSame(glyphs[3].color, blue), "cd blue: \(glyphs.map(\.color))")
}

// MARK: - 2.5

/// **2.5** (ruling RT-J items 2–3, `C9w`). An underline is one rect centred at
/// `baseline − underlinePosition`, the face's `underlineThickness` tall, over
/// the line's visible extent — `"x   "`'s trailing spaces are not
/// underlined. Red before: the stub drew none. Mutation **M2.5**: drop the
/// visible-extent clip (the `"x   "` arm).
@MainActor
@Test func anUnderlineIsARectAtTheFacesPosition() throws {
    let system = CoreTextTextSystem()
    let face = system.decorationMetrics(rtKey(system))
    for string in ["xx", "x   "] {
        let line = try #require(measured(system, [(string, 13)]).lines.first)
        if string == "x   " {
            try #require(line.visibleMaxX < line.width - 1, "set up: the spaces are past the visible extent")
        }
        let drawn = lines(rtFrame(rtTopLeft(Text(string).underline()), system: system))
        let expected = RectGeometry(minX: line.offsetX + line.visibleMinX, maxX: line.offsetX + line.visibleMaxX,
                                    centre: line.baseline - face.underlinePosition, thickness: face.underlineThickness)
        #expect(drawn.count == 1 && drawn[0].matches(expected),
                note("\(string.debugDescription): drawn \(drawn), expected \(expected)"))
    }
}

// MARK: - 2.6

/// **2.6** (`C9s`, `C9ms`; ruling RT-J item 2). A strikethrough sits on half
/// its own face's x-height: a 13-point and a 30-point run on one line strike
/// at `baseline − xHeight₁₃ / 2` and `baseline − xHeight₃₀ / 2`, each the
/// face's underline thickness tall. Red before: the stub drew none. Mutation
/// **M2.6**: use the line's tallest run's metrics for every strike.
@MainActor
@Test func aStrikethroughSitsOnHalfTheXHeight() throws {
    let system = CoreTextTextSystem()
    let line = try #require(measured(system, [("ab", 13), ("cd", 30)]).lines.first)
    let drawn = lines(rtFrame(rtTopLeft(rtJoin(Text("ab").font(size: 13), Text("cd").font(size: 30))
        .strikethrough()), system: system))
    try #require(drawn.count == 2, "two strikes: \(drawn)")
    for (index, size) in [13.0, 30.0].enumerated() {
        let face = system.decorationMetrics(rtKey(system, size))
        let centre = line.baseline - face.strikethroughPosition
        #expect(abs(drawn[index].y - (centre - face.underlineThickness / 2)) < 1e-3
                    && abs(drawn[index].height - face.underlineThickness) < 1e-3,
                note("\(size) pt: drawn \(drawn[index]), centre \(centre), thickness \(face.underlineThickness)"))
    }
}

// MARK: - 2.7

/// **2.7** (`C9m`, `C9b`, `F3`, `F2`; ruling RT-J item 3a). On one line, a
/// 10-point and a 30-point run underlined in one colour draw ONE rect across
/// both, at the lower position and the greater thickness; in two colours, two
/// rects with their own geometry; strikethroughs never join. Red before: the
/// stub drew none. Mutations **M2.7a** never join (the one-colour arm),
/// **M2.7b** join whatever the colour (the two-colour arm).
@MainActor
@Test func sameColouredUnderlinesMergeAndOthersDoNot() throws {
    let system = CoreTextTextSystem()
    let line = try #require(measured(system, [("ab", 10), ("cd", 30)]).lines.first)
    let f10 = system.decorationMetrics(rtKey(system, 10)), f30 = system.decorationMetrics(rtKey(system, 30))
    let width10 = measured(system, [("ab", 10)]).widestLine
    func frame(_ text: Text) -> [RectGeometry] { lines(rtFrame(rtTopLeft(text), system: system)) }

    let one = frame(rtJoin(Text("ab").font(size: 10), Text("cd").font(size: 30)).underline())
    let joined = RectGeometry(minX: line.visibleMinX, maxX: line.visibleMaxX,
                              centre: line.baseline - min(f10.underlinePosition, f30.underlinePosition),
                              thickness: max(f10.underlineThickness, f30.underlineThickness))
    #expect(one.count == 1 && one[0].matches(joined), note("one colour: \(one), expected \(joined)"))

    let two = frame(rtJoin(Text("ab").font(size: 10).underline(color: .red),
                           Text("cd").font(size: 30).underline(color: .blue)))
    let own10 = RectGeometry(minX: line.visibleMinX, maxX: width10, centre: line.baseline - f10.underlinePosition,
                             thickness: f10.underlineThickness)
    let own30 = RectGeometry(minX: width10, maxX: line.visibleMaxX, centre: line.baseline - f30.underlinePosition,
                             thickness: f30.underlineThickness)
    #expect(two.count == 2 && two[0].matches(own10) && two[1].matches(own30),
            note("two colours: \(two), expected \(own10) \(own30)"))

    let strikes = frame(rtJoin(Text("ab").font(size: 10), Text("cd").font(size: 30)).strikethrough())
    #expect(strikes.count == 2, note("strikethroughs never join: \(strikes)"))
}

// MARK: - 2.8

/// **2.8** (`C11bg`, `C11bg2`, `F4e`; ruling RT-J item 5). A run's background
/// fills its segment — its spaces included — by the LINE's box: a 10-point
/// `"ab  "` beside a 30-point run fills the mixed line's height. Built from a
/// run request (no public `Text` modifier sets a run background; lane 3's
/// `AttributedString` does). Red before: the stub drew none. Mutation
/// **M2.8**: use the run's own face's line height.
@MainActor
@Test func aBackgroundFillsTheRunByTheLineBox() throws {
    let system = CoreTextTextSystem()
    let m10 = system.fontMetrics(rtKey(system, 10)), m30 = system.fontMetrics(rtKey(system, 30))
    let mixed = (max(m10.ascent, m30.ascent) + max(m10.descent, m30.descent) + max(m10.leading, m30.leading))
        .rounded(.up)
    let width = measured(system, [("ab  ", 10)]).widestLine
    let text = Text(content: .runs([
        TextRunRequest(string: "ab  ", font: .explicit(.system(size: 10)), background: .yellow),
        TextRunRequest(string: "CD", font: .explicit(.system(size: 30))),
    ]))
    let frame = rtFrame(rtTopLeft(text), system: system)
    let yellow = frame.resolve(.yellow)
    let fills = frame.scene.rects.filter { rtSame($0.background, yellow) }.map(RectGeometry.init)
    let expected = RectGeometry(x: 0, width: width, y: 0, height: mixed)
    #expect(fills.count == 1 && fills[0].matches(expected), note("drawn \(fills), expected \(expected)"))
}

// MARK: - 2.11

/// **2.11** (`GX-J`; ruling RT-J item 1). Under `.shadow`, a styled text is
/// ONE leaf: one shadow image, drawn before the background rect, the glyphs
/// and the underline it holds. Red before: the stub drew no rects. Mutation
/// **M2.11**: emit the underline after `endLeafGroup` (a second shadow).
@MainActor
@Test func aStyledTextIsOneShadowLeaf() throws {
    let text = Text(content: .runs([TextRunRequest(string: "ab", background: .yellow),
                                    TextRunRequest(string: "cd")]))
        .underline()
        .shadow(color: .textPrimary, radius: Pixels(0), x: Pixels(2), y: Pixels(2))
    let scene = effectFrame(text).finalizedScene()
    let kinds = scene.drawList.map(\.kind)
    try #require(scene.rects.count == 2 && scene.glyphs.count == 4, "set up: background, underline, four glyphs")
    #expect(gxImages(scene).count == 1, "one shadow for the whole text: \(gxImages(scene).count), \(kinds)")
    #expect(kinds.first == .image, "the shadow first: \(kinds)")
}

// MARK: - 2.17

/// **2.17** (`M6`, `C11lnc`, `C11lne`; ruling RT-K). A link run draws in the
/// accent unless its run sets a colour; the environment's `foregroundStyle`
/// does not reach it (a plain run beside it is green). Red before: the stub
/// drew every glyph in the environment's colour. Mutation **M2.17**: let the
/// environment's `foregroundStyle` reach a link run.
@MainActor
@Test func aLinkDrawsInTheAccentUnlessItsRunIsColoured() throws {
    let text = Text(content: .runs([TextRunRequest(string: "ab", link: "https://example.com"),
                                    TextRunRequest(string: "cd", foreground: .red, link: "https://example.org"),
                                    TextRunRequest(string: "ef")]))
    let frame = rtFrame(rtTopLeft(text.environment(\.foregroundStyle, Color.green)))
    let glyphs = frame.scene.glyphs
    try #require(glyphs.count == 6, "six glyphs")
    let accent = frame.resolve(.accentColor), red = frame.resolve(.red), green = frame.resolve(.green)
    let expected = [accent, accent, red, red, green, green]
    #expect(zip(glyphs, expected).allSatisfy { rtSame($0.color, $1) },
            note("link accent, coloured link red, plain green: \(glyphs.map { $0.color })"))
}
