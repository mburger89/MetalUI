import Foundation
import Testing
import MetalUIPortableText
import MetalUITextSystem
import MetalUIDemoContent
@testable import MetalUI

// Rich text, lane 3 — string literals, values and interpolation (rulings RT-B,
// RT-C; `RT-O` items 4–6, 14; spec §4.3 tests 3.4–3.8, 3.15, 3.16). Runs on
// Linux and Windows too. `+` is called through a deprecated protocol witness
// reached by a generic constraint (`RT-O` item 9), so the suite stays at 0
// warnings.

private let fontURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().appendingPathComponent("Fonts/NotoSans-Regular.ttf")

@MainActor
private protocol KeyConcatenating {
    func concatenate(_ parts: [Text]) -> Text
}

private struct KeyPlus: KeyConcatenating {
    @available(*, deprecated, message: "calls the deprecated Text + Text on purpose: the interpolation must equal it (RT-C item 4, RT-O item 9)")
    func concatenate(_ parts: [Text]) -> Text { parts.dropFirst().reduce(parts[0]) { $0 + $1 } }
}

@MainActor
private func joinThrough<C: KeyConcatenating>(_ witness: C, _ parts: [Text]) -> Text { witness.concatenate(parts) }

/// `Text + Text + …` with no warning at the call site.
@MainActor
func keyJoin(_ parts: Text...) -> Text { joinThrough(KeyPlus(), parts) }

/// A text's segments with its own `Text`-level fields pushed into the ones
/// each left unset — what `+` concatenates (ruling RT-E item 2) — so a plain
/// `Text("f").font(.title)` is the one segment `"f"` in `.title`.
@MainActor
func segments(_ text: Text) -> [TextRunRequest] { text.pushedRuns }

/// **3.4** (`M1`, `M2`, `M14`; ruling RT-B item 1). A literal parses; a
/// `String` value and `Text(verbatim:)` do not; `LocalizedStringKey(value)`
/// does. `ProposalText` likewise. Red before: the stub parsed nothing.
/// Mutation **M3.4**: make `init<S: StringProtocol>` parse.
@MainActor
@Test func aLiteralParsesAndAValueDoesNot() {
    let boldB = [TextRunRequest(string: "b", weight: .bold)]
    #expect(segments(Text("**b**")) == boldB, "a literal is parsed: \(Text("**b**").content)")
    let value = "**b**"
    #expect(Text(value).content == .plain("**b**"), "a value is verbatim (M2)")
    #expect(Text(value.dropFirst(0)).content == .plain("**b**"), "a substring is verbatim")
    #expect(Text(verbatim: "**b**").content == .plain("**b**"), "verbatim: is verbatim")
    #expect(segments(Text(LocalizedStringKey(value))) == boldB, "an explicit key is parsed (M14)")
    #expect(ProposalText("**b**").content == .runs(boldB), "ProposalText parses a literal")
    #expect(ProposalText(value).content == .plain("**b**"), "ProposalText keeps a value verbatim")
    #expect(Text("plain words").content == .plain("plain words"), "no trigger: the plain path (RT-O item 14)")
}

/// **3.5** (`M10`, `M10b`; ruling RT-C item 3). An interpolated value is
/// inserted verbatim — never parsed — but takes the format's attributes at
/// its position. Red before: the stub joined the pieces unparsed. Mutation
/// **M3.5**: substitute the values into the format before parsing.
@MainActor
@Test func anInterpolatedValueIsVerbatimButTakesTheFormatsStyle() {
    let v = "**x**"
    #expect(Text("a \(v)").content == .plain("a **x**"), "a value with no markup in the format (M10)")
    #expect(segments(Text("_a_ \(v)")) == [TextRunRequest(string: "a", italic: true), TextRunRequest(string: " **x**")],
            "the value's asterisks stay literal beside parsed markup: \(Text("_a_ \(v)").content)")
    let n = "n"
    #expect(segments(Text("**\(n)**")) == [TextRunRequest(string: "n", weight: .bold)],
            "the value takes the format's bold (M10b): \(Text("**\(n)**").content)")
    #expect(segments(Text("a **b\(n)c** d")) == [TextRunRequest(string: "a "), TextRunRequest(string: "bnc", weight: .bold),
                                                 TextRunRequest(string: " d")],
            "inside a bold run: \(Text("a **b\(n)c** d").content)")
    let star = "*"
    #expect(segments(Text("_a\(star)b_")) == [TextRunRequest(string: "a*b", italic: true)],
            "a value is never a delimiter: \(Text("_a\(star)b_").content)")
}

/// **3.6** (`M11`, `M11b`, `M29`; ruling RT-C item 3, divergence 151). An
/// interpolated value is its `String(describing:)`: `3.5`, where SwiftUI's
/// `%lf` prints `3.500000`; integers agree. Red before: the stub dropped
/// values. Mutation **M3.6**: format a `Double` with `%lf`.
@MainActor
@Test func anInterpolatedValueIsItsDescription() {
    #expect(Text("v \(3.5)").string == "v 3.5", "\(Text("v \(3.5)").string)")
    #expect(Text("n \(7)").string == "n 7")
    #expect(Text("Count: \(42)").string == "Count: 42")
    #expect(Text("**v \(0.25)**").string == "v 0.25", "parsed, and still the description")
}

/// **3.7** (`C14`; ruling RT-C item 4). A `Text` interpolated into a literal
/// keeps its runs: `Text("a \(Text("b").bold())")` is
/// `Text("a ") + Text("b").bold()`. Red before: the stub inserted the text's
/// string. Mutation **M3.7**: interpolate the text's `.string`.
@MainActor
@Test func anInterpolatedTextKeepsItsRuns() {
    #expect(segments(Text("a \(Text("b").bold())")) == segments(keyJoin(Text("a "), Text("b").bold())),
            "\(Text("a \(Text("b").bold())").content)")
    let inner = Text("c").foregroundColor(.red).underline()
    #expect(segments(Text("**x \(inner)**")) == [TextRunRequest(string: "x ", weight: .bold),
                                                 TextRunRequest(string: "c", weight: .bold, foreground: .red,
                                                                underline: .single)],
            "the format's bold reaches the interpolated text's unset weight: \(Text("**x \(inner)**").content)")
    let light = Text("l").fontWeight(.light)
    #expect(segments(Text("**\(light)**")) == [TextRunRequest(string: "l", weight: .light)],
            "the interpolated text's own weight wins (RT-E item 2)")
}

/// **3.7b** (`I3`, `RT-O` item 4). An interpolated `AttributedString` keeps
/// its runs — never its debug description. Red before: the stub inserted its
/// characters. Mutation **M3.7b**: delete the `AttributedString` overload (the
/// generic one takes it).
@MainActor
@Test func anInterpolatedAttributedStringKeepsItsRuns() {
    var heavy = AttributedString("BOLD")
    heavy.font = .body.bold()
    var red = AttributedString("RED")
    red.foregroundColor = .red
    #expect(segments(Text("v \(heavy)")) == segments(keyJoin(Text("v "), Text("BOLD").font(.body.bold()))),
            "\(Text("v \(heavy)").content)")
    #expect(segments(Text("v \(red)")) == segments(keyJoin(Text("v "), Text("RED").foregroundColor(.red))),
            "\(Text("v \(red)").content)")
    #expect(Text("v \(red)").string == "v RED", "never the description: \(Text("v \(red)").string.debugDescription)")
}

/// A literal interpolating a decorated `Text` (3.8's subject).
@MainActor
private func interpolateDecorated(_ arm: Int) -> Text {
    switch arm {
    case 0: Text("a \(Text("b").onClick {})")
    case 1: Text("a \(Text("b").background(.surface))")
    default: Text("a \(Text("b").bold())")
    }
}

/// **3.8** (ruling RT-C item 4, RT-E item 4, divergence 155). Interpolating a
/// `Text` that carries a handler or a decoration traps, naming the field, as
/// `+` does; a plain one does not. Red before: the stub did not check.
/// Mutation **M3.8**: delete the check.
@Test func interpolatingADecoratedTextTraps() async {
    func check(_ result: ExitTest.Result?, _ field: String) {
        let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
        #expect(stderr.contains("the interpolated operand carries \(field)") && stderr.contains("divergence 155"),
                "arm \(field): aborted, but not at the operand check:\n\(stderr)")
    }
    check(await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        await MainActor.run { _ = interpolateDecorated(0) }
    }, "handlers.onClick")
    check(await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        await MainActor.run { _ = interpolateDecorated(1) }
    }, "decoration")
    await #expect(processExitsWith: .success) {
        await MainActor.run { _ = interpolateDecorated(2) }
    }
}

@MainActor
private protocol ImageInterpolating {
    func interpolate(_ image: Image) -> Text
}

private struct ImageInterpolation: ImageInterpolating {
    @available(*, deprecated, message: "interpolates an Image on purpose: the deprecated overload must trap (RT-T item 1)")
    func interpolate(_ image: Image) -> Text { Text("v \(image)") }
}

@MainActor
private func interpolateThrough<W: ImageInterpolating>(_ witness: W, _ image: Image) -> Text {
    witness.interpolate(image)
}

/// **3.10b** (ruling RT-T item 1, `RT-O` item 5 amended). Interpolating an
/// `Image` traps, naming the absence — never its description. (An
/// `@available(*, unavailable)` overload cannot refuse it at compile time: it
/// loses to the generic one, guard 3.10's Image arm; the deprecated overload
/// warns at the call site and traps here.) Called through a deprecated
/// witness (`RT-O` item 9). Red before: the unavailable stub let the generic
/// overload write the description. Mutation **M3.10b**: make the overload
/// append the description instead of trapping.
@Test func interpolatingAnImageTraps() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        await MainActor.run {
            _ = interpolateThrough(ImageInterpolation(), Image(decorative: ImageBitmap(width: 1, height: 1, rgba: [0, 0, 0, 0]), scale: 1))
        }
    }
    let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(stderr.contains("interpolating an Image into Text is not offered"), "trapped, but not at the overload:\n\(stderr)")
}

/// A frame over Noto Sans, recording accessibility.
@MainActor
private func portableFrame<E: Element>(_ element: E) throws -> Frame {
    let system = PortableTextSystem(resolver: try PortableFontResolver(defaultFont: [UInt8](Data(contentsOf: fontURL))))
    let frame = Frame(contentSize: Size(width: Pixels(300), height: Pixels(200)), scaleFactor: 1, textSystem: system,
                      collectsAccessibility: true)
    var root = element
    frame.render(&root)
    return frame
}

/// **3.15** (divergence 154; ruling RT-A). A control's `String` title is
/// verbatim — SwiftUI parses it (`M30`, `M31`): `Button("**b**")` and
/// `Toggle("**b**", isOn:)` publish and draw `**b**`, five glyphs. Green on
/// arrival (it pins the divergence). Mutation **M3.15**: route the `String`
/// title through `LocalizedStringKey`.
@MainActor
@Test func aControlTitleIsVerbatim() throws {
    let button = try portableFrame(Button("**b**") {})
    #expect(button.axEmissions.compactMap(\.text).contains("**b**"),
            "the button's title: \(button.axEmissions.compactMap(\.text))")
    #expect(button.scene.glyphs.count == 5, "five glyphs drawn: \(button.scene.glyphs.count)")
    let toggle = try portableFrame(Toggle("**b**", isOn: .constant(false)))
    #expect(toggle.axEmissions.compactMap(\.text).contains("**b**"),
            "the toggle's title: \(toggle.axEmissions.compactMap(\.text))")
    #expect(toggle.scene.glyphs.count == 5, "five glyphs drawn: \(toggle.scene.glyphs.count)")
}

/// **3.16** (`RT-O` item 14). A literal with no Markdown trigger character
/// never runs the parser: building and rendering the main demo (every literal
/// there has none) leaves the parse counter where it was; `Text("**b**")`
/// moves it by exactly one. Red before: the stub never counted (the `**b**`
/// arm). Mutation **M3.16**: always run the parser (the demo arm).
@MainActor
@Test func aLiteralWithNoMarkupRunsNoParser() throws {
    let before = markdownParserRuns
    _ = try renderDemoFrame(scale: 1)
    #expect(markdownParserRuns == before, "the demo ran the parser \(markdownParserRuns - before) times")
    let start = markdownParserRuns
    _ = Text("**b**")
    #expect(markdownParserRuns == start + 1, "one parse for one marked-up literal: \(markdownParserRuns - start)")
}

/// The rich-text demo (spec §6, `RT-O` item 10) renders headlessly through
/// the portable text system — the path its SDL switch draws (human check RT4)
/// — without a trap: every section's text is drawn, in more than the plain
/// colours (red, blue, orange and the accent links among them), with
/// decoration rects (underlines, the strikethroughs, the yellow background),
/// and its literals reach the parser. Not one of the fourteen images.
@MainActor
@Test func theRichTextDemoDrawsThroughThePortableSystem() throws {
    let system = PortableTextSystem(resolver: try PortableFontResolver(defaultFont: [UInt8](Data(contentsOf: fontURL))))
    let frame = Frame(contentSize: Size(width: Pixels(920), height: Pixels(640)), scaleFactor: 1, textSystem: system)
    let before = markdownParserRuns
    var root = richTextDemoContent()
    frame.render(&root)
    #expect(markdownParserRuns > before, "the demo's Markdown literals ran the parser")
    let glyphColours = Set(frame.scene.glyphs.map { "\($0.color.h) \($0.color.s) \($0.color.l) \($0.color.a)" })
    #expect(frame.scene.glyphs.count > 300 && glyphColours.count >= 5,
            "\(frame.scene.glyphs.count) glyphs in \(glyphColours.count) colours")
    for colour in [Color.red, .blue, .orange, .yellow] {
        let resolved = frame.resolve(colour)
        let drawn = frame.scene.glyphs.contains { $0.color.h == resolved.h && $0.color.l == resolved.l }
            || frame.scene.rects.contains { $0.background.h == resolved.h && $0.background.l == resolved.l }
        #expect(drawn, "\(colour) is drawn")
    }
}
